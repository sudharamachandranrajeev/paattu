// What every page shares: the library, the settings and the player, plus the
// actions that touch more than one of them (fetching playlists, mixes).

import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import 'library.dart';
import 'log.dart';
import 'links.dart';
import 'player/paattu_audio_handler.dart';
import 'settings.dart';
import 'sources/youtube.dart';
import 'track.dart';
import 'util.dart';

const appVersion = '0.5.1';
const repoUrl = 'https://github.com/sudharamachandranrajeev/paattu';

class AppState {
  AppState(this.library, this.settings, this.player);

  final Library library;
  final Settings settings;
  final PaattuAudioHandler player;
  final messenger = GlobalKey<ScaffoldMessengerState>();
  final navigator = GlobalKey<NavigatorState>();

  /// Playlists being fetched right now.
  final fetching = ValueNotifier<Set<String>>({});

  void toast(String text) {
    final state = messenger.currentState;
    if (state == null) return;
    state
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text), duration: const Duration(seconds: 3)));
  }

  void _setFetching(String id, bool on) {
    final next = Set.of(fetching.value);
    if (on) {
      next.add(id);
    } else {
      next.remove(id);
    }
    fetching.value = next;
  }

  /// Load (or refresh) a YouTube playlist's songs.
  Future<void> fetchPlaylist(String id) async {
    if (fetching.value.contains(id)) return;
    _setFetching(id, true);
    try {
      library.setPlaylistTracks(await playlistDetails(id));
      library.changed();
    } finally {
      _setFetching(id, false);
    }
  }

  /// Follow a YouTube profile: it and the stubs of its public playlists.
  Future<Json> followProfile(String query, {String language = ''}) async {
    final info = await channelPlaylists(query);
    final user = library.upsertUser(info, language);
    library.changed();
    return user;
  }

  /// Add (and save) a YouTube playlist by link.
  Future<Json> addYouTubePlaylist(String query, {String language = ''}) async {
    final id = playlistId(query);
    if (id == null) throw SourceException("that isn't a YouTube playlist link");
    final details = await playlistDetails(id);
    final entry = library.setPlaylistTracks(details);
    library.setSaved(id, true);
    if (language.isNotEmpty) library.setPlaylistLanguage(id, language);
    library.changed();
    return entry;
  }

  /// What a pasted link is: ('playlist', id) or ('user', query).
  (String, String) classify(String query) {
    final q = query.trim();
    if (q.isEmpty) throw SourceException('paste a YouTube profile or playlist link');
    final list = playlistId(q);
    if (list != null) return ('playlist', list);
    if (looksLikeSingleVideo(q)) {
      throw SourceException("that's a single video. Paste a profile (@handle) or a playlist link");
    }
    if (channelRef(q) == null) throw SourceException("that doesn't look like a YouTube profile or playlist");
    return ('user', q);
  }

  Future<void> playPlaylist(String id, {bool shuffled = false, int start = 0}) async {
    if (!library.fetched(id)) {
      toast('Loading the playlist…');
      await fetchPlaylist(id);
    }
    // Trailers and teasers are left out, unless that's what was tapped.
    final all = library.playlistTracks(id);
    final picked = shuffled ? -1 : start;
    final tracks = <Json>[];
    var at = 0;
    for (var i = 0; i < all.length; i++) {
      if (i == picked) at = tracks.length;
      if (asString(all[i]['kind']) != 'trailer' || i == picked) tracks.add(all[i]);
    }
    if (tracks.isEmpty) {
      toast('No songs in that playlist');
      return;
    }
    await player.playTracks(tracks, start: at, shuffled: shuffled);
  }

  /// Shuffle a mix: load its playlists that aren't loaded yet, then queue
  /// one upload of each song.
  Future<void> playMix(Json mix) async {
    final playlists = library.mixPlaylists(mix);
    if (playlists.isEmpty) {
      toast('${mix['title']} has nothing to play yet. Edit it to pick playlists');
      return;
    }
    final waiting = playlists.where((p) => p['tracks'] is! List).map((p) => asString(p['id'])).toList();
    if (waiting.isNotEmpty) {
      toast('Loading ${plural(waiting.length, 'playlist')} for ${mix['title']}…');
      final failed = <String>[];
      // A few at a time, so a big mix doesn't hammer YouTube.
      for (var i = 0; i < waiting.length; i += 4) {
        await Future.wait([
          for (final id in waiting.skip(i).take(4))
            fetchPlaylist(id).catchError((Object _) {
              failed.add(id);
            }),
        ]);
      }
      if (failed.length == waiting.length && playlists.every((p) => library.playlist(asString(p['id']))?['tracks'] is! List)) {
        toast("Couldn't load ${mix['title']}'s playlists. Check the internet connection");
        return;
      }
    }
    final songs = PaattuAudioHandler.uniqueSongs([
      for (final p in library.mixPlaylists(mix)) ...library.playlistTracks(asString(p['id'])),
    ]);
    if (songs.isEmpty) {
      toast('No songs in ${mix['title']} yet');
      return;
    }
    songs.shuffle(Random());
    await player.playTracks(songs);
    toast('${mix['title']}: ${plural(songs.length, 'song')}');
  }

  /// Heart or unheart a song (and say so).
  void toggleFavourite(Json track) {
    final on = library.toggleFavourite(track);
    toast(on ? 'Added ${trackTitle(track)} to Favourites' : 'Removed ${trackTitle(track)} from Favourites');
  }

  void saveSong(Json track) {
    final added = library.saveSong(track);
    toast(added ? 'Saved ${trackTitle(track)}' : '${trackTitle(track)} is already saved');
  }

  void addToPlaylist(String playlistId, List<Json> tracks) {
    try {
      final added = library.addTracks(playlistId, tracks);
      library.changed();
      final title = library.playlist(playlistId)?['title'];
      toast(added.isEmpty
          ? 'Already in $title'
          : added.length == 1
              ? 'Added ${trackTitle(tracks.first)} to $title'
              : 'Added ${plural(added.length, 'song')} to $title');
    } on LibraryException catch (error) {
      toast(error.message);
    }
  }

  /// A song as the library knows it (search results carry extra fields).
  Json known(Json track) => library.track(trackId(track)) ?? track;
}

class Paattu extends InheritedWidget {
  const Paattu({super.key, required this.state, required super.child});

  final AppState state;

  static AppState of(BuildContext context) => context.getInheritedWidgetOfExactType<Paattu>()!.state;

  @override
  bool updateShouldNotify(Paattu oldWidget) => oldWidget.state != state;
}

/// Run [action], showing its error as a snackbar; returns null on failure.
Future<T?> attempt<T>(AppState app, Future<T> Function() action, {String? failure}) async {
  try {
    return await action();
  } catch (error, stack) {
    final reason = error is LibraryException ? error.message : errorText(error);
    final expected = error is LibraryException || error is SourceException;
    problemLog.error(failure ?? 'failed', error, expected ? null : stack);
    app.toast(failure == null ? _capitalise(reason) : '$failure: $reason');
    return null;
  }
}

String _capitalise(String text) => text.isEmpty ? text : text[0].toUpperCase() + text.substring(1);

/// Rebuild when the library or settings change.
class LibraryBuilder extends StatelessWidget {
  const LibraryBuilder({super.key, required this.builder});
  final Widget Function(BuildContext context, AppState app) builder;

  @override
  Widget build(BuildContext context) {
    final app = Paattu.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([app.library, app.settings]),
      builder: (context, _) => builder(context, app),
    );
  }
}

/// Unawaited futures that may fail (fire and forget from a button); a failure
/// goes to the problem log.
void fire(Future<void> future) =>
    unawaited(future.catchError((Object error, StackTrace stack) => problemLog.error('unexpected', error, stack)));
