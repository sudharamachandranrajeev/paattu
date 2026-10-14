# Changelog

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
