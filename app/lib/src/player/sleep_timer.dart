// Stopping by itself: after a while, or at the end of the song playing. The
// player drives it from its own tick (paattu_audio_handler.dart) and fades
// out when it is up, so nothing is cut off mid-word.
//
// Listeners are told when the timer starts, is cancelled or is up; the time
// left is read straight off [remaining], so a screen showing it ticks on its
// own rather than being rebuilt four times a second.

import 'package:flutter/foundation.dart';

class SleepTimer extends ChangeNotifier {
  SleepTimer({DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  final DateTime Function() _clock;

  /// When a countdown ends, or null when there isn't one.
  DateTime? _ends;

  /// Whether it stops at the end of the song playing instead.
  bool _endOfSong = false;

  /// Whether it is up and hasn't been noticed yet (so the player stops once).
  bool _due = false;

  bool get on => _ends != null || _endOfSong;
  bool get endOfSong => _endOfSong;

  /// Time left on a countdown, or null when it isn't one.
  Duration? get remaining {
    final ends = _ends;
    if (ends == null) return null;
    final left = ends.difference(_clock());
    return left.isNegative ? Duration.zero : left;
  }

  /// Whether it is up. Reads true once: the player notices and stops.
  bool get due => _due;

  /// Stop after [duration], replacing a timer that was running.
  void start(Duration duration) {
    if (duration <= Duration.zero) return cancel();
    _ends = _clock().add(duration);
    _endOfSong = false;
    _due = false;
    notifyListeners();
  }

  /// Stop when the song playing ends.
  void startAtEndOfSong() {
    _ends = null;
    _endOfSong = true;
    _due = false;
    notifyListeners();
  }

  /// Add [duration] to a countdown (or start one from now).
  void extend(Duration duration) {
    _ends = (_ends ?? _clock()).add(duration);
    _endOfSong = false;
    _due = false;
    notifyListeners();
  }

  void cancel() {
    if (!on && !_due) return;
    _ends = null;
    _endOfSong = false;
    _due = false;
    notifyListeners();
  }

  /// The player's tick: a countdown that has run out is up.
  void tick() {
    final ends = _ends;
    if (ends == null || _due) return;
    if (!_clock().isBefore(ends)) _fire();
  }

  /// The song playing ran to its end: an end-of-song timer is up. A song the
  /// person skipped or that broke doesn't count — they're still listening.
  void songEnded() {
    if (!_endOfSong || _due) return;
    _fire();
  }

  void _fire() {
    _ends = null;
    _endOfSong = false;
    _due = true;
    notifyListeners();
  }

  /// The player has stopped for it.
  void noticed() {
    if (!_due) return;
    _due = false;
    notifyListeners();
  }
}

/// What the sheet offers, in minutes.
const sleepPresets = [5, 10, 15, 30, 45, 60, 90];

/// "25 min", "1:05 left" — a countdown in the fewest useful words.
String describeSleep(Duration? left) {
  if (left == null) return '';
  final total = left.inSeconds;
  if (total <= 0) return 'now';
  final h = total ~/ 3600;
  final m = (total % 3600) ~/ 60;
  final s = total % 60;
  if (h > 0) return '$h:${m.toString().padLeft(2, '0')} left';
  if (m > 0) return s == 0 ? '$m min left' : '$m:${s.toString().padLeft(2, '0')} left';
  return '$s s left';
}
