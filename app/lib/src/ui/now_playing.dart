// The song playing: the mini player under every page, the full screen (the
// song's cover on a blurred copy of itself with its video behind, or the
// look chosen in Settings; the next songs on an arc; the controls in a glass
// dome) and the queue.

import 'dart:io';
import 'dart:math';
import 'dart:ui' show ImageFilter;

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:rxdart/rxdart.dart';

import '../app_state.dart';
import '../history.dart' show counted;
import '../links.dart';
import '../player/paattu_audio_handler.dart';
import '../settings.dart';
import '../track.dart';
import '../util.dart';
import 'beat.dart';
import 'cover_theme.dart';
import 'depth_cover.dart';
import 'glass.dart';
import 'lyrics_view.dart';
import 'sleep_timer.dart';
import 'sound_page.dart';
import 'video_background.dart';
import 'widgets.dart';

void openNowPlaying(BuildContext context) => Navigator.of(context).push(PageRouteBuilder<void>(
      pageBuilder: (_, _, _) => const NowPlayingPage(),
      transitionsBuilder: (_, animation, _, child) => SlideTransition(
        position: Tween(begin: const Offset(0, 1), end: Offset.zero)
            .animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
        child: child,
      ),
    ));

/// Rebuilds with the song, whether it's playing and whether it's loading.
class PlayerBuilder extends StatelessWidget {
  const PlayerBuilder({super.key, required this.builder});
  final Widget Function(BuildContext context, Json? track, bool playing, bool loading) builder;

  @override
  Widget build(BuildContext context) {
    final player = Paattu.of(context).player;
    return StreamBuilder<(Json?, bool, bool)>(
      stream: Rx.combineLatest3(player.current, player.playingStream, player.loading, (a, b, c) => (a, b, c)),
      initialData: (player.current.value, player.playing, player.loading.value),
      builder: (context, snapshot) {
        final (track, playing, loading) = snapshot.data!;
        return builder(context, track, playing, loading);
      },
    );
  }
}

/// The song playing, as a glass pill above the navigation.
class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context) {
    final player = Paattu.of(context).player;
    return PlayerBuilder(builder: (context, track, playing, loading) {
      if (track == null) return const SizedBox.shrink();
      return CoverTheme(track: track, child: Builder(builder: (context) => _pill(context, player, track, playing, loading)));
    });
  }

  Widget _pill(BuildContext context, PaattuAudioHandler player, Json track, bool playing, bool loading) {
    final theme = Theme.of(context);
    return SafeArea(
      top: false,
      bottom: false,
      minimum: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Glass(
        blur: true,
        radius: 28,
        color: Color.alphaBlend(theme.colorScheme.primary.withValues(alpha: 0.12), theme.colorScheme.surface.withValues(alpha: 0.7)),
        onTap: () => openNowPlaying(context),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 6, 4, 2),
              child: Row(
                children: [
                  TrackCover(track, size: 46, radius: 23),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(trackTitle(track), maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600)),
                        Text(trackSubtitle(track), maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                      ],
                    ),
                  ),
                  FavouriteButton(track),
                  _PlayButton(playing: playing, loading: loading, onPressed: player.togglePlay),
                  IconButton(tooltip: 'Next', icon: const Icon(Icons.skip_next), onPressed: player.skipToNext),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 0, 22, 6),
              child: ClipRRect(borderRadius: BorderRadius.circular(2), child: _ThinProgress(player: player)),
            ),
          ],
        ),
      ),
    );
  }
}

class _ThinProgress extends StatelessWidget {
  const _ThinProgress({required this.player});
  final PaattuAudioHandler player;

  @override
  Widget build(BuildContext context) => StreamBuilder<(Duration, Duration?)>(
        stream: Rx.combineLatest2(player.positionStream, player.durationStream, (a, b) => (a, b)),
        builder: (context, snapshot) {
          final (position, duration) = snapshot.data ?? (Duration.zero, null);
          final value = duration == null || duration.inMilliseconds == 0
              ? 0.0
              : (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0);
          return LinearProgressIndicator(
            value: value,
            minHeight: 2,
            backgroundColor: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.12),
          );
        },
      );
}

/// The mini player's play button: a small accent circle.
class _PlayButton extends StatelessWidget {
  const _PlayButton({required this.playing, required this.loading, required this.onPressed});
  final bool playing;
  final bool loading;
  final Future<void> Function() onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox.square(
      dimension: 44,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (loading) const SizedBox.square(dimension: 42, child: CircularProgressIndicator(strokeWidth: 2)),
          IconButton.filled(
            tooltip: playing ? 'Pause' : 'Play',
            style: IconButton.styleFrom(backgroundColor: scheme.primary, foregroundColor: Colors.white, fixedSize: const Size.square(36)),
            iconSize: 22,
            icon: Icon(playing ? Icons.pause : Icons.play_arrow),
            onPressed: onPressed,
          ),
        ],
      ),
    );
  }
}

class NowPlayingPage extends StatelessWidget {
  const NowPlayingPage({super.key});

  // Heights the layout plans with (the dome grows by the volume bar off Android).
  static const _barHeight = 60.0;
  static const _arcHeight = 128.0;
  static const _infoHeight = 44.0;
  static double get _domeHeight => Platform.isAndroid ? 340 : 384;

  @override
  Widget build(BuildContext context) {
    final app = Paattu.of(context);
    return PlayerBuilder(builder: (context, track, playing, loading) {
      if (track == null) {
        return Backdrop(
          child: Scaffold(appBar: AppBar(), body: const EmptyState(icon: Icons.music_note, title: 'Nothing playing')),
        );
      }
      return CoverTheme(
        track: track,
        child: BeatDriver(
          player: app.player,
          track: track,
          playing: playing,
          loading: loading,
          child: ListenableBuilder(
            listenable: app.settings,
            builder: (context, _) => _page(context, app, track, playing, loading),
          ),
        ),
      );
    });
  }

  Widget _page(BuildContext context, AppState app, Json track, bool playing, bool loading) {
    final theme = Theme.of(context);
    final settings = app.settings;
    final style = settings.nowPlayingStyle;
    final wide = MediaQuery.sizeOf(context).width > 760;
    final bar = SizedBox(
      height: _barHeight,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            GlassIconButton(
              icon: Icons.keyboard_arrow_down,
              tooltip: 'Close',
              blur: true,
              onPressed: () => Navigator.pop(context),
            ),
            Expanded(
              child: Text('Now Playing',
                  textAlign: TextAlign.center, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
            ),
            GlassIconButton(
              icon: Icons.more_vert,
              tooltip: 'More',
              blur: true,
              onPressed: () => showTrackMenu(context, track),
            ),
          ],
        ),
      ),
    );
    final dome = _Dome(app: app, track: track, playing: playing, loading: loading);
    Widget square(Widget child) =>
        Center(child: Padding(padding: const EdgeInsets.all(24), child: AspectRatio(aspectRatio: 1, child: child)));
    final cover = square(settings.coverDepth
        ? DepthCover(track: track)
        : Material(
            elevation: 12,
            borderRadius: BorderRadius.circular(24),
            clipBehavior: Clip.antiAlias,
            child: TrackCover(track, size: null, large: true, radius: 24),
          ));
    final shownCard = switch (style) {
      // The cover stays, with the video playing behind it.
      NowPlayingStyle.cover => cover,
      // The cover makes way for the video while it plays.
      NowPlayingStyle.video => ValueListenableBuilder<bool>(
          valueListenable: songVideoShown,
          builder: (context, shown, cover) =>
              AnimatedOpacity(opacity: shown ? 0 : 1, duration: const Duration(milliseconds: 900), child: cover),
          child: cover,
        ),
      // The picture behind is the cover.
      NowPlayingStyle.full => const SizedBox.expand(),
      NowPlayingStyle.record => square(_Record(track: track, playing: playing)),
    };
    final card = settings.lyricsShown
        ? _WithWords(square: style != NowPlayingStyle.full, words: CoverLyrics(app: app, track: track), child: shownCard)
        : shownCard;
    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: Stack(
        children: [
          Positioned.fill(
            child: _Background(
              app: app,
              track: track,
              wide: wide,
              sharp: style == NowPlayingStyle.full,
              video: settings.videoBackground,
              blur: settings.videoBlur * (wide ? 1.2 : 0.4),
            ),
          ),
          SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: wide ? 560 : double.infinity),
                child: LayoutBuilder(builder: (context, box) {
                  final room = box.maxHeight - _barHeight - _domeHeight;
                  final info = settings.songInfo && room - _infoHeight > 120;
                  final arc = room - _arcHeight - (info ? _infoHeight : 0) > 120;
                  if (room < 40) {
                    // A short window (a phone on its side): scroll instead.
                    return SingleChildScrollView(
                      child: Column(children: [bar, SizedBox(height: 260, child: card), dome]),
                    );
                  }
                  return Column(
                    children: [
                      bar,
                      Expanded(child: card),
                      if (info) _SongInfo(app: app, track: track),
                      if (arc) _UpcomingArc(player: app.player),
                      dome,
                    ],
                  );
                }),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The song's picture filling the top of the screen (on wide screens, all
/// of it), blurred unless [sharp], fading into the page. Its video, blurred
/// by [blur], fades in over the picture once it plays.
class _Background extends StatelessWidget {
  const _Background({
    required this.app,
    required this.track,
    required this.wide,
    required this.sharp,
    required this.video,
    required this.blur,
  });
  final AppState app;
  final Json track;
  final bool wide;
  final bool sharp;
  final bool video;
  final double blur;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final art = TrackCover(track, size: null, large: true, radius: 0);
    final moving = video ? SongVideo(app: app, track: track, blur: blur) : const SizedBox.expand();
    return LayoutBuilder(builder: (context, box) {
      // How much of the height the square picture covers.
      final cover = wide ? 1.0 : (box.maxWidth / max(1, box.maxHeight)).clamp(0.3, 1.0);
      return Stack(
        fit: StackFit.expand,
        children: [
          if (wide) ...[
            if (sharp)
              Opacity(opacity: 0.7, child: art)
            else
              ImageFiltered(
                imageFilter: ImageFilter.blur(sigmaX: 40, sigmaY: 40, tileMode: TileMode.decal),
                child: Opacity(opacity: 0.6, child: art),
              ),
            Opacity(opacity: sharp ? 0.7 : 0.6, child: moving),
          ] else
            Align(
              alignment: Alignment.topCenter,
              child: AspectRatio(
                aspectRatio: 1,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (sharp)
                      art
                    else
                      ClipRect(
                        child: ImageFiltered(
                          imageFilter: ImageFilter.blur(sigmaX: 28, sigmaY: 28, tileMode: TileMode.clamp),
                          child: art,
                        ),
                      ),
                    moving,
                  ],
                ),
              ),
            ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.35),
                  scheme.primary.withValues(alpha: sharp ? 0 : 0.12),
                  scheme.surface.withValues(alpha: wide ? 0.55 : 0),
                  scheme.surface,
                ],
                stops: [0, cover * 0.45, cover * 0.75, max(cover, 0.8)],
              ),
            ),
          ),
        ],
      );
    });
  }
}

/// The cover on a record, turning while the song plays.
class _Record extends StatefulWidget {
  const _Record({required this.track, required this.playing});
  final Json track;
  final bool playing;

  @override
  State<_Record> createState() => _RecordState();
}

class _RecordState extends State<_Record> with SingleTickerProviderStateMixin {
  late final _turn = AnimationController(vsync: this, duration: const Duration(seconds: 6));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _spin();
  }

  @override
  void didUpdateWidget(_Record old) {
    super.didUpdateWidget(old);
    _spin();
  }

  void _spin() {
    final on = widget.playing && !MediaQuery.disableAnimationsOf(context);
    if (on && !_turn.isAnimating) {
      _turn.repeat();
    } else if (!on && _turn.isAnimating) {
      _turn.stop();
    }
  }

  @override
  void dispose() {
    _turn.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return LayoutBuilder(builder: (context, box) {
      final side = box.biggest.shortestSide;
      return Stack(
        fit: StackFit.expand,
        children: [
          RotationTransition(
            turns: _turn,
            child: DecoratedBox(
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Color(0xFF111114),
                boxShadow: [BoxShadow(color: Color(0x80000000), blurRadius: 30, offset: Offset(0, 14))],
              ),
              child: CustomPaint(
                painter: _GroovesPainter(),
                child: Center(
                  child: SizedBox.square(
                    dimension: side * 0.5,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        ClipOval(child: TrackCover(widget.track, size: null, large: true, radius: 0)),
                        Center(
                          child: Container(
                            width: side * 0.035,
                            height: side * 0.035,
                            decoration: BoxDecoration(color: scheme.surface, shape: BoxShape.circle),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          // The light on the record stays put while it turns.
          IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: SweepGradient(
                  colors: [
                    Colors.white.withValues(alpha: 0),
                    Colors.white.withValues(alpha: 0.09),
                    Colors.white.withValues(alpha: 0),
                    Colors.white.withValues(alpha: 0),
                    Colors.white.withValues(alpha: 0.09),
                    Colors.white.withValues(alpha: 0),
                  ],
                  stops: const [0.04, 0.12, 0.2, 0.54, 0.62, 0.7],
                ),
              ),
            ),
          ),
        ],
      );
    });
  }
}

/// The record's grooves, between its edge and the label.
class _GroovesPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final centre = size.center(Offset.zero);
    final outer = size.shortestSide / 2;
    final groove = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = max(0.6, outer * 0.004);
    for (var i = 0; outer * (0.96 - i * 0.022) > outer * 0.53; i++) {
      groove.color = Colors.white.withValues(alpha: i % 3 == 0 ? 0.07 : 0.035);
      canvas.drawCircle(centre, outer * (0.96 - i * 0.022), groove);
    }
  }

  @override
  bool shouldRepaint(_GroovesPainter old) => false;
}

/// The next songs, fanned out on an arc above the dome. Tap one to play it.
/// The words over the card: at the top of the cover's square, or of the
/// card when the picture fills it.
class _WithWords extends StatelessWidget {
  const _WithWords({required this.square, required this.words, required this.child});
  final bool square;
  final Widget words;
  final Widget child;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, box) {
        // The square the cover sits in: centred, 24 in from the edges.
        final side = max(0.0, min(box.maxWidth, box.maxHeight) - 48);
        return Stack(
          fit: StackFit.expand,
          children: [
            child,
            if (square)
              Positioned(
                left: (box.maxWidth - side) / 2,
                top: (box.maxHeight - side) / 2,
                width: side,
                height: side * 0.62,
                child: words,
              )
            else
              Positioned(left: 24, right: 24, top: 8, height: max(0.0, box.maxHeight * 0.6), child: words),
          ],
        );
      });
}

/// What the song is, in a line above Up next: the film and year, the
/// singers and music, its language and label, how it's streaming, and how
/// often you've played it.
class _SongInfo extends StatelessWidget {
  const _SongInfo({required this.app, required this.track});
  final AppState app;
  final Json track;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final film = asString(track['movie']), year = asString(track['year']);
    final id = trackId(track);
    final plays = app.history.plays.where((p) => p['id'] == id && counted(p)).length;
    final views = toInt(track['views']) ?? 0;
    final style = theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600);
    Widget part(IconData icon, String text) => Padding(
          padding: const EdgeInsets.only(right: 14),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 15, color: scheme.secondary),
            const SizedBox(width: 5),
            Text(text, style: style),
          ]),
        );
    return SizedBox(
      height: NowPlayingPage._infoHeight,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
        child: Glass(
          radius: 18,
          child: StreamBuilder<String>(
            stream: app.player.quality,
            initialData: app.player.quality.value,
            builder: (context, quality) {
              final parts = [
                if (film.isNotEmpty || year.isNotEmpty)
                  part(Icons.movie_outlined, [film, year].where((s) => s.isNotEmpty).join(' · ')),
                if (asStrings(track['credits']).isNotEmpty)
                  part(Icons.person_outline, asStrings(track['credits']).take(4).join(', ')),
                if (asString(track['language']).isNotEmpty) part(Icons.translate, asString(track['language'])),
                if (asString(track['channel']).isNotEmpty) part(Icons.label_outline, asString(track['channel'])),
                if ((quality.data ?? '').isNotEmpty) part(Icons.graphic_eq, quality.data!),
                part(Icons.public, siteName(trackSite(track))),
                if (views > 0) part(Icons.trending_up, '${shortCount(views)} plays'),
                part(Icons.replay, plays == 0 ? 'First play' : 'Played ${plural(plays, 'time')}'),
              ];
              return ShaderMask(
                // The ends fade, so it reads as more to scroll to.
                blendMode: BlendMode.dstIn,
                shaderCallback: (b) => const LinearGradient(
                  colors: [Colors.transparent, Colors.black, Colors.black, Colors.transparent],
                  stops: [0, 0.04, 0.94, 1],
                ).createShader(b),
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  children: [Center(child: Row(children: parts))],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _UpcomingArc extends StatelessWidget {
  const _UpcomingArc({required this.player});
  final PaattuAudioHandler player;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return SizedBox(
      height: NowPlayingPage._arcHeight,
      child: StreamBuilder<List<Json>>(
        stream: Rx.combineLatest2(player.queueTracks, player.current, (queue, _) => queue),
        initialData: player.queueTracks.value,
        builder: (context, snapshot) {
          final queue = snapshot.data ?? const <Json>[];
          final first = player.index + 1;
          final next = [for (var i = first; i < min(queue.length, first + 4); i++) (i, queue[i])];
          if (next.isEmpty) return const SizedBox();
          return LayoutBuilder(builder: (context, box) {
            final w = box.maxWidth;
            final r = max(300.0, w * 0.75);
            const step = 18 * pi / 180, labelWidth = 104.0, labelHeight = 58.0;
            final centre = Offset(w / 2, r + 34);
            return Stack(
              clipBehavior: Clip.hardEdge,
              children: [
                for (var k = 0; k < next.length; k++)
                  () {
                    final angle = -pi / 2 + (k - (next.length - 1) / 2) * step;
                    final at = centre + Offset(cos(angle), sin(angle)) * r;
                    final (index, song) = next[k];
                    return Positioned(
                      left: at.dx - labelWidth / 2,
                      top: at.dy - labelHeight / 2,
                      width: labelWidth,
                      height: labelHeight,
                      child: Transform.rotate(
                        angle: angle + pi / 2,
                        child: Semantics(
                          button: true,
                          label: 'Play next: ${trackTitle(song)}',
                          excludeSemantics: true,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: () => player.skipToQueueItem(index),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text((k + 1).toString().padLeft(2, '0'),
                                    style: theme.textTheme.labelSmall?.copyWith(color: scheme.secondary, fontWeight: FontWeight.w700)),
                                Text(trackTitle(song).toUpperCase(),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    textAlign: TextAlign.center,
                                    style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w700, letterSpacing: 0.6)),
                                Text(trackSubtitle(song),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    textAlign: TextAlign.center,
                                    style: theme.textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant, fontSize: 10)),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  }(),
              ],
            );
          });
        },
      ),
    );
  }
}

/// The controls in a glass dome: title, the transport around a big glowing
/// play button, the seek bar and the song's buttons.
class _Dome extends StatelessWidget {
  const _Dome({required this.app, required this.track, required this.playing, required this.loading});
  final AppState app;
  final Json track;
  final bool playing;
  final bool loading;

  static const _rise = 44.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final player = app.player;
    final muted = theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant);
    return ClipPath(
      clipper: const _DomeShape(_rise),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: CustomPaint(
          painter: _DomePainter(edge: scheme.glassEdge, glow: scheme.primary, fill: scheme.surface),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 30, 16, 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(trackTitle(track),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600)),
                Text(trackSubtitle(track), maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: muted),
                StreamBuilder<String>(
                  stream: player.quality,
                  initialData: player.quality.value,
                  builder: (context, snapshot) => Text(
                    [siteName(trackSite(track)), snapshot.data ?? ''].where((s) => s.isNotEmpty).join(' · '),
                    style: muted?.copyWith(fontSize: 11, color: scheme.secondary),
                  ),
                ),
                const SizedBox(height: 10),
                StreamBuilder<PlaybackState>(
                  stream: player.playbackState,
                  builder: (context, snapshot) {
                    final state = snapshot.data;
                    final shuffle = state?.shuffleMode == AudioServiceShuffleMode.all;
                    final repeat = state?.repeatMode ?? AudioServiceRepeatMode.none;
                    return SizedBox(
                      height: 104,
                      child: Row(
                        children: [
                          IconButton(
                            tooltip: shuffle ? 'Shuffle on' : 'Shuffle off',
                            icon: Icon(Icons.shuffle, color: shuffle ? scheme.secondary : scheme.onSurfaceVariant),
                            onPressed: player.toggleShuffle,
                          ),
                          Expanded(
                            child: Stack(
                              alignment: Alignment.center,
                              // The play button's ripples go past the row.
                              clipBehavior: Clip.none,
                              children: [
                                Glass(
                                  radius: 999,
                                  child: SizedBox(
                                    height: 60,
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        IconButton(
                                            iconSize: 32,
                                            tooltip: 'Previous',
                                            icon: const Icon(Icons.skip_previous_rounded),
                                            onPressed: player.skipToPrevious),
                                        IconButton(
                                            iconSize: 32,
                                            tooltip: 'Next',
                                            icon: const Icon(Icons.skip_next_rounded),
                                            onPressed: player.skipToNext),
                                      ],
                                    ),
                                  ),
                                ),
                                _BigPlay(playing: playing, loading: loading, onPressed: player.togglePlay),
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: switch (repeat) {
                              AudioServiceRepeatMode.one => 'Repeat this song',
                              AudioServiceRepeatMode.none => 'Repeat off',
                              _ => 'Repeat the queue',
                            },
                            icon: Icon(repeat == AudioServiceRepeatMode.one ? Icons.repeat_one : Icons.repeat,
                                color: repeat == AudioServiceRepeatMode.none ? scheme.onSurfaceVariant : scheme.secondary),
                            onPressed: player.cycleRepeat,
                          ),
                        ],
                      ),
                    );
                  },
                ),
                _SeekBar(player: player),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    FavouriteButton(track),
                    IconButton(
                      tooltip: 'Add to a playlist',
                      icon: const Icon(Icons.playlist_add),
                      onPressed: () async {
                        final target = await pickPlaylist(context);
                        if (target != null) app.addToPlaylist(target, [track]);
                      },
                    ),
                    RadioButton(track: track),
                    IconButton(
                      tooltip: 'Queue',
                      icon: const Icon(Icons.queue_music),
                      onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const QueuePage())),
                    ),
                    const SleepTimerButton(),
                    ListenableBuilder(
                      listenable: app.settings,
                      builder: (context, _) => IconButton(
                        tooltip: 'Sound',
                        icon: Icon(Icons.equalizer, color: app.settings.sound.on ? scheme.primary : null),
                        onPressed: () => openSound(context),
                      ),
                    ),
                  ],
                ),
                if (!Platform.isAndroid) _VolumeBar(app: app),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Start the radio of [track] (songs like it, without end), or stop it.
class RadioButton extends StatelessWidget {
  const RadioButton({super.key, required this.track});
  final Json track;

  @override
  Widget build(BuildContext context) {
    final app = Paattu.of(context);
    final player = app.player;
    return StreamBuilder<Json?>(
      stream: player.radio,
      initialData: player.radio.value,
      builder: (context, snapshot) {
        final on = snapshot.data != null;
        return IconButton(
          tooltip: on ? 'Radio of ${trackTitle(snapshot.data!)}: tap to stop' : 'Start radio',
          isSelected: on,
          icon: const Icon(Icons.radio_outlined),
          selectedIcon: Icon(Icons.radio, color: Theme.of(context).colorScheme.primary),
          onPressed: () {
            if (on) {
              player.stopRadio();
              app.toast('Radio off');
            } else {
              fire(player.startRadio(track));
            }
          },
        );
      },
    );
  }
}

/// A dome: the middle of the top edge [rise] higher than its ends.
class _DomeShape extends CustomClipper<Path> {
  const _DomeShape(this.rise);
  final double rise;

  static Path outline(Size size, double rise) => Path()
    ..moveTo(0, rise)
    ..quadraticBezierTo(size.width / 2, -rise, size.width, rise);

  @override
  Path getClip(Size size) => outline(size, rise)
    ..lineTo(size.width, size.height)
    ..lineTo(0, size.height)
    ..close();

  @override
  bool shouldReclip(_DomeShape old) => old.rise != rise;
}

/// The dome's glass: darker as it goes down, a glow where the play button
/// sits, and a light edge along the top.
class _DomePainter extends CustomPainter {
  const _DomePainter({required this.edge, required this.glow, required this.fill});
  final Color edge;
  final Color glow;
  final Color fill;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color.alphaBlend(glow.withValues(alpha: 0.22), fill.withValues(alpha: 0.55)), fill.withValues(alpha: 0.96)],
        ).createShader(rect),
    );
    // Where the play button is: about a third of the way down.
    canvas.drawRect(
      rect,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(0, -0.25),
          radius: 0.55,
          colors: [glow.withValues(alpha: 0.35), glow.withValues(alpha: 0)],
        ).createShader(rect),
    );
    canvas.drawPath(
      _DomeShape.outline(size, _Dome._rise),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = edge,
    );
  }

  @override
  bool shouldRepaint(_DomePainter old) => old.edge != edge || old.glow != glow || old.fill != fill;
}

/// Play / pause in rings of light that move with the song (beat.dart): the
/// inner ring swells with how loud it is, the outer one and the glow kick on
/// its beats, and the hardest beats send a ripple out.
class _BigPlay extends StatelessWidget {
  const _BigPlay({required this.playing, required this.loading, required this.onPressed});
  final bool playing;
  final bool loading;
  final Future<void> Function() onPressed;

  /// Outside Now Playing: rings that never move.
  static final _still = Beat();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label: playing ? 'Pause' : 'Play',
      excludeSemantics: true,
      onTap: onPressed,
      child: GestureDetector(
        onTap: onPressed,
        child: SizedBox.square(
          dimension: 104,
          child: Stack(
            alignment: Alignment.center,
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(child: CustomPaint(painter: _RingsPainter(BeatDriver.of(context) ?? _still, scheme.primary))),
              Container(
                width: 76,
                height: 76,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: tileColours(scheme, 0),
                  ),
                ),
              ),
              if (loading)
                const SizedBox.square(dimension: 68, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
              Container(
                width: 52,
                height: 52,
                decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.white),
                child: Icon(playing ? Icons.pause_rounded : Icons.play_arrow_rounded, size: 32, color: Colors.black),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RingsPainter extends CustomPainter {
  _RingsPainter(this.beat, this.colour) : super(repaint: beat);
  final Beat beat;
  final Color colour;

  @override
  void paint(Canvas canvas, Size size) {
    final centre = size.center(Offset.zero);
    final level = beat.level, punch = beat.punch;
    void ring(double radius, double alpha, double width) => canvas.drawCircle(
        centre,
        radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = width
          ..color = colour.withValues(alpha: alpha.clamp(0.0, 1.0)));
    for (final (start, strength) in beat.ripples) {
      final t = (beat.now - start).inMicroseconds / Beat.rippleTime.inMicroseconds;
      final eased = 1 - (1 - t) * (1 - t);
      ring(45 + 27 * eased, strength * 0.55 * (1 - t), 2.5 * (1 - t) + 0.5);
    }
    // The glow behind the button.
    canvas.drawCircle(
        centre,
        38 + 3 * punch,
        Paint()
          ..color = colour.withValues(alpha: 0.6 + 0.3 * punch)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, 10 + 8 * punch + 3 * level));
    ring(52 * (1 + 0.1 * punch), 0.25 + 0.5 * punch, 1.5 + punch);
    ring(45 * (1 + 0.05 * level), 0.5 + 0.3 * level, 1.5);
  }

  @override
  bool shouldRepaint(_RingsPainter old) => old.beat != beat || old.colour != colour;
}

class _SeekBar extends StatefulWidget {
  const _SeekBar({required this.player});
  final PaattuAudioHandler player;

  @override
  State<_SeekBar> createState() => _SeekBarState();
}

class _SeekBarState extends State<_SeekBar> {
  double? _dragging;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return StreamBuilder<(Duration, Duration?, Duration)>(
      stream: Rx.combineLatest3(
          widget.player.positionStream, widget.player.durationStream, widget.player.bufferedStream, (a, b, c) => (a, b, c)),
      builder: (context, snapshot) {
        final (position, duration, buffered) = snapshot.data ?? (Duration.zero, null, Duration.zero);
        final total = duration?.inMilliseconds.toDouble() ?? 0;
        final value = (_dragging ?? position.inMilliseconds.toDouble()).clamp(0.0, total > 0 ? total : 1.0);
        final style = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
        return Column(
          children: [
            Slider(
              value: value,
              max: total > 0 ? total : 1.0,
              secondaryTrackValue: total > 0 ? buffered.inMilliseconds.clamp(0, total).toDouble() : null,
              onChanged: total > 0 ? (v) => setState(() => _dragging = v) : null,
              onChangeEnd: (v) {
                widget.player.seek(Duration(milliseconds: v.round()));
                setState(() => _dragging = null);
              },
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(formatTime(value / 1000), style: style),
                  Text(duration == null ? '--:--' : formatDuration(duration), style: style),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _VolumeBar extends StatelessWidget {
  const _VolumeBar({required this.app});
  final AppState app;

  @override
  Widget build(BuildContext context) => StreamBuilder<double>(
        stream: app.player.volumeStream,
        initialData: app.player.volume,
        builder: (context, snapshot) {
          final volume = snapshot.data ?? 1.0;
          return Row(
            children: [
              Icon(volume == 0 ? Icons.volume_off : Icons.volume_down, size: 20),
              Expanded(
                child: Slider(
                  value: volume,
                  onChanged: (v) => app.player.setVolume(v),
                  onChangeEnd: (v) => app.settings.volume = v,
                ),
              ),
              const Icon(Icons.volume_up, size: 20),
            ],
          );
        },
      );
}

class QueuePage extends StatelessWidget {
  const QueuePage({super.key});

  @override
  Widget build(BuildContext context) {
    final app = Paattu.of(context);
    final player = app.player;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Queue'),
        actions: [
          TextButton(
            onPressed: () {
              player.clearUpcoming();
              app.toast('Cleared the songs after this one');
            },
            child: const Text('Clear upcoming'),
          ),
        ],
      ),
      body: StreamBuilder<List<Json>>(
        stream: player.queueTracks,
        initialData: player.queueTracks.value,
        builder: (context, snapshot) {
          final tracks = snapshot.data ?? const <Json>[];
          if (tracks.isEmpty) return const EmptyState(icon: Icons.queue_music, title: 'The queue is empty');
          return StreamBuilder<Json?>(
            stream: player.current,
            builder: (context, _) {
              final at = player.index;
              return ReorderableListView.builder(
                buildDefaultDragHandles: false,
                itemCount: tracks.length,
                onReorderItem: player.moveInQueue,
                itemBuilder: (context, i) {
                  final t = tracks[i];
                  return Dismissible(
                    key: ValueKey('q$i:${trackId(t)}:${tracks.length}'),
                    direction: DismissDirection.endToStart,
                    background: Container(
                      color: Theme.of(context).colorScheme.errorContainer,
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.only(right: 24),
                      child: const Icon(Icons.delete_outline),
                    ),
                    onDismissed: (_) => player.removeQueueItemAt(i),
                    child: TrackTile(
                      track: t,
                      playingId: i == at ? trackId(t) : null,
                      trailing: ReorderableDragStartListener(
                        index: i,
                        child: const Padding(padding: EdgeInsets.all(8), child: Icon(Icons.drag_handle)),
                      ),
                      onTap: () => player.skipToQueueItem(i),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}
