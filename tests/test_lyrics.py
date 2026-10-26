"""A song's words and their English letters (tests/lyrics_cases.json and
tests/transliterate_cases.json, shared with the app)."""

import json
import pathlib
import tempfile
import unittest
from unittest import mock

from paattu import lyrics, transliterate

HERE = pathlib.Path(__file__).parent
CASES = json.loads((HERE / "lyrics_cases.json").read_text(encoding="utf-8"))
LETTERS = json.loads((HERE / "transliterate_cases.json").read_text(encoding="utf-8"))


class TransliterateTest(unittest.TestCase):
    def test_lines(self):
        for case in LETTERS["lines"]:
            self.assertEqual(transliterate.script_of(case["text"]), case["script"], case["text"])
            self.assertEqual(transliterate.transliterate(case["text"]), case["latin"], case["text"])

    def test_scripts(self):
        for case in LETTERS["scripts"]:
            self.assertEqual(transliterate.script_of(case["text"]), case["script"], case["text"])

    def test_english_stays_as_it_is(self):
        self.assertEqual(transliterate.transliterate("Kanmani anbodu"), "")


class LyricsTest(unittest.TestCase):
    def test_lrc(self):
        self.assertEqual([list(l) for l in lyrics.parse_lrc(CASES["lrc"]["text"])], CASES["lrc"]["lines"])

    def test_same_song(self):
        for case in CASES["sameSong"]:
            self.assertEqual(lyrics.same_song(case["name"], case["track"]), case["same"], case["name"])

    def test_queries(self):
        for case in CASES["queries"]:
            self.assertEqual(lyrics.queries(case["track"]), case["queries"])

    def test_best(self):
        for case in CASES["best"]:
            got = lyrics.best(case["found"], case["track"], case["language"])
            picked = None if not got else {"index": case["found"].index(got[0]), "timed": got[1]}
            self.assertEqual(picked, case["picked"], case)

    def test_youtube_music(self):
        self.assertEqual(lyrics.music_lyrics_id(CASES["youtubeNext"]), CASES["youtubeNextId"])
        self.assertEqual(list(lyrics.music_lyrics(CASES["youtubeBrowse"])), CASES["youtubeLyrics"])

    def test_youtube_music_timed(self):
        self.assertEqual(lyrics.music_timed_lyrics(CASES["youtubeTimedBrowse"]), CASES["youtubeTimedLrc"])
        self.assertIsNone(lyrics.music_timed_lyrics(CASES["youtubeBrowse"]))

    def test_shift(self):
        for case in CASES["shift"]:
            self.assertEqual(lyrics.lyric_shift(case["played"], case["reference"], case["fps"], case["most"]),
                             case["shift"], case["comment"])

    def _find(self, lrclib, songs, youtube, level=None):
        with mock.patch.object(lyrics, "_lrclib", side_effect=lrclib), \
                mock.patch.object(lyrics.ytmusic, "search", return_value=songs), \
                mock.patch.object(lyrics, "_from_youtube_music", side_effect=youtube):
            return lyrics.find({"id": "xXqgcm8dWyE", "title": "Malare", "movie": "Premam", "duration": 230},
                               "Malayalam", level)

    def test_words_timed_to_another_upload_are_lined_up(self):
        found = [{"trackName": "Malare", "duration": 200, "syncedLyrics": "[00:17.76]മലരേ"}]
        songs = [{"id": "songsongson", "title": "Malare", "duration": 201}]
        envelopes = {"xXqgcm8dWyE": CASES["shift"][0]["played"], "songsongson": CASES["shift"][0]["reference"]}

        def level(track):
            return [v for v in envelopes[track["id"]] for _ in range(5)]
        got = self._find(lambda q: found, songs, lambda vid: None, level)
        self.assertEqual((got["synced"], got["shift"], got["partial"]), ("[00:17.76]മലരേ", 3.0, False))
        # Nothing to line them up with: shown untimed.
        got = self._find(lambda q: found, songs, lambda vid: None)
        self.assertEqual((got["synced"], got["plain"]), ("", "മലരേ"))
        # YouTube Music's own timing, the song's length: taken as it is.
        timed = {"synced": "[00:01.00]a", "plain": "", "source": "YouTube Music"}
        songs = [{"id": "songsongson", "title": "Malare", "duration": 231}]
        got = self._find(lambda q: [], songs, lambda vid: dict(timed))
        self.assertEqual((got["synced"], got["shift"]), ("[00:01.00]a", 0))

    def test_a_find_made_while_a_site_was_down_is_partial(self):
        def busy(query):
            raise OSError("503")
        got = self._find(busy, [], lambda vid: {"synced": "", "plain": "x", "source": "YouTube Music"})
        self.assertTrue(got["partial"])
        got = self._find(busy, [], lambda vid: None)
        self.assertEqual((got["plain"], got["partial"]), ("", True))
        with self.assertRaises(RuntimeError):
            with mock.patch.object(lyrics.ytmusic, "search", side_effect=OSError("down")), \
                    mock.patch.object(lyrics, "_lrclib", side_effect=busy):
                lyrics.find({"id": "xXqgcm8dWyE", "title": "Malare"})

    def test_partial_finds_are_asked_again_after_an_hour(self):
        with tempfile.TemporaryDirectory() as tmp, mock.patch.object(lyrics, "FOLDER", pathlib.Path(tmp)), \
                mock.patch.object(lyrics, "find", return_value={"plain": "x", "partial": True}) as find:
            track = {"id": "aaaaaaaaaaa", "title": "Malare"}
            lyrics.lookup(track, now=1000)
            lyrics.lookup(track, now=1000 + 1800)
            self.assertEqual(find.call_count, 1)
            lyrics.lookup(track, now=1000 + 3700)
            self.assertEqual(find.call_count, 2)
            # What the last version kept (untimed finds, often) is looked up again.
            lyrics._file(track).write_text('{"fetched": 1000, "found": {"plain": "x"}}')
            lyrics.lookup(track, now=1001)
            self.assertEqual(find.call_count, 3)

    def test_shown(self):
        for case in CASES["shown"]:
            self.assertEqual(lyrics.shown(case["found"], case["latin"]), case["shows"])

    def test_misses_are_asked_again_after_three_days(self):
        with tempfile.TemporaryDirectory() as tmp, mock.patch.object(lyrics, "FOLDER", pathlib.Path(tmp)), \
                mock.patch.object(lyrics, "find", return_value=None) as find:
            track = {"id": "aaaaaaaaaaa", "title": "Malare"}
            self.assertIsNone(lyrics.lookup(track, now=1000))
            self.assertIsNone(lyrics.lookup(track, now=1000 + 86400))
            self.assertEqual(find.call_count, 1)
            find.return_value = {"synced": "", "plain": "x", "source": "LRCLIB"}
            self.assertEqual(lyrics.lookup(track, now=1000 + 4 * 86400)["plain"], "x")
            self.assertEqual(lyrics.lookup(track, now=10 ** 9)["plain"], "x")
            self.assertEqual(find.call_count, 2)


if __name__ == "__main__":
    unittest.main()
