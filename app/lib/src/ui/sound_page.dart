// Sound: a fifteen-band equaliser drawn over its curve, presets (yours
// too), and knobs for the preamp, bass, treble, balance and speed. Moving a
// control plays it straight away; letting go keeps it. Fine steps (or Shift
// on a keyboard) move the bands in tenths of a dB, slowly, from where they are.

import 'dart:io';
import 'dart:math';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_state.dart';
import '../sound.dart';
import 'glass.dart';
import 'widgets.dart';

void openSound(BuildContext context) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const SoundPage()));

class SoundPage extends StatefulWidget {
  const SoundPage({super.key});

  @override
  State<SoundPage> createState() => _SoundPageState();
}

class _SoundPageState extends State<SoundPage> {
  late final AppState _app = Paattu.of(context);
  late Sound _sound = _app.settings.sound;
  bool _fine = false;

  /// A control moving: heard now, kept when it's let go. Shaping the sound
  /// while the equaliser is off turns it on.
  void _move(Sound next, {bool shaping = true}) {
    if (shaping && !next.on) return _keep(next.copyWith(on: true));
    setState(() => _sound = next);
    fire(_app.player.setSound(next, live: true));
  }

  void _keep(Sound next) {
    setState(() => _sound = next);
    _app.settings.sound = next;
    fire(_app.player.setSound(next));
  }

  Future<void> _saveAs() async {
    final name = await askText(context, title: 'Save the bands as a preset', label: 'Name', action: 'Save');
    if (name == null || !mounted) return;
    if (isBuiltInPreset(name)) {
      _app.toast('$name is a built-in preset. Pick another name');
      return;
    }
    _keep(_sound.savedAs(name));
    _app.toast('Saved $name');
  }

  Future<void> _delete(SoundPreset preset) async {
    final ok = await confirm(context, title: 'Delete ${preset.name}?', action: 'Delete');
    if (ok && mounted) _keep(_sound.withoutPreset(preset.id));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final s = _sound;
    final pre = s.gains['pre']!;
    final android = Platform.isAndroid;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sound'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Switch(value: s.on, onChanged: (on) => _keep(s.copyWith(on: on))),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          Text(s.summary, style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
          const SizedBox(height: 12),
          AnimatedOpacity(
            opacity: s.on ? 1 : 0.55,
            duration: const Duration(milliseconds: 200),
            child: Glass(
              radius: 28,
              padding: const EdgeInsets.fromLTRB(4, 14, 4, 10),
              child: SizedBox(
                height: 276,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: CustomPaint(painter: _CurvePainter(s, scheme.primary, scheme.onSurfaceVariant)),
                    ),
                    Row(
                      children: [
                        for (var i = 0; i < soundBands.length; i++)
                          Expanded(
                            child: _BandSlider(
                              label: bandLabel(soundBands[i]),
                              value: s.bands[i],
                              fine: _fine,
                              onChanged: (v) => _move(s.withBands([...s.bands]..[i] = v)),
                              onChangeEnd: (v) => _keep(_sound.withBands([..._sound.bands]..[i] = v)),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              FilterChip(
                avatar: const Icon(Icons.tune, size: 18),
                label: const Text('Fine steps'),
                tooltip: 'Move the bands in tenths of a dB, slowly, from where they are (or hold Shift)',
                selected: _fine,
                onSelected: (on) => setState(() => _fine = on),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text('15 bands, 25 Hz to 16 kHz. Double-tap a band for 0.',
                    style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
              ),
            ],
          ),
          const SectionHeader('Presets'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final p in s.presets)
                p.saved
                    ? InputChip(
                        label: Text(p.name),
                        selected: s.on && s.preset == p.id,
                        onPressed: () => _keep(s.withPreset(p.id)),
                        onDeleted: () => _delete(p),
                        deleteButtonTooltipMessage: 'Delete ${p.name}',
                      )
                    : ChoiceChip(
                        label: Text(p.name),
                        selected: s.on && s.preset == p.id,
                        onSelected: (_) => _keep(s.withPreset(p.id)),
                      ),
              ActionChip(avatar: const Icon(Icons.add, size: 18), label: const Text('Save as…'), onPressed: _saveAs),
            ],
          ),
          const SectionHeader('Tone'),
          Wrap(
            alignment: WrapAlignment.spaceEvenly,
            spacing: 12,
            runSpacing: 16,
            children: [
              _Knob(
                label: 'Preamp',
                value: s.preamp,
                format: soundDb,
                onChanged: (v) => _move(s.copyWith(preamp: v)),
                onChangeEnd: (v) => _keep(_sound.copyWith(preamp: v)),
              ),
              _Knob(
                label: 'Bass',
                value: s.bass,
                format: soundDb,
                onChanged: (v) => _move(s.copyWith(bass: v)),
                onChangeEnd: (v) => _keep(_sound.copyWith(bass: v)),
              ),
              _Knob(
                label: 'Treble',
                value: s.treble,
                format: soundDb,
                onChanged: (v) => _move(s.copyWith(treble: v)),
                onChangeEnd: (v) => _keep(_sound.copyWith(treble: v)),
              ),
              // The phone's effects can't move sound between the speakers.
              if (!android)
                _Knob(
                  label: 'Balance',
                  value: s.balance,
                  min: -1,
                  max: 1,
                  step: 0.05,
                  format: (v) => v == 0 ? 'Centre' : '${v < 0 ? 'L' : 'R'} ${(v.abs() * 100).round()}%',
                  onChanged: (v) => _move(s.copyWith(balance: v)),
                  onChangeEnd: (v) => _keep(_sound.copyWith(balance: v)),
                ),
              _Knob(
                label: 'Speed',
                value: s.speed,
                min: speedMin,
                max: speedMax,
                origin: 1,
                step: 0.05,
                format: (v) => '${speedText(v)}×',
                onChanged: (v) => _move(s.copyWith(speed: v), shaping: false),
                onChangeEnd: (v) => _keep(_sound.copyWith(speed: v)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Keep loud songs from clipping'),
            subtitle: Text(s.noclip && pre != s.preamp
                ? 'The preamp plays at ${soundDb(pre)} dB, leaving room for the boosts'
                : 'Lowers the preamp by the biggest boost'),
            value: s.noclip,
            onChanged: (on) => _keep(s.copyWith(noclip: on)),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => _keep(s.reset()),
              icon: const Icon(Icons.restart_alt),
              label: const Text('Reset to flat'),
            ),
          ),
          Text(
            'Drag a slider or knob, or scroll over it. Double-tap one to put it back. '
            'Speed keeps the pitch and works with the equaliser off.',
            style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

/// Where a slider's track is: the value above it, the band below.
const _labelHeight = 22.0;
const _trackInset = _labelHeight + 10;

/// The curve behind the sliders, on their scale: each column is an octave,
/// centred on its band.
class _CurvePainter extends CustomPainter {
  _CurvePainter(this.sound, this.accent, this.muted);
  final Sound sound;
  final Color accent;
  final Color muted;

  @override
  void paint(Canvas canvas, Size size) {
    final top = _trackInset, height = size.height - 2 * _trackInset;
    if (height <= 0) return;
    double yOf(double db) => top + (soundLimit - db.clamp(-soundLimit, soundLimit)) / (2 * soundLimit) * height;
    final grid = Paint()
      ..color = muted.withValues(alpha: 0.18)
      ..strokeWidth = 1;
    for (final db in [-12.0, -6.0, 0.0, 6.0, 12.0]) {
      canvas.drawLine(Offset(0, yOf(db)), Offset(size.width, yOf(db)), grid..color = muted.withValues(alpha: db == 0 ? 0.3 : 0.14));
    }
    final column = size.width / soundBands.length;
    final shape = sound.curve.where((g) => g.$2 != 0).toList();
    final line = Path();
    for (var x = 0.0; x <= size.width; x += 2) {
      // A column is 2/3 octave, the first centred on 25 Hz.
      final f = 25 * pow(2, (x - column / 2) / column * 2 / 3);
      final y = yOf(shape.isEmpty ? 0 : soundResponse(shape, f.toDouble()));
      if (x == 0) {
        line.moveTo(x, y);
      } else {
        line.lineTo(x, y);
      }
    }
    final fill = Path.from(line)
      ..lineTo(size.width, yOf(0))
      ..lineTo(0, yOf(0))
      ..close();
    canvas.drawPath(
      fill,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [accent.withValues(alpha: 0.28), accent.withValues(alpha: 0.04), accent.withValues(alpha: 0.28)],
        ).createShader(Rect.fromLTWH(0, top, size.width, height)),
    );
    canvas.drawPath(
      line,
      Paint()
        ..color = accent.withValues(alpha: 0.9)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(_CurvePainter old) => old.sound != sound || old.accent != accent || old.muted != muted;
}

double _snap(double v, double min, double max, double step) => ((v / step).round() * step).clamp(min, max).toDouble();

/// Scrolling over a control steps it (and not the page), saving once the
/// scrolling stops.
mixin _Wheel<T extends StatefulWidget> on State<T> {
  double get value;
  double get step;
  double snap(double v);
  void moved(double v);
  void committed(double v);

  DateTime _lastWheel = DateTime(0);

  void onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    GestureBinding.instance.pointerSignalResolver.register(event, (event) {
      final scroll = event as PointerScrollEvent;
      final next = snap(value + (scroll.scrollDelta.dy < 0 ? step : -step));
      moved(next);
      final at = _lastWheel = DateTime.now();
      Future.delayed(const Duration(milliseconds: 450), () {
        if (mounted && _lastWheel == at) committed(value);
      });
    });
  }
}

class _BandSlider extends StatefulWidget {
  const _BandSlider({
    required this.label,
    required this.value,
    required this.onChanged,
    required this.onChangeEnd,
    this.fine = false,
  });
  final String label;
  final double value;

  /// Tenths of a dB, a quarter as fast, from where it is (also with Shift held).
  final bool fine;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;

  @override
  State<_BandSlider> createState() => _BandSliderState();
}

class _BandSliderState extends State<_BandSlider> with _Wheel {
  bool _dragging = false;

  /// Where a fine drag started, and the value then.
  double _fromDy = 0, _fromValue = 0;

  bool get _fine => widget.fine || HardwareKeyboard.instance.isShiftPressed;

  @override
  double get value => widget.value;
  @override
  double get step => _fine ? 0.1 : 0.5;
  @override
  double snap(double v) => tenth(_snap(v, -soundLimit, soundLimit, step));
  @override
  void moved(double v) => widget.onChanged(v);
  @override
  void committed(double v) => widget.onChangeEnd(v);

  double _at(double dy, double height) {
    final perPixel = 2 * soundLimit / max(1, height - 2 * _trackInset);
    if (_fine) return snap(_fromValue - (dy - _fromDy) * perPixel / 4);
    return snap(soundLimit - (dy - _trackInset) * perPixel);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final text = soundDb(widget.value);
    return LayoutBuilder(builder: (context, box) {
      return Semantics(
        slider: true,
        label: '${widget.label} hertz',
        value: '$text dB',
        increasedValue: '${soundDb(snap(widget.value + step))} dB',
        decreasedValue: '${soundDb(snap(widget.value - step))} dB',
        onIncrease: () => committed(snap(widget.value + step)),
        onDecrease: () => committed(snap(widget.value - step)),
        child: Listener(
          onPointerSignal: onPointerSignal,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            dragStartBehavior: DragStartBehavior.down,
            onVerticalDragStart: (d) {
              setState(() => _dragging = true);
              _fromDy = d.localPosition.dy;
              _fromValue = widget.value;
              moved(_at(d.localPosition.dy, box.maxHeight));
            },
            onVerticalDragUpdate: (d) {
              final v = _at(d.localPosition.dy, box.maxHeight);
              if (v != widget.value) moved(v);
            },
            onVerticalDragEnd: (_) {
              setState(() => _dragging = false);
              committed(widget.value);
            },
            onVerticalDragCancel: () => setState(() => _dragging = false),
            onDoubleTap: () => committed(0),
            child: Column(
              children: [
                SizedBox(
                  height: _labelHeight,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: Center(
                      child: FittedBox(
                        child: Text(text,
                            style: theme.textTheme.labelSmall?.copyWith(
                                color: _dragging ? scheme.primary : scheme.onSurface,
                                fontWeight: _dragging ? FontWeight.w700 : FontWeight.w500)),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: _trackInset - _labelHeight),
                Expanded(
                  child: CustomPaint(
                    size: Size.infinite,
                    painter: _TrackPainter(widget.value, scheme.primary, scheme.onSurface, _dragging),
                  ),
                ),
                const SizedBox(height: _trackInset - _labelHeight),
                SizedBox(
                  height: _labelHeight,
                  child: Padding(
                    // A gap, so neighbouring labels on a narrow phone don't run together.
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: Center(
                      child: FittedBox(
                        child: Text(widget.label, style: theme.textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant)),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    });
  }
}

class _TrackPainter extends CustomPainter {
  _TrackPainter(this.value, this.accent, this.foreground, this.pressed);
  final double value;
  final Color accent;
  final Color foreground;
  final bool pressed;

  @override
  void paint(Canvas canvas, Size size) {
    final x = size.width / 2;
    double yOf(double db) => (soundLimit - db) / (2 * soundLimit) * size.height;
    final track = Paint()
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(x, 0), Offset(x, size.height), track..color = foreground.withValues(alpha: 0.12));
    canvas.drawLine(Offset(x, yOf(0)), Offset(x, yOf(value)), track..color = accent);
    final r = pressed ? 9.0 : 7.5;
    canvas.drawCircle(Offset(x, yOf(value)), r, Paint()..color = accent);
    canvas.drawCircle(
      Offset(x, yOf(value)),
      r,
      Paint()
        ..color = foreground.withValues(alpha: 0.9)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(_TrackPainter old) =>
      old.value != value || old.accent != accent || old.foreground != foreground || old.pressed != pressed;
}

/// A rotary knob: drag up or down, scroll, or double-tap to put it back to
/// [origin], which sits at the top.
class _Knob extends StatefulWidget {
  const _Knob({
    required this.label,
    required this.value,
    required this.format,
    required this.onChanged,
    required this.onChangeEnd,
    this.min = -soundLimit,
    this.max = soundLimit,
    this.origin = 0,
    this.step = 0.5,
  });
  final String label;
  final double value;
  final String Function(double value) format;
  final double min;
  final double max;
  final double origin;
  final double step;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;

  @override
  State<_Knob> createState() => _KnobState();
}

class _KnobState extends State<_Knob> with _Wheel {
  static const _size = 72.0;
  bool _dragging = false;
  double _startY = 0;
  double _startTurn = 0;

  @override
  double get value => widget.value;
  @override
  double get step => widget.step;
  @override
  double snap(double v) => _snap(v, widget.min, widget.max, widget.step);
  @override
  void moved(double v) => widget.onChanged(v);
  @override
  void committed(double v) => widget.onChangeEnd(v);

  /// How far round the knob is: -1 (all the way left) … 0 (origin) … 1.
  double _turnOf(double v) {
    final w = widget;
    if (v >= w.origin) return w.max > w.origin ? (v - w.origin) / (w.max - w.origin) : 0;
    return w.origin > w.min ? -(w.origin - v) / (w.origin - w.min) : 0;
  }

  double _valueOf(double turn) {
    final w = widget;
    final t = turn.clamp(-1.0, 1.0);
    return snap(t >= 0 ? w.origin + t * (w.max - w.origin) : w.origin + t * (w.origin - w.min));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final text = widget.format(widget.value);
    return Semantics(
      slider: true,
      label: widget.label,
      value: text,
      increasedValue: widget.format(snap(widget.value + step)),
      decreasedValue: widget.format(snap(widget.value - step)),
      onIncrease: () => committed(snap(widget.value + step)),
      onDecrease: () => committed(snap(widget.value - step)),
      child: Listener(
        onPointerSignal: onPointerSignal,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onVerticalDragStart: (d) => setState(() {
            _dragging = true;
            _startY = d.localPosition.dy;
            _startTurn = _turnOf(widget.value);
          }),
          // A full turn either way for 150 px.
          onVerticalDragUpdate: (d) {
            final v = _valueOf(_startTurn + (_startY - d.localPosition.dy) / 150);
            if (v != widget.value) moved(v);
          },
          onVerticalDragEnd: (_) {
            setState(() => _dragging = false);
            committed(widget.value);
          },
          onVerticalDragCancel: () => setState(() => _dragging = false),
          onDoubleTap: () => committed(widget.origin),
          child: SizedBox(
            width: 84,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedScale(
                  scale: _dragging ? 1.05 : 1,
                  duration: const Duration(milliseconds: 90),
                  child: SizedBox(
                    width: _size,
                    height: _size,
                    child: CustomPaint(
                      painter: _KnobPainter(_turnOf(widget.value), scheme.primary, scheme.onSurface),
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          child: FittedBox(
                            child: Text(text,
                                style: theme.textTheme.labelMedium?.copyWith(
                                    fontWeight: FontWeight.w700, color: _dragging ? scheme.primary : scheme.onSurface)),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(widget.label, style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _KnobPainter extends CustomPainter {
  _KnobPainter(this.turn, this.accent, this.foreground);
  final double turn;
  final Color accent;
  final Color foreground;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2 - 4;
    const deg = pi / 180;
    // 270° of travel, from the lower left round to the lower right; the
    // origin is at the top (270°, as the canvas measures from 3 o'clock).
    final at = 270 + turn * 135;
    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    final rect = Rect.fromCircle(center: c, radius: r);
    canvas.drawArc(rect, 135 * deg, 270 * deg, false, arc..color = foreground.withValues(alpha: 0.14));
    if ((at - 270).abs() > 0.5) {
      canvas.drawArc(rect, min(at, 270.0) * deg, (at - 270).abs() * deg, false, arc..color = accent);
    }
    canvas.drawCircle(c, r - 9, Paint()..color = foreground.withValues(alpha: 0.07));
    canvas.drawCircle(c + Offset(cos(at * deg), sin(at * deg)) * (r - 15), 3, Paint()..color = accent);
  }

  @override
  bool shouldRepaint(_KnobPainter old) => old.turn != turn || old.accent != accent || old.foreground != foreground;
}
