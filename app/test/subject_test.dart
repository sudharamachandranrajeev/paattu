// The same cases as tests/test_depth.py: the app and the desktop Paattu must
// lift the same covers alike.

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:paattu/src/subject.dart';

const side = 50;

/// A guess with a solid square subject between (x0, y0) and (x1, y1).
List<double> blob(int x0, int y0, int x1, int y1, {double inside = 0.95, double outside = 0.02}) => [
      for (var y = 0; y < side; y++)
        for (var x = 0; x < side; x++) x0 <= x && x < x1 && y0 <= y && y < y1 ? inside : outside,
    ];

void main() {
  group('cleanMask', () {
    test('a clear subject', () {
      final mask = cleanMask(blob(10, 20, 30, 40), side)!;
      expect(mask.area, closeTo(0.16, 1e-9));
      expect(mask.centre.dx, closeTo(0.4, 0.05));
      expect(mask.centre.dy, closeTo(0.6, 0.05));
      expect(mask.alpha[25 * side + 20], 1.0);
      expect(mask.alpha[5 * side + 5], 0.0);
    });

    test('edges fade out', () {
      // A subject cut off by the bottom of the frame fades out there.
      final alpha = cleanMask(blob(15, 30, 35, side), side)!.alpha;
      expect(alpha[(side - 1) * side + 25], 0.0);
      expect(alpha[(side - 2) * side + 25], greaterThan(0.0));
      expect(alpha[(side - 2) * side + 25], lessThan(1.0));
      expect(alpha[40 * side + 25], 1.0);
    });

    test('holes', () {
      // A patch inside the subject the model was unsure of is filled; one it
      // was sure is background (between an arm and the body) is kept.
      for (final (inner, expected) in [(0.3, 1.0), (0.02, 0.0)]) {
        final guess = blob(10, 10, 40, 40);
        for (var y = 23; y < 27; y++) {
          for (var x = 23; x < 27; x++) {
            guess[y * side + x] = inner;
          }
        }
        expect(cleanMask(guess, side)!.alpha[25 * side + 25], closeTo(expected, 1e-6), reason: '$inner');
      }
    });

    test('no good guesses', () {
      expect(cleanMask(List.filled(side * side, 0.3), side), isNull, reason: 'nothing stands out');
      expect(cleanMask(blob(10, 10, 30, 30, inside: 0.4), side), isNull, reason: 'nothing is sure');
      expect(cleanMask(blob(20, 20, 24, 24), side), isNull, reason: 'a speck');
      expect(cleanMask(blob(0, 0, side, 46), side), isNull, reason: 'most of the picture');
      final haze = [
        for (var y = 0; y < side; y++)
          for (var x = 0; x < side; x++) 0.5 + 0.45 * ((x + y) % 7 - 3) / 3,
      ];
      expect(cleanMask(haze, side), isNull, reason: 'a haze');
      expect(cleanMask(blob(10, 20, 30, 40).sublist(1), side), isNull, reason: 'the wrong size');
      expect(cleanMask([double.nan, ...blob(10, 20, 30, 40).skip(1)], side), isNull, reason: 'NaN');
    });
  });

  test('modelInput is scaled by the brightest, then normalised', () {
    final input = modelInput(Uint8List.fromList([100, 200, 50, 255, 0, 0, 0, 255]));
    expect(input.length, 6);
    expect(input[0], closeTo((100 / 200 - 0.485) / 0.229, 1e-6));
    expect(input[2], closeTo((200 / 200 - 0.456) / 0.224, 1e-6));
    expect(input[5], closeTo((0 - 0.406) / 0.225, 1e-6));
  });
}
