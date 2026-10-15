// The subject of a song's cover (the people in it, mostly) cut out of the
// picture, for Now Playing to lift out of it in 3D. Android asks ML Kit's
// subject segmentation (part of Google Play services); Windows and Linux run
// U²-Net's small model (models/u2netp.onnx, bundled beside the app) with
// ONNX Runtime. Nothing leaves the device.

import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';
import 'package:google_mlkit_subject_segmentation/google_mlkit_subject_segmentation.dart' as mlkit;
import 'package:path_provider/path_provider.dart';

import 'log.dart';
import 'track.dart';
import 'util.dart';

/// The side of the square the subject is looked for in (U²-Net's input).
const maskSide = 320;

/// The side the cover is kept at for showing (the size of the largest
/// YouTube thumbnail's height).
const _pictureSide = 720;

/// A cover with its subject found.
class CoverSubject {
  CoverSubject({required this.picture, required this.mask, required this.centre});

  /// The cover, cut square as the app shows it.
  final ui.Image picture;

  /// The subject: opaque where it is, see-through elsewhere ([maskSide] square).
  final ui.Image mask;

  /// The subject's middle, 0 to 1 across and down the picture.
  final Offset centre;
}

/// A guess at the subject, cleaned up for lifting out of the picture.
class SubjectMask {
  SubjectMask(this.alpha, this.centre, this.area);

  /// How much each pixel is the subject, 0 to 1, row by row.
  final Float32List alpha;

  /// The subject's middle, 0 to 1 across and down.
  final Offset centre;

  /// How much of the picture the subject covers, 0 to 1.
  final double area;
}

/// What [raw] (a [side] by [side] guess at how much each pixel is the
/// subject) leaves to lift: stretched to 0–1, made firmer (the guess is often
/// unsure inside the subject, which would let the picture behind show
/// through) and faded out at the picture's edges, where a subject cut off by
/// the frame would otherwise show a hard line once lifted. Unsure patches the
/// subject closes around (a shirt the model half missed) are filled; what it
/// is sure is background (the gap between an arm and the body) is kept.
/// paattu/depth.py does the same for the Omarchy app. Null when the guess is
/// no good: nothing stands out, the subject is a speck or most of the
/// picture, or it is a haze, not a shape.
SubjectMask? cleanMask(List<double> raw, int side) {
  final n = side * side;
  if (raw.length != n || n == 0) return null;
  var lo = double.infinity, hi = double.negativeInfinity;
  for (final v in raw) {
    if (!v.isFinite) return null;
    if (v < lo) lo = v;
    if (v > hi) hi = v;
  }
  if (!(hi >= 0.5 && hi - lo > 0.3)) return null;
  final span = hi - lo;
  final edge = max(1, (side * 0.04).round());
  final alpha = Float32List(n);
  var solid = 0, haze = 0;
  var sx = 0.0, sy = 0.0, sum = 0.0;
  for (var y = 0; y < side; y++) {
    for (var x = 0; x < side; x++) {
      final i = y * side + x;
      final a = (raw[i] - lo) / span;
      if (a > 0.5) solid++;
      if (a > 0.15 && a < 0.85) haze++;
      final t = ((a - 0.2) / 0.6).clamp(0.0, 1.0);
      final firm = t * t * (3 - 2 * t);
      final border = min(min(x, y), min(side - 1 - x, side - 1 - y));
      alpha[i] = border >= edge ? firm : firm * border / edge;
      sx += x * a;
      sy += y * a;
      sum += a;
    }
  }
  final area = solid / n;
  if (area < 0.03 || area > 0.8 || haze > solid) return null;
  // Close the subject (grow it, then shrink it back, by `reach`): what that
  // adds is gaps and dents narrower than twice `reach`. Of that, the unsure
  // pixels become subject, fading in over a few pixels so no hard line shows.
  final reach = max(1, (side * 0.03).round());
  final grown = _distances([for (final v in raw) (v - lo) / span > 0.5], side, reach);
  final inside = _distances([for (final d in grown) d > reach], side, reach + 3);
  for (var i = 0; i < n; i++) {
    final fill = (inside[i] - reach) / 3;
    if (fill <= 0) continue;
    final a = (raw[i] - lo) / span;
    final sure = ((a - 0.1) / 0.1).clamp(0.0, 1.0);
    final y = i ~/ side, x = i % side;
    final border = min(min(x, y), min(side - 1 - x, side - 1 - y));
    final keep = min(1.0, fill) * sure * (border >= edge ? 1.0 : border / edge);
    if (keep > alpha[i]) alpha[i] = keep;
  }
  return SubjectMask(alpha, Offset((sx / sum + 0.5) / side, (sy / sum + 0.5) / side), area);
}

/// How many steps (across, down or corner to corner) each pixel is from the
/// nearest of [seeds], counted up to [limit] + 1.
List<int> _distances(List<bool> seeds, int side, int limit) {
  final far = limit + 1;
  final distance = List<int>.filled(seeds.length, far);
  var frontier = <int>[];
  for (var i = 0; i < seeds.length; i++) {
    if (seeds[i]) {
      distance[i] = 0;
      frontier.add(i);
    }
  }
  var step = 0;
  while (frontier.isNotEmpty && step < limit) {
    step++;
    final reached = <int>[];
    for (final i in frontier) {
      final y = i ~/ side, x = i % side;
      for (var ny = max(0, y - 1); ny < min(side, y + 2); ny++) {
        for (var nx = max(0, x - 1); nx < min(side, x + 2); nx++) {
          final j = ny * side + nx;
          if (distance[j] == far) {
            distance[j] = step;
            reached.add(j);
          }
        }
      }
    }
    frontier = reached;
  }
  return distance;
}

/// U²-Net's input from a [maskSide] square of RGBA pixels: scaled by the
/// brightest value, then each channel set against ImageNet's mean and spread,
/// as the model was trained.
Float32List modelInput(Uint8List rgba) {
  const mean = [0.485, 0.456, 0.406];
  const spread = [0.229, 0.224, 0.225];
  final n = rgba.length ~/ 4;
  var top = 1;
  for (var i = 0; i < n; i++) {
    top = max(top, max(rgba[i * 4], max(rgba[i * 4 + 1], rgba[i * 4 + 2])));
  }
  final input = Float32List(3 * n);
  for (var i = 0; i < n; i++) {
    for (var c = 0; c < 3; c++) {
      input[c * n + i] = (rgba[i * 4 + c] / top - mean[c]) / spread[c];
    }
  }
  return input;
}

// Covers seen lately, by picture address: a song played again, or Now
// Playing opened again, finds its subject at once.
final _found = LinkedHashMap<String, Future<CoverSubject?>>();

/// The subject of [track]'s cover, or null for a cover without one to lift
/// (or none at all).
Future<CoverSubject?> subjectOf(Json track) async {
  final url = trackArt(track, large: true);
  if (url == null || url.isEmpty) return null;
  final found = _found.remove(url) ?? _find(url, trackArtFallback(track));
  _found[url] = found;
  while (_found.length > 12) {
    _found.remove(_found.keys.first);
  }
  try {
    return await found;
  } catch (error) {
    // A failure (no network, ML Kit still fetching its model) is tried again
    // next time; a cover without a subject is not.
    if (identical(_found[url], found)) {
      _found.remove(url);
      problemLog.warn("couldn't find the subject of ${trackTitle(track)}'s cover: ${errorText(error)}");
    }
    return null;
  }
}

Future<CoverSubject?> _find(String url, String? fallback) async {
  ui.Image cover;
  try {
    cover = await _load(url);
  } catch (_) {
    if (fallback == null) rethrow;
    cover = await _load(fallback);
  }
  try {
    final small = await _square(cover, maskSide);
    final List<double>? raw;
    try {
      raw = Platform.isAndroid ? await _mlKit(small) : await _u2net(small);
    } finally {
      small.dispose();
    }
    if (raw == null) return null;
    final mask = cleanMask(raw, maskSide);
    if (mask == null) return null;
    return CoverSubject(
      picture: await _square(cover, min(_pictureSide, min(cover.width, cover.height))),
      mask: await _maskImage(mask.alpha),
      centre: mask.centre,
    );
  } finally {
    cover.dispose();
  }
}

Future<ui.Image> _load(String url) {
  final done = Completer<ui.Image>();
  final stream = NetworkImage(url).resolve(ImageConfiguration.empty);
  late final ImageStreamListener listener;
  listener = ImageStreamListener((info, _) {
    stream.removeListener(listener);
    if (!done.isCompleted) done.complete(info.image.clone());
    info.dispose();
  }, onError: (error, stack) {
    stream.removeListener(listener);
    if (!done.isCompleted) done.completeError(error, stack);
  });
  stream.addListener(listener);
  return done.future.timeout(const Duration(seconds: 20));
}

/// The middle square of [image], [side] pixels across, as the app shows covers.
Future<ui.Image> _square(ui.Image image, int side) async {
  final short = min(image.width, image.height).toDouble();
  final from = Rect.fromLTWH((image.width - short) / 2, (image.height - short) / 2, short, short);
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawImageRect(
      image, from, Rect.fromLTWH(0, 0, side.toDouble(), side.toDouble()), Paint()..filterQuality = FilterQuality.high);
  final picture = recorder.endRecording();
  try {
    return await picture.toImage(side, side);
  } finally {
    picture.dispose();
  }
}

Future<ui.Image> _maskImage(Float32List alpha) {
  final pixels = Uint8List(alpha.length * 4);
  for (var i = 0; i < alpha.length; i++) {
    // Only the alpha counts; the same value in every channel reads the same
    // whether the pixels are taken as premultiplied or not.
    final a = (alpha[i] * 255).round().clamp(0, 255);
    pixels[i * 4] = pixels[i * 4 + 1] = pixels[i * 4 + 2] = pixels[i * 4 + 3] = a;
  }
  final done = Completer<ui.Image>();
  ui.decodeImageFromPixels(pixels, maskSide, maskSide, ui.PixelFormat.rgba8888, done.complete);
  return done.future;
}

/// Android: ML Kit, which wants the picture as a file.
Future<List<double>?> _mlKit(ui.Image square) async {
  final png = await square.toByteData(format: ui.ImageByteFormat.png);
  if (png == null) return null;
  final file = File('${(await getTemporaryDirectory()).path}/cover-subject-${DateTime.now().microsecondsSinceEpoch}.png');
  await file.writeAsBytes(png.buffer.asUint8List(png.offsetInBytes, png.lengthInBytes));
  final segmenter = mlkit.SubjectSegmenter(
    options: mlkit.SubjectSegmenterOptions(
      enableForegroundBitmap: false,
      enableForegroundConfidenceMask: true,
      enableMultipleSubjects: mlkit.SubjectResultOptions(enableConfidenceMask: false, enableSubjectBitmap: false),
    ),
  );
  try {
    final result = await segmenter.processImage(mlkit.InputImage.fromFilePath(file.path));
    return result.foregroundConfidenceMask;
  } finally {
    unawaited(segmenter.close());
    unawaited(file.delete().then((_) {}, onError: (Object _) {}));
  }
}

Future<OrtSession>? _session;

/// Windows and Linux: U²-Net with ONNX Runtime. The model sits in the app's
/// data folder, beside the executable.
Future<List<double>?> _u2net(ui.Image square) async {
  final pixels = await square.toByteData(format: ui.ImageByteFormat.rawRgba);
  if (pixels == null) return null;
  final model = '${File(Platform.resolvedExecutable).parent.path}${Platform.pathSeparator}data'
      '${Platform.pathSeparator}u2netp.onnx';
  final session = await (_session ??= OnnxRuntime().createSession(model).catchError((Object error) {
    _session = null;
    throw error;
  }));
  final input = await OrtValue.fromList(
      modelInput(pixels.buffer.asUint8List(pixels.offsetInBytes, pixels.lengthInBytes)), [1, 3, maskSide, maskSide]);
  Map<String, OrtValue> outputs = const {};
  try {
    outputs = await session.run({session.inputNames.first: input});
    final mask = outputs[session.outputNames.first];
    return mask == null ? null : [for (final v in await mask.asFlattenedList()) (v as num).toDouble()];
  } finally {
    await input.dispose();
    for (final output in outputs.values) {
      await output.dispose();
    }
  }
}
