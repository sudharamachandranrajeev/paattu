// The song's words on Now Playing: the line being sung at the top of the
// cover, its English letters under it, coming in as Settings says (popping
// out of the cover in 3D, fading, or plain) and filled with the cover's own
// colours moving slowly through the letters. Words that aren't timed show as
// a Lyrics button; either way a tap opens all of them.

import 'dart:async';
import 'dart:math';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../lyrics.dart';
import '../settings.dart';
import '../titles.dart';
import '../track.dart';
import '../util.dart';
import 'cover_theme.dart';
import 'glass.dart';

/// The language to look a song's words up in: its own, or the one its names
/// suggest, or the first picked for the charts.
String lyricsLanguage(AppState app, Json track) {
  final own = asString(track['language']);
  if (own.isNotEmpty) return own;
  final picked = app.settings.chartLanguages;
  return guessLanguage([
    asString(track['rawTitle']),
    trackTitle(track),
    asString(track['movie']),
    asString(track['channel']),
  ], fallback: picked.isEmpty ? '' : picked.first);
}

class CoverLyrics extends StatefulWidget {
  const CoverLyrics({super.key, required this.app, required this.track});
  final AppState app;
  final Json track;

  @override
  State<CoverLyrics> createState() => _CoverLyricsState();
}

class _CoverLyricsState extends State<CoverLyrics> with SingleTickerProviderStateMixin {
  // The cover's colours run through the letters once every few seconds.
  late final _flow = AnimationController(vsync: this, duration: const Duration(seconds: 9));
  StreamSubscription<Duration>? _position;
  String? _for;
  Json? _found;
  (Json?, bool)? _shownFor;
  SongLyrics _words = SongLyrics.none;
  List<Color>? _colours;
  int _line = -1;
  Duration _at = Duration.zero;

  @override
  void initState() {
    super.initState();
    _position = widget.app.player.positionStream.listen(_moved);
    _follow();
  }

  @override
  void didUpdateWidget(CoverLyrics old) {
    super.didUpdateWidget(old);
    _follow();
  }

  @override
  void dispose() {
    _position?.cancel();
    _flow.dispose();
    super.dispose();
  }

  void _follow() {
    final key = trackKey(widget.track);
    if (key == _for) return;
    _for = key;
    _found = null;
    _shownFor = null;
    _words = SongLyrics.none;
    _colours = null;
    _line = -1;
    final track = widget.track;
    unawaited(
      widget.app.lyrics.lookup(track, lyricsLanguage(widget.app, track)).then((found) {
        if (mounted && _for == key) {
          setState(() => _found = found);
          _moved(_at);
        }
      }, onError: (Object _) {}),
    );
    final art = trackArt(track, large: true);
    if (art != null) {
      unawaited(
        coverBrightColours(art).then((colours) {
          if (mounted && _for == key && colours != null) setState(() => _colours = colours);
        }),
      );
    }
  }

  void _moved(Duration position) {
    _at = position;
    // A little early, so a line is in place as it's sung.
    final at = _shown(widget.app.settings.lyricsTransliterated).lineAt(position.inMilliseconds / 1000 + 0.25);
    if (at != _line && mounted) setState(() => _line = at);
  }

  SongLyrics _shown(bool latin) {
    if (_shownFor == null || !identical(_shownFor!.$1, _found) || _shownFor!.$2 != latin) {
      _shownFor = (_found, latin);
      _words = shownLyrics(_found, latin: latin);
    }
    return _words;
  }

  @override
  Widget build(BuildContext context) {
    final settings = widget.app.settings;
    final words = _shown(settings.lyricsTransliterated);
    final moving = settings.lyricGradient && words.found;
    if (moving && !_flow.isAnimating) {
      _flow.repeat();
    } else if (!moving && _flow.isAnimating) {
      _flow.stop();
    }
    if (!words.found) return const SizedBox.shrink();
    final colours = _colours ?? [Theme.of(context).colorScheme.primary, Colors.white];
    if (!words.synced) {
      return Align(
        alignment: Alignment.topCenter,
        child: Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Glass(
            blur: true,
            radius: 18,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            onTap: () => showLyrics(context, widget.app, words, colours),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.lyrics_outlined, size: 18),
                const SizedBox(width: 8),
                Text('Lyrics', style: Theme.of(context).textTheme.labelLarge),
              ],
            ),
          ),
        ),
      );
    }
    final line = _line >= 0 ? words.lines[_line] : null;
    final effect = settings.lyricEffect;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => showLyrics(context, widget.app, words, colours),
      child: LayoutBuilder(
        builder: (context, box) {
          final big = (box.maxWidth / 15).clamp(17.0, 30.0);
          return Stack(
            children: [
              // A shade across the top of the cover, so the words read on any picture.
              Positioned.fill(
                child: IgnorePointer(
                  child: AnimatedOpacity(
                    opacity: line != null && line.text.isNotEmpty ? 1 : 0,
                    duration: const Duration(milliseconds: 600),
                    child: const DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Color(0x99000000), Color(0x55000000), Color(0x00000000)],
                          stops: [0, 0.55, 1],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 36),
                // A long line on a small cover shrinks to fit rather than spill.
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.topCenter,
                  child: SizedBox(
                    width: max(0.0, box.maxWidth - 36),
                    child: AnimatedSwitcher(
                      duration: Duration(
                        milliseconds: switch (effect) {
                          LyricEffect.pop => 640,
                          LyricEffect.fade => 450,
                          LyricEffect.plain => 0,
                        },
                      ),
                      switchInCurve: Curves.easeOutCubic,
                      switchOutCurve: Curves.easeInCubic,
                      layoutBuilder: (current, previous) =>
                          Stack(alignment: Alignment.topCenter, children: [...previous, ?current]),
                      transitionBuilder: (child, animation) => _LineTransition(
                        animation: animation,
                        effect: effect,
                        incoming: child.key == ValueKey(_line),
                        child: child,
                      ),
                      child: KeyedSubtree(
                        key: ValueKey(_line),
                        child: line == null || line.text.isEmpty
                            ? const SizedBox(width: double.infinity)
                            : _Line(line: line, size: big, colours: colours, flow: moving ? _flow : null),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// How a line comes in and goes: out of the cover towards you, tipping up
/// from below and coming into focus, and away up and over as the next comes.
class _LineTransition extends AnimatedWidget {
  const _LineTransition({
    required Animation<double> animation,
    required this.effect,
    required this.incoming,
    required this.child,
  }) : super(listenable: animation);

  final LyricEffect effect;
  final bool incoming;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final t = (listenable as Animation<double>).value;
    if (effect == LyricEffect.plain) return child;
    final away = 1 - t;
    final blur = away * (effect == LyricEffect.pop ? 7 : 4);
    Widget out = Opacity(opacity: t.clamp(0.0, 1.0), child: child);
    if (blur > 0.05) {
      out = ImageFiltered(
        imageFilter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: out,
      );
    }
    if (effect == LyricEffect.fade) {
      return Transform.translate(offset: Offset(0, (incoming ? 10 : -8) * away), child: out);
    }
    final matrix = Matrix4.identity()
      ..setEntry(3, 2, 0.0016)
      ..translateByDouble(0, incoming ? 34 * away : -26 * away, incoming ? 60 * away : 0, 1)
      ..rotateX(incoming ? -0.95 * away : 0.75 * away)
      ..scaleByDouble(0.78 + 0.22 * t, 0.78 + 0.22 * t, 1, 1);
    return Transform(alignment: Alignment.center, transform: matrix, child: out);
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.line, required this.size, required this.colours, this.flow});
  final LyricLine line;
  final double size;
  final List<Color> colours;
  final Animation<double>? flow;

  @override
  Widget build(BuildContext context) {
    final glow = [Shadow(color: Colors.black.withValues(alpha: 0.55), blurRadius: 14)];
    final words = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          line.text,
          textAlign: TextAlign.center,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: size,
            fontWeight: FontWeight.w800,
            height: 1.25,
            color: Colors.white,
            shadows: glow,
          ),
        ),
        if (line.latin.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            line.latin,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: size * 0.62,
              fontWeight: FontWeight.w600,
              height: 1.25,
              letterSpacing: 0.3,
              color: Colors.white.withValues(alpha: 0.86),
              shadows: glow,
            ),
          ),
        ],
      ],
    );
    final flow = this.flow;
    if (flow == null) return _filled(words, 0, still: true);
    return AnimatedBuilder(animation: flow, builder: (context, child) => _filled(child!, flow.value), child: words);
  }

  // The letters filled with the cover's colours, the gradient sliding along.
  Widget _filled(Widget words, double at, {bool still = false}) => ShaderMask(
    blendMode: BlendMode.modulate,
    shaderCallback: (bounds) => LinearGradient(
      colors: still ? [colours.first, colours.first] : [...colours, colours.first],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      tileMode: TileMode.mirror,
      transform: _Slide(sin(at * 2 * pi), bounds.width),
    ).createShader(bounds),
    child: words,
  );
}

class _Slide extends GradientTransform {
  const _Slide(this.by, this.width);
  final double by;
  final double width;

  @override
  Matrix4? transform(Rect bounds, {TextDirection? textDirection}) => Matrix4.translationValues(by * width * 0.8, 0, 0);
}

/// All of a song's words in a sheet, its English letters under each line.
void showLyrics(BuildContext context, AppState app, SongLyrics words, List<Color> colours) {
  final theme = Theme.of(context);
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      maxChildSize: 0.95,
      builder: (context, scroll) => ListView(
        controller: scroll,
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
        children: [
          Text('Lyrics', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
          Text(
            [words.language, words.source, if (!words.synced) 'not timed'].where((s) => s.isNotEmpty).join(' · '),
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          for (final line in words.lines)
            if (line.text.isEmpty)
              const SizedBox(height: 14)
            else
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(line.text, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                    if (line.latin.isNotEmpty)
                      Text(
                        line.latin,
                        style: theme.textTheme.bodyMedium?.copyWith(color: colours.first.withValues(alpha: 0.9)),
                      ),
                  ],
                ),
              ),
        ],
      ),
    ),
  );
}
