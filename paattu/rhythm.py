"""A song's rhythm, for Now Playing's cover: how loud it is and where the
beats hit, 50 times a second (`paattu rhythm SONG`). The same as the app's
(app/lib/src/player/rhythm.dart): mpv decodes the song to 16-bit mono, as
fast as it can, and the levels and beats are worked out from that and kept
in ~/.cache/paattu/rhythm/ID.json.

Loudness is each frame's mean square in decibels against the song's loud
parts (the 95th percentile; 30 dB below them is 0). The beats come from the
low end alone (a one-pole low-pass at 150 Hz): how far its loudness rises over
the two frames before, against the song's sharper rises (the 90th percentile
of them, square-rooted so the smaller beats show too), and nothing where the
song is near silent. Both are kept as 0-255.
"""

import array
import json
import math
import os
import shutil
import subprocess
import sys
import tempfile

FPS = 50
RATE = 11025
VERSION = 1


def _decibels(mean_square):
    return 10 * math.log10(mean_square + 1e-10)


def _percentile(values, p):
    if not values:
        return 0.0
    ordered = sorted(values)
    return ordered[round((len(ordered) - 1) * p)]


def analyse(samples, rate):
    """{level: [0-255...], punch: [0-255...]} for mono 16-bit samples at rate a second."""
    hop = rate / FPS
    n = int(len(samples) / hop) if hop > 0 else 0
    if n == 0:
        return {"level": [], "punch": []}
    a = math.exp(-2 * math.pi * 150 / rate)
    b = 1 - a
    loud, low = [0.0] * n, [0.0] * n
    lowpass = 0.0
    for f in range(n):
        start, end = math.floor(f * hop), math.floor((f + 1) * hop)
        total = bass = 0.0
        for s in samples[start:end]:
            x = s / 32768
            lowpass = lowpass * a + b * x
            total += x * x
            bass += lowpass * lowpass
        count = max(1, end - start)
        loud[f] = _decibels(total / count)
        low[f] = _decibels(bass / count)
    top = _percentile(loud, 0.95)
    levels = [min(1.0, max(0.0, (v - (top - 30)) / 30)) for v in loud]
    rises = [0.0, 0.0] + [max(0.0, low[f] - max(low[f - 1], low[f - 2])) for f in range(2, n)]
    rises = rises[:n]
    sharp = _percentile([r for r in rises if r > 0], 0.9)
    punch = [0] * n
    if sharp > 0:
        for f in range(n):
            gate = min(1.0, max(0.0, (levels[f] - 0.15) / 0.2))
            punch[f] = round(math.sqrt(min(1.0, rises[f] / sharp)) * gate * 255)
    return {"level": [round(v * 255) for v in levels], "punch": punch}


def decode(source, timeout=180):
    """The song at source (a link mpv can play, through yt-dlp for YouTube) as
    mono 16-bit samples at RATE a second."""
    mpv = shutil.which("mpv")
    if not mpv:
        raise RuntimeError("mpv isn't installed")
    with tempfile.TemporaryDirectory(prefix="paattu-rhythm-") as folder:
        pcm = os.path.join(folder, "song.pcm")
        subprocess.run([mpv, "--no-config", "--really-quiet", "--vid=no", "--ytdl-format=bestaudio/best",
                        "--ao=pcm", "--ao-pcm-file=" + pcm, "--ao-pcm-waveheader=no", "--audio-format=s16",
                        "--audio-channels=mono", "--audio-samplerate=%d" % RATE, "--", source],
                       check=True, timeout=timeout, stdin=subprocess.DEVNULL,
                       stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
        samples = array.array("h")
        with open(pcm, "rb") as f:
            data = f.read()
        samples.frombytes(data[:len(data) // 2 * 2])
        if sys.byteorder != "little":
            samples.byteswap()
        return samples


def find(source, folder, name):
    """The rhythm of the song at source, kept in folder as NAME.json:
    {version, fps, level, punch}."""
    kept = os.path.join(folder, name + ".json")
    try:
        with open(kept, encoding="utf-8") as f:
            found = json.load(f)
        if found.get("version") == VERSION:
            os.utime(kept)
            return found
    except (OSError, ValueError):
        pass
    found = dict(analyse(decode(source), RATE), version=VERSION, fps=FPS)
    if not found["level"]:
        raise RuntimeError("no sound in that song")
    os.makedirs(folder, exist_ok=True)
    _forget_old(folder)
    with tempfile.NamedTemporaryFile("w", dir=folder, suffix=".tmp", delete=False, encoding="utf-8") as f:
        json.dump(found, f, separators=(",", ":"))
    os.replace(f.name, kept)
    return found


def _forget_old(folder, keep=300):
    """Keep the most recently used rhythms."""
    files = sorted((e for e in os.scandir(folder) if e.name.endswith(".json")),
                   key=lambda e: e.stat().st_mtime, reverse=True)
    for entry in files[keep:]:
        try:
            os.unlink(entry.path)
        except OSError:
            pass
