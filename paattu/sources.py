"""Songs from outside the library: search JioSaavn, YouTube and SoundCloud, or
take a link from any site yt-dlp can play.

JioSaavn carries the labels' Malayalam and Tamil film albums and streams most
of them at 320 kbps AAC, so it comes first. YouTube has everything else
(Opus, about 130-160 kbps), SoundCloud the covers and remixes. A link can be
from Bandcamp, Audiomack, archive.org, a direct audio file and so on.

Track ids: a YouTube song keeps its video id. A song from anywhere else is
keyed by its link (host, path and query made filename-safe), so the shell can
tell which song mpv is playing from its path alone (Model.js trackId does the
same). Such tracks carry the link they play from in "url".

Search results are remembered in ~/.cache/paattu/search.json, so a song found
in a search can be played, hearted, saved or added to a playlist by its id.
"""

import concurrent.futures
import contextlib
import html
import json
import os
import re
import tempfile
import unicodedata
import urllib.parse
import urllib.request

from . import paths, youtube

SITES = {"jiosaavn": "JioSaavn", "youtube": "YouTube", "soundcloud": "SoundCloud"}
SEARCH_SITES = ("jiosaavn", "youtube", "soundcloud")
JIOSAAVN_API = "https://www.jiosaavn.com/api.php"
USER_AGENT = "Mozilla/5.0 (X11; Linux x86_64) Paattu/1.0"
REMEMBER = 400
LOSSLESS = ("flac", "alac", "wav", "aiff", "ape", "wavpack")

_LINK_RE = re.compile(r"^https?://([^/?#]+)([^?#]*)(?:\?([^#]*))?", re.I)
_YOUTUBE_HOST_RE = re.compile(r"(^|\.)(youtube\.com|youtu\.be|youtube-nocookie\.com)$")
_VIDEO_ID_RE = re.compile(r"^[\w-]{11}$")


class SourceError(Exception):
    pass


# ---------------------------------------------------------------- ids and links

def is_link(text):
    return bool(_LINK_RE.match((text or "").strip()))


def _host(url):
    found = _LINK_RE.match((url or "").strip())
    if not found:
        return ""
    host = found.group(1).lower()
    return host[4:] if host.startswith("www.") else host


def is_youtube(url):
    return bool(_YOUTUBE_HOST_RE.search(_host(url)))


def is_video_id(track_id):
    return bool(_VIDEO_ID_RE.match(track_id or ""))


def track_id(url):
    """A link's track id: the video id for YouTube, else its host and path
    made filename-safe (never 11 characters of [A-Za-z0-9_-], so it can't be
    mistaken for a video id). Keep in step with trackId in Model.js."""
    url = (url or "").strip()
    found = _LINK_RE.match(url)
    if not found:
        return youtube.video_id(url)
    if is_youtube(url):
        return youtube.video_id(url)
    path = found.group(2).rstrip("/")
    query = found.group(3) or ""
    key = re.sub(r"[^A-Za-z0-9._-]+", "_", _host(url) + path + ("?" + query if query else ""))[:150]
    return "link." + key if is_video_id(key) else key


def track_url(track):
    """What mpv plays for a track."""
    return track.get("url") or youtube.watch_url(track["id"])


def site_of(url):
    """jiosaavn, youtube, soundcloud, or the host of any other site."""
    host = _host(url)
    if not host or is_youtube(url):
        return "youtube"
    if re.search(r"(^|\.)(jio)?saavn\.com$", host):
        return "jiosaavn"
    if re.search(r"(^|\.)soundcloud\.com$", host):
        return "soundcloud"
    return host


def site_name(site):
    return SITES.get(site, site or "")


def quality_label(track):
    """"Lossless", "320 kbps", or "" when the site doesn't say."""
    if (track.get("codec") or "").lower() in LOSSLESS:
        return "Lossless"
    return "%d kbps" % track["quality"] if track.get("quality") else ""


# ---------------------------------------------------------------- search

def _get_json(url, params, timeout=15):
    request = urllib.request.Request(url + "?" + urllib.parse.urlencode(params),
                                     headers={"User-Agent": USER_AGENT, "Accept": "application/json"})
    with urllib.request.urlopen(request, timeout=timeout) as response:
        return json.loads(response.read().decode("utf-8", "replace"))


def _int(value):
    try:
        return int(float(value))
    except (TypeError, ValueError):
        return None


def _unique(names):
    out = []
    for name in names:
        name = " ".join(html.unescape(name or "").split())
        if name and name not in out:
            out.append(name)
    return out


_FROM_RE = re.compile(r"\s*\((?:From|from)\s+[\"“]([^\"”]+)[\"”]\)\s*$")
_SOUNDTRACK_RE = re.compile(r"\s*\((?:Original Motion Picture Soundtrack|Original Soundtrack|OST|Original Score)[^)]*\)\s*$", re.I)
_LANGUAGE_SUFFIX_RE = re.compile(r"\s+-\s+(?:Malayalam|Tamil|Telugu|Kannada|Hindi)$", re.I)


def film_and_title(title, album):
    """JioSaavn: 'Malare (From "Premam")' on a hits album is Malare from Premam;
    an album 'Devara Part 1 - Telugu (Original Motion Picture Soundtrack)' is the film."""
    found = _FROM_RE.search(title)
    if found:
        return title[:found.start()].strip(), found.group(1).strip()
    film = _LANGUAGE_SUFFIX_RE.sub("", _SOUNDTRACK_RE.sub("", album)).strip()
    return title, "" if film.lower() == title.lower() else film


def jiosaavn_track(item):
    """A JioSaavn search result (api_version 4, or the older flat shape)."""
    url = item.get("perma_url") or ""
    if (item.get("type") or "song") != "song" or not is_link(url):
        return None
    info = item.get("more_info") or {}
    pick = lambda key: info.get(key) if info.get(key) not in (None, "") else item.get(key)
    raw_title = html.unescape(item.get("title") or item.get("song") or "").strip()
    album = html.unescape(pick("album") or "").strip()
    title, film = film_and_title(raw_title, album)
    artists = info.get("artistMap") or {}
    music = [a.get("name") for a in artists.get("artists") or [] if a.get("role") == "music"]
    singers = [a.get("name") for a in (artists.get("primary_artists") or []) + (artists.get("featured_artists") or [])]
    if not music and not singers:
        music = (pick("music") or "").split(", ")
        singers = (item.get("primary_artists") or item.get("singers") or "").split(", ")
    image = item.get("image") or ""
    return {
        "id": track_id(url),
        "url": url,
        "site": "jiosaavn",
        "rawTitle": raw_title,
        "title": title,
        "movie": film,
        "album": album,
        "credits": _unique(music + singers)[:6],
        "kind": "song",
        "channel": html.unescape(pick("label") or ""),
        "duration": _int(pick("duration")),
        "views": _int(item.get("play_count")),
        "language": (item.get("language") or "").title(),
        "year": str(item.get("year") or ""),
        "quality": 320 if str(pick("320kbps")).lower() == "true" else 128,
        "codec": "aac",
        "art": re.sub(r"-\d+x\d+\.(jpg|jpeg|png|webp)$", r"-500x500.\1", image),
    }


def search_jiosaavn(query, limit=12):
    data = _get_json(JIOSAAVN_API, {"__call": "search.getResults", "_format": "json", "_marker": "0",
                                    "api_version": "4", "ctx": "web6dot0", "n": str(min(limit * 2, 50)), "p": "1", "q": query})
    tracks, seen = [], set()
    for track in (jiosaavn_track(item) for item in (data or {}).get("results") or []):
        # The same film song turns up again on hits compilations.
        key = (track["title"].lower(), track["movie"].lower()) if track else None
        if track and key not in seen:
            seen.add(key)
            tracks.append(track)
    return tracks[:limit]


def youtube_track(entry):
    from .titles import clean_title

    vid = entry.get("id") or ""
    title = entry.get("title") or ""
    if not is_video_id(vid) or not title or title.lower() in youtube.UNAVAILABLE:
        return None
    if entry.get("live_status") in ("is_live", "is_upcoming") or entry.get("availability") in (
            "private", "needs_auth", "subscriber_only", "premium_only"):
        return None
    channel = entry.get("channel") or entry.get("uploader") or ""
    meta = clean_title(title, channel)
    return {"id": vid, "site": "youtube", "rawTitle": title, "title": meta["title"] or title, "movie": meta["movie"],
            "credits": meta["credits"][:6], "kind": meta["kind"], "channel": channel,
            "duration": _int(entry.get("duration")), "views": entry.get("view_count")}


def search_youtube(query, limit=12):
    data = youtube.lookup("ytsearch%d:%s" % (limit, query), timeout=60)
    return [t for t in (youtube_track(e) for e in data.get("entries") or []) if t]


# How many videos found by search are tried for a song's picture.
VIDEO_TRIES = 3


def video_for(track):
    """The song's video, small and silent, for a blurred background
    (youtube.small_video): its own for a YouTube song, unless that is its
    cover held still (a YouTube Music art track), else the first video found
    by searching YouTube whose length is within 20 s of the song's and whose
    picture moves (most film songs are there as a lyric or video song). None
    when there isn't one. Keep in step with videoFor in the app."""
    own = track.get("id") or ""
    if is_video_id(own):
        video = youtube.small_video(own)
        if video:
            return video
    else:
        own = ""
    seconds = _int(track.get("duration"))
    credits = track.get("credits") or []
    query = " ".join(s for s in (track.get("title") or "", credits[0] if credits else track.get("movie") or "") if s)
    if not seconds or not query:
        return None
    found = [t for t in search_youtube(query, limit=6)
             if t["id"] != own and t["duration"] and abs(t["duration"] - seconds) <= 20]
    for t in found[:VIDEO_TRIES]:
        try:
            video = youtube.small_video(t["id"])
        except youtube.YouTubeError:
            continue
        if video:
            return video
    return None


def _thumbnail(thumbnails, prefer=("t500x500", "crop", "t300x300", "original")):
    by_id = {t.get("id"): t.get("url") for t in thumbnails or [] if t.get("url")}
    for key in prefer:
        if by_id.get(key):
            return by_id[key]
    sized = sorted((t for t in thumbnails or [] if t.get("url")), key=lambda t: t.get("width") or 0)
    return sized[-1]["url"] if sized else ""


def soundcloud_track(entry):
    from .titles import clean_title

    url = entry.get("webpage_url") or ""
    title = entry.get("title") or ""
    if not is_link(url) or not title:
        return None
    channel = entry.get("uploader") or ""
    meta = clean_title(title, channel)
    return {"id": track_id(url), "url": url, "site": "soundcloud", "rawTitle": title,
            "title": meta["title"] or title, "movie": meta["movie"], "credits": meta["credits"][:6],
            "kind": "song", "channel": channel, "duration": _int(entry.get("duration")),
            "views": entry.get("view_count"), "art": _thumbnail(entry.get("thumbnails"))}


def search_soundcloud(query, limit=12):
    data = youtube.lookup("scsearch%d:%s" % (limit, query), timeout=60)
    return [t for t in (soundcloud_track(e) for e in data.get("entries") or []) if t]


SEARCHERS = {"jiosaavn": search_jiosaavn, "youtube": search_youtube, "soundcloud": search_soundcloud}


def _reason(error):
    text = str(error) or error.__class__.__name__
    if "timed out" in text.lower():
        return "didn't answer in time"
    return re.sub(r"^<urlopen error (.*)>$", r"\1", text)


def search(query, sites=SEARCH_SITES, limit=12):
    """Search the sites at once. Returns ({site: [tracks]}, {site: error})."""
    sites = [s for s in sites if s in SEARCHERS]
    found, errors = {}, {}
    with concurrent.futures.ThreadPoolExecutor(max_workers=len(sites) or 1) as pool:
        jobs = {site: pool.submit(SEARCHERS[site], query, limit) for site in sites}
        for site, job in jobs.items():
            try:
                found[site] = job.result()
            except Exception as error:  # one site failing shouldn't sink the others
                errors[site] = _reason(error)
                found[site] = []
    return found, errors


# ---------------------------------------------------------------- the same song elsewhere

QUALITY_ORDER = ("jiosaavn", "youtube", "soundcloud")


def _words(text):
    """Words of letters, marks and digits (the app's [\\p{L}\\p{M}\\p{N}]+:
    Malayalam and Tamil vowel signs are marks, which \\w leaves out)."""
    chars = [c if unicodedata.category(c)[0] in "LMN" else " " for c in (text or "").lower()]
    return "".join(chars).split()


def track_site(track):
    return track.get("site") or site_of(track_url(track))


def same_song(a, b):
    """Whether a and b are one song on two sites: the same title (or one the
    start of the other, "Malare" and "Malare Reprise" aside), not from two
    different films, and about as long (or, length unknown, from the same
    film). Keep in step with sameSong in the app."""
    ta, tb = _words(a.get("title")), _words(b.get("title"))
    if not ta or not tb:
        return False
    short, long = (ta, tb) if len(ta) <= len(tb) else (tb, ta)
    if long[:len(short)] != short:
        return False
    same_title = len(short) == len(long)
    ma, mb = " ".join(_words(a.get("movie"))), " ".join(_words(b.get("movie")))
    both_movies = bool(ma and mb)
    same_movie = both_movies and (mb in ma or ma in mb)
    if both_movies and not same_movie:
        return False
    da, db = _int(a.get("duration")), _int(b.get("duration"))
    if da and db and da > 0 and db > 0:
        return abs(da - db) <= 20
    return same_title and same_movie


def alternates_for(track):
    """track on the other sites, best sound first, for when its own stream
    won't play. One copy a site at most; a site that fails is left out."""
    title = track.get("title") or ""
    if not title or track.get("kind") == "jukebox":
        return []
    credits = track.get("credits") or []
    query = " ".join(x for x in (title, track.get("movie") or (credits[0] if credits else "")) if x)
    own = track_site(track)
    sites = [site for site in QUALITY_ORDER if site != own]
    found, _ = search(query, sites, 6)
    out = []
    for site in sites:
        match = next((t for t in found.get(site) or [] if same_song(track, t)), None)
        if match:
            out.append(match)
    return out


# ---------------------------------------------------------------- links

def _best_audio(info):
    """(kbps, codec) of the best audio yt-dlp found; lossless beats any bitrate."""
    best_rank, best = -1, (0, "")
    for f in info.get("formats") or [info]:
        if f.get("acodec") == "none":
            continue
        codec = (f.get("acodec") or "").split(".")[0].lower()
        if codec in ("", "unknown"):
            ext = (f.get("ext") or "").lower()
            codec = {"m4a": "aac", "ogg": "vorbis"}.get(ext, ext if ext in LOSSLESS + ("mp3", "opus") else "")
        kbps = round(f.get("abr") or f.get("tbr") or 0)
        rank = kbps + (10000 if codec in LOSSLESS else 0)
        if rank > best_rank:
            best_rank, best = rank, (kbps, codec)
    return best


def link_track(info, url=""):
    """A song yt-dlp read from a link (any site, or a direct audio file)."""
    from .titles import clean_title

    page = info.get("webpage_url") or info.get("url") or url
    if is_youtube(page):
        return youtube_track({**info, "id": youtube.video_id(page) or info.get("id")})
    # A direct file: play the link itself, not what it redirected to.
    if info.get("extractor_key") == "Generic" or not info.get("webpage_url"):
        page = url or page
    if not is_link(page):
        return None
    raw = info.get("track") or info.get("title") or urllib.parse.unquote(page.rsplit("/", 1)[-1])
    artist = info.get("artist") or info.get("creator") or info.get("uploader") or info.get("channel") or ""
    meta = clean_title(raw, artist)
    kbps, codec = _best_audio(info)
    credits = _unique([artist] + list(info.get("artists") or []) + meta["credits"])
    return {"id": track_id(page), "url": page, "site": site_of(page), "rawTitle": info.get("title") or raw,
            "title": (info.get("track") or meta["title"] or raw).strip(), "movie": info.get("album") or meta["movie"],
            "credits": credits[:6], "kind": "song", "channel": info.get("uploader") or info.get("channel") or "",
            "duration": _int(info.get("duration")), "views": info.get("view_count"),
            "quality": kbps or None, "codec": codec, "art": info.get("thumbnail") or _thumbnail(info.get("thumbnails"))}


def resolve(url, limit=200):
    """The songs behind a link: one track, or every track of an album / set."""
    info = youtube.lookup(url, timeout=120)
    entries = info.get("entries")
    if entries is None:
        track = link_track(info, url)
        if not track:
            raise SourceError("couldn't find a song at that link")
        return [track]
    tracks = []
    for entry in list(entries)[:limit]:
        target = entry.get("webpage_url") or entry.get("url") or ""
        if entry.get("ie_key") == "Youtube" or is_youtube(target):
            track = youtube_track(entry)
        else:
            track = link_track({**entry, "webpage_url": target}, target)
        if track and track["id"] not in {t["id"] for t in tracks}:
            tracks.append(track)
    if not tracks:
        raise SourceError("no songs at that link")
    return tracks


# ---------------------------------------------------------------- remembered results

def _load():
    try:
        with open(paths.SEARCH, encoding="utf-8") as f:
            return json.load(f)
    except (FileNotFoundError, json.JSONDecodeError):
        return {}


def remember(tracks):
    """Keep tracks found by a search or a link, newest last."""
    if not tracks:
        return
    known = _load()
    for track in tracks:
        known.pop(track["id"], None)
        known[track["id"]] = track
    keep = dict(list(known.items())[-REMEMBER:])
    paths.CACHE.mkdir(parents=True, exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=paths.CACHE, prefix=".search.", suffix=".json")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            json.dump(keep, f, ensure_ascii=False, separators=(",", ":"))
        os.replace(tmp, paths.SEARCH)
    except BaseException:
        with contextlib.suppress(FileNotFoundError):
            os.unlink(tmp)
        raise


def recall(tid):
    """A song found earlier by a search or a link, or None."""
    return _load().get(tid)
