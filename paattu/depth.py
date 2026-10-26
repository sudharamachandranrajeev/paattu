"""A depth map of a song's cover, for the cover in 3D in the app window's
Now Playing (Settings > Cover in 3D).

The cover isn't cut apart: it is drawn whole, each point moved by how near it
is as the cover leans (app/plugin's DepthCover.qml and the Flutter app's
depth_cover.dart, with the same shader), so the subject glides over what is
behind it with no edge to give a poor cut-out away. How near each point is
comes from the cover's subject where there is one: U²-Net's small model
(models/u2netp.onnx) guesses which pixels are the subject, the guess is
cleaned up the way the Flutter app does it (app/lib/src/subject.dart), then
softened a lot, so a guess that is a little off only moves a little more or
less. Where nothing stands out, the cover's own sections (the few colours it
is made of, nearer the more central, colourful and away from its edges they
are) are taken as layers instead, which drift slowly past each other.

ONNX Runtime, NumPy and Pillow aren't needed for anything else, so the work
runs in its own process with them from uv (fetched the first time, then
cached by uv):

    python depth.py MODEL COVER OUT_DIR NAME

prints {"picture": ..., "depth": ..., "subject": true/false, "centre": [x, y]}
(and "area" with a subject). This file only uses the standard library at the
top, so the CLI and the tests can import it.
"""

import json
import math
import os
import shutil
import subprocess
import sys
from pathlib import Path

# The side of the square the subject is looked for in (the model's input).
MASK_SIDE = 320
# The largest the pictures are kept at.
PICTURE_SIDE = 720
# The side of the depth map, and how many colours a cover is taken apart into
# when no subject stands out.
DEPTH_SIDE = 64
REGIONS = 5
# Bumped when the pictures change, so cached ones are made again.
VERSION = 4
# Covers whose pictures are kept (the oldest go).
KEEP = 300
# How the cover is shown (the shader of the app's DepthCover.qml and the
# Flutter app's depth_cover.dart): this much bigger, with its nearest points
# moving up to about LEAN of its side as it leans, rounded about CORNER of its
# side. A subject cut off by the frame fades from the depth map before the
# edge, so nothing is pulled in from outside the picture.
LIFT = 1.06
LEAN = 0.02
CORNER = 0.08

HELPER = Path(__file__).resolve()
MODEL = HELPER.parent.parent / "models" / "u2netp.onnx"
PACKAGES = ("onnxruntime>=1.17", "numpy>=1.26", "pillow>=10")


class DepthError(RuntimeError):
    pass


def clean_mask(raw, side):
    """What `raw` (a side by side guess at how much each pixel is the subject,
    row by row) leaves to lift: (alpha, (x, y), area), stretched to 0-1 and
    made firmer (the guess is often unsure inside the subject, which would let
    the picture behind show through). Unsure patches the subject closes around
    (a shirt the model half missed) are filled; what it is sure is background
    (the gap between an arm and the body) is kept. The subject is shown a
    little bigger (LIFT) and moves as the cover leans, so it fades out before
    the cover's (rounded) edge wherever it is shown: a subject cut off by the
    frame would otherwise stick out past it. The centre is 0 to 1 across and
    down. None when the guess is no good: nothing stands out, the subject is a
    speck or most of the picture, or it is a haze, not a shape."""
    n = side * side
    if len(raw) != n or n == 0 or not all(math.isfinite(v) for v in raw):
        return None
    lo, hi = min(raw), max(raw)
    if not (hi >= 0.5 and hi - lo > 0.3):
        return None
    span = hi - lo
    alpha = [0.0] * n
    solid = haze = 0
    sx = sy = total = 0.0
    for i, v in enumerate(raw):
        a = (v - lo) / span
        if a > 0.5:
            solid += 1
        if 0.15 < a < 0.85:
            haze += 1
        t = min(1.0, max(0.0, (a - 0.2) / 0.6))
        alpha[i] = t * t * (3 - 2 * t)
        y, x = divmod(i, side)
        sx += x * a
        sy += y * a
        total += a
    area = solid / n
    if area < 0.03 or area > 0.8 or haze > solid:
        return None
    cx, cy = (sx / total + 0.5) / side, (sy / total + 0.5) / side
    # Close the subject (grow it, then shrink it back, by `reach`): what that
    # adds is gaps and dents narrower than twice `reach`. Of that, the unsure
    # pixels become subject, fading in over a few pixels so no hard line shows.
    reach = max(1, round(side * 0.03))
    grown = _distances([(v - lo) / span > 0.5 for v in raw], side, reach)
    inside = _distances([d > reach for d in grown], side, reach + 3)
    for i in range(n):
        fill = (inside[i] - reach) / 3
        if fill > 0:
            sure = min(1.0, max(0.0, ((raw[i] - lo) / span - 0.1) / 0.1))
            alpha[i] = max(alpha[i], min(1.0, fill) * sure)
    for i in range(n):
        if alpha[i] > 0:
            y, x = divmod(i, side)
            alpha[i] *= _in_frame(cx + ((x + 0.5) / side - cx) * LIFT, cy + ((y + 0.5) / side - cy) * LIFT)
    return alpha, (cx, cy), area


def _in_frame(x, y):
    """How far (x, y), 0 to 1 across and down the cover as shown, is inside
    it: 0 outside the cover's rounded edge less the furthest the subject moves
    as it leans, 1 a little further in."""
    across, down = min(x, 1 - x), min(y, 1 - y)
    if across < CORNER and down < CORNER:
        edge = CORNER - math.hypot(CORNER - across, CORNER - down)
    else:
        edge = min(across, down)
    return min(1.0, max(0.0, (edge - LEAN) / 0.04))

def _distances(seeds, side, limit):
    """How many steps (across, down or corner to corner) each pixel is from
    the nearest seed, counted up to limit + 1."""
    far = limit + 1
    distance = [far] * len(seeds)
    frontier = [i for i, seed in enumerate(seeds) if seed]
    for i in frontier:
        distance[i] = 0
    step = 0
    while frontier and step < limit:
        step += 1
        reached = []
        for i in frontier:
            y, x = divmod(i, side)
            for ny in range(max(0, y - 1), min(side, y + 2)):
                row = ny * side
                for nx in range(max(0, x - 1), min(side, x + 2)):
                    j = row + nx
                    if distance[j] == far:
                        distance[j] = step
                        reached.append(j)
        frontier = reached
    return distance


def model_input(rgb):
    """U²-Net's input (channel by channel) from a square of RGB bytes: scaled
    by the brightest value, then each channel set against ImageNet's mean and
    spread, as the model was trained."""
    mean = (0.485, 0.456, 0.406)
    spread = (0.229, 0.224, 0.225)
    n = len(rgb) // 3
    top = max(1, max(rgb, default=0))
    out = [0.0] * (3 * n)
    for c in range(3):
        for i in range(n):
            out[c * n + i] = (rgb[i * 3 + c] / top - mean[c]) / spread[c]
    return out


def cover_clip(width, height):
    """The square the app shows of a cover (Model.coverClip): YouTube
    thumbnails are 4:3 with a 16:9 picture letterboxed in them."""
    if abs(width - height) <= 2:
        return 0, 0, width, height
    frame = round(width * 9 / 16)
    top = round((height - frame) / 2) if height > frame else 0
    side = min(frame, height)
    left = round((width - side) / 2)
    return left, top, left + side, top + side


# ---------------------------------------------------------------- the depth map
# The same in app/lib/src/depth.dart (tests/depth_cases.json).

def regions(rgb, side, k=REGIONS, rounds=6):
    """The few colours a side by side square of RGB bytes is made of: (label
    of each pixel, the colours). k-means, started from the average colour
    and then each time the pixel furthest from every colour so far, so the
    same picture always comes apart the same way."""
    n = side * side
    pixels = [(float(rgb[i * 3]), float(rgb[i * 3 + 1]), float(rgb[i * 3 + 2])) for i in range(n)]

    def far(a, b):
        r, g, bl = a[0] - b[0], a[1] - b[1], a[2] - b[2]
        return r * r + g * g + bl * bl

    total = [0.0, 0.0, 0.0]
    for p in pixels:
        total[0] += p[0]
        total[1] += p[1]
        total[2] += p[2]
    centres = [(total[0] / n, total[1] / n, total[2] / n)]
    nearest = [far(p, centres[0]) for p in pixels]
    while len(centres) < k:
        best = 0
        for i in range(1, n):
            if nearest[i] > nearest[best]:
                best = i
        if nearest[best] < 1:
            break
        centres.append(pixels[best])
        nearest = [min(nearest[i], far(pixels[i], pixels[best])) for i in range(n)]

    def assign():
        labels = [0] * n
        for i, p in enumerate(pixels):
            best, gap = 0, far(p, centres[0])
            for c in range(1, len(centres)):
                d = far(p, centres[c])
                if d < gap:
                    best, gap = c, d
            labels[i] = best
        return labels

    for _ in range(rounds):
        labels = assign()
        sums = [[0.0, 0.0, 0.0, 0] for _ in centres]
        for i, c in enumerate(labels):
            s = sums[c]
            s[0] += pixels[i][0]
            s[1] += pixels[i][1]
            s[2] += pixels[i][2]
            s[3] += 1
        centres = [(s[0] / s[3], s[1] / s[3], s[2] / s[3]) if s[3] else centres[c] for c, s in enumerate(sums)]
    return assign(), centres


def _tidy(labels, side, k):
    """Each pixel takes the label most of the 3 by 3 around it have (its own
    on a tie), so specks don't become layers of their own."""
    out = list(labels)
    for y in range(side):
        for x in range(side):
            counts = [0] * k
            for ny in range(max(0, y - 1), min(side, y + 2)):
                for nx in range(max(0, x - 1), min(side, x + 2)):
                    counts[labels[ny * side + nx]] += 1
            own = labels[y * side + x]
            best = own
            for c in range(k):
                if counts[c] > counts[best]:
                    best = c
            out[y * side + x] = best
    return out


def region_depth(rgb, side):
    """How near each pixel of a side by side square of RGB bytes is, 0 to 1,
    when nothing in it stands out as its subject: each of its colours a layer,
    nearer the more central, colourful and away from the picture's edges it
    is. All one depth (0.5) when no layer stands out from the rest."""
    labels, colours = regions(rgb, side)
    k = len(colours)
    labels = _tidy(labels, side, k)
    n = side * side
    count = [0] * k
    ring = [0] * k
    middle = [0.0] * k
    rim = 0
    for i, c in enumerate(labels):
        y, x = divmod(i, side)
        count[c] += 1
        if x == 0 or y == 0 or x == side - 1 or y == side - 1:
            ring[c] += 1
            rim += 1
        middle[c] += min(1.0, math.hypot((x + 0.5) / side - 0.5, (y + 0.5) / side - 0.5) / math.sqrt(0.5))
    score = [0.0] * k
    for c in range(k):
        if not count[c]:
            continue
        touch = (ring[c] / rim) / (count[c] / n)
        top, low = max(colours[c]), min(colours[c])
        colourful = (top - low) / top if top > 0 else 0.0
        score[c] = 0.45 * (1 - middle[c] / count[c]) + 0.2 * colourful + 0.35 / (1 + touch)
    used = [score[c] for c in range(k) if count[c]]
    lo, hi = min(used), max(used)
    level = [(s - lo) / (hi - lo) if hi - lo > 0.05 else 0.5 for s in score]
    return [level[c] for c in labels]


def blur(values, side, sigma):
    """A side by side square of values, blurred (Gaussian, the edges held)."""
    reach = int(math.ceil(sigma * 3))
    weights = [math.exp(-(i * i) / (2 * sigma * sigma)) for i in range(-reach, reach + 1)]
    total = sum(weights)
    weights = [w / total for w in weights]
    across = [0.0] * (side * side)
    for y in range(side):
        row = y * side
        for x in range(side):
            v = 0.0
            for j, w in enumerate(weights):
                v += values[row + min(side - 1, max(0, x + j - reach))] * w
            across[row + x] = v
    out = [0.0] * (side * side)
    for y in range(side):
        for x in range(side):
            v = 0.0
            for j, w in enumerate(weights):
                v += across[min(side - 1, max(0, y + j - reach)) * side + x] * w
            out[y * side + x] = v
    return out


def shrink(values, side, to):
    """A side by side square of values, `to` across: each the average of the
    block it covers (side a multiple of to)."""
    step = side // to
    out = [0.0] * (to * to)
    for y in range(to):
        for x in range(to):
            v = 0.0
            for dy in range(step):
                row = (y * step + dy) * side + x * step
                for dx in range(step):
                    v += values[row + dx]
            out[y * to + x] = v / (step * step)
    return out


def depth_map(rgb, side, subject=None):
    """(depth, shadow, subject) for a side by side square of RGB bytes and,
    if it has one, how much each pixel is its subject: how near each point
    is (soft, so a cut-out that is a little off doesn't show), the subject's
    shadow on what is behind it, and where the subject is (a little soft)."""
    layers = blur(region_depth(rgb, side), side, side / 32)
    if subject is None:
        return layers, [0.0] * (side * side), [0.0] * (side * side)
    # Softened, then brought back up (so a slim subject is as near as a broad
    # one) and past full from its edge in: the subject is all one depth and
    # moves in one piece, a face never stretched across, and only what is
    # behind it stretches round its edge.
    lifted = blur(subject, side, side / 20)
    top = max(lifted)
    if top > 0:
        lifted = [min(1.0, 2 * v / top) for v in lifted]
    depth = [0.25 * a * (1 - b) + b for a, b in zip(layers, lifted)]
    shadow = [0.55 * v for v in blur(subject, side, side / 16)]
    return depth, shadow, blur(subject, side, side / 80)


def depth_centre(depth, side):
    """Where the nearest of a depth map is, 0 to 1 across and down."""
    sx = sy = total = 0.0
    for i, d in enumerate(depth):
        y, x = divmod(i, side)
        w = d * d
        sx += (x + 0.5) * w
        sy += (y + 0.5) * w
        total += w
    if total <= 0:
        return 0.5, 0.5
    return sx / total / side, sy / total / side


def depth_pixels(depth, shadow, subject):
    """The depth map as RGB bytes: depth in red, shadow in green, subject in blue."""
    out = bytearray(len(depth) * 3)
    for i, values in enumerate(zip(depth, shadow, subject)):
        for c, v in enumerate(values):
            out[i * 3 + c] = min(255, max(0, int(v * 255 + 0.5)))
    return bytes(out)


# ---------------------------------------------------------------- the CLI side

def find_uv():
    found = shutil.which("uv")
    if found:
        return found
    home = Path.home()
    for candidate in (home / ".local/bin/uv", home / ".cargo/bin/uv", home / ".local/share/mise/shims/uv"):
        if os.access(candidate, os.X_OK):
            return str(candidate)
    return None


def _forget_old(folder):
    found = sorted(folder.glob("*.json"), key=lambda p: p.stat().st_mtime)
    for old in found[:max(0, len(found) - KEEP)]:
        for suffix in (".json", ".picture.jpg", ".depth.png", ".subject.png", ".back.png"):
            old.with_suffix(suffix).unlink(missing_ok=True)


def lift(cover, folder, name, timeout=300):
    """The pictures for `cover` (a file), made once and kept in `folder` as
    NAME.picture.jpg (the cover, square) and NAME.depth.png with NAME.json
    beside them."""
    folder.mkdir(parents=True, exist_ok=True)
    record = folder / (name + ".json")
    stamp = cover.stat()
    made_from = [stamp.st_size, stamp.st_mtime_ns, VERSION]
    try:
        known = json.loads(record.read_text())
        if known.get("from") == made_from and (not known.get("depth") or Path(known["depth"]).exists()):
            return known
    except (OSError, ValueError, AttributeError):
        pass
    uv = find_uv()
    if not uv:
        raise DepthError("the cover in 3D needs uv (https://docs.astral.sh/uv/) to run ONNX Runtime: "
                         "install it, or turn Cover in 3D off in Settings")
    if not MODEL.exists():
        raise DepthError("the model for the cover in 3D is missing (%s): reinstall Paattu" % MODEL)
    command = [uv, "run", "--no-project", "--quiet", "--python", "3.12"]
    for package in PACKAGES:
        command += ["--with", package]
    command += ["python", "-I", str(HELPER), str(MODEL), str(cover), str(folder), name]
    try:
        done = subprocess.run(command, capture_output=True, text=True, timeout=timeout, cwd=folder)
    except subprocess.TimeoutExpired:
        raise DepthError("making the cover's depth map took too long") from None
    lines = done.stdout.strip().splitlines()
    try:
        result = json.loads(lines[-1]) if done.returncode == 0 and lines else None
    except ValueError:
        result = None
    if not isinstance(result, dict):
        detail = (done.stderr.strip().splitlines() or ["exit %d" % done.returncode])[-1]
        raise DepthError("couldn't make the cover's depth map: %s" % detail)
    result["from"] = made_from
    temp = record.with_suffix(".json.part")
    temp.write_text(json.dumps(result))
    temp.replace(record)
    _forget_old(folder)
    return result


# ---------------------------------------------------------------- the helper

def _save(image, path, **options):
    temp = path.with_name(path.name + ".part")
    image.save(temp, format=options.pop("format", "PNG"), **options)
    temp.replace(path)


def _run(model, cover, folder, name):
    import numpy as np
    import onnxruntime
    from PIL import Image

    with Image.open(cover) as opened:
        picture = opened.convert("RGB")
    picture = picture.crop(cover_clip(*picture.size))
    if picture.width > PICTURE_SIDE:
        picture = picture.resize((PICTURE_SIDE, PICTURE_SIDE), Image.LANCZOS)

    small = picture.resize((MASK_SIDE, MASK_SIDE), Image.BICUBIC)
    shape = (1, 3, MASK_SIDE, MASK_SIDE)
    pixels = np.asarray(small, dtype=np.float32)
    pixels = pixels / max(1.0, float(pixels.max()))
    pixels = (pixels - np.array([0.485, 0.456, 0.406], np.float32)) / np.array([0.229, 0.224, 0.225], np.float32)
    session = onnxruntime.InferenceSession(str(model), providers=["CPUExecutionProvider"])
    guess = session.run(None, {session.get_inputs()[0].name: pixels.transpose(2, 0, 1).reshape(shape)})[0]
    found = clean_mask(guess.reshape(-1).astype(float).tolist(), MASK_SIDE)

    rgb = picture.resize((DEPTH_SIDE, DEPTH_SIDE), Image.BOX).tobytes()
    if found is None:
        depth, shadow, subject = depth_map(rgb, DEPTH_SIDE)
        result = {"subject": False, "centre": [round(v, 4) for v in depth_centre(depth, DEPTH_SIDE)]}
    else:
        alpha, centre, area = found
        depth, shadow, subject = depth_map(rgb, DEPTH_SIDE, shrink(alpha, MASK_SIDE, DEPTH_SIDE))
        result = {"subject": True, "centre": [round(centre[0], 4), round(centre[1], 4)], "area": round(area, 4)}

    folder = Path(folder)
    shown, depth_file = folder / (name + ".picture.jpg"), folder / (name + ".depth.png")
    _save(picture, shown, format="JPEG", quality=92)
    _save(Image.frombytes("RGB", (DEPTH_SIDE, DEPTH_SIDE), depth_pixels(depth, shadow, subject)), depth_file)
    return dict(result, picture=str(shown), depth=str(depth_file))


if __name__ == "__main__":
    if len(sys.argv) != 5:
        sys.exit("usage: depth.py MODEL COVER OUT_DIR NAME")
    print(json.dumps(_run(*sys.argv[1:])))
