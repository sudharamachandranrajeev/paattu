// The song's video, silent, kept in time with the music on Now Playing:
// blurred behind it (SongVideo) and, in video mode, sharp in a card of its
// own (SongVideoCard, which FloatingVideo melts into the page and moves like
// the 3D cover), both from the one player (SongVideoHost). In video
// mode the music is the video's own sound (PaattuAudioHandler.setVideoMode),
// so the picture is held to it closely enough for the lips to match.
// Android plays the video with ExoPlayer (video_player); Windows and Linux
// with libmpv (media_kit), like the music.

import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:media_kit/media_kit.dart' as mk;
import 'package:media_kit_video/media_kit_video.dart' as mkv;
import 'package:video_player/video_player.dart' as exo;

import '../app_state.dart';
import '../log.dart';
import '../player/paattu_audio_handler.dart';
import '../sources/http.dart';
import '../sources/sources.dart' as sources;
import '../sources/youtube.dart' show videoYouTube;
import '../track.dart';
import '../util.dart';

/// Whether a song's video is showing, for Now Playing on a phone to fade
/// the cover out of its way.
final songVideoShown = ValueNotifier<bool>(false);

/// Plays [track]'s video for the SongVideo and SongVideoCard under it: none
/// unless [enabled]; [big] (video mode) for a picture sharp enough to watch,
/// else the smallest, for the blur.
class SongVideoHost extends StatefulWidget {
  const SongVideoHost({
    super.key,
    required this.app,
    required this.track,
    required this.enabled,
    required this.big,
    required this.child,
  });
  final AppState app;
  final Json track;
  final bool enabled;
  final bool big;
  final Widget child;

  @override
  State<SongVideoHost> createState() => _SongVideoHostState();
}

class _SongVideoHostState extends State<SongVideoHost> {
  late final _video = _SongVideoPlayer(widget.app);

  @override
  void initState() {
    super.initState();
    _video.show(widget.enabled ? widget.track : null, big: widget.big);
  }

  @override
  void didUpdateWidget(SongVideoHost old) {
    super.didUpdateWidget(old);
    _video.show(widget.enabled ? widget.track : null, big: widget.big);
  }

  @override
  void dispose() {
    _video.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _SongVideoScope(video: _video, child: widget.child);
}

class _SongVideoScope extends InheritedNotifier<_SongVideoPlayer> {
  const _SongVideoScope({required _SongVideoPlayer video, required super.child}) : super(notifier: video);

  static _SongVideoPlayer? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_SongVideoScope>()?.notifier;
}

/// The song's video, blurred by [blur], fading in over what's behind it once
/// it's playing. Nothing shows for a song without one.
class SongVideo extends StatelessWidget {
  const SongVideo({super.key, required this.blur});
  final double blur;

  @override
  Widget build(BuildContext context) {
    final video = _SongVideoScope.of(context);
    final playback = video?.playback;
    return AnimatedOpacity(
      opacity: video?.shown ?? false ? 1 : 0,
      duration: const Duration(milliseconds: 900),
      child: playback == null
          ? const SizedBox.expand()
          : ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: blur, sigmaY: blur, tileMode: TileMode.decal),
              child: playback.view(BoxFit.cover),
            ),
    );
  }
}

/// The song's video, sharp, filling the card it's given (16 by 9, cut to fit
/// rather than with bars); [cover] until it plays, and for a song without one.
class SongVideoCard extends StatelessWidget {
  const SongVideoCard({super.key, required this.cover});
  final Widget cover;

  @override
  Widget build(BuildContext context) {
    final video = _SongVideoScope.of(context);
    final playback = video?.playback;
    final shown = playback != null && video!.shown;
    return Stack(
      fit: StackFit.expand,
      children: [
        AnimatedOpacity(opacity: shown ? 0 : 1, duration: const Duration(milliseconds: 600), child: cover),
        if (playback != null)
          AnimatedOpacity(
            opacity: shown ? 1 : 0,
            duration: const Duration(milliseconds: 600),
            child: playback.view(BoxFit.cover),
          ),
      ],
    );
  }
}

/// [child] (video mode's card) with no edge of its own: it fades out into the
/// page behind it all round, and on a computer it leans a little towards the
/// pointer, like the 3D cover. It moves only while it settles after the
/// pointer: a picture that moves on its own needs no more, and drawing the
/// page afresh every frame made the whole app lag on Windows. Still for
/// those who turn animations off.
class FloatingVideo extends StatefulWidget {
  const FloatingVideo({super.key, required this.child});
  final Widget child;

  @override
  State<FloatingVideo> createState() => _FloatingVideoState();
}

class _FloatingVideoState extends State<FloatingVideo> with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_tick);
  final _tilt = ValueNotifier(Offset.zero);
  Offset _aim = Offset.zero;
  Duration _last = Duration.zero;

  @override
  void dispose() {
    _ticker.dispose();
    _tilt.dispose();
    super.dispose();
  }

  void _tick(Duration elapsed) {
    final seconds = (elapsed - _last).inMicroseconds / 1e6;
    _last = elapsed;
    final next = _tilt.value + (_aim - _tilt.value) * (1 - exp(-seconds * 3));
    if ((next - _aim).distance < 0.002) {
      _tilt.value = _aim;
      _ticker.stop();
    } else {
      _tilt.value = next;
    }
  }

  void _aimAt(Offset aim) {
    _aim = aim;
    if (MediaQuery.disableAnimationsOf(context) || _ticker.isActive || aim == _tilt.value) return;
    _last = Duration.zero;
    _ticker.start();
  }

  void _pointerMoved(Offset at) {
    final size = context.size;
    if (size == null || size.isEmpty) return;
    _aimAt(Offset((at.dx / size.width * 2 - 1).clamp(-1.0, 1.0), (at.dy / size.height * 2 - 1).clamp(-1.0, 1.0)));
  }

  /// Opaque in the middle, clear at the edges: a fade over the outer [edge]
  /// of each side.
  static Shader _fade(Rect rect, Axis axis, double edge) => LinearGradient(
        begin: axis == Axis.horizontal ? Alignment.centerLeft : Alignment.topCenter,
        end: axis == Axis.horizontal ? Alignment.centerRight : Alignment.bottomCenter,
        colors: const [Colors.transparent, Colors.white, Colors.white, Colors.transparent],
        stops: [0, edge, 1 - edge, 1],
      ).createShader(rect);

  /// Both fades (the outer 12% down, 8% across) as one small picture,
  /// stretched over the card: one mask, not one for each way, as each is a
  /// layer of its own, drawn again with every frame of the video.
  static final ui.Image _edges = () {
    const side = 128;
    final rect = Rect.fromLTWH(0, 0, side.toDouble(), side.toDouble());
    final recorder = ui.PictureRecorder();
    Canvas(recorder)
      ..drawRect(rect, Paint()..shader = _fade(rect, Axis.vertical, 0.12))
      ..drawRect(rect, Paint()
        ..shader = _fade(rect, Axis.horizontal, 0.08)
        ..blendMode = BlendMode.dstIn);
    return recorder.endRecording().toImageSync(side, side);
  }();

  static Shader _edgesOver(Rect rect) => ImageShader(
        _edges,
        TileMode.clamp,
        TileMode.clamp,
        Float64List.fromList([
          rect.width / _edges.width, 0, 0, 0, //
          0, rect.height / _edges.height, 0, 0,
          0, 0, 1, 0,
          rect.left, rect.top, 0, 1,
        ]),
        filterQuality: FilterQuality.medium,
      );

  @override
  Widget build(BuildContext context) {
    final melted = ShaderMask(blendMode: BlendMode.dstIn, shaderCallback: _edgesOver, child: widget.child);
    return MouseRegion(
      onHover: (event) => _pointerMoved(event.localPosition),
      onExit: (_) => _aimAt(Offset.zero),
      child: ValueListenableBuilder(
        valueListenable: _tilt,
        child: RepaintBoundary(child: melted),
        builder: (context, tilt, child) => Transform(
          alignment: Alignment.center,
          transform: Matrix4.identity()
            ..setEntry(3, 2, 0.0012)
            ..rotateX(-tilt.dy * 0.07)
            ..rotateY(tilt.dx * 0.09),
          child: child,
        ),
      ),
    );
  }
}

/// The one player behind SongVideo and SongVideoCard: which video, and
/// keeping it in time with the music.
/// The speed (times the music's) for a picture [drift] ms ahead of its own
/// sound: as it is out, 1% for each 50 ms, up to 4%, and nothing within
/// 60 ms, so the speed doesn't wander with the readings.
double videoNudge(double drift) => drift.abs() < 60 ? 1.0 : 1 - (drift / 50).round().clamp(-4, 4) / 100;

class _SongVideoPlayer extends ChangeNotifier {
  _SongVideoPlayer(this.app) {
    _sound = _player.playingVideo.listen((_) => _soundChanged());
  }

  final AppState app;
  late final StreamSubscription<String?> _sound;

  Json? _track;
  bool _big = false;
  String? _id;
  _Playback? playback;
  bool shown = false;
  int _generation = 0;
  StreamSubscription<bool>? _playing;
  Timer? _timer;
  bool _checking = false;
  double _rate = 1;
  double _nudge = 1;
  DateTime _nudged = DateTime(0);

  /// How far ahead the picture is (ms), smoothed over the last few checks:
  /// one check's reading is out by tens of ms either way.
  double? _drift;
  DateTime _settled = DateTime(0);
  bool _disposed = false;

  PaattuAudioHandler get _player => app.player;

  /// Whether the music is this video's own sound, so the two can be held
  /// together closely.
  bool get _exact => _id != null && _player.playingVideo.value == _id;

  /// Play [track]'s video (none for null), [big] or small.
  void show(Json? track, {required bool big}) {
    final same = track != null &&
        _track != null &&
        track['site'] == _track!['site'] &&
        trackId(track) == trackId(_track!) &&
        big == _big;
    if (same || (track == null && _track == null)) return;
    _stop();
    _track = track;
    _big = big;
    if (track != null) fire(_start(track));
  }

  /// In video mode the music changed to a video's sound (or back): show that
  /// video, if it isn't the one showing.
  void _soundChanged() {
    final track = _track, playing = _player.playingVideo.value;
    if (track == null || !_big || playing == null || playing == _id) return;
    _stop();
    _track = track;
    fire(_start(track));
  }

  Future<void> _start(Json track) async {
    final generation = ++_generation;
    final ResolvedStream? picture;
    try {
      final playing = _player.playingVideo.value;
      final id = _id = _big && playing != null && identical(_player.current.value, track)
          ? playing
          : (await sources.videoFor(track))?.id;
      if (generation != _generation) return;
      picture = id == null ? null : await _picture(track, id);
    } catch (error) {
      problemLog.warn('no video for ${trackTitle(track)}: $error');
      return; // no video then: the picture stays
    }
    if (picture == null || _disposed || generation != _generation) return;
    final playback = _Playback.of(picture);
    try {
      // Loading takes a moment, which the music plays on through.
      final music = _player.position;
      await playback
          .open(_player.playing ? music + const Duration(milliseconds: 1500) : music, play: _player.playing)
          .timeout(const Duration(seconds: 20));
    } catch (error) {
      problemLog.warn('video for ${trackTitle(track)} would not open: $error');
      await playback.dispose();
      return;
    }
    if (_disposed || generation != _generation) {
      await playback.dispose();
      return;
    }
    this.playback = playback;
    _rate = _player.speed;
    _nudge = 1;
    _drift = null;
    if (_rate != 1) await playback.setRate(_rate);
    _playing = _player.playingStream.listen((on) => fire(on ? playback.play() : playback.pause()));
    _timer = Timer.periodic(const Duration(milliseconds: 250), (_) => fire(_keepInStep()));
    shown = songVideoShown.value = true;
    notifyListeners();
  }

  /// The picture of video [id]: big enough to watch in video mode (less to
  /// save data), else the smallest, for the blur.
  Future<ResolvedStream?> _picture(Json track, String id) async {
    if (!_big) return (await sources.videoFor(track))?.picture;
    return videoYouTube(id, height: app.settings.saveData ? 360 : 720);
  }

  /// Follow the music: its place (after a seek, or when the video falls
  /// behind) and its speed. A video found by search can be shorter than the
  /// song: it fades out at its end. When the music is the video's own sound,
  /// a small drift is made up by running the picture a little faster or
  /// slower (seeking would stutter), so the lips stay with the singing.
  Future<void> _keepInStep() async {
    final playback = this.playback;
    if (playback == null || _checking) return;
    _checking = true;
    try {
      final music = _player.position;
      final length = playback.duration;
      final over = length > Duration.zero && music >= length;
      if (over == shown) {
        shown = songVideoShown.value = !over;
        notifyListeners();
      }
      if (over) return;
      // Android pauses and resumes videos with the app, whatever the music did.
      if (playback.playing != _player.playing) {
        fire(_player.playing ? playback.play() : playback.pause());
        return;
      }
      final rate = _player.speed;
      // After a seek, give the video time to get there before checking again.
      if (!_player.playing || DateTime.now().isBefore(_settled)) {
        if (rate != _rate) await _setRate(rate, 1);
        _drift = null;
        return;
      }
      final ahead = (await playback.position() - _player.position).inMilliseconds;
      if (playback != this.playback) return;
      if (ahead.abs() > (_exact ? 600 : 350)) {
        problemLog.info('video ${ahead}ms out: seeking it to the music');
        _settled = DateTime.now().add(const Duration(seconds: 3));
        _drift = null;
        await _setRate(rate, 1);
        fire(playback.seek(_player.position + const Duration(milliseconds: 150)));
        return;
      }
      final drift = _drift = _drift == null ? ahead.toDouble() : _drift! * 0.7 + ahead * 0.3;
      final nudge = _exact ? videoNudge(drift) : 1.0;
      // Each change of speed jolts the picture a little (on Windows most), so
      // it changes at most every 2 s, except back to normal once in line.
      final settledIn = nudge == 1 || DateTime.now().difference(_nudged) > const Duration(seconds: 2);
      if (rate != _rate || (nudge != _nudge && settledIn)) await _setRate(rate, nudge);
    } catch (_) {
      // the video is closing; the next check sees
    } finally {
      _checking = false;
    }
  }

  Future<void> _setRate(double rate, double nudge) async {
    if (nudge != _nudge) _nudged = DateTime.now();
    _rate = rate;
    _nudge = nudge;
    await playback?.setRate(rate * nudge);
  }

  void _stop() {
    _generation++;
    _timer?.cancel();
    _timer = null;
    final playing = _playing;
    if (playing != null) fire(playing.cancel());
    _playing = null;
    final playback = this.playback;
    this.playback = null;
    _id = null;
    _track = null;
    final wasShown = shown;
    shown = false;
    // Called while the page builds or closes: say so once that is done.
    if (songVideoShown.value) scheduleMicrotask(() => songVideoShown.value = false);
    if (playback != null) fire(playback.dispose());
    if (wasShown && !_disposed) scheduleMicrotask(() => _disposed ? null : notifyListeners());
  }

  @override
  void dispose() {
    _stop();
    _disposed = true;
    fire(_sound.cancel());
    super.dispose();
  }
}

/// What plays the video, without sound.
abstract class _Playback {
  factory _Playback.of(ResolvedStream video) => Platform.isAndroid ? _ExoPlayback(video) : _MpvPlayback(video);

  /// Load the video at [at]: done when its first picture is ready.
  Future<void> open(Duration at, {required bool play});

  /// Where it is now (asked of the player, not its last report).
  Future<Duration> position();
  Duration get duration;
  bool get playing;
  Future<void> play();
  Future<void> pause();
  Future<void> seek(Duration to);
  Future<void> setRate(double rate);

  /// The picture, fitted to the space it's given.
  Widget view(BoxFit fit);
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

  // value.position is only brought up to date twice a second.
  @override
  Future<Duration> position() async => await _controller.position ?? _controller.value.position;
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
  Widget view(BoxFit fit) {
    final size = _controller.value.size;
    return FittedBox(
      fit: fit,
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
  Future<Duration> position() async => _player.state.position;
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
  Widget view(BoxFit fit) => mkv.Video(
        controller: _controller,
        controls: mkv.NoVideoControls,
        fit: fit,
        fill: Colors.transparent,
        wakelock: false,
        pauseUponEnteringBackgroundMode: false,
      );

  @override
  Future<void> dispose() => _player.dispose();
}
