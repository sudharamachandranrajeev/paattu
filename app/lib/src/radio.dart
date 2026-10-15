// The radio: songs like a song, from YouTube Music's own radio for it, a
// helping at a time as the queue runs out. Like Spotify's and YouTube's, it
// leaves out what was played in the last few hours and songs skipped more
// than once, and when one song's radio runs dry it carries on from a song it
// played. paattu/radio.py does the same on the desktop.

import 'history.dart';
import 'links.dart';
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
    };
    final out = <Json>[];
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
      final fresh = interleaveSongs([page.songs], avoid: avoid, limit: count - out.length);
      out.addAll(fresh);
      if (fresh.isEmpty || _more == null) _video = null;
    }
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
