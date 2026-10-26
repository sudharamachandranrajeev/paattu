"""The radio: songs like a song, from YouTube Music's own radio for it, a
helping at a time as the queue runs out. Like Spotify's and YouTube's, it
leaves out what was played in the last few hours, songs skipped more than
once, songs turned down (skipped the first time) and songs you took out of
Up next, and when one song's radio runs dry it carries on from a song it
played. It plays to your taste too: songs by the singers, composers and
films you play to the end come first (history.taste_order), those of ones
you skip or take out go down, those of ones you keep taking out are left
out (history.shunned), and a few songs you love that share something with
the station are mixed in. Each helping is ranked (Affinity) before your
taste: songs you play most, then your favourites and songs very like them,
then songs in your playlists and ones close to them, then songs by the
singers and composers, of the themes and in the languages you play a lot.
The app's radio.dart does the same.

The engine's mpv script (engine/paattu.lua) asks for more with
`paattu radio more` when two songs or fewer are left; where the radio is up
to lives in $XDG_RUNTIME_DIR/paattu/radio.json between helpings.
"""

import contextlib
import fcntl
import json
import os
import re
import tempfile
import time

from . import paths, ytmusic
from .history import (counted, features, heard_since, shunned, skipped_often, song_identity, taste,
                      taste_order, top_songs, turned_down)
from .sources import is_video_id, same_song, track_site
from .titles import guess_language

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

    def __init__(self, history, state=None, favourites=(), playlists=(), language_of=None):
        self.history = history
        self.state = state if state is not None else {}
        self.favourites = favourites
        self.playlists = playlists
        self.language_of = language_of

    def next(self, station, queue, count=10, now=None):
        """Up to count songs like station that aren't in queue."""
        state = self.state
        if state.get("station") != station.get("id"):
            state.clear()
            state.update(station=station.get("id"), video=None, more=None, used=[], given=[])
        now = time.time() if now is None else now
        plays = self.history.signals

        def key_of(tid):
            return song_identity(self.history.track(tid) or {"id": tid})

        avoid = set(state["given"])
        for song in queue:
            avoid.update((song.get("id") or "", song_identity(song)))
        avoid |= heard_since(plays, now - 6 * 3600, key_of)
        avoid |= skipped_often(plays, now)
        avoid |= turned_down(plays, key_of)
        likes = taste(plays, self.history.track, now)
        shun = shunned(plays, self.history.track, likes, now)
        affinity = Affinity(plays, self.history.track, now, self.favourites, self.playlists, self.language_of)
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
            liked = [s for s in affinity.order(taste_order(songs, likes)) if not shun & set(features(s))]
            fresh = interleave_songs([liked], avoid, count - len(out))
            out += fresh
            if not fresh or not more:
                state["video"] = None
        out = with_favourites(out, loved_like(station, top_songs(plays, self.history.track, now), avoid))
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


def loved_like(station, top, avoid, count=2):
    """Up to count of the songs you like most ([(song, score, plays)] from
    history.top_songs) that share a singer, composer or film with station,
    leaving out avoid."""
    wanted = set(features(station))
    picked = [song for song, _, _ in top if wanted & set(features(song))]
    return interleave_songs([picked], set(avoid), count)


def with_favourites(songs, loved):
    """songs with the loved ones put in third and seventh (or at the end of a
    short helping)."""
    out = list(songs)
    for at, song in zip((2, 6), loved):
        out.insert(min(at, len(out)), song)
    return out


# What a song is about, from words in its title: theme -> words.
THEMES = {
    "love": ("love", "romantic", "romance", "pranayam", "kadhal", "kaadhal", "ishq", "prema"),
    "sad": ("sad", "emotional", "heartbreak", "breakup", "pathos", "melancholy", "sogam"),
    "dance": ("kuthu", "dance", "party", "mass", "celebration", "peppy", "gaana", "folk"),
    "devotional": ("devotional", "bhakti", "bhajan", "ayyappa", "christian", "krishna", "murugan", "prayer"),
    "calm": ("melody", "melodies", "lullaby", "lofi", "unplugged", "acoustic", "reprise", "soothing", "soulful"),
    "wedding": ("wedding", "kalyanam", "marriage"),
    "festival": ("onam", "christmas", "vishu", "pongal", "diwali", "eid"),
    "rap": ("rap", "hiphop"),
}
_THEME_WORDS = {word: theme for theme, words in THEMES.items() for word in words}


def themes(song):
    """The themes (THEMES) a song's title or upload's title speaks of."""
    text = " ".join((song.get("title") or "", song.get("rawTitle") or "")).lower().replace("hip hop", "hiphop")
    return sorted({_THEME_WORDS[w] for w in re.findall(r"[a-z]+", text) if w in _THEME_WORDS})


def song_language(song):
    """A song's language: its own, else guessed from its names."""
    own = (song.get("language") or "").strip().title()
    credits = [str(c) for c in song.get("credits") or []]
    return own or guess_language(song.get("title", ""), song.get("movie", ""), song.get("channel", ""), *credits)


class Affinity:
    """How near a song is to what you play and keep, as a tier, best first:

    0  a song you play again and again (again counted plays in days), most
       played first
    1  one of your favourites, or very like one (its film and a singer or
       composer)
    2  in one of your other playlists, or close to a song there (its film)
    3  by a singer or composer you play a lot
    4  of a theme (themes) you play a lot
    5  in a language (language_of, song_language when not given) you play
       a lot
    6  none of these

    A lot is often counted plays in days.

    rank gives (tier, strength): within a tier the stronger come first (the
    plays behind it; 2 for the song itself in tiers 1 and 2, 1 for one like
    it). plays can be History.signals: songs taken out don't count."""

    def __init__(self, plays, track, now, favourites=(), playlists=(), language_of=None, days=90, often=3,
                 again=2):
        self.often, self.again = often, again
        self.language_of = language_of or song_language
        self.played, self.by, self.themes, self.languages = {}, {}, {}, {}
        since = now - days * 86400
        for play in plays:
            if play.get("removed") or int(play.get("at") or 0) < since or not counted(play):
                continue
            song = track(play.get("id") or "")
            if not song:
                continue
            key = song_identity(song)
            self.played[key] = self.played.get(key, 0) + 1
            for feature in features(song):
                if feature.startswith("by:"):
                    self.by[feature] = self.by.get(feature, 0) + 1
            for theme in themes(song):
                self.themes[theme] = self.themes.get(theme, 0) + 1
            language = self.language_of(song)
            if language:
                self.languages[language] = self.languages.get(language, 0) + 1
        self.favourites = {song_identity(s) for s in favourites}
        self.loved_by = {(f, c) for s in favourites for f in features(s) if f.startswith("film:")
                         for c in features(s) if c.startswith("by:")}
        self.kept = {song_identity(s) for s in playlists}
        self.kept_films = {f for s in playlists for f in features(s) if f.startswith("film:")}

    def rank(self, song):
        key = song_identity(song)
        mine = features(song)
        films = [f for f in mine if f.startswith("film:")]
        by = [f for f in mine if f.startswith("by:")]
        if self.played.get(key, 0) >= self.again:
            return 0, self.played[key]
        if key in self.favourites:
            return 1, 2
        if any((f, c) in self.loved_by for f in films for c in by):
            return 1, 1
        if key in self.kept:
            return 2, 2
        if any(f in self.kept_films for f in films):
            return 2, 1
        for tier, counts, keys in ((3, self.by, by), (4, self.themes, themes(song)),
                                   (5, self.languages, [self.language_of(song)])):
            best = max((counts.get(k, 0) for k in keys), default=0)
            if best >= self.often:
                return tier, best
        return 6, 0

    def order(self, songs):
        """songs by tier, the stronger first within one, else as they were."""
        ranked = sorted(((self.rank(s), i, s) for i, s in enumerate(songs)),
                        key=lambda r: (r[0][0], -r[0][1], r[1]))
        return [s for _, _, s in ranked]


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
