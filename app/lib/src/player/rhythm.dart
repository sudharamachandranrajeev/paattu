// The song's rhythm, for the rings around Now Playing's play button: how loud
// it is and where the beats hit, 50 times a second, worked out once from the
// song's file and kept. The file is the one the player already has (kept on
// this device, or downloaded ahead), else the song is downloaded for it (not
// while saving data). Decoding is the platform's: Android's MediaCodec, or a
// silent libmpv player on the desktop that writes the sound to a file as
// fast as it can decode it.

import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/services.dart' show MethodChannel;
import 'package:media_kit/media_kit.dart';

import '../log.dart';

/// How loud the song is and how hard its beats hit, [fps] times a second,
/// each 0 (quiet, nothing) to 1.
class Rhythm {
  const Rhythm(this.level, this.punch);

  /// Frames a second.
  static const fps = 50;

  /// Loudness, against the song's own loud parts (30 dB below them is 0).
  final Uint8List level;

  /// How sharply the low end (the kick, the bass, the drums) rises.
  final Uint8List punch;

  int get length => level.length;

  /// The frame at [at] into the song (clamped).
  int frameAt(Duration at) => (at.inMicroseconds * fps ~/ Duration.microsecondsPerSecond).clamp(0, max(0, length - 1));

  double levelOf(int frame) => length == 0 ? 0 : level[frame] / 255;

  /// The hardest beat from frame [from] to [to] (inclusive), so a frame
  /// skipped between two screen refreshes still counts.
  double punchBetween(int from, int to) {
    if (length == 0) return 0;
    var most = 0;
    for (var i = max(0, from); i <= min(to, length - 1); i++) {
      if (punch[i] > most) most = punch[i];
    }
    return most / 255;
  }

  static const _version = 1;

  /// Kept as: version, frame count (4 bytes), the levels, the punches.
  Uint8List toBytes() {
    final out = BytesBuilder(copy: false)
      ..addByte(_version)
      ..add((ByteData(4)..setUint32(0, length)).buffer.asUint8List())
      ..add(level)
      ..add(punch);
    return out.takeBytes();
  }

  /// Null for a file from another version (or a broken one).
  static Rhythm? fromBytes(Uint8List bytes) {
    if (bytes.length < 5 || bytes[0] != _version) return null;
    final n = ByteData.sublistView(bytes, 1, 5).getUint32(0);
    if (bytes.length != 5 + 2 * n) return null;
    return Rhythm(Uint8List.sublistView(bytes, 5, 5 + n), Uint8List.sublistView(bytes, 5 + n));
  }
}

/// The rhythm of [pcm], mono samples at [rate] a second.
///
/// Each frame's loudness is its mean square, in decibels against the song's
/// loud parts (the 95th percentile). The beats come from the low end alone
/// (a one-pole low-pass at 150 Hz): how far its loudness rises over the two
/// frames before, against the song's sharper rises (the 90th percentile of
/// them, square-rooted so the smaller beats show too),
/// and nothing where the song is near silent.
Rhythm analyse(Int16List pcm, int rate) {
  final hop = rate / Rhythm.fps;
  final n = hop <= 0 ? 0 : (pcm.length / hop).floor();
  final level = Uint8List(n), punch = Uint8List(n);
  if (n == 0) return Rhythm(level, punch);
  final a = exp(-2 * pi * 150 / rate);
  final loud = Float64List(n), low = Float64List(n);
  var lowpass = 0.0;
  for (var f = 0; f < n; f++) {
    final start = (f * hop).floor(), end = ((f + 1) * hop).floor();
    var all = 0.0, bass = 0.0;
    for (var s = start; s < end; s++) {
      final x = pcm[s] / 32768;
      lowpass = lowpass * a + (1 - a) * x;
      all += x * x;
      bass += lowpass * lowpass;
    }
    final count = max(1, end - start);
    loud[f] = _decibels(all / count);
    low[f] = _decibels(bass / count);
  }
  final top = _percentile(loud, 0.95);
  final levels = Float64List(n);
  for (var f = 0; f < n; f++) {
    levels[f] = ((loud[f] - (top - 30)) / 30).clamp(0.0, 1.0);
    level[f] = (levels[f] * 255).round();
  }
  final rises = Float64List(n);
  for (var f = 2; f < n; f++) {
    rises[f] = max(0.0, low[f] - max(low[f - 1], low[f - 2]));
  }
  final sharp = _percentile(rises.where((r) => r > 0).toList(), 0.9);
  if (sharp > 0) {
    for (var f = 0; f < n; f++) {
      final gate = ((levels[f] - 0.15) / 0.2).clamp(0.0, 1.0);
      punch[f] = (sqrt((rises[f] / sharp).clamp(0.0, 1.0)) * gate * 255).round();
    }
  }
  return Rhythm(level, punch);
}

double _decibels(double meanSquare) => 10 * log(meanSquare + 1e-10) / ln10;

double _percentile(List<double> values, double p) {
  if (values.isEmpty) return 0;
  final sorted = List.of(values)..sort();
  return sorted[((sorted.length - 1) * p).round()];
}

/// Works out songs' rhythms (one at a time) and keeps them in [dir].
class RhythmFinder {
  RhythmFinder(this.dir);

  final Directory dir;

  /// Rhythms kept; the least recently used go.
  static const keep = 300;

  /// Samples a second decoded: plenty for loudness and the low end.
  static const _rate = 11025;

  static const _android = MethodChannel('dev.paattu.paattu/rhythm');

  final _known = <String, Rhythm>{};
  final _jobs = <String, Future<Rhythm?>>{};
  Future<void> _queue = Future.value();
  bool _trimmed = false;

  /// The rhythm of song [key], worked out from the file [song] gives (null:
  /// no file to be had) unless already known. Null when it can't be.
  Future<Rhythm?> of(String key, Future<File?> Function() song) {
    final known = _known[key];
    if (known != null) return Future.value(known);
    return _jobs[key] ??= _find(key, song).whenComplete(() {
      _jobs.remove(key);
    });
  }

  Future<Rhythm?> _find(String key, Future<File?> Function() song) async {
    final kept = File('${dir.path}${Platform.pathSeparator}${_safeName(key)}.rhythm');
    try {
      if (await kept.exists()) {
        final rhythm = Rhythm.fromBytes(await kept.readAsBytes());
        if (rhythm != null) {
          unawaited(kept.setLastModified(DateTime.now()).catchError((Object _) {}));
          return _known[key] = rhythm;
        }
      }
    } catch (_) {
      // Worked out again below.
    }
    // One decode at a time: a song changed quickly doesn't pile them up.
    final turn = Completer<void>();
    final before = _queue;
    _queue = turn.future;
    await before;
    try {
      final file = await song();
      if (file == null) return null;
      final clock = Stopwatch()..start();
      final pcm = File('${dir.path}${Platform.pathSeparator}decoding.pcm');
      await dir.create(recursive: true);
      final rate = await _decode(file, pcm);
      final bytes = await pcm.readAsBytes();
      unawaited(pcm.delete().then((_) {}, onError: (Object _) {}));
      final rhythm = await Isolate.run(() => analyse(Int16List.sublistView(bytes, 0, bytes.length ~/ 2 * 2), rate));
      if (rhythm.length == 0) return null;
      await kept.writeAsBytes(rhythm.toBytes(), flush: true);
      problemLog.info('rhythm of $key: ${rhythm.length ~/ Rhythm.fps} s in ${clock.elapsedMilliseconds} ms');
      unawaited(_trim());
      return _known[key] = rhythm;
    } catch (error) {
      problemLog.warn('rhythm of $key: $error');
      return null;
    } finally {
      turn.complete();
    }
  }

  /// Decode [song] into [pcm] as 16-bit mono; the samples a second.
  Future<int> _decode(File song, File pcm) async {
    if (Platform.isAndroid) {
      final rate = await _android.invokeMethod<int>('decode', {'path': song.path, 'out': pcm.path, 'rate': _rate});
      return rate!;
    }
    final player = Player(configuration: const PlayerConfiguration(title: 'Paattu rhythm', bufferSize: 4 << 20));
    try {
      final mpv = player.platform as NativePlayer;
      for (final (name, value) in [
        ('ao', 'pcm'),
        ('ao-pcm-file', pcm.path),
        ('ao-pcm-waveheader', 'no'),
        ('audio-format', 's16'),
        ('audio-channels', 'mono'),
        ('audio-samplerate', '$_rate'),
      ]) {
        await mpv.setProperty(name, value);
      }
      final failed = player.stream.error.first.then<void>((message) => throw StateError(message));
      final done = player.stream.completed.firstWhere((completed) => completed);
      await player.open(Media(song.path));
      await Future.any([done, failed]).timeout(const Duration(minutes: 2));
      return _rate;
    } finally {
      await player.dispose();
    }
  }

  /// Keep the [keep] most recently used.
  Future<void> _trim() async {
    if (_trimmed) return;
    _trimmed = true;
    final files = <(File, DateTime)>[];
    await for (final entry in dir.list()) {
      if (entry is File && entry.path.endsWith('.rhythm')) files.add((entry, await entry.lastModified()));
    }
    if (files.length <= keep) return;
    files.sort((a, b) => b.$2.compareTo(a.$2));
    for (final (file, _) in files.skip(keep)) {
      await file.delete().then((_) {}, onError: (Object _) {});
    }
  }

  static String _safeName(String key) => key.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
}
