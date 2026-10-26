// The next songs, downloaded while this one plays, so they start at once and
// a slow or dropped connection doesn't stop them part way. Files live in the
// app's temporary folder and only for this run: the last few are kept.
// (Songs worth keeping go to the offline library, offline.dart.)

import 'dart:async';
import 'dart:io';

import '../device.dart';
import '../log.dart';
import '../sources/http.dart';
import 'download.dart';

class SongCache {
  SongCache(this.dir);

  final Directory dir;

  /// Songs kept; older ones are deleted. Fewer on a TV.
  static int get keep => onTv ? 3 : 8;

  /// Bigger songs (an hour-long jukebox) aren't downloaded.
  static const maxBytes = 60 << 20;

  final _files = <String, File>{};
  final _jobs = <String, Future<File?>>{};
  bool _ready = false;

  /// Empty the folder (left from the last run).
  Future<void> start() async {
    try {
      if (await dir.exists()) await dir.delete(recursive: true);
      await dir.create(recursive: true);
      _ready = true;
    } catch (error) {
      // A cache that can't be made just means songs stream as they did before.
      problemLog.warn('song cache: $error');
    }
  }

  /// The song [key] downloaded, if it is.
  File? file(String key) => _files[key];

  /// Download [stream] as [key] (once; asking again waits for the same
  /// download). Null when it can't be: a playlist stream (HLS), too big, or
  /// the download failed.
  Future<File?> fetch(String key, ResolvedStream stream) {
    if (!_ready) return Future.value();
    final done = _files[key];
    if (done != null) return Future.value(done);
    // A block body, not an arrow: `_jobs.remove` hands back the job it took
    // out — this very future — and whenComplete waits on a Future its callback
    // returns, so an arrow body would wait on itself for ever.
    return _jobs[key] ??= _download(key, stream).whenComplete(() {
      _jobs.remove(key);
    });
  }

  /// Forget [key] (its file didn't play).
  void drop(String key) {
    final file = _files.remove(key);
    if (file != null) unawaited(_delete(file));
  }

  Future<File?> _download(String key, ResolvedStream stream) async {
    final name = _safeName(key);
    final file = await downloadStream(
      stream,
      File('${dir.path}${Platform.pathSeparator}$name${audioExtension(stream.codec)}'),
      limit: maxBytes,
      label: key,
    );
    if (file == null) return null;
    _files[key] = file;
    _trim();
    return file;
  }

  void _trim() {
    while (_files.length > keep) {
      final oldest = _files.keys.first;
      unawaited(_delete(_files.remove(oldest)!));
    }
  }

  /// A key as a filename ("youtube:hvqnG6VjqV0" → "youtube_hvqnG6VjqV0").
  static String _safeName(String key) => key.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');

  // A file being played can't be deleted on Windows; it goes next run.
  static Future<void> _delete(File file) => file.delete().then((_) {}, onError: (Object _) {});
}
