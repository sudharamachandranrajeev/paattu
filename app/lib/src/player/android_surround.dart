// Surround on Android (MainActivity.kt's "sound" channel): the phone's own
// virtualizer on a player's audio session. Stock Android's is AOSP's open
// one; phone makers often put their own in its place (and some apply it only
// on headphones). The desktop widens the stereo with extrastereo instead.

import 'package:flutter/services.dart';

import '../log.dart';

const _channel = MethodChannel('dev.paattu.paattu/sound');

/// The strength each session's virtualizer was last given (0 … 1000).
final _given = <int, int>{};

/// The virtualizer on audio [session] at [surround] (0 none … 1 full); those
/// of sessions not in [live] (players gone) are let go. Only talks to
/// Android when the answer changes.
Future<void> androidSurround(int session, double surround, Iterable<int> live) async {
  final strength = (surround.clamp(0.0, 1.0) * 1000).round();
  if (_given[session] == strength) return;
  _given.removeWhere((s, _) => s != session && !live.contains(s));
  _given[session] = strength;
  try {
    await _channel.invokeMethod<void>('surround', {
      'session': session,
      'strength': strength,
      'live': [...live],
    });
  } catch (error) {
    problemLog.warn('surround on the phone: $error');
  }
}
