// The songs kept on this device: what's there, how much room it takes, and
// taking a song out again. They play from here with no internet (offline.dart).

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../offline.dart';
import '../track.dart';
import '../util.dart';
import 'widgets.dart';

class OfflinePage extends StatelessWidget {
  const OfflinePage({super.key});

  @override
  Widget build(BuildContext context) {
    final app = Paattu.of(context);
    final offline = app.offline;
    return Scaffold(
      appBar: AppBar(title: const Text('On this device')),
      body: ListenableBuilder(
        listenable: offline,
        builder: (context, _) {
          final songs = offline.songs;
          if (songs.isEmpty) {
            return EmptyState(
              icon: Icons.download_for_offline_outlined,
              title: 'No songs kept yet',
              body: 'Songs you listen to are kept here as you play them, so they work with no '
                  'internet and no data. Keep one by hand from a song\'s menu.',
            );
          }
          return ListView(
            padding: const EdgeInsets.only(bottom: 32),
            children: [
              _Summary(offline: offline),
              for (final entry in songs)
                TrackTile(
                  track: entry.track,
                  onTap: () => app.player.playTrack(entry.track),
                  playingId: trackId(app.player.current.value ?? const {}) == trackId(entry.track)
                      ? trackId(entry.track)
                      : null,
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(entry.size,
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                      IconButton(
                        tooltip: 'Take it off this device',
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => _remove(context, app, entry),
                      ),
                    ],
                  ),
                ),
              const _PlayAll(),
            ],
          );
        },
      ),
    );
  }

  Future<void> _remove(BuildContext context, AppState app, OfflineEntry entry) async {
    final sure = await confirm(
      context,
      title: 'Take ${entry.title} off this device?',
      body: 'It streams again when you play it, and is kept again once you listen to it.',
      action: 'Take it off',
    );
    if (sure) app.dropOffline(entry);
  }
}

/// How many songs, how much room, and how much is allowed.
class _Summary extends StatelessWidget {
  const _Summary({required this.offline});
  final OfflineLibrary offline;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final limit = offline.limitBytes;
    final used = offline.totalBytes;
    final fraction = limit > 0 ? (used / limit).clamp(0.0, 1.0) : 0.0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('${plural(offline.count, 'song')} · ${formatBytes(used)}',
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
              ),
              TextButton.icon(
                onPressed: () => _playAll(context, offline, shuffled: true),
                icon: const Icon(Icons.shuffle, size: 18),
                label: const Text('Shuffle'),
              ),
              TextButton.icon(
                onPressed: () => _playAll(context, offline),
                icon: const Icon(Icons.play_arrow, size: 18),
                label: const Text('Play'),
              ),
            ],
          ),
          if (limit > 0) ...[
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(value: fraction, minHeight: 5),
            ),
            const SizedBox(height: 6),
            Text('${formatBytes(used)} of ${formatBytes(limit)} allowed', style: muted),
          ],
          const SizedBox(height: 4),
          Text(offline.path, style: muted?.copyWith(fontSize: 11)),
          const SizedBox(height: 4),
          Text('These play with no internet. Past the space allowed, the songs played least '
              'recently go first.',
              style: muted),
        ],
      ),
    );
  }
}

/// Play everything kept here.
class _PlayAll extends StatelessWidget {
  const _PlayAll();

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _playAll(context, Paattu.of(context).offline),
                icon: const Icon(Icons.play_circle_outline),
                label: const Text('Play everything on this device'),
              ),
            ),
          ],
        ),
      );
}

void _playAll(BuildContext context, OfflineLibrary offline, {bool shuffled = false}) {
  final app = Paattu.of(context);
  final songs = [for (final entry in offline.songs) entry.track];
  if (songs.isEmpty) return;
  fire(app.player.playTracks(songs, shuffled: shuffled));
}
