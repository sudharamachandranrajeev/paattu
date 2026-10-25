// YouTube Music without an account: its song search (clean titles, singers
// and films, the labels' own uploads) and its radio, the endless list of
// songs like one song that YouTube Music plays after it. Both are the web
// app's own calls; paattu/ytmusic.py makes the same ones.

import '../links.dart';
import '../util.dart';
import 'http.dart';
import 'jiosaavn.dart' show filmAndTitle;

const _client = {'clientName': 'WEB_REMIX', 'clientVersion': '1.20250101.01.00', 'hl': 'en', 'gl': 'IN'};
final _searchApi = Uri.parse('https://music.youtube.com/youtubei/v1/search?prettyPrint=false');
final _nextApi = Uri.parse('https://music.youtube.com/youtubei/v1/next?prettyPrint=false');
final _browseApi = Uri.parse('https://music.youtube.com/youtubei/v1/browse?prettyPrint=false');
const _headers = {'Origin': 'https://music.youtube.com', 'Referer': 'https://music.youtube.com/'};

/// The search's "Songs" filter.
const _songsOnly = 'EgWKAQIIAWoKEAoQAxAEEAkQBQ==';

/// Songs on YouTube Music for [query], best match first.
Future<List<Json>> searchMusic(String query, {int limit = 20}) async {
  final response = await postJson(
      _searchApi, {'context': const {'client': _client}, 'query': query, 'params': _songsOnly},
      headers: _headers);
  return musicSearchSongs(response).take(limit).toList();
}

/// One helping of a radio: its songs and the token for the next helping.
class RadioPage {
  const RadioPage(this.songs, this.more);
  final List<Json> songs;
  final String? more;
}

/// Songs like the song [videoId] (the first is that song), or the next
/// helping of them with [more].
Future<RadioPage> musicRadio(String videoId, {String? more}) async {
  final body = <String, dynamic>{'context': const {'client': _client}, 'isAudioOnly': true};
  if (more != null) {
    body['continuation'] = more;
  } else {
    body['videoId'] = videoId;
    body['playlistId'] = 'RDAMVM$videoId';
  }
  return radioPage(await postJson(_nextApi, body, headers: _headers));
}

/// The words on a song's Lyrics tab (from Musixmatch, in English letters, not
/// timed) and where they're from, or null.
Future<(String, String)?> musicLyricsOf(String videoId) async {
  final browseId = musicLyricsId(await postJson(
      _nextApi, {'context': const {'client': _client}, 'videoId': videoId},
      headers: _headers));
  if (browseId == null) return null;
  return musicLyrics(await postJson(
      _browseApi, {'context': const {'client': _client}, 'browseId': browseId},
      headers: _headers));
}

/// The browse id of the Lyrics tab in a song's /next (lyrics.py's music_lyrics_id).
String? musicLyricsId(Object? response) {
  for (final tab in _all(response, 'tabRenderer')) {
    final id = asString(asJson(asJson(tab['endpoint'])['browseEndpoint'])['browseId']);
    if (id.startsWith('MPLY')) return id;
  }
  return null;
}

String _runsText(Object? node) => [for (final r in asList(asJson(node)['runs'])) asString(asJson(r)['text'])].join();

/// (words, where from) on a Lyrics page (lyrics.py's music_lyrics), or null.
(String, String)? musicLyrics(Object? response) {
  for (final shelf in _all(response, 'musicDescriptionShelfRenderer')) {
    final text = _runsText(shelf['description']).trim();
    if (text.isEmpty) continue;
    final source = _runsText(shelf['footer']).replaceAll('Source:', '').trim();
    return (text, 'YouTube Music${source.isEmpty ? '' : ' ($source)'}');
  }
  return null;
}

/// The playlists on YouTube Music's charts page for India, title -> playlist id.
Future<Map<String, String>> musicCharts() async => youtubeCharts(await postJson(
    _browseApi,
    {
      'context': const {'client': _client},
      'browseId': 'FEmusic_charts',
      'formData': const {
        'selectedValues': ['IN'],
      },
    },
    headers: _headers));

/// title -> playlist id for the playlists in a charts page (charts.py's
/// youtube_charts).
Map<String, String> youtubeCharts(Object? response) {
  final out = <String, String>{};
  for (final item in _all(response, 'musicTwoRowItemRenderer')) {
    final title = _runs(item['title']).map((r) => r.text).join();
    final id = asString(asJson(asJson(item['navigationEndpoint'])['browseEndpoint'])['browseId']);
    if (title.isNotEmpty && id.startsWith('VL')) out[title] = id.substring(2);
  }
  return out;
}

/// The songs in a search response.
List<Json> musicSearchSongs(Object? response) => [
      for (final item in _all(response, 'musicResponsiveListItemRenderer')) ?_searchSong(item),
    ];

/// The songs and the next token in a radio response.
RadioPage radioPage(Object? response) {
  final songs = [
    for (final item in _all(response, 'playlistPanelVideoRenderer')) ?_radioSong(item),
  ];
  final more = [..._all(response, 'nextRadioContinuationData'), ..._all(response, 'nextContinuationData')]
      .map((c) => asString(c['continuation']))
      .where((c) => c.isNotEmpty)
      .firstOrNull;
  return RadioPage(songs, more);
}

/// Every object under [key], anywhere in [node], in order.
List<Json> _all(Object? node, String key, [List<Json>? out]) {
  out ??= [];
  if (node is Map) {
    node.forEach((k, value) {
      if (k == key && value is Map) {
        out!.add(asJson(value));
      } else {
        _all(value, key, out);
      }
    });
  } else if (node is List) {
    for (final value in node) {
      _all(value, key, out);
    }
  }
  return out;
}

typedef _Run = ({String text, String page});

List<_Run> _runs(Object? text) => [
      for (final run in asList(asJson(text)['runs']).map(asJson))
        (
          text: asString(run['text']),
          page: asString(asJson(asJson(asJson(asJson(run['navigationEndpoint'])['browseEndpoint'])[
                  'browseEndpointContextSupportedConfigs'])['browseEndpointContextMusicConfig'])['pageType']),
        ),
    ];

Json? _searchSong(Json item) {
  final id = asString(asJson(item['playlistItemData'])['videoId']);
  final columns = [
    for (final column in asList(item['flexColumns']))
      _runs(asJson(asJson(column)['musicResponsiveListItemFlexColumnRenderer'])['text']),
  ];
  if (columns.isEmpty) return null;
  return _song(id, columns.first.map((r) => r.text).join(), columns.length > 1 ? columns[1] : const [],
      art: _thumbnail(asJson(asJson(item['thumbnail'])['musicThumbnailRenderer'])['thumbnail']));
}

Json? _radioSong(Json item) => _song(
      asString(item['videoId']),
      _runs(item['title']).map((r) => r.text).join(),
      _runs(item['longBylineText']),
      length: _runs(item['lengthText']).map((r) => r.text).join(),
      art: _thumbnail(item['thumbnail']),
    );

final _timeRe = RegExp(r'^\d{1,2}(?::\d\d){1,2}$');
final _creditSplitRe = RegExp(r'\s*(?:,|&)\s*');
// "Irupathu Kodi (Language: Tamil; Film: Thullatha Manamum Thullum; Film Artist 1: Vijay)"
final _labelNotesRe = RegExp(r'\s*\((?:Language|Film)\s*:[^)]*\)\s*$', caseSensitive: false);
final _noteFilmRe = RegExp(r'(?:^|;)\s*Film\s*:\s*([^;)]+)', caseSensitive: false);

/// A song from its title and the line under it ("Singer, Singer • Film
/// (Original Motion Picture Soundtrack) • 1985", the length on its own in
/// a search), in the shape of youtubeTrack.
Json? _song(String id, String heading, List<_Run> details, {String length = '', String art = ''}) {
  final rawTitle = squash(heading);
  if (!isVideoId(id) || rawTitle.isEmpty) return null;
  final artists = <String>[];
  var album = '';
  var seconds = _seconds(length);
  var segment = 0;
  for (final run in details) {
    final text = run.text.trim();
    if (text == '•') {
      segment++;
    } else if (run.page == 'MUSIC_PAGE_TYPE_ARTIST' || run.page == 'MUSIC_PAGE_TYPE_USER_CHANNEL') {
      artists.add(text);
    } else if (run.page == 'MUSIC_PAGE_TYPE_ALBUM') {
      album = text;
    } else if (_timeRe.hasMatch(text)) {
      seconds ??= _seconds(text);
    } else if (segment == 0) {
      // Singers YouTube Music has no page for.
      artists.addAll(text.split(_creditSplitRe));
    }
  }
  var title = rawTitle;
  var film = '';
  final notes = _labelNotesRe.firstMatch(title);
  if (notes != null) {
    film = _noteFilmRe.firstMatch(notes.group(0)!)?.group(1)?.trim() ?? '';
    title = title.substring(0, notes.start).trim();
  }
  final (clean, fromAlbum) = filmAndTitle(title, album);
  final credits = uniqueNames(artists).take(6).toList();
  return <String, dynamic>{
    'id': id,
    'site': 'youtube',
    'rawTitle': rawTitle,
    'title': clean,
    'movie': film.isNotEmpty ? film : fromAlbum,
    'credits': credits,
    'kind': 'audio',
    'channel': credits.isNotEmpty ? credits.first : '',
    'duration': seconds,
    if (art.isNotEmpty) 'art': art,
  };
}

int? _seconds(String text) {
  if (!_timeRe.hasMatch(text.trim())) return null;
  return text.trim().split(':').fold<int>(0, (total, part) => total * 60 + int.parse(part));
}

final _artSizeRe = RegExp(r'=w\d+-h\d+(-[a-z0-9-]+)?$');

/// The song's square cover, 544 pixels (YouTube Music's own big size).
String _thumbnail(Object? thumbnail) {
  final images = asList(asJson(thumbnail)['thumbnails']).map(asJson).toList();
  if (images.isEmpty) return '';
  final url = asString(images.last['url']);
  if (!url.contains('googleusercontent.com')) return '';
  return url.replaceFirst(_artSizeRe, '=w544-h544-l90-rj');
}
