// Songs are plain JSON maps, the same shape as tracks in the desktop Paattu's
// library.json: {id, title, movie, credits, kind, channel, duration, ...} and,
// for songs from outside YouTube, {url, site, art, quality, codec}.

import 'links.dart';
import 'util.dart';

String trackId(Json t) => asString(t['id']);

String trackTitle(Json t) {
  final title = asString(t['title']);
  if (title.isNotEmpty) return title;
  final raw = asString(t['rawTitle']);
  return raw.isNotEmpty ? raw : 'Unknown song';
}

/// "Premam · Vijay Yesudas": the film, then the first credit (or the channel).
String trackSubtitle(Json t) {
  final parts = <String>[];
  final movie = asString(t['movie']);
  if (movie.isNotEmpty) parts.add(movie);
  final credits = asStrings(t['credits']);
  final channel = asString(t['channel']);
  if (credits.isNotEmpty) {
    parts.add(credits.first);
  } else if (channel.isNotEmpty) {
    parts.add(channel);
  }
  return parts.join(' · ');
}

/// jiosaavn, youtube, soundcloud or another host.
String trackSite(Json t) {
  final site = asString(t['site']);
  if (site.isNotEmpty) return site;
  final url = asString(t['url']);
  return url.isNotEmpty ? siteOf(url) : 'youtube';
}

/// The page the song lives on.
String trackPage(Json t) {
  final url = asString(t['url']);
  return url.isNotEmpty ? url : watchUrl(trackId(t));
}

Duration? trackDuration(Json t) {
  final seconds = toInt(t['duration']);
  return seconds == null || seconds <= 0 ? null : Duration(seconds: seconds);
}

/// Cover art: the site's own, or YouTube's thumbnail. [large] for the
/// now-playing screen (YouTube's big one isn't there for every video).
String? trackArt(Json t, {bool large = false}) {
  final art = asString(t['art']);
  if (art.isNotEmpty) return art;
  final id = trackId(t);
  if (!isVideoId(id)) return null;
  return large ? 'https://i.ytimg.com/vi/$id/maxresdefault.jpg' : 'https://i.ytimg.com/vi/$id/mqdefault.jpg';
}

String? trackArtFallback(Json t) {
  final id = trackId(t);
  return isVideoId(id) && asString(t['art']).isEmpty ? 'https://i.ytimg.com/vi/$id/hqdefault.jpg' : null;
}

/// The bits of a track worth keeping in the library (no transient fields).
Json storedTrack(Json t) {
  final out = <String, dynamic>{};
  t.forEach((key, value) {
    if (!key.startsWith('_') && value != null) out[key] = value;
  });
  return out;
}
