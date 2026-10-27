"""Your music in numbers (tests/stats_cases.json, shared with the app)."""

import json
import pathlib
import unittest

from paattu import stats

CASES = json.loads((pathlib.Path(__file__).parent / "stats_cases.json").read_text())


def hour_of(at):
    return at // 3600 % 24


class StatsTest(unittest.TestCase):
    def test_runs(self):
        for run in CASES["runs"]:
            got = stats.music_stats(CASES["plays"], CASES["tracks"].get, CASES["now"], run["days"],
                                    CASES["favourites"], hour_of)
            self.assertEqual(got, run["stats"], run["days"])
            self.assertEqual(stats.quirks(got), run["quirks"], run["days"])

    def test_nothing_played(self):
        got = stats.music_stats([], CASES["tracks"].get, CASES["now"])
        self.assertEqual(got["plays"], 0)
        self.assertEqual(stats.quirks(got), [])

    def test_two_songs_of_one_title_stay_two(self):
        tracks = {"a": {"id": "a", "title": "Malare", "movie": "Premam"},
                  "b": {"id": "b", "title": "Malare", "movie": "Other"}}
        plays = [{"id": id, "at": 100 + i, "heard": 200, "length": 200} for i, id in enumerate("aaabb")]
        got = stats.music_stats(plays, tracks.get, 1000, hour_of=hour_of)
        self.assertEqual(got["top_songs"], [["Malare", 3], ["Malare", 2]])


if __name__ == "__main__":
    unittest.main()
