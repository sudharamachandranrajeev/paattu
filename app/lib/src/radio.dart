// The radio: songs like a song, from YouTube Music's own radio for it, a
// helping at a time as the queue runs out. Like Spotify's and YouTube's, it
// leaves out what was played in the last few hours, songs skipped more than
// once and songs turned down (skipped the first time), and when one song's
// radio runs dry it carries on from a song it played. It plays to your taste
// too: songs by the singers, composers and films you play to the end come
// first (tasteOrder), and a few songs you love that share something with the
// station are mixed in. paattu/radio.py does the same on the desktop.

import 'dart:math';

import 'history.dart';
import 'links.dart';
import 'made.dart' show topSongs;
import 'sources/sources.dart' show sameSong;
import 'sources/youtube_music.dart';
import 'track.dart';
import 'util.dart';

/// Whether a radio or made-up playlist should have [song]: a song (not a
/// trailer or a jukebox), between a minute and a quarter of an hour long.
bool radioWorthy(Json song) {
  if (const {'trailer', 'jukebox'}.contains(asString(song['kind']))) return false;
  final seconds = toInt(song['duration']);
  return seconds == null || (seconds >= 60 && seconds <= 900);
}

/// Songs from [lists] taken in turn, one from each list at a time, leaving
/// out unworthy ones, repeats and anything in [avoid] (ids and song keys,
/// which grows), up to [limit].
List<Json> interleaveSongs(List<List<Json>> lists, {Set<String>? avoid, int limit = 1 << 30}) {
  final seen = avoid ?? <String>{};
  final out = <Json>[];
  final at = List.filled(lists.length, 0);
  var going = true;
  while (going && out.length < limit) {
    going = false;
    for (var i = 0; i < lists.length && out.length < limit; i++) {
      while (at[i] < lists[i].length) {
        final song = lists[i][at[i]++];
        final id = trackId(song), key = songIdentity(song);
        if (id.isEmpty || !radioWorthy(song) || seen.contains(id) || seen.contains(key)) continue;
        seen
          ..add(id)
          ..add(key);
        out.add(song);
        going = true;
        break;
      }
    }
  }
  return out;
}

/// The YouTube video for [track]: its own, or YouTube Music's copy of a song
/// from another site. Null when there's none.
Future<String?> youtubeIdFor(Json track) async {
  final id = trackId(track);
  if (trackSite(track) == 'youtube' && isVideoId(id)) return id;
  final movie = asString(track['movie']);
  final credits = asStrings(track['credits']);
  final query = [trackTitle(track), movie.isNotEmpty ? movie : (credits.isNotEmpty ? credits.first : '')]
      .where((s) => s.isNotEmpty)
      .join(' ');
  final found = await searchMusic(query, limit: 6);
  return found.where((song) => sameSong(track, song)).map(trackId).firstOrNull;
}

/// Songs skipped (stopped within half a minute) at least twice in 30 days.
Set<String> skippedOften(List<Json> plays, DateTime now) {
  final since = epochSeconds(now) - 30 * 86400;
  final skips = <String, int>{};
  for (final play in plays) {
    if ((toInt(play['at']) ?? 0) < since || counted(play)) continue;
    final id = asString(play['id']);
    skips[id] = (skips[id] ?? 0) + 1;
  }
  return {for (final e in skips.entries) if (e.value >= 2) e.key};
}

/// Up to [count] of the songs you like most (from topSongs) that share a
/// singer, composer or film with [station], leaving out [avoid].
List<Json> lovedLike(Json station, List<Json> top, Set<String> avoid, {int count = 2}) {
  final wanted = features(station).toSet();
  final picked = [for (final song in top) if (features(song).any(wanted.contains)) song];
  return interleaveSongs([picked], avoid: {...avoid}, limit: count);
}

/// [songs] with the [loved] ones put in third and seventh (or at the end of
/// a short helping).
List<Json> withFavourites(List<Json> songs, List<Json> loved) {
  final out = [...songs];
  const at = [2, 6];
  for (var i = 0; i < loved.length && i < at.length; i++) {
    out.insert(min(at[i], out.length), loved[i]);
  }
  return out;
}

class SongRadio {
  SongRadio(this.history);

  final History history;

  /// The song the radio was started from, the video whose radio is being
  /// played and the token for its next helping.
  Json? _station;
  String? _video;
  String? _more;
  final _usedVideos = <String>{};
  final _given = <String>{};

  /// Up to [count] songs like [station] that aren't in [queue].
  Future<List<Json>> next(Json station, List<Json> queue, {int count = 10}) async {
    if (_station == null || trackId(_station!) != trackId(station)) {
      _station = station;
      _video = null;
      _more = null;
      _usedVideos.clear();
      _given.clear();
    }
    final now = DateTime.now();
    final plays = history.plays;
    String keyOf(String id) => songIdentity(history.track(id) ?? {'id': id});
    final avoid = <String>{
      ..._given,
      for (final song in queue) ...{trackId(song), songIdentity(song)},
      ...heardSince(plays, now.subtract(const Duration(hours: 6)), keyOf: keyOf),
      ...skippedOften(plays, now),
      ...turnedDown(plays, keyOf: keyOf),
    };
    final likes = taste(plays, history.track, now: now);
    var out = <Json>[];
    for (var tries = 0; out.length < count && tries < 4; tries++) {
      if (_video == null) {
        final from = _usedVideos.isEmpty ? station : _nextStation(out, queue);
        if (from == null) break;
        _video = await youtubeIdFor(from);
        if (_video == null) break;
        _usedVideos.add(_video!);
        _more = null;
      }
      final page = await musicRadio(_video!, more: _more);
      _more = page.more;
      final fresh = interleaveSongs([tasteOrder(page.songs, likes)], avoid: avoid, limit: count - out.length);
      out.addAll(fresh);
      if (fresh.isEmpty || _more == null) _video = null;
    }
    final top = [for (final t in topSongs(plays, history.track, now: now)) t.song];
    out = withFavourites(out, lovedLike(station, top, avoid));
    for (final song in out) {
      _given
        ..add(trackId(song))
        ..add(songIdentity(song));
    }
    return out;
  }

  /// A song the radio played (newest first) whose own radio hasn't been used.
  Json? _nextStation(List<Json> fresh, List<Json> queue) => [...fresh.reversed, ...queue.reversed]
      .where((s) => trackSite(s) == 'youtube' && isVideoId(trackId(s)) && !_usedVideos.contains(trackId(s)))
      .firstOrNull;
}
