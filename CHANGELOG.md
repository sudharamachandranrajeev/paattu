# Changelog

## 0.6.2 — Songs play again on phones whose equaliser starts late

Which file: the same as before (`Paattu-0.6.2-android.apk` is the one that
matters; the Windows and Linux builds and Omarchy only change their version
number). On Omarchy, `git pull` (a `--dev` install).

What's fixed:
- On some Android phones no song would play: every site and every try
  failed at once with `NullPointerException … Equalizer.getNumberOfBands()`,
  and after five songs the player stopped. The player asks the phone's
  equaliser for its bands as it starts, and on these phones the equaliser
  wasn't there yet; the player then kept that failure, so every later try
  failed the same way, whatever the song. Now a player that doesn't start
  is started again afresh, and if it fails a second time it carries on
  without the phone's equaliser (the sound settings then don't apply, and
  the app says so).
- The problem log says "the phone's player didn't start" for this, not the
  raw error.

## 0.6.1 — Made-for-you playlists that came out short are made again

Which file: the same as before (`Paattu-0.6.1-windows-x64-setup.exe`,
`Paattu-0.6.1-android.apk`, the AppImage or the tarball). On Omarchy,
`git pull` (a `--dev` install) or pull and run `./install.sh`.

What's fixed:
- A Daily mix, Weekly discovery or Monthly top made while YouTube Music
  didn't answer could come out with a song or two and stay like that all
  day. A playlist with fewer than 15 songs still plays, but isn't kept, so
  opening it again makes it again (and a short one already kept is made
  again).

## 0.6.0 — Radio, playlists made for you, and fades between songs

Which file: the same as before (`Paattu-0.6.0-windows-x64-setup.exe`,
`Paattu-0.6.0-android.apk`, the AppImage or the tarball). On Omarchy, pull
and run `./install.sh` (or `git pull` for a `--dev` install), then
`paattu engine restart` (it loads the engine's new script) and
`omarchy restart shell`.

What's new:
- **Radio**: *Start radio* on Now Playing plays songs like the one playing,
  without end, from YouTube Music's own radio for it. It leaves out songs
  you heard in the last six hours and songs you skipped twice, and when one
  song's radio runs dry it carries on from a song it played.
- **Auto radio** (on by default): when a song or a queue you picked runs
  out, the music carries on with songs like the last one (not with repeat
  on, or after you turned the radio off). Settings in the app, *Look &
  settings → Between songs* on Omarchy.
- **Made for you** on Home, from what you play (how long, how often, how
  lately, your Favourites and Saved songs, what you skip): a **Daily mix**
  of songs you love with a few like them, a **Weekly discovery** of songs
  new to you, and the **Monthly top**.
- **Describe a playlist**: "Ilaiyaraaja melodies, rain songs, Premam" makes
  one from each part's songs and their radios. Play it, or save it as a
  playlist.
- **Fades between songs**: 3 seconds by default, 0 to 12 in Settings. In
  the app the songs overlap (the next one is ready 25 seconds early); on
  Omarchy, where mpv plays one song at a time, one fades out and then the
  next fades in.
- **Songs downloaded ahead** in the app: the next two download in pieces
  while one plays (not with *Save data* on), so a slow stream doesn't stop
  the music.
- **Omarchy finds a dead stream elsewhere**, like the apps: a song that
  won't load is looked for on the other sites and the copy found plays in
  its place.
- Omarchy's queue shows the titles of songs found online (radio, search,
  made for you), not their links.
- New commands: `paattu radio`, `paattu made`, `paattu describe`; plays
  are kept in `~/.local/share/paattu/history.json`.

## 0.5.1 — Songs play on Android again, and a problem log

Which file: the same as before (`Paattu-0.5.1-windows-x64-setup.exe`,
`Paattu-0.5.1-android.apk`, the AppImage or the tarball). On Omarchy, pull
and run `./install.sh` (or `git pull` for a `--dev` install), then
`omarchy restart shell`. 0.5.0's builds were never published (the Linux
tarball failed its test), so this is the first release with 0.5.0's new
look too.

What's fixed and new:
- **Songs play in the apps again.** JioSaavn changed the links its web
  player gets (they're now for its copy-protected player and refuse a plain
  request), and most search results were JioSaavn's copy. The apps now ask
  for the links yt-dlp gets, which play.
- **Music from** (Settings in the apps, *Look & settings* on Omarchy):
  YouTube by default, or JioSaavn, SoundCloud or every site. Search results
  no longer say which site they're from.
- **A song that won't play is found elsewhere**: the apps try its stream
  another way, then the same song on the other sites (best sound first:
  JioSaavn, YouTube, SoundCloud), before skipping it. A skipped song says
  why in plain words ("the site refused to stream it", "it took too long to
  start") and the next one plays. Shorter waits for a dead stream.
- **Problem log** in the apps' Settings: what the app tried and what went
  wrong (each stream, the player's errors with the server's answer, failed
  searches, crashes). Save it to a file, copy it, read it or clear it;
  attach it to a bug report. It's `paattu.log` in the app's folder, and
  Android's `adb logcat` shows the same lines.
- The Linux tarball asks for libmpv.so.2, which Debian 12+, Ubuntu 24.04+,
  Fedora and Arch have (older systems: the AppImage).

## 0.5.0 — A new look, and the song's video behind Now Playing

Which file: the same as before (`Paattu-0.5.0-windows-x64-setup.exe`,
`Paattu-0.5.0-android.apk`, the AppImage or the tarball). On Omarchy, pull
and run `./install.sh` (or `git pull` for a `--dev` install), then
`omarchy restart shell`.

What's new:
- **A new look** in the app and the Omarchy window: a dark page lit from
  the top by your colour scheme, frosted-glass panels with big round
  corners, pill-shaped song rows, round glass buttons, and Poppins in the
  app (Malayalam and Tamil still use the system's fonts). Album, artist,
  playlist and profile pages open with a large glowing picture.
- **The song's video behind Now Playing**: a small piece of it, blurred,
  silent and kept in time with the music (it follows seeks, pauses and
  speed). Songs from JioSaavn or SoundCloud use a YouTube video of the
  same length when there is one. It costs about 1 MB a minute; turn it off
  in Settings (the app) or *Look & settings* (Omarchy).
- **Omarchy: a Now Playing page**, from the sidebar or by clicking the song
  in the player bar: the cover big, the song, its stream and what's up
  next. The video needs Qt Multimedia (`qt6-multimedia-ffmpeg`, which
  `install.sh` now offers); without it the page works without the video.
- `paattu video SONG` prints where to stream a song's small video.
- A new colour scheme, **Chembarathi** (hibiscus red and marigold).
- The Favourites tile on Omarchy says "Songs you hearted" again.

## 0.4.0 — Equaliser, tone and speed

Which file: the same as before (`Paattu-0.4.0-windows-x64-setup.exe`,
`Paattu-0.4.0-android.apk`, the AppImage or the tarball). On Omarchy, pull
and run `./install.sh` (or `git pull` for a `--dev` install), then
`omarchy restart shell`.

What's new:
- **Sound page with a ten-band equaliser** (31 Hz to 16 kHz, ±12 dB), drawn
  over its curve, in the style of Poweramp and AIMP. You hear a slider while
  you drag it; double-click or double-tap puts it back to 0.
- **Presets**: Flat, Melody, Kuthu, Bass boost, Treble boost, Classical,
  Rock, Pop, Dance, Jazz, Acoustic, Loudness, Headphones and Late night.
  Save your own bands as a preset, and delete them again.
- **Tone knobs**: preamp, bass, treble, left / right balance, and speed
  (0.5× to 2×) that keeps the pitch.
- **Keep loud songs from clipping** (on by default) lowers the preamp by
  the curve's biggest boost.
- Windows and the Linux app run the same filters as the Omarchy engine.
  Android uses the phone's own equaliser and loudness enhancer, matched to
  the same curve (balance isn't available there).
- Omarchy: the Sound page in the Paattu window, an equaliser button on the
  now-playing bar, and the `paattu sound` command.

## 0.3.0 — Faster YouTube, albums, artists and suggestions

Which file: the same as 0.2.0 (`Paattu-0.3.0-windows-x64-setup.exe`,
`Paattu-0.3.0-android.apk`, the AppImage or the tarball). On Omarchy, pull
and run `./install.sh` (or `git pull` for a `--dev` install), then
`omarchy restart shell`.

What's new:
- **YouTube songs start much faster in the app** (Windows, Android and the
  Linux app), and the ones that sometimes never played now do. Audio links
  come from one quick request to YouTube's Vision Pro client; on Android the
  first request asks for a byte range, which YouTube doesn't slow down to
  playing speed.
- **Search for songs, albums, artists and playlists** across JioSaavn,
  YouTube and SoundCloud, with a tab for each. Scrolling down loads more,
  without repeats.
- **Album, playlist and artist pages**: play, shuffle, save the songs, add
  them to a playlist, or open them on the site. A JioSaavn artist page
  lists their songs (more as you scroll), albums and singles, playlists and
  similar singers. A YouTube channel page lists its popular uploads and
  playlists, and you can follow the channel. YouTube playlists can be saved
  to the library.
- **Suggestions while you type**: YouTube's search phrases, plus JioSaavn
  songs, albums, singers and playlists to open straight away. The app also
  keeps your recent searches.
- Omarchy: all of the above in the Paattu window, from the new
  `paattu browse` command (`browse search --kind album …`,
  `browse suggest`, `browse open`, `browse play`).

## 0.2.0 — Windows, Android and any Linux

Which file:
- **Windows 11**: `Paattu-0.2.0-windows-x64-setup.exe` (not code signed yet:
  SmartScreen → More info → Run anyway), or the portable zip.
- **Android**: `Paattu-0.2.0-android.apk` (allow installing unknown apps).
- **Linux app**: `Paattu-0.2.0-linux-x86_64.AppImage` (`chmod +x`, run), or
  the tarball with your distro's libmpv.
- **Linux command and Omarchy plugin**: clone the repository and run
  `./install.sh`.

What's new:
- **Paattu app for Windows 11 and Android** (and a Linux AppImage), built
  with Flutter: Home with your mixes and shelves, search across JioSaavn
  (320 kbps AAC), YouTube and SoundCloud, links to songs, albums and
  playlists, YouTube profiles and playlists, Favourites, Saved songs, your
  own playlists, a queue, a now-playing screen with the stream quality,
  Android lock-screen / notification controls, and the Paattu themes.
  The library imports from and exports to the desktop Paattu's
  `library.json`.
- **`install.sh` for any distro**: Arch, Debian, Ubuntu, Fedora, openSUSE,
  Void and Alpine. Installs mpv, python3, a current yt-dlp and deno, copies
  the program to `~/.local/lib/paattu`, and only sets up the Omarchy plugin
  on Omarchy. `--check`, `--uninstall [--purge]`, `--dev`, `--yes`.
- `paattu` works without systemd (starts mpv itself) and without Omarchy
  (`paattu --version`, browser fallback for `watch`).
- CI: tests, shellcheck and `install.sh` on five distros; releases build the
  signed APK, the Windows installer, the AppImage and the tarball, and start
  each one (Windows, an Android emulator, Ubuntu, Fedora and Arch) first.

## 0.1.0-alpha — first release

The Omarchy music player for Malayalam and Tamil songs: YouTube profiles and
playlists, Favourites and your own playlists, mixes, search across JioSaavn,
YouTube and SoundCloud, a bar control, a desktop widget and an app window.
