// Links and track ids, as in paattu/sources.py and paattu/youtube.py.
//
// A YouTube song keeps its video id. A song from anywhere else is keyed by
// its link (host, path and query made filename-safe), so libraries move
// between the app and the desktop Paattu unchanged.

import 'util.dart';

const searchSites = ['jiosaavn', 'youtube', 'soundcloud'];
const siteNames = {'jiosaavn': 'JioSaavn', 'youtube': 'YouTube', 'soundcloud': 'SoundCloud', 'link': 'From the link'};
const lossless = ['flac', 'alac', 'wav', 'aiff', 'ape', 'wavpack'];
const audioExtensions = ['mp3', 'm4a', 'aac', 'flac', 'ogg', 'oga', 'opus', 'wav', 'webm', 'alac', 'aiff'];

final _linkRe = RegExp(r'^https?://([^/?#]+)([^?#]*)(?:\?([^#]*))?', caseSensitive: false);
final _youtubeHostRe = RegExp(r'(^|\.)(youtube\.com|youtu\.be|youtube-nocookie\.com)$');
final _videoIdRe = RegExp(r'^[A-Za-z0-9_-]{11}$');
final _unsafeRe = RegExp(r'[^A-Za-z0-9._-]+');
final channelIdRe = RegExp(r'^UC[A-Za-z0-9_-]{22}$');
final playlistIdRe = RegExp(r'^(?:PL|OLAK5uy_|UU|FL|LL|VL|RDCLAK5uy_|OL)[A-Za-z0-9_-]{8,}$');
final _videoPathRe = RegExp(r'/(?:shorts|embed|live)/([A-Za-z0-9_-]{11})');

bool isLink(String? text) => _linkRe.hasMatch((text ?? '').trim());

String hostOf(String? url) {
  final found = _linkRe.firstMatch((url ?? '').trim());
  if (found == null) return '';
  final host = found.group(1)!.toLowerCase();
  return host.startsWith('www.') ? host.substring(4) : host;
}

bool isYouTube(String? url) => _youtubeHostRe.hasMatch(hostOf(url));

bool isVideoId(String? id) => _videoIdRe.hasMatch(id ?? '');

/// A video id from a watch / youtu.be / music URL or a bare 11-char id.
String? videoId(String? query) {
  final q = (query ?? '').trim();
  if (_videoIdRe.hasMatch(q)) return q;
  final uri = Uri.tryParse(q.contains('://') ? q : 'https://$q');
  if (uri == null) return null;
  if (uri.host.endsWith('youtu.be')) {
    final path = uri.path.replaceAll('/', '');
    return path.isEmpty ? null : path.substring(0, path.length < 11 ? path.length : 11);
  }
  final v = uri.queryParameters['v'];
  if (v != null && v.isNotEmpty) return v.length > 11 ? v.substring(0, 11) : v;
  return _videoPathRe.firstMatch(uri.path)?.group(1);
}

/// A link's track id: the video id for YouTube, else its host and path made
/// filename-safe (never 11 characters of [A-Za-z0-9_-], so it can't be
/// mistaken for a video id).
String? linkTrackId(String? url) {
  final text = (url ?? '').trim();
  final found = _linkRe.firstMatch(text);
  if (found == null || isYouTube(text)) return videoId(text);
  var path = found.group(2)!;
  while (path.endsWith('/')) {
    path = path.substring(0, path.length - 1);
  }
  final query = found.group(3) ?? '';
  var key = (hostOf(text) + path + (query.isNotEmpty ? '?$query' : '')).replaceAll(_unsafeRe, '_');
  if (key.length > 150) key = key.substring(0, 150);
  return isVideoId(key) ? 'link.$key' : key;
}

String watchUrl(String id) => 'https://www.youtube.com/watch?v=$id';

/// jiosaavn, youtube, soundcloud, or the host of any other site.
String siteOf(String? url) {
  final host = hostOf(url);
  if (host.isEmpty || isYouTube(url)) return 'youtube';
  if (RegExp(r'(^|\.)(jio)?saavn\.com$').hasMatch(host)) return 'jiosaavn';
  if (RegExp(r'(^|\.)soundcloud\.com$').hasMatch(host)) return 'soundcloud';
  return host;
}

String siteName(String? site) => siteNames[site] ?? site ?? '';

/// A link straight to an audio file (played as it is).
bool isAudioFile(String? url) {
  final found = _linkRe.firstMatch((url ?? '').trim());
  if (found == null) return false;
  final path = found.group(2)!.toLowerCase();
  final dot = path.lastIndexOf('.');
  return dot != -1 && audioExtensions.contains(path.substring(dot + 1));
}

/// A playlist id from a playlist / watch URL or a bare id, else null.
String? playlistId(String? query) {
  final q = (query ?? '').trim();
  if (playlistIdRe.hasMatch(q)) return q.startsWith('VL') ? q.substring(2) : q;
  if (q.contains('list=')) {
    final uri = Uri.tryParse(q.contains('://') ? q : 'https://$q');
    final list = uri?.queryParameters['list'];
    if (list != null && list.isNotEmpty) return list;
  }
  return null;
}

/// What a YouTube profile reference points at: ('id', UC…), ('handle', @x)
/// or ('user', name) — or null when it isn't one.
(String, String)? channelRef(String? query) {
  var q = (query ?? '').trim();
  if (q.isEmpty) return null;
  if (channelIdRe.hasMatch(q)) return ('id', q);
  final looksLikeUrl = q.startsWith('http://') || q.startsWith('https://') || q.startsWith('www.') ||
      q.startsWith('youtube.com') || q.startsWith('m.youtube.com') || q.startsWith('music.youtube.com');
  if (looksLikeUrl) {
    if (!q.startsWith('http')) q = 'https://$q';
    final parts = (Uri.tryParse(q)?.pathSegments ?? const <String>[]).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return null;
    if (parts.first.startsWith('@')) return ('handle', Uri.decodeComponent(parts.first));
    if (parts.length > 1 && parts.first == 'channel' && channelIdRe.hasMatch(parts[1])) return ('id', parts[1]);
    if (parts.length > 1 && (parts.first == 'c' || parts.first == 'user')) return ('user', parts[1]);
    return null;
  }
  if (q.contains(' ') && !q.startsWith('@')) return null;
  return ('handle', '@${q.replaceFirst(RegExp('^@+'), '').split('/').first}');
}

bool looksLikeSingleVideo(String q) => RegExp(r'(youtu\.be/|/watch\b|/shorts/|/embed/|/live/)').hasMatch(q);

/// "Lossless", "320 kbps", or "" when the site doesn't say.
String qualityLabel(Json track) {
  if (lossless.contains(asString(track['codec']).toLowerCase())) return 'Lossless';
  final kbps = toInt(track['quality']);
  return kbps != null && kbps > 0 ? '$kbps kbps' : '';
}
