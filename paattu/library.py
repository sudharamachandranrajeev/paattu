"""The music library: followed YouTube users, their public playlists, tracks.

Everything lives in one JSON file that the Omarchy shell plugin watches, so
the bar, the desktop widget and the app update as soon as it changes.

    users      channel id  -> {id, handle, name, url, language, playlists[...]}
    playlists  playlist id -> {id, title, owner, language, saved, tracks[...] | None,
                               removedTracks[...]}
               or your own:     {id, title, local: True, saved: True, tracks[...]}
    tracks     track id    -> {id, title, movie, credits, kind, duration, ...}
               (a YouTube video id; songs from JioSaavn, SoundCloud or any
               other link are keyed by their link and carry url, site, art,
               quality: see sources.py)
    removed    playlist id -> {title, owner, removed}
    mixes      [{id, title, sources: [{type: language|user|playlist, id}]}]

A user's playlists are listed when the user is added; a playlist's tracks are
fetched when it is saved, opened or played (tracks is None until then).
Playlists and songs taken out of the app are remembered (removed,
removedTracks) so syncing with YouTube doesn't bring them back.

Your own playlists (Favourites, Saved songs and the ones you make) never
come from YouTube: nothing syncs or refreshes them, and their songs stay in
the library even when the playlist they were found in goes. Saved songs is
where songs found by a search land when you add them to the library.

Mixes are the shuffle buttons (bar, desktop, Home). Each shuffles everything
in its sources: a language (its saved playlists), a followed user (their
saved playlists) or one playlist. A new library starts with a Malayalam and a
Tamil mix; after that they're yours to rename, change, reorder or delete.
"""

import contextlib
import fcntl
import json
import os
import re
import secrets
import tempfile
import time

from . import paths

VERSION = 1
FAVOURITES = "paattu-favourites"
SAVED = "paattu-saved"
FAVOURITE_NAMES = ("favourites", "favorites", "fav", "favs", "liked")
SAVED_NAMES = ("saved songs", "saved", "saved-songs")
OWN_PREFIX = "paattu-"
MIX_PREFIX = "mix-"
MIX_SOURCES = ("language", "user", "playlist")
FIRST_MIXES = ("Malayalam", "Tamil")


def now():
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())


def empty():
    return {"version": VERSION, "updated": now(), "users": {}, "playlists": {}, "tracks": {}, "removed": {},
            "mixes": first_mixes()}


def first_mixes():
    return [{"id": MIX_PREFIX + lang.lower(), "title": lang + " mix", "sources": [{"type": "language", "id": lang}],
             "created": now()} for lang in FIRST_MIXES]


def load():
    try:
        with open(paths.LIBRARY, encoding="utf-8") as f:
            data = json.load(f)
    except FileNotFoundError:
        return empty()
    for key in ("users", "playlists", "tracks", "removed"):
        data.setdefault(key, {})
    # Libraries from before mixes get the two they used to have built in.
    data.setdefault("mixes", first_mixes())
    return data


def _write_json(path, value):
    fd, tmp = tempfile.mkstemp(dir=path.parent, prefix="." + path.stem + ".", suffix=".json")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            json.dump(value, f, ensure_ascii=False, separators=(",", ":"))
        os.replace(tmp, path)
    except BaseException:
        with contextlib.suppress(FileNotFoundError):
            os.unlink(tmp)
        raise


def save(data):
    prune_mixes(data)
    data["updated"] = now()
    paths.DATA.mkdir(parents=True, exist_ok=True)
    _write_json(paths.LIBRARY, data)
    _write_json(paths.SHELF, shelf(data))


def shelf(data):
    """The small summary the bar and desktop widget read: saved playlists per
    language and the followed users, without tracks or unsaved playlists."""
    users = data["users"]
    languages = {}
    for playlist in data["playlists"].values():
        if not playlist.get("saved") or playlist.get("local"):
            continue
        owner = users.get(playlist.get("owner"), {})
        languages.setdefault(playlist.get("language") or "Other", []).append({
            "id": playlist["id"],
            "title": playlist.get("title", ""),
            "owner": playlist.get("owner", ""),
            "ownerName": owner.get("name") or playlist.get("ownerName", ""),
            "count": playlist.get("count") if playlist.get("tracks") is not None else None,
            "featured": bool(playlist.get("featured")),
            "auto": bool(playlist.get("auto")),
            "followers": owner.get("followers") or 0,
        })
    for items in languages.values():
        items.sort(key=lambda p: (not p["featured"], not p["auto"], -p["followers"], p["title"].lower()))
    return {
        "updated": data["updated"],
        "languages": languages,
        "users": sorted(({"id": u["id"], "name": u.get("name", ""), "handle": u.get("handle", ""),
                          "language": u.get("language", ""), "kind": u.get("kind", ""),
                          "playlists": len(u.get("playlists", []))} for u in users.values()),
                        key=lambda u: (u["language"], u["name"].lower())),
        "mine": [{"id": p["id"], "title": p.get("title", ""), "count": len(p["tracks"]),
                  "favourites": p["id"] == FAVOURITES, "saved": p["id"] == SAVED, "tracks": p["tracks"]} for p in own_playlists(data)],
        "mixes": [mix_summary(data, mix) for mix in data.get("mixes", [])],
        "counts": {"users": len(users), "tracks": len(data["tracks"]),
                   "saved": sum(len(v) for v in languages.values())},
    }


@contextlib.contextmanager
def edit():
    """Load, change and save the library under a lock."""
    paths.DATA.mkdir(parents=True, exist_ok=True)
    with open(paths.DATA / ".lock", "w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        data = load()
        yield data
        save(data)


# ---------------------------------------------------------------- lookups

def find_user(data, query):
    """A followed user by channel id, @handle, name or URL fragment."""
    q = (query or "").strip().lower().lstrip("@")
    for user in data["users"].values():
        candidates = [user["id"], user.get("handle", ""), user.get("name", ""), user.get("url", "")]
        if any(q and (c.lower().lstrip("@") == q or c.lower().endswith("/" + q) or c.lower().endswith("/@" + q))
               for c in candidates if c):
            return user
    return None


def playlist_tracks(data, playlist_id):
    playlist = data["playlists"].get(playlist_id) or {}
    return [data["tracks"][t] for t in playlist.get("tracks") or [] if t in data["tracks"]]


def own_playlists(data):
    """Favourites first, then Saved songs, then your playlists, oldest first."""
    mine = [p for p in data["playlists"].values() if p.get("local")]
    return sorted(mine, key=lambda p: (p["id"] != FAVOURITES, p["id"] != SAVED, p.get("created", ""),
                                       p.get("title", "").lower()))


def find_own_playlist(data, ref):
    """One of your playlists by id, name, "favourites" or "saved"."""
    ref = (ref or "").strip()
    if ref.lower() in FAVOURITE_NAMES:
        ref = FAVOURITES
    elif ref.lower() in SAVED_NAMES:
        ref = SAVED
    if ref in data["playlists"] and data["playlists"][ref].get("local"):
        return data["playlists"][ref]
    named = [p for p in own_playlists(data) if p.get("title", "").lower() == ref.lower()]
    return named[0] if named else None


def language_playlists(data, language):
    """Saved playlists in a language; ones without a language count as Other (as on the shelves)."""
    return [p for p in data["playlists"].values()
            if p.get("saved") and not p.get("local") and (p.get("language") or "Other") == language]


def find_mix(data, ref):
    """A mix by id or name ("tamil" finds "Tamil mix")."""
    ref = " ".join((ref or "").split()).lower()
    for mix in data.get("mixes", []):
        title = mix.get("title", "").lower()
        if ref and ref in (mix["id"], title, re.sub(r"\s+mix$", "", title)):
            return mix
    return None


def source_title(data, source):
    if source["type"] == "language":
        return source["id"]
    if source["type"] == "user":
        return data["users"].get(source["id"], {}).get("name", "")
    return data["playlists"].get(source["id"], {}).get("title", "")


def mix_playlists(data, mix):
    """The playlists a mix shuffles, in the order of its sources."""
    out = {}
    for source in mix.get("sources", []):
        if source["type"] == "language":
            found = language_playlists(data, source["id"])
        elif source["type"] == "user":
            user = data["users"].get(source["id"], {})
            found = [data["playlists"][pid] for pid in user.get("playlists", [])
                     if data["playlists"].get(pid, {}).get("saved")]
        else:
            found = [data["playlists"][source["id"]]] if source["id"] in data["playlists"] else []
        for playlist in found:
            out.setdefault(playlist["id"], playlist)
    return list(out.values())


def mix_summary(data, mix):
    playlists = mix_playlists(data, mix)
    songs = {t for p in playlists for t in p.get("tracks") or []}
    return {"id": mix["id"], "title": mix.get("title", ""),
            "sources": [dict(source, title=source_title(data, source)) for source in mix.get("sources", [])],
            "playlists": len(playlists), "count": len(songs),
            "waiting": sum(1 for p in playlists if p.get("tracks") is None)}


# ---------------------------------------------------------------- updates

def upsert_user(data, info, language, curated=False):
    """Add or refresh a followed user and the stubs of their public playlists."""
    users = data["users"]
    user = users.get(info["id"], {})
    listed = [p for p in info.get("playlists", []) if p["id"] not in data["removed"]]
    user.update({
        "id": info["id"],
        "handle": info.get("handle") or user.get("handle", ""),
        "name": info.get("name") or user.get("name", ""),
        "url": info.get("url") or user.get("url", ""),
        "followers": info.get("followers") or user.get("followers"),
        "avatar": info.get("avatar") or user.get("avatar", ""),
        "language": language or user.get("language", ""),
        "curated": bool(curated or user.get("curated")),
        "added": user.get("added") or now(),
        "synced": now(),
        "playlists": [p["id"] for p in listed],
    })
    users[info["id"]] = user
    for stub in listed:
        upsert_playlist_stub(data, stub, owner=user)
    return user


def upsert_playlist_stub(data, stub, owner=None, language=""):
    """Record a playlist we know about without touching its tracks."""
    from .titles import guess_language, playlist_title

    playlists = data["playlists"]
    entry = playlists.get(stub["id"], {})
    owner_name = owner["name"] if owner else stub.get("ownerName", "")
    raw_title = stub.get("title") or entry.get("rawTitle", "")
    entry.update({
        "id": stub["id"],
        "rawTitle": raw_title,
        "title": playlist_title(raw_title, owner_name),
        "owner": owner["id"] if owner else entry.get("owner") or stub.get("ownerId", ""),
        "ownerName": owner_name or entry.get("ownerName", ""),
        "thumbnail": short_thumbnail(stub.get("thumbnail") or entry.get("thumbnail", "")),
    })
    entry.pop("url", None)
    entry["language"] = (entry.get("language") if entry.get("languageSet") else None) or guess_language(
        stub.get("title", ""), default=language or (owner or {}).get("language", "") or entry.get("language", ""))
    if stub.get("auto") or entry.get("auto"):
        entry["auto"] = True
        kind = "Most played" if raw_title.lower().startswith("popular") else "New releases"
        entry["title"] = (owner_name + " — " + kind) if owner_name else kind
    entry.setdefault("saved", False)
    entry.setdefault("tracks", None)
    playlists[stub["id"]] = entry
    return entry


def short_thumbnail(url):
    """i.ytimg.com thumbnails work without their signed query string."""
    found = re.match(r"^https://i\d?\.ytimg\.com/vi/([\w-]{11})/", url or "")
    return "https://i.ytimg.com/vi/%s/hqdefault.jpg" % found.group(1) if found else (url or "")


def set_playlist_tracks(data, details):
    """Store a fetched playlist: its metadata and cleaned tracks."""
    from .titles import clean_title

    entry = data["playlists"].get(details["id"]) or {"id": details["id"], "saved": False}
    if not entry.get("rawTitle"):
        stub = {"id": details["id"], "title": details.get("title", ""), "ownerName": details.get("channel", ""),
                "ownerId": details.get("channelId", ""), "thumbnail": details.get("thumbnail", "")}
        data["playlists"][details["id"]] = entry
        entry = upsert_playlist_stub(data, stub, owner=data["users"].get(details.get("channelId", "")))
    ids = []
    removed = set(entry.get("removedTracks") or ())
    for raw in details["tracks"]:
        if raw["id"] in removed:
            continue
        meta = clean_title(raw["title"], raw.get("channel") or details.get("channel", ""))
        track = data["tracks"].get(raw["id"], {})
        track.update({
            "id": raw["id"],
            "rawTitle": raw["title"],
            "title": meta["title"],
            "movie": meta["movie"],
            "credits": meta["credits"][:6],
            "kind": meta["kind"],
            "channel": raw.get("channel") or details.get("channel", ""),
            "duration": raw.get("duration"),
            "views": raw.get("views"),
        })
        data["tracks"][raw["id"]] = track
        ids.append(raw["id"])
    entry["tracks"] = ids
    entry["count"] = len(ids)
    entry["fetched"] = now()
    if not entry.get("thumbnail") and ids:
        entry["thumbnail"] = f"https://i.ytimg.com/vi/{ids[0]}/hqdefault.jpg"
    return entry


def remove_user(data, user_id, keep_saved=True):
    """Unfollow a user; their saved playlists stay unless keep_saved is False."""
    user = data["users"].pop(user_id, None)
    if not user:
        return None
    for pid in user.get("playlists", []):
        playlist = data["playlists"].get(pid)
        if playlist and (not keep_saved or not playlist.get("saved")):
            data["playlists"].pop(pid, None)
    for pid in [pid for pid, entry in data["removed"].items() if entry.get("owner") == user_id]:
        del data["removed"][pid]
    prune_tracks(data)
    return user


def create_playlist(data, title):
    """A new playlist of your own (or Favourites, which has a fixed id)."""
    title = " ".join((title or "").split())
    if not title:
        raise ValueError("give the playlist a name")
    if title.lower() in ("favourites", "favorites"):
        return favourites(data)
    if title.lower() == "saved songs":
        return saved_songs(data)
    if find_own_playlist(data, title):
        raise ValueError("you already have a playlist called %s" % title)
    pid = OWN_PREFIX + secrets.token_hex(4)
    while pid in data["playlists"]:
        pid = OWN_PREFIX + secrets.token_hex(4)
    data["playlists"][pid] = _own(pid, title)
    return data["playlists"][pid]


def favourites(data):
    if FAVOURITES not in data["playlists"]:
        data["playlists"][FAVOURITES] = _own(FAVOURITES, "Favourites")
    return data["playlists"][FAVOURITES]


def saved_songs(data):
    """Songs you added to the library (from a search, a link or a playlist)."""
    if SAVED not in data["playlists"]:
        data["playlists"][SAVED] = _own(SAVED, "Saved songs")
    return data["playlists"][SAVED]


def builtin(playlist_id):
    return playlist_id in (FAVOURITES, SAVED)


def _own(pid, title):
    return {"id": pid, "title": title, "local": True, "saved": True, "owner": "", "ownerName": "You",
            "language": "", "tracks": [], "count": 0, "created": now()}


def rename_playlist(data, playlist_id, title):
    playlist = data["playlists"].get(playlist_id)
    title = " ".join((title or "").split())
    if not playlist or not playlist.get("local"):
        raise ValueError("only your own playlists can be renamed")
    if builtin(playlist_id):
        raise ValueError("%s keeps its name" % playlist["title"])
    if not title:
        raise ValueError("give the playlist a name")
    other = find_own_playlist(data, title)
    if other and other["id"] != playlist_id:
        raise ValueError("you already have a playlist called %s" % title)
    playlist["title"] = title
    return playlist


def add_tracks(data, playlist_id, tracks):
    """Add songs to one of your playlists. tracks: track dicts (at least an id);
    ones the library doesn't know yet are stored. Returns the ids added."""
    playlist = data["playlists"].get(playlist_id)
    if not playlist or not playlist.get("local"):
        raise ValueError("songs can only be added to your own playlists")
    added = []
    for track in tracks:
        tid = track["id"]
        if tid not in data["tracks"]:
            data["tracks"][tid] = dict(track)
        if tid not in playlist["tracks"] and tid not in added:
            added.append(tid)
    playlist["tracks"] = playlist["tracks"] + added
    playlist["count"] = len(playlist["tracks"])
    return added


def remove_playlist(data, playlist_id):
    """Take a playlist out of the app; syncing its owner won't bring it back.
    Your own playlists are simply deleted."""
    playlist = data["playlists"].pop(playlist_id, None)
    if playlist is None:
        return None
    if playlist.get("local"):
        prune_tracks(data)
        return playlist
    owner = data["users"].get(playlist.get("owner"))
    if owner:
        owner["playlists"] = [pid for pid in owner.get("playlists", []) if pid != playlist_id]
    data["removed"][playlist_id] = {"title": playlist.get("title", ""), "owner": playlist.get("owner", ""),
                                    "removed": now()}
    prune_tracks(data)
    return playlist


def unremove_playlists(data, ids=None, owner=None):
    """Forget that playlists were removed (by id, or all of an owner's).
    Returns their ids; the caller fetches them again."""
    picked = [pid for pid, entry in data["removed"].items()
              if (ids is not None and pid in ids) or (owner is not None and entry.get("owner") == owner)]
    for pid in picked:
        del data["removed"][pid]
    return picked


def remove_tracks(data, playlist_id, track_ids):
    """Take songs out of a playlist; refreshing it from YouTube won't bring them back."""
    playlist = data["playlists"].get(playlist_id)
    if not playlist or playlist.get("tracks") is None:
        return []
    drop = [tid for tid in dict.fromkeys(track_ids) if tid in playlist["tracks"]]
    playlist["tracks"] = [tid for tid in playlist["tracks"] if tid not in drop]
    playlist["count"] = len(playlist["tracks"])
    if not playlist.get("local"):  # nothing refreshes your own playlists
        playlist["removedTracks"] = list(dict.fromkeys((playlist.get("removedTracks") or []) + drop))
    prune_tracks(data)
    return drop


def remove_starter(data):
    """Take out the starter library (`paattu seed`): unfollow its profiles and
    delete its playlists. Profiles you added whole, playlists you saved
    yourself and your own playlists stay. Returns (users, saved playlists) gone."""
    starter = {uid: user for uid, user in data["users"].items() if user.get("curated") and not user.get("saveAll")}
    gone = 0
    for pid, playlist in list(data["playlists"].items()):
        if playlist.get("local") or playlist.get("owner") not in starter:
            continue
        if playlist.get("saved") and not playlist.get("featured"):
            continue  # saved by you, not by the seed
        del data["playlists"][pid]
        gone += 1 if playlist.get("saved") else 0
    for uid in starter:
        del data["users"][uid]
    for pid in [pid for pid, entry in data["removed"].items() if entry.get("owner") in starter]:
        del data["removed"][pid]
    prune_tracks(data)
    return list(starter.values()), gone


# ---------------------------------------------------------------- mixes

def get_mix(data, ref):
    mix = find_mix(data, ref)
    if not mix:
        raise ValueError("there's no mix called %s (make one: paattu mix new NAME)" % ref)
    return mix


def create_mix(data, title, sources=()):
    title = " ".join((title or "").split())
    if not title:
        raise ValueError("give the mix a name")
    if find_mix(data, title):
        raise ValueError("there's already a mix called %s" % title)
    mid = MIX_PREFIX + secrets.token_hex(4)
    while find_mix(data, mid):
        mid = MIX_PREFIX + secrets.token_hex(4)
    mix = {"id": mid, "title": title, "sources": [], "created": now()}
    data["mixes"].append(mix)
    add_mix_sources(data, mid, sources)
    return mix


def rename_mix(data, ref, title):
    mix = get_mix(data, ref)
    title = " ".join((title or "").split())
    if not title:
        raise ValueError("give the mix a name")
    other = find_mix(data, title)
    if other and other["id"] != mix["id"]:
        raise ValueError("there's already a mix called %s" % title)
    mix["title"] = title
    return mix


def remove_mix(data, ref):
    mix = get_mix(data, ref)
    data["mixes"] = [m for m in data["mixes"] if m["id"] != mix["id"]]
    return mix


def move_mix(data, ref, position):
    """Put a mix at position (0 = first button)."""
    mix = get_mix(data, ref)
    rest = [m for m in data["mixes"] if m["id"] != mix["id"]]
    position = max(0, min(int(position), len(rest)))
    data["mixes"] = rest[:position] + [mix] + rest[position:]
    return position


def add_mix_sources(data, ref, sources):
    """sources: [{type, id}]. Returns the ones that weren't in the mix yet."""
    mix = get_mix(data, ref)
    have = {(s["type"], s["id"]) for s in mix["sources"]}
    added = []
    for source in sources:
        kind, sid = source["type"], source["id"]
        if kind not in MIX_SOURCES or not sid:
            raise ValueError("a mix takes languages, followed users and playlists")
        if kind == "user" and sid not in data["users"]:
            raise ValueError("not following %s" % sid)
        if kind == "playlist" and sid not in data["playlists"]:
            raise ValueError("unknown playlist %s" % sid)
        if (kind, sid) not in have:
            have.add((kind, sid))
            added.append({"type": kind, "id": sid})
    mix["sources"] = mix["sources"] + added
    return added


def drop_mix_sources(data, ref, sources):
    mix = get_mix(data, ref)
    drop = {(s["type"], s["id"]) for s in sources}
    gone = [s for s in mix["sources"] if (s["type"], s["id"]) in drop]
    mix["sources"] = [s for s in mix["sources"] if (s["type"], s["id"]) not in drop]
    return gone


def prune_mixes(data):
    """Forget mix sources whose user or playlist has left the library."""
    for mix in data.get("mixes", []):
        mix["sources"] = [s for s in mix.get("sources", [])
                          if s["type"] == "language"
                          or (s["type"] == "user" and s["id"] in data["users"])
                          or (s["type"] == "playlist" and s["id"] in data["playlists"])]


def prune_tracks(data):
    """Drop tracks no playlist refers to any more."""
    used = set()
    for playlist in data["playlists"].values():
        used.update(playlist.get("tracks") or [])
    for tid in list(data["tracks"]):
        if tid not in used:
            del data["tracks"][tid]
