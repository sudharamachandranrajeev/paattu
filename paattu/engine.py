"""The playback engine: a headless mpv (paattu-engine.service) driven over JSON IPC.

mpv resolves YouTube through yt-dlp and plays the audio stream directly, so
there is no YouTube player page and no ads. mpv-mpris publishes it over MPRIS,
which is what Omarchy's media keys and OSD talk to.
"""

import json
import random
import shutil
import socket
import subprocess
import time

from . import config, paths, sound
from .titles import song_key
from .sources import track_url

SERVICE = "paattu-engine.service"
OPENSNITCH_RULES = "/etc/opensnitchd/rules"
FIREWALL_RULE = "003-paattu-allow-youtube.json"


class EngineError(Exception):
    pass


def _systemctl(*args):
    """systemctl's exit code, or None without systemd (other inits, containers)."""
    if not shutil.which("systemctl"):
        return None
    return subprocess.run(["systemctl", *args], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode


def firewall_status():
    """'ok', 'blocked' (a saved OpenSnitch rule denies mpv), 'ask' (OpenSnitch
    will prompt for mpv), or 'none' (no OpenSnitch)."""
    import os
    try:
        names = os.listdir(OPENSNITCH_RULES)
    except OSError:
        return "none"
    if _systemctl("is-active", "--quiet", "opensnitchd.service") not in (0, None):
        return "none"
    if FIREWALL_RULE in names:
        return "ok"  # precedence rule, sorts before any saved deny
    if any(n.startswith(("deny-", "reject-")) and n.endswith("-usr-bin-mpv.json") for n in names):
        return "blocked"
    if any(n.startswith("allow-") and n.endswith("-usr-bin-mpv.json") for n in names):
        return "ok"
    return "ask"


def _connect():
    sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    sock.settimeout(5)
    sock.connect(str(paths.SOCKET))
    return sock


def running():
    try:
        _connect().close()
        return True
    except OSError:
        return False


def start(wait=6.0):
    """Start the engine if it isn't up. Returns once its socket answers."""
    if running():
        return
    paths.RUNTIME.mkdir(parents=True, exist_ok=True)
    if _systemctl("--user", "start", SERVICE) != 0:
        # No unit (no systemd, or running from the source tree): start mpv directly.
        if not shutil.which("mpv"):
            raise EngineError("mpv is not installed")
        subprocess.Popen(mpv_command(), stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                         stderr=subprocess.DEVNULL, start_new_session=True)
    deadline = time.monotonic() + wait
    while time.monotonic() < deadline:
        if running():
            return
        time.sleep(0.1)
    raise EngineError("the engine didn't start; try: mpv --version, then paattu engine restart"
                      if not shutil.which("systemctl") else "the engine didn't start; see: journalctl --user -u " + SERVICE)


def stop():
    _systemctl("--user", "stop", SERVICE)
    if running():
        with _connect() as sock:
            sock.sendall(b'{"command":["quit"]}\n')


def mpv_command():
    return ["mpv", "--config-dir=" + str(paths.MPV_CONFIG), "--input-ipc-server=" + str(paths.SOCKET)]


class Engine:
    """One IPC connection; commands are answered in order."""

    def __init__(self, autostart=True):
        if autostart:
            start()
        try:
            self.sock = _connect()
        except OSError:
            raise EngineError("the engine isn't running (paattu engine start)")
        self.buffer = b""
        self.next_id = 1

    def close(self):
        self.sock.close()

    def __enter__(self):
        return self

    def __exit__(self, *exc):
        self.close()

    def _reply(self, request_id):
        while True:
            while b"\n" not in self.buffer:
                try:
                    chunk = self.sock.recv(65536)
                except TimeoutError:
                    raise EngineError("the engine stopped answering; try: paattu engine restart")
                if not chunk:
                    raise EngineError("the engine closed the connection")
                self.buffer += chunk
            line, self.buffer = self.buffer.split(b"\n", 1)
            message = json.loads(line)
            if message.get("request_id") == request_id:
                return message

    def send(self, command):
        request_id = self.next_id
        self.next_id += 1
        self.sock.sendall(json.dumps({"command": command, "request_id": request_id}).encode() + b"\n")
        reply = self._reply(request_id)
        if reply.get("error") != "success":
            raise EngineError(f"{command!r}: {reply.get('error')}")
        return reply.get("data")

    BATCH = 200

    def batch(self, commands):
        """Send many commands, reading the answers as we go.

        mpv stops reading a client whose replies it can't write, so sending
        a whole mix (thousands of loadfiles) before reading deadlocks once the
        socket buffers fill. Chunks of BATCH keep both sides moving.
        """
        replies = []
        for at in range(0, len(commands), self.BATCH):
            first = self.next_id
            payload = b""
            for command in commands[at:at + self.BATCH]:
                payload += json.dumps({"command": command, "request_id": self.next_id}).encode() + b"\n"
                self.next_id += 1
            try:
                self.sock.sendall(payload)
            except TimeoutError:
                raise EngineError("the engine stopped answering; try: paattu engine restart")
            replies += [self._reply(i) for i in range(first, self.next_id)]
        return replies

    def get(self, prop, default=None):
        try:
            return self.send(["get_property", prop])
        except EngineError:
            return default

    def set(self, prop, value):
        return self.send(["set_property", prop, value])


# ---------------------------------------------------------------- queues

def queue_tracks(tracks, dedupe=True, skip_trailers=True):
    """Tracks worth queueing: no trailers, one upload per song."""
    out, seen = [], set()
    for track in tracks:
        if skip_trailers and track.get("kind") == "trailer":
            continue
        key = song_key(track)
        if dedupe and key in seen and track.get("title"):
            continue
        seen.add(key)
        out.append(track)
    return out


def display_title(track):
    title = track.get("title") or track.get("rawTitle") or track.get("id", "")
    return title + (" · " + track["movie"] if track.get("movie") else "")


def load(engine, tracks, start=0, shuffle=False, source=None):
    """Replace the queue with tracks and start playing tracks[start]."""
    if not tracks:
        raise EngineError("nothing to play")
    # The sound settings, in case the engine started (or restarted) since.
    sound.apply(engine, config.load()["sound"])
    start = max(0, min(start, len(tracks) - 1))
    order = list(range(len(tracks)))
    if shuffle:
        rest = [i for i in order if i != start]
        random.shuffle(rest)
        order = [start] + rest
        start = 0
    commands = [["stop"]]
    for i in order:
        track = tracks[i]
        commands.append({"name": "loadfile", "url": track_url(track), "flags": "append",
                         "options": {"force-media-title": display_title(track)}})
    commands.append(["set_property", "user-data/paattu/source", source or {}])
    commands.append(["set_property", "user-data/paattu/shuffle", bool(shuffle)])
    commands.append(["playlist-play-index", start])
    commands.append(["set_property", "pause", False])
    failed = [r for r in engine.batch(commands) if r.get("error") != "success"]
    if len(failed) > 1:  # "stop" on an idle engine is the only expected miss
        raise EngineError("the engine refused %d commands: %s" % (len(failed), failed[-1].get("error")))


def enqueue(engine, tracks, next_up=False):
    """Add tracks after the current one (next_up) or at the end."""
    pos = engine.get("playlist-pos", -1)
    count = engine.get("playlist-count", 0)
    commands = []
    for offset, track in enumerate(tracks):
        commands.append({"name": "loadfile", "url": track_url(track),
                         "flags": "append-play" if count == 0 and offset == 0 else "append",
                         "options": {"force-media-title": display_title(track)}})
        if next_up and pos is not None and pos >= 0:
            commands.append(["playlist-move", count + offset, pos + 1 + offset])
    engine.batch(commands)


def set_shuffle(engine, value):
    current = bool(engine.get("user-data/paattu/shuffle", False))
    value = (not current) if value == "toggle" else value == "on"
    if value != current:
        engine.send(["playlist-shuffle"] if value else ["playlist-unshuffle"])
        engine.set("user-data/paattu/shuffle", value)
    return value


REPEAT_MODES = ("off", "all", "one")


def repeat_mode(engine):
    if engine.get("loop-file") not in (False, "no", None):
        return "one"
    if engine.get("loop-playlist") not in (False, "no", None):
        return "all"
    return "off"


def set_repeat(engine, mode):
    if mode == "cycle":
        mode = REPEAT_MODES[(REPEAT_MODES.index(repeat_mode(engine)) + 1) % len(REPEAT_MODES)]
    if mode not in REPEAT_MODES:
        raise EngineError("repeat is off, all or one")
    engine.set("loop-file", "inf" if mode == "one" else "no")
    engine.set("loop-playlist", "inf" if mode == "all" else "no")
    return mode


def status(engine):
    path = engine.get("path") or ""
    return {
        "running": True,
        "idle": bool(engine.get("idle-active", True)),
        "paused": bool(engine.get("pause", False)),
        "title": engine.get("media-title") or "",
        "path": path,
        "position": engine.get("time-pos") or 0,
        "duration": engine.get("duration") or 0,
        "volume": engine.get("volume") or 0,
        "index": engine.get("playlist-pos", -1),
        "count": engine.get("playlist-count", 0),
        "shuffle": bool(engine.get("user-data/paattu/shuffle", False)),
        "repeat": repeat_mode(engine),
        "source": engine.get("user-data/paattu/source") or {},
    }
