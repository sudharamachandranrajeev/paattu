"""The charts: what's played most this week, by language, across the sites
that say so in the open. JioSaavn's editors keep a weekly Top 50 by streams,
a most searched list and a most streamed love songs list for each language
(content.getCharts, asked in that language); YouTube Music's charts have the
week's most watched videos for some (Tamil, Telugu, Hindi, Punjabi, not
Malayalam). The top chart is both, taken in turn and once each.

Songs you turned down (history.turned_down) are left out. Each chart is kept
in ~/.cache/paattu/charts.json for 12 hours. The app's charts.dart makes the
same ones.
"""

import contextlib
import json
import os
import tempfile
import time

from . import browse, paths, ytmusic
from .history import song_identity, turned_down
from .radio import interleave_songs
from .sources import JIOSAAVN_API, SourceError

LANGUAGES = ("Malayalam", "Tamil", "Hindi", "Telugu", "Kannada", "Punjabi")
KINDS = ("top", "searched", "love")
TITLES = {"top": "Top of the week", "searched": "Most searched", "love": "Love songs"}
BLURBS = {"top": "The %s songs played most this week on JioSaavn and YouTube",
          "searched": "The %s songs looked for most on JioSaavn",
          "love": "The %s love songs streamed most on JioSaavn"}
FILE = paths.CACHE / "charts.json"
KEEP = 12 * 3600
SIZE = 50
BROWSE_API = "https://music.youtube.com/youtubei/v1/browse?prettyPrint=false"


def saavn_title(kind, language):
    return {"top": "%s: India Superhits Top 50", "searched": "Most Searched Songs - %s",
            "love": "Most Streamed Love Songs: %s"}[kind] % language


def youtube_title(kind, language):
    return "Top Weekly Videos " + language if kind == "top" else None


def youtube_charts(response):
    """{title: playlist id} for the playlists on YouTube Music's charts page."""
    out = {}
    for item in ytmusic._all(response, "musicTwoRowItemRenderer"):
        runs = (item.get("title") or {}).get("runs") or []
        title = "".join(r.get("text") or "" for r in runs)
        browse_id = ((item.get("navigationEndpoint") or {}).get("browseEndpoint") or {}).get("browseId") or ""
        if title and browse_id.startswith("VL"):
            out[title] = browse_id[2:]
    return out


def sources_of(kind, language, saavn, youtube):
    """Where a chart's songs are: the JioSaavn playlist page, the YouTube
    playlist id (either can be None) and a picture, given JioSaavn's charts
    for the language and youtube_charts."""
    wanted = saavn_title(kind, language).lower()
    found = next((c for c in saavn or [] if (c.get("title") or "").strip().lower() == wanted), None)
    title = youtube_title(kind, language)
    return {"kind": kind, "language": language, "saavn": (found or {}).get("perma_url") or None,
            "youtube": youtube.get(title) if title else None, "art": (found or {}).get("image") or ""}


def merge(lists, avoid):
    """The songs of a chart's lists taken in turn by rank, once each, leaving
    out avoid, up to SIZE."""
    return interleave_songs(lists, set(avoid), SIZE)


def _saavn_charts(language):
    return browse._json(JIOSAAVN_API, {"__call": "content.getCharts", "_format": "json", "_marker": "0",
                                       "api_version": "4", "ctx": "web6dot0"},
                        headers={"Cookie": "L=" + language.lower()})


def _youtube_charts():
    body = {"context": {"client": ytmusic.CLIENT}, "browseId": "FEmusic_charts", "formData": {"selectedValues": ["IN"]}}
    return youtube_charts(ytmusic._post(BROWSE_API, body))


def _quietly(job, *args):
    try:
        return job(*args)
    except Exception:  # noqa: BLE001 - a site that's down leaves its list out
        return None


def _load():
    try:
        with open(FILE, encoding="utf-8") as f:
            data = json.load(f)
        return data if isinstance(data, dict) else {}
    except (FileNotFoundError, json.JSONDecodeError):
        return {}


def _save(data):
    FILE.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=FILE.parent, prefix=".charts.", suffix=".json")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            json.dump(data, f, ensure_ascii=False)
        os.replace(tmp, FILE)
    except BaseException:
        with contextlib.suppress(FileNotFoundError):
            os.unlink(tmp)
        raise


def key(kind, language):
    return "%s:%s" % (kind, language.lower())


def kept(kind, language):
    """The chart as last fetched ({fetched, art, tracks}), or None."""
    entry = _load().get(key(kind, language))
    return entry if isinstance(entry, dict) and entry.get("tracks") else None


def chart(kind, language, history, refresh=False, now=None):
    """A chart's songs, fetched when the copy kept is older than 12 hours (or
    refresh), less the songs history says you turned down."""
    now = time.time() if now is None else now
    entry = kept(kind, language)
    if refresh or not entry or now - (entry.get("fetched") or 0) > KEEP:
        where = sources_of(kind, language, _quietly(_saavn_charts, language) or [],
                           (_quietly(_youtube_charts) or {}) if youtube_title(kind, language) else {})
        lists = [_quietly(browse.jiosaavn_songs_at, where["saavn"]) if where["saavn"] else None,
                 _quietly(browse.youtube_songs, where["youtube"]) if where["youtube"] else None]
        songs = merge([songs for songs in lists if songs], ())
        if not songs:
            if entry:
                return _without_turned_down(entry["tracks"], history)
            raise SourceError("couldn't get the %s chart. Check the internet connection" % language)
        entry = {"fetched": now, "art": where["art"] or next((s.get("art") for s in songs if s.get("art")), ""),
                 "tracks": songs}
        data = _load()
        data[key(kind, language)] = entry
        _save(data)
    return _without_turned_down(entry["tracks"], history)


def _without_turned_down(songs, history):
    down = turned_down(history.plays, lambda tid: song_identity(history.track(tid) or {"id": tid}))
    return [s for s in songs if s.get("id") not in down and song_identity(s) not in down]


def languages(config_languages):
    """The languages to show charts for: the ones in the config that have charts."""
    return [lang for lang in (l.title() for l in config_languages or []) if lang in LANGUAGES] or ["Malayalam", "Tamil"]
