import json
import os
import stat
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from paattu import depth  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent

SIDE = 50


def blob(x0, y0, x1, y1, inside=0.95, outside=0.02):
    """A guess with a solid square subject between (x0, y0) and (x1, y1)."""
    return [inside if x0 <= x < x1 and y0 <= y < y1 else outside for y in range(SIDE) for x in range(SIDE)]


class CleanMaskTest(unittest.TestCase):
    def test_a_clear_subject(self):
        alpha, (cx, cy), area = depth.clean_mask(blob(10, 20, 30, 40), SIDE)
        self.assertAlmostEqual(area, 0.16)
        self.assertAlmostEqual(cx, 0.4, places=1)
        self.assertAlmostEqual(cy, 0.6, places=1)
        self.assertEqual(alpha[25 * SIDE + 20], 1.0)
        self.assertEqual(alpha[5 * SIDE + 5], 0.0)

    def test_edges_fade_out(self):
        # A subject cut off by the bottom of the frame fades out before it, as
        # shown (bigger, and moving as the cover leans), so it never sticks out.
        alpha, _, _ = depth.clean_mask(blob(15, 30, 35, SIDE), SIDE)
        self.assertEqual(alpha[(SIDE - 1) * SIDE + 25], 0.0)
        self.assertEqual(alpha[(SIDE - 2) * SIDE + 25], 0.0)
        self.assertGreater(alpha[(SIDE - 3) * SIDE + 25], 0.0)
        self.assertLess(alpha[(SIDE - 3) * SIDE + 25], 1.0)
        self.assertEqual(alpha[40 * SIDE + 25], 1.0)
        # And before the cover's rounded corner.
        alpha, _, _ = depth.clean_mask(blob(0, 0, 30, 30), SIDE)
        self.assertEqual(alpha[2 * SIDE + 2], 0.0)
        self.assertEqual(alpha[0 * SIDE + 20], 0.0)
        self.assertEqual(alpha[10 * SIDE + 10], 1.0)

    def test_holes(self):
        # A patch inside the subject the model was unsure of is filled; one it
        # was sure is background (between an arm and the body) is kept.
        for inner, expected in ((0.3, 1.0), (0.02, 0.0)):
            guess = blob(10, 10, 40, 40)
            for y in range(23, 27):
                for x in range(23, 27):
                    guess[y * SIDE + x] = inner
            alpha, _, _ = depth.clean_mask(guess, SIDE)
            self.assertAlmostEqual(alpha[25 * SIDE + 25], expected, msg=inner)

    def test_no_good_guesses(self):
        self.assertIsNone(depth.clean_mask([0.3] * SIDE * SIDE, SIDE), "nothing stands out")
        self.assertIsNone(depth.clean_mask(blob(10, 10, 30, 30, inside=0.4), SIDE), "nothing is sure")
        self.assertIsNone(depth.clean_mask(blob(20, 20, 24, 24), SIDE), "a speck")
        self.assertIsNone(depth.clean_mask(blob(0, 0, SIDE, 46), SIDE), "most of the picture")
        haze = [0.5 + 0.45 * ((x + y) % 7 - 3) / 3 for y in range(SIDE) for x in range(SIDE)]
        self.assertIsNone(depth.clean_mask(haze, SIDE), "a haze")
        self.assertIsNone(depth.clean_mask(blob(10, 20, 30, 40)[:-1], SIDE), "the wrong size")
        self.assertIsNone(depth.clean_mask([float("nan")] + blob(10, 20, 30, 40)[1:], SIDE))


class ModelInputTest(unittest.TestCase):
    def test_scaled_by_the_brightest_then_normalised(self):
        values = depth.model_input(bytes([200, 100, 0, 0, 0, 0]))
        self.assertEqual(len(values), 6)
        self.assertAlmostEqual(values[0], (1 - 0.485) / 0.229)
        self.assertAlmostEqual(values[2], (0.5 - 0.456) / 0.224)
        self.assertAlmostEqual(values[5], (0 - 0.406) / 0.225)


class CoverClipTest(unittest.TestCase):
    def test_letterboxed_thumbnail(self):
        self.assertEqual(depth.cover_clip(480, 360), (105, 45, 375, 315))

    def test_square(self):
        self.assertEqual(depth.cover_clip(500, 500), (0, 0, 500, 500))


class DepthMapTest(unittest.TestCase):
    """The same cases as app/test/depth_test.dart (depth_cases.json): the app
    and the desktop Paattu give the same covers the same depth."""

    @classmethod
    def setUpClass(cls):
        cls.cases = json.loads((ROOT / "tests" / "depth_cases.json").read_text())

    def close(self, got, want):
        self.assertEqual(len(got), len(want))
        for a, b in zip(got, want):
            self.assertAlmostEqual(a, b, places=7)

    def test_regions(self):
        c = self.cases
        labels, colours = depth.regions(c["rgb"], c["side"])
        self.assertEqual(labels, c["labels"])
        for got, want in zip(colours, c["colours"]):
            self.close(got, want)

    def test_region_depth(self):
        c = self.cases
        got = depth.region_depth(c["rgb"], c["side"])
        self.close(got, c["regionDepth"])
        # The red disc in the middle is the nearest layer, the yellow along
        # the top edge the furthest, the blue around them between.
        side = c["side"]
        self.assertEqual(got[7 * side + 6], 1.0)
        self.assertLess(got[0], got[11 * side])
        self.assertLess(got[11 * side], 1.0)

    def test_a_flat_picture_is_all_one_depth(self):
        self.assertEqual(set(depth.region_depth([90, 90, 90] * 64, 8)), {0.5})

    def test_blur_and_shrink(self):
        b, s = self.cases["blur"], self.cases["shrink"]
        self.close(depth.blur(b["values"], b["side"], b["sigma"]), b["out"])
        self.close(depth.shrink(s["values"], s["side"], s["to"]), s["out"])

    def test_depth_map(self):
        c = self.cases
        for name, subject in (("withSubject", c["subject"]), ("withoutSubject", None)):
            want = c[name]
            d, shadow, lifted = depth.depth_map(c["rgb"], c["side"], subject)
            self.close(d, want["depth"])
            self.close(shadow, want["shadow"])
            self.close(lifted, want["subject"])
            self.close(depth.depth_centre(d, c["side"]), want["centre"])
            self.assertEqual(list(depth.depth_pixels(d, shadow, lifted)), want["pixels"])
        self.assertEqual(set(c["withoutSubject"]["shadow"]), {0.0})


class ShaderTest(unittest.TestCase):
    def test_the_apps_draw_the_cover_alike(self):
        def shared(path):
            text = (ROOT / path).read_text()
            return text[text.index("// shared from here"):text.index("// shared to here")]
        self.assertEqual(shared("plugin/shaders/DepthCover.frag"), shared("app/shaders/depth_cover.frag"))

    def test_the_built_shader_is_there(self):
        # Built with qsb (see the top of plugin/shaders/DepthCover.frag).
        built = ROOT / "plugin" / "DepthCover.frag.qsb"
        self.assertTrue(built.exists())
        self.assertGreaterEqual(built.stat().st_mtime, (ROOT / "plugin/shaders/DepthCover.frag").stat().st_mtime - 1)


class LiftTest(unittest.TestCase):
    """The pictures are made once per cover, by the helper uv runs."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        root = Path(self.tmp.name)
        self.cover = root / "cover.jpg"
        self.cover.write_bytes(b"jpeg")
        self.folder = root / "depth"
        self.runs = root / "runs"
        # A stand-in for uv: counts its runs and answers like the helper.
        self.uv = root / "uv"
        self.uv.write_text("#!/bin/sh\necho run >> '%s'\necho '{\"subject\": null}'\n" % self.runs)
        self.uv.chmod(self.uv.stat().st_mode | stat.S_IXUSR)

    def tearDown(self):
        self.tmp.cleanup()

    def lift(self):
        with mock.patch.object(depth, "find_uv", return_value=str(self.uv)), \
                mock.patch.object(depth, "MODEL", self.cover):
            return depth.lift(self.cover, self.folder, "song")

    def test_made_once(self):
        self.assertIsNone(self.lift()["subject"])
        self.assertIsNone(self.lift()["subject"])
        self.assertEqual(self.runs.read_text().count("run"), 1)
        self.assertIn("from", json.loads((self.folder / "song.json").read_text()))
        # A new cover is looked at again.
        self.cover.write_bytes(b"another jpeg")
        self.lift()
        self.assertEqual(self.runs.read_text().count("run"), 2)

    def test_without_uv(self):
        with mock.patch.object(depth, "find_uv", return_value=None):
            with self.assertRaisesRegex(depth.DepthError, "needs uv"):
                depth.lift(self.cover, self.folder, "song")

    def test_helper_failing(self):
        self.uv.write_text("#!/bin/sh\necho 'ModuleNotFoundError: no onnxruntime' >&2\nexit 1\n")
        with self.assertRaisesRegex(depth.DepthError, "no onnxruntime"):
            self.lift()


if __name__ == "__main__":
    unittest.main()
