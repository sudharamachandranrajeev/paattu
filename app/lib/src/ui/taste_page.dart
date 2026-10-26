// What the radio learned: the singers, composers and films ranked by how you
// play them (history.dart's tasteRanking). Songs played to the end lift them,
// skips and songs taken out of the radio's Up next drop them, and ones taken
// out again and again are left out of the radio until let back in.

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../history.dart';
import '../util.dart';
import 'glass.dart';
import 'widgets.dart';

/// How many of each kind are shown.
const _shown = 30;

class TastePage extends StatelessWidget {
  const TastePage({super.key});

  @override
  Widget build(BuildContext context) {
    final history = Paattu.of(context).history;
    return Scaffold(
      appBar: AppBar(title: const Text('What the radio learned')),
      body: ListenableBuilder(
        listenable: history,
        builder: (context, _) {
          final ranks = tasteRanking(history.signals, history.track, now: DateTime.now());
          if (ranks.isEmpty) {
            return const EmptyState(
              icon: Icons.radio,
              title: 'Nothing learned yet',
              body: 'Play songs to the end and the radio plays more like them. Skip a song or take it out '
                  "of the radio's Up next and it plays less like it.",
            );
          }
          final left = [for (final r in ranks) if (r.shunned) r];
          final more = [for (final r in ranks) if (!r.shunned && r.score > 0) r].take(_shown).toList();
          final less = [for (final r in ranks.reversed) if (!r.shunned && r.score <= 0) r].take(_shown).toList();
          return ListView(
            padding: const EdgeInsets.only(bottom: 32),
            children: [
              if (left.isNotEmpty) ...[
                const SectionHeader('Left out of the radio'),
                GlassGroup(children: [for (final r in left) _RankTile(rank: r, history: history)]),
              ],
              if (more.isNotEmpty) ...[
                const SectionHeader('Plays more of'),
                GlassGroup(children: [for (final r in more) _RankTile(rank: r, history: history)]),
              ],
              if (less.isNotEmpty) ...[
                const SectionHeader('Plays less of'),
                GlassGroup(children: [for (final r in less) _RankTile(rank: r, history: history)]),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _RankTile extends StatelessWidget {
  const _RankTile({required this.rank, required this.history});
  final TasteRank rank;
  final History history;

  @override
  Widget build(BuildContext context) {
    final film = rank.feature.startsWith('film:');
    final name = rank.feature.substring(rank.feature.indexOf(':') + 1);
    final what = film ? 'Film' : 'Singer or composer';
    return ListTile(
      leading: Icon(film ? Icons.movie_outlined : Icons.person_outline),
      title: Text(name.split(' ').map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1)).join(' ')),
      subtitle: Text([
        what,
        'score ${rank.score.toStringAsFixed(1)}',
        if (rank.removed > 0) 'taken out ${plural(rank.removed, 'time')}',
      ].join(' · ')),
      trailing: rank.shunned || rank.removed > 0
          ? TextButton(
              onPressed: () {
                final count = history.forgive(rank.feature);
                Paattu.of(context).toast('The radio forgot ${plural(count, 'song')} taken out');
              },
              child: Text(rank.shunned ? 'Let back in' : 'Forget'),
            )
          : null,
    );
  }
}
