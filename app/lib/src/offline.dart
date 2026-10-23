// Songs kept on this device: a folder of audio files the player reads instead
// of streaming, so the songs you listen to keep playing with no internet and
// no data. The folder carries its own index (paattu-offline.json) so it can be
// copied to another device and still make sense.
//
// Songs arrive two ways: by themselves as you listen (a play that counts, by
// history.dart's rule) and by hand, from a song's menu or the Offline page.
// Past the space allowed, the songs used least recently go first.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'log.dart';
import 'player/download.dart';
import 'sources/http.dart';
import 'track.dart';
import 'util.dart';

/// The index beside the songs.
const offlineIndex = 'paattu-offline.json';

/// A song too big to be worth keeping (a long jukebox or a whole concert).
const offlineMaxSongBytes = 150 << 20;

/// One song kept offline.
class OfflineEntry {
  const OfflineEntry({
    required this.key,
    required this.file,
    required this.bytes,
    required this.saved,
    required this.used,
    required this.plays,
    required this.codec,
    required this.kbps,
    required this.track,
  });

  factory OfflineEntry.fromJson(String key, Json json) => OfflineEntry(
        key: key,
        file: asString(json['file']),
        bytes: toInt(json['bytes']) ?? 0,
        saved: parseStamp(asString(json['saved'])),
        used: parseStamp(asString(json['used'])),
        plays: toInt(json['plays']) ?? 0,
        codec: asString(json['codec']),
        kbps: toInt(json['kbps']),
        track: asJson(json['track']),
      );

  final String key;

  /// Its filename inside the library's folder.
  final String file;
  final int bytes;
  final DateTime saved;

  /// When it was last played from here (what eviction goes by).
  final DateTime used;
  final int plays;
  final String codec;
  final int? kbps;
  final Json track;

  String get title => trackTitle(track);
  String get subtitle => trackSubtitle(track);

  /// "4.1 MB"
  String get size => formatBytes(bytes);

  /// "Opus · 160 kbps", as the player says of a stream.
  String get quality =>
      ResolvedStream(Uri.file(file), codec: codec, kbps: kbps, lifetime: Duration.zero).label;

  Json toJson() => <String, dynamic>{
        'file': file,
        'bytes': bytes,
        'saved': stamp(saved),
        'used': stamp(used),
        'plays': plays,
        'codec': codec,
        if (kbps != null) 'kbps': kbps,
        'track': track,
      };

  OfflineEntry copyWith({DateTime? used, int? plays}) => OfflineEntry(
        key: key,
        file: file,
        bytes: bytes,
        saved: saved,
        used: used ?? this.used,
        plays: plays ?? this.plays,
        codec: codec,
        kbps: kbps,
        track: track,
      );
}

class OfflineLibrary extends ChangeNotifier {
  OfflineLibrary(this.dir, {this.limitBytes = defaultLimitBytes});

  /// Default space allowed for kept songs.
  static const defaultLimitBytes = 2 << 30; // 2 GB

  /// Where the songs are.
  Directory dir;

  /// Space allowed; 0 or less for no limit.
  int limitBytes;

  final _songs = <String, OfflineEntry>{};
  final _jobs = <String, Future<bool>>{};
  Timer? _indexTimer;
  bool _ready = false;

  File get _indexFile => File('${dir.path}${Platform.pathSeparator}$offlineIndex');

  /// Where the songs are, to show in Settings.
  String get path => dir.path;
  bool get ready => _ready;
  int get count => _songs.length;
  int get totalBytes => _songs.values.fold(0, (sum, e) => sum + e.bytes);

  /// The songs kept, newest first.
  List<OfflineEntry> get songs {
    final all = _songs.values.toList()..sort((a, b) => b.saved.compareTo(a.saved));
    return all;
  }

  bool has(String key) => _songs.containsKey(key);
  OfflineEntry? entry(String key) => _songs[key];

  /// Read the folder: its index, and drop entries whose file has gone.
  Future<void> load() async {
    try {
      if (!await dir.exists()) await dir.create(recursive: true);
      _ready = true;
      final file = _indexFile;
      if (await file.exists()) {
        final decoded = asJson(jsonDecode(await file.readAsString()));
        final songs = asJson(decoded['songs']);
        for (final entry in songs.entries) {
          final parsed = OfflineEntry.fromJson(entry.key, asJson(entry.value));
          if (parsed.file.isEmpty) continue;
          _songs[entry.key] = parsed;
        }
      }
      // Files removed behind Paattu's back (or a copied folder) leave entries
      // pointing at nothing.
      final gone = <String>[];
      for (final entry in _songs.entries) {
        if (!await File('${dir.path}${Platform.pathSeparator}${entry.value.file}').exists()) {
          gone.add(entry.key);
        }
      }
      for (final key in gone) {
        _songs.remove(key);
      }
      // A folder copied in, or a smaller space allowed while Paattu was shut:
      // fit it now rather than waiting for the next song to be kept.
      final over = limitBytes > 0 && totalBytes > limitBytes;
      if (over) await _evict();
      if (gone.isNotEmpty || over) await _writeIndex();
      problemLog.info('offline: ${plural(_songs.length, 'song')} kept, ${formatBytes(totalBytes)} in $path');
    } catch (error) {
      // No offline library then; songs stream as they did before.
      _ready = false;
      problemLog.warn('offline library: ${errorText(error)}');
    }
    notifyListeners();
  }

  /// A song kept here as something the player can play with no network: its
  /// file, carrying the quality it was saved at. Null when it isn't kept, or
  /// its file has gone.
  Future<ResolvedStream?> localStream(String key) async {
    final entry = _songs[key];
    if (entry == null) return null;
    final file = File('${dir.path}${Platform.pathSeparator}${entry.file}');
    if (!await file.exists()) {
      await forget(key);
      return null;
    }
    return ResolvedStream(Uri.file(file.path),
        codec: entry.codec, kbps: entry.kbps, lifetime: const Duration(days: 3650));
  }

  /// The file a song is kept in, if it is.
  File? file(String key) {
    final entry = _songs[key];
    return entry == null ? null : File('${dir.path}${Platform.pathSeparator}${entry.file}');
  }

  /// Keep [track] here, finding its stream with [resolve] (the player passes
  /// its own, so a link already found is used again). Asking twice, or while
  /// one is going, waits for the same save. Whether it is kept afterwards.
  Future<bool> save(Json track, Future<ResolvedStream> Function() resolve) {
    final key = trackKey(track);
    if (trackId(track).isEmpty) return Future.value(false);
    if (_songs.containsKey(key)) return Future.value(true);
    // The callback has to be a block: `_jobs.remove` returns the job it took
    // out — this very future — and whenComplete waits on a Future its callback
    // returns, so an arrow body here would wait on itself for ever.
    return _jobs[key] ??= _save(key, track, resolve).whenComplete(() {
      _jobs.remove(key);
    });
  }

  Future<bool> _save(String key, Json track, Future<ResolvedStream> Function() resolve) async {
    if (!_ready) return false;
    try {
      final stream = await resolve();
      final name = await _fileName(track, key, stream.codec);
      final file = await downloadStream(stream, File('${dir.path}${Platform.pathSeparator}$name'),
          limit: offlineMaxSongBytes, label: key);
      if (file == null) return false;
      final now = DateTime.now();
      _songs[key] = OfflineEntry(
        key: key,
        file: name,
        bytes: await file.length(),
        saved: now,
        used: now,
        plays: 0,
        codec: stream.codec,
        kbps: stream.kbps,
        track: storedTrack(track),
      );
      await _evict();
      await _writeIndex();
      notifyListeners();
      problemLog.info('offline: kept ${trackTitle(track)} (${formatBytes(_songs[key]!.bytes)})');
      return true;
    } catch (error) {
      problemLog.warn('offline: keeping ${trackTitle(track)}: ${errorText(error)}');
      return false;
    }
  }

  /// A song was played from here: it counts as used, so it isn't evicted next.
  void notePlayed(String key) {
    final entry = _songs[key];
    if (entry == null) return;
    _songs[key] = entry.copyWith(used: DateTime.now(), plays: entry.plays + 1);
    _indexSoon();
  }

  /// Take a song out (and delete its file).
  Future<void> remove(String key) async {
    final entry = _songs.remove(key);
    if (entry == null) return;
    await _writeIndex();
    notifyListeners();
    await _deleteFile(entry.file);
  }

  /// Forget an entry whose file wouldn't play, so the song streams instead.
  Future<void> forget(String key) async {
    final entry = _songs[key];
    if (entry == null) return;
    _songs.remove(key);
    problemLog.warn('offline: ${entry.file} is not there or wouldn\'t play; forgetting it');
    await _writeIndex();
    notifyListeners();
    await _deleteFile(entry.file);
  }

  /// Empty the library: every song's file goes.
  Future<void> clear() async {
    final files = [for (final e in _songs.values) e.file];
    _songs.clear();
    await _writeIndex();
    notifyListeners();
    for (final file in files) {
      await _deleteFile(file);
    }
  }

  /// Keep songs in [folder] from now on, with [allowed] bytes of room. Called
  /// when Settings changes either; the songs already kept are carried across,
  /// so nothing is left behind in the old folder.
  Future<void> moveTo(Directory folder, {required int allowed}) async {
    if (folder.path == dir.path && allowed == limitBytes) return;
    final moved = folder.path != dir.path;
    limitBytes = allowed;
    if (moved) await _relocate(folder);
    await _evict();
    await _writeIndex();
    notifyListeners();
  }

  /// Allow [allowed] bytes of room from now on, dropping what doesn't fit.
  Future<void> applyLimit(int allowed) => moveTo(dir, allowed: allowed);

  /// Carry the songs and the index over to [folder].
  Future<void> _relocate(Directory folder) async {
    final from = dir;
    dir = folder;
    _ready = false;
    try {
      if (!await folder.exists()) await folder.create(recursive: true);
      _ready = true;
      for (final entry in _songs.values.toList()) {
        final old = File('${from.path}${Platform.pathSeparator}${entry.file}');
        final fresh = File('${folder.path}${Platform.pathSeparator}${entry.file}');
        if (await fresh.exists()) continue; // a song already kept there
        if (!await old.exists()) {
          _songs.remove(entry.key); // it isn't in either folder
          continue;
        }
        await _carry(old, fresh);
      }
      final oldIndex = File('${from.path}${Platform.pathSeparator}$offlineIndex');
      if (!await _indexFile.exists() && await oldIndex.exists()) await _carry(oldIndex, _indexFile);
      problemLog.info('offline: songs are kept in ${folder.path} now');
    } catch (error) {
      problemLog.warn('offline: moving the songs to ${folder.path}: ${errorText(error)}');
    }
  }

  /// A file carried to [to]: renamed where that works, copied where it can't
  /// (a rename doesn't cross file systems).
  static Future<void> _carry(File from, File to) async {
    try {
      await from.rename(to.path);
    } on FileSystemException {
      await from.copy(to.path);
      await from.delete();
    }
  }

  /// Drop the songs used least recently until the library fits.
  Future<void> _evict() async {
    if (limitBytes <= 0) return;
    while (totalBytes > limitBytes && _songs.length > 1) {
      final oldest = _songs.values.reduce((a, b) => a.used.isBefore(b.used) ? a : b);
      _songs.remove(oldest.key);
      problemLog.info('offline: no room left, dropped ${oldest.title}');
      await _deleteFile(oldest.file);
    }
  }

  /// A filename that says what the song is, so the folder reads like a music
  /// collection: "Vijay Yesudas - Malare.m4a".
  Future<String> _fileName(Json track, String key, String codec) async {
    final artist = asStrings(track['credits']).isNotEmpty
        ? asStrings(track['credits']).first
        : asString(track['channel']);
    final parts = [artist, trackTitle(track)].where((p) => p.trim().isNotEmpty);
    var name = parts.join(' - ');
    if (name.trim().isEmpty) name = trackId(track);
    // A name a file system takes, and no path in it.
    name = squash(name)
        .replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1f]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (name.length > 120) name = name.substring(0, 120).trim();
    if (name.isEmpty) name = trackId(track);
    var candidate = '$name${audioExtension(codec)}';
    // A file already there — the same song from another site, another song
    // called the same, or one that isn't Paattu's at all: don't write over it.
    for (var n = 2; await File('${dir.path}${Platform.pathSeparator}$candidate').exists(); n++) {
      candidate = '$name ($n)${audioExtension(codec)}';
    }
    return candidate;
  }

  /// Drop a song's file. (One being played can't be deleted on Windows; it
  /// goes next run.)
  Future<void> _deleteFile(String fileName) async {
    try {
      final file = File('${dir.path}${Platform.pathSeparator}$fileName');
      if (await file.exists()) await file.delete();
    } catch (error) {
      problemLog.warn('offline: deleting $fileName: ${errorText(error)}');
    }
  }

  /// Write the index a moment after the last change, as history.dart does.
  void _indexSoon() {
    _indexTimer?.cancel();
    _indexTimer = Timer(const Duration(seconds: 2), () => unawaited(_writeIndex()));
    notifyListeners();
  }

  Future<void> _writeIndex() async {
    _indexTimer?.cancel();
    if (!_ready) return;
    try {
      final text = const JsonEncoder.withIndent(' ').convert(<String, dynamic>{
        'version': 1,
        'songs': {for (final e in _songs.values) e.key: e.toJson()},
      });
      final tmp = File('${_indexFile.path}.tmp');
      await tmp.writeAsString(text);
      await tmp.rename(_indexFile.path);
    } catch (error) {
      problemLog.warn('offline: writing the index: ${errorText(error)}');
    }
  }

  @override
  void dispose() {
    _indexTimer?.cancel();
    super.dispose();
  }
}

/// Where the kept songs go: [chosen] (the folder picked in Settings) where
/// Paattu can write to one, else a folder of the app's own. (On Android a
/// folder of one's own needs "All files access", which Settings asks for.)
Directory keptSongsDirectory(String chosen, Directory appDir) {
  if (chosen.trim().isNotEmpty) return Directory(chosen.trim());
  return Directory('${appDir.path}${Platform.pathSeparator}offline');
}

/// "4.1 MB", "812 KB".
String formatBytes(int bytes) {
  if (bytes <= 0) return '0 KB';
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  final text = unit >= 2 ? value.toStringAsFixed(1) : value.round().toString();
  return '$text ${units[unit]}';
}

/// "2026-10-23T11:00:00Z" as a time (the epoch when it isn't one).
DateTime parseStamp(String text) => DateTime.tryParse(text) ?? DateTime.fromMillisecondsSinceEpoch(0);

/// A time as library.json writes it.
String stamp(DateTime time) => time.toUtc().toIso8601String().replaceAll(RegExp(r'\.\d+'), '');
