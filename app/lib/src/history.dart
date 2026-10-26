// What was played and for how long (history.json beside library.json), which
// the daily, weekly and monthly playlists are made from and which keeps the
// radio from repeating itself. The desktop Paattu keeps the same file in
// ~/.local/share/paattu/history.json (paattu/history.py):
//
//     plays   [{id, at (seconds since 1970), heard (seconds), length}], oldest first
//     removed [{id, at}], oldest first: songs the radio queued that you took
//             out of Up next before they played
//     tracks  id -> the song, for the ids in plays, removed and made
//     made    daily|weekly|monthly -> {key, tracks[ids]}: the playlist made
//             for that day, week or month

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'titles.dart';
import 'track.dart';
import 'util.dart';

/// Plays kept; older ones are dropped.
const historyLimit = 3000;

/// Songs taken out of the radio kept.
const removedLimit = 500;

/// A play that counts: half the song, or 30 seconds of a long one.
bool counted(Json play) {
  final heard = toInt(play['heard']) ?? 0;
  final length = toInt(play['length']) ?? 0;
  return heard >= (length > 0 ? min(30, length ~/ 2) : 30);
}

/// A song heard to its end: 90% of it, or all but its last 20 seconds (so a
/// fade into the next song counts). With its length unknown, a play that
/// counts. These are kept on the device and join the played playlists.
bool fullyPlayed(Json play) {
  final heard = toInt(play['heard']) ?? 0;
  final length = toInt(play['length']) ?? 0;
  if (length <= 0) return counted(play);
  return heard >= max<num>(1, min(length * 0.9, length - 20));
}

int epochSeconds(DateTime t) => t.millisecondsSinceEpoch ~/ 1000;

class History extends ChangeNotifier {
  History(this.file);

  final File file;
  Json data = _empty();
  Timer? _saveTimer;

  static Json _empty() => {
    'version': 1,
    'plays': <dynamic>[],
    'removed': <dynamic>[],
    'tracks': <String, dynamic>{},
    'made': <String, dynamic>{},
  };

  List<Json> get plays => asList(data['plays']).map(asJson).toList();

  /// The plays with the songs taken out of the radio among them (as plays of
  /// nothing, marked removed), oldest first: what the radio and the playlists
  /// made for you learn from. A song taken out is turned down (turnedDown)
  /// until it is played to the end.
  List<Json> get signals {
    final all = [
      ...plays,
      for (final r in asList(data['removed']).map(asJson))
        if (asString(r['id']).isNotEmpty)
          <String, dynamic>{'id': asString(r['id']), 'at': toInt(r['at']) ?? 0, 'heard': 0, 'removed': true},
    ];
    final order = [for (var i = 0; i < all.length; i++) (toInt(all[i]['at']) ?? 0, i)]
      ..sort((a, b) => a.$1 != b.$1 ? a.$1.compareTo(b.$1) : a.$2.compareTo(b.$2));
    return [for (final (_, i) in order) all[i]];
  }

  Json get _tracks => asJson(data['tracks']);
  Json get _made => asJson(data['made']);

  Json? track(String id) => _tracks[id] is Map ? asJson(_tracks[id]) : null;

  Future<void> load() async {
    try {
      if (await file.exists()) {
        final decoded = asJson(jsonDecode(await file.readAsString()));
        data = {..._empty(), ...decoded};
        for (final key in ['tracks', 'made']) {
          if (data[key] is! Map) data[key] = <String, dynamic>{};
        }
        for (final key in ['plays', 'removed']) {
          if (data[key] is! List) data[key] = <dynamic>[];
        }
      }
    } catch (error) {
      debugPrint('history: $error');
      data = _empty();
    }
    notifyListeners();
  }

  /// [track] played for [heard] seconds (of [length]).
  void played(Json track, int heard, {int? length, DateTime? at}) {
    final id = trackId(track);
    if (id.isEmpty || heard < 1) return;
    final list = asList(data['plays']);
    list.add(<String, dynamic>{
      'id': id,
      'at': epochSeconds(at ?? DateTime.now()),
      'heard': heard,
      if ((length ?? toInt(track['duration']) ?? 0) > 0) 'length': length ?? toInt(track['duration']),
    });
    if (list.length > historyLimit) list.removeRange(0, list.length - historyLimit);
    _tracks[id] = storedTrack(track);
    _prune();
    _changed();
  }

  /// [track], which the radio queued, taken out of Up next before it played.
  void removedFromRadio(Json track, {DateTime? at}) {
    final id = trackId(track);
    if (id.isEmpty) return;
    final list = asList(data['removed']);
    list.add(<String, dynamic>{'id': id, 'at': epochSeconds(at ?? DateTime.now())});
    if (list.length > removedLimit) list.removeRange(0, list.length - removedLimit);
    _tracks[id] = storedTrack(track);
    _prune();
    _changed();
  }

  /// Forget the songs with [feature] (a singer, composer or film, as features
  /// gives it) taken out of the radio, so it is no longer shunned. Returns how
  /// many.
  int forgive(String feature) {
    final list = asList(data['removed']);
    final before = list.length;
    list.removeWhere((r) => r is Map && features(track(asString(r['id'])) ?? const {}).contains(feature));
    _prune();
    _changed();
    return before - list.length;
  }

  /// The playlist made for [kind] ('daily', 'weekly', 'monthly') and the
  /// period it was made for, or null.
  ({String key, List<Json> tracks})? made(String kind) {
    final entry = asJson(_made[kind]);
    final key = asString(entry['key']);
    if (key.isEmpty) return null;
    return (key: key, tracks: [for (final id in asStrings(entry['tracks'])) ?track(id)]);
  }

  void setMade(String kind, String key, List<Json> songs) {
    for (final song in songs) {
      _tracks[trackId(song)] = storedTrack(song);
    }
    _made[kind] = <String, dynamic>{
      'key': key,
      'made': nowStamp(),
      'tracks': [for (final s in songs) trackId(s)],
    };
    _prune();
    _changed();
  }

  void clear() {
    // Where ListenBrainz sync got to stays: those plays were sent already.
    final kept = data['listenbrainz'];
    data = _empty();
    if (kept != null) data['listenbrainz'] = kept;
    _changed();
  }

  /// Changes made straight to [data] (listenbrainz.dart's sync).
  void edited() {
    _prune();
    _changed();
  }

  /// Forget songs nothing refers to any more.
  void _prune() {
    final used = <String>{
      for (final p in asList(data['plays'])) asString(asJson(p)['id']),
      for (final r in asList(data['removed'])) asString(asJson(r)['id']),
      for (final m in _made.values) ...asStrings(asJson(m)['tracks']),
    };
    _tracks.removeWhere((id, _) => !used.contains(id));
  }

  void _changed() {
    notifyListeners();
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(seconds: 2), save);
  }

  Future<void> save() async {
    _saveTimer?.cancel();
    await file.parent.create(recursive: true);
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(jsonEncode(data), flush: true);
    await tmp.rename(file.path);
  }
}

/// How much each song was liked lately: every counted play within [days],
/// worth less the older it is (half as much every [halfLife] days), less half
/// a play for every quick skip. Keyed by song (songKey), so a song's video
/// and audio uploads count together; [ids] maps each key to its latest id.
({Map<String, double> score, Map<String, String> ids, Map<String, int> count}) liking(
  List<Json> plays, {
  required DateTime now,
  int days = 30,
  double halfLife = 7,
  String Function(String id)? keyOf,
}) {
  final score = <String, double>{};
  final ids = <String, String>{};
  final count = <String, int>{};
  final since = epochSeconds(now) - days * 86400;
  for (final play in plays) {
    final at = toInt(play['at']) ?? 0;
    if (at < since) continue;
    final id = asString(play['id']);
    final key = keyOf?.call(id) ?? id;
    ids[key] = id;
    final age = (epochSeconds(now) - at) / 86400;
    if (counted(play)) {
      score[key] = (score[key] ?? 0) + pow(0.5, age / halfLife).toDouble();
      count[key] = (count[key] ?? 0) + 1;
    } else {
      score[key] = (score[key] ?? 0) - 0.5;
    }
  }
  return (score: score, ids: ids, count: count);
}

/// Songs skipped the first time they were played and not played to the end
/// since: the radio, the playlists made for you and the charts leave them
/// out. By id and by song.
Set<String> turnedDown(List<Json> plays, {String Function(String id)? keyOf}) {
  final first = <String, (String, bool)>{};
  final finished = <String>{};
  for (final play in plays) {
    final id = asString(play['id']);
    final key = keyOf?.call(id) ?? id;
    first.putIfAbsent(key, () => (id, counted(play)));
    if (fullyPlayed(play)) finished.add(key);
  }
  return {
    for (final MapEntry(:key, value: (id, liked)) in first.entries)
      if (!liked && !finished.contains(key)) ...{key, id},
  };
}

/// What a song is liked for: its singers and composers and its film.
List<String> features(Json song) => [
      for (final credit in asStrings(song['credits']).take(4))
        if (credit.trim().isNotEmpty) 'by:${credit.trim().toLowerCase()}',
      if (asString(song['movie']).trim().isNotEmpty) 'film:${asString(song['movie']).trim().toLowerCase()}',
    ];

/// What you like, from what you played lately: for each singer, composer and
/// film, the songs of theirs played to the end, less half for each one
/// skipped and one for each one taken out of the radio (a play that counts but
/// stopped short is worth a quarter), each worth less the older it is. [plays]
/// can be History.signals.
Map<String, double> taste(List<Json> plays, Json? Function(String id) track,
    {required DateTime now, int days = 90, double halfLife = 30}) {
  final likes = <String, double>{};
  final since = epochSeconds(now) - days * 86400;
  for (final play in plays) {
    final at = toInt(play['at']) ?? 0;
    final song = at >= since ? track(asString(play['id'])) : null;
    if (song == null) continue;
    final worth = pow(0.5, (epochSeconds(now) - at) / 86400 / halfLife).toDouble();
    final value = play['removed'] == true
        ? -worth
        : fullyPlayed(play)
        ? worth
        : counted(play)
        ? worth / 4
        : -worth / 2;
    for (final feature in features(song)) {
      likes[feature] = (likes[feature] ?? 0) + value;
    }
  }
  return likes;
}

/// The singers, composers and films you keep taking out of the radio: at
/// least [times] songs of theirs in [days], and liked less than skipped on the
/// whole ([likes] from taste). The radio leaves their songs out.
Set<String> shunned(List<Json> plays, Json? Function(String id) track, Map<String, double> likes,
    {required DateTime now, int days = 90, int times = 3}) => {
  for (final MapEntry(:key, value: n) in removals(plays, track, now: now, days: days).entries)
    if (n >= times && (likes[key] ?? 0) < 0) key,
};

/// For each singer, composer and film, how many songs of theirs were taken
/// out of the radio in [days].
Map<String, int> removals(List<Json> plays, Json? Function(String id) track, {required DateTime now, int days = 90}) {
  final since = epochSeconds(now) - days * 86400;
  final out = <String, int>{};
  for (final play in plays) {
    if (play['removed'] != true || (toInt(play['at']) ?? 0) < since) continue;
    final song = track(asString(play['id']));
    for (final feature in song == null ? const <String>[] : features(song)) {
      out[feature] = (out[feature] ?? 0) + 1;
    }
  }
  return out;
}

/// A singer, composer or film as the radio sees it: [score] from taste,
/// [removed] the times it was taken out of the radio.
typedef TasteRank = ({String feature, double score, int removed, bool shunned});

/// Your taste as the radio sees it, best liked first.
List<TasteRank> tasteRanking(List<Json> plays, Json? Function(String id) track, {required DateTime now}) {
  final likes = taste(plays, track, now: now);
  final taken = removals(plays, track, now: now);
  final shun = shunned(plays, track, likes, now: now);
  return [
    for (final f in {...likes.keys, ...taken.keys})
      (feature: f, score: ((likes[f] ?? 0) * 1000).round() / 1000, removed: taken[f] ?? 0, shunned: shun.contains(f)),
  ]..sort((a, b) => a.score != b.score ? b.score.compareTo(a.score) : a.feature.compareTo(b.feature));
}

/// How much [song] is like what you like, -2 to 2.
double fit(Json song, Map<String, double> likes) =>
    features(song).fold<double>(0, (sum, f) => sum + (likes[f] ?? 0)).clamp(-2.0, 2.0);

/// [songs] (best first, as a radio gives them) with the ones like what you
/// like moved up, by up to ten places, and the ones like what you skip down.
List<Json> tasteOrder(List<Json> songs, Map<String, double> likes) {
  final ranked = [for (var i = 0; i < songs.length; i++) (i - 5 * fit(songs[i], likes), i, songs[i])]
    ..sort((a, b) => a.$1 != b.$1 ? a.$1.compareTo(b.$1) : a.$2.compareTo(b.$2));
  return [for (final (_, _, song) in ranked) song];
}

/// Songs played (or skipped) since [since], by song and by id.
Set<String> heardSince(List<Json> plays, DateTime since, {String Function(String id)? keyOf}) => {
  for (final play in plays)
    if ((toInt(play['at']) ?? 0) >= epochSeconds(since)) ...{
      asString(play['id']),
      if (keyOf != null) keyOf(asString(play['id'])),
    },
};

/// The key a song is known by across uploads, falling back to its id when it
/// has no title.
String songIdentity(Json track) {
  final key = songKey(track);
  return key == '|' ? trackId(track) : key;
}
