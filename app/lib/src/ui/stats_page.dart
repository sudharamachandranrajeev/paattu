// Your music in numbers (stats.dart): how much you listened over the week,
// month, three months or all of it, the titles your listening earned, what
// you played most and when, and how your taste sits beside everyone else's:
// this week's charts in your languages, or what the whole world plays on
// ListenBrainz.

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../charts.dart' show pickedChartLanguages;
import '../history.dart';
import '../library.dart' show favouritesId;
import '../listenbrainz.dart' show listenBrainzApi;
import '../sources/http.dart' show getJson;
import '../stats.dart';
import '../util.dart';
import 'glass.dart';
import 'widgets.dart';

/// The periods to choose from: days, or null for all of it.
const _periods = <(String, int?)>[('Week', 7), ('Month', 30), ('3 months', 90), ('All time', null)];

class StatsPage extends StatefulWidget {
  const StatsPage({super.key});

  @override
  State<StatsPage> createState() => _StatsPageState();
}

class _StatsPageState extends State<StatsPage> {
  int? _days = 30;

  @override
  Widget build(BuildContext context) {
    final app = Paattu.of(context);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Your music in numbers')),
      body: ListenableBuilder(
        listenable: app.history,
        builder: (context, _) {
          final history = app.history;
          final s = musicStats(
            history.signals,
            history.track,
            now: DateTime.now(),
            days: _days,
            favourites: app.library.playlistTracks(favouritesId),
          );
          final titles = quirks(s);
          return ListView(
            padding: const EdgeInsets.only(bottom: 32),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: Wrap(
                  spacing: 8,
                  children: [
                    for (final (label, days) in _periods)
                      ChoiceChip(
                        label: Text(label),
                        selected: _days == days,
                        onSelected: (_) => setState(() => _days = days),
                      ),
                  ],
                ),
              ),
              if (s.plays + s.skips == 0)
                const EmptyState(
                  icon: Icons.insights,
                  title: 'Nothing played yet',
                  body: 'Play a few songs and your numbers show up here.',
                )
              else ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _Number(value: '${s.plays}', label: 'plays'),
                      _Number(value: _listened(s.minutes), label: 'listened'),
                      _Number(value: '${s.songs}', label: 'songs'),
                      _Number(value: '${s.artists}', label: 'singers & composers'),
                      _Number(value: '${s.skips}', label: 'skips'),
                      _Number(value: '${s.streak}', label: s.streak == 1 ? 'day streak' : 'days in a row'),
                    ],
                  ),
                ),
                if (titles.isNotEmpty) ...[
                  const SectionHeader('Titles you earned'),
                  GlassGroup(
                    children: [
                      for (final (title, why) in titles)
                        ListTile(
                          leading: Icon(Icons.emoji_events_outlined, color: theme.colorScheme.primary),
                          title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: Text(why),
                        ),
                    ],
                  ),
                ],
                for (final (heading, rows) in [
                  ('On repeat', s.topSongs),
                  ('Your singers & composers', s.topArtists),
                  ('Films you keep going back to', s.topFilms),
                ])
                  if (rows.isNotEmpty) ...[
                    SectionHeader(heading),
                    GlassGroup(children: [for (final (i, row) in rows.indexed) _Ranked(place: i + 1, row: row)]),
                  ],
                const SectionHeader('When you listen'),
                _Hours(hours: s.hours),
                if (s.themes.isNotEmpty) ...[
                  const SectionHeader('What your songs are about'),
                  _Shares(counts: s.themes, whole: s.plays, label: (t) => themeTitles[t]?.$2 ?? t),
                ],
                if (s.languages.isNotEmpty) ...[
                  const SectionHeader('Languages'),
                  _Shares(counts: s.languages, whole: s.plays, label: (l) => l),
                ],
              ],
              const SectionHeader('You and everyone else'),
              const _Community(),
            ],
          );
        },
      ),
    );
  }

  static String _listened(int minutes) =>
      minutes < 120 ? '$minutes min' : '${(minutes / 60).toStringAsFixed(minutes < 600 ? 1 : 0)} h';
}

class _Number extends StatelessWidget {
  const _Number({required this.value, required this.label});
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: 112,
      child: Glass(
        radius: 18,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value, style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
            Text(label, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}

class _Ranked extends StatelessWidget {
  const _Ranked({required this.place, required this.row});
  final int place;
  final (String, int) row;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      leading: Text('$place',
          style: theme.textTheme.titleLarge?.copyWith(color: theme.colorScheme.primary, fontWeight: FontWeight.w800)),
      title: Text(row.$1, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: Text(plural(row.$2, 'play'), style: theme.textTheme.bodySmall),
    );
  }
}

/// Plays by hour of the day, as 24 bars.
class _Hours extends StatelessWidget {
  const _Hours({required this.hours});
  final List<int> hours;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final most = hours.fold(1, (a, b) => a > b ? a : b);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Glass(
        padding: const EdgeInsets.fromLTRB(14, 16, 14, 10),
        child: Column(
          children: [
            SizedBox(
              height: 80,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (final n in hours)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 1.5),
                        child: FractionallySizedBox(
                          heightFactor: n == 0 ? 0.03 : 0.08 + 0.92 * n / most,
                          alignment: Alignment.bottomCenter,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primary.withValues(alpha: n == 0 ? 0.25 : 0.85),
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                for (final label in ['12 AM', '6 AM', '12 PM', '6 PM', '11 PM'])
                  Text(label, style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Each of [counts] as a share of [whole], biggest first.
class _Shares extends StatelessWidget {
  const _Shares({required this.counts, required this.whole, required this.label});
  final Map<String, int> counts;
  final int whole;
  final String Function(String key) label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rows = counts.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return GlassGroup(
      children: [
        for (final MapEntry(:key, :value) in rows)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: Text(label(key))),
                    Text('${(value * 100 / whole).round()}%', style: theme.textTheme.labelMedium),
                  ],
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(value: value / whole, minHeight: 6),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Your taste beside everyone else's: this week's top charts in your
/// languages (the songs you played too are marked), or the artists the
/// whole world plays most on ListenBrainz this month (and which of them you
/// play too).
class _Community extends StatefulWidget {
  const _Community();

  @override
  State<_Community> createState() => _CommunityState();
}

class _CommunityState extends State<_Community> {
  bool _world = false;
  Future<_Compared>? _compared;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _compared ??= _compare();
  }

  void _pick(bool world) => setState(() {
        _world = world;
        _compared = _compare();
      });

  Future<_Compared> _compare() async {
    final app = Paattu.of(context);
    final plays = app.history.plays.where(counted).toList();
    if (_world) {
      final mine = <String, int>{};
      for (final play in plays) {
        for (final credit in asStrings(app.history.track(asString(play['id']))?['credits'])) {
          final name = credit.trim().toLowerCase();
          if (name.isNotEmpty) mine[name] = (mine[name] ?? 0) + 1;
        }
      }
      final answer = asJson(await getJson(Uri.parse('$listenBrainzApi/1/stats/sitewide/artists?count=50&range=month')));
      final rows = [
        for (final a in asList(asJson(answer['payload'])['artists']).map(asJson))
          (
            name: asString(a['artist_name']),
            detail: '${plural(toInt(a['listen_count']) ?? 0, 'listen')} worldwide',
            yours: mine.containsKey(asString(a['artist_name']).trim().toLowerCase()),
          ),
      ];
      return (rows: rows, note: 'The most played artists on ListenBrainz this month');
    }
    final played = {for (final p in plays) songIdentity(app.history.track(asString(p['id'])) ?? {'id': p['id']})};
    final rows = <({String name, String detail, bool yours})>[];
    for (final language in pickedChartLanguages(app.settings.chartLanguages)) {
      for (final song in (await app.charts.chart('top', language)).take(20)) {
        rows.add((
          name: asString(song['title']),
          detail: '$language · ${asString(song['movie'])}',
          yours: played.contains(songIdentity(song)),
        ));
      }
    }
    final shared = rows.where((r) => r.yours).length;
    final mainstream = rows.isEmpty ? 0 : (shared * 100 / rows.length).round();
    return (
      rows: rows,
      note: "This week's top songs in your languages. You've played $shared of them: "
          '${mainstream >= 40 ? 'you have your finger on the pulse' : mainstream >= 15 ? 'a bit of both worlds' : 'you march to your own beat'}'
          ' ($mainstream% mainstream)',
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Wrap(
            spacing: 8,
            children: [
              ChoiceChip(label: const Text('Your languages'), selected: !_world, onSelected: (_) => _pick(false)),
              ChoiceChip(label: const Text('The whole world'), selected: _world, onSelected: (_) => _pick(true)),
            ],
          ),
        ),
        FutureBuilder<_Compared>(
          future: _compared,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Padding(
                padding: const EdgeInsets.all(16),
                child: Text("Couldn't fetch what everyone plays (${errorText(snapshot.error!)})"),
              );
            }
            final compared = snapshot.data;
            if (compared == null) {
              return const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()));
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Text(compared.note,
                      style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                ),
                GlassGroup(
                  children: [
                    for (final (i, r) in compared.rows.indexed)
                      ListTile(
                        dense: true,
                        leading: Text('${i + 1}', style: theme.textTheme.labelLarge),
                        title: Text(r.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text(r.detail, maxLines: 1, overflow: TextOverflow.ellipsis),
                        trailing: r.yours
                            ? Chip(
                                label: const Text('You too'),
                                visualDensity: VisualDensity.compact,
                                backgroundColor: theme.colorScheme.primaryContainer,
                              )
                            : null,
                      ),
                  ],
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}

typedef _Compared = ({List<({String name, String detail, bool yours})> rows, String note});
