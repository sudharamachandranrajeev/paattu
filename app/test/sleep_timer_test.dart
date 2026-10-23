// The sleep timer: counting down, stopping at the end of a song, being
// extended or cancelled — and the words it is described in.

import 'package:flutter_test/flutter_test.dart';
import 'package:paattu/src/player/sleep_timer.dart';

void main() {
  group('SleepTimer', () {
    late DateTime now;
    late SleepTimer sleep;

    setUp(() {
      now = DateTime(2026, 10, 23, 23, 30);
      sleep = SleepTimer(clock: () => now);
    });

    test('off until it is started', () {
      expect(sleep.on, isFalse);
      expect(sleep.remaining, isNull);
      now = now.add(const Duration(hours: 3));
      sleep.tick();
      expect(sleep.due, isFalse);
    });

    test('a countdown runs out once, and is up until noticed', () {
      sleep.start(const Duration(minutes: 30));
      expect(sleep.on, isTrue);
      expect(sleep.endOfSong, isFalse);
      expect(sleep.remaining, const Duration(minutes: 30));

      now = now.add(const Duration(minutes: 29));
      sleep.tick();
      expect(sleep.due, isFalse);
      expect(sleep.remaining, const Duration(minutes: 1));

      // Past its time but not ticked yet: the time left doesn't go negative.
      now = now.add(const Duration(minutes: 2));
      expect(sleep.remaining, Duration.zero);

      sleep.tick();
      expect(sleep.due, isTrue);
      // It's up: there's nothing left to count down.
      expect(sleep.remaining, isNull);

      sleep.noticed();
      expect(sleep.due, isFalse);
      expect(sleep.on, isFalse);
      // And it doesn't fire again on its own.
      sleep.tick();
      expect(sleep.due, isFalse);
    });

    test('starting again replaces the timer that was running', () {
      sleep.start(const Duration(minutes: 10));
      now = now.add(const Duration(minutes: 5));
      sleep.start(const Duration(minutes: 60));
      expect(sleep.remaining, const Duration(minutes: 60));
      now = now.add(const Duration(minutes: 20));
      sleep.tick();
      expect(sleep.due, isFalse);
    });

    test('end of this song waits for the song, not the clock', () {
      sleep.startAtEndOfSong();
      expect(sleep.on, isTrue);
      expect(sleep.endOfSong, isTrue);
      expect(sleep.remaining, isNull);

      now = now.add(const Duration(hours: 5));
      sleep.tick();
      expect(sleep.due, isFalse, reason: 'the clock alone shouldn\'t stop it');

      sleep.songEnded();
      expect(sleep.due, isTrue);
      sleep.noticed();
      expect(sleep.on, isFalse);
    });

    test('a countdown isn\'t stopped early by a song ending', () {
      sleep.start(const Duration(minutes: 10));
      sleep.songEnded();
      expect(sleep.due, isFalse);
      expect(sleep.remaining, const Duration(minutes: 10));
    });

    test('extend adds to what is left, and starts one when there was none', () {
      sleep.start(const Duration(minutes: 5));
      now = now.add(const Duration(minutes: 2));
      sleep.extend(const Duration(minutes: 5));
      expect(sleep.remaining, const Duration(minutes: 8));

      sleep.cancel();
      sleep.extend(const Duration(minutes: 15));
      expect(sleep.remaining, const Duration(minutes: 15));
    });

    test('cancel stops it', () {
      sleep.start(const Duration(minutes: 5));
      sleep.cancel();
      expect(sleep.on, isFalse);
      now = now.add(const Duration(minutes: 10));
      sleep.tick();
      expect(sleep.due, isFalse);
    });

    test('starting with no time left is a cancel', () {
      sleep.start(const Duration(minutes: 5));
      sleep.start(Duration.zero);
      expect(sleep.on, isFalse);
    });

    test('listeners hear about starting, cancelling and being up', () {
      var heard = 0;
      sleep.addListener(() => heard++);
      sleep.start(const Duration(minutes: 5));
      sleep.cancel();
      expect(heard, 2);
      // Cancelling an already-off timer says nothing.
      sleep.cancel();
      expect(heard, 2);
      sleep.startAtEndOfSong();
      sleep.songEnded();
      sleep.noticed();
      expect(heard, 5);
    });
  });

  group('describeSleep', () {
    test('nothing, now, seconds, minutes and hours', () {
      expect(describeSleep(null), '');
      expect(describeSleep(Duration.zero), 'now');
      expect(describeSleep(const Duration(seconds: 45)), '45 s left');
      expect(describeSleep(const Duration(minutes: 25)), '25 min left');
      expect(describeSleep(const Duration(minutes: 25, seconds: 10)), '25:10 left');
      expect(describeSleep(const Duration(hours: 1, minutes: 5)), '1:05 left');
      expect(describeSleep(const Duration(hours: 2)), '2:00 left');
    });

    test('a negative time left reads as now', () {
      expect(describeSleep(const Duration(seconds: -30)), 'now');
    });
  });

  test('the presets are the ones the sheet offers', () {
    expect(sleepPresets, [5, 10, 15, 30, 45, 60, 90]);
  });
}
