"""Sound: the equaliser, preamp, bass, treble, surround, balance and speed.

Everything is FFmpeg's `equalizer` (a peaking filter) in one lavfi graph,
because that is the only audio filter in the libmpv media_kit ships for
Windows, and it is in every other mpv. A peaking filter with a tiny Q is a
flat gain, which makes the preamp and the left / right levels. The engine
here, the desktop app (the same graph) and the Android app (this curve on
the phone's own equaliser) all share these numbers: tests/sound_cases.json.

The equaliser has fifteen bands, the ISO 2/3-octave centres from 25 Hz to
16 kHz. Peaking filters overlap: fifteen of them at +12 dB sum to far more
than 12 dB, and one band at +12 dB lifts its neighbours too. So the sliders
are the levels wanted at the band centres, and the filters' own gains are
worked out to give them (band_gains): the interaction of each filter at each
centre and halfway between centres, solved by least squares, then once more
with the interaction measured at the gains found (V. Valimaki and J. Liski,
"Accurate cascade graphic equalizer", IEEE Signal Processing Letters 24(2),
2017). The curve then lands within about half a dB of every slider.

Surround widens the stereo image with FFmpeg's `extrastereo`: each side
moves away from the middle (L+R)/2 by WIDEN times (1 at none, 2.5 at full,
FFmpeg's own default). The Windows app ships a libmpv that has it (the one
media_kit ships has only `equalizer`); Android hands the strength to the
phone's own virtualizer instead.

Each filter is named (equalizer@b3), so a slider can move it while it plays
with `af-command paattu g <dB> equalizer@b3`; the graph is set again when the
slider is let go, as mpv rebuilds filters from it between songs.
"""

import functools
import math

# The bands (Hz): the ISO 2/3-octave centres.
BANDS = (25, 40, 63, 100, 160, 250, 400, 630, 1000, 1600, 2500, 4000, 6300, 10000, 16000)
# Each band filter's width (octaves): a little wider than the 2/3 octave
# between bands, which measured the closest fit to the sliders.
WIDTH = 0.8
# Settings from before 0.14 have ten bands, one octave wide, uncompensated.
OLD_BANDS = (31, 62, 125, 250, 500, 1000, 2000, 4000, 8000, 16000)
LIMIT = 12.0  # dB either way: bands, preamp, bass, treble
SPEED = (0.5, 2.0)
LABEL = "paattu"
# extrastereo's m at full surround.
WIDEN = 2.5
RATE = 48000  # for drawing the curve and finding its peak

# The levels the ten-band presets gave at these centres, so they sound as before.
PRESETS = (
    ("flat", "Flat", (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)),
    ("melody", "Melody", (-1.5, -2, -2, -1, -0.5, 1, 2, 3, 4.5, 4, 3.5, 3, 1, 0.5, -0.5)),
    ("kuthu", "Kuthu", (5, 6, 6.5, 4.5, 3, 2, 0.5, 0.5, 0.5, 1, 1.5, 2.5, 2.5, 2, 1)),
    ("bass", "Bass boost", (5, 6, 7, 5.5, 4.5, 3.5, 1.5, 0.5, 0, 0, 0, 0, 0, 0, 0)),
    ("treble", "Treble boost", (0, 0, 0, 0, 0, 0, 0, 0.5, 1, 2, 3.5, 5.5, 6, 7, 6.5)),
    ("classical", "Classical", (0, 0, 0, 0, 0, 0, 0, 0, -0.5, -2.5, -3.5, -4.5, -4, -4.5, -5)),
    ("rock", "Rock", (4, 4, 3.5, -0.5, -2.5, -4, -2, -0.5, 2, 3.5, 4.5, 6.5, 6, 6, 5)),
    ("pop", "Pop", (-0.5, 0.5, 3.5, 4, 4.5, 6, 4, 2.5, 0.5, -1, -1.5, -2, -1.5, -1.5, -1)),
    ("dance", "Dance", (5, 5.5, 6, 3, 1.5, 0.5, -0.5, -1.5, -4, -4.5, -4.5, -5, -1.5, -0.5, 0)),
    ("jazz", "Jazz", (2.5, 3, 3, 1.5, 1.5, 2, -0.5, -1.5, -1.5, -0.5, 0.5, 1.5, 2.5, 3, 3)),
    ("acoustic", "Acoustic", (3.5, 4.5, 5.5, 4, 3, 2, 2, 2, 2.5, 3, 4, 5, 4, 3.5, 2.5)),
    ("loudness", "Loudness", (4, 5, 5.5, 3, 2, 0.5, -0.5, -1, -1, 0, 1, 3, 4.5, 5.5, 5.5)),
    ("headphones", "Headphones", (2.5, 3, 2.5, 1.5, 1, 0, 0, 0, 0, 1, 1.5, 3, 3, 3.5, 3.5)),
    ("night", "Late night", (-1, -1, -1, -0.5, 0.5, 1.5, 1.5, 1.5, 1, 0, -0.5, -1.5, -2.5, -3, -3)),
)

_BUILT_IN = dict((key, bands) for key, _, bands in PRESETS)

DEFAULTS = {
    "on": False,
    # A preset's id, a saved preset's name, or "" once the bands are moved.
    "preset": "flat",
    "bands": [0] * len(BANDS),
    "preamp": 0,
    "bass": 0,
    "treble": 0,
    # 0 (none) … 1 (full): how much wider the stereo is.
    "surround": 0,
    # -1 (left only) … 1 (right only).
    "balance": 0,
    # Lower the preamp by the curve's highest boost, so loud songs don't clip.
    "noclip": True,
    # Faster or slower, at the same pitch. Not part of "on".
    "speed": 1,
    # Your own presets: {name: [fifteen bands]}.
    "presets": {},
}

# (name, the filter's fixed options); the order of the graph.
FILTERS = (
    (("pre", "f=1000:t=q:w=0.001"),)
    + tuple(("b%d" % i, "f=%d:t=o:w=%g" % (f, WIDTH)) for i, f in enumerate(BANDS))
    + (("bass", "f=60:t=o:w=3"), ("treble", "f=10000:t=o:w=2"),
       ("surround", None),
       ("left", "f=1000:t=q:w=0.001:c=FL"), ("right", "f=1000:t=q:w=0.001:c=FR"))
)


def tenth(x):
    """x to 0.1 dB, rounding halves up (as JavaScript's and Dart's round)."""
    return math.floor(x * 10 + 0.5) / 10


def hundredth(x):
    """x to 0.01, halves up (Python's round() rounds them to even)."""
    return math.floor(x * 100 + 0.5) / 100


def fmt(x):
    """2.5 → "2.5", 3.0 → "3", -0.0 → "0"."""
    x = tenth(x)
    return "0" if x == 0 else ("%.1f" % x).rstrip("0").rstrip(".")


def _number(value, low, high, default=0.0):
    try:
        x = float(value)
    except (TypeError, ValueError):
        return float(default)
    return float(default) if math.isnan(x) else float(min(high, max(low, x)))


def preset_bands(name, settings=None):
    for key, _, bands in PRESETS:
        if key == name:
            return list(bands)
    saved = (settings or {}).get("presets") or {}
    return list(saved[name]) if name in saved else None


def bands_of(values):
    """Fifteen band levels in range from a config value. Ten (settings from
    before 0.14) become the levels their old filters gave at the new centres."""
    values = list(values) if isinstance(values, (list, tuple)) else []
    if len(values) == len(OLD_BANDS):
        old = [("f=%d:t=o:w=1" % f, _number(v, -LIMIT, LIMIT)) for f, v in zip(OLD_BANDS, values)]
        values = [response(old, f) for f in BANDS]
    values = values[:len(BANDS)] + [0] * (len(BANDS) - len(values[:len(BANDS)]))
    return [tenth(_number(v, -LIMIT, LIMIT)) for v in values]


def normalize(settings):
    """settings with every key, each in range."""
    s = dict(DEFAULTS, **(settings or {}))
    bands = bands_of(s.get("bands"))
    # A built-in preset from before 0.14 is that preset in fifteen bands
    # (which are its old levels to the half dB).
    old = isinstance(s.get("bands"), list) and len(s["bands"]) == len(OLD_BANDS)
    if old and [math.floor(b * 2 + 0.5) / 2 for b in bands] == list(_BUILT_IN.get(s.get("preset"), ())):
        bands = [float(b) for b in _BUILT_IN[s["preset"]]]
    presets = {}
    for name, values in (s.get("presets") or {}).items():
        if isinstance(name, str) and name.strip() and isinstance(values, list):
            presets[name.strip()] = bands_of(values)
    return {
        "on": s.get("on") is True,
        "preset": s.get("preset") if isinstance(s.get("preset"), str) else "",
        "bands": bands,
        "preamp": tenth(_number(s.get("preamp"), -LIMIT, LIMIT)),
        "bass": tenth(_number(s.get("bass"), -LIMIT, LIMIT)),
        "treble": tenth(_number(s.get("treble"), -LIMIT, LIMIT)),
        "surround": hundredth(_number(s.get("surround"), 0, 1)),
        "balance": hundredth(_number(s.get("balance"), -1, 1)),
        "noclip": s.get("noclip") is not False,
        "speed": hundredth(_number(s.get("speed"), *SPEED, default=1.0)),
        "presets": presets,
    }


def _alpha(w0, options):
    opts = dict(part.split("=") for part in options.split(":"))
    width = float(opts["w"])
    if opts["t"] == "q":
        return math.sin(w0) / (2 * width)
    # FFmpeg's octave width (af_biquads.c).
    return math.sin(w0) * math.sinh(math.log(2) / 2 * width * w0 / math.sin(w0))


def response(gains, freq, rate=RATE):
    """The level (dB) at freq through peaking filters [(options, gain)]."""
    total = 0.0
    z1 = complex(math.cos(2 * math.pi * freq / rate), -math.sin(2 * math.pi * freq / rate))
    for options, gain in gains:
        if not gain:
            continue
        f0 = float(dict(part.split("=") for part in options.split(":"))["f"])
        w0 = 2 * math.pi * f0 / rate
        alpha, a = _alpha(w0, options), 10 ** (gain / 40)
        cos = math.cos(w0)
        num = (1 + alpha * a) + (-2 * cos) * z1 + (1 - alpha * a) * z1 * z1
        den = (1 + alpha / a) + (-2 * cos) * z1 + (1 - alpha / a) * z1 * z1
        total += 20 * math.log10(abs(num / den))
    return total


# Where the curve is matched to the sliders: each centre, and halfway between
# two (where it should be their average), which counts half as much.
_FIT = [(f, i, i, 1.0) for i, f in enumerate(BANDS)] + [
    (math.sqrt(f * BANDS[i + 1]), i, i + 1, 0.5) for i, f in enumerate(BANDS[:-1])]
# A filter's interaction is measured at its gain, or at this when that's tiny.
_PROTO = 12.0
_BAND_LIMIT = 30.0


def _solve(a, y):
    """x with a·x = y (Gaussian elimination with partial pivoting)."""
    n = len(y)
    m = [list(row) + [y[i]] for i, row in enumerate(a)]
    for c in range(n):
        p = max(range(c, n), key=lambda r: abs(m[r][c]))
        m[c], m[p] = m[p], m[c]
        for r in range(n):
            if r != c and m[r][c]:
                k = m[r][c] / m[c][c]
                for j in range(c, n + 1):
                    m[r][j] -= k * m[c][j]
    return [m[i][n] / m[i][i] for i in range(n)]


def band_gains(bands):
    """The band filters' gains (dB) that put the curve at bands' levels."""
    return list(_band_gains(tuple(float(b) for b in bands)))


@functools.lru_cache(maxsize=32)
def _band_gains(bands):
    if not any(bands):
        return [0.0] * len(BANDS)
    want = [(bands[i] + bands[j]) / 2 for _, i, j, _ in _FIT]
    g = [_PROTO] * len(BANDS)
    for _ in range(2):
        at = [g_ if abs(g_) >= 0.5 else _PROTO for g_ in g]
        # a[k][m]: filter m's level at fit point k, per dB of its gain.
        a = [[response([(FILTERS[1 + m][1], at[m])], f) / at[m] for m in range(len(BANDS))] for f, _, _, _ in _FIT]
        weights = [w for _, _, _, w in _FIT]
        normal = [[sum(w * row[i] * row[j] for w, row in zip(weights, a)) for j in range(len(BANDS))]
                  for i in range(len(BANDS))]
        g = _solve(normal, [sum(w * row[i] * y for w, row, y in zip(weights, a, want)) for i in range(len(BANDS))])
    return [min(_BAND_LIMIT, max(-_BAND_LIMIT, x)) for x in g]


def curve(settings):
    """[(options, gain)] for the bands, bass and treble: the shape of the sound."""
    s = normalize(settings)
    shape = list(zip((opts for _, opts in FILTERS[1:1 + len(BANDS)]), band_gains(s["bands"])))
    return shape + [(FILTERS[-5][1], s["bass"]), (FILTERS[-4][1], s["treble"])]


# Where the peak is looked for: 20 Hz … 20 kHz, 24 steps an octave, and the bands.
_GRID = sorted(set([20 * 2 ** (i / 24) for i in range(240)] + list(BANDS)))


def peak(settings):
    """The curve's highest boost (dB), 0 if it only cuts."""
    shape = [g for g in curve(settings) if g[1]]
    return max([0.0] + [response(shape, f) for f in _GRID]) if shape else 0.0


def widen(settings):
    """extrastereo's m for the surround: 1 (none) … WIDEN."""
    return hundredth(1 + (WIDEN - 1) * normalize(settings)["surround"])


def surround_room(settings):
    """How much louder (dB) the surround can make a side panned hard one way."""
    return 20 * math.log10((1 + widen(settings)) / 2)


def gains(settings):
    """{filter name: dB} as the graph gets them (surround's isn't a gain: widen)."""
    s = normalize(settings)
    pre = s["preamp"] - (peak(s) + surround_room(s) if s["noclip"] else 0)
    b = s["balance"]
    out = {"pre": tenth(max(-30.0, pre))}
    out.update(("b%d" % i, tenth(g)) for i, g in enumerate(band_gains(s["bands"])))
    out.update(bass=s["bass"], treble=s["treble"],
               left=tenth(20 * math.log10(max(0.01, 1 - b))) if b > 0 else 0.0,
               right=tenth(20 * math.log10(max(0.01, 1 + b))) if b < 0 else 0.0)
    return out


def graph(settings):
    """mpv's `af` entry for the settings ("" when the sound effects are off)."""
    s = normalize(settings)
    if not s["on"]:
        return ""
    levels = gains(s)
    return "@%s:lavfi=[%s]" % (LABEL, ",".join(
        "extrastereo@surround=m=%g" % widen(s) if options is None else
        "equalizer@%s=%s:g=%s" % (name, options, fmt(levels[name])) for name, options in FILTERS))


def summary(settings):
    """One line: "On · Melody · preamp -3.5 dB · bass +2 dB · surround 40% · 1.25×"."""
    s = normalize(settings)
    names = dict((key, name) for key, name, _ in PRESETS)
    parts = ["On" if s["on"] else "Off", names.get(s["preset"], s["preset"] or "Custom")]
    for key, label in (("preamp", "preamp"), ("bass", "bass"), ("treble", "treble")):
        if s[key]:
            parts.append("%s %s%s dB" % (label, "+" if s[key] > 0 else "", fmt(s[key])))
    if s["surround"]:
        parts.append("surround %d%%" % round(s["surround"] * 100))
    if s["balance"]:
        parts.append("balance %d%% %s" % (round(abs(s["balance"]) * 100), "right" if s["balance"] > 0 else "left"))
    if s["speed"] != 1:
        parts.append(("%g" % s["speed"]) + "×")
    return " · ".join(parts)


def apply(engine, settings):
    """Bring a running engine in line with settings (only what changed)."""
    s = normalize(settings)
    want = graph(s)
    commands = []
    if engine.get("user-data/paattu/af") != want:
        commands.append(["af", "add", want] if want else ["af", "remove", "@" + LABEL])
        commands.append(["set_property", "user-data/paattu/af", want])
    speed = engine.get("speed", 1.0)
    if not isinstance(speed, (int, float)) or abs(speed - s["speed"]) > 0.001:
        commands.append(["set_property", "speed", s["speed"]])
    # ("af remove" answers an error when the filter isn't there; that's fine.)
    return engine.batch(commands) if commands else []
