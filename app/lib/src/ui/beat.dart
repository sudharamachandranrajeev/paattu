// Now Playing's pulse: the song's rhythm (rhythm.dart) followed as it plays,
// once for the whole screen, so the play button's rings and the cover's
// subject move to the same beat. Still while paused, before the rhythm is
// known, and with animations turned off.

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show Ticker;

import '../player/paattu_audio_handler.dart';
import '../player/rhythm.dart';
import '../util.dart';

/// Where the song is: its loudness followed smoothly, the beat jumping up and
/// dying away, and the ripples the hardest beats send out. Painters repaint
/// with it (it is a Listenable), without rebuilding anything.
class Beat extends ChangeNotifier {
  /// 0 (quiet) to 1, rising quickly and falling slowly, so it breathes.
  double level = 0;

  /// 0 to 1: up on a beat, then dying away.
  double punch = 0;

  /// The ripples going out: when each started and how hard its beat was.
  final ripples = <(Duration, double)>[];
  Duration now = Duration.zero;
  Duration _lastRipple = Duration.zero;

  /// How long a ripple takes to go out.
  static const rippleTime = Duration(milliseconds: 700);

  void follow(double loudness, double hit, double seconds, Duration at) {
    now = at;
    level += (loudness - level) * (1 - exp(-seconds * (loudness > level ? 30 : 8)));
    punch = max(hit, punch * exp(-seconds * 9));
    if (hit > 0.6 && at - _lastRipple > const Duration(milliseconds: 220)) {
      _lastRipple = at;
      ripples.add((at, hit));
    }
    ripples.removeWhere((r) => at - r.$1 > rippleTime);
    notifyListeners();
  }

  /// Back to still.
  void settle() {
    level = 0;
    punch = 0;
    ripples.clear();
    notifyListeners();
  }
}

/// Follows [track]'s rhythm while it plays, for everything under it
/// ([BeatDriver.of]).
class BeatDriver extends StatefulWidget {
  const BeatDriver({
    super.key,
    required this.player,
    required this.track,
    required this.playing,
    required this.loading,
    required this.child,
  });
  final PaattuAudioHandler player;
  final Json track;
  final bool playing;
  final bool loading;
  final Widget child;

  /// The beat of the song on screen, or null outside Now Playing.
  static Beat? of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<_BeatScope>()?.beat;

  @override
  State<BeatDriver> createState() => _BeatDriverState();
}

class _BeatDriverState extends State<BeatDriver> with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_tick);
  final _beat = Beat();
  Rhythm? _rhythm;
  Json? _asked;
  int _frame = -1;
  Duration _last = Duration.zero;

  @override
  void initState() {
    super.initState();
    _ask();
  }

  @override
  void didUpdateWidget(BeatDriver old) {
    super.didUpdateWidget(old);
    _ask();
    _run();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _run();
  }

  /// The song's rhythm, asked for once it has loaded (so the player knows
  /// which copy of the song it plays).
  void _ask() {
    final track = widget.track;
    if (widget.loading || identical(track, _asked)) return;
    _asked = track;
    _rhythm = null;
    widget.player.rhythmOf(track).then((rhythm) {
      if (!mounted || !identical(track, _asked)) return;
      _rhythm = rhythm;
      _run();
    });
  }

  /// Moving only while there is something to move with.
  void _run() {
    final moving = _rhythm != null && widget.playing && !widget.loading && !MediaQuery.disableAnimationsOf(context);
    if (moving && !_ticker.isActive) {
      _frame = -1;
      _last = Duration.zero;
      _ticker.start();
    } else if (!moving && _ticker.isActive) {
      _ticker.stop();
      _beat.settle();
    }
  }

  void _tick(Duration elapsed) {
    final rhythm = _rhythm;
    if (rhythm == null) return;
    final step = (elapsed - _last).inMicroseconds / Duration.microsecondsPerSecond;
    _last = elapsed;
    final frame = rhythm.frameAt(widget.player.position);
    // Every frame since the last refresh (none skipped); a seek starts afresh.
    final from = _frame < 0 || frame < _frame || frame - _frame > 10 ? frame : _frame + 1;
    _frame = frame;
    _beat.follow(rhythm.levelOf(frame), rhythm.punchBetween(from, frame), step.clamp(0.0, 0.1), elapsed);
  }

  @override
  void dispose() {
    _ticker.dispose();
    _beat.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _BeatScope(beat: _beat, child: widget.child);
}

class _BeatScope extends InheritedWidget {
  const _BeatScope({required this.beat, required super.child});
  final Beat beat;

  @override
  bool updateShouldNotify(_BeatScope old) => old.beat != beat;
}
