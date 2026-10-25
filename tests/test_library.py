import copy
import json
import os
import pathlib
import shutil
import subprocess
import sys
import tempfile
import time
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from paattu import art, cli, cliamp, config, engine, library, paths, seeds, youtube  # noqa: E402

CHANNEL = {
    "id": "UCoRF8GByEjmM_yHwUGIDGyQ", "handle": "@saregamamalayalam", "name": "Saregama Malayalam",
    "url": "https://www.youtube.com/@saregamamalayalam", "followers": 2650000, "avatar": "",
    "playlists": [
        {"id": "PLGSaQXigBvdM", "title": "Hits of Sushin Shyam | Saregama Malayalam", "thumbnail": "t1"},
        {"id": "PLV1bF0JcivaesjK7MqHB9Ogl_uTQmwoYP", "title": "Karam - Official Playlist | Vineeth Sreenivasan", "thumbnail": "t2"},
        {"id": "PLtrailers0001", "title": "Movie Trailers | Saregama Malayalam", "thumbnail": "t3"},
        {"id": "PLtamil00000001", "title": "Evergreen Tamil Melodies", "thumbnail": "t4"},
    ],
}
DETAILS = {
    "id": "PLGSaQXigBvdM", "title": "Hits of Sushin Shyam | Saregama Malayalam", "channel": "Saregama Malayalam",
    "channelId": "UCoRF8GByEjmM_yHwUGIDGyQ", "thumbnail": "",
    "tracks": [
        {"id": "hvqnG6VjqV0", "title": "Thalatherichavar - Video | Romancham | Sushin Shyam | Saregama Malayalam", "duration": 276},
        {"id": "OkvkSXKcLBM", "title": "Athmave Poo - Lyrical | Romancham | Sushin Shyam | Saregama Malayalam", "duration": 225},
        {"id": "eysNkSGQH_I", "title": "Athmave Poo - Video Song | Romancham | Sushin Shyam | Saregama Malayalam", "duration": 225},
        {"id": "trailer0001", "title": "Romancham - Official Trailer | Saregama Malayalam", "duration": 120},
    ],
}


class TempDirs(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        root = pathlib.Path(self.tmp.name)
        self.saved = {name: getattr(paths, name) for name in
                      ("DATA", "LIBRARY", "SHELF", "CONFIG", "CONFIG_FILE", "THEMES", "CLIAMP_PLAYLISTS", "ART")}
        paths.DATA = root / "data"
        paths.ART = root / "art"
        paths.LIBRARY = paths.DATA / "library.json"
        paths.SHELF = paths.DATA / "shelf.json"
        paths.CONFIG = root / "config"
        paths.CONFIG_FILE = paths.CONFIG / "config.json"
        paths.THEMES = paths.CONFIG / "themes"
        paths.CLIAMP_PLAYLISTS = root / "cliamp"

    def tearDown(self):
        for name, value in self.saved.items():
            setattr(paths, name, value)
        self.tmp.cleanup()


class LibraryTest(TempDirs):
    def test_user_playlists_and_tracks(self):
        with library.edit() as data:
            user = library.upsert_user(data, CHANNEL, "Malayalam")
            library.set_playlist_tracks(data, DETAILS)
        data = library.load()
        self.assertEqual(user["playlists"][0], "PLGSaQXigBvdM")
        hits = data["playlists"]["PLGSaQXigBvdM"]
        self.assertEqual(hits["title"], "Hits of Sushin Shyam")
        self.assertEqual(hits["language"], "Malayalam")
        self.assertEqual(hits["count"], 4)
        self.assertEqual(data["playlists"]["PLV1bF0JcivaesjK7MqHB9Ogl_uTQmwoYP"]["title"], "Karam")
        library.upsert_playlist_stub(data, {"id": "UULPoRF8GByEjmM_yHwUGIDGyQ", "title": "Popular uploads", "auto": True},
                                     owner=data["users"][CHANNEL["id"]])
        self.assertEqual(data["playlists"]["UULPoRF8GByEjmM_yHwUGIDGyQ"]["title"], "Saregama Malayalam — Most played")
        self.assertEqual(data["playlists"]["PLtamil00000001"]["language"], "Tamil")
        self.assertIsNone(data["playlists"]["PLtrailers0001"]["tracks"])
        self.assertEqual(data["tracks"]["hvqnG6VjqV0"]["movie"], "Romancham")
        self.assertIs(library.find_user(data, "@saregamamalayalam"), data["users"][CHANNEL["id"]])
        self.assertIs(library.find_user(data, "saregamamalayalam"), data["users"][CHANNEL["id"]])
        self.assertTrue(paths.SHELF.is_relative_to(pathlib.Path(self.tmp.name)))

    def test_shelf_lists_saved_playlists_by_language(self):
        with library.edit() as data:
            library.upsert_user(data, CHANNEL, "Malayalam")
            library.set_playlist_tracks(data, DETAILS)["saved"] = True
        import json
        shelf = json.loads(paths.SHELF.read_text())
        self.assertEqual([p["id"] for p in shelf["languages"]["Malayalam"]], ["PLGSaQXigBvdM"])
        self.assertEqual(shelf["languages"]["Malayalam"][0]["ownerName"], "Saregama Malayalam")
        self.assertEqual(shelf["counts"], {"users": 1, "tracks": 4, "saved": 1})

    def test_remove_user_keeps_saved(self):
        with library.edit() as data:
            library.upsert_user(data, CHANNEL, "Malayalam")
            library.set_playlist_tracks(data, DETAILS)["saved"] = True
        with library.edit() as data:
            library.remove_user(data, CHANNEL["id"])
        data = library.load()
        self.assertEqual(list(data["playlists"]), ["PLGSaQXigBvdM"])
        self.assertEqual(len(data["tracks"]), 4)

    def test_queue_skips_trailers_and_duplicate_uploads(self):
        with library.edit() as data:
            library.set_playlist_tracks(data, DETAILS)
        tracks = engine.queue_tracks(library.playlist_tracks(library.load(), "PLGSaQXigBvdM"))
        self.assertEqual([t["id"] for t in tracks], ["hvqnG6VjqV0", "OkvkSXKcLBM"])

    def test_cliamp_export(self):
        with library.edit() as data:
            library.upsert_user(data, CHANNEL, "Malayalam")
            library.set_playlist_tracks(data, DETAILS)["saved"] = True
        names = cliamp.export(library.load())
        self.assertEqual(names, ["Paattu - Malayalam - Hits of Sushin Shyam.toml"])
        text = (paths.CLIAMP_PLAYLISTS / names[0]).read_text()
        self.assertIn('path = "https://www.youtube.com/watch?v=hvqnG6VjqV0"', text)
        self.assertIn('title = "Thalatherichavar"', text)
        self.assertIn('album = "Romancham"', text)
        self.assertIn("duration_secs = 276", text)


    def test_removed_playlist_stays_out_after_sync(self):
        with library.edit() as data:
            library.upsert_user(data, CHANNEL, "Malayalam")
            library.set_playlist_tracks(data, DETAILS)["saved"] = True
        with library.edit() as data:
            library.remove_playlist(data, "PLGSaQXigBvdM")
        data = library.load()
        self.assertNotIn("PLGSaQXigBvdM", data["playlists"])
        self.assertNotIn("PLGSaQXigBvdM", data["users"][CHANNEL["id"]]["playlists"])
        self.assertEqual(data["tracks"], {})
        with library.edit() as data:  # sync with YouTube, which still lists it
            library.upsert_user(data, CHANNEL, "Malayalam")
        data = library.load()
        self.assertNotIn("PLGSaQXigBvdM", data["playlists"])
        self.assertEqual(len(data["users"][CHANNEL["id"]]["playlists"]), 3)
        with library.edit() as data:
            self.assertEqual(library.unremove_playlists(data, owner=CHANNEL["id"]), ["PLGSaQXigBvdM"])
            library.upsert_user(data, CHANNEL, "Malayalam")
        self.assertIn("PLGSaQXigBvdM", library.load()["playlists"])

    def test_removed_songs_stay_out_after_refresh(self):
        with library.edit() as data:
            library.set_playlist_tracks(data, DETAILS)
        with library.edit() as data:
            self.assertEqual(library.remove_tracks(data, "PLGSaQXigBvdM", ["OkvkSXKcLBM", "nothere0000"]), ["OkvkSXKcLBM"])
        data = library.load()
        self.assertEqual(data["playlists"]["PLGSaQXigBvdM"]["count"], 3)
        self.assertNotIn("OkvkSXKcLBM", data["tracks"])
        with library.edit() as data:  # refresh from YouTube
            library.set_playlist_tracks(data, DETAILS)
        playlist = library.load()["playlists"]["PLGSaQXigBvdM"]
        self.assertEqual(playlist["tracks"], ["hvqnG6VjqV0", "eysNkSGQH_I", "trailer0001"])


def big_channel(n):
    playlists = [{"id": "PLbig%07d" % i, "title": "Album %d" % i, "thumbnail": ""} for i in range(n)]
    return dict(CHANNEL, playlists=playlists)


class CliTest(TempDirs):
    """CLI commands against a fake YouTube, with no art downloads and no
    player (the real engine may be playing)."""

    def setUp(self):
        super().setUp()
        self.channel = CHANNEL
        self.fetched = []
        self.patches = [(youtube, "channel_playlists", lambda query: self.channel),
                        (youtube, "playlist_details", self.details),
                        (youtube, "video_details", lambda vid: {
                            "id": vid, "title": "Kanmani Anbodu - Lyric Video | Guna | Ilaiyaraaja",
                            "channel": "Pyramid Audio", "duration": 290, "views": 10}),
                        (art, "fetch_many", lambda jobs: 0),
                        (cli, "_spawn_art", lambda ids: None),
                        (engine, "running", lambda: False)]
        self.originals = [(obj, name, getattr(obj, name)) for obj, name, _ in self.patches]
        for obj, name, value in self.patches:
            setattr(obj, name, value)

    def tearDown(self):
        for obj, name, value in self.originals:
            setattr(obj, name, value)
        super().tearDown()

    def details(self, pid):
        self.fetched.append(pid)
        other = {"channelId": "UC" + "o" * 22, "channel": "Someone else"} if pid.startswith("PLother") else {}
        return dict(DETAILS, id=pid, title="Playlist " + pid, **other)

    def run_cli(self, *argv):
        args = cli.build_parser().parse_args(list(argv))
        args.func(args, cli.Reporter(False))


class ImportTest(CliTest):
    def test_profile_link_adds_every_playlist(self):
        self.run_cli("import", "https://www.youtube.com/@saregamamalayalam/playlists", "--lang", "Malayalam")
        data = library.load()
        playlists = data["users"][CHANNEL["id"]]["playlists"]
        self.assertEqual(len(playlists), 4)
        self.assertTrue(all(data["playlists"][pid]["saved"] for pid in playlists))
        self.assertEqual(sorted(self.fetched), sorted(playlists))  # small profile: songs for all of them

    def test_big_profile_fetches_a_few_now(self):
        self.channel = big_channel(cli.FETCH_ALL_UP_TO + 10)
        self.run_cli("import", "@saregamamalayalam")
        data = library.load()
        self.assertEqual(sum(1 for p in data["playlists"].values() if p["saved"]), cli.FETCH_ALL_UP_TO + 10)
        self.assertEqual(len(self.fetched), cli.FETCH_FIRST)
        self.run_cli("user", "fetch", "@saregamamalayalam")
        self.assertEqual(len(self.fetched), cli.FETCH_ALL_UP_TO + 10)

    def test_playlist_link_adds_one_playlist(self):
        self.run_cli("import", "https://www.youtube.com/playlist?list=PLGSaQXigBvdM")
        data = library.load()
        self.assertEqual(list(data["playlists"]), ["PLGSaQXigBvdM"])
        self.assertTrue(data["playlists"]["PLGSaQXigBvdM"]["saved"])

    def test_unfollowing_a_whole_profile_removes_its_playlists(self):
        self.run_cli("import", "@saregamamalayalam")
        self.run_cli("playlist", "add", "https://www.youtube.com/playlist?list=PLother0000001")
        self.run_cli("user", "remove", "@saregamamalayalam")
        self.assertEqual(list(library.load()["playlists"]), ["PLother0000001"])

    def test_remove_and_restore(self):
        self.run_cli("import", "@saregamamalayalam")
        self.run_cli("playlist", "remove", "PLtrailers0001")
        self.run_cli("playlist", "remove-songs", "PLGSaQXigBvdM", "https://youtu.be/OkvkSXKcLBM")
        self.run_cli("user", "sync", "@saregamamalayalam")
        data = library.load()
        self.assertNotIn("PLtrailers0001", data["playlists"])
        self.assertNotIn("OkvkSXKcLBM", data["playlists"]["PLGSaQXigBvdM"]["tracks"])
        self.run_cli("playlist", "restore", "--user", "@saregamamalayalam")
        self.run_cli("playlist", "restore-songs", "PLGSaQXigBvdM")
        data = library.load()
        self.assertTrue(data["playlists"]["PLtrailers0001"]["saved"])
        self.assertIn("OkvkSXKcLBM", data["playlists"]["PLGSaQXigBvdM"]["tracks"])
        self.assertEqual(data["removed"], {})


class OwnPlaylistTest(CliTest):
    def setUp(self):
        super().setUp()
        self.run_cli("import", "https://www.youtube.com/playlist?list=PLGSaQXigBvdM")

    def favourites(self):
        return library.load()["playlists"][library.FAVOURITES]["tracks"]

    def test_favourites_from_the_library_and_from_outside(self):
        self.run_cli("fav", "hvqnG6VjqV0", "https://youtu.be/zzzzzzzzzzz")
        data = library.load()
        self.assertEqual(self.favourites(), ["hvqnG6VjqV0", "zzzzzzzzzzz"])
        self.assertEqual(data["tracks"]["zzzzzzzzzzz"]["title"], "Kanmani Anbodu")  # looked up on YouTube
        shelf = library.shelf(data)
        self.assertEqual([(m["id"], m["tracks"]) for m in shelf["mine"]],
                         [(library.FAVOURITES, ["hvqnG6VjqV0", "zzzzzzzzzzz"])])
        on_shelves = [e["id"] for items in shelf["languages"].values() for e in items]
        self.assertEqual(on_shelves, ["PLGSaQXigBvdM"])  # Favourites isn't on the language shelves
        self.run_cli("fav", "--toggle", "hvqnG6VjqV0")
        self.assertEqual(self.favourites(), ["zzzzzzzzzzz"])
        self.run_cli("fav", "--toggle", "hvqnG6VjqV0")
        self.run_cli("fav", "hvqnG6VjqV0")  # already there: no duplicate
        self.assertEqual(self.favourites(), ["zzzzzzzzzzz", "hvqnG6VjqV0"])
        self.run_cli("fav", "--remove", "zzzzzzzzzzz")
        self.assertNotIn("zzzzzzzzzzz", library.load()["tracks"])  # nothing else refers to it
        with self.assertRaises(ValueError):
            self.run_cli("playlist", "remove", "Favourites")  # emptied, never deleted
        self.assertEqual(self.favourites(), ["hvqnG6VjqV0"])

    def test_own_playlists_keep_their_songs(self):
        self.run_cli("playlist", "new", "Car songs", "hvqnG6VjqV0", "trailer0001")
        own = library.find_own_playlist(library.load(), "car songs")
        self.assertEqual(own["tracks"], ["hvqnG6VjqV0", "trailer0001"])
        # The playlist the songs came from goes; they stay.
        self.run_cli("playlist", "remove", "PLGSaQXigBvdM")
        data = library.load()
        self.assertEqual(library.playlist_tracks(data, own["id"])[0]["title"], "Thalatherichavar")
        # Nothing refreshes it from YouTube.
        self.fetched.clear()
        self.run_cli("playlist", "fetch", own["id"])
        self.assertEqual(self.fetched, [])
        # It plays exactly what's in it, trailer included.
        args = cli.build_parser().parse_args(["play", "Car songs"])
        tracks, start, source = cli._queue_from_args(args, cli.Reporter(False))
        self.assertEqual([t["id"] for t in tracks], ["hvqnG6VjqV0", "trailer0001"])
        self.assertEqual(source, {"type": "playlist", "id": own["id"], "title": "Car songs"})
        # Removing from it, or deleting it (by name), leaves nothing to bring back.
        self.run_cli("playlist", "remove-songs", "Car songs", "trailer0001")
        self.assertNotIn("removedTracks", library.load()["playlists"][own["id"]])
        self.run_cli("playlist", "remove", "car songs")
        data = library.load()
        self.assertNotIn(own["id"], data["removed"])
        self.assertEqual(data["tracks"], {})

    def test_songs_only_go_into_your_own_playlists(self):
        with self.assertRaises(ValueError):
            self.run_cli("playlist", "add-songs", "PLGSaQXigBvdM", "hvqnG6VjqV0")
        with self.assertRaises(ValueError):
            self.run_cli("playlist", "add-songs", "No such list", "hvqnG6VjqV0")
        self.run_cli("playlist", "new", "Melodies")
        with self.assertRaises(ValueError):
            self.run_cli("playlist", "new", "melodies")
        self.run_cli("playlist", "add-songs", "Melodies", "OkvkSXKcLBM")
        self.run_cli("playlist", "rename", "Melodies", "Night drive")
        own = library.find_own_playlist(library.load(), "Night drive")
        self.assertEqual(own["tracks"], ["OkvkSXKcLBM"])
        with self.assertRaises(ValueError):
            self.run_cli("playlist", "unsave", own["id"])
        with self.assertRaises(ValueError):
            self.run_cli("playlist", "rename", "favourites", "Liked")

    def test_the_playing_song_is_the_default(self):
        with self.assertRaises(engine.EngineError):
            self.run_cli("fav")


OTHER = dict(CHANNEL, id="UC" + "o" * 22, handle="@someoneelse", name="Someone else",
             url="https://www.youtube.com/@someoneelse",
             playlists=[{"id": "PLother0000001", "title": "Long drive", "thumbnail": ""}])


class StarterTest(CliTest):
    def seed(self):
        """What `paattu seed` leaves: a curated profile with featured playlists."""
        with library.edit() as data:
            user = library.upsert_user(data, CHANNEL, "Malayalam", curated=True)
            for pid in ("PLGSaQXigBvdM", "PLtamil00000001"):
                library.set_playlist_tracks(data, dict(DETAILS, id=pid))
                data["playlists"][pid].update(saved=True, featured=True)
            data["removed"]["PLtrailers0001"] = {"title": "Trailers", "owner": user["id"], "removed": library.now()}

    def art(self, kind, ident):
        path = paths.art_path(kind, ident)
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(b"jpg")
        return path

    def test_removing_it_keeps_what_you_added(self):
        self.seed()
        self.run_cli("playlist", "save", "PLV1bF0JcivaesjK7MqHB9Ogl_uTQmwoYP")  # saved by you, from a starter profile
        self.channel = OTHER
        self.run_cli("import", "@someoneelse")  # a profile you added
        self.run_cli("fav", "OkvkSXKcLBM")  # a starter song you hearted
        self.run_cli("mix", "new", "Mine", "--user", "@someoneelse", "--playlist", "PLGSaQXigBvdM")
        gone = [self.art("p", "PLGSaQXigBvdM"), self.art("u", CHANNEL["id"])]
        kept = [self.art("p", "PLother0000001"), self.art("v", "OkvkSXKcLBM")]

        self.run_cli("seed", "--remove")
        data = library.load()
        self.assertEqual(list(data["users"]), [OTHER["id"]])
        self.assertEqual(sorted(data["playlists"]), sorted(
            ["PLV1bF0JcivaesjK7MqHB9Ogl_uTQmwoYP", "PLother0000001", library.FAVOURITES]))
        self.assertEqual(data["removed"], {})
        self.assertIn("OkvkSXKcLBM", data["tracks"])  # Favourites keeps it
        mine = library.find_mix(data, "mine")
        self.assertEqual(mine["sources"], [{"type": "user", "id": OTHER["id"]}])  # the starter playlist left it
        self.assertEqual([p.exists() for p in gone + kept], [False, False, True, True])
        self.run_cli("seed", "--remove")  # nothing left to remove
        self.assertEqual(len(library.load()["playlists"]), 3)


class MixTest(CliTest):
    def setUp(self):
        super().setUp()
        self.run_cli("import", "@saregamamalayalam", "--lang", "Malayalam")

    def mixes(self):
        return [(m["title"], [(s["type"], s["id"]) for s in m["sources"]]) for m in library.load()["mixes"]]

    def queue(self, mix):
        args = cli.build_parser().parse_args(["play", "--mix=" + mix])
        return cli._queue_from_args(args, cli.Reporter(False))

    def test_a_new_library_has_no_mixes(self):
        self.assertEqual(self.mixes(), [])
        self.run_cli("mix", "new", "Tamil mix", "--lang", "Tamil")
        data = library.load()
        self.assertEqual([p["id"] for p in library.mix_playlists(data, library.find_mix(data, "tamil"))],
                         ["PLtamil00000001"])
        tracks, start, source = self.queue("tamil")
        self.assertEqual((source["type"], source["title"]), ("mix", "Tamil mix"))
        # Libraries from before mixes don't get any either.
        with library.edit() as data:
            del data["mixes"]
        self.assertEqual(library.load()["mixes"], [])

    def test_the_mixes_libraries_used_to_start_with_go_unless_changed(self):
        def first(lang, *extra):
            return {"id": "mix-" + lang.lower(), "title": lang + " mix",
                    "sources": [{"type": "language", "id": lang}, *extra]}
        with library.edit() as data:
            data.pop("mixesVersion")
            data["mixes"] = [first("Malayalam", {"type": "playlist", "id": "paattu-played-malayalam"}),
                             first("Tamil", {"type": "language", "id": "Kannada"}),
                             {"id": "mix-ab12", "title": "Mine", "sources": [{"type": "language", "id": "Malayalam"}]}]
        self.assertEqual([m["title"] for m in library.load()["mixes"]], ["Tamil mix", "Mine"])
        with library.edit() as data:
            data["mixes"].insert(0, first("Malayalam"))  # made again by hand after: stays
        self.assertEqual([m["title"] for m in library.load()["mixes"]], ["Malayalam mix", "Tamil mix", "Mine"])

    def test_make_change_and_order_mixes(self):
        self.run_cli("mix", "new", "Malayalam mix", "--lang", "Malayalam")
        self.run_cli("mix", "new", "Tamil mix", "--lang", "Tamil")
        self.run_cli("fav", "hvqnG6VjqV0")
        self.run_cli("mix", "new", "Road trip", "--user", "@saregamamalayalam", "--playlist", "favourites")
        self.run_cli("mix", "add", "road trip", "--lang", "tamil", "--playlist", "Hits of Sushin Shyam")
        self.run_cli("mix", "drop", "Road trip", "--user", "saregamamalayalam")
        self.assertEqual(self.mixes()[2], ("Road trip", [("playlist", library.FAVOURITES), ("language", "Tamil"),
                                                         ("playlist", "PLGSaQXigBvdM")]))
        self.run_cli("mix", "move", "road trip", "1")
        self.run_cli("mix", "rename", "Tamil", "Kollywood")
        self.run_cli("mix", "remove", "malayalam mix")
        self.assertEqual([title for title, _ in self.mixes()], ["Road trip", "Kollywood"])
        shelf = library.shelf(library.load())["mixes"][0]
        self.assertEqual([s["title"] for s in shelf["sources"]], ["Favourites", "Tamil", "Hits of Sushin Shyam"])
        self.assertEqual((shelf["playlists"], shelf["count"], shelf["waiting"]), (3, 4, 0))
        for bad in (["mix", "new", "kollywood"], ["mix", "add", "Nope", "--lang", "Tamil"],
                    ["mix", "add", "Kollywood"], ["mix", "add", "Kollywood", "--user", "@nobody"],
                    ["mix", "add", "Kollywood", "--playlist", "PLnotsaved"]):
            with self.assertRaises((ValueError, youtube.YouTubeError), msg=bad):
                self.run_cli(*bad)

    def test_playlists_picked_for_a_mix_get_their_songs(self):
        with library.edit() as data:
            library.upsert_playlist_stub(data, {"id": "PLother0000002", "title": "Not saved"})
        self.fetched.clear()
        self.run_cli("mix", "new", "Pick", "--playlist", "PLother0000002")
        self.assertEqual(self.fetched, ["PLother0000002"])
        self.assertEqual(len(self.queue("pick")[0]), 2)

    def test_empty_mixes_and_leaving_users(self):
        self.run_cli("mix", "new", "Nothing")
        with self.assertRaisesRegex(engine.EngineError, "empty"):
            self.queue("nothing")
        self.run_cli("mix", "add", "nothing", "--user", "@saregamamalayalam", "--lang", "Kannada")
        self.run_cli("user", "remove", "@saregamamalayalam", "--purge")
        self.assertEqual(self.mixes()[0], ("Nothing", [("language", "Kannada")]))
        with self.assertRaisesRegex(engine.EngineError, "no saved playlists in Kannada"):
            self.queue("nothing")


@unittest.skipUnless(shutil.which("mpv"), "needs mpv")
class EngineBatchTest(unittest.TestCase):
    def test_a_whole_mix_loads_without_deadlocking(self):
        # Thousands of loadfile replies overflow the socket buffers unless
        # Engine.batch reads as it sends.
        with tempfile.TemporaryDirectory() as tmp:
            sock = pathlib.Path(tmp) / "s"
            mpv = subprocess.Popen(["mpv", "--no-config", "--idle=yes", "--ao=null", "--vo=null", "--ytdl=no",
                                    "--no-terminal", "--input-ipc-server=" + str(sock)])
            saved = paths.SOCKET, engine.track_url
            try:
                for _ in range(50):
                    if sock.exists():
                        break
                    time.sleep(0.1)
                paths.SOCKET, engine.track_url = sock, lambda track: tmp + "/missing/" + track["id"]
                tracks = [{"id": "v%010d" % i, "title": "Song %d" % i} for i in range(3000)]
                with engine.Engine(autostart=False) as e:
                    engine.load(e, tracks, source={"title": "test"})
                    self.assertEqual(e.get("playlist-count"), 3000)
            finally:
                paths.SOCKET, engine.track_url = saved
                mpv.terminate()
                mpv.wait(5)


class SeedTest(unittest.TestCase):
    def test_featured_prefers_hits_then_albums_and_skips_trailers(self):
        stubs = [{"id": p["id"], "title": p["title"]} for p in CHANNEL["playlists"]]
        picked = [p["id"] for p in seeds.pick_featured(stubs, 3)]
        self.assertEqual(set(picked[:2]), {"PLGSaQXigBvdM", "PLtamil00000001"})
        self.assertEqual(picked[2], "PLV1bF0JcivaesjK7MqHB9Ogl_uTQmwoYP")
        self.assertNotIn("PLtrailers0001", picked)

    def test_handles_are_unique(self):
        handles = [h.lower() for h, _, _ in seeds.CURATED]
        self.assertEqual(len(handles), len(set(handles)))


class YoutubeParseTest(unittest.TestCase):
    def test_users(self):
        self.assertEqual(youtube.normalize_user("@Muzik247"), "https://www.youtube.com/@Muzik247")
        self.assertEqual(youtube.normalize_user("Muzik247"), "https://www.youtube.com/@Muzik247")
        self.assertEqual(youtube.normalize_user("https://www.youtube.com/@thinkmusicofficial/videos"),
                         "https://www.youtube.com/@thinkmusicofficial")
        self.assertEqual(youtube.normalize_user("https://music.youtube.com/channel/UCLbdVvreihwZRL6kwuEUYsA"),
                         "https://www.youtube.com/channel/UCLbdVvreihwZRL6kwuEUYsA")
        self.assertEqual(youtube.normalize_user("UCLbdVvreihwZRL6kwuEUYsA"),
                         "https://www.youtube.com/channel/UCLbdVvreihwZRL6kwuEUYsA")

    def test_playlists_and_videos(self):
        self.assertEqual(youtube.normalize_playlist("https://www.youtube.com/playlist?list=PLGSaQXigBvdM"), "PLGSaQXigBvdM")
        self.assertEqual(youtube.normalize_playlist("https://music.youtube.com/watch?v=abc&list=OLAK5uy_kxyz12345"), "OLAK5uy_kxyz12345")
        self.assertEqual(youtube.normalize_playlist("VLPLGSaQXigBvdM"), "PLGSaQXigBvdM")
        with self.assertRaises(youtube.YouTubeError):
            youtube.normalize_playlist("https://www.youtube.com/watch?v=hvqnG6VjqV0")
        self.assertEqual(youtube.video_id("https://youtu.be/hvqnG6VjqV0?si=x"), "hvqnG6VjqV0")
        self.assertEqual(youtube.video_id("https://www.youtube.com/watch?v=hvqnG6VjqV0&list=PL1"), "hvqnG6VjqV0")
        self.assertEqual(youtube.video_id("hvqnG6VjqV0"), "hvqnG6VjqV0")

    def test_classify_pasted_links(self):
        self.assertEqual(youtube.classify("https://www.youtube.com/@Muzik247/playlists"), ("user", "https://www.youtube.com/@Muzik247"))
        self.assertEqual(youtube.classify("@Muzik247/featured"), ("user", "https://www.youtube.com/@Muzik247"))
        self.assertEqual(youtube.classify("https://www.youtube.com/watch?v=hvqnG6VjqV0&list=PLGSaQXigBvdM"), ("playlist", "PLGSaQXigBvdM"))
        with self.assertRaises(youtube.YouTubeError):
            youtube.classify("https://youtu.be/hvqnG6VjqV0")


class ConfigTest(TempDirs):
    def test_set_and_validate(self):
        cfg = config.set_key("desktop.style", "card")
        self.assertEqual(cfg["desktop"]["style"], "card")
        self.assertEqual(cfg["desktop"]["workspace"], 1)
        with self.assertRaises(ValueError):
            config.set_key("desktop.style", "spinning")
        with self.assertRaises(ValueError):
            config.set_key("theme", "nope")
        self.assertEqual(config.parse_value("1.2"), 1.2)
        self.assertEqual(config.parse_value("true"), True)
        self.assertEqual(config.parse_value("vinyl"), "vinyl")

    def test_now_playing_settings(self):
        cfg = config.load()
        self.assertEqual((cfg["nowPlayingStyle"], cfg["videoBlur"], cfg["coverColors"], cfg["coverDepth"]),
                         ("cover", 30, False, True))
        self.assertEqual(config.set_key("nowPlayingStyle", "record")["nowPlayingStyle"], "record")
        self.assertEqual(config.set_key("videoBlur", 0)["videoBlur"], 0)
        self.assertTrue(config.set_key("coverColors", True)["coverColors"])
        for key, value in (("nowPlayingStyle", "spinning"), ("videoBlur", 101), ("videoBlur", -1), ("videoBlur", 2.5),
                           ("videoBlur", True), ("coverColors", "yes"), ("coverDepth", 1)):
            with self.assertRaises(ValueError, msg="%s = %r" % (key, value)):
                config.set_key(key, value)


if __name__ == "__main__":
    unittest.main()


class PlayedTest(unittest.TestCase):
    """Songs played join their language's mix (tests/played_cases.json, shared with the app)."""

    CASES = json.loads((pathlib.Path(__file__).parent / "played_cases.json").read_text())

    def library(self):
        return copy.deepcopy(self.CASES["library"])

    def test_language(self):
        data = self.library()
        for case in self.CASES["language"]:
            self.assertEqual(library.played_language(data, case["track"]), case["language"], case)

    def test_plays(self):
        data = self.library()
        for case in self.CASES["plays"]:
            self.assertEqual(library.note_played(data, case["track"]), case["language"], case)
            for language in ("malayalam", "tamil"):
                playlist = data["playlists"].get(library.PLAYED_PREFIX + language)
                self.assertEqual(playlist and playlist["tracks"], case[language], case)
        mixes = {m["id"]: m["sources"] for m in data["mixes"]}
        self.assertIn({"type": "playlist", "id": "paattu-played-malayalam"}, mixes["mix-malayalam"])
        self.assertIn({"type": "playlist", "id": "paattu-played-tamil"}, mixes["mix-tamil"])
        self.assertEqual(data["playlists"]["paattu-played-tamil"]["title"], "Played in Tamil")
        self.assertIn("s2", data["tracks"])

    def test_deleted_stays_deleted(self):
        data = self.library()
        library.note_played(data, {"id": "s1", "title": "Pularikalo", "language": "Malayalam"})
        library.remove_playlist(data, "paattu-played-malayalam")
        self.assertEqual(data["playedOff"], ["Malayalam"])
        self.assertEqual(library.note_played(data, {"id": "s3", "title": "x", "language": "Malayalam"}), "")
        self.assertNotIn("paattu-played-malayalam", data["playlists"])

    def test_dropped_source_stays_dropped(self):
        data = self.library()
        library.note_played(data, {"id": "s1", "title": "Pularikalo", "language": "Malayalam"})
        library.drop_mix_sources(data, "mix-malayalam", [{"type": "playlist", "id": "paattu-played-malayalam"}])
        library.note_played(data, {"id": "s3", "title": "x", "language": "Malayalam"})
        self.assertEqual(data["mixes"][0]["sources"], [{"type": "language", "id": "Malayalam"}])
