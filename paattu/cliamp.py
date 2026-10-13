"""Share the library with cliamp: each saved playlist becomes a cliamp TOML playlist.

cliamp (Super+Shift+Alt+M) then plays the same Malayalam / Tamil library in
the terminal, with its Winamp-style EQ and visualizer.
"""

import re

from . import library, paths
from .sources import track_url

PREFIX = "Paattu - "


def _toml_string(value):
    return '"' + str(value).replace("\\", "\\\\").replace('"', '\\"').replace("\n", " ") + '"'


def playlist_toml(tracks):
    lines = []
    for track in tracks:
        lines.append("[[track]]")
        lines.append("path = " + _toml_string(track_url(track)))
        lines.append("title = " + _toml_string(track.get("title") or track.get("rawTitle", "")))
        artist = ", ".join(track.get("credits") or []) or track.get("channel", "")
        if artist:
            lines.append("artist = " + _toml_string(artist))
        if track.get("movie"):
            lines.append("album = " + _toml_string(track["movie"]))
        if track.get("duration"):
            lines.append("duration_secs = %d" % int(track["duration"]))
        lines.append("")
    return "\n".join(lines)


def file_name(playlist):
    title = playlist["title"]
    if playlist.get("auto") and playlist.get("ownerName"):
        title = playlist["ownerName"] + " - " + title
    name = PREFIX + (playlist.get("language") + " - " if playlist.get("language") else "") + title
    return re.sub(r"[/\\:\0]+", " ", name).strip()[:120] + ".toml"


def export(data, language=None):
    """Write every saved, fetched playlist; remove exports that are gone. Returns names written."""
    paths.CLIAMP_PLAYLISTS.mkdir(parents=True, exist_ok=True)
    written = set()
    for playlist in data["playlists"].values():
        if not playlist.get("saved") or playlist.get("tracks") is None:
            continue
        if language and playlist.get("language") != language:
            continue
        tracks = library.playlist_tracks(data, playlist["id"])
        if not tracks:
            continue
        name = file_name(playlist)
        (paths.CLIAMP_PLAYLISTS / name).write_text(playlist_toml(tracks), encoding="utf-8")
        written.add(name)
    if not language:
        for old in paths.CLIAMP_PLAYLISTS.glob(PREFIX + "*.toml"):
            if old.name not in written:
                old.unlink()
    return sorted(written)
