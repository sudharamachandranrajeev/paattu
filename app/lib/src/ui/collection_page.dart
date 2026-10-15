// Albums, playlists and artists found by a search: their songs, ready to
// play, save or add to a playlist. Artists' pages also list their albums.

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_state.dart';
import '../links.dart';
import '../sources/jiosaavn.dart';
import '../sources/sources.dart' as sources;
import '../sources/youtube.dart';
import '../util.dart';
import 'glass.dart';
import 'widgets.dart';

/// Open a search result: an album or playlist's songs, or an artist's page.
void openResult(BuildContext context, Json item) {
  final page = asString(item['type']) == 'artist' ? ArtistPage(artist: item) : CollectionPage(collection: item);
  Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
}

IconData resultIcon(Json item) => switch (asString(item['type'])) {
      'album' => Icons.album,
      'artist' => Icons.person,
      'playlist' => Icons.queue_music,
      _ => Icons.music_note,
    };

String resultTypeName(Json item) => switch (asString(item['type'])) {
      'album' => 'Album',
      'artist' => 'Artist',
      'playlist' => 'Playlist',
      'song' => 'Song',
      _ => '',
    };

/// An album or playlist in a grid.
class ResultCard extends StatelessWidget {
  const ResultCard({super.key, required this.item});
  final Json item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final count = toInt(item['count']);
    final detail = [
      asString(item['subtitle']),
      if (count != null && !asString(item['subtitle']).contains('$count')) plural(count, 'song'),
    ].where((s) => s.isNotEmpty).join(' · ');
    return InkWell(
      onTap: () => openResult(context, item),
      borderRadius: BorderRadius.circular(24),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 1,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Cover(url: asString(item['art']), size: null, radius: 22, icon: resultIcon(item)),
                  Positioned(left: 8, top: 8, child: GlassChip(label: siteName(asString(item['site'])))),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Text(asString(item['title']),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
            if (detail.isNotEmpty)
              Text(detail,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}

/// An artist (or any result) in a list.
class ResultTile extends StatelessWidget {
  const ResultTile({super.key, required this.item});
  final Json item;

  @override
  Widget build(BuildContext context) {
    final round = asString(item['type']) == 'artist';
    return PillTile(
      onTap: () => openResult(context, item),
      leading: Cover(url: asString(item['art']), size: 50, radius: round ? 25 : 14, icon: resultIcon(item)),
      title: asString(item['title']),
      subtitle: [asString(item['subtitle']), siteName(asString(item['site']))].where((s) => s.isNotEmpty).join(' · '),
      trailing: const [Icon(Icons.chevron_right), SizedBox(width: 10)],
    );
  }
}

/// A row of albums or artists that scrolls sideways.
class ResultShelf extends StatelessWidget {
  const ResultShelf({super.key, required this.title, required this.items});
  final String title;
  final List<Json> items;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    final round = asString(items.first['type']) == 'artist';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(title),
        SizedBox(
          height: round ? 170 : 210,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(width: 4),
            itemBuilder: (context, i) {
              final item = items[i];
              if (!round) return SizedBox(width: 150, child: ResultCard(item: item));
              return SizedBox(
                width: 120,
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => openResult(context, item),
                  child: Column(
                    children: [
                      const SizedBox(height: 4),
                      Cover(url: asString(item['art']), size: 104, radius: 52, icon: Icons.person),
                      const SizedBox(height: 6),
                      Text(asString(item['title']), maxLines: 2, textAlign: TextAlign.center, overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

List<Widget> _songActions(BuildContext context, List<Json> songs) {
  final app = Paattu.of(context);
  return [
    FilledButton.icon(
      icon: const Icon(Icons.play_arrow),
      label: const Text('Play'),
      onPressed: songs.isEmpty ? null : () => fire(app.player.playTracks(songs)),
    ),
    FilledButton.tonalIcon(
      icon: const Icon(Icons.shuffle),
      label: const Text('Shuffle'),
      onPressed: songs.isEmpty ? null : () => fire(app.player.playTracks(songs, shuffled: true)),
    ),
    OutlinedButton.icon(
      icon: const Icon(Icons.playlist_add),
      label: const Text('Add to playlist'),
      onPressed: songs.isEmpty
          ? null
          : () async {
              final target = await pickPlaylist(context);
              if (target != null) app.addToPlaylist(target, songs);
            },
    ),
  ];
}

Widget _openButton(String url, String site) => IconButton(
      tooltip: 'Open on ${siteName(site)}',
      icon: const Icon(Icons.open_in_new),
      onPressed: url.isEmpty ? null : () => fire(launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication)),
    );

class CollectionPage extends StatefulWidget {
  const CollectionPage({super.key, required this.collection});
  final Json collection;

  @override
  State<CollectionPage> createState() => _CollectionPageState();
}

class _CollectionPageState extends State<CollectionPage> {
  late Future<List<Json>> _songs = sources.collectionSongs(widget.collection);

  @override
  Widget build(BuildContext context) {
    final app = Paattu.of(context);
    final c = widget.collection;
    final site = asString(c['site']);
    final youtubeList = site == 'youtube' && asString(c['type']) == 'playlist';
    return Scaffold(
      appBar: AppBar(title: Text(asString(c['title'])), actions: [_openButton(asString(c['url']), site)]),
      body: FutureBuilder<List<Json>>(
        future: _songs,
        builder: (context, snapshot) {
          final songs = snapshot.data ?? const <Json>[];
          final header = PageHeader(
            art: asString(c['art']),
            title: asString(c['title']),
            lines: [
              asString(c['subtitle']),
              [
                resultTypeName(c),
                siteName(site),
                if (snapshot.hasData) plural(songs.length, 'song'),
                asString(c['language']),
              ].where((s) => s.isNotEmpty).join(' · '),
            ],
            actions: [
              ..._songActions(context, songs),
              if (youtubeList)
                OutlinedButton.icon(
                  icon: const Icon(Icons.library_add),
                  label: const Text('Save to library'),
                  onPressed: () async {
                    try {
                      await app.addYouTubePlaylist(asString(c['url']));
                      app.toast('Saved ${asString(c['title'])} to the library');
                    } catch (error) {
                      app.toast("Couldn't save it: ${errorText(error)}");
                    }
                  },
                )
              else
                OutlinedButton.icon(
                  icon: const Icon(Icons.library_add),
                  label: const Text('Save songs'),
                  onPressed: songs.isEmpty
                      ? null
                      : () {
                          final added = app.library.addTracks(app.library.savedSongs()['id'] as String, songs);
                          app.library.changed();
                          app.toast(added.isEmpty ? 'Already saved' : 'Saved ${plural(added.length, 'song')}');
                        },
                ),
            ],
          );
          if (snapshot.connectionState != ConnectionState.done) {
            return ListView(children: [header, const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()))]);
          }
          if (snapshot.hasError) {
            return ListView(children: [
              header,
              EmptyState(
                icon: Icons.cloud_off,
                title: "Couldn't load the songs",
                body: errorText(snapshot.error!),
                action: FilledButton(
                  onPressed: () => setState(() => _songs = sources.collectionSongs(c)),
                  child: const Text('Try again'),
                ),
              ),
            ]);
          }
          return NowPlayingBuilder(
            builder: (context, playingId) => ListView.builder(
              padding: const EdgeInsets.only(bottom: 24),
              itemCount: songs.length + 1,
              itemBuilder: (context, i) => i == 0
                  ? header
                  : TrackTile(
                      track: songs[i - 1],
                      playingId: playingId,
                      index: i,
                      onTap: () => fire(app.player.playTracks(songs, start: i - 1)),
                    ),
            ),
          );
        },
      ),
    );
  }
}

/// A singer, composer or channel: their songs (more as you scroll, on
/// JioSaavn) and their albums and playlists.
class ArtistPage extends StatefulWidget {
  const ArtistPage({super.key, required this.artist});
  final Json artist;

  @override
  State<ArtistPage> createState() => _ArtistPageState();
}

class _ArtistPageState extends State<ArtistPage> {
  final _songs = <Json>[];
  final _seen = <String>{};
  final _albums = <Json>[];
  final _playlists = <Json>[];
  final _similar = <Json>[];
  String _name = '';
  String _art = '';
  String _about = '';
  int _page = 0;
  bool _loading = false;
  bool _done = false;
  String? _error;

  String get _site => asString(widget.artist['site']);

  @override
  void initState() {
    super.initState();
    _name = asString(widget.artist['title']);
    _art = asString(widget.artist['art']);
    _about = asString(widget.artist['subtitle']);
    fire(_more());
  }

  void _addAll(List<Json> into, Iterable<Json> items) {
    for (final item in items) {
      if (!into.any((x) => x['id'] == item['id'] && x['site'] == item['site'])) into.add(item);
    }
  }

  Future<void> _more() async {
    if (_loading || _done) return;
    _loading = true; // the list already shows a spinner until it's done
    try {
      _page++;
      switch (_site) {
        case 'jiosaavn':
          final data = await jiosaavnArtist(widget.artist, page: _page);
          final songs = asList(data['songs']).map(asJson).where((s) => _seen.add(asString(s['id']))).toList();
          _songs.addAll(songs);
          if (_page == 1) {
            if (asString(data['name']).isNotEmpty) _name = asString(data['name']);
            if (asString(data['art']).isNotEmpty) _art = asString(data['art']);
            final followers = toInt(data['followers']);
            _about = [asString(data['role']), if (followers != null) '${shortCount(followers)} followers']
                .where((s) => s.isNotEmpty)
                .join(' · ');
            _addAll(_playlists, asList(data['playlists']).map(asJson));
            _addAll(_similar, asList(data['similar']).map(asJson));
          }
          _addAll(_albums, [...asList(data['albums']).map(asJson), ...asList(data['singles']).map(asJson)]);
          if (songs.isEmpty) _done = true;
        case 'youtube':
          // A channel: its popular uploads, and its own playlists.
          final id = asString(widget.artist['id']);
          final popular = sources.youtubeSongs(await playlistDetails('UULP${id.substring(2)}'));
          _songs.addAll(popular.where((s) => _seen.add(asString(s['id']))));
          try {
            final info = await channelPlaylists(asString(widget.artist['url']));
            if (asString(info['avatar']).isNotEmpty) _art = asString(info['avatar']);
            _addAll(_playlists, [
              for (final p in asList(info['playlists']).map(asJson))
                if (p['auto'] != true)
                  {
                    'type': 'playlist',
                    'site': 'youtube',
                    'id': asString(p['id']),
                    'url': 'https://www.youtube.com/playlist?list=${asString(p['id'])}',
                    'title': asString(p['title']),
                    'art': asString(p['thumbnail']),
                  },
            ]);
          } catch (_) {
            // the songs are the main thing
          }
          _done = true;
        default:
          _songs.addAll((await sources.resolveLink(asString(widget.artist['url']))).where((s) => _seen.add(asString(s['id']))));
          _done = true;
      }
    } catch (error) {
      if (_page == 1) _error = errorText(error);
      _done = true;
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final app = Paattu.of(context);
    final url = asString(widget.artist['url']);
    final header = PageHeader(
      art: _art,
      title: _name,
      round: true,
      lines: [_about, siteName(_site)],
      actions: [
        ..._songActions(context, _songs),
        if (_site == 'youtube')
          OutlinedButton.icon(
            icon: const Icon(Icons.person_add),
            label: const Text('Follow'),
            onPressed: () async {
              try {
                await app.followProfile(url);
                app.toast('Following $_name: their playlists are in the library');
              } catch (error) {
                app.toast("Couldn't follow: ${errorText(error)}");
              }
            },
          ),
      ],
    );
    final shelves = [
      ResultShelf(title: 'Albums', items: _albums),
      ResultShelf(title: 'Playlists', items: _playlists),
      if (_done) ResultShelf(title: 'Similar', items: _similar),
    ];
    return Scaffold(
      appBar: AppBar(title: Text(_name), actions: [_openButton(url, _site)]),
      body: NowPlayingBuilder(
        builder: (context, playingId) => ListView.builder(
          padding: const EdgeInsets.only(bottom: 24),
          itemCount: 1 + shelves.length + 1 + _songs.length + 1,
          itemBuilder: (context, i) {
            if (i == 0) return header;
            i -= 1;
            if (i < shelves.length) return shelves[i];
            i -= shelves.length;
            if (i == 0) {
              if (_error != null) {
                return EmptyState(icon: Icons.cloud_off, title: "Couldn't load $_name", body: _error);
              }
              return _songs.isEmpty ? const SizedBox.shrink() : const SectionHeader('Songs');
            }
            i -= 1;
            if (i < _songs.length) {
              return TrackTile(
                track: _songs[i],
                playingId: playingId,
                onTap: () => fire(app.player.playTracks(List.of(_songs), start: i)),
              );
            }
            // The end: ask for more as it comes into view.
            if (!_done && !_loading) WidgetsBinding.instance.addPostFrameCallback((_) => fire(_more()));
            return _done
                ? const SizedBox(height: 8)
                : const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()));
          },
        ),
      ),
    );
  }
}
