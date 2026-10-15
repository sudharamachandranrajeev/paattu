// Why a song wouldn't play, in words for the person listening. The player's
// own errors say little ("Source error" from ExoPlayer, "Failed to open …"
// from mpv), so the stream's HTTP status, asked separately, says more.

import 'dart:async';

import 'package:just_audio/just_audio.dart';

import '../util.dart';

/// A short reason [error] stopped a song, given the stream's HTTP [status]
/// when it was checked.
String playReason(Object error, {int? status}) {
  if (status != null && status >= 400) {
    return switch (status) {
      401 || 403 => 'the site refused to stream it',
      404 || 410 => "it isn't on the site any more",
      429 => 'the site is getting too many requests; try again in a while',
      >= 500 => 'the site is having trouble',
      _ => 'the site said $status',
    };
  }
  if (error is TimeoutException) return 'it took too long to start';
  if (error is PlayerException) {
    final message = (error.message ?? '').toLowerCase();
    if (message.contains('failed host lookup') || message.contains('unable to connect')) {
      return "can't reach the internet";
    }
    if (['recognize file format', 'decod', 'renderer'].any(message.contains)) {
      return "this device can't play that kind of stream";
    }
    return "the stream wouldn't load";
  }
  return errorText(error);
}
