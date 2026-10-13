"""Turn YouTube video titles from South Indian music labels into song metadata.

Label uploads follow a loose convention:

    Thalatherichavar - Video | Romancham | Sushin Shyam | Saregama Malayalam
    Vaathi Coming Video Song | Master | Thalapathy Vijay | Anirudh Ravichander
    Kanmani Anbodu Kadhalan (Lyric Video) | Guna | Kamal Haasan | Ilaiyaraaja
    Malare - Premam Song | Nivin Pauly | Sai Pallavi

clean_title() pulls out the song, the movie (or album), the remaining credits,
and what kind of upload it is (video, lyrical, audio, jukebox, ...).
"""

import re
import unicodedata

# Upload-type words that decorate a song name; removed from the title.
_DECORATIONS = [
    r"official\s+(?:full\s+)?(?:video|lyric(?:al)?\s+video|lyrics?|audio|music\s+video|song)(?:\s+song)?",
    r"full\s+video\s+songs?", r"full\s+songs?", r"full\s+video", r"video\s+songs?", r"song\s+video",
    r"lyric(?:al)?\s+(?:video\s+)?songs?", r"lyric(?:al)?\s+videos?", r"lyrics?", r"lyrical",
    r"audio\s+songs?", r"audio\s+jukebox", r"video\s+jukebox", r"jukebox", r"audio",
    r"promo\s+songs?", r"promo\s+video", r"music\s+video", r"video",
    r"lyrical\s*\+\s*karaoke(?:\s+video)?", r"karaoke\s+video",
    r"\d+k(?:\s*/\s*\d+k)?(?:\s+video)?", r"\d+\s*fps", r"hd", r"hq", r"hi-?res(?:\s+audio)?", r"\d+\s*-?bit",
    r"remastered", r"dolby\s+atmos", r"5\.1", r"exclusive",
    r"(?:malayalam|tamil)\s+(?:film\s+|movie\s+)?songs?", r"(?:malayalam|tamil)", r"(?:movie|film)\s+songs?",
    r"songs?",
]
_DECORATION_RE = re.compile(r"^(?:" + "|".join(_DECORATIONS) + r")$", re.I)
# The same words when they trail a song name: "Vaathi Coming Video Song".
_TRAILING_RE = re.compile(
    r"(?:[\s\-–—:|]+(?:" + "|".join(_DECORATIONS) + r"))+\s*$", re.I)
_BRACKETS_RE = re.compile(r"\s*[\(\[\{]([^\)\]\}]*)[\)\]\}]")
_SEPARATORS_RE = re.compile(r"\s*[|｜•]\s*|\s+//\s+")
_DASH_RE = re.compile(r"\s+[-–—]\s+")
_HASHTAG_RE = re.compile(r"(?:^|\s)#(\w+)", re.U)
# "Premam Song": a movie name followed by a bare "Song".
_BARE_SONG_RE = re.compile(r"^(.+?)\s+songs?$", re.I)
_NOT_A_MOVIE = {"video", "lyric", "lyrical", "audio", "full", "official", "title", "promo", "movie", "film",
                "theme", "8k", "4k", "hd", "fps", "malayalam", "tamil"}
_LEADING_NOISE_RE = re.compile(r"^(?:exclusive|new|latest|superhit|super hit)\s*[-–—:]\s*", re.I)
_SPACES_RE = re.compile(r"\s+")
# A segment that names itself as the song: "Kaathalae Kaathalae Video Song".
_VIDEO_SONG_RE = re.compile(r"\b(?:video|lyric(?:al)?(?:\s+video)?|full(?:\s+video)?)\s+songs?\s*$", re.I)

# Labels and channels whose names show up as a credit segment.
LABELS = {
    "saregama malayalam", "saregama tamil", "saregama south", "saregama", "saregama music",
    "sony music south", "sony music malayalam", "sony music india", "sony music",
    "think music", "think music india", "think music malayalam", "muzik247", "muzik 247",
    "divo", "divo music", "lahari music", "lahari music tamil", "t-series", "t-series tamil",
    "tseries tamil", "u1 records", "manorama music", "manorama music songs", "millennium audios",
    "goodwill entertainments", "satyam audios", "east coast", "zee music south", "zee music company",
    "aditya music", "aditya music tamil", "magic frames", "magic frames music", "friday music company",
    "wonderwall media", "mango music", "mango music malayalam", "sun music", "sun tv",
}

KINDS = ("video", "lyrical", "audio", "jukebox", "promo", "trailer", "karaoke", "cover", "live")


def _norm(text):
    return _SPACES_RE.sub(" ", unicodedata.normalize("NFKC", text or "")).strip()


def _strip_decorations(text):
    text = _norm(text)
    previous = None
    while previous != text:
        previous = text
        text = _TRAILING_RE.sub("", text).strip(" -–—:|,")
    return text


def upload_kind(raw):
    """What sort of upload a title describes."""
    t = raw.lower()
    if re.search(r"\b(?:trailer|teaser|first look|glimpse|making|bts|behind the scenes)\b", t):
        return "trailer"
    if re.search(r"\b(?:jukebox|non[\s-]?stop|back\s+to\s+back|audio songs|all songs|full album|mashup|medley)\b", t):
        return "jukebox"
    if "karaoke" in t:
        return "karaoke"
    if re.search(r"\b(?:cover|unplugged|reprise|remix|recreated)\b", t):
        return "cover"
    if re.search(r"\blive\b(?!\s+(?:love|life))", t):
        return "live"
    if re.search(r"\blyric", t):
        return "lyrical"
    if re.search(r"\bpromo\b", t):
        return "promo"
    if re.search(r"\baudio\b", t):
        return "audio"
    return "video"


def clean_title(raw, channel=""):
    """Split a label upload title into {title, movie, credits, kind}."""
    raw = _norm(raw)
    kind = upload_kind(raw)
    channel_key = _norm(channel).lower()

    # Bracketed notes: "(Lyric Video)", "[4K]", "(From "Leo")".
    movie_hint = ""
    def bracket(match):
        nonlocal movie_hint
        inner = match.group(1).strip()
        found = re.match(r"^from\s+[\"'“‘]?(.+?)[\"'”’]?$", inner, re.I)
        if found:
            movie_hint = found.group(1).strip()
            return ""
        return "" if _DECORATION_RE.match(inner) or not inner else " (" + inner + ")"
    text = _BRACKETS_RE.sub(bracket, raw)
    text = _HASHTAG_RE.sub(lambda m: " " + m.group(1), text).strip()

    segments = [s.strip() for s in _SEPARATORS_RE.split(text) if s.strip()]
    if not segments:
        return {"title": raw, "movie": movie_hint, "credits": [], "kind": kind}

    head = _LEADING_NOISE_RE.sub("", segments[0])
    rest = segments[1:]
    movie = movie_hint
    title = head

    # The part around " - " is either decoration, the movie, or the song:
    #   "Song - Video Song"                    decoration
    #   "Malare - Premam Song"                 song - movie
    #   "Kumki - Onnum Puriyala Video Song"    movie - song (decorated tail)
    #   "Song - Movie" / "Artist - Song"       ambiguous; read as song - movie
    parts = _DASH_RE.split(head, maxsplit=1)
    if len(parts) == 2:
        left, tail = parts[0].strip(), parts[1].strip()
        tail_clean = _strip_decorations(tail)
        bare = _BARE_SONG_RE.match(tail)
        if not tail_clean or _DECORATION_RE.match(tail):
            title = left
        elif channel_key and left.lower() == channel_key:
            # "Sushin Shyam - Ray (Official Video)" on Sushin Shyam's channel
            title = tail_clean
            rest = [left] + rest
        elif bare and bare.group(1).split()[-1].lower() not in _NOT_A_MOVIE:
            title = left
            movie = movie or _strip_decorations(bare.group(1))
        elif tail_clean.lower() != _norm(tail).lower():
            title = tail_clean
            movie = movie or _strip_decorations(left)
        else:
            title = left
            if not movie and len(tail_clean.split()) <= 5:
                movie = tail_clean

    # Think Music style, the movie first and then the song named as one:
    #   "96 Songs | Kaathalae Kaathalae Song | Vijay Sethupathi, Trisha | …"
    #   "96 | Kaathalae Kaathalae Video Song | Vijay Sethupathi, Trisha | …"
    if len(parts) == 1 and rest and not movie_hint:
        second = _strip_decorations(rest[0])
        named = second and second.lower() != _norm(rest[0]).lower() and second.lower() not in LABELS
        movie_songs = re.match(r"^(.+?)\s+songs$", head, re.I)
        if named and (movie_songs or (_strip_decorations(head) == head and _VIDEO_SONG_RE.search(rest[0]))):
            movie = movie_songs.group(1).strip() if movie_songs else head
            title = second
            rest = rest[1:]

    title = _strip_decorations(title)

    credits = []
    for segment in rest:
        cleaned = _strip_decorations(segment)
        key = cleaned.lower()
        if not cleaned or _DECORATION_RE.match(segment) or key in LABELS or key == channel_key:
            continue
        if not movie:
            movie = cleaned
            continue
        if cleaned.lower() != movie.lower():
            credits.append(cleaned)

    if not title:
        title = movie or raw
    return {"title": title, "movie": movie, "credits": credits, "kind": kind}


def playlist_title(raw, channel=""):
    """Shorten a playlist title: drop the trailing '| Label' and decorations."""
    text = _norm(raw)
    segments = [s.strip() for s in _SEPARATORS_RE.split(text) if s.strip()]
    keep = [s for s in segments if s.lower() not in LABELS and s.lower() != _norm(channel).lower()]
    if not keep:
        keep = segments or [text]
    head = keep[0]
    head = re.sub(r"\s*[-–—]\s*official\s+(?:playlist|jukebox|album)\s*$", "", head, flags=re.I)
    return head.strip() or text


def song_key(track):
    """Identity of a song across its video / lyrical / audio uploads."""
    title = re.sub(r"[^\w]+", "", (track.get("title") or "").lower(), flags=re.U)
    movie = re.sub(r"[^\w]+", "", (track.get("movie") or "").lower(), flags=re.U)
    return title + "|" + movie


def guess_language(*texts, default=""):
    """Malayalam / Tamil from names and titles; default when neither shows."""
    joined = " ".join(t for t in texts if t)
    lower = joined.lower()
    malayalam = len(re.findall(r"malayalam|mollywood", lower)) + len(re.findall(r"[\u0d00-\u0d7f]+", joined))
    tamil = len(re.findall(r"tamil|kollywood", lower)) + len(re.findall(r"[\u0b80-\u0bff]+", joined))
    if malayalam > tamil:
        return "Malayalam"
    if tamil > malayalam:
        return "Tamil"
    return default
