// What was played and for how long (history.json beside library.json), which
// the daily, weekly and monthly playlists are made from and which keeps the
// radio from repeating itself. The desktop Paattu keeps the same file in
// ~/.local/share/paattu/history.json (paattu/history.py):
//
//     plays   [{id, at (seconds since 1970), heard (seconds), length}], oldest first
//     tracks  id -> the song, for the ids in plays and made
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

/// A play that counts: half the song, or 30 seconds of a long one.
bool counted(Json play) {
  final heard = toInt(play['heard']) ?? 0;
  final length = toInt(play['length']) ?? 0;
  return heard >= (length > 0 ? min(30, length ~/ 2) : 30);
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
    'tracks': <String, dynamic>{},
    'made': <String, dynamic>{},
  };

  List<Json> get plays => asList(data['plays']).map(asJson).toList();
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
        if (data['plays'] is! List) data['plays'] = <dynamic>[];
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
