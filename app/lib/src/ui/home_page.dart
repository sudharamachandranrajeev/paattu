// Home: a big card that shuffles your first mix, the playlists made for you
// and the mixes as bright tiles, a few of your favourites, your playlists and the saved YouTube playlists
// by language.

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../library.dart';
import '../util.dart';
import 'glass.dart';
import 'library_page.dart';
import 'made_page.dart';
import 'mix_editor.dart';
import 'playlist_page.dart';
import 'widgets.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key, required this.onSearch, this.onSettings});
  final VoidCallback onSearch;
  final VoidCallback? onSettings;

  @override
  Widget build(BuildContext context) => LibraryBuilder(builder: (context, app) {
        final library = app.library;
        final own = library.ownPlaylists().where((p) => asList(p['tracks']).isNotEmpty || !Library.builtin(asString(p['id']))).toList();
        final shelves = library.shelves();
        final languages = library.languages();
        final empty = own.isEmpty && shelves.isEmpty;
        final favourites = library.playlistTracks(favouritesId);
        return Scaffold(
          appBar: AppBar(
            titleSpacing: 20,
            title: Row(
              children: [
                Image.asset('assets/icon.png', width: 30, height: 30),
                const SizedBox(width: 10),
                const Text('Paattu', style: TextStyle(fontWeight: FontWeight.w700)),
              ],
            ),
            actions: [
              GlassIconButton(icon: Icons.search, tooltip: 'Search', size: 42, onPressed: onSearch),
              if (onSettings != null) ...[
                const SizedBox(width: 8),
                GlassIconButton(icon: Icons.settings_outlined, tooltip: 'Settings', size: 42, onPressed: onSettings),
              ],
              const SizedBox(width: 16),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.only(bottom: 24),
            children: [
              _Hero(app: app, onSearch: onSearch),
              const SectionHeader('Made for you'),
              const MadeForYouShelf(),
              const SectionHeader('Mixes'),
              _Mixes(app: app),
              if (empty)
                EmptyState(
                  icon: Icons.library_music_outlined,
                  title: 'Your library is empty',
                  body: 'Search for songs, or add a YouTube profile or playlist to fill the shelves and mixes.',
                  action: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    alignment: WrapAlignment.center,
                    children: [
                      FilledButton.icon(onPressed: onSearch, icon: const Icon(Icons.search), label: const Text('Search songs')),
                      OutlinedButton.icon(
                        onPressed: () => showAddFromYouTube(context),
                        icon: const Icon(Icons.add_link),
                        label: const Text('Add from YouTube'),
                      ),
                    ],
                  ),
                ),
              if (favourites.isNotEmpty) _Favourites(app: app, tracks: favourites),
              if (own.isNotEmpty) ...[
                const SectionHeader('Your playlists'),
                _Shelf(playlists: own),
              ],
              for (final language in languages) ...[
                SectionHeader(language),
                _Shelf(playlists: shelves[language] ?? const []),
              ],
            ],
          ),
        );
      });
}

/// A playlist's picture for a mix: its first playlist that has one.
String _mixArt(Library library, Json mix) =>
    library.mixPlaylists(mix).map((p) => asString(p['thumbnail'])).firstWhere((t) => t.isNotEmpty, orElse: () => '');

String _mixDetail(Library library, Json mix) {
  final counts = library.mixCounts(mix);
  return counts.playlists == 0
      ? 'Nothing picked yet'
      : counts.waiting > 0
          ? '${plural(counts.playlists, 'playlist')}, ${counts.waiting} to load'
          : '${plural(counts.songs, 'song')} from ${plural(counts.playlists, 'playlist')}';
}

/// The card at the top, with a deck of cards behind it: shuffle the first
/// mix (or, with no mixes, go and find songs).
class _Hero extends StatelessWidget {
  const _Hero({required this.app, required this.onSearch});
  final AppState app;
  final VoidCallback onSearch;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final mix = app.library.mixList().firstOrNull;
    final hour = DateTime.now().hour;
    final greeting = hour < 5
        ? 'Late night'
        : hour < 12
            ? 'Good morning'
            : hour < 17
                ? 'Good afternoon'
                : 'Good evening';
    final title = mix == null ? 'Find your songs' : 'Shuffle ${asString(mix['title'])}';
    final detail = mix == null ? 'Search JioSaavn and YouTube, or add a YouTube playlist' : _mixDetail(app.library, mix);
    final art = mix == null ? '' : _mixArt(app.library, mix);
    final action = mix == null ? onSearch : () => fire(app.playMix(mix));
    Widget layer(Color colour) => DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [colour.withValues(alpha: 0.6), colour.withValues(alpha: 0.15)],
            ),
          ),
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: SizedBox(
        height: 204,
        child: Stack(
          children: [
            Positioned(left: 40, right: 40, top: 0, height: 60, child: layer(scheme.secondary)),
            Positioned(left: 20, right: 20, top: 10, height: 60, child: layer(scheme.primary)),
            Positioned.fill(
              top: 20,
              child: Glass(
                blur: true,
                radius: 28,
                color: Color.alphaBlend(scheme.primary.withValues(alpha: 0.16), scheme.surface.withValues(alpha: 0.72)),
                onTap: action,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 18, 8, 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(greeting, style: theme.textTheme.labelLarge?.copyWith(color: scheme.onSurfaceVariant)),
                            const SizedBox(height: 2),
                            Text(title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600, height: 1.2)),
                            const SizedBox(height: 4),
                            Text(detail,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                            const Spacer(),
                            ExcludeSemantics(
                              child: Glass(
                                radius: 999,
                                color: Colors.white.withValues(alpha: 0.1),
                                padding: const EdgeInsets.fromLTRB(14, 8, 18, 8),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(mix == null ? Icons.search : Icons.shuffle, size: 18),
                                    const SizedBox(width: 6),
                                    Text(mix == null ? 'Search' : 'Start now',
                                        style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600)),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (art.isNotEmpty)
                      SizedBox(
                        width: 136,
                        child: ShaderMask(
                          // The picture melts into the card at its left edge.
                          shaderCallback: (rect) => const LinearGradient(
                            colors: [Colors.transparent, Colors.black],
                            stops: [0, 0.45],
                          ).createShader(rect),
                          blendMode: BlendMode.dstIn,
                          child: Image.network(art, fit: BoxFit.cover, errorBuilder: (_, _, _) => const SizedBox()),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Mixes extends StatelessWidget {
  const _Mixes({required this.app});
  final AppState app;

  @override
  Widget build(BuildContext context) {
    final mixes = app.library.mixList();
    return SizedBox(
      height: 180,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        scrollDirection: Axis.horizontal,
        itemCount: mixes.length + 1,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (context, i) => i < mixes.length
            ? _MixTile(app: app, mix: mixes[i], index: i)
            : SizedBox(
                width: 120,
                child: Glass(
                  radius: 28,
                  onTap: () => editMix(context, null),
                  child: const Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [Icon(Icons.add, size: 32), SizedBox(height: 6), Text('New mix')],
                  ),
                ),
              ),
      ),
    );
  }
}

/// A mix as a bright square: how many songs, its name, how many playlists.
/// Tap to shuffle; long-press (or right-click) for the rest.
class _MixTile extends StatelessWidget {
  const _MixTile({required this.app, required this.mix, required this.index});
  final AppState app;
  final Json mix;
  final int index;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final counts = app.library.mixCounts(mix);
    final title = asString(mix['title']);
    final art = _mixArt(app.library, mix);
    const white = Colors.white;
    return Tooltip(
      message: 'Long-press to edit',
      excludeFromSemantics: true,
      child: Semantics(
        button: true,
        label: 'Shuffle $title: ${_mixDetail(app.library, mix)}',
        excludeSemantics: true,
        onTap: () => fire(app.playMix(mix)),
        onLongPress: () => _menu(context),
        child: GestureDetector(
          onLongPress: () => _menu(context),
          onSecondaryTap: () => _menu(context),
          child: Material(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
            clipBehavior: Clip.antiAlias,
            child: Ink(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: tileColours(theme.colorScheme, index),
                ),
              ),
              child: InkWell(
                onTap: () => fire(app.playMix(mix)),
                child: SizedBox(
                  width: 168,
                  child: Stack(
                    children: [
                      if (art.isNotEmpty)
                        Positioned.fill(
                          child: ShaderMask(
                            shaderCallback: (rect) => LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [Colors.transparent, Colors.black.withValues(alpha: 0.3)],
                            ).createShader(rect),
                            blendMode: BlendMode.dstIn,
                            child: Image.network(art, fit: BoxFit.cover, errorBuilder: (_, _, _) => const SizedBox()),
                          ),
                        ),
                      Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            GlassChip(
                              icon: Icons.headphones,
                              label: counts.playlists == 0 ? 'Empty' : '${shortCount(counts.songs)} songs',
                            ),
                            const Spacer(),
                            Text(title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.titleMedium?.copyWith(color: white, fontWeight: FontWeight.w600)),
                            Text(counts.playlists.toString().padLeft(2, '0'),
                                style: theme.textTheme.displaySmall
                                    ?.copyWith(color: white, fontWeight: FontWeight.w700, height: 1.05)),
                            Text(counts.playlists == 1 ? 'playlist' : 'playlists',
                                style: theme.textTheme.labelSmall?.copyWith(color: white.withValues(alpha: 0.8))),
                          ],
                        ),
                      ),
                      const Positioned(right: 12, bottom: 12, child: Icon(Icons.play_arrow_rounded, color: white, size: 32)),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _menu(BuildContext context) async {
    final id = asString(mix['id']);
    final mixes = app.library.mixList();
    final position = mixes.indexWhere((m) => m['id'] == id);
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      useRootNavigator: true,
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(title: Text(asString(mix['title']), style: const TextStyle(fontWeight: FontWeight.w600))),
            ListTile(leading: const Icon(Icons.shuffle), title: const Text('Shuffle'), onTap: () => Navigator.pop(sheet, 'play')),
            ListTile(leading: const Icon(Icons.tune), title: const Text('Edit'), onTap: () => Navigator.pop(sheet, 'edit')),
            if (position > 0)
              ListTile(leading: const Icon(Icons.arrow_back), title: const Text('Move earlier'), onTap: () => Navigator.pop(sheet, 'left')),
            if (position < mixes.length - 1)
              ListTile(leading: const Icon(Icons.arrow_forward), title: const Text('Move later'), onTap: () => Navigator.pop(sheet, 'right')),
            ListTile(leading: const Icon(Icons.delete_outline), title: const Text('Remove'), onTap: () => Navigator.pop(sheet, 'remove')),
          ],
        ),
      ),
    );
    if (!context.mounted) return;
    switch (choice) {
      case 'play':
        fire(app.playMix(mix));
      case 'edit':
        await editMix(context, id);
      case 'left':
        app.library.moveMix(id, position - 1);
        app.library.changed();
      case 'right':
        app.library.moveMix(id, position + 1);
        app.library.changed();
      case 'remove':
        if (await confirm(context, title: 'Remove ${mix['title']}?', body: 'Its playlists stay in the library.')) {
          app.library.removeMix(id);
          app.library.changed();
        }
    }
  }
}

/// A few favourites in a sheet rising from below, as the design's lists do.
class _Favourites extends StatelessWidget {
  const _Favourites({required this.app, required this.tracks});
  final AppState app;
  final List<Json> tracks;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final shown = tracks.take(5).toList();
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [scheme.primary.withValues(alpha: 0.32), scheme.primary.withValues(alpha: 0)],
            stops: const [0, 0.7],
          ),
        ),
        child: Column(
          children: [
            const SizedBox(height: 10),
            Container(
              width: 44,
              height: 4,
              decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(2)),
            ),
            SectionHeader(
              'From your favourites',
              action: TextButton(onPressed: () => openPlaylist(context, favouritesId), child: const Text('See all')),
            ),
            NowPlayingBuilder(
              builder: (context, playingId) => Column(
                children: [
                  for (var i = 0; i < shown.length; i++)
                    TrackTile(
                      track: shown[i],
                      playingId: playingId,
                      playlistId: favouritesId,
                      onTap: () => fire(app.playPlaylist(favouritesId, start: i)),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Shelf extends StatelessWidget {
  const _Shelf({required this.playlists});
  final List<Json> playlists;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 222,
        child: ListView.separated(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          scrollDirection: Axis.horizontal,
          itemCount: playlists.length,
          separatorBuilder: (_, _) => const SizedBox(width: 4),
          itemBuilder: (context, i) {
            final p = playlists[i];
            final id = asString(p['id']);
            return PlaylistCard(
              playlist: p,
              icon: id == favouritesId
                  ? Icons.favorite
                  : id == savedId
                      ? Icons.library_music
                      : null,
              onTap: () => openPlaylist(context, id),
            );
          },
        ),
      );
}

void openPlaylist(BuildContext context, String id) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => PlaylistPage(playlistId: id)));
