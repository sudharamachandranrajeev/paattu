// What kind of device this is (MainActivity.kt's "device" channel). A TV
// has little memory and storage to spare, so Paattu keeps less there: no
// songs kept offline unless asked, a smaller picture cache and fewer songs
// held ready ahead.

import 'dart:io';

import 'package:flutter/services.dart';

import 'log.dart';

const _channel = MethodChannel('dev.paattu.paattu/device');

/// Whether Paattu runs on a TV (Android TV, Google TV, a TV box).
bool onTv = false;

/// Find out once, at the start, before the settings are read.
Future<void> detectDevice() async {
  if (!Platform.isAndroid) return;
  try {
    onTv = await _channel.invokeMethod<bool>('isTv') ?? false;
  } catch (error) {
    problemLog.warn('which device: $error');
  }
}
