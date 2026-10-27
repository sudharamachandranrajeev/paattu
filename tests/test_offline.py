"""Songs kept on this computer (paattu/offline.py) and finding a newer Paattu (paattu/update.py)."""

import io
import json
import pathlib
import tempfile
import unittest
from unittest import mock

from paattu import cli, offline, update


def _entry(name, used, size=100, **track):
    return {"file": name, "bytes": size, "saved": used, "used": used, "plays": 0, "codec": "opus",
            "track": {"title": name, **track}}


class OfflineTest(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.dir = pathlib.Path(self._tmp.name)

    def tearDown(self):
        self._tmp.cleanup()

    def keep(self, key, entry):
        (self.dir / entry["file"]).write_bytes(b"x" * entry["bytes"])
        with offline.editing(self.dir) as kept:
            kept[key] = entry

    def test_key_is_the_apps(self):
        self.assertEqual(offline.key({"id": "abc"}), "youtube:abc")
        self.assertEqual(offline.key({"id": "x1", "url": "https://www.jiosaavn.com/song/x/x1"}), "jiosaavn:x1")

    def test_file_names_say_what_the_song_is(self):
        track = {"id": "a", "title": "Malare: the song", "credits": ["Vijay Yesudas"]}
        self.assertEqual(offline.file_name(track, "aac", self.dir), "Vijay Yesudas - Malare the song.m4a")
        (self.dir / "Vijay Yesudas - Malare the song.m4a").write_bytes(b"")
        self.assertEqual(offline.file_name(track, "aac", self.dir), "Vijay Yesudas - Malare the song (2).m4a")
        self.assertEqual(offline.file_name({"id": "b", "channel": "Muzik247"}, "opus", self.dir), "Muzik247.webm")
        self.assertEqual(offline.file_name({"id": "c"}, "", self.dir), "c.audio")

    def test_the_index_leaves_out_files_that_went(self):
        self.keep("youtube:a", _entry("a.webm", "2026-01-01T00:00:00Z", id="a"))
        self.keep("youtube:b", _entry("b.webm", "2026-01-02T00:00:00Z", id="b"))
        (self.dir / "a.webm").unlink()
        self.assertEqual(list(offline.read(self.dir)), ["youtube:b"])
        self.assertEqual(offline.file_of({"id": "b"}, self.dir), self.dir / "b.webm")
        self.assertIsNone(offline.file_of({"id": "a"}, self.dir))
        index = json.loads((self.dir / offline.INDEX).read_text())
        self.assertEqual(index["version"], 1)

    def test_the_songs_used_least_recently_go_first(self):
        kept = {"youtube:a": _entry("a.webm", "2026-01-03T00:00:00Z"),
                "youtube:b": _entry("b.webm", "2026-01-01T00:00:00Z"),
                "youtube:c": _entry("c.webm", "2026-01-02T00:00:00Z")}
        for e in kept.values():
            (self.dir / e["file"]).write_bytes(b"x")
        self.assertEqual(offline.evict(kept, 200, self.dir), ["b.webm"])
        self.assertEqual(sorted(kept), ["youtube:a", "youtube:c"])
        self.assertFalse((self.dir / "b.webm").exists())
        self.assertEqual(offline.evict(kept, 0, self.dir), [])

    def test_playing_from_here_counts_as_used(self):
        self.keep("youtube:a", _entry("a.webm", "2020-01-01T00:00:00Z", id="a"))
        offline.note_played({"id": "a"}, self.dir)
        entry = offline.read(self.dir)["youtube:a"]
        self.assertEqual(entry["plays"], 1)
        self.assertGreater(entry["used"], "2020-01-01T00:00:00Z")
        offline.note_played({"id": "nope"}, self.dir)

    def test_removing_deletes_the_file(self):
        self.keep("youtube:a", _entry("a.webm", "2026-01-01T00:00:00Z", id="a"))
        self.assertEqual(offline.remove("youtube:a", self.dir)["file"], "a.webm")
        self.assertFalse((self.dir / "a.webm").exists())
        self.assertIsNone(offline.remove("youtube:a", self.dir))

    def test_no_internet_plays_the_kept_songs(self):
        self.keep("youtube:aaaaaaaaaaa", _entry("a.webm", "2026-01-01T00:00:00Z", id="aaaaaaaaaaa", title="Malare"))
        self.keep("youtube:bbbbbbbbbbb", _entry("b.webm", "2026-01-02T00:00:00Z", id="bbbbbbbbbbb", title="Pularikalo"))
        out = cli.Reporter(True)
        printed = io.StringIO()
        with mock.patch.object(offline, "folder", return_value=self.dir), \
                mock.patch.object(offline, "reachable", return_value=False), \
                mock.patch("shutil.which", return_value=None), \
                mock.patch("sys.stdout", printed):
            cli.cmd_failover(mock.Mock(url="https://www.youtube.com/watch?v=aaaaaaaaaaa", title="Malare"), out)
        found = json.loads(printed.getvalue())
        self.assertTrue(found["offline"])
        self.assertEqual(found["url"], "https://www.youtube.com/watch?v=bbbbbbbbbbb")
        self.assertEqual(found["more"], [])

    def test_no_internet_and_nothing_kept_says_so(self):
        with mock.patch.object(offline, "folder", return_value=self.dir), \
                mock.patch.object(offline, "reachable", return_value=False):
            with self.assertRaises(cli.SourceError):
                cli.cmd_failover(mock.Mock(url="https://www.youtube.com/watch?v=a", title=""), cli.Reporter(True))


class UpdateTest(unittest.TestCase):
    def test_versions_compare_as_people_read_them(self):
        self.assertTrue(update.is_newer("0.10.0", "0.9.9"))
        self.assertTrue(update.is_newer("v0.12.0", "0.11.2"))
        self.assertTrue(update.is_newer("1.0", "0.99.99"))
        self.assertFalse(update.is_newer("0.11.2", "0.11.2"))
        self.assertFalse(update.is_newer("0.11.2-beta", "0.11.2"))
        self.assertFalse(update.is_newer("0.11", "0.11.0"))

    def test_the_newest_release_that_isnt_a_draft(self):
        releases = [{"tag_name": "v0.9.0", "body": "old"}, {"tag_name": "v0.13.0", "draft": True},
                    {"tag_name": "v0.12.0", "body": "new", "prerelease": True, "html_url": "page"},
                    {"tag_name": ""}]
        self.assertEqual(update.newest(releases),
                         {"version": "0.12.0", "tag": "v0.12.0", "notes": "new", "page": "page"})
        self.assertIsNone(update.newest([]))
        self.assertIsNone(update.newest({"message": "rate limited"}))


    def test_earlier_releases_newest_first(self):
        releases = [{"tag_name": "v1.0.0"}, {"tag_name": "v0.22.0", "prerelease": True},
                    {"tag_name": "v0.23.1", "prerelease": True}, {"tag_name": "v0.21.0", "draft": True},
                    {"tag_name": "v1.0.1"}]
        out = update.earlier(releases, "1.0.0")
        self.assertEqual([r["version"] for r in out], ["0.23.1"])  # none before OLDEST_TO_GO_BACK_TO
        self.assertTrue(out[0]["prerelease"])
        self.assertEqual(update.earlier(None, "1.0.0"), [])


if __name__ == "__main__":
    unittest.main()
