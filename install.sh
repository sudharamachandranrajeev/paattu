#!/usr/bin/env bash
#
# Paattu: Malayalam & Tamil music from YouTube, JioSaavn, SoundCloud and any
# link. Installs the `paattu` command and its player engine (mpv + yt-dlp) on
# any Linux distro, and on Omarchy also the bar control, the home-workspace
# widget and the app window.
#
# Usage: ./install.sh              install or update for your user (safe to re-run)
#        ./install.sh --yes        don't ask before installing packages
#        ./install.sh --dev        run Paattu from this checkout (for working on it)
#        ./install.sh --check      show what's installed, change nothing
#        ./install.sh --uninstall  remove Paattu; your library and settings stay
#        ./install.sh --uninstall --purge
#                                  remove the library, settings and cover art too
#        sudo ./install.sh --firewall
#                                  OpenSnitch: let the player reach the music sites
#
# Packages, through your package manager (asks for sudo): mpv, mpv-mpris (media
# keys), python3, and on Arch-based distros qt6-multimedia-ffmpeg (the Omarchy
# app's video behind Now Playing). There yt-dlp and deno come from pacman too;
# elsewhere they come from their official GitHub releases into ~/.local/bin,
# since distro yt-dlp is usually too old for YouTube. Supported: Arch (and
# Omarchy, Manjaro, EndeavourOS, CachyOS), Debian, Ubuntu (and Mint, Pop!_OS),
# Fedora, openSUSE, Void and Alpine.
#
# Your user, no sudo:
#   ~/.local/lib/paattu/                              the program (a link to this checkout with --dev)
#   ~/.local/bin/paattu                               the command
#   ~/.config/paattu/{config.json,themes/,mpv/}       settings, colour schemes, engine config and script
#   ~/.config/systemd/user/paattu-engine.service      headless mpv, started on demand (with systemd)
#   ~/.local/share/paattu/, ~/.cache/paattu/          library and cover art
# On Omarchy, also:
#   ~/.config/omarchy/plugins/rajeevrama.paattu       shell plugin (enabled in the bar)
#   ~/.local/share/applications/paattu.desktop        launcher entry
#
# --firewall (root): /etc/opensnitchd/rules/003-paattu-allow-youtube.json

set -euo pipefail

SRC=$(cd "$(dirname "$(readlink -f "$0")")" && pwd)
REPO_URL=https://github.com/sudharamachandranrajeev/paattu
PLUGIN_ID=rajeevrama.paattu
RULE=/etc/opensnitchd/rules/003-paattu-allow-youtube.json
CLIAMP_DENY=/etc/opensnitchd/rules/deny-always-simple-usr-bin-cliamp.json

XDG_CONFIG=${XDG_CONFIG_HOME:-$HOME/.config}
LIB=$HOME/.local/lib/paattu
BIN=$HOME/.local/bin
CONFIG=$XDG_CONFIG/paattu
DATA=${XDG_DATA_HOME:-$HOME/.local/share}/paattu
CACHE=${XDG_CACHE_HOME:-$HOME/.cache}/paattu
UNIT_DIR=$XDG_CONFIG/systemd/user
UNIT=paattu-engine.service
PLUGIN_DIR=$XDG_CONFIG/omarchy/plugins/$PLUGIN_ID
APPS=${XDG_DATA_HOME:-$HOME/.local/share}/applications
ICONS=${XDG_DATA_HOME:-$HOME/.local/share}/icons/hicolor/scalable/apps

YES=0 DEV=0 PURGE=0 ACTION=install

say() { printf '\033[1m%s\033[0m\n' "$*"; }
note() { printf '  %s\n' "$*"; }
warn() { printf '  \033[33m%s\033[0m\n' "$*"; }
die() { printf '\033[31m%s\033[0m\n' "$*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }
# The first line a command prints (no pipe into head: with pipefail, SIGPIPE reads as failure).
first_line() {
  local out
  out=$("$@" 2>/dev/null) || return 1
  printf '%s\n' "${out%%$'\n'*}"
}

# ---------------------------------------------------------------- distro

# The package manager, from /etc/os-release (ID, then ID_LIKE), else whichever is there.
detect_pm() {
  local ids=""
  # shellcheck source=/dev/null
  [[ -r /etc/os-release ]] && ids=$(. /etc/os-release && echo " ${ID:-} ${ID_LIKE:-} ")
  case $ids in
    *" arch "* | *" archarm "* | *" manjaro "* | *" endeavouros "* | *" cachyos "* | *" omarchy "*) echo pacman ;;
    *" debian "* | *" ubuntu "*) echo apt ;;
    *" opensuse"* | *" suse "* | *" sles "*) echo zypper ;;
    *" fedora "* | *" rhel "* | *" centos "*) echo dnf ;;
    *" void "*) echo xbps ;;
    *" alpine "*) echo apk ;;
    *)
      local pm
      for pm in pacman apt-get zypper dnf xbps-install apk; do
        if have "$pm"; then
          case $pm in apt-get) echo apt ;; xbps-install) echo xbps ;; *) echo "$pm" ;; esac
          return
        fi
      done
      echo unknown ;;
  esac
}

# Package names: what Paattu needs, then what's nice to have (installed one by
# one, so a name a distro doesn't carry can't stop the rest).
required_packages() {
  case $1 in
    pacman) echo "mpv python yt-dlp" ;;
    apt) echo "mpv python3 ca-certificates" ;;
    dnf | zypper | xbps) echo "mpv python3" ;;
    apk) echo "mpv python3 ca-certificates" ;;
  esac
}
optional_packages() {
  case $1 in
    pacman) echo "mpv-mpris deno yt-dlp-ejs qt6-multimedia-ffmpeg" ;;
    apt | dnf | xbps | apk) echo "mpv-mpris" ;;
    zypper) echo "mpv-plugin-mpris" ;;
  esac
}

installed() {
  case $1 in
    pacman) pacman -Q "$2" &>/dev/null ;;
    apt) dpkg-query -W -f='${Status}' "$2" 2>/dev/null | grep -q "ok installed" ;;
    dnf | zypper) rpm -q "$2" &>/dev/null ;;
    xbps) xbps-query "$2" &>/dev/null ;;
    apk) apk info -e "$2" &>/dev/null ;;
    *) return 1 ;;
  esac
}

# Install packages as root (already confirmed): `pm_install PM PKG...`
pm_install() {
  local pm=$1
  shift
  local sudo=()
  (( EUID == 0 )) || sudo=(sudo)
  case $pm in
    pacman) "${sudo[@]}" pacman -S --needed --noconfirm "$@" ;;
    apt) "${sudo[@]}" env DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "$@" ;;
    dnf) "${sudo[@]}" dnf install -y "$@" ;;
    zypper) "${sudo[@]}" zypper --non-interactive install --no-recommends "$@" ;;
    xbps) "${sudo[@]}" xbps-install -Sy "$@" ;;
    apk) "${sudo[@]}" apk add "$@" ;;
  esac
}

confirm() {
  (( YES )) && return 0
  local answer
  if [[ -r /dev/tty ]]; then
    read -r -p "  $1 [Y/n] " answer </dev/tty || answer=n
  else
    return 0
  fi
  [[ -z $answer || ${answer,,} == y* ]]
}

install_packages() {
  local pm=$1 missing=() optional=() p
  for p in $(required_packages "$pm"); do installed "$pm" "$p" || missing+=("$p"); done
  # mpv and python3 from somewhere else (Flatpak doesn't count: the engine runs mpv directly).
  if [[ $pm == pacman ]] && have yt-dlp && ! installed pacman yt-dlp; then
    missing=("${missing[@]/yt-dlp/}")
  fi
  for p in $(optional_packages "$pm"); do installed "$pm" "$p" || optional+=("$p"); done
  # Only the ones that matter: no MPRIS plugin search when one is there already.
  [[ -n $(find_mpris) ]] && optional=("${optional[@]/mpv-mpris/}") && optional=("${optional[@]/mpv-plugin-mpris/}")
  [[ $pm == pacman ]] && have deno && optional=("${optional[@]/deno/}")
  read -r -a missing <<<"${missing[*]}"
  read -r -a optional <<<"${optional[*]}"

  if (( ${#missing[@]} + ${#optional[@]} == 0 )); then
    note "mpv, python3 and the rest are installed"
    return
  fi
  if (( EUID != 0 )) && ! have sudo; then
    note "missing: ${missing[*]} ${optional[*]}"
    die "Install them as root with your package manager, then run this again."
  fi
  if ! confirm "Install ${missing[*]} ${optional[*]} with $pm (needs sudo)?"; then
    (( ${#missing[@]} )) && die "Paattu needs: ${missing[*]}"
    return
  fi
  if [[ $pm == apt ]]; then
    local sudo=()
    (( EUID == 0 )) || sudo=(sudo)
    "${sudo[@]}" apt-get update -qq
  fi
  if (( ${#missing[@]} )); then
    if ! pm_install "$pm" "${missing[@]}"; then
      [[ $pm == dnf ]] && note "On Fedora, mpv may need RPM Fusion: https://rpmfusion.org/Configuration"
      die "Couldn't install ${missing[*]}"
    fi
  fi
  for p in "${optional[@]}"; do
    if pm_install "$pm" "$p" >/dev/null 2>&1; then note "installed $p"; else note "$p: not available here (optional)"; fi
  done
}

# mpv-mpris: where the distro put it (a custom mpv config dir skips /etc/mpv/scripts).
find_mpris() {
  local f
  for f in /usr/lib/mpv-mpris/mpris.so /usr/lib64/mpv-mpris/mpris.so /usr/lib/*/mpv-mpris/mpris.so \
           /etc/mpv/scripts/mpris.so /usr/share/mpv/scripts/mpris.so /usr/lib/mpv/scripts/mpris.so \
           /usr/lib64/mpv/scripts/mpris.so; do
    if [[ -f $f ]]; then
      readlink -f "$f"
      return 0
    fi
  done
  find /usr/lib /usr/lib64 /usr/share/mpv /etc/mpv -name mpris.so -path '*mpv*' 2>/dev/null | head -n 1 || true
}

# ---------------------------------------------------------------- downloads

fetch() {
  if have curl; then
    curl -fsSL --retry 3 -o "$2" "$1"
  elif have wget; then
    wget -q -O "$2" "$1"
  else
    python3 -c 'import sys, urllib.request; urllib.request.urlretrieve(sys.argv[1], sys.argv[2])' "$1" "$2"
  fi
}

# yt-dlp: pacman's on Arch; elsewhere the official build in ~/.local/bin, kept
# current (YouTube changes often and old versions stop working).
install_ytdlp() {
  local pm=$1 ours=$BIN/yt-dlp
  if [[ $pm == pacman ]] && have yt-dlp && [[ $(command -v yt-dlp) != "$ours" ]]; then
    note "yt-dlp $(yt-dlp --version 2>/dev/null) ($(command -v yt-dlp))"
    return
  fi
  mkdir -p "$BIN"
  if [[ -x $ours ]]; then
    "$ours" -U >/dev/null 2>&1 || warn "couldn't update yt-dlp (offline?)"
  else
    local tmp
    tmp=$(mktemp "$BIN/.yt-dlp.XXXXXX")
    if ! fetch https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp "$tmp"; then
      rm -f "$tmp"
      die "Couldn't download yt-dlp from GitHub"
    fi
    chmod 755 "$tmp"
    mv -f "$tmp" "$ours"
  fi
  note "yt-dlp $("$ours" --version 2>/dev/null) ($ours)"
}

# deno runs YouTube's player JavaScript for yt-dlp; without it many songs
# won't resolve. Official build into ~/.local/bin when the distro has none.
install_deno() {
  local pm=$1
  if have deno; then
    note "$(first_line deno --version) ($(command -v deno))"
    return
  fi
  local arch
  case $(uname -m) in
    x86_64 | amd64) arch=x86_64 ;;
    aarch64 | arm64) arch=aarch64 ;;
    *) warn "no deno build for $(uname -m): some YouTube songs may not play"; return ;;
  esac
  local libc
  libc=$(ldd --version 2>&1 || true)
  if [[ $pm == apk || ( $libc != *GLIBC* && $libc != *"GNU libc"* ) ]]; then
    warn "deno's builds need glibc; install deno yourself for full YouTube support"
    return
  fi
  local tmp
  tmp=$(mktemp -d)
  if fetch "https://github.com/denoland/deno/releases/latest/download/deno-$arch-unknown-linux-gnu.zip" "$tmp/deno.zip" \
      && python3 -m zipfile -e "$tmp/deno.zip" "$tmp/out" && [[ -f $tmp/out/deno ]]; then
    mkdir -p "$BIN"
    install -m 755 "$tmp/out/deno" "$BIN/deno"
    note "$(first_line "$BIN/deno" --version) ($BIN/deno)"
  else
    warn "couldn't download deno: some YouTube songs may not play"
  fi
  rm -rf "$tmp"
}

# ---------------------------------------------------------------- install

# Files that belong to the plugin: copy what changed, drop what's gone.
sync_dir() {
  local src=$1 dst=$2 f
  mkdir -p "$dst"
  for f in "$src"/*; do
    [[ -f $f ]] || continue
    cmp -s "$f" "$dst/${f##*/}" || install -m 644 "$f" "$dst/${f##*/}"
  done
  for f in "$dst"/*.qml "$dst"/*.js "$dst"/*.json; do
    [[ -e $f && ! -e $src/${f##*/} ]] && rm -f "$f"
  done
  return 0
}

install_program() {
  mkdir -p "$(dirname "$LIB")" "$BIN"
  if (( DEV )); then
    [[ -L $LIB || ! -e $LIB ]] || rm -rf "$LIB"
    ln -sfn "$SRC" "$LIB"
    note "$LIB -> $SRC"
  elif [[ $SRC == "$(readlink -f "$LIB" 2>/dev/null)" ]]; then
    if [[ -L $LIB ]]; then
      note "$LIB -> $SRC (--dev install; re-run from a copy to stop following it)"
    else
      note "$LIB (up to date)"
    fi
  else
    local stage part
    stage=$(mktemp -d "$(dirname "$LIB")/.paattu.XXXXXX")
    for part in bin paattu engine themes share plugin models install.sh README.md LICENSE pyproject.toml; do
      if [[ -e $SRC/$part ]]; then cp -R "$SRC/$part" "$stage/"; fi
    done
    rm -rf "$stage"/*/__pycache__ "$stage"/*/*/__pycache__
    chmod 755 "$stage" "$stage/bin/paattu" "$stage/install.sh"
    if [[ -L $LIB ]]; then rm -f "$LIB"; else rm -rf "$LIB"; fi
    mv "$stage" "$LIB"
    note "$LIB"
  fi
  ln -sfn "$LIB/bin/paattu" "$BIN/paattu"
  note "$BIN/paattu"
}

install_engine() {
  local mpris ytdlp mpv
  mpris=$(find_mpris)
  ytdlp=$(command -v yt-dlp || true)
  [[ -x $BIN/yt-dlp ]] && ytdlp=$BIN/yt-dlp
  mkdir -p "$CONFIG/mpv"
  local mpris_line="# (mpv-mpris isn't installed: no media keys)"
  [[ -n $mpris ]] && mpris_line="scripts-append=$mpris"
  {
    sed "s|^scripts-append=.*mpris\\.so\$|$mpris_line|" "$SRC/engine/mpv.conf"
    # The engine may start without ~/.local/bin on its PATH.
    if [[ $ytdlp == "$BIN/yt-dlp" ]]; then
      printf '\n# yt-dlp from install.sh\nscript-opts-append=ytdl_hook-ytdl_path=%s\n' "$ytdlp"
    fi
  } >"$CONFIG/mpv/mpv.conf.new"
  mv -f "$CONFIG/mpv/mpv.conf.new" "$CONFIG/mpv/mpv.conf"
  note "$CONFIG/mpv/mpv.conf${mpris:+ (media keys: $mpris)}"
  [[ -n $mpris ]] || warn "no mpv-mpris: media keys won't control Paattu"
  # The engine's script: play history, radio, failover and fades.
  mkdir -p "$CONFIG/mpv/scripts"
  sed "s|@PAATTU@|$BIN/paattu|" "$SRC/engine/paattu.lua" >"$CONFIG/mpv/scripts/paattu.lua.new"
  mv -f "$CONFIG/mpv/scripts/paattu.lua.new" "$CONFIG/mpv/scripts/paattu.lua"
  note "$CONFIG/mpv/scripts/paattu.lua"

  if ! have systemctl || ! systemctl --user show-environment >/dev/null 2>&1; then
    note "no systemd user session: paattu starts mpv itself when you press play"
    return
  fi
  mpv=$(command -v mpv)
  local config_arg=$CONFIG/mpv path=%h/.local/bin:/usr/local/bin:/usr/bin:/bin
  [[ $config_arg == "$HOME"/* ]] && config_arg=%h/${config_arg#"$HOME"/}
  [[ -d /run/current-system/sw/bin ]] && path+=:/run/current-system/sw/bin
  mkdir -p "$UNIT_DIR"
  sed -e "s|@MPV@|$mpv|" -e "s|@MKDIR@|$(command -v mkdir)|" -e "s|@CONFIG@|$config_arg|" \
      -e "s|@PATH@|$path|" -e "s|@URL@|$REPO_URL|" "$SRC/engine/$UNIT" >"$UNIT_DIR/$UNIT"
  systemctl --user daemon-reload
  note "$UNIT_DIR/$UNIT (starts when you press play)"
}

install_themes() {
  mkdir -p "$CONFIG/themes"
  local theme dest added=0
  for theme in "$SRC"/themes/*.json; do
    dest=$CONFIG/themes/${theme##*/}
    [[ -e $dest ]] && continue
    install -m 644 "$theme" "$dest"
    added=$((added + 1))
  done
  note "$CONFIG/themes ($added new)"
  [[ -e $CONFIG/config.json ]] || "$BIN/paattu" config set theme omarchy >/dev/null
}

install_omarchy() {
  say "Adding Paattu to Omarchy"
  sync_dir "$LIB/plugin" "$PLUGIN_DIR"
  note "plugin: $PLUGIN_DIR"
  mkdir -p "$APPS" "$ICONS"
  install -m 644 "$SRC/share/paattu.svg" "$ICONS/paattu.svg"
  install -m 644 "$SRC/share/paattu.desktop" "$APPS/paattu.desktop"
  update-desktop-database "$APPS" 2>/dev/null || true
  note "launcher: Super+Space → Paattu"
  omarchy-shell shell rescanPlugins >/dev/null 2>&1 || true
  if grep -q "\"$PLUGIN_ID\"" "$XDG_CONFIG/omarchy/shell.json" 2>/dev/null; then
    note "bar: already there"
  else
    omarchy plugin enable "$PLUGIN_ID" --section right --before rajeevrama.dual-headphones >/dev/null 2>&1 \
      || omarchy plugin enable "$PLUGIN_ID" --section right >/dev/null 2>&1 \
      || warn "couldn't add it to the bar: omarchy plugin enable $PLUGIN_ID"
    note "bar: right section, next to the audio controls"
  fi
}

install_all() {
  if (( EUID == 0 )); then
    die "Run without sudo (it asks when it needs to); only --firewall needs root."
  fi
  local pm
  pm=$(detect_pm)

  say "Checking packages ($pm)"
  if [[ $pm == unknown ]]; then
    warn "unknown package manager: install mpv, python3 (3.10+) and mpv-mpris yourself"
  else
    install_packages "$pm"
  fi
  have mpv || die "mpv is missing"
  have python3 || die "python3 is missing"
  python3 -c 'import sys; sys.exit(sys.version_info < (3, 10))' \
    || die "Paattu needs Python 3.10 or newer (this is $(python3 --version))"

  say "Getting yt-dlp and deno"
  install_ytdlp "$pm"
  install_deno "$pm"

  say "Installing the paattu command"
  install_program

  say "Installing the engine"
  install_engine

  say "Installing colour schemes"
  install_themes

  if have omarchy-shell; then
    install_omarchy
  fi

  echo
  say "Done"
  if [[ :$PATH: != *:$BIN:* ]]; then
    warn "$BIN isn't on your PATH. Add this to your shell's startup file:"
    note "  export PATH=\"\$HOME/.local/bin:\$PATH\""
  fi
  if have omarchy-shell; then
    note "Open: the bar's music icon, the widget on workspace 1, or Super+Space → Paattu."
  else
    note "Play from the terminal: paattu search \"Malare\", paattu play <link>, paattu --help"
    note "Media keys work through MPRIS. For a window, get the Paattu desktop app"
    note "(AppImage) from $REPO_URL/releases"
  fi
  [[ -s $DATA/shelf.json ]] || note "Add music: paattu user add @handle (a YouTube profile) or paattu search NAME"
  if [[ -d /etc/opensnitchd/rules && ! -e $RULE ]]; then
    echo
    note "OpenSnitch is on: before the first song, let the player through so a"
    note "prompt can't time out into a permanent block:"
    note "  sudo $LIB/install.sh --firewall"
  elif [[ -r $RULE ]] && ! grep -q saavn "$RULE"; then
    echo
    note "The OpenSnitch rule only covers YouTube. For search (JioSaavn, SoundCloud)"
    note "and pasted links, update it:"
    note "  sudo $LIB/install.sh --firewall"
  fi
}

# ---------------------------------------------------------------- check / uninstall

check() {
  local pm mpris
  pm=$(detect_pm)
  # shellcheck source=/dev/null
  note "distro: $( (. /etc/os-release 2>/dev/null && echo "${PRETTY_NAME:-?}") || echo unknown) ($pm)"
  note "mpv: $(first_line mpv --version || echo missing)"
  mpris=$(find_mpris)
  note "mpv-mpris: ${mpris:-missing (no media keys)}"
  note "python3: $(python3 --version 2>/dev/null || echo missing)"
  note "yt-dlp: $( (have yt-dlp && echo "$(yt-dlp --version 2>/dev/null) ($(command -v yt-dlp))") || ([[ -x $BIN/yt-dlp ]] && echo "$("$BIN/yt-dlp" --version) ($BIN/yt-dlp)") || echo missing)"
  note "deno: $(first_line deno --version || first_line "$BIN/deno" --version || echo missing)"
  note "paattu command: $(command -v paattu || ([[ -e $BIN/paattu ]] && echo "$BIN/paattu (not on PATH)") || echo missing)"
  if [[ -L $LIB ]]; then note "program: $LIB -> $(readlink -f "$LIB")"; elif [[ -d $LIB ]]; then note "program: $LIB"; else note "program: not installed"; fi
  if have systemctl && systemctl --user show-environment >/dev/null 2>&1; then
    note "engine: $(systemctl --user is-active "$UNIT" 2>/dev/null || true)"
  else
    note "engine: no systemd user session (paattu starts mpv itself)"
  fi
  if have omarchy-shell; then
    note "plugin: $(omarchy-shell shell listPlugins 2>/dev/null | grep -o "\"$PLUGIN_ID\"[^}]*\"enabled\": *[a-z]*" | grep -o 'enabled": *[a-z]*' || echo unknown)"
  fi
  if [[ -d /etc/opensnitchd/rules ]]; then
    if [[ -e $RULE ]]; then note "firewall rule: $RULE"; else note "firewall rule: not installed (sudo $0 --firewall)"; fi
    [[ -e $CLIAMP_DENY ]] && note "note: OpenSnitch blocks cliamp ($CLIAMP_DENY)"
  fi
  if [[ -f $DATA/shelf.json ]]; then
    note "library: $(python3 -c 'import json,sys; c=json.load(open(sys.argv[1]))["counts"]; print("%(users)d users, %(saved)d playlists, %(tracks)d songs" % c)' "$DATA/shelf.json")"
  else
    note "library: empty (paattu user add @handle, or paattu search NAME)"
  fi
}

uninstall() {
  (( EUID == 0 )) && die "Run without sudo."
  say "Removing Paattu"
  if have systemctl && systemctl --user show-environment >/dev/null 2>&1; then
    systemctl --user disable --now "$UNIT" >/dev/null 2>&1 || true
  fi
  if [[ -e $UNIT_DIR/$UNIT ]]; then
    rm -f "$UNIT_DIR/$UNIT"
    if have systemctl; then systemctl --user daemon-reload 2>/dev/null || true; fi
    note "removed the engine service"
  fi
  if [[ -d $PLUGIN_DIR ]]; then
    if have omarchy; then omarchy plugin disable "$PLUGIN_ID" >/dev/null 2>&1 || true; fi
    rm -rf "$PLUGIN_DIR"
    note "removed the Omarchy plugin"
  fi
  rm -f "$APPS/paattu.desktop" "$ICONS/paattu.svg"
  if [[ -L $BIN/paattu ]]; then rm -f "$BIN/paattu"; fi
  if [[ -L $LIB ]]; then rm -f "$LIB"; elif [[ -d $LIB ]]; then rm -rf "$LIB"; fi
  rm -rf "$CONFIG/mpv"
  note "removed the paattu command and $LIB"
  if (( PURGE )); then
    rm -rf "$CONFIG" "$DATA" "$CACHE"
    note "removed your library, settings and cover art"
  else
    note "kept your library and settings: $DATA, $CONFIG (--purge removes them)"
  fi
  [[ -x $BIN/yt-dlp || -x $BIN/deno ]] && note "left yt-dlp/deno in $BIN (other programs may use them)"
  return 0
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
  "description": "Paattu: mpv and yt-dlp may reach YouTube, JioSaavn, SoundCloud, Bandcamp, archive.org and Audiomack (managed by Paattu's install.sh)",
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
    note "It was saved when a cliamp prompt timed out unanswered. Without it,"
    note "OpenSnitch asks again the next time cliamp connects."
    read -r -p "  Remove it? [y/N] " answer
    if [[ ${answer,,} == y* ]]; then
      rm -f "$CLIAMP_DENY"
      note "removed"
    else
      note "kept"
    fi
  fi
}

usage() {
  sed -n '8,16p' "$0" | sed 's/^# \{0,1\}//'
}

for arg in "$@"; do
  case $arg in
    --check) ACTION=check ;;
    --firewall) ACTION=firewall ;;
    --uninstall) ACTION=uninstall ;;
    --purge) PURGE=1 ;;
    --yes | -y) YES=1 ;;
    --dev) DEV=1 ;;
    -h | --help) usage; exit 0 ;;
    *) usage >&2; exit 2 ;;
  esac
done

case $ACTION in
  check) check ;;
  firewall) firewall ;;
  uninstall) uninstall ;;
  install) install_all ;;
esac
