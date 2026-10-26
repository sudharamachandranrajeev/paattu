"""Where Paattu keeps its files (XDG locations)."""

import os
from pathlib import Path

HOME = Path.home()
CONFIG = Path(os.environ.get("XDG_CONFIG_HOME") or HOME / ".config") / "paattu"
DATA = Path(os.environ.get("XDG_DATA_HOME") or HOME / ".local/share") / "paattu"
CACHE = Path(os.environ.get("XDG_CACHE_HOME") or HOME / ".cache") / "paattu"
RUNTIME = Path(os.environ.get("XDG_RUNTIME_DIR") or f"/run/user/{os.getuid()}") / "paattu"

LIBRARY = DATA / "library.json"
SHELF = DATA / "shelf.json"
CONFIG_FILE = CONFIG / "config.json"
THEMES = CONFIG / "themes"
ART = CACHE / "art"
SEARCH = CACHE / "search.json"
# Songs' videos found (sources.video_id_for).
VIDEOS = CACHE / "videos.json"
SOCKET = RUNTIME / "mpv.sock"
MPV_CONFIG = CONFIG / "mpv"
CLIAMP_PLAYLISTS = Path(os.environ.get("CLIAMP_CONFIG_DIR") or HOME / ".config/cliamp") / "playlists"


def art_path(kind, ident):
    """Cached artwork: kind is 'v' (video), 'p' (playlist) or 'u' (user)."""
    return ART / kind / f"{ident}.jpg"
