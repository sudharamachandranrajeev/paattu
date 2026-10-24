"""ListenBrainz scrobbling and sync (tests/listenbrainz_cases.json, shared with the app)."""

import copy
import json
import pathlib
import tempfile
import unittest
from unittest import mock

from paattu import __version__, history, listenbrainz

CASES = json.loads((pathlib.Path(__file__).parent / "listenbrainz_cases.json").read_text())


def _versioned(listen):
    text = json.dumps(listen).replace('"VERSION"', json.dumps(__version__))
    return json.loads(text)


class ListenBrainzTest(unittest.TestCase):
    def test_listens(self):
        for case in CASES["listens"]:
            self.assertEqual(listenbrainz.listen(case["play"], case["song"], CASES["device"]),
                             _versioned(case["listen"]))

    def test_pending(self):
        data = copy.deepcopy(CASES["history"])
        got = [[play["id"], play["at"]] for play, _ in listenbrainz.pending(data)]
        self.assertEqual(got, CASES["pending"])

    def test_merge(self):
        data = copy.deepcopy(CASES["history"])
        found = [p for p in (listenbrainz.play_of(f, CASES["device"]) for f in CASES["fetched"]) if p]
        added = listenbrainz.merge(data, found)
        self.assertEqual([[p["id"], p["at"]] for p in data["plays"]], CASES["merged"])
        self.assertEqual([[p["id"], p["at"]] for p, _ in added], CASES["added"])
        self.assertEqual(data["tracks"]["d"], {"id": "d", "title": "D", "language": "Tamil"})
        d = next(p for p in data["plays"] if p["id"] == "d")
        self.assertEqual(d, {"id": "d", "at": 4500, "heard": 200, "length": 260, "from": "listenbrainz"})
        # Read again: nothing new.
        self.assertEqual(listenbrainz.merge(data, found), [])

    def test_state_made_once(self):
        data = {}
        device = listenbrainz.state(data)["device"]
        self.assertEqual(len(device), 12)
        self.assertEqual(listenbrainz.state(data), {"device": device, "sent": 0, "fetched": 0})

    def test_clear_keeps_state(self):
        h = history.History()
        h.data = copy.deepcopy(CASES["history"])
        h.clear()
        self.assertEqual(h.data["plays"], [])
        self.assertEqual(h.data["listenbrainz"]["sent"], 500)

    def test_sync(self):
        """Sends what's pending once, reads the rest back in."""
        with tempfile.TemporaryDirectory() as folder:
            path = pathlib.Path(folder) / "history.json"
            path.write_text(json.dumps(CASES["history"]))
            sent, asked = [], []

            def call(api_path, token, body=None, query=None):
                if body is not None:
                    sent.append(body)
                    return {"status": "ok"}
                asked.append(query)
                return {"payload": {"listens": CASES["fetched"] if query["min_ts"] == 0 else []}}

            with mock.patch.object(listenbrainz, "_call", call):
                added = listenbrainz.sync("token", "me", path)
                self.assertEqual([[p["id"], p["at"]] for p, _ in added], CASES["added"])
                self.assertEqual(sent[0]["listen_type"], "import")
                self.assertEqual([l["listened_at"] for l in sent[0]["payload"]], [1000, 3000, 7000])
                state = json.loads(path.read_text())["listenbrainz"]
                self.assertEqual((state["sent"], state["fetched"]), (7000, 9000))
                self.assertEqual(listenbrainz.sync("token", "me", path), [])
            self.assertEqual(len(sent), 1)
            self.assertEqual(asked[1]["min_ts"], max(0, 9000 - listenbrainz.OVERLAP))


if __name__ == "__main__":
    unittest.main()
