// Finding a song that won't play on another site, the reasons given when it
// can't be played anywhere, where search looks, and the problem log.

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:paattu/src/log.dart';
import 'package:paattu/src/player/reasons.dart';
import 'package:paattu/src/search_feed.dart';
import 'package:paattu/src/settings.dart';
import 'package:paattu/src/sources/sources.dart';
import 'package:paattu/src/util.dart';

void main() {
  group('sameSong', () {
    final youtube = {'title': 'Malare', 'movie': 'Premam', 'duration': 318, 'site': 'youtube'};

    test('the same film song on another site', () {
      expect(sameSong(youtube, {'title': 'Malare', 'movie': 'Premam', 'duration': 316, 'site': 'jiosaavn'}), isTrue);
    });

    test('a longer title that starts the same, as long', () {
      expect(sameSong(youtube, {'title': 'Malare (Male)', 'movie': 'Premam', 'duration': 310}), isTrue);
    });

    test('another film', () {
      expect(sameSong(youtube, {'title': 'Malare', 'movie': 'Kaali', 'duration': 318}), isFalse);
    });

    test('much longer or shorter', () {
      expect(sameSong(youtube, {'title': 'Malare', 'movie': 'Premam', 'duration': 600}), isFalse);
    });

    test('another title', () {
      expect(sameSong(youtube, {'title': 'Malarey Mounama', 'duration': 318}), isFalse);
      expect(sameSong(youtube, {'title': 'Aluva Puzha', 'movie': 'Premam', 'duration': 318}), isFalse);
    });

    test('length unknown: only the same title from the same film', () {
      expect(sameSong({'title': 'Malare', 'movie': 'Premam'}, {'title': 'Malare', 'movie': 'Premam (OST)'}), isTrue);
      expect(sameSong({'title': 'Malare', 'movie': 'Premam'}, {'title': 'Malare Reprise', 'movie': 'Premam'}), isFalse);
      expect(sameSong({'title': 'Malare'}, {'title': 'Malare'}), isFalse);
    });

    test('words, not letters, in any case and script', () {
      expect(sameSong({'title': 'Vaathi Coming', 'duration': 228}, {'title': 'vaathi  coming!', 'duration': 230}), isTrue);
      expect(sameSong({'title': 'മലരേ', 'duration': 300}, {'title': 'മലരേ', 'duration': 305}), isTrue);
    });
  });

  test('sites best sound first', () {
    expect(qualityOrder, ['jiosaavn', 'youtube', 'soundcloud']);
  });

  group('playReason', () {
    test('from the stream server', () {
      final error = PlayerException(0, 'Source error', 0);
      expect(playReason(error, status: 403), 'the site refused to stream it');
      expect(playReason(error, status: 404), "it isn't on the site any more");
      expect(playReason(error, status: 429), contains('too many requests'));
      expect(playReason(error, status: 503), 'the site is having trouble');
    });

    test("from the player when the server didn't say", () {
      expect(playReason(PlayerException(0, 'Source error', 0)), "the stream wouldn't load");
      expect(playReason(PlayerException(1, 'Failed to recognize file format.', 0)),
          "this device can't play that kind of stream");
      expect(playReason(PlayerException(1, 'MediaCodecAudioRenderer error, index=0', 0)),
          "this device can't play that kind of stream");
      expect(playReason(TimeoutException('setAudioSource')), 'it took too long to start');
    });

    test('from the site', () {
      expect(playReason(SourceException('YouTube wants a sign-in for this one')), 'YouTube wants a sign-in for this one');
      expect(playReason(const SocketException('Failed host lookup: www.youtube.com')), "can't reach the internet");
      expect(playReason(SourceException('www.jiosaavn.com said 403'), status: 200), 'www.jiosaavn.com said 403');
    });
  });

  group('music from', () {
    late Directory dir;
    late Settings settings;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('paattu-test');
      settings = Settings(File('${dir.path}/settings.json'));
    });

    tearDown(() => dir.deleteSync(recursive: true));

    test('YouTube unless chosen', () {
      expect(settings.musicFrom, 'youtube');
      expect(settings.musicSites, ['youtube']);
    });

    test('one site, or every site', () {
      settings.musicFrom = 'jiosaavn';
      expect(settings.musicSites, ['jiosaavn']);
      settings.musicFrom = 'all';
      expect(settings.musicSites, ['jiosaavn', 'youtube', 'soundcloud']);
      settings.musicFrom = 'napster';
      expect(settings.musicSites, ['youtube']);
    });

    test('a kind the site lacks comes from the sites that have it', () {
      expect(SearchFeed('premam', 'song', ['youtube']).pagers.map((p) => p.site), ['youtube']);
      expect(SearchFeed('premam', 'album', ['youtube']).pagers.map((p) => p.site), ['jiosaavn', 'soundcloud']);
      expect(SearchFeed('premam', 'album', ['soundcloud']).pagers.map((p) => p.site), ['soundcloud']);
    });
  });

  group('problem log', () {
    late Directory dir;

    setUp(() => dir = Directory.systemTemp.createTempSync('paattu-test'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('lines from before it starts, then after; errors with where', () async {
      final log = ProblemLog();
      log.info('early');
      await log.start(File('${dir.path}/paattu.log'), header: 'Paattu test');
      log.warn('a warning');
      log.error('it broke', StateError('bad state'), StackTrace.current);
      final text = await log.text();
      expect(text, contains('=== Paattu test'));
      expect(text.indexOf('early'), greaterThan(text.indexOf('=== Paattu test')));
      expect(text, contains('!  a warning'));
      expect(text, contains('!! it broke: Bad state: bad state'));
      expect(text, contains('playback_test.dart'));
      await log.clear();
      expect((await log.text()).trim(), isEmpty);
    });

    test('a big log keeps its newest part', () async {
      final file = File('${dir.path}/paattu.log');
      file.writeAsStringSync(List.generate(20000, (i) => 'line $i ${'x' * 30}').join('\n'));
      final log = ProblemLog();
      await log.start(file, header: 'again');
      final text = await log.text();
      expect(text.length, lessThan(300 * 1024));
      expect(text, contains('line 19999'));
      expect(text, isNot(contains('line 0 ')));
      expect(text.startsWith('line '), isTrue);
    });
  });
}
