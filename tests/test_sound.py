import json
import os
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from paattu import cli, config, engine, paths, sound  # noqa: E402

CASES = json.loads(Path(__file__).with_name("sound_cases.json").read_text(encoding="utf-8"))


class SharedCases(unittest.TestCase):
    """tests/sound_cases.json: the app's Dart tests check the same numbers."""

    def test_cases(self):
        for case in CASES:
            with self.subTest(case["case"]):
                self.assertEqual(sound.normalize(case["settings"]), case["normalized"])
                self.assertEqual(sound.gains(case["settings"]), case["gains"])
                self.assertEqual(sound.graph(case["settings"]), case["graph"])


class Curve(unittest.TestCase):
    def test_a_band_peaks_at_its_frequency(self):
        band = [(sound.FILTERS[9][1], 6.0)]  # 1 kHz
        self.assertAlmostEqual(sound.response(band, 1000), 6.0, places=2)
        self.assertLess(sound.response(band, 100), 0.3)

    def test_the_curve_lands_on_the_sliders(self):
        hard = {"all up": [12] * 15, "zigzag": [12 if i % 2 else -12 for i in range(15)],
                "one band": [12 if i == 7 else 0 for i in range(15)], "step": [-12] * 7 + [12] * 8,
                "melody": list(sound.PRESETS[1][2])}
        for name, bands in hard.items():
            with self.subTest(name):
                shape = sound.curve({"bands": bands})
                for f, want in zip(sound.BANDS, bands):
                    self.assertAlmostEqual(sound.response(shape, f), want, delta=0.5)
                for i in range(14):
                    halfway = (sound.BANDS[i] * sound.BANDS[i + 1]) ** 0.5
                    self.assertAlmostEqual(sound.response(shape, halfway), (bands[i] + bands[i + 1]) / 2, delta=1.2)

    def test_ten_bands_become_fifteen(self):
        old = [4, 3, 1, 0, -1, 0, 1.5, 2, 3, 3]
        shape = [("f=%d:t=o:w=1" % f, g) for f, g in zip(sound.OLD_BANDS, old)]
        new = sound.normalize({"bands": old})["bands"]
        self.assertEqual(len(new), 15)
        for f, level in zip(sound.BANDS, new):
            self.assertAlmostEqual(level, sound.response(shape, f), delta=0.051)
        # A built-in preset stays that preset, and your own presets come along.
        s = sound.normalize({"preset": "rock", "bands": [5, 3, -2, -3.5, -1.5, 1.5, 3.5, 4.5, 4.5, 4.5],
                             "presets": {"Car": old}})
        self.assertEqual(s["bands"], list(sound.PRESETS[6][2]))
        self.assertEqual(s["presets"]["Car"], new)

    def test_tiny_q_is_a_flat_gain(self):
        pre = [(sound.FILTERS[0][1], -6.0)]
        for f in (25, 100, 1000, 8000, 18000):
            self.assertAlmostEqual(sound.response(pre, f), -6.0, delta=0.05)

    def test_noclip_lowers_the_preamp_by_the_peak(self):
        s = {"on": True, "bands": [0] * 8 + [6] + [0] * 6}
        self.assertAlmostEqual(sound.gains(s)["pre"], -6.0, delta=0.2)
        self.assertEqual(sound.gains(dict(s, noclip=False))["pre"], 0.0)
        self.assertEqual(sound.gains({"on": True, "bands": [-3] * 15})["pre"], 0.0)  # cuts need no room

    def test_numbers(self):
        self.assertEqual([sound.fmt(x) for x in (2.5, 3.0, -0.0, -0.04, 1.25, -2.25)], ["2.5", "3", "0", "0", "1.3", "-2.2"])
        self.assertEqual(sound.graph({"on": False, "bands": [5] * 15}), "")
        self.assertEqual(sound.summary({"on": True, "preset": "melody", "bass": 2, "surround": 0.4, "speed": 1.25}),
                         "On · Melody · bass +2 dB · surround 40% · 1.25×")

    def test_surround_widens_and_makes_room(self):
        self.assertEqual([sound.widen({"surround": x}) for x in (0, 0.5, 1, 3)], [1.0, 1.75, 2.5, 2.5])
        self.assertIn("extrastereo@surround=m=1,", sound.graph({"on": True}))
        # A side panned hard one way comes out (1 + m) / 2 louder.
        self.assertAlmostEqual(sound.gains({"on": True, "surround": 1})["pre"], -4.9, delta=0.05)
        self.assertEqual(sound.gains({"on": True, "surround": 1, "noclip": False})["pre"], 0.0)


class FakeEngine:
    def __init__(self):
        self.props = {"speed": 1.0}
        self.sent = []

    def get(self, prop, default=None):
        return self.props.get(prop, default)

    def batch(self, commands):
        self.sent += commands
        for command in commands:
            if command[0] == "set_property":
                self.props[command[1]] = command[2]
        return [{"error": "success"} for _ in commands]


class Apply(unittest.TestCase):
    def test_only_what_changed(self):
        e = FakeEngine()
        s = {"on": True, "preset": "melody", "bands": list(sound.PRESETS[1][2]), "speed": 1.25}
        sound.apply(e, s)
        self.assertEqual([c[:2] for c in e.sent], [["af", "add"], ["set_property", "user-data/paattu/af"],
                                                   ["set_property", "speed"]])
        self.assertEqual(e.sent[0][2], sound.graph(s))
        e.sent = []
        sound.apply(e, s)
        self.assertEqual(e.sent, [])
        sound.apply(e, dict(s, on=False))
        self.assertEqual(e.sent[0], ["af", "remove", "@paattu"])


class Command(unittest.TestCase):
    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        for patch in (mock.patch.object(paths, "CONFIG", Path(tmp.name)),
                      mock.patch.object(paths, "CONFIG_FILE", Path(tmp.name) / "config.json"),
                      mock.patch.object(engine, "running", return_value=False)):
            patch.start()
            self.addCleanup(patch.stop)

    def run_cli(self, *argv):
        with mock.patch("sys.stdout"):
            self.assertEqual(cli.main(list(argv)), 0)
        return config.load()["sound"]

    def test_presets_bands_and_saving(self):
        s = self.run_cli("sound", "preset", "Bass", "boost")
        self.assertEqual((s["on"], s["preset"], s["bands"][2]), (True, "bass", 7.0))
        s = self.run_cli("sound", "set", "--band", "16k=+2", "--band", "1.6k=+1", "--band", "1=-1", "--preamp", "-3",
                         "--balance", "-0.2", "--surround", "0.35")
        self.assertEqual((s["bands"][14], s["bands"][9], s["bands"][0], s["preamp"], s["balance"], s["surround"], s["preset"]),
                         (2.0, 1.0, -1.0, -3.0, -0.2, 0.35, ""))
        s = self.run_cli("sound", "save", "Car")
        self.assertEqual((s["preset"], s["presets"]["Car"]), ("Car", s["bands"]))
        s = self.run_cli("sound", "set", "--bands=" + ",".join(str(b) for b in sound.PRESETS[1][2]))
        self.assertEqual(s["preset"], "melody")  # moved onto a preset's curve
        s = self.run_cli("sound", "delete", "car")
        self.assertEqual(s["presets"], {})
        s = self.run_cli("sound", "off")
        self.assertFalse(s["on"])

    def test_bad_input(self):
        with mock.patch("sys.stdout"), mock.patch("sys.stderr"):
            self.assertEqual(cli.main(["sound", "save", "Rock"]), 1)
            self.assertEqual(cli.main(["sound", "set", "--band", "3k=1"]), 1)
            self.assertEqual(cli.main(["sound", "preset", "nope"]), 1)
        self.assertEqual([cli._sound_band(k) for k in ("1", "15", "25", "1k", "1.6k", "16000")], [0, 14, 0, 8, 9, 14])


if __name__ == "__main__":
    unittest.main()
