// The next songs, downloaded while this one plays, so they start at once and
// a slow or dropped connection doesn't stop them part way. Files live in the
// app's temporary folder and only for this run: the last few are kept.

import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../log.dart';
import '../sources/http.dart';
import '../util.dart';

class SongCache {
  SongCache(this.dir);

  final Directory dir;

  /// Songs kept; older ones are deleted.
  static const keep = 8;

  /// Bigger songs (an hour-long jukebox) aren't downloaded.
  static const maxBytes = 60 << 20;

  /// YouTube sends a whole file only at the speed it plays; asked for in
  /// pieces, it sends each as fast as it can.
  static const _piece = 2 << 20;

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
    return _jobs[key] ??= _download(key, stream).whenComplete(() => _jobs.remove(key));
  }

  /// Forget [key] (its file didn't play).
  void drop(String key) {
    final file = _files.remove(key);
    if (file != null) unawaited(_delete(file));
  }

  Future<File?> _download(String key, ResolvedStream stream) async {
    if (stream.uri.path.endsWith('.m3u8') || stream.uri.path.endsWith('.mpd')) return null;
    final name = key.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    final part = File('${dir.path}${Platform.pathSeparator}$name.part');
    final sink = part.openWrite();
    var ok = false;
    try {
      var from = 0;
      int? total;
      while (total == null || from < total) {
        final request = http.Request('GET', stream.uri)
          ..headers.addAll({'User-Agent': browserAgent, ...?stream.headers, 'Range': 'bytes=$from-${from + _piece - 1}'});
        final response = await httpClient.send(request).timeout(const Duration(seconds: 15));
        if (response.statusCode == 200) {
          // No pieces from this server: the whole file comes at once.
          if (from > 0) throw SourceException('the server stopped sending pieces');
          total = response.contentLength;
        } else if (response.statusCode == 206) {
          total ??= int.tryParse(response.headers['content-range']?.split('/').last ?? '');
        } else {
          unawaited(response.stream.listen(null).cancel());
          throw SourceException('${stream.uri.host} said ${response.statusCode}');
        }
        if (total != null && total > maxBytes) {
          unawaited(response.stream.listen(null).cancel());
          return null;
        }
        var got = 0;
        await for (final bytes in response.stream.timeout(const Duration(seconds: 20))) {
          sink.add(bytes);
          got += bytes.length;
        }
        if (got == 0) throw SourceException('${stream.uri.host} sent nothing');
        from += got;
        // The whole file, or the last piece of one whose size wasn't said.
        if (response.statusCode == 200 || (total == null && got < _piece)) break;
      }
      await sink.close();
      final file = File('${dir.path}${Platform.pathSeparator}$name${_extension(stream.codec)}');
      await part.rename(file.path);
      _files[key] = file;
      ok = true;
      _trim();
      return file;
    } catch (error) {
      problemLog.warn('download $key: ${errorText(error)}');
      return null;
    } finally {
      if (!ok) {
        await sink.close().catchError((Object _) {});
        await _delete(part);
      }
    }
  }

  void _trim() {
    while (_files.length > keep) {
      final oldest = _files.keys.first;
      unawaited(_delete(_files.remove(oldest)!));
    }
  }

  static String _extension(String codec) => switch (codec) {
        'opus' || 'vorbis' => '.webm',
        'aac' => '.m4a',
        'mp3' => '.mp3',
        'flac' => '.flac',
        _ => '.audio',
      };

  // A file being played can't be deleted on Windows; it goes next run.
  static Future<void> _delete(File file) => file.delete().then((_) {}, onError: (Object _) {});
}
