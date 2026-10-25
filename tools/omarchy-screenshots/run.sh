#!/usr/bin/env bash
# Screenshots of the Omarchy plugin for the README, drawn offscreen (nothing
# shows on screen and nothing reaches the network):
#
#     tools/omarchy-screenshots/run.sh OUT_DIR
#
# It builds a throwaway Quickshell config (the plugin, Omarchy's Commons and
# Ui), a made-up library with drawn covers (make_data.py) and a private mpv
# with no audio output playing a local tone under YouTube-shaped ids, then
# shell.qml opens the app window's pages and the desktop widget's styles and
# saves each as a PNG. A stub `paattu` on PATH answers the plugin's commands.
# Needs quickshell, Omarchy's shell (/usr/share/omarchy/shell), mpv, ffmpeg,
# ImageMagick and python3. The software renderer draws no rounded corners on
# covers (no layer effects); the real shell does.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
repo=$(cd "$here/../.." && pwd)
out=$(mkdir -p "${1:?usage: run.sh OUT_DIR}" && cd "$1" && pwd)
work=$(mktemp -d)
# mpv's socket path must stay under 108 bytes, so the runtime folder is short.
runtime=${PAATTU_SHOTS_RUNTIME:-$(mktemp -d /tmp/pshots.XXXXXX)}
mpv_pid=
cleanup() {
  [ -n "$mpv_pid" ] && kill "$mpv_pid" 2>/dev/null || true
  rm -rf "$work"
  [ -z "${PAATTU_SHOTS_RUNTIME:-}" ] && rm -rf "$runtime"
  return 0
}
trap cleanup EXIT

export XDG_DATA_HOME=$work/data XDG_CONFIG_HOME=$work/config XDG_CACHE_HOME=$work/cache XDG_RUNTIME_DIR=$runtime
mkdir -p "$work/root/Ui" "$work/bin" "$work/songs" "$XDG_CONFIG_HOME/paattu/themes" "$runtime/paattu"
chmod 700 "$runtime"

# The Quickshell config: the plugin next to Omarchy's Commons and Ui (with no
# layer-shell keyboard panel, which the offscreen platform can't make).
cp -r "$repo/plugin" "$work/root/paattu"
cp "$here/shell.qml" "$work/root/shell.qml"
ln -s /usr/share/omarchy/shell/Commons "$work/root/Commons"
for f in /usr/share/omarchy/shell/Ui/*; do ln -s "$f" "$work/root/Ui/"; done
rm "$work/root/Ui/KeyboardPanel.qml"
printf 'import QtQuick\nItem {}\n' > "$work/root/Ui/KeyboardPanel.qml"
printf '#!/bin/sh\necho "{\\"event\\": \\"done\\"}"\n' > "$work/bin/paattu"
chmod +x "$work/bin/paattu"

# Settings, themes, the library and its covers.
cp "$repo"/themes/*.json "$XDG_CONFIG_HOME/paattu/themes/"
cat > "$XDG_CONFIG_HOME/paattu/config.json" <<'EOF'
{"theme": "chembarathi", "videoBackground": false, "coverDepth": false, "desktop": {"style": "card"},
 "sound": {"on": true, "preset": "melody", "bands": [-2, -1.5, -1, 0.5, 2, 3.5, 3.5, 2, 0.5, -0.5],
           "bass": 2, "treble": 1}}
EOF
queue=$(PYTHONPATH=$repo python3 "$here/make_data.py")

# The songs: one quiet tone, linked under names whose absolute path carries
# "?v=<id>", which the plugin reads as that song's id.
ffmpeg -loglevel error -y -f lavfi -i "sine=frequency=220:duration=261" -af volume=0.05 \
  -c:a libopus -b:a 160k "$work/songs/song.webm"
files=()
for id in $(python3 -c 'import json, sys; print(" ".join(json.loads(sys.argv[1])))' "$queue"); do
  ln -s song.webm "$work/songs/song?v=$id"
  files+=("song?v=$id")
done
sock=$runtime/paattu/mpv.sock
(cd "$work/songs" && exec mpv --no-config --idle=yes --ao=null --vid=no --volume=80 --msg-level=all=error \
  --input-ipc-server="$sock" --start=107 "${files[@]}") &
mpv_pid=$!
for _ in $(seq 50); do [ -S "$sock" ] && break; sleep 0.1; done

OUT=$out PATH=$work/bin:$PATH QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software \
  timeout 120 quickshell -p "$work/root" 2>&1 | grep -iE "error|step" || true
ls "$out"
