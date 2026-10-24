// The rhythm behind Now Playing's rings: beats found where the kick hits,
// loudness that follows the song, and the desktop's libmpv decode (where
// libmpv is installed).

import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:paattu/src/player/rhythm.dart';

const rate = 11025;

/// [seconds] of quiet hiss with a 55 Hz kick every half second (80 ms long).
Int16List kicks(double seconds, {double every = 0.5}) {
  final random = Random(1);
  return Int16List.fromList([
    for (var i = 0; i < seconds * rate; i++)
      (((i / rate) % every < 0.08 ? 0.8 * sin(2 * pi * 55 * i / rate) : 0) + 0.02 * (random.nextDouble() - 0.5)) *
          32767 ~/
          1,
  ]);
}

void main() {
  test('beats where the kick hits, nothing between', () {
    final rhythm = analyse(kicks(10), rate);
    expect(rhythm.length, 500);
    for (var beat = 1; beat < 19; beat++) {
      final at = beat * 25; // frames (50 a second) every half second
      expect(rhythm.punchBetween(at - 1, at + 2), greaterThan(0.6), reason: 'beat $beat');
      expect(rhythm.punchBetween(at + 8, at + 20), lessThan(0.15), reason: 'after beat $beat');
    }
  });

  test('loud on the kick, quieter between', () {
    final rhythm = analyse(kicks(10), rate);
    expect(rhythm.levelOf(rhythm.frameAt(const Duration(milliseconds: 2020))), greaterThan(0.8));
    expect(rhythm.levelOf(rhythm.frameAt(const Duration(milliseconds: 2300))), lessThan(0.3));
  });

  test('silence has no beats', () {
    final rhythm = analyse(Int16List(rate * 3), rate);
    expect(rhythm.punch.every((p) => p == 0), isTrue);
  });

  test('frames clamp to the song', () {
    final rhythm = analyse(kicks(2), rate);
    expect(rhythm.frameAt(const Duration(minutes: 5)), rhythm.length - 1);
    expect(rhythm.frameAt(Duration.zero), 0);
  });

  test('kept and read back', () {
    final rhythm = analyse(kicks(3), rate);
    final back = Rhythm.fromBytes(rhythm.toBytes())!;
    expect(back.level, rhythm.level);
    expect(back.punch, rhythm.punch);
    expect(Rhythm.fromBytes(Uint8List.fromList([9, 0, 0, 0, 0])), isNull);
    expect(Rhythm.fromBytes(Uint8List.fromList([1, 0, 0, 0, 5, 1])), isNull);
  });

  // PAATTU_RHYTHM_SONG=some.m4a flutter test test/rhythm_test.dart
  final song = Platform.environment['PAATTU_RHYTHM_SONG'];
  test('libmpv decodes a song', () async {
    MediaKit.ensureInitialized();
    final dir = await Directory.systemTemp.createTemp('rhythm');
    addTearDown(() => dir.delete(recursive: true));
    final rhythm = await RhythmFinder(dir).of('test:song', () async => File(song!));
    expect(rhythm, isNotNull);
    expect(rhythm!.length, greaterThan(Rhythm.fps * 5));
    expect(File('${dir.path}/test_song.rhythm').existsSync(), isTrue);
  }, skip: song == null || !Platform.isLinux);
}
