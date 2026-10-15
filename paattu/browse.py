"""Search beyond single songs: albums, singers and playlists from JioSaavn,
YouTube and SoundCloud, a page at a time; suggestions while typing; and the
songs of an album, a playlist or a singer.

Keep in step with the app (app/lib/src/sources and search_feed.dart).

Results that aren't songs are dicts:
    type      album | artist | playlist  (or song / query, for a suggestion)
    site      jiosaavn | youtube | soundcloud
    id, url   the site's id and page for it
    title, subtitle, art, artKey (its cached cover: art/c/<artKey>.jpg),
    count (songs, when known), year, language

Each site pages its own way, so a page comes with a cursor for the next one
(a page number, an offset or YouTube's continuation token), or None at the end.
"""

import concurrent.futures
import html
import json
import re
import time
import urllib.error
import urllib.parse
import urllib.request

from . import paths, sources, youtube
from .sources import JIOSAAVN_API, SourceError, is_link, track_id
from .titles import clean_title, song_key

KINDS = ("song", "album", "artist", "playlist")
KIND_SITES = {
    "song": ("jiosaavn", "youtube", "soundcloud"),
    "album": ("jiosaavn", "soundcloud"),
    "artist": ("jiosaavn", "youtube", "soundcloud"),
    "playlist": ("jiosaavn", "youtube", "soundcloud"),
}
PAGE = 20
BROWSER = "Mozilla/5.0 (X11; Linux x86_64; rv:140.0) Gecko/20100101 Firefox/140.0"


# ---------------------------------------------------------------- http

def _fetch(url, params=None, body=None, headers=None, timeout=15):
    if params:
        url += ("&" if "?" in url else "?") + urllib.parse.urlencode(params)
    head = {"User-Agent": BROWSER, **(headers or {})}
    data = None
    if body is not None:
        data = json.dumps(body).encode()
        head["Content-Type"] = "application/json"
    request = urllib.request.Request(url, data=data, headers=head)
    with urllib.request.urlopen(request, timeout=timeout) as response:
        return response.read().decode("utf-8", "replace")


def _json(url, params=None, body=None, headers=None, timeout=15):
    return json.loads(_fetch(url, params, body, headers, timeout))


def _int(value):
    try:
        return int(float(str(value).replace(",", "")))
    except (TypeError, ValueError):
        return None


def _text(node):
    """The words in one of YouTube's text objects."""
    if isinstance(node, str):
        return node
    if not isinstance(node, dict):
        return ""
    if "simpleText" in node:
        return node["simpleText"] or ""
    if "content" in node:
        return node["content"] or ""
    return "".join(run.get("text") or "" for run in node.get("runs") or [])


def _plural(n, word):
    return "%d %s%s" % (n, word, "" if n == 1 else "s")


def _short(n):
    """12400 → 12K, 1250000 → 1.3M (as Model.js formatCount)."""
    for size, unit in ((1e6, "M"), (1e3, "K")):
        if n >= size:
            text = "%.0f" % (n / size) if n >= size * 10 else "%.1f" % (n / size)
            return text.removesuffix(".0") + unit
    return str(n)


def _followers(n, word="follower"):
    return "%s %s%s" % (_short(n), word, "" if n == 1 else "s")


def art_key(item):
    """The cached cover's file name for an album, artist or playlist."""
    return re.sub(r"[^A-Za-z0-9._-]+", "_", "%s.%s.%s" % (item.get("site"), item.get("type"), item.get("id")))[:150]


def _with_key(item):
    if item:
        item["artKey"] = art_key(item)
    return item


# ---------------------------------------------------------------- JioSaavn

_SIZE_RE = re.compile(r"([-_])\d+x\d+\.(jpg|jpeg|png|webp)$")


def _big(url):
    """Albums' pictures end -150x150.jpg, artists' _50x50.jpg; both come in 500x500."""
    return _SIZE_RE.sub(r"\g<1>500x500.\2", url or "")


def _saavn(call, **params):
    return _json(JIOSAAVN_API, {"__call": call, "_format": "json", "_marker": "0", "api_version": "4",
                                "ctx": "web6dot0", **params})


def _unescape(text):
    return " ".join(html.unescape(text or "").split())


def _titled(text):
    return text[:1].upper() + text[1:].lower() if text else ""


def saavn_songs(items, limit=200):
    """JioSaavn songs, without the same film song again from a hits compilation."""
    tracks, seen = [], set()
    for track in (sources.jiosaavn_track(item) for item in items or []):
        if track and song_key(track) not in seen:
            seen.add(song_key(track))
            tracks.append(track)
    return tracks[:limit]


def jiosaavn_collection(item):
    """A JioSaavn album, playlist or artist as a result, or None."""
    item = item or {}
    kind = item.get("type") or ""
    info = item.get("more_info") or {}
    title = _unescape(item.get("title") or item.get("name"))
    if not title or not item.get("id"):
        return None
    count = _int(info.get("song_count")) or _int(item.get("numsongs"))
    base = {"type": kind, "site": "jiosaavn", "id": str(item["id"]), "url": item.get("perma_url") or "",
            "title": title, "art": _big(item.get("image"))}
    if kind == "album":
        music = _unescape(item.get("subtitle") or info.get("music"))
        year = str(item.get("year") or "")
        return _with_key({**base, "subtitle": " · ".join(s for s in (music, year) if s), "count": count, "year": year,
                          "language": _titled(item.get("language") or "")})
    if kind == "playlist":
        return _with_key({**base, "subtitle": _unescape(item.get("subtitle")), "count": count,
                          "language": _titled(info.get("language") or "")})
    if kind == "artist":
        role = item.get("description") or item.get("role") or ""
        return _with_key({**base, "subtitle": "Singer" if role in ("Artist", "Primary") else _titled(role)})
    return None


def _typed(items, kind):
    return [dict(item, type=item.get("type") or kind) for item in items or [] if isinstance(item, dict)]


def _jiosaavn_page(kind, query, cursor):
    page = _int(cursor) or 1
    if kind == "song":
        data = _saavn("search.getResults", q=query, n=str(PAGE), p=str(page))
        found = saavn_songs(data.get("results"))
        return found, (str(page + 1) if data.get("results") else None)
    call = {"album": "search.getAlbumResults", "playlist": "search.getPlaylistResults"}.get(kind, "search.getArtistResults")
    data = _saavn(call, q=query, n=str(PAGE), p=str(page))
    total = _int(data.get("total")) or 0
    if (page - 1) * PAGE >= total:
        return [], None
    found = [c for c in map(jiosaavn_collection, _typed(data.get("results"), kind)) if c]
    return found, (str(page + 1) if page * PAGE < total and data.get("results") else None)


def jiosaavn_songs_at(url):
    """The songs of a JioSaavn album or playlist page."""
    parts = [p for p in urllib.parse.urlparse(url).path.split("/") if p]
    kind = {"album": "album", "featured": "playlist", "s": "playlist", "playlist": "playlist"}.get(parts[0] if parts else "")
    if not kind or len(parts) < 2:
        raise SourceError("that JioSaavn link isn't an album or a playlist")
    data = _saavn("webapi.get", token=parts[-1], type=kind, n="200", p="1")
    return saavn_songs(data.get("songs") if isinstance(data.get("songs"), list) else data.get("list"))


def jiosaavn_artist(item, page=1):
    url = item.get("url") or ""
    token = [p for p in urllib.parse.urlparse(url).path.split("/") if p][-1] if url else ""
    if token:
        data = _saavn("webapi.get", type="artist", token=token, n_song="25", n_album="20", p=str(page),
                      category="", sort_order="")
    else:
        data = _saavn("artist.getArtistPageDetails", artistId=item.get("id") or "", n_song="25", n_album="20",
                      page=str(page), category="", sort_order="")

    def collections(items, kind):
        return [c for c in map(jiosaavn_collection, _typed(items, kind)) if c]

    songs = saavn_songs(data.get("topSongs"), 25)
    followers = _int(data.get("follower_count")) or _int(data.get("fan_count"))
    about = " · ".join(s for s in (_titled(data.get("dominantType") or ""),
                                   _followers(followers) if followers else "") if s)
    return {
        "name": _unescape(data.get("name")) or item.get("title") or "",
        "art": _big(data.get("image")) or item.get("art") or "",
        "about": about or item.get("subtitle") or "",
        "songs": songs,
        "albums": collections(data.get("topAlbums"), "album") + collections(data.get("singles"), "album"),
        "playlists": collections(data.get("dedicated_artist_playlist"), "playlist") if page == 1 else [],
        "similar": collections(data.get("similarArtists"), "artist") if page == 1 else [],
        "next": page + 1 if songs else None,
    }


def suggest_jiosaavn(query):
    data = _saavn("autocomplete.get", query=query)
    groups = sorted(((_int((data.get(key) or {}).get("position")) or 9, key)
                     for key in ("topquery", "songs", "albums", "artists", "playlists")))
    out, seen = [], set()
    for _, key in groups:
        for raw in (data.get(key) or {}).get("data") or []:
            kind = raw.get("type") or ""
            title = _unescape(raw.get("title"))
            subtitle = _unescape(raw.get("subtitle") or raw.get("description"))
            # The same song or album often comes twice under different ids.
            if not title or (kind, title.lower(), subtitle.lower()) in seen:
                continue
            seen.add((kind, title.lower(), subtitle.lower()))
            if kind == "song":
                info = raw.get("more_info") or {}
                out.append({"type": "song", "site": "jiosaavn", "id": raw.get("id") or "",
                            "url": raw.get("perma_url") or "", "title": title,
                            "subtitle": " · ".join(s for s in (_unescape(info.get("album")),
                                                               _unescape(info.get("primary_artists"))) if s),
                            "art": _big(raw.get("image")), "artKey": art_key({"site": "jiosaavn", "type": "song",
                                                                              "id": raw.get("id")})})
            else:
                found = jiosaavn_collection(raw)
                if found:
                    out.append(found)
    return out


# ---------------------------------------------------------------- YouTube
# The web site's own search: a page in about half a second (yt-dlp's
# ytsearch takes several and can't continue from where it stopped).

_YT_SEARCH = "https://www.youtube.com/youtubei/v1/search?prettyPrint=false"
_YT_CONTEXT = {"client": {"clientName": "WEB", "clientVersion": "2.20251001.00.00", "hl": "en", "gl": "IN"}}
_YT_FILTERS = {"song": "EgIQAQ==", "playlist": "EgIQAw==", "artist": "EgIQAg=="}
_YT_ITEMS = ("videoRenderer", "lockupViewModel", "playlistRenderer", "channelRenderer")


def _yt_walk(node, items, tokens):
    """Search results (in page order) and the continuation token in a response."""
    if isinstance(node, dict):
        for key, value in node.items():
            if key in _YT_ITEMS and isinstance(value, dict):
                items.append((key, value))
            elif key == "continuationCommand" and isinstance(value, dict) and value.get("token"):
                tokens.append(value["token"])
            else:
                _yt_walk(value, items, tokens)
    elif isinstance(node, list):
        for value in node:
            _yt_walk(value, items, tokens)


def _seconds(text):
    parts = [p for p in (text or "").strip().split(":") if p.isdigit()]
    if not parts:
        return None
    total = 0
    for p in parts:
        total = total * 60 + int(p)
    return total


def _biggest(images):
    images = [i for i in images or [] if i.get("url")]
    if not images:
        return ""
    url = max(images, key=lambda i: i.get("width") or 0)["url"]
    return "https:" + url if url.startswith("//") else url


def _yt_video(r):
    if not r.get("lengthText"):  # live now or still to come
        return None
    views = re.sub(r"[^\d]", "", _text(r.get("viewCountText")))
    return sources.youtube_track({"id": r.get("videoId") or "", "title": _text(r.get("title")),
                                  "channel": _text(r.get("ownerText") or r.get("longBylineText")),
                                  "duration": _seconds(_text(r.get("lengthText"))),
                                  "view_count": int(views) if views else None})


def _yt_playlist(key, r):
    if key == "lockupViewModel":
        if r.get("contentType") != "LOCKUP_CONTENT_TYPE_PLAYLIST":
            return None
        pid = r.get("contentId") or ""
        meta = (r.get("metadata") or {}).get("lockupMetadataViewModel") or {}
        title = _text(meta.get("title"))
        rows = ((meta.get("metadata") or {}).get("contentMetadataViewModel") or {}).get("metadataRows") or []
        owner = _text(((rows[0].get("metadataParts") or [{}])[0]).get("text")) if rows else ""
        image = ((r.get("contentImage") or {}).get("collectionThumbnailViewModel") or {}).get("primaryThumbnail") or {}
        badges = _find(image, "thumbnailBadgeViewModel", [])
        count = _int(re.sub(r"[^\d]", "", badges[0].get("text") or "")) if badges else None
        art = _biggest((((image.get("thumbnailViewModel") or {}).get("image")) or {}).get("sources"))
    else:
        pid = r.get("playlistId") or ""
        title = _text(r.get("title"))
        owner = _text(r.get("shortBylineText") or r.get("longBylineText"))
        count = _int(re.sub(r"[^\d]", "", _text(r.get("videoCountText")) or r.get("videoCount") or ""))
        art = _biggest(((r.get("thumbnails") or [{}])[0]).get("thumbnails"))
    # Mixes (RD…) are endless radio, not playlists.
    if not pid or not title or pid.startswith("RD"):
        return None
    return _with_key({"type": "playlist", "site": "youtube", "id": pid,
                      "url": "https://www.youtube.com/playlist?list=" + pid, "title": title,
                      "subtitle": " · ".join(s for s in (owner, _plural(count, "video") if count else "") if s),
                      "art": art, "count": count})


def _find(node, key, out):
    if isinstance(node, dict):
        for k, v in node.items():
            if k == key:
                out.append(v)
            else:
                _find(v, key, out)
    elif isinstance(node, list):
        for v in node:
            _find(v, key, out)
    return out


def _yt_channel(r):
    cid = r.get("channelId") or ""
    name = _text(r.get("title"))
    if not youtube.CHANNEL_ID_RE.match(cid) or not name:
        return None
    # YouTube puts the subscriber count in videoCountText and the @handle in
    # subscriberCountText.
    counts = [t for t in (_text(r.get("videoCountText")), _text(r.get("subscriberCountText"))) if "subscriber" in t]
    return _with_key({"type": "artist", "site": "youtube", "id": cid,
                      "url": "https://www.youtube.com/channel/" + cid, "title": name,
                      "subtitle": counts[0] if counts else "YouTube channel",
                      "art": _biggest((r.get("thumbnail") or {}).get("thumbnails"))})


def _youtube_page(kind, query, cursor):
    body = {"context": _YT_CONTEXT}
    if cursor:
        body["continuation"] = cursor
    else:
        body.update(query=query, params=_YT_FILTERS.get(kind, _YT_FILTERS["song"]))
    data = _json(_YT_SEARCH, body=body, headers={"Origin": "https://www.youtube.com"})
    items, tokens = [], []
    _yt_walk(data, items, tokens)
    found = []
    for key, r in items:
        if kind == "song" and key == "videoRenderer":
            found.append(_yt_video(r))
        elif kind == "playlist" and key in ("lockupViewModel", "playlistRenderer"):
            found.append(_yt_playlist(key, r))
        elif kind == "artist" and key == "channelRenderer":
            found.append(_yt_channel(r))
    found = [f for f in found if f]
    return found, (tokens[-1] if tokens and items else None)


_YT_SUGGEST = "https://suggestqueries.google.com/complete/search"


def suggest_youtube(query):
    data = _json(_YT_SUGGEST, {"client": "firefox", "ds": "yt", "hl": "en", "q": query}, timeout=6)
    return [s for s in (data[1] if isinstance(data, list) and len(data) > 1 else []) if isinstance(s, str)]


def youtube_songs(pid):
    """A YouTube playlist's songs (yt-dlp)."""
    details = youtube.playlist_details(pid)
    tracks = [sources.youtube_track({**t, "view_count": t.get("views")}) for t in details["tracks"]]
    return [t for t in tracks if t]


def youtube_channel(item):
    """A channel's most played uploads and its own playlists, side by side."""
    cid = item.get("id") or ""
    with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
        popular = pool.submit(youtube_songs, "UULP" + cid[2:])
        info = pool.submit(youtube.channel_playlists, item.get("url") or cid)
        try:
            channel = info.result()
        except Exception:  # the songs are the main thing
            channel = {}
        songs = popular.result()
    playlists = [_with_key({"type": "playlist", "site": "youtube", "id": p["id"],
                            "url": "https://www.youtube.com/playlist?list=" + p["id"], "title": p.get("title") or "",
                            "subtitle": channel.get("name") or "", "art": p.get("thumbnail") or ""})
                 for p in channel.get("playlists") or [] if not p.get("auto")]
    followers = channel.get("followers")
    return {"name": channel.get("name") or item.get("title") or "", "art": channel.get("avatar") or item.get("art") or "",
            "about": _followers(followers, "subscriber") if followers else item.get("subtitle") or "",
            "songs": songs, "albums": [], "playlists": playlists, "similar": [], "next": None}


# ---------------------------------------------------------------- SoundCloud
# The web player's API, with the client id its scripts carry (kept a day).

_SC_API = "https://api-v2.soundcloud.com"
_SC_SCRIPT_RE = re.compile(r"https://a-v2\.sndcdn\.com/assets/[^\"]+\.js")
_SC_ID_RE = re.compile(r"client_id\s*:\s*\"([0-9a-zA-Z]{32})\"")
_SC_FILE = paths.CACHE / "soundcloud.json"


def _sc_client_id(fresh=False):
    if not fresh:
        try:
            saved = json.loads(_SC_FILE.read_text())
            if saved.get("clientId") and time.time() - saved.get("at", 0) < 86400:
                return saved["clientId"]
        except (OSError, ValueError):
            pass
    page = _fetch("https://soundcloud.com/")
    # The id is in one of the last scripts the page loads.
    for script in reversed(_SC_SCRIPT_RE.findall(page)):
        try:
            found = _SC_ID_RE.search(_fetch(script))
        except Exception:
            continue
        if found:
            paths.CACHE.mkdir(parents=True, exist_ok=True)
            _SC_FILE.write_text(json.dumps({"clientId": found.group(1), "at": time.time()}))
            return found.group(1)
    raise SourceError("couldn't read SoundCloud's player (it may have changed)")


def _sc(path, **params):
    for attempt in range(2):
        client = _sc_client_id(fresh=attempt > 0)
        try:
            return _json(path if path.startswith("http") else _SC_API + path, {**params, "client_id": client})
        except urllib.error.HTTPError as error:
            if attempt or error.code not in (401, 403):
                raise


def _sc_art(t):
    art = t.get("artwork_url") or (t.get("user") or {}).get("avatar_url") or ""
    return art.replace("-large.", "-t500x500.")


def soundcloud_track(t):
    """A SoundCloud API track as a Paattu song, or None."""
    url = t.get("permalink_url") or ""
    title = t.get("title") or ""
    if not is_link(url) or not title or t.get("streamable") is False or t.get("policy") == "SNIP":
        return None
    channel = (t.get("user") or {}).get("username") or ""
    meta = clean_title(title, channel)
    publisher = t.get("publisher_metadata") or {}
    ms = _int(t.get("full_duration")) or _int(t.get("duration"))
    return {"id": track_id(url), "url": url, "site": "soundcloud", "rawTitle": title, "title": meta["title"] or title,
            "movie": publisher.get("album_title") or meta["movie"],
            "credits": sources._unique([publisher.get("artist") or ""] + meta["credits"])[:6], "kind": "song",
            "channel": channel, "duration": round(ms / 1000) if ms else None, "views": _int(t.get("playback_count")),
            "art": _sc_art(t)}


def _sc_tracks(items):
    out, seen = [], set()
    for track in map(soundcloud_track, [i for i in items if isinstance(i, dict)]):
        if track and track["id"] not in seen:
            seen.add(track["id"])
            out.append(track)
    return out


def soundcloud_collection(raw):
    url = raw.get("permalink_url") or ""
    if not is_link(url):
        return None
    if raw.get("kind") == "user":
        followers = _int(raw.get("followers_count"))
        return _with_key({"type": "artist", "site": "soundcloud", "id": str(raw.get("id") or ""), "url": url,
                          "title": raw.get("username") or "",
                          "subtitle": _followers(followers) if followers is not None else "",
                          "art": (raw.get("avatar_url") or "").replace("-large.", "-t500x500.")})
    if _int(raw.get("track_count")) == 0:
        return None
    return _with_key({"type": "album" if raw.get("is_album") else "playlist", "site": "soundcloud",
                      "id": str(raw.get("id") or ""), "url": url, "title": raw.get("title") or "",
                      "subtitle": (raw.get("user") or {}).get("username") or "", "art": _sc_art(raw),
                      "count": _int(raw.get("track_count"))})


def _soundcloud_page(kind, query, cursor):
    offset = _int(cursor) or 0
    path = {"song": "/search/tracks", "album": "/search/albums",
            "playlist": "/search/playlists_without_albums"}.get(kind, "/search/users")
    data = _sc(path, q=query, limit=str(PAGE), offset=str(offset))
    items = data.get("collection") or []
    found = _sc_tracks(items) if kind == "song" else [c for c in map(soundcloud_collection, items) if c]
    return found, (str(offset + PAGE) if items and data.get("next_href") else None)


def soundcloud_songs_at(url):
    """The songs of a SoundCloud track, set or profile page."""
    data = _sc("/resolve", url=url)
    kind = data.get("kind")
    if kind == "track":
        return _sc_tracks([data])
    if kind in ("playlist", "system-playlist"):
        items = data.get("tracks") or []
        # Sets list the first few tracks in full and the rest as bare ids.
        full = {str(t.get("id")): t for t in items if t.get("title")}
        stubs = [str(t.get("id")) for t in items if not t.get("title")]
        for i in range(0, len(stubs), 50):
            for t in _sc("/tracks", ids=",".join(stubs[i:i + 50])) or []:
                full[str(t.get("id"))] = t
        return _sc_tracks([full.get(str(t.get("id"))) for t in items])
    if kind == "user":
        return _sc_tracks((_sc("/users/%s/tracks" % data.get("id"), limit="50") or {}).get("collection") or [])
    raise SourceError("that SoundCloud link isn't a track, set or profile")


def soundcloud_user(item):
    songs = soundcloud_songs_at(item.get("url") or "")
    return {"name": item.get("title") or "", "art": item.get("art") or "", "about": item.get("subtitle") or "",
            "songs": songs, "albums": [], "playlists": [], "similar": [], "next": None}


# ---------------------------------------------------------------- pages from every site

PAGERS = {"jiosaavn": _jiosaavn_page, "youtube": _youtube_page, "soundcloud": _soundcloud_page}


def result_key(item):
    """What makes two results the same: a film song is the same song on every
    site (the 320 kbps JioSaavn copy, asked first, stands for it); anything
    else only on its own site."""
    kind = item.get("type") or "song"
    if kind == "song":
        if item.get("movie") and item.get("title"):
            return "song|" + song_key(item)
        return "song|" + str(item.get("id"))
    return "%s|%s|%s" % (kind, item.get("site"), item.get("id"))


def interleave(pages, seen):
    """Pages from several sites as one list, a result from each in turn,
    leaving out anything already in seen (which grows)."""
    out = []
    for i in range(max((len(p) for p in pages), default=0)):
        for page in pages:
            if i < len(page):
                key = result_key(page[i])
                if key not in seen:
                    seen.add(key)
                    out.append(page[i])
    return out


def _reason(error):
    if isinstance(error, urllib.error.HTTPError):
        return "the site answered %d" % error.code
    return sources._reason(error)


def search(query, kind="song", sites=sources.SEARCH_SITES, cursors=None, seen=()):
    """One page of kind from each site. cursors: {site: cursor} from the last
    page (None: start; a site missing from it is finished).
    Returns (results, {site: next cursor}, {site: error})."""
    if kind not in KIND_SITES:
        raise ValueError("search for one of: " + ", ".join(KINDS))
    sites = [s for s in sources.SEARCH_SITES if s in sites and s in KIND_SITES[kind]] or [
        s for s in sources.SEARCH_SITES if s in KIND_SITES[kind]]  # none of them has it: the sites that do
    if cursors is not None:
        sites = [s for s in sites if cursors.get(s)]
    pages, following, errors = {}, {}, {}
    with concurrent.futures.ThreadPoolExecutor(max_workers=len(sites) or 1) as pool:
        jobs = {s: pool.submit(PAGERS[s], kind, query, (cursors or {}).get(s)) for s in sites}
        for site, job in jobs.items():
            try:
                pages[site], following[site] = job.result(timeout=40)
            except Exception as error:  # one site failing shouldn't sink the others
                errors[site] = _reason(error)
                pages[site], following[site] = [], None
    results = interleave([pages[s] for s in sites], set(seen))
    return results, {s: c for s, c in following.items() if c}, errors


def suggest(query):
    """YouTube's search phrases (type 'query'), then JioSaavn's songs, albums,
    singers and playlists for a few typed letters."""
    q = (query or "").strip()
    if not q or is_link(q):
        return []
    with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
        phrases, things = pool.submit(suggest_youtube, q), pool.submit(suggest_jiosaavn, q)
        try:
            words = phrases.result(timeout=8)
        except Exception:
            words = []
        try:
            found = things.result(timeout=8)
        except Exception:
            found = []
    words = [w for w in words if w.lower() != q.lower()][:6]
    return [{"type": "query", "title": w} for w in words] + found[:8]


def collection_songs(item):
    """The songs of an album or playlist from a search."""
    site, url = item.get("site"), item.get("url") or ""
    if site == "youtube":
        songs = youtube_songs(item.get("id") or url)
    elif site == "jiosaavn":
        songs = jiosaavn_songs_at(url)
    elif site == "soundcloud":
        songs = soundcloud_songs_at(url)
    else:
        songs = sources.resolve(url)
    if not songs:
        raise SourceError("no songs there")
    return songs


def artist(item, page=1):
    """A singer's or channel's page: name, art, about, songs, albums,
    playlists, similar artists, and the next page of songs (or None)."""
    site = item.get("site")
    if site == "jiosaavn":
        return jiosaavn_artist(item, page)
    if site == "youtube":
        return youtube_channel(item)
    if site == "soundcloud":
        return soundcloud_user(item)
    raise SourceError("can't open that")
