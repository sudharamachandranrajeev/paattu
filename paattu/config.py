"""~/.config/paattu/config.json: looks and behaviour, hot-reloaded by the shell.

Like `spicetify config`, everything can be set from the command line
(`paattu config set desktop.style vinyl`) and themes are plain files you can
copy and edit (~/.config/paattu/themes/<name>.json).
"""

import contextlib
import copy
import json
import os
import tempfile

from . import paths, sound

DEFAULTS = {
    "theme": "omarchy",
    "desktop": {
        "enabled": True,
        "workspace": 1,
        "monitor": "",
        "style": "vinyl",
        "position": "bottom-left",
        "marginX": 56,
        "marginY": 56,
        "scale": 1.0,
        "opacity": 0.92,
        "showQuickPicks": True,
        "showUpNext": True,
    },
    "queue": {"dedupe": True, "skipTrailers": True},
    "languages": ["Malayalam", "Tamil"],
    # Where the music comes from (YouTube, or JioSaavn's 320 kbps film songs,
    # SoundCloud, or all three) and how many results a site.
    "search": {"sites": ["youtube"], "limit": 12},
    # The equaliser, tone, balance and speed (paattu sound).
    "sound": sound.DEFAULTS,
    # Now Playing shows the song's video, blurred and silent, behind it (paattu video).
    "videoBackground": True,
    # Video mode: Now Playing shows the song's video and the engine plays the
    # video's own sound, so the singing matches the lips.
    "videoMode": False,
    # How Now Playing looks: the cover with the video behind it, the video in
    # place of the cover, the full picture, or the cover on a turning record.
    "nowPlayingStyle": "cover",
    # How blurred the video is, 0 (sharp) to 100.
    "videoBlur": 30,
    # Now Playing takes its colours from the song's cover.
    "coverColors": False,
    # The cover in 3D, its subject lifted out of the picture (paattu depth).
    "coverDepth": True,
    # Seconds a song fades out at its end and the next fades in (0 for none).
    "fade": 3,
    # When the queue runs out, carry on with songs like the last one (paattu radio).
    "autoRadio": True,
    # Songs kept on this computer to play with no internet (paattu offline): the
    # folder ("" for ~/.local/share/paattu/offline), the room they may take, and
    # whether a song played to the end is kept by itself.
    "offline": {"dir": "", "limitMb": 2048, "autoSave": True},
    # The song's words over its cover on Now Playing (paattu lyrics): whether
    # they show, how each line comes in (popping out in 3D, fading in, or
    # plain), whether the cover's colours move through the letters, and the
    # words in English letters under the song's own script. The bar of what
    # the song is (film, year, singers, music...) above Up next.
    "lyrics": {"show": True, "effect": "3d", "gradient": True, "transliterate": True},
    "songInfo": True,
    # Soft sounds when you click, go to another page or change the song.
    "uiSounds": True,
}

STYLES = ("vinyl", "card", "minimal")
NOW_PLAYING_STYLES = ("cover", "video", "full", "record")
LYRIC_EFFECTS = ("3d", "comic", "karaoke", "glow", "fade", "plain")
SITES = ("jiosaavn", "youtube", "soundcloud")
POSITIONS = ("top-left", "top", "top-right", "left", "center", "right", "bottom-left", "bottom", "bottom-right")


def _merge(base, override):
    out = copy.deepcopy(base)
    for key, value in (override or {}).items():
        if isinstance(value, dict) and isinstance(out.get(key), dict):
            out[key] = _merge(out[key], value)
        else:
            out[key] = value
    return out


def load():
    try:
        with open(paths.CONFIG_FILE, encoding="utf-8") as f:
            return _merge(DEFAULTS, json.load(f))
    except (FileNotFoundError, json.JSONDecodeError):
        return copy.deepcopy(DEFAULTS)


def save(config):
    paths.CONFIG.mkdir(parents=True, exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=paths.CONFIG, prefix=".config.", suffix=".json")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            json.dump(config, f, indent=2, ensure_ascii=False)
            f.write("\n")
        os.replace(tmp, paths.CONFIG_FILE)
    except BaseException:
        with contextlib.suppress(FileNotFoundError):
            os.unlink(tmp)
        raise


def parse_value(raw):
    """CLI strings to JSON values: numbers, booleans, lists stay typed."""
    try:
        return json.loads(raw)
    except json.JSONDecodeError:
        return raw


def validate(key, value):
    if key == "desktop.style" and value not in STYLES:
        raise ValueError("desktop.style is one of: " + ", ".join(STYLES))
    if key == "desktop.position" and value not in POSITIONS:
        raise ValueError("desktop.position is one of: " + ", ".join(POSITIONS))
    if key == "theme" and value != "omarchy" and value not in theme_names():
        raise ValueError("unknown theme %r; see: paattu theme list" % value)
    if key == "desktop.workspace" and not (isinstance(value, int) and value >= 1):
        raise ValueError("desktop.workspace is a workspace number")
    if key in ("desktop.scale", "desktop.opacity") and not isinstance(value, (int, float)):
        raise ValueError(key + " is a number")
    if key in ("videoBackground", "videoMode", "coverColors", "coverDepth") and not isinstance(value, bool):
        raise ValueError(key + " is true or false")
    if key == "nowPlayingStyle" and value not in NOW_PLAYING_STYLES:
        raise ValueError("nowPlayingStyle is one of: " + ", ".join(NOW_PLAYING_STYLES))
    if key == "videoBlur" and not (isinstance(value, int) and not isinstance(value, bool) and 0 <= value <= 100):
        raise ValueError("videoBlur is 0 to 100")
    if key == "fade" and not (isinstance(value, int) and not isinstance(value, bool) and 0 <= value <= 12):
        raise ValueError("fade is 0 to 12 seconds")
    if key == "lyrics.effect" and value not in LYRIC_EFFECTS:
        raise ValueError("lyrics.effect is one of: " + ", ".join(LYRIC_EFFECTS))
    if key in ("autoRadio", "offline.autoSave", "songInfo", "uiSounds", "lyrics.show", "lyrics.gradient",
               "lyrics.transliterate") and not isinstance(value, bool):
        raise ValueError(key + " is true or false")
    if key == "offline.limitMb" and not (isinstance(value, int) and not isinstance(value, bool) and value >= 0):
        raise ValueError("offline.limitMb is a number of megabytes (0 for no limit)")
    if key == "offline.dir" and not isinstance(value, str):
        raise ValueError("offline.dir is a folder")
    if key == "search.sites" and not (isinstance(value, list) and value and all(s in SITES for s in value)):
        raise ValueError("search.sites is a list of: " + ", ".join(SITES))


def get(config, key):
    node = config
    for part in key.split("."):
        if not isinstance(node, dict) or part not in node:
            raise KeyError(key)
        node = node[part]
    return node


def set_key(key, value):
    validate(key, value)
    try:
        with open(paths.CONFIG_FILE, encoding="utf-8") as f:
            stored = json.load(f)
    except (FileNotFoundError, json.JSONDecodeError):
        stored = {}
    node = stored
    parts = key.split(".")
    for part in parts[:-1]:
        node = node.setdefault(part, {})
    node[parts[-1]] = value
    save(stored)
    return load()


def theme_names():
    if not paths.THEMES.is_dir():
        return []
    return sorted(p.stem for p in paths.THEMES.glob("*.json"))


def theme(name):
    with open(paths.THEMES / (name + ".json"), encoding="utf-8") as f:
        return json.load(f)
