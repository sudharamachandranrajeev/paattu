# Paattu — പാട്ട് · பாட்டு

Malayalam & Tamil music from public YouTube playlists, plus search across
JioSaavn, YouTube and SoundCloud. *Paattu* means "song" in both languages.

| Where | What you get | Install |
|---|---|---|
| **Linux** (any distro) | the `paattu` command and music engine; on [Omarchy](https://omarchy.org) also a bar control, a desktop widget and an app window | `./install.sh` (below) |
| **Windows 11** | the Paattu app | `Paattu-…-windows-x64-setup.exe` from [Releases](../../releases) (or the portable zip) |
| **Android** | the Paattu app, with lock-screen and notification controls | `Paattu-…-android.apk` from [Releases](../../releases) |
| **Linux desktop app** | the same app as Windows / Android | `Paattu-…-linux-x86_64.AppImage` or the tarball from [Releases](../../releases) |

The apps and the Linux command share the library format: export it from
one (Settings → Export the library, or `~/.local/share/paattu/library.json`)
and import it in another.

### Linux: the command and the Omarchy plugin

```
git clone https://github.com/sudharamachandranrajeev/paattu.git
cd paattu
./install.sh                    # asks once for sudo to install mpv and python
./install.sh --check            # what's installed
sudo ~/.local/lib/paattu/install.sh --firewall   # only with OpenSnitch: let mpv / yt-dlp reach the music sites
./install.sh --uninstall        # remove it (--purge also removes your library)
```

`install.sh` works on Arch (and Omarchy, Manjaro, EndeavourOS, CachyOS),
Debian, Ubuntu (and Mint, Pop!_OS), Fedora, openSUSE, Void and Alpine. It
installs **mpv** (and mpv-mpris for media keys) and **python3** with your
package manager, a current **yt-dlp** (from pacman on Arch, otherwise the
official release into `~/.local/bin`, since distro packages are usually too
old for YouTube) and **deno** (yt-dlp needs a JavaScript runtime for
YouTube), then the program into `~/.local/lib/paattu`, the `paattu` command,
and an mpv engine service for systemd users. Nothing else runs as root.
`--yes` answers its questions; `--dev` links your checkout instead of
copying it (for working on Paattu). Without systemd, `paattu` starts mpv
itself.

On Omarchy, open it with **Super+Shift+M**, the music icon in the bar, the
widget on workspace 1, or Super+Space → Paattu. Elsewhere, use the command:
`paattu search malare`, `paattu play --mix "Malayalam mix"`, `paattu --help`.

### Windows and Android

Download from [Releases](../../releases). The Windows installer is not code
signed yet, so SmartScreen says "Windows protected your PC": choose **More
info → Run anyway**. On Android, allow your browser or file manager to
install unknown apps when asked. On Linux, the AppImage brings its own mpv
and uses your desktop's GTK 3 (`chmod +x` it and run it); the tarball also
needs mpv's library, libmpv.so.2 (`mpv` on Arch, `libmpv2` on Debian 12+ /
Ubuntu 24.04+, `mpv-libs` on Fedora; on older systems use the AppImage).

The apps search and play by themselves (no yt-dlp or mpv to install):
JioSaavn songs at 320 kbps AAC, YouTube's best audio (Opus), SoundCloud,
and direct links to audio files. They have the same library as the Linux
command: Home with your mixes and shelves, Search, Library (your playlists,
YouTube profiles and playlists), Favourites, a queue and a now-playing
screen, and the Paattu themes.

Songs come from YouTube unless **Settings → Music from** says JioSaavn,
SoundCloud or every site. A song that won't play is tried another way, then
as the same song on the other sites (best sound first); if nothing works,
the app says why in plain words and plays the next one. When something goes
wrong, **Settings → Problem log → Save the problem log** writes what the app
tried and what failed to a text file: attach it to an
[issue](../../issues).

## How it works

| Piece | What it is |
|---|---|
| `paattu` (Python, stdlib only) | library, YouTube lookups, search, playback commands — `paattu --help` |
| `paattu-engine.service` | headless **mpv** with a JSON IPC socket; resolves YouTube, JioSaavn, SoundCloud and other links through **yt-dlp** |
| `~/.config/omarchy/plugins/rajeevrama.paattu` | Omarchy shell plugin: bar widget + desktop widget + app window |
| `~/.local/share/paattu/library.json` | users, playlists, tracks (`shelf.json` is the small summary the bar reads) |
| `~/.cache/paattu/art/` | cover art, fetched by `paattu art` so the shell never touches the network |
| `~/.local/share/paattu/history.json` | what you played and for how long, behind the radio and the playlists made for you |
| `~/.config/paattu/mpv/scripts/paattu.lua` | the engine's script: notes each play, asks for more radio songs, fades, finds a dead stream elsewhere |

Choices, and why:

- **yt-dlp, not Piped.** yt-dlp runs locally and pulls the audio stream
  straight from YouTube, so no third-party instance sees what you play and
  there's nothing to go down.
- **No ads, without a browser.** Ads live in YouTube's player page; Paattu
  never loads it, so there's nothing to block. The video button opens Brave
  (the default browser) where Shields blocks the page's ads.
- **mpv as the engine.** mpv + yt-dlp is the most reliable YouTube audio path,
  and mpv-mpris makes media keys, the Omarchy OSD and the lock screen work
  for free. cliamp keeps its own role (below).

## Feature 1: YouTube profiles and their public playlists

Paste a YouTube profile (a label, a composer, a friend) and **every public
playlist on it** becomes a playlist in Paattu. Paste a playlist link and just
that one is added. In the app, use **Add from YouTube** (top bar, home page,
or the bar panel). From a terminal:

```
paattu import @Muzik247                   # a profile: all of its playlists
paattu import 'https://www.youtube.com/playlist?list=…' --lang Malayalam
paattu user list
paattu user sync                          # new playlists on followed profiles, fresh songs
```

Every profile also gets two automatic playlists: **Most played** (its popular
uploads) and **New releases**. Songs are fetched right away for profiles with
up to 40 playlists. Big labels have hundreds, so Paattu fetches the best 12
(hits, jukeboxes, recent movie albums) and loads the rest when you open or
play them. *Load songs for N playlists* on the profile page, or
`paattu user fetch @handle`, fetches them all at once. Profiles added this
way stay whole: `user sync` adds their new playlists too.

### Removing things

- **A playlist:** the trash button on its row (profile page) or *Remove from
  app* on the playlist page. Click twice to confirm. It stays out of the app,
  even when the profile is synced again. *Bring back N removed playlists* on
  the profile page undoes it.
- **A song:** hover it in a playlist and click the trash button. Refreshing
  the playlist won't bring it back; *Bring back N removed songs* on the
  playlist page will.
- **A profile:** *Unfollow* on its page. A profile added whole goes with all
  of its playlists. For the optional starter library's profiles, the
  playlists you saved stay.

```
paattu playlist remove PL…                # one or more ids
paattu playlist restore [PL…] [--user @handle]
paattu playlist remove-songs PL… VIDEO…   # ids or watch links
paattu playlist restore-songs PL…
paattu user save-all @handle              # older profiles: add the playlists not saved yet
paattu user remove @handle
```

The optional starter library's profiles come with four saved playlists each.
*Add the other N playlists* on a profile's page adds the rest.

Video titles from the labels (`Song - Video Song | Movie | Composer | Label`)
are cleaned into song, movie and credits by `paattu/titles.py`.

### The optional starter library

A new library is empty: add the profiles and playlists you want. If you'd
rather start with a ready-made South Indian library, `paattu seed` follows
27 verified channels (`paattu/seeds.py`) and saves about four playlists from
each:

- **Malayalam:** Muzik247, Saregama Malayalam, Sony Music Malayalam,
  Manorama Music Songs, Goodwill, East Coast, Satyam Audios,
  Millennium Audios, Magic Frames, Wonderwall, Mango Music, Friday Music,
  Think Music Malayalam, Sushin Shyam
- **Tamil:** Think Music, Sony Music South, Saregama Tamil, T-Series Tamil,
  Divo, Aditya Music Tamil, U1 Records, Lahari Music Tamil, Zee Music South,
  A. R. Rahman, Anirudh, Ilaiyaraaja, Sid Sriram

`paattu seed --remove` takes it out again: those profiles, the playlists they
brought and their cached cover art. Profiles and playlists you added, your
own playlists, Favourites and mixes stay. `paattu art --prune` clears cached
art for anything no longer in the library.

## Favourites and your own playlists

Songs you want to keep go in **Favourites** or in playlists you make. Sync
and refresh never touch them, so a song stays there even after the YouTube
playlist it came from drops it or you remove that playlist.

- **Heart** a song to add it to Favourites (click again to take it out).
- **Save** (the bookmark) keeps it in **Saved songs**, your library of
  songs found by searching. Like Favourites it's always there and can't be
  renamed or deleted.
- **Add to playlist** (the list-plus button) ticks the playlists the song
  is in. Click one to add or remove it, or type a name to start a new one.

Both buttons are on every now-playing view: the app's bottom bar, the bar
panel and all three desktop styles. In the app they're also on every song
row (hover a row; hearted songs keep their heart showing). The desktop widget
can't take typing, so its *New playlist…* opens the app's picker.

Favourites sits in the sidebar; your playlists are on Home under *Your
playlists*, where you can also start a new one. Their pages can rename and
delete them (Favourites can't be deleted).

```
paattu fav                              # heart the song that's playing
paattu fav VIDEO… | --remove | --toggle | --list
paattu save [SONG…] | --remove | --toggle | --list   # Saved songs
paattu play saved
paattu playlist new "Night drive" [VIDEO…] [--now]
paattu playlist add-songs "Night drive" [VIDEO…]   # default: the song that's playing
paattu playlist remove-songs "Night drive" VIDEO…
paattu playlist rename "Night drive" "Rain songs"
paattu playlist remove "Rain songs"     # deletes it
paattu play favourites                  # or the name of any playlist you made
```

A song from outside the library (a watch link) gets its title from yt-dlp.
Your playlists live in `library.json` next to the saved ones (`local: true`,
ids `paattu-…`; Favourites is `paattu-favourites`) and appear in `shelf.json`
under `mine` for the bar and the desktop widget.

## Search: new songs from YouTube, JioSaavn, SoundCloud or a link

The search box at the top of the app and of the bar panel (press `/` in
either) looks beyond your library. Type a song, a film or a singer and press
**Enter** to search where the music comes from: YouTube unless *Look &
settings → Music from* (the apps: *Settings → Music from*) picks another
site or all three. Albums come from JioSaavn and SoundCloud whichever you
pick.

| Site | What it has | Plays at |
|---|---|---|
| **JioSaavn** | the labels' film albums | AAC, up to 320 kbps |
| **YouTube** | everything else: lyric videos, old film songs, live shows | Opus, about 130–160 kbps |
| **SoundCloud** | covers, remixes, independent artists | whatever the uploader gave |

Or **paste a link** to a song, album or playlist on any site yt-dlp can play:
JioSaavn, YouTube, SoundCloud, Bandcamp, Audiomack, archive.org, or a plain
mp3 / m4a / flac file. A FLAC link plays lossless.

While you type, suggestions come up: YouTube's search phrases, and
JioSaavn songs, albums, singers and playlists that open straight away. After
**Enter**, the tabs switch between **Songs**, **Albums**, **Artists** and
**Playlists**; each loads more as you scroll down, and the same film song
from two sites shows once (the 320 kbps JioSaavn copy). An album or playlist
opens on its own page to play, shuffle, save or open on its site. A
JioSaavn artist's page has their songs (more as you scroll), albums and
singles, playlists and similar singers; a YouTube channel's has its popular
uploads and playlists, and **Follow** adds it to YouTube users.

Click a result to play it. Hover it for its buttons: heart (Favourites),
save (Saved songs), add to any of your playlists or a new one, and play
next. In the app, typing filters your library as before and the online
results sit above it, without saying which site each is from. In the bar
panel, *All N in Paattu* opens the same search in the app.

Every now-playing view shows what mpv is decoding: *AAC · 320 kbps* from
the stream's own bit rate, or *Opus · ~130 kbps* measured when the site
doesn't say. Paattu streams; it doesn't download, and it doesn't scrape mp3
download sites.

```
paattu search kaathalae kaathalae               # where the music comes from (search.sites)
paattu search --site jiosaavn --limit 20 malare
paattu search 'https://www.jiosaavn.com/album/…'   # what's at a link
paattu browse search --kind album chithra       # songs, albums, artists or playlists, a page at a time
paattu browse search --kind song --after '{"youtube": "…"}' chithra   # the next page
paattu browse suggest chith                     # what the search box suggests
paattu browse open '{"type": "artist", "site": "jiosaavn", "id": "455", …}'   # an item from browse search
paattu play SONG                                # an id from a search, or any song link
paattu add [--next] SONG
paattu save SONG | paattu fav SONG
paattu playlist add-songs "Night drive" SONG
```

Songs from other sites get ids made from their page address
(`jiosaavn.com_song_kaathalae-kaathalae-from-96_QyVdYxxAZgM`). The last 400
search results are remembered in `~/.cache/paattu/search.json`, so their ids
work after the search. A song you save, heart or add to a playlist is copied
into `library.json`. Search settings are in `paattu config`:
`search.sites` (`["youtube"]`, or any of jiosaavn, youtube, soundcloud) and
`search.limit`.

## Mixes (the shuffle buttons)

The shuffle buttons on the bar panel, the desktop widget and Home are
**mixes**, and you choose what goes in them. A new library starts with
*Malayalam mix* and *Tamil mix*. You can rename, change, reorder or delete
them, and add as many more as you like. A mix shuffles everything in it:

- **a language:** every saved playlist in that language, including ones
  saved later
- **a YouTube profile:** every saved playlist of that profile, including new
  ones that `user sync` adds
- **a playlist:** that one playlist, saved or one of yours (Favourites and
  Saved songs too)

In the app, **Mixes** in the sidebar lists them in button order. Use the
arrows to reorder, the pencil to change one, the trash to delete, or type a
name to make a new one. A mix's page has two parts: *In this mix* (click a
source to take it out) and *Add to this mix*, which lists every language,
profile and playlist with a filter box. **Add to mix** on a profile, playlist
or language page puts that one into any mix, or starts a new mix with it.
*Edit mixes* on the bar panel and on Home opens the list. In the bar panel,
keys 1–9 start mix 1–9. With nothing playing, middle-clicking the bar icon
starts the first mix.

```
paattu mix list
paattu mix new "Night drive" --user @Muzik247 --playlist favourites
paattu mix add "Night drive" --lang Tamil --playlist 'https://www.youtube.com/playlist?list=…'
paattu mix drop "Night drive" --lang Tamil
paattu mix rename "Tamil mix" "Kollywood"
paattu mix move "Night drive" 1         # its place among the buttons, from 1
paattu mix remove Kollywood
paattu mix fetch "Night drive"          # load songs for its playlists that don't have them yet
paattu play --mix "Night drive"         # what the button does
```

Mixes live in `library.json` under `mixes` (list order is button order) and
in `shelf.json` with their counts. When you remove a playlist or unfollow a
profile, it also leaves every mix it was in. Starting a mix whose playlists
have no songs loaded yet loads a few first. Playlists you picked one by one
always load. *Load songs for N playlists* on the mix page loads the rest.
A mix you delete stays deleted, even the first two.

## Playing

```
paattu play --mix "Malayalam mix"       # a shuffle button (see Mixes)
paattu play --lang Malayalam            # shuffled mix of the saved Malayalam playlists
paattu play PL… [--shuffle] [--index 3]
paattu play --user @ARRahman
paattu toggle | next | prev | seek +10 | volume 60 | shuffle | repeat
paattu status | queue | jump 5
paattu watch                            # this song's video in Brave, audio pauses
paattu video SONG                       # where to stream its small, silent video
```

Now Playing (in the app, and on Omarchy from the sidebar or by clicking the
song in the player bar) shows the song's video behind it, blurred, silent
and kept in time with the music: the smallest H.264 picture, about 1 MB a
minute. A YouTube Music song whose own video is only its cover held still
(an "art track"), and JioSaavn and SoundCloud songs, use a YouTube video of
about the same length found by search (a lyric or video song) when there is
one. On a phone the cover sits, rounded, on a blurred copy of itself and fades
out when the video comes on. On Omarchy it needs Qt Multimedia (`qt6-multimedia-ffmpeg`);
turn it off with `paattu config set videoBackground false` or in *Look &
settings*.

The queue skips trailers and plays each song once even when a playlist has
both the video and the lyrical upload.

## Radio and playlists made for you

```
paattu radio start [SONG]               # songs like SONG (or the one playing), without end
paattu radio stop                       # the radio's songs still to come go
paattu made                             # Daily mix, Weekly discovery, Monthly top
paattu made daily --play [--refresh]    # play today's (--refresh: a new one)
paattu describe "Ilaiyaraaja melodies, rain songs, Premam" --play [--save NAME]
paattu config set fade 3                # seconds a song fades out and the next in (0: off)
paattu config set autoRadio false       # don't carry on when the queue runs out
```

**Radio** (the *Start radio* button on Now Playing, in the app and on
Omarchy) plays songs like a song, from YouTube Music's own radio for it, a
helping at a time as the queue runs low. Like Spotify's and YouTube's, it
leaves out what you played in the last six hours and songs you skipped more
than once, and when one song's radio runs dry it carries on from a song it
played. With **auto radio** on (the default), any queue that runs out
carries on as a radio of its last song, unless repeat is on or you turned
the radio off.

**Made for you** (on Home) comes from what you play: how long you listened
(a play counts after half a song or 30 seconds), how often, how lately
(a play is worth half as much a week later), your Favourites and Saved
songs, and what you skip.
- **Daily mix**: songs you love, two at a time, then one like them that's
  new to you. A new one every day.
- **Weekly discovery**: only songs you haven't played, from the radios of
  the songs you like most. A new one every Monday.
- **Monthly top**: what you played most in the last 30 days.
- **Describe a playlist**: "songs from Premam, rain songs and Ilaiyaraaja"
  looks up each part and takes their songs in turn, topped up from each
  part's radio.

**Fades**: each song fades out over its last seconds and the next fades in
(3 seconds by default; *Look & settings → Between songs* on Omarchy,
*Settings → Playback* in the app). In the app the next song is ready 25
seconds early and the two overlap (a true crossfade), and the next two songs
download in pieces while one plays, so a slow stream doesn't stop the music.
On Omarchy mpv plays one song at a time, so the fade out and the fade in
come one after the other rather than overlapping.

## Sound: equaliser, tone, balance and speed

A ten-band equaliser (31 Hz to 16 kHz, ±12 dB) with presets (Melody, Kuthu,
Bass boost, Rock, Late night and more, plus your own), a preamp, bass and
treble, left / right balance, and speed that keeps the pitch. "Keep loud
songs from clipping" (on by default) lowers the preamp by the biggest
boost, so a bass boost doesn't distort.

- **Omarchy**: the Sound page in the Paattu window (the equaliser button on
  the now-playing bar opens it). Drag a slider or knob, scroll over it, or
  double-click it to put it back; you hear it while you drag.
- **Windows and the Linux app**: Settings → Sound, or the equaliser button
  on Now playing. Same controls and presets.
- **Android**: the same page, played through the phone's own equaliser
  (usually five bands, so the curve is matched at those) and loudness
  enhancer. There's no balance on Android.

```
paattu sound                              # what's on
paattu sound presets
paattu sound preset melody                # turns the equaliser on
paattu sound set --band 1k=+2 --band 31=-1 --bass 3 --treble -1
paattu sound set --preamp -2 --balance -0.2 --speed 1.25 --noclip on
paattu sound save "Car"                   # keep the bands as your preset
paattu sound delete "Car"
paattu sound off | on | reset
```

Everything is one chain of FFmpeg `equalizer` filters in mpv, the only
audio filter the Windows libmpv has; the desktop engine and the Windows /
Linux app build the same chain from the same numbers
(`tests/sound_cases.json`).

## Customising (Spicetify-style)

Everything is a file that applies live, and everything can be set from the
command line:

```
paattu theme list
paattu theme set kanjeevaram            # or: omarchy (follows your Omarchy theme)
paattu config set desktop.style card    # vinyl | card | minimal
paattu config set desktop.position top-right
paattu config set desktop.workspace 1
paattu config set desktop.scale 1.2
paattu config set desktop.opacity 0.8
paattu config set videoBackground false # no video behind Now Playing
```

- **Themes** are JSON files in `~/.config/paattu/themes/` (`background`,
  `surface`, `foreground`, `muted`, `accent`, `highlight`). Seven ship with
  it: Kasavu, Kanjeevaram, Monsoon, Neelakurinji, Filter Coffee, Theyyam,
  Chembarathi.
  Copy one, edit the colours, and it appears in *Look & settings*.
- **Desktop widget:** right-click it to cycle styles, scroll for volume,
  middle-click to open the app. Hover for style / video / open buttons.
- **Bar widget:** label on/off, label width and scroll behaviour are in
  Omarchy's bar settings (or `omarchy bar set rajeevrama.paattu label none`).
  Click opens the panel, middle-click plays/pauses (or starts the first mix),
  right-click skips. In the panel, 1–9 start your mixes.

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
visualizer. Features worth bringing over next, natively: the 10-band EQ
presets (mpv `af` equalizer), the spectrum visualizer (cava), Radio Browser
stations (cliamp's history already has Anbu FM Malayalam, BIG 92.7, Big FM
Tamil), and synced lyrics (LRCLIB).

## Firewall (OpenSnitch)

OpenSnitch asks before a new program connects, and an unanswered prompt
becomes a permanent block after 30 seconds. `sudo ./install.sh --firewall`
adds one rule letting mpv and python (yt-dlp) reach only the music sites:
YouTube, JioSaavn and SoundCloud for search, plus Bandcamp, archive.org and
Audiomack for links. A link to any other site gets an OpenSnitch prompt the
first time. It also offers to remove the old rule that blocks cliamp.
`paattu play` warns (desktop notification) when the rule is missing. If you
added the rule before search existed, run it again to add the new sites.

## Roadmap (one feature at a time)

1. ✅ YouTube profiles (all their playlists) and playlist links; remove /
   restore playlists and songs; South Indian library
2. ✅ Favourites and your own playlists, from every now-playing view
3. ✅ Mixes: your own shuffle buttons (languages, profiles, playlists);
   starter library made optional
4. ✅ Search JioSaavn, YouTube and SoundCloud from the app and the bar; play
   or keep a song from any link; Saved songs; stream quality on now playing
5. ✅ Albums, artists and playlists in search, endless results, suggestions
   while typing; faster YouTube in the app
6. ✅ Sound: a ten-band equaliser with presets, preamp, bass, treble,
   balance and speed, on Omarchy, Windows, Linux and Android
7. ✅ A new look, and the song's video softly blurred behind Now playing
8. ✅ Song radio, auto radio, Daily / Weekly / Monthly playlists, playlists
   from a description, fades between songs and songs downloaded ahead
9. A real spectrum visualizer on the widgets
10. Malayalam / Tamil radio stations (Radio Browser)
11. Synced lyrics in the app and on the desktop widget
12. Album-art accent colours (Spotify-style adaptive theme)

## Development

```
python3 -m unittest discover -s tests     # titles, library, search, seeds, cliamp export, config
node --test tests/*.test.mjs              # the plugin's Model.js
./install.sh --dev                        # use this checkout as the installed program
```

The app is in `app/` (Flutter, Dart): `lib/src/` has the library model
(a port of `paattu/library.py`), title cleaning (`titles.py`), the sources
(JioSaavn, YouTube via youtube_explode_dart, SoundCloud) and the player
(just_audio: ExoPlayer on Android, libmpv on Windows / Linux, with
audio_service for Android's media controls). Now Playing's silent video is
video_player on Android and media_kit_video on Windows / Linux. `lib/src/ui/`
holds the glass look (`glass.dart`). `app/test/` runs the same
title and track-id cases as `tests/`. With Flutter installed:

```
cd app && flutter pub get && flutter test && flutter run
```

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

Five rules learned the hard way:

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
