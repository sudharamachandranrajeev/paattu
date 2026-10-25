// Playlists made for you from what you play (history.dart): a daily mix of
// songs you love with a few like them, a weekly list of songs new to you
// like what you played lately, and the month's most played. Plus playlists
// made from a description ("Ilaiyaraaja melodies, rain songs, Premam").
// paattu/made.py makes the same ones on the desktop.

import 'dart:math';

import 'history.dart';
import 'library.dart';
import 'radio.dart';
import 'sources/youtube_music.dart';
import 'track.dart';
import 'util.dart';

const madeKinds = ['daily', 'weekly', 'monthly'];

/// Songs in a made playlist.
const madeSize = 30;

/// A made playlist with fewer songs was cut short (YouTube Music didn't
/// answer): it plays, but isn't kept, so the next try makes it again.
const madeKeep = madeSize ~/ 2;

/// The songs of a stored made playlist if it's the one for [key] and whole
/// enough to keep (made.py's kept_made).
List<Json>? keptMade(({String key, List<Json> tracks})? made, String key) =>
    made != null && made.key == key && made.tracks.length >= madeKeep ? made.tracks : null;

String madeTitle(String kind) => switch (kind) {
      'daily' => 'Daily mix',
      'weekly' => 'Weekly discovery',
      _ => 'Monthly top',
    };

String madeBlurb(String kind) => switch (kind) {
      'daily' => 'Songs you love and a few like them. New every day',
      'weekly' => 'Songs new to you, like what you played lately. New every Monday',
      _ => 'What you played most in the last 30 days',
    };

/// The day, week or month a playlist is made for: 2026-10-15, 2026-W42
/// (the ISO week) or 2026-10.
String periodKey(String kind, DateTime now) {
  String two(int n) => n.toString().padLeft(2, '0');
  switch (kind) {
    case 'daily':
      return '${now.year}-${two(now.month)}-${two(now.day)}';
    case 'weekly':
      final day = DateTime.utc(now.year, now.month, now.day);
      final thursday = day.add(Duration(days: DateTime.thursday - day.weekday));
      final week = thursday.difference(DateTime.utc(thursday.year)).inDays ~/ 7 + 1;
      return '${thursday.year}-W${two(week)}';
    default:
      return '${now.year}-${two(now.month)}';
  }
}

typedef Liked = ({Json song, double score, int count});

/// The songs played within [days], most liked first (see [liking]); songs
/// skipped more than played are left out.
List<Liked> topSongs(List<Json> plays, Json? Function(String id) track,
    {required DateTime now, int days = 30, double halfLife = 7}) {
  String keyOf(String id) => songIdentity(track(id) ?? {'id': id});
  final liked = liking(plays, now: now, days: days, halfLife: halfLife, keyOf: keyOf);
  final out = <Liked>[
    for (final MapEntry(:key, :value) in liked.score.entries)
      if (value > 0)
        if (track(liked.ids[key]!) case final song?) (song: song, score: value, count: liked.count[key] ?? 0),
  ];
  out.sort((a, b) => b.score.compareTo(a.score));
  return out;
}

/// [count] of [items] picked at random, an item [weight] times as likely as
/// one of weight 1 (Efraimidis and Spirakis' weighted sampling).
List<T> weightedPick<T>(List<T> items, double Function(T item) weight, int count, Random random) {
  final keyed = [
    for (final item in items) (item, pow(random.nextDouble(), 1 / max(weight(item), 1e-6)).toDouble()),
  ]..sort((a, b) => b.$2.compareTo(a.$2));
  return [for (final (item, _) in keyed.take(count)) item];
}

/// Two songs you know, then one new one, and so on; when one kind runs out
/// the other fills the list.
List<Json> dailyMix(List<Json> familiar, List<Json> fresh, {int size = madeSize}) {
  final out = <Json>[];
  final seen = <String>{};
  var f = 0, n = 0;
  bool take(List<Json> list, int at) {
    final song = list[at];
    final key = songIdentity(song);
    if (!seen.add(trackId(song)) || !seen.add(key)) return false;
    out.add(song);
    return true;
  }

  while (out.length < size && (f < familiar.length || n < fresh.length)) {
    final wantFresh = out.length % 3 == 2;
    if ((wantFresh && n < fresh.length) || f >= familiar.length) {
      take(fresh, n++);
    } else {
      take(familiar, f++);
    }
  }
  return out;
}

final _describeSplitRe = RegExp(r'[,;\n/+&]|\s+(?:and|with|plus)\s+', caseSensitive: false);
final _describeLeadRe = RegExp(
    r'^(?:(?:a|an|some)\s+)?(?:(?:playlist|mix)\s+(?:of|with|for)\s+)?(?:(?:the\s+)?(?:best|top)\s+)?(?:(?:songs?|hits|music)\s+(?:from|of|by|in)\s+)?',
    caseSensitive: false);

/// What a description asks for, one search each: "songs from Premam, rain
/// songs and Ilaiyaraaja" is Premam, rain songs and Ilaiyaraaja. Six at most.
List<String> describePhrases(String description) {
  final out = <String>[];
  for (final part in description.split(_describeSplitRe)) {
    final phrase = squash(squash(part).replaceFirst(_describeLeadRe, ''));
    if (phrase.isNotEmpty && !out.any((p) => p.toLowerCase() == phrase.toLowerCase())) out.add(phrase);
  }
  return out.take(6).toList();
}

/// A playlist of about [size] songs for [description]: the songs each part of
/// it finds on YouTube Music, taken in turn, topped up from the radio of each
/// part's best match.
Future<List<Json>> describePlaylist(String description, {int size = madeSize}) async {
  final phrases = describePhrases(description);
  if (phrases.isEmpty) throw SourceException('say what the playlist should have');
  final found = await Future.wait(
      [for (final phrase in phrases) searchMusic(phrase).catchError((Object _) => <Json>[])]);
  final avoid = <String>{};
  final out = interleaveSongs(found, avoid: avoid, limit: size);
  if (out.length < size) {
    final more = await Future.wait([
      for (final list in found)
        if (list.isNotEmpty) musicRadio(trackId(list.first)).then((page) => page.songs).catchError((Object _) => <Json>[]),
    ]);
    out.addAll(interleaveSongs(more, avoid: avoid, limit: size - out.length));
  }
  if (out.isEmpty) throw SourceException("couldn't find songs for that. Try other words, or check the internet connection");
  return out;
}

class MadeForYou {
  MadeForYou(this.history, this.library);

  final History history;
  final Library library;

  Json? _track(String id) => history.track(id) ?? library.track(id);

  /// This period's playlist of [kind], made now if there isn't one yet (or
  /// [refresh] makes a new one). The history keeps it, unless it was cut short.
  Future<List<Json>> playlist(String kind, {bool refresh = false}) async {
    final now = DateTime.now();
    final key = periodKey(kind, now);
    final kept = keptMade(history.made(kind), key);
    if (kept != null && !refresh) return kept;
    final songs = await _make(kind, now);
    if (songs.isEmpty) throw SourceException("couldn't make ${madeTitle(kind)}. Check the internet connection");
    if (songs.length >= madeKeep) history.setMade(kind, key, songs);
    return songs;
  }

  Future<List<Json>> _make(String kind, DateTime now) async {
    final random = Random();
    final plays = history.plays;
    final top = topSongs(plays, _track, now: now, days: kind == 'weekly' ? 28 : 30);
    final favourites = library.playlistTracks(favouritesId);
    final mine = [...favourites, ...library.playlistTracks(savedId)];
    final skipped = {
      ...skippedOften(plays, now),
      ...turnedDown(plays, keyOf: (id) => songIdentity(_track(id) ?? {'id': id})),
    };
    switch (kind) {
      case 'monthly':
        final most = [...top]..sort((a, b) => b.count != a.count ? b.count.compareTo(a.count) : b.score.compareTo(a.score));
        final avoid = {...skipped};
        final out = interleaveSongs([
          [for (final t in most) t.song],
        ], avoid: avoid, limit: madeSize);
        out.addAll(interleaveSongs([[...favourites]..shuffle(random)], avoid: avoid, limit: madeSize - out.length));
        if (out.length < madeSize) {
          out.addAll(await _discover(await _seeds(top, mine, random), avoid, madeSize - out.length));
        }
        return out;
      case 'weekly':
        final avoid = <String>{
          ...skipped,
          for (final play in plays) ...{asString(play['id']), songIdentity(_track(asString(play['id'])) ?? play)},
          for (final song in mine) ...{trackId(song), songIdentity(song)},
        };
        return _discover(await _seeds(top, mine, random), avoid, madeSize);
      default:
        final favouriteIds = {for (final s in favourites) trackId(s)};
        final weights = <String, double>{
          for (final s in mine) trackId(s): favouriteIds.contains(trackId(s)) ? 1.0 : 0.5,
        };
        for (final t in top) {
          final id = trackId(t.song);
          weights[id] = (weights[id] ?? 0) + t.score;
        }
        final pool = interleaveSongs([
          [for (final t in top) t.song],
          mine,
        ], avoid: {...skipped});
        final familiar = weightedPick(pool, (s) => weights[trackId(s)] ?? 0.5, madeSize * 2 ~/ 3, random);
        final avoid = <String>{
          ...skipped,
          for (final s in familiar) ...{trackId(s), songIdentity(s)},
          ...heardSince(plays, now.subtract(const Duration(days: 3)),
              keyOf: (id) => songIdentity(_track(id) ?? {'id': id})),
        };
        final fresh = await _discover(await _seeds(top, mine, random, from: familiar), avoid, madeSize);
        return dailyMix(familiar, fresh);
    }
  }

  /// Up to five songs to find new songs from: [from], else the songs you
  /// like most (a few of the best at random), your favourites and saved
  /// songs, or, for someone new, today's Malayalam and Tamil hits.
  Future<List<Json>> _seeds(List<Liked> top, List<Json> mine, Random random, {List<Json>? from}) async {
    final liked = [for (final t in top.take(10)) t.song];
    var seeds = from != null && from.isNotEmpty
        ? weightedPick(from, (_) => 1, 3, random)
        : [...weightedPick(liked, (_) => 1, 5, random), ...weightedPick(mine, (_) => 1, 5, random)];
    if (seeds.isEmpty) {
      final hits = await Future.wait([
        for (final query in ['Malayalam hits', 'Tamil hits']) searchMusic(query, limit: 5).catchError((Object _) => <Json>[]),
      ]);
      seeds = interleaveSongs(hits);
    }
    return seeds.take(5).toList();
  }

  /// Up to [count] songs from the radios of [seeds], taken in turn, leaving
  /// out [avoid] (which grows).
  Future<List<Json>> _discover(List<Json> seeds, Set<String> avoid, int count) async {
    final pages = await Future.wait([
      for (final seed in seeds)
        () async {
          final video = await youtubeIdFor(seed);
          if (video == null) return <Json>[];
          final first = await musicRadio(video);
          if (first.more == null || first.songs.length >= count) return first.songs;
          final next = await musicRadio(video, more: first.more);
          return [...first.songs, ...next.songs];
        }()
            .catchError((Object _) => <Json>[]),
    ]);
    return interleaveSongs(pages, avoid: avoid, limit: count);
  }
}
