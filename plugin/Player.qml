import QtQuick
import Quickshell
import Quickshell.Io
import "Model.js" as Model

// Live connection to the Paattu engine (headless mpv) over its JSON IPC
// socket. Transport controls go straight to mpv; anything that needs the
// library (play a playlist, follow a user) goes through the `paattu` CLI.
Item {
  id: root

  readonly property string runtimeDir: Quickshell.env("XDG_RUNTIME_DIR") || ("/run/user/" + Quickshell.env("UID"))
  readonly property string socketPath: runtimeDir + "/paattu/mpv.sock"
  property bool polling: true

  // The live connection (a Socket), or null between attempts.
  property var socket: null
  readonly property bool connected: !!socket && socket.connected
  property bool idle: true
  property bool paused: true
  property bool buffering: false
  property string path: ""
  property string mediaTitle: ""
  property real position: 0
  property real duration: 0
  property real volume: 80
  property bool muted: false
  property int index: -1
  property int count: 0
  property var playlist: []
  property bool shuffle: false
  property bool loopFile: false
  property bool loopPlaylist: false
  property var source: ({})
  // The song the radio plays songs like ({} when it's off).
  property var radio: ({})
  readonly property bool radioOn: !!(radio && radio.id)

  // The stream's audio, for the quality badge.
  property string audioCodec: ""
  property real demuxBitrate: 0
  property real liveBitrate: 0
  property real sampleRate: 0

  readonly property bool hasTrack: connected && !idle && path !== ""
  readonly property bool playing: hasTrack && !paused
  // The playing song's id: its video id, or for other sites its link made
  // into an id (Model.trackId, same as the CLI).
  readonly property string videoId: Model.trackId(path)
  readonly property bool onYouTube: Model.isVideoId(videoId)
  // "AAC · 320 kbps", "Opus · ~130 kbps", "FLAC · Lossless".
  readonly property string quality: hasTrack ? Model.streamQuality({ codec: audioCodec, demux: demuxBitrate,
    live: liveBitrate, rate: sampleRate }) : ""
  readonly property string repeat: loopFile ? "one" : (loopPlaylist ? "all" : "off")
  readonly property real progress: duration > 0 ? Math.min(1, position / duration) : 0

  signal trackChanged(string videoId)

  property int nextRequest: 1000
  property var pending: ({})

  function send(command, callback) {
    if (!connected) return false
    var id = nextRequest++
    if (callback) {
      var next = pending
      next[id] = callback
      pending = next
    }
    socket.write(JSON.stringify({ command: command, request_id: id }) + "\n")
    socket.flush()
    return true
  }

  function setProperty(name, value) { return send(["set_property", name, value]) }

  // ---------- controls ----------
  function togglePause() { if (hasTrack) send(["cycle", "pause"]) }
  function play() { setProperty("pause", false) }
  function pause() { setProperty("pause", true) }
  function next() { send(["playlist-next", "weak"]) }
  function previous() {
    if (position > 4) send(["seek", 0, "absolute"])
    else send(["playlist-prev", "weak"])
  }
  function seekTo(seconds) { send(["seek", Math.max(0, seconds), "absolute"]); position = Math.max(0, seconds) }
  function seekBy(seconds) { send(["seek", seconds, "relative"]) }
  function seekFraction(f) { if (duration > 0) seekTo(f * duration) }
  function setVolume(v) { volume = Math.max(0, Math.min(100, v)); setProperty("volume", volume) }
  function changeVolume(delta) { setVolume(volume + delta) }
  function toggleMute() { send(["cycle", "mute"]) }
  function playIndex(i) { send(["playlist-play-index", i]); play() }
  function removeIndex(i) { send(["playlist-remove", i]) }
  function stop() { send(["stop"]) }

  function setShuffle(on) {
    if (on === shuffle) return
    send([on ? "playlist-shuffle" : "playlist-unshuffle"])
    setProperty("user-data/paattu/shuffle", on)
  }
  function toggleShuffle() { setShuffle(!shuffle) }

  function setRepeat(mode) {
    setProperty("loop-file", mode === "one" ? "inf" : "no")
    setProperty("loop-playlist", mode === "all" ? "inf" : "no")
  }
  function cycleRepeat() { setRepeat(Model.nextRepeat(repeat)) }

  // ---------- events ----------
  readonly property var observed: [
    "idle-active", "pause", "path", "media-title", "duration", "volume", "mute", "playlist-pos",
    "playlist-count", "playlist", "loop-file", "loop-playlist", "paused-for-cache",
    "user-data/paattu/shuffle", "user-data/paattu/source", "user-data/paattu/radio"
  ]

  function subscribe() {
    for (var i = 0; i < observed.length; i++) send(["observe_property", i + 1, observed[i]])
    pollPosition()
  }

  function apply(name, value) {
    switch (name) {
    case "idle-active": idle = value !== false; if (idle) { position = 0; duration = 0 } break
    case "pause": paused = value === true; break
    case "path":
      var before = Model.trackId(path)
      path = value || ""
      if (Model.trackId(path) !== before) {
        position = 0
        resetQuality()
        trackChanged(Model.trackId(path))
      }
      break
    case "media-title": mediaTitle = value || ""; break
    case "duration": duration = Number(value) || 0; break
    case "volume": volume = Number(value) || 0; break
    case "mute": muted = value === true; break
    case "playlist-pos": index = value === null || value === undefined ? -1 : value; break
    case "playlist-count": count = Number(value) || 0; break
    case "playlist": playlist = value || []; break
    case "loop-file": loopFile = value !== false && value !== "no" && value !== null; break
    case "loop-playlist": loopPlaylist = value !== false && value !== "no" && value !== null; break
    case "paused-for-cache": buffering = value === true; break
    case "user-data/paattu/shuffle": shuffle = value === true; break
    case "user-data/paattu/source": source = value || ({}); break
    case "user-data/paattu/radio": radio = value || ({}); break
    }
  }

  function handleLine(line) {
    var msg = Model.parseEvent(line)
    if (!msg) return
    if (msg.event === "property-change") {
      apply(msg.name, msg.data)
    } else if (msg.request_id !== undefined && pending[msg.request_id]) {
      var callback = pending[msg.request_id]
      var next = pending
      delete next[msg.request_id]
      pending = next
      callback(msg.error === "success" ? msg.data : null, msg.error)
    }
  }

  function pollPosition() {
    send(["get_property", "time-pos"], function(value) { if (value !== null) root.position = Number(value) || 0 })
    pollQuality()
  }

  function resetQuality() {
    audioCodec = ""
    demuxBitrate = 0
    liveBitrate = 0
    sampleRate = 0
  }

  // The codec and the container's bit rate settle once the stream opens; the
  // measured bit rate (VBR Opus has no other) is smoothed so it doesn't flicker.
  function pollQuality() {
    if (!demuxBitrate || !audioCodec) {
      send(["get_property", "audio-codec-name"], function(v) { root.audioCodec = v || "" })
      send(["get_property", "current-tracks/audio/demux-bitrate"], function(v) { root.demuxBitrate = Number(v) || 0 })
      send(["get_property", "audio-params/samplerate"], function(v) { root.sampleRate = Number(v) || 0 })
    }
    if (!demuxBitrate) {
      send(["get_property", "audio-bitrate"], function(v) {
        var now = Number(v) || 0
        if (now > 0) root.liveBitrate = root.liveBitrate > 0 ? root.liveBitrate * 0.8 + now * 0.2 : now
      })
    }
  }

  function resetState() {
    idle = true
    paused = true
    path = ""
    mediaTitle = ""
    position = 0
    duration = 0
    playlist = []
    count = 0
    index = -1
    radio = ({})
    resetQuality()
  }

  onConnectedChanged: {
    pending = ({})
    if (connected) subscribe()
    else resetState()
  }

  Component {
    id: socketComponent
    Socket {
      id: link
      path: root.socketPath
      connected: true
      parser: SplitParser { onRead: function(line) { root.handleLine(line) } }
      onError: root.drop(link)
    }
  }

  // Connect whenever the engine's socket shows up (it starts on demand, and
  // restarts). Quickshell 0.3.1's Socket can't be reused: once a connect fails,
  // toggling `connected` or `path` does nothing, and one that connects while
  // mpv is quitting reports PeerClosedError yet stays "connected". So each
  // attempt is a fresh Socket, and any Socket that errors is dropped.
  function reconnect() {
    drop(socket)
    socket = socketComponent.createObject(root)
  }
  function drop(s) {
    if (!s) return
    if (s === socket) socket = null
    // A failed connect errors inside createObject(), before the Socket can be
    // destroyed ("indestructible object"), so destroy it once that returns.
    Qt.callLater(function() { s.destroy() })
  }

  Component.onCompleted: reconnect()

  // Not straight away after a disconnect: mpv may still be quitting.
  Timer {
    interval: 2000
    running: !root.connected
    repeat: true
    onTriggered: root.reconnect()
  }

  Timer {
    interval: 1000
    running: root.polling && root.connected && root.hasTrack && !root.paused
    repeat: true
    onTriggered: root.pollPosition()
  }
}
