"""Sound: the equaliser, preamp, bass, treble, balance and speed.

Everything is FFmpeg's `equalizer` (a peaking filter) in one lavfi graph,
because that is the only audio filter in the libmpv media_kit ships for
Windows, and it is in every other mpv. A peaking filter with a tiny Q is a
flat gain, which makes the preamp and the left / right levels. The engine
here, the desktop app (the same graph) and the Android app (this curve on
the phone's own equaliser) all share these numbers: tests/sound_cases.json.

Each filter is named (equalizer@b3), so a slider can move it while it plays
with `af-command paattu g <dB> equalizer@b3`; the graph is set again when the
slider is let go, as mpv rebuilds filters from it between songs.
"""

import math

# The bands (Hz), Poweramp's ten.
BANDS = (31, 62, 125, 250, 500, 1000, 2000, 4000, 8000, 16000)
LIMIT = 12.0  # dB either way: bands, preamp, bass, treble
SPEED = (0.5, 2.0)
LABEL = "paattu"
RATE = 48000  # for drawing the curve and finding its peak

PRESETS = (
    ("flat", "Flat", (0, 0, 0, 0, 0, 0, 0, 0, 0, 0)),
    ("melody", "Melody", (-2, -1.5, -1, 0.5, 2, 3.5, 3.5, 2, 0.5, -0.5)),
    ("kuthu", "Kuthu", (6, 5, 3, 1, 0, 0, 1, 2, 2, 1)),
    ("bass", "Bass boost", (6, 5, 4.5, 2.5, 0.5, 0, 0, 0, 0, 0)),
    ("treble", "Treble boost", (0, 0, 0, 0, 0, 0.5, 2, 3.5, 5, 6)),
    ("classical", "Classical", (0, 0, 0, 0, 0, 0, -3, -3, -3, -4.5)),
    ("rock", "Rock", (5, 3, -2, -3.5, -1.5, 1.5, 3.5, 4.5, 4.5, 4.5)),
    ("pop", "Pop", (-1, 2.5, 4, 4.5, 3, 0, -1.5, -1.5, -1, -1)),
    ("dance", "Dance", (6, 4.5, 1.5, 0, 0, -3, -4, -4, 0, 0)),
    ("jazz", "Jazz", (3, 2, 1, 2, -1.5, -1.5, 0, 1, 2, 3)),
    ("acoustic", "Acoustic", (4, 4, 3, 1, 1.5, 1.5, 3, 3.5, 3, 2)),
    ("loudness", "Loudness", (5, 4, 2, 0, -1, -1, 0, 2, 4, 5)),
    ("headphones", "Headphones", (3, 2, 1, 0, -0.5, 0, 1, 2, 2.5, 3)),
    ("night", "Late night", (-1, -1, 0, 1, 1.5, 1, 0, -1, -2, -3)),
)

DEFAULTS = {
    "on": False,
    # A preset's id, a saved preset's name, or "" once the bands are moved.
    "preset": "flat",
    "bands": [0] * len(BANDS),
    "preamp": 0,
    "bass": 0,
    "treble": 0,
    # -1 (left only) … 1 (right only).
    "balance": 0,
    # Lower the preamp by the curve's highest boost, so loud songs don't clip.
    "noclip": True,
    # Faster or slower, at the same pitch. Not part of "on".
    "speed": 1,
    # Your own presets: {name: [ten bands]}.
    "presets": {},
}

# (name, the filter's fixed options); the order of the graph.
FILTERS = (
    (("pre", "f=1000:t=q:w=0.001"),)
    + tuple(("b%d" % i, "f=%d:t=o:w=1" % f) for i, f in enumerate(BANDS))
    + (("bass", "f=60:t=o:w=3"), ("treble", "f=10000:t=o:w=2"),
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


def normalize(settings):
    """settings with every key, each in range."""
    s = dict(DEFAULTS, **(settings or {}))
    bands = list(s.get("bands") or [])[:len(BANDS)]
    bands += [0] * (len(BANDS) - len(bands))
    presets = {}
    for name, values in (s.get("presets") or {}).items():
        if isinstance(name, str) and name.strip() and isinstance(values, list):
            values = [tenth(_number(v, -LIMIT, LIMIT)) for v in values[:len(BANDS)]]
            presets[name.strip()] = values + [0.0] * (len(BANDS) - len(values))
    return {
        "on": s.get("on") is True,
        "preset": s.get("preset") if isinstance(s.get("preset"), str) else "",
        "bands": [tenth(_number(b, -LIMIT, LIMIT)) for b in bands],
        "preamp": tenth(_number(s.get("preamp"), -LIMIT, LIMIT)),
        "bass": tenth(_number(s.get("bass"), -LIMIT, LIMIT)),
        "treble": tenth(_number(s.get("treble"), -LIMIT, LIMIT)),
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


def curve(settings):
    """[(options, gain)] for the bands, bass and treble: the shape of the sound."""
    s = normalize(settings)
    shape = [(opts, s["bands"][i]) for i, (_, opts) in enumerate(FILTERS[1:1 + len(BANDS)])]
    return shape + [(FILTERS[-4][1], s["bass"]), (FILTERS[-3][1], s["treble"])]


# Where the peak is looked for: 20 Hz … 20 kHz, 24 steps an octave, and the bands.
_GRID = sorted(set([20 * 2 ** (i / 24) for i in range(240)] + list(BANDS)))


def peak(settings):
    """The curve's highest boost (dB), 0 if it only cuts."""
    shape = [g for g in curve(settings) if g[1]]
    return max([0.0] + [response(shape, f) for f in _GRID]) if shape else 0.0


def gains(settings):
    """{filter name: dB} as the graph gets them."""
    s = normalize(settings)
    pre = s["preamp"] - (peak(s) if s["noclip"] else 0)
    b = s["balance"]
    out = {"pre": tenth(max(-30.0, pre))}
    out.update(("b%d" % i, g) for i, g in enumerate(s["bands"]))
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
        "equalizer@%s=%s:g=%s" % (name, options, fmt(levels[name])) for name, options in FILTERS))


def summary(settings):
    """One line: "On · Melody · preamp -3.5 dB · bass +2 dB · 1.25×"."""
    s = normalize(settings)
    names = dict((key, name) for key, name, _ in PRESETS)
    parts = ["On" if s["on"] else "Off", names.get(s["preset"], s["preset"] or "Custom")]
    for key, label in (("preamp", "preamp"), ("bass", "bass"), ("treble", "treble")):
        if s[key]:
            parts.append("%s %s%s dB" % (label, "+" if s[key] > 0 else "", fmt(s[key])))
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
