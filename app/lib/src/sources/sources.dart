// Songs from outside the library: search JioSaavn, YouTube and SoundCloud at
// once, take a link, and find what to stream for any song.

import '../links.dart';
import '../titles.dart';
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
  final site = asString(track['site']).isNotEmpty ? asString(track['site']) : (url.isEmpty ? 'youtube' : siteOf(url));
  if (site == 'jiosaavn') return streamJioSaavn(track, lower: attempt >= 2);
  if (site == 'soundcloud') return streamSoundCloud(track);
  final id = asString(track['id']);
  if ((url.isEmpty || isYouTube(url)) && isVideoId(id)) return streamYouTube(id, attempt: attempt);
  if (url.isNotEmpty && isYouTube(url)) {
    final vid = videoId(url);
    if (vid != null) return streamYouTube(vid, attempt: attempt);
  }
  if (isAudioFile(url)) {
    final codec = asString(track['codec']);
    return ResolvedStream(Uri.parse(url), codec: codec, kbps: toInt(track['quality']), lifetime: const Duration(days: 1));
  }
  throw SourceException("${hostOf(url)} songs can't be played in the app yet");
}

/// How many different ways [streamFor] can try for a song.
int streamAttempts(Json track) => switch (asString(track['site'])) {
      'jiosaavn' => 3,
      'soundcloud' => 2,
      '' || 'youtube' => 4,
      _ => 1,
    };
