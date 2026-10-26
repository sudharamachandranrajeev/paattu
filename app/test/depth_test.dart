// The same cases as tests/test_depth.py (tests/depth_cases.json): the app and
// the desktop Paattu must give the same covers the same depth.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:paattu/src/depth.dart';

void main() {
  final c = jsonDecode(File('../tests/depth_cases.json').readAsStringSync()) as Map<String, dynamic>;
  final side = c['side'] as int;
  final rgb = (c['rgb'] as List).cast<int>();
  List<double> numbers(Object? list) => [for (final v in list as List) (v as num).toDouble()];
  void close(List<double> got, Object? want) {
    final expected = numbers(want);
    expect(got.length, expected.length);
    for (var i = 0; i < got.length; i++) {
      expect(got[i], closeTo(expected[i], 1e-7), reason: 'at $i');
    }
  }

  test('regions', () {
    final (labels, colours) = regions(rgb, side);
    expect(labels, c['labels']);
    for (var i = 0; i < colours.length; i++) {
      close(colours[i], (c['colours'] as List)[i]);
    }
  });

  test('region depth', () {
    final got = regionDepth(rgb, side);
    close(got, c['regionDepth']);
    // The red disc in the middle is the nearest layer, the yellow along the
    // top edge the furthest, the blue around them between.
    expect(got[7 * side + 6], 1.0);
    expect(got[0], lessThan(got[11 * side]));
    expect(got[11 * side], lessThan(1.0));
    expect(regionDepth(List.filled(64 * 3, 90), 8).toSet(), {0.5});
  });

  test('blur and shrink', () {
    final b = c['blur'] as Map<String, dynamic>, s = c['shrink'] as Map<String, dynamic>;
    close(blur(numbers(b['values']), b['side'] as int, (b['sigma'] as num).toDouble()), b['out']);
    close(shrink(numbers(s['values']), s['side'] as int, s['to'] as int), s['out']);
  });

  test('depth map', () {
    for (final (name, subject) in [('withSubject', numbers(c['subject'])), ('withoutSubject', null)]) {
      final want = c[name] as Map<String, dynamic>;
      final map = depthMap(rgb, side, subject);
      close(map.depth, want['depth']);
      close(map.shadow, want['shadow']);
      close(map.subject, want['subject']);
      final centre = depthCentre(map.depth, side);
      close([centre.dx, centre.dy], want['centre']);
      expect(depthPixels(map), [
        for (var i = 0; i < side * side; i++) ...[...(want['pixels'] as List).sublist(i * 3, i * 3 + 3), 255],
      ]);
    }
  });
}
