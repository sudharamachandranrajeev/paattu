"""paattu — Malayalam & Tamil music from YouTube playlists, JioSaavn and any link, built into Omarchy."""

import argparse
import concurrent.futures
import contextlib
import getpass
import json
import os
import random
import re
import shutil
import subprocess
import sys
import time

from . import (__version__, art, browse, charts, cliamp, config, depth, engine, history, library, listenbrainz, lyrics,
               made, offline, paths, radio, rhythm, seeds, sound, sources, titles, update, youtube)
from .depth import DepthError
from .listenbrainz import ListenBrainzError
from .offline import OfflineError
from .update import UpdateError
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


def _sleep_text(sleep):
    if sleep.get("mode") == "end":
        return "Sleep: at the end of this song"
    if sleep.get("mode") == "time":
        left = max(0, int(sleep.get("at", 0) - time.time()))
        return "Sleep in %s" % _fmt_duration(left) if left else "Sleep: now"
    return "Sleep timer off"


def cmd_sleep(args, out):
    value = args.value
    if value is not None and value not in ("end", "off") and not re.fullmatch(r"\+?[0-9]+", value):
        raise ValueError("sleep takes minutes (30), more minutes (+5), end or off")
    with engine.Engine(autostart=False) as e:
        if value is not None:
            e.send(["script-message", "paattu-sleep", value])
        sleep = e.get("user-data/paattu/sleep") or {}
    out.data({"sleep": sleep}, _sleep_text(sleep))


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



# ---------------------------------------------------------------- radio, history, made for you

def _station(e):
    """The song the radio plays songs like, or None when it's off."""
    station = e.get("user-data/paattu/radio") or {}
    return station if isinstance(station, dict) and station.get("id") else None


def _entry_track(data, entry):
    tid = sources.track_id(entry.get("filename", "")) or ""
    return _known(data, tid) or {"id": tid, "title": entry.get("title", "")}


def _songs_left(e):
    return e.get("playlist-count", 0) - e.get("playlist-pos", -1) - 1


def _extend_radio(e, data, station, out, count=10):
    """Queue up to count more songs like station when two or fewer are left
    (the engine's script and a click can both ask). Returns how many songs
    are left after the one playing."""
    with radio.session() as state:
        if _songs_left(e) > 2:
            return _songs_left(e)
        queue = [_entry_track(data, entry) for entry in e.get("playlist") or []]
        with history.editing() as h:  # only read, but not while it's half written
            songs = radio.SongRadio(h, state).next(station, queue, count)
        if songs:
            sources.remember(songs)
            engine.enqueue(e, songs)
            state["added"] = (state.get("added") or []) + [sources.track_url(s) for s in songs]
    if songs:
        _spawn_art([s["id"] for s in songs[:8]])
    return _songs_left(e)


def cmd_radio(args, out):
    data = library.load()
    if args.action == "start":
        track = _songs(data, [args.target] if args.target else [], out)[0]
        _check_firewall()
        with engine.Engine() as e:
            playing = sources.track_id(e.get("path") or "") == track["id"] and not e.get("idle-active", True)
            if playing:
                e.send(["playlist-clear"])  # everything but the song playing
            else:
                engine.load(e, [track], source={"type": "radio", "id": track["id"], "title": "Radio"})
            e.set("user-data/paattu/radio", history.stored_track(track))
            e.set("user-data/paattu/radio-stopped", False)
            out.progress("Finding songs like %s…" % (track.get("title") or track["id"]))
            left = _extend_radio(e, data, track, out)
        if not left:
            raise SourceError("couldn't find songs like %s. Check the internet connection" % (track.get("title") or track["id"]))
        out.done("Radio: songs like %s" % (track.get("title") or track["id"]), count=left)
    elif args.action == "stop":
        with engine.Engine(autostart=False) as e:
            e.set("user-data/paattu/radio", {})
            e.set("user-data/paattu/radio-stopped", True)
            with radio.session() as state:
                added = set(state.pop("added", None) or [])
            entries = e.get("playlist") or []
            pos = e.get("playlist-pos", -1)
            # The radio's songs still to come go; ones it played stay.
            drop = [i for i, entry in enumerate(entries) if i > pos and entry.get("filename") in added]
            for index in reversed(drop):
                e.send(["playlist-remove", index])
        out.done("Radio off", removed=len(drop))
    elif args.action == "more":
        # Asked by the engine's script as the queue runs low.
        if not engine.running():
            out.done()
            return
        with engine.Engine(autostart=False) as e:
            if engine.repeat_mode(e) != "off" or _songs_left(e) > 2:
                out.done()
                return
            station = _station(e)
            if not station:
                if not config.load().get("autoRadio", True) or e.get("user-data/paattu/radio-stopped", False):
                    out.done()
                    return
                station = _playing_track(data, out)
                if not station:
                    out.done()
                    return
                e.set("user-data/paattu/radio", history.stored_track(station))
            left = _extend_radio(e, data, station, out)
        out.done("Radio: %s to come" % _plural(left, "song"), count=left)
    else:
        with engine.Engine(autostart=False) as e:
            station = _station(e) if engine.running() else None
        out.data({"radio": station}, "Radio: songs like %s" % station.get("title") if station else "Radio off")


def cmd_played(args, out):
    """Note a play in the history (the engine's script calls this as each song ends)."""
    data = library.load()
    tid = sources.track_id(args.url) or ""
    if not tid:
        out.done()
        return
    track = _known(data, tid)
    if not track:
        song, _, movie = (args.title or "").partition(" · ")
        track = {"id": tid, "title": song or tid, "movie": movie, "credits": [], "kind": "song"}
        if not sources.is_youtube(args.url):
            track.update(url=args.url, site=sources.site_of(args.url))
    with history.editing() as h:
        h.played(track, args.heard, length=args.length or None)
    # A song played to the end joins its language's played playlist and is
    # kept on this computer; one played from here counts as used.
    play = {"heard": args.heard, "length": args.length or track.get("duration") or 0}
    if history.fully_played(play):
        with library.edit() as data:
            library.note_played(data, track)
        if offline.settings()["autoSave"] and not offline.file_of(track):
            offline.keep_soon(track)
    if history.counted(play):
        offline.note_played(track)
    # Sent to ListenBrainz, and the other devices' plays read back.
    if listenbrainz.account():
        try:
            _listenbrainz_sync()
        except ListenBrainzError as e:
            print("paattu: " + str(e), file=sys.stderr)
    out.done()


def _listenbrainz_sync():
    """Sync with ListenBrainz; the songs other devices played join the mixes
    like the ones played here. Returns how many plays came in."""
    found = listenbrainz.account()
    added = listenbrainz.sync(found["token"], found["user"])
    heard = [song for play, song in added if history.fully_played(play)]
    if heard:
        with library.edit() as data:
            for song in heard:
                library.note_played(data, song)
    return len(added)


def cmd_listenbrainz(args, out):
    """Scrobbling to ListenBrainz, which carries plays between devices."""
    found = listenbrainz.account()
    if args.action == "login":
        # From the environment (the shell's Settings) or asked for, so it
        # stays out of the shell history and the process list.
        token = os.environ.get("PAATTU_LISTENBRAINZ_TOKEN", "").strip()
        if not token:
            token = getpass.getpass("ListenBrainz user token (listenbrainz.org/settings): ").strip()
        if not token:
            raise ValueError("no token given")
        out.progress("Checking the token…")
        user = listenbrainz.user_of(token)
        listenbrainz.save_account(token, user)
        out.progress("Sending your plays…")
        added = _listenbrainz_sync()
        out.done("Scrobbling to ListenBrainz as %s; %d plays from other devices came in" % (user, added), user=user,
                 added=added)
    elif args.action == "logout":
        listenbrainz.forget_account()
        out.done("Not scrobbling any more (your listens stay on ListenBrainz)")
    elif args.action == "sync":
        if not found:
            raise ValueError("not connected to ListenBrainz: paattu listenbrainz login")
        added = _listenbrainz_sync()
        out.done("%d plays from other devices came in" % added, user=found["user"], added=added)
    else:
        synced = history.History.load().data.get("listenbrainz") or {}
        fields = {"user": found["user"] if found else "", "synced": synced.get("synced") or 0}
        if args.json:
            out.data(fields)
        elif found:
            when = time.strftime("%Y-%m-%d %H:%M", time.localtime(fields["synced"])) if fields["synced"] else "never"
            print("Scrobbling to ListenBrainz as %s (last synced %s)" % (found["user"], when))
        else:
            print("Not connected to ListenBrainz (paattu listenbrainz login)")


def _made_summary(h, kind, today):
    key = made.period_key(kind, today)
    songs = made.kept_made(h.made(kind), key) or []
    return {"kind": kind, "title": made.TITLES[kind], "blurb": made.BLURBS[kind], "key": key,
            "count": len(songs), "art": next((s.get("art") for s in songs if s.get("art")), "")}


def _play_made(songs, source, out):
    _check_firewall()
    with engine.Engine() as e:
        engine.load(e, songs, source=source)
    _spawn_art([t["id"] for t in songs[:8]])


def cmd_made(args, out):
    import datetime
    if not args.kind:
        h = history.History.load()
        rows = [_made_summary(h, kind, datetime.date.today()) for kind in made.KINDS]
        out.data(rows, "\n".join("%-17s %s" % (r["title"], _plural(r["count"], "song") if r["count"] else "made when you open it")
                                 for r in rows))
        return
    data = library.load()
    out.progress("Making your %s…" % made.TITLES[args.kind])
    with history.editing() as h:
        songs = made.MadeForYou(h, data).playlist(args.kind, refresh=args.refresh)
    key = made.period_key(args.kind, datetime.date.today())
    sources.remember(songs)
    title = "%s %s" % (made.TITLES[args.kind], key)
    if args.play:
        _play_made(songs, {"type": "made", "id": args.kind, "title": made.TITLES[args.kind]}, out)
    if out.as_json:
        out.data({"event": "done", "ok": True, "kind": args.kind, "key": key, "title": made.TITLES[args.kind],
                  "name": title, "blurb": made.BLURBS[args.kind], "tracks": songs})
        return
    print("%s: %s" % (title, made.BLURBS[args.kind]))
    for n, t in enumerate(songs, 1):
        print(_result_line(n, t))


def _chart_summary(kind, language):
    entry = charts.kept(kind, language) or {}
    songs = entry.get("tracks") or []
    return {"kind": kind, "language": language, "title": "%s · %s" % (charts.TITLES[kind], language),
            "blurb": charts.BLURBS[kind] % language, "count": len(songs),
            "art": entry.get("art") or next((s.get("art") for s in songs if s.get("art")), "")}


def cmd_charts(args, out):
    """What's played most this week, by language (paattu/charts.py)."""
    languages = charts.languages(config.load().get("languages"))
    if not args.kind:
        rows = [_chart_summary(kind, lang) for lang in languages for kind in charts.KINDS]
        out.data(rows, "\n".join("%-34s %s" % (r["title"], _plural(r["count"], "song") if r["count"] else "fetched when you open it")
                                 for r in rows))
        return
    language = (args.language or languages[0]).title()
    if language not in charts.LANGUAGES:
        raise ValueError("no charts for %s (there are %s)" % (language, ", ".join(charts.LANGUAGES)))
    out.progress("Getting the %s chart…" % language)
    songs = charts.chart(args.kind, language, history.History.load(), refresh=args.refresh)
    sources.remember(songs)
    summary = _chart_summary(args.kind, language)
    if args.play:
        _play_made(songs, {"type": "chart", "id": charts.key(args.kind, language), "title": summary["title"]}, out)
    if out.as_json:
        out.data({"event": "done", "ok": True, **summary, "count": len(songs), "tracks": songs})
        return
    print("%s: %s" % (summary["title"], summary["blurb"]))
    for n, t in enumerate(songs, 1):
        print(_result_line(n, t))


def cmd_describe(args, out):
    text = " ".join(args.text)
    out.progress("Finding songs for %s…" % text)
    songs = made.describe_playlist(text)
    sources.remember(songs)
    if args.save:
        with library.edit() as data:
            playlist = library.create_playlist(data, args.save)
            library.add_tracks(data, playlist["id"], songs)
    if args.play:
        _play_made(songs, {"type": "describe", "id": "", "title": text}, out)
    if out.as_json:
        out.data({"event": "done", "ok": True, "title": text, "tracks": songs})
        return
    for n, t in enumerate(songs, 1):
        print(_result_line(n, t))


def cmd_failover(args, out):
    """The same song on another site, for a stream that won't play (the
    engine's script asks; it plays what this prints)."""
    data = library.load()
    tid = sources.track_id(args.url) or ""
    track = _known(data, tid)
    if not track:
        song, _, movie = (args.title or "").partition(" · ")
        track = {"id": tid, "title": song, "movie": movie, "url": args.url, "site": sources.site_of(args.url)}
    if not offline.reachable():
        _play_kept_instead(track, out)
        return
    found = sources.alternates_for(track)
    if not found:
        raise SourceError("no other site has %s" % (track.get("title") or "that song"))
    sources.remember(found)
    best = found[0]
    out.data({"event": "done", "ok": True, "url": sources.track_url(best), "title": engine.display_title(best),
              "site": sources.track_site(best)},
             sources.track_url(best))


def _play_kept_instead(track, out):
    """No internet: the songs kept on this computer, shuffled, for the engine's
    script to play after the one that wouldn't."""
    kept = [t for t in offline.tracks(shuffled=True) if offline.key(t) != offline.key(track)]
    if not kept:
        raise SourceError("there's no internet, and no songs are kept on this computer")
    message = "No internet: playing the %s kept on this computer" % _plural(len(kept), "song")
    if shutil.which("notify-send"):
        subprocess.Popen(["notify-send", "-a", "Paattu", "Paattu", message], stdin=subprocess.DEVNULL,
                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
    first, rest = kept[0], kept[1:]
    out.data({"event": "done", "ok": True, "offline": True, "message": message, "url": sources.track_url(first),
              "title": engine.display_title(first),
              "more": [{"url": sources.track_url(t), "title": engine.display_title(t)} for t in rest]},
             message)


def _offline_row(entry):
    track = entry.get("track") or {}
    return {"key": entry["key"], "id": track.get("id", ""), "title": track.get("title") or entry["file"],
            "file": entry["file"], "bytes": entry.get("bytes") or 0, "saved": entry.get("saved") or "",
            "plays": entry.get("plays") or 0, "codec": entry.get("codec") or "", "kbps": entry.get("kbps"),
            "track": track}


def cmd_offline(args, out):
    """Songs kept on this computer, to play with no internet (paattu/offline.py)."""
    if args.action == "keep":
        if not args.target:
            raise ValueError("usage: paattu offline keep SONG (a link or id, or current)")
        data = library.load()
        if args.target == "current":
            track = _playing_track(data, out)
            if not track:
                raise EngineError("nothing is playing")
        else:
            tid = sources.track_id(args.target) or args.target
            track = _known(data, tid)
            if not track:
                song, _, movie = (args.title or "").partition(" · ")
                track = {"id": tid, "title": song or tid, "movie": movie, "credits": [], "kind": "song"}
                if sources.is_link(args.target) and not sources.is_youtube(args.target):
                    track.update(url=args.target, site=sources.site_of(args.target))
        if not args.quiet:
            out.progress("Keeping %s…" % (track.get("title") or track["id"]))
        entry = offline.keep(track)
        if not args.quiet:
            out.done("%s is on this computer" % (track.get("title") or track["id"]), song=_offline_row(
                {**entry, "key": offline.key(track)}))
        return
    if args.action == "drop":
        if not args.target:
            raise ValueError("usage: paattu offline drop SONG (its key, link or id)")
        kept = offline.read()
        k = args.target if args.target in kept else next(
            (key for key, e in kept.items() if (e.get("track") or {}).get("id") == (sources.track_id(args.target) or args.target)),
            None)
        entry = offline.remove(k) if k else None
        if not entry:
            raise ValueError("%s isn't kept on this computer" % args.target)
        out.done("Took %s off this computer" % ((entry.get("track") or {}).get("title") or entry["file"]))
        return
    if args.action == "clear":
        gone = [offline.remove(e["key"]) for e in offline.songs()]
        out.done("Took %s off this computer" % _plural(len(gone), "song"))
        return
    if args.action == "play":
        tracks = offline.tracks(shuffled=args.shuffle and not args.start)
        if not tracks:
            raise EngineError("no songs are kept on this computer yet")
        with engine.Engine() as e:
            engine.load(e, tracks, start=args.start, shuffle=args.shuffle and args.start > 0,
                        source={"type": "offline", "id": "offline", "title": "On this computer"})
        out.done("Playing the %s kept on this computer" % _plural(len(tracks), "song"), count=len(tracks))
        return
    conf = config.load()
    rows = [_offline_row(e) for e in offline.songs()]
    total = sum(r["bytes"] for r in rows)
    status = {**offline.settings(conf), "folder": str(offline.folder(conf)), "count": len(rows), "bytes": total}
    out.data({"event": "done", "ok": True, **status, "songs": rows},
             "%s kept, %s, in %s%s" % (_plural(len(rows), "song"), _megabytes(total), status["folder"],
                                       "".join("\n  " + r["title"] + "  (" + r["file"] + ")" for r in rows)))


def cmd_update(args, out):
    """A newer Paattu: whether there is one, and installing it."""
    if args.action == "apply":
        out.progress("Updating Paattu…")
        version = update.apply(lambda message: out.progress(message))
        out.done("Paattu %s is installed. Restart the shell to load the new window: omarchy restart shell" % version,
                 version=version)
        return
    found = update.check()
    text = ("Paattu %s is out (this is %s)%s" % (found["latest"], found["current"],
                                                  "\n\n" + found["notes"] if found["notes"] else "")
            if found["available"] else "Paattu %s is the newest" % found["current"])
    out.data({"event": "done", "ok": True, **found}, text)


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

def _search_art(tracks, wait=5, collections=()):
    """Cache result covers (songs', and albums', singers' and playlists' from
    browse), giving up on slow ones after about `wait` seconds."""
    jobs = [(art.track_art(t["id"], t), paths.art_path("v", t["id"])) for t in tracks]
    jobs += [(c.get("art"), paths.art_path("c", c["artKey"])) for c in collections if c.get("artKey")]
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


# ---------------------------------------------------------------- browse

def _browse_item(text):
    try:
        item = json.loads(text)
    except ValueError:
        item = None
    if not isinstance(item, dict) or item.get("type") not in ("album", "artist", "playlist") or not item.get("site"):
        raise ValueError("give an album, singer or playlist as JSON, as paattu browse search --json prints them")
    return item


def _split(found):
    songs = [t for t in found if (t.get("type") or "song") == "song"]
    return songs, [c for c in found if (c.get("type") or "song") != "song"]


def cmd_browse_search(args, out):
    query = " ".join(args.query).strip()
    if not query or sources.is_link(query):
        raise ValueError("search for words (paattu search looks up links)")
    cfg = config.load()["search"]
    sites = args.site or [s for s in cfg.get("sites") or sources.SEARCH_SITES if s in sources.SEARCH_SITES]
    cursors = json.loads(args.after) if args.after else None
    if not args.json:
        out.progress("Searching %s…" % ", ".join(sources.site_name(s) for s in sites if s in browse.KIND_SITES[args.kind]))
    found, following, errors = browse.search(query, args.kind, sites, cursors)
    songs, collections = _split(found)
    sources.remember(songs)
    if args.json:
        _search_art(songs, collections=collections)
        # Each with its key, so the app can drop repeats from later pages.
        results = [dict(item, key=browse.result_key(item)) for item in found]
        out.done("", query=query, kind=args.kind, results=results, next=following, errors=errors)
        return
    for n, item in enumerate(found, 1):
        if item in songs:
            print(_result_line(n, item))
        else:
            print("%3d. %-34s %-30s %s" % (n, item["title"][:34], (item.get("subtitle") or "")[:30],
                                           sources.site_name(item["site"])))
    for site, message in errors.items():
        print("\n%s: %s" % (sources.site_name(site), message), file=sys.stderr)
    if following:
        print("\nMore: paattu browse search --kind %s --after '%s' -- %s" % (args.kind, json.dumps(following), query))
    if not found:
        print("Nothing found for %s" % query)


def cmd_browse_suggest(args, out):
    query = " ".join(args.query).strip()
    found = browse.suggest(query)
    if args.json:
        out.done("", query=query, suggestions=found)
        return
    for item in found:
        print("%-9s %s%s" % (item["type"], item["title"], "  ·  " + item["subtitle"] if item.get("subtitle") else ""))


def cmd_browse_open(args, out):
    item = _browse_item(args.item)
    if not args.json:
        out.progress("Opening %s…" % (item.get("title") or "it"))
    if item["type"] == "artist":
        page = browse.artist(item, args.page)
    else:
        page = {"songs": browse.collection_songs(item)}
    songs = page["songs"]
    sources.remember(songs)
    if args.json:
        shelves = page.get("albums", []) + page.get("playlists", []) + page.get("similar", [])
        _search_art(songs[:60], collections=shelves + ([dict(item, art=page["art"])] if page.get("art") else []))
        out.done("", item=item, **page)
        return
    if page.get("name"):
        print("%s  ·  %s" % (page["name"], page.get("about") or sources.site_name(item["site"])))
    for n, t in enumerate(songs, 1):
        print(_result_line(n, t))
    for shelf in ("albums", "playlists", "similar"):
        if page.get(shelf):
            print("\n%s: %s" % (shelf.title(), ", ".join(c["title"] for c in page[shelf][:12])))


def cmd_browse_play(args, out):
    data = library.load()
    tracks = [t for t in (_known(data, tid) for tid in args.ids) if t]
    if not tracks:
        raise SourceError("those songs aren't known: open the album or search again first")
    _check_firewall()
    with engine.Engine() as e:
        engine.load(e, tracks, start=args.index, shuffle=args.shuffle,
                    source={"type": "search", "id": args.source or "", "title": args.title or "Search"})
    first = tracks[max(0, min(args.index, len(tracks) - 1))]  # shuffling still starts there
    _spawn_art([t["id"] for t in tracks[:8]])
    out.done("Playing %s — %s" % (first.get("title") or first["id"], args.title or "Search"),
             track=first["id"], count=len(tracks))


def cmd_video(args, out):
    tid = sources.track_id(args.target)
    track = _known(library.load(), tid) or {"id": tid}
    video = sources.video_for(track)
    if args.json:
        out.done("", video=video)
    else:
        print(video["url"] if video else "No video for that song")


def _song_id(target):
    """A song id as given (the app passes the ids it knows), or a link's."""
    if re.fullmatch(r"[A-Za-z0-9_][A-Za-z0-9._-]{0,199}", target or ""):
        return target
    tid = sources.track_id(target)
    if not tid:
        raise ValueError("not a song: %s" % target)
    return tid


def cmd_depth(args, out):
    tid = _song_id(args.target)
    cover = paths.art_path("v", tid)
    if not cover.exists():
        cache_art_for(library.load(), track_ids=[tid])
    if not cover.exists():
        out.done("No cover for that song", subject=None)
        return
    out.progress("Finding the subject of the cover…")
    found = depth.lift(cover, paths.CACHE / "depth", tid)
    fields = {key: found.get(key) for key in ("subject", "back", "centre", "area")}
    if args.json:
        out.done("", **fields)
    elif found.get("subject"):
        print("Subject: %s\nRest of the cover: %s" % (found["subject"], found["back"]))
    else:
        print("Nothing in that cover stands out to lift")


def cmd_rhythm(args, out):
    """The rhythm of a song (Now Playing's cover moves with it): from its link
    (the engine's path) or id, decoded by mpv, kept in ~/.cache/paattu/rhythm."""
    target = args.target
    tid = sources.track_id(target) if "://" in target else _song_id(target)
    if not tid:
        raise ValueError("not a song: %s" % target)
    if "://" not in target:
        track = _known(library.load(), tid) or {"id": tid}
        target = sources.track_url(track)
    out.progress("Finding the song's rhythm…")
    found = rhythm.find(target, str(paths.CACHE / "rhythm"), re.sub(r"[^A-Za-z0-9_-]", "_", tid))
    if args.json:
        out.done("", id=tid, fps=found["fps"], level=found["level"], punch=found["punch"])
    else:
        print("%s: %d s, %d beats" % (tid, len(found["level"]) // found["fps"], sum(1 for p in found["punch"] if p > 153)))


def cmd_lyrics(args, out):
    """A song's words (the one playing, if none is given), timed where they
    can be, with English letters under each line in an Indian script."""
    data = library.load()
    if args.target:
        tid = sources.track_id(args.target) if "://" in args.target else _song_id(args.target)
        track = dict(_known(data, tid) or {"id": tid})
    else:
        track = dict(_playing_track(data, out) or {})
        if not track:
            raise ValueError("nothing is playing; give a song")
    for key in ("title", "movie"):
        if getattr(args, key):
            track[key] = getattr(args, key)
    if args.duration:
        track["duration"] = args.duration
    settings = config.load()
    language = args.language or track.get("language") or titles.guess_language(
        track.get("rawTitle"), track.get("title"), track.get("movie"), track.get("channel"),
        default=(settings.get("languages") or [""])[0])
    out.progress("Looking for the words…")
    found = lyrics.shown(lyrics.lookup(track, language, refresh=args.refresh),
                         latin=(settings.get("lyrics") or {}).get("transliterate", True))
    if args.json:
        out.done("", id=track.get("id"), **found)
        return
    if not found["found"]:
        print("No words found for %s" % (track.get("title") or track.get("id")))
        return
    for line in found["lines"]:
        stamp = ("%d:%02d" % divmod(int(line["time"]), 60)) + "  " if line["time"] is not None else ""
        print(stamp + line["text"])
        if line["latin"]:
            print(" " * len(stamp) + line["latin"])
    print("\n(%s%s)" % (found["source"], "" if found["synced"] else ", not timed"))


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


def _sound_band(key):
    """A band by number (1-15) or frequency (100, 1k, 1.6k, 16000)."""
    text = key.strip().lower()
    if text.isdigit() and 1 <= int(text) <= len(sound.BANDS):
        return int(text) - 1
    try:
        hz = float(text[:-1]) * 1000 if text.endswith("k") else float(text)
    except ValueError:
        hz = None
    for i, f in enumerate(sound.BANDS):
        if hz is not None and abs(hz - f) <= f * 0.05:
            return i
    raise ValueError("no band %r: say 1-%d or a frequency (%s)" % (
        key, len(sound.BANDS), ", ".join(_hz(f) for f in sound.BANDS)))


def _hz(f):
    return "%gk" % (f / 1000) if f >= 1000 else str(f)


def _find_preset(name, s):
    """A preset's id from its id or name (any case), or a saved preset's name."""
    wanted = name.strip().lower()
    for key, title, _ in sound.PRESETS:
        if wanted in (key, title.lower()):
            return key
    for saved in s["presets"]:
        if saved.lower() == wanted:
            return saved
    raise ValueError("no preset %r; see: paattu sound presets" % name)


def _matching_preset(s):
    for key, _, bands in sound.PRESETS:
        if list(bands) == s["bands"]:
            return key
    return next((name for name, bands in s["presets"].items() if bands == s["bands"]), "")


def _sound_text(s):
    dbs = ["%+.1f" % b if b else "0" for b in s["bands"]]
    applied = sound.gains(s)["pre"]
    lines = [sound.summary(s),
             "  " + " ".join("%5s" % _hz(f) for f in sound.BANDS) + "  Hz",
             "  " + " ".join("%5s" % d for d in dbs) + "  dB"]
    if s["noclip"] and applied != s["preamp"]:
        lines.append("Preamp %s dB plays at %s dB, leaving room for the boosts (paattu sound set --noclip off)"
                     % (sound.fmt(s["preamp"]), sound.fmt(applied)))
    return "\n".join(lines)


def cmd_sound(args, out):
    s = sound.normalize(config.load().get("sound"))
    action, name = args.action, " ".join(args.name).strip()
    if action == "presets":
        rows = [{"id": key, "name": title, "bands": list(bands), "saved": False} for key, title, bands in sound.PRESETS]
        rows += [{"id": n, "name": n, "bands": b, "saved": True} for n, b in s["presets"].items()]
        out.data({"presets": rows}, "\n".join("%-12s %s" % (r["name"], " ".join("%+g" % b if b else "0" for b in r["bands"]))
                                             for r in rows))
        return
    if action in ("preset", "save", "delete") and not name:
        raise ValueError("usage: paattu sound %s NAME" % action)
    if action == "on":
        s["on"] = True
    elif action == "off":
        s["on"] = False
    elif action == "preset":
        key = _find_preset(name, s)
        s.update(bands=sound.preset_bands(key, s), preset=key, on=True)
    elif action == "save":
        if any(name.lower() in (key, title.lower()) for key, title, _ in sound.PRESETS):
            raise ValueError("%r is a built-in preset; pick another name" % name)
        s["presets"][name] = list(s["bands"])
        s["preset"] = name
    elif action == "delete":
        saved = next((n for n in s["presets"] if n.lower() == name.lower()), None)
        if saved is None:
            raise ValueError("no saved preset %r" % name)
        del s["presets"][saved]
        if s["preset"] == saved:
            s["preset"] = ""
    elif action == "reset":
        s = sound.normalize({"on": s["on"], "presets": s["presets"]})
    elif action == "set":
        if args.bands is not None:
            values = [config.parse_value(v) for v in args.bands.replace(",", " ").split()]
            if len(values) != len(sound.BANDS) or not all(isinstance(v, (int, float)) for v in values):
                raise ValueError("--bands takes %d numbers (dB)" % len(sound.BANDS))
            s["bands"] = values
        for item in args.band or []:
            key, _, value = item.partition("=")
            try:
                s["bands"][_sound_band(key)] = float(value)
            except ValueError:
                raise ValueError("--band takes BAND=DB, e.g. 1k=+2.5")
        for key in ("preamp", "bass", "treble", "balance", "speed"):
            if getattr(args, key) is not None:
                s[key] = getattr(args, key)
        if args.noclip is not None:
            s["noclip"] = args.noclip == "on"
        if args.bands is not None or args.band:
            s = sound.normalize(s)
            s["preset"] = _matching_preset(s)
    if action != "show":
        s = sound.normalize(s)
        config.set_key("sound", s)
    if engine.running():
        with engine.Engine(autostart=False) as e:
            sound.apply(e, s)
    out.done(_sound_text(s), sound=s, summary=sound.summary(s), gains=sound.gains(s), graph=sound.graph(s))


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

    browsing = sub.add_parser("browse", help="albums, singers and playlists: search a page at a time, suggestions, "
                                             "open one, play its songs").add_subparsers(dest="action", required=True)
    a = browsing.add_parser("search", help="one page of songs, albums, singers (artist) or playlists from each site")
    a.add_argument("query", nargs="+")
    a.add_argument("--kind", default="song", choices=browse.KINDS)
    a.add_argument("--site", action="append", choices=sources.SEARCH_SITES, help="only this site (repeatable)")
    a.add_argument("--after", help="the next page: the JSON 'next' of the page before")
    a.set_defaults(func=cmd_browse_search)
    a = browsing.add_parser("suggest", help="suggestions for a few typed letters")
    a.add_argument("query", nargs="+")
    a.set_defaults(func=cmd_browse_suggest)
    a = browsing.add_parser("open", help="the songs of an album or playlist, or a singer's page (JSON from search)")
    a.add_argument("item")
    a.add_argument("--page", type=int, default=1, help="a singer's next page of songs")
    a.set_defaults(func=cmd_browse_open)
    a = browsing.add_parser("play", help="play songs found by browse (ids, in order)")
    a.add_argument("ids", nargs="+")
    a.add_argument("--index", type=int, default=0, help="start at this one (from 0)")
    a.add_argument("--shuffle", action="store_true")
    a.add_argument("--title", help="what they're from, for the player")
    a.add_argument("--source", help="the album's or playlist's id")
    a.set_defaults(func=cmd_browse_play)

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
    a = sub.add_parser("sleep", help="sleep timer: 30 (minutes), +5 (more), end (of this song), off; status when left out")
    a.add_argument("value", nargs="?")
    a.set_defaults(func=cmd_sleep)
    sub.add_parser("queue", help="the play queue").set_defaults(func=cmd_queue)
    a = sub.add_parser("jump", help="play queue entry N")
    a.add_argument("index", type=int)
    a.set_defaults(func=cmd_jump)

    a = sub.add_parser("radio", help="songs like a song, without end: start [song] | stop | more | status")
    a.add_argument("action", nargs="?", default="status", choices=("start", "stop", "more", "status"))
    a.add_argument("target", nargs="?", help="the song (a link or id); the one playing when left out")
    a.set_defaults(func=cmd_radio)
    a = sub.add_parser("played", help="note a play in the history (the engine does this)")
    a.add_argument("url")
    a.add_argument("heard", type=int, help="seconds listened")
    a.add_argument("--length", type=int, help="the song's length in seconds")
    a.add_argument("--title", help="what the engine called it")
    a.set_defaults(func=cmd_played)
    a = sub.add_parser("listenbrainz", help="scrobble to ListenBrainz, which carries plays between devices: "
                                            "login | logout | sync | status")
    a.add_argument("action", nargs="?", default="status", choices=("login", "logout", "sync", "status"))
    a.set_defaults(func=cmd_listenbrainz)
    a = sub.add_parser("made", help="playlists made for you: daily, weekly or monthly (none: what's there)")
    a.add_argument("kind", nargs="?", choices=made.KINDS)
    a.add_argument("--refresh", action="store_true", help="make a new one now")
    a.add_argument("--play", action="store_true")
    a.set_defaults(func=cmd_made)
    a = sub.add_parser("charts", help="what's played most this week, by language (none: what's there)")
    a.add_argument("kind", nargs="?", choices=charts.KINDS)
    a.add_argument("language", nargs="?", help="Malayalam, Tamil, Hindi, Telugu, Kannada or Punjabi")
    a.add_argument("--refresh", action="store_true", help="fetch it again now")
    a.add_argument("--play", action="store_true")
    a.set_defaults(func=cmd_charts)
    a = sub.add_parser("offline", help="songs kept on this computer, to play with no internet: "
                                       "list | keep SONG | drop SONG | play | clear")
    a.add_argument("action", nargs="?", default="list", choices=("list", "keep", "drop", "play", "clear"))
    a.add_argument("target", nargs="?", help="the song: a link or id (current: the one playing)")
    a.add_argument("--title", help="what the engine called it")
    a.add_argument("--shuffle", action="store_true")
    a.add_argument("--start", type=int, default=0, help="play: the song to start at (0 is the newest)")
    a.add_argument("--quiet", action="store_true", help="say nothing (the engine keeps songs this way)")
    a.set_defaults(func=cmd_offline)
    a = sub.add_parser("update", help="a newer Paattu: check | apply")
    a.add_argument("action", nargs="?", default="check", choices=("check", "apply"))
    a.set_defaults(func=cmd_update)
    a = sub.add_parser("describe", help='a playlist from a description: "Ilaiyaraaja melodies, rain songs, Premam"')
    a.add_argument("text", nargs="+")
    a.add_argument("--play", action="store_true")
    a.add_argument("--save", metavar="NAME", help="keep it as a playlist of yours")
    a.set_defaults(func=cmd_describe)
    a = sub.add_parser("failover", help="the same song on another site, for a link that won't play")
    a.add_argument("url")
    a.add_argument("--title", help="what the engine called it")
    a.set_defaults(func=cmd_failover)

    a = sub.add_parser("video", help="where to stream a song's video, small and silent (for a background)")
    a.add_argument("target", help="the song: a link or id")
    a.set_defaults(func=cmd_video)

    a = sub.add_parser("depth", help="lift a song's cover's subject out of it (the cover in 3D in Now Playing)")
    a.add_argument("target", help="the song: an id or a link")
    a.set_defaults(func=cmd_depth)

    a = sub.add_parser("lyrics", help="a song's words, timed, with English letters under them (none: the one playing)")
    a.add_argument("target", nargs="?", help="the song: an id or a link")
    a.add_argument("--title", help="what the song is called, if Paattu doesn't know it")
    a.add_argument("--movie", help="the film or album it's from")
    a.add_argument("--duration", type=int, help="its length in seconds")
    a.add_argument("--language", help="the language it's in (Malayalam, Tamil, Hindi, Telugu, Kannada)")
    a.add_argument("--refresh", action="store_true", help="look again, not in what was kept")
    a.set_defaults(func=cmd_lyrics)

    a = sub.add_parser("rhythm", help="a song's loudness and beats (Now Playing's cover moves with them)")
    a.add_argument("target", help="the song: an id or a link")
    a.set_defaults(func=cmd_rhythm)

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

    a = sub.add_parser("sound", help="equaliser, preamp, bass, treble, balance and speed")
    a.add_argument("action", nargs="?", default="show",
                   choices=("show", "on", "off", "preset", "presets", "set", "save", "delete", "reset"))
    a.add_argument("name", nargs="*", help="a preset (preset, save, delete)")
    a.add_argument("--bands", help="all fifteen bands in dB, 25 Hz to 16 kHz, e.g. --bands=0,0,-1,-1,0,1,2,3,4,4,3,3,1,0,0")
    a.add_argument("--band", action="append", metavar="BAND=DB", help="one band by number (1-15) or Hz (1.6k), e.g. 1k=+2")
    a.add_argument("--preamp", type=float, metavar="DB")
    a.add_argument("--bass", type=float, metavar="DB")
    a.add_argument("--treble", type=float, metavar="DB")
    a.add_argument("--balance", type=float, metavar="-1..1")
    a.add_argument("--speed", type=float, metavar="0.5..2")
    a.add_argument("--noclip", choices=("on", "off"), help="lower the preamp by the biggest boost (default on)")
    a.set_defaults(func=cmd_sound)

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
    except (YouTubeError, EngineError, SourceError, DepthError, ListenBrainzError, OfflineError, UpdateError,
            ValueError, KeyError) as e:
        out.error(str(e).strip("'"))
        return 1
    except KeyboardInterrupt:
        return 130
    return 0
