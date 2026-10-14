// The song playing: the mini player under every page, the full screen with
// seek bar and controls, and the queue.

import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:rxdart/rxdart.dart';

import '../app_state.dart';
import '../links.dart';
import '../player/paattu_audio_handler.dart';
import '../track.dart';
import '../util.dart';
import 'sound_page.dart';
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

class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context) {
    final player = Paattu.of(context).player;
    final theme = Theme.of(context);
    return PlayerBuilder(builder: (context, track, playing, loading) {
      if (track == null) return const SizedBox.shrink();
      return Material(
        color: theme.colorScheme.surfaceContainerHigh,
        child: InkWell(
          onTap: () => openNowPlaying(context),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _ThinProgress(player: player),
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 6, 4, 6),
                child: Row(
                  children: [
                    Hero(tag: 'cover', child: TrackCover(track, size: 44)),
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
            ],
          ),
        ),
      );
    });
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
          return LinearProgressIndicator(value: value, minHeight: 2);
        },
      );
}

class _PlayButton extends StatelessWidget {
  const _PlayButton({required this.playing, required this.loading, required this.onPressed, this.big = false});
  final bool playing;
  final bool loading;
  final bool big;
  final Future<void> Function() onPressed;

  @override
  Widget build(BuildContext context) {
    final size = big ? 72.0 : 44.0;
    final icon = Icon(playing ? Icons.pause : Icons.play_arrow, size: big ? 40 : 28);
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (loading) SizedBox(width: size - 4, height: size - 4, child: const CircularProgressIndicator(strokeWidth: 2)),
          big
              ? IconButton.filled(tooltip: playing ? 'Pause' : 'Play', icon: icon, iconSize: 40, onPressed: onPressed)
              : IconButton(tooltip: playing ? 'Pause' : 'Play', icon: icon, onPressed: onPressed),
        ],
      ),
    );
  }
}

class NowPlayingPage extends StatelessWidget {
  const NowPlayingPage({super.key});

  @override
  Widget build(BuildContext context) {
    final app = Paattu.of(context);
    final player = app.player;
    final theme = Theme.of(context);
    return PlayerBuilder(builder: (context, track, playing, loading) {
      if (track == null) {
        return Scaffold(appBar: AppBar(), body: const EmptyState(icon: Icons.music_note, title: 'Nothing playing'));
      }
      final wide = MediaQuery.sizeOf(context).width > 760;
      final cover = Hero(
        tag: 'cover',
        child: AspectRatio(
          aspectRatio: 1,
          child: Material(
            elevation: 8,
            borderRadius: BorderRadius.circular(16),
            clipBehavior: Clip.antiAlias,
            child: TrackCover(track, size: null, large: true, radius: 16),
          ),
        ),
      );
      final details = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(trackTitle(track), maxLines: 2, overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Text(trackSubtitle(track), maxLines: 2, overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                  ],
                ),
              ),
              FavouriteButton(track, size: 28),
            ],
          ),
          const SizedBox(height: 8),
          StreamBuilder<String>(
            stream: player.quality,
            initialData: player.quality.value,
            builder: (context, snapshot) {
              final label = [siteName(trackSite(track)), snapshot.data ?? ''].where((s) => s.isNotEmpty).join(' · ');
              return Align(
                alignment: Alignment.centerLeft,
                child: Chip(
                  visualDensity: VisualDensity.compact,
                  avatar: Icon(Icons.graphic_eq, size: 16, color: theme.colorScheme.primary),
                  label: Text(label),
                ),
              );
            },
          ),
          const SizedBox(height: 8),
          _SeekBar(player: player),
          const SizedBox(height: 4),
          StreamBuilder<PlaybackState>(
            stream: player.playbackState,
            builder: (context, snapshot) {
              final state = snapshot.data;
              final shuffle = state?.shuffleMode == AudioServiceShuffleMode.all;
              final repeat = state?.repeatMode ?? AudioServiceRepeatMode.none;
              return Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  IconButton(
                    tooltip: shuffle ? 'Shuffle on' : 'Shuffle off',
                    icon: Icon(Icons.shuffle, color: shuffle ? theme.colorScheme.primary : null),
                    onPressed: player.toggleShuffle,
                  ),
                  IconButton(iconSize: 36, tooltip: 'Previous', icon: const Icon(Icons.skip_previous), onPressed: player.skipToPrevious),
                  _PlayButton(playing: playing, loading: loading, big: true, onPressed: player.togglePlay),
                  IconButton(iconSize: 36, tooltip: 'Next', icon: const Icon(Icons.skip_next), onPressed: player.skipToNext),
                  IconButton(
                    tooltip: switch (repeat) {
                      AudioServiceRepeatMode.one => 'Repeat this song',
                      AudioServiceRepeatMode.none => 'Repeat off',
                      _ => 'Repeat the queue',
                    },
                    icon: Icon(repeat == AudioServiceRepeatMode.one ? Icons.repeat_one : Icons.repeat,
                        color: repeat == AudioServiceRepeatMode.none ? null : theme.colorScheme.primary),
                    onPressed: player.cycleRepeat,
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              TextButton.icon(
                onPressed: () async {
                  final target = await pickPlaylist(context);
                  if (target != null) app.addToPlaylist(target, [track]);
                },
                icon: const Icon(Icons.playlist_add),
                label: const Text('Add to playlist'),
              ),
              TextButton.icon(
                onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const QueuePage())),
                icon: const Icon(Icons.queue_music),
                label: const Text('Queue'),
              ),
              IconButton(tooltip: 'More', icon: const Icon(Icons.more_horiz), onPressed: () => showTrackMenu(context, track)),
            ],
          ),
          if (!Platform.isAndroid) _VolumeBar(app: app),
        ],
      );
      return Scaffold(
        appBar: AppBar(
          leading: IconButton(icon: const Icon(Icons.keyboard_arrow_down), tooltip: 'Close', onPressed: () => Navigator.pop(context)),
          title: const Text('Now playing'),
          centerTitle: true,
          actions: [
            ListenableBuilder(
              listenable: app.settings,
              builder: (context, _) => IconButton(
                tooltip: 'Sound',
                icon: Icon(Icons.equalizer, color: app.settings.sound.on ? theme.colorScheme.primary : null),
                onPressed: () => openSound(context),
              ),
            ),
          ],
        ),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: wide ? 1000 : 520),
              child: wide
                  ? Padding(
                      padding: const EdgeInsets.all(32),
                      child: Row(
                        children: [
                          Expanded(child: cover),
                          const SizedBox(width: 40),
                          Expanded(child: details),
                        ],
                      ),
                    )
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                      children: [
                        Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: cover),
                        const SizedBox(height: 24),
                        details,
                      ],
                    ),
            ),
          ),
        ),
      );
    });
  }
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
