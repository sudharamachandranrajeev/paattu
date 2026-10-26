// Paattu for Android, Windows and Linux.

import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/material.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';
import 'package:path_provider/path_provider.dart';

import 'src/app_state.dart';
import 'src/charts.dart';
import 'src/history.dart';
import 'src/library.dart';
import 'src/listenbrainz.dart';
import 'src/log.dart';
import 'src/lyrics.dart';
import 'src/offline.dart';
import 'src/player/android_power.dart';
import 'src/player/paattu_audio_handler.dart';
import 'src/player/rhythm.dart';
import 'src/player/song_cache.dart';
import 'src/radio.dart';
import 'src/settings.dart';
import 'src/sources/jiosaavn.dart';
import 'src/ui/settings_page.dart' show offerUpdate;
import 'src/ui/shell.dart';
import 'src/update.dart';
import 'src/util.dart' show asString, nowStamp;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Anything that goes wrong uncaught goes to the problem log.
  final shown = FlutterError.onError;
  FlutterError.onError = (details) {
    problemLog.error('flutter: ${details.context ?? 'error'}', details.exception, details.stack);
    shown?.call(details);
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    problemLog.error('uncaught', error, stack);
    return true;
  };
  final desktop = Platform.isLinux || Platform.isWindows;
  if (desktop) {
    // ExoPlayer plays on Android; libmpv (media_kit) on the desktop.
    try {
      JustAudioMediaKit.ensureInitialized(linux: true, windows: true);
      JustAudioMediaKit.title = 'Paattu';
      // Speed through mpv's own `speed`, which keeps the pitch: with pitch
      // control on, media_kit puts scaletempo in `af`, over the equaliser.
      JustAudioMediaKit.pitch = false;
    } catch (error) {
      problemLog.error('libmpv', error);
      playbackUnavailable = Platform.isLinux
          ? "Paattu needs mpv's library to play. Install it (Arch: mpv, Debian/Ubuntu: libmpv2, "
                'Fedora: mpv-libs) and open Paattu again'
          : "Paattu can't find libmpv-2.dll next to paattu.exe. Reinstall Paattu";
    }
  }

  final dir = await getApplicationSupportDirectory();
  // Before the log's header, so it says what this build really is.
  await readAppVersion();
  unawaited(
    problemLog.start(
      File('${dir.path}${Platform.pathSeparator}paattu.log'),
      header: 'Paattu $appVersion on ${Platform.operatingSystem} ${Platform.operatingSystemVersion}',
    ),
  );
  final library = Library(File('${dir.path}${Platform.pathSeparator}library.json'));
  final settings = Settings(File('${dir.path}${Platform.pathSeparator}settings.json'));
  final history = History(File('${dir.path}${Platform.pathSeparator}history.json'));
  await Future.wait([library.load(), settings.load(), history.load()]);
  jiosaavnSaveData = settings.saveData;

  // The songs kept on this device: the folder picked in Settings where Paattu
  // can write to one, else a folder of the app's own.
  final offline = OfflineLibrary(
    keptSongsDirectory(settings.offlineDir, dir),
    limitBytes: settings.offlineLimitMb << 20,
  );
  await offline.load();

  // Plays scrobbled to ListenBrainz, and other devices' read back.
  final listenBrainz = ListenBrainz(history, library, settings);

  final player = await _player();
  try {
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());
  } catch (_) {
    // Not every desktop has an audio session to configure.
  }
  if (desktop && playbackUnavailable == null) await player.setVolume(settings.volume);
  // (On Android it waits for the first song, which brings the equaliser.)
  fire(player.setSound(settings.sound));
  final songs = SongCache(Directory('${(await getTemporaryDirectory()).path}${Platform.pathSeparator}paattu-songs'));
  fire(songs.start());
  // Kept between runs: small, and a song's rhythm never changes.
  final rhythms = RhythmFinder(
    Directory('${(await getApplicationCacheDirectory()).path}${Platform.pathSeparator}rhythm'),
  );
  player
    ..cache = songs
    ..offline = offline
    ..rhythms = rhythms
    ..radioSongs = SongRadio(
      history,
      favourites: () => library.playlistTracks(favouritesId),
      playlists: () => [
        for (final p in library.ownPlaylists())
          if (p['id'] != favouritesId) ...library.playlistTracks(asString(p['id'])),
      ],
      languageOf: library.playedLanguage,
    ).next
    ..onPlayed = ((track, heard, length) {
      history.played(track, heard, length: length);
      // A song played to the end joins its language's played playlist.
      if (fullyPlayed({'heard': heard, 'length': length ?? 0}) && library.notePlayed(track).isNotEmpty) {
        library.changed();
      }
      if (scrobbles({'heard': heard, 'length': length ?? 0})) fire(listenBrainz.sync());
    })
    ..onRemovedFromRadio = history.removedFromRadio;
  void playback() {
    jiosaavnSaveData = settings.saveData;
    player
      ..crossfade = settings.crossfade
      ..autoRadio = settings.autoRadio
      ..cacheAhead = !settings.saveData
      // Saving data means not pulling whole songs down, so don't keep them.
      ..keepListened = settings.offlineAutoSave && !settings.saveData;
    fire(player.setVideoMode(settings.videoMode));
    // The folder or the space allowed changed while running.
    fire(offline.moveTo(keptSongsDirectory(settings.offlineDir, dir), allowed: settings.offlineLimitMb << 20));
    fire(androidScreenAwake(settings.screenAwake));
  }

  playback();
  settings.addListener(playback);

  // A newer Paattu: looked for once a day, quietly, and offered from Settings.
  final updates = UpdateManager(
    currentVersion: appVersion,
    dir: Directory('${dir.path}${Platform.pathSeparator}updates'),
  );
  final offered = settings.updateOffered;
  if (offered != null) {
    // What the last run found, so Settings can say it at once.
    updates
      ..available = Release.fromJsonKept(offered)
      ..state = isNewerVersion(updates.available!.version, appVersion) ? UpdateState.available : UpdateState.idle;
  }

  final charts = Charts(
    history,
    File('${(await getApplicationCacheDirectory()).path}${Platform.pathSeparator}charts.json'),
  );
  fire(charts.load());
  final lyrics = Lyrics(
    Directory('${(await getApplicationCacheDirectory()).path}${Platform.pathSeparator}lyrics'),
    // Words timed to another upload of the song are lined up with the one
    // playing by their loudness (the rhythm Now Playing's cover moves with).
    level: (track) async => (await player.rhythmOf(track))?.level,
  );
  final app = AppState(library, settings, player, history, offline, updates, listenBrainz, charts, lyrics);
  runApp(PaattuApp(state: app));
  fire(listenBrainz.sync());
  fire(_lookForUpdates(app));
  if (Platform.isAndroid) fire(_androidBackground(settings));
  final problem = playbackUnavailable;
  if (problem != null) fire(Future.delayed(const Duration(seconds: 1), () => player.messages.add(problem)));
}

/// What Android needs for the music to go on with the screen locked: the
/// notification permission (the media notification is also the lock screen's
/// and the launcher widgets' controls), and, asked once, being left out of
/// battery optimisation (Settings › Playback can ask again).
Future<void> _androidBackground(Settings settings) async {
  await androidAskNotifications();
  if (settings.batteryAsked || await androidBatteryExempt()) return;
  settings.batteryAsked = true;
  await androidAskBatteryExempt();
}

/// Look for a newer Paattu each time the app starts, quietly, and ask whether
/// to install it when there is one (update.dart). What it finds is kept in
/// settings, so Settings can say it without asking GitHub again.
Future<void> _lookForUpdates(AppState app) async {
  final settings = app.settings;
  settings.updateChecked = nowStamp();
  await app.updates.check(quiet: true);
  final release = app.updates.available;
  settings.updateOffered = release?.toJson();
  if (release == null) return;
  // The first page may still be on its way.
  for (var i = 0; i < 50 && app.navigator.currentState?.overlay == null; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  final context = app.navigator.currentState?.overlay?.context;
  if (context == null || !context.mounted) {
    app.toast('Paattu ${release.version} is out — Settings has the update');
    return;
  }
  await offerUpdate(context, app, release);
}

/// On Android the player runs in a media service (notification, lock screen,
/// headset buttons), and on Windows it shows in the system's media controls
/// (the volume flyout, the lock screen, media keys; audio_service_win). On
/// Linux it runs in the app.
Future<PaattuAudioHandler> _player() async {
  if (!Platform.isAndroid && !Platform.isWindows) return PaattuAudioHandler();
  try {
    final service = AudioService.init(
      builder: PaattuAudioHandler.new,
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'dev.paattu.paattu.audio',
        androidNotificationChannelName: 'Playback',
        androidNotificationChannelDescription: 'The song playing, with controls',
        androidNotificationIcon: 'drawable/ic_stat_paattu',
        androidNotificationOngoing: false,
        androidStopForegroundOnPause: true,
        notificationColor: Color(0xFF0F766E),
      ),
    );
    // Never kept from starting by the media controls.
    return await (Platform.isWindows ? service.timeout(const Duration(seconds: 10)) : service);
  } catch (error, stack) {
    problemLog.error('audio service', error, stack);
    return PaattuAudioHandler();
  }
}
