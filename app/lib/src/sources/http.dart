// One HTTP client for the sites Paattu reads, with a browser-like identity.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../util.dart';

const browserAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36';
const _timeout = Duration(seconds: 20);

final http.Client httpClient = http.Client();

Map<String, String> _headers(Map<String, String>? extra) => {
      'User-Agent': browserAgent,
      'Accept-Language': 'en-US,en;q=0.8',
      ...?extra,
    };

void _check(http.Response response) {
  if (response.statusCode >= 400) {
    throw SourceException('${response.request?.url.host ?? 'the site'} said ${response.statusCode}');
  }
}

Future<String> getText(Uri uri, {Map<String, String>? headers}) async {
  final response = await httpClient.get(uri, headers: _headers(headers)).timeout(_timeout);
  _check(response);
  return utf8.decode(response.bodyBytes, allowMalformed: true);
}

Future<Object?> getJson(Uri uri, {Map<String, String>? headers}) async =>
    jsonDecode(await getText(uri, headers: {'Accept': 'application/json', ...?headers}));

Future<Object?> postForm(Uri uri, Map<String, String> fields, {Map<String, String>? headers}) async {
  final response = await httpClient
      .post(uri, headers: _headers({'Accept': 'application/json', ...?headers}), body: fields)
      .timeout(_timeout);
  _check(response);
  return jsonDecode(utf8.decode(response.bodyBytes, allowMalformed: true));
}

Future<Object?> postJson(Uri uri, Object body, {Map<String, String>? headers}) async {
  final response = await httpClient
      .post(uri,
          headers: _headers({'Content-Type': 'application/json', 'Accept': 'application/json', ...?headers}),
          body: jsonEncode(body))
      .timeout(_timeout);
  _check(response);
  return jsonDecode(utf8.decode(response.bodyBytes, allowMalformed: true));
}

/// Whether the internet can be reached: a connection to YouTube Music within
/// a few seconds.
Future<bool> reachable() async {
  try {
    final socket = await Socket.connect('music.youtube.com', 443, timeout: const Duration(seconds: 3));
    socket.destroy();
    return true;
  } catch (_) {
    return false;
  }
}

/// What the player streams for a song, and how good it is.
class ResolvedStream {
  ResolvedStream(this.uri,
      {this.codec = '', this.kbps, this.headers, Duration lifetime = const Duration(minutes: 20)})
      : expires = DateTime.now().add(lifetime);

  final Uri uri;
  /// Headers the stream's server wants (YouTube checks the client's user agent).
  final Map<String, String>? headers;
  final String codec;
  final int? kbps;
  final DateTime expires;

  bool get fresh => DateTime.now().isBefore(expires);

  /// "Opus · 160 kbps", "AAC · 320 kbps", "FLAC".
  String get label {
    final name = switch (codec) {
      'opus' => 'Opus',
      'aac' => 'AAC',
      'mp3' => 'MP3',
      'flac' => 'FLAC',
      'vorbis' => 'Vorbis',
      'wav' => 'WAV',
      '' => '',
      _ => codec.toUpperCase(),
    };
    final rate = kbps != null && kbps! > 0 && !['flac', 'wav', 'alac'].contains(codec) ? '$kbps kbps' : '';
    return [name, rate].where((s) => s.isNotEmpty).join(' · ');
  }
}

/// The HTTP status a stream's server answers with, asked for its first two
/// bytes (to say why the player couldn't open it).
Future<int> streamStatus(ResolvedStream stream) async {
  final request = http.Request('GET', stream.uri)
    ..headers.addAll({'User-Agent': browserAgent, ...?stream.headers, 'Range': 'bytes=0-1'});
  final response = await httpClient.send(request).timeout(const Duration(seconds: 6));
  unawaited(response.stream.listen(null).cancel());
  return response.statusCode;
}
