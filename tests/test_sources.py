import argparse
import json
import os
import pathlib
import sys
import tempfile
import unittest
from unittest import mock

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from paattu import art, cli, engine, library, paths, sources, youtube  # noqa: E402

HERE = pathlib.Path(__file__).resolve().parent
# Shared with model.test.mjs: Model.js trackId must give the same ids.
TRACK_IDS = json.loads((HERE / "track_ids.json").read_text())

SAAVN_MALARE = {
    "id": "JWg0ED0Q", "title": "Malare", "subtitle": "Vijay Yesudas - Premam", "type": "song",
    "perma_url": "https://www.jiosaavn.com/song/malare/Oj8MATF0B2I",
    "image": "https://c.saavncdn.com/665/Premam-Malayalam-2015-150x150.jpg",
    "language": "malayalam", "year": "2015", "play_count": "9568589",
    "more_info": {
        "music": "Rajesh Murugesan", "album": "Premam", "label": "Muzik 247", "320kbps": "true", "duration": "316",
        "artistMap": {
            "primary_artists": [{"name": "Vijay Yesudas", "role": "primary_artists"}],
            "featured_artists": [],
            "artists": [{"name": "Rajesh Murugesan", "role": "music"}, {"name": "Vijay Yesudas", "role": "singer"},
                        {"name": "Shabareesh Varma", "role": "lyricist"}],
        },
    },
}
SAAVN_FROM = {
    "id": "x1", "title": "Malare (From &quot;Premam&quot;)", "type": "song",
    "perma_url": "https://www.jiosaavn.com/song/malare-from-premam/AQ0dbjB1ZQI",
    "image": "https://c.saavncdn.com/123/Hits-150x150.jpg", "language": "malayalam", "year": "2020",
    "more_info": {"music": "Rajesh Murugesan", "album": "Malayalam Love Hits", "label": "Muzik 247",
                  "320kbps": "false", "duration": "300",
                  "artistMap": {"primary_artists": [{"name": "Vijay Yesudas"}], "featured_artists": [], "artists": []}},
}


class SearchCache(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        root = pathlib.Path(self.tmp.name)
        self.saved = {name: getattr(paths, name) for name in
                      ("DATA", "LIBRARY", "SHELF", "CONFIG", "CONFIG_FILE", "ART", "CACHE", "SEARCH")}
        paths.DATA = root / "data"
        paths.LIBRARY = paths.DATA / "library.json"
        paths.SHELF = paths.DATA / "shelf.json"
        paths.CONFIG = root / "config"
        paths.CONFIG_FILE = paths.CONFIG / "config.json"
        paths.CACHE = root / "cache"
        paths.ART = paths.CACHE / "art"
        paths.SEARCH = paths.CACHE / "search.json"
        self.spawn_art = cli._spawn_art
        cli._spawn_art = lambda ids: None

    def tearDown(self):
        for name, value in self.saved.items():
            setattr(paths, name, value)
        cli._spawn_art = self.spawn_art
        self.tmp.cleanup()


class TrackIdTest(unittest.TestCase):
    def test_ids_match_the_shared_cases(self):
        for url, want in TRACK_IDS.items():
            self.assertEqual(sources.track_id(url), want, url)

    def test_ids_of_other_sites_never_look_like_video_ids(self):
        for url in TRACK_IDS:
            tid = sources.track_id(url)
            if tid and not sources.is_youtube(url) and sources.is_link(url):
                self.assertFalse(sources.is_video_id(tid), url)

    def test_sites(self):
        self.assertEqual(sources.site_of("https://www.jiosaavn.com/song/x/y"), "jiosaavn")
        self.assertEqual(sources.site_of("https://m.soundcloud.com/a/b"), "soundcloud")
        self.assertEqual(sources.site_of("https://music.youtube.com/watch?v=hvqnG6VjqV0"), "youtube")
        self.assertEqual(sources.site_of("https://artist.bandcamp.com/track/song"), "artist.bandcamp.com")
        self.assertEqual(sources.site_name("jiosaavn"), "JioSaavn")

    def test_track_url(self):
        self.assertEqual(sources.track_url({"id": "hvqnG6VjqV0"}), youtube.watch_url("hvqnG6VjqV0"))
        self.assertEqual(sources.track_url({"id": "x", "url": "https://a.b/c.flac"}), "https://a.b/c.flac")

    def test_quality_label(self):
        self.assertEqual(sources.quality_label({"quality": 320, "codec": "aac"}), "320 kbps")
        self.assertEqual(sources.quality_label({"quality": 900, "codec": "flac"}), "Lossless")
        self.assertEqual(sources.quality_label({"id": "hvqnG6VjqV0"}), "")


class ParseTest(unittest.TestCase):
    def test_jiosaavn_song(self):
        t = sources.jiosaavn_track(SAAVN_MALARE)
        self.assertEqual(t["id"], "jiosaavn.com_song_malare_Oj8MATF0B2I")
        self.assertEqual((t["title"], t["movie"], t["site"]), ("Malare", "Premam", "jiosaavn"))
        self.assertEqual(t["credits"], ["Rajesh Murugesan", "Vijay Yesudas"])
        self.assertEqual((t["quality"], t["codec"], t["duration"], t["year"]), (320, "aac", 316, "2015"))
        self.assertEqual(t["language"], "Malayalam")
        self.assertEqual(t["art"], "https://c.saavncdn.com/665/Premam-Malayalam-2015-500x500.jpg")

    def test_jiosaavn_from_film_on_a_hits_album(self):
        t = sources.jiosaavn_track(SAAVN_FROM)
        self.assertEqual((t["title"], t["movie"], t["album"]), ("Malare", "Premam", "Malayalam Love Hits"))
        self.assertEqual(t["rawTitle"], 'Malare (From "Premam")')
        self.assertEqual(t["quality"], 128)
        self.assertEqual(t["credits"], ["Vijay Yesudas"])

    def test_jiosaavn_skips_albums_and_playlists(self):
        self.assertIsNone(sources.jiosaavn_track({**SAAVN_MALARE, "type": "album"}))

    def test_film_and_title(self):
        self.assertEqual(sources.film_and_title("Kaathalae", "96 (Original Motion Picture Soundtrack)"), ("Kaathalae", "96"))
        self.assertEqual(sources.film_and_title("Chuttamalle", "Devara Part 1 - Telugu (Original Motion Picture Soundtrack)"),
                         ("Chuttamalle", "Devara Part 1"))
        self.assertEqual(sources.film_and_title("Premam", "Premam"), ("Premam", ""))

    def test_youtube_result(self):
        t = sources.youtube_track({"id": "hvqnG6VjqV0", "channel": "Saregama Malayalam", "duration": 276.0,
                                   "title": "Thalatherichavar - Video | Romancham | Sushin Shyam | Saregama Malayalam"})
        self.assertEqual((t["id"], t["site"], t["duration"]), ("hvqnG6VjqV0", "youtube", 276))
        self.assertNotIn("url", t)
        self.assertIsNone(sources.youtube_track({"id": "hvqnG6VjqV0", "title": "x", "live_status": "is_live"}))
        self.assertIsNone(sources.youtube_track({"id": "hvqnG6VjqV0", "title": "[Private video]"}))

    def test_video_for_a_background(self):
        url = "https://rr3.googlevideo.com/videoplayback?expire=1792071358&itag=160"
        asked = []

        def run(target, timeout=180, extra=()):
            asked.append((target, extra))
            return {"duration": 316, "url": url}

        found = [{"id": "XotCQRUbqMM", "duration": 295}, {"id": "0G2VxhV_gXM", "duration": 314}]
        with mock.patch.object(youtube, "_run", run), \
                mock.patch.object(sources, "search_youtube", lambda query, limit=12: found):
            # A YouTube song: its own video, the smallest H.264 picture.
            self.assertEqual(sources.video_for({"id": "hvqnG6VjqV0"}),
                             {"id": "hvqnG6VjqV0", "url": url, "duration": 316, "expires": 1792071358})
            self.assertEqual(asked[-1], ("https://www.youtube.com/watch?v=hvqnG6VjqV0", ("-f", youtube.SMALL_VIDEO)))
            # Another site's: the first search result as long as the song (within 20 s).
            saavn = sources.jiosaavn_track(SAAVN_MALARE)
            self.assertEqual(sources.video_for(saavn)["id"], "0G2VxhV_gXM")
            self.assertIsNone(sources.video_for(dict(saavn, duration=200)))
            self.assertIsNone(sources.video_for({"id": saavn["id"], "title": "Malare"}))  # length unknown

    def test_soundcloud_result(self):
        t = sources.soundcloud_track({
            "webpage_url": "https://soundcloud.com/someone/malare-cover", "title": "Malare cover", "uploader": "someone",
            "duration": 200, "thumbnails": [{"id": "t300x300", "url": "https://i1.sndcdn.com/a-t300x300.jpg"},
                                            {"id": "t500x500", "url": "https://i1.sndcdn.com/a-t500x500.jpg"}]})
        self.assertEqual(t["id"], "soundcloud.com_someone_malare-cover")
        self.assertEqual(t["art"], "https://i1.sndcdn.com/a-t500x500.jpg")
        self.assertEqual(t["url"], "https://soundcloud.com/someone/malare-cover")

    def test_link_prefers_lossless(self):
        info = {"extractor_key": "Bandcamp", "webpage_url": "https://artist.bandcamp.com/track/song",
                "title": "Song", "track": "Song", "artist": "Artist", "album": "Album", "duration": 180,
                "formats": [{"acodec": "mp3", "abr": 320}, {"acodec": "flac", "abr": 0, "ext": "flac"},
                            {"acodec": "none", "vcodec": "h264", "tbr": 2000}]}
        t = sources.link_track(info, info["webpage_url"])
        self.assertEqual((t["quality"], t["codec"], t["movie"]), (None, "flac", "Album"))
        self.assertEqual(sources.quality_label(t), "Lossless")
        self.assertEqual(t["site"], "artist.bandcamp.com")

    def test_direct_file_plays_its_own_link(self):
        info = {"extractor_key": "Generic", "url": "https://cdn.example.org/x/redirected.mp3",
                "title": "redirected", "formats": [{"acodec": "mp3", "abr": 256, "ext": "mp3"}]}
        t = sources.link_track(info, "https://example.org/songs/Malare%20Live.mp3")
        self.assertEqual(t["url"], "https://example.org/songs/Malare%20Live.mp3")
        self.assertEqual((t["quality"], t["codec"]), (256, "mp3"))


class SearchTest(SearchCache):
    def test_one_site_failing_leaves_the_others(self):
        saved = dict(sources.SEARCHERS)
        sources.SEARCHERS["jiosaavn"] = lambda q, n: [sources.jiosaavn_track(SAAVN_MALARE)]
        sources.SEARCHERS["youtube"] = lambda q, n: (_ for _ in ()).throw(youtube.YouTubeError("timed out"))
        try:
            found, errors = sources.search("malare", ("jiosaavn", "youtube"))
        finally:
            sources.SEARCHERS.update(saved)
        self.assertEqual([t["title"] for t in found["jiosaavn"]], ["Malare"])
        self.assertEqual(found["youtube"], [])
        self.assertEqual(errors, {"youtube": "didn't answer in time"})

    def test_remember_keeps_the_newest(self):
        sources.remember([{"id": "a.b_%d" % n, "title": str(n)} for n in range(sources.REMEMBER + 5)])
        sources.remember([{"id": "a.b_3", "title": "again"}])
        self.assertIsNone(sources.recall("a.b_0"))
        self.assertEqual(sources.recall("a.b_3")["title"], "again")
        self.assertEqual(len(json.loads(paths.SEARCH.read_text())), sources.REMEMBER)

    def test_resolve_an_album(self):
        lookup = youtube.lookup
        youtube.lookup = lambda target, timeout=60, extra=(): {"entries": [
            {"webpage_url": "https://artist.bandcamp.com/track/one", "title": "One", "artist": "A", "album": "LP"},
            {"webpage_url": "https://artist.bandcamp.com/track/two", "title": "Two", "artist": "A", "album": "LP"},
            {"ie_key": "Youtube", "id": "hvqnG6VjqV0", "url": "https://www.youtube.com/watch?v=hvqnG6VjqV0",
             "title": "Thalatherichavar"}]}
        try:
            tracks = sources.resolve("https://artist.bandcamp.com/album/lp")
        finally:
            youtube.lookup = lookup
        self.assertEqual([t["id"] for t in tracks], ["artist.bandcamp.com_track_one", "artist.bandcamp.com_track_two",
                                                     "hvqnG6VjqV0"])
        self.assertEqual(tracks[0]["url"], "https://artist.bandcamp.com/track/one")


class SavedSongsTest(SearchCache):
    def args(self, **kw):
        base = {"videos": [], "remove": False, "toggle": False, "list": False, "json": True}
        return argparse.Namespace(**{**base, **kw})

    def test_save_a_search_result_by_id(self):
        found = sources.jiosaavn_track(SAAVN_MALARE)
        sources.remember([found])
        out = cli.Reporter(True)
        cli.cmd_save(self.args(videos=[found["id"]]), out)
        data = library.load()
        self.assertEqual(data["playlists"][library.SAVED]["tracks"], [found["id"]])
        self.assertEqual(data["tracks"][found["id"]]["url"], found["url"])
        self.assertEqual(data["tracks"][found["id"]]["quality"], 320)
        # ...hearted by its link as well as its id, and saved only once.
        cli.cmd_fav(self.args(videos=[found["url"]]), out)
        cli.cmd_save(self.args(videos=[found["url"]], toggle=True), out)
        data = library.load()
        self.assertEqual(data["playlists"][library.FAVOURITES]["tracks"], [found["id"]])
        self.assertEqual(data["playlists"][library.SAVED]["tracks"], [])
        # Still a favourite, so it stays in the library.
        self.assertIn(found["id"], data["tracks"])

    def test_saved_songs_is_built_in(self):
        with library.edit() as data:
            mine = library.create_playlist(data, "Road trip")
            self.assertIs(library.create_playlist(data, "Saved songs"), library.saved_songs(data))
            library.favourites(data)
            with self.assertRaises(ValueError):
                library.rename_playlist(data, library.SAVED, "Mine")
            self.assertEqual([p["id"] for p in library.own_playlists(data)], [library.FAVOURITES, library.SAVED, mine["id"]])
            self.assertIs(library.find_own_playlist(data, "saved"), library.saved_songs(data))
        shelf = library.shelf(library.load())
        self.assertEqual([p["saved"] for p in shelf["mine"]], [False, True, False])

    def test_add_a_result_to_your_playlist_and_play_it(self):
        found = sources.soundcloud_track({"webpage_url": "https://soundcloud.com/s/cover", "title": "Cover", "uploader": "s"})
        sources.remember([found])
        out = cli.Reporter(True)
        with library.edit() as data:
            library.create_playlist(data, "Covers")
        cli.cmd_playlist_add_songs(argparse.Namespace(playlist="Covers", videos=[found["id"]], json=True), out)
        data = library.load()
        own = library.find_own_playlist(data, "Covers")
        self.assertEqual(own["tracks"], [found["id"]])
        args = argparse.Namespace(target=found["id"], lang=None, user=None, mix=None, index=None, track=None)
        tracks, start, source = cli._queue_from_args(args, out)
        self.assertEqual(([t["id"] for t in tracks], source["type"], source["title"]), ([found["id"]], "track", "SoundCloud"))
        self.assertEqual(engine.display_title(tracks[0]), "Cover")

    def test_unknown_names_are_not_songs(self):
        with self.assertRaises(sources.SourceError):
            cli._songs(library.load(), ["not-a-song-at-all"], cli.Reporter(True))


class ArtTest(unittest.TestCase):
    def test_cover_links(self):
        self.assertEqual(art.track_art("hvqnG6VjqV0"), art.video_thumbnail("hvqnG6VjqV0"))
        self.assertEqual(art.track_art("jiosaavn.com_song_x", {"art": "https://c.saavncdn.com/a-500x500.jpg"}),
                         "https://c.saavncdn.com/a-500x500.jpg")
        self.assertEqual(art.track_art("example.com_a.mp3", {"url": "https://example.com/a.mp3"}), "")
        self.assertEqual(art.track_art("example.com_a.mp3"), "")



class SongVideoTest(unittest.TestCase):
    """The video behind Now Playing: a song's own unless it's a still."""

    def small(self, kbps):
        return {"requested_formats": [{"url": "https://rr1---sn-x.googlevideo.com/videoplayback?expire=1", "tbr": kbps}],
                "duration": 248}

    def test_a_still_cover_is_no_video(self):
        with mock.patch.object(youtube, "_run", lambda *a, **k: self.small(10.4)):
            self.assertIsNone(youtube.small_video("NAkQVL61BRI"))
        with mock.patch.object(youtube, "_run", lambda *a, **k: self.small(96.9)):
            self.assertEqual(youtube.small_video("isDo6u7QQ74")["id"], "isDo6u7QQ74")

    def test_video_mode_picture_is_as_tall_as_asked(self):
        asked = []

        def run(target, timeout=180, extra=()):
            asked.append(extra)
            return self.small(10.4)  # a still passes: only the small picture is judged

        with mock.patch.object(youtube, "_run", run):
            self.assertEqual(youtube.video_picture("isDo6u7QQ74", 720)["id"], "isDo6u7QQ74")
        self.assertIn("[height<=720]", asked[-1][1])

    def test_a_songs_video_is_remembered(self):
        found = []

        def video_for(track):
            found.append(track["id"])
            return {"id": "S3oq6IwPWBw", "url": "u"} if track["id"] == "a" else None

        with tempfile.TemporaryDirectory() as tmp, \
                mock.patch.object(paths, "VIDEOS", pathlib.Path(tmp) / "videos.json"), \
                mock.patch.object(sources, "video_for", video_for):
            self.assertEqual(sources.video_id_for({"id": "a"}, now=1000), ("S3oq6IwPWBw", {"id": "S3oq6IwPWBw", "url": "u"}))
            self.assertEqual(sources.video_id_for({"id": "a"}, now=2000), ("S3oq6IwPWBw", None))
            self.assertEqual(sources.video_id_for({"id": "b"}, now=2000), (None, None))
            self.assertEqual(sources.video_id_for({"id": "b"}, now=3000), (None, None))
            # None found is asked again after a day; a video found, after a month.
            sources.video_id_for({"id": "b"}, now=2000 + sources.NO_VIDEO_KEPT + 1)
            self.assertEqual(found, ["a", "b", "b"])

    def test_an_art_track_gets_a_video_found_by_search(self):
        still = {"NAkQVL61BRI", "rcdWUeVKFnA"}
        tried = []

        def small_video(vid):
            tried.append(vid)
            return None if vid in still else {"id": vid}

        found = [{"id": "NAkQVL61BRI", "duration": 248}, {"id": "RfbehsDXLMo", "duration": 211},
                 {"id": "rcdWUeVKFnA", "duration": 249}, {"id": "S3oq6IwPWBw", "duration": 267}]
        song = {"id": "NAkQVL61BRI", "title": "Naan Naan", "credits": ["Santhosh Narayanan"], "duration": 248}
        with mock.patch.object(youtube, "small_video", small_video), \
                mock.patch.object(sources, "search_youtube", lambda query, limit: found):
            self.assertEqual(sources.video_for(song), {"id": "S3oq6IwPWBw"})
        # Its own first, then the ones about as long, the still one passed over.
        self.assertEqual(tried, ["NAkQVL61BRI", "rcdWUeVKFnA", "S3oq6IwPWBw"])
        with mock.patch.object(youtube, "small_video", lambda vid: {"id": vid}):
            self.assertEqual(sources.video_for({**song, "id": "isDo6u7QQ74"}), {"id": "isDo6u7QQ74"})


if __name__ == "__main__":
    unittest.main()
