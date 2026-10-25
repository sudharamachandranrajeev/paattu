"""The charts (tests/chart_cases.json, shared with the app)."""

import json
import pathlib
import unittest

from paattu import charts

CASES = json.loads((pathlib.Path(__file__).parent / "chart_cases.json").read_text())


class ChartsTest(unittest.TestCase):
    def test_youtube_charts(self):
        self.assertEqual(charts.youtube_charts(CASES["youtube"]), CASES["youtubeCharts"])

    def test_where_a_charts_songs_are(self):
        for case in CASES["sources"]:
            found = charts.sources_of(case["kind"], case["language"], CASES["saavn"], CASES["youtubeCharts"])
            self.assertEqual(found, case, case)

    def test_merged(self):
        merge = CASES["merge"]
        self.assertEqual([s["id"] for s in charts.merge(merge["lists"], merge["avoid"])], merge["songs"])


if __name__ == "__main__":
    unittest.main()
