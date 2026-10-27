"""What you play shapes what comes next (tests/taste_cases.json, shared with the app)."""

import contextlib
import json
import pathlib
import tempfile
import unittest
from unittest import mock

from paattu import cli, engine, history, radio

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

    def test_songs_taken_out_of_the_radio(self):
        case = CASES["removals"]
        h = history.History()
        h.data = json.loads(json.dumps(case["history"]))
        signals = h.signals
        self.assertEqual([[s["id"], bool(s.get("removed"))] for s in signals], case["signals"])
        self.assertEqual(sorted(history.turned_down(signals)), case["turnedDown"])
        likes = history.taste(signals, h.track, CASES["now"])
        self.assertEqual(sorted(likes), sorted(case["taste"]))
        for feature, value in case["taste"].items():
            self.assertAlmostEqual(likes[feature], value, places=5)
        self.assertEqual(sorted(history.shunned(signals, h.track, likes, CASES["now"])), case["shunned"])
        self.assertEqual(history.taste_ranking(signals, h.track, CASES["now"]), case["ranking"])
        forgiven = case["forgiven"]
        self.assertEqual(h.forgive(forgiven["feature"]), forgiven["count"])
        self.assertEqual([r["id"] for r in h.data["removed"]], forgiven["removed"])
        likes = history.taste(h.signals, h.track, CASES["now"])
        self.assertEqual(sorted(history.shunned(h.signals, h.track, likes, CASES["now"])), forgiven["shunned"])

    def test_removed_from_radio_keeps_the_song(self):
        h = history.History()
        h.removed_from_radio(TRACKS["a"], at=5)
        h.removed_from_radio({"id": ""}, at=6)
        self.assertEqual(h.data["removed"], [{"id": "a", "at": 5, "song": history.stored_track(TRACKS["a"])}])
        self.assertEqual(h.track("a")["title"], "Malare")
        h.data["removed"] = [{"id": "x", "at": i} for i in range(history.REMOVED_LIMIT)]
        h.removed_from_radio(TRACKS["b"], at=7)
        self.assertEqual(len(h.data["removed"]), history.REMOVED_LIMIT)
        self.assertIsNone(h.track("a"))
        self.assertEqual(h.data["removed"][-1]["id"], "b")

    def test_taken_out_songs_outlive_0_23(self):
        # 0.23.1 keeps tracks only for plays and made: the song in the entry
        # brings it back.
        with tempfile.TemporaryDirectory() as tmp:
            path = pathlib.Path(tmp) / "history.json"
            h = history.History(path)
            h.removed_from_radio(TRACKS["a"], at=5)
            h.data["tracks"] = {}
            h.save()
            self.assertEqual(history.History.load(path).track("a")["title"], "Malare")

    def test_affinity(self):
        case = CASES["affinity"]
        for tid, expected in case["themes"].items():
            self.assertEqual(radio.themes(case["tracks"][tid]), expected, tid)
        a = radio.Affinity(case["plays"], case["tracks"].get, CASES["now"], case["favourites"], case["playlists"])
        self.assertEqual({s["id"]: list(a.rank(s)) for s in case["songs"]}, case["ranks"])
        self.assertEqual([s["id"] for s in a.order(case["songs"])], case["order"])

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


class QueueEngine:
    def __init__(self, links, pos):
        self.entries = [{"filename": link} for link in links]
        self.pos = pos

    def __enter__(self):
        return self

    def __exit__(self, *exc):
        return False

    def get(self, prop, default=None):
        return {"playlist": self.entries, "playlist-pos": self.pos}.get(prop, default)

    def send(self, command):
        assert command[0] == "playlist-remove"
        del self.entries[command[1]]


class RadioRemoveTest(unittest.TestCase):
    """paattu radio remove N --entry LINK: a queue that moved meanwhile, or a
    second click, takes out that song and no other."""

    def remove(self, e, target, link):
        removed = []
        state = {"added": [x["filename"] for x in e.entries]}
        h = mock.Mock(removed_from_radio=removed.append)
        with mock.patch.object(engine, "Engine", lambda **kw: e), \
                mock.patch.object(radio, "session", lambda: contextlib.nullcontext(state)), \
                mock.patch.object(history, "editing", lambda: contextlib.nullcontext(h)), \
                mock.patch.object(cli, "_known", lambda data, tid: None):
            cli._radio_remove({}, target, mock.Mock(), link)
        return [t["id"] for t in removed]

    def test_the_song_named_even_if_the_queue_moved(self):
        links = ["https://www.youtube.com/watch?v=" + c * 11 for c in "abc"]
        e = QueueEngine(links, 0)
        self.assertEqual(self.remove(e, "2", links[1]), ["b" * 11])
        with self.assertRaises(cli.SourceError):  # the second click: gone already
            self.remove(e, "2", links[1])
        self.assertEqual(self.remove(e, "3", links[2]), ["c" * 11])
        self.assertEqual([x["filename"] for x in e.entries], [links[0]])


if __name__ == "__main__":
    unittest.main()
