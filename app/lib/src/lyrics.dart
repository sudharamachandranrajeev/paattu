// A song's words, timed to it where they can be, for Now Playing.
//
// LRCLIB (lrclib.net, open and free, no key) has film songs' words in their
// own script, most of them timed line by line (LRC). The song is looked for by
// its title and film, and a find is taken only when its name is the song's;
// timing only when its length is within 10 seconds of the song's (a music
// video with a longer start would be out of step), otherwise its words as
// they are. YouTube Music (its Lyrics tab, from Musixmatch) is asked next:
// words in English letters, not timed.
//
// Each line comes with its words in English letters (transliterate.dart) when
// it's in an Indian script. Finds and misses are kept in the app's cache, a
// miss for 3 days. paattu/lyrics.py does the same (tests/lyrics_cases.json).

import 'dart:convert';
import 'dart:io';

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
const _timedWithin = 10;
const _sameSongWithin = 120;

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

/// The best of LRCLIB's finds for the track: (find, timed) or null. One in
/// the song's language comes first (a film's song is often dubbed into
/// others), timed next, then in its own script, then the nearest length.
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
    final rank = <num>[fits, timed ? 1 : 0, script != null ? 1 : 0, -gap];
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

/// What Now Playing shows of a find ({synced, plain, source}, or null).
SongLyrics shownLyrics(Json? found, {bool latin = true}) {
  if (found == null) return SongLyrics.none;
  final synced = asString(found['synced']);
  final timed = synced.isNotEmpty
      ? [for (final (at, t) in parseLrc(synced)) (at as double?, t)]
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

/// The song's words from the internet: {synced, plain, source} or null.
Future<Json?> findLyrics(Json track, String language) async {
  var asked = false;
  Json? fallback;
  for (final query in lyricQueries(track)) {
    (Json, bool)? picked;
    try {
      picked = bestLyrics(await _askLrclib(query), track, language);
      asked = true;
    } catch (_) {
      continue; // try the next name, then YouTube Music
    }
    if (picked == null) continue;
    final (item, timed) = picked;
    var plain = asString(item['plainLyrics']);
    if (!timed && plain.isEmpty) plain = [for (final (_, t) in parseLrc(asString(item['syncedLyrics']))) t].join('\n');
    final got = <String, dynamic>{
      'synced': timed ? asString(item['syncedLyrics']) : '',
      'plain': plain,
      'source': 'LRCLIB',
    };
    if (timed) return got;
    fallback ??= got;
  }
  if (fallback != null) return fallback;
  final id = trackId(track);
  String? video = isVideoId(id) && asString(track['url']).isEmpty ? id : null;
  try {
    if (video == null && asString(track['title']).isNotEmpty) {
      final length = toInt(track['duration']) ?? 0;
      final queries = lyricQueries(track);
      for (final song in await searchMusic(queries.isEmpty ? '' : queries.first, limit: 5)) {
        if (sameSong(asString(song['title']), track) &&
            (length == 0 || ((toInt(song['duration']) ?? 0) - length).abs() <= 5)) {
          video = trackId(song);
          break;
        }
      }
    }
    if (video != null) {
      final found = await musicLyricsOf(video);
      if (found != null) return {'plain': found.$1, 'synced': '', 'source': found.$2};
    }
  } catch (_) {
    if (!asked) rethrow;
  }
  return null;
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

typedef LyricsFinder = Future<Json?> Function(Json track, String language);

/// Songs' words, kept in [dir] (one file a song, as lyrics.py keeps them).
class Lyrics {
  Lyrics(this.dir, {LyricsFinder? find}) : _find = find ?? findLyrics;

  final Directory dir;
  final LyricsFinder _find;
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
        if (kept['found'] != null || now.difference(fetched) < _missKeep) {
          return kept['found'] == null ? null : asJson(kept['found']);
        }
      }
    } catch (error) {
      problemLog.warn('lyrics: ${errorText(error)}');
    }
    final found = await _find(track, language);
    try {
      await dir.create(recursive: true);
      final tmp = File('${file.path}.tmp');
      await tmp.writeAsString(
          jsonEncode({'fetched': now.millisecondsSinceEpoch ~/ 1000, 'id': trackKey(track), 'found': found}),
          flush: true);
      await tmp.rename(file.path);
    } catch (error) {
      problemLog.warn('lyrics: ${errorText(error)}');
    }
    return found;
  }
}
