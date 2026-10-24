"""What was played and for how long (~/.local/share/paattu/history.json),
which the daily, weekly and monthly playlists are made from and which keeps
the radio from repeating itself. The app keeps the same file beside its
library (app/lib/src/history.dart):

    plays   [{id, at (seconds since 1970), heard (seconds), length}], oldest first
    tracks  id -> the song, for the ids in plays and made
    made    daily|weekly|monthly -> {key, tracks[ids]}: the playlist made
            for that day, week or month

The engine's mpv script records each play with `paattu played`.
"""

import contextlib
import fcntl
import json
import os
import tempfile
import time

from . import paths
from .library import now as now_stamp
from .titles import song_key

FILE = paths.DATA / "history.json"

# Plays kept; older ones are dropped.
LIMIT = 3000


def counted(play):
    """A play that counts: half the song, or 30 seconds of a long one."""
    heard = int(play.get("heard") or 0)
    length = int(play.get("length") or 0)
    return heard >= (min(30, length // 2) if length > 0 else 30)


def song_identity(track):
    """The key a song is known by across uploads, or its id when it has no title."""
    key = song_key(track)
    return track.get("id", "") if key == "|" else key


def stored_track(track):
    """A song as the history keeps it: without the queue's own notes (keys
    starting with _) or empty fields."""
    return {k: v for k, v in track.items() if not k.startswith("_") and v is not None}


def _empty():
    return {"version": 1, "plays": [], "tracks": {}, "made": {}}


class History:
    def __init__(self, path=FILE):
        self.path = path
        self.data = _empty()

    @classmethod
    def load(cls, path=FILE):
        history = cls(path)
        try:
            with open(path, encoding="utf-8") as f:
                stored = json.load(f)
            if isinstance(stored, dict):
                history.data = {**_empty(), **stored}
                for key in ("tracks", "made"):
                    if not isinstance(history.data.get(key), dict):
                        history.data[key] = {}
                if not isinstance(history.data.get("plays"), list):
                    history.data["plays"] = []
        except (FileNotFoundError, json.JSONDecodeError):
            pass
        return history

    @property
    def plays(self):
        return [p for p in self.data["plays"] if isinstance(p, dict)]

    def track(self, tid):
        found = self.data["tracks"].get(tid)
        return found if isinstance(found, dict) else None

    def played(self, track, heard, length=None, at=None):
        """track played for heard seconds (of length)."""
        tid = track.get("id") or ""
        if not tid or heard < 1:
            return
        length = length or track.get("duration")
        play = {"id": tid, "at": int(at if at is not None else time.time()), "heard": int(heard)}
        if length and int(length) > 0:
            play["length"] = int(length)
        plays = self.data["plays"]
        plays.append(play)
        del plays[:-LIMIT]
        self.data["tracks"][tid] = stored_track(track)
        self._prune()

    def made(self, kind):
        """(period key, songs) of the playlist made for kind, or None."""
        entry = self.data["made"].get(kind)
        if not isinstance(entry, dict) or not entry.get("key"):
            return None
        return entry["key"], [t for t in (self.track(i) for i in entry.get("tracks") or []) if t]

    def set_made(self, kind, key, songs):
        for song in songs:
            self.data["tracks"][song["id"]] = stored_track(song)
        self.data["made"][kind] = {"key": key, "made": now_stamp(), "tracks": [s["id"] for s in songs]}
        self._prune()

    def clear(self):
        # Where ListenBrainz sync got to stays: those plays were sent already.
        kept = self.data.get("listenbrainz")
        self.data = _empty()
        if kept:
            self.data["listenbrainz"] = kept

    def _prune(self):
        """Forget songs nothing refers to any more."""
        used = {p.get("id") for p in self.plays}
        for entry in self.data["made"].values():
            if isinstance(entry, dict):
                used.update(entry.get("tracks") or [])
        tracks = self.data["tracks"]
        for tid in [t for t in tracks if t not in used]:
            del tracks[tid]

    def save(self):
        self.path.parent.mkdir(parents=True, exist_ok=True)
        fd, tmp = tempfile.mkstemp(dir=self.path.parent, prefix=".history.", suffix=".json")
        try:
            with os.fdopen(fd, "w", encoding="utf-8") as f:
                json.dump(self.data, f, ensure_ascii=False, separators=(",", ":"))
            os.replace(tmp, self.path)
        except BaseException:
            with contextlib.suppress(FileNotFoundError):
                os.unlink(tmp)
            raise


@contextlib.contextmanager
def editing(path=FILE):
    """The history, locked against other paattu commands writing it at the
    same time, and saved afterwards."""
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path.with_name(".history.lock"), "w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        history = History.load(path)
        yield history
        history.save()


def liking(plays, now, days=30, half_life=7, key_of=None):
    """How much each song was liked lately: every counted play within days,
    worth less the older it is (half as much every half_life days), less half
    a play for every quick skip. Keyed by song, so a song's video and audio
    uploads count together. Returns (score, ids: key -> latest id, count)."""
    score, ids, count = {}, {}, {}
    since = now - days * 86400
    for play in plays:
        at = int(play.get("at") or 0)
        if at < since:
            continue
        tid = play.get("id") or ""
        key = key_of(tid) if key_of else tid
        ids[key] = tid
        if counted(play):
            score[key] = score.get(key, 0) + 0.5 ** ((now - at) / 86400 / half_life)
            count[key] = count.get(key, 0) + 1
        else:
            score[key] = score.get(key, 0) - 0.5
    return score, ids, count


def heard_since(plays, since, key_of=None):
    """Songs played (or skipped) since `since` (seconds), by id and by song."""
    out = set()
    for play in plays:
        if int(play.get("at") or 0) >= since:
            out.add(play.get("id") or "")
            if key_of:
                out.add(key_of(play.get("id") or ""))
    return out


def skipped_often(plays, now):
    """Songs skipped (stopped within half a minute) at least twice in 30 days."""
    since = now - 30 * 86400
    skips = {}
    for play in plays:
        if int(play.get("at") or 0) < since or counted(play):
            continue
        skips[play.get("id")] = skips.get(play.get("id"), 0) + 1
    return {tid for tid, n in skips.items() if n >= 2}


def top_songs(plays, track, now, days=30, half_life=7):
    """[(song, score, count)] played within days, most liked first; songs
    skipped more than played are left out. track(id) gives the song."""
    def key_of(tid):
        return song_identity(track(tid) or {"id": tid})

    score, ids, count = liking(plays, now, days, half_life, key_of)
    out = []
    for key, value in score.items():
        song = track(ids[key]) if value > 0 else None
        if song:
            out.append((song, value, count.get(key, 0)))
    out.sort(key=lambda t: -t[1])
    return out
