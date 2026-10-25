# Changelog

## 0.14.0 — A fifteen-band equaliser that lands where you put it

Which file: the same as before (`Paattu-0.14.0-android.apk`,
`Paattu-0.14.0-windows-x64-setup.exe`, the AppImage or the tarball). On
Omarchy, `git pull`, then `./install.sh`, then `omarchy restart shell`.

- **Fifteen bands.** The equaliser has the ISO 2/3-octave bands, from 25 Hz
  to 16 kHz, on every platform and on `paattu sound` (`--band 1.6k=+2`).
- **Each slider is what you hear.** Band filters overlap, so before, a curve
  could come out far louder than its sliders (all ten at +12 dB gave about
  +18.5 dB) and one band lifted its neighbours. Now the filters' gains are
  worked out so the sound lands within about half a dB of every slider, and
  the curve drawn behind them is the one you hear.
- **Fine tuning.** Hold Shift while dragging or scrolling a band (or turn on
  *Fine steps* in the app) to move it in tenths of a dB.
- **Your sound stays the same.** Ten-band settings and your own presets
  become the fifteen levels they gave, and the built-in presets were carried
  over the same way.

## 0.13.0 — Lyrics over the cover

Which file: the same as before (`Paattu-0.13.0-android.apk`,
`Paattu-0.13.0-windows-x64-setup.exe`, the AppImage or the tarball). On
Omarchy, `git pull`, then `./install.sh`, then `omarchy restart shell`.

- **Lyrics.** The line being sung shows over the top of the cover on Now
  Playing, popping out of it in 3D and filled with the cover's colours moving
  slowly through the letters. Under it is how it sounds in English letters,
  for Malayalam, Tamil, Hindi, Telugu and Kannada. The words come from LRCLIB
  (timed, in the song's own script) or YouTube Music.
- **The Lyrics button** on Now Playing shows all the words in place of Up
  next, the line being sung lit up.
- **Settings › Lyrics** turns the words over the cover on or off, picks how
  each line comes in (3D, fade or plain), and turns the moving colours and
  the English letters on or off.
- **About the song.** A bar just above Up next has the film and year, the
  singers and composer, the language, the label, the quality, the site and
  the plays (Settings › Now Playing › About the song).
- **`paattu lyrics`** prints a song's words with their times.

## 0.12.0 — Recommendations that learn, charts, and music with no internet

Which file: the same as before (`Paattu-0.12.0-android.apk`,
`Paattu-0.12.0-windows-x64-setup.exe`, the AppImage or the tarball). On
Omarchy, `git pull`, then `./install.sh`, then `omarchy restart shell`; from
now on the Paattu window offers each update itself.

- **No mixes to start with.** A new library has no *Malayalam mix* or *Tamil
  mix*; *Make a mix* makes your own. The two a library used to start with are
  taken away unless you changed them. Mixes you made stay.
- **Only songs played to the end count as yours.** A song joins *Played in
  Malayalam / Tamil* and is kept on the device once you've heard 90% of it
  (or all but its last 20 seconds). A song you skip the first time it plays
  isn't kept, and the radio and the playlists made for you leave it out.
- **The radio learns what you like.** Songs by the singers and composers, and
  from the films, you play to the end come first; ones you skip drop back;
  and a couple of your favourites like the station's song join it.
- **Charts.** Home has the week's *Top* (JioSaavn's weekly top 50 with
  YouTube Music's top weekly videos where it has them), *Most searched* and
  *Love songs* for Malayalam, Tamil, Hindi, Telugu, Kannada and Punjabi.
  Settings › Charts picks the languages in the app; on Omarchy they follow
  your languages (`paattu charts`).
- **Music with no internet.** When a song won't play because the internet
  has gone, the songs kept on the device play instead.
- **Home › On this device** (*On this computer* on Omarchy) plays or
  shuffles the kept songs, shows the newest and opens the full list.
- **Kept songs on Omarchy.** Songs you play to the end are downloaded into
  `~/.local/share/paattu/offline` (2 GB, least recently played go first) and
  play from there; the *On this computer* page and `paattu offline` manage
  them. The folder's index is the app's, so it can be copied between them.
- **Updates ask at start.** The app looks for a newer Paattu each time it
  starts and asks whether to install it. The Omarchy window does the same
  when it opens (`paattu update`, `paattu update apply`).

## 0.11.2 — Sidebar fits short windows (Omarchy)

- On a short Omarchy app window the sidebar menu no longer runs under the
  library counts at the bottom; it scrolls instead.

## 0.11.1 — ListenBrainz says why

- When ListenBrainz turns plays away, Paattu shows its reason instead of
  "didn't accept the token". The usual one: a MetaBrainz account whose email
  isn't verified yet (verify it at metabrainz.org/profile, then sync again).

## 0.11.0 — Plays follow you across devices (ListenBrainz)

Which file: the same as before (`Paattu-0.11.0-android.apk`,
`Paattu-0.11.0-windows-x64-setup.exe`, the AppImage or the tarball). On
Omarchy, `git pull`, then `./install.sh`, then `omarchy restart shell`.

- **Scrobble to ListenBrainz, and every device shares what you play.** Settings
  › Sync between devices (the app) or Look & settings (Omarchy; or `paattu
  listenbrainz login`) takes your ListenBrainz user token. After that each
  song you hear properly (half of it, or four minutes: ListenBrainz's own rule)
  is sent as a listen with the song itself in it, and each device reads the
  others' plays back into its own history. So the daily, weekly and monthly
  playlists, the radio and the *Played in Malayalam / Tamil* playlists follow
  you from phone to desktop to Omarchy. It syncs at start, after each play and
  when the app comes back. Plays already in the history are sent when you
  connect. Listens from other players are left alone.
- **ListenBrainz listening history is public.** Playlists, favourites and mixes
  don't go through it (ListenBrainz playlists need MusicBrainz IDs that most
  YouTube and JioSaavn songs don't have); move those with Export / Import.
- The token is kept in the app's settings, or in
  `~/.config/paattu/listenbrainz.json` (readable only by you) on Omarchy.
  *Stop scrobbling* forgets it; the listens stay on ListenBrainz.

## 0.10.0 — Mixes that grow as you listen, and a cover that moves with the music

Which file: the same as before (`Paattu-0.10.0-android.apk`,
`Paattu-0.10.0-windows-x64-setup.exe`, the AppImage or the tarball). On
Omarchy, `git pull`, then `./install.sh`, then `omarchy restart shell`.

- **The Malayalam and Tamil mixes take in what you play.** A song listened to
  properly (half of it, or 30 seconds), from anywhere — a search, the radio,
  a link — goes to the front of its language's own playlist, *Played in
  Malayalam* or *Played in Tamil* (the last 300), which is in that
  language's mix. The language is the song's own (JioSaavn says), else that
  of the library's playlists it is in, else what its title, film, channel
  and credits show; a song with none shows nothing. Delete the playlist and
  it isn't made again; take it out of the mix and it stays out. The same on
  Omarchy and in the app.
- **The cover in 3D moves with the song** (Settings › Cover in 3D): its
  subject swells and rises a little on each beat, while the picture behind
  breathes with the loudness, always inside the margin the lifted subject
  already covers, so the picture's own copy of it never shows. In the app
  the subject also glows softly at its edges on the beat, in the cover's
  colour; on Omarchy `paattu rhythm SONG` works the rhythm out (mpv decodes
  it in a couple of seconds) and keeps it in `~/.cache/paattu/rhythm`.

## 0.9.0 — Now Playing moves with the music

Which file: the same as before (`Paattu-0.9.0-android.apk`,
`Paattu-0.9.0-windows-x64-setup.exe`, the AppImage or the tarball). Omarchy's
Now Playing has no rings, so nothing changes there; `git pull` keeps the
version in step.

- The rings around Now Playing's play button follow the song: the inner ring
  swells with how loud it is, the outer ring and the glow kick on the beats,
  and the hardest beats send a ripple out. Paattu works out each song's
  rhythm once, from its file, and keeps it (a few kilobytes a song). The
  file is the one already downloaded ahead or kept on the device; the first
  song of a queue is downloaded for it, except with *Save data* on, when
  only songs already on the device move. The rings stay still while paused
  and when the system's animations are turned off.

## 0.8.2 — Media controls on Android, updates found, and a folder of your own

Which file: `Paattu-0.8.2-android.apk` (and the same Windows and Linux files
as before).

- Fixed: on Android there was no media notification, and so no lock-screen
  controls and nothing in launcher widgets (Niagara and the like). The
  release build's resource shrinking took out audio_service's button icons,
  which it looks up by name, and every playback update then failed with
  "You must specify an icon resource id to build a CustomAction". They are
  kept now, and the release's emulator check fails if that ever comes back.
- Fixed: *Check for updates* said it couldn't reach the releases. It asked
  GitHub for the "latest" release, which leaves out pre-releases — and every
  Paattu release is one. It reads the list now and takes the newest version.
- **Settings › On this device › Folder** works on Android too: pick any
  folder (the phone's Music folder, an SD card). Paattu asks for "All files
  access" first, since Android lets an app write only to its own folders
  without it, and checks it can write to the folder before using it.

## 0.8.1 — 0.8.0 that installs over 0.7.1 on Android

Which file: `Paattu-0.8.1-android.apk` (and the same Windows and Linux files
as before). Everything new is 0.8.0's, below.

- Fixed: Android said "App not installed as package appears to be invalid"
  for 0.8.0 over an older Paattu. Its build number (Android's versionCode)
  was the release run's number, which started again at 1 when the project
  moved to its new repository, and Android won't install a lower one over
  0.7.1's 16. It now comes from the version (0.8.1 is 801), so it only goes
  up.

## 0.8.0 — A sleep timer, songs kept on the device, and updates from inside the app

Which file: the same as before (`Paattu-0.8.0-android.apk`,
`Paattu-0.8.0-windows-x64-setup.exe`, the AppImage or the tarball). On
Omarchy, `git pull`, then `./install.sh --dev`, then `omarchy restart shell`
and `paattu engine restart` (the engine script has the sleep timer).

All three are in the app (Android, Windows, Linux). On Omarchy the sleep
timer is in too: a **Sleep** chip on Now Playing (each press goes 15, 30,
60 minutes, end of this song, off) and `paattu sleep 30|+5|end|off`. The kept
songs and the updater aren't on Omarchy yet.

What's new:
- **Sleep timer**: the moon button on Now Playing. Pick a while (5 to 90
  minutes) or *End of this song*, and Paattu quiets the song over 8 seconds
  and pauses. Pressing play during the fade-out carries on at full volume.
  The queue stays where it is, so play picks up from that song.
- **Songs kept on this device**: a song you listen to properly (half of it,
  or 30 seconds of a long one) is kept in a folder as you play it, so it
  plays later with no internet and no data. **Library › On this device**
  shows what's kept, how much room it takes, and plays or takes off any of
  it. A song's menu has **Keep on this device** for one you want now.
  Settings › On this device turns the automatic keeping off, moves the
  folder (not on Android, which keeps an app's folder to itself), and sets
  the room allowed — 2 GB by default, and past it the songs played least
  recently go first. The files are named `Singer - Song.m4a`, so the folder
  reads like a music collection to anything else that opens it.
- **Updates from inside the app**: Settings › About › *Check for updates*
  reads the releases on GitHub, shows what's new, then downloads the right
  file for this device, checks its SHA-256 against the release's
  `SHA256SUMS.txt`, and installs it — the system's installer on a phone, the
  setup program on Windows (Paattu closes so it can be replaced), and the
  AppImage replaced where it stands on Linux. It looks once a day by itself
  and says when something's there. A release that publishes no checksum
  isn't installed at all.

Good to know:
- Kept songs aren't kept when **Save data** is on: pulling whole songs down
  is what that setting is for avoiding.
- Kept songs are your copies for this device; the folder carries its own
  index (`paattu-offline.json`), so it can be moved or copied whole.
- The updates the app finds are the ones published on
  [Releases](../../releases). **The repository has to be public for the app
  to see them** — GitHub answers 404 to everyone else about a private one,
  so until it's public, checking for updates says it couldn't reach the
  releases and *Check for updates* keeps working only from a browser that's
  signed in.
- Fixed on Android: the music could stop once the screen locked, and the
  notification, lock-screen controls and launcher widgets (Niagara and the
  like) went missing. Between songs — loading the next one, or changing over
  in a crossfade — the player said "paused" for a moment, which took the
  media service out of the foreground; locked, some phones then froze the
  app, and Android doesn't let one back into the foreground from the
  background. Paattu now tells Android it's playing from play until pause.
  Wi-Fi is also held awake while music plays, the notification permission is
  asked for (Android 13+), and Paattu asks once to be left out of battery
  optimisation (Settings › Playback › *Play with the screen locked* asks
  again).
- Fixed: a song downloaded ahead of time could leave the app waiting on
  itself for ever, so the *next* song after it wasn't downloaded ahead
  either. Playback was unaffected, which is why it went unnoticed.
- The app's own version (Settings › About, and the head of the problem log)
  now comes from the build, and a test keeps it in step with `pubspec.yaml`.
  It had been saying 0.6.0 while the build was 0.7.1.

## 0.7.1 — 0.7.0, built for Windows again

Which file: the same as before (`Paattu-0.7.1-android.apk`,
`Paattu-0.7.1-windows-x64-setup.exe`, the AppImage or the tarball). On
Omarchy, `git pull`, then `./install.sh --dev` (the bar plugin is a copy, so
new Now Playing files only reach it this way), then `omarchy restart shell`.

0.7.0's builds were never published: its Windows build failed on GitHub's
newer Visual Studio (2026), which refuses the way the Windows media controls
(audio_service_win) are built. This release is 0.7.0 (below) with that fixed.

## 0.7.0 — Now Playing your way: four looks, the video behind the cover, its colours, and the cover in 3D

Which file: the same as before (`Paattu-0.7.0-android.apk`,
`Paattu-0.7.0-windows-x64-setup.exe`, the AppImage or the tarball). On
Omarchy, `git pull` (a `--dev` install), then `omarchy restart shell`.

What's new, in the app (Android, Windows, Linux) and on Omarchy alike:
- Settings › Now Playing › Look chooses how Now Playing looks. **Cover**, the
  new default, keeps the cover in front and plays the song's video, blurred,
  behind it. **Video first**: the cover fades away while the video plays. **Full picture** fills the page with the cover (or the video),
  sharp, with the song's details over it. **Record** puts the cover on a
  turning record.
- **Video blur**: how soft the video behind Now Playing is, from none to 100
  (30 by default).
- **Cover colours**: Now Playing and the player bar take their colours from
  the song's cover, changing slowly from one song to the next and keeping
  the theme dark or light. A cover with no colour to speak of (black and
  white, grey) keeps the theme's. Off by default.
- **Cover in 3D** (on by default): the cover leans towards the pointer (on a
  phone, as you tilt it) and drifts slowly when nothing moves it, and the
  people in it stand out of the picture, sharp and a little nearer, over the
  rest of the cover with their shadow on it. The subject is found on the
  device, never sent anywhere: by ML Kit on Android (Google Play services
  fetches its model the first time), by U²-Net's small model with ONNX
  Runtime on Windows and Linux, and on Omarchy by `paattu depth`, which runs
  the same model through uv (fetched the first time: about 35 MB). A cover
  without a clear subject only leans.
- Windows: the system's media controls (the media flyout by the volume,
  the keyboard's media keys) now show and control what's playing, as
  Android's and Linux's already did.

Good to know:
- The Windows and Linux downloads are bigger: they carry ONNX Runtime and
  the model.
- On Omarchy, Cover in 3D needs [uv](https://docs.astral.sh/uv/); without it
  the cover only leans.

## 0.6.2 — Songs play again on phones whose equaliser starts late, and the video behind Now Playing moves

Which file: the same as before (`Paattu-0.6.2-android.apk`,
`Paattu-0.6.2-windows-x64-setup.exe`, the AppImage or the tarball). On
Omarchy, `git pull` (a `--dev` install).

What's new:
- The video behind Now Playing now moves for far more songs. Many YouTube
  Music songs' own videos are "art tracks", their cover held still (about
  10 kbps where a real video runs at about 100), so the background looked
  like a blurred photo. Such a still now counts as no video, and YouTube is
  searched for the song's real video (a lyric or video song of about the
  same length; up to three are tried). In the app and on Omarchy alike.
- On a phone, Now Playing shows the cover with rounded corners on a
  blurred copy of itself that fills the sides. When the song's video comes
  on, the cover fades out of its way; for a song with no moving video on
  YouTube the cover stays.

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
