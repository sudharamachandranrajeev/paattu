"""A song's words, timed to it where they can be, for Now Playing.

LRCLIB (lrclib.net, open and free, no key) has film songs' words in their own
script, most of them timed line by line (LRC). The song is looked for by its
title and film, and a find is taken only when its name is the song's; timing
only when its length is within 10 seconds of the song's (a music video with
a longer start would be out of step), otherwise its words as they are.
YouTube Music (its Lyrics tab, from Musixmatch) is asked next: words in
English letters, not timed.

Each line comes with its words in English letters (transliterate.py) when it's
in an Indian script. Finds and misses are kept in ~/.cache/paattu/lyrics, a
miss for 3 days. The app's lyrics.dart does the same (tests/lyrics_cases.json).
"""

import contextlib
import hashlib
import json
import os
import re
import tempfile
import time
import urllib.parse

from . import __version__, browse, offline, paths, ytmusic
from .sources import is_video_id
from .transliterate import LANGUAGES, script_of, transliterate

SCRIPTS = {language: script for script, language in LANGUAGES.items()}

LRCLIB = "https://lrclib.net/api/search"
AGENT = "Paattu/%s (https://github.com/sudharamachandranrajeev/paattu)" % __version__
BROWSE_API = "https://music.youtube.com/youtubei/v1/browse?prettyPrint=false"
FOLDER = paths.CACHE / "lyrics"
MISS_KEEP = 3 * 86400
TIMED_WITHIN = 10
SAME_SONG_WITHIN = 120

_STAMP = re.compile(r"\[(\d+):(\d{1,2}(?:[.:]\d{1,3})?)\]")
_OFFSET = re.compile(r"^\[offset:\s*([+-]?\d+)\]", re.I | re.M)
_BRACKETS = re.compile(r"\s*[(\[][^)\]]*[)\]]")
_NOT_WORD = re.compile(r"[^\w]+", re.U)


def parse_lrc(text):
    """Timed words ([mm:ss.xx] words, a line can carry several times) as
    [(seconds, words)] in time order, [offset:ms] applied."""
    found = _OFFSET.search(text or "")
    shift = int(found.group(1)) / 1000 if found else 0
    out = []
    for raw in (text or "").splitlines():
        stamps = []
        rest = raw.strip()
        while True:
            m = _STAMP.match(rest)
            if not m:
                break
            stamps.append(int(m.group(1)) * 60 + float(m.group(2).replace(":", ".")))
            rest = rest[m.end():]
        for at in stamps:
            out.append((round(max(0.0, at - shift), 2), rest.strip()))
    out.sort(key=lambda line: line[0])
    return out


def words(text):
    """The words of a name to match on: no brackets, lower case."""
    return {w for w in _NOT_WORD.split(_BRACKETS.sub(" ", text or "").lower()) if w}


def same_song(name, track):
    """Whether a find called name is the track: its title's words are all in
    the name, or the name's are all in the title and film."""
    found = words(name)
    title, film = words(track.get("title")), words(track.get("movie"))
    if not found:
        return False
    return any(part and part <= found for part in (title, film)) or found <= (title | film)


def _plain(name):
    return " ".join(w for w in _NOT_WORD.split(_BRACKETS.sub(" ", name or "")) if w)


def queries(track):
    """What to ask LRCLIB for: the title and film, then each alone (YouTube
    titles mix the two up now and then)."""
    title, film = _plain(track.get("title")), _plain(track.get("movie"))
    out = []
    film = "" if film.lower() == title.lower() else film
    for q in (" ".join(p for p in (title, film) if p), title, film):
        if q and q not in out:
            out.append(q)
    return out


def best(found, track, language=""):
    """The best of LRCLIB's finds for the track: (find, timed) or None. One in
    the song's language comes first (a film's song is often dubbed into
    others), timed next, then in its own script, then the nearest length."""
    length = track.get("duration") or 0
    wanted = SCRIPTS.get(language)
    picked = None
    for item in found if isinstance(found, list) else []:
        if not isinstance(item, dict) or item.get("instrumental"):
            continue
        synced, plain = item.get("syncedLyrics") or "", item.get("plainLyrics") or ""
        if not (synced or plain) or not same_song(item.get("trackName") or "", track):
            continue
        gap = abs((item.get("duration") or 0) - length) if length and item.get("duration") else 0
        if gap > SAME_SONG_WITHIN:
            continue
        timed = bool(synced) and gap <= TIMED_WITHIN
        script = script_of(synced or plain)
        fits = 1 if not wanted or not script else 2 if script == wanted else 0
        rank = (fits, timed, script is not None, -gap)
        if picked is None or rank > picked[0]:
            picked = (rank, item, timed)
    return (picked[1], picked[2]) if picked else None


def music_lyrics_id(response):
    """The browse id of the Lyrics tab in YouTube Music's /next for a song."""
    for tab in ytmusic._all(response, "tabRenderer"):
        browse_id = ((tab.get("endpoint") or {}).get("browseEndpoint") or {}).get("browseId") or ""
        if browse_id.startswith("MPLY"):
            return browse_id
    return None


def _text(node):
    return "".join(r.get("text") or "" for r in (node or {}).get("runs") or [])


def music_lyrics(response):
    """(words, where from) on YouTube Music's Lyrics page, or None."""
    for shelf in ytmusic._all(response, "musicDescriptionShelfRenderer"):
        text = _text(shelf.get("description")).strip()
        if text:
            source = _text(shelf.get("footer")).replace("Source:", "").strip()
            return text, "YouTube Music" + (" (%s)" % source if source else "")
    return None


def lines(found, latin=True):
    """What Now Playing shows: [{time (None when not timed), text, latin}]."""
    if found.get("synced"):
        timed = parse_lrc(found["synced"])
    else:
        timed = [(None, line.strip()) for line in (found.get("plain") or "").splitlines()]
    scripts = [script_of(t) for _, t in timed]
    out = [{"time": at, "text": t, "latin": transliterate(t, script) if latin and script else ""}
           for (at, t), script in zip(timed, scripts)]
    named = [script for script in scripts if script]
    worded = len([t for _, t in timed if t])
    script = max(dict.fromkeys(named), key=named.count) if named and len(named) * 2 >= worded else None
    while out and not out[0]["text"] and out[0]["time"] is None:
        out.pop(0)
    return out, script


def shown(found, latin=True):
    if not found:
        return {"found": False, "synced": False, "lines": []}
    out, script = lines(found, latin)
    return {"found": bool(out), "synced": bool(found.get("synced")), "source": found.get("source") or "",
            "script": script or "latin", "language": LANGUAGES.get(script, ""), "lines": out}


def _lrclib(query):
    url = LRCLIB + "?" + urllib.parse.urlencode({"q": query})
    for attempt in range(2):
        try:
            return browse._json(url, headers={"User-Agent": AGENT}, timeout=15)
        except Exception:  # noqa: BLE001 - LRCLIB is busy now and then (503)
            if attempt:
                raise
            time.sleep(1)


def _from_youtube_music(video_id):
    body = {"context": {"client": ytmusic.CLIENT}, "videoId": video_id}
    browse_id = music_lyrics_id(ytmusic._post(ytmusic.NEXT_API, body))
    if not browse_id:
        return None
    found = music_lyrics(ytmusic._post(BROWSE_API, {"context": {"client": ytmusic.CLIENT}, "browseId": browse_id}))
    return {"plain": found[0], "synced": "", "source": found[1]} if found else None


def find(track, language=""):
    """The song's words from the internet: {synced, plain, source} or None."""
    asked = False
    fallback = None
    for query in queries(track):
        try:
            picked = best(_lrclib(query), track, language)
            asked = True
        except Exception:  # noqa: BLE001 - try the next name, then YouTube Music
            continue
        if picked:
            item, timed = picked
            got = {"synced": item.get("syncedLyrics") if timed else "",
                   "plain": item.get("plainLyrics") or "", "source": "LRCLIB"}
            if not timed and not got["plain"]:
                got["plain"] = "\n".join(t for _, t in parse_lrc(item.get("syncedLyrics")))
            if timed:
                return got
            fallback = fallback or got
    if fallback:
        return fallback
    tid = track.get("id") or ""
    video = tid if is_video_id(tid) and not track.get("url") else None
    try:
        if not video and track.get("title"):
            length = track.get("duration") or 0
            for song in ytmusic.search(" ".join(queries(track)[:1]), limit=5):
                if same_song(song.get("title") or "", track) and (
                        not length or abs((song.get("duration") or 0) - length) <= 5):
                    video = song.get("id")
                    break
        if video:
            return _from_youtube_music(video)
    except Exception:  # noqa: BLE001 - nothing to show, then
        if not asked:
            raise
    return None


def _file(track):
    return FOLDER / (hashlib.sha1(offline.key(track).encode()).hexdigest()[:20] + ".json")


def lookup(track, language="", refresh=False, now=None):
    """The song's words (found or not), from the cache when there."""
    now = time.time() if now is None else now
    path = _file(track)
    with contextlib.suppress(FileNotFoundError, json.JSONDecodeError, OSError):
        kept = json.loads(path.read_text(encoding="utf-8"))
        if not refresh and (kept.get("found") or now - (kept.get("fetched") or 0) < MISS_KEEP):
            return kept.get("found")
    found = find(track, language)
    FOLDER.mkdir(parents=True, exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=FOLDER, prefix=".lyrics.", suffix=".json")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            json.dump({"fetched": now, "id": offline.key(track), "found": found}, f, ensure_ascii=False)
        os.replace(tmp, path)
    except BaseException:
        with contextlib.suppress(FileNotFoundError):
            os.unlink(tmp)
        raise
    return found
