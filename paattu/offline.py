"""Songs kept on this computer: a folder of audio files the engine plays in
place of the stream, so the songs you listen to keep playing with no internet.

The folder carries its own index (paattu-offline.json), in the same format as
the app's offline.dart, so a folder copied from a phone (or to one) still makes
sense. Songs arrive by themselves when they're played to the end
(history.fully_played; config "offline.autoSave") and by hand (`paattu offline
keep`); past the room allowed ("offline.limitMb"), the songs used least
recently go first. yt-dlp downloads them.

The engine's script (engine/paattu.lua) reads the index as each song loads and
opens the kept file instead of the link, so the queue, the history and the
radio all still see the song's link.
"""

import contextlib
import fcntl
import json
import os
import random
import re
import socket
import subprocess
import sys
import time
from pathlib import Path

from . import config, paths
from .sources import track_site, track_url

INDEX = "paattu-offline.json"
LOCK = ".paattu-offline.lock"
MAX_SONG_BYTES = 150 << 20
EXTENSIONS = {"opus": ".webm", "vorbis": ".webm", "aac": ".m4a", "mp3": ".mp3", "flac": ".flac"}


class OfflineError(Exception):
    pass


def settings(conf=None):
    conf = config.load() if conf is None else conf
    return {**config.DEFAULTS["offline"], **(conf.get("offline") or {})}


def folder(conf=None):
    where = settings(conf)["dir"]
    return Path(os.path.expanduser(where)) if where else paths.DATA / "offline"


def key(track):
    """What a song is kept under: "site:id", as the app's trackKey."""
    return "%s:%s" % (track_site(track), track.get("id", ""))


def _stamp(at=None):
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(at))


def read(where=None):
    """{key: entry} of the songs kept, leaving out those whose file has gone."""
    where = where or folder()
    try:
        with open(where / INDEX, encoding="utf-8") as f:
            songs = (json.load(f) or {}).get("songs") or {}
    except (FileNotFoundError, json.JSONDecodeError, AttributeError):
        return {}
    return {k: e for k, e in songs.items()
            if isinstance(e, dict) and e.get("file") and (where / e["file"]).is_file()}


def _write(where, songs):
    tmp = where / (INDEX + ".tmp")
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump({"version": 1, "songs": songs}, f, indent=1, ensure_ascii=False)
    os.replace(tmp, where / INDEX)


@contextlib.contextmanager
def editing(where=None):
    """The kept songs to change, written back after (one change at a time:
    two downloads finishing together both land)."""
    where = where or folder()
    where.mkdir(parents=True, exist_ok=True)
    with open(where / LOCK, "w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        songs = read(where)
        yield songs
        _write(where, songs)


def songs(where=None):
    """The entries kept, newest first, each with its key."""
    kept = read(where)
    return sorted(({**e, "key": k} for k, e in kept.items()), key=lambda e: e.get("saved") or "", reverse=True)


def file_of(track, where=None):
    """The file a song is kept in, or None."""
    where = where or folder()
    entry = read(where).get(key(track))
    return where / entry["file"] if entry else None


def file_name(track, codec, where):
    """A filename that says what the song is ("Vijay Yesudas - Malare.m4a"),
    not already taken. Keep in step with _fileName in the app."""
    credits = [c for c in track.get("credits") or [] if c]
    artist = credits[0] if credits else track.get("channel") or ""
    name = " - ".join(p for p in (artist, track.get("title") or "") if p.strip())
    name = re.sub(r"\s+", " ", re.sub(r'[\\/:*?"<>|\x00-\x1f]', "", name)).strip()[:120].strip()
    name = name or track.get("id") or "song"
    ext = EXTENSIONS.get(codec, ".audio")
    candidate, n = name + ext, 2
    while (where / candidate).exists():
        candidate, n = "%s (%d)%s" % (name, n, ext), n + 1
    return candidate


def evict(kept, limit_bytes, where):
    """Drop the songs used least recently until the rest fit. The titles dropped."""
    dropped = []
    while limit_bytes > 0 and len(kept) > 1 and sum(e.get("bytes") or 0 for e in kept.values()) > limit_bytes:
        oldest = min(kept, key=lambda k: kept[k].get("used") or "")
        entry = kept.pop(oldest)
        with contextlib.suppress(FileNotFoundError):
            (where / entry["file"]).unlink()
        dropped.append((entry.get("track") or {}).get("title") or entry["file"])
    return dropped


def _codec(acodec, ext):
    codec = (acodec or "").split(".")[0].lower()
    if codec in ("", "none", "unknown", "na"):
        codec = {"m4a": "aac", "webm": "opus", "ogg": "vorbis"}.get(ext, ext)
    return {"mp4a": "aac"}.get(codec, codec)


def keep(track, conf=None):
    """Download a song into the folder and note it in the index; the entry.
    A song already kept comes back as it is."""
    conf = config.load() if conf is None else conf
    where = folder(conf)
    k = key(track)
    entry = read(where).get(k)
    if entry:
        return entry
    where.mkdir(parents=True, exist_ok=True)
    part = where / (".download-%s" % re.sub(r"[^A-Za-z0-9_-]", "_", track.get("id") or "song"))
    command = ["yt-dlp", "--ignore-config", "--no-warnings", "--no-playlist", "--socket-timeout", "20",
               "-f", "bestaudio[filesize<150M]/bestaudio[filesize_approx<150M]/bestaudio",
               "--max-filesize", str(MAX_SONG_BYTES), "-o", str(part) + ".%(ext)s",
               "--print", "after_move:%(filepath)s\t%(acodec)s\t%(abr)s", "--", track_url(track)]
    try:
        proc = subprocess.run(command, capture_output=True, text=True, timeout=600)
    except FileNotFoundError:
        raise OfflineError("yt-dlp is not installed")
    except subprocess.TimeoutExpired:
        raise OfflineError("the download took too long")
    lines = [l for l in proc.stdout.splitlines() if "\t" in l]
    if proc.returncode != 0 or not lines:
        for left in where.glob(part.name + ".*"):
            left.unlink(missing_ok=True)
        errors = [l for l in proc.stderr.splitlines() if l.strip()]
        raise OfflineError(re.sub(r"^ERROR:\s*(\[[^\]]+\]\s*)?", "", errors[-1]) if errors else
                           "%s is too big to keep" % (track.get("title") or "that song"))
    path, acodec, abr = lines[-1].split("\t")[:3]
    path = Path(path)
    codec = _codec(acodec, path.suffix.lstrip(".").lower())
    try:
        kbps = round(float(abr))
    except ValueError:
        kbps = None
    limit = int(settings(conf)["limitMb"] or 0) << 20
    with editing(where) as kept:
        if k in kept:  # kept by another run meanwhile
            path.unlink(missing_ok=True)
            return kept[k]
        name = file_name(track, codec, where)
        os.replace(path, where / name)
        now = _stamp()
        entry = {"file": name, "bytes": (where / name).stat().st_size, "saved": now, "used": now, "plays": 0,
                 "codec": codec, "track": {k2: v for k2, v in track.items() if not k2.startswith("_") and v is not None}}
        if kbps:
            entry["kbps"] = kbps
        kept[k] = entry
        evict(kept, limit, where)
    return entry


def keep_soon(track):
    """Keep a song in the background, so whoever asked isn't held up."""
    title = (track.get("title") or "") + (" · " + track["movie"] if track.get("movie") else "")
    subprocess.Popen([sys.executable, "-m", "paattu", "offline", "keep", "--quiet", "--title=" + title, "--",
                      track_url(track)],
                     cwd=str(Path(__file__).resolve().parent.parent), stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                     stderr=subprocess.DEVNULL, start_new_session=True)


def note_played(track, where=None):
    """A song played from here counts as used, so it isn't the next to go."""
    where = where or folder()
    k = key(track)
    if k not in read(where):
        return
    with editing(where) as kept:
        if k in kept:
            kept[k]["used"] = _stamp()
            kept[k]["plays"] = int(kept[k].get("plays") or 0) + 1


def remove(k, where=None):
    """Take a song out, and delete its file. The entry taken, or None."""
    where = where or folder()
    with editing(where) as kept:
        entry = kept.pop(k, None)
    if entry:
        with contextlib.suppress(FileNotFoundError):
            (where / entry["file"]).unlink()
    return entry


def tracks(shuffled=False, where=None):
    """The kept songs as tracks to queue, newest first or shuffled."""
    out = [e["track"] for e in songs(where) if (e.get("track") or {}).get("id")]
    if shuffled:
        random.shuffle(out)
    return out


def reachable(host="music.youtube.com", timeout=3):
    """Whether the internet is there (a connection to YouTube Music opens)."""
    try:
        socket.create_connection((host, 443), timeout=timeout).close()
        return True
    except OSError:
        return False
