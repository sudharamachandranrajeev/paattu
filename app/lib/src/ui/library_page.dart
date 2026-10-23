// Library: your playlists, saved YouTube playlists and followed profiles,
// and adding more from YouTube.

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_state.dart';
import '../library.dart';
import '../offline.dart';
import '../util.dart';
import 'glass.dart';
import 'home_page.dart';
import 'offline_page.dart';
import 'playlist_page.dart';
import 'widgets.dart';

/// Ask for a name and make a playlist. Returns its id.
Future<String?> newPlaylist(BuildContext context) async {
  final app = Paattu.of(context);
  final name = await askText(context, title: 'New playlist', label: 'Name', action: 'Create');
  if (name == null) return null;
  try {
    final p = app.library.createPlaylist(name);
    app.library.changed();
    return asString(p['id']);
  } on LibraryException catch (error) {
    app.toast(error.message);
    return null;
  }
}

class LibraryPage extends StatelessWidget {
  const LibraryPage({super.key});

  @override
  Widget build(BuildContext context) => DefaultTabController(
        length: 2,
        child: LibraryBuilder(builder: (context, app) {
          final library = app.library;
          final own = library.ownPlaylists();
          final saved = [for (final lang in library.languages()) ...library.shelves()[lang] ?? const <Json>[]];
          final users = library.sortedUsers();
          return Scaffold(
            appBar: AppBar(
              title: const Text('Library'),
              bottom: const TabBar(tabs: [Tab(text: 'Playlists'), Tab(text: 'Profiles')]),
            ),
            body: TabBarView(
              children: [
                ListView(
                  padding: const EdgeInsets.only(bottom: 96),
                  children: [
                    const SectionHeader('Yours'),
                    for (final p in own) _PlaylistRow(playlist: p),
                    if (!own.any((p) => p['id'] == favouritesId))
                      PillTile(
                        leading: const Cover(icon: Icons.favorite, size: 50, radius: 25),
                        title: 'Favourites',
                        subtitle: 'Heart a song to put it here',
                        onTap: () {
                          library.favourites();
                          library.changed();
                          openPlaylist(context, favouritesId);
                        },
                      ),
                    const _OfflineRow(),
                    const SectionHeader('Saved from YouTube'),
                    if (saved.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 16),
                        child: Text('Add a YouTube profile or playlist, and save the playlists you like.'),
                      ),
                    for (final p in saved) _PlaylistRow(playlist: p),
                  ],
                ),
                users.isEmpty
                    ? EmptyState(
                        icon: Icons.person_add_alt,
                        title: 'No profiles yet',
                        body: "Follow a YouTube channel (a music label, a singer, a fan's playlists) to pick from its playlists.",
                        action: FilledButton.icon(
                          onPressed: () => showAddFromYouTube(context),
                          icon: const Icon(Icons.add_link),
                          label: const Text('Add from YouTube'),
                        ),
                      )
                    : ListView(
                        padding: const EdgeInsets.only(bottom: 96),
                        children: [
                          for (final u in users)
                            PillTile(
                              leading: Cover(url: asString(u['avatar']), icon: Icons.person, size: 50, radius: 25),
                              title: asString(u['name']),
                              subtitle: [
                                asString(u['handle']),
                                asString(u['language']),
                                plural(asList(u['playlists']).length, 'playlist'),
                              ].where((s) => s.isNotEmpty).join(' · '),
                              trailing: const [Icon(Icons.chevron_right), SizedBox(width: 10)],
                              onTap: () => openProfile(context, asString(u['id'])),
                            ),
                        ],
                      ),
              ],
            ),
          );
        }),
      );
}

class _PlaylistRow extends StatelessWidget {
  const _PlaylistRow({required this.playlist});
  final Json playlist;

  @override
  Widget build(BuildContext context) {
    final id = asString(playlist['id']);
    final count = playlist['tracks'] is List ? plural(asList(playlist['tracks']).length, 'song') : 'Not loaded yet';
    final owner = playlist['local'] == true ? '' : asString(playlist['ownerName']);
    return PillTile(
      leading: Cover(
        url: asString(playlist['thumbnail']),
        size: 50,
        radius: 25,
        icon: id == favouritesId
            ? Icons.favorite
            : id == savedId
                ? Icons.library_music
                : Icons.queue_music,
      ),
      title: asString(playlist['title']),
      subtitle: [owner, count].where((s) => s.isNotEmpty).join(' · '),
      trailing: const [Icon(Icons.chevron_right), SizedBox(width: 10)],
      onTap: () => openPlaylist(context, id),
    );
  }
}

/// The songs kept on this device, and how much room they take.
class _OfflineRow extends StatelessWidget {
  const _OfflineRow();

  @override
  Widget build(BuildContext context) {
    final offline = Paattu.of(context).offline;
    return ListenableBuilder(
      listenable: offline,
      builder: (context, _) => PillTile(
        leading: const Cover(icon: Icons.download_for_offline, size: 50, radius: 25),
        title: 'On this device',
        subtitle: offline.count == 0
            ? 'Songs you listen to, kept for no internet'
            : '${plural(offline.count, 'song')} · ${formatBytes(offline.totalBytes)}',
        trailing: const [Icon(Icons.chevron_right), SizedBox(width: 10)],
        onTap: () =>
            Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const OfflinePage())),
      ),
    );
  }
}

void openProfile(BuildContext context, String userId) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ProfilePage(userId: userId)));

/// Paste a YouTube profile or playlist link and add it.
Future<void> showAddFromYouTube(BuildContext context) => showDialog<void>(
      context: context,
      builder: (_) => const _AddFromYouTube(),
    );

class _AddFromYouTube extends StatefulWidget {
  const _AddFromYouTube();

  @override
  State<_AddFromYouTube> createState() => _AddFromYouTubeState();
}

class _AddFromYouTubeState extends State<_AddFromYouTube> {
  final _link = TextEditingController();
  String _language = '';
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _link.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final app = Paattu.of(context);
    final navigator = Navigator.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final (kind, ref) = app.classify(_link.text);
      if (kind == 'playlist') {
        final p = await app.addYouTubePlaylist(ref, language: _language);
        app.toast('Added ${p['title']} (${plural(asList(p['tracks']).length, 'song')})');
        navigator.pop();
        navigator.push(MaterialPageRoute<void>(builder: (_) => PlaylistPage(playlistId: asString(p['id']))));
      } else {
        final user = await app.followProfile(ref, language: _language);
        app.toast('Following ${user['name']}. Save the playlists you like');
        navigator.pop();
        navigator.push(MaterialPageRoute<void>(builder: (_) => ProfilePage(userId: asString(user['id']))));
      }
    } catch (error) {
      if (mounted) setState(() => _error = errorText(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Add from YouTube'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _link,
                autofocus: true,
                enabled: !_busy,
                decoration: InputDecoration(
                  labelText: 'Profile or playlist',
                  hintText: '@saregamamalayalam or a playlist link',
                  errorText: _error,
                  errorMaxLines: 3,
                ),
                onSubmitted: (_) => _busy ? null : _add(),
              ),
              const SizedBox(height: 16),
              const Text('Language'),
              const SizedBox(height: 6),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: '', label: Text('Guess')),
                  ButtonSegment(value: 'Malayalam', label: Text('Malayalam')),
                  ButtonSegment(value: 'Tamil', label: Text('Tamil')),
                ],
                selected: {_language},
                showSelectedIcon: false,
                onSelectionChanged: _busy ? null : (picked) => setState(() => _language = picked.first),
              ),
              if (_busy) const Padding(padding: EdgeInsets.only(top: 16), child: LinearProgressIndicator()),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: _busy ? null : () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: _busy ? null : _add, child: const Text('Add')),
        ],
      );
}

/// A followed profile: its playlists, to save to the shelves or open.
class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key, required this.userId});
  final String userId;

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  bool _syncing = false;

  Future<void> _sync(AppState app, Json user) async {
    setState(() => _syncing = true);
    await attempt(app, () => app.followProfile(asString(user['url']).isNotEmpty ? asString(user['url']) : widget.userId,
        language: asString(user['language'])), failure: "Couldn't refresh");
    if (mounted) setState(() => _syncing = false);
  }

  @override
  Widget build(BuildContext context) => LibraryBuilder(builder: (context, app) {
        final library = app.library;
        final user = library.user(widget.userId);
        if (user == null) {
          return Scaffold(appBar: AppBar(), body: const EmptyState(icon: Icons.person_off, title: 'Not following this profile'));
        }
        final playlists = library.userPlaylists(widget.userId);
        final theme = Theme.of(context);
        return Scaffold(
          appBar: AppBar(
            actions: [
              IconButton(
                tooltip: 'Refresh from YouTube',
                icon: const Icon(Icons.refresh),
                onPressed: _syncing ? null : () => _sync(app, user),
              ),
              PopupMenuButton<String>(
                onSelected: (choice) async {
                  if (choice == 'open') {
                    fire(launchUrl(Uri.parse(asString(user['url'])), mode: LaunchMode.externalApplication));
                  } else if (choice == 'unfollow') {
                    final ok = await confirm(context,
                        title: 'Unfollow ${user['name']}?', body: 'Playlists you saved from it stay.', action: 'Unfollow');
                    if (!ok || !context.mounted) return;
                    library.removeUser(widget.userId);
                    library.changed();
                    Navigator.pop(context);
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'open', child: Text('Open on YouTube')),
                  PopupMenuItem(value: 'unfollow', child: Text('Unfollow')),
                ],
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.only(bottom: 24),
            children: [
              if (_syncing) const LinearProgressIndicator(),
              _ProfileHeader(user: user, playlists: playlists),
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: Text('Save playlists to put them on your shelves and in mixes.'),
              ),
              for (final p in playlists)
                PillTile(
                  leading: Cover(url: asString(p['thumbnail']), size: 50, radius: 25),
                  title: asString(p['title']),
                  subtitle: p['tracks'] is List ? plural(asList(p['tracks']).length, 'song') : 'Not loaded yet',
                  onTap: () => openPlaylist(context, asString(p['id'])),
                  trailing: [
                    IconButton(
                      tooltip: p['saved'] == true ? 'Take off the shelves' : 'Save',
                      icon: Icon(p['saved'] == true ? Icons.bookmark : Icons.bookmark_add_outlined,
                          color: p['saved'] == true ? theme.colorScheme.primary : null),
                      onPressed: () {
                        final id = asString(p['id']);
                        final saving = p['saved'] != true;
                        library.setSaved(id, saving);
                        library.changed();
                        if (saving && !library.fetched(id)) fire(attempt(app, () => app.fetchPlaylist(id)));
                      },
                    ),
                  ],
                ),
            ],
          ),
        );
      });
}

/// A profile's picture glowing in the theme's colour, its name, and its
/// numbers in a glass strip.
class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({required this.user, required this.playlists});
  final Json user;
  final List<Json> playlists;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final followers = toInt(user['followers']);
    final stats = [
      if (followers != null) (shortCount(followers), 'subscribers'),
      (playlists.length.toString(), 'playlists'),
      (playlists.where((p) => p['saved'] == true).length.toString(), 'saved'),
    ];
    final muted = theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(colors: tileColours(scheme, 0)),
              boxShadow: [BoxShadow(color: scheme.primary.withValues(alpha: 0.45), blurRadius: 36)],
            ),
            child: Cover(url: asString(user['avatar']), icon: Icons.person, size: 104, radius: 52),
          ),
          const SizedBox(height: 14),
          Text(asString(user['name']),
              textAlign: TextAlign.center, style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w600)),
          if (asString(user['handle']).isNotEmpty) Text(asString(user['handle']), style: muted),
          const SizedBox(height: 16),
          Glass(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: IntrinsicHeight(
              child: Row(
                children: [
                  for (final (i, (number, label)) in stats.indexed) ...[
                    if (i > 0) VerticalDivider(width: 1, color: scheme.glassEdge),
                    Expanded(
                      child: Column(
                        children: [
                          Text(number, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600)),
                          Text(label, style: muted),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
