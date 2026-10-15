"""YouTube Music without an account: its song search (clean titles, singers
and films, the labels' own uploads) and its radio, the endless list of songs
like one song that YouTube Music plays after it. Both are the web app's own
calls; the app's youtube_music.dart makes the same ones.
"""

import json
import re
import urllib.request

from .sources import film_and_title, is_video_id

CLIENT = {"clientName": "WEB_REMIX", "clientVersion": "1.20250101.01.00", "hl": "en", "gl": "IN"}
SEARCH_API = "https://music.youtube.com/youtubei/v1/search?prettyPrint=false"
NEXT_API = "https://music.youtube.com/youtubei/v1/next?prettyPrint=false"
HEADERS = {"Origin": "https://music.youtube.com", "Referer": "https://music.youtube.com/",
           "User-Agent": "Mozilla/5.0 (X11; Linux x86_64; rv:140.0) Gecko/20100101 Firefox/140.0",
           "Content-Type": "application/json"}
SONGS_ONLY = "EgWKAQIIAWoKEAoQAxAEEAkQBQ=="  # the search's "Songs" filter


def _post(url, body, timeout=15):
    request = urllib.request.Request(url, data=json.dumps(body).encode(), headers=HEADERS)
    with urllib.request.urlopen(request, timeout=timeout) as response:
        return json.loads(response.read().decode("utf-8", "replace"))


def search(query, limit=20):
    """Songs on YouTube Music for query, best match first."""
    response = _post(SEARCH_API, {"context": {"client": CLIENT}, "query": query, "params": SONGS_ONLY})
    return search_songs(response)[:limit]


def radio(video_id, more=None):
    """(songs, token for the next helping) like the song video_id (the first
    is that song), or the next helping with more."""
    body = {"context": {"client": CLIENT}, "isAudioOnly": True}
    if more:
        body["continuation"] = more
    else:
        body.update(videoId=video_id, playlistId="RDAMVM" + video_id)
    return radio_page(_post(NEXT_API, body))


def _all(node, key, out=None):
    """Every object under key, anywhere in node, in order."""
    out = [] if out is None else out
    if isinstance(node, dict):
        for k, value in node.items():
            if k == key and isinstance(value, dict):
                out.append(value)
            else:
                _all(value, key, out)
    elif isinstance(node, list):
        for value in node:
            _all(value, key, out)
    return out


def _runs(text):
    out = []
    for run in (text or {}).get("runs") or []:
        page = (((run.get("navigationEndpoint") or {}).get("browseEndpoint") or {})
                .get("browseEndpointContextSupportedConfigs") or {}).get("browseEndpointContextMusicConfig") or {}
        out.append((run.get("text") or "", page.get("pageType") or ""))
    return out


def search_songs(response):
    """The songs in a search response."""
    songs = []
    for item in _all(response, "musicResponsiveListItemRenderer"):
        columns = [_runs((c.get("musicResponsiveListItemFlexColumnRenderer") or {}).get("text"))
                   for c in item.get("flexColumns") or []]
        if not columns:
            continue
        art = ((item.get("thumbnail") or {}).get("musicThumbnailRenderer") or {}).get("thumbnail")
        song = _song((item.get("playlistItemData") or {}).get("videoId") or "", "".join(t for t, _ in columns[0]),
                     columns[1] if len(columns) > 1 else [], art=_thumbnail(art))
        if song:
            songs.append(song)
    return songs


def radio_page(response):
    """(songs, next token) in a radio response."""
    songs = []
    for item in _all(response, "playlistPanelVideoRenderer"):
        song = _song(item.get("videoId") or "", "".join(t for t, _ in _runs(item.get("title"))),
                     _runs(item.get("longBylineText")), length="".join(t for t, _ in _runs(item.get("lengthText"))),
                     art=_thumbnail(item.get("thumbnail")))
        if song:
            songs.append(song)
    tokens = [c.get("continuation") for c in
              _all(response, "nextRadioContinuationData") + _all(response, "nextContinuationData")]
    return songs, next((t for t in tokens if t), None)


_TIME_RE = re.compile(r"^\d{1,2}(?::\d\d){1,2}$")
_CREDIT_SPLIT_RE = re.compile(r"\s*(?:,|&)\s*")
# "Irupathu Kodi (Language: Tamil; Film: Thullatha Manamum Thullum; Film Artist 1: Vijay)"
_LABEL_NOTES_RE = re.compile(r"\s*\((?:Language|Film)\s*:[^)]*\)\s*$", re.I)
_NOTE_FILM_RE = re.compile(r"(?:^|;)\s*Film\s*:\s*([^;)]+)", re.I)


def _unique(names):
    out = []
    for name in names:
        name = " ".join((name or "").split())
        if name and name not in out:
            out.append(name)
    return out


def _seconds(text):
    text = (text or "").strip()
    if not _TIME_RE.match(text):
        return None
    total = 0
    for part in text.split(":"):
        total = total * 60 + int(part)
    return total


def _song(vid, heading, details, length="", art=""):
    """A song from its title and the line under it ("Singer, Singer • Film
    (Original Motion Picture Soundtrack) • 1985", the length on its own in a
    search), in the shape of sources.youtube_track."""
    raw_title = " ".join(heading.split())
    if not is_video_id(vid) or not raw_title:
        return None
    artists, album, seconds, segment = [], "", _seconds(length), 0
    for text, page in details:
        text = text.strip()
        if text == "•":
            segment += 1
        elif page in ("MUSIC_PAGE_TYPE_ARTIST", "MUSIC_PAGE_TYPE_USER_CHANNEL"):
            artists.append(text)
        elif page == "MUSIC_PAGE_TYPE_ALBUM":
            album = text
        elif _TIME_RE.match(text):
            seconds = seconds if seconds is not None else _seconds(text)
        elif segment == 0:
            artists.extend(_CREDIT_SPLIT_RE.split(text))  # singers without a page
    title, film = raw_title, ""
    notes = _LABEL_NOTES_RE.search(title)
    if notes:
        found = _NOTE_FILM_RE.search(notes.group(0))
        film = found.group(1).strip() if found else ""
        title = title[:notes.start()].strip()
    clean, from_album = film_and_title(title, album)
    credits = _unique(artists)[:6]
    song = {"id": vid, "site": "youtube", "rawTitle": raw_title, "title": clean, "movie": film or from_album,
            "credits": credits, "kind": "audio", "channel": credits[0] if credits else "", "duration": seconds}
    if art:
        song["art"] = art
    return song


_ART_SIZE_RE = re.compile(r"=w\d+-h\d+(-[a-z0-9-]+)?$")


def _thumbnail(thumbnail):
    """The song's square cover, 544 pixels (YouTube Music's own big size)."""
    images = (thumbnail or {}).get("thumbnails") or []
    if not images:
        return ""
    url = images[-1].get("url") or ""
    if "googleusercontent.com" not in url:
        return ""
    return _ART_SIZE_RE.sub("=w544-h544-l90-rj", url)
