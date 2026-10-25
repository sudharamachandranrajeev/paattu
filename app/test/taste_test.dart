// What you play shapes what comes next, as on the desktop
// (tests/taste_cases.json, shared with paattu/history.py and radio.py).

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:paattu/src/history.dart';
import 'package:paattu/src/radio.dart';
import 'package:paattu/src/util.dart';

void main() {
  final cases = asJson(jsonDecode(File('../tests/taste_cases.json').readAsStringSync()));
  final tracks = asJson(cases['tracks']);
  final plays = asList(cases['plays']).map(asJson).toList();
  final now = DateTime.fromMillisecondsSinceEpoch((toInt(cases['now'])!) * 1000);
  Json? track(String id) => tracks[id] is Map ? asJson(tracks[id]) : null;
  String keyOf(String id) => songIdentity(track(id) ?? {'id': id});
  List<String> ids(List<Json> songs) => [for (final s in songs) asString(s['id'])];
  Map<String, double> likesOf(Object? raw) => {
        for (final MapEntry(:key, :value) in asJson(raw).entries) key: (value as num).toDouble(),
      };

  test('a song played to the end', () {
    for (final c in asList(cases['fullyPlayed']).map(asJson)) {
      expect(fullyPlayed(asJson(c['play'])), c['full'], reason: '$c');
    }
  });

  test('songs turned down', () {
    final down = turnedDown(plays, keyOf: keyOf);
    final played = {for (final p in plays) asString(p['id'])}.toList()..sort();
    expect(played.where(down.contains), asStrings(cases['turnedDown']));
    expect(down, contains(keyOf('b')));
  });

  test('taste', () {
    final likes = taste(plays, track, now: now);
    final expected = likesOf(cases['taste']);
    expect(likes.keys.toSet(), expected.keys.toSet());
    for (final MapEntry(:key, :value) in expected.entries) {
      expect(likes[key], closeTo(value, 1e-5), reason: key);
    }
  });

  test('taste order', () {
    final order = asJson(cases['order']);
    final songs = asList(order['songs']).map(asJson).toList();
    expect(ids(tasteOrder(songs, likesOf(cases['likes']))), asStrings(order['liked']));
    expect(ids(tasteOrder(songs, likesOf(order['skipping']))), asStrings(order['skipped']));
  });

  test('loved songs join the radio', () {
    final loved = asJson(cases['loved']);
    final top = [for (final id in asStrings(loved['top'])) track(id)!];
    final picked = lovedLike(asJson(loved['station']), top, asStrings(loved['avoid']).toSet());
    expect(ids(picked), asStrings(loved['picked']));
    List<Json> helping(Object? raw) => [for (final id in asStrings(raw)) <String, dynamic>{'id': id, 'title': id}];
    expect(ids(withFavourites(helping(loved['helping']), picked)), asStrings(loved['withLoved']));
    expect(ids(withFavourites(helping(loved['short']), picked)), asStrings(loved['shortWithLoved']));
  });
}
