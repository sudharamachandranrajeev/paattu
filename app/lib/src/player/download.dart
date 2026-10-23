// Downloading a resolved stream into a file. YouTube sends a whole file only
// at the speed it plays; asked for in pieces, it sends each as fast as it can.
// Shared by the temporary song cache (song_cache.dart) and the offline library
// (offline.dart), so both download the same way and a half-finished file is
// never mistaken for a whole one.

import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../log.dart';
import '../sources/http.dart';
import '../util.dart';

/// Bytes asked for at a time.
const downloadPiece = 2 << 20;

/// The file extension for a codec.
String audioExtension(String codec) => switch (codec) {
      'opus' || 'vorbis' => '.webm',
      'aac' => '.m4a',
      'mp3' => '.mp3',
      'flac' => '.flac',
      _ => '.audio',
    };

/// Download [stream] into [target], through a `.part` file beside it that is
/// renamed once the whole thing has arrived. [limit] bytes at most: something
/// bigger (an hour-long jukebox) isn't worth the space. [label] names it in
/// the problem log.
///
/// Returns the file, or null when there is none to have: a playlist stream
/// (HLS or DASH, which has no single file), one over [limit], or a download
/// that failed.
Future<File?> downloadStream(
  ResolvedStream stream,
  File target, {
  int? limit,
  String label = '',
  void Function(int got, int? total)? onProgress,
}) async {
  if (stream.uri.path.endsWith('.m3u8') || stream.uri.path.endsWith('.mpd')) return null;
  final part = File('${target.path}.part');
  final sink = part.openWrite();
  var ok = false;
  try {
    var from = 0;
    int? total;
    while (total == null || from < total) {
      final request = http.Request('GET', stream.uri)
        ..headers.addAll({
          'User-Agent': browserAgent,
          ...?stream.headers,
          'Range': 'bytes=$from-${from + downloadPiece - 1}',
        });
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
      if (limit != null && total != null && total > limit) {
        unawaited(response.stream.listen(null).cancel());
        return null;
      }
      var got = 0;
      await for (final bytes in response.stream.timeout(const Duration(seconds: 20))) {
        sink.add(bytes);
        got += bytes.length;
        onProgress?.call(from + got, total);
      }
      if (got == 0) throw SourceException('${stream.uri.host} sent nothing');
      from += got;
      // The whole file, or the last piece of one whose size wasn't said.
      if (response.statusCode == 200 || (total == null && got < downloadPiece)) break;
    }
    await sink.close();
    await part.rename(target.path);
    ok = true;
    return target;
  } catch (error) {
    problemLog.warn('download ${label.isEmpty ? target.path : label}: ${errorText(error)}');
    return null;
  } finally {
    if (!ok) {
      await sink.close().catchError((Object _) {});
      // A file being written can't always go at once on Windows; it's a .part,
      // so nothing reads it as a song.
      await part.delete().then((_) {}, onError: (Object _) {});
    }
  }
}
