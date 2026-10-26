// A song's words and their English letters, as on the desktop
// (tests/lyrics_cases.json and tests/transliterate_cases.json, shared with
// paattu/lyrics.py and paattu/transliterate.py).

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:paattu/src/lyrics.dart';
import 'package:paattu/src/sources/youtube_music.dart';
import 'package:paattu/src/transliterate.dart';
import 'package:paattu/src/util.dart';

void main() {
  final cases = asJson(jsonDecode(File('../tests/lyrics_cases.json').readAsStringSync()));
  final letters = asJson(jsonDecode(File('../tests/transliterate_cases.json').readAsStringSync()));

  test('lines in English letters', () {
    for (final c in asList(letters['lines']).map(asJson)) {
      final text = asString(c['text']);
      expect(scriptOf(text), c['script'], reason: text);
      expect(transliterate(text), c['latin'], reason: text);
    }
    for (final c in asList(letters['scripts']).map(asJson)) {
      expect(scriptOf(asString(c['text'])), c['script'], reason: '${c['text']}');
    }
    expect(transliterate('Kanmani anbodu'), '');
  });

  test('LRC', () {
    final lrc = asJson(cases['lrc']);
    expect([for (final (at, t) in parseLrc(asString(lrc['text']))) [at, t]], lrc['lines']);
  });

  test('the same song', () {
    for (final c in asList(cases['sameSong']).map(asJson)) {
      expect(sameSong(asString(c['name']), asJson(c['track'])), c['same'], reason: '${c['name']}');
    }
  });

  test('what to ask for', () {
    for (final c in asList(cases['queries']).map(asJson)) {
      expect(lyricQueries(asJson(c['track'])), asStrings(c['queries']));
    }
  });

  test('the best find', () {
    for (final c in asList(cases['best']).map(asJson)) {
      final found = asList(c['found']);
      final got = bestLyrics(found, asJson(c['track']), asString(c['language']));
      final picked = got == null ? null : {'index': found.indexWhere((f) => mapEquals(asJson(f), got.$1)), 'timed': got.$2};
      expect(picked, c['picked'], reason: '$c');
    }
  });

  test('YouTube Music', () {
    expect(musicLyricsId(cases['youtubeNext']), cases['youtubeNextId']);
    final found = musicLyrics(cases['youtubeBrowse'])!;
    expect([found.$1, found.$2], cases['youtubeLyrics']);
  });

  test("YouTube Music's timed words", () {
    expect(musicTimedLyrics(cases['youtubeTimedBrowse']), cases['youtubeTimedLrc']);
    expect(musicTimedLyrics(cases['youtubeBrowse']), isNull);
  });

  test('lining up two uploads of a song', () {
    for (final c in asList(cases['shift']).map(asJson)) {
      List<int> ints(Object? v) => [for (final x in asList(v)) (x as num).toInt()];
      expect(lyricShift(ints(c['played']), ints(c['reference']), c['fps'] as int, c['most'] as num), c['shift'],
          reason: '${c['comment']}');
    }
  });

  test('what Now Playing shows', () {
    for (final c in asList(cases['shown']).map(asJson)) {
      final found = c['found'] == null ? null : asJson(c['found']);
      expect(shownLyrics(found, latin: c['latin'] == true).toJson(), c['shows'], reason: '$c');
    }
  });

  test('the line being sung', () {
    final words = shownLyrics({'synced': '[00:01.00]a\n[00:05.00]b\n[00:09.00]c', 'source': 'LRCLIB'});
    expect([words.lineAt(0), words.lineAt(1), words.lineAt(6.5), words.lineAt(100)], [-1, 0, 1, 2]);
    expect(shownLyrics({'plain': 'a\nb'}).lineAt(5), -1);
  });

  test('misses are asked again after three days', () async {
    final dir = await Directory.systemTemp.createTemp('paattu-lyrics');
    addTearDown(() => dir.delete(recursive: true));
    var asked = 0;
    final lyrics = Lyrics(dir, find: (track, language, {level}) async {
      asked++;
      return null;
    });
    final track = {'id': 'aaaaaaaaaaa', 'title': 'Malare'};
    expect(await lyrics.lookup(track, 'Malayalam'), isNull);
    expect(await lyrics.lookup(track, 'Malayalam'), isNull);
    expect(asked, 1);
  });

  test("partial finds and the last version's are asked again", () async {
    final dir = await Directory.systemTemp.createTemp('paattu-lyrics');
    addTearDown(() => dir.delete(recursive: true));
    var asked = 0;
    final lyrics = Lyrics(dir, find: (track, language, {level}) async {
      asked++;
      return {'plain': 'x', 'partial': asked == 1};
    });
    final track = {'id': 'aaaaaaaaaaa', 'title': 'Malare'};
    expect((await lyrics.lookup(track, 'Malayalam'))!['plain'], 'x');
    expect(asked, 1);
    // Kept an hour ago: asked again.
    final file = dir.listSync().whereType<File>().single;
    final kept = asJson(jsonDecode(file.readAsStringSync()));
    file.writeAsStringSync(jsonEncode({...kept, 'fetched': (kept['fetched'] as int) - 3700}));
    await lyrics.lookup(track, 'Malayalam');
    expect(asked, 2);
    await lyrics.lookup(track, 'Malayalam');
    expect(asked, 2);
    file.writeAsStringSync(jsonEncode({'fetched': kept['fetched'], 'found': {'plain': 'x'}}));
    await lyrics.lookup(track, 'Malayalam');
    expect(asked, 3);
  });
}

bool mapEquals(Json a, Json b) => jsonEncode(a) == jsonEncode(b);
