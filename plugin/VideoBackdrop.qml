import QtQuick
import QtQuick.Effects
import QtMultimedia

// The song's video behind Now Playing: silent, blurred and kept in time with
// the music (which mpv plays). `paattu video` finds it: the smallest H.264
// picture, about 1 MB a minute. AppWindow loads this file by name, so a
// system without Qt Multimedia only goes without the video.
Item {
  id: root

  required property var app
  readonly property var player: app.player
  // The song: mpv's link for it.
  readonly property string target: player.hasTrack ? player.path : ""
  readonly property real speed: (app.store.config.sound || {}).speed || 1
  // The video's length: one found by search can be shorter than the song.
  property real length: 0
  // Past the end of a shorter video: it fades out.
  readonly property bool over: length > 0 && player.position >= length
  property bool shown: false
  // Videos found this session, by link: {url, duration, expires}, or null
  // for none. Errors aren't remembered, so the song is tried again next time.
  property var found: ({})
  // After a seek, the video gets a moment to get there before it's checked again.
  property real settledAt: 0
  // The song whose video link failed and was looked up again.
  property string retried: ""

  clip: true
  opacity: shown && !over ? 1 : 0
  Behavior on opacity { NumberAnimation { duration: 900; easing.type: Easing.InOutQuad } }

  onTargetChanged: {
    shown = false
    length = 0
    media.stop()
    media.source = ""
    // Skipping through songs doesn't look each one up.
    findSoon.restart()
  }
  Component.onCompleted: findSoon.restart()

  Timer {
    id: findSoon
    interval: 1200
    onTriggered: root.find()
  }

  function find() {
    var asked = target
    if (!asked) return
    var known = found[asked]
    if (known !== undefined && (!known || !known.expires || known.expires * 1000 > Date.now() + 10 * 60000)) {
      use(known)
      return
    }
    lookups.run(["video", "--", asked], "", function(ok, e) {
      var video = ok ? (e.video || null) : null
      if (ok) {
        var next = root.found
        next[asked] = video
        root.found = next
      }
      if (asked === root.target) root.use(video)
    })
  }

  function use(video) {
    if (!video || !video.url) return
    length = video.duration || 0
    media.source = video.url
    media.playbackRate = speed
    // Loading takes a moment, which the music plays on through.
    media.play()
    if (!player.playing) media.pause()
  }

  // A link that stopped working (expired, or the network's address changed):
  // look the song up again, once.
  function failed() {
    var next = found
    delete next[target]
    found = next
    shown = false
    media.source = ""
    if (retried === target) return
    retried = target
    findSoon.restart()
  }

  // Follow the music: playing or not, its speed and its place.
  function keepInStep() {
    if (media.source == "" || !media.hasVideo) return
    if (over) {
      if (media.playbackState === MediaPlayer.PlayingState) media.pause()
      return
    }
    if (player.playing && media.playbackState !== MediaPlayer.PlayingState) media.play()
    else if (!player.playing && media.playbackState === MediaPlayer.PlayingState) media.pause()
    if (media.playbackRate !== speed) media.playbackRate = speed
    if (Date.now() < settledAt || !media.seekable) return
    // The bar's position is up to a second old: ask mpv where it is now.
    player.send(["get_property", "time-pos"], function(value) {
      if (value === null || media.source == "") return
      var music = Number(value) * 1000
      if (Math.abs(media.position - music) > 450) {
        root.settledAt = Date.now() + 3000
        // A seek lands about half a second short of where it was asked.
        media.position = music + 400
      } else if (!root.shown) {
        root.shown = true
      }
    })
  }

  Timer {
    interval: 1000
    repeat: true
    running: media.source != ""
    onTriggered: root.keepInStep()
  }

  Connections {
    target: root.player
    function onPausedChanged() { root.keepInStep() }
  }

  Jobs { id: lookups }

  MediaPlayer {
    id: media
    // No audioOutput: the video stays silent.
    videoOutput: picture
    onErrorOccurred: root.failed()
    onMediaStatusChanged: if (mediaStatus === MediaPlayer.LoadedMedia || mediaStatus === MediaPlayer.BufferedMedia) root.keepInStep()
  }

  // Bigger than the window, so the blur's soft edges fall outside it.
  VideoOutput {
    id: picture
    anchors.fill: parent
    anchors.margins: -60
    fillMode: VideoOutput.PreserveAspectCrop
    layer.enabled: true
    layer.effect: MultiEffect {
      blurEnabled: true
      blurMax: 64
      blur: 1
      saturation: -0.1
      brightness: -0.12
    }
  }
}
