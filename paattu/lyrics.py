"""A song's words, timed to it where they can be, for Now Playing.

LRCLIB (lrclib.net, open and free, no key) has film songs' words in their own
script, most of them timed line by line (LRC). The song is looked for by its
title and film, and a find is taken only when its name is the song's. Its
timing is taken as it is only when its length is within 2 seconds of the
song's. YouTube Music's Lyrics tab is asked as well: its words are timed to
the song as YouTube Music has it (the "song" upload, not a music video).

Words timed to another upload of the song than the one playing (a music
video with a longer start, say) are put in step with it: the two uploads'
loudness over time (rhythm.py) are lined up, and the lines moved by how far
apart they are. Words that can't be lined up are shown untimed.

Each line comes with its words in English letters (transliterate.py) when it's
in an Indian script. Finds and misses are kept in ~/.cache/paattu/lyrics, a
miss for 3 days, and a find made while a site was down for an hour. The app's lyrics.dart does the same (tests/lyrics_cases.json).
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
PARTIAL_KEEP = 3600
TIMED_WITHIN = 2
VERSION = 2
# YouTube Music's Android app is given its Lyrics tab timed.
ANDROID_CLIENT = {"clientName": "ANDROID_MUSIC", "clientVersion": "7.21.50", "hl": "en", "gl": "IN",
                  "androidSdkVersion": 30}
ANDROID_AGENT = "com.google.android.apps.youtube.music/7.21.50 (Linux; U; Android 11) gzip"
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
    """The best of LRCLIB's finds for the track: (find, timed) or None, timed
    when its timing fits the track as it is. One in the song's language comes
    first (a film's song is often dubbed into others), timed next, then in
    its own script, then the nearest length."""
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
        rank = (fits, bool(synced), script is not None, -gap)
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


def _stamp(seconds):
    minutes, rest = divmod(max(0.0, seconds), 60)
    return "[%02d:%05.2f]" % (minutes, rest)


def music_timed_lyrics(response):
    """The timed words (as LRC) on YouTube Music's Lyrics page as its Android
    app is given it, or None. A lone music note (the start, a break) is an
    empty line."""
    out = []
    for model in ytmusic._all(response, "lyricsData"):
        for item in model.get("timedLyricsData") or []:
            cue = (item or {}).get("cueRange") or {}
            start = cue.get("startTimeMilliseconds")
            if start is None:
                continue
            text = (item.get("lyricLine") or "").strip()
            out.append(_stamp(int(start) / 1000) + ("" if not text.strip("♪ ") else text))
        if out:
            return "\n".join(out)
    return None


def _coarse(level, step):
    return [sum(level[i:i + step]) / step for i in range(0, len(level) - step + 1, step)]


def _pearson(a, b):
    n = len(a)
    ma, mb = sum(a) / n, sum(b) / n
    sab = saa = sbb = 0.0
    for x, y in zip(a, b):
        dx, dy = x - ma, y - mb
        sab += dx * dy
        saa += dx * dx
        sbb += dy * dy
    return sab / (saa * sbb) ** 0.5 if saa > 0 and sbb > 0 else -1.0


def lyric_shift(played, reference, fps, most):
    """How many seconds later the song comes in the upload played than in the
    reference upload the words are timed to, from the two loudness envelopes
    (rhythm.py, fps a second), up to most either way; or None when they
    don't line up clearly (not the same recording, say). Lined up a tenth of
    a second at a time; taken when the best fit is a close one (0.6) and
    clearly better (by 0.1) than any other a second or more from it."""
    step = max(1, fps // 10)
    a, b = _coarse(played, step), _coarse(reference, step)
    need = 0.6 * min(len(a), len(b))
    scores = {}
    for s in range(-int(most * 10), int(most * 10) + 1):
        lo, hi = max(0, -s), min(len(b), len(a) - s)
        if hi - lo >= max(need, 2):
            scores[s] = _pearson(a[lo + s:hi + s], b[lo:hi])
    if not scores:
        return None
    top = max(scores, key=lambda s: (scores[s], -abs(s)))
    second = max((v for s, v in scores.items() if abs(s - top) > 10), default=-1.0)
    if scores[top] < 0.6 or scores[top] - second < 0.1:
        return None
    return top / 10


def lines(found, latin=True):
    """What Now Playing shows: [{time (None when not timed), text, latin}]."""
    if found.get("synced"):
        shift = found.get("shift") or 0
        timed = [(round(max(0.0, at + shift), 2), "" if not t.strip("♪ ") else t)
                 for at, t in parse_lrc(found["synced"])]
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


def _android_post(url, body):
    return browse._json(url, body=body, headers={"User-Agent": ANDROID_AGENT})


def _from_youtube_music(video_id):
    """YouTube Music's words for a song: {synced, plain, source} (synced
    timed to that song) or None."""
    body = {"context": {"client": ytmusic.CLIENT}, "videoId": video_id}
    browse_id = music_lyrics_id(ytmusic._post(ytmusic.NEXT_API, body))
    if not browse_id:
        return None
    with contextlib.suppress(Exception):  # the plain words, then
        synced = music_timed_lyrics(_android_post(BROWSE_API, {"context": {"client": ANDROID_CLIENT},
                                                               "browseId": browse_id}))
        if synced:
            return {"synced": synced, "plain": "", "source": "YouTube Music"}
    found = music_lyrics(ytmusic._post(BROWSE_API, {"context": {"client": ytmusic.CLIENT}, "browseId": browse_id}))
    return {"plain": found[0], "synced": "", "source": found[1]} if found else None


def _untimed(got):
    """Timed words that can't be put in step with the song, shown untimed."""
    plain = got.get("plain") or "\n".join(t for _, t in parse_lrc(got.get("synced")) if t.strip("♪ "))
    return {"synced": "", "plain": plain, "source": got["source"]}


def find(track, language="", level=None):
    """The song's words from the internet: {synced, plain, source, shift,
    partial} or None. level(track) gives a song's loudness envelope
    (rhythm.py's level at rhythm.FPS), to put words timed to another upload
    in step with this one; without it those are shown untimed. partial: a
    site couldn't be asked, so a better find may come later."""
    from .rhythm import FPS

    length = track.get("duration") or 0
    partial = asked = False
    plain = None
    # LRCLIB's words timed to another upload: (got, its length).
    off = []
    for query in queries(track):
        try:
            picked = best(_lrclib(query), track, language)
            asked = True
        except Exception:  # noqa: BLE001 - try the next name, then YouTube Music
            partial = True
            continue
        if not picked:
            continue
        item, timed = picked
        got = {"synced": item.get("syncedLyrics") or "", "plain": item.get("plainLyrics") or "", "source": "LRCLIB"}
        if timed:
            return dict(got, shift=0, partial=False)
        if got["synced"] and item.get("duration") and all(got["synced"] != o["synced"] for o, _ in off):
            off.append((got, float(item["duration"])))
        plain = plain or _untimed(got)

    # Words timed to another upload: (got, its length, that upload's id).
    elsewhere = []
    tid = track.get("id") or ""
    video = tid if is_video_id(tid) and not track.get("url") else None
    try:
        songs = []
        if track.get("title"):
            songs = [song for song in ytmusic.search(" ".join(queries(track)[:1]), limit=5)
                     if same_song(song.get("title") or "", track) and song.get("id")]
        for got, at in off:
            # LRCLIB's timing is to an upload as long as its find: YouTube
            # Music's song of that length, likely.
            fits = [song for song in songs if abs((song.get("duration") or 0) - at) <= TIMED_WITHIN]
            if fits:
                elsewhere.append((got, at, fits[0]["id"]))
        near = sorted((song for song in songs
                       if not length or abs((song.get("duration") or 0) - length) <= SAME_SONG_WITHIN),
                      key=lambda song: abs((song.get("duration") or 0) - length))
        if near or video:
            song = near[0] if near else {"id": video, "duration": 0}
            got = _from_youtube_music(song["id"])
            if got and got["synced"]:
                at = song.get("duration") or 0
                if song["id"] == tid or (length and at and abs(at - length) <= TIMED_WITHIN):
                    return dict(got, shift=0, partial=partial)
                if at:
                    elsewhere.append((got, at, song["id"]))
                plain = plain or _untimed(got)
            elif got:
                plain = plain or dict(got)
        asked = True
    except Exception:  # noqa: BLE001 - what LRCLIB found, then
        partial = True

    # The nearest in length first: the likeliest to line up.
    for got, at, reference in sorted(elsewhere, key=lambda e: abs(e[1] - length))[:2]:
        if not (level and reference and length):
            continue
        try:
            shift = lyric_shift(level(track), level({"id": reference}), FPS, abs(at - length) + 8)
        except Exception:  # noqa: BLE001 - shown untimed for now
            partial = True
            continue
        if shift is not None:
            return dict(got, shift=shift, partial=partial)
    if plain:
        return dict(plain, shift=0, partial=partial)
    if not asked:
        raise RuntimeError("couldn't ask for the words")
    # Nothing found while a site was down: asked again sooner than a miss.
    return {"synced": "", "plain": "", "source": "", "shift": 0, "partial": True} if partial else None


def _file(track):
    return FOLDER / (hashlib.sha1(offline.key(track).encode()).hexdigest()[:20] + ".json")


def lookup(track, language="", refresh=False, now=None, level=None):
    """The song's words (found or not), from the cache when there."""
    now = time.time() if now is None else now
    path = _file(track)
    with contextlib.suppress(FileNotFoundError, json.JSONDecodeError, OSError):
        kept = json.loads(path.read_text(encoding="utf-8"))
        found = kept.get("found")
        keep = PARTIAL_KEEP if (found or {}).get("partial") else None if found else MISS_KEEP
        if not refresh and kept.get("version") == VERSION and (
                keep is None or now - (kept.get("fetched") or 0) < keep):
            return found
    found = find(track, language, level)
    FOLDER.mkdir(parents=True, exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=FOLDER, prefix=".lyrics.", suffix=".json")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            json.dump({"version": VERSION, "fetched": now, "id": offline.key(track), "found": found}, f, ensure_ascii=False)
        os.replace(tmp, path)
    except BaseException:
        with contextlib.suppress(FileNotFoundError):
            os.unlink(tmp)
        raise
    return found
