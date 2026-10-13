// Search JioSaavn, YouTube and SoundCloud at once, or paste a link to a
// song, album or playlist.

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../links.dart';
import '../sources/sources.dart' as sources;
import '../util.dart';
import 'widgets.dart';

class SearchPage extends StatefulWidget {
  const SearchPage({super.key, this.focus});
  final FocusNode? focus;

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> with AutomaticKeepAliveClientMixin {
  final _query = TextEditingController();
  Set<String>? _sites;
  Map<String, List<Json>> _found = {};
  Map<String, String> _errors = {};
  bool _busy = false;
  String _searched = '';
  int _generation = 0;

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final app = Paattu.of(context);
    final q = _query.text.trim();
    if (q.isEmpty) return;
    final generation = ++_generation;
    setState(() {
      _busy = true;
      _searched = q;
    });
    Map<String, List<Json>> found;
    var errors = <String, String>{};
    if (isLink(q)) {
      try {
        found = {'link': await sources.resolveLink(q)};
      } catch (error) {
        found = {'link': <Json>[]};
        errors = {'link': errorText(error)};
      }
    } else {
      final sites = searchSites.where((s) => (_sites ?? app.settings.searchSites.toSet()).contains(s)).toList();
      final results = await sources.search(q, sites: sites.isEmpty ? searchSites : sites);
      found = results.found;
      errors = results.errors;
    }
    if (!mounted || generation != _generation) return;
    setState(() {
      _found = found;
      _errors = errors;
      _busy = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final app = Paattu.of(context);
    final theme = Theme.of(context);
    final chosen = _sites ?? app.settings.searchSites.toSet();
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 12,
        title: TextField(
          controller: _query,
          focusNode: widget.focus,
          textInputAction: TextInputAction.search,
          onSubmitted: (_) => _search(),
          decoration: InputDecoration(
            hintText: 'Songs, films, singers, or a link',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: _query.text.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Clear',
                    icon: const Icon(Icons.close),
                    onPressed: () => setState(() {
                      _query.clear();
                      widget.focus?.requestFocus();
                    }),
                  ),
            filled: true,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(28), borderSide: BorderSide.none),
            contentPadding: const EdgeInsets.symmetric(vertical: 0),
          ),
          onChanged: (_) => setState(() {}),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(52),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Row(
              children: [
                for (final site in searchSites)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      label: Text(siteName(site)),
                      selected: chosen.contains(site),
                      onSelected: (on) {
                        final next = Set.of(chosen);
                        on ? next.add(site) : next.remove(site);
                        if (next.isEmpty) return;
                        setState(() => _sites = next);
                        if (_searched.isNotEmpty && !isLink(_searched)) _search();
                      },
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
      body: _busy && _found.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : _found.isEmpty
              ? const EmptyState(
                  icon: Icons.travel_explore,
                  title: 'Find any song',
                  body: 'JioSaavn streams film songs at 320 kbps, YouTube has nearly everything, and SoundCloud has '
                      'covers and remixes. Paste a link to play a song, album or playlist.',
                )
              : NowPlayingBuilder(
                  builder: (context, playingId) => ListView(
                    padding: const EdgeInsets.only(bottom: 24),
                    children: [
                      if (_busy) const LinearProgressIndicator(),
                      for (final entry in _found.entries) ...[
                        SectionHeader(
                          entry.value.isEmpty ? siteName(entry.key) : '${siteName(entry.key)} · ${entry.value.length}',
                          action: entry.value.isEmpty ? null : _GroupActions(tracks: entry.value, link: entry.key == 'link'),
                        ),
                        if (_errors[entry.key] != null)
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                            child: Text("Couldn't ${entry.key == 'link' ? 'open the link' : 'search ${siteName(entry.key)}'}: ${_errors[entry.key]}",
                                style: TextStyle(color: theme.colorScheme.error)),
                          )
                        else if (entry.value.isEmpty)
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                            child: Text('Nothing found'),
                          ),
                        for (var i = 0; i < entry.value.length; i++)
                          TrackTile(
                            track: entry.value[i],
                            playingId: playingId,
                            showSite: entry.key == 'link',
                            trailing: _QualityTag(track: entry.value[i]),
                            onTap: () => fire(app.player.playTracks(entry.value, start: i)),
                          ),
                      ],
                    ],
                  ),
                ),
    );
  }
}

class _QualityTag extends StatelessWidget {
  const _QualityTag({required this.track});
  final Json track;

  @override
  Widget build(BuildContext context) {
    final label = qualityLabel(track);
    if (label.isEmpty) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(border: Border.all(color: scheme.primary.withValues(alpha: 0.6)), borderRadius: BorderRadius.circular(4)),
      child: Text(label, style: TextStyle(fontSize: 11, color: scheme.primary)),
    );
  }
}

class _GroupActions extends StatelessWidget {
  const _GroupActions({required this.tracks, required this.link});
  final List<Json> tracks;
  final bool link;

  @override
  Widget build(BuildContext context) {
    final app = Paattu.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(tooltip: 'Play all', icon: const Icon(Icons.play_arrow), onPressed: () => fire(app.player.playTracks(tracks))),
        if (link) ...[
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
      ],
    );
  }
}
