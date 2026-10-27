"""Your music in numbers, from the play history: how much you listened, what
you played most, when, how often you skip, and a few titles earned along
the way (quirks). The app's stats.dart does the same; tests/stats_cases.json
holds cases both run.
"""

import time

from .history import counted, song_identity
from .radio import song_language, themes

DAY = 86400


def music_stats(plays, track, now, days=None, favourites=(), hour_of=None):
    """The numbers for the last days (None: all of it). plays can be
    History.signals (songs taken out of the radio count as such). hour_of
    gives a play's hour of the day, 0-23 (local time when not given)."""
    hour_of = hour_of or (lambda at: time.localtime(at).tm_hour)
    since = now - days * DAY if days else 0
    loved = {song_identity(s) for s in favourites}
    out = {"plays": 0, "skips": 0, "removed": 0, "minutes": 0, "songs": 0, "artists": 0, "streak": 0,
           "favourite_plays": 0, "hours": [0] * 24, "top_songs": [], "top_artists": [], "top_films": [],
           "themes": {}, "languages": {}}
    songs, artists, films, titles, days_played = {}, {}, {}, {}, set()
    for play in plays:
        at = int(play.get("at") or 0)
        if at < since:
            continue
        if play.get("removed"):
            out["removed"] += 1
            continue
        out["minutes"] += int(play.get("heard") or 0)
        if not counted(play):
            out["skips"] += 1
            continue
        song = track(play.get("id") or "") or {"id": play.get("id") or ""}
        key = song_identity(song)
        out["plays"] += 1
        songs[key] = songs.get(key, 0) + 1
        titles.setdefault(key, song.get("title") or song.get("id") or "")
        if key in loved:
            out["favourite_plays"] += 1
        for credit in (song.get("credits") or [])[:4]:
            name = str(credit).strip()
            if name:
                artists[name] = artists.get(name, 0) + 1
        film = (song.get("movie") or "").strip()
        if film:
            films[film] = films.get(film, 0) + 1
        for theme in themes(song):
            out["themes"][theme] = out["themes"].get(theme, 0) + 1
        language = song_language(song)
        if language:
            out["languages"][language] = out["languages"].get(language, 0) + 1
        out["hours"][hour_of(at)] += 1
        days_played.add(at // DAY)
    out["minutes"] //= 60
    out["songs"], out["artists"] = len(songs), len(artists)
    out["top_songs"] = _top(songs, name=titles.get)  # by song: two of one title stay two
    out["top_artists"] = _top(artists)
    out["top_films"] = _top(films)
    run = 0
    for day in sorted(days_played):
        run = run + 1 if day - 1 in days_played else 1
        out["streak"] = max(out["streak"], run)
    return out


def _top(counts, count=5, name=str):
    rows = sorted(counts.items(), key=lambda kv: (-kv[1], name(kv[0]).lower()))[:count]
    return [[name(key), n] for key, n in rows]


THEME_TITLES = {
    "love": ("Hopeless romantic", "love songs"),
    "sad": ("Professional heartbreaker", "sad songs"),
    "dance": ("Kuthu machine", "songs to dance to"),
    "devotional": ("Devout ears", "devotional songs"),
    "calm": ("Zen master", "calm melodies"),
    "wedding": ("Wedding DJ in waiting", "wedding songs"),
    "festival": ("Festival spirit", "festival songs"),
    "rap": ("Mic dropper", "rap"),
}


def quirks(stats):
    """The titles your listening earned: [[title, why]], most telling first."""
    out = []
    plays, skips = stats["plays"], stats["skips"]
    if not plays:
        return out
    if stats["top_songs"] and stats["top_songs"][0][1] >= 5:
        name, n = stats["top_songs"][0]
        out.append(["Stuck on repeat", "%s, %d times. It should start paying rent" % (name, n)])
    if stats["top_artists"] and stats["top_artists"][0][1] * 3 >= plays and plays >= 5:
        name, n = stats["top_artists"][0]
        out.append(["%s superfan" % name, "in %d%% of your songs" % _percent(n, plays)])
    if stats["themes"]:
        theme, n = sorted(stats["themes"].items(), key=lambda kv: (-kv[1], kv[0]))[0]
        if n * 5 >= plays:
            title, what = THEME_TITLES[theme]
            out.append([title, "%d%% %s" % (_percent(n, plays), what)])
    peak = max(range(24), key=lambda h: (stats["hours"][h], -h))
    out.append(list(_hour_title(peak)))
    rate = skips / (plays + skips)
    if rate >= 0.4:
        out.append(["Itchy skip finger", "skipped %d%% of songs within half a minute" % _percent(rate, 1)])
    elif rate <= 0.1 and plays >= 10:
        out.append(["Patient listener", "skipped only %d%% of songs" % _percent(rate, 1)])
    fresh = stats["songs"] / plays
    if plays >= 10 and fresh >= 0.7:
        out.append(["Explorer", "%d different songs in %d plays" % (stats["songs"], plays)])
    elif plays >= 10 and fresh <= 0.3:
        out.append(["Creature of habit", "%d songs, %d plays" % (stats["songs"], plays)])
    if stats["favourite_plays"] * 2 >= plays and plays >= 5:
        out.append(["Loyal to the favourites", "%d%% of your plays" % _percent(stats["favourite_plays"], plays)])
    if stats["streak"] >= 7:
        out.append(["Unbroken", "music %d days in a row" % stats["streak"]])
    if stats["minutes"] >= 150:
        out.append(["Feature-length", "%d minutes: %d films' worth" % (stats["minutes"], stats["minutes"] // 150)])
    if stats["removed"] >= 3:
        out.append(["Picky DJ", "took %d songs out of the radio" % stats["removed"]])
    return out


def _percent(part, whole):
    """part of whole as a whole percentage, a half rounded up (as Dart does)."""
    return int(part * 100 / whole + 0.5)


def _hour_title(hour):
    if hour < 5:
        return "Midnight philosopher", "you play most around %s" % _clock(hour)
    if hour < 9:
        return "Early bird with headphones", "you play most around %s" % _clock(hour)
    if hour < 17:
        return "Daytime groover", "you play most around %s" % _clock(hour)
    if hour < 21:
        return "Sunset crooner", "you play most around %s" % _clock(hour)
    return "Night owl", "you play most around %s" % _clock(hour)


def _clock(hour):
    return "%d %s" % (hour % 12 or 12, "AM" if hour < 12 else "PM")
