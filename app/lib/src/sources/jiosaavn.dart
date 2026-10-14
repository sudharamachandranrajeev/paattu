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

Map<String, String> _call(String call, Map<String, String> extra) => {
      '__call': call,
      '_format': 'json',
      '_marker': '0',
      'api_version': '4',
      'ctx': 'web6dot0',
      ...extra,
    };

/// One page of songs (pages count from 1).
Future<List<Json>> searchJioSaavn(String query, {int limit = 12, int page = 1}) async {
  final data = asJson(await getJson(_api.replace(queryParameters: _call('search.getResults', {
    'n': '${limit * 2 > 50 ? 50 : limit * 2}',
    'p': '$page',
    'q': query,
  }))));
  final tracks = _unique(asList(data['results']), limit);
  _remember(tracks);
  return tracks;
}

// Albums' pictures end -150x150.jpg, artists' _50x50.jpg; both come in 500x500.
final _anySizeRe = RegExp(r'([-_])\d+x\d+\.(jpg|jpeg|png|webp)$');
String _bigImage(String url) => url.replaceFirstMapped(_anySizeRe, (m) => '${m.group(1)}500x500.${m.group(2)}');

/// A JioSaavn album, playlist or artist as a search result (see
/// collection in sources.dart), or null.
Json? jiosaavnCollection(Object? raw) {
  final item = asJson(raw);
  final type = asString(item['type']);
  final info = asJson(item['more_info']);
  final title = htmlUnescape(asString(item['title'] ?? item['name'])).trim();
  if (title.isEmpty || asString(item['id']).isEmpty) return null;
  final url = asString(item['perma_url']);
  final count = toInt(info['song_count']) ?? toInt(item['numsongs']);
  switch (type) {
    case 'album':
      final music = htmlUnescape(asString(item['subtitle']).isNotEmpty ? asString(item['subtitle']) : asString(info['music']));
      return {
        'type': 'album',
        'site': 'jiosaavn',
        'id': asString(item['id']),
        'url': url,
        'title': title,
        'subtitle': [music, asString(item['year'])].where((s) => s.isNotEmpty).join(' · '),
        'art': _bigImage(asString(item['image'])),
        'count': count,
        'year': asString(item['year']),
        'language': _title(asString(item['language'])),
      };
    case 'playlist':
      return {
        'type': 'playlist',
        'site': 'jiosaavn',
        'id': asString(item['id']),
        'url': url,
        'title': title,
        'subtitle': htmlUnescape(asString(item['subtitle'])),
        'art': _bigImage(asString(item['image'])),
        'count': count,
        'language': _title(asString(info['language'])),
      };
    case 'artist':
      final role = asString(item['description']).isNotEmpty ? asString(item['description']) : asString(item['role']);
      return {
        'type': 'artist',
        'site': 'jiosaavn',
        'id': asString(item['id']),
        'url': url,
        'title': title,
        'subtitle': role == 'Artist' || role == 'Primary' ? 'Singer' : _title(role),
        'art': _bigImage(asString(item['image'])),
      };
  }
  return null;
}

/// One page of albums, playlists or artists ([kind] 'album', 'playlist',
/// 'artist'). Empty when there are no more.
Future<List<Json>> searchJioSaavnCollections(String query, String kind, {int page = 1, int limit = 20}) async {
  final call = switch (kind) {
    'album' => 'search.getAlbumResults',
    'playlist' => 'search.getPlaylistResults',
    _ => 'search.getArtistResults',
  };
  final data = asJson(await getJson(_api.replace(queryParameters: _call(call, {'q': query, 'n': '$limit', 'p': '$page'}))));
  final total = toInt(data['total']) ?? 0;
  if ((page - 1) * limit >= total) return const [];
  return [
    for (final item in asList(data['results']))
      if (jiosaavnCollection(asJson(item)..putIfAbsent('type', () => kind)) case final found?) found,
  ];
}

/// A singer's or composer's page: their best songs and albums, a page at
/// a time (pages count from 1).
Future<Json> jiosaavnArtist(Json artist, {int page = 1}) async {
  final url = asString(artist['url']);
  final token = url.isEmpty ? '' : Uri.parse(url).pathSegments.where((p) => p.isNotEmpty).last;
  final data = asJson(await getJson(_api.replace(
      queryParameters: token.isNotEmpty
          ? _call('webapi.get', {'type': 'artist', 'token': token, 'n_song': '25', 'n_album': '20', 'p': '$page', 'category': '', 'sort_order': ''})
          : _call('artist.getArtistPageDetails',
              {'artistId': asString(artist['id']), 'n_song': '25', 'n_album': '20', 'page': '$page', 'category': '', 'sort_order': ''}))));
  final songs = _unique(asList(data['topSongs']), 25);
  _remember(songs);
  List<Json> collections(Object? items, String type) => [
        for (final item in asList(items))
          if (jiosaavnCollection(asJson(item)..putIfAbsent('type', () => type)) case final found?) found,
      ];
  return {
    'name': htmlUnescape(asString(data['name'])),
    'art': _bigImage(asString(data['image'])),
    'followers': toInt(data['follower_count']) ?? toInt(data['fan_count']),
    'role': _title(asString(data['dominantType'])),
    'songs': songs,
    'albums': collections(data['topAlbums'], 'album'),
    'singles': collections(data['singles'], 'album'),
    'playlists': collections(data['dedicated_artist_playlist'], 'playlist'),
    'similar': collections(data['similarArtists'], 'artist'),
  };
}

/// What JioSaavn suggests for a few typed letters: songs, albums, artists
/// and playlists, best first.
Future<List<Json>> suggestJioSaavn(String query) async {
  final data = asJson(await getJson(_api.replace(queryParameters: _call('autocomplete.get', {'query': query}))));
  final groups = [
    for (final key in const ['topquery', 'songs', 'albums', 'artists', 'playlists'])
      (toInt(asJson(data[key])['position']) ?? 9, key, asList(asJson(data[key])['data'])),
  ]..sort((a, b) => a.$1.compareTo(b.$1));
  final out = <Json>[];
  final seen = <String>{};
  for (final (_, _, items) in groups) {
    for (final raw in items.map(asJson)) {
      final type = asString(raw['type']);
      final title = htmlUnescape(asString(raw['title'])).trim();
      final subtitle = htmlUnescape(asString(raw['subtitle'] ?? raw['description'])).trim();
      // The same song or album often comes twice under different ids.
      if (title.isEmpty || !seen.add('$type|${title.toLowerCase()}|${subtitle.toLowerCase()}')) continue;
      if (type == 'song') {
        final info = asJson(raw['more_info']);
        out.add({
          'type': 'song',
          'site': 'jiosaavn',
          'id': asString(raw['id']),
          'url': asString(raw['perma_url']),
          'title': title,
          'subtitle': [htmlUnescape(asString(info['album'])), htmlUnescape(asString(info['primary_artists']))]
              .where((s) => s.isNotEmpty)
              .join(' · '),
          'art': _bigImage(asString(raw['image'])),
        });
      } else if (jiosaavnCollection(raw) case final found?) {
        out.add(found);
      }
    }
  }
  return out;
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
