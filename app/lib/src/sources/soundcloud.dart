// SoundCloud: covers, remixes and uploads the labels don't carry. Uses the
// public web player's API with the client id it ships in its scripts.

import '../links.dart';
import '../titles.dart';
import '../util.dart';
import 'http.dart';

final _apiBase = Uri.parse('https://api-v2.soundcloud.com');
final _scriptRe = RegExp(r'https://a-v2\.sndcdn\.com/assets/[^"]+\.js');
final _clientIdRe = RegExp(r'client_id\s*:\s*"([0-9a-zA-Z]{32})"');

String? _clientId;

Future<String> _findClientId({bool fresh = false}) async {
  if (_clientId != null && !fresh) return _clientId!;
  final page = await getText(Uri.parse('https://soundcloud.com/'));
  // The id lives in one of the last scripts the page loads.
  final scripts = _scriptRe.allMatches(page).map((m) => m.group(0)!).toList().reversed;
  for (final script in scripts) {
    try {
      final found = _clientIdRe.firstMatch(await getText(Uri.parse(script)));
      if (found != null) return _clientId = found.group(1)!;
    } catch (_) {
      continue;
    }
  }
  throw SourceException("couldn't read SoundCloud's player (it may have changed)");
}

/// GET from the API, finding a new client id once if the old one stopped working.
Future<Object?> _api(String path, Map<String, String> query) async {
  for (var attempt = 0;; attempt++) {
    final id = await _findClientId(fresh: attempt > 0);
    final uri = path.startsWith('http') ? Uri.parse(path) : _apiBase.replace(path: path);
    try {
      return await getJson(uri.replace(queryParameters: {...uri.queryParameters, ...query, 'client_id': id}));
    } on SourceException catch (error) {
      if (attempt > 0 || !(error.message.endsWith('401') || error.message.endsWith('403'))) rethrow;
    }
  }
}

String _art(Json t) {
  var art = asString(t['artwork_url']);
  if (art.isEmpty) art = asString(asJson(t['user'])['avatar_url']);
  return art.replaceFirst('-large.', '-t500x500.');
}

/// A SoundCloud API track as a Paattu song, or null.
Json? soundcloudTrack(Object? raw) {
  final t = asJson(raw);
  final url = asString(t['permalink_url']);
  final title = asString(t['title']);
  if (!isLink(url) || title.isEmpty || t['streamable'] == false || t['policy'] == 'SNIP') return null;
  final user = asJson(t['user']);
  final channel = asString(user['username']);
  final meta = cleanTitle(title, channel);
  final publisher = asJson(t['publisher_metadata']);
  final ms = toInt(t['full_duration']) ?? toInt(t['duration']);
  return <String, dynamic>{
    'id': linkTrackId(url),
    'url': url,
    'site': 'soundcloud',
    'rawTitle': title,
    'title': meta.title.isNotEmpty ? meta.title : title,
    'movie': asString(publisher['album_title']).isNotEmpty ? asString(publisher['album_title']) : meta.movie,
    'credits': uniqueNames([asString(publisher['artist']), ...meta.credits]).take(6).toList(),
    'kind': 'song',
    'channel': channel,
    'duration': ms == null ? null : (ms / 1000).round(),
    'views': toInt(t['playback_count']),
    'art': _art(t),
    '_sc': t,
  };
}

final _known = <String, Json>{};

List<Json> _tracks(Iterable<Object?> items, {int limit = 200}) {
  final out = <Json>[];
  for (final track in items.map(soundcloudTrack)) {
    if (track == null || out.any((t) => t['id'] == track['id'])) continue;
    _known[asString(track['id'])] = asJson(track['_sc']);
    out.add(track);
  }
  return out.take(limit).toList();
}

/// One page of songs (pages count from 1).
Future<List<Json>> searchSoundCloud(String query, {int limit = 12, int page = 1}) async {
  final data = asJson(await _api('/search/tracks', {'q': query, 'limit': '${limit + 4}', 'offset': '${(page - 1) * (limit + 4)}'}));
  return _tracks(asList(data['collection']), limit: limit);
}

/// A SoundCloud set or user as a search result (see collection in
/// sources.dart), or null.
Json? soundcloudCollection(Object? raw) {
  final item = asJson(raw);
  final url = asString(item['permalink_url']);
  if (!isLink(url)) return null;
  if (asString(item['kind']) == 'user') {
    final followers = toInt(item['followers_count']);
    return {
      'type': 'artist',
      'site': 'soundcloud',
      'id': asString(item['id']),
      'url': url,
      'title': asString(item['username']),
      'subtitle': followers == null ? '' : '${shortCount(followers)} ${followers == 1 ? 'follower' : 'followers'}',
      'art': asString(item['avatar_url']).replaceFirst('-large.', '-t500x500.'),
    };
  }
  final user = asJson(item['user']);
  if (toInt(item['track_count']) == 0) return null;
  return {
    'type': item['is_album'] == true ? 'album' : 'playlist',
    'site': 'soundcloud',
    'id': asString(item['id']),
    'url': url,
    'title': asString(item['title']),
    'subtitle': asString(user['username']),
    'art': _art(item),
    'count': toInt(item['track_count']),
  };
}

/// One page of albums, playlists or users ([kind] 'album', 'playlist', 'artist').
Future<List<Json>> searchSoundCloudCollections(String query, String kind, {int page = 1, int limit = 20}) async {
  final path = switch (kind) {
    'album' => '/search/albums',
    'playlist' => '/search/playlists_without_albums',
    _ => '/search/users',
  };
  final data = asJson(await _api(path, {'q': query, 'limit': '$limit', 'offset': '${(page - 1) * limit}'}));
  return [
    for (final item in asList(data['collection']))
      if (soundcloudCollection(item) case final found?) found,
  ];
}

/// The songs behind a SoundCloud track, set (album / playlist) or profile link.
Future<List<Json>> resolveSoundCloud(String url) async {
  final data = asJson(await _api('/resolve', {'url': url}));
  final kind = asString(data['kind']);
  if (kind == 'track') {
    final tracks = _tracks([data]);
    if (tracks.isEmpty) throw SourceException("SoundCloud won't play that track here");
    return tracks;
  }
  if (kind == 'playlist' || kind == 'system-playlist') {
    final items = asList(data['tracks']).map(asJson).toList();
    // Sets list the first few tracks in full and the rest as bare ids.
    final stubs = [for (final t in items) if (t['title'] == null) asString(t['id'])];
    final full = <String, Json>{for (final t in items) if (t['title'] != null) asString(t['id']): t};
    for (var i = 0; i < stubs.length; i += 50) {
      final batch = stubs.sublist(i, i + 50 > stubs.length ? stubs.length : i + 50);
      for (final t in asList(await _api('/tracks', {'ids': batch.join(',')})).map(asJson)) {
        full[asString(t['id'])] = t;
      }
    }
    final tracks = _tracks([for (final t in items) full[asString(t['id'])]]);
    if (tracks.isEmpty) throw SourceException('no songs SoundCloud will play in that set');
    return tracks;
  }
  if (kind == 'user') {
    final page = asJson(await _api('/users/${data['id']}/tracks', {'limit': '50'}));
    final tracks = _tracks(asList(page['collection']));
    if (tracks.isEmpty) throw SourceException('no songs on that profile');
    return tracks;
  }
  throw SourceException("that SoundCloud link isn't a track, set or profile");
}

/// The best stream SoundCloud offers for a song.
Future<ResolvedStream> streamSoundCloud(Json track) async {
  final id = asString(track['id']);
  var sc = _known[id];
  if (sc == null || sc['media'] == null) {
    final found = await resolveSoundCloud(asString(track['url']));
    sc = _known[asString(found.first['id'])] ?? <String, dynamic>{};
  }
  final transcodings = asList(asJson(sc['media'])['transcodings']).map(asJson).where((t) {
    final format = asJson(t['format']);
    final protocol = asString(format['protocol']);
    return t['snipped'] != true && (protocol == 'progressive' || protocol == 'hls');
  }).toList();
  if (transcodings.isEmpty) throw SourceException("SoundCloud won't stream this song");

  int rank(Json t) {
    final format = asJson(t['format']);
    final mime = asString(format['mime_type']);
    final preset = asString(t['preset']);
    final kbps = toInt(RegExp(r'(\d+)k').firstMatch(preset)?.group(1)) ?? 0;
    var score = kbps;
    if (mime.contains('mp4a') || mime.contains('aac')) score += 1000;
    if (asString(format['protocol']) == 'progressive') score += 50;
    if (mime.contains('mpeg') && !mime.contains('mpegurl')) score += 500;
    if (t['quality'] == 'hq') score += 2000;
    return score;
  }

  transcodings.sort((a, b) => rank(b) - rank(a));
  Object? lastError;
  for (final t in transcodings) {
    try {
      final data = asJson(await _api(asString(t['url']), {
        if (asString(sc['track_authorization']).isNotEmpty) 'track_authorization': asString(sc['track_authorization']),
      }));
      final link = asString(data['url']);
      if (link.isEmpty) continue;
      final mime = asString(asJson(t['format'])['mime_type']);
      final codec = mime.contains('mp4a') || mime.contains('aac')
          ? 'aac'
          : mime.contains('opus')
              ? 'opus'
              : 'mp3';
      final kbps = toInt(RegExp(r'(\d+)k').firstMatch(asString(t['preset']))?.group(1)) ?? (codec == 'mp3' ? 128 : null);
      return ResolvedStream(Uri.parse(link), codec: codec, kbps: kbps, lifetime: const Duration(minutes: 10));
    } catch (error) {
      lastError = error;
    }
  }
  throw SourceException("SoundCloud won't stream this song (${errorText(lastError ?? 'no link')})");
}
