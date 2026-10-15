"""The radio: songs like a song, from YouTube Music's own radio for it, a
helping at a time as the queue runs out. Like Spotify's and YouTube's, it
leaves out what was played in the last few hours and songs skipped more than
once, and when one song's radio runs dry it carries on from a song it played.
The app's radio.dart does the same.

The engine's mpv script (engine/paattu.lua) asks for more with
`paattu radio more` when two songs or fewer are left; where the radio is up
to lives in $XDG_RUNTIME_DIR/paattu/radio.json between helpings.
"""

import contextlib
import fcntl
import json
import os
import tempfile
import time

from . import paths, ytmusic
from .history import heard_since, skipped_often, song_identity
from .sources import is_video_id, same_song, track_site

STATE = paths.RUNTIME / "radio.json"


def radio_worthy(song):
    """Whether a radio or made-up playlist should have song: a song (not a
    trailer or a jukebox), between a minute and a quarter of an hour long."""
    if song.get("kind") in ("trailer", "jukebox"):
        return False
    seconds = song.get("duration")
    return not seconds or 60 <= seconds <= 900


def interleave_songs(lists, avoid=None, limit=None):
    """Songs from lists taken in turn, one from each list at a time, leaving
    out unworthy ones, repeats and anything in avoid (ids and song keys,
    which grows), up to limit."""
    seen = avoid if avoid is not None else set()
    out = []
    at = [0] * len(lists)
    going = True
    while going and (limit is None or len(out) < limit):
        going = False
        for i, songs in enumerate(lists):
            if limit is not None and len(out) >= limit:
                break
            while at[i] < len(songs):
                song = songs[at[i]]
                at[i] += 1
                tid, key = song.get("id") or "", song_identity(song)
                if not tid or not radio_worthy(song) or tid in seen or key in seen:
                    continue
                seen.update((tid, key))
                out.append(song)
                going = True
                break
    return out


def youtube_id_for(track):
    """The YouTube video for track: its own, or YouTube Music's copy of a song
    from another site. None when there's none."""
    tid = track.get("id") or ""
    if track_site(track) == "youtube" and is_video_id(tid):
        return tid
    credits = track.get("credits") or []
    query = " ".join(x for x in (track.get("title") or "", track.get("movie") or (credits[0] if credits else "")) if x)
    if not query:
        return None
    return next((s["id"] for s in ytmusic.search(query, limit=6) if same_song(track, s)), None)


class SongRadio:
    """One station's radio. state holds where it is up to (see load_state):
    the station's id, the video whose radio is being played, the token for
    its next helping, the videos used and the songs given."""

    def __init__(self, history, state=None):
        self.history = history
        self.state = state if state is not None else {}

    def next(self, station, queue, count=10, now=None):
        """Up to count songs like station that aren't in queue."""
        state = self.state
        if state.get("station") != station.get("id"):
            state.clear()
            state.update(station=station.get("id"), video=None, more=None, used=[], given=[])
        now = time.time() if now is None else now
        plays = self.history.plays

        def key_of(tid):
            return song_identity(self.history.track(tid) or {"id": tid})

        avoid = set(state["given"])
        for song in queue:
            avoid.update((song.get("id") or "", song_identity(song)))
        avoid |= heard_since(plays, now - 6 * 3600, key_of)
        avoid |= skipped_often(plays, now)
        out = []
        for _ in range(4):
            if len(out) >= count:
                break
            if not state["video"]:
                start = station if not state["used"] else self._next_station(out, queue)
                video = youtube_id_for(start) if start else None
                if not video:
                    break
                state.update(video=video, more=None)
                state["used"].append(video)
            songs, more = ytmusic.radio(state["video"], more=state["more"])
            state["more"] = more
            fresh = interleave_songs([songs], avoid, count - len(out))
            out += fresh
            if not fresh or not more:
                state["video"] = None
        for song in out:
            state["given"] += [song["id"], song_identity(song)]
        del state["given"][:-2000]
        return out

    def _next_station(self, fresh, queue):
        """A song the radio played (newest first) whose own radio hasn't been used."""
        for song in [*reversed(fresh), *reversed(queue)]:
            tid = song.get("id") or ""
            if track_site(song) == "youtube" and is_video_id(tid) and tid not in self.state["used"]:
                return song
        return None


@contextlib.contextmanager
def session():
    """The radio's saved state, locked while a helping is fetched (the
    engine's script and a click can ask at once), saved afterwards."""
    paths.RUNTIME.mkdir(parents=True, exist_ok=True)
    with open(paths.RUNTIME / "radio.lock", "w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        try:
            with open(STATE, encoding="utf-8") as f:
                state = json.load(f)
            if not isinstance(state, dict):
                state = {}
        except (FileNotFoundError, json.JSONDecodeError):
            state = {}
        yield state
        fd, tmp = tempfile.mkstemp(dir=paths.RUNTIME, prefix=".radio.", suffix=".json")
        try:
            with os.fdopen(fd, "w", encoding="utf-8") as f:
                json.dump(state, f, ensure_ascii=False)
            os.replace(tmp, STATE)
        except BaseException:
            with contextlib.suppress(FileNotFoundError):
                os.unlink(tmp)
            raise
