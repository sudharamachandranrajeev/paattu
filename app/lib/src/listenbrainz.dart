// Scrobbling to ListenBrainz, which also carries plays between devices. The
// desktop Paattu does the same (paattu/listenbrainz.py, `paattu listenbrainz`).
//
// Each song heard properly (half of it, or four minutes: ListenBrainz's own
// rule) is sent as a listen with the song itself in additional_info, so
// another Paattu can play it. Each device reads the others' listens back into
// its own history, so the made-for-you playlists and the Played in ...
// playlists follow every device. Listens from other players have no song in
// them and are left alone. Listening history on ListenBrainz is public.
//
// history.json keeps where it got to under "listenbrainz": device (this
// install's random id, so its own listens aren't read back), sent (the newest
// of its own plays sent) and fetched (the newest listen read). Plays read back
// carry "from": "listenbrainz" and are never sent again.

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/widgets.dart';

import 'app_state.dart';
import 'history.dart';
import 'library.dart';
import 'log.dart';
import 'settings.dart';
import 'sources/http.dart';
import 'track.dart';
import 'util.dart';

const listenBrainzApi = 'https://api.listenbrainz.org';
const listenBrainzTokenPage = 'https://listenbrainz.org/settings/';
const _services = {'youtube': 'youtube.com', 'jiosaavn': 'jiosaavn.com', 'soundcloud': 'soundcloud.com'};

/// What of a song goes with its listen: enough to play it and show it.
const _songKeys = [
  'id', 'title', 'rawTitle', 'movie', 'credits', 'channel', 'kind', 'duration', 'url', 'site', 'art', //
  'language', 'album', 'year',
];
const playedFrom = 'listenbrainz';

/// Listens read again from this far back, for a device that sends its plays late.
const listenOverlap = 2 * 86400;
const _page = 100;
const _pages = 50;

/// A play ListenBrainz counts: half the song, or four minutes of a long one.
bool scrobbles(Json play) {
  final heard = toInt(play['heard']) ?? 0;
  final length = toInt(play['length']) ?? 0;
  return heard >= (length > 0 ? min(240, length ~/ 2) : 240);
}

/// The sync state in history [data], made (with a new device id) if missing.
Json listenState(Json data) {
  if (data['listenbrainz'] is! Map) data['listenbrainz'] = <String, dynamic>{};
  final state = asJson(data['listenbrainz']);
  if (asString(state['device']).isEmpty) state['device'] = tokenHex(6);
  state['sent'] ??= 0;
  state['fetched'] ??= 0;
  return state;
}

bool _blank(Object? value) => value == null || value == '' || (value is List && value.isEmpty);

/// The listen ListenBrainz is sent for [play] of [song].
Json listenOf(Json play, Json song, String device, {String version = sourceVersion}) {
  final credits = asStrings(song['credits']).where((c) => c.isNotEmpty).toList();
  final length = toInt(play['length']) ?? toInt(song['duration']) ?? 0;
  final service = _services[trackSite(song)];
  final title = asString(song['title']);
  final rawTitle = asString(song['rawTitle']);
  final channel = asString(song['channel']);
  final movie = asString(song['movie']);
  return {
    'listened_at': toInt(play['at']),
    'track_metadata': {
      'artist_name': credits.isNotEmpty ? credits.join(', ') : (channel.isNotEmpty ? channel : 'Unknown artist'),
      'track_name': title.isNotEmpty ? title : (rawTitle.isNotEmpty ? rawTitle : trackId(song)),
      if (movie.isNotEmpty) 'release_name': movie,
      'additional_info': {
        'media_player': 'Paattu',
        'submission_client': 'Paattu',
        'submission_client_version': version,
        'origin_url': trackPage(song),
        'paattu_device': device,
        'paattu_heard': toInt(play['heard']) ?? 0,
        'paattu_song': {
          for (final key in _songKeys)
            if (!_blank(song[key])) key: song[key],
        },
        'music_service': ?service,
        if (length > 0) 'duration': length,
        if (credits.isNotEmpty) 'artist_names': credits,
      },
    },
  };
}

/// This device's plays still to send, oldest first.
List<(Json, Json)> pendingListens(Json data) {
  final sent = toInt(listenState(data)['sent']) ?? 0;
  final tracks = asJson(data['tracks']);
  return [
    for (final play in asList(data['plays']).whereType<Map>().map(asJson))
      if (play['from'] == null && (toInt(play['at']) ?? 0) > sent && tracks[play['id']] is Map && scrobbles(play))
        (play, asJson(tracks[play['id']])),
  ];
}

/// (play, song) for a listen another Paattu sent, or null.
(Json, Json)? playOfListen(Json found, String device) {
  final info = asJson(asJson(found['track_metadata'])['additional_info']);
  final song = info['paattu_song'];
  final at = found['listened_at'];
  if (song is! Map || asString(song['id']).isEmpty || at is! int || info['paattu_device'] == device) return null;
  final length = toInt(info['duration']) ?? 0;
  return (
    <String, dynamic>{
      'id': song['id'],
      'at': at,
      'heard': toInt(info['paattu_heard']) ?? 0,
      if (length > 0) 'length': length,
      'from': playedFrom,
    },
    asJson(song),
  );
}

/// Add the plays read (playOfListen's) to history [data], in time order,
/// each once. Returns the ones added, oldest first.
List<(Json, Json)> mergeListens(Json data, List<(Json, Json)> found) {
  final plays = asList(data['plays']);
  final tracks = asJson(data['tracks']);
  final have = {for (final p in plays.whereType<Map>()) '${p['id']}@${p['at']}'};
  final added = <(Json, Json)>[];
  for (final (play, song) in [...found]..sort((a, b) => (a.$1['at'] as int).compareTo(b.$1['at'] as int))) {
    if (!have.add('${play['id']}@${play['at']}')) continue;
    var at = plays.length;
    while (at > 0 && plays[at - 1] is Map && (toInt((plays[at - 1] as Map)['at']) ?? 0) > (play['at'] as int)) {
      at--;
    }
    plays.insert(at, play);
    tracks[asString(play['id'])] = storedTrack(song);
    added.add((play, song));
  }
  if (plays.length > historyLimit) plays.removeRange(0, plays.length - historyLimit);
  return added;
}

class ListenBrainzException implements Exception {
  ListenBrainzException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Keeps this device's plays and ListenBrainz in step: sends each play heard
/// properly, and reads the other devices' back now and then (at start, when
/// the app comes back, after a play).
class ListenBrainz extends ChangeNotifier {
  ListenBrainz(this.history, this.library, this.settings) {
    _lifecycle = AppLifecycleListener(
      onResume: () {
        if (DateTime.now().difference(_lastSync) > const Duration(minutes: 10)) fire(sync());
      },
    );
  }

  final History history;
  final Library library;
  final Settings settings;
  late final AppLifecycleListener _lifecycle;
  Future<int>? _syncing;
  DateTime _lastSync = DateTime.fromMillisecondsSinceEpoch(0);

  /// What went wrong the last time, if it did.
  String? problem;

  bool get connected => settings.listenBrainzToken.isNotEmpty;
  bool get syncing => _syncing != null;
  int get lastSynced => toInt(asJson(history.data['listenbrainz'])['synced']) ?? 0;

  Future<Object?> _call(String path, String token, {Object? body, Map<String, String>? query}) async {
    final uri = Uri.parse('$listenBrainzApi$path').replace(queryParameters: query);
    final headers = {'Authorization': 'Token $token', 'User-Agent': 'Paattu/$appVersion'};
    try {
      final response =
          await (body == null
                  ? httpClient.get(uri, headers: headers)
                  : httpClient.post(
                      uri,
                      headers: {...headers, 'Content-Type': 'application/json'},
                      body: jsonEncode(body),
                    ))
              .timeout(const Duration(seconds: 20));
      final text = utf8.decode(response.bodyBytes, allowMalformed: true);
      if (response.statusCode == 401) throw ListenBrainzException("ListenBrainz didn't accept the token");
      if (response.statusCode == 429) throw ListenBrainzException('ListenBrainz asked to wait a while');
      if (response.statusCode >= 400) {
        Object? said;
        try {
          said = asJson(jsonDecode(text))['error'];
        } catch (_) {}
        throw ListenBrainzException('ListenBrainz said ${response.statusCode} ${said ?? ''}'.trim());
      }
      return jsonDecode(text);
    } on ListenBrainzException {
      rethrow;
    } catch (error) {
      throw ListenBrainzException("couldn't reach ListenBrainz (${errorText(error)})");
    }
  }

  /// Check [token], keep it, and sync. Returns the user it belongs to.
  Future<String> connect(String token) async {
    final found = asJson(await _call('/1/validate-token', token.trim()));
    final user = asString(found['user_name']);
    if (found['valid'] != true || user.isEmpty) throw ListenBrainzException("ListenBrainz didn't accept the token");
    settings.listenBrainz = (token: token.trim(), user: user);
    notifyListeners();
    await sync();
    return user;
  }

  void disconnect() {
    settings.listenBrainz = null;
    problem = null;
    notifyListeners();
  }

  /// Send this device's plays, read the others'. Returns how many came in;
  /// one sync at a time. What goes wrong is kept in [problem], and the next
  /// sync tries again.
  Future<int> sync() {
    if (!connected) return Future.value(0);
    return _syncing ??= _sync().whenComplete(() {
      _syncing = null;
      notifyListeners();
    });
  }

  Future<int> _sync() async {
    final token = settings.listenBrainzToken;
    final user = settings.listenBrainzUser;
    _lastSync = DateTime.now();
    notifyListeners();
    try {
      final state = listenState(history.data);
      final device = asString(state['device']);
      final waiting = pendingListens(history.data);
      for (var start = 0; start < waiting.length; start += _page) {
        final chunk = waiting.skip(start).take(_page).toList();
        await _call(
          '/1/submit-listens',
          token,
          body: {
            'listen_type': chunk.length == 1 ? 'single' : 'import',
            'payload': [for (final (play, song) in chunk) listenOf(play, song, device, version: appVersion)],
          },
        );
        listenState(history.data)['sent'] = toInt(chunk.last.$1['at']);
        history.edited();
      }
      final fetched = toInt(state['fetched']) ?? 0;
      var since = max(0, fetched - listenOverlap);
      final found = <Json>[];
      for (var i = 0; i < _pages; i++) {
        final page = asList(
          asJson(
            asJson(
              await _call(
                '/1/user/${Uri.encodeComponent(user)}/listens',
                token,
                query: {'min_ts': '$since', 'count': '$_page'},
              ),
            )['payload'],
          )['listens'],
        ).map(asJson).toList();
        found.addAll(page);
        if (page.length < _page) break;
        since = page.map((f) => toInt(f['listened_at']) ?? 0).reduce(max);
      }
      final added = mergeListens(history.data, [for (final f in found) ?playOfListen(f, device)]);
      final ours = listenState(history.data);
      ours['fetched'] = max(toInt(ours['fetched']) ?? 0, found.map((f) => toInt(f['listened_at']) ?? 0).fold(0, max));
      ours['synced'] = epochSeconds(DateTime.now());
      history.edited();
      // The songs other devices played join the mixes like the ones played here.
      var joined = false;
      for (final (play, song) in added) {
        if (counted(play) && library.notePlayed(song).isNotEmpty) joined = true;
      }
      if (joined) library.changed();
      problem = null;
      if (added.isNotEmpty) problemLog.info('listenbrainz: ${added.length} plays from other devices');
      return added.length;
    } catch (error) {
      problem = errorText(error);
      problemLog.warn('listenbrainz: $problem');
      return 0;
    }
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }
}
