// Paattu for Android, Windows and Linux.

import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/material.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';
import 'package:path_provider/path_provider.dart';

import 'src/app_state.dart';
import 'src/library.dart';
import 'src/player/paattu_audio_handler.dart';
import 'src/settings.dart';
import 'src/sources/jiosaavn.dart';
import 'src/ui/shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final desktop = Platform.isLinux || Platform.isWindows;
  if (desktop) {
    // ExoPlayer plays on Android; libmpv (media_kit) on the desktop.
    JustAudioMediaKit.ensureInitialized(linux: true, windows: true);
    JustAudioMediaKit.title = 'Paattu';
  }

  final dir = await getApplicationSupportDirectory();
  final library = Library(File('${dir.path}${Platform.pathSeparator}library.json'));
  final settings = Settings(File('${dir.path}${Platform.pathSeparator}settings.json'));
  await Future.wait([library.load(), settings.load()]);
  jiosaavnSaveData = settings.saveData;

  final player = await _player();
  try {
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());
  } catch (_) {
    // Not every desktop has an audio session to configure.
  }
  if (desktop) await player.setVolume(settings.volume);

  runApp(PaattuApp(state: AppState(library, settings, player)));
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
  } catch (error) {
    debugPrint('audio service: $error');
    return PaattuAudioHandler();
  }
}
