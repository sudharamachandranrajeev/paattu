"""Read public YouTube channels and playlists with yt-dlp (no account, no API key)."""

import json
import re
import subprocess
import urllib.parse

YTDLP = ["yt-dlp", "--ignore-config", "--no-warnings", "--socket-timeout", "20", "--flat-playlist", "-J"]
UNAVAILABLE = {"[private video]", "[deleted video]", "[unavailable video]"}
CHANNEL_ID_RE = re.compile(r"^UC[\w-]{22}$")
PLAYLIST_ID_RE = re.compile(r"^(?:PL|OLAK5uy_|UU|FL|LL|VL|RDCLAK5uy_|OL)[\w-]{8,}$")


class YouTubeError(Exception):
    pass


def _run(url, timeout=180, extra=()):
    try:
        proc = subprocess.run(YTDLP + list(extra) + [url], capture_output=True, text=True, timeout=timeout)
    except FileNotFoundError:
        raise YouTubeError("yt-dlp is not installed")
    except subprocess.TimeoutExpired:
        raise YouTubeError("YouTube didn't answer in time (is the firewall asking about python?)")
    if proc.returncode != 0 or not proc.stdout.strip():
        lines = [l for l in proc.stderr.strip().splitlines() if l.strip()]
        message = lines[-1] if lines else "yt-dlp failed"
        raise YouTubeError(re.sub(r"^ERROR:\s*(\[[^\]]+\]\s*)?", "", message))
    return json.loads(proc.stdout)


def lookup(target, timeout=60, extra=()):
    """yt-dlp's JSON for a link or a search ("ytsearch10:…", "scsearch10:…");
    lists come back flat (one entry per item, not resolved)."""
    return _run(target, timeout=timeout, extra=extra)


def normalize_user(query):
    """A channel's base URL from @handle, handle, channel id or any channel URL."""
    q = (query or "").strip()
    if not q:
        raise YouTubeError("Give a YouTube @handle or channel URL")
    if q.startswith(("http://", "https://", "www.", "youtube.com", "music.youtube.com", "m.youtube.com")):
        if not q.startswith("http"):
            q = "https://" + q
        parsed = urllib.parse.urlparse(q)
        parts = [p for p in parsed.path.split("/") if p]
        if not parts:
            raise YouTubeError("That URL doesn't point at a channel")
        if parts[0].startswith("@"):
            return "https://www.youtube.com/" + parts[0]
        if parts[0] in ("channel", "c", "user") and len(parts) > 1:
            return "https://www.youtube.com/" + parts[0] + "/" + parts[1]
        raise YouTubeError("That URL doesn't point at a channel")
    if CHANNEL_ID_RE.match(q):
        return "https://www.youtube.com/channel/" + q
    return "https://www.youtube.com/@" + q.lstrip("@").split("/")[0].replace(" ", "")


def normalize_playlist(query):
    """A playlist id from a playlist / watch URL or a bare id."""
    q = (query or "").strip()
    if PLAYLIST_ID_RE.match(q):
        return q[2:] if q.startswith("VL") else q
    if "list=" in q:
        params = urllib.parse.parse_qs(urllib.parse.urlparse(q if "://" in q else "https://" + q).query)
        if params.get("list"):
            return params["list"][0]
    raise YouTubeError("That isn't a YouTube playlist link")


def video_id(query):
    """A video id from a watch / youtu.be / music URL or a bare 11-char id."""
    q = (query or "").strip()
    if re.match(r"^[\w-]{11}$", q):
        return q
    parsed = urllib.parse.urlparse(q if "://" in q else "https://" + q)
    if parsed.netloc.endswith("youtu.be"):
        return parsed.path.strip("/")[:11] or None
    params = urllib.parse.parse_qs(parsed.query)
    if params.get("v"):
        return params["v"][0][:11]
    found = re.search(r"/(?:shorts|embed|live)/([\w-]{11})", parsed.path)
    return found.group(1) if found else None


def classify(query):
    """What a pasted link is: ('playlist', id) or ('user', channel URL)."""
    q = (query or "").strip()
    if not q:
        raise YouTubeError("Paste a YouTube profile or playlist link")
    try:
        return "playlist", normalize_playlist(q)
    except YouTubeError:
        pass
    if re.search(r"(youtu\.be/|/watch\b|/shorts/|/embed/|/live/)", q):
        raise YouTubeError("That's a single video. Paste a profile (@handle) or a playlist link")
    return "user", normalize_user(q)


def watch_url(vid):
    return "https://www.youtube.com/watch?v=" + vid


def _best_thumbnail(thumbnails, prefer=None):
    thumbnails = [t for t in thumbnails or [] if t.get("url")]
    if prefer:
        for t in thumbnails:
            if t.get("id") == prefer:
                return t["url"]
    if not thumbnails:
        return ""
    sized = [t for t in thumbnails if t.get("width")]
    pick = max(sized, key=lambda t: t["width"]) if sized else thumbnails[-1]
    return pick["url"]


AUTO_PLAYLISTS = (("UULP", "Popular uploads"), ("UULF", "Latest uploads"))
AUTO_LIMIT = "1:200"


def auto_playlists(channel_id):
    """The playlists YouTube keeps for every channel: most viewed and newest videos."""
    return [{"id": prefix + channel_id[2:], "title": title, "thumbnail": "", "auto": True}
            for prefix, title in AUTO_PLAYLISTS]


def channel_playlists(query):
    """A channel and its public playlists: Popular / Latest uploads, then its Playlists tab."""
    url = normalize_user(query)
    try:
        data = _run(url + "/playlists")
    except YouTubeError as e:
        if "playlists tab" not in str(e):
            raise
        data = _run(url + "/videos", extra=("--playlist-items", "0"))
        data["entries"] = []
    channel_id = data.get("channel_id") or data.get("id") or ""
    if not CHANNEL_ID_RE.match(channel_id):
        raise YouTubeError("Couldn't find that YouTube user")
    handle = data.get("uploader_id") or ""
    playlists = auto_playlists(channel_id)
    seen = {p["id"] for p in playlists}
    for entry in data.get("entries") or []:
        pid = entry.get("id") or ""
        if not pid or pid in seen or entry.get("ie_key") not in (None, "YoutubeTab"):
            continue
        seen.add(pid)
        playlists.append({
            "id": pid,
            "title": entry.get("title") or "",
            "thumbnail": _best_thumbnail(entry.get("thumbnails")),
        })
    name = re.sub(r"\s+-\s+(?:Playlists|Videos)$", "", data.get("channel") or data.get("title") or "")
    return {
        "id": channel_id,
        "handle": handle if handle.startswith("@") else "",
        "name": name,
        "url": "https://www.youtube.com/" + handle if handle.startswith("@") else url,
        "followers": data.get("channel_follower_count"),
        "avatar": _best_thumbnail(data.get("thumbnails"), prefer="avatar_uncropped"),
        "playlists": playlists,
    }


def video_details(vid):
    """One video's title, channel and length (for songs added from outside the library)."""
    data = _run(watch_url(vid), timeout=60)
    return {"id": vid, "title": data.get("title") or "", "channel": data.get("channel") or data.get("uploader") or "",
            "duration": data.get("duration"), "views": data.get("view_count")}


# A video's smallest H.264 picture, without sound: plenty for a blurred
# background (about 1 MB a minute), and every player can show it.
SMALL_VIDEO = "wv*[vcodec^=avc1][protocol=https][height>=100]/wv*[vcodec^=avc1][protocol=https]"

# Video mode's picture: the tallest H.264 up to a height, else the smallest.
BIG_VIDEO = "bv*[vcodec^=avc1][protocol=https][height<=%d]/wv*[vcodec^=avc1][protocol=https]"

# Below this many kbps the picture doesn't move: a YouTube Music song's own
# video is often an "art track", its cover held still (about 10 kbps at
# 144p, where a video runs at about 100). Keep in step with the app.
STILL_KBPS = 30


def small_video(vid):
    """Where to stream a video's smallest picture: {"id", "url", "duration",
    "expires"} (expires: Unix time the link stops working, or None). None
    when the picture is a still (STILL_KBPS)."""
    return _picture(vid, SMALL_VIDEO, still=True)


def video_picture(vid, height):
    """Where to stream a video's picture, without sound, the tallest H.264
    up to `height` lines (video mode: big enough to watch), as small_video."""
    return _picture(vid, BIG_VIDEO % height, still=False)


def _picture(vid, formats, still):
    data = _run(watch_url(vid), timeout=60, extra=("-f", formats))
    chosen = (data.get("requested_formats") or [data])[0]
    url = chosen.get("url") or ""
    if not url:
        raise YouTubeError("that video has no picture to show")
    kbps = chosen.get("tbr") or chosen.get("vbr")
    if still and kbps is not None and kbps < STILL_KBPS:
        return None
    expires = urllib.parse.parse_qs(urllib.parse.urlsplit(url).query).get("expire", [None])[0]
    return {"id": vid, "url": url, "duration": data.get("duration"),
            "expires": int(expires) if expires and expires.isdigit() else None}


def playlist_details(query):
    """A public playlist and its available videos."""
    pid = normalize_playlist(query)
    # Uploads lists of big labels run to thousands of videos; the newest /
    # most viewed 200 are plenty.
    extra = ("--playlist-items", AUTO_LIMIT) if pid.startswith("UU") else ()
    data = _run("https://www.youtube.com/playlist?list=" + pid, extra=extra)
    tracks = []
    seen = set()
    for entry in data.get("entries") or []:
        vid = entry.get("id")
        title = entry.get("title") or ""
        if not vid or vid in seen or title.lower() in UNAVAILABLE:
            continue
        if entry.get("availability") in ("private", "needs_auth", "subscriber_only", "premium_only"):
            continue
        if entry.get("live_status") in ("is_upcoming", "is_live"):
            continue
        seen.add(vid)
        tracks.append({
            "id": vid,
            "title": title,
            "channel": entry.get("channel") or entry.get("uploader") or "",
            "duration": entry.get("duration"),
            "views": entry.get("view_count"),
        })
    return {
        "id": pid,
        "title": data.get("title") or "",
        "channel": data.get("channel") or data.get("uploader") or "",
        "channelId": data.get("channel_id") or "",
        "thumbnail": _best_thumbnail(data.get("thumbnails")),
        "modified": data.get("modified_date"),
        "tracks": tracks,
    }
