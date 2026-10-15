// The player: a queue of songs (library JSON maps), streamed one at a time.
// Stream links are found just before a song plays (they expire); the next two
// songs are fetched (and downloaded, song_cache.dart) while this one plays,
// and a stream that fails is tried again another way, then as the same song
// on another site, before the song is skipped with the reason why.
//
// There are two players ("decks"): the next song gets ready on the other one
// before this one ends, so it starts at once, and the two cross-fade. When
// the queue runs low, the radio (radio.dart) adds songs like the one playing.
//
// On Android this is the audio_service handler behind the media
// notification and lock screen; on the desktop it is used directly.

import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';
import 'package:rxdart/rxdart.dart';

import '../log.dart';
import '../sound.dart';
import '../sources/http.dart' show streamStatus;
import '../sources/sources.dart';
import '../titles.dart';
import '../track.dart';
import '../util.dart';
import 'reasons.dart';
import 'song_cache.dart';

/// Why this device can't play (libmpv didn't load on the desktop), or null.
/// The app still opens; picking a song shows this instead.
String? playbackUnavailable;

class PaattuAudioHandler extends BaseAudioHandler with SeekHandler {
  PaattuAudioHandler() {
    for (final deck in _decks) {
      final p = deck.player;
      // Errors are handled from errorStream; this one only reports state.
      p.playbackEventStream.listen((event) {
        if (deck == _deck) _broadcast(event);
      }, onError: (Object _, StackTrace _) {});
      p.playingStream.listen((_) {
        if (deck == _deck) _broadcast(p.playbackEvent);
      });
      p.processingStateStream.listen((state) {
        if (state == ProcessingState.completed && deck == _deck) unawaited(_completed());
      });
      p.errorStream.listen((error) => _deckFailed(deck, error));
      p.durationStream.listen((duration) {
        final item = mediaItem.value;
        if (deck == _deck && item != null && duration != null && item.duration != duration) {
          mediaItem.add(item.copyWith(duration: duration));
        }
      });
    }
    Timer.periodic(_tickEvery, (_) => _tick());
  }

  final _decks = [_Deck(), _Deck()];
  int _live = 0;

  /// The deck playing (the one the controls and the screen follow), and the
  /// other, where the next song gets ready.
  _Deck get _deck => _decks[_live];
  _Deck get _spare => _decks[1 - _live];
  late final _liveDeck = BehaviorSubject<_Deck>.seeded(_deck);
  AudioPlayer get _player => _deck.player;

  Sound _sound = const Sound();
  final _random = Random();
  double _volume = 1;
  final _volumes = BehaviorSubject<double>.seeded(1);

  /// Seconds the songs overlap, fading one into the next (0 for none).
  int crossfade = 3;

  /// Download the next songs while this one plays (off to save data).
  bool cacheAhead = true;
  SongCache? cache;

  /// Carry on with songs like the last one when the queue runs out.
  bool autoRadio = true;

  /// Songs like a song, for the radio (radio.dart's SongRadio.next).
  Future<List<Json>> Function(Json station, List<Json> queue)? radioSongs;

  /// A song was played (or skipped): how many seconds of how long it is.
  void Function(Json track, int heard, int? length)? onPlayed;

  /// Songs in play order, and where the queue was before shuffling.
  final List<Json> _queue = [];
  List<Json>? _unshuffled;
  int _index = -1;
  AudioServiceRepeatMode _repeat = AudioServiceRepeatMode.none;
  bool _shuffle = false;

  final _streams = <String, ResolvedStream>{};

  /// The ways to play the song at [_index] (its stream asked one way, then
  /// another; then the same song on another site) and the one being tried.
  List<_Way> _ways = const [];
  int _way = 0;
  Json? _waysFor;
  bool _lookedElsewhere = false;
  String? _firstReason;
  int _failures = 0;
  int _generation = 0;
  bool _loading = false;

  /// The next song, loading or loaded on the spare deck; the last song tried
  /// there (a song that wouldn't get ready isn't tried again).
  _Ready? _ready;
  Json? _triedReady;

  /// The deck fading out, and the fade's number.
  _Deck? _fadingOut;
  int _fade = 0;

  /// The song being listened to, and for how long.
  Json? _heardTrack;
  Duration _heard = Duration.zero;
  int? _heardLength;

  /// The radio's song (null when the radio is off); whether it was turned
  /// off for this queue; the station whose songs are being fetched.
  final radio = BehaviorSubject<Json?>.seeded(null);
  bool _radioStopped = false;
  Json? _extendingFor;

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
  Duration get position => _player.position;
  double get speed => _player.speed;
  Stream<Duration> get positionStream => _liveDeck.switchMap((d) => d.player.positionStream);
  Stream<Duration> get bufferedStream => _liveDeck.switchMap((d) => d.player.bufferedPositionStream);
  Stream<Duration?> get durationStream => _liveDeck.switchMap((d) => d.player.durationStream);
  Stream<bool> get playingStream => _liveDeck.switchMap((d) => d.player.playingStream);
  bool get playing => _player.playing;
  double get volume => _volume;
  Stream<double> get volumeStream => _volumes.stream;

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
    // A new queue: the radio starts again when it runs low (auto radio).
    radio.add(null);
    _radioStopped = false;
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
    _checkReady();
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
    _endFade();
    final generation = ++_generation;
    final track = _queue[index];
    // A new song (or the same one picked again) starts with its own stream;
    // resuming one that broke part way carries on with the next way.
    final resuming = from != null && identical(track, _waysFor);
    if (!resuming) {
      _listened();
      _startWays(track);
    }
    _index = index;
    // Ready on the other deck: it starts at once.
    final ready = _ready;
    if (!resuming && ready != null && ready.loaded && identical(ready.track, track)) {
      _ready = null;
      await _swapTo(ready, play: autoplay);
      return;
    }
    _dropReady();
    current.add(track);
    quality.add('');
    mediaItem.add(_mediaItem(track));
    _loading = true;
    loading.add(true);
    _broadcast(_player.playbackEvent);

    final deck = _deck;
    while (true) {
      if (_way >= _ways.length) {
        if (!_lookedElsewhere) {
          _lookedElsewhere = true;
          final elsewhere = await alternatesFor(track).catchError((Object _) => <Json>[]);
          if (generation != _generation) return;
          problemLog.info('elsewhere for ${_describe(track)}: '
              '${elsewhere.isEmpty ? 'none' : elsewhere.map(_describe).join(', ')}');
          for (final other in elsewhere) {
            final last = streamAttempts(other) - 1;
            _ways.add(_Way(other, 0));
            if (last > 0) _ways.add(_Way(other, last));
          }
          if (elsewhere.isNotEmpty) continue;
        }
        _loading = false;
        loading.add(false);
        await _skipBroken(track);
        return;
      }
      final way = _ways[_way];
      ResolvedStream? stream;
      try {
        stream = await _resolve(way.track, way.attempt);
        if (generation != _generation) return;
        await deck.player
            .setAudioSource(_source(deck, way, stream), initialPosition: from)
            .timeout(const Duration(seconds: 15));
        if (generation != _generation) return;
        _loaded(deck);
        await deck.player.setVolume(_volume);
        _showSong(track, stream.label);
        _loading = false;
        loading.add(false);
        _failures = 0;
        problemLog.info('playing ${_describe(track)}: ${way.describe}, ${stream.label}, '
            '${deck.cached != null ? 'downloaded' : stream.uri.host}');
        if (autoplay) unawaited(deck.player.play());
        _broadcast(deck.player.playbackEvent);
        _started();
        return;
      } on PlayerInterruptedException {
        return; // another song was picked meanwhile
      } catch (error, stack) {
        if (generation != _generation) return;
        // A downloaded file that won't play: stream the song instead.
        if (_dropCached(deck)) continue;
        _streams.remove(_streamKey(way.track));
        await _noteFailure(track, way, error, stack, stream);
        if (generation != _generation) return;
        _way++;
      }
    }
  }

  void _startWays(Json track) {
    _waysFor = track;
    _ways = [for (var a = 0; a < streamAttempts(track); a++) _Way(track, a)];
    _way = 0;
    _lookedElsewhere = false;
    _firstReason = null;
  }

  /// What [deck] should play for [way]: the song's download, if it has one,
  /// or its stream.
  AudioSource _source(_Deck deck, _Way way, ResolvedStream stream) {
    final key = _streamKey(way.track);
    final file = way.attempt == 0 ? cache?.file(key) : null;
    deck.cached = file == null ? null : key;
    return file != null
        ? AudioSource.file(file.path, tag: trackId(way.track))
        : AudioSource.uri(stream.uri, headers: stream.headers, tag: trackId(way.track));
  }

  /// Forget the download [deck] was playing (it wouldn't play). Whether it
  /// was playing one.
  bool _dropCached(_Deck deck) {
    final key = deck.cached;
    if (key == null) return false;
    deck.cached = null;
    cache?.drop(key);
    problemLog.warn('the download of $key would not play; streaming it');
    return true;
  }

  /// A deck that has played a song has the phone's equaliser: give it the sound.
  void _loaded(_Deck deck) {
    if (deck.loaded) return;
    deck.loaded = true;
    if (deck.equalizer != null) unawaited(_phoneSound(deck).catchError((Object e) => problemLog.warn('equaliser: $e')));
  }

  void _showSong(Json track, String label) {
    current.add(track);
    quality.add(label);
    mediaItem.add(_mediaItem(track, _player.duration).copyWith(extras: {'quality': label}));
    if (!identical(_heardTrack, track)) {
      _heardTrack = track;
      _heard = Duration.zero;
      _heardLength = toInt(track['duration']);
    }
  }

  /// A song started: more radio songs if the queue is running low, and the
  /// next songs fetched a few seconds in (once this one has what it needs).
  void _started() {
    unawaited(_extendRadio());
    final generation = _generation;
    unawaited(Future<void>.delayed(const Duration(seconds: 4), () async {
      if (generation == _generation) await _prefetch();
    }));
  }

  /// Play the song made ready on the spare deck, at once or fading in.
  Future<void> _swapTo(_Ready ready, {required bool play, bool fade = false}) async {
    final old = _deck, next = ready.deck;
    _live = _decks.indexOf(next);
    _liveDeck.add(next);
    _loading = false;
    loading.add(false);
    _failures = 0;
    _showSong(ready.track, ready.label);
    problemLog.info('playing ${_describe(ready.track)} (ready${fade ? ', fading in' : ''}): ${ready.label}');
    if (fade) {
      _fadeIn(old, next);
    } else {
      await next.player.setVolume(_volume);
      unawaited(old.player.stop());
      if (play) unawaited(next.player.play());
    }
    _broadcast(next.player.playbackEvent);
    _started();
  }

  /// The two decks overlap for [crossfade] seconds, one fading out as the
  /// other fades in (equal power, so the sound doesn't dip).
  void _fadeIn(_Deck old, _Deck next) {
    final fade = ++_fade;
    _fadingOut = old;
    final total = max(1, crossfade) * 1000;
    unawaited(() async {
      await next.player.setVolume(0);
      if (fade != _fade) return; // paused or moved on already
      unawaited(next.player.play());
      final clock = Stopwatch()..start();
      while (fade == _fade) {
        final t = (clock.elapsedMilliseconds / total).clamp(0.0, 1.0);
        await Future.wait([
          old.player.setVolume(_volume * cos(t * pi / 2)),
          next.player.setVolume(_volume * sin(t * pi / 2)),
        ]);
        if (t >= 1) break;
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      if (fade == _fade) _endFade();
    }());
  }

  /// Finish a fade now: the old song stops, the new one at full volume.
  void _endFade() {
    final old = _fadingOut;
    if (old == null) return;
    _fade++;
    _fadingOut = null;
    unawaited(old.player.stop());
    unawaited(_player.setVolume(_volume));
  }

  static const _tickEvery = Duration(milliseconds: 250);

  /// Four times a second: count what's heard, get the next song ready 25
  /// seconds before this one ends, and start the cross-fade.
  void _tick() {
    final deck = _deck, player = deck.player;
    if (_loading || _index < 0 || !player.playing) return;
    if (player.processingState == ProcessingState.ready && identical(_heardTrack, current.value)) {
      _heard += _tickEvery;
    }
    final duration = player.duration;
    if (duration == null || duration <= Duration.zero) return;
    _heardLength = duration.inSeconds;
    final left = duration - player.position;
    final next = _nextIndex();
    if (next == null || _fadingOut != null) return;
    if (_ready == null && left <= const Duration(seconds: 25) && !identical(_triedReady, _queue[next])) {
      unawaited(_prepare(next));
    }
    final ready = _ready;
    final fade = Duration(seconds: crossfade);
    if (crossfade > 0 && ready != null && ready.loaded && ready.index == next && left <= fade && duration > fade * 3) {
      _ready = null;
      _listened();
      _generation++;
      _index = next;
      _startWays(ready.track);
      unawaited(_swapTo(ready, play: true, fade: true));
    }
  }

  /// Load the song at [index] on the spare deck, ready to play.
  Future<void> _prepare(int index) async {
    final track = _queue[index];
    final deck = _spare;
    final ready = _ready = _Ready(index, track, deck);
    _triedReady = track;
    final way = _Way(track, 0);
    try {
      final stream = await _resolve(track, 0);
      if (_ready != ready) return;
      await deck.player.setVolume(0);
      await deck.player.setAudioSource(_source(deck, way, stream)).timeout(const Duration(seconds: 15));
      if (_ready != ready) return;
      _loaded(deck);
      ready
        ..label = stream.label
        ..loaded = true;
    } on PlayerInterruptedException {
      // dropped meanwhile
    } catch (error) {
      if (_ready != ready) return;
      // It gets the usual tries when its turn comes.
      problemLog.warn('getting ${_describe(track)} ready: ${errorText(error)}');
      _dropCached(deck);
      _dropReady();
      _triedReady = track;
    }
  }

  /// Forget the song readied on the spare deck (the queue changed).
  void _dropReady() {
    final ready = _ready;
    _ready = null;
    _triedReady = null;
    if (ready != null && ready.deck != _deck && ready.deck != _fadingOut) unawaited(ready.deck.player.stop());
  }

  /// Whether the song readied is still the next one.
  void _checkReady() {
    final ready = _ready;
    if (ready == null) return;
    final next = _nextIndex();
    if (next != ready.index || !identical(_queue[next!], ready.track)) _dropReady();
  }

  /// Where the queue goes after this song on its own, or null.
  int? _nextIndex() {
    if (_index < 0 || _repeat == AudioServiceRepeatMode.one) return null;
    if (_index + 1 < _queue.length) return _index + 1;
    return _repeat == AudioServiceRepeatMode.all && _queue.length > 1 ? 0 : null;
  }

  /// The next [count] songs to play.
  List<Json> _upcoming(int count) {
    if (_index < 0 || _repeat == AudioServiceRepeatMode.one) return const [];
    final out = <Json>[];
    for (var i = 1; i <= count && i < _queue.length; i++) {
      var at = _index + i;
      if (at >= _queue.length) {
        if (_repeat != AudioServiceRepeatMode.all) break;
        at -= _queue.length;
      }
      out.add(_queue[at]);
    }
    return out;
  }

  /// The song just played (or skipped) goes into the history.
  void _listened() {
    final track = _heardTrack;
    final heard = _heard.inSeconds;
    _heardTrack = null;
    _heard = Duration.zero;
    if (track != null && heard > 0) onPlayed?.call(track, heard, _heardLength);
  }

  /// Log why [way] failed, and keep the first reason to tell the person.
  Future<void> _noteFailure(Json track, _Way way, Object error, StackTrace stack, ResolvedStream? stream) async {
    int? status;
    // The player says little about why; the stream's server says more.
    if (stream != null && error is! SourceException) {
      status = await streamStatus(stream).then<int?>((s) => s).catchError((Object _) => null);
    }
    final reason = playReason(error, status: status);
    _firstReason ??= reason;
    final where = stream == null ? 'finding the stream' : 'playing ${stream.uri.host} (${status ?? 'no answer'})';
    problemLog.error('${_describe(track)}, ${way.describe}, $where: $reason', error,
        error is SourceException || error is PlayerException || error is TimeoutException ? null : stack);
  }

  String _streamKey(Json track) => '${trackSite(track)}:${trackId(track)}';

  Future<ResolvedStream> _resolve(Json track, int attempt) async {
    final key = _streamKey(track);
    final known = _streams[key];
    // A downloaded song doesn't need a fresh link.
    if (attempt == 0 && known != null && (known.fresh || cache?.file(key) != null)) return known;
    final stream = await streamFor(track, attempt: attempt).timeout(const Duration(seconds: 12));
    _streams[key] = stream;
    return stream;
  }

  /// Find the next two songs' streams while this one plays, and download
  /// them (one at a time) unless saving data.
  Future<void> _prefetch() async {
    final generation = _generation;
    for (final next in _upcoming(2)) {
      if (generation != _generation) return;
      try {
        final stream = await _resolve(next, 0);
        final songs = cache;
        if (cacheAhead && songs != null) await songs.fetch(_streamKey(next), stream);
      } catch (error) {
        // it gets another go when it plays
        problemLog.warn('prefetch ${_describe(next)}: ${errorText(error)}');
      }
    }
  }

  Future<void> _skipBroken(Json track) async {
    _failures++;
    // A song picked on its own that won't play still gets its radio.
    if (_failures < 5) await _extendRadio();
    final reason = _firstReason ?? "it wouldn't load";
    final next = _index + 1 < _queue.length ? _index + 1 : (_repeat == AudioServiceRepeatMode.all ? 0 : null);
    final stopping = _failures >= 5 || _queue.length <= 1 || next == null;
    if (_failures >= 5) {
      messages.add("Stopped: $_failures songs in a row wouldn't play (the last because $reason). "
          'Settings > Problem log has the details');
    } else {
      messages.add("Couldn't play ${trackTitle(track)}: $reason.${stopping ? '' : ' Playing the next song.'}");
    }
    problemLog.warn('skipped ${_describe(track)}: $reason');
    if (stopping) {
      _failures = 0;
      await _player.stop();
      _broadcast(_player.playbackEvent);
      return;
    }
    await _playAt(next);
  }

  void _deckFailed(_Deck deck, Object error) {
    if (deck == _deck) return _failed(error);
    final ready = _ready;
    if (ready != null && ready.deck == deck) {
      problemLog.warn('getting ${_describe(ready.track)} ready: ${errorText(error)}');
      _dropCached(deck);
      _dropReady();
      _triedReady = ready.track;
    }
    // (A song fading out that breaks just stops sooner.)
  }

  /// A stream that stopped working part way: try the next way from where it
  /// got to (or, for a download, stream the same way).
  void _failed(Object error) {
    if (_loading || _index < 0 || _index >= _queue.length) return;
    final track = _queue[_index];
    final at = _player.position;
    final way = _way < _ways.length ? _ways[_way] : _Way(track, 0);
    problemLog.error('${_describe(track)}, ${way.describe}, stopped at ${at.inSeconds}s', error);
    if (!_dropCached(_deck)) {
      _streams.remove(_streamKey(way.track));
      _firstReason ??= playReason(error);
      _way++;
    }
    unawaited(_playAt(_index, from: at));
  }

  static String _describe(Json track) => '"${trackTitle(track)}" (${trackSite(track)} ${trackId(track)})';

  Future<void> _completed() async {
    if (_loading) return;
    if (_repeat == AudioServiceRepeatMode.one) {
      _listened();
      _showSong(_queue[_index], quality.value);
      await _player.seek(Duration.zero);
      await _player.play();
      return;
    }
    final next = _nextIndex();
    if (next != null) {
      await _playAt(next);
    } else {
      _listened();
      await _player.pause();
      await _player.seek(Duration.zero);
    }
  }

  // ---------------------------------------------------------------- radio

  /// Play songs like [track] after it, without end: from now if it's the
  /// song playing, else starting with it.
  Future<void> startRadio(Json track) async {
    final playingIt = _index >= 0 && _index < _queue.length && trackId(_queue[_index]) == trackId(track);
    if (!playingIt) {
      await playTracks([track]);
    } else {
      _queue.removeRange(_index + 1, _queue.length);
      _unshuffled = null;
      _shuffle = false;
      _publishQueue();
    }
    if (_index < 0) return; // it couldn't play
    _radioStopped = false;
    radio.add(_queue[_index]);
    messages.add('Radio: songs like ${trackTitle(track)}');
    await _extendRadio();
  }

  /// Turn the radio off: the songs it queued that haven't played go.
  void stopRadio() {
    radio.add(null);
    _radioStopped = true;
    if (_index < 0) return;
    final upcoming = _queue.sublist(_index + 1);
    final kept = upcoming.where((t) => t['_radio'] != true).toList();
    if (kept.length == upcoming.length) return;
    _queue
      ..removeRange(_index + 1, _queue.length)
      ..addAll(kept);
    _unshuffled?.removeWhere((t) => t['_radio'] == true && !_queue.contains(t));
    _publishQueue();
  }

  /// More songs from the radio when two or fewer are left: the radio's own,
  /// or (with auto radio) one of the song playing.
  Future<void> _extendRadio() async {
    final source = radioSongs;
    if (source == null || _index < 0 || _repeat != AudioServiceRepeatMode.none) return;
    if (_queue.length - _index - 1 > 2) return;
    var station = radio.value;
    if (station == null) {
      if (!autoRadio || _radioStopped) return;
      station = _queue[_index];
      radio.add(station);
    }
    if (identical(_extendingFor, station)) return;
    _extendingFor = station;
    try {
      final songs = await source(station, List.of(_queue));
      if (!identical(radio.value, station) || songs.isEmpty) return;
      final added = [for (final song in songs) <String, dynamic>{...song, '_radio': true}];
      _queue.addAll(added);
      _unshuffled?.addAll(added);
      _publishQueue();
      problemLog.info('radio of ${_describe(station)}: ${added.length} songs');
    } catch (error) {
      problemLog.warn('radio of ${_describe(station)}: ${errorText(error)}');
    } finally {
      if (identical(_extendingFor, station)) _extendingFor = null;
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
  Future<void> pause() async {
    _endFade();
    await _player.pause();
  }

  Future<void> togglePlay() => _player.playing ? pause() : play();

  @override
  Future<void> stop() async {
    _generation++;
    _endFade();
    _dropReady();
    _listened();
    await _player.stop();
    _loading = false;
    loading.add(false);
    _broadcast(_player.playbackEvent);
  }

  @override
  Future<void> seek(Duration position) async {
    _endFade();
    await _player.seek(position);
  }

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
      await seek(Duration.zero);
      return;
    }
    await _playAt(_index - 1);
  }

  @override
  Future<void> skipToQueueItem(int index) => _playAt(index);

  @override
  Future<void> setRepeatMode(AudioServiceRepeatMode repeatMode) async {
    _repeat = repeatMode == AudioServiceRepeatMode.group ? AudioServiceRepeatMode.all : repeatMode;
    _checkReady();
    _broadcast(_player.playbackEvent);
    unawaited(_extendRadio());
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

  Future<void> setVolume(double volume) async {
    _volume = volume.clamp(0.0, 1.0);
    _volumes.add(_volume);
    // A fade in progress takes the new volume at its next step.
    if (_fadingOut == null) await _player.setVolume(_volume);
  }

  // ---------------------------------------------------------------- sound

  /// Play with [next]'s equaliser, tone, balance and speed. [live] is for a
  /// control being dragged: on the desktop only the filters that moved
  /// change, without rebuilding the chain; set it again (not live) when the
  /// control is let go, so the next song gets it too.
  Future<void> setSound(Sound next, {bool live = false}) async {
    final before = _sound;
    _sound = next;
    for (final deck in _decks) {
      if (next.speed != deck.player.speed) await deck.player.setSpeed(next.speed);
    }
    if (_decks.first.equalizer != null) {
      // Each deck's equaliser is there once it has played a song (_loaded).
      for (final deck in _decks.where((d) => d.loaded)) {
        await _phoneSound(deck);
      }
      return;
    }
    if (live && before.on && next.on) {
      for (final command in next.movesFrom(before)) {
        await JustAudioMediaKit.command(command);
      }
    } else {
      await JustAudioMediaKit.setAudioFilters(next.graph);
    }
  }

  /// The sound on [deck]'s phone equaliser. Always the latest settings.
  Future<void> _phoneSound(_Deck deck) async {
    final equalizer = deck.equalizer!, loudness = deck.loudness!;
    final parameters = await equalizer.parameters;
    final s = _sound;
    final (gains, boost) =
        s.phone([for (final b in parameters.bands) b.centerFrequency], parameters.minDecibels, parameters.maxDecibels);
    for (var i = 0; i < gains.length; i++) {
      if (parameters.bands[i].gain != gains[i]) await parameters.bands[i].setGain(gains[i]);
    }
    if (loudness.targetGain != boost) await loudness.setTargetGain(boost);
    if (equalizer.enabled != s.on) await equalizer.setEnabled(s.on);
    if (loudness.enabled != boost > 0) await loudness.setEnabled(boost > 0);
  }

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

/// One way to play a song: [track] (the song, or the same song on another
/// site) asked for its stream the [attempt]th way.
class _Way {
  const _Way(this.track, this.attempt);
  final Json track;
  final int attempt;

  String get describe => '${trackSite(track)} way ${attempt + 1}';
}

/// One of the two players, with the phone's equaliser and loudness enhancer
/// that carry the sound settings on Android (the desktop's libmpv gets them
/// as audio filters instead).
class _Deck {
  _Deck() {
    final equalizer = this.equalizer, loudness = this.loudness;
    player = AudioPlayer(
      useProxyForRequestHeaders: false,
      audioPipeline: equalizer == null || loudness == null
          ? null
          : AudioPipeline(androidAudioEffects: [equalizer, loudness]),
    );
  }

  final AndroidEqualizer? equalizer = Platform.isAndroid ? AndroidEqualizer() : null;
  final AndroidLoudnessEnhancer? loudness = Platform.isAndroid ? AndroidLoudnessEnhancer() : null;
  late final AudioPlayer player;

  /// Whether it has played a song (the phone's equaliser is there after the first).
  bool loaded = false;

  /// The download it plays (its cache key), if it plays one.
  String? cached;
}

/// The song at [index] in the queue, loading (then [loaded]) on [deck].
class _Ready {
  _Ready(this.index, this.track, this.deck);
  final int index;
  final Json track;
  final _Deck deck;
  bool loaded = false;
  String label = '';
}
