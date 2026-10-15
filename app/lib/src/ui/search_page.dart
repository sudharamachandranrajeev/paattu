// Search for songs, albums, singers and playlists where the music comes
// from (YouTube unless Settings says otherwise), with suggestions while
// typing; or paste a link to a song, album or playlist. Each tab grows as
// it's scrolled.

import 'dart:async';

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../links.dart';
import '../search_feed.dart';
import '../sources/sources.dart' as sources;
import '../util.dart';
import 'collection_page.dart';
import 'glass.dart';
import 'widgets.dart';

const _tabs = [
  ('song', 'Songs', Icons.music_note),
  ('album', 'Albums', Icons.album),
  ('artist', 'Artists', Icons.person),
  ('playlist', 'Playlists', Icons.queue_music),
];

class SearchPage extends StatefulWidget {
  const SearchPage({super.key, this.focus});
  final FocusNode? focus;

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> with AutomaticKeepAliveClientMixin, SingleTickerProviderStateMixin {
  final _query = TextEditingController();
  late final FocusNode _focus = widget.focus ?? FocusNode();
  late final TabController _tabController = TabController(length: _tabs.length, vsync: this);
  Map<String, SearchFeed> _feeds = {};
  String _searched = '';

  // A pasted link's songs.
  List<Json>? _linkSongs;
  String? _linkError;
  bool _linkBusy = false;

  // Suggestions for what's being typed.
  Timer? _suggestTimer;
  List<Json> _suggestions = const [];
  String _suggestedFor = '';
  int _suggestGeneration = 0;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _focus.addListener(_refresh);
  }

  @override
  void dispose() {
    _suggestTimer?.cancel();
    _focus.removeListener(_refresh);
    if (widget.focus == null) _focus.dispose();
    for (final feed in _feeds.values) {
      feed.dispose();
    }
    _tabController.dispose();
    _query.dispose();
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  /// Show suggestions while the box has focus and holds something not yet searched.
  bool get _suggesting => _focus.hasFocus && (_query.text.trim() != _searched || _searched.isEmpty);

  void _typed(String text) {
    setState(() {});
    _suggestTimer?.cancel();
    final q = text.trim();
    if (q.isEmpty || isLink(q)) {
      setState(() => _suggestions = const []);
      return;
    }
    _suggestTimer = Timer(const Duration(milliseconds: 220), () async {
      final generation = ++_suggestGeneration;
      final found = await sources.suggest(q);
      if (!mounted || generation != _suggestGeneration) return;
      setState(() {
        _suggestions = found;
        _suggestedFor = q;
      });
    });
  }

  Future<void> _search([String? text]) async {
    final app = Paattu.of(context);
    final q = (text ?? _query.text).trim();
    if (q.isEmpty) return;
    if (text != null) {
      _query.value = TextEditingValue(text: q, selection: TextSelection.collapsed(offset: q.length));
    }
    _suggestTimer?.cancel();
    _suggestGeneration++;
    _focus.unfocus();
    for (final feed in _feeds.values) {
      feed.dispose();
    }
    _feeds = {};
    _linkSongs = null;
    _linkError = null;
    setState(() => _searched = q);
    if (isLink(q)) {
      setState(() => _linkBusy = true);
      try {
        final songs = await sources.resolveLink(q);
        if (mounted && _searched == q) setState(() => _linkSongs = songs);
      } catch (error) {
        if (mounted && _searched == q) setState(() => _linkError = errorText(error));
      } finally {
        if (mounted && _searched == q) setState(() => _linkBusy = false);
      }
      return;
    }
    app.settings.rememberSearch(q);
    final sites = app.settings.musicSites;
    setState(() {
      _feeds = {for (final (kind, _, _) in _tabs) kind: SearchFeed(q, kind, sites)};
    });
    fire(_feeds[_tabs[_tabController.index].$1]!.more());
  }

  Future<void> _openSuggestion(Json item) async {
    final app = Paattu.of(context);
    switch (asString(item['type'])) {
      case 'query':
        await _search(asString(item['title']));
      case 'song':
        _focus.unfocus();
        app.toast('Opening ${asString(item['title'])}…');
        try {
          await app.player.playTrack(await sources.suggestedSong(item));
        } catch (error) {
          app.toast("Couldn't open ${asString(item['title'])}: ${errorText(error)}");
        }
      default:
        _focus.unfocus();
        openResult(context, item);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final app = Paattu.of(context);
    final showTabs = _feeds.isNotEmpty && !_suggesting;
    final scheme = Theme.of(context).colorScheme;
    OutlineInputBorder pill(BorderSide side) => OutlineInputBorder(borderRadius: BorderRadius.circular(28), borderSide: side);
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 12,
        title: TextField(
          controller: _query,
          focusNode: _focus,
          textInputAction: TextInputAction.search,
          onSubmitted: (_) => _search(),
          onChanged: _typed,
          decoration: InputDecoration(
            hintText: 'Songs, films, singers, or a link',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: _query.text.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Clear',
                    icon: const Icon(Icons.close),
                    onPressed: () {
                      _query.clear();
                      _typed('');
                      _focus.requestFocus();
                    },
                  ),
            // The theme's glass field, as a pill.
            border: pill(BorderSide(color: scheme.glassEdge)),
            enabledBorder: pill(BorderSide(color: scheme.glassEdge)),
            focusedBorder: pill(BorderSide(color: scheme.primary, width: 1.5)),
            contentPadding: const EdgeInsets.symmetric(vertical: 0),
          ),
        ),
        bottom: showTabs
            ? PreferredSize(
                preferredSize: const Size.fromHeight(46),
                child: Column(
                  children: [
                    TabBar(
                      controller: _tabController,
                      isScrollable: true,
                      tabAlignment: TabAlignment.start,
                      onTap: (i) => fire(_feeds[_tabs[i].$1]?.more() ?? Future.value()),
                      tabs: [
                        for (final (_, label, icon) in _tabs)
                          Tab(
                            height: 44,
                            child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(icon, size: 18), const SizedBox(width: 6), Text(label)]),
                          ),
                      ],
                    ),
                  ],
                ),
              )
            : null,
      ),
      body: _suggesting
          ? _Suggestions(
              typed: _query.text.trim(),
              suggestions: _query.text.trim() == _suggestedFor ? _suggestions : const [],
              recent: app.settings.recentSearches,
              onSearch: _search,
              onFill: (text) {
                _query.value = TextEditingValue(text: '$text ', selection: TextSelection.collapsed(offset: text.length + 1));
                _typed(_query.text);
              },
              onOpen: _openSuggestion,
              onForget: (q) => setState(() => app.settings.forgetSearch(q)),
            )
          : _searched.isEmpty
              ? const EmptyState(
                  icon: Icons.travel_explore,
                  title: 'Find any song',
                  body: 'Search songs, films, singers and playlists, or paste a link. '
                      'Settings picks where the music comes from.',
                )
              : isLink(_searched)
                  ? _LinkResults(songs: _linkSongs, error: _linkError, busy: _linkBusy)
                  : TabBarView(
                      controller: _tabController,
                      children: [
                        for (final (kind, _, _) in _tabs)
                          if (_feeds[kind] case final feed?) _FeedView(key: ObjectKey(feed), feed: feed) else const SizedBox(),
                      ],
                    ),
    );
  }
}

/// Recent searches (box empty) or suggestions (something typed).
class _Suggestions extends StatelessWidget {
  const _Suggestions({
    required this.typed,
    required this.suggestions,
    required this.recent,
    required this.onSearch,
    required this.onFill,
    required this.onOpen,
    required this.onForget,
  });

  final String typed;
  final List<Json> suggestions;
  final List<String> recent;
  final ValueChanged<String> onSearch;
  final ValueChanged<String> onFill;
  final ValueChanged<Json> onOpen;
  final ValueChanged<String> onForget;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (typed.isEmpty) {
      if (recent.isEmpty) {
        return const EmptyState(
          icon: Icons.travel_explore,
          title: 'Find any song',
          body: 'Start typing: suggestions come from YouTube and JioSaavn as you go.',
        );
      }
      return ListView(
        children: [
          const SectionHeader('Recent searches'),
          for (final q in recent)
            ListTile(
              leading: const Icon(Icons.history),
              title: Text(q, maxLines: 1, overflow: TextOverflow.ellipsis),
              onTap: () => onSearch(q),
              trailing: IconButton(tooltip: 'Forget', icon: const Icon(Icons.close), onPressed: () => onForget(q)),
            ),
        ],
      );
    }
    final matching = recent.where((q) => q.toLowerCase().startsWith(typed.toLowerCase()) && q != typed).take(3);
    return ListView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      children: [
        ListTile(
          leading: Icon(isLink(typed) ? Icons.link : Icons.search, color: theme.colorScheme.primary),
          title: Text(isLink(typed) ? 'Open this link' : 'Search for "$typed"', maxLines: 1, overflow: TextOverflow.ellipsis),
          onTap: () => onSearch(typed),
        ),
        for (final q in matching)
          ListTile(
            leading: const Icon(Icons.history),
            title: Text(q, maxLines: 1, overflow: TextOverflow.ellipsis),
            onTap: () => onSearch(q),
          ),
        for (final item in suggestions)
          if (asString(item['type']) == 'query')
            ListTile(
              leading: const Icon(Icons.search),
              title: Text(asString(item['title']), maxLines: 1, overflow: TextOverflow.ellipsis),
              onTap: () => onOpen(item),
              trailing: IconButton(
                tooltip: 'Fill in',
                icon: const Icon(Icons.north_west),
                onPressed: () => onFill(asString(item['title'])),
              ),
            )
          else
            ListTile(
              leading: Cover(
                url: asString(item['art']),
                size: 44,
                radius: asString(item['type']) == 'artist' ? 22 : 6,
                icon: resultIcon(item),
              ),
              title: Text(asString(item['title']), maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(
                [resultTypeName(item), asString(item['subtitle'])].where((s) => s.isNotEmpty).join(' · '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              onTap: () => onOpen(item),
            ),
      ],
    );
  }
}

/// One tab of results, asking for the next page as its end comes into view.
class _FeedView extends StatelessWidget {
  const _FeedView({super.key, required this.feed});
  final SearchFeed feed;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: feed,
        builder: (context, _) {
          final items = feed.items;
          final errors = feed.errors;
          if (items.isEmpty && feed.done) {
            return EmptyState(
              icon: Icons.search_off,
              title: 'Nothing found',
              body: errors.isEmpty ? null : _errorText(feed, errors, "Couldn't search"),
            );
          }
          final footer = _Footer(feed: feed);
          final note = errors.isEmpty
              ? null
              : Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Text(
                    _errorText(feed, errors, "Couldn't search"),
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                );
          if (feed.kind == 'song') {
            return NowPlayingBuilder(
              builder: (context, playingId) => ListView.builder(
                padding: const EdgeInsets.only(bottom: 24),
                itemCount: items.length + 2,
                itemBuilder: (context, i) {
                  if (i == 0) return _SongsHeader(feed: feed, note: note);
                  if (i == items.length + 1) return footer;
                  final app = Paattu.of(context);
                  return TrackTile(
                    track: items[i - 1],
                    playingId: playingId,
                    // The song, then its radio (or, without auto radio, the songs found after it).
                    onTap: () => fire(app.settings.autoRadio
                        ? app.player.playTrack(items[i - 1])
                        : app.player.playTracks(List.of(items), start: i - 1)),
                  );
                },
              ),
            );
          }
          if (feed.kind == 'artist') {
            return ListView.builder(
              padding: const EdgeInsets.only(bottom: 24),
              itemCount: items.length + 2,
              itemBuilder: (context, i) {
                if (i == 0) return note ?? const SizedBox(height: 8);
                if (i == items.length + 1) return footer;
                return ResultTile(item: items[i - 1]);
              },
            );
          }
          return CustomScrollView(
            slivers: [
              if (note != null) SliverToBoxAdapter(child: note),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                sliver: SliverGrid.builder(
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 190,
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 8,
                    childAspectRatio: 0.74,
                  ),
                  itemCount: items.length,
                  itemBuilder: (context, i) => ResultCard(item: items[i]),
                ),
              ),
              SliverToBoxAdapter(child: footer),
              const SliverToBoxAdapter(child: SizedBox(height: 24)),
            ],
          );
        },
      );
}

/// Why a search failed: naming the site only when several were asked.
String _errorText(SearchFeed feed, Map<String, String> errors, String lead) => feed.pagers.length == 1
    ? '$lead: ${errors.values.first}'
    : errors.entries.map((e) => '$lead ${siteName(e.key)}: ${e.value}').join('\n');

class _SongsHeader extends StatelessWidget {
  const _SongsHeader({required this.feed, this.note});
  final SearchFeed feed;
  final Widget? note;

  @override
  Widget build(BuildContext context) {
    final app = Paattu.of(context);
    final items = feed.items;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ?note,
        if (items.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    feed.done ? plural(items.length, 'song') : '${items.length}+ songs',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                TextButton.icon(
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Play all'),
                  onPressed: () => fire(app.player.playTracks(List.of(items))),
                ),
                TextButton.icon(
                  icon: const Icon(Icons.shuffle),
                  label: const Text('Shuffle'),
                  onPressed: () => fire(app.player.playTracks(List.of(items), shuffled: true)),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// The end of a tab: asks for more when it's built (scrolled into view).
class _Footer extends StatelessWidget {
  const _Footer({required this.feed});
  final SearchFeed feed;

  @override
  Widget build(BuildContext context) {
    if (!feed.done && !feed.loading) {
      WidgetsBinding.instance.addPostFrameCallback((_) => fire(feed.more()));
    }
    if (feed.done) {
      return feed.items.isEmpty
          ? const SizedBox.shrink()
          : Padding(
              padding: const EdgeInsets.all(20),
              child: Text("That's everything",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
            );
    }
    return const Padding(
      padding: EdgeInsets.all(20),
      child: Center(child: SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 3))),
    );
  }
}

class _LinkResults extends StatelessWidget {
  const _LinkResults({required this.songs, required this.error, required this.busy});
  final List<Json>? songs;
  final String? error;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final app = Paattu.of(context);
    final theme = Theme.of(context);
    if (busy) return const Center(child: CircularProgressIndicator());
    if (error != null) {
      return EmptyState(icon: Icons.link_off, title: "Couldn't open the link", body: error);
    }
    final tracks = songs ?? const <Json>[];
    if (tracks.isEmpty) return const EmptyState(icon: Icons.link_off, title: 'No songs at that link');
    return NowPlayingBuilder(
      builder: (context, playingId) => ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          SectionHeader(
            plural(tracks.length, 'song'),
            action: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(tooltip: 'Play all', icon: const Icon(Icons.play_arrow), onPressed: () => fire(app.player.playTracks(tracks))),
                IconButton(
                  tooltip: 'Save all to the library',
                  icon: const Icon(Icons.library_add),
                  onPressed: () {
                    final added = app.library.addTracks(app.library.savedSongs()['id'] as String, tracks);
                    app.library.changed();
                    app.toast(added.isEmpty ? 'Already saved' : 'Saved ${plural(added.length, 'song')}');
                  },
                ),
                IconButton(
                  tooltip: 'Add all to a playlist',
                  icon: const Icon(Icons.playlist_add),
                  onPressed: () async {
                    final target = await pickPlaylist(context);
                    if (target != null) app.addToPlaylist(target, tracks);
                  },
                ),
              ],
            ),
          ),
          for (var i = 0; i < tracks.length; i++)
            TrackTile(
              track: tracks[i],
              playingId: playingId,
              trailing: Text(qualityLabel(tracks[i]), style: theme.textTheme.bodySmall),
              onTap: () => fire(app.player.playTracks(tracks, start: i)),
            ),
        ],
      ),
    );
  }
}
