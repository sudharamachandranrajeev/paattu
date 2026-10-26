// The same cases as tests/test_sound.py (tests/sound_cases.json): the app
// and the desktop Paattu must turn the settings into the same filters.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:paattu/src/sound.dart';

void main() {
  test('the shared cases', () {
    final cases = jsonDecode(File('../tests/sound_cases.json').readAsStringSync()) as List;
    expect(cases, isNotEmpty);
    for (final c in cases.cast<Map<String, dynamic>>()) {
      final s = Sound.fromJson(c['settings']);
      expect(jsonDecode(jsonEncode(s.toJson())), c['normalized'], reason: c['case'] as String);
      expect(s.gains, c['gains'], reason: c['case'] as String);
      expect(s.graph, c['graph'], reason: c['case'] as String);
    }
  });

  test('a band peaks at its frequency; a tiny Q is a flat gain', () {
    final band = [(soundFilters[9], 6.0)]; // 1 kHz
    expect(soundResponse(band, 1000), closeTo(6.0, 0.01));
    expect(soundResponse(band, 100), lessThan(0.3));
    final pre = [(soundFilters[0], -6.0)];
    for (final f in [25.0, 100.0, 1000.0, 8000.0, 18000.0]) {
      expect(soundResponse(pre, f), closeTo(-6.0, 0.05));
    }
  });

  test('noclip lowers the preamp by the peak', () {
    const s = Sound(on: true, bands: [0, 0, 0, 0, 0, 0, 0, 0, 6, 0, 0, 0, 0, 0, 0]);
    expect(s.gains['pre'], closeTo(-6.0, 0.2));
    expect(s.copyWith(noclip: false).gains['pre'], 0.0);
    expect(Sound(on: true, bands: List.filled(15, -3)).gains['pre'], 0.0);
  });

  test('surround widens, makes room, and moves live', () {
    expect([for (final x in [0.0, 0.5, 1.0]) Sound(surround: x).widen], [1.0, 1.75, 2.5]);
    expect(const Sound(on: true).graph, contains('extrastereo@surround=m=1,'));
    const wide = Sound(on: true, surround: 1);
    expect(wide.gains['pre'], closeTo(-4.9, 0.05));
    expect(wide.copyWith(noclip: false).gains['pre'], 0.0);
    expect(wide.movesFrom(const Sound(on: true)).last, ['af-command', 'paattu', 'm', '2.5', 'extrastereo@surround']);
    // The phone's virtualizer widens on its own: no room taken from its bands.
    expect(wide.phone([1000], -15, 15).$1, [0.0]);
    expect(wide.summary, 'On · Flat · surround 100%');
  });

  test('the curve lands on the sliders', () {
    for (final bands in [
      List<double>.filled(15, 12),
      [for (var i = 0; i < 15; i++) i.isOdd ? 12.0 : -12.0],
      [for (var i = 0; i < 15; i++) i == 7 ? 12.0 : 0.0],
      builtInPresets[1].bands,
    ]) {
      final shape = Sound(bands: bands).curve;
      for (var i = 0; i < 15; i++) {
        expect(soundResponse(shape, soundBands[i].toDouble()), closeTo(bands[i], 0.5), reason: '$bands at ${soundBands[i]}');
      }
    }
  });

  test('ten bands from before 0.14 become fifteen', () {
    const old = <double>[4, 3, 1, 0, -1, 0, 1.5, 2, 3, 3];
    final shape = [for (var i = 0; i < 10; i++) (SoundFilter('', oldSoundBands[i], 1), old[i])];
    final s = Sound.fromJson({'bands': old, 'preset': 'rock', 'presets': {'Car': old}});
    expect(s.bands.length, 15);
    for (var i = 0; i < 15; i++) {
      expect(s.bands[i], closeTo(soundResponse(shape, soundBands[i].toDouble()), 0.051));
    }
    expect(s.saved['Car'], s.bands);
    final rock = Sound.fromJson({'preset': 'rock', 'bands': [5, 3, -2, -3.5, -1.5, 1.5, 3.5, 4.5, 4.5, 4.5]});
    expect(rock.bands, builtInPresets[6].bands);
    expect(rock.matchingPreset, 'rock');
  });

  test('numbers and words', () {
    expect([2.5, 3.0, -0.0, -0.04, 1.25, -2.25].map(soundFmt), ['2.5', '3', '0', '0', '1.3', '-2.2']);
    expect([2.5, -3.0, 0.0].map(soundDb), ['+2.5', '-3', '0']);
    expect(soundBands.map(bandLabel).toList(),
        ['25', '40', '63', '100', '160', '250', '400', '630', '1k', '1.6k', '2.5k', '4k', '6.3k', '10k', '16k']);
    expect(Sound(bands: List.filled(15, 5)).graph, '');
    expect(Sound.fromJson({'on': true, 'preset': 'melody', 'bass': 2, 'speed': 1.25}).summary,
        'On · Melody · bass +2 dB · 1.25×');
    expect(Sound.fromJson({'preset': '', 'balance': -0.3}).summary, 'Off · Custom · balance 30% left');
  });

  test('presets: pick, follow the bands, save and delete', () {
    var s = const Sound().withPreset('melody');
    expect((s.on, s.preset, s.bands[8]), (true, 'melody', 4.5));
    s = s.withBands([...s.bands]..[0] = 1);
    expect(s.preset, '');
    s = s.savedAs(' Car ');
    expect(s.preset, 'Car');
    expect(s.saved['Car'], s.bands);
    expect(s.findPreset('car'), 'Car');
    expect(s.findPreset('Bass Boost'), 'bass');
    expect(() => s.savedAs('rock'), throwsArgumentError);
    expect(s.withBands(builtInPresets[1].bands).preset, 'melody');
    s = s.withoutPreset('Car');
    expect(s.saved, isEmpty);
    expect(s.preset, '');
    expect(s.reset().bands, everyElement(0.0));
  });

  test('a dragged band moves its filter, its neighbours and the preamp', () {
    const before = Sound(on: true);
    final after = before.copyWith(bands: [0, 0, 0, 6, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]);
    final moved = after.movesFrom(before).map((c) => c[4]).toList();
    expect(moved.first, 'equalizer@pre');
    expect(moved, containsAll(['equalizer@b2', 'equalizer@b3', 'equalizer@b4']));
    expect(moved, isNot(contains('equalizer@b10')));
    expect(after.movesFrom(after), isEmpty);
  });

  test("the curve on a phone's five bands", () {
    const centres = [60.0, 230.0, 910.0, 3600.0, 14000.0];
    final s = Sound.fromJson({'on': true, 'preset': 'bass', 'bands': builtInPresets[3].bands});
    final (bands, loudness) = s.phone(centres, -15, 15);
    // The bass boost is there, under a preamp cut that leaves room for it.
    expect(bands.first, greaterThan(bands.last + 5));
    expect(bands.last, closeTo(s.gains['pre']!, 0.2));
    expect(loudness, 0.0);
    final (_, louder) = Sound.fromJson({'on': true, 'preamp': 4}).phone(centres, -15, 15);
    expect(louder, 4.0);
    final (clamped, _) = Sound.fromJson({'on': true, 'noclip': false, 'bands': List.filled(15, 12)}).phone(centres, -15, 15);
    expect(clamped, everyElement(lessThanOrEqualTo(15)));
    final (off, quiet) = Sound(bands: List.filled(15, 6)).phone(centres, -15, 15);
    expect(off, List.filled(5, 0.0));
    expect(quiet, 0.0);
  });
}
