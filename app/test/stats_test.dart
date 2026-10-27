// Your music in numbers, as on the desktop (tests/stats_cases.json, shared
// with paattu/stats.py).

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:paattu/src/stats.dart';
import 'package:paattu/src/util.dart';

void main() {
  final cases = asJson(jsonDecode(File('../tests/stats_cases.json').readAsStringSync()));
  final tracks = asJson(cases['tracks']);
  final plays = asList(cases['plays']).map(asJson).toList();
  final now = DateTime.fromMillisecondsSinceEpoch(toInt(cases['now'])! * 1000);
  Json? track(String id) => tracks[id] is Map ? asJson(tracks[id]) : null;

  test('the numbers and the titles they earn', () {
    for (final run in asList(cases['runs']).map(asJson)) {
      final got = musicStats(
        plays,
        track,
        now: now,
        days: toInt(run['days']),
        favourites: asList(cases['favourites']).map(asJson).toList(),
        hourOf: (at) => at ~/ 3600 % 24,
      );
      expect(jsonDecode(jsonEncode(got.toJson())), run['stats'], reason: '${run['days']}');
      expect([for (final (t, why) in quirks(got)) [t, why]], run['quirks'], reason: '${run['days']}');
    }
  });

  test('nothing played', () {
    final got = musicStats(const [], track, now: now);
    expect(got.plays, 0);
    expect(quirks(got), isEmpty);
  });

  test('two songs of one title stay two', () {
    const songs = {
      'a': {'id': 'a', 'title': 'Malare', 'movie': 'Premam'},
      'b': {'id': 'b', 'title': 'Malare', 'movie': 'Other'},
    };
    final played = [
      for (final (i, id) in 'aaabb'.split('').indexed) {'id': id, 'at': 100 + i, 'heard': 200, 'length': 200},
    ];
    final got = musicStats(played, (id) => songs[id], now: DateTime.fromMillisecondsSinceEpoch(1000000));
    expect(got.topSongs, [('Malare', 3), ('Malare', 2)]);
  });
}
