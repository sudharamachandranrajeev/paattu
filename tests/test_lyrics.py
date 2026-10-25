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
