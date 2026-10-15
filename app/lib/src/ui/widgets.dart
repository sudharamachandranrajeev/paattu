// Pieces the pages share: cover art, song rows, the song menu, pickers.

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_state.dart';
import '../library.dart';
import '../links.dart';
import '../track.dart';
import '../util.dart';
import 'glass.dart';

/// Cover art from the network, with a fallback picture and a placeholder.
class Cover extends StatelessWidget {
  const Cover({super.key, this.url, this.fallback, this.size = 48, this.radius = 6, this.icon = Icons.music_note});

  final String? url;
  final String? fallback;
  final double? size;
  final double radius;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget placeholder() => Container(
          color: scheme.surfaceContainerHighest,
          alignment: Alignment.center,
          child: Icon(icon, color: scheme.onSurfaceVariant, size: size == null ? 48 : size! * 0.45),
        );
    Widget image(String? link, Widget Function() otherwise) => link == null || link.isEmpty
        ? otherwise()
        : Image.network(link,
            fit: BoxFit.cover,
            width: size,
            height: size,
            gaplessPlayback: true,
            errorBuilder: (_, _, _) => otherwise());
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox(
        width: size,
        height: size,
        child: image(url, () => image(fallback, placeholder)),
      ),
    );
  }
}

class TrackCover extends StatelessWidget {
  const TrackCover(this.track, {super.key, this.size = 48, this.large = false, this.radius = 6});
  final Json track;
  final double? size;
  final bool large;
  final double radius;

  @override
  Widget build(BuildContext context) =>
      Cover(url: trackArt(track, large: large), fallback: trackArtFallback(track), size: size, radius: radius);
}

/// The song playing now, for highlighting it in lists.
class NowPlayingBuilder extends StatelessWidget {
  const NowPlayingBuilder({super.key, required this.builder});
  final Widget Function(BuildContext context, String? playingId) builder;

  @override
  Widget build(BuildContext context) {
    final player = Paattu.of(context).player;
    return StreamBuilder<Json?>(
      stream: player.current,
      initialData: player.current.value,
      builder: (context, snapshot) => builder(context, snapshot.data == null ? null : trackId(snapshot.data!)),
    );
  }
}

/// A song in a list, as a glass pill: round cover, title, film · singer,
/// length and a menu.
class TrackTile extends StatelessWidget {
  const TrackTile({
    super.key,
    required this.track,
    required this.onTap,
    this.playingId,
    this.index,
    this.playlistId,
    this.trailing,
  });

  final Json track;
  final VoidCallback onTap;
  final String? playingId;
  final int? index;
  final String? playlistId;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final playing = playingId != null && playingId == trackId(track);
    final subtitle = trackSubtitle(track);
    final duration = trackDuration(track);
    final scheme = theme.colorScheme;
    return PillTile(
      active: playing,
      onTap: onTap,
      onLongPress: () => showTrackMenu(context, track, playlistId: playlistId),
      leading: Container(
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: playing ? scheme.primary : Colors.transparent, width: 2),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            TrackCover(track, size: 46, radius: 23),
            if (playing)
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.45), shape: BoxShape.circle),
                child: Icon(Icons.graphic_eq, color: scheme.primary),
              ),
          ],
        ),
      ),
      title: trackTitle(track),
      subtitle: subtitle,
      trailing: [
        ?trailing,
        if (duration != null)
          Padding(
            padding: const EdgeInsets.only(left: 6),
            child: Text(formatDuration(duration),
                style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
          ),
        IconButton(
          tooltip: 'More',
          icon: const Icon(Icons.more_horiz),
          onPressed: () => showTrackMenu(context, track, playlistId: playlistId),
        ),
      ],
    );
  }
}

/// A row in a list since 0.5: a glass pill with a round picture, a title and
/// a muted line under it. [active] tints it, for the song playing now.
class PillTile extends StatelessWidget {
  const PillTile({
    super.key,
    required this.leading,
    required this.title,
    this.subtitle = '',
    this.trailing = const [],
    this.onTap,
    this.onLongPress,
    this.active = false,
  });

  final Widget leading;
  final String title;
  final String subtitle;
  final List<Widget> trailing;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Glass(
        radius: 999,
        color: active ? scheme.primary.withValues(alpha: 0.16) : null,
        onTap: onTap,
        onLongPress: onLongPress,
        padding: EdgeInsets.fromLTRB(6, 6, trailing.isEmpty ? 18 : 2, 6),
        child: Row(
          children: [
            leading,
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyLarge
                        ?.copyWith(fontWeight: FontWeight.w600, color: active ? scheme.primary : null),
                  ),
                  if (subtitle.isNotEmpty)
                    Text(subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                ],
              ),
            ),
            ...trailing,
          ],
        ),
      ),
    );
  }
}

/// A heart button that follows the library.
class FavouriteButton extends StatelessWidget {
  const FavouriteButton(this.track, {super.key, this.size});
  final Json track;
  final double? size;

  @override
  Widget build(BuildContext context) => LibraryBuilder(builder: (context, app) {
        final on = app.library.isFavourite(trackId(track));
        return IconButton(
          iconSize: size,
          tooltip: on ? 'Remove from Favourites' : 'Add to Favourites',
          icon: Icon(on ? Icons.favorite : Icons.favorite_border, color: on ? Theme.of(context).colorScheme.primary : null),
          onPressed: () => app.toggleFavourite(track),
        );
      });
}

/// The song menu: play, queue, heart, save, add to a playlist, open.
Future<void> showTrackMenu(BuildContext context, Json track, {String? playlistId}) {
  final app = Paattu.of(context);
  final library = app.library;
  final id = trackId(track);
  final ownList = playlistId != null && library.playlist(playlistId)?['local'] == true;
  final ytList = playlistId != null && !ownList && library.playlist(playlistId) != null;
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
      useRootNavigator: true,
    isScrollControlled: true,
    builder: (sheet) => SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: TrackCover(track),
              title: Text(trackTitle(track), maxLines: 2, overflow: TextOverflow.ellipsis),
              subtitle: Text([trackSubtitle(track), siteName(trackSite(track))].where((s) => s.isNotEmpty).join(' · ')),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.play_arrow),
              title: const Text('Play now'),
              onTap: () {
                Navigator.pop(sheet);
                fire(app.player.playTrack(track));
              },
            ),
            ListTile(
              leading: const Icon(Icons.radio),
              title: const Text('Start radio'),
              subtitle: const Text('This song, then songs like it'),
              onTap: () {
                Navigator.pop(sheet);
                fire(app.player.startRadio(track));
              },
            ),
            ListTile(
              leading: const Icon(Icons.playlist_play),
              title: const Text('Play next'),
              onTap: () {
                Navigator.pop(sheet);
                app.player.playNext([track]);
              },
            ),
            ListTile(
              leading: const Icon(Icons.queue_music),
              title: const Text('Add to queue'),
              onTap: () {
                Navigator.pop(sheet);
                app.player.enqueue([track]);
              },
            ),
            ListTile(
              leading: Icon(library.isFavourite(id) ? Icons.favorite : Icons.favorite_border),
              title: Text(library.isFavourite(id) ? 'Remove from Favourites' : 'Add to Favourites'),
              onTap: () {
                Navigator.pop(sheet);
                app.toggleFavourite(track);
              },
            ),
            if (!library.isSaved(id))
              ListTile(
                leading: const Icon(Icons.library_add),
                title: const Text('Save to library'),
                onTap: () {
                  Navigator.pop(sheet);
                  app.saveSong(track);
                },
              ),
            ListTile(
              leading: const Icon(Icons.playlist_add),
              title: const Text('Add to a playlist…'),
              onTap: () async {
                Navigator.pop(sheet);
                final target = await pickPlaylist(context);
                if (target != null) app.addToPlaylist(target, [track]);
              },
            ),
            if (ownList || ytList)
              ListTile(
                leading: const Icon(Icons.remove_circle_outline),
                title: Text('Remove from ${library.playlist(playlistId)?['title'] ?? 'this playlist'}'),
                onTap: () {
                  Navigator.pop(sheet);
                  library.removeTracks(playlistId, [id]);
                  library.changed();
                  app.toast('Removed ${trackTitle(track)}');
                },
              ),
            ListTile(
              leading: const Icon(Icons.open_in_new),
              title: Text('Open on ${siteName(trackSite(track))}'),
              onTap: () {
                Navigator.pop(sheet);
                fire(launchUrl(Uri.parse(trackPage(track)), mode: LaunchMode.externalApplication));
              },
            ),
          ],
        ),
      ),
    ),
  );
}

/// Pick one of your playlists (or make a new one). Returns its id.
Future<String?> pickPlaylist(BuildContext context) {
  final app = Paattu.of(context);
  return showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
      useRootNavigator: true,
    isScrollControlled: true,
    builder: (sheet) {
      final own = app.library.ownPlaylists();
      if (!own.any((p) => p['id'] == favouritesId)) own.insert(0, app.library.favourites());
      return SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(sheet).height * 0.7),
          child: ListView(
            shrinkWrap: true,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text('Add to a playlist', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
              ),
              ListTile(
                leading: const Icon(Icons.add),
                title: const Text('New playlist…'),
                onTap: () async {
                  final name = await askText(sheet, title: 'New playlist', label: 'Name', action: 'Create');
                  if (name == null || !sheet.mounted) return;
                  try {
                    final p = app.library.createPlaylist(name);
                    app.library.changed();
                    if (sheet.mounted) Navigator.pop(sheet, p['id'] as String);
                  } on LibraryException catch (error) {
                    app.toast(error.message);
                  }
                },
              ),
              for (final p in own)
                ListTile(
                  leading: Icon(p['id'] == favouritesId
                      ? Icons.favorite
                      : p['id'] == savedId
                          ? Icons.library_music
                          : Icons.queue_music),
                  title: Text(asString(p['title'])),
                  subtitle: Text(plural(asList(p['tracks']).length, 'song')),
                  onTap: () => Navigator.pop(sheet, p['id'] as String),
                ),
            ],
          ),
        ),
      );
    },
  );
}

/// Ask for a line of text.
Future<String?> askText(BuildContext context,
    {required String title, String label = '', String initial = '', String action = 'OK', String? hint}) {
  final controller = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (dialog) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        decoration: InputDecoration(labelText: label.isEmpty ? null : label, hintText: hint),
        onSubmitted: (value) => Navigator.pop(dialog, value.trim().isEmpty ? null : value.trim()),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dialog), child: const Text('Cancel')),
        FilledButton(
          onPressed: () => Navigator.pop(dialog, controller.text.trim().isEmpty ? null : controller.text.trim()),
          child: Text(action),
        ),
      ],
    ),
  ).whenComplete(controller.dispose);
}

Future<bool> confirm(BuildContext context, {required String title, String? body, String action = 'Remove'}) async {
  final answer = await showDialog<bool>(
    context: context,
    builder: (dialog) => AlertDialog(
      title: Text(title),
      content: body == null ? null : Text(body),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dialog, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(dialog, true), child: Text(action)),
      ],
    ),
  );
  return answer == true;
}

class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.action});
  final String title;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 8, 8),
        child: Row(
          children: [
            Expanded(
              child: Text(title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(fontSize: 18, fontWeight: FontWeight.w600)),
            ),
            ?action,
          ],
        ),
      );
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, this.body, this.action});
  final IconData icon;
  final String title;
  final String? body;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(height: 12),
            Text(title, style: theme.textTheme.titleMedium, textAlign: TextAlign.center),
            if (body != null) ...[
              const SizedBox(height: 6),
              Text(body!, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  textAlign: TextAlign.center),
            ],
            if (action != null) ...[const SizedBox(height: 16), action!],
          ],
        ),
      ),
    );
  }
}

/// A square playlist card for the home shelves.
class PlaylistCard extends StatelessWidget {
  const PlaylistCard({super.key, required this.playlist, required this.onTap, this.width = 150, this.icon});
  final Json playlist;
  final VoidCallback onTap;
  final double width;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final count = playlist['tracks'] is List ? plural(asList(playlist['tracks']).length, 'song') : '';
    final owner = asString(playlist['ownerName']);
    final subtitle = owner.isNotEmpty ? owner : count;
    return SizedBox(
      width: width,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Stack(
                children: [
                  Cover(
                    url: asString(playlist['thumbnail']),
                    size: width - 8,
                    radius: 22,
                    icon: icon ?? Icons.queue_music,
                  ),
                  if (count.isNotEmpty && owner.isNotEmpty)
                    Positioned(left: 8, top: 8, child: GlassChip(icon: Icons.headphones, label: count)),
                ],
              ),
              const SizedBox(height: 6),
              Text(asString(playlist['title']), maxLines: 2, overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
              Text(subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            ],
          ),
        ),
      ),
    );
  }
}

/// The top of an album, playlist or artist page: the picture glowing in the
/// theme's colour, the name, details and the play buttons.
class PageHeader extends StatelessWidget {
  const PageHeader({
    super.key,
    required this.art,
    required this.title,
    required this.lines,
    required this.actions,
    this.round = false,
    this.icon,
  });
  final String art;
  final String title;
  final List<String> lines;
  final List<Widget> actions;
  final bool round;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final wide = MediaQuery.sizeOf(context).width >= 600;
    final size = wide ? 200.0 : 168.0;
    final radius = round ? size / 2 : 28.0;
    final picture = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        boxShadow: [BoxShadow(color: theme.colorScheme.primary.withValues(alpha: 0.4), blurRadius: 40, offset: const Offset(0, 8))],
      ),
      child: Cover(url: art, size: size, radius: radius, icon: icon ?? (round ? Icons.person : Icons.album)),
    );
    final text = Column(
      crossAxisAlignment: wide ? CrossAxisAlignment.start : CrossAxisAlignment.center,
      children: [
        Text(title,
            textAlign: wide ? TextAlign.start : TextAlign.center,
            style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
        for (final line in lines.where((l) => l.isNotEmpty))
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(line,
                textAlign: wide ? TextAlign.start : TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ),
        const SizedBox(height: 14),
        Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.center, children: actions),
      ],
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: wide
          ? Row(children: [picture, const SizedBox(width: 24), Expanded(child: text)])
          : Column(children: [picture, const SizedBox(height: 18), text]),
    );
  }
}
