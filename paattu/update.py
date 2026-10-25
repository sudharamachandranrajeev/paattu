"""A newer Paattu for this computer: the releases on GitHub (the ones the app
updates from, see app/lib/src/update.dart), and installing one.

A --dev install (~/.local/lib/paattu a link to a git checkout) updates by
pulling that checkout and running its install.sh --dev; any other by fetching
the release's source and running its install.sh, as installing by hand does.
The shell loads the new window once it's restarted (omarchy restart shell), and
the engine its new script when it next starts.
"""

import re
import subprocess
import tarfile
import tempfile
import urllib.request
from pathlib import Path

from . import __version__, browse, paths

RELEASES = "https://api.github.com/repos/sudharamachandranrajeev/paattu/releases?per_page=20"
SOURCE = "https://github.com/sudharamachandranrajeev/paattu/archive/refs/tags/%s.tar.gz"
LIB = paths.HOME / ".local/lib/paattu"


class UpdateError(Exception):
    pass


def version_parts(version):
    plain = re.sub(r"^[vV]", "", (version or "").strip()).split("-")[0]
    return [int(p) if p.strip().isdigit() else 0 for p in plain.split(".")]


def is_newer(candidate, current):
    """Whether candidate is newer than current, part by part (0.10.0 beats 0.9.9)."""
    a, b = version_parts(candidate), version_parts(current)
    width = max(len(a), len(b))
    return a + [0] * (width - len(a)) > b + [0] * (width - len(b))


def newest(releases):
    """The newest release that isn't a draft, from GitHub's list (every Paattu
    release is a pre-release, so /releases/latest passes over them)."""
    best = None
    for release in releases if isinstance(releases, list) else []:
        version = re.sub(r"^[vV]", "", (release or {}).get("tag_name") or "")
        if release.get("draft") or not version:
            continue
        if best is None or is_newer(version, best["version"]):
            best = {"version": version, "tag": release["tag_name"], "notes": release.get("body") or "",
                    "page": release.get("html_url") or ""}
    return best


def dev_checkout():
    """The git checkout a --dev install runs from, or None."""
    if not LIB.is_symlink():
        return None
    target = LIB.resolve()
    return target if (target / ".git").exists() else None


def check():
    try:
        found = newest(browse._json(RELEASES, headers={"Accept": "application/vnd.github+json"}, timeout=20))
    except Exception as e:  # noqa: BLE001 - offline, or GitHub down
        raise UpdateError("couldn't ask GitHub about a newer Paattu (%s)" % e)
    if not found:
        raise UpdateError("GitHub has no Paattu releases")
    return {"current": __version__, "latest": found["version"], "tag": found["tag"],
            "available": is_newer(found["version"], __version__), "notes": found["notes"].strip(),
            "page": found["page"], "dev": dev_checkout() is not None}


def _run(command, cwd=None):
    proc = subprocess.run(command, cwd=cwd, stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=900)
    if proc.returncode != 0:
        lines = [l for l in (proc.stderr + "\n" + proc.stdout).splitlines() if l.strip()]
        raise UpdateError("%s failed: %s" % (Path(command[0]).name, lines[-1] if lines else "exit %d" % proc.returncode))
    return proc.stdout


def installed_version():
    text = (LIB / "paattu" / "__init__.py").read_text(encoding="utf-8")
    found = re.search(r'__version__\s*=\s*"([^"]+)"', text)
    return found.group(1) if found else "?"


def apply(say=lambda message: None):
    """Install the newest Paattu; the version installed."""
    checkout = dev_checkout()
    if checkout:
        say("Pulling %s…" % checkout)
        _run(["git", "-C", str(checkout), "pull", "--ff-only"])
        say("Installing…")
        _run([str(checkout / "install.sh"), "--dev", "--yes"], cwd=str(checkout))
        return installed_version()
    found = check()
    if not found["available"]:
        raise UpdateError("Paattu %s is the newest" % found["current"])
    with tempfile.TemporaryDirectory(prefix="paattu-update.") as tmp:
        say("Downloading Paattu %s…" % found["latest"])
        archive = Path(tmp) / "source.tar.gz"
        request = urllib.request.Request(SOURCE % found["tag"], headers={"User-Agent": browse.BROWSER})
        with urllib.request.urlopen(request, timeout=60) as response, open(archive, "wb") as f:
            f.write(response.read())
        with tarfile.open(archive) as tar:
            try:
                tar.extractall(tmp, filter="data")
            except TypeError:  # Python before 3.12 and its backports
                tar.extractall(tmp)
        source = next((p for p in Path(tmp).iterdir() if (p / "install.sh").is_file()), None)
        if not source:
            raise UpdateError("the download for Paattu %s has no install.sh" % found["latest"])
        say("Installing Paattu %s…" % found["latest"])
        _run(["bash", str(source / "install.sh"), "--yes"], cwd=str(source))
    return installed_version()
