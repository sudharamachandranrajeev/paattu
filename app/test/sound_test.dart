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
    final band = [(soundFilters[6], 6.0)]; // 1 kHz
    expect(soundResponse(band, 1000), closeTo(6.0, 0.01));
    expect(soundResponse(band, 62), lessThan(0.3));
    final pre = [(soundFilters[0], -6.0)];
    for (final f in [25.0, 100.0, 1000.0, 8000.0, 18000.0]) {
      expect(soundResponse(pre, f), closeTo(-6.0, 0.05));
    }
  });

  test('noclip lowers the preamp by the peak', () {
    const s = Sound(on: true, bands: [0, 0, 0, 0, 0, 6, 0, 0, 0, 0]);
    expect(s.gains['pre'], -6.0);
    expect(s.copyWith(noclip: false).gains['pre'], 0.0);
    expect(const Sound(on: true, bands: [-3, -3, -3, -3, -3, -3, -3, -3, -3, -3]).gains['pre'], 0.0);
  });

  test('numbers and words', () {
    expect([2.5, 3.0, -0.0, -0.04, 1.25, -2.25].map(soundFmt), ['2.5', '3', '0', '0', '1.3', '-2.2']);
    expect([2.5, -3.0, 0.0].map(soundDb), ['+2.5', '-3', '0']);
    expect(soundBands.map(bandLabel).toList(), ['31', '62', '125', '250', '500', '1k', '2k', '4k', '8k', '16k']);
    expect(const Sound(bands: [5, 5, 5, 5, 5, 5, 5, 5, 5, 5]).graph, '');
    expect(Sound.fromJson({'on': true, 'preset': 'melody', 'bass': 2, 'speed': 1.25}).summary,
        'On · Melody · bass +2 dB · 1.25×');
    expect(Sound.fromJson({'preset': '', 'balance': -0.3}).summary, 'Off · Custom · balance 30% left');
  });

  test('presets: pick, follow the bands, save and delete', () {
    var s = const Sound().withPreset('melody');
    expect((s.on, s.preset, s.bands[5]), (true, 'melody', 3.5));
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

  test('a dragged band moves only its filter and the preamp', () {
    const before = Sound(on: true);
    final after = before.copyWith(bands: [0, 0, 0, 6, 0, 0, 0, 0, 0, 0]);
    expect(after.movesFrom(before), [
      ['af-command', 'paattu', 'g', '-6', 'equalizer@pre'],
      ['af-command', 'paattu', 'g', '6', 'equalizer@b3'],
    ]);
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
    final (clamped, _) = Sound.fromJson({'on': true, 'noclip': false, 'bands': List.filled(10, 12)}).phone(centres, -15, 15);
    expect(clamped, everyElement(lessThanOrEqualTo(15)));
    final (off, quiet) = const Sound(bands: [6, 6, 6, 6, 6, 6, 6, 6, 6, 6]).phone(centres, -15, 15);
    expect(off, List.filled(5, 0.0));
    expect(quiet, 0.0);
  });
}
