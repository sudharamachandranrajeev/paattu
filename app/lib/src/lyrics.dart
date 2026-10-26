// A song's words, timed to it where they can be, for Now Playing.
//
// LRCLIB (lrclib.net, open and free, no key) has film songs' words in their
// own script, most of them timed line by line (LRC). The song is looked for by
// its title and film, and a find is taken only when its name is the song's.
// Its timing is taken as it is only when its length is within 2 seconds of the
// song's. YouTube Music's Lyrics tab is asked as well: its words are timed to
// the song as YouTube Music has it (the "song" upload, not a music video).
//
// Words timed to another upload of the song than the one playing (a music
// video with a longer start, say) are put in step with it: the two uploads'
// loudness over time (player/rhythm.dart) are lined up, and the lines moved by
// how far apart they are. Words that can't be lined up are shown untimed.
//
// Each line comes with its words in English letters (transliterate.dart) when
// it's in an Indian script. Finds and misses are kept in the app's cache, a
// miss for 3 days, and a find made while a site was down for an hour.
// paattu/lyrics.py does the same (tests/lyrics_cases.json).

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';

import 'app_state.dart' show appVersion;
import 'links.dart';
import 'log.dart';
import 'sources/http.dart';
import 'sources/youtube_music.dart';
import 'track.dart';
import 'transliterate.dart';
import 'util.dart';

const _lrclib = 'https://lrclib.net/api/search';
const _missKeep = Duration(days: 3);
const _partialKeep = Duration(hours: 1);
const _timedWithin = 2;
const _sameSongWithin = 120;
const _version = 2;

/// The loudness envelopes rhythm.dart makes, a second's worth.
const _envelopeFps = 50;

final _stampRe = RegExp(r'^\[(\d+):(\d{1,2}(?:[.:]\d{1,3})?)\]');
final _offsetRe = RegExp(r'^\[offset:\s*([+-]?\d+)\]', caseSensitive: false, multiLine: true);
final _bracketsRe = RegExp(r'\s*[(\[][^)\]]*[)\]]');
final _notWordRe = RegExp(r'[^\p{L}\p{N}_]+', unicode: true);
final _linesRe = RegExp(r'\r\n|\r|\n');

double _round2(double x) => (x * 100).round() / 100;

/// Timed words ([mm:ss.xx] words, a line can carry several times) in time
/// order, [offset:ms] applied.
List<(double, String)> parseLrc(String? text) {
  final found = _offsetRe.firstMatch(text ?? '');
  final shift = found == null ? 0 : int.parse(found.group(1)!) / 1000;
  final out = <(double, String)>[];
  for (final raw in (text ?? '').split(_linesRe)) {
    final stamps = <double>[];
    var rest = raw.trim();
    for (var m = _stampRe.firstMatch(rest); m != null; m = _stampRe.firstMatch(rest)) {
      stamps.add(int.parse(m.group(1)!) * 60 + double.parse(m.group(2)!.replaceAll(':', '.')));
      rest = rest.substring(m.end);
    }
    for (final at in stamps) {
      out.add((_round2((at - shift).clamp(0, double.infinity).toDouble()), rest.trim()));
    }
  }
  return out..sort((a, b) => a.$1.compareTo(b.$1));
}

/// The words of a name to match on: no brackets, lower case.
Set<String> lyricWords(String? text) =>
    (text ?? '').replaceAll(_bracketsRe, ' ').toLowerCase().split(_notWordRe).where((w) => w.isNotEmpty).toSet();

/// Whether a find called [name] is the track: its title's words are all in
/// the name, or the name's are all in the title and film.
bool sameSong(String name, Json track) {
  final found = lyricWords(name);
  final title = lyricWords(asString(track['title'])), film = lyricWords(asString(track['movie']));
  if (found.isEmpty) return false;
  return [title, film].any((part) => part.isNotEmpty && found.containsAll(part)) ||
      title.union(film).containsAll(found);
}

String _plain(String name) => name.replaceAll(_bracketsRe, ' ').split(_notWordRe).where((w) => w.isNotEmpty).join(' ');

/// What to ask LRCLIB for: the title and film, then each alone (YouTube
/// titles mix the two up now and then).
List<String> lyricQueries(Json track) {
  final title = _plain(asString(track['title']));
  var film = _plain(asString(track['movie']));
  if (film.toLowerCase() == title.toLowerCase()) film = '';
  final out = <String>[];
  for (final q in [[title, film].where((p) => p.isNotEmpty).join(' '), title, film]) {
    if (q.isNotEmpty && !out.contains(q)) out.add(q);
  }
  return out;
}

const _scriptOfLanguage = {
  'Hindi': 'devanagari',
  'Tamil': 'tamil',
  'Telugu': 'telugu',
  'Kannada': 'kannada',
  'Malayalam': 'malayalam',
};

/// The best of LRCLIB's finds for the track: (find, timed) or null, timed
/// when its timing fits the track as it is. One in the song's language comes
/// first (a film's song is often dubbed into others), timed next, then in its
/// own script, then the nearest length.
(Json, bool)? bestLyrics(Object? found, Json track, [String language = '']) {
  final length = toInt(track['duration']) ?? 0;
  final wanted = _scriptOfLanguage[language];
  (List<num>, Json, bool)? picked;
  for (final raw in asList(found)) {
    if (raw is! Map) continue;
    final item = asJson(raw);
    if (item['instrumental'] == true) continue;
    final synced = asString(item['syncedLyrics']), plain = asString(item['plainLyrics']);
    if ((synced.isEmpty && plain.isEmpty) || !sameSong(asString(item['trackName']), track)) continue;
    final duration = item['duration'] is num ? item['duration'] as num : 0;
    final gap = length > 0 && duration != 0 ? (duration - length).abs() : 0;
    if (gap > _sameSongWithin) continue;
    final timed = synced.isNotEmpty && gap <= _timedWithin;
    final script = scriptOf(synced.isNotEmpty ? synced : plain);
    final fits = wanted == null || script == null ? 1 : (script == wanted ? 2 : 0);
    final rank = <num>[fits, synced.isNotEmpty ? 1 : 0, script != null ? 1 : 0, -gap];
    if (picked == null || _greater(rank, picked.$1)) picked = (rank, item, timed);
  }
  return picked == null ? null : (picked.$2, picked.$3);
}

bool _greater(List<num> a, List<num> b) {
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return a[i] > b[i];
  }
  return false;
}

/// One line Now Playing shows: when it starts (null when not timed), its
/// words, and those in English letters ('' when they're in them already).
class LyricLine {
  const LyricLine(this.time, this.text, this.latin);
  final double? time;
  final String text;
  final String latin;

  Json toJson() => {'time': time, 'text': text, 'latin': latin};
}

/// A song's words as shown.
class SongLyrics {
  const SongLyrics({required this.lines, required this.synced, this.source = '', this.script = 'latin'});
  static const none = SongLyrics(lines: [], synced: false);

  final List<LyricLine> lines;
  final bool synced;
  final String source;
  final String script;

  bool get found => lines.isNotEmpty;
  String get language => scriptLanguages[script] ?? '';

  /// The line sung at [seconds], or -1 before the first.
  int lineAt(double seconds) {
    if (!synced) return -1;
    var at = -1;
    for (var i = 0; i < lines.length; i++) {
      if ((lines[i].time ?? 0) > seconds) break;
      at = i;
    }
    return at;
  }

  Json toJson() => found || synced || source.isNotEmpty
      ? {
          'found': found,
          'synced': synced,
          'source': source,
          'script': script,
          'language': language,
          'lines': [for (final l in lines) l.toJson()],
        }
      : {'found': false, 'synced': false, 'lines': const []};
}

List<double> _coarse(List<int> level, int step) => [
      for (var i = 0; i + step <= level.length; i += step)
        level.sublist(i, i + step).fold(0, (a, b) => a + b) / step,
    ];

double _pearson(List<double> a, List<double> b) {
  final n = a.length;
  final ma = a.fold(0.0, (x, y) => x + y) / n, mb = b.fold(0.0, (x, y) => x + y) / n;
  var sab = 0.0, saa = 0.0, sbb = 0.0;
  for (var i = 0; i < n; i++) {
    final dx = a[i] - ma, dy = b[i] - mb;
    sab += dx * dy;
    saa += dx * dx;
    sbb += dy * dy;
  }
  return saa > 0 && sbb > 0 ? sab / sqrt(saa * sbb) : -1;
}

/// How many seconds later the song comes in the upload [played] than in the
/// [reference] upload the words are timed to, from the two loudness
/// envelopes ([fps] a second), up to [most] either way; or null when they
/// don't line up clearly (not the same recording, say). Lined up a tenth of
/// a second at a time; taken when the best fit is a close one (0.6) and
/// clearly better (by 0.1) than any other a second or more from it.
double? lyricShift(List<int> played, List<int> reference, int fps, num most) {
  final step = max(1, fps ~/ 10);
  final a = _coarse(played, step), b = _coarse(reference, step);
  final need = 0.6 * min(a.length, b.length);
  final scores = <int, double>{};
  final reach = (most * 10).toInt();
  for (var s = -reach; s <= reach; s++) {
    final lo = max(0, -s), hi = min(b.length, a.length - s);
    if (hi - lo >= max(need, 2)) scores[s] = _pearson(a.sublist(lo + s, hi + s), b.sublist(lo, hi));
  }
  if (scores.isEmpty) return null;
  int? top;
  for (final MapEntry(:key, :value) in scores.entries) {
    if (top == null || value > scores[top]! || (value == scores[top]! && key.abs() < top.abs())) top = key;
  }
  var second = -1.0;
  for (final MapEntry(:key, :value) in scores.entries) {
    if ((key - top!).abs() > 10 && value > second) second = value;
  }
  if (scores[top]! < 0.6 || scores[top]! - second < 0.1) return null;
  return top! / 10;
}

bool _note(String text) => text.replaceAll(RegExp(r'[♪ ]'), '').isEmpty;

/// What Now Playing shows of a find ({synced, plain, source, shift}, or null).
SongLyrics shownLyrics(Json? found, {bool latin = true}) {
  if (found == null) return SongLyrics.none;
  final synced = asString(found['synced']);
  final shift = found['shift'] is num ? (found['shift'] as num).toDouble() : 0.0;
  final timed = synced.isNotEmpty
      ? [
          for (final (at, t) in parseLrc(synced))
            (_round2(max(0.0, at + shift)) as double?, _note(t) ? '' : t),
        ]
      : [for (final line in asString(found['plain']).split(_linesRe)) (null, line.trim())];
  final scripts = [for (final (_, t) in timed) scriptOf(t)];
  final out = [
    for (var i = 0; i < timed.length; i++)
      LyricLine(timed[i].$1, timed[i].$2,
          latin && scripts[i] != null ? transliterate(timed[i].$2, scripts[i]) : ''),
  ];
  final named = scripts.nonNulls.toList();
  final worded = timed.where((l) => l.$2.isNotEmpty).length;
  String? script;
  if (named.isNotEmpty && named.length * 2 >= worded) {
    final counts = <String, int>{};
    for (final s in named) {
      counts[s] = (counts[s] ?? 0) + 1;
    }
    for (final MapEntry(:key, :value) in counts.entries) {
      if (script == null || value > counts[script]!) script = key;
    }
  }
  while (out.isNotEmpty && out.first.text.isEmpty && out.first.time == null) {
    out.removeAt(0);
  }
  return SongLyrics(lines: out, synced: synced.isNotEmpty, source: asString(found['source']), script: script ?? 'latin');
}

/// [items] by [gap], the smallest first, those as near in the order given.
List<T> _nearestFirst<T>(List<T> items, num Function(T) gap) {
  final order = [for (var i = 0; i < items.length; i++) i];
  order.sort((a, b) {
    final by = gap(items[a]).compareTo(gap(items[b]));
    return by != 0 ? by : a - b;
  });
  return [for (final i in order) items[i]];
}

/// Timed words that can't be put in step with the song, shown untimed.
Json _untimed(Json got) {
  var plain = asString(got['plain']);
  if (plain.isEmpty) {
    plain = [for (final (_, t) in parseLrc(asString(got['synced']))) if (!_note(t)) t].join('\n');
  }
  return {'synced': '', 'plain': plain, 'source': got['source']};
}

/// A song's loudness envelope (rhythm.dart's level), or null when it can't
/// be had now (saving data, say).
typedef LyricsLevel = Future<List<int>?> Function(Json track);

/// The song's words from the internet: {synced, plain, source, shift,
/// partial} or null. [level] gives a song's loudness envelope, to put words
/// timed to another upload in step with this one; without it those are shown
/// untimed. partial: a site couldn't be asked, so a better find may come
/// later.
Future<Json?> findLyrics(Json track, String language, {LyricsLevel? level}) async {
  final length = toInt(track['duration']) ?? 0;
  var partial = false, asked = false;
  Json? plain;
  // LRCLIB's words timed to another upload: (got, its length).
  final off = <(Json, double)>[];
  for (final query in lyricQueries(track)) {
    (Json, bool)? picked;
    try {
      picked = bestLyrics(await _askLrclib(query), track, language);
      asked = true;
    } catch (_) {
      partial = true;
      continue; // try the next name, then YouTube Music
    }
    if (picked == null) continue;
    final (item, timed) = picked;
    final got = <String, dynamic>{
      'synced': asString(item['syncedLyrics']),
      'plain': asString(item['plainLyrics']),
      'source': 'LRCLIB',
    };
    if (timed) return {...got, 'shift': 0, 'partial': false};
    final duration = item['duration'];
    if (asString(got['synced']).isNotEmpty && duration is num && duration != 0 &&
        off.every((o) => o.$1['synced'] != got['synced'])) {
      off.add((got, duration.toDouble()));
    }
    plain ??= _untimed(got);
  }

  // Words timed to another upload: (got, its length, that upload's id).
  final elsewhere = <(Json, double, String)>[];
  final id = trackId(track);
  final video = isVideoId(id) && asString(track['url']).isEmpty ? id : null;
  try {
    var songs = <Json>[];
    if (asString(track['title']).isNotEmpty) {
      final queries = lyricQueries(track);
      songs = [
        for (final song in await searchMusic(queries.isEmpty ? '' : queries.first, limit: 5))
          if (sameSong(asString(song['title']), track) && trackId(song).isNotEmpty) song,
      ];
    }
    for (final (got, at) in off) {
      // LRCLIB's timing is to an upload as long as its find: YouTube Music's
      // song of that length, likely.
      for (final song in songs) {
        if (((toInt(song['duration']) ?? 0) - at).abs() <= _timedWithin) {
          elsewhere.add((got, at, trackId(song)));
          break;
        }
      }
    }
    int gap(Json song) => ((toInt(song['duration']) ?? 0) - length).abs();
    final near = _nearestFirst([
      for (final song in songs)
        if (length == 0 || gap(song) <= _sameSongWithin) song,
    ], gap);
    if (near.isNotEmpty || video != null) {
      final song = near.isNotEmpty ? near.first : {'id': video, 'duration': 0};
      final got = await musicLyricsOf(trackId(song));
      if (got != null && asString(got['synced']).isNotEmpty) {
        final at = toInt(song['duration']) ?? 0;
        if (trackId(song) == id || (length > 0 && at > 0 && (at - length).abs() <= _timedWithin)) {
          return {...got, 'shift': 0, 'partial': partial};
        }
        if (at > 0) elsewhere.add((got, at.toDouble(), trackId(song)));
        plain ??= _untimed(got);
      } else if (got != null) {
        plain ??= got;
      }
    }
    asked = true;
  } catch (_) {
    partial = true; // what LRCLIB found, then
  }

  // The nearest in length first: the likeliest to line up.
  for (final (got, at, reference) in _nearestFirst(elsewhere, (e) => (e.$2 - length).abs()).take(2)) {
    if (level == null || length == 0) continue;
    try {
      final played = await level(track), theirs = await level({'id': reference});
      if (played == null || theirs == null) {
        partial = true;
        continue;
      }
      final shift = lyricShift(played, theirs, _envelopeFps, (at - length).abs() + 8);
      if (shift != null) return {...got, 'shift': shift, 'partial': partial};
    } catch (_) {
      partial = true; // shown untimed for now
    }
  }
  if (plain != null) return {...plain, 'shift': 0, 'partial': partial};
  if (!asked) throw StateError("couldn't ask for the words");
  // Nothing found while a site was down: asked again sooner than a miss.
  return partial ? {'synced': '', 'plain': '', 'source': '', 'shift': 0, 'partial': true} : null;
}

Future<Object?> _askLrclib(String query) async {
  final uri = Uri.parse(_lrclib).replace(queryParameters: {'q': query});
  final headers = {'User-Agent': 'Paattu/$appVersion (https://github.com/sudharamachandranrajeev/paattu)'};
  try {
    return await getJson(uri, headers: headers);
  } catch (_) {
    await Future<void>.delayed(const Duration(seconds: 1)); // LRCLIB is busy now and then (503)
    return getJson(uri, headers: headers);
  }
}

typedef LyricsFinder = Future<Json?> Function(Json track, String language, {LyricsLevel? level});

/// Songs' words, kept in [dir] (one file a song, as lyrics.py keeps them).
/// [level] gives songs' loudness, to line words up with the upload playing.
class Lyrics {
  Lyrics(this.dir, {LyricsFinder? find, this.level}) : _find = find ?? findLyrics;

  final Directory dir;
  final LyricsFinder _find;
  final LyricsLevel? level;
  final _asking = <String, Future<Json?>>{};

  File _file(Json track) =>
      File('${dir.path}${Platform.pathSeparator}${sha1.convert(utf8.encode(trackKey(track))).toString().substring(0, 20)}.json');

  /// The song's words (found or not), from what was kept when there.
  Future<Json?> lookup(Json track, String language, {bool refresh = false}) {
    final key = trackKey(track);
    // The callback mustn't hand back the future it's removing: whenComplete
    // would wait on it, and so on itself.
    return _asking[key] ??= _lookup(track, language, refresh).whenComplete(() {
      _asking.remove(key);
    });
  }

  Future<Json?> _lookup(Json track, String language, bool refresh) async {
    final file = _file(track);
    final now = DateTime.now();
    try {
      if (!refresh && await file.exists()) {
        final kept = asJson(jsonDecode(await file.readAsString()));
        final fetched = DateTime.fromMillisecondsSinceEpoch(((kept['fetched'] as num?) ?? 0).toInt() * 1000);
        final found = kept['found'] == null ? null : asJson(kept['found']);
        final keep = found == null ? _missKeep : (found['partial'] == true ? _partialKeep : null);
        if (kept['version'] == _version && (keep == null || now.difference(fetched) < keep)) return found;
      }
    } catch (error) {
      problemLog.warn('lyrics: ${errorText(error)}');
    }
    final found = await _find(track, language, level: level);
    try {
      await dir.create(recursive: true);
      final tmp = File('${file.path}.tmp');
      await tmp.writeAsString(
          jsonEncode({'version': _version, 'fetched': now.millisecondsSinceEpoch ~/ 1000, 'id': trackKey(track), 'found': found}),
          flush: true);
      await tmp.rename(file.path);
    } catch (error) {
      problemLog.warn('lyrics: ${errorText(error)}');
    }
    return found;
  }
}
