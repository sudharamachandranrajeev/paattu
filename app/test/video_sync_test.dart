// The picture's speed in video mode (video_background.dart): a steady small
// correction, none for the noise in a reading.

import 'package:flutter_test/flutter_test.dart';
import 'package:paattu/src/ui/video_background.dart';

void main() {
  test('in line, or nearly: normal speed', () {
    for (final drift in [0.0, 30.0, -59.0]) {
      expect(videoNudge(drift), 1.0, reason: '$drift ms');
    }
  });

  test('ahead runs slower, behind faster, 1% a 50 ms, up to 4%', () {
    expect(videoNudge(100), 0.98);
    expect(videoNudge(-100), 1.02);
    expect(videoNudge(500), 0.96);
    expect(videoNudge(-500), 1.04);
  });
}
