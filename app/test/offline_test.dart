// The songs kept on this device: reading the folder back, dropping entries
// whose file has gone, making room by what was played least recently, and
// carrying the songs over when the folder changes. Nothing here reaches the
// network — a save that has to download is the player's business.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:paattu/src/offline.dart';

/// A song as a previous run would have left it in the index.
OfflineEntry _song(String key, String file, int bytes, {DateTime? used, int plays = 0}) => OfflineEntry(
      key: key,
      file: file,
      bytes: bytes,
      saved: used ?? DateTime.utc(2026, 10, 20),
      used: used ?? DateTime.utc(2026, 10, 20),
      plays: plays,
      codec: 'opus',
      kbps: 160,
      track: <String, dynamic>{
        'id': key.split(':').last,
        'site': key.split(':').first,
        'title': 'Malare',
        'movie': 'Premam',
      },
    );

/// Write [entries] into [dir]: the files and the index beside them.
void _seed(Directory dir, List<OfflineEntry> entries) {
  dir.createSync(recursive: true);
  for (final entry in entries) {
    File('${dir.path}${Platform.pathSeparator}${entry.file}').writeAsBytesSync(List.filled(32, 7));
  }
  File('${dir.path}${Platform.pathSeparator}$offlineIndex').writeAsStringSync(jsonEncode(<String, dynamic>{
    'version': 1,
    'songs': {for (final e in entries) e.key: e.toJson()},
  }));
}

bool _exists(Directory dir, String file) =>
    File('${dir.path}${Platform.pathSeparator}$file').existsSync();

void main() {
  late Directory root;
  late Directory dir;

  setUp(() {
    root = Directory.systemTemp.createTempSync('paattu-offline');
    dir = Directory('${root.path}${Platform.pathSeparator}offline');
  });

  tearDown(() => root.deleteSync(recursive: true));

  test('a new folder loads empty, and is made', () async {
    final offline = OfflineLibrary(dir);
    await offline.load();
    expect(offline.ready, isTrue);
    expect(offline.count, 0);
    expect(offline.totalBytes, 0);
    expect(dir.existsSync(), isTrue);
  });

  test('songs are read back from the index, newest first', () async {
    _seed(dir, [
      _song('youtube:older', 'Older.webm', 100, used: DateTime.utc(2026, 10, 1)),
      _song('youtube:newer', 'Newer.webm', 200, used: DateTime.utc(2026, 10, 20)),
    ]);
    final offline = OfflineLibrary(dir);
    await offline.load();
    expect(offline.count, 2);
    expect(offline.totalBytes, 300);
    expect(offline.songs.map((e) => e.key), ['youtube:newer', 'youtube:older']);
    expect(offline.has('youtube:older'), isTrue);
    expect(offline.has('youtube:gone'), isFalse);
    expect(offline.entry('youtube:newer')?.title, 'Malare');
    expect(offline.entry('youtube:newer')?.size, '200 B');
  });

  test('an entry whose file has gone is dropped on load', () async {
    _seed(dir, [_song('youtube:here', 'Here.webm', 100), _song('youtube:deleted', 'Deleted.webm', 900)]);
    File('${dir.path}${Platform.pathSeparator}Deleted.webm').deleteSync();
    final offline = OfflineLibrary(dir);
    await offline.load();
    expect(offline.songs.map((e) => e.key), ['youtube:here']);
    expect(offline.totalBytes, 100);
  });

  test('a song kept here is something the player can play with no network', () async {
    _seed(dir, [_song('youtube:hvqnG6VjqV0', 'Vijay Yesudas - Malare.webm', 100)]);
    final offline = OfflineLibrary(dir);
    await offline.load();
    final stream = await offline.localStream('youtube:hvqnG6VjqV0');
    expect(stream, isNotNull);
    expect(stream!.uri.scheme, 'file');
    expect(stream.uri.toFilePath(), endsWith('Vijay Yesudas - Malare.webm'));
    expect(stream.label, 'Opus · 160 kbps');
    expect(stream.fresh, isTrue);
    expect(offline.file('youtube:hvqnG6VjqV0')?.path, stream.uri.toFilePath());
  });

  test('a song whose file went missing mid-run is forgotten', () async {
    _seed(dir, [_song('youtube:x', 'X.webm', 100)]);
    final offline = OfflineLibrary(dir);
    await offline.load();
    File('${dir.path}${Platform.pathSeparator}X.webm').deleteSync();
    expect(await offline.localStream('youtube:x'), isNull);
    expect(offline.has('youtube:x'), isFalse);
  });

  test('a song not kept has no stream', () async {
    final offline = OfflineLibrary(dir);
    await offline.load();
    expect(await offline.localStream('youtube:nope'), isNull);
    expect(offline.file('youtube:nope'), isNull);
  });

  test('playing a song from here marks it used, so it isn\'t dropped first', () async {
    _seed(dir, [
      _song('youtube:a', 'A.webm', 100, used: DateTime.utc(2026, 10, 1)),
      _song('youtube:b', 'B.webm', 100, used: DateTime.utc(2026, 10, 2)),
    ]);
    final offline = OfflineLibrary(dir);
    await offline.load();
    offline.notePlayed('youtube:a');
    expect(offline.entry('youtube:a')!.plays, 1);
    expect(offline.entry('youtube:a')!.used.isAfter(DateTime.utc(2026, 10, 2)), isTrue);
    // The least recently used is b now, not a.
    await offline.applyLimit(150);
    expect(offline.has('youtube:a'), isTrue);
    expect(offline.has('youtube:b'), isFalse);
  });

  group('making room', () {
    test('the songs used least recently go first', () async {
      _seed(dir, [
        _song('youtube:old', 'Old.webm', 100, used: DateTime.utc(2026, 10, 1)),
        _song('youtube:mid', 'Mid.webm', 100, used: DateTime.utc(2026, 10, 5)),
        _song('youtube:new', 'New.webm', 100, used: DateTime.utc(2026, 10, 9)),
      ]);
      final offline = OfflineLibrary(dir);
      await offline.load();
      expect(offline.totalBytes, 300);
      await offline.applyLimit(250);
      expect(offline.has('youtube:old'), isFalse);
      expect(offline.totalBytes, 200);
      // Its file went with it.
      expect(_exists(dir, 'Old.webm'), isFalse);
      expect(_exists(dir, 'New.webm'), isTrue);
    });

    test('a folder over the room allowed is made to fit as it loads', () async {
      _seed(dir, [
        _song('youtube:old', 'Old.webm', 100, used: DateTime.utc(2026, 10, 1)),
        _song('youtube:new', 'New.webm', 100, used: DateTime.utc(2026, 10, 9)),
      ]);
      final offline = OfflineLibrary(dir, limitBytes: 150);
      await offline.load();
      expect(offline.has('youtube:old'), isFalse);
      expect(offline.has('youtube:new'), isTrue);
    });

    test('it keeps going until it fits', () async {
      _seed(dir, [
        for (var i = 0; i < 5; i++)
          _song('youtube:s$i', 'S$i.webm', 100, used: DateTime.utc(2026, 10, i + 1)),
      ]);
      final offline = OfflineLibrary(dir);
      await offline.load();
      await offline.applyLimit(150);
      expect(offline.totalBytes, lessThanOrEqualTo(150));
      expect(offline.has('youtube:s4'), isTrue);
      expect(offline.has('youtube:s0'), isFalse);
    });

    test('no limit means nothing is dropped', () async {
      _seed(dir, [_song('youtube:a', 'A.webm', 1 << 30), _song('youtube:b', 'B.webm', 1 << 30)]);
      final offline = OfflineLibrary(dir, limitBytes: 0);
      await offline.load();
      await offline.applyLimit(0);
      expect(offline.count, 2);
    });

    test('the last song is kept even when it is over the limit', () async {
      _seed(dir, [_song('youtube:big', 'Big.webm', 1000)]);
      final offline = OfflineLibrary(dir);
      await offline.load();
      await offline.applyLimit(10);
      expect(offline.count, 1);
    });
  });

  test('taking a song off deletes its file and rewrites the index', () async {
    _seed(dir, [_song('youtube:a', 'A.webm', 100), _song('youtube:b', 'B.webm', 100)]);
    final offline = OfflineLibrary(dir);
    await offline.load();
    await offline.remove('youtube:a');
    expect(offline.has('youtube:a'), isFalse);
    expect(_exists(dir, 'A.webm'), isFalse);
    expect(_exists(dir, 'B.webm'), isTrue);
    // The index on disk agrees, so the next run doesn't bring it back.
    final again = OfflineLibrary(dir);
    await again.load();
    expect(again.songs.map((e) => e.key), ['youtube:b']);
  });

  test('emptying the library takes every file', () async {
    _seed(dir, [_song('youtube:a', 'A.webm', 100), _song('youtube:b', 'B.webm', 100)]);
    final offline = OfflineLibrary(dir);
    await offline.load();
    await offline.clear();
    expect(offline.count, 0);
    expect(_exists(dir, 'A.webm'), isFalse);
    expect(_exists(dir, 'B.webm'), isFalse);
  });

  test('a song already kept is kept again without downloading', () async {
    _seed(dir, [_song('youtube:a', 'A.webm', 100)]);
    final offline = OfflineLibrary(dir);
    await offline.load();
    var resolved = 0;
    final kept = await offline.save({'id': 'a', 'site': 'youtube'}, () async {
      resolved++;
      throw StateError('it should not need a stream');
    });
    expect(kept, isTrue);
    expect(resolved, 0);
  });

  test('a save that can\'t find a stream keeps nothing and doesn\'t throw', () async {
    final offline = OfflineLibrary(dir);
    await offline.load();
    final kept = await offline.save({'id': 'a', 'site': 'youtube'}, () async => throw StateError('no stream'));
    expect(kept, isFalse);
    expect(offline.count, 0);
  });

  test('a song with no id is not kept', () async {
    final offline = OfflineLibrary(dir);
    await offline.load();
    expect(await offline.save({'site': 'youtube'}, () async => throw StateError('unused')), isFalse);
  });

  test('a library whose folder can\'t be made isn\'t ready, and keeps nothing', () async {
    // A file where the folder should be.
    final blocking = File('${root.path}${Platform.pathSeparator}blocked');
    blocking.writeAsStringSync('in the way');
    final offline = OfflineLibrary(Directory(blocking.path));
    await offline.load();
    expect(offline.ready, isFalse);
    expect(await offline.save({'id': 'a', 'site': 'youtube'}, () async => throw StateError('unused')), isFalse);
  });

  group('moving folder', () {
    test('the songs and the index are carried over', () async {
      _seed(dir, [_song('youtube:a', 'A.webm', 100)]);
      final offline = OfflineLibrary(dir);
      await offline.load();
      final other = Directory('${root.path}${Platform.pathSeparator}music');
      await offline.moveTo(other, allowed: OfflineLibrary.defaultLimitBytes);
      expect(offline.path, other.path);
      expect(offline.has('youtube:a'), isTrue);
      expect(_exists(other, 'A.webm'), isTrue);
      expect(_exists(other, offlineIndex), isTrue);
      // And a fresh read of the new folder finds it.
      final again = OfflineLibrary(other);
      await again.load();
      expect(again.songs.map((e) => e.key), ['youtube:a']);
      expect((await again.localStream('youtube:a'))?.uri.toFilePath(), endsWith('A.webm'));
    });

    test('moving to the same folder with the same room does nothing', () async {
      _seed(dir, [_song('youtube:a', 'A.webm', 100)]);
      final offline = OfflineLibrary(dir);
      await offline.load();
      var heard = 0;
      offline.addListener(() => heard++);
      await offline.moveTo(dir, allowed: offline.limitBytes);
      expect(heard, 0);
      expect(_exists(dir, 'A.webm'), isTrue);
    });

    test('only the room changing still makes it fit', () async {
      _seed(dir, [_song('youtube:a', 'A.webm', 100), _song('youtube:b', 'B.webm', 100)]);
      final offline = OfflineLibrary(dir);
      await offline.load();
      await offline.moveTo(dir, allowed: 150);
      expect(offline.totalBytes, lessThanOrEqualTo(150));
    });
  });

  group('keptSongsDirectory', () {
    test('the folder picked, or the app\'s own', () {
      final app = Directory('${root.path}${Platform.pathSeparator}support');
      expect(keptSongsDirectory('', app).path, '${app.path}${Platform.pathSeparator}offline');
      expect(keptSongsDirectory('   ', app).path, '${app.path}${Platform.pathSeparator}offline');
      expect(keptSongsDirectory('/music/paattu', app).path, '/music/paattu');
      expect(keptSongsDirectory('  /music/paattu  ', app).path, '/music/paattu');
    });
  });

  group('formatBytes', () {
    test('readable sizes', () {
      expect(formatBytes(0), '0 KB');
      expect(formatBytes(-5), '0 KB');
      expect(formatBytes(512), '512 B');
      expect(formatBytes(4096), '4 KB');
      expect(formatBytes((4.1 * 1024 * 1024).round()), '4.1 MB');
      expect(formatBytes(2 << 30), '2.0 GB');
    });
  });

  test('a checksum of a kept song reads back as it was written', () {
    final entry = _song('youtube:a', 'A.webm', 1234, plays: 3, used: DateTime.utc(2026, 10, 21, 8, 30));
    final back = OfflineEntry.fromJson('youtube:a', jsonDecode(jsonEncode(entry.toJson())) as Map<String, dynamic>);
    expect(back.key, entry.key);
    expect(back.file, entry.file);
    expect(back.bytes, entry.bytes);
    expect(back.plays, 3);
    expect(back.codec, 'opus');
    expect(back.kbps, 160);
    expect(back.used, DateTime.utc(2026, 10, 21, 8, 30));
    expect(back.track['title'], 'Malare');
  });
}
