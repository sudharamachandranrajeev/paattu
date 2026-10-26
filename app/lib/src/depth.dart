// A depth map of a song's cover, for the cover in 3D (ui/depth_cover.dart):
// how near each point of the picture is, so a shader can move each by that
// as the cover leans and the subject glides over what is behind it in one
// piece, with no cut-out edge to show. From the subject's mask where
// subject.dart finds one (softened a lot, so a mask a little off only moves a
// little more or less); otherwise from the cover's own sections, the few
// colours it is made of, nearer the more central, colourful and away from
// its edges they are. The same as paattu/depth.py for the Omarchy app
// (tests/depth_cases.json).

import 'dart:math';
import 'dart:typed_data';
import 'dart:ui';

/// The side of the depth map.
const depthSide = 64;

/// How many colours a cover is taken apart into when no subject stands out.
const depthRegions = 5;

double _far(List<double> a, List<double> b) {
  final r = a[0] - b[0], g = a[1] - b[1], bl = a[2] - b[2];
  return r * r + g * g + bl * bl;
}

/// The few colours a [side] by [side] square of RGB bytes is made of: the
/// label of each pixel, and the colours. k-means, started from the average
/// colour and then each time the pixel furthest from every colour so far,
/// so the same picture always comes apart the same way.
(List<int>, List<List<double>>) regions(List<int> rgb, int side, {int k = depthRegions, int rounds = 6}) {
  final n = side * side;
  final pixels = [
    for (var i = 0; i < n; i++) [rgb[i * 3].toDouble(), rgb[i * 3 + 1].toDouble(), rgb[i * 3 + 2].toDouble()],
  ];
  final total = [0.0, 0.0, 0.0];
  for (final p in pixels) {
    total[0] += p[0];
    total[1] += p[1];
    total[2] += p[2];
  }
  var centres = [
    [total[0] / n, total[1] / n, total[2] / n],
  ];
  var nearest = [for (final p in pixels) _far(p, centres[0])];
  while (centres.length < k) {
    var best = 0;
    for (var i = 1; i < n; i++) {
      if (nearest[i] > nearest[best]) best = i;
    }
    if (nearest[best] < 1) break;
    final added = pixels[best];
    centres.add(added);
    nearest = [for (var i = 0; i < n; i++) min(nearest[i], _far(pixels[i], added))];
  }

  List<int> assign() {
    final labels = List.filled(n, 0);
    for (var i = 0; i < n; i++) {
      var best = 0;
      var gap = _far(pixels[i], centres[0]);
      for (var c = 1; c < centres.length; c++) {
        final d = _far(pixels[i], centres[c]);
        if (d < gap) {
          best = c;
          gap = d;
        }
      }
      labels[i] = best;
    }
    return labels;
  }

  for (var round = 0; round < rounds; round++) {
    final labels = assign();
    final sums = [
      for (var c = 0; c < centres.length; c++) [0.0, 0.0, 0.0, 0.0],
    ];
    for (var i = 0; i < n; i++) {
      final s = sums[labels[i]];
      s[0] += pixels[i][0];
      s[1] += pixels[i][1];
      s[2] += pixels[i][2];
      s[3] += 1;
    }
    centres = [
      for (var c = 0; c < centres.length; c++)
        sums[c][3] > 0 ? [sums[c][0] / sums[c][3], sums[c][1] / sums[c][3], sums[c][2] / sums[c][3]] : centres[c],
    ];
  }
  return (assign(), centres);
}

/// Each pixel takes the label most of the 3 by 3 around it have (its own on
/// a tie), so specks don't become layers of their own.
List<int> _tidy(List<int> labels, int side, int k) {
  final out = List.of(labels);
  for (var y = 0; y < side; y++) {
    for (var x = 0; x < side; x++) {
      final counts = List.filled(k, 0);
      for (var ny = max(0, y - 1); ny < min(side, y + 2); ny++) {
        for (var nx = max(0, x - 1); nx < min(side, x + 2); nx++) {
          counts[labels[ny * side + nx]]++;
        }
      }
      var best = labels[y * side + x];
      for (var c = 0; c < k; c++) {
        if (counts[c] > counts[best]) best = c;
      }
      out[y * side + x] = best;
    }
  }
  return out;
}

/// How near each pixel of a [side] by [side] square of RGB bytes is, 0 to 1,
/// when nothing in it stands out as its subject: each of its colours a
/// layer, nearer the more central, colourful and away from the picture's
/// edges it is. All one depth (0.5) when no layer stands out from the rest.
List<double> regionDepth(List<int> rgb, int side) {
  final (found, colours) = regions(rgb, side);
  final k = colours.length;
  final labels = _tidy(found, side, k);
  final n = side * side;
  final count = List.filled(k, 0), ring = List.filled(k, 0);
  final middle = List.filled(k, 0.0);
  var rim = 0;
  for (var i = 0; i < n; i++) {
    final c = labels[i], y = i ~/ side, x = i % side;
    count[c]++;
    if (x == 0 || y == 0 || x == side - 1 || y == side - 1) {
      ring[c]++;
      rim++;
    }
    final dx = (x + 0.5) / side - 0.5, dy = (y + 0.5) / side - 0.5;
    middle[c] += min(1.0, sqrt(dx * dx + dy * dy) / sqrt(0.5));
  }
  final score = List.filled(k, 0.0);
  for (var c = 0; c < k; c++) {
    if (count[c] == 0) continue;
    final touch = (ring[c] / rim) / (count[c] / n);
    final top = colours[c].reduce(max), low = colours[c].reduce(min);
    final colourful = top > 0 ? (top - low) / top : 0.0;
    score[c] = 0.45 * (1 - middle[c] / count[c]) + 0.2 * colourful + 0.35 / (1 + touch);
  }
  final used = [
    for (var c = 0; c < k; c++)
      if (count[c] > 0) score[c],
  ];
  final lo = used.reduce(min), hi = used.reduce(max);
  final level = [for (final s in score) hi - lo > 0.05 ? (s - lo) / (hi - lo) : 0.5];
  return [for (final c in labels) level[c]];
}

/// A [side] by [side] square of values, blurred (Gaussian, the edges held).
List<double> blur(List<double> values, int side, double sigma) {
  final reach = (sigma * 3).ceil();
  final weights = [for (var i = -reach; i <= reach; i++) exp(-(i * i) / (2 * sigma * sigma))];
  final total = weights.fold(0.0, (a, b) => a + b);
  for (var i = 0; i < weights.length; i++) {
    weights[i] /= total;
  }
  final across = List.filled(side * side, 0.0);
  for (var y = 0; y < side; y++) {
    final row = y * side;
    for (var x = 0; x < side; x++) {
      var v = 0.0;
      for (var j = 0; j < weights.length; j++) {
        v += values[row + (x + j - reach).clamp(0, side - 1)] * weights[j];
      }
      across[row + x] = v;
    }
  }
  final out = List.filled(side * side, 0.0);
  for (var y = 0; y < side; y++) {
    for (var x = 0; x < side; x++) {
      var v = 0.0;
      for (var j = 0; j < weights.length; j++) {
        v += across[(y + j - reach).clamp(0, side - 1) * side + x] * weights[j];
      }
      out[y * side + x] = v;
    }
  }
  return out;
}

/// A [side] by [side] square of values, [to] across: each the average of the
/// block it covers ([side] a multiple of [to]).
List<double> shrink(List<double> values, int side, int to) {
  final step = side ~/ to;
  final out = List.filled(to * to, 0.0);
  for (var y = 0; y < to; y++) {
    for (var x = 0; x < to; x++) {
      var v = 0.0;
      for (var dy = 0; dy < step; dy++) {
        final row = (y * step + dy) * side + x * step;
        for (var dx = 0; dx < step; dx++) {
          v += values[row + dx];
        }
      }
      out[y * to + x] = v / (step * step);
    }
  }
  return out;
}

/// A cover's depth map, [depthSide] square.
class DepthMap {
  DepthMap(this.depth, this.shadow, this.subject);

  /// How near each point is, soft, so a cut-out a little off doesn't show.
  final List<double> depth;

  /// The subject's shadow on what is behind it.
  final List<double> shadow;

  /// Where the subject is, a little soft (all 0 without one).
  final List<double> subject;
}

/// The depth map of a [side] by [side] square of RGB bytes and, if it has
/// one, how much each pixel is its subject.
DepthMap depthMap(List<int> rgb, int side, [List<double>? subject]) {
  final layers = blur(regionDepth(rgb, side), side, side / 32);
  if (subject == null) {
    return DepthMap(layers, List.filled(side * side, 0.0), List.filled(side * side, 0.0));
  }
  // Softened, then brought back up (so a slim subject is as near as a broad
  // one) and past full from its edge in: the subject is all one depth and
  // moves in one piece, a face never stretched across, and only what is
  // behind it stretches round its edge.
  var lifted = blur(subject, side, side / 20);
  final top = lifted.reduce(max);
  if (top > 0) lifted = [for (final v in lifted) min(1.0, 2 * v / top)];
  return DepthMap(
    [for (var i = 0; i < lifted.length; i++) 0.25 * layers[i] * (1 - lifted[i]) + lifted[i]],
    [for (final v in blur(subject, side, side / 16)) 0.55 * v],
    blur(subject, side, side / 80),
  );
}

/// Where the nearest of a depth map is, 0 to 1 across and down.
Offset depthCentre(List<double> depth, int side) {
  var sx = 0.0, sy = 0.0, total = 0.0;
  for (var i = 0; i < depth.length; i++) {
    final w = depth[i] * depth[i];
    sx += (i % side + 0.5) * w;
    sy += (i ~/ side + 0.5) * w;
    total += w;
  }
  return total <= 0 ? const Offset(0.5, 0.5) : Offset(sx / total / side, sy / total / side);
}

/// The depth map as RGBA bytes: depth in red, shadow in green, subject in
/// blue, opaque.
Uint8List depthPixels(DepthMap map) {
  final out = Uint8List(map.depth.length * 4);
  int byte(double v) => (v * 255 + 0.5).floor().clamp(0, 255);
  for (var i = 0; i < map.depth.length; i++) {
    out[i * 4] = byte(map.depth[i]);
    out[i * 4 + 1] = byte(map.shadow[i]);
    out[i * 4 + 2] = byte(map.subject[i]);
    out[i * 4 + 3] = 255;
  }
  return out;
}
