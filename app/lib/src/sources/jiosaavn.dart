// JioSaavn: the labels' Malayalam and Tamil film albums, most at 320 kbps AAC.
// The search and the track shape follow paattu/sources.py.

import '../links.dart';
import '../util.dart';
import 'http.dart';

final _api = Uri.parse('https://www.jiosaavn.com/api.php');

final _fromRe = RegExp(r'''\s*\((?:From|from)\s+["“]([^"”]+)["”]\)\s*$''');
final _soundtrackRe = RegExp(
    r'\s*\((?:Original Motion Picture Soundtrack|Original Soundtrack|OST|Original Score)[^)]*\)\s*$',
    caseSensitive: false);
final _languageSuffixRe = RegExp(r'\s+-\s+(?:Malayalam|Tamil|Telugu|Kannada|Hindi)$', caseSensitive: false);
final _imageSizeRe = RegExp(r'-\d+x\d+\.(jpg|jpeg|png|webp)$');

/// 'Malare (From "Premam")' on a hits album is Malare from Premam; an album
/// 'Devara Part 1 - Telugu (Original Motion Picture Soundtrack)' is the film.
(String, String) filmAndTitle(String title, String album) {
  final found = _fromRe.firstMatch(title);
  if (found != null) return (title.substring(0, found.start).trim(), found.group(1)!.trim());
  final film = album.replaceFirst(_soundtrackRe, '').replaceFirst(_languageSuffixRe, '').trim();
  return (title, film.toLowerCase() == title.toLowerCase() ? '' : film);
}

String _title(String text) => text.isEmpty ? text : text[0].toUpperCase() + text.substring(1).toLowerCase();

/// A JioSaavn song (api_version 4, or the older flat shape), or null.
Json? jiosaavnTrack(Object? raw) {
  final item = asJson(raw);
  final url = asString(item['perma_url']);
  final type = asString(item['type']);
  if ((type.isEmpty ? 'song' : type) != 'song' || !isLink(url)) return null;
  final info = asJson(item['more_info']);
  Object? pick(String key) => info[key] != null && info[key] != '' ? info[key] : item[key];
  final rawTitle = htmlUnescape(asString(item['title'] ?? item['song'])).trim();
  final album = htmlUnescape(asString(pick('album'))).trim();
  final (title, film) = filmAndTitle(rawTitle, album);
  final artists = asJson(info['artistMap']);
  var music = [
    for (final a in asList(artists['artists']).map(asJson))
      if (a['role'] == 'music') asString(a['name'])
  ];
  var singers = [
    for (final a in [...asList(artists['primary_artists']), ...asList(artists['featured_artists'])])
      asString(asJson(a)['name'])
  ];
  if (music.isEmpty && singers.isEmpty) {
    music = asString(pick('music')).split(', ');
    singers = asString(item['primary_artists'] ?? item['singers']).split(', ');
  }
  final image = asString(item['image']);
  return <String, dynamic>{
    'id': linkTrackId(url),
    'url': url,
    'site': 'jiosaavn',
    'rawTitle': rawTitle,
    'title': title,
    'movie': film,
    'album': album,
    'credits': uniqueNames([...music, ...singers]).take(6).toList(),
    'kind': 'song',
    'channel': htmlUnescape(asString(pick('label'))),
    'duration': toInt(pick('duration')),
    'views': toInt(item['play_count']),
    'language': _title(asString(item['language'])),
    'year': asString(item['year']),
    'quality': asString(pick('320kbps')).toLowerCase() == 'true' ? 320 : 128,
    'codec': 'aac',
    'art': image.replaceFirstMapped(_imageSizeRe, (m) => '-500x500.${m.group(1)}'),
    // Not stored in the library (the leading _), only kept for playing.
    '_media': asString(info['encrypted_media_url']),
  };
}

/// Songs without the copies hits compilations repeat.
List<Json> _unique(Iterable<Object?> items, int limit) {
  final tracks = <Json>[];
  final seen = <String>{};
  for (final track in items.map(jiosaavnTrack)) {
    if (track == null) continue;
    final key = '${asString(track['title']).toLowerCase()}|${asString(track['movie']).toLowerCase()}';
    if (seen.add(key)) tracks.add(track);
  }
  return tracks.take(limit).toList();
}

final _media = <String, String>{};

void _remember(List<Json> tracks) {
  for (final t in tracks) {
    final media = asString(t['_media']);
    if (media.isNotEmpty) _media[asString(t['id'])] = media;
  }
}

Future<List<Json>> searchJioSaavn(String query, {int limit = 12}) async {
  final data = asJson(await getJson(_api.replace(queryParameters: {
    '__call': 'search.getResults',
    '_format': 'json',
    '_marker': '0',
    'api_version': '4',
    'ctx': 'web6dot0',
    'n': '${limit * 2 > 50 ? 50 : limit * 2}',
    'p': '1',
    'q': query,
  })));
  final tracks = _unique(asList(data['results']), limit);
  _remember(tracks);
  return tracks;
}

/// The songs behind a JioSaavn song, album or playlist link.
Future<List<Json>> resolveJioSaavn(String url) async {
  final parts = Uri.parse(url).pathSegments.where((p) => p.isNotEmpty).toList();
  if (parts.length < 2) throw SourceException("that JioSaavn link doesn't point at a song, album or playlist");
  final type = switch (parts.first) {
    'song' => 'song',
    'album' => 'album',
    'featured' || 's' || 'playlist' => 'playlist',
    _ => throw SourceException("that JioSaavn link doesn't point at a song, album or playlist"),
  };
  final data = asJson(await getJson(_api.replace(queryParameters: {
    '__call': 'webapi.get',
    'token': parts.last,
    'type': type,
    '_format': 'json',
    '_marker': '0',
    'api_version': '4',
    'ctx': 'web6dot0',
    'n': '200',
    'p': '1',
  })));
  final items = data['songs'] is List ? asList(data['songs']) : asList(data['list']);
  final tracks = _unique(items, 200);
  if (tracks.isEmpty) throw SourceException('no songs at that link');
  _remember(tracks);
  return tracks;
}

/// Stream 128 kbps rather than 320 (the "save data" setting).
bool jiosaavnSaveData = false;

/// The signed AAC link for a song, best quality first.
Future<ResolvedStream> streamJioSaavn(Json track, {bool lower = false}) async {
  final id = asString(track['id']);
  var media = _media[id] ?? asString(track['_media']);
  if (media.isEmpty) {
    final found = await resolveJioSaavn(asString(track['url']));
    media = asString(found.first['_media']);
    if (media.isEmpty) throw SourceException("JioSaavn won't stream this song");
    _media[id] = media;
  }
  final want = lower || jiosaavnSaveData || toInt(track['quality']) == 128 ? ['128'] : ['320', '128'];
  Object? lastError;
  for (final bitrate in want) {
    try {
      final data = asJson(await postForm(_api, {
        '__call': 'song.generateAuthToken',
        '_format': 'json',
        '_marker': '0',
        'api_version': '4',
        'ctx': 'web6dot0',
        'bitrate': bitrate,
        'url': media,
      }));
      final link = asString(data['auth_url']);
      if (link.isNotEmpty) {
        return ResolvedStream(Uri.parse(link), codec: 'aac', kbps: int.parse(bitrate),
            lifetime: const Duration(minutes: 30));
      }
      lastError = SourceException(asString(data['message']).isNotEmpty ? asString(data['message']) : 'no link');
    } catch (error) {
      lastError = error;
    }
  }
  throw SourceException("JioSaavn won't stream this song (${errorText(lastError ?? 'no link')})");
}
