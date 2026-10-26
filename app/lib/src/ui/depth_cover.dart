// A song's cover in 3D. It tilts as the phone moves (on a computer, as the
// pointer moves over it), drifting slowly when nothing moves it, and the
// picture has depth: depth.dart makes a soft map of how near each point of
// it is, and a shader (shaders/depth_cover.frag) moves each point by that as
// the cover leans, so its subject (found by subject.dart) glides over what
// is behind it in one piece, with no cut-out edge to show. A cover without a
// subject is taken as layers of its own colours, which also drift slowly
// past each other under a slow sheen. On Now Playing (beat.dart) the near
// parts swell a little on each beat while the rest breathes with the
// loudness. The effect eases in over the plain cover once the map is ready.

import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:sensors_plus/sensors_plus.dart';

import '../log.dart';
import '../subject.dart';
import '../track.dart';
import '../util.dart';
import 'beat.dart';
import 'widgets.dart';

class DepthCover extends StatefulWidget {
  const DepthCover({super.key, required this.track, this.radius = 24});
  final Json track;
  final double radius;

  @override
  State<DepthCover> createState() => _DepthCoverState();
}

class _DepthCoverState extends State<DepthCover> with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_tick);
  final _tilt = ValueNotifier(Offset.zero);
  // Seconds, for the drift, and how far the effect has come in, 0 to 1.
  final _clock = ValueNotifier(0.0);
  final _strength = ValueNotifier(0.0);
  CoverDepth? _depth;
  ui.FragmentShader? _shader;
  String? _art;
  bool _still = false;

  // Where the phone or the pointer would have the cover tilt, and when it
  // last moved: after a few still seconds the cover drifts on its own.
  Offset _aim = Offset.zero;
  DateTime _moved = DateTime(0);
  Duration _last = Duration.zero;
  StreamSubscription<AccelerometerEvent>? _motion;
  Offset? _held;

  static Future<ui.FragmentProgram>? _program;

  @override
  void initState() {
    super.initState();
    _find();
    (_program ??= ui.FragmentProgram.fromAsset('shaders/depth_cover.frag')).then((program) {
      if (mounted) setState(() => _shader = program.fragmentShader());
    }, onError: (Object error) {
      _program = null;
      problemLog.warn("couldn't load the cover in 3D's shader: ${errorText(error)}");
    });
    if (Platform.isAndroid) {
      _motion = accelerometerEventStream(samplingPeriod: SensorInterval.uiInterval)
          .listen(_phoneMoved, onError: (Object _) {}, cancelOnError: true);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Still, for those who turn animations off: the depth without the motion.
    final still = _still = MediaQuery.disableAnimationsOf(context);
    if (still && _ticker.isActive) {
      _ticker.stop();
      _tilt.value = Offset.zero;
    } else if (!still && !_ticker.isActive) {
      _last = Duration.zero;
      _ticker.start();
    }
    if (still && _depth != null) _strength.value = 1;
  }

  @override
  void didUpdateWidget(DepthCover old) {
    super.didUpdateWidget(old);
    if (trackArt(old.track, large: true) != trackArt(widget.track, large: true)) {
      // The last cover's pictures go with the old card as it fades out.
      _depth = null;
      _find();
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _motion?.cancel();
    _tilt.dispose();
    _clock.dispose();
    _strength.dispose();
    _shader?.dispose();
    super.dispose();
  }

  Future<void> _find() async {
    final art = _art = trackArt(widget.track, large: true);
    final depth = await depthOf(widget.track);
    if (depth == null || !mounted || art != _art) return;
    _strength.value = _still ? 1 : 0;
    setState(() => _depth = depth);
  }

  /// Gravity across and down the screen, against how the phone is usually
  /// held (which it follows slowly), so the cover tilts with movements, not
  /// with the way it's held.
  void _phoneMoved(AccelerometerEvent event) {
    final now = Offset(event.x, event.y);
    final held = _held = Offset.lerp(_held ?? now, now, 0.03)!;
    final moved = now - held;
    _aim = Offset((-moved.dx / 2.5).clamp(-1.0, 1.0), (moved.dy / 2.5).clamp(-1.0, 1.0));
    if (moved.distance > 0.2) _moved = DateTime.now();
  }

  void _pointerMoved(Offset at) {
    final size = context.size;
    if (size == null || size.isEmpty) return;
    _aim = Offset((at.dx / size.width * 2 - 1).clamp(-1.0, 1.0), (at.dy / size.height * 2 - 1).clamp(-1.0, 1.0));
    _moved = DateTime.now();
  }

  void _tick(Duration elapsed) {
    final seconds = (elapsed - _last).inMicroseconds / 1e6;
    _last = elapsed;
    final t = elapsed.inMicroseconds / 1e6;
    final still = DateTime.now().difference(_moved) > const Duration(seconds: 3);
    final aim = still ? Offset(sin(t * 0.45) * 0.35, cos(t * 0.31) * 0.25) : _aim;
    final next = _tilt.value + (aim - _tilt.value) * (1 - exp(-seconds * 5));
    if ((next - _tilt.value).distance > 0.0004) _tilt.value = next;
    if (_depth != null) {
      _clock.value = t;
      if (_strength.value < 1) _strength.value = min(1.0, _strength.value + seconds / 1.2);
    }
  }

  @override
  Widget build(BuildContext context) {
    final depth = _depth, shader = _shader;
    final radius = BorderRadius.circular(widget.radius);
    final card = AnimatedSwitcher(
      duration: const Duration(milliseconds: 600),
      child: depth == null || shader == null
          ? Material(
              key: const ValueKey('flat'),
              elevation: 12,
              borderRadius: radius,
              clipBehavior: Clip.antiAlias,
              child: TrackCover(widget.track, size: null, large: true, radius: widget.radius),
            )
          : Stack(
              key: ValueKey(depth),
              fit: StackFit.expand,
              children: [
                // The same shadow as the plain cover's, so the card doesn't
                // seem to gain a dark layer behind it as it leans.
                DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: radius,
                    boxShadow: kElevationToShadow[12],
                  ),
                ),
                CustomPaint(
                  painter: _DepthPainter(depth, shader, _tilt, _clock, _strength, BeatDriver.of(context), widget.radius),
                ),
              ],
            ),
    );
    return MouseRegion(
      onHover: (event) => _pointerMoved(event.localPosition),
      onExit: (_) => _aim = Offset.zero,
      child: ValueListenableBuilder<Offset>(
        valueListenable: _tilt,
        child: card,
        builder: (context, tilt, card) => Transform(
          alignment: Alignment.center,
          transform: Matrix4.identity()
            ..setEntry(3, 2, 0.0015)
            ..rotateX(-tilt.dy * 0.2)
            ..rotateY(tilt.dx * 0.2),
          child: card,
        ),
      ),
    );
  }
}

/// The cover drawn by shaders/depth_cover.frag (its uniforms in order).
class _DepthPainter extends CustomPainter {
  _DepthPainter(this.depth, this.shader, this.tilt, this.clock, this.strength, this.beat, this.radius)
      : super(repaint: Listenable.merge([tilt, clock, strength, beat]));

  final CoverDepth depth;
  final ui.FragmentShader shader;
  final ValueListenable<Offset> tilt;
  final ValueListenable<double> clock;
  final ValueListenable<double> strength;
  final Beat? beat;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final t = tilt.value, s = strength.value;
    final values = [
      size.width, size.height,
      t.dx, t.dy,
      depth.centre.dx, depth.centre.dy,
      s * s * (3 - 2 * s),
      beat?.punch ?? 0,
      beat?.level ?? 0,
      clock.value,
      // A subject stands still but for a breath; layers drift.
      depth.subject ? 0.25 : 1.0,
      min(0.5, radius / size.width),
      size.width,
    ];
    for (var i = 0; i < values.length; i++) {
      shader.setFloat(i, values[i]);
    }
    shader
      ..setImageSampler(0, depth.picture, filterQuality: FilterQuality.medium)
      ..setImageSampler(1, depth.depth, filterQuality: FilterQuality.low);
    canvas.drawRect(Offset.zero & size, Paint()..shader = shader);
  }

  @override
  bool shouldRepaint(_DepthPainter old) =>
      old.depth != depth || old.shader != shader || old.radius != radius || old.beat != beat;
}
