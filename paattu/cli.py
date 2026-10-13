"""paattu — Malayalam & Tamil music from YouTube playlists, JioSaavn and any link, built into Omarchy."""

import argparse
import concurrent.futures
import contextlib
import json
import random
import shutil
import subprocess
import sys

from . import __version__, art, cliamp, config, engine, library, paths, seeds, sources, youtube
from .engine import EngineError
from .sources import SourceError
from .youtube import YouTubeError

PLUGIN_ID = "rajeevrama.paattu"
# Adding a profile saves all its playlists. Songs are fetched right away for a
# small profile; a big label (hundreds of playlists) gets its best few now and
# the rest load when opened or played.
FETCH_ALL_UP_TO = 40
FETCH_FIRST = 12


class Reporter:
    """Plain text for people, JSON lines (--json) for the shell plugin."""

    def __init__(self, as_json):
        self.as_json = as_json

    def progress(self, message, **fields):
        if self.as_json:
            print(json.dumps({"event": "progress", "message": message, **fields}, ensure_ascii=False), flush=True)
        else:
            print(message, flush=True)

    def done(self, message="", **fields):
        if self.as_json:
            print(json.dumps({"event": "done", "ok": True, "message": message, **fields}, ensure_ascii=False), flush=True)
        elif message:
            print(message, flush=True)

    def data(self, payload, text=None):
        if self.as_json:
            print(json.dumps(payload, ensure_ascii=False), flush=True)
        elif text is not None:
            print(text, flush=True)

    def error(self, message):
        if self.as_json:
            print(json.dumps({"event": "error", "ok": False, "message": message}, ensure_ascii=False), flush=True)
        else:
            print("paattu: " + message, file=sys.stderr, flush=True)


def _fmt_duration(seconds):
    if not seconds:
        return "--:--"
    seconds = int(seconds)
    return "%d:%02d" % (seconds // 60, seconds % 60) if seconds < 3600 else \
        "%d:%02d:%02d" % (seconds // 3600, seconds // 60 % 60, seconds % 60)


def _language(value):
    if not value:
        return ""
    for lang in seeds.LANGUAGES + ("Other",):
        if lang.lower().startswith(value.lower()):
            return lang
    return value.title()


# ---------------------------------------------------------------- fetching

def fetch_playlists(ids, out, workers=6):
    """Fetch tracks for playlists in parallel and store them. Returns failures."""
    # Your own playlists don't come from YouTube.
    ids = [pid for pid in dict.fromkeys(ids) if not pid.startswith(library.OWN_PREFIX)]
    if not ids:
        return []
    results, failures = {}, []

    def one(pid):
        return pid, youtube.playlist_details(pid)

    with concurrent.futures.ThreadPoolExecutor(max_workers=workers) as pool:
        futures = [pool.submit(one, pid) for pid in ids]
        for n, future in enumerate(concurrent.futures.as_completed(futures), 1):
            try:
                pid, details = future.result()
                results[pid] = details
                out.progress("Fetched %s (%d tracks)" % (details["title"] or pid, len(details["tracks"])),
                             step=n, total=len(ids))
            except YouTubeError as e:
                failures.append(str(e))
                out.progress("Skipped a playlist: %s" % e, step=n, total=len(ids))
    with library.edit() as data:
        for details in results.values():
            library.set_playlist_tracks(data, details)
    return failures


def ensure_tracks(pid, out):
    data = library.load()
    playlist = data["playlists"].get(pid)
    if playlist is None or playlist.get("tracks") is None:
        out.progress("Fetching playlist from YouTube…")
        failures = fetch_playlists([pid], out)
        if failures:
            raise YouTubeError(failures[0])
        data = library.load()
    return data


def cache_art_for(data, playlist_ids=(), user_ids=(), track_ids=()):
    jobs = list(art.playlist_jobs(data, playlist_ids)) + list(art.user_jobs(data, user_ids)) + \
        list(art.track_jobs(track_ids, lambda tid: _known(data, tid)))
    return art.fetch_many(jobs)


# ---------------------------------------------------------------- users

def _songs_now(playlists):
    """Which newly saved playlists to fetch songs for right away."""
    if len(playlists) <= FETCH_ALL_UP_TO:
        return playlists
    return seeds.pick_featured(playlists, FETCH_FIRST) or playlists[:FETCH_FIRST]


def _find_user(data, query):
    user = library.find_user(data, query)
    if not user:
        raise YouTubeError("not following %s" % query)
    return user


def _waiting(data, user):
    """Saved playlists of a user whose songs haven't been fetched yet."""
    return [pid for pid in user.get("playlists", [])
            if data["playlists"].get(pid, {}).get("saved") and data["playlists"][pid].get("tracks") is None]


def cmd_user_add(args, out):
    out.progress("Looking up %s on YouTube…" % args.query)
    info = youtube.channel_playlists(args.query)
    language = _language(args.lang) or _guess_user_language(info)
    with library.edit() as data:
        user = library.upsert_user(data, info, language)
        stubs = [data["playlists"][pid] for pid in user["playlists"]]
        user["saveAll"] = args.save is None
        picked = stubs if args.save is None else seeds.pick_featured(stubs, args.save)
        for playlist in picked:
            playlist["saved"] = True
        fetch_now = [p["id"] for p in _songs_now(picked) if p.get("tracks") is None]
    out.progress("%s: %d public playlists" % (info["name"], len(user["playlists"])))
    fetch_playlists(fetch_now, out)
    data = library.load()
    cache_art_for(data, playlist_ids=user["playlists"][:40], user_ids=[user["id"]])
    later = len(_waiting(data, data["users"][user["id"]]))
    out.done("Added %s (%s): %s in your library%s" % (
        info["name"], language or "no language", _plural(len(picked), "playlist"),
        "; songs for the other %d load when you open or play them" % later if later else ""),
        user=user["id"], playlists=len(user["playlists"]), saved=len(picked), waiting=later)


def _plural(n, word):
    return "%d %s%s" % (n, word, "" if n == 1 else "s")


def cmd_user_save_all(args, out):
    with library.edit() as data:
        user = _find_user(data, args.query)
        user["saveAll"] = True
        newly = [data["playlists"][pid] for pid in user["playlists"]
                 if pid in data["playlists"] and not data["playlists"][pid].get("saved")]
        for playlist in newly:
            playlist["saved"] = True
        fetch_now = [p["id"] for p in _songs_now(newly) if p.get("tracks") is None]
    fetch_playlists(fetch_now, out)
    data = library.load()
    cache_art_for(data, playlist_ids=[p["id"] for p in newly][:40])
    later = len(_waiting(data, data["users"][user["id"]]))
    out.done("All %s of %s are in your library%s" % (
        _plural(len(user["playlists"]), "playlist"), user["name"],
        "; songs for %d load when you open or play them" % later if later else ""), user=user["id"], waiting=later)


def cmd_user_fetch(args, out):
    data = library.load()
    user = _find_user(data, args.query)
    waiting = _waiting(data, user)
    if not waiting:
        out.done("Songs for all of %s's saved playlists are here" % user["name"], user=user["id"])
        return
    out.progress("Fetching songs for %s…" % _plural(len(waiting), "playlist"), step=0, total=len(waiting))
    failures = fetch_playlists(waiting, out)
    cache_art_for(library.load(), playlist_ids=waiting[:40])
    out.done("Fetched %d of %s" % (len(waiting) - len(failures), _plural(len(waiting), "playlist")), user=user["id"])


def _guess_user_language(info):
    from .titles import guess_language
    titles = " ".join(p["title"] for p in info["playlists"][:60])
    return guess_language(info["name"], info.get("handle", ""), titles, default="Other")


def cmd_user_list(args, out):
    data = library.load()
    users = sorted(data["users"].values(), key=lambda u: (u.get("language", ""), u.get("name", "").lower()))
    if args.json:
        out.data(users)
        return
    for user in users:
        saved = sum(1 for pid in user.get("playlists", []) if data["playlists"].get(pid, {}).get("saved"))
        print("%-10s %-34s %-28s %4d playlists, %d saved" % (
            user.get("language", ""), user.get("name", "")[:34], user.get("handle", ""),
            len(user.get("playlists", [])), saved))


def cmd_user_sync(args, out):
    data = library.load()
    if args.query:
        user = library.find_user(data, args.query)
        if not user:
            raise YouTubeError("not following %s" % args.query)
        users = [user]
    else:
        users = list(data["users"].values())
    refresh, added_total = [], 0
    for n, user in enumerate(users, 1):
        out.progress("Syncing %s…" % user["name"], step=n, total=len(users))
        try:
            info = youtube.channel_playlists(user["url"] or user["id"])
        except YouTubeError as e:
            out.progress("Skipped %s: %s" % (user["name"], e))
            continue
        with library.edit() as data:
            before = set(data["users"].get(info["id"], {}).get("playlists", []))
            fresh = library.upsert_user(data, info, user.get("language", ""))
            added = [data["playlists"][pid] for pid in fresh["playlists"] if pid not in before]
            added_total += len(added)
            if fresh.get("saveAll"):
                # Profiles added whole keep getting their new playlists.
                for playlist in added:
                    playlist["saved"] = True
                refresh += [p["id"] for p in _songs_now(added) if p.get("tracks") is None]
            # Refresh the songs of saved playlists already fetched (opened or played).
            refresh += [pid for pid in fresh["playlists"]
                        if data["playlists"][pid].get("saved") and data["playlists"][pid].get("tracks") is not None]
    fetch_playlists(refresh, out)
    out.done("Synced %s: %s" % (_plural(len(users), "user"), _plural(added_total, "new playlist")))


def cmd_user_remove(args, out):
    with library.edit() as data:
        user = _find_user(data, args.query)
        # A profile added whole goes whole: its playlists are all "saved", and
        # keeping hundreds of them without their profile isn't what anyone wants.
        purge = args.purge or bool(user.get("saveAll"))
        before = len(data["playlists"])
        library.remove_user(data, user["id"], keep_saved=not purge)
        dropped = before - len(data["playlists"])
    out.done("Unfollowed %s" % user["name"] + (" and removed %s" % _plural(dropped, "playlist") if purge else ""),
             removed=dropped)


# ---------------------------------------------------------------- playlists

def cmd_playlist_add(args, out):
    pid = youtube.normalize_playlist(args.url)
    out.progress("Fetching playlist from YouTube…")
    details = youtube.playlist_details(pid)
    with library.edit() as data:
        library.unremove_playlists(data, ids={pid})
        entry = library.set_playlist_tracks(data, details)
        entry["saved"] = True
        owner = data["users"].get(entry.get("owner"))
        if owner and pid not in owner["playlists"]:
            owner["playlists"].append(pid)
        if args.lang:
            entry["language"], entry["languageSet"] = _language(args.lang), True
    cache_art_for(library.load(), playlist_ids=[pid])
    out.done("Saved %s (%d tracks, %s)" % (entry["title"], entry["count"], entry.get("language") or "no language"),
             playlist=pid)


def cmd_playlist_save(args, out, saved=True):
    with library.edit() as data:
        missing = [pid for pid in args.ids if pid not in data["playlists"]]
        if not saved and any(data["playlists"].get(pid, {}).get("local") for pid in args.ids):
            raise ValueError("your own playlists stay in the library (delete one with: paattu playlist remove ID)")
        for pid in args.ids:
            if pid in data["playlists"]:
                data["playlists"][pid]["saved"] = saved
    if missing:
        raise YouTubeError("unknown playlist %s (add it by URL with: paattu playlist add)" % missing[0])
    if saved:
        data = library.load()
        fetch_playlists([pid for pid in args.ids if data["playlists"][pid].get("tracks") is None], out)
        cache_art_for(library.load(), playlist_ids=args.ids)
    out.done(("Saved " if saved else "Removed from library: ") + ", ".join(
        library.load()["playlists"][pid]["title"] for pid in args.ids))


def cmd_import(args, out):
    """One box for anything pasted: a profile adds all its playlists, a
    playlist link adds that playlist."""
    kind, target = youtube.classify(args.link)
    if kind == "playlist":
        args.url = args.link
        return cmd_playlist_add(args, out)
    args.query, args.save = target, None
    return cmd_user_add(args, out)


def _playlist_ref(data, ref):
    """A playlist id from an id, or the name of one of your playlists."""
    if ref in data["playlists"]:
        return ref
    if (ref or "").strip().lower() in FAVOURITE_NAMES:
        return library.FAVOURITES
    if (ref or "").strip().lower() in library.SAVED_NAMES:
        return library.SAVED
    own = library.find_own_playlist(data, ref)
    return own["id"] if own else ref


def cmd_playlist_remove(args, out):
    with library.edit() as data:
        args.ids = [_playlist_ref(data, ref) for ref in args.ids]
        if library.FAVOURITES in args.ids:
            raise ValueError("Favourites stays; take songs out with: paattu fav --remove SONG")
        if library.SAVED in args.ids:
            raise ValueError("Saved songs stays; take songs out with: paattu save --remove SONG")
        unknown = [pid for pid in args.ids if pid not in data["playlists"]]
        if unknown:
            raise YouTubeError("unknown playlist %s" % unknown[0])
        gone = [library.remove_playlist(data, pid) for pid in args.ids]
    names = ", ".join(p["title"] for p in gone)
    out.done(("Deleted %s" if all(p.get("local") for p in gone) else "Removed %s from Paattu") % names, removed=args.ids)


def cmd_playlist_restore(args, out):
    data = library.load()
    owner = _find_user(data, args.user)["id"] if args.user else None
    if not args.ids and not owner:
        raise YouTubeError("say which playlists to bring back (ids, or --user)")
    with library.edit() as data:
        was = dict(data["removed"])
        ids = library.unremove_playlists(data, ids=set(args.ids) if args.ids else None, owner=owner)
    if not ids:
        raise YouTubeError("nothing removed to bring back")
    followed = library.load()["users"]
    for uid in {was[pid].get("owner") for pid in ids} & set(followed):
        out.progress("Listing %s's playlists…" % followed[uid]["name"])
        info = youtube.channel_playlists(followed[uid].get("url") or uid)
        with library.edit() as data:
            library.upsert_user(data, info, followed[uid].get("language", ""))
    # Playlists that aren't listed under a followed user come back by id.
    fetch_playlists([pid for pid in ids if pid not in library.load()["playlists"]], out)
    with library.edit() as data:
        back = [data["playlists"][pid] for pid in ids if pid in data["playlists"]]
        for playlist in back:
            playlist["saved"] = True
    out.done("Brought back %s" % ", ".join(p["title"] for p in back) if back else "Those playlists are gone from YouTube",
             restored=[p["id"] for p in back])


def cmd_playlist_remove_songs(args, out):
    with library.edit() as data:
        args.id = _playlist_ref(data, args.id)
        playlist = data["playlists"].get(args.id)
        if not playlist:
            raise YouTubeError("unknown playlist %s" % args.id)
        dropped = library.remove_tracks(data, args.id, [_track_ref(v) for v in args.songs])
        if not dropped:
            raise YouTubeError("those songs aren't in %s" % playlist["title"])
    out.done("Removed %s from %s" % (_plural(len(dropped), "song"), playlist["title"]), removed=dropped)


def cmd_playlist_restore_songs(args, out):
    with library.edit() as data:
        playlist = data["playlists"].get(args.id)
        if not playlist:
            raise YouTubeError("unknown playlist %s" % args.id)
        count = len(playlist.pop("removedTracks", None) or [])
    if count:
        failures = fetch_playlists([args.id], out)
        if failures:
            raise YouTubeError(failures[0])
    out.done("Brought back %s in %s" % (_plural(count, "removed song"), playlist["title"]))


def cmd_playlist_fetch(args, out):
    failures = fetch_playlists(args.ids, out)
    data = library.load()
    cache_art_for(data, playlist_ids=args.ids, track_ids=[t for pid in args.ids
                                                          for t in (data["playlists"].get(pid, {}).get("tracks") or [])])
    if failures:
        raise YouTubeError(failures[0])
    out.done("Fetched %d playlist%s" % (len(args.ids), "" if len(args.ids) == 1 else "s"))


def cmd_playlist_lang(args, out):
    with library.edit() as data:
        playlist = data["playlists"].get(args.id)
        if not playlist:
            raise YouTubeError("unknown playlist %s" % args.id)
        playlist["language"], playlist["languageSet"] = _language(args.language), True
    out.done("%s is now %s" % (playlist["title"], playlist["language"]))


def cmd_playlist_list(args, out):
    data = library.load()
    playlists = [p for p in data["playlists"].values() if args.all or p.get("saved")]
    if args.lang:
        playlists = [p for p in playlists if p.get("language") == _language(args.lang)]
    playlists.sort(key=lambda p: (p.get("language", ""), p.get("ownerName", ""), p.get("title", "")))
    if args.json:
        out.data(playlists)
        return
    for p in playlists:
        count = "%4d" % p["count"] if p.get("tracks") is not None else "   ?"
        print("%-34s %-10s %s  %-40s %s" % (p["id"], p.get("language", ""), count, p.get("title", "")[:40],
                                           p.get("ownerName", "")))


def cmd_playlist_show(args, out):
    data = ensure_tracks(args.id, out if args.json else Reporter(False))
    playlist = data["playlists"][args.id]
    tracks = library.playlist_tracks(data, args.id)
    if args.json:
        out.data({"playlist": playlist, "tracks": tracks})
        return
    print("%s — %s (%d tracks)" % (playlist["title"], playlist.get("ownerName", ""), len(tracks)))
    for n, t in enumerate(tracks, 1):
        print("%3d. %-40s %-26s %s" % (n, t["title"][:40], t.get("movie", "")[:26], _fmt_duration(t.get("duration"))))


# ---------------------------------------------------------------- your own playlists

FAVOURITE_NAMES = library.FAVOURITE_NAMES


def _track_from(vid, title="", channel="", duration=None, views=None):
    from .titles import clean_title
    meta = clean_title(title, channel) if title else {"title": "", "movie": "", "credits": [], "kind": "video"}
    return {"id": vid, "rawTitle": title, "title": meta["title"] or title, "movie": meta["movie"],
            "credits": meta["credits"][:6], "kind": meta["kind"], "channel": channel,
            "duration": round(duration) if duration else None, "views": views}


def _lookup_track(vid, out):
    """A song the library doesn't know: ask YouTube for its title."""
    out.progress("Looking up the song on YouTube…")
    try:
        d = youtube.video_details(vid)
    except YouTubeError:
        return _track_from(vid)
    return _track_from(vid, d["title"], d["channel"], d["duration"], d["views"])


def _known(data, tid):
    """A song by id: in the library, or found by an earlier search or link."""
    return (data["tracks"].get(tid) or sources.recall(tid)) if tid else None


def _playing_track(data, out):
    if not engine.running():
        return None
    with engine.Engine(autostart=False) as e:
        path = e.get("path") or ""
        title = e.get("media-title") or ""
        duration = e.get("duration")
    tid = sources.track_id(path) if path else None
    if not tid:
        return None
    known = _known(data, tid)
    if known:
        return known
    if not sources.is_video_id(tid):
        # A link played from a terminal: what mpv knows about it.
        song, _, movie = title.partition(" · ")
        return {"id": tid, "url": path, "site": sources.site_of(path), "rawTitle": title, "title": song or tid,
                "movie": movie, "credits": [], "kind": "song", "duration": round(duration) if duration else None}
    # Songs queued without a title play under their video id.
    if not title or title == tid or tid in title:
        return _lookup_track(tid, out)
    return _track_from(tid, title, duration=duration)


def _songs_for(data, ref, out):
    """The songs a reference names: an id from the library or a search, a
    video id, or a link to a song (or an album / set) on any site yt-dlp plays."""
    ref = (ref or "").strip()
    known = _known(data, ref)
    if known:
        return [known]
    if sources.is_link(ref):
        known = _known(data, sources.track_id(ref))
        if known:
            return [known]
        vid = youtube.video_id(ref) if sources.is_youtube(ref) else None
        if vid:
            return [_lookup_track(vid, out)]
        out.progress("Looking up %s…" % ref)
        tracks = sources.resolve(ref)
        sources.remember(tracks)
        return tracks
    vid = youtube.video_id(ref)
    if vid and sources.is_video_id(vid):
        return [_lookup_track(vid, out)]
    raise SourceError("not a song: %s (use a link, or an id from paattu search)" % ref)


def _songs(data, refs, out):
    """Track dicts for refs (see _songs_for); none given means the song playing now."""
    if not refs:
        track = _playing_track(data, out)
        if not track:
            raise EngineError("nothing is playing; name a song (a link, or an id from paattu search)")
        return [track]
    tracks = []
    for ref in refs:
        for track in _songs_for(data, ref, out):
            if track["id"] not in {t["id"] for t in tracks}:
                tracks.append(track)
    return tracks


def _track_ref(ref):
    """A track id from an id or a link."""
    if sources.is_link(ref):
        return sources.track_id(ref) or ref
    return youtube.video_id(ref) or ref


def _song_names(tracks):
    if len(tracks) == 1:
        return tracks[0].get("title") or tracks[0]["id"]
    return _plural(len(tracks), "song")


def _own_playlist(data, ref):
    """One of your playlists, inside library.edit(); Favourites and Saved songs are made on first use."""
    if (ref or "").strip().lower() in FAVOURITE_NAMES or ref == library.FAVOURITES:
        return library.favourites(data)
    if (ref or "").strip().lower() in library.SAVED_NAMES or ref == library.SAVED:
        return library.saved_songs(data)
    playlist = library.find_own_playlist(data, ref)
    if playlist:
        return playlist
    if ref in data["playlists"]:
        raise ValueError("%s comes from YouTube; songs go into your own playlists (paattu playlist new NAME)"
                         % data["playlists"][ref]["title"])
    raise ValueError("you have no playlist called %s (make one: paattu playlist new NAME)" % ref)


def _toggle_songs(args, out, playlist_id, make):
    """fav / save: add songs to (or take them out of) Favourites or Saved songs,
    or list it. Returns (removed?, tracks), or None after listing."""
    data = library.load()
    if args.list:
        tracks = library.playlist_tracks(data, playlist_id)
        if args.json:
            out.data(tracks)
            return None
        for n, t in enumerate(tracks, 1):
            print("%3d. %-40s %-26s %s" % (n, (t.get("title") or t["id"])[:40], t.get("movie", "")[:26], t["id"]))
        return None
    tracks = _songs(data, args.videos, out)
    ids = [t["id"] for t in tracks]
    with library.edit() as data:
        have = set(make(data)["tracks"])
        remove = all(tid in have for tid in ids) if args.toggle else args.remove
        if remove:
            library.remove_tracks(data, playlist_id, ids)
        else:
            library.add_tracks(data, playlist_id, tracks)
    if not remove:
        _spawn_art(ids)
    return remove, tracks


def cmd_fav(args, out):
    done = _toggle_songs(args, out, library.FAVOURITES, library.favourites)
    if done:
        remove, tracks = done
        out.done(("Removed %s from Favourites" if remove else "Added %s to Favourites") % _song_names(tracks),
                 favourite=not remove, songs=[t["id"] for t in tracks])


def cmd_save(args, out):
    done = _toggle_songs(args, out, library.SAVED, library.saved_songs)
    if done:
        remove, tracks = done
        out.done(("Took %s out of Saved songs" if remove else "Saved %s to your library") % _song_names(tracks),
                 saved=not remove, songs=[t["id"] for t in tracks])


def cmd_playlist_new(args, out):
    data = library.load()
    tracks = _songs(data, args.videos, out) if args.videos or args.now else []
    with library.edit() as data:
        playlist = library.create_playlist(data, args.name)
        library.add_tracks(data, playlist["id"], tracks)
    if tracks:
        _spawn_art([t["id"] for t in tracks])
    out.done("Made %s" % playlist["title"] + (" with %s" % _song_names(tracks) if tracks else ""),
             playlist=playlist["id"])


def cmd_playlist_add_songs(args, out):
    data = library.load()
    _own_playlist(data, args.playlist)  # fail before looking anything up
    tracks = _songs(data, args.videos, out)
    with library.edit() as data:
        playlist = _own_playlist(data, args.playlist)
        added = library.add_tracks(data, playlist["id"], tracks)
    _spawn_art(added)
    if not added:
        out.done("%s is already in %s" % (_song_names(tracks), playlist["title"]), playlist=playlist["id"], added=[])
        return
    out.done("Added %s to %s" % (_song_names([t for t in tracks if t["id"] in added]), playlist["title"]),
             playlist=playlist["id"], added=added)


def cmd_playlist_rename(args, out):
    with library.edit() as data:
        playlist = _own_playlist(data, args.playlist)
        old = playlist["title"]
        library.rename_playlist(data, playlist["id"], args.name)
    out.done("Renamed %s to %s" % (old, playlist["title"]), playlist=playlist["id"])


# ---------------------------------------------------------------- seed

def _queue_ids():
    """Track ids in the play queue (their art stays while they're queued)."""
    if not engine.running():
        return []
    with engine.Engine(autostart=False) as e:
        return [tid for tid in (sources.track_id(entry.get("filename") or "") for entry in e.get("playlist") or []) if tid]


def _megabytes(size):
    return "%.0f MB" % (size / 1e6) if size >= 1e6 else "%.0f kB" % (size / 1e3)


def cmd_seed_remove(args, out):
    with library.edit() as data:
        users, playlists = library.remove_starter(data)
        left = (len(data["users"]), sum(1 for p in data["playlists"].values() if p.get("saved")), len(data["tracks"]))
    if not users:
        out.done("The starter library isn't in Paattu", removed=0)
        return
    files, freed = art.prune(library.load(), _queue_ids())
    out.done("Removed the starter library: %s and their %s%s. Left: %s, %s, %s" % (
        _plural(len(users), "profile"), _plural(playlists, "saved playlist"),
        " (and %s of cached art)" % _megabytes(freed) if files else "",
        _plural(left[0], "profile"), _plural(left[1], "playlist"), _plural(left[2], "song")),
        removed=playlists, users=[u["id"] for u in users])


def cmd_seed(args, out):
    if args.remove:
        return cmd_seed_remove(args, out)
    languages = [_language(l) for l in args.lang.split(",")] if args.lang else list(seeds.LANGUAGES)
    picks = [c for c in seeds.CURATED if c[1] in languages]
    out.progress("Following %d Malayalam / Tamil labels and composers…" % len(picks), step=0, total=len(picks))
    infos = {}

    def lookup(entry):
        return entry, youtube.channel_playlists(entry[0])

    with concurrent.futures.ThreadPoolExecutor(max_workers=6) as pool:
        futures = [pool.submit(lookup, entry) for entry in picks]
        for n, future in enumerate(concurrent.futures.as_completed(futures), 1):
            try:
                entry, info = future.result()
                infos[entry[0]] = (entry, info)
                out.progress("%s: %d playlists" % (info["name"], len(info["playlists"])), step=n, total=len(picks))
            except YouTubeError as e:
                out.progress("Skipped a channel: %s" % e, step=n, total=len(picks))

    to_fetch = []
    with library.edit() as data:
        for handle, language, kind in picks:
            if handle not in infos:
                continue
            _, info = infos[handle]
            user = library.upsert_user(data, info, language, curated=True)
            user["kind"] = kind
            stubs = [data["playlists"][pid] for pid in user["playlists"]]
            for playlist in seeds.pick_featured(stubs, args.per_user):
                playlist["saved"] = True
                playlist["featured"] = True
                if playlist.get("tracks") is None:
                    to_fetch.append(playlist["id"])
    out.progress("Fetching %d featured playlists…" % len(to_fetch))
    fetch_playlists(to_fetch, out)
    data = library.load()
    out.progress("Caching artwork…")
    featured = [p["id"] for p in data["playlists"].values() if p.get("featured")]
    cache_art_for(data, playlist_ids=featured, user_ids=list(data["users"]))
    saved = sum(1 for p in data["playlists"].values() if p.get("saved"))
    out.done("Library ready: %d users, %d saved playlists, %d tracks" % (len(data["users"]), saved, len(data["tracks"])),
             users=len(data["users"]), saved=saved, tracks=len(data["tracks"]))


# ---------------------------------------------------------------- mixes

def _mix_sources(data, args):
    """[{type, id}] from --lang / --user / --playlist (call inside library.edit())."""
    sources = [{"type": "language", "id": _language(v)} for v in args.lang or []]
    for ref in args.user or []:
        user = library.find_user(data, ref)
        if not user:
            raise YouTubeError("not following %s" % ref)
        sources.append({"type": "user", "id": user["id"]})
    for ref in args.playlist or []:
        pid = _playlist_ref(data, ref)
        if pid == library.FAVOURITES:
            library.favourites(data)
        elif pid == library.SAVED:
            library.saved_songs(data)
        if pid not in data["playlists"]:
            with contextlib.suppress(YouTubeError):
                pid = youtube.normalize_playlist(ref)
        if pid not in data["playlists"]:
            named = [p["id"] for p in data["playlists"].values()
                     if p.get("saved") and p.get("title", "").lower() == " ".join(ref.split()).lower()]
            if len(named) > 1:
                raise ValueError("%d playlists are called %s; use the id (paattu playlist list)" % (len(named), ref))
            pid = named[0] if named else pid
        if pid not in data["playlists"]:
            raise YouTubeError("%s isn't in Paattu (add it first: paattu import LINK)" % ref)
        sources.append({"type": "playlist", "id": pid})
    return sources


def _source_names(data, sources):
    return ", ".join(library.source_title(data, s) or s["id"] for s in sources)


def _unfetched(data, sources):
    return [s["id"] for s in sources if s["type"] == "playlist" and data["playlists"][s["id"]].get("tracks") is None]


def _mix_line(mix):
    if not mix["sources"]:
        return "%-22s empty" % mix["title"][:22]
    what = ", ".join(s["title"] or s["id"] for s in mix["sources"])
    if not mix["playlists"]:
        return "%-22s %s · no saved playlists yet" % (mix["title"][:22], what)
    waiting = ", %s not loaded (paattu mix fetch)" % _plural(mix["waiting"], "playlist") if mix["waiting"] else ""
    return "%-22s %s · %s%s" % (mix["title"][:22], what, _plural(mix["count"], "song"), waiting)


def cmd_mix(args, out):
    action = args.action
    if action == "list":
        mixes = library.shelf(library.load())["mixes"]
        if args.json:
            out.data(mixes)
            return
        for n, mix in enumerate(mixes, 1):
            print("%d. %s" % (n, _mix_line(mix)))
        if not mixes:
            print("No mixes. Make one: paattu mix new NAME --lang Malayalam")
        return
    fetch, fields = [], {}
    with library.edit() as data:
        if action == "fetch":
            mix = library.get_mix(data, args.mix)
            fetch = [p["id"] for p in library.mix_playlists(data, mix) if p.get("tracks") is None]
            message = "Loaded songs for %s in %s" % (_plural(len(fetch), "playlist"), mix["title"]) if fetch else \
                "Every playlist in %s has its songs" % mix["title"]
        elif action == "new":
            sources = _mix_sources(data, args)
            mix = library.create_mix(data, args.name, sources)
            fetch = _unfetched(data, sources)
            message = "Made %s" % mix["title"] + (" from %s" % _source_names(data, sources) if sources else "")
        elif action in ("add", "drop"):
            mix = library.get_mix(data, args.mix)
            sources = _mix_sources(data, args)
            if not sources:
                raise ValueError("say what to %s: --lang, --user or --playlist" % action)
            if action == "add":
                changed = library.add_mix_sources(data, mix["id"], sources)
                fetch = _unfetched(data, changed)
                message = ("Added %s to %s" if changed else "%s is already in %s") % (
                    _source_names(data, changed or sources), mix["title"])
            else:
                changed = library.drop_mix_sources(data, mix["id"], sources)
                message = ("Took %s out of %s" if changed else "%s isn't in %s") % (
                    _source_names(data, changed or sources), mix["title"])
            fields["changed"] = changed
        elif action == "rename":
            mix = library.get_mix(data, args.mix)
            old = mix["title"]
            library.rename_mix(data, mix["id"], args.name)
            message = "Renamed %s to %s" % (old, mix["title"])
        elif action == "move":
            mix = library.get_mix(data, args.mix)
            position = library.move_mix(data, mix["id"], args.position - 1)
            message = "%s is now button %d" % (mix["title"], position + 1)
        else:
            mix = library.remove_mix(data, args.mix)
            message = "Deleted %s" % mix["title"]
    if fetch:
        failures = fetch_playlists(fetch, out)
        if len(failures) == len(fetch):
            raise YouTubeError(failures[0])
        if failures:
            message += " (%s couldn't load: %s)" % (_plural(len(failures), "playlist"), failures[0])
    out.done(message, mix=mix["id"], **fields)


# ---------------------------------------------------------------- playback

def _queue_from_args(args, out):
    """(tracks, start, source) for `paattu play`."""
    cfg = config.load()
    data = library.load()
    target = args.target or ""
    start = 0
    if args.lang or args.user or args.mix:
        explicit = []
        if args.mix:
            mix = library.find_mix(data, args.mix)
            if not mix:
                raise ValueError("there's no mix called %s (paattu mix list)" % args.mix)
            playlists = library.mix_playlists(data, mix)
            if not mix["sources"]:
                raise EngineError("%s is empty: add a language, profile or playlist to it" % mix["title"])
            if not playlists:
                raise EngineError("Nothing to play in %s yet: no saved playlists in %s" % (
                    mix["title"], _source_names(data, mix["sources"])))
            explicit = [s["id"] for s in mix["sources"] if s["type"] == "playlist"]
            source = {"type": "mix", "id": mix["id"], "title": mix["title"]}
        elif args.lang:
            language = _language(args.lang)
            playlists = library.language_playlists(data, language)
            source = {"type": "language", "id": language, "title": language + " mix"}
        else:
            user = library.find_user(data, args.user)
            if not user:
                raise YouTubeError("not following %s" % args.user)
            playlists = [data["playlists"][pid] for pid in user["playlists"] if data["playlists"].get(pid, {}).get("saved")]
            source = {"type": "user", "id": user["id"], "title": user["name"]}
        unfetched = [p["id"] for p in playlists if p.get("tracks") is None]
        # Playlists picked one by one for a mix always play; otherwise, when
        # nothing is playable yet, fetch a few to start with.
        fetch = [pid for pid in unfetched if pid in explicit]
        if unfetched and not any(p.get("tracks") for p in playlists):
            fetch += [pid for pid in unfetched if pid not in fetch][:FETCH_FIRST]
        if fetch:
            fetch_playlists(fetch, out)
            data = library.load()
        tracks = [t for p in playlists for t in library.playlist_tracks(data, p["id"])]
        random.shuffle(tracks)
        return engine.queue_tracks(tracks, cfg["queue"]["dedupe"], cfg["queue"]["skipTrailers"]), 0, source

    own = library.find_own_playlist(data, target) if target else None
    if target.strip().lower() in FAVOURITE_NAMES and not own:
        raise EngineError("Favourites is empty: press the heart on a song first")
    if target.strip().lower() in library.SAVED_NAMES and not own:
        raise EngineError("Saved songs is empty: save a song from a search first")
    if target and not own and not sources.is_video_id(target) and (
            _known(data, target) or sources.is_link(target) and not sources.is_youtube(target)):
        # One song (or an album / set) from a search or another site.
        tracks = _songs_for(data, target, out)
        return tracks, 0, {"type": "track", "id": tracks[0]["id"],
                           "title": sources.site_name(tracks[0].get("site") or "youtube")}
    vid = youtube.video_id(target) if target and not own else None
    try:
        pid = own["id"] if own else youtube.normalize_playlist(target)
    except YouTubeError:
        pid = None
    if pid:
        data = ensure_tracks(pid, out)
        playlist = data["playlists"][pid]
        tracks = library.playlist_tracks(data, pid)
        # Your own playlists play exactly what you put in them.
        tracks = tracks if own else engine.queue_tracks(tracks, cfg["queue"]["dedupe"], cfg["queue"]["skipTrailers"])
        wanted = args.track or vid
        if wanted:
            start = next((i for i, t in enumerate(tracks) if t["id"] == wanted), 0)
        elif args.index:
            start = args.index - 1
        return tracks, start, {"type": "playlist", "id": pid, "title": playlist["title"]}
    if vid:
        track = _known(data, vid) or {"id": vid, "title": "", "rawTitle": ""}
        return [track], 0, {"type": "track", "id": vid, "title": track.get("title") or "YouTube"}
    raise YouTubeError("play a playlist id or link, a video link, --mix NAME, --lang Malayalam|Tamil, or --user @handle")


FIREWALL_FIX = "sudo ~/.local/lib/paattu/install.sh --firewall"


def _check_firewall():
    """OpenSnitch turns an unanswered prompt into a permanent block after 30 s."""
    state = engine.firewall_status()
    if state == "blocked":
        raise EngineError("OpenSnitch has a saved rule blocking mpv, so nothing can stream. Fix: " + FIREWALL_FIX)
    if state == "ask" and shutil.which("notify-send"):
        subprocess.Popen(["notify-send", "-a", "Paattu", "-u", "critical", "Paattu: allow mpv in OpenSnitch",
                          "OpenSnitch is about to ask about mpv. Click Allow, or run once: " + FIREWALL_FIX],
                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def cmd_play(args, out):
    tracks, start, source = _queue_from_args(args, out)
    if not tracks:
        raise EngineError("nothing to play there yet")
    _check_firewall()
    with engine.Engine() as e:
        engine.load(e, tracks, start=start, shuffle=args.shuffle, source=source)
    first = tracks[start]
    _spawn_art([t["id"] for t in tracks[start:start + 8]])
    out.done("Playing %s — %s" % (first.get("title") or first["id"], source["title"]),
             track=first["id"], count=len(tracks))


def cmd_add(args, out):
    data = library.load()
    tracks = []
    for ref in args.targets:
        vid = youtube.video_id(ref) if not sources.is_link(ref) or sources.is_youtube(ref) else None
        if vid and sources.is_video_id(vid) and not _known(data, ref):
            # A video the library doesn't know plays under its id; no lookup needed.
            tracks.append(data["tracks"].get(vid) or {"id": vid, "title": ""})
        else:
            tracks += _songs_for(data, ref, out)
    with engine.Engine() as e:
        engine.enqueue(e, tracks, next_up=args.next)
    _spawn_art([t["id"] for t in tracks[:8]])
    out.done(("Playing %s next" if args.next else "Queued %s") % _song_names(tracks), count=len(tracks))


def _spawn_art(track_ids):
    """Cache cover art for upcoming tracks without holding up playback."""
    if track_ids:
        # --tracks=ID: video ids can start with "-", which would read as an option.
        subprocess.Popen([sys.executable, "-m", "paattu", "art"] + ["--tracks=" + t for t in track_ids],
                         cwd=str(paths_root()), stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                         stderr=subprocess.DEVNULL, start_new_session=True)


def paths_root():
    import pathlib
    return pathlib.Path(__file__).resolve().parent.parent


def cmd_transport(args, out):
    with engine.Engine(autostart=False) as e:
        action = args.action
        if action == "toggle":
            e.send(["cycle", "pause"])
        elif action == "pause":
            e.set("pause", True)
        elif action == "resume":
            e.set("pause", False)
        elif action == "next":
            e.send(["playlist-next", "weak"])
        elif action == "prev":
            if (e.get("time-pos") or 0) > 4:
                e.send(["seek", 0, "absolute"])
            else:
                e.send(["playlist-prev", "weak"])
        elif action == "stop":
            e.send(["stop"])
    out.done()


def cmd_seek(args, out):
    value = args.value
    with engine.Engine(autostart=False) as e:
        if value.startswith(("+", "-")):
            e.send(["seek", float(value), "relative"])
        else:
            e.send(["seek", float(value), "absolute"])
    out.done()


def cmd_volume(args, out):
    with engine.Engine(autostart=False) as e:
        if args.value is None:
            out.data({"volume": e.get("volume")}, "%d" % (e.get("volume") or 0))
            return
        if args.value.startswith(("+", "-")):
            e.send(["add", "volume", float(args.value)])
        else:
            e.set("volume", max(0.0, min(100.0, float(args.value))))
        out.done("%d" % e.get("volume"))


def cmd_shuffle(args, out):
    with engine.Engine(autostart=False) as e:
        value = engine.set_shuffle(e, args.mode)
    out.done("Shuffle " + ("on" if value else "off"), shuffle=value)


def cmd_repeat(args, out):
    with engine.Engine(autostart=False) as e:
        mode = engine.set_repeat(e, args.mode)
    out.done("Repeat " + mode, repeat=mode)


def cmd_status(args, out):
    if not engine.running():
        out.data({"running": False}, "Engine stopped")
        return
    with engine.Engine(autostart=False) as e:
        st = engine.status(e)
    tid = sources.track_id(st["path"]) if st["path"] else None
    track = _known(library.load(), tid)
    st["track"] = track
    if args.json:
        out.data(st)
        return
    if st["idle"]:
        print("Idle")
        return
    title = track["title"] if track else st["title"]
    print("%s %s%s  %s / %s  [%d/%d]  vol %d  shuffle %s  repeat %s" % (
        "⏸" if st["paused"] else "▶", title, " · " + track["movie"] if track and track.get("movie") else "",
        _fmt_duration(st["position"]), _fmt_duration(st["duration"]), st["index"] + 1, st["count"],
        st["volume"], "on" if st["shuffle"] else "off", st["repeat"]))


def cmd_queue(args, out):
    with engine.Engine(autostart=False) as e:
        entries = e.get("playlist") or []
    data = library.load()
    rows = []
    for n, entry in enumerate(entries):
        tid = sources.track_id(entry.get("filename", ""))
        track = _known(data, tid)
        rows.append({"index": n, "id": tid, "title": (track or {}).get("title") or entry.get("title", ""),
                     "movie": (track or {}).get("movie", ""), "current": bool(entry.get("current"))})
    if args.json:
        out.data(rows)
        return
    for row in rows:
        print("%s %3d. %s%s" % ("▶" if row["current"] else " ", row["index"] + 1, row["title"],
                                " · " + row["movie"] if row["movie"] else ""))


def cmd_jump(args, out):
    with engine.Engine(autostart=False) as e:
        e.send(["playlist-play-index", args.index - 1])
        e.set("pause", False)
    out.done()


def cmd_engine(args, out):
    if args.action == "start":
        engine.start()
        out.done("Engine running")
    elif args.action == "stop":
        engine.stop()
        out.done("Engine stopped")
    elif args.action == "restart":
        engine.stop()
        engine.start()
        out.done("Engine restarted")
    else:
        out.data({"running": engine.running(), "socket": str(paths.SOCKET)},
                 "running" if engine.running() else "stopped")


def cmd_art(args, out):
    data = library.load()
    if args.prune:
        files, freed = art.prune(data, _queue_ids())
        out.done("Deleted %s of art for things no longer in Paattu (%s)" % (_plural(files, "image"), _megabytes(freed)),
                 deleted=files)
        return
    track_ids = list(args.tracks or [])
    for pid in args.playlist or []:
        track_ids += data["playlists"].get(pid, {}).get("tracks") or []
    user_ids = list(args.user or [])
    playlist_ids = list(args.playlist or [])
    for uid in args.user_playlists or []:
        playlist_ids += data["users"].get(uid, {}).get("playlists", [])
    if args.missing:
        playlist_ids += [p["id"] for p in data["playlists"].values() if p.get("saved")]
        user_ids += list(data["users"])
    count = cache_art_for(data, playlist_ids=playlist_ids, user_ids=user_ids, track_ids=track_ids)
    out.done("Cached %d image%s" % (count, "" if count == 1 else "s"), cached=count)


# ---------------------------------------------------------------- search

def _search_art(tracks, wait=5):
    """Cache result covers, giving up on slow ones after about `wait` seconds."""
    jobs = [(art.track_art(t["id"], t), paths.art_path("v", t["id"])) for t in tracks]
    jobs = [(u, d) for u, d in jobs if u and not (d.exists() and d.stat().st_size > 0)]
    if not jobs:
        return
    pool = concurrent.futures.ThreadPoolExecutor(max_workers=16)
    futures = [pool.submit(art.fetch, u, d, 4) for u, d in jobs]
    concurrent.futures.wait(futures, timeout=wait)
    pool.shutdown(wait=False, cancel_futures=True)


def _result_line(n, t):
    quality = sources.quality_label(t)
    return "%3d. %-34s %-22s %-8s %s" % (n, (t.get("title") or t["id"])[:34], (t.get("movie") or ", ".join(t.get("credits") or []))[:22],
                                     quality, t["id"])


def cmd_search(args, out):
    query = " ".join(args.query).strip()
    if not query:
        raise ValueError("search for a song, a film or a singer: paattu search malare premam")
    cfg = config.load()["search"]
    limit = max(1, min(args.limit or cfg.get("limit") or 12, 50))
    if sources.is_link(query):
        # A link: the song (or album / set) behind it, from any site yt-dlp plays.
        found, errors = {"link": _songs_for(library.load(), query, out)}, {}
    else:
        sites = args.site or [s for s in cfg.get("sites") or sources.SEARCH_SITES if s in sources.SEARCHERS]
        if not args.json:
            out.progress("Searching %s…" % ", ".join(sources.site_name(s) for s in sites))
        found, errors = sources.search(query, sites, limit)
    results = [dict(t, site=t.get("site") or "youtube") for tracks in found.values() for t in tracks]
    sources.remember(results)
    if args.json:
        _search_art(results)
        out.done("%s for %s" % (_plural(len(results), "song"), query) if results else "Nothing found for %s" % query,
                 query=query, results=results, errors=errors)
        return
    for site, tracks in found.items():
        if not tracks:
            continue
        print("\n%s" % ("Link" if site == "link" else sources.site_name(site)))
        for n, t in enumerate(tracks, 1):
            print(_result_line(n, t))
    for site, message in errors.items():
        print("\n%s: %s" % (sources.site_name(site), message), file=sys.stderr)
    if results:
        print("\nPlay one: paattu play ID   ·   keep it: paattu save ID / paattu fav ID / "
              "paattu playlist add-songs NAME ID")
    else:
        print("Nothing found for %s" % query)


def cmd_theme(args, out):
    if args.action == "list" or not args.name:
        current = config.load()["theme"]
        names = ["omarchy"] + config.theme_names()
        if args.json:
            themes = [{"name": "omarchy", "title": "Omarchy", "description": "Follows your Omarchy theme"}]
            for name in names[1:]:
                try:
                    data = config.theme(name)
                    themes.append({**data, "name": name, "title": data.get("name") or name.replace("-", " ").title()})
                except (OSError, ValueError):
                    continue
            out.data({"current": current, "themes": themes, "dir": str(paths.THEMES)})
            return
        for name in names:
            label = "follows your Omarchy theme" if name == "omarchy" else config.theme(name).get("description", "")
            print("%s %-14s %s" % ("*" if name == current else " ", name, label))
        return
    config.set_key("theme", args.name)
    out.done("Theme: " + args.name)


def cmd_config(args, out):
    if args.action == "path":
        print(paths.CONFIG_FILE)
        return
    if args.action == "set":
        cfg = config.set_key(args.key, config.parse_value(args.value))
        out.done("%s = %s" % (args.key, json.dumps(config.get(cfg, args.key))))
        return
    cfg = config.load()
    value = config.get(cfg, args.key) if args.key else cfg
    out.data(value, json.dumps(value, indent=2, ensure_ascii=False))


def cmd_export(args, out):
    names = cliamp.export(library.load(), _language(args.lang) if args.lang else None)
    out.done("Wrote %d cliamp playlist%s to %s" % (len(names), "" if len(names) == 1 else "s", paths.CLIAMP_PLAYLISTS),
             count=len(names))


def cmd_watch(args, out):
    """Open the video in Brave (Shields blocks the ads) and pause the audio.
    A song from another site opens at its page there (and keeps playing)."""
    target = args.target or ""
    position = 0
    playing = not target and engine.running()
    if playing:
        with engine.Engine(autostart=False) as e:
            target = e.get("path") or ""
            position = int(e.get("time-pos") or 0)
    if not target:
        raise EngineError("nothing playing to watch")
    known = _known(library.load(), target)
    if known and known.get("url"):
        target = known["url"]
    vid = youtube.video_id(target) if not sources.is_link(target) or sources.is_youtube(target) else None
    if vid:
        url = youtube.watch_url(vid) + ("&t=%ds" % position if position else "")
        if playing:
            with engine.Engine(autostart=False) as e:
                e.set("pause", True)
    elif sources.is_link(target):
        url = target
    else:
        raise EngineError("not a song link: %s" % target)
    launcher = shutil.which("omarchy-launch-webapp") or shutil.which("xdg-open")
    if not launcher:
        import webbrowser
        webbrowser.open(url)
        out.done("Opened " + url)
        return
    subprocess.Popen([launcher, url], stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                     start_new_session=True)
    out.done("Opened " + url)


def cmd_open(args, out):
    if not shutil.which("omarchy-shell"):
        raise EngineError("the Paattu window is part of the Omarchy shell; elsewhere use the Paattu desktop app "
                          "or the commands (paattu --help)")
    payload = json.dumps({"view": args.view or "home"})
    subprocess.run(["omarchy-shell", "shell", "summon", PLUGIN_ID, payload], capture_output=True)
    out.done()


# ---------------------------------------------------------------- parser

def build_parser():
    p = argparse.ArgumentParser(prog="paattu", description=__doc__)
    p.add_argument("--version", action="version", version="paattu " + __version__)
    p.add_argument("--json", action="store_true", help="JSON output (for the shell plugin)")
    sub = p.add_subparsers(dest="command", required=True)

    user = sub.add_parser("user", help="follow YouTube users and their public playlists").add_subparsers(dest="action", required=True)
    a = user.add_parser("add", help="follow a YouTube user (@handle or channel URL) and save all their playlists")
    a.add_argument("query")
    a.add_argument("--lang", help="Malayalam, Tamil or Other (guessed when left out)")
    a.add_argument("--save", type=int, metavar="N", help="save only the N best playlists (default: all)")
    a.set_defaults(func=cmd_user_add)
    a = user.add_parser("save-all", help="save every playlist of a followed user")
    a.add_argument("query")
    a.set_defaults(func=cmd_user_save_all)
    a = user.add_parser("fetch", help="fetch songs for a user's saved playlists that don't have them yet")
    a.add_argument("query")
    a.set_defaults(func=cmd_user_fetch)
    user.add_parser("list", help="followed users").set_defaults(func=cmd_user_list)
    a = user.add_parser("sync", help="pick up new playlists and tracks")
    a.add_argument("query", nargs="?")
    a.set_defaults(func=cmd_user_sync)
    a = user.add_parser("remove", help="unfollow a user (saved playlists stay)")
    a.add_argument("query")
    a.add_argument("--purge", action="store_true", help="also remove their saved playlists")
    a.set_defaults(func=cmd_user_remove)

    pl = sub.add_parser("playlist", help="public playlists in the library").add_subparsers(dest="action", required=True)
    a = pl.add_parser("add", help="save a public playlist by URL")
    a.add_argument("url")
    a.add_argument("--lang")
    a.set_defaults(func=cmd_playlist_add)
    a = pl.add_parser("remove", help="remove playlists from Paattu (syncing won't bring them back)")
    a.add_argument("ids", nargs="+")
    a.set_defaults(func=cmd_playlist_remove)
    a = pl.add_parser("restore", help="bring back removed playlists")
    a.add_argument("ids", nargs="*")
    a.add_argument("--user", help="all removed playlists of this user")
    a.set_defaults(func=cmd_playlist_restore)
    a = pl.add_parser("remove-songs", help="remove songs from a playlist (refreshing won't bring them back)")
    a.add_argument("id")
    a.add_argument("songs", nargs="+", help="video ids or links")
    a.set_defaults(func=cmd_playlist_remove_songs)
    a = pl.add_parser("restore-songs", help="bring back the songs removed from a playlist")
    a.add_argument("id")
    a.set_defaults(func=cmd_playlist_restore_songs)
    a = pl.add_parser("new", help="make a playlist of your own")
    a.add_argument("name")
    a.add_argument("videos", nargs="*", help="songs to start it with (video links or ids)")
    a.add_argument("--now", action="store_true", help="start it with the song playing now")
    a.set_defaults(func=cmd_playlist_new)
    a = pl.add_parser("add-songs", help="add songs to one of your playlists (default: the song playing now)")
    a.add_argument("playlist", help="its id or name, or favourites")
    a.add_argument("videos", nargs="*")
    a.set_defaults(func=cmd_playlist_add_songs)
    a = pl.add_parser("rename", help="rename one of your playlists")
    a.add_argument("playlist")
    a.add_argument("name")
    a.set_defaults(func=cmd_playlist_rename)
    a = pl.add_parser("save", help="save playlists into the library")
    a.add_argument("ids", nargs="+")
    a.set_defaults(func=cmd_playlist_save)
    a = pl.add_parser("unsave", help="take playlists out of the library")
    a.add_argument("ids", nargs="+")
    a.set_defaults(func=lambda args, out: cmd_playlist_save(args, out, saved=False))
    a = pl.add_parser("fetch", help="(re)fetch tracks")
    a.add_argument("ids", nargs="+")
    a.set_defaults(func=cmd_playlist_fetch)
    a = pl.add_parser("lang", help="set a playlist's language")
    a.add_argument("id")
    a.add_argument("language")
    a.set_defaults(func=cmd_playlist_lang)
    a = pl.add_parser("list", help="saved playlists")
    a.add_argument("--lang")
    a.add_argument("--all", action="store_true", help="include playlists you haven't saved")
    a.set_defaults(func=cmd_playlist_list)
    a = pl.add_parser("show", help="tracks of a playlist")
    a.add_argument("id")
    a.set_defaults(func=cmd_playlist_show)

    songs_help = "song links (any site) or ids (from paattu search)"
    a = sub.add_parser("fav", help="add songs to Favourites (default: the song playing now)")
    a.add_argument("videos", nargs="*", help=songs_help)
    mode = a.add_mutually_exclusive_group()
    mode.add_argument("--remove", action="store_true", help="take them out of Favourites")
    mode.add_argument("--toggle", action="store_true", help="add, or take out if already there")
    mode.add_argument("--list", action="store_true", help="list Favourites")
    a.set_defaults(func=cmd_fav)
    a = sub.add_parser("save", help="save songs to your library (Saved songs; default: the song playing now)")
    a.add_argument("videos", nargs="*", help=songs_help)
    mode = a.add_mutually_exclusive_group()
    mode.add_argument("--remove", action="store_true", help="take them out of Saved songs")
    mode.add_argument("--toggle", action="store_true", help="save, or take out if already saved")
    mode.add_argument("--list", action="store_true", help="list Saved songs")
    a.set_defaults(func=cmd_save)

    a = sub.add_parser("search", help="find songs on JioSaavn (320 kbps), YouTube and SoundCloud, or look up a link")
    a.add_argument("query", nargs="+", help="a song, film or singer; or a link to a song or album on any site")
    a.add_argument("--site", action="append", choices=sources.SEARCH_SITES, help="only this site (repeatable)")
    a.add_argument("--limit", type=int, help="results per site (default 12)")
    a.set_defaults(func=cmd_search)

    a = sub.add_parser("import", help="add a YouTube profile (all its playlists) or a playlist link")
    a.add_argument("link")
    a.add_argument("--lang", help="Malayalam, Tamil or Other (guessed when left out)")
    a.set_defaults(func=cmd_import)

    a = sub.add_parser("seed", help="build the Malayalam & Tamil starter library (--remove takes it out)")
    a.add_argument("--lang", help="comma-separated, default Malayalam,Tamil")
    a.add_argument("--per-user", type=int, default=4, help="featured playlists saved per user (default 4)")
    a.add_argument("--remove", action="store_true",
                   help="take the starter library out: its profiles and playlists go, what you added stays")
    a.set_defaults(func=cmd_seed)

    mix = sub.add_parser("mix", help="the shuffle buttons: mixes of languages, YouTube users and playlists") \
        .add_subparsers(dest="action", required=True)

    def mix_sources(a):
        a.add_argument("--lang", action="append", metavar="LANGUAGE", help="a language's saved playlists")
        a.add_argument("--user", action="append", metavar="USER", help="a followed user's saved playlists")
        a.add_argument("--playlist", action="append", metavar="PLAYLIST",
                       help="one playlist: id, link, favourites, or the name of one you made or saved")

    mix.add_parser("list", help="the mixes, in button order").set_defaults(func=cmd_mix)
    a = mix.add_parser("new", help="make a mix")
    a.add_argument("name")
    mix_sources(a)
    a.set_defaults(func=cmd_mix)
    a = mix.add_parser("add", help="add languages, users or playlists to a mix")
    a.add_argument("mix", help="its name or id")
    mix_sources(a)
    a.set_defaults(func=cmd_mix)
    a = mix.add_parser("drop", help="take languages, users or playlists out of a mix")
    a.add_argument("mix")
    mix_sources(a)
    a.set_defaults(func=cmd_mix)
    a = mix.add_parser("rename", help="rename a mix")
    a.add_argument("mix")
    a.add_argument("name")
    a.set_defaults(func=cmd_mix)
    a = mix.add_parser("move", help="change a mix's place among the buttons")
    a.add_argument("mix")
    a.add_argument("position", type=int, help="1 is the first button")
    a.set_defaults(func=cmd_mix)
    a = mix.add_parser("remove", help="delete a mix")
    a.add_argument("mix")
    a.set_defaults(func=cmd_mix)
    a = mix.add_parser("fetch", help="load songs for the playlists in a mix that don't have them yet")
    a.add_argument("mix")
    a.set_defaults(func=cmd_mix)

    a = sub.add_parser("play", help="play a playlist (yours by name, favourites, saved), a song (link or search id), "
                                    "a mix, a language or a user")
    a.add_argument("target", nargs="?")
    a.add_argument("--mix", help="a mix by name or id (paattu mix list)")
    a.add_argument("--lang")
    a.add_argument("--user")
    a.add_argument("--index", type=int, help="start at this track number")
    a.add_argument("--track", help="start at this video id")
    a.add_argument("--shuffle", action="store_true")
    a.set_defaults(func=cmd_play)
    a = sub.add_parser("add", help="queue songs: links (any site), video ids or ids from paattu search")
    a.add_argument("targets", nargs="+")
    a.add_argument("--next", action="store_true", help="play after the current track")
    a.set_defaults(func=cmd_add)
    for name, text in (("toggle", "play / pause"), ("pause", "pause"), ("resume", "resume"), ("next", "next track"),
                       ("prev", "previous track (or restart this one)"), ("stop", "stop and clear the queue")):
        sub.add_parser(name, help=text).set_defaults(func=cmd_transport, action=name)
    a = sub.add_parser("seek", help="seek: 90 (absolute), +10 / -10 (relative)")
    a.add_argument("value")
    a.set_defaults(func=cmd_seek)
    a = sub.add_parser("volume", help="volume 0-100, or +5 / -5")
    a.add_argument("value", nargs="?")
    a.set_defaults(func=cmd_volume)
    a = sub.add_parser("shuffle", help="shuffle on|off|toggle")
    a.add_argument("mode", nargs="?", default="toggle", choices=("on", "off", "toggle"))
    a.set_defaults(func=cmd_shuffle)
    a = sub.add_parser("repeat", help="repeat off|all|one|cycle")
    a.add_argument("mode", nargs="?", default="cycle", choices=("off", "all", "one", "cycle"))
    a.set_defaults(func=cmd_repeat)
    sub.add_parser("status", help="what's playing").set_defaults(func=cmd_status)
    sub.add_parser("queue", help="the play queue").set_defaults(func=cmd_queue)
    a = sub.add_parser("jump", help="play queue entry N")
    a.add_argument("index", type=int)
    a.set_defaults(func=cmd_jump)

    a = sub.add_parser("engine", help="the mpv playback engine")
    a.add_argument("action", choices=("start", "stop", "restart", "status"))
    a.set_defaults(func=cmd_engine)

    a = sub.add_parser("art", help="cache artwork")
    a.add_argument("--tracks", nargs="*", action="extend", help="song ids (--tracks=ID for ids starting with -)")
    a.add_argument("--playlist", nargs="*")
    a.add_argument("--user", nargs="*")
    a.add_argument("--user-playlists", nargs="*")
    a.add_argument("--missing", action="store_true")
    a.add_argument("--prune", action="store_true", help="delete cached art for things no longer in the library")
    a.set_defaults(func=cmd_art)

    a = sub.add_parser("theme", help="colour schemes (list | set NAME)")
    a.add_argument("action", nargs="?", default="list", choices=("list", "set"))
    a.add_argument("name", nargs="?")
    a.set_defaults(func=cmd_theme)
    a = sub.add_parser("config", help="get / set settings, e.g. desktop.style vinyl")
    a.add_argument("action", choices=("get", "set", "path"))
    a.add_argument("key", nargs="?")
    a.add_argument("value", nargs="?")
    a.set_defaults(func=cmd_config)

    a = sub.add_parser("export", help="share the library with cliamp")
    a.add_argument("target", choices=("cliamp",))
    a.add_argument("--lang")
    a.set_defaults(func=cmd_export)
    a = sub.add_parser("watch", help="watch the video in Brave (ad-free with Shields); other sites open at the song's page")
    a.add_argument("target", nargs="?")
    a.set_defaults(func=cmd_watch)
    a = sub.add_parser("open", help="open the Paattu window")
    a.add_argument("view", nargs="?")
    a.set_defaults(func=cmd_open)
    return p


def main(argv=None):
    args = build_parser().parse_args(argv)
    out = Reporter(args.json)
    if args.command == "config" and args.action == "set" and (args.key is None or args.value is None):
        out.error("usage: paattu config set KEY VALUE")
        return 2
    try:
        args.func(args, out)
    except (YouTubeError, EngineError, SourceError, ValueError, KeyError) as e:
        out.error(str(e).strip("'"))
        return 1
    except KeyboardInterrupt:
        return 130
    return 0
