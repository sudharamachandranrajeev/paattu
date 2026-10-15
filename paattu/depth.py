"""The subject of a song's cover lifted out of it, for the cover in 3D in the
app window's Now Playing (Settings > Cover in 3D).

U²-Net's small model (models/u2netp.onnx) guesses which pixels are the
subject, and the guess is cleaned up the way the Flutter app does it
(app/lib/src/subject.dart), so both lift the same covers. Two pictures come
out: the subject alone (see-through elsewhere) and the rest of the cover,
softened and darkened a little, with the subject's shadow on it.

ONNX Runtime, NumPy and Pillow aren't needed for anything else, so the work
runs in its own process with them from uv (fetched the first time, then
cached by uv):

    python depth.py MODEL COVER OUT_DIR NAME

prints {"subject": ..., "back": ..., "centre": [x, y], "area": a}, or
{"subject": null} for a cover without a subject to lift. This file only uses
the standard library at the top, so the CLI and the tests can import it.
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
# Bumped when the pictures change, so cached ones are made again.
VERSION = 2
# Covers whose pictures are kept (the oldest go).
KEEP = 300
# How the subject is shown (the app's DepthCover.qml, the Flutter app's
# depth_cover.dart): this much bigger, about its centre, moving up to LEAN of
# the cover's side as it leans, on a cover rounded about CORNER of its side.
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
        for path in (old, old.with_suffix(".subject.png"), old.with_suffix(".back.png")):
            path.unlink(missing_ok=True)


def lift(cover, folder, name, timeout=300):
    """The pictures for `cover` (a file), made once and kept in `folder` as
    NAME.subject.png and NAME.back.png with NAME.json beside them."""
    folder.mkdir(parents=True, exist_ok=True)
    record = folder / (name + ".json")
    stamp = cover.stat()
    made_from = [stamp.st_size, stamp.st_mtime_ns, VERSION]
    try:
        known = json.loads(record.read_text())
        if known.get("from") == made_from and (not known.get("subject") or Path(known["subject"]).exists()):
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
        raise DepthError("finding the cover's subject took too long") from None
    lines = done.stdout.strip().splitlines()
    try:
        result = json.loads(lines[-1]) if done.returncode == 0 and lines else None
    except ValueError:
        result = None
    if not isinstance(result, dict):
        detail = (done.stderr.strip().splitlines() or ["exit %d" % done.returncode])[-1]
        raise DepthError("couldn't find the cover's subject: %s" % detail)
    result["from"] = made_from
    temp = record.with_suffix(".json.part")
    temp.write_text(json.dumps(result))
    temp.replace(record)
    _forget_old(folder)
    return result


# ---------------------------------------------------------------- the helper

def _save(image, path):
    temp = path.with_name(path.name + ".part")
    image.save(temp, format="PNG")
    temp.replace(path)


def _run(model, cover, folder, name):
    import numpy as np
    import onnxruntime
    from PIL import Image, ImageFilter

    with Image.open(cover) as opened:
        picture = opened.convert("RGB")
    picture = picture.crop(cover_clip(*picture.size))
    if picture.width > PICTURE_SIDE:
        picture = picture.resize((PICTURE_SIDE, PICTURE_SIDE), Image.LANCZOS)
    side = picture.width

    small = picture.resize((MASK_SIDE, MASK_SIDE), Image.BICUBIC)
    shape = (1, 3, MASK_SIDE, MASK_SIDE)
    pixels = np.asarray(small, dtype=np.float32)
    pixels = pixels / max(1.0, float(pixels.max()))
    pixels = (pixels - np.array([0.485, 0.456, 0.406], np.float32)) / np.array([0.229, 0.224, 0.225], np.float32)
    session = onnxruntime.InferenceSession(str(model), providers=["CPUExecutionProvider"])
    guess = session.run(None, {session.get_inputs()[0].name: pixels.transpose(2, 0, 1).reshape(shape)})[0]
    found = clean_mask(guess.reshape(-1).astype(float).tolist(), MASK_SIDE)
    if found is None:
        return {"subject": None}
    alpha, centre, area = found

    mask = Image.fromarray((np.clip(np.array(alpha, np.float32), 0, 1) * 255 + 0.5).astype(np.uint8)
                           .reshape(MASK_SIDE, MASK_SIDE))
    subject = picture.convert("RGBA")
    subject.putalpha(mask.resize((side, side), Image.BILINEAR))

    # The rest of the cover: softened, darkened a little, and the subject's
    # shadow falling just below it.
    back = picture.filter(ImageFilter.GaussianBlur(3 * side / PICTURE_SIDE))
    back = Image.blend(back, Image.new("RGB", back.size), 0.15)
    shadow = mask.filter(ImageFilter.GaussianBlur(7)).resize((side, side), Image.BILINEAR)
    shadow = shadow.point(lambda v: round(v * 0.55))
    drop = round(side * 0.015)
    fall = Image.new("L", (side, side))
    fall.paste(shadow.crop((0, 0, side, side - drop)), (0, drop))
    back.paste(Image.new("RGB", back.size), (0, 0), fall)

    folder = Path(folder)
    _save(subject, folder / (name + ".subject.png"))
    _save(back, folder / (name + ".back.png"))
    return {"subject": str(folder / (name + ".subject.png")), "back": str(folder / (name + ".back.png")),
            "centre": [round(centre[0], 4), round(centre[1], 4)], "area": round(area, 4)}


if __name__ == "__main__":
    if len(sys.argv) != 5:
        sys.exit("usage: depth.py MODEL COVER OUT_DIR NAME")
    print(json.dumps(_run(*sys.argv[1:])))
