"""YouTube Music's answers, the radio, the play history and the playlists made
for you: the same cases as app/test/made_test.dart (ytmusic_cases.json and
made_cases.json), so the desktop and the app agree."""

import datetime
import json
import os
import pathlib
import random
import sys
import tempfile
import unittest
from unittest import mock

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from paattu import history, made, radio, sources, ytmusic  # noqa: E402

HERE = pathlib.Path(__file__).resolve().parent
YTMUSIC = json.loads((HERE / "ytmusic_cases.json").read_text())
MADE = json.loads((HERE / "made_cases.json").read_text())

NOW = datetime.datetime(2026, 10, 15, 12, tzinfo=datetime.timezone.utc).timestamp()


def ago(days):
    return int(NOW - round(days * 86400))


def play(tid, days_ago, heard, length=240):
    return {"id": tid, "at": ago(days_ago), "heard": heard, "length": length}


def ids(songs):
    return [s["id"] for s in songs]


class YouTubeMusicTest(unittest.TestCase):
    def test_search(self):
        songs = ytmusic.search_songs(YTMUSIC["search"])
        self.assertEqual(songs, YTMUSIC["expect"]["search"])
        self.assertTrue(songs[0]["art"].endswith("=w544-h544-l90-rj"))

    def test_radio_and_its_next_helping(self):
        for key in ("next", "more"):
            songs, more = ytmusic.radio_page(YTMUSIC[key])
            self.assertEqual(songs, YTMUSIC["expect"][key]["songs"], key)
            self.assertEqual(more, YTMUSIC["expect"][key]["more"], key)

    def test_label_notes_give_the_film(self):
        song = ytmusic.radio_page(YTMUSIC["more"])[0][0]
        self.assertEqual(song["title"], "Irupathu Kodi")
        self.assertEqual(song["movie"], "Thullatha Manamum Thullum")


class MadeTest(unittest.TestCase):
    def test_periods(self):
        for case in MADE["period"]:
            day = datetime.date.fromisoformat(case["date"])
            self.assertEqual(made.period_key(case["kind"], day), case["key"], case)

    def test_describe(self):
        for case in MADE["describe"]:
            self.assertEqual(made.describe_phrases(case["text"]), case["phrases"], case["text"])

    def test_daily_mix(self):
        case = MADE["daily"]
        self.assertEqual(ids(made.daily_mix(case["familiar"], case["fresh"], size=case["size"])), case["ids"])

    def test_weighted_pick(self):
        rng = random.Random(7)
        heavy_in = 0
        for _ in range(200):
            picked = made.weighted_pick(list(range(20)), lambda n: 50 if n == 3 else 1, 5, rng)
            self.assertEqual(len(set(picked)), 5)
            heavy_in += 3 in picked
        self.assertGreater(heavy_in, 180)

    def test_describe_playlist_tops_up_from_the_radio(self):
        def song(tid, title):
            return {"id": tid, "title": title, "duration": 240, "kind": "audio"}

        found = {"Premam": [song("p1", "Malare"), song("p2", "Aluva Puzha")], "Ilaiyaraaja": [song("i1", "Ilaya Nila")]}
        radios = {"p1": ([song("p1", "Malare"), song("r1", "Kalippu")], None), "i1": ([song("r2", "Poongatru")], None)}
        with mock.patch.object(ytmusic, "search", side_effect=lambda q, limit=20: found.get(q, [])), \
                mock.patch.object(ytmusic, "radio", side_effect=lambda v, more=None: radios[v]):
            songs = made.describe_playlist("songs from Premam and Ilaiyaraaja", size=5)
        self.assertEqual(ids(songs), ["p1", "i1", "p2", "r1", "r2"])


class HistoryTest(unittest.TestCase):
    def test_counted(self):
        self.assertTrue(history.counted({"heard": 30, "length": 240}))
        self.assertFalse(history.counted({"heard": 29, "length": 240}))
        self.assertTrue(history.counted({"heard": 20, "length": 40}))
        self.assertFalse(history.counted({"heard": 29}))

    def test_top_songs(self):
        plays = [play("a", 1, 200), play("a", 2, 200), play("b", 20, 200), play("b", 21, 200), play("b", 22, 200),
                 play("c", 1, 200), play("c", 1, 5), play("c", 2, 5), play("c", 3, 5), play("old", 40, 200)]
        tracks = {tid: {"id": tid, "title": "Song " + tid} for tid in ("a", "b", "c", "old")}
        top = history.top_songs(plays, tracks.get, NOW)
        self.assertEqual([t[0]["id"] for t in top], ["a", "b"])
        self.assertEqual(top[0][2], 2)

    def test_skipped_and_heard(self):
        plays = [play("s", 1, 5), play("s", 2, 3), play("t", 1, 5), play("u", 0.1, 100)]
        self.assertEqual(history.skipped_often(plays, NOW), {"s"})
        self.assertEqual(history.heard_since(plays, NOW - 6 * 3600), {"u"})

    def test_round_trip(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = pathlib.Path(tmp) / "history.json"
            h = history.History(path)
            song = {"id": "abcdefghijk", "title": "Malare", "movie": "Premam", "_radio": True, "art": None}
            h.played(song, 120, length=240, at=NOW)
            self.assertEqual(h.plays, [{"id": "abcdefghijk", "at": int(NOW), "heard": 120, "length": 240}])
            self.assertEqual(h.track("abcdefghijk"), {"id": "abcdefghijk", "title": "Malare", "movie": "Premam"})
            h.set_made("daily", "2026-10-15", [song])
            self.assertEqual(h.made("daily")[0], "2026-10-15")
            h.save()
            again = history.History.load(path)
            self.assertEqual(again.plays, h.plays)
            self.assertEqual(ids(again.made("daily")[1]), ["abcdefghijk"])


class RadioTest(unittest.TestCase):
    def test_interleave(self):
        def song(tid, title, duration=240, kind="audio"):
            return {"id": tid, "title": title, "duration": duration, "kind": kind}

        lists = [[song("a1", "A"), song("a2", "B"), song("a3", "C")],
                 [song("b1", "A"), song("b2", "D", 3600), song("b3", "E"), song("b4", "F", 200, "trailer")]]
        avoid = {"c|"}
        self.assertEqual(ids(radio.interleave_songs(lists, avoid)), ["a1", "b3", "a2"])
        self.assertTrue({"a1", "a|", "a2", "b|", "b3", "e|"} <= avoid)

    def test_a_station_carries_on_and_leaves_out_what_was_heard(self):
        def song(tid, title):
            return {"id": tid, "site": "youtube", "title": title, "duration": 240, "kind": "audio"}

        station = song("AAAAAAAAAAA", "Station")
        pages = {
            ("AAAAAAAAAAA", None): ([station, song("BBBBBBBBBBB", "Two"), song("CCCCCCCCCCC", "Three")], "more-1"),
            ("AAAAAAAAAAA", "more-1"): ([song("DDDDDDDDDDD", "Four")], None),
            ("DDDDDDDDDDD", None): ([song("DDDDDDDDDDD", "Four"), song("EEEEEEEEEEE", "Five")], None),
        }
        h = history.History(pathlib.Path("/nonexistent/history.json"))
        h.played(song("CCCCCCCCCCC", "Three"), 200, at=NOW - 3600)
        r = radio.SongRadio(h)
        with mock.patch.object(ytmusic, "radio", side_effect=lambda v, more=None: pages[(v, more)]):
            first = r.next(station, [station], count=2, now=NOW)
            second = r.next(station, [station, *first], count=1, now=NOW)
        self.assertEqual(ids(first), ["BBBBBBBBBBB", "DDDDDDDDDDD"])
        self.assertEqual(ids(second), ["EEEEEEEEEEE"])


class SameSongTest(unittest.TestCase):
    def test_same_song(self):
        self.assertTrue(sources.same_song({"title": "Malare", "movie": "Premam", "duration": 230},
                                          {"title": "Malare", "movie": "Premam (Original)", "duration": 240}))
        self.assertFalse(sources.same_song({"title": "Malare", "movie": "Premam"}, {"title": "Malare", "movie": "Other"}))
        self.assertFalse(sources.same_song({"title": "Malare", "duration": 230}, {"title": "Malare", "duration": 300}))
        # Same title, no films and one length unknown: can't tell.
        self.assertFalse(sources.same_song({"title": "മലരേ"}, {"title": "മലരേ", "duration": 200}))
        self.assertTrue(sources.same_song({"title": "മലരേ", "movie": "Premam"}, {"title": "മലരേ", "movie": "Premam"}))


if __name__ == "__main__":
    unittest.main()
