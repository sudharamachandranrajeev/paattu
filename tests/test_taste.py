"""What you play shapes what comes next (tests/taste_cases.json, shared with the app)."""

import json
import pathlib
import unittest

from paattu import history, radio

CASES = json.loads((pathlib.Path(__file__).parent / "taste_cases.json").read_text())
TRACKS = CASES["tracks"]


def key_of(tid):
    return history.song_identity(TRACKS.get(tid) or {"id": tid})


class TasteTest(unittest.TestCase):
    def test_fully_played(self):
        for case in CASES["fullyPlayed"]:
            self.assertEqual(history.fully_played(case["play"]), case["full"], case["play"])

    def test_turned_down(self):
        down = history.turned_down(CASES["plays"], key_of)
        ids = {p["id"] for p in CASES["plays"]}
        self.assertEqual(sorted(i for i in ids if i in down), CASES["turnedDown"])
        self.assertIn(key_of("b"), down)

    def test_taste(self):
        likes = history.taste(CASES["plays"], TRACKS.get, CASES["now"])
        self.assertEqual(sorted(likes), sorted(CASES["taste"]))
        for feature, value in CASES["taste"].items():
            self.assertAlmostEqual(likes[feature], value, places=5)

    def test_taste_order(self):
        order = CASES["order"]
        self.assertEqual([s["id"] for s in history.taste_order(order["songs"], CASES["likes"])], order["liked"])
        self.assertEqual([s["id"] for s in history.taste_order(order["songs"], order["skipping"])], order["skipped"])

    def test_loved_songs_join_the_radio(self):
        loved = CASES["loved"]
        top = [(TRACKS[tid], 1.0, 1) for tid in loved["top"]]
        picked = radio.loved_like(loved["station"], top, set(loved["avoid"]))
        self.assertEqual([s["id"] for s in picked], loved["picked"])

        def helping(ids):
            return [{"id": i, "title": i} for i in ids]

        self.assertEqual([s["id"] for s in radio.with_favourites(helping(loved["helping"]), picked)], loved["withLoved"])
        self.assertEqual([s["id"] for s in radio.with_favourites(helping(loved["short"]), picked)],
                         loved["shortWithLoved"])


if __name__ == "__main__":
    unittest.main()
