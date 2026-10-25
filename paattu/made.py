"""Playlists made for you from what you play (history.py): a daily mix of
songs you love with a few like them, a weekly list of songs new to you like
what you played lately, and the month's most played. Plus playlists made from
a description ("Ilaiyaraaja melodies, rain songs, Premam"). The app's
made.dart makes the same ones.
"""

import concurrent.futures
import datetime
import random
import re
import time

from . import library, ytmusic
from .history import heard_since, skipped_often, song_identity, top_songs, turned_down
from .radio import interleave_songs, youtube_id_for
from .sources import SourceError

KINDS = ("daily", "weekly", "monthly")

# Songs in a made playlist.
SIZE = 30

# A made playlist with fewer songs was cut short (YouTube Music didn't
# answer): it plays, but isn't kept, so the next try makes it again.
KEEP = SIZE // 2

TITLES = {"daily": "Daily mix", "weekly": "Weekly discovery", "monthly": "Monthly top"}
BLURBS = {
    "daily": "Songs you love and a few like them. New every day",
    "weekly": "Songs new to you, like what you played lately. New every Monday",
    "monthly": "What you played most in the last 30 days",
}


def period_key(kind, day):
    """The day, week or month a playlist is made for (day is a date):
    2026-10-15, 2026-W42 (the ISO week) or 2026-10."""
    if kind == "daily":
        return day.strftime("%Y-%m-%d")
    if kind == "weekly":
        year, week, _ = day.isocalendar()
        return "%d-W%02d" % (year, week)
    return day.strftime("%Y-%m")


def kept_made(stored, key):
    """The songs of a stored made playlist ((key, songs) or None) if it's the
    one for key and whole enough to keep; else None."""
    if stored and stored[0] == key and len(stored[1]) >= KEEP:
        return stored[1]
    return None


def weighted_pick(items, weight, count, rng):
    """count of items picked at random, an item weight(item) times as likely
    as one of weight 1 (Efraimidis and Spirakis' weighted sampling)."""
    keyed = [(rng.random() ** (1 / max(weight(item), 1e-6)), item) for item in items]
    keyed.sort(key=lambda k: -k[0])
    return [item for _, item in keyed[:count]]


def daily_mix(familiar, fresh, size=SIZE):
    """Two songs you know, then one new one, and so on; when one kind runs out
    the other fills the list."""
    out, seen = [], set()
    f = n = 0

    def take(song):
        key = song_identity(song)
        if song["id"] in seen or key in seen:
            seen.update((song["id"], key))
            return
        seen.update((song["id"], key))
        out.append(song)

    while len(out) < size and (f < len(familiar) or n < len(fresh)):
        want_fresh = len(out) % 3 == 2
        if (want_fresh and n < len(fresh)) or f >= len(familiar):
            take(fresh[n])
            n += 1
        else:
            take(familiar[f])
            f += 1
    return out


_SPLIT_RE = re.compile(r"[,;\n/+&]|\s+(?:and|with|plus)\s+", re.I)
_LEAD_RE = re.compile(
    r"^(?:(?:a|an|some)\s+)?(?:(?:playlist|mix)\s+(?:of|with|for)\s+)?(?:(?:the\s+)?(?:best|top)\s+)?"
    r"(?:(?:songs?|hits|music)\s+(?:from|of|by|in)\s+)?", re.I)
_SPACES_RE = re.compile(r"\s+")


def _squash(text):
    return _SPACES_RE.sub(" ", text or "").strip()


def describe_phrases(description):
    """What a description asks for, one search each: "songs from Premam, rain
    songs and Ilaiyaraaja" is Premam, rain songs and Ilaiyaraaja. Six at most."""
    out = []
    for part in _SPLIT_RE.split(description or ""):
        phrase = _squash(_LEAD_RE.sub("", _squash(part), count=1))
        if phrase and phrase.lower() not in (p.lower() for p in out):
            out.append(phrase)
    return out[:6]


def _quietly(job, *args, **kwargs):
    try:
        return job(*args, **kwargs)
    except Exception:  # one search failing shouldn't sink the playlist
        return None


def _each(job, items):
    """job(item) for every item at once, in order; None where it failed."""
    if not items:
        return []
    with concurrent.futures.ThreadPoolExecutor(max_workers=min(6, len(items))) as pool:
        return list(pool.map(lambda item: _quietly(job, item), items))


def describe_playlist(description, size=SIZE):
    """A playlist of about size songs for description: the songs each part
    of it finds on YouTube Music, taken in turn, topped up from the radio of
    each part's best match."""
    phrases = describe_phrases(description)
    if not phrases:
        raise SourceError("say what the playlist should have")
    found = [songs or [] for songs in _each(ytmusic.search, phrases)]
    avoid = set()
    out = interleave_songs(found, avoid, size)
    if len(out) < size:
        firsts = [songs[0]["id"] for songs in found if songs]
        more = [page[0] if page else [] for page in _each(ytmusic.radio, firsts)]
        out += interleave_songs(more, avoid, size - len(out))
    if not out:
        raise SourceError("couldn't find songs for that. Try other words, or check the internet connection")
    return out


class MadeForYou:
    def __init__(self, history, data, rng=None):
        self.history = history
        self.data = data  # the library
        self.rng = rng or random.Random()

    def _track(self, tid):
        return self.history.track(tid) or self.data["tracks"].get(tid)

    def playlist(self, kind, refresh=False, now=None):
        """This period's playlist of kind, made now if there isn't one yet (or
        refresh makes a new one). The history keeps it (unless it was cut
        short); save the history after."""
        now = time.time() if now is None else now
        key = period_key(kind, datetime.date.fromtimestamp(now))
        kept = kept_made(self.history.made(kind), key)
        if kept and not refresh:
            return kept
        songs = self._make(kind, now)
        if not songs:
            raise SourceError("couldn't make %s. Check the internet connection" % TITLES[kind])
        if len(songs) >= KEEP:
            self.history.set_made(kind, key, songs)
        return songs

    def _make(self, kind, now):
        plays = self.history.plays
        top = top_songs(plays, self._track, now, days=28 if kind == "weekly" else 30)
        favourites = library.playlist_tracks(self.data, library.FAVOURITES)
        mine = favourites + library.playlist_tracks(self.data, library.SAVED)
        skipped = skipped_often(plays, now) | turned_down(
            plays, lambda tid: song_identity(self._track(tid) or {"id": tid}))
        if kind == "monthly":
            most = sorted(top, key=lambda t: (-t[2], -t[1]))
            avoid = set(skipped)
            out = interleave_songs([[t[0] for t in most]], avoid, SIZE)
            shuffled = list(favourites)
            self.rng.shuffle(shuffled)
            out += interleave_songs([shuffled], avoid, SIZE - len(out))
            if len(out) < SIZE:
                out += self._discover(self._seeds(top, mine), avoid, SIZE - len(out))
            return out
        if kind == "weekly":
            avoid = set(skipped)
            for play in plays:
                avoid.update((play.get("id"), song_identity(self._track(play.get("id")) or play)))
            for song in mine:
                avoid.update((song["id"], song_identity(song)))
            return self._discover(self._seeds(top, mine), avoid, SIZE)
        favourite_ids = {s["id"] for s in favourites}
        weights = {s["id"]: 1.0 if s["id"] in favourite_ids else 0.5 for s in mine}
        for song, score, _ in top:
            weights[song["id"]] = weights.get(song["id"], 0) + score
        pool = interleave_songs([[t[0] for t in top], mine], set(skipped))
        familiar = weighted_pick(pool, lambda s: weights.get(s["id"], 0.5), SIZE * 2 // 3, self.rng)
        avoid = set(skipped)
        for song in familiar:
            avoid.update((song["id"], song_identity(song)))
        avoid |= heard_since(plays, now - 3 * 86400, lambda tid: song_identity(self._track(tid) or {"id": tid}))
        fresh = self._discover(self._seeds(top, mine, familiar), avoid, SIZE)
        return daily_mix(familiar, fresh)

    def _seeds(self, top, mine, picked=None):
        """Up to five songs to find new songs from: picked, else the songs you
        like most (a few of the best at random), your favourites and saved
        songs, or, for someone new, today's Malayalam and Tamil hits."""
        liked = [t[0] for t in top[:10]]
        if picked:
            seeds = weighted_pick(picked, lambda _: 1, 3, self.rng)
        else:
            seeds = weighted_pick(liked, lambda _: 1, 5, self.rng) + weighted_pick(mine, lambda _: 1, 5, self.rng)
        if not seeds:
            hits = _each(lambda q: ytmusic.search(q, limit=5), ["Malayalam hits", "Tamil hits"])
            seeds = interleave_songs([h or [] for h in hits])
        return seeds[:5]

    def _discover(self, seeds, avoid, count):
        """Up to count songs from the radios of seeds, taken in turn, leaving
        out avoid (which grows)."""
        def radio_of(seed):
            video = youtube_id_for(seed)
            if not video:
                return []
            songs, more = ytmusic.radio(video)
            if not more or len(songs) >= count:
                return songs
            return songs + ytmusic.radio(video, more=more)[0]

        pages = [page or [] for page in _each(radio_of, seeds)]
        return interleave_songs(pages, avoid, count)
