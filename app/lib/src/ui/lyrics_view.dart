// The song's words on Now Playing: the line being sung at the top of the
// cover, its English letters under it, coming in as Settings says (popping
// out of the cover in 3D, bursting in comic-book style, filling as it's sung,
// glowing into focus, fading, or plain) and filled with the cover's own
// colours moving slowly through the letters: the colours Now Playing takes
// from the cover, which also light the glows and the bursts as lines go. Words that aren't timed show as
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

class _CoverLyricsState extends State<CoverLyrics> with TickerProviderStateMixin {
  // The cover's colours run through the letters once every few seconds.
  late final _flow = AnimationController(vsync: this, duration: const Duration(seconds: 9));
  // How much of the line has been sung, for Karaoke.
  late final _sung = AnimationController(vsync: this);
  StreamSubscription<Duration>? _position;
  // The colours stand still while the song is paused.
  StreamSubscription<bool>? _playing;
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
    _playing = widget.app.player.playingStream.distinct().listen((_) {
      if (mounted) setState(() {});
    });
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
    _playing?.cancel();
    _flow.dispose();
    _sung.dispose();
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
    final words = _shown(widget.app.settings.lyricsTransliterated);
    final now = position.inMilliseconds / 1000;
    final at = words.lineAt(now + 0.25);
    if (at != _line && mounted) setState(() => _line = at);
    if (widget.app.settings.lyricEffect == LyricEffect.karaoke && at >= 0 && mounted) _sing(words, at, now);
  }

  // Karaoke: the line fills from when it starts to when the next does (ten
  // seconds at most, for a line before a long break), kept with the song.
  void _sing(SongLyrics words, int at, double now) {
    final start = words.lines[at].time ?? 0;
    final next = at + 1 < words.lines.length ? words.lines[at + 1].time ?? start + 4 : start + 4;
    final end = min(next, start + 10);
    final sung = end > start ? ((now - start) / (end - start)).clamp(0.0, 1.0) : 1.0;
    if (!widget.app.player.playing) {
      _sung.stop();
      _sung.value = sung;
    } else if (!_sung.isAnimating || (_sung.value - sung).abs() > 0.04) {
      _sung.value = sung;
      final left = max(0.0, end - now);
      if (left > 0) _sung.animateTo(1, duration: Duration(milliseconds: (left * 1000).round()));
    }
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
    if (moving && widget.app.player.playing && !_flow.isAnimating) {
      _flow.repeat();
    } else if ((!moving || !widget.app.player.playing) && _flow.isAnimating) {
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
    final shown = _line;
    final effect = settings.lyricEffect;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => showLyrics(context, widget.app, words, colours),
      child: LayoutBuilder(
        builder: (context, box) {
          final big = (box.maxWidth / 15).clamp(17.0, 30.0);
          return Stack(
            children: [
              // A soft shade behind the words, so they read on any picture.
              // It fades out before its edges: the 3D cover leans and swells
              // under it, and a shade with edges showed as a grey patch
              // where the cover had moved from.
              Positioned.fill(
                child: IgnorePointer(
                  child: AnimatedOpacity(
                    opacity: line != null && line.text.isNotEmpty ? 1 : 0,
                    duration: const Duration(milliseconds: 600),
                    child: const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: RadialGradient(
                          center: Alignment(0, -0.2),
                          radius: 0.4,
                          colors: [Color(0x8C000000), Color(0x4D000000), Color(0x00000000)],
                          stops: [0, 0.6, 1],
                          transform: _Widen(),
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
                          LyricEffect.comic => 760,
                          LyricEffect.glow => 720,
                          LyricEffect.karaoke || LyricEffect.fade => 450,
                          LyricEffect.plain => 0,
                        },
                      ),
                      // A comic line overshoots and wobbles into place.
                      switchInCurve: effect == LyricEffect.comic ? Curves.elasticOut : Curves.easeOutCubic,
                      switchOutCurve: Curves.easeInCubic,
                      layoutBuilder: (current, previous) =>
                          Stack(alignment: Alignment.topCenter, children: [...previous, ?current]),
                      transitionBuilder: (child, animation) => _LineTransition(
                        animation: animation,
                        effect: effect,
                        colours: colours,
                        incoming: child.key == ValueKey(_line),
                        child: child,
                      ),
                      child: KeyedSubtree(
                        key: ValueKey(_line),
                        child: line == null || line.text.isEmpty
                            ? const SizedBox(width: double.infinity)
                            : _Line(
                                line: line,
                                size: big,
                                colours: colours,
                                effect: effect,
                                flow: moving ? _flow : null,
                                sung: effect == LyricEffect.karaoke ? _sung : null,
                                // A line going stays filled as the next fills.
                                singing: () => _line == shown,
                              ),
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

/// How a line comes in and goes, as [effect] has it. 3D: out of the cover
/// towards you, tipping up from below into focus with a glow of the song's
/// colours, and away up and over in a burst of them as the next comes.
/// Comic pop: springing in, a little askew, and popping away bigger in a
/// burst. Glow: out of a blur, glowing, then rising away into one. Karaoke
/// and Fade: fading in and out.
class _LineTransition extends AnimatedWidget {
  const _LineTransition({
    required Animation<double> animation,
    required this.effect,
    required this.colours,
    required this.incoming,
    required this.child,
  }) : super(listenable: animation);

  final LyricEffect effect;
  final List<Color> colours;
  final bool incoming;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final t = (listenable as Animation<double>).value;
    if (effect == LyricEffect.plain) return child;
    final away = (1 - t).clamp(0.0, 1.0);
    final blur = switch (effect) {
      LyricEffect.pop => away * 7,
      LyricEffect.glow => away * 10,
      LyricEffect.comic => incoming ? 0.0 : away * 3,
      _ => away * 4,
    };
    Widget out = child;
    // The song's colour glowing behind the letters: on the way in for 3D,
    // all along (brighter as it comes and goes) for Glow.
    final glow = switch (effect) {
      LyricEffect.pop => incoming ? sin(t.clamp(0.0, 1.0) * pi) * 0.9 : 0.0,
      LyricEffect.glow => 0.85 + 0.15 * away,
      _ => 0.0,
    };
    if (glow > 0.02) out = _Glow(colour: colours.first, amount: glow, child: out);
    out = Opacity(opacity: t.clamp(0.0, 1.0), child: out);
    if (blur > 0.05) {
      out = ImageFiltered(
        imageFilter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: out,
      );
    }
    // Lines going in 3D or comic-book style burst into the song's colours.
    if (!incoming && (effect == LyricEffect.pop || effect == LyricEffect.comic) && away > 0) {
      out = CustomPaint(foregroundPainter: _Burst(away, colours, comic: effect == LyricEffect.comic), child: out);
    }
    switch (effect) {
      case LyricEffect.fade || LyricEffect.karaoke:
        return Transform.translate(offset: Offset(0, (incoming ? 10 : -8) * away), child: out);
      case LyricEffect.glow:
        return Transform.translate(
          offset: Offset(0, incoming ? 6 * away : -22 * away),
          child: Transform.scale(scale: incoming ? 0.96 + 0.04 * t : 1 + 0.04 * away, child: out),
        );
      case LyricEffect.comic:
        final scale = incoming ? 0.35 + 0.65 * t : 1 + 0.3 * away;
        return Transform.rotate(
          angle: -0.05 + (incoming ? -0.12 * (1 - t) : 0.06 * away),
          child: Transform.scale(scale: scale, child: out),
        );
      default:
        final matrix = Matrix4.identity()
          ..setEntry(3, 2, 0.0016)
          ..translateByDouble(0, incoming ? 34 * away : -26 * away, incoming ? 60 * away : 0, 1)
          ..rotateX(incoming ? -0.95 * away : 0.75 * away)
          ..scaleByDouble(0.78 + 0.22 * t, 0.78 + 0.22 * t, 1, 1);
        return Transform(alignment: Alignment.center, transform: matrix, child: out);
    }
  }
}

/// [child] with a soft glow of [colour] behind it, as much as [amount].
class _Glow extends StatelessWidget {
  const _Glow({required this.colour, required this.amount, required this.child});
  final Color colour;
  final double amount;
  final Widget child;

  @override
  Widget build(BuildContext context) => Stack(
    alignment: Alignment.center,
    children: [
      IgnorePointer(
        child: Opacity(
          opacity: amount.clamp(0.0, 1.0),
          // The letters thickened, then softened: a halo, not a shadow.
          child: ImageFiltered(
            imageFilter: ImageFilter.compose(
              outer: ImageFilter.blur(sigmaX: 9, sigmaY: 9, tileMode: TileMode.decal),
              inner: ImageFilter.dilate(radiusX: 3, radiusY: 3),
            ),
            child: ColorFiltered(colorFilter: ColorFilter.mode(colour, BlendMode.srcIn), child: child),
          ),
        ),
      ),
      child,
    ],
  );
}

/// Bits of the song's colours flying out from a line as it goes, [away] 0 to
/// 1 as it does: dots, or for comic-book style stars and dashes.
class _Burst extends CustomPainter {
  _Burst(this.away, this.colours, {required this.comic});
  final double away;
  final List<Color> colours;
  final bool comic;

  @override
  void paint(Canvas canvas, Size size) {
    final centre = size.center(Offset.zero);
    final reach = max(size.width, size.height) * 0.55;
    // Out fast, then slowing, fading as it goes.
    final out = 1 - pow(1 - away, 3).toDouble();
    final fade = (1 - away) * min(1.0, away * 6);
    const count = 16;
    for (var i = 0; i < count; i++) {
      // The same scatter each time, not a random one.
      final angle = i * 2 * pi / count + sin(i * 12.9898) * 0.35;
      final far = reach * (0.55 + 0.45 * ((sin(i * 78.233) + 1) / 2)) * out;
      final at = centre + Offset(cos(angle) * far, sin(angle) * far * 0.6);
      final paint = Paint()..color = colours[i % colours.length].withValues(alpha: fade);
      final r = (comic ? 5.0 : 3.2) * (1 - 0.5 * away);
      if (comic && i.isEven) {
        canvas.drawPath(_star(at, r * 1.8, r * 0.7, 5, angle), paint);
      } else if (comic) {
        canvas.drawLine(at - Offset(cos(angle), sin(angle) * 0.6) * r * 2.4, at,
            paint..strokeWidth = 3..strokeCap = StrokeCap.round);
      } else {
        canvas.drawCircle(at, r, paint);
      }
    }
  }

  @override
  bool shouldRepaint(_Burst old) => old.away != away || old.colours != colours || old.comic != comic;
}

/// A star of [points] points around [centre], [outer] and [inner] its radii.
Path _star(Offset centre, double outer, double inner, int points, double turn) {
  final path = Path();
  for (var i = 0; i < points * 2; i++) {
    final r = i.isEven ? outer : inner;
    final a = turn + i * pi / points - pi / 2;
    final p = centre + Offset(cos(a) * r, sin(a) * r);
    i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
  }
  return path..close();
}

class _Line extends StatelessWidget {
  const _Line({
    required this.line,
    required this.size,
    required this.colours,
    required this.effect,
    this.flow,
    this.sung,
    this.singing,
  });
  final LyricLine line;
  final double size;
  final List<Color> colours;
  final LyricEffect effect;
  final Animation<double>? flow;
  final Animation<double>? sung;
  final bool Function()? singing;

  Widget _words({Color colour = Colors.white, List<Shadow>? shadows, Paint? outline}) => Column(
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
          color: outline == null ? colour : null,
          foreground: outline,
          shadows: shadows,
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
            color: outline == null ? colour.withValues(alpha: colour.a * 0.86) : null,
            foreground: outline,
            shadows: shadows,
          ),
        ),
      ],
    ],
  );

  @override
  Widget build(BuildContext context) {
    final glow = [Shadow(color: Colors.black.withValues(alpha: 0.55), blurRadius: 14)];
    if (effect == LyricEffect.comic) return _comic();
    final words = _words(shadows: glow);
    final flow = this.flow, sung = this.sung;
    if (sung != null) {
      // Karaoke: the sung part in the song's colours over the rest, dim.
      final dim = _words(colour: Colors.white.withValues(alpha: 0.45), shadows: glow);
      final lit = _words();
      return Stack(
        alignment: Alignment.topCenter,
        children: [
          dim,
          AnimatedBuilder(
            animation: Listenable.merge([sung, ?flow]),
            builder: (context, child) => ClipRect(
              clipper: _Sung(singing?.call() ?? true ? sung.value : 1),
              child: _filled(child!, flow?.value ?? 0, still: flow == null),
            ),
            child: lit,
          ),
        ],
      );
    }
    if (flow == null) return _filled(words, 0, still: true);
    return AnimatedBuilder(animation: flow, builder: (context, child) => _filled(child!, flow.value), child: words);
  }

  // Comic pop: white letters with a thick dark outline on a starburst of the
  // song's colours sliding through it.
  Widget _comic() {
    final outline = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = max(4.0, size / 5)
      ..strokeJoin = StrokeJoin.round
      ..color = const Color(0xFF14101A);
    final letters = Stack(
      alignment: Alignment.topCenter,
      children: [
        _words(outline: outline, shadows: const [Shadow(color: Color(0xFF14101A), offset: Offset(2, 3))]),
        _words(),
      ],
    );
    final flow = this.flow;
    Widget burst(double at) => CustomPaint(painter: _Starburst(colours, at), child: letters);
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: size * 0.6, vertical: size * 0.5),
      child: flow == null ? burst(0) : AnimatedBuilder(animation: flow, builder: (context, _) => burst(flow.value)),
    );
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

/// As much of a line, from the left, as has been sung.
class _Sung extends CustomClipper<Rect> {
  const _Sung(this.part);
  final double part;

  @override
  Rect getClip(Size size) => Rect.fromLTRB(-20, -20, -20 + (size.width + 40) * part, size.height + 20);

  @override
  bool shouldReclip(_Sung old) => old.part != part;
}

/// A comic-book starburst behind a line, filled with the song's colours
/// sliding through it ([at] 0 to 1 round), outlined dark.
class _Starburst extends CustomPainter {
  _Starburst(this.colours, this.at);
  final List<Color> colours;
  final double at;

  @override
  void paint(Canvas canvas, Size size) {
    final box = Offset.zero & size;
    final centre = box.center;
    final rx = size.width / 2 + 18, ry = size.height / 2 + 16;
    final path = Path();
    const points = 18;
    for (var i = 0; i < points * 2; i++) {
      // Spikes of a few lengths, the same each time.
      final spike = i.isEven ? 1.0 + 0.12 * sin(i * 2.7) : 0.8;
      final a = i * pi / points;
      final p = centre + Offset(cos(a) * rx * spike, sin(a) * ry * spike);
      i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
    }
    path.close();
    final fill = Paint()
      ..shader = LinearGradient(
        colors: [...colours, colours.first],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        tileMode: TileMode.mirror,
        transform: _Slide(sin(at * 2 * pi), size.width),
      ).createShader(box.inflate(24));
    canvas.drawPath(path.shift(const Offset(3, 4)), Paint()..color = const Color(0x8014101A));
    canvas.drawPath(path, fill);
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeJoin = StrokeJoin.round
        ..color = const Color(0xFF14101A),
    );
  }

  @override
  bool shouldRepaint(_Starburst old) => old.at != at || old.colours != colours;
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

/// A radial gradient at (0, -0.2) of radius 0.4 (of the height) stretched
/// sideways into the ellipse that just fits its box, so it is clear at every
/// edge.
class _Widen extends GradientTransform {
  const _Widen();

  @override
  Matrix4 transform(Rect bounds, {TextDirection? textDirection}) {
    final centre = Offset(bounds.center.dx, bounds.top + bounds.height * 0.4);
    final stretch = bounds.height > 0 ? bounds.width / (bounds.height * 0.8) : 1.0;
    return Matrix4.translationValues(centre.dx, centre.dy, 0)
      ..scaleByDouble(stretch, 1, 1, 1)
      ..translateByDouble(-centre.dx, -centre.dy, 0, 1);
  }
}
