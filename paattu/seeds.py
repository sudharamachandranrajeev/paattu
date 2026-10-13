"""The South Indian starter library: Malayalam and Tamil labels and composers.

Every handle here was checked against YouTube on 2026-10-12. `paattu seed`
follows these users, lists their public playlists, and saves a few featured
ones per user (hits, jukeboxes, recent movie albums) so there is music to play
straight away. Everything else stays one click away in the app.
"""

import re

CURATED = [
    # Malayalam labels
    ("@Muzik247", "Malayalam", "label"),
    ("@saregamamalayalam", "Malayalam", "label"),
    ("@SonyMusicMalayalamOfficial", "Malayalam", "label"),
    ("@ManoramaFilmSongs", "Malayalam", "label"),
    ("@GOODWILLENTERTAINMENTS", "Malayalam", "label"),
    ("@east_coast", "Malayalam", "label"),
    ("@Satyam_Audios", "Malayalam", "label"),
    ("@millenniumaudios", "Malayalam", "label"),
    ("@MagicFramesMusic", "Malayalam", "label"),
    ("@wonderwallmedia", "Malayalam", "label"),
    ("@MangoMusicMalayalam", "Malayalam", "label"),
    ("@fridaymusiccompany", "Malayalam", "label"),
    ("@ThinkMusicMalayalam", "Malayalam", "label"),
    # Malayalam composers
    ("@SUSHINTDT", "Malayalam", "artist"),
    # Tamil labels
    ("@thinkmusicofficial", "Tamil", "label"),
    ("@SonyMusicSouthOfficial", "Tamil", "label"),
    ("@SaregamaTamil", "Tamil", "label"),
    ("@TseriesTamil", "Tamil", "label"),
    ("@divomusicofficial", "Tamil", "label"),
    ("@AdityaMusicTamil", "Tamil", "label"),
    ("@U1Records", "Tamil", "label"),
    ("@LahariMusicTamil", "Tamil", "label"),
    ("@zeemusicsouth", "Tamil", "label"),
    # Tamil composers and singers
    ("@ARRahman", "Tamil", "artist"),
    ("@AnirudhOfficial", "Tamil", "artist"),
    ("@ilaiyaraajaofficial", "Tamil", "artist"),
    ("@sidsrirammusic", "Tamil", "artist"),
]

LANGUAGES = ("Malayalam", "Tamil")

_GOOD = [
    (r"^popular uploads$", 6),
    (r"^latest uploads$", 2),
    (r"\bhits?\b|superhits?|super hits|chartbusters?", 4),
    (r"jukebox|non[\s-]?stop|back to back", 3),
    (r"evergreen|golden|classics?|all[\s-]?time|best of|top \d+|\btop\b", 3),
    (r"melod|romantic|love songs|feel good|trending|viral|latest|new release|20(?:2[4-9])", 2),
    (r"official (?:playlist|album|jukebox)|audio songs|video songs|full album", 2),
    (r"malayalam|tamil", 1),
]
_BAD = re.compile(
    r"trailer|teaser|bgm|background score|scene|comedy|interview|making|shorts|karaoke|instrumental|"
    r"devotional|christian|bhakti|ayyappa|murugan|krishna|amman|kids|nursery|podcast|dubbed|telugu|hindi|"
    r"kannada|bengali|marathi|punjabi|status|ringtone|reels",
    re.I)


def featured_score(title):
    """How much a playlist title sounds like a good place to start listening."""
    if _BAD.search(title):
        return -1
    return sum(weight for pattern, weight in _GOOD if re.search(pattern, title, re.I))


def pick_featured(playlists, count):
    """The best-scoring playlists, then the newest movie albums, up to count."""
    if count <= 0:
        return []
    scored = [(featured_score(p.get("rawTitle") or p.get("title", "")), i, p) for i, p in enumerate(playlists)]
    hits = [p for score, i, p in sorted(scored, key=lambda s: (-s[0], s[1])) if score >= 3]
    albums = [p for score, i, p in scored if 0 <= score < 3]  # channel order: newest first
    picked, seen = [], set()
    for p in hits[: max(1, count - 1)] + albums + hits:
        if p["id"] not in seen:
            picked.append(p)
            seen.add(p["id"])
        if len(picked) == count:
            break
    return picked
