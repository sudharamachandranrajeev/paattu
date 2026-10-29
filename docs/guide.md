# Paattu feature guide

Everything below works the same in the app (Android, Windows, Linux) and on Omarchy unless it says
otherwise; the `paattu` commands are for Linux. [Back to the README](../README.md).

## All features at a glance

* **YouTube profiles and playlists** – paste a profile (a label, a composer, a friend) and every
  public playlist on it becomes a Paattu playlist; paste a playlist link for just that one.
* **Search everywhere** – JioSaavn (film albums, AAC up to 320 kbps), YouTube (Opus) and SoundCloud,
  with Songs / Albums / Artists / Playlists tabs, endless results and suggestions while you type, or
  paste a link to any site yt-dlp can play.
* **Favourites, Saved songs and your own playlists** – from every now-playing view; sync and
  refresh never touch them.
* **Mixes** – your own shuffle buttons made of languages, profiles and playlists; songs you play
  to the end join *Played in Malayalam / Tamil*, so the mixes grow as you listen.
* **Radio and playlists made for you** – song radio from YouTube, shaped by what you play
  and skip, auto radio when the queue runs out, Daily mix, Weekly discovery, Monthly top, and
  playlists from a description.
* **Charts** – the week's top songs, most searched and love songs for Malayalam, Tamil, Hindi,
  Telugu, Kannada and Punjabi, from JioSaavn and YouTube.
* **Now Playing with the song's video** – blurred, silent and in time behind the cover; four looks
  (cover, video first, full picture, record), colours from the cover, and the cover in 3D: its
  subject gliding over the picture in one piece (or its layers drifting) and moving with the song's rhythm.
* **Lyrics over the cover** – the line being sung pops out of the cover in 3D (or bursts in
  comic-book style, fills as it's sung, or glows in), filled with the cover's colours moving through it, with how it sounds in English letters under it (Malayalam,
  Tamil, Hindi, Telugu, Kannada); all the words in place of Up next, and a bar with the film, year,
  singers, language and plays.
* **Sound** – a fifteen-band equaliser (ISO 2/3-octave, each slider the level you get there) with presets (Melody, Kuthu, Bass boost, Late night…), preamp,
  bass, treble, balance and pitch-keeping speed, on every platform.
* **Fades and crossfades** – songs fade into each other; the app readies the next song 25 s early
  and downloads the next two in pieces.
* **Sleep timer** – minutes or *end of this song*, with an 8-second fade-out.
* **Your music in numbers** – plays, hours, most played songs, singers and films, the hour you
  listen most, and titles your listening earns (*Stuck on repeat*, *Night owl*, *Picky DJ*…), set
  beside this week's charts in your languages and what the whole ListenBrainz community plays.
* **Songs kept on this device** – songs you play to the end are kept for playing offline
  (2 GB by default, least recently played go first), and take over when the internet goes.
* **Plays follow you (ListenBrainz)** – scrobbles carry your history between the phone, the
  desktop app and Omarchy, so made-for-you playlists follow you.
* **No ads, no third-party proxies** – streams come straight from the sites; Paattu never loads
  YouTube's player page and never scrapes mp3 download sites.
* **Omarchy-native** – a bar widget with a panel, a desktop widget on workspace 1 (vinyl, card or
  minimal), an app window, media keys and the lock screen through MPRIS, seven themes
  (plain JSON files), and a `paattu` command for everything.
* **Updates from inside the app** – checked against each release's `SHA256SUMS.txt` before
  installing.

## Where songs come from in the apps

The apps search and play by themselves (no yt-dlp or mpv to install): JioSaavn songs at 320 kbps
AAC, YouTube's best audio (Opus), SoundCloud, and direct links to audio files. They have the same
library as the Linux command: Home with your mixes and shelves, Search, Library (your playlists,
YouTube profiles and playlists), Favourites, a queue and a now-playing screen, and the Paattu
themes.

Songs come from YouTube unless **Settings → Music from** says JioSaavn, SoundCloud or every site. A
song that won't play is tried another way, then as the same song on the other sites (best sound
first); if nothing works, the app says why in plain words and plays the next one. When something
goes wrong, **Settings → Problem log → Save the problem log** writes what the app tried and what
failed to a text file: attach it to an [issue](https://github.com/sudharamachandranrajeev/paattu/issues).

## Platform notes

* **Windows** – `Paattu-…-windows-x64-setup.exe` (Inno Setup) or `…-windows-x64-portable.zip`. The
  installer is not code signed yet, so Windows says "Windows protected your PC": choose **More
  info → Run anyway**. On Windows 11 the window's title bar takes the app's colours, and the song's
  cover's while Now Playing or the mini player shows it in them; Windows 10 gives it only a dark or
  light frame. Paattu runs once: opening it again brings the open one to the front.
* **Android** – `Paattu-…-android.apk`, with lock-screen and notification controls. Allow your
  browser or file manager to install unknown apps when asked.
* **Android TV** – `Paattu-…-android-tv.apk`, the same app on the TV's home screen, run with the
  remote. A TV keeps no songs offline unless you turn it on (512 MB when you do), readies three
  songs ahead instead of eight and keeps fewer pictures in memory.

## YouTube profiles and their public playlists

Paste a YouTube profile (a label, a composer, a friend) and **every public
playlist on it** becomes a playlist in Paattu. Paste a playlist link and just
that one is added. In the app, use **Add from YouTube** (top bar, home page,
or the bar panel). From a terminal:

```
paattu import @handle                     # a profile: all of its playlists
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

**Removing things**

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

**The optional starter library**

A new library is empty: add the profiles and playlists you want. If you'd
rather start with a ready-made South Indian library, `paattu seed` follows
27 verified channels of Malayalam and Tamil film music labels and composers
(listed in `paattu/seeds.py`) and saves about four playlists from each.

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
JioSaavn, YouTube, SoundCloud, other music and archive sites, or a plain
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
paattu search "rain song"                       # where the music comes from (search.sites)
paattu search --site jiosaavn --limit 20 mazha
paattu search 'https://www.jiosaavn.com/album/…'   # what's at a link
paattu browse search --kind album SINGER        # songs, albums, artists or playlists, a page at a time
paattu browse search --kind song --after '{"youtube": "…"}' SINGER   # the next page
paattu browse suggest mazh                      # what the search box suggests
paattu browse open '{"type": "artist", "site": "jiosaavn", "id": "455", …}'   # an item from browse search
paattu play SONG                                # an id from a search, or any song link
paattu add [--next] SONG
paattu save SONG | paattu fav SONG
paattu playlist add-songs "Night drive" SONG
```

Songs from other sites get ids made from their page address
(`jiosaavn.com_song_<song-name>_<id>`). The last 400
search results are remembered in `~/.cache/paattu/search.json`, so their ids
work after the search. A song you save, heart or add to a playlist is copied
into `library.json`. Search settings are in `paattu config`:
`search.sites` (`["youtube"]`, or any of jiosaavn, youtube, soundcloud) and
`search.limit`.

## Mixes (the shuffle buttons)

The shuffle buttons on the bar panel, the desktop widget and Home are
**mixes**, and you choose what goes in them. A new library starts with none:
*Make a mix* on Home (or **Mixes** in the sidebar) makes one, and you can
rename, change, reorder or delete them and add as many as you like. Songs you
play to the end (90% of them, or all but the last 20 seconds), from anywhere,
go into *Played in Malayalam* or *Played in Tamil* (by the song's language),
playlists you can put in a mix, so it grows as you listen. A mix shuffles
everything in it:

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
paattu mix new "Night drive" --user @handle --playlist favourites
paattu mix add "Night drive" --lang Tamil --playlist 'https://www.youtube.com/playlist?list=…'
paattu mix drop "Night drive" --lang Tamil
paattu mix rename "Night drive" "Kollywood"
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
A mix you delete stays deleted. Libraries from before 0.12 started with a
*Malayalam mix* and a *Tamil mix*; 0.12 takes those away unless you changed
them.

## Playing, Now Playing looks and the cover in 3D

```
paattu play --mix "Night drive"         # a shuffle button (see Mixes)
paattu play --lang Malayalam            # shuffled mix of the saved Malayalam playlists
paattu play PL… [--shuffle] [--index 3]
paattu play --user @handle
paattu toggle | next | prev | seek +10 | volume 60 | shuffle | repeat
paattu status | queue | jump 5
paattu watch                            # this song's video in your browser, audio pauses
paattu video SONG                       # where to stream its small, silent video
paattu depth SONG                       # its cover's depth map, for the cover in 3D
paattu rhythm SONG                      # its loudness and beats (the cover in 3D moves with them)
```

Now Playing (in the app, and on Omarchy from the sidebar or by clicking the
song in the player bar) shows the song's video behind it, blurred, silent
and kept in time with the music: the smallest H.264 picture, about 1 MB a
minute. A YouTube song whose own video is only its cover held still
(an "art track"), and JioSaavn and SoundCloud songs, use a YouTube video of
about the same length found by search (a lyric or video song) when there is
one. On Omarchy it needs Qt Multimedia (`qt6-multimedia-ffmpeg`); turn it off
with `paattu config set videoBackground false` or in *Look & settings*.

Settings › Now Playing chooses how it looks, the same in the app (Android,
Windows, Linux) and on Omarchy:

- **Cover** (the default): the cover stays, and the video plays blurred
  behind it.
- **Video first**: the cover fades away while the video plays.
- **Full picture**: the cover (or the video) fills the whole page, sharp,
  with the song's details over it.
- **Record**: the cover is the label of a turning record.

**Video mode** (the Audio | Video switch at the top of Now Playing) plays
the song's video sharp, with its own sound. The video fills its card with no
black bars, its edges melt into the page, and it leans a little and swells
on the beat like the cover in 3D.

**Video blur** sets how soft the video is, from none to 100 (30 by default).
**Cover colours** gives Now Playing and the player bar the colours of the
song's cover, changing slowly from one song to the next and keeping the
theme dark or light. **Cover in 3D** (on by default) tilts the cover towards
the pointer (on a phone, as you tilt it), drifting slowly when nothing moves
it, and gives the picture depth. Nothing is cut out: a soft map of how near
each point of the cover is moves it as it leans (one shader, the same in the
app and on Omarchy), so the people in it glide over what is behind them in
one piece, catching the light, their shadow sliding on the picture behind.
On the beat the near parts swell a little and the rest breathes with the
loudness. A cover without anyone in it is taken apart into the few colours
it is made of, each a layer (nearer the more central, colourful and away
from the edges it is), and the layers drift slowly past each other under a
slow sheen. The subject is found on the device: by a segmentation model on Android, and by
U²-Net's small model (`models/u2netp.onnx`, with ONNX Runtime) on Windows,
Linux and Omarchy. On Omarchy, `paattu depth` runs it through
[uv](https://docs.astral.sh/uv/), which fetches ONNX Runtime, NumPy and
Pillow (and Python 3.12 if needed) the first time: about 35 MB to download,
about 100 MB in uv's cache. Without uv (or on the software renderer) the
cover only tilts. Each cover's depth map is kept in
`~/.cache/paattu/depth/`.

The queue skips trailers and plays each song once even when a playlist has
both the video and the lyrical upload.

**About the song** (Settings › Now Playing, on by default) puts a bar just
above Up next: the film and year, the singers and composer, the language, the
label, the stream's quality, the site, its plays on the site and, in the app,
how many times you've played it.

## Lyrics

When the song's words can be found, the line being sung shows over the top
of the cover on Now Playing, with how it sounds in English letters under it
(for Malayalam, Tamil, Hindi, Telugu and Kannada). The **Lyrics** button
shows all the words in place of Up next, the line being sung lit up.

The words come from [LRCLIB](https://lrclib.net) or YouTube, in the
song's own script and timed line by line where they have them so. Words
timed to another upload of the song than the one playing (a music video with
a longer start, say) are put in step with it: the two uploads' loudness over
time is lined up and the lines moved by how far apart they are. Words that
can't be timed show only through the Lyrics button. The English letters are
worked out on the device from the script. What was found is kept for each
song; a song with no words is asked about again after three days, and one
looked up while a site was down after an hour.

Settings › Lyrics:

- **Over the cover** shows the line being sung (on by default).
- **Each line** comes in **popping out in 3D** (the default, with a glow of
  the song's colours, and bursting into them as it goes), as a **comic pop**
  (on a starburst, white letters outlined dark, popping away in a burst), as
  **karaoke** (filling with the colours as it's sung), **glowing in** (out of
  a blur, rising away into one), **fading in**, or **plain**. The colours are
  the ones Now Playing takes from the cover.
- **Cover's colours** fills the words with the cover's colours, moving slowly
  through them; off, they're one colour.
- **English letters** shows how each line sounds under it.

On Omarchy, `paattu lyrics [id]` prints the words of a song (the one playing
when no id is given) with their times; `--refresh` asks again.

## Sleep timer

The moon button on Now Playing stops the music by itself:

- a while from now — 5, 10, 15, 30, 45, 60 or 90 minutes;
- **End of this song**, which waits for the song playing to finish rather
  than cutting it off;
- **+5 min** to add to a countdown that's running, or *Turn off*.

When it's up Paattu quiets the song over 8 seconds and pauses, so nothing
stops mid-word. The queue stays where it is: press play in the morning and
it carries on from that song. Pressing play *during* the fade-out cancels it
and comes back to full volume. A song you skip doesn't end an *End of this
song* timer — you're still listening.

On Omarchy the **Sleep** chip on Now Playing goes 15, 30, 60 minutes, end of
this song, off with each press, and the command does the same:

```
paattu sleep 30      # pause in 30 minutes (8 s fade-out first)
paattu sleep +5      # 5 more minutes
paattu sleep end     # pause when this song finishes
paattu sleep off
paattu sleep         # what's set
```

The engine script (`engine/paattu.lua`) keeps the timer, so it runs whether
or not the bar is open. Pausing during the fade-out ends it.

## Songs kept on this device

A song you play to the end (90% of it, or all but the last 20 seconds) is
kept in a folder, so it plays later with no internet and no data. The library
builds itself out of what you listen to, rather than out of what you remember
to download. A song you skip the first time it plays isn't kept, and the
radio and the playlists made for you leave it out from then on.

When a song won't play because the internet has gone, Paattu plays the songs
kept here instead, shuffled (the app first tries the next kept song in the
queue).

- **Home › On this device** (the app) and **Home › On this computer**
  (Omarchy) play or shuffle them and show the newest; *See all* opens the
  list, which also takes a song off again.
- A song's menu has **Keep on this device**, for one you want now whether or
  not you've played it. The same menu takes it off.
- **Settings › On this device** turns the automatic keeping off, moves the
  folder, and sets the room allowed: **2 GB by default**, and past it the
  songs played *least recently* go first, so what you still listen to stays.
  On Omarchy the *On this computer* page has the same switches.

On Omarchy yt-dlp downloads them into `~/.local/share/paattu/offline`, and the
engine plays the file in place of the stream:

```
paattu offline                          # what's kept, and the room it takes
paattu offline keep current             # keep the song playing (or a link or id)
paattu offline drop SONG
paattu offline play [--shuffle]
paattu config set offline.autoSave false
paattu config set offline.limitMb 5120  # 0: no limit
paattu config set offline.dir ~/Music/Paattu
```

The files are named `Singer - Song.m4a` (or `.webm` for Opus, `.flac`,
`.mp3`), so the folder reads like a music collection to anything else that
opens it, and it carries its own index (`paattu-offline.json`) so the whole
folder can be moved or copied to another device. You can point it at any
folder you like (on Android, Paattu first asks for "All files access", which
writing outside its own folder needs; the phone's Music folder or an SD card
work).

Two things worth knowing:

- Kept songs aren't kept while **Save data** is on — pulling whole songs down
  is exactly what that setting avoids. Turn Save data off and keeping starts.
- A kept song plays from its file, so it needs no stream link and works
  offline. If a kept file turns out to be broken, Paattu forgets it and
  streams the song instead, rather than failing on it.

## Updates

**Settings › About › Check for updates** reads the [Releases](https://github.com/sudharamachandranrajeev/paattu/releases)
on GitHub, shows what's new in the version it found, then downloads the right
file for this device, checks its SHA-256 against the release's
`SHA256SUMS.txt`, and installs it:

| Where | What installing does |
|---|---|
| **Android** | hands the APK to the system's installer (allow "install unknown apps" when asked) |
| **Windows** | runs the setup program; Paattu closes so it can be replaced, and setup offers to start the new one |
| **Linux AppImage** | replaces the AppImage where it stands — open Paattu again to use the new one |
| **Linux tarball** | saves the AppImage to Downloads and says where, since Paattu can't replace an installed folder safely |

Each time the app starts it looks for a newer version by itself and, when
there is one, asks whether to install it (*Not now* leaves it in Settings). A download that doesn't match its checksum is thrown away, and
a release that publishes no checksum isn't installed at all — you can always
get it from the releases page instead.

On Omarchy the Paattu window asks the same way when it opens. *Update* pulls
a `--dev` checkout and runs its `install.sh --dev`, or downloads the release
and runs its `install.sh`; then *Restart the shell* loads the new window.

```
paattu update                           # is there a newer one?
paattu update apply                     # install it
paattu update rollback [VERSION]        # go back to an earlier one (else the one before this)
```

**Going back.** When a new version misbehaves, *Settings › About › Go back to
an earlier version* lists the earlier releases for this device and installs
the one you pick the same way, checked against its SHA-256. Your library,
plays and settings stay; 0.23.1 is the oldest offered, the first that reads
them as this one writes them. From 1.0.1 on, the version you went back to
doesn't offer the one you left as it starts (Settings still has it).
Android won't put an older version over a newer one,
so there it opens that release's page and says what to do: export the
library, uninstall Paattu, install the older APK and import the library
again. On Omarchy, `paattu update rollback` does it; a `--dev` install says
which tag to check out instead of moving your checkout.

**The repository has to be public for the app to see its releases.** GitHub
answers 404 to everybody else about a private one, so while it's private,
*Check for updates* reports that it couldn't reach the releases.

## Radio and playlists made for you

```
paattu radio start [SONG]               # songs like SONG (or the one playing), without end
paattu radio stop                       # the radio's songs still to come go
paattu radio remove N                   # take queue entry N out (the radio learns from it)
paattu radio taste                      # what the radio learned: singers, composers, films
paattu radio forgive by:NAME            # let one it leaves out back in (or film:NAME)
paattu made                             # Daily mix, Weekly discovery, Monthly top
paattu stats [--days 30]                # your music in numbers, and the titles it earned
paattu made daily --play [--refresh]    # play today's (--refresh: a new one)
paattu describe "old melodies, rain songs, FILM" --play [--save NAME]
paattu charts                           # the charts for your languages
paattu charts top Malayalam --play      # top / searched / love, then the language
paattu config set fade 3                # seconds a song fades out and the next in (0: off)
paattu config set autoRadio false       # don't carry on when the queue runs out
```

**Radio** (the *Start radio* button on Now Playing, in the app and on
Omarchy) plays songs like a song, from YouTube's own radio for it, a
helping at a time as the queue runs low. Like the radio on the big streaming
apps, it leaves out what you played in the last six hours and songs you skipped more
than once, and when one song's radio runs dry it carries on from a song it
played. With **auto radio** on (the default), any queue that runs out
carries on as a radio of its last song, unless repeat is on or you turned
the radio off. What you play shapes it: songs by the singers and composers,
and from the films, you play to the end come first, ones you skip drop back,
and a couple of your own favourites like the station's song join it.

**Taking a song out of the radio's Up next** (the cross on Up next, or a
swipe on the Queue page in the app) teaches it. That song is turned down
until you play it to the end. Its singers, composers and film count against
it, more than a skip does. One taken out three times in 90 days, and liked
less than skipped on the whole, is left out of the radio. *Settings ›
Playback › What the radio learned* (or `paattu radio taste`) ranks them all
by that score, and lets one back in.

**Each helping is ranked** before your taste orders it, best first:
1. songs you play again and again (two or more plays), most played first;
2. your favourites, and songs very like one (its film and a singer or
   composer);
3. songs in your other playlists, and songs from their films;
4. songs by a singer or composer you play a lot (three plays in 90 days);
5. songs of a theme you play a lot (love, sad, dance, devotional, calm,
   wedding, festival, rap, from the words in their titles);
6. songs in a language you play a lot;
7. then the rest, as YouTube gave them.

**Made for you** (on Home) comes from what you play: how long you listened
(a play counts after half a song or 30 seconds), how often, how lately
(a play is worth half as much a week later), your Favourites and Saved
songs, and what you skip.
- **Daily mix**: songs you love, two at a time, then one like them that's
  new to you. A new one every day.
- **Weekly discovery**: only songs you haven't played, from the radios of
  the songs you like most. A new one every Monday.
- **Monthly top**: what you played most in the last 30 days.
- **Charts**: the week's *Top* (JioSaavn's weekly top 50 and, where it has
  one, YouTube's top weekly music videos, taken in turn), *Most searched* and
  *Love songs* for each of your languages (Settings › Charts in the app).
  Fetched again every 12 hours, without the songs you turned down.
- **Describe a playlist**: "songs from a film, rain songs and a composer"
  looks up each part and takes their songs in turn, topped up from each
  part's radio.

**Your music in numbers** (*Your music in numbers* on Home in the app, *Your
numbers* in the Omarchy window's sidebar, `paattu stats`) counts the last
week, month, three months or all of it: plays, time listened, songs,
singers and composers, skips, the longest run of days, your most played
songs, singers and films, the hour you play most, and the themes and
languages. Your listening earns titles: *Stuck on repeat* (one song five
times or more), *Night owl*, *Itchy skip finger*, *Explorer* or *Creature of
habit*, *Picky DJ* (three songs taken out of the radio) and more. In the app,
*You and everyone else* sets you against this week's top songs in your
languages (how mainstream you are) and against the artists the whole
ListenBrainz community played most this month.

**Fades**: each song fades out over its last seconds and the next fades in
(3 seconds by default; *Look & settings → Between songs* on Omarchy,
*Settings → Playback* in the app). In the app the next song is ready 25
seconds early and the two overlap (a true crossfade), and the next two songs
download in pieces while one plays, so a slow stream doesn't stop the music.
On Omarchy mpv plays one song at a time, so the fade out and the fade in
come one after the other rather than overlapping.

## Sync plays between devices (ListenBrainz)

```
paattu listenbrainz login     # asks for your user token (listenbrainz.org/settings)
paattu listenbrainz sync      # send new plays, read the other devices' in
paattu listenbrainz status
paattu listenbrainz logout
```

Each song heard properly is scrobbled with the song in the listen's
`additional_info`, and the plays other Paattu installs (the app on Android,
Windows and Linux, and this one) scrobbled come back into
`~/.local/share/paattu/history.json`. Made-for-you playlists and the *Played
in ...* playlists are made from that history, so they follow you. Your
listening history on ListenBrainz is public. Playlists and favourites don't
sync this way (ListenBrainz playlists need MusicBrainz IDs); use the library
export and import for them.

## Sound: equaliser, tone, balance and speed

A fifteen-band equaliser (the ISO 2/3-octave bands: 25, 40, 63, 100, 160,
250, 400, 630 Hz, 1, 1.6, 2.5, 4, 6.3, 10 and 16 kHz, ±12 dB) with presets
(Melody, Kuthu, Bass boost, Rock, Late night and more, plus your own), a
preamp, bass and treble, left / right balance, and speed that keeps the
pitch. "Keep loud songs from clipping" (on by default) lowers the preamp by
the biggest boost, so a bass boost doesn't distort.

Each slider is the level the sound gets at its band, to within about half a
dB. Neighbouring band filters overlap, so setting each filter to its slider
would pile up (fifteen bands at +12 dB would give about +22 dB) and one band
would lift its neighbours. Paattu works out the filters' own gains instead:
it measures how each filter reaches the band centres and the points between,
and solves for the gains by least squares, twice (Välimäki and Liski's
*accurate cascade graphic equaliser*). The curve drawn behind the sliders is
what you hear. For fine tuning, hold Shift (or turn on *Fine steps* in the
app): the slider moves in tenths of a dB, a quarter as fast, from where it is.

Settings from before 0.14 had ten bands. They become the fifteen levels
those ten filters gave, so the sound stays as it was; the built-in presets
were carried over the same way.

- **Omarchy**: the Sound page in the Paattu window (the equaliser button on
  the now-playing bar opens it). Drag a slider or knob, scroll over it, or
  double-click it to put it back; you hear it while you drag.
- **Windows and the Linux app**: Settings → Sound, or the equaliser button
  on Now playing. Same controls and presets.
- **Android**: the same page, played through the phone's own equaliser
  and loudness enhancer. That equaliser usually has five bands, so the
  fifteen-band curve is matched at those five. There's no balance on Android.

**Surround** (0–100%) widens the stereo: each side moves further from
what both share, up to 2.5 times at full (FFmpeg's `extrastereo`). With
*Keep loud songs from clipping* on, the preamp also leaves room for a sound
panned hard one way. On Android it is the phone's own virtualizer at that
strength (stock Android's is open source; some phone makers ship their
own, and some apply it only on headphones). Commercial surround formats can't
be added to an app: they are licensed to phone and PC makers, and the songs
are plain stereo. Where your phone or PC has them, they work on Paattu too.

```
paattu sound                              # what's on
paattu sound presets
paattu sound preset melody                # turns the equaliser on
paattu sound set --band 1k=+2 --band 1.6k=+1.5 --band 25=-1 --bass 3 --treble -1
paattu sound set --preamp -2 --balance -0.2 --speed 1.25 --noclip on
paattu sound set --surround 0.4                # 0 (none) … 1 (full)
paattu sound save "Car"                   # keep the bands as your preset
paattu sound delete "Car"
paattu sound off | on | reset
```

Everything is one chain of FFmpeg filters in mpv (`equalizer`, and
`extrastereo` for the surround); the desktop engine and the Windows /
Linux app build the same chain from the same numbers
(`tests/sound_cases.json`). media_kit's Windows libmpv has only
`equalizer`, so the Windows app ships shinchiro's full libmpv build
instead, pinned in [paattu-libmpv](https://github.com/sudharamachandranrajeev/paattu-libmpv).

## Customising (themes, desktop widget, bar)

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
paattu config set nowPlayingStyle record  # cover | video | full | record
paattu config set videoBlur 50          # 0 (sharp) to 100
paattu config set coverColors true      # Now Playing in the cover's colours
paattu config set coverDepth false      # a flat cover in Now Playing
paattu config set songInfo false        # no bar about the song above Up next
paattu config set lyrics.show false     # no words over the cover
paattu config set lyrics.effect fade    # 3d | comic | karaoke | glow | fade | plain
paattu config set lyrics.gradient false # the words in one colour
paattu config set lyrics.transliterate false  # no English letters under them
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

## More screenshots

All screenshots show a made-up library with drawn covers.

<table>
  <tr>
    <td align="center"><img src="screenshots/app-playlist-dark.png" alt="Your playlist" width="200"><br><sub>Your playlist</sub></td>
    <td align="center"><img src="screenshots/app-settings-dark.png" alt="Settings: the themes" width="200"><br><sub>Settings: the themes</sub></td>
    <td align="center"><img src="screenshots/app-home-light.png" alt="Home in the light Kasavu theme" width="200"><br><sub>Home (Kasavu, light)</sub></td>
    <td align="center"><img src="screenshots/app-now-playing-light.png" alt="Now Playing in the Kasavu theme" width="200"><br><sub>Now Playing (Kasavu)</sub></td>
  </tr>
</table>

<p align="center">
  <img src="screenshots/app-home-desktop.png" alt="Home on a desktop window" width="80%"><br>
  <sub>Home on a desktop window</sub>
</p>

**On Omarchy** (the app window and the desktop widget):

<table>
  <tr>
    <td align="center"><img src="screenshots/omarchy-playlist.png" alt="A playlist" width="420"><br><sub>A playlist</sub></td>
    <td align="center"><img src="screenshots/omarchy-sound.png" alt="Sound" width="420"><br><sub>Sound</sub></td>
  </tr>
  <tr>
    <td align="center"><img src="screenshots/omarchy-mixes.png" alt="Mixes" width="420"><br><sub>Mixes</sub></td>
    <td align="center">
      <img src="screenshots/omarchy-desktop-card.png" alt="Card desktop widget" width="150">
      <img src="screenshots/omarchy-desktop-vinyl.png" alt="Vinyl desktop widget" width="250"><br>
      <img src="screenshots/omarchy-desktop-minimal.png" alt="Minimal desktop widget" width="250"><br>
      <sub>Desktop widget: card, vinyl, minimal</sub>
    </td>
  </tr>
</table>
