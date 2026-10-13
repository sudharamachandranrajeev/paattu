#!/bin/bash
#
# Paattu: Malayalam & Tamil music from public YouTube playlists, built into
# Omarchy (bar control, home-workspace widget, app window, `paattu` command).
#
# Usage: ./install.sh              install / repair for your user (safe to re-run)
#        ./install.sh --check      show what's installed, change nothing
#        sudo ./install.sh --firewall
#                                  OpenSnitch: let the player reach YouTube
#
# Your user, no sudo:
#   ~/.local/bin/paattu                               -> ~/Work/paattu/bin/paattu
#   ~/.config/paattu/{config.json,themes/,mpv/}       settings, colour schemes, engine config
#   ~/.config/systemd/user/paattu-engine.service      headless mpv (started on demand)
#   ~/.local/share/applications/paattu.desktop        launcher entry
#   ~/.config/omarchy/plugins/rajeevrama.paattu       shell plugin (enabled in the bar)
#   ~/.local/share/paattu/, ~/.cache/paattu/          library and cover art
#
# --firewall (root): /etc/opensnitchd/rules/003-paattu-allow-youtube.json

set -euo pipefail

SRC=$(cd "$(dirname "$(readlink -f "$0")")" && pwd)
PLUGIN_ID=rajeevrama.paattu
RULE=/etc/opensnitchd/rules/003-paattu-allow-youtube.json
CLIAMP_DENY=/etc/opensnitchd/rules/deny-always-simple-usr-bin-cliamp.json

say() { printf '\033[1m%s\033[0m\n' "$*"; }
note() { printf '  %s\n' "$*"; }
have() { command -v "$1" >/dev/null 2>&1; }

check() {
  for pkg in mpv mpv-mpris yt-dlp yt-dlp-ejs deno python; do
    if pacman -Q "$pkg" &>/dev/null; then note "$(pacman -Q "$pkg")"; else note "$pkg: not installed"; fi
  done
  note "paattu command: $(command -v paattu || echo missing)"
  note "engine: $(systemctl --user is-active paattu-engine.service 2>/dev/null || true)"
  if have omarchy-shell; then
    note "plugin: $(omarchy-shell shell listPlugins 2>/dev/null | grep -o "\"$PLUGIN_ID\"[^}]*\"enabled\": *[a-z]*" | grep -o 'enabled": *[a-z]*' || echo unknown)"
  fi
  if [[ -e $RULE ]]; then note "firewall rule: $RULE"; else note "firewall rule: not installed (sudo $0 --firewall)"; fi
  [[ -e $CLIAMP_DENY ]] && note "note: OpenSnitch blocks cliamp ($CLIAMP_DENY)"
  if [[ -f ~/.local/share/paattu/shelf.json ]]; then
    note "library: $(python3 -c 'import json,sys; c=json.load(open(sys.argv[1]))["counts"]; print("%(users)d users, %(saved)d playlists, %(tracks)d songs" % c)' ~/.local/share/paattu/shelf.json)"
  else
    note "library: empty (Add from YouTube in the app, or: paattu import @handle)"
  fi
}

firewall() {
  if (( EUID != 0 )); then
    echo "Run with sudo: sudo $0 --firewall" >&2
    exit 1
  fi
  if [[ ! -d /etc/opensnitchd/rules ]]; then
    note "OpenSnitch isn't installed; nothing to do."
    return
  fi
  local now
  now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  say "Allowing the player to reach YouTube, JioSaavn and SoundCloud (OpenSnitch)"
  # mpv streams the audio; yt-dlp (python) resolves it, and searches and cover
  # art go through the paattu command (python). Only the hosts of the sites
  # Paattu searches, plus Bandcamp, archive.org and Audiomack for pasted links;
  # a link to any other site gets an OpenSnitch prompt the first time.
  cat >"$RULE" <<EOF
{
  "created": "$now",
  "updated": "$now",
  "name": "003-paattu-allow-youtube",
  "description": "Paattu: mpv and yt-dlp may reach YouTube, JioSaavn, SoundCloud, Bandcamp, archive.org and Audiomack (managed by ~/Work/paattu/install.sh)",
  "enabled": true,
  "precedence": true,
  "action": "allow",
  "duration": "always",
  "operator": {
    "type": "list",
    "operand": "list",
    "sensitive": false,
    "data": "",
    "list": [
      {
        "type": "regexp",
        "operand": "process.path",
        "sensitive": false,
        "data": "^/usr/bin/(mpv|python3(\\\\.[0-9]+)?)$",
        "list": null
      },
      {
        "type": "regexp",
        "operand": "dest.host",
        "sensitive": false,
        "data": "(^|\\\\.)(youtube\\\\.com|googlevideo\\\\.com|ytimg\\\\.com|youtu\\\\.be|ggpht\\\\.com|googleusercontent\\\\.com|youtube-nocookie\\\\.com|jiosaavn\\\\.com|saavn\\\\.com|saavncdn\\\\.com|soundcloud\\\\.com|soundcloud\\\\.cloud|sndcdn\\\\.com|bandcamp\\\\.com|bcbits\\\\.com|archive\\\\.org|audiomack\\\\.com)$",
        "list": null
      }
    ]
  }
}
EOF
  chmod 644 "$RULE"
  note "wrote $RULE"

  if [[ -e $CLIAMP_DENY ]]; then
    echo
    note "OpenSnitch also has a saved rule that blocks cliamp from the network:"
    note "  $CLIAMP_DENY"
    note "It was created on 2026-10-12 when a cliamp prompt timed out unanswered."
    note "Without it, OpenSnitch asks again the next time cliamp connects."
    read -r -p "  Remove it? [y/N] " answer
    if [[ ${answer,,} == y* ]]; then
      rm -f "$CLIAMP_DENY"
      note "removed"
    else
      note "kept"
    fi
  fi
}

case ${1:-} in
  --check) check; exit 0 ;;
  --firewall) firewall; exit 0 ;;
  "") ;;
  *) echo "usage: $0 [--check | --firewall]" >&2; exit 2 ;;
esac

if (( EUID == 0 )); then
  echo "Run without sudo (only --firewall needs it)." >&2
  exit 1
fi

say "Checking packages"
missing=()
for pkg in mpv mpv-mpris yt-dlp python; do pacman -Q "$pkg" &>/dev/null || missing+=("$pkg"); done
if (( ${#missing[@]} )); then
  note "missing: ${missing[*]} — install with: omarchy pkg add ${missing[*]}"
  exit 1
fi
pacman -Q yt-dlp-ejs &>/dev/null || note "recommended: yt-dlp-ejs + deno (YouTube's JS challenges): omarchy pkg add yt-dlp-ejs deno"
note "ok"

say "Installing the paattu command"
mkdir -p ~/.local/bin
ln -sfn "$SRC/bin/paattu" ~/.local/bin/paattu
note "~/.local/bin/paattu"

say "Installing the engine"
mkdir -p ~/.config/paattu/mpv ~/.config/systemd/user
install -m 644 "$SRC/engine/mpv.conf" ~/.config/paattu/mpv/mpv.conf
install -m 644 "$SRC/engine/paattu-engine.service" ~/.config/systemd/user/paattu-engine.service
systemctl --user daemon-reload
note "paattu-engine.service (starts when you press play)"

say "Installing colour schemes"
mkdir -p ~/.config/paattu/themes
for theme in "$SRC"/themes/*.json; do
  dest=~/.config/paattu/themes/$(basename "$theme")
  if [[ -e $dest ]]; then note "kept $(basename "$theme")"; else install -m 644 "$theme" "$dest"; note "added $(basename "$theme")"; fi
done
[[ -e ~/.config/paattu/config.json ]] || paattu config set theme omarchy >/dev/null

say "Adding Paattu to the app launcher"
mkdir -p ~/.local/share/applications ~/.local/share/icons/hicolor/scalable/apps
install -m 644 "$SRC/share/paattu.svg" ~/.local/share/icons/hicolor/scalable/apps/paattu.svg
install -m 644 "$SRC/share/paattu.desktop" ~/.local/share/applications/paattu.desktop
update-desktop-database ~/.local/share/applications 2>/dev/null || true
note "Super+Space → Paattu"

say "Enabling the shell plugin"
if [[ ! -f ~/.config/omarchy/plugins/$PLUGIN_ID/manifest.json ]]; then
  note "plugin files missing from ~/.config/omarchy/plugins/$PLUGIN_ID"
  exit 1
fi
omarchy-shell shell rescanPlugins >/dev/null 2>&1 || true
if grep -q "\"$PLUGIN_ID\"" ~/.config/omarchy/shell.json 2>/dev/null; then
  note "already in the bar"
else
  omarchy plugin enable "$PLUGIN_ID" --section right --before rajeevrama.dual-headphones 2>/dev/null \
    || omarchy plugin enable "$PLUGIN_ID" --section right
  note "bar: right section, next to the audio controls"
fi

echo
say "Done"
note "Open: Super+Shift+M, the bar's music icon, or the widget on workspace 1."
note "Command line: paattu --help"
[[ -s ~/.local/share/paattu/shelf.json ]] || note "Add music: Add from YouTube in the app (a profile @handle or a playlist link)."
if [[ -d /etc/opensnitchd/rules && ! -e $RULE ]]; then
  echo
  note "OpenSnitch is on: before the first song, let the player through so a"
  note "prompt can't time out into a permanent block:"
  note "  sudo $SRC/install.sh --firewall"
elif [[ -r $RULE ]] && ! grep -q saavn "$RULE"; then
  echo
  note "The OpenSnitch rule only covers YouTube. For search (JioSaavn, SoundCloud)"
  note "and pasted links, update it:"
  note "  sudo $SRC/install.sh --firewall"
fi
