// The music library: followed YouTube users, their public playlists, your
// own playlists, songs and mixes. A port of paattu/library.py, in the same
// JSON format, so a library exported from the desktop Paattu
// (~/.local/share/paattu/library.json) imports here unchanged and back.
//
//     users      channel id  -> {id, handle, name, url, language, playlists[...]}
//     playlists  playlist id -> {id, title, owner, language, saved, tracks[...] | null,
//                                removedTracks[...]}
//                or your own:     {id, title, local: true, saved: true, tracks[...]}
//     tracks     track id    -> {id, title, movie, credits, kind, duration, ...}
//     removed    playlist id -> {title, owner, removed}
//     mixes      [{id, title, sources: [{type: language|user|playlist, id}]}]
//     playedOff  [language]  (its played playlist was deleted: not made again)
//
// Songs listened to go to the front of their language's own "played"
// playlist, which is in that language's mix (notePlayed).

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'titles.dart';
import 'track.dart';
import 'util.dart';

const libraryVersion = 1;
const favouritesId = 'paattu-favourites';
const savedId = 'paattu-saved';
const _ownPrefix = 'paattu-';
const _mixPrefix = 'mix-';
const mixSourceTypes = ['language', 'user', 'playlist'];
const _firstMixes = ['Malayalam', 'Tamil'];
const playedPrefix = 'paattu-played-';
const playedKeep = 300;
const _favouriteNames = ['favourites', 'favorites', 'fav', 'favs', 'liked'];
const _savedNames = ['saved songs', 'saved', 'saved-songs'];

class LibraryException implements Exception {
  LibraryException(this.message);
  final String message;
  @override
  String toString() => message;
}

Json emptyLibrary() => {
      'version': libraryVersion,
      'updated': nowStamp(),
      'users': <String, dynamic>{},
      'playlists': <String, dynamic>{},
      'tracks': <String, dynamic>{},
      'removed': <String, dynamic>{},
      'mixes': firstMixes(),
    };

List<dynamic> firstMixes() => [
      for (final lang in _firstMixes)
        <String, dynamic>{
          'id': '$_mixPrefix${lang.toLowerCase()}',
          'title': '$lang mix',
          'sources': <dynamic>[
            <String, dynamic>{'type': 'language', 'id': lang},
          ],
          'created': nowStamp(),
        },
    ];

/// A library read from JSON, with anything missing filled in.
Json normaliseLibrary(Object? decoded) {
  if (decoded is! Map) throw LibraryException("that isn't a Paattu library");
  final data = decoded.cast<String, dynamic>();
  for (final key in ['users', 'playlists', 'tracks', 'removed']) {
    if (data[key] is! Map) data[key] = <String, dynamic>{};
  }
  // Libraries from before mixes get the two they used to have built in.
  if (data['mixes'] is! List) data['mixes'] = firstMixes();
  return data;
}

class Library extends ChangeNotifier {
  Library(this.file) : data = emptyLibrary();

  final File file;
  Json data;
  Timer? _saveTimer;
  bool _loaded = false;

  bool get loaded => _loaded;
  Json get users => data['users'] as Json;
  Json get playlists => data['playlists'] as Json;
  Json get tracks => data['tracks'] as Json;
  Json get removed => data['removed'] as Json;
  List<dynamic> get mixes => data['mixes'] as List<dynamic>;

  Future<void> load() async {
    try {
      if (await file.exists()) data = normaliseLibrary(jsonDecode(await file.readAsString()));
    } catch (error) {
      // A damaged file is kept aside rather than overwritten.
      debugPrint('library: $error');
      try {
        await file.copy('${file.path}.damaged');
      } catch (_) {}
      data = emptyLibrary();
    }
    _loaded = true;
    notifyListeners();
  }

  /// Something changed: tell the UI now, write the file shortly.
  void changed() {
    pruneMixes();
    data['updated'] = nowStamp();
    notifyListeners();
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 400), save);
  }

  Future<void> save() async {
    _saveTimer?.cancel();
    final text = jsonEncode(data);
    await file.parent.create(recursive: true);
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(text, flush: true);
    await tmp.rename(file.path);
  }

  String export() => const JsonEncoder.withIndent(' ').convert(data);

  /// Replace the library with an imported one (desktop Paattu or another device).
  void replaceWith(Object? decoded) {
    data = normaliseLibrary(decoded);
    changed();
  }

  // ---------------------------------------------------------------- lookups

  Json? track(String id) => tracks[id] is Map ? asJson(tracks[id]) : null;
  Json? playlist(String id) => playlists[id] is Map ? asJson(playlists[id]) : null;
  Json? user(String id) => users[id] is Map ? asJson(users[id]) : null;

  /// A followed user by channel id, @handle, name or URL fragment.
  Json? findUser(String query) {
    final q = query.trim().toLowerCase().replaceFirst(RegExp('^@+'), '');
    if (q.isEmpty) return null;
    for (final value in users.values) {
      final u = asJson(value);
      for (final c in [u['id'], u['handle'], u['name'], u['url']].map(asString)) {
        if (c.isEmpty) continue;
        final lc = c.toLowerCase();
        if (lc.replaceFirst(RegExp('^@+'), '') == q || lc.endsWith('/$q') || lc.endsWith('/@$q')) return u;
      }
    }
    return null;
  }

  List<Json> playlistTracks(String playlistId) {
    final p = playlist(playlistId);
    return [for (final id in asStrings(p?['tracks'])) ?track(id)];
  }

  bool fetched(String playlistId) => playlist(playlistId)?['tracks'] is List;

  /// Favourites first, then Saved songs, then your playlists, oldest first.
  List<Json> ownPlaylists() {
    final mine = playlists.values.map(asJson).where((p) => p['local'] == true).toList();
    int rank(Json p) => p['id'] == favouritesId ? 0 : (p['id'] == savedId ? 1 : 2);
    mine.sort((a, b) {
      final byRank = rank(a).compareTo(rank(b));
      if (byRank != 0) return byRank;
      final byCreated = asString(a['created']).compareTo(asString(b['created']));
      if (byCreated != 0) return byCreated;
      return asString(a['title']).toLowerCase().compareTo(asString(b['title']).toLowerCase());
    });
    return mine;
  }

  /// One of your playlists by id, name, "favourites" or "saved".
  Json? findOwnPlaylist(String ref) {
    var r = ref.trim();
    if (_favouriteNames.contains(r.toLowerCase())) {
      r = favouritesId;
    } else if (_savedNames.contains(r.toLowerCase())) {
      r = savedId;
    }
    final direct = playlist(r);
    if (direct != null && direct['local'] == true) return direct;
    for (final p in ownPlaylists()) {
      if (asString(p['title']).toLowerCase() == r.toLowerCase()) return p;
    }
    return null;
  }

  /// Saved playlists from YouTube (not your own ones), by language.
  Map<String, List<Json>> shelves() {
    final out = <String, List<Json>>{};
    for (final value in playlists.values) {
      final p = asJson(value);
      if (p['saved'] != true || p['local'] == true) continue;
      final lang = asString(p['language']).isEmpty ? 'Other' : asString(p['language']);
      out.putIfAbsent(lang, () => []).add(p);
    }
    for (final list in out.values) {
      list.sort((a, b) {
        int flag(Json p, String key) => p[key] == true ? 0 : 1;
        final byFeatured = flag(a, 'featured').compareTo(flag(b, 'featured'));
        if (byFeatured != 0) return byFeatured;
        final byAuto = flag(a, 'auto').compareTo(flag(b, 'auto'));
        if (byAuto != 0) return byAuto;
        int followers(Json p) => toInt(user(asString(p['owner']))?['followers']) ?? 0;
        final byFollowers = followers(b).compareTo(followers(a));
        if (byFollowers != 0) return byFollowers;
        return asString(a['title']).toLowerCase().compareTo(asString(b['title']).toLowerCase());
      });
    }
    return out;
  }

  /// Languages that have saved playlists, Malayalam and Tamil first.
  List<String> languages() {
    final names = shelves().keys.toList();
    int rank(String l) => l == 'Malayalam' ? 0 : (l == 'Tamil' ? 1 : (l == 'Other' ? 3 : 2));
    names.sort((a, b) => rank(a) != rank(b) ? rank(a).compareTo(rank(b)) : a.compareTo(b));
    return names;
  }

  List<Json> sortedUsers() {
    final list = users.values.map(asJson).toList();
    list.sort((a, b) {
      final byLang = asString(a['language']).compareTo(asString(b['language']));
      return byLang != 0 ? byLang : asString(a['name']).toLowerCase().compareTo(asString(b['name']).toLowerCase());
    });
    return list;
  }

  List<Json> userPlaylists(String userId) =>
      [for (final pid in asStrings(user(userId)?['playlists'])) ?playlist(pid)];

  /// Saved playlists in a language; ones without a language count as Other.
  List<Json> languagePlaylists(String language) => playlists.values
      .map(asJson)
      .where((p) =>
          p['saved'] == true &&
          p['local'] != true &&
          (asString(p['language']).isEmpty ? 'Other' : asString(p['language'])) == language)
      .toList();

  // ---------------------------------------------------------------- your songs

  bool isFavourite(String trackId) => asStrings(playlist(favouritesId)?['tracks']).contains(trackId);
  bool isSaved(String trackId) => asStrings(playlist(savedId)?['tracks']).contains(trackId);

  /// Playlists of yours a song is in.
  List<Json> playlistsWith(String trackId) =>
      ownPlaylists().where((p) => asStrings(p['tracks']).contains(trackId)).toList();

  /// Heart or unheart a song. Returns whether it's a favourite now.
  bool toggleFavourite(Json track) {
    final id = trackId(track);
    if (isFavourite(id)) {
      removeTracks(favouritesId, [id]);
      changed();
      return false;
    }
    addTracks(favourites()['id'] as String, [track]);
    changed();
    return true;
  }

  /// Put a song in Saved songs (the library's own list). Returns false if it was there.
  bool saveSong(Json track) {
    final added = addTracks(savedSongs()['id'] as String, [track]);
    changed();
    return added.isNotEmpty;
  }

  // ---------------------------------------------------------------- updates

  /// Add or refresh a followed user and the stubs of their public playlists.
  Json upsertUser(Json info, String language) {
    final id = asString(info['id']);
    final user = asJson(users[id] ?? <String, dynamic>{});
    final listed = asList(info['playlists']).map(asJson).where((p) => !removed.containsKey(p['id'])).toList();
    String pick(String key) => asString(info[key]).isNotEmpty ? asString(info[key]) : asString(user[key]);
    user.addAll({
      'id': id,
      'handle': pick('handle'),
      'name': pick('name'),
      'url': pick('url'),
      'followers': info['followers'] ?? user['followers'],
      'avatar': pick('avatar'),
      'language': language.isNotEmpty ? language : asString(user['language']),
      'curated': user['curated'] == true,
      'added': user['added'] ?? nowStamp(),
      'synced': nowStamp(),
      'playlists': [for (final p in listed) p['id']],
    });
    users[id] = user;
    for (final stub in listed) {
      upsertPlaylistStub(stub, owner: user);
    }
    return user;
  }

  /// Record a playlist we know about without touching its tracks.
  Json upsertPlaylistStub(Json stub, {Json? owner, String language = ''}) {
    final id = asString(stub['id']);
    final entry = asJson(playlists[id] ?? <String, dynamic>{});
    final ownerName = owner != null ? asString(owner['name']) : asString(stub['ownerName']);
    final rawTitle = asString(stub['title']).isNotEmpty ? asString(stub['title']) : asString(entry['rawTitle']);
    entry.addAll({
      'id': id,
      'rawTitle': rawTitle,
      'title': playlistTitle(rawTitle, ownerName),
      'owner': owner != null
          ? owner['id']
          : (asString(entry['owner']).isNotEmpty ? entry['owner'] : asString(stub['ownerId'])),
      'ownerName': ownerName.isNotEmpty ? ownerName : asString(entry['ownerName']),
      'thumbnail': shortThumbnail(
          asString(stub['thumbnail']).isNotEmpty ? asString(stub['thumbnail']) : asString(entry['thumbnail'])),
    });
    entry.remove('url');
    final setLanguage = entry['languageSet'] == true ? asString(entry['language']) : '';
    entry['language'] = setLanguage.isNotEmpty
        ? setLanguage
        : guessLanguage([asString(stub['title'])],
            fallback: language.isNotEmpty
                ? language
                : (asString(owner?['language']).isNotEmpty
                    ? asString(owner?['language'])
                    : asString(entry['language'])));
    if (stub['auto'] == true || entry['auto'] == true) {
      entry['auto'] = true;
      final kind = rawTitle.toLowerCase().startsWith('popular') ? 'Most played' : 'New releases';
      entry['title'] = ownerName.isNotEmpty ? '$ownerName — $kind' : kind;
    }
    entry.putIfAbsent('saved', () => false);
    entry.putIfAbsent('tracks', () => null);
    playlists[id] = entry;
    return entry;
  }

  /// Store a fetched playlist: its metadata and cleaned tracks.
  Json setPlaylistTracks(Json details) {
    final id = asString(details['id']);
    var entry = playlist(id) ?? <String, dynamic>{'id': id, 'saved': false};
    if (asString(entry['rawTitle']).isEmpty) {
      playlists[id] = entry;
      entry = upsertPlaylistStub({
        'id': id,
        'title': details['title'] ?? '',
        'ownerName': details['channel'] ?? '',
        'ownerId': details['channelId'] ?? '',
        'thumbnail': details['thumbnail'] ?? '',
      }, owner: user(asString(details['channelId'])));
    }
    final ids = <String>[];
    final gone = asStrings(entry['removedTracks']).toSet();
    for (final raw in asList(details['tracks']).map(asJson)) {
      final tid = asString(raw['id']);
      if (tid.isEmpty || gone.contains(tid) || ids.contains(tid)) continue;
      final channel = asString(raw['channel']).isNotEmpty ? asString(raw['channel']) : asString(details['channel']);
      final meta = cleanTitle(asString(raw['title']), channel);
      final t = asJson(tracks[tid] ?? <String, dynamic>{});
      t.addAll({
        'id': tid,
        'rawTitle': raw['title'],
        'title': meta.title,
        'movie': meta.movie,
        'credits': meta.credits.take(6).toList(),
        'kind': meta.kind,
        'channel': channel,
        'duration': raw['duration'],
        'views': raw['views'],
      });
      tracks[tid] = t;
      ids.add(tid);
    }
    entry['tracks'] = ids;
    entry['count'] = ids.length;
    entry['fetched'] = nowStamp();
    if (asString(entry['thumbnail']).isEmpty && ids.isNotEmpty) {
      entry['thumbnail'] = 'https://i.ytimg.com/vi/${ids.first}/hqdefault.jpg';
    }
    playlists[id] = entry;
    return entry;
  }

  /// Save or unsave a YouTube playlist (saved ones are on the shelves and in mixes).
  void setSaved(String playlistId, bool saved) {
    final p = playlist(playlistId);
    if (p == null) return;
    p['saved'] = saved;
    playlists[playlistId] = p;
  }

  void setPlaylistLanguage(String playlistId, String language) {
    final p = playlist(playlistId);
    if (p == null) return;
    p['language'] = language;
    p['languageSet'] = true;
    playlists[playlistId] = p;
  }

  /// Unfollow a user; their saved playlists stay unless [keepSaved] is false.
  Json? removeUser(String userId, {bool keepSaved = true}) {
    final u = users.remove(userId);
    if (u == null) return null;
    for (final pid in asStrings(asJson(u)['playlists'])) {
      final p = playlist(pid);
      if (p != null && (!keepSaved || p['saved'] != true)) playlists.remove(pid);
    }
    removed.removeWhere((pid, entry) => asJson(entry)['owner'] == userId);
    pruneTracks();
    return asJson(u);
  }

  /// A new playlist of your own (or Favourites / Saved songs, which have fixed ids).
  Json createPlaylist(String name) {
    final title = squash(name);
    if (title.isEmpty) throw LibraryException('Give the playlist a name');
    if (['favourites', 'favorites'].contains(title.toLowerCase())) return favourites();
    if (title.toLowerCase() == 'saved songs') return savedSongs();
    if (findOwnPlaylist(title) != null) throw LibraryException('You already have a playlist called $title');
    var pid = '$_ownPrefix${tokenHex(4)}';
    while (playlists.containsKey(pid)) {
      pid = '$_ownPrefix${tokenHex(4)}';
    }
    playlists[pid] = _own(pid, title);
    return asJson(playlists[pid]);
  }

  Json favourites() {
    playlists.putIfAbsent(favouritesId, () => _own(favouritesId, 'Favourites'));
    return asJson(playlists[favouritesId]);
  }

  /// Songs you added to the library (from a search, a link or a playlist).
  Json savedSongs() {
    playlists.putIfAbsent(savedId, () => _own(savedId, 'Saved songs'));
    return asJson(playlists[savedId]);
  }

  static bool builtin(String playlistId) => playlistId == favouritesId || playlistId == savedId;

  Json _own(String pid, String title) => {
        'id': pid,
        'title': title,
        'local': true,
        'saved': true,
        'owner': '',
        'ownerName': 'You',
        'language': '',
        'tracks': <dynamic>[],
        'count': 0,
        'created': nowStamp(),
      };

  Json renamePlaylist(String playlistId, String name) {
    final p = playlist(playlistId);
    final title = squash(name);
    if (p == null || p['local'] != true) throw LibraryException('Only your own playlists can be renamed');
    if (builtin(playlistId)) throw LibraryException('${p['title']} keeps its name');
    if (title.isEmpty) throw LibraryException('Give the playlist a name');
    final other = findOwnPlaylist(title);
    if (other != null && other['id'] != playlistId) {
      throw LibraryException('You already have a playlist called $title');
    }
    p['title'] = title;
    return p;
  }

  /// Add songs to one of your playlists; songs the library doesn't know yet
  /// are stored. Returns the ids added.
  List<String> addTracks(String playlistId, List<Json> songs) {
    final p = playlist(playlistId);
    if (p == null || p['local'] != true) throw LibraryException('Songs can only be added to your own playlists');
    final have = asStrings(p['tracks']);
    final added = <String>[];
    for (final song in songs) {
      final tid = trackId(song);
      if (tid.isEmpty) continue;
      if (!tracks.containsKey(tid)) tracks[tid] = storedTrack(song);
      if (!have.contains(tid) && !added.contains(tid)) added.add(tid);
    }
    p['tracks'] = [...have, ...added];
    p['count'] = (p['tracks'] as List).length;
    return added;
  }

  /// Take a playlist out of the app; syncing its owner won't bring it back.
  /// Your own playlists are simply deleted.
  Json? removePlaylist(String playlistId) {
    final value = playlists.remove(playlistId);
    if (value == null) return null;
    final p = asJson(value);
    if (p['local'] == true) {
      final language = asString(p['language']);
      if (playlistId.startsWith(playedPrefix) && language.isNotEmpty) {
        data['playedOff'] = ({...asStrings(data['playedOff']), language}.toList()..sort());
      }
      pruneTracks();
      return p;
    }
    final owner = user(asString(p['owner']));
    if (owner != null) {
      owner['playlists'] = asStrings(owner['playlists']).where((id) => id != playlistId).toList();
    }
    removed[playlistId] = <String, dynamic>{'title': p['title'] ?? '', 'owner': p['owner'] ?? '', 'removed': nowStamp()};
    pruneTracks();
    return p;
  }

  /// Forget that playlists were removed (by id, or all of an owner's).
  List<String> unremovePlaylists({List<String>? ids, String? owner}) {
    final picked = removed.entries
        .where((e) => (ids != null && ids.contains(e.key)) || (owner != null && asJson(e.value)['owner'] == owner))
        .map((e) => e.key)
        .toList();
    for (final pid in picked) {
      removed.remove(pid);
    }
    return picked;
  }

  /// Take songs out of a playlist; refreshing it from YouTube won't bring them back.
  List<String> removeTracks(String playlistId, List<String> trackIds) {
    final p = playlist(playlistId);
    if (p == null || p['tracks'] is! List) return [];
    final have = asStrings(p['tracks']);
    final drop = trackIds.toSet().where(have.contains).toList();
    p['tracks'] = have.where((id) => !drop.contains(id)).toList();
    p['count'] = (p['tracks'] as List).length;
    if (p['local'] != true) {
      p['removedTracks'] = {...asStrings(p['removedTracks']), ...drop}.toList();
    }
    pruneTracks();
    return drop;
  }

  /// Move a song within one of your playlists.
  void moveTrack(String playlistId, int from, int to) {
    final p = playlist(playlistId);
    if (p == null || p['local'] != true) return;
    final list = asStrings(p['tracks']);
    if (from < 0 || from >= list.length) return;
    final id = list.removeAt(from);
    list.insert(to.clamp(0, list.length), id);
    p['tracks'] = list;
  }

  // ---------------------------------------------------------------- mixes

  List<Json> mixList() => mixes.map(asJson).toList();

  /// A mix by id or name ("tamil" finds "Tamil mix").
  Json? findMix(String ref) {
    final r = squash(ref).toLowerCase();
    if (r.isEmpty) return null;
    for (final m in mixList()) {
      final title = asString(m['title']).toLowerCase();
      if (r == m['id'] || r == title || r == title.replaceFirst(RegExp(r'\s+mix$'), '')) return m;
    }
    return null;
  }

  Json getMix(String ref) {
    final mix = findMix(ref);
    if (mix == null) throw LibraryException("There's no mix called $ref");
    return mix;
  }

  String sourceTitle(Json source) {
    final id = asString(source['id']);
    switch (source['type']) {
      case 'language':
        return id;
      case 'user':
        return asString(user(id)?['name']);
      default:
        return asString(playlist(id)?['title']);
    }
  }

  /// The playlists a mix shuffles, in the order of its sources.
  List<Json> mixPlaylists(Json mix) {
    final out = <String, Json>{};
    for (final source in asList(mix['sources']).map(asJson)) {
      final id = asString(source['id']);
      List<Json> found;
      if (source['type'] == 'language') {
        found = languagePlaylists(id);
      } else if (source['type'] == 'user') {
        found = [
          for (final pid in asStrings(user(id)?['playlists']))
            if (playlist(pid)?['saved'] == true) playlist(pid)!,
        ];
      } else {
        found = [?playlist(id)];
      }
      for (final p in found) {
        out.putIfAbsent(asString(p['id']), () => p);
      }
    }
    return out.values.toList();
  }

  /// How many songs a mix has, and how many of its playlists aren't loaded yet.
  ({int playlists, int songs, int waiting}) mixCounts(Json mix) {
    final list = mixPlaylists(mix);
    final songs = <String>{for (final p in list) ...asStrings(p['tracks'])};
    return (playlists: list.length, songs: songs.length, waiting: list.where((p) => p['tracks'] is! List).length);
  }

  Json createMix(String name, [List<Json> sources = const []]) {
    final title = squash(name);
    if (title.isEmpty) throw LibraryException('Give the mix a name');
    if (findMix(title) != null) throw LibraryException("There's already a mix called $title");
    var mid = '$_mixPrefix${tokenHex(4)}';
    while (findMix(mid) != null) {
      mid = '$_mixPrefix${tokenHex(4)}';
    }
    final mix = <String, dynamic>{'id': mid, 'title': title, 'sources': <dynamic>[], 'created': nowStamp()};
    mixes.add(mix);
    setMixSources(mid, sources);
    return mix;
  }

  Json renameMix(String ref, String name) {
    final mix = getMix(ref);
    final title = squash(name);
    if (title.isEmpty) throw LibraryException('Give the mix a name');
    final other = findMix(title);
    if (other != null && other['id'] != mix['id']) throw LibraryException("There's already a mix called $title");
    mix['title'] = title;
    return mix;
  }

  void removeMix(String ref) {
    final mix = getMix(ref);
    mixes.removeWhere((m) => asJson(m)['id'] == mix['id']);
  }

  /// Put a mix at [position] (0 = first button).
  void moveMix(String ref, int position) {
    final mix = getMix(ref);
    mixes.removeWhere((m) => asJson(m)['id'] == mix['id']);
    mixes.insert(position.clamp(0, mixes.length), mix);
  }

  /// Replace a mix's sources ([{type, id}]).
  void setMixSources(String ref, List<Json> sources) {
    final mix = getMix(ref);
    final seen = <String>{};
    final keep = <Json>[];
    for (final s in sources) {
      final type = asString(s['type']);
      final id = asString(s['id']);
      if (!mixSourceTypes.contains(type) || id.isEmpty) {
        throw LibraryException('A mix takes languages, followed users and playlists');
      }
      if (type == 'user' && !users.containsKey(id)) throw LibraryException('Not following $id');
      if (type == 'playlist' && !playlists.containsKey(id)) throw LibraryException('Unknown playlist $id');
      if (seen.add('$type:$id')) keep.add(<String, dynamic>{'type': type, 'id': id});
    }
    mix['sources'] = keep;
  }

  // ---------------------------------------------------------------- played

  /// The mix language (Malayalam or Tamil) of a song, or '': its own, else
  /// the one most of the library's playlists holding it are in, else guessed
  /// from its names.
  String playedLanguage(Json track) {
    final own = asString(track['language']);
    final titled = own.isEmpty ? '' : own[0].toUpperCase() + own.substring(1).toLowerCase();
    if (_firstMixes.contains(titled)) return titled;
    final id = trackId(track);
    final votes = <String, int>{};
    for (final p in playlists.values.map(asJson)) {
      final language = asString(p['language']);
      if (_firstMixes.contains(language) && p['local'] != true && asStrings(p['tracks']).contains(id)) {
        votes[language] = (votes[language] ?? 0) + 1;
      }
    }
    if (votes.isNotEmpty) {
      // The first of the most (as Python's max).
      return _firstMixes.reduce((a, b) => (votes[b] ?? 0) > (votes[a] ?? 0) ? b : a);
    }
    return guessLanguage([
      asString(track['title']),
      asString(track['movie']),
      asString(track['channel']),
      ...asStrings(track['credits']),
    ]);
  }

  /// A song listened to goes to the front of its language's played playlist
  /// (made the first time, and put in that language's mix). Returns the
  /// language, or '' when it has none or its played playlist was deleted.
  String notePlayed(Json track) {
    final tid = trackId(track);
    final language = tid.isEmpty ? '' : playedLanguage(track);
    if (language.isEmpty || asStrings(data['playedOff']).contains(language)) return '';
    final pid = '$playedPrefix${language.toLowerCase()}';
    var p = playlist(pid);
    if (p == null) {
      p = playlists[pid] = {..._own(pid, 'Played in $language'), 'language': language};
      final mix = findMix('$_mixPrefix${language.toLowerCase()}') ?? findMix(language);
      if (mix != null) {
        setMixSources(asString(mix['id']), [
          ...asList(mix['sources']).map(asJson),
          {'type': 'playlist', 'id': pid},
        ]);
      }
    }
    if (!tracks.containsKey(tid)) tracks[tid] = storedTrack(track);
    p['tracks'] = [tid, ...asStrings(p['tracks']).where((t) => t != tid)].take(playedKeep).toList();
    p['count'] = (p['tracks'] as List).length;
    pruneTracks();
    return language;
  }

  /// Forget mix sources whose user or playlist has left the library.
  void pruneMixes() {
    for (final m in mixList()) {
      m['sources'] = asList(m['sources']).map(asJson).where((s) {
        final id = asString(s['id']);
        return s['type'] == 'language' ||
            (s['type'] == 'user' && users.containsKey(id)) ||
            (s['type'] == 'playlist' && playlists.containsKey(id));
      }).toList();
    }
  }

  /// Drop tracks no playlist refers to any more.
  void pruneTracks() {
    final used = <String>{for (final p in playlists.values) ...asStrings(asJson(p)['tracks'])};
    tracks.removeWhere((id, _) => !used.contains(id));
  }
}

/// i.ytimg.com thumbnails work without their signed query string.
String shortThumbnail(String url) {
  final found = RegExp(r'^https://i\d?\.ytimg\.com/vi/([A-Za-z0-9_-]{11})/').firstMatch(url);
  return found != null ? 'https://i.ytimg.com/vi/${found.group(1)}/hqdefault.jpg' : url;
}
