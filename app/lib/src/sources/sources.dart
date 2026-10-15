// Songs from outside the library: search JioSaavn, YouTube and SoundCloud at
// once, take a link, and find what to stream for any song.

import '../links.dart';
import '../log.dart';
import '../titles.dart';
import '../track.dart';
import '../util.dart';
import 'http.dart';
import 'jiosaavn.dart';
import 'soundcloud.dart';
import 'youtube.dart';

export 'http.dart' show ResolvedStream;

class SearchResults {
  SearchResults(this.found, this.errors);
  final Map<String, List<Json>> found;
  final Map<String, String> errors;

  bool get isEmpty => found.values.every((tracks) => tracks.isEmpty);
}

Future<List<Json>> _searchSite(String site, String query, int limit) => switch (site) {
      'jiosaavn' => searchJioSaavn(query, limit: limit),
      'youtube' => searchYouTube(query, limit: limit),
      'soundcloud' => searchSoundCloud(query, limit: limit),
      _ => Future.value(<Json>[]),
    };

/// Search the sites together; one failing doesn't sink the others.
Future<SearchResults> search(String query, {List<String> sites = searchSites, int limit = 12}) async {
  final found = <String, List<Json>>{};
  final errors = <String, String>{};
  await Future.wait([
    for (final site in sites.where(searchSites.contains))
      _searchSite(site, query, limit).timeout(const Duration(seconds: 40)).then((tracks) {
        found[site] = tracks;
      }).catchError((Object error) {
        found[site] = <Json>[];
        errors[site] = errorText(error);
      }),
  ]);
  return SearchResults({for (final site in sites) if (found.containsKey(site)) site: found[site]!}, errors);
}

// ---------------------------------------------------------------- browsing

// Albums, artists and playlists from a search are JSON maps:
//   type      album | artist | playlist (and song, for a suggestion)
//   site      jiosaavn | youtube | soundcloud
//   id, url   the site's id and page for it
//   title, subtitle, art, and count (songs, when known), year, language

/// What a search can look for, and the sites that have each.
const resultKinds = ['song', 'album', 'artist', 'playlist'];
const kindSites = {
  'song': ['jiosaavn', 'youtube', 'soundcloud'],
  'album': ['jiosaavn', 'soundcloud'],
  'artist': ['jiosaavn', 'youtube', 'soundcloud'],
  'playlist': ['jiosaavn', 'youtube', 'soundcloud'],
};

/// One site's results of one kind, a page at a time.
class SitePager {
  SitePager(this.site, this.kind, this.query);
  final String site;
  final String kind;
  final String query;
  int _page = 0;
  YouTubeSearch? _youtube;
  bool done = false;
  String? error;

  /// The next page; empty (and [done]) when there are no more.
  Future<List<Json>> next() async {
    if (done) return const [];
    _page++;
    try {
      final found = await _fetch().timeout(const Duration(seconds: 30));
      if (found == null || found.isEmpty) done = true;
      return found ?? const [];
    } catch (e) {
      problemLog.warn('search $site ${kind}s "$query" page $_page: $e');
      // The first page's error is worth showing; a later one just ends the list.
      if (_page == 1) error = errorText(e);
      done = true;
      return const [];
    }
  }

  Future<List<Json>?> _fetch() => switch (site) {
        'youtube' => (_youtube ??= YouTubeSearch(query, kind)).next(),
        'jiosaavn' => kind == 'song'
            ? searchJioSaavn(query, limit: 20, page: _page)
            : searchJioSaavnCollections(query, kind, page: _page),
        'soundcloud' => kind == 'song'
            ? searchSoundCloud(query, limit: 20, page: _page)
            : searchSoundCloudCollections(query, kind, page: _page),
        _ => Future.value(null),
      };
}

/// What makes two results the same: a film song is the same song on every
/// site (so the 320 kbps JioSaavn copy, asked first, stands for it); other
/// things are the same only on the same site.
String resultKey(Json item) {
  final type = asString(item['type']);
  if (type.isEmpty || type == 'song') {
    if (asString(item['movie']).isNotEmpty && asString(item['title']).isNotEmpty) return 'song|${songKey(item)}';
    return 'song|${asString(item['id'])}';
  }
  return '$type|${asString(item['site'])}|${asString(item['id'])}';
}

/// Pages from several sites as one list: taken in turn, a result from each
/// site at a time, leaving out anything already in [seen] (which grows).
List<Json> interleave(List<List<Json>> pages, Set<String> seen) {
  final out = <Json>[];
  final longest = pages.fold(0, (n, page) => page.length > n ? page.length : n);
  for (var i = 0; i < longest; i++) {
    for (final page in pages) {
      if (i < page.length && seen.add(resultKey(page[i]))) out.add(page[i]);
    }
  }
  return out;
}

/// Suggestions for what's typed: YouTube's search phrases, then JioSaavn's
/// songs, albums, singers and playlists. A phrase is a map with type 'query'.
Future<List<Json>> suggest(String query) async {
  final q = query.trim();
  if (q.isEmpty || isLink(q)) return const [];
  final phrases = suggestYouTube(q).timeout(const Duration(seconds: 6)).catchError((Object _) => <String>[]);
  final things = suggestJioSaavn(q).timeout(const Duration(seconds: 6)).catchError((Object _) => <Json>[]);
  final words = await phrases;
  final found = await things;
  final lower = q.toLowerCase();
  return [
    for (final phrase in words.where((w) => w.toLowerCase() != lower).take(6)) {'type': 'query', 'title': phrase},
    ...found.take(8),
  ];
}

/// The songs of an album or playlist from a search.
Future<List<Json>> collectionSongs(Json collection) async {
  final url = asString(collection['url']);
  final songs = switch (asString(collection['site'])) {
    'youtube' => youtubeSongs(await playlistDetails(asString(collection['id']))),
    'jiosaavn' => await resolveJioSaavn(url),
    'soundcloud' => await resolveSoundCloud(url),
    _ => await resolveLink(url),
  };
  if (songs.isEmpty) throw SourceException('no songs there');
  return songs;
}

/// A song from a suggestion (JioSaavn's are only stubs).
Future<Json> suggestedSong(Json suggestion) async => (await resolveLink(asString(suggestion['url']))).first;

/// A song for a link straight to an audio file.
Json audioFileTrack(String url) {
  final uri = Uri.parse(url);
  final file = Uri.decodeComponent(uri.pathSegments.isEmpty ? url : uri.pathSegments.last);
  final dot = file.lastIndexOf('.');
  final name = (dot > 0 ? file.substring(0, dot) : file).replaceAll('_', ' ');
  final ext = dot > 0 ? file.substring(dot + 1).toLowerCase() : '';
  final meta = cleanTitle(name);
  return <String, dynamic>{
    'id': linkTrackId(url),
    'url': url,
    'site': siteOf(url),
    'rawTitle': name,
    'title': meta.title.isNotEmpty ? meta.title : name,
    'movie': meta.movie,
    'credits': meta.credits,
    'kind': 'song',
    'channel': hostOf(url),
    'codec': switch (ext) { 'm4a' => 'aac', 'ogg' || 'oga' => 'vorbis', _ => ext },
  };
}

/// YouTube playlist rows (from playlistDetails) as songs.
List<Json> youtubeSongs(Json details) => [
      for (final raw in asList(details['tracks']).map(asJson))
        () {
          final channel = asString(raw['channel']);
          final meta = cleanTitle(asString(raw['title']), channel);
          return <String, dynamic>{
            'id': raw['id'],
            'site': 'youtube',
            'rawTitle': raw['title'],
            'title': meta.title,
            'movie': meta.movie,
            'credits': meta.credits.take(6).toList(),
            'kind': meta.kind,
            'channel': channel,
            'duration': raw['duration'],
            'views': raw['views'],
          };
        }(),
    ];

/// The songs behind a link: one song, or every song of an album / set / playlist.
Future<List<Json>> resolveLink(String url) async {
  final link = url.trim();
  if (!isLink(link) && !isVideoId(link)) throw SourceException("that isn't a link");
  if (isYouTube(link) || isVideoId(link)) {
    final vid = videoId(link);
    if (vid != null && isVideoId(vid)) return [await youtubeVideo(vid)];
    final list = playlistId(link);
    if (list != null) {
      final songs = youtubeSongs(await playlistDetails(list));
      if (songs.isEmpty) throw SourceException('no songs in that playlist');
      return songs;
    }
    if (channelRef(link) != null) {
      throw SourceException("that's a YouTube profile: add it from the Library page");
    }
    throw SourceException("couldn't find a song at that link");
  }
  switch (siteOf(link)) {
    case 'jiosaavn':
      return resolveJioSaavn(link);
    case 'soundcloud':
      return resolveSoundCloud(link);
  }
  if (isAudioFile(link)) return [audioFileTrack(link)];
  throw SourceException(
      "${hostOf(link)} links aren't supported in the app yet. Try YouTube, JioSaavn, SoundCloud or a direct audio file");
}

/// What to stream for a song. A higher [attempt] tries another way (another
/// YouTube client, JioSaavn's lower bitrate) after a stream failed.
Future<ResolvedStream> streamFor(Json track, {int attempt = 0}) async {
  final url = asString(track['url']);
  final site = trackSite(track);
  if (site == 'jiosaavn') return streamJioSaavn(track, lower: attempt >= 2);
  if (site == 'soundcloud') return streamSoundCloud(track);
  final id = _youTubeId(track);
  if (id != null) return streamYouTube(id, attempt: attempt);
  if (isAudioFile(url)) {
    final codec = asString(track['codec']);
    return ResolvedStream(Uri.parse(url), codec: codec, kbps: toInt(track['quality']), lifetime: const Duration(days: 1));
  }
  throw SourceException("${hostOf(url)} songs can't be played in the app yet");
}

/// The YouTube video a song is, if it's one.
String? _youTubeId(Json track) {
  final url = asString(track['url']);
  final id = asString(track['id']);
  if ((url.isEmpty || isYouTube(url)) && isVideoId(id)) return id;
  return url.isNotEmpty && isYouTube(url) ? videoId(url) : null;
}

final _videos = <String, ResolvedStream?>{};

/// How many videos found by search are tried for a song's picture.
const videoTries = 3;

/// A silent picture to blur behind Now Playing: the song's own video, unless
/// that is its cover held still (a YouTube Music art track), else the first
/// YouTube video found by search that is about as long and whose picture
/// moves (most film songs are there as a lyric or video song). Null when
/// there's none; looked up once a session. Same as video_for on the desktop.
Future<ResolvedStream?> videoFor(Json track) async {
  final key = '${track['site']}:${track['id']}';
  if (_videos.containsKey(key)) {
    final known = _videos[key];
    if (known == null || known.fresh) return known;
  }
  return _videos[key] = await findVideo(track, searchYouTube, videoYouTube);
}

/// [videoFor] with its two lookups given: [search] YouTube, and a [video]'s
/// moving picture (null for a still).
Future<ResolvedStream?> findVideo(
  Json track,
  Future<List<Json>> Function(String query, {int limit}) search,
  Future<ResolvedStream?> Function(String id) video,
) async {
  final own = _youTubeId(track);
  if (own != null) {
    final picture = await video(own);
    if (picture != null) return picture;
  }
  final seconds = toInt(track['duration']);
  final credits = asStrings(track['credits']);
  final query = [asString(track['title']), credits.isNotEmpty ? credits.first : asString(track['movie'])]
      .where((s) => s.isNotEmpty)
      .join(' ');
  if (seconds == null || query.isEmpty) return null;
  final found = await search(query, limit: 6);
  final near = [
    for (final t in found)
      if (asString(t['id']) != own && toInt(t['duration']) != null && (toInt(t['duration'])! - seconds).abs() <= 20)
        asString(t['id']),
  ];
  for (final id in near.take(videoTries)) {
    try {
      final picture = await video(id);
      if (picture != null) return picture;
    } catch (_) {
      // That one won't play here; try the next.
    }
  }
  return null;
}

/// How many different ways [streamFor] can try for a song.
int streamAttempts(Json track) => switch (asString(track['site'])) {
      'jiosaavn' => 3,
      'soundcloud' => 2,
      '' || 'youtube' => 3,
      _ => 1,
    };

// ---------------------------------------------------------------- the same song elsewhere

/// Sites best sound first: JioSaavn's 320 kbps AAC, YouTube's Opus, then
/// SoundCloud's 128 kbps MP3.
const qualityOrder = ['jiosaavn', 'youtube', 'soundcloud'];

final _wordRe = RegExp(r'[\p{L}\p{M}\p{N}]+', unicode: true);

List<String> _words(Object? text) => [for (final m in _wordRe.allMatches(asString(text).toLowerCase())) m[0]!];

/// Whether [a] and [b] are one song on two sites: the same title (or one
/// the start of the other, "Malare" and "Malare Reprise" aside), not from
/// two different films, and about as long (or, length unknown, from the same
/// film).
bool sameSong(Json a, Json b) {
  final ta = _words(a['title']), tb = _words(b['title']);
  if (ta.isEmpty || tb.isEmpty) return false;
  final (short, long) = ta.length <= tb.length ? (ta, tb) : (tb, ta);
  final sameTitle = short.length == long.length;
  for (var i = 0; i < short.length; i++) {
    if (short[i] != long[i]) return false;
  }
  final ma = _words(a['movie']).join(' '), mb = _words(b['movie']).join(' ');
  final bothMovies = ma.isNotEmpty && mb.isNotEmpty;
  final sameMovie = bothMovies && (ma.contains(mb) || mb.contains(ma));
  if (bothMovies && !sameMovie) return false;
  final da = toInt(a['duration']), db = toInt(b['duration']);
  if (da != null && db != null && da > 0 && db > 0) return (da - db).abs() <= 20;
  return sameTitle && sameMovie;
}

/// [track] on the other sites, best sound first, for when its own stream
/// won't play. One copy a site at most; a site that fails is left out.
Future<List<Json>> alternatesFor(Json track) async {
  final title = asString(track['title']);
  if (title.isEmpty || asString(track['kind']) == 'jukebox') return const [];
  final movie = asString(track['movie']);
  final credits = asStrings(track['credits']);
  final query = [title, movie.isNotEmpty ? movie : (credits.isNotEmpty ? credits.first : '')]
      .where((s) => s.isNotEmpty)
      .join(' ');
  final own = trackSite(track);
  final found = await Future.wait([
    for (final site in qualityOrder.where((s) => s != own))
      _searchSite(site, query, 6)
          .timeout(const Duration(seconds: 8))
          .then((tracks) => tracks.where((t) => sameSong(track, t)).firstOrNull)
          .catchError((Object _) => null),
  ]);
  return found.whereType<Json>().toList();
}
