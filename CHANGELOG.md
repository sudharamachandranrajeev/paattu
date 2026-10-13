# Changelog

## 0.2.0 — Windows, Android and any Linux

- **Paattu app for Windows 11 and Android** (and a Linux AppImage), built
  with Flutter: Home with your mixes and shelves, search across JioSaavn
  (320 kbps AAC), YouTube and SoundCloud, links to songs, albums and
  playlists, YouTube profiles and playlists, Favourites, Saved songs, your
  own playlists, a queue, a now-playing screen with the stream quality,
  Android lock-screen / notification controls, and the six Paattu themes.
  The library imports from and exports to the desktop Paattu's
  `library.json`.
- **`install.sh` for any distro**: Arch, Debian, Ubuntu, Fedora, openSUSE,
  Void and Alpine. Installs mpv, python3, a current yt-dlp and deno, copies
  the program to `~/.local/lib/paattu`, and only sets up the Omarchy plugin
  on Omarchy. `--check`, `--uninstall [--purge]`, `--dev`, `--yes`.
- `paattu` works without systemd (starts mpv itself) and without Omarchy
  (`paattu --version`, browser fallback for `watch`).
- CI: tests, shellcheck and `install.sh` on five distros; releases build the
  signed APK, the Windows installer and the AppImage.

## 0.1.0-alpha — first release

The Omarchy music player for Malayalam and Tamil songs: YouTube profiles and
playlists, Favourites and your own playlists, mixes, search across JioSaavn,
YouTube and SoundCloud, a bar control, a desktop widget and an app window.
