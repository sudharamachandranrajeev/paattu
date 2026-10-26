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
}
