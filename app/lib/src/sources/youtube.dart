// YouTube without an account or API key: search, playlists, a profile's
// playlists and the audio streams (via youtube_explode_dart).

import 'dart:convert';

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

/// The best audio stream for a video. Later [attempt]s ask YouTube as
/// different apps, for when a stream stops working part way.
Future<ResolvedStream> streamYouTube(String id, {int attempt = 0}) async {
  final clients = switch (attempt) {
    0 => null,
    1 => [YoutubeApiClient.androidVr],
    2 => [YoutubeApiClient.ios],
    _ => [YoutubeApiClient.tv],
  };
  final manifest = await yt.videos.streams.getManifest(id, ytClients: clients, requireWatchPage: attempt > 0);
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
      headers: {'User-Agent': agent},
      lifetime: const Duration(hours: 3));
}
