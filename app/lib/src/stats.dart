// Your music in numbers, from the play history: how much you listened, what
// you played most, when, how often you skip, and a few titles earned along
// the way (quirks). paattu/stats.py does the same; tests/stats_cases.json
// holds cases both run.

import 'history.dart';
import 'radio.dart' show songLanguage, themes;
import 'util.dart';

const _day = 86400;

class MusicStats {
  int plays = 0, skips = 0, removed = 0, minutes = 0, songs = 0, artists = 0, streak = 0, favouritePlays = 0;
  final hours = List.filled(24, 0);
  List<(String, int)> topSongs = const [], topArtists = const [], topFilms = const [];
  final themes = <String, int>{};
  final languages = <String, int>{};

  /// As stats.py gives them, for the shared cases.
  Json toJson() => {
    'plays': plays,
    'skips': skips,
    'removed': removed,
    'minutes': minutes,
    'songs': songs,
    'artists': artists,
    'streak': streak,
    'favourite_plays': favouritePlays,
    'hours': hours,
    'top_songs': [for (final (name, n) in topSongs) [name, n]],
    'top_artists': [for (final (name, n) in topArtists) [name, n]],
    'top_films': [for (final (name, n) in topFilms) [name, n]],
    'themes': themes,
    'languages': languages,
  };
}

/// The numbers for the last [days] (null: all of it). [plays] can be
/// History.signals (songs taken out of the radio count as such). [hourOf]
/// gives a play's hour of the day, 0-23 (local time when not given).
MusicStats musicStats(
  List<Json> plays,
  Json? Function(String id) track, {
  required DateTime now,
  int? days,
  List<Json> favourites = const [],
  int Function(int at)? hourOf,
}) {
  hourOf ??= (at) => DateTime.fromMillisecondsSinceEpoch(at * 1000).hour;
  final since = days == null ? 0 : epochSeconds(now) - days * _day;
  final loved = {for (final s in favourites) songIdentity(s)};
  final out = MusicStats();
  final songs = <String, int>{}, artists = <String, int>{}, films = <String, int>{};
  final titles = <String, String>{};
  final daysPlayed = <int>{};
  var seconds = 0;
  for (final play in plays) {
    final at = toInt(play['at']) ?? 0;
    if (at < since) continue;
    if (play['removed'] == true) {
      out.removed++;
      continue;
    }
    seconds += toInt(play['heard']) ?? 0;
    if (!counted(play)) {
      out.skips++;
      continue;
    }
    final id = asString(play['id']);
    final song = track(id) ?? <String, dynamic>{'id': id};
    final key = songIdentity(song);
    out.plays++;
    songs[key] = (songs[key] ?? 0) + 1;
    titles.putIfAbsent(key, () => asString(song['title']).isNotEmpty ? asString(song['title']) : id);
    if (loved.contains(key)) out.favouritePlays++;
    for (final credit in asStrings(song['credits']).take(4)) {
      final name = credit.trim();
      if (name.isNotEmpty) artists[name] = (artists[name] ?? 0) + 1;
    }
    final film = asString(song['movie']).trim();
    if (film.isNotEmpty) films[film] = (films[film] ?? 0) + 1;
    for (final theme in themes(song)) {
      out.themes[theme] = (out.themes[theme] ?? 0) + 1;
    }
    final language = songLanguage(song);
    if (language.isNotEmpty) out.languages[language] = (out.languages[language] ?? 0) + 1;
    out.hours[hourOf(at)]++;
    daysPlayed.add(at ~/ _day);
  }
  out
    ..minutes = seconds ~/ 60
    ..songs = songs.length
    ..artists = artists.length
    ..topSongs = _top(songs, name: (key) => titles[key]!) // by song: two of one title stay two
    ..topArtists = _top(artists)
    ..topFilms = _top(films);
  var run = 0;
  for (final day in daysPlayed.toList()..sort()) {
    run = daysPlayed.contains(day - 1) ? run + 1 : 1;
    if (run > out.streak) out.streak = run;
  }
  return out;
}

List<(String, int)> _top(Map<String, int> counts, {int count = 5, String Function(String)? name}) {
  final show = name ?? (key) => key;
  final rows = counts.entries.toList()
    ..sort((a, b) =>
        a.value != b.value ? b.value.compareTo(a.value) : show(a.key).toLowerCase().compareTo(show(b.key).toLowerCase()));
  return [for (final e in rows.take(count)) (show(e.key), e.value)];
}

const themeTitles = {
  'love': ('Hopeless romantic', 'love songs'),
  'sad': ('Professional heartbreaker', 'sad songs'),
  'dance': ('Kuthu machine', 'songs to dance to'),
  'devotional': ('Devout ears', 'devotional songs'),
  'calm': ('Zen master', 'calm melodies'),
  'wedding': ('Wedding DJ in waiting', 'wedding songs'),
  'festival': ('Festival spirit', 'festival songs'),
  'rap': ('Mic dropper', 'rap'),
};

int _percent(num part, num whole) => (part * 100 / whole).round();

/// The titles your listening earned: (title, why), most telling first.
List<(String, String)> quirks(MusicStats s) {
  final out = <(String, String)>[];
  final plays = s.plays, skips = s.skips;
  if (plays == 0) return out;
  if (s.topSongs.isNotEmpty && s.topSongs.first.$2 >= 5) {
    final (name, n) = s.topSongs.first;
    out.add(('Stuck on repeat', '$name, $n times. It should start paying rent'));
  }
  if (s.topArtists.isNotEmpty && s.topArtists.first.$2 * 3 >= plays && plays >= 5) {
    final (name, n) = s.topArtists.first;
    out.add(('$name superfan', 'in ${_percent(n, plays)}% of your songs'));
  }
  if (s.themes.isNotEmpty) {
    final top = s.themes.entries.toList()
      ..sort((a, b) => a.value != b.value ? b.value.compareTo(a.value) : a.key.compareTo(b.key));
    final MapEntry(key: theme, value: n) = top.first;
    if (n * 5 >= plays) {
      final (title, what) = themeTitles[theme]!;
      out.add((title, '${_percent(n, plays)}% $what'));
    }
  }
  var peak = 0;
  for (var h = 1; h < 24; h++) {
    if (s.hours[h] > s.hours[peak]) peak = h;
  }
  out.add(_hourTitle(peak));
  final rate = skips / (plays + skips);
  if (rate >= 0.4) {
    out.add(('Itchy skip finger', 'skipped ${_percent(rate, 1)}% of songs within half a minute'));
  } else if (rate <= 0.1 && plays >= 10) {
    out.add(('Patient listener', 'skipped only ${_percent(rate, 1)}% of songs'));
  }
  final fresh = s.songs / plays;
  if (plays >= 10 && fresh >= 0.7) {
    out.add(('Explorer', '${s.songs} different songs in $plays plays'));
  } else if (plays >= 10 && fresh <= 0.3) {
    out.add(('Creature of habit', '${s.songs} songs, $plays plays'));
  }
  if (s.favouritePlays * 2 >= plays && plays >= 5) {
    out.add(('Loyal to the favourites', '${_percent(s.favouritePlays, plays)}% of your plays'));
  }
  if (s.streak >= 7) out.add(('Unbroken', 'music ${s.streak} days in a row'));
  if (s.minutes >= 150) out.add(('Feature-length', "${s.minutes} minutes: ${s.minutes ~/ 150} films' worth"));
  if (s.removed >= 3) out.add(('Picky DJ', 'took ${s.removed} songs out of the radio'));
  return out;
}

(String, String) _hourTitle(int hour) {
  final clock = '${hour % 12 == 0 ? 12 : hour % 12} ${hour < 12 ? 'AM' : 'PM'}';
  final why = 'you play most around $clock';
  if (hour < 5) return ('Midnight philosopher', why);
  if (hour < 9) return ('Early bird with headphones', why);
  if (hour < 17) return ('Daytime groover', why);
  if (hour < 21) return ('Sunset crooner', why);
  return ('Night owl', why);
}
