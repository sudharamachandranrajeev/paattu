// Colours from the song's cover, for Now Playing and the mini player when
// "Colours from the cover" is on: the chosen theme's look (dark or light,
// glass, type) in the cover's colours, changing with the song.

import 'dart:async';
import 'dart:collection';

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../log.dart';
import '../settings.dart';
import '../track.dart';
import '../util.dart';

/// [child] in [track]'s cover's colours, when the setting is on.
class CoverTheme extends StatefulWidget {
  const CoverTheme({super.key, required this.track, required this.child});
  final Json? track;
  final Widget child;

  @override
  State<CoverTheme> createState() => _CoverThemeState();
}

class _CoverThemeState extends State<CoverTheme> {
  ThemeData? _theme;
  String? _for;

  // Themes made lately, by the theme they're made from and the cover.
  static final _made = LinkedHashMap<String, Future<ThemeData?>>();

  void _follow(PaattuTheme base) {
    final track = widget.track;
    final art = track == null ? null : trackArt(track);
    final key = art == null ? null : '${base.id}|$art';
    if (key == _for) return;
    _for = key;
    if (key == null) {
      _theme = null;
      return;
    }
    final made = _made.remove(key) ?? _make(base, art!);
    _made[key] = made;
    while (_made.length > 24) {
      _made.remove(_made.keys.first);
    }
    unawaited(made.then((theme) {
      // Tried again next time when it failed (no network, say).
      if (theme == null && identical(_made[key], made)) _made.remove(key);
      if (mounted && _for == key && theme != null) setState(() => _theme = theme);
    }));
  }

  static Future<ThemeData?> _make(PaattuTheme base, String art) async {
    try {
      final scheme = await ColorScheme.fromImageProvider(
        provider: NetworkImage(art),
        brightness: base.dark ? Brightness.dark : Brightness.light,
        dynamicSchemeVariant: DynamicSchemeVariant.fidelity,
      ).timeout(const Duration(seconds: 20));
      return PaattuTheme(
        'cover',
        'From the cover',
        "The song's cover's colours",
        dark: base.dark,
        background: scheme.surface,
        surface: scheme.surfaceContainerHigh,
        foreground: scheme.onSurface,
        muted: scheme.onSurfaceVariant,
        accent: scheme.primary,
        highlight: scheme.tertiary,
      ).data;
    } catch (error) {
      problemLog.warn("couldn't take colours from the cover: ${errorText(error)}");
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = Paattu.of(context).settings;
    return ListenableBuilder(
      listenable: settings,
      builder: (context, child) {
        final on = settings.coverColors && widget.track != null;
        if (on) {
          _follow(settings.theme);
        } else {
          _for = null;
          _theme = null;
        }
        // Always the same widgets, so what's inside keeps its state (the
        // video playing) when the colours come and go.
        return AnimatedTheme(
          data: (on ? _theme : null) ?? Theme.of(context),
          duration: const Duration(milliseconds: 700),
          child: child!,
        );
      },
      child: widget.child,
    );
  }
}
