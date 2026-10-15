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
import 'src/history.dart';
import 'src/library.dart';
import 'src/log.dart';
import 'src/player/paattu_audio_handler.dart';
import 'src/player/song_cache.dart';
import 'src/radio.dart';
import 'src/settings.dart';
import 'src/sources/jiosaavn.dart';
import 'src/ui/shell.dart';

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
  unawaited(problemLog.start(File('${dir.path}${Platform.pathSeparator}paattu.log'),
      header: 'Paattu $appVersion on ${Platform.operatingSystem} ${Platform.operatingSystemVersion}'));
  final library = Library(File('${dir.path}${Platform.pathSeparator}library.json'));
  final settings = Settings(File('${dir.path}${Platform.pathSeparator}settings.json'));
  final history = History(File('${dir.path}${Platform.pathSeparator}history.json'));
  await Future.wait([library.load(), settings.load(), history.load()]);
  jiosaavnSaveData = settings.saveData;

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
  player
    ..cache = songs
    ..radioSongs = SongRadio(history).next
    ..onPlayed = ((track, heard, length) => history.played(track, heard, length: length));
  void playback() {
    jiosaavnSaveData = settings.saveData;
    player
      ..crossfade = settings.crossfade
      ..autoRadio = settings.autoRadio
      ..cacheAhead = !settings.saveData;
  }

  playback();
  settings.addListener(playback);

  runApp(PaattuApp(state: AppState(library, settings, player, history)));
  final problem = playbackUnavailable;
  if (problem != null) fire(Future.delayed(const Duration(seconds: 1), () => player.messages.add(problem)));
}

/// On Android the player runs in a media service (notification, lock screen,
/// headset buttons); elsewhere it runs in the app.
Future<PaattuAudioHandler> _player() async {
  if (!Platform.isAndroid) return PaattuAudioHandler();
  try {
    return await AudioService.init(
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
  } catch (error, stack) {
    problemLog.error('audio service', error, stack);
    return PaattuAudioHandler();
  }
}
