// The radio: songs like a song, from YouTube Music's own radio for it, a
// helping at a time as the queue runs out. Like Spotify's and YouTube's, it
// leaves out what was played in the last few hours, songs skipped more than
// once, songs turned down (skipped the first time) and songs you took out of
// Up next, and when one song's radio runs dry it carries on from a song it
// played. It plays to your taste too: songs by the singers, composers and
// films you play to the end come first (tasteOrder), those of ones you skip
// or take out go down, those of ones you keep taking out are left out
// (shunned), and a few songs you love that share something with the station
// are mixed in. Each helping is ranked (Affinity) before your taste: songs you
// play most, then your favourites and songs very like them, then songs in
// your playlists and ones close to them, then songs by the singers and
// composers, of the themes and in the languages you play a lot.
// paattu/radio.py does the same on the desktop.

import 'dart:math';

import 'history.dart';
import 'links.dart';
import 'made.dart' show topSongs;
import 'sources/sources.dart' show sameSong;
import 'sources/youtube_music.dart';
import 'titles.dart' show guessLanguage;
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
  SongRadio(this.history, {this.favourites, this.playlists, this.languageOf});

  final History history;

  /// Your favourites and the songs in your other playlists, for Affinity.
  final List<Json> Function()? favourites;
  final List<Json> Function()? playlists;
  final String Function(Json song)? languageOf;

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
    final plays = history.signals;
    String keyOf(String id) => songIdentity(history.track(id) ?? {'id': id});
    final avoid = <String>{
      ..._given,
      for (final song in queue) ...{trackId(song), songIdentity(song)},
      ...heardSince(plays, now.subtract(const Duration(hours: 6)), keyOf: keyOf),
      ...skippedOften(plays, now),
      ...turnedDown(plays, keyOf: keyOf),
    };
    final likes = taste(plays, history.track, now: now);
    final shun = shunned(plays, history.track, likes, now: now);
    final affinity = Affinity(
      plays,
      history.track,
      now: now,
      favourites: favourites?.call() ?? const [],
      playlists: playlists?.call() ?? const [],
      languageOf: languageOf,
    );
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
      final liked = [
        for (final song in affinity.order(tasteOrder(page.songs, likes)))
          if (!features(song).any(shun.contains)) song,
      ];
      final fresh = interleaveSongs([liked], avoid: avoid, limit: count - out.length);
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

/// What a song is about, from words in its title: theme -> words.
const themeWords = {
  'love': ['love', 'romantic', 'romance', 'pranayam', 'kadhal', 'kaadhal', 'ishq', 'prema'],
  'sad': ['sad', 'emotional', 'heartbreak', 'breakup', 'pathos', 'melancholy', 'sogam'],
  'dance': ['kuthu', 'dance', 'party', 'mass', 'celebration', 'peppy', 'gaana', 'folk'],
  'devotional': ['devotional', 'bhakti', 'bhajan', 'ayyappa', 'christian', 'krishna', 'murugan', 'prayer'],
  'calm': ['melody', 'melodies', 'lullaby', 'lofi', 'unplugged', 'acoustic', 'reprise', 'soothing', 'soulful'],
  'wedding': ['wedding', 'kalyanam', 'marriage'],
  'festival': ['onam', 'christmas', 'vishu', 'pongal', 'diwali', 'eid'],
  'rap': ['rap', 'hiphop'],
};
final _themeOf = {
  for (final MapEntry(key: theme, value: words) in themeWords.entries)
    for (final word in words) word: theme,
};

/// The themes (themeWords) a song's title or upload's title speaks of.
List<String> themes(Json song) {
  final text = '${asString(song['title'])} ${asString(song['rawTitle'])}'.toLowerCase().replaceAll('hip hop', 'hiphop');
  return {
    for (final m in RegExp('[a-z]+').allMatches(text)) ?_themeOf[m[0]],
  }.toList()
    ..sort();
}

/// A song's language: its own, else guessed from its names.
String songLanguage(Json song) {
  final own = asString(song['language']).trim();
  if (own.isNotEmpty) return own[0].toUpperCase() + own.substring(1).toLowerCase();
  return guessLanguage([
    asString(song['title']),
    asString(song['movie']),
    asString(song['channel']),
    ...asStrings(song['credits']),
  ]);
}

/// How near a song is to what you play and keep, as a tier, best first:
///
///  0  a song you play again and again ([again] counted plays in [days]),
///     most played first
///  1  one of your favourites, or very like one (its film and a singer or
///     composer)
///  2  in one of your other playlists, or close to a song there (its film)
///  3  by a singer or composer you play a lot
///  4  of a theme (themes) you play a lot
///  5  in a language ([languageOf], songLanguage when not given) you play a lot
///  6  none of these
///
/// A lot is [often] counted plays in [days]. rank gives (tier, strength):
/// within a tier the stronger come first (the plays behind it; 2 for the song
/// itself in tiers 1 and 2, 1 for one like it). [plays] can be
/// History.signals: songs taken out don't count. As paattu/radio.py's.
class Affinity {
  Affinity(
    List<Json> plays,
    Json? Function(String id) track, {
    required DateTime now,
    List<Json> favourites = const [],
    List<Json> playlists = const [],
    String Function(Json song)? languageOf,
    int days = 90,
    this.often = 3,
    this.again = 2,
  }) : languageOf = languageOf ?? songLanguage {
    final since = epochSeconds(now) - days * 86400;
    for (final play in plays) {
      if (play['removed'] == true || (toInt(play['at']) ?? 0) < since || !counted(play)) continue;
      final song = track(asString(play['id']));
      if (song == null) continue;
      final key = songIdentity(song);
      _played[key] = (_played[key] ?? 0) + 1;
      for (final f in features(song)) {
        if (f.startsWith('by:')) _by[f] = (_by[f] ?? 0) + 1;
      }
      for (final t in themes(song)) {
        _themes[t] = (_themes[t] ?? 0) + 1;
      }
      final language = this.languageOf(song);
      if (language.isNotEmpty) _languages[language] = (_languages[language] ?? 0) + 1;
    }
    _favourites.addAll(favourites.map(songIdentity));
    for (final s in favourites) {
      final fs = features(s);
      for (final f in fs.where((f) => f.startsWith('film:'))) {
        for (final c in fs.where((c) => c.startsWith('by:'))) {
          _lovedBy.add('$f|$c');
        }
      }
    }
    _kept.addAll(playlists.map(songIdentity));
    _keptFilms.addAll([for (final s in playlists) ...features(s).where((f) => f.startsWith('film:'))]);
  }

  final int often, again;
  final String Function(Json song) languageOf;
  final _played = <String, int>{}, _by = <String, int>{}, _themes = <String, int>{}, _languages = <String, int>{};
  final _favourites = <String>{}, _lovedBy = <String>{}, _kept = <String>{}, _keptFilms = <String>{};

  (int, int) rank(Json song) {
    final key = songIdentity(song);
    final mine = features(song);
    final films = mine.where((f) => f.startsWith('film:')).toList();
    final by = mine.where((f) => f.startsWith('by:')).toList();
    if ((_played[key] ?? 0) >= again) return (0, _played[key]!);
    if (_favourites.contains(key)) return (1, 2);
    if (films.any((f) => by.any((c) => _lovedBy.contains('$f|$c')))) return (1, 1);
    if (_kept.contains(key)) return (2, 2);
    if (films.any(_keptFilms.contains)) return (2, 1);
    for (final (tier, counts, keys) in [
      (3, _by, by),
      (4, _themes, themes(song)),
      (5, _languages, [languageOf(song)]),
    ]) {
      final best = keys.fold(0, (most, k) => max(most, counts[k] ?? 0));
      if (best >= often) return (tier, best);
    }
    return (6, 0);
  }

  /// [songs] by tier, the stronger first within one, else as they were.
  List<Json> order(List<Json> songs) {
    final ranked = [for (var i = 0; i < songs.length; i++) (rank(songs[i]), i, songs[i])]
      ..sort((a, b) {
        if (a.$1.$1 != b.$1.$1) return a.$1.$1.compareTo(b.$1.$1);
        if (a.$1.$2 != b.$1.$2) return b.$1.$2.compareTo(a.$1.$2);
        return a.$2.compareTo(b.$2);
      });
    return [for (final (_, _, song) in ranked) song];
  }
}
