// YouTube without an account or API key: search, playlists, a profile's
// playlists and the audio streams (via youtube_explode_dart).

import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:math';

import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import '../links.dart';
import '../titles.dart';
import '../util.dart';
import 'http.dart';

final yt = YoutubeExplode();

const _unavailable = {'[private video]', '[deleted video]', '[unavailable video]'};
const _cookies = {'Cookie': 'CONSENT=YES+cb; SOCS=CAI'};

/// The user agents googlevideo expects for each player client (its "c=").
const _clientAgents = {
  'ANDROID': 'com.google.android.youtube/20.10.38 (Linux; U; Android 11) gzip',
  'ANDROID_VR':
      'com.google.android.apps.youtube.vr.oculus/1.56.21 (Linux; U; Android 12L; eureka-user Build/SQ3A.220605.009.A1) gzip',
  'IOS': 'com.google.ios.youtube/20.10.4 (iPhone16,2; U; CPU iOS 18_3_2 like Mac OS X;)',
};

Json? youtubeTrack(Video video) {
  final id = video.id.value;
  final title = video.title;
  if (!isVideoId(id) || title.isEmpty || _unavailable.contains(title.toLowerCase()) || video.isLive) return null;
  final meta = cleanTitle(title, video.author);
  return <String, dynamic>{
    'id': id,
    'site': 'youtube',
    'rawTitle': title,
    'title': meta.title.isNotEmpty ? meta.title : title,
    'movie': meta.movie,
    'credits': meta.credits.take(6).toList(),
    'kind': meta.kind,
    'channel': video.author,
    'duration': video.duration?.inSeconds,
    'views': video.engagement.viewCount,
  };
}

Future<List<Json>> searchYouTube(String query, {int limit = 12}) async {
  final results = await yt.search.search(query);
  return results.map(youtubeTrack).whereType<Json>().take(limit).toList();
}

String _biggest(List<Thumbnail> thumbnails) {
  if (thumbnails.isEmpty) return '';
  final sorted = [...thumbnails]..sort((a, b) => a.width - b.width);
  final url = sorted.last.url.toString();
  return url.startsWith('//') ? 'https:$url' : url;
}

/// A YouTube playlist or channel from a search, in the shape of collection
/// in sources.dart, or null.
Json? youtubeCollection(SearchResult result) {
  if (result case SearchPlaylist(:final id, :final title, :final videoCount, :final thumbnails) when title.isNotEmpty) {
    return {
      'type': 'playlist',
      'site': 'youtube',
      'id': id.value,
      'url': 'https://www.youtube.com/playlist?list=${id.value}',
      'title': title,
      'subtitle': videoCount > 0 ? plural(videoCount, 'video') : '',
      'art': _biggest(thumbnails),
      'count': videoCount > 0 ? videoCount : null,
    };
  }
  if (result case SearchChannel(:final id, :final name, :final thumbnails) when name.isNotEmpty) {
    return {
      'type': 'artist',
      'site': 'youtube',
      'id': id.value,
      'url': 'https://www.youtube.com/channel/${id.value}',
      'title': name,
      // (its videoCount is really the subscriber count, when YouTube gives one)
      'subtitle': 'YouTube channel',
      'art': _biggest(thumbnails),
    };
  }
  return null;
}

/// YouTube's search, a page (about 20) at a time: songs ([kind] 'song'),
/// playlists ('playlist') or channels ('artist').
class YouTubeSearch {
  YouTubeSearch(this.query, this.kind);
  final String query;
  final String kind;
  VideoSearchList? _videos;
  SearchList? _content;
  bool _started = false;

  /// The next page, or null when there are no more.
  Future<List<Json>?> next() async {
    if (kind == 'song') {
      final page = _started ? await _videos?.nextPage() : await yt.search.search(query);
      _started = true;
      _videos = page;
      return page?.map(youtubeTrack).whereType<Json>().toList();
    }
    final page = _started
        ? await _content?.nextPage()
        : await yt.search.searchContent(query, filter: kind == 'playlist' ? TypeFilters.playlist : TypeFilters.channel);
    _started = true;
    _content = page;
    return page?.map(youtubeCollection).whereType<Json>().toList();
  }
}

/// What YouTube suggests for a few typed letters.
Future<List<String>> suggestYouTube(String query) async {
  final data = asList(jsonDecode(await getText(Uri.https('suggestqueries.google.com', '/complete/search', {
    'client': 'firefox',
    'ds': 'yt',
    'hl': 'en',
    'q': query,
  }))));
  return data.length > 1 ? asStrings(data[1]) : const [];
}

/// One video as a song (for links to a single video).
Future<Json> youtubeVideo(String id) async {
  final track = youtubeTrack(await yt.videos.get(id));
  if (track == null) throw SourceException("that video isn't playable");
  return track;
}

/// A public playlist and its videos, in the shape Library.setPlaylistTracks takes.
Future<Json> playlistDetails(String id) async {
  final playlist = await yt.playlists.get(id);
  // Uploads lists of big labels run to thousands; the first 200 are plenty.
  final limit = id.startsWith('UU') ? 200 : 1000;
  final tracks = <Json>[];
  await for (final video in yt.playlists.getVideos(id).take(limit + 20)) {
    if (_unavailable.contains(video.title.toLowerCase()) || video.isLive) continue;
    tracks.add({
      'id': video.id.value,
      'title': video.title,
      'channel': video.author,
      'duration': video.duration?.inSeconds,
      'views': video.engagement.viewCount,
    });
    if (tracks.length >= limit) break;
  }
  return {
    'id': id,
    'title': playlist.title,
    'channel': playlist.author,
    'channelId': '',
    'thumbnail': tracks.isEmpty ? '' : 'https://i.ytimg.com/vi/${tracks.first['id']}/hqdefault.jpg',
    'tracks': tracks,
  };
}

// ---------------------------------------------------------------- profiles

final _initialDataRe = RegExp(r'var ytInitialData\s*=\s*(\{.*?\});</script>', dotAll: true);
final _clientVersionRe = RegExp(r'"INNERTUBE_CLIENT_VERSION":"([^"]+)"');
final _subscribersRe = RegExp(r'"(\d[\d.,]*\s*[KMB]?) subscribers"');

int? _count(String? text) {
  final found = RegExp(r'([\d.,]+)\s*([KMB]?)').firstMatch(text ?? '');
  if (found == null) return null;
  final number = double.tryParse(found.group(1)!.replaceAll(',', ''));
  if (number == null) return null;
  final scale = switch (found.group(2)) { 'K' => 1e3, 'M' => 1e6, 'B' => 1e9, _ => 1.0 };
  return (number * scale).round();
}

String _lastImage(Object? sources) {
  final list = asList(sources).map(asJson).where((s) => asString(s['url']).isNotEmpty).toList();
  if (list.isEmpty) return '';
  list.sort((a, b) => (toInt(a['width']) ?? 0) - (toInt(b['width']) ?? 0));
  final url = asString(list.last['url']);
  return url.startsWith('//') ? 'https:$url' : url;
}

/// Playlists on a page of the Playlists tab, and the token for the next page.
(List<Json>, String?) _playlistsIn(Object? data) {
  final found = <Json>[];
  String? next;
  void walk(Object? node) {
    if (node is List) {
      var hasPlaylists = false;
      for (final item in node) {
        if (item is Map && (item.containsKey('lockupViewModel') || item.containsKey('gridPlaylistRenderer'))) {
          hasPlaylists = true;
        }
      }
      for (final item in node) {
        if (hasPlaylists && item is Map && item.containsKey('continuationItemRenderer')) {
          final token = asString(asJson(asJson(asJson(item['continuationItemRenderer'])['continuationEndpoint'])[
              'continuationCommand'])['token']);
          if (token.isNotEmpty) next = token;
        }
        walk(item);
      }
    } else if (node is Map) {
      final lockup = asJson(node['lockupViewModel']);
      if (lockup.isNotEmpty && asString(lockup['contentType']) == 'LOCKUP_CONTENT_TYPE_PLAYLIST') {
        final title = asString(asJson(asJson(asJson(lockup['metadata'])['lockupMetadataViewModel'])['title'])['content']);
        final image = asJson(asJson(asJson(asJson(lockup['contentImage'])['collectionThumbnailViewModel'])[
            'primaryThumbnail'])['thumbnailViewModel']);
        found.add({'id': asString(lockup['contentId']), 'title': title, 'thumbnail': _lastImage(asJson(image['image'])['sources'])});
        return;
      }
      final grid = asJson(node['gridPlaylistRenderer']);
      if (grid.isNotEmpty) {
        final title = asJson(grid['title']);
        final text = asString(title['simpleText']).isNotEmpty
            ? asString(title['simpleText'])
            : asList(title['runs']).map((r) => asString(asJson(r)['text'])).join();
        found.add({
          'id': asString(grid['playlistId']),
          'title': text,
          'thumbnail': _lastImage(asJson(grid['thumbnail'])['thumbnails']),
        });
        return;
      }
      for (final value in node.values) {
        walk(value);
      }
    }
  }

  walk(data);
  return (found.where((p) => asString(p['id']).isNotEmpty).toList(), next);
}

/// A channel and its public playlists: Popular / Latest uploads, then its
/// Playlists tab. The shape Library.upsertUser takes.
Future<Json> channelPlaylists(String query) async {
  final ref = channelRef(query);
  if (ref == null) throw SourceException('give a YouTube @handle or channel link');
  final base = switch (ref.$1) {
    'id' => 'https://www.youtube.com/channel/${ref.$2}',
    'handle' => 'https://www.youtube.com/${Uri.encodeComponent(ref.$2).replaceAll('%40', '@')}',
    _ => 'https://www.youtube.com/c/${Uri.encodeComponent(ref.$2)}',
  };
  String page;
  try {
    page = await getText(Uri.parse('$base/playlists'), headers: _cookies);
  } on SourceException catch (error) {
    if (error.message.endsWith('404')) throw SourceException("couldn't find that YouTube user");
    rethrow;
  }
  final raw = _initialDataRe.firstMatch(page);
  if (raw == null) throw SourceException("couldn't read that YouTube page");
  final data = asJson(jsonDecode(raw.group(1)!));
  final meta = asJson(asJson(data['metadata'])['channelMetadataRenderer']);
  final channelId = asString(meta['externalId']);
  if (!channelIdRe.hasMatch(channelId)) throw SourceException("couldn't find that YouTube user");
  final vanity = asString(meta['vanityChannelUrl']);
  final handle = vanity.contains('/@') ? vanity.substring(vanity.indexOf('/@') + 1) : '';

  final playlists = <Json>[
    {'id': 'UULP${channelId.substring(2)}', 'title': 'Popular uploads', 'thumbnail': '', 'auto': true},
    {'id': 'UULF${channelId.substring(2)}', 'title': 'Latest uploads', 'thumbnail': '', 'auto': true},
  ];
  final seen = {for (final p in playlists) p['id']};
  var (found, next) = _playlistsIn(data);
  final version = _clientVersionRe.firstMatch(page)?.group(1) ?? '2.20250101.00.00';
  for (var pages = 0;; pages++) {
    for (final p in found) {
      if (seen.add(p['id'])) playlists.add(p);
    }
    if (next == null || pages >= 6) break;
    try {
      final more = await postJson(Uri.parse('https://www.youtube.com/youtubei/v1/browse?prettyPrint=false'), {
        'context': {
          'client': {'clientName': 'WEB', 'clientVersion': version, 'hl': 'en', 'gl': 'US'},
        },
        'continuation': next,
      }, headers: _cookies);
      (found, next) = _playlistsIn(more);
    } catch (_) {
      break; // the first page is still worth having
    }
  }

  return {
    'id': channelId,
    'handle': handle,
    'name': asString(meta['title']),
    'url': handle.isNotEmpty ? 'https://www.youtube.com/$handle' : 'https://www.youtube.com/channel/$channelId',
    'followers': _count(_subscribersRe.firstMatch(page)?.group(1)),
    'avatar': _lastImage(asJson(meta['avatar'])['thumbnails']),
    'playlists': playlists,
  };
}

// ---------------------------------------------------------------- streams

/// YouTube's Vision Pro app. As of October 2026 it is the one client that
/// hands out audio links without a proof-of-origin token or a JavaScript
/// challenge (yt-dlp asks as it too): the Android and iOS apps' links are
/// refused (403) and the VR app's need a sign-in, which made songs wait on
/// youtube_explode's retries. It needs a visitor id, which one small request
/// gives and which lasts the session.
const _visionAgent =
    'Mozilla/5.0 (Macintosh; Intel Mac OS X 15_7_3) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15';
const _visionClient = {
  'clientName': 'VISIONOS',
  'clientVersion': '1.02',
  'deviceMake': 'Apple',
  'deviceModel': 'RealityDevice17,1',
  'userAgent': _visionAgent,
  'osName': 'visionOS',
  'osVersion': '26.5.23O471',
  'hl': 'en',
  'timeZone': 'UTC',
  'utcOffsetMinutes': 0,
};
final _playerApi = Uri.parse('https://www.youtube.com/youtubei/v1/player?prettyPrint=false');

String? _visitor;

/// YouTube's id for this visitor, from the small file its service worker reads.
Future<String> _visitorId({bool fresh = false}) async {
  final known = _visitor;
  if (!fresh && known != null) return known;
  var text = await getText(Uri.parse('https://www.youtube.com/sw.js_data'), headers: {'User-Agent': _visionAgent});
  if (text.startsWith(")]}'")) text = text.substring(4);
  Object? node = jsonDecode(text);
  for (final i in const [0, 2, 0, 0, 13]) {
    node = asList(node).length > i ? asList(node)[i] : null;
  }
  final id = asString(node);
  if (id.isEmpty) throw SourceException("couldn't start a YouTube session");
  return _visitor = id;
}

/// Headers for googlevideo. Without a Range header it sends a file at about
/// the speed it plays; Android's player sends none for the first request
/// (it adds its own when seeking, which replaces this one). mpv on the
/// desktop always asks for a range.
Map<String, String> streamHeaders(String agent, {bool? android}) => {
      'User-Agent': agent,
      if (android ?? Platform.isAndroid) 'Range': 'bytes=0-',
    };

/// The best audio in a player response: the original language (not a dubbed
/// copy), not the loudness-levelled (DRC) copy, then the highest bitrate.
ResolvedStream bestAudio(Json response, {String agent = _visionAgent, bool? android}) {
  final status = asJson(response['playabilityStatus']);
  if (asString(status['status']) != 'OK') {
    final reason = squash(asString(status['reason']));
    throw SourceException(reason.isEmpty ? "YouTube won't play this video" : reason);
  }
  final streaming = asJson(response['streamingData']);
  final audio = [
    for (final f in asList(streaming['adaptiveFormats']).map(asJson))
      if (asString(f['mimeType']).startsWith('audio/') && asString(f['url']).isNotEmpty) f,
  ];
  if (audio.isEmpty) throw SourceException('YouTube has no audio for this video');
  int rank(Json f) {
    final track = asJson(f['audioTrack']);
    var score = toInt(f['bitrate']) ?? 0;
    if (track.isNotEmpty && track['audioIsDefault'] != true) score -= 1 << 24;
    if (f['isDrc'] == true) score -= 1 << 20;
    return score;
  }

  audio.sort((a, b) => rank(b) - rank(a));
  final best = audio.first;
  final mime = asString(best['mimeType']);
  final codec = mime.contains('opus')
      ? 'opus'
      : mime.contains('mp4a')
          ? 'aac'
          : mime.split(';').first.split('/').last;
  final bits = toInt(best['averageBitrate']) ?? toInt(best['bitrate']) ?? 0;
  // Links last about six hours; stop using one well before that.
  final seconds = toInt(streaming['expiresInSeconds']) ?? 21600;
  return ResolvedStream(Uri.parse(asString(best['url'])),
      codec: codec,
      kbps: (bits / 1000).round(),
      headers: streamHeaders(agent, android: android),
      lifetime: Duration(seconds: max(600, seconds - 1800)));
}

/// The smallest picture of a video, without sound, for the blurred
/// background of Now Playing: H.264, which every phone and PC decodes in
/// hardware, at 144p (about 130 kbps), plenty under a blur. Null when
/// YouTube won't play it.
ResolvedStream? smallestVideo(Json response, {String agent = _visionAgent, bool? android}) {
  if (asString(asJson(response['playabilityStatus'])['status']) != 'OK') return null;
  final streaming = asJson(response['streamingData']);
  final videos = [
    for (final f in asList(streaming['adaptiveFormats']).map(asJson))
      if (asString(f['mimeType']).startsWith('video/') &&
          asString(f['mimeType']).contains('avc1') &&
          asString(f['url']).isNotEmpty &&
          (toInt(f['height']) ?? 0) > 0)
        f,
  ];
  if (videos.isEmpty) return null;
  videos.sort((a, b) => toInt(a['height'])! - toInt(b['height'])!);
  final seconds = toInt(streaming['expiresInSeconds']) ?? 21600;
  return ResolvedStream(Uri.parse(asString(videos.first['url'])),
      codec: 'h264',
      kbps: ((toInt(videos.first['bitrate']) ?? 0) / 1000).round(),
      headers: streamHeaders(agent, android: android),
      lifetime: Duration(seconds: max(600, seconds - 1800)));
}

/// A video's player response, as YouTube's Vision Pro app.
Future<Json> _visionPlayer(String id, {bool fresh = false}) async {
  final visitor = await _visitorId(fresh: fresh);
  final response = await postJson(_playerApi, {
    'context': {
      'client': {..._visionClient, 'visitorData': visitor},
    },
    'videoId': id,
    'contentCheckOk': true,
    'racyCheckOk': true,
  }, headers: {
    'User-Agent': _visionAgent,
    'X-YouTube-Client-Name': '101',
    'X-YouTube-Client-Version': '1.02',
    'X-Goog-Visitor-Id': visitor,
    'Origin': 'https://www.youtube.com',
  });
  return asJson(response);
}

Future<ResolvedStream> _visionStream(String id, {bool fresh = false}) async =>
    bestAudio(await _visionPlayer(id, fresh: fresh));

/// A video's smallest silent picture (see [smallestVideo]), or null.
Future<ResolvedStream?> videoYouTube(String id) async => smallestVideo(await _visionPlayer(id));

/// The best audio stream for a video: as YouTube's Vision Pro app, then again
/// with a new visitor id, then (slower) youtube_explode's own ways, for when
/// a stream won't start or stops part way.
Future<ResolvedStream> streamYouTube(String id, {int attempt = 0}) async {
  if (attempt < 2) return _visionStream(id, fresh: attempt == 1);
  final manifest = await yt.videos.streams.getManifest(id);
  final audio = manifest.audioOnly;
  if (audio.isEmpty) throw SourceException('YouTube has no audio for this video');
  final best = audio.withHighestBitrate();
  final codecText = best.audioCodec.toLowerCase();
  final codec = codecText.contains('opus')
      ? 'opus'
      : codecText.startsWith('mp4a')
          ? 'aac'
          : codecText;
  final agent = _clientAgents[best.url.queryParameters['c']] ?? browserAgent;
  return ResolvedStream(best.url,
      codec: codec,
      kbps: (best.bitrate.bitsPerSecond / 1000).round(),
      headers: streamHeaders(agent),
      lifetime: const Duration(hours: 3));
}
