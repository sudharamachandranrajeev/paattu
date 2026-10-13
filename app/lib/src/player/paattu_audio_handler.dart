// The player: a queue of songs (library JSON maps), streamed one at a time.
// Stream links are found just before a song plays (they expire), the next
// song's link is fetched while this one plays, and a stream that fails is
// tried again another way before the song is skipped.
//
// On Android this is the audio_service handler behind the media
// notification and lock screen; on the desktop it is used directly.

import 'dart:async';
import 'dart:math';

import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';
import 'package:rxdart/rxdart.dart';

import '../sources/sources.dart';
import '../titles.dart';
import '../track.dart';
import '../util.dart';

/// Why this device can't play (libmpv didn't load on the desktop), or null.
/// The app still opens; picking a song shows this instead.
String? playbackUnavailable;

class PaattuAudioHandler extends BaseAudioHandler with SeekHandler {
  PaattuAudioHandler() {
    // Errors are handled from errorStream; this one only reports state.
    _player.playbackEventStream.listen(_broadcast, onError: (Object _, StackTrace _) {});
    _player.playingStream.listen((_) => _broadcast(_player.playbackEvent));
    _player.processingStateStream.listen((state) {
      if (state == ProcessingState.completed) unawaited(_completed());
    });
    _player.errorStream.listen(_failed);
    _player.durationStream.listen((duration) {
      final item = mediaItem.value;
      if (item != null && duration != null && item.duration != duration) {
        mediaItem.add(item.copyWith(duration: duration));
      }
    });
  }

  final _player = AudioPlayer(useProxyForRequestHeaders: false);
  final _random = Random();

  /// Songs in play order, and where the queue was before shuffling.
  final List<Json> _queue = [];
  List<Json>? _unshuffled;
  int _index = -1;
  AudioServiceRepeatMode _repeat = AudioServiceRepeatMode.none;
  bool _shuffle = false;

  final _streams = <String, ResolvedStream>{};
  int _attempt = 0;
  int _failures = 0;
  int _generation = 0;
  bool _loading = false;

  /// The song playing (or loading), with the stream's quality.
  final current = BehaviorSubject<Json?>.seeded(null);
  final quality = BehaviorSubject<String>.seeded('');
  final queueTracks = BehaviorSubject<List<Json>>.seeded(const []);
  final loading = BehaviorSubject<bool>.seeded(false);

  /// Things to tell the person ("Couldn't play …").
  final messages = StreamController<String>.broadcast();

  int get index => _index;
  bool get shuffleOn => _shuffle;
  AudioServiceRepeatMode get repeat => _repeat;
  AudioPlayer get player => _player;
  Stream<Duration> get positionStream => _player.positionStream;
  Stream<Duration> get bufferedStream => _player.bufferedPositionStream;
  Stream<Duration?> get durationStream => _player.durationStream;
  Stream<bool> get playingStream => _player.playingStream;
  bool get playing => _player.playing;
  double get volume => _player.volume;
  Stream<double> get volumeStream => _player.volumeStream;

  // ---------------------------------------------------------------- the queue

  /// Play [tracks], starting at [start] (or anywhere, shuffled).
  Future<void> playTracks(List<Json> tracks, {int start = 0, bool shuffled = false}) async {
    final songs = tracks.where((t) => trackId(t).isNotEmpty).toList();
    if (songs.isEmpty) return;
    _queue
      ..clear()
      ..addAll(songs);
    _unshuffled = null;
    _shuffle = false;
    var at = start.clamp(0, songs.length - 1);
    if (shuffled) {
      final first = _queue.removeAt(_random.nextInt(_queue.length));
      _queue.shuffle(_random);
      _queue.insert(0, first);
      _unshuffled = List.of(songs);
      _shuffle = true;
      at = 0;
    }
    _publishQueue();
    await _playAt(at);
  }

  Future<void> playTrack(Json track) => playTracks([track]);

  /// Put songs straight after the one playing.
  void playNext(List<Json> tracks) {
    if (_queue.isEmpty) {
      unawaited(playTracks(tracks));
      return;
    }
    _queue.insertAll(_index + 1, tracks);
    _unshuffled?.addAll(tracks);
    _publishQueue();
    messages.add(tracks.length == 1 ? 'Playing ${trackTitle(tracks.first)} next' : 'Playing ${tracks.length} songs next');
  }

  /// Add songs to the end of the queue.
  void enqueue(List<Json> tracks) {
    if (_queue.isEmpty) {
      unawaited(playTracks(tracks));
      return;
    }
    _queue.addAll(tracks);
    _unshuffled?.addAll(tracks);
    _publishQueue();
    messages.add(tracks.length == 1 ? 'Added ${trackTitle(tracks.first)} to the queue' : 'Added ${tracks.length} songs to the queue');
  }

  void moveInQueue(int from, int to) {
    if (from < 0 || from >= _queue.length || to < 0 || to >= _queue.length || from == to) return;
    final track = _queue.removeAt(from);
    _queue.insert(to, track);
    if (_index == from) {
      _index = to;
    } else if (from < _index && to >= _index) {
      _index--;
    } else if (from > _index && to <= _index) {
      _index++;
    }
    _publishQueue();
  }

  @override
  Future<void> removeQueueItemAt(int index) async {
    if (index < 0 || index >= _queue.length) return;
    final removed = _queue.removeAt(index);
    _unshuffled?.remove(removed);
    if (index < _index) {
      _index--;
      _publishQueue();
    } else if (index == _index) {
      _publishQueue();
      if (_queue.isEmpty) {
        await stop();
      } else {
        await _playAt(min(index, _queue.length - 1), autoplay: _player.playing);
      }
    } else {
      _publishQueue();
    }
  }

  void clearUpcoming() {
    if (_index < 0) return;
    _queue.removeRange(_index + 1, _queue.length);
    _unshuffled = null;
    _shuffle = false;
    _publishQueue();
  }

  void _publishQueue() {
    queueTracks.add(List.unmodifiable(_queue));
    queue.add([for (final t in _queue) _mediaItem(t)]);
    _broadcast(_player.playbackEvent);
  }

  MediaItem _mediaItem(Json t, [Duration? duration]) {
    // YouTube's biggest thumbnail isn't there for every video; hqdefault is.
    final art = trackArtFallback(t) ?? trackArt(t);
    return MediaItem(
      id: trackId(t),
      title: trackTitle(t),
      artist: trackSubtitle(t),
      album: asString(t['movie']).isNotEmpty ? asString(t['movie']) : null,
      duration: duration ?? trackDuration(t),
      artUri: art == null ? null : Uri.tryParse(art),
    );
  }

  // ---------------------------------------------------------------- playing

  Future<void> _playAt(int index, {bool autoplay = true, Duration? from}) async {
    if (index < 0 || index >= _queue.length) return;
    final problem = playbackUnavailable;
    if (problem != null) {
      messages.add(problem);
      return;
    }
    final generation = ++_generation;
    final changed = index != _index;
    _index = index;
    if (changed) {
      _attempt = 0;
    }
    final track = _queue[index];
    current.add(track);
    quality.add('');
    mediaItem.add(_mediaItem(track));
    _loading = true;
    loading.add(true);
    _broadcast(_player.playbackEvent);

    while (true) {
      try {
        final stream = await _resolve(track, _attempt);
        if (generation != _generation) return;
        await _player.setAudioSource(
          AudioSource.uri(stream.uri, headers: stream.headers, tag: trackId(track)),
          initialPosition: from,
        );
        if (generation != _generation) return;
        quality.add(stream.label);
        mediaItem.add(_mediaItem(track, _player.duration).copyWith(extras: {'quality': stream.label}));
        _loading = false;
        loading.add(false);
        _failures = 0;
        if (autoplay) unawaited(_player.play());
        _broadcast(_player.playbackEvent);
        unawaited(_prefetch());
        return;
      } on PlayerInterruptedException {
        return; // another song was picked meanwhile
      } catch (error) {
        if (generation != _generation) return;
        _streams.remove(trackId(track));
        _attempt++;
        if (_attempt < streamAttempts(track)) continue;
        _loading = false;
        loading.add(false);
        await _skipBroken(track, error);
        return;
      }
    }
  }

  Future<ResolvedStream> _resolve(Json track, int attempt) async {
    final id = trackId(track);
    final known = _streams[id];
    if (attempt == 0 && known != null && known.fresh) return known;
    final stream = await streamFor(track, attempt: attempt).timeout(const Duration(seconds: 45));
    _streams[id] = stream;
    return stream;
  }

  /// Find the next song's stream while this one plays.
  Future<void> _prefetch() async {
    final next = _index + 1 < _queue.length ? _queue[_index + 1] : null;
    if (next == null) return;
    final known = _streams[trackId(next)];
    if (known != null && known.fresh) return;
    try {
      _streams[trackId(next)] = await streamFor(next).timeout(const Duration(seconds: 45));
    } catch (_) {
      // it gets another go when it plays
    }
  }

  Future<void> _skipBroken(Json track, Object error) async {
    _failures++;
    messages.add("Couldn't play ${trackTitle(track)}: ${errorText(error)}");
    if (_failures >= 5 || _queue.length <= 1) {
      _failures = 0;
      await _player.stop();
      _broadcast(_player.playbackEvent);
      return;
    }
    final next = _index + 1;
    if (next < _queue.length) {
      await _playAt(next);
    } else if (_repeat == AudioServiceRepeatMode.all) {
      await _playAt(0);
    } else {
      await _player.stop();
      _broadcast(_player.playbackEvent);
    }
  }

  /// A stream that stopped working part way: try again another way from
  /// where it got to.
  void _failed(Object error) {
    if (_loading || _index < 0 || _index >= _queue.length) return;
    final track = _queue[_index];
    final at = _player.position;
    _streams.remove(trackId(track));
    _attempt++;
    if (_attempt < streamAttempts(track)) {
      unawaited(_playAt(_index, from: at));
    } else {
      unawaited(_skipBroken(track, error));
    }
  }

  Future<void> _completed() async {
    if (_loading) return;
    if (_repeat == AudioServiceRepeatMode.one) {
      await _player.seek(Duration.zero);
      await _player.play();
      return;
    }
    if (_index + 1 < _queue.length) {
      await _playAt(_index + 1);
    } else if (_repeat == AudioServiceRepeatMode.all && _queue.isNotEmpty) {
      await _playAt(0);
    } else {
      await _player.pause();
      await _player.seek(Duration.zero);
    }
  }

  // ---------------------------------------------------------------- controls

  @override
  Future<void> play() async {
    if (_index < 0 && _queue.isNotEmpty) return _playAt(0);
    if (_player.processingState == ProcessingState.idle && _index >= 0) {
      return _playAt(_index, from: _player.position);
    }
    await _player.play();
  }

  @override
  Future<void> pause() => _player.pause();

  Future<void> togglePlay() => _player.playing ? pause() : play();

  @override
  Future<void> stop() async {
    _generation++;
    await _player.stop();
    _loading = false;
    loading.add(false);
    _broadcast(_player.playbackEvent);
  }

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> skipToNext() async {
    if (_index + 1 < _queue.length) {
      await _playAt(_index + 1);
    } else if (_repeat == AudioServiceRepeatMode.all && _queue.isNotEmpty) {
      await _playAt(0);
    }
  }

  @override
  Future<void> skipToPrevious() async {
    if (_player.position > const Duration(seconds: 4) || _index <= 0) {
      await _player.seek(Duration.zero);
      return;
    }
    await _playAt(_index - 1);
  }

  @override
  Future<void> skipToQueueItem(int index) => _playAt(index);

  @override
  Future<void> setRepeatMode(AudioServiceRepeatMode repeatMode) async {
    _repeat = repeatMode == AudioServiceRepeatMode.group ? AudioServiceRepeatMode.all : repeatMode;
    _broadcast(_player.playbackEvent);
  }

  /// none → all → one → none.
  Future<void> cycleRepeat() => setRepeatMode(switch (_repeat) {
        AudioServiceRepeatMode.none => AudioServiceRepeatMode.all,
        AudioServiceRepeatMode.all => AudioServiceRepeatMode.one,
        _ => AudioServiceRepeatMode.none,
      });

  @override
  Future<void> setShuffleMode(AudioServiceShuffleMode shuffleMode) async {
    final on = shuffleMode != AudioServiceShuffleMode.none;
    if (on == _shuffle || _queue.isEmpty) {
      _shuffle = on;
      _broadcast(_player.playbackEvent);
      return;
    }
    final playing = _index >= 0 && _index < _queue.length ? _queue[_index] : null;
    if (on) {
      _unshuffled = List.of(_queue);
      final upcoming = _queue.sublist(_index + 1)..shuffle(_random);
      _queue
        ..removeRange(_index + 1, _queue.length)
        ..addAll(upcoming);
    } else if (_unshuffled != null) {
      _queue
        ..clear()
        ..addAll(_unshuffled!);
      _unshuffled = null;
      _index = playing == null ? 0 : max(0, _queue.indexOf(playing));
    }
    _shuffle = on;
    _publishQueue();
  }

  Future<void> toggleShuffle() =>
      setShuffleMode(_shuffle ? AudioServiceShuffleMode.none : AudioServiceShuffleMode.all);

  Future<void> setVolume(double volume) => _player.setVolume(volume.clamp(0.0, 1.0));

  @override
  Future<void> onTaskRemoved() => stop();

  // ---------------------------------------------------------------- state

  void _broadcast(PlaybackEvent event) {
    final playing = _player.playing;
    playbackState.add(playbackState.value.copyWith(
      controls: [
        MediaControl.skipToPrevious,
        if (playing) MediaControl.pause else MediaControl.play,
        MediaControl.skipToNext,
        MediaControl.stop,
      ],
      systemActions: const {
        MediaAction.seek,
        MediaAction.seekForward,
        MediaAction.seekBackward,
        MediaAction.skipToQueueItem,
        MediaAction.setRepeatMode,
        MediaAction.setShuffleMode,
      },
      androidCompactActionIndices: const [0, 1, 2],
      processingState: _loading
          ? AudioProcessingState.loading
          : switch (event.processingState) {
              ProcessingState.idle => AudioProcessingState.idle,
              ProcessingState.loading => AudioProcessingState.loading,
              ProcessingState.buffering => AudioProcessingState.buffering,
              ProcessingState.ready => AudioProcessingState.ready,
              ProcessingState.completed => AudioProcessingState.completed,
            },
      playing: playing,
      updatePosition: _player.position,
      bufferedPosition: _player.bufferedPosition,
      speed: _player.speed,
      queueIndex: _index < 0 ? null : _index,
      repeatMode: _repeat,
      shuffleMode: _shuffle ? AudioServiceShuffleMode.all : AudioServiceShuffleMode.none,
    ));
  }

  /// A queue mix: songs from these playlists' tracks, one upload per song.
  static List<Json> uniqueSongs(Iterable<Json> tracks) {
    final seen = <String>{};
    final out = <Json>[];
    for (final t in tracks) {
      if (asString(t['kind']) == 'trailer') continue;
      final key = songKey(t);
      if (key != '|' && !seen.add(key)) continue;
      if (key == '|' && !seen.add(trackId(t))) continue;
      out.add(t);
    }
    return out;
  }
}
