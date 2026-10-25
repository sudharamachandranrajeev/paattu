"""A made-up Paattu library (songs, films, singers and labels that don't exist)
and drawn covers, for run.sh. XDG_* point into its work folder."""
import colorsys
import json
import math
import subprocess

from paattu import library, paths

SONGS = [
    ('Kaayal Kaattil', 'Kaayalkara', 'Anjana Menon', 'Hari Prasad', 'Malayalam'),
    ('Nilaavin Theeram', 'Neelaraavu', 'Rahul Nair', 'Sreeram Varma', 'Malayalam'),
    ('Mazhamegham Pole', 'Kaayalkara', 'Devika Pillai', 'Hari Prasad', 'Malayalam'),
    ('Ponnolam', 'Ponnambalam Days', 'Arjun Menon', 'Nikhil Das', 'Malayalam'),
    ('Thira Paadum', 'Neelaraavu', 'Kavya Raghav', 'Sreeram Varma', 'Malayalam'),
    ('Vaaka Pookkum Neram', 'Mazhavillu Express', 'Anjana Menon', 'Nikhil Das', 'Malayalam'),
    ('Chandana Kaatte', 'Ponnambalam Days', 'Vineeth Kumar', 'Nikhil Das', 'Malayalam'),
    ('Akale Oru Theeram', 'Mazhavillu Express', 'Devika Pillai', 'Hari Prasad', 'Malayalam'),
    ('Ilam Thennal Vazhi', 'Kaayalkara', 'Rahul Nair', 'Hari Prasad', 'Malayalam'),
    ('Minnaminni', 'Neelaraavu', 'Meera Krishnan', 'Sreeram Varma', 'Malayalam'),
    ('Varnachirakukal', 'Mazhavillu Express', 'Arjun Menon', 'Nikhil Das', 'Malayalam'),
    ('Kuyil Paadum Raavil', 'Ponnambalam Days', 'Kavya Raghav', 'Nikhil Das', 'Malayalam'),
    ('Nila Kaigal', 'Thendral Theru', 'Arun Selvam', 'Vikram Sundar', 'Tamil'),
    ('Mazhai Saaral Neram', 'Nilaa Nagaram', 'Priya Ganesh', 'Karthik Raja Mohan', 'Tamil'),
    ('Kaatril Oru Varisai', 'Thendral Theru', 'Meera Krishnan', 'Vikram Sundar', 'Tamil'),
    ('Vaanam Thodum', 'Iravu Express', 'Surya Narayan', 'Karthik Raja Mohan', 'Tamil'),
    ('Pon Maalai', 'Nilaa Nagaram', 'Priya Ganesh', 'Karthik Raja Mohan', 'Tamil'),
    ('Thendral Varum Vazhi', 'Thendral Theru', 'Arun Selvam', 'Vikram Sundar', 'Tamil'),
    ('Kadal Alai Osai', 'Iravu Express', 'Lakshmi Bala', 'Anand Ravi', 'Tamil'),
    ('Oru Naal Kanavil', 'Nilaa Nagaram', 'Surya Narayan', 'Karthik Raja Mohan', 'Tamil'),
    ('Megam Koodum', 'Iravu Express', 'Lakshmi Bala', 'Anand Ravi', 'Tamil'),
    ('Iravin Nizhal Pol', 'Thendral Theru', 'Priya Ganesh', 'Vikram Sundar', 'Tamil'),
    ('Pookkal Pesum Mozhi', 'Iravu Express', 'Arun Selvam', 'Anand Ravi', 'Tamil'),
    ('Vizhiyil Kavithai', 'Nilaa Nagaram', 'Meera Krishnan', 'Karthik Raja Mohan', 'Tamil'),
]


def tid(i):
    return "pTtDemo%04d" % (i + 1)  # 11 characters, shaped like a YouTube id


QUEUE = [1, 15, 9, 20, 4, 23, 10, 18]


def main():
    tracks = {}
    for i, (title, movie, singer, composer, lang) in enumerate(SONGS):
        tracks[tid(i)] = {"id": tid(i), "rawTitle": title, "title": title, "movie": movie,
                          "credits": [singer, composer], "kind": "song",
                          "channel": "Kaayal Records" if lang == "Malayalam" else "Thendral Audio",
                          "language": lang, "duration": 200 + (i * 37) % 140}

    def pl(pid, title, songs, owner="", lang="", local=False):
        return {"id": pid, "title": title, "rawTitle": title, "owner": owner,
                "ownerName": "You" if local else ("Kaayal Records" if lang == "Malayalam" else "Thendral Audio"),
                "language": lang, "saved": True, **({"local": True} if local else {}),
                "tracks": [tid(i) for i in songs], "count": len(songs),
                "created": "2026-10-0%dT10:00:00Z" % (songs[0] % 9 + 1)}

    pls = [
        pl("PLdemoMonsoonMelodies", "Monsoon Melodies", [2, 7, 0, 9, 4, 11, 5], "UCdemoKaayal", "Malayalam"),
        pl("PLdemoKaayalkara", "Kaayalkara (Full Album)", [0, 2, 8], "UCdemoKaayal", "Malayalam"),
        pl("PLdemoMalayalamHits", "Malayalam Hits 2026", list(range(11, -1, -1)), "UCdemoKaayal", "Malayalam"),
        pl("PLdemoTheruJukebox", "Thendral Theru Jukebox", [12, 14, 17, 21], "UCdemoThendral", "Tamil"),
        pl("PLdemoTamilMelodies", "Tamil Melodies", list(range(12, 24)), "UCdemoThendral", "Tamil"),
        pl("PLdemoLateNightTamil", "Late Night Tamil", [18, 20, 15, 23], "UCdemoThendral", "Tamil"),
        pl(library.FAVOURITES, "Favourites", [1, 13, 4, 16, 9, 22], local=True),
        pl(library.SAVED, "Saved songs", [6, 19, 3], local=True),
        pl("paattu-demo0001", "Night drive", QUEUE, local=True),
        pl("paattu-demo0002", "Rain songs", [2, 13, 7, 21, 5], local=True),
    ]
    data = {
        "version": 1,
        "users": {
            "UCdemoKaayal": {"id": "UCdemoKaayal", "handle": "@KaayalRecords", "name": "Kaayal Records",
                             "language": "Malayalam", "saveAll": True,
                             "playlists": ["PLdemoMonsoonMelodies", "PLdemoKaayalkara", "PLdemoMalayalamHits"]},
            "UCdemoThendral": {"id": "UCdemoThendral", "handle": "@ThendralAudio", "name": "Thendral Audio",
                               "language": "Tamil", "saveAll": True,
                               "playlists": ["PLdemoTheruJukebox", "PLdemoTamilMelodies", "PLdemoLateNightTamil"]},
        },
        "playlists": {p["id"]: p for p in pls},
        "tracks": tracks,
        "removed": {},
        "mixes": [
            {"id": "mix-malayalam", "title": "Malayalam mix", "sources": [{"type": "language", "id": "Malayalam"}]},
            {"id": "mix-tamil", "title": "Tamil mix", "sources": [{"type": "language", "id": "Tamil"}]},
            {"id": "mix-rainy", "title": "Rainy evenings", "sources": [
                {"type": "playlist", "id": "paattu-demo0002"}, {"type": "playlist", "id": "PLdemoMonsoonMelodies"}]},
        ],
    }
    library.save(data)

    # Covers: a gradient, a glowing sun or moon and hills, each in its own hue.
    def cover(path, i):
        path.parent.mkdir(parents=True, exist_ok=True)
        hue = (i * 47 + 330) % 360
        def hx(h, l, s):
            r, g, b = colorsys.hls_to_rgb((h % 360) / 360, l, s)
            return "#%02x%02x%02x" % (int(r * 255), int(g * 255), int(b * 255))
        top, bottom, glow = hx(hue, 0.55, 0.65), hx(hue + 40, 0.22, 0.7), hx(hue + 200, 0.75, 0.9)
        cx, cy = 90 + (i % 5) * 43, 108 + (i % 3) * 22
        hills = []
        for layer in range(3):
            y = 223 + layer * 43
            pts = " ".join("%d,%d" % (x, y - 22 * math.sin(x / 360 * 3.14159 * (2 + layer) + i))
                           for x in range(0, 361, 12))
            hills += ["-fill", "rgba(0,0,0,%.2f)" % (0.18 + layer * 0.12),
                      "-draw", "polygon %s 360,360 0,360" % pts]
        subprocess.run(["magick", "-size", "360x360", "gradient:%s-%s" % (top, bottom),
                        "(", "-size", "360x360", "xc:none", "-fill", glow, "-draw",
                        "circle %d,%d %d,%d" % (cx, cy, cx + 32, cy), "(", "+clone", "-blur", "0x26", ")",
                        "+swap", "-compose", "over", "-composite", ")", "-compose", "screen", "-composite",
                        "-compose", "over", *hills, "-quality", "88", str(path)], check=True)

    for i in range(len(SONGS)):
        cover(paths.art_path("v", tid(i)), i)
    for p in pls:
        first = SONGS.index(next(s for s in SONGS if s[0] == tracks[p["tracks"][0]]["title"]))
        cover(paths.art_path("p", p["id"]), first)
    cover(paths.art_path("u", "UCdemoKaayal"), 3)
    cover(paths.art_path("u", "UCdemoThendral"), 16)
    print(json.dumps([tid(i) for i in QUEUE]))


main()
