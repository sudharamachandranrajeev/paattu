// The song's video, silent and blurred, kept in time with the music behind
// Now Playing. Android plays it with ExoPlayer (video_player); Windows and
// Linux with libmpv (media_kit), like the music.

import 'dart:async';
import 'dart:io';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart' as mk;
import 'package:media_kit_video/media_kit_video.dart' as mkv;
import 'package:video_player/video_player.dart' as exo;

import '../app_state.dart';
import '../log.dart';
import '../player/paattu_audio_handler.dart';
import '../sources/http.dart';
import '../sources/sources.dart' as sources;
import '../track.dart';
import '../util.dart';

/// The video of [track], fading in over what's behind it once it's playing.
/// Nothing shows for a song without one.
class SongVideo extends StatefulWidget {
  const SongVideo({super.key, required this.app, required this.track, required this.blur});
  final AppState app;
  final Json track;
  final double blur;

  @override
  State<SongVideo> createState() => _SongVideoState();
}

class _SongVideoState extends State<SongVideo> {
  _Playback? _playback;
  bool _shown = false;
  int _generation = 0;
  StreamSubscription<bool>? _playing;
  Timer? _timer;
  double _rate = 1;
  DateTime _settled = DateTime(0);

  PaattuAudioHandler get _player => widget.app.player;

  @override
  void initState() {
    super.initState();
    fire(_start());
  }

  @override
  void didUpdateWidget(SongVideo old) {
    super.didUpdateWidget(old);
    if (old.track['site'] != widget.track['site'] || trackId(old.track) != trackId(widget.track)) {
      _stop();
      fire(_start());
    }
  }

  @override
  void dispose() {
    _stop();
    super.dispose();
  }

  Future<void> _start() async {
    final generation = ++_generation;
    final ResolvedStream? video;
    try {
      video = await sources.videoFor(widget.track);
    } catch (error) {
      problemLog.warn('no video for ${trackTitle(widget.track)}: $error');
      return; // no video then: the picture stays
    }
    if (video == null || !mounted || generation != _generation) return;
    final playback = _Playback.of(video);
    try {
      // Loading takes a moment, which the music plays on through.
      final music = _player.player.position;
      await playback
          .open(_player.playing ? music + const Duration(milliseconds: 1500) : music, play: _player.playing)
          .timeout(const Duration(seconds: 20));
    } catch (error) {
      problemLog.warn('video for ${trackTitle(widget.track)} would not open: $error');
      await playback.dispose();
      return;
    }
    if (!mounted || generation != _generation) {
      await playback.dispose();
      return;
    }
    _playback = playback;
    _rate = _player.player.speed;
    if (_rate != 1) await playback.setRate(_rate);
    _playing = _player.playingStream.listen((on) => fire(on ? playback.play() : playback.pause()));
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _keepInStep());
    if (mounted) setState(() => _shown = true);
  }

  /// Follow the music: its place (after a seek, or when the video falls
  /// behind) and its speed. A video found by search can be shorter than the
  /// song: it fades out at its end.
  void _keepInStep() {
    final playback = _playback;
    if (playback == null) return;
    final music = _player.player.position;
    final length = playback.duration;
    final over = length > Duration.zero && music >= length;
    if (over == _shown) setState(() => _shown = !over);
    if (over) return;
    // Android pauses and resumes videos with the app, whatever the music did.
    if (playback.playing != _player.playing) fire(_player.playing ? playback.play() : playback.pause());
    final rate = _player.player.speed;
    if (rate != _rate) {
      _rate = rate;
      fire(playback.setRate(rate));
    }
    // After a seek, give the video time to get there before checking again.
    if (DateTime.now().isBefore(_settled)) return;
    if ((playback.position - music).inMilliseconds.abs() > 350) {
      _settled = DateTime.now().add(const Duration(seconds: 3));
      fire(playback.seek(music + const Duration(milliseconds: 150)));
    }
  }

  void _stop() {
    _generation++;
    _timer?.cancel();
    _timer = null;
    final playing = _playing;
    if (playing != null) fire(playing.cancel());
    _playing = null;
    final playback = _playback;
    _playback = null;
    _shown = false;
    if (playback != null) fire(playback.dispose());
  }

  @override
  Widget build(BuildContext context) {
    final playback = _playback;
    return AnimatedOpacity(
      opacity: _shown ? 1 : 0,
      duration: const Duration(milliseconds: 900),
      child: playback == null
          ? const SizedBox.expand()
          : ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: widget.blur, sigmaY: widget.blur, tileMode: TileMode.decal),
              child: playback.view(),
            ),
    );
  }
}

/// What plays the video, without sound.
abstract class _Playback {
  factory _Playback.of(ResolvedStream video) => Platform.isAndroid ? _ExoPlayback(video) : _MpvPlayback(video);

  /// Load the video at [at]: done when its first picture is ready.
  Future<void> open(Duration at, {required bool play});
  Duration get position;
  Duration get duration;
  bool get playing;
  Future<void> play();
  Future<void> pause();
  Future<void> seek(Duration to);
  Future<void> setRate(double rate);

  /// The picture, filling the space it's given.
  Widget view();
  Future<void> dispose();
}

/// Android: ExoPlayer, the player just_audio uses for the music.
class _ExoPlayback implements _Playback {
  _ExoPlayback(ResolvedStream video)
      : _controller = exo.VideoPlayerController.networkUrl(
          video.uri,
          httpHeaders: video.headers ?? const {},
          // Silent, and never asks for audio focus (which would pause the music).
          videoPlayerOptions: exo.VideoPlayerOptions(mixWithOthers: true),
        );

  final exo.VideoPlayerController _controller;

  @override
  Future<void> open(Duration at, {required bool play}) async {
    await _controller.initialize();
    await _controller.setVolume(0);
    await _controller.seekTo(at);
    if (play) await _controller.play();
  }

  @override
  Duration get position => _controller.value.position;
  @override
  Duration get duration => _controller.value.duration;
  @override
  bool get playing => _controller.value.isPlaying;
  @override
  Future<void> play() => _controller.play();
  @override
  Future<void> pause() => _controller.pause();
  @override
  Future<void> seek(Duration to) => _controller.seekTo(to);
  @override
  Future<void> setRate(double rate) => _controller.setPlaybackSpeed(rate);

  @override
  Widget view() {
    final size = _controller.value.size;
    return FittedBox(
      fit: BoxFit.cover,
      clipBehavior: Clip.hardEdge,
      child: SizedBox(width: size.width, height: size.height, child: exo.VideoPlayer(_controller)),
    );
  }

  @override
  Future<void> dispose() => _controller.dispose();
}

/// Windows and Linux: another libmpv, beside the music's.
class _MpvPlayback implements _Playback {
  _MpvPlayback(this._video) {
    _controller = mkv.VideoController(_player);
  }

  final ResolvedStream _video;
  final _player = mk.Player();
  late final mkv.VideoController _controller;

  @override
  Future<void> open(Duration at, {required bool play}) async {
    await _player.setVolume(0);
    await _player.open(mk.Media(_video.uri.toString(), httpHeaders: _video.headers, start: at), play: play);
    await _controller.waitUntilFirstFrameRendered;
  }

  @override
  Duration get position => _player.state.position;
  @override
  Duration get duration => _player.state.duration;
  @override
  bool get playing => _player.state.playing;
  @override
  Future<void> play() => _player.play();
  @override
  Future<void> pause() => _player.pause();
  @override
  Future<void> seek(Duration to) => _player.seek(to);
  @override
  Future<void> setRate(double rate) => _player.setRate(rate);

  @override
  Widget view() => mkv.Video(
        controller: _controller,
        controls: mkv.NoVideoControls,
        fit: BoxFit.cover,
        fill: Colors.transparent,
        wakelock: false,
        pauseUponEnteringBackgroundMode: false,
      );

  @override
  Future<void> dispose() => _player.dispose();
}
