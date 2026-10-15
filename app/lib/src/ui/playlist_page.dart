// One playlist: yours (rename, reorder, remove songs) or a YouTube one
// (load / refresh, save to the shelves, language).

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_state.dart';
import '../library.dart';
import '../util.dart';
import 'widgets.dart';

const _languages = ['Malayalam', 'Tamil', 'Other'];

class PlaylistPage extends StatefulWidget {
  const PlaylistPage({super.key, required this.playlistId});
  final String playlistId;

  @override
  State<PlaylistPage> createState() => _PlaylistPageState();
}

class _PlaylistPageState extends State<PlaylistPage> {
  bool _asked = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_asked) return;
    _asked = true;
    final app = Paattu.of(context);
    final p = app.library.playlist(widget.playlistId);
    if (p != null && p['local'] != true && !app.library.fetched(widget.playlistId)) {
      fire(attempt(app, () => app.fetchPlaylist(widget.playlistId), failure: "Couldn't load the playlist"));
    }
  }

  Future<void> _menu(AppState app, Json p) async {
    final id = widget.playlistId;
    final own = p['local'] == true;
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      useRootNavigator: true,
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (own && !Library.builtin(id))
              ListTile(leading: const Icon(Icons.edit), title: const Text('Rename'), onTap: () => Navigator.pop(sheet, 'rename')),
            if (!own) ...[
              ListTile(leading: const Icon(Icons.refresh), title: const Text('Refresh from YouTube'), onTap: () => Navigator.pop(sheet, 'refresh')),
              ListTile(leading: const Icon(Icons.translate), title: const Text('Language'), onTap: () => Navigator.pop(sheet, 'language')),
              ListTile(leading: const Icon(Icons.open_in_new), title: const Text('Open on YouTube'), onTap: () => Navigator.pop(sheet, 'open')),
            ],
            ListTile(
              leading: const Icon(Icons.queue_music),
              title: const Text('Add all to the queue'),
              onTap: () => Navigator.pop(sheet, 'queue'),
            ),
            if (!Library.builtin(id))
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: Text(own ? 'Delete playlist' : 'Remove from the app'),
                onTap: () => Navigator.pop(sheet, 'remove'),
              ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    switch (choice) {
      case 'rename':
        final name = await askText(context, title: 'Rename playlist', initial: asString(p['title']), action: 'Rename');
        if (name == null) return;
        try {
          app.library.renamePlaylist(id, name);
          app.library.changed();
        } on LibraryException catch (error) {
          app.toast(error.message);
        }
      case 'refresh':
        await attempt(app, () => app.fetchPlaylist(id), failure: "Couldn't refresh");
      case 'language':
        final language = await showDialog<String>(
          context: context,
          builder: (dialog) => SimpleDialog(
            title: const Text('Language'),
            children: [
              for (final lang in _languages)
                SimpleDialogOption(onPressed: () => Navigator.pop(dialog, lang), child: Text(lang)),
            ],
          ),
        );
        if (language == null) return;
        app.library.setPlaylistLanguage(id, language == 'Other' ? '' : language);
        app.library.changed();
      case 'open':
        fire(launchUrl(Uri.parse('https://www.youtube.com/playlist?list=$id'), mode: LaunchMode.externalApplication));
      case 'queue':
        app.player.enqueue(app.library.playlistTracks(id));
      case 'remove':
        final ok = await confirm(context,
            title: own ? 'Delete ${p['title']}?' : 'Remove ${p['title']}?',
            body: own ? 'The playlist and its list of songs go.' : "Syncing its profile won't bring it back.");
        if (!ok || !mounted) return;
        app.library.removePlaylist(id);
        app.library.changed();
        Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) => LibraryBuilder(builder: (context, app) {
        final library = app.library;
        final p = library.playlist(widget.playlistId);
        if (p == null) {
          return Scaffold(appBar: AppBar(), body: const EmptyState(icon: Icons.queue_music, title: "This playlist isn't in the library any more"));
        }
        final own = p['local'] == true;
        final tracks = library.playlistTracks(widget.playlistId);
        return Scaffold(
          appBar: AppBar(
            title: Text(asString(p['title']), maxLines: 1, overflow: TextOverflow.ellipsis),
            actions: [
              if (!own)
                IconButton(
                  tooltip: p['saved'] == true ? 'On your shelves (tap to take off)' : 'Save to your shelves',
                  icon: Icon(p['saved'] == true ? Icons.bookmark : Icons.bookmark_border),
                  onPressed: () {
                    library.setSaved(widget.playlistId, p['saved'] != true);
                    library.changed();
                    app.toast(p['saved'] == true ? 'Saved ${p['title']}' : 'Took ${p['title']} off the shelves');
                  },
                ),
              IconButton(tooltip: 'More', icon: const Icon(Icons.more_vert), onPressed: () => _menu(app, p)),
            ],
          ),
          body: ValueListenableBuilder<Set<String>>(
            valueListenable: app.fetching,
            builder: (context, fetching, _) {
              final loading = fetching.contains(widget.playlistId);
              final header = PageHeader(
                art: asString(p['thumbnail']),
                title: asString(p['title']),
                icon: widget.playlistId == favouritesId ? Icons.favorite : Icons.queue_music,
                lines: [
                  [
                    asString(p['ownerName']),
                    if (asString(p['language']).isNotEmpty) asString(p['language']),
                    if (p['tracks'] is List) plural(tracks.length, 'song'),
                  ].where((s) => s.isNotEmpty).join(' · '),
                ],
                actions: [
                  FilledButton.icon(
                    onPressed: tracks.isEmpty ? null : () => fire(app.playPlaylist(widget.playlistId)),
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('Play'),
                  ),
                  OutlinedButton.icon(
                    onPressed: tracks.isEmpty ? null : () => fire(app.playPlaylist(widget.playlistId, shuffled: true)),
                    icon: const Icon(Icons.shuffle),
                    label: const Text('Shuffle'),
                  ),
                ],
              );
              if (tracks.isEmpty) {
                return ListView(children: [
                  header,
                  if (loading)
                    const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()))
                  else
                    EmptyState(
                      icon: Icons.music_off_outlined,
                      title: p['tracks'] is List ? 'No songs here yet' : "This playlist isn't loaded",
                      body: own ? 'Add songs from a search or any song menu.' : null,
                      action: own
                          ? null
                          : OutlinedButton(
                              onPressed: () => attempt(app, () => app.fetchPlaylist(widget.playlistId),
                                  failure: "Couldn't load the playlist"),
                              child: const Text('Load'),
                            ),
                    ),
                ]);
              }
              return NowPlayingBuilder(
                builder: (context, playingId) => own
                    ? ReorderableListView.builder(
                        header: header,
                        buildDefaultDragHandles: false,
                        itemCount: tracks.length,
                        onReorderItem: (from, to) {
                          library.moveTrack(widget.playlistId, from, to);
                          library.changed();
                        },
                        itemBuilder: (context, i) => TrackTile(
                          key: ValueKey('$i:${tracks[i]['id']}'),
                          track: tracks[i],
                          playingId: playingId,
                          playlistId: widget.playlistId,
                          trailing: ReorderableDragStartListener(
                            index: i,
                            child: const Padding(padding: EdgeInsets.all(8), child: Icon(Icons.drag_handle)),
                          ),
                          onTap: () => fire(app.playPlaylist(widget.playlistId, start: i)),
                        ),
                      )
                    : ListView.builder(
                        itemCount: tracks.length + 2,
                        itemBuilder: (context, i) {
                          if (i == 0) return header;
                          if (i == 1) return loading ? const LinearProgressIndicator() : const SizedBox.shrink();
                          final index = i - 2;
                          return TrackTile(
                            track: tracks[index],
                            playingId: playingId,
                            playlistId: widget.playlistId,
                            onTap: () => fire(app.playPlaylist(widget.playlistId, start: index)),
                          );
                        },
                      ),
              );
            },
          ),
        );
      });
}
