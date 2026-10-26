// Soft interface sounds, made by tools/ui-sounds.py: a drop for a tap, a
// breath for another page and a small singing bowl for another song, about
// -20 dBFS at their loudest so they sit under the music. One player plays them
// all from one file, seeking to each, so they cost one decoder and nothing
// downloaded. Settings › Sound turns them off.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

import 'log.dart';

/// Where each sound is in assets/sounds/ui.wav (ui-sounds.py's OFFSETS), in
/// order of weight: a heavier one is never cut short by a lighter one.
enum UiSound {
  tap(Duration.zero, Duration(milliseconds: 250)),
  move(Duration(milliseconds: 500), Duration(milliseconds: 500)),
  change(Duration(milliseconds: 1250), Duration(milliseconds: 1500));

  const UiSound(this.start, this.length);
  final Duration start, length;
}

class UiSounds {
  UiSounds._();
  static final instance = UiSounds._();

  /// Off until main.dart turns them on (never in tests).
  bool enabled = false;

  AudioPlayer? _player;
  Future<void>? _loading;
  bool _broken = false;
  UiSound? _playing;
  DateTime _since = DateTime(0);
  Timer? _stop;

  void play(UiSound sound) {
    if (!enabled || _broken) return;
    // A page opened by a tap gets the breath alone: a heavier sound just
    // begun is left to ring.
    final playing = _playing;
    if (playing != null && playing.index > sound.index && DateTime.now().difference(_since) < playing.length ~/ 2) {
      return;
    }
    _playing = sound;
    _since = DateTime.now();
    unawaited(_play(sound));
  }

  Future<void> _play(UiSound sound) async {
    try {
      final player = _player ??= AudioPlayer(
        // Never the music's: no audio focus, no pausing for calls.
        handleInterruptions: false,
        handleAudioSessionActivation: false,
        androidApplyAudioAttributes: false,
      );
      await (_loading ??= player.setAsset('assets/sounds/ui.wav', preload: true));
      _stop?.cancel();
      await player.seek(sound.start);
      unawaited(player.play());
      _stop = Timer(sound.length, () {
        if (identical(_playing, sound)) _playing = null;
        unawaited(player.pause());
      });
    } catch (error) {
      _broken = true;
      problemLog.error('interface sounds', error);
    }
  }
}

/// The theme's ink splash, with the tap sound: every Material button, list
/// row, chip and switch splashes when tapped or picked with a remote, so this
/// one place gives them all a sound.
class SoundingSplash extends InteractiveInkFeatureFactory {
  const SoundingSplash(this.base);
  final InteractiveInkFeatureFactory base;

  @override
  InteractiveInkFeature create({
    required MaterialInkController controller,
    required RenderBox referenceBox,
    required Offset position,
    required Color color,
    required TextDirection textDirection,
    bool containedInkWell = false,
    RectCallback? rectCallback,
    BorderRadius? borderRadius,
    ShapeBorder? customBorder,
    double? radius,
    VoidCallback? onRemoved,
  }) {
    UiSounds.instance.play(UiSound.tap);
    return base.create(
      controller: controller,
      referenceBox: referenceBox,
      position: position,
      color: color,
      textDirection: textDirection,
      containedInkWell: containedInkWell,
      rectCallback: rectCallback,
      borderRadius: borderRadius,
      customBorder: customBorder,
      radius: radius,
      onRemoved: onRemoved,
    );
  }

  // Equal when the splash under it is, so the theme stays equal between builds.
  @override
  bool operator ==(Object other) => other is SoundingSplash && other.base == base;

  @override
  int get hashCode => base.hashCode;
}

/// The breath when a page opens or closes.
class SoundingPages extends NavigatorObserver {
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is PageRoute && previousRoute != null) UiSounds.instance.play(UiSound.move);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is PageRoute) UiSounds.instance.play(UiSound.move);
  }
}
