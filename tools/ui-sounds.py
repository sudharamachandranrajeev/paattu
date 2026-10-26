#!/usr/bin/env python3
"""Makes Paattu's interface sounds: three soft, low tones in the spirit of a
singing bowl, quiet enough to sit under the music.

  tap     a drop of water on wood, for buttons
  move    a breath of a fifth, for going to another page
  change  a small singing bowl, for another song

The app plays them from one file (app/assets/sounds/ui.wav, each sound at the
offset ui_sounds.dart names); the Omarchy window from one file each
(plugin/ui-*.wav). Run from the repo root after changing them.
"""

import math
import os
import random
import struct
import wave

RATE = 22050
PEAK = 10 ** (-20 / 20)  # -20 dBFS at the loudest


def tone(seconds, partials, attack, decay, glide=0.0):
    """partials: [(hertz, amplitude, beat hertz)]; the sound swells in over
    attack seconds and fades with time constant decay; glide bends the pitch
    down by that fraction over the sound."""
    out = []
    phases = [0.0] * len(partials)
    for i in range(int(seconds * RATE)):
        t = i / RATE
        bend = 1 - glide * min(1.0, t / seconds)
        env = min(1.0, t / attack) ** 2 * math.exp(-t / decay)
        # The last 20 ms fade to nothing, so nothing clicks.
        env *= min(1.0, (seconds - t) / 0.02)
        value = 0.0
        for k, (hz, amp, beat) in enumerate(partials):
            phases[k] += 2 * math.pi * hz * bend / RATE
            wobble = 1 - 0.25 * (1 - math.cos(2 * math.pi * beat * t)) if beat else 1
            value += amp * wobble * math.sin(phases[k])
        out.append(value * env)
    return out


def breath(seconds, level, attack, decay, seed=7):
    """A little low, soft noise: air over the tones."""
    rng = random.Random(seed)
    out, low = [], 0.0
    for i in range(int(seconds * RATE)):
        t = i / RATE
        low += 0.04 * (rng.uniform(-1, 1) - low)
        env = min(1.0, t / attack) ** 2 * math.exp(-t / decay) * min(1.0, (seconds - t) / 0.02)
        out.append(low * level * env)
    return out


def mix(*sounds):
    n = max(len(s) for s in sounds)
    return [sum(s[i] for s in sounds if i < len(s)) for i in range(n)]


def normal(samples):
    top = max(abs(v) for v in samples) or 1
    return [v / top * PEAK for v in samples]


SOUNDS = {
    "tap": normal(tone(0.25, [(261.6, 1, 0), (523.2, 0.18, 0), (784.9, 0.05, 0)],
                       attack=0.004, decay=0.055, glide=0.04)),
    "move": normal(mix(tone(0.5, [(196.0, 1, 0), (293.7, 0.6, 0), (392.0, 0.12, 0)], attack=0.03, decay=0.14),
                       breath(0.5, 1.5, attack=0.02, decay=0.1))),
    "change": normal(tone(1.5, [(220.0, 1, 0.7), (596.2, 0.32, 1.1), (1133.0, 0.1, 1.6)],
                          attack=0.012, decay=0.45)),
}
# Where each sound starts in the app's one file, in seconds.
OFFSETS = {"tap": 0.0, "move": 0.5, "change": 1.25}


def write(path, samples):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with wave.open(path, "wb") as f:
        f.setnchannels(1)
        f.setsampwidth(2)
        f.setframerate(RATE)
        f.writeframes(b"".join(struct.pack("<h", int(max(-1, min(1, v)) * 32767)) for v in samples))


def main():
    sprite = [0.0] * int((OFFSETS["change"] + len(SOUNDS["change"]) / RATE + 0.05) * RATE)
    for name, samples in SOUNDS.items():
        start = int(OFFSETS[name] * RATE)
        sprite[start:start + len(samples)] = samples
        write("plugin/ui-%s.wav" % name, samples)
    write("app/assets/sounds/ui.wav", sprite)


if __name__ == "__main__":
    main()
