// On Windows, the window's title bar in the app's colours: the page's, or the
// song's cover's with "Colours from the cover" on (as Now Playing and the bar
// at the bottom have them), so the frame melts into the app and changes with
// the song. Windows 11 takes the colours (flutter_window.cpp's "window"
// channel); Windows 10 takes only a dark or a light frame.

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../log.dart';

const _channel = MethodChannel('dev.paattu.paattu/window');

/// Gives the title bar the colours of the theme [child] is drawn in. The
/// app's own ([fallback], round the whole app) holds when no song's is shown;
/// a song's (the mini player's, Now Playing's) when one is, the latest built.
class TitleBarColour extends StatefulWidget {
  const TitleBarColour({super.key, required this.child, this.fallback = false});
  final Widget child;
  final bool fallback;

  @override
  State<TitleBarColour> createState() => _TitleBarColourState();
}

class _TitleBarColourState extends State<TitleBarColour> {
  @override
  void dispose() {
    _TitleBar.leave(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (Platform.isWindows) _TitleBar.report(this, Theme.of(context), fallback: widget.fallback);
    return widget.child;
  }
}

abstract final class _TitleBar {
  static final _songs = <Object, ThemeData>{};
  static ThemeData? _app;
  static String _sent = '';
  static bool _broken = false;
  static Timer? _settle;

  static void report(Object who, ThemeData theme, {required bool fallback}) {
    if (fallback) {
      _app = theme;
    } else {
      // The latest goes last.
      _songs
        ..remove(who)
        ..[who] = theme;
    }
    _apply();
  }

  static void leave(Object who) {
    if (_songs.remove(who) != null) _apply();
  }

  // AnimatedTheme rebuilds every frame of a change of colours: the frame
  // takes the colours it comes to rest on, not each one on the way.
  static void _apply() {
    _settle?.cancel();
    _settle = Timer(const Duration(milliseconds: 120), _send);
  }

  static void _send() {
    final theme = _songs.isNotEmpty ? _songs.values.last : _app;
    if (theme == null || _broken) return;
    final scheme = theme.colorScheme;
    // The page's own colour (PaattuTheme's background) with a breath of the
    // accent, like the glass over it; a thin accent edge round the window.
    final caption = Color.alphaBlend(scheme.primary.withValues(alpha: 0.08), scheme.surfaceContainerLowest);
    final border = Color.alphaBlend(scheme.primary.withValues(alpha: 0.35), caption);
    final args = <String, Object>{
      'caption': _rgb(caption),
      'text': _rgb(scheme.onSurface),
      'border': _rgb(border),
      'dark': theme.brightness == Brightness.dark,
    };
    final key = args.values.join(',');
    if (key == _sent) return;
    _sent = key;
    _channel.invokeMethod<void>('setTitleBar', args).catchError((Object error) {
      // An older build of the runner: leave the frame as Windows draws it.
      _broken = true;
      problemLog.warn('title bar: $error');
    });
  }

  static int _rgb(Color c) =>
      ((c.r * 255).round() & 0xff) << 16 | ((c.g * 255).round() & 0xff) << 8 | ((c.b * 255).round() & 0xff);
}
