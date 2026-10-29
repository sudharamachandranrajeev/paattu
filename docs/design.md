# Paattu design and development notes

[Back to the README](../README.md).

## Build and test

```bash
# The Python CLI and the plugin's Model.js
$ python3 -m unittest discover -s tests     # titles, library, search, seeds, cliamp export, config
$ node --test tests/*.test.mjs              # the plugin's Model.js

# Use this checkout as the installed program
$ ./install.sh --dev

# The app (Flutter 3.47)
$ cd app && flutter pub get && flutter test && flutter run

# README screenshots: the app (real fonts, a made-up library, drawn covers) ...
$ cd app && PAATTU_SHOTS=/tmp/shots flutter test test/screenshots_test.dart

# ... and the Omarchy plugin, drawn offscreen with a private silent mpv
$ tools/omarchy-screenshots/run.sh /tmp/shots-omarchy
```

## The app's code, CI and releases

The app is in `app/` (Flutter, Dart): `lib/src/` has the library model
(a port of `paattu/library.py`), title cleaning (`titles.py`), the sources
(JioSaavn, YouTube via youtube_explode_dart, SoundCloud) and the player
(just_audio: ExoPlayer on Android, libmpv on Windows / Linux, with
audio_service for Android's media controls). Now Playing's silent video is
video_player on Android and media_kit_video on Windows / Linux. `lib/src/ui/`
holds the glass look (`glass.dart`). `subject.dart` finds the cover's subject
(ML Kit on Android, U²-Net with ONNX Runtime on Windows / Linux, from
`packages/flutter_onnxruntime`). `player/sleep_timer.dart` is the sleep timer,
`offline.dart` the songs kept on this device, and `update.dart` the in-app
updater (GitHub's releases, checked by SHA-256 before anything is installed;
Android's half of it is the `installApk` method channel in `MainActivity.kt`,
which hands the APK to the system's installer through a FileProvider).
`app/test/` runs the same title, track-id and subject-mask cases as `tests/`,
plus the sleep timer, the offline library and the updater's version and
checksum reading. `app/test/screenshots_test.dart` renders the README's app
screenshots and is skipped unless `PAATTU_SHOTS` names an output folder.

GitHub Actions does the rest: `ci.yml` runs every test, shellcheck, and
`install.sh` on Debian, Ubuntu, Fedora, Arch and openSUSE containers;
`release.yml` builds the signed APK, the Windows installer (Inno Setup) and
the Linux AppImage and tarball, starts each one (the installer on Windows, an
Android emulator, Ubuntu, Fedora and Arch containers), and on a `v*` tag
publishes them as a release. The Android signing key is in the repository secrets
(`PAATTU_KEYSTORE_BASE64`, `PAATTU_KEYSTORE_PASSWORD`, `PAATTU_KEY_ALIAS`,
`PAATTU_KEY_PASSWORD`); without them the APK is signed with a debug key.

The shell plugin hot-reloads, except `Home.qml` (the always-loaded desktop
widget / window host), which needs `omarchy restart shell`.

## Five rules learned the hard way

- **Never bind `layer.enabled` to an Image's status** (`Cover.qml`). When a
  window first gets the screen's scale (1.5× here), Qt walks the item tree
  and reloads images. If an image drops out of `Ready`, the layer turns off
  and deletes its effect items while Qt is still walking them, and the whole
  shell aborts ("pure virtual method called").
- **Don't write a whole queue to mpv before reading its replies**
  (`engine.py`). mpv stops reading a client whose replies it can't send, so a
  mix of thousands of songs deadlocked and timed out. `Engine.batch` sends
  in chunks of 200 and reads as it goes. `tests/test_library.py` checks this
  against a real mpv.
- **YouTube ids can start with `-`** (66 songs in the library do), and
  argparse reads those as options. Pass ids to the CLI as `--track=ID` or
  after `--` (`Model.js` builds them that way; `tests/model.test.mjs` checks).
- **A Quickshell `Socket` is good for one connection** (`Player.qml`,
  Quickshell 0.3.1). Once a connect fails, setting `connected` or `path`
  again does nothing, so a shell started before the engine never saw it
  start and the UI stopped following playback. One that connects while mpv
  is quitting reports an error but stays "connected". Each attempt makes a
  fresh Socket, and any Socket that reports an error is thrown away.
- **A row's MouseArea goes under its buttons** (`z: -1`). A MouseArea that
  fills the row and comes after the buttons in the file gets their clicks,
  so the heart played the song instead.

Track ids for other sites are made in two places, `sources.track_id` and
`Model.trackId`; `tests/track_ids.json` holds the cases both suites check.

## cliamp

cliamp (Super+Shift+Alt+M) is a good terminal player and it was evaluated
as the engine. Its daemon mode, v2 IPC, EQ and spectrum stream are all
usable from a shell plugin, but only one cliamp instance can run per user,
so a cliamp engine would lock you out of cliamp's own TUI. Paattu keeps mpv
as the engine and shares the library instead:

```
paattu export cliamp      # every saved playlist → ~/.config/cliamp/playlists/Paattu - *.toml
```

cliamp then plays the same Malayalam / Tamil library with its Winamp EQ and
visualizer. Features worth bringing over next, natively: the spectrum visualizer (cava), Radio Browser
stations (cliamp's history already has Anbu FM Malayalam, BIG 92.7, Big FM
Tamil), and synced lyrics (LRCLIB).
