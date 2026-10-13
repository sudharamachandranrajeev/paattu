// Home: the shuffle mixes, your playlists and the saved YouTube playlists by
// language.

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../library.dart';
import '../util.dart';
import 'library_page.dart';
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
        return Scaffold(
          appBar: AppBar(
            title: const Text('Paattu', style: TextStyle(fontWeight: FontWeight.w700)),
            actions: [
              IconButton(tooltip: 'Search', icon: const Icon(Icons.search), onPressed: onSearch),
              if (onSettings != null) IconButton(tooltip: 'Settings', icon: const Icon(Icons.settings_outlined), onPressed: onSettings),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.only(bottom: 24),
            children: [
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

class _Shelf extends StatelessWidget {
  const _Shelf({required this.playlists});
  final List<Json> playlists;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 214,
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

class _Mixes extends StatelessWidget {
  const _Mixes({required this.app});
  final AppState app;

  @override
  Widget build(BuildContext context) {
    final mixes = app.library.mixList();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final mix in mixes) _MixButton(app: app, mix: mix),
          ActionChip(
            avatar: const Icon(Icons.add, size: 18),
            label: const Text('New mix'),
            onPressed: () => editMix(context, null),
          ),
        ],
      ),
    );
  }
}

class _MixButton extends StatelessWidget {
  const _MixButton({required this.app, required this.mix});
  final AppState app;
  final Json mix;

  @override
  Widget build(BuildContext context) {
    final counts = app.library.mixCounts(mix);
    final detail = counts.playlists == 0
        ? 'Nothing picked yet'
        : counts.waiting > 0
            ? '${plural(counts.playlists, 'playlist')}, ${counts.waiting} to load'
            : plural(counts.songs, 'song');
    return Tooltip(
      message: '$detail. Long-press to edit',
      child: GestureDetector(
        onLongPress: () => _menu(context),
        onSecondaryTap: () => _menu(context),
        child: FilledButton.tonalIcon(
          onPressed: () => fire(app.playMix(mix)),
          icon: const Icon(Icons.shuffle),
          label: Text(asString(mix['title'])),
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

void openPlaylist(BuildContext context, String id) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => PlaylistPage(playlistId: id)));
