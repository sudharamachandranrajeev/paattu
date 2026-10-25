// The charts, as on the desktop (tests/chart_cases.json, shared with
// paattu/charts.py).

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:paattu/src/charts.dart';
import 'package:paattu/src/sources/youtube_music.dart';
import 'package:paattu/src/util.dart';

void main() {
  final cases = asJson(jsonDecode(File('../tests/chart_cases.json').readAsStringSync()));
  final youtube = {for (final MapEntry(:key, :value) in asJson(cases['youtubeCharts']).entries) key: asString(value)};

  test("YouTube Music's charts", () {
    expect(youtubeCharts(cases['youtube']), youtube);
  });

  test("where a chart's songs are", () {
    final saavn = asList(cases['saavn']).map(asJson).toList();
    for (final c in asList(cases['sources']).map(asJson)) {
      expect(chartSources(asString(c['kind']), asString(c['language']), saavn, youtube), c, reason: '$c');
    }
  });

  test('the lists merged', () {
    final merge = asJson(cases['merge']);
    final lists = [for (final l in asList(merge['lists'])) asList(l).map(asJson).toList()];
    expect(mergeChart(lists, asStrings(merge['avoid']).toSet()).map((s) => s['id']), asStrings(merge['songs']));
  });

  test('languages with charts', () {
    expect(pickedChartLanguages(['Tamil', 'Klingon']), ['Tamil']);
    expect(pickedChartLanguages([]), ['Malayalam', 'Tamil']);
  });
}
