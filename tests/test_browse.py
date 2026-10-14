import os
import sys
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from paattu import browse, cli  # noqa: E402

VIDEO = {
    "videoId": "0G2VxhV_gXM",
    "title": {"runs": [{"text": "Premam Malare Video Song | Rajesh Murugesan | Vijay Yesudas"}]},
    "ownerText": {"runs": [{"text": "Anwar Rasheed Entertainment Official"}]},
    "lengthText": {"simpleText": "5:14"},
    "viewCountText": {"simpleText": "156,247,155 views"},
}
LOCKUP = {
    "contentId": "PLwNJ6jKo9IIbuuwqjBkcgV-yLGez8rtL4",
    "contentType": "LOCKUP_CONTENT_TYPE_PLAYLIST",
    "contentImage": {"collectionThumbnailViewModel": {"primaryThumbnail": {"thumbnailViewModel": {
        "image": {"sources": [{"url": "https://i.ytimg.com/vi/x/hq720.jpg?a", "width": 360},
                              {"url": "https://i.ytimg.com/vi/x/hq720.jpg?b", "width": 720}]},
        "overlays": [{"thumbnailOverlayBadgeViewModel": {"thumbnailBadges": [
            {"thumbnailBadgeViewModel": {"text": "7 videos"}}]}}]}}}},
    "metadata": {"lockupMetadataViewModel": {
        "title": {"content": "Premam malayalam songs"},
        "metadata": {"contentMetadataViewModel": {"metadataRows": [
            {"metadataParts": [{"text": {"content": "Dhananjayan A"}}, {"text": {"content": "Playlist"}}]}]}}}},
}
CHANNEL = {
    "channelId": "UCG9zrUjlsWGbxhPYps16_ew",
    "title": {"simpleText": "Chitra"},
    "thumbnail": {"thumbnails": [{"url": "//yt3.ggpht.com/a=s88", "width": 88}, {"url": "//yt3.ggpht.com/a=s176", "width": 176}]},
    "videoCountText": {"simpleText": "11.8K subscribers"},
    "subscriberCountText": {"simpleText": "@chitra"},
}


class YouTubeResults(unittest.TestCase):
    def test_video(self):
        t = browse._yt_video(VIDEO)
        self.assertEqual((t["id"], t["duration"], t["views"]), ("0G2VxhV_gXM", 314, 156247155))
        self.assertEqual(t["channel"], "Anwar Rasheed Entertainment Official")
        self.assertIsNone(browse._yt_video({**VIDEO, "lengthText": None}))  # live

    def test_playlist(self):
        p = browse._yt_playlist("lockupViewModel", LOCKUP)
        self.assertEqual((p["type"], p["id"], p["count"]), ("playlist", LOCKUP["contentId"], 7))
        self.assertEqual(p["subtitle"], "Dhananjayan A · 7 videos")
        self.assertEqual(p["art"], "https://i.ytimg.com/vi/x/hq720.jpg?b")
        self.assertEqual(p["artKey"], "youtube.playlist." + LOCKUP["contentId"])
        self.assertIsNone(browse._yt_playlist("lockupViewModel", {**LOCKUP, "contentId": "RDCLAK5uy_x"}))

    def test_channel(self):
        c = browse._yt_channel(CHANNEL)
        self.assertEqual((c["type"], c["title"], c["subtitle"]), ("artist", "Chitra", "11.8K subscribers"))
        self.assertEqual(c["art"], "https://yt3.ggpht.com/a=s176")

    def test_walk_finds_items_and_the_next_page(self):
        page = {"contents": [{"itemSectionRenderer": {"contents": [{"videoRenderer": VIDEO}, {"channelRenderer": CHANNEL}]}},
                             {"continuationItemRenderer": {"continuationEndpoint": {"continuationCommand": {"token": "T"}}}}]}
        items, tokens = [], []
        browse._yt_walk(page, items, tokens)
        self.assertEqual([k for k, _ in items], ["videoRenderer", "channelRenderer"])
        self.assertEqual(tokens, ["T"])


class OtherSites(unittest.TestCase):
    def test_jiosaavn_album_and_artist(self):
        album = browse.jiosaavn_collection({
            "id": "1234", "title": "Premam", "subtitle": "Rajesh Murugesan", "type": "album", "year": "2015",
            "language": "malayalam", "perma_url": "https://www.jiosaavn.com/album/premam/abc",
            "image": "https://c.saavncdn.com/665/Premam-Malayalam-2015-150x150.jpg", "more_info": {"song_count": "9"}})
        self.assertEqual((album["subtitle"], album["count"], album["language"]), ("Rajesh Murugesan · 2015", 9, "Malayalam"))
        self.assertEqual(album["art"], "https://c.saavncdn.com/665/Premam-Malayalam-2015-500x500.jpg")
        artist = browse.jiosaavn_collection({"id": "455", "name": "K. S. Chithra", "type": "artist", "role": "Artist",
                                             "image": "https://c.saavncdn.com/artists/Chithra_50x50.jpg"})
        self.assertEqual((artist["subtitle"], artist["art"]), ("Singer", "https://c.saavncdn.com/artists/Chithra_500x500.jpg"))
        self.assertIsNone(browse.jiosaavn_collection({"id": "1", "type": "album"}))

    def test_soundcloud(self):
        user = browse.soundcloud_collection({"kind": "user", "id": 7, "username": "Masala Coffee", "followers_count": 1200,
                                             "permalink_url": "https://soundcloud.com/masalacoffee",
                                             "avatar_url": "https://i1.sndcdn.com/avatars-x-large.jpg"})
        self.assertEqual((user["type"], user["subtitle"]), ("artist", "1.2K followers"))
        self.assertEqual(user["art"], "https://i1.sndcdn.com/avatars-x-t500x500.jpg")
        sets = {"kind": "playlist", "id": 9, "title": "Live", "track_count": 6, "user": {"username": "Masala Coffee"},
                "permalink_url": "https://soundcloud.com/masalacoffee/sets/live"}
        self.assertEqual(browse.soundcloud_collection({**sets, "is_album": True})["type"], "album")
        self.assertEqual(browse.soundcloud_collection(sets)["type"], "playlist")
        self.assertIsNone(browse.soundcloud_collection({**sets, "track_count": 0}))
        track = browse.soundcloud_track({"permalink_url": "https://soundcloud.com/a/b", "title": "Malare cover",
                                         "user": {"username": "a"}, "duration": 200400})
        self.assertEqual((track["id"], track["duration"], track["site"]), ("soundcloud.com_a_b", 200, "soundcloud"))
        self.assertIsNone(browse.soundcloud_track({"permalink_url": "https://soundcloud.com/a/c", "title": "x",
                                                   "policy": "SNIP"}))


class Merging(unittest.TestCase):
    SAAVN = {"id": "jiosaavn.com_song_malare_x", "site": "jiosaavn", "title": "Malare", "movie": "Premam"}
    TUBE = {"id": "AAAAAAAAAAA", "site": "youtube", "title": "Malare", "movie": "Premam"}
    OTHER = {"id": "BBBBBBBBBBB", "site": "youtube", "title": "Malare cover", "movie": ""}
    CLOUD = {"id": "soundcloud.com_a_b", "site": "soundcloud", "title": "Malare lofi", "movie": ""}

    def test_keys(self):
        self.assertEqual(browse.result_key(self.SAAVN), browse.result_key(self.TUBE))
        self.assertNotEqual(browse.result_key({"type": "album", "site": "jiosaavn", "id": "1"}),
                            browse.result_key({"type": "album", "site": "soundcloud", "id": "1"}))

    def test_interleave(self):
        seen = set()
        out = browse.interleave([[self.SAAVN], [self.TUBE, self.OTHER], [self.CLOUD]], seen)
        self.assertEqual([t["id"] for t in out], [self.SAAVN["id"], self.CLOUD["id"], self.OTHER["id"]])
        self.assertEqual(browse.interleave([[self.OTHER, self.CLOUD]], seen), [])

    def test_short_counts(self):
        self.assertEqual([browse._short(n) for n in (999, 1000, 1200, 12443, 12443303)], ["999", "1K", "1.2K", "12K", "12M"])

    def test_cli(self):
        args = cli.build_parser().parse_args(["browse", "play", "--index", "2", "--title", "Premam", "--", "-abcdefghij", "x"])
        self.assertEqual((args.ids, args.index, args.title), (["-abcdefghij", "x"], 2, "Premam"))
        with self.assertRaises(ValueError):
            cli._browse_item('{"type": "song"}')


if __name__ == "__main__":
    unittest.main()
