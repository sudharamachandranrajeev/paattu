"""Download artwork into ~/.cache/paattu/art so the shell never touches the network."""

import concurrent.futures
import contextlib
import os
import re
import tempfile
import urllib.request

from . import paths

USER_AGENT = "Mozilla/5.0 (X11; Linux x86_64) Paattu/1.0"


def video_thumbnail(vid):
    # hqdefault is 480x360 with the 16:9 frame letterboxed in the middle; the
    # shell crops the centre square out of it for cover art.
    return f"https://i.ytimg.com/vi/{vid}/hqdefault.jpg"


def fetch(url, dest, timeout=15):
    """Save url to dest unless it's already there. True when dest exists after."""
    if dest.exists() and dest.stat().st_size > 0:
        return True
    if not url:
        return False
    dest.parent.mkdir(parents=True, exist_ok=True)
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            body = response.read()
    except Exception:
        return False
    if not body:
        return False
    fd, tmp = tempfile.mkstemp(dir=dest.parent, prefix=".art.")
    try:
        with os.fdopen(fd, "wb") as f:
            f.write(body)
        os.replace(tmp, dest)
    except BaseException:
        with contextlib.suppress(FileNotFoundError):
            os.unlink(tmp)
        raise
    return True


def fetch_many(jobs, workers=8):
    """jobs: iterable of (url, dest). Returns how many files are now cached."""
    jobs = [(u, d) for u, d in jobs if u and not (d.exists() and d.stat().st_size > 0)]
    if not jobs:
        return 0
    done = 0
    with concurrent.futures.ThreadPoolExecutor(max_workers=workers) as pool:
        for ok in pool.map(lambda job: fetch(*job), jobs):
            done += 1 if ok else 0
    return done


def playlist_jobs(data, playlist_ids):
    for pid in playlist_ids:
        playlist = data["playlists"].get(pid)
        if playlist:
            yield playlist.get("thumbnail"), paths.art_path("p", pid)


def track_art(tid, track=None):
    """A song's cover: its own (JioSaavn, SoundCloud, other links) or YouTube's thumbnail."""
    if track and track.get("art"):
        return track["art"]
    if track and track.get("url"):
        return ""
    return video_thumbnail(tid) if re.match(r"^[\w-]{11}$", tid) else ""


def track_jobs(track_ids, find=lambda tid: None):
    """find(id): the track's details (library or search results), for its art link."""
    for tid in track_ids:
        yield track_art(tid, find(tid)), paths.art_path("v", tid)


def user_jobs(data, user_ids):
    for uid in user_ids:
        user = data["users"].get(uid)
        if user:
            yield user.get("avatar"), paths.art_path("u", uid)


def prune(data, keep_tracks=()):
    """Delete cached art for playlists, users and songs no longer in the library.
    Returns (files, bytes) freed."""
    keep = {"p": set(data["playlists"]), "u": set(data["users"]), "v": set(data["tracks"]) | set(keep_tracks)}
    files = freed = 0
    for kind, ids in keep.items():
        folder = paths.ART / kind
        if not folder.is_dir():
            continue
        for path in folder.glob("*.jpg"):
            if path.stem in ids:
                continue
            with contextlib.suppress(FileNotFoundError):
                freed += path.stat().st_size
                path.unlink()
                files += 1
    return files, freed
