# Paattu on Linux and Omarchy: the `paattu` command and the plugin

The `paattu` command and its mpv engine run on any Linux. On [Omarchy](https://omarchy.org) the installer
also adds a bar control, a desktop widget and an app window. [Back to the README](../README.md).

## Install

You'll need [Git](https://git-scm.com); `install.sh` brings the rest.

```bash
# Clone this repository
$ git clone https://github.com/sudharamachandranrajeev/paattu.git

# Go into the repository
$ cd paattu

# Install (asks once for sudo to install mpv and python)
$ ./install.sh

# What's installed
$ ./install.sh --check

# Only with OpenSnitch: let mpv / yt-dlp reach the music sites
$ sudo ~/.local/lib/paattu/install.sh --firewall

# Remove it (--purge also removes your library)
$ ./install.sh --uninstall
```

`install.sh` works on Arch (and Omarchy, Manjaro, EndeavourOS, CachyOS), Debian, Ubuntu (and Mint,
Pop!_OS), Fedora, openSUSE, Void and Alpine. It installs **mpv** (and mpv-mpris for media keys) and
**python3** with your package manager, a current **yt-dlp** (from pacman on Arch, otherwise the
official release into `~/.local/bin`, since distro packages are usually too old for YouTube) and
**deno** (yt-dlp needs a JavaScript runtime for YouTube), then the program into
`~/.local/lib/paattu`, the `paattu` command, and an mpv engine service for systemd users. Nothing
else runs as root. `--yes` answers its questions; `--dev` links your checkout instead of copying it
(for working on Paattu; the bar plugin is still a copy, so run it again after `git pull`). Without
systemd, `paattu` starts mpv itself.

On Omarchy, open it with **Super+Shift+M**, the music icon in the bar, the widget on workspace 1, or
Super+Space → Paattu. Elsewhere, use the command: `paattu search mazha`,
`paattu play --lang Malayalam`, `paattu --help`.

## Download notes for the Linux app

* **Linux** – the AppImage brings its own mpv and uses your desktop's GTK 3 (`chmod +x` it and run
  it). The tarball (`…-linux-x64.tar.gz`) also needs mpv's library, libmpv.so.2 (`mpv` on Arch,
  `libmpv2` on Debian 12+ / Ubuntu 24.04+, `mpv-libs` on Fedora; on older systems use the AppImage).

## How it works (Linux / Omarchy)

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
  never loads it, so there's nothing to block. The video button opens the
  song's page in your default browser.
- **mpv as the engine.** mpv + yt-dlp is the most reliable YouTube audio path,
  and mpv-mpris makes media keys, the Omarchy OSD and the lock screen work
  for free. cliamp keeps its own role (see [cliamp](design.md#cliamp)).

## Firewall (OpenSnitch)

OpenSnitch asks before a new program connects, and an unanswered prompt
becomes a permanent block after 30 seconds. `sudo ./install.sh --firewall`
adds one rule letting mpv and python (yt-dlp) reach only the music sites:
YouTube, JioSaavn and SoundCloud for search, plus a few other music and
archive sites for links. A link to any other site gets an OpenSnitch prompt the
first time. It also offers to remove the old rule that blocks cliamp.
`paattu play` warns (desktop notification) when the rule is missing. If you
added the rule before search existed, run it again to add the new sites.
