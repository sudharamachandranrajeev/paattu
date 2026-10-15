// Playlists made for you (made.dart) and playlists made from a description:
// the cards on Home, and a page of their songs, ready to play or keep as a
// playlist of your own.

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../library.dart';
import '../made.dart';
import '../track.dart';
import '../util.dart';
import 'glass.dart';
import 'widgets.dart';

/// Daily, weekly and monthly, then "Describe a playlist", as bright tiles.
class MadeForYouShelf extends StatelessWidget {
  const MadeForYouShelf({super.key});

  @override
  Widget build(BuildContext context) {
    final app = Paattu.of(context);
    return ListenableBuilder(
      listenable: app.history,
      builder: (context, _) => SizedBox(
        height: 180,
        child: ListView.separated(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          scrollDirection: Axis.horizontal,
          itemCount: madeKinds.length + 1,
          separatorBuilder: (_, _) => const SizedBox(width: 12),
          itemBuilder: (context, i) {
            if (i == madeKinds.length) {
              return _MadeTile(
                index: i,
                icon: Icons.auto_awesome,
                title: 'Describe a playlist',
                detail: 'Films, singers, moods…',
                onTap: () => describeAPlaylist(context),
              );
            }
            final kind = madeKinds[i];
            final songs = keptMade(app.history.made(kind), periodKey(kind, DateTime.now()));
            return _MadeTile(
              index: i,
              icon: switch (kind) {
                'daily' => Icons.wb_sunny_outlined,
                'weekly' => Icons.explore_outlined,
                _ => Icons.emoji_events_outlined,
              },
              title: madeTitle(kind),
              detail: songs != null ? plural(songs.length, 'song') : 'Made when you open it',
              art: songs?.map(trackArt).nonNulls.firstOrNull ?? '',
              onTap: () => openMade(context, kind),
            );
          },
        ),
      ),
    );
  }
}

class _MadeTile extends StatelessWidget {
  const _MadeTile({
    required this.index,
    required this.icon,
    required this.title,
    required this.detail,
    required this.onTap,
    this.art = '',
  });
  final int index;
  final IconData icon;
  final String title;
  final String detail;
  final String art;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const white = Colors.white;
    return Semantics(
      button: true,
      label: '$title: $detail',
      excludeSemantics: true,
      child: Material(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        clipBehavior: Clip.antiAlias,
        child: Ink(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: tileColours(theme.colorScheme, index + 1),
            ),
          ),
          child: InkWell(
            onTap: onTap,
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
                        Icon(icon, color: white, size: 30),
                        const Spacer(),
                        Text(title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleMedium?.copyWith(color: white, fontWeight: FontWeight.w700, height: 1.15)),
                        const SizedBox(height: 2),
                        Text(detail,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelSmall?.copyWith(color: white.withValues(alpha: 0.85))),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

void openMade(BuildContext context, String kind) {
  final app = Paattu.of(context);
  Navigator.of(context).push(MaterialPageRoute<void>(
    builder: (_) => MadePage(
      title: madeTitle(kind),
      blurb: madeBlurb(kind),
      icon: Icons.auto_awesome,
      name: '${madeTitle(kind)} ${periodKey(kind, DateTime.now())}',
      load: (refresh) => app.made.playlist(kind, refresh: refresh),
    ),
  ));
}

const _examples = [
  'Ilaiyaraaja melodies',
  'Rain songs',
  'A. R. Rahman 90s hits',
  'Premam, Bangalore Days and Ustad Hotel',
  'K. S. Chithra and Yesudas duets',
  'Kuthu songs for a road trip',
];

/// Ask what the playlist should have, then make it.
Future<void> describeAPlaylist(BuildContext context) async {
  final controller = TextEditingController();
  final description = await showDialog<String>(
    context: context,
    builder: (dialog) {
      void done() => Navigator.pop(dialog, controller.text.trim().isEmpty ? null : controller.text.trim());
      return AlertDialog(
        title: const Text('Describe a playlist'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Name films, singers, composers, moods or eras. Separate them with commas.'),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                autofocus: true,
                minLines: 1,
                maxLines: 3,
                textInputAction: TextInputAction.done,
                decoration: const InputDecoration(hintText: 'Ilaiyaraaja, rain songs, Premam'),
                onSubmitted: (_) => done(),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final example in _examples)
                    ActionChip(label: Text(example), onPressed: () => controller.text = example),
                ],
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialog), child: const Text('Cancel')),
          FilledButton(onPressed: done, child: const Text('Make it')),
        ],
      );
    },
  ).whenComplete(controller.dispose);
  if (description == null || !context.mounted) return;
  // The songs found for it are made once; refreshing searches again.
  await Navigator.of(context).push(MaterialPageRoute<void>(
    builder: (_) => MadePage(
      title: _capitalised(description),
      blurb: 'Made from your description',
      icon: Icons.auto_awesome,
      name: _capitalised(description),
      load: (_) => describePlaylist(description),
    ),
  ));
}

String _capitalised(String text) => text.isEmpty ? text : text[0].toUpperCase() + text.substring(1);

class MadePage extends StatefulWidget {
  const MadePage({
    super.key,
    required this.title,
    required this.blurb,
    required this.load,
    required this.name,
    this.icon = Icons.auto_awesome,
  });

  final String title;
  final String blurb;

  /// The songs (new ones with refresh).
  final Future<List<Json>> Function(bool refresh) load;

  /// What a saved copy is called.
  final String name;
  final IconData icon;

  @override
  State<MadePage> createState() => _MadePageState();
}

class _MadePageState extends State<MadePage> {
  late Future<List<Json>> _songs = widget.load(false);

  void _refresh() => setState(() => _songs = widget.load(true));

  Future<void> _save(List<Json> songs) async {
    final app = Paattu.of(context);
    final name = await askText(context, title: 'Save as a playlist', label: 'Name', initial: widget.name, action: 'Save');
    if (name == null) return;
    try {
      final playlist = app.library.createPlaylist(name);
      app.library.addTracks(asString(playlist['id']), songs);
      app.library.changed();
      app.toast('Saved ${playlist['title']}: ${plural(songs.length, 'song')}');
    } on LibraryException catch (error) {
      app.toast(error.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = Paattu.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [IconButton(tooltip: 'Make it again', icon: const Icon(Icons.refresh), onPressed: _refresh)],
      ),
      body: FutureBuilder<List<Json>>(
        future: _songs,
        builder: (context, snapshot) {
          final songs = snapshot.data ?? const <Json>[];
          final header = PageHeader(
            art: songs.map(trackArt).nonNulls.firstOrNull ?? '',
            title: widget.title,
            icon: widget.icon,
            lines: [widget.blurb, if (snapshot.hasData) plural(songs.length, 'song')],
            actions: [
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
                label: const Text('Save as playlist'),
                onPressed: songs.isEmpty ? null : () => _save(songs),
              ),
            ],
          );
          if (snapshot.connectionState != ConnectionState.done) {
            return ListView(children: [
              header,
              const Padding(
                padding: EdgeInsets.all(32),
                child: Column(children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 12),
                  Text('Picking songs…'),
                ]),
              ),
            ]);
          }
          if (snapshot.hasError) {
            return ListView(children: [
              header,
              EmptyState(
                icon: Icons.cloud_off,
                title: "Couldn't make it",
                body: _capitalised(errorText(snapshot.error!)),
                action: FilledButton(onPressed: _refresh, child: const Text('Try again')),
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
                      onTap: () => fire(app.player.playTracks(songs, start: i - 1)),
                    ),
            ),
          );
        },
      ),
    );
  }
}
