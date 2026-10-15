// A song's cover in 3D. It tilts as the phone moves (on a computer, as the
// pointer moves over it), drifting slowly when nothing moves it, and its
// subject (found by subject.dart) stands out of the picture: sharp, a little
// bigger and nearer, with a shadow on the rest of the picture, softened
// behind it. A cover without a subject to lift only tilts.

import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:sensors_plus/sensors_plus.dart';

import '../subject.dart';
import '../track.dart';
import '../util.dart';
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
  _Layers? _layers;
  String? _art;

  // Where the phone or the pointer would have the cover tilt, and when it
  // last moved: after a few still seconds the cover drifts on its own.
  Offset _aim = Offset.zero;
  DateTime _moved = DateTime(0);
  Duration _last = Duration.zero;
  StreamSubscription<AccelerometerEvent>? _motion;
  Offset? _held;

  @override
  void initState() {
    super.initState();
    _find();
    if (Platform.isAndroid) {
      _motion = accelerometerEventStream(samplingPeriod: SensorInterval.uiInterval)
          .listen(_phoneMoved, onError: (Object _) {}, cancelOnError: true);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Still, for those who turn animations off.
    final still = MediaQuery.disableAnimationsOf(context);
    if (still && _ticker.isActive) {
      _ticker.stop();
      _tilt.value = Offset.zero;
    } else if (!still && !_ticker.isActive) {
      _last = Duration.zero;
      _ticker.start();
    }
  }

  @override
  void didUpdateWidget(DepthCover old) {
    super.didUpdateWidget(old);
    if (trackArt(old.track, large: true) != trackArt(widget.track, large: true)) {
      // The last cover's pictures go with the old card as it fades out.
      _layers = null;
      _find();
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _motion?.cancel();
    _tilt.dispose();
    super.dispose();
  }

  Future<void> _find() async {
    final art = _art = trackArt(widget.track, large: true);
    final subject = await subjectOf(widget.track);
    if (subject == null || !mounted || art != _art) return;
    final layers = await _Layers.of(subject);
    if (!mounted || art != _art) {
      layers.dispose();
      return;
    }
    setState(() => _layers = layers);
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
  }

  @override
  Widget build(BuildContext context) {
    final layers = _layers;
    final radius = BorderRadius.circular(widget.radius);
    final card = AnimatedSwitcher(
      duration: const Duration(milliseconds: 600),
      child: layers == null
          ? Material(
              key: const ValueKey('flat'),
              elevation: 12,
              borderRadius: radius,
              clipBehavior: Clip.antiAlias,
              child: TrackCover(widget.track, size: null, large: true, radius: widget.radius),
            )
          : Stack(
              key: ValueKey(layers),
              fit: StackFit.expand,
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: radius,
                    boxShadow: const [BoxShadow(color: Color(0x73000000), blurRadius: 28, offset: Offset(0, 12))],
                  ),
                ),
                CustomPaint(painter: _DepthPainter(layers, _tilt, widget.radius)),
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

/// The pictures the 3D cover is drawn from, made once per cover.
class _Layers {
  _Layers(this.subject, this.back, this.shadow);

  final CoverSubject subject;

  /// The cover softened and darkened a little, behind the subject.
  final ui.Image back;

  /// The subject's shadow.
  final ui.Image shadow;

  static Future<_Layers> of(CoverSubject subject) async {
    Future<ui.Image> draw(ui.Image from, ui.ImageFilter filter, {Color? tint, ColorFilter? colour}) async {
      final w = from.width, h = from.height;
      final box = Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble());
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder)..saveLayer(box, Paint()..imageFilter = filter);
      canvas.drawImage(from, Offset.zero, Paint()..colorFilter = colour);
      if (tint != null) canvas.drawRect(box, Paint()..color = tint);
      canvas.restore();
      final picture = recorder.endRecording();
      try {
        return await picture.toImage(w, h);
      } finally {
        picture.dispose();
      }
    }

    final side = subject.picture.width / 720;
    final back = await draw(subject.picture, ui.ImageFilter.blur(sigmaX: 3 * side, sigmaY: 3 * side, tileMode: TileMode.clamp),
        tint: const Color(0x26000000));
    final shadow = await draw(subject.mask, ui.ImageFilter.blur(sigmaX: 7, sigmaY: 7, tileMode: TileMode.decal),
        colour: const ColorFilter.mode(Color(0x8C000000), BlendMode.srcIn));
    return _Layers(subject, back, shadow);
  }

  void dispose() {
    back.dispose();
    shadow.dispose();
  }
}

class _DepthPainter extends CustomPainter {
  _DepthPainter(this.layers, this.tilt, this.radius) : super(repaint: tilt);

  final _Layers layers;
  final ValueListenable<Offset> tilt;
  final double radius;

  static Rect _all(ui.Image image) => Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble());

  @override
  void paint(Canvas canvas, Size size) {
    final subject = layers.subject;
    final box = Offset.zero & size;
    final smooth = Paint()..filterQuality = FilterQuality.medium;
    final t = tilt.value;
    // The subject is nearer than the picture: it moves further as the cover
    // tilts, and its shadow falls the other way.
    final lift = t * size.shortestSide * subjectLean;
    final centre = Offset(subject.centre.dx * size.width, subject.centre.dy * size.height);

    canvas.save();
    canvas.clipRRect(RRect.fromRectAndRadius(box, Radius.circular(radius)));
    canvas.drawImageRect(layers.back, _all(layers.back), box, smooth);
    canvas.drawImageRect(layers.shadow, _all(layers.shadow), box.shift(-lift * 0.8 + Offset(0, size.height * 0.015)), smooth);
    canvas.restore();

    canvas.save();
    canvas.translate(centre.dx + lift.dx, centre.dy + lift.dy);
    canvas.scale(subjectLift);
    canvas.translate(-centre.dx, -centre.dy);
    canvas.saveLayer(box.inflate(size.shortestSide * 0.05), Paint());
    canvas.drawImageRect(subject.picture, _all(subject.picture), box, smooth);
    canvas.drawImageRect(subject.mask, _all(subject.mask), box, Paint()
      ..filterQuality = FilterQuality.medium
      ..blendMode = BlendMode.dstIn);
    canvas.restore();
    canvas.restore();
  }

  @override
  bool shouldRepaint(_DepthPainter old) => old.layers != layers || old.radius != radius;
}
