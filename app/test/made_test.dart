// YouTube Music's answers read the same as tests/test_ytmusic.py reads them
// (tests/ytmusic_cases.json), the playlists made for you are planned the
// same as on the desktop (tests/made_cases.json), and the play history adds
// up as it should.

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:paattu/src/history.dart';
import 'package:paattu/src/made.dart';
import 'package:paattu/src/radio.dart';
import 'package:paattu/src/sources/youtube_music.dart';
import 'package:paattu/src/track.dart';
import 'package:paattu/src/util.dart';

Json _read(String name) => asJson(jsonDecode(File('../tests/$name').readAsStringSync()));

List<String> _ids(List<Json> songs) => songs.map(trackId).toList();

void main() {
  group('YouTube Music', () {
    final cases = _read('ytmusic_cases.json');
    final expected = asJson(cases['expect']);

    test('songs from a search', () {
      final songs = musicSearchSongs(cases['search']);
      expect(songs, expected['search']);
      expect(songs.first['art'], endsWith('=w544-h544-l90-rj'));
    });

    test('a radio and its next helping', () {
      for (final key in ['next', 'more']) {
        final page = radioPage(cases[key]);
        expect(page.songs, asJson(expected[key])['songs'], reason: key);
        expect(page.more, asJson(expected[key])['more'], reason: key);
      }
    });

    test("labels' notes give the film and leave the title", () {
      final song = radioPage(cases['more']).songs.first;
      expect(song['title'], 'Irupathu Kodi');
      expect(song['movie'], 'Thullatha Manamum Thullum');
    });
  });

  group('made for you', () {
    final cases = _read('made_cases.json');

    test('the day, week and month', () {
      for (final c in asList(cases['period']).map(asJson)) {
        expect(periodKey(asString(c['kind']), DateTime.parse(asString(c['date']))), c['key'], reason: '$c');
      }
    });

    test('what a description asks for', () {
      for (final c in asList(cases['describe']).map(asJson)) {
        expect(describePhrases(asString(c['text'])), c['phrases'], reason: asString(c['text']));
      }
    });

    test('a daily mix: two you know, one new', () {
      final c = asJson(cases['daily']);
      final familiar = asList(c['familiar']).map(asJson).toList();
      final fresh = asList(c['fresh']).map(asJson).toList();
      expect(_ids(dailyMix(familiar, fresh, size: toInt(c['size'])!)), c['ids']);
    });

    test('weighted picks: no repeats, the heavy one nearly always in', () {
      final random = Random(7);
      var heavyIn = 0;
      for (var i = 0; i < 200; i++) {
        final picked = weightedPick(List.generate(20, (i) => i), (n) => n == 3 ? 50 : 1, 5, random);
        expect(picked.toSet().length, 5);
        if (picked.contains(3)) heavyIn++;
      }
      expect(heavyIn, greaterThan(180));
    });
  });

  group('play history', () {
    final now = DateTime.utc(2026, 10, 15, 12);
    int ago(double days) => epochSeconds(now) - (days * 86400).round();
    Json play(String id, double daysAgo, int heard, [int length = 240]) =>
        {'id': id, 'at': ago(daysAgo), 'heard': heard, 'length': length};

    test('a play counts at half the song or 30 seconds', () {
      expect(counted({'heard': 30, 'length': 240}), isTrue);
      expect(counted({'heard': 29, 'length': 240}), isFalse);
      expect(counted({'heard': 20, 'length': 40}), isTrue);
      expect(counted({'heard': 29}), isFalse);
    });

    test('liked lately: recent plays count more, skips count against', () {
      final plays = [
        play('a', 1, 200),
        play('a', 2, 200),
        play('b', 20, 200),
        play('b', 21, 200),
        play('b', 22, 200),
        play('c', 1, 200),
        play('c', 1, 5),
        play('c', 2, 5),
        play('c', 3, 5),
        play('old', 40, 200),
      ];
      final tracks = {for (final id in ['a', 'b', 'c', 'old']) id: <String, dynamic>{'id': id, 'title': 'Song $id'}};
      final top = topSongs(plays, (id) => tracks[id], now: now);
      expect(top.map((t) => trackId(t.song)).toList(), ['a', 'b']);
      expect(top.first.count, 2);
    });

    test('skipped often and heard lately', () {
      final plays = [play('s', 1, 5), play('s', 2, 3), play('t', 1, 5), play('u', 0.1, 100)];
      expect(skippedOften(plays, now), {'s'});
      expect(heardSince(plays, now.subtract(const Duration(hours: 6))), {'u'});
    });

    test('the history keeps plays, songs and made playlists', () async {
      final dir = Directory.systemTemp.createTempSync('paattu-history');
      addTearDown(() => dir.deleteSync(recursive: true));
      final history = History(File('${dir.path}/history.json'));
      final song = <String, dynamic>{'id': 'abcdefghijk', 'title': 'Malare', 'movie': 'Premam', '_radio': true};
      history.played(song, 120, length: 240, at: now);
      expect(history.plays.single, {'id': 'abcdefghijk', 'at': epochSeconds(now), 'heard': 120, 'length': 240});
      expect(history.track('abcdefghijk'), {'id': 'abcdefghijk', 'title': 'Malare', 'movie': 'Premam'});
      history.setMade('daily', '2026-10-15', [song]);
      expect(history.made('daily')?.key, '2026-10-15');
      expect(_ids(history.made('daily')!.tracks), ['abcdefghijk']);
      await history.save();
      final again = History(File('${dir.path}/history.json'));
      await again.load();
      expect(again.plays, history.plays);
    });
  });

  group('radio', () {
    test('songs taken in turn, each once, songs only', () {
      Json song(String id, String title, [int duration = 240, String kind = 'audio']) =>
          {'id': id, 'title': title, 'duration': duration, 'kind': kind};
      final lists = [
        [song('a1', 'A'), song('a2', 'B'), song('a3', 'C')],
        [song('b1', 'A'), song('b2', 'D', 3600), song('b3', 'E'), song('b4', 'F', 200, 'trailer')],
      ];
      final avoid = {'c|'};
      expect(_ids(interleaveSongs(lists, avoid: avoid)), ['a1', 'b3', 'a2']);
      expect(avoid, containsAll(['a1', 'a|', 'a2', 'b|', 'b3', 'e|']));
    });
  });
}
