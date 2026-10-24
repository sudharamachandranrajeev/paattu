"""Scrobbling to ListenBrainz, which also carries plays between devices
(`paattu listenbrainz`). The app does the same (app/lib/src/listenbrainz.dart).

Each song heard properly (half of it, or four minutes: ListenBrainz's own
rule) is sent as a listen with the song itself in additional_info, so another
Paattu can play it. Each device reads the others' listens back into its own
history, so the made-for-you playlists and the Played in ... playlists follow
every device. Listens from other players have no song in them and are left
alone. Listening history on ListenBrainz is public.

history.json keeps where it got to under "listenbrainz":

    device   this install's random id, so its own listens aren't read back
    sent     the newest of its own plays sent (seconds since 1970)
    fetched  the newest listen read

Plays read back carry "from": "listenbrainz" and are never sent again. The
token and user name are in ~/.config/paattu/listenbrainz.json, which only you
can read.
"""

import contextlib
import fcntl
import json
import os
import secrets
import time
import urllib.error
import urllib.parse
import urllib.request

from . import __version__, history, paths, sources

API = "https://api.listenbrainz.org"
ACCOUNT = paths.CONFIG / "listenbrainz.json"
SERVICES = {"youtube": "youtube.com", "jiosaavn": "jiosaavn.com", "soundcloud": "soundcloud.com"}
# What of a song goes with its listen: enough to play it and show it.
SONG_KEYS = ("id", "title", "rawTitle", "movie", "credits", "channel", "kind", "duration", "url", "site", "art",
             "language", "album", "year")
FROM = "listenbrainz"
# Listens read again from this far back, for a device that sends its plays late.
OVERLAP = 2 * 86400
PAGE = 100
PAGES = 50
TIMEOUT = 15


class ListenBrainzError(Exception):
    pass


def scrobbles(play):
    """A play ListenBrainz counts: half the song, or four minutes of a long one."""
    heard = int(play.get("heard") or 0)
    length = int(play.get("length") or 0)
    return heard >= (min(240, length // 2) if length > 0 else 240)


def state(data):
    """The sync state in history data, made (with a new device id) if missing."""
    found = data.get("listenbrainz")
    if not isinstance(found, dict):
        found = data["listenbrainz"] = {}
    if not found.get("device"):
        found["device"] = secrets.token_hex(6)
    found.setdefault("sent", 0)
    found.setdefault("fetched", 0)
    return found


def _site(song):
    return song.get("site") or sources.site_of(song.get("url") or "")


def _page(song):
    return song.get("url") or "https://www.youtube.com/watch?v=" + song.get("id", "")


def listen(play, song, device):
    """The listen ListenBrainz is sent for a play of song."""
    credits = [c for c in song.get("credits") or [] if c]
    info = {
        "media_player": "Paattu",
        "submission_client": "Paattu",
        "submission_client_version": __version__,
        "origin_url": _page(song),
        "paattu_device": device,
        "paattu_heard": int(play.get("heard") or 0),
        "paattu_song": {k: song[k] for k in SONG_KEYS if song.get(k) not in (None, "", [])},
    }
    service = SERVICES.get(_site(song))
    if service:
        info["music_service"] = service
    length = int(play.get("length") or song.get("duration") or 0)
    if length > 0:
        info["duration"] = length
    if credits:
        info["artist_names"] = credits
    metadata = {
        "artist_name": ", ".join(credits) or song.get("channel") or "Unknown artist",
        "track_name": song.get("title") or song.get("rawTitle") or song.get("id", ""),
        "additional_info": info,
    }
    if song.get("movie"):
        metadata["release_name"] = song["movie"]
    return {"listened_at": int(play["at"]), "track_metadata": metadata}


def pending(data):
    """[(play, song)]: this device's plays still to send, oldest first."""
    sync = state(data)
    out = []
    for play in data.get("plays") or []:
        if not isinstance(play, dict) or play.get("from") or int(play.get("at") or 0) <= sync["sent"]:
            continue
        song = (data.get("tracks") or {}).get(play.get("id"))
        if isinstance(song, dict) and scrobbles(play):
            out.append((play, song))
    return out


def play_of(found, device):
    """(play, song) for a listen another Paattu sent, or None."""
    metadata = found.get("track_metadata") or {}
    info = metadata.get("additional_info") or {}
    song = info.get("paattu_song")
    at = found.get("listened_at")
    if not isinstance(song, dict) or not song.get("id") or not isinstance(at, int) or info.get("paattu_device") == device:
        return None
    play = {"id": song["id"], "at": at, "heard": int(info.get("paattu_heard") or 0), "from": FROM}
    if int(info.get("duration") or 0) > 0:
        play["length"] = int(info["duration"])
    return play, song


def merge(data, found):
    """Add the plays read (play_of's) to history data, in time order, each
    once. Returns the ones added, oldest first."""
    plays = data["plays"]
    have = {(p.get("id"), p.get("at")) for p in plays if isinstance(p, dict)}
    added = []
    for play, song in sorted(found, key=lambda f: f[0]["at"]):
        if (play["id"], play["at"]) in have:
            continue
        have.add((play["id"], play["at"]))
        at = len(plays)
        while at > 0 and isinstance(plays[at - 1], dict) and int(plays[at - 1].get("at") or 0) > play["at"]:
            at -= 1
        plays.insert(at, play)
        data["tracks"][play["id"]] = history.stored_track(song)
        added.append((play, song))
    del plays[:-history.LIMIT]
    return added


# ---------------------------------------------------------------- the account


def account():
    """{token, user} or None."""
    try:
        with open(ACCOUNT, encoding="utf-8") as f:
            found = json.load(f)
        return found if isinstance(found, dict) and found.get("token") and found.get("user") else None
    except (OSError, ValueError):
        return None


def save_account(token, user):
    ACCOUNT.parent.mkdir(parents=True, exist_ok=True)
    tmp = ACCOUNT.with_name(".listenbrainz.json.tmp")
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        json.dump({"token": token, "user": user}, f)
    os.replace(tmp, ACCOUNT)


def forget_account():
    with contextlib.suppress(FileNotFoundError):
        os.unlink(ACCOUNT)


# ---------------------------------------------------------------- the API


def _call(path, token, body=None, query=None):
    url = API + path + ("?" + urllib.parse.urlencode(query) if query else "")
    headers = {"Authorization": "Token " + token, "User-Agent": "Paattu/" + __version__}
    data = None
    if body is not None:
        data = json.dumps(body, ensure_ascii=False).encode()
        headers["Content-Type"] = "application/json"
    request = urllib.request.Request(url, data=data, headers=headers)
    try:
        with urllib.request.urlopen(request, timeout=TIMEOUT) as response:
            return json.load(response)
    except urllib.error.HTTPError as error:
        try:
            said = json.load(error).get("error") or ""
        except (ValueError, AttributeError):
            said = ""
        if error.code == 401:
            raise ListenBrainzError("ListenBrainz didn't accept the token") from None
        if error.code == 429:
            raise ListenBrainzError("ListenBrainz asked to wait a while") from None
        raise ListenBrainzError("ListenBrainz said %d %s" % (error.code, said)) from None
    except (urllib.error.URLError, TimeoutError, OSError) as error:
        raise ListenBrainzError("couldn't reach ListenBrainz (%s)" % getattr(error, "reason", error)) from None


def user_of(token):
    """The ListenBrainz user a token belongs to."""
    found = _call("/1/validate-token", token)
    if not found.get("valid") or not found.get("user_name"):
        raise ListenBrainzError("ListenBrainz didn't accept the token")
    return found["user_name"]


def submit(token, listens):
    for start in range(0, len(listens), PAGE):
        chunk = listens[start:start + PAGE]
        _call("/1/submit-listens", token, {"listen_type": "single" if len(chunk) == 1 else "import", "payload": chunk})


def listens_since(token, user, since):
    """The listens after since (seconds), oldest pages first."""
    out = []
    for _ in range(PAGES):
        found = _call("/1/user/%s/listens" % urllib.parse.quote(user, safe=""), token,
                      query={"min_ts": since, "count": PAGE})
        page = (found.get("payload") or {}).get("listens") or []
        out.extend(page)
        if len(page) < PAGE:
            break
        since = max(int(f.get("listened_at") or 0) for f in page)
    return out


# ---------------------------------------------------------------- sync


def sync(token, user, path=history.FILE):
    """Send this device's plays, read the others'. Returns the plays added
    [(play, song)], oldest first."""
    path.parent.mkdir(parents=True, exist_ok=True)
    # One sync at a time; another one running does the work.
    with open(path.with_name(".listenbrainz.lock"), "w") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            return []
        with history.editing(path) as h:
            sync_state = dict(state(h.data))
            waiting = pending(h.data)
        if waiting:
            submit(token, [listen(play, song, sync_state["device"]) for play, song in waiting])
            with history.editing(path) as h:
                state(h.data)["sent"] = max(int(play["at"]) for play, _ in waiting)
        found = listens_since(token, user, max(0, sync_state["fetched"] - OVERLAP))
        with history.editing(path) as h:
            added = merge(h.data, [p for p in (play_of(f, sync_state["device"]) for f in found) if p])
            h._prune()
            newest = max((int(f.get("listened_at") or 0) for f in found), default=0)
            ours = state(h.data)
            ours["fetched"] = max(ours["fetched"], newest)
            ours["synced"] = int(time.time())
        return added
