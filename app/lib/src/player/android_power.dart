// What Android needs for music to keep playing with the screen locked
// (MainActivity.kt's "power" channel): Wi-Fi held awake while playing, the
// notification permission (Android 13+), and being left out of battery
// optimisation on phones that stop apps in the background. Also writing to a
// folder picked for the kept songs.

import 'dart:io';

import 'package:flutter/services.dart';

import '../log.dart';

const _channel = MethodChannel('dev.paattu.paattu/power');

bool? _awake;

/// Hold Wi-Fi awake while [on] (music playing or about to). Called on every
/// state change, so it only talks to Android when the answer changes.
Future<void> androidKeepAwake(bool on) async {
  if (!Platform.isAndroid || _awake == on) return;
  _awake = on;
  try {
    await _channel.invokeMethod<void>('keepAwake', {'on': on});
  } catch (error) {
    problemLog.warn('keeping Wi-Fi awake: $error');
  }
}

/// Whether the media notification (and with it the lock screen and launcher
/// widget controls) is allowed. Always true before Android 13.
Future<bool> androidNotificationsAllowed() => _ask('notificationsAllowed');

/// Ask for the notification permission, if it isn't given yet.
Future<void> androidAskNotifications() => _ask('askNotifications');

/// Whether Paattu is left out of battery optimisation.
Future<bool> androidBatteryExempt() => _ask('batteryExempt');

/// Show Android's "let Paattu run in the background?" question.
Future<void> androidAskBatteryExempt() => _ask('askBatteryExempt');

/// Whether Paattu may write to folders other than its own (Android 11+:
/// "All files access"; before that, the storage permission).
Future<bool> androidFilesAllowed() => _ask('filesAllowed');

/// Ask for that: the system's settings page on Android 11+, the permission
/// question before.
Future<void> androidAskFiles() => _ask('askFiles');

Future<bool> _ask(String method) async {
  if (!Platform.isAndroid) return true;
  try {
    return await _channel.invokeMethod<bool>(method) ?? true;
  } catch (error) {
    problemLog.warn('$method: $error');
    return true;
  }
}
