"""The rhythm behind Now Playing's cover (paattu/rhythm.py), the same as the
app's (tests/rhythm_cases.json)."""

import json
import math
import os
import pathlib
import shutil
import subprocess
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from paattu import rhythm  # noqa: E402

CASES = json.loads((pathlib.Path(__file__).parent / "rhythm_cases.json").read_text())


def kicks(seconds, rate):
    return [int((((i / rate) % 0.5 < 0.08) * 0.8 * math.sin(2 * math.pi * 55 * i / rate)
                 + 0.02 * math.sin(2 * math.pi * 3000 * i / rate)) * 32767) for i in range(int(seconds * rate))]


class RhythmTest(unittest.TestCase):
    def test_same_as_the_app(self):
        found = rhythm.analyse(kicks(CASES["seconds"], CASES["rate"]), CASES["rate"])
        for key in ("level", "punch"):
            self.assertEqual(len(found[key]), len(CASES[key]))
            for got, want in zip(found[key], CASES[key]):
                self.assertLessEqual(abs(got - want), 1, key)

    def test_beats_where_the_kick_hits(self):
        found = rhythm.analyse(kicks(10, rhythm.RATE), rhythm.RATE)
        for beat in range(1, 19):
            at = beat * 25
            self.assertGreater(max(found["punch"][at - 1:at + 3]), 150, beat)
            self.assertLess(max(found["punch"][at + 8:at + 21]), 40, beat)

    def test_silence(self):
        found = rhythm.analyse([0] * rhythm.RATE * 2, rhythm.RATE)
        self.assertEqual(set(found["punch"]), {0})

    @unittest.skipUnless(shutil.which("mpv") and shutil.which("ffmpeg"), "needs mpv and ffmpeg")
    def test_find_decodes_and_keeps(self):
        with tempfile.TemporaryDirectory() as folder:
            song = os.path.join(folder, "beat.m4a")
            subprocess.run(["ffmpeg", "-loglevel", "error", "-f", "lavfi", "-i", "sine=f=55:d=6",
                            "-c:a", "aac", song], check=True)
            found = rhythm.find(song, os.path.join(folder, "kept"), "beat")
            self.assertEqual(found["fps"], 50)
            self.assertGreater(len(found["level"]), 250)
            self.assertTrue(os.path.exists(os.path.join(folder, "kept", "beat.json")))
            self.assertEqual(rhythm.find("/nowhere", os.path.join(folder, "kept"), "beat")["level"], found["level"])


if __name__ == "__main__":
    unittest.main()
