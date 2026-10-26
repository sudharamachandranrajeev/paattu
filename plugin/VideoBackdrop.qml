import QtQuick
import QtQuick.Effects
import QtMultimedia

// The song's video on Now Playing: silent, kept in time with the music
// (which mpv plays), blurred behind it all (unless Settings turns that off)
// and, in video mode, sharp in Now Playing's card (`texture`, drawn there by
// NowPlayingPage). `paattu video` finds it: the smallest H.264 picture, about
// 1 MB a minute, or up to 720p in video mode, where the engine plays the
// video's own sound (paattu.lua), so the picture is held to it closely
// enough for the lips to match. AppWindow loads this file by name, so a
// system without Qt Multimedia only goes without the video.
Item {
  id: root

  required property var app
  readonly property var player: app.player
  // The song: mpv's link for it.
  readonly property string target: player.hasTrack ? player.path : ""
  readonly property bool big: app.store.config.videoMode === true
  readonly property bool blurred: app.store.config.videoBackground !== false
  // The video's picture, for Now Playing's card.
  readonly property alias texture: videoTexture
  // The video showing (its YouTube id), and whether the music is its sound.
  property string videoId: ""
  readonly property bool exact: big && videoId !== "" && player.video === videoId
  // How much faster or slower than the music the picture runs, to catch up.
  property real nudge: 1
  readonly property real speed: (app.store.config.sound || {}).speed || 1
  // Settings › Video blur: 0 (sharp) to 100.
  readonly property real blurLevel: Math.max(0, Math.min(100, Number(app.store.config.videoBlur === undefined ? 30 : app.store.config.videoBlur)))
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

  onTargetChanged: restart()
  onBigChanged: restart()
  Component.onCompleted: findSoon.restart()

  // In video mode the engine found the song's video (or another) to play the
  // sound of: show that one.
  Connections {
    target: root.player
    function onVideoChanged() { if (root.big && root.player.video !== "" && root.player.video !== root.videoId) root.restart() }
  }

  function restart() {
    shown = false
    length = 0
    videoId = ""
    nudge = 1
    media.stop()
    media.source = ""
    // Skipping through songs doesn't look each one up.
    findSoon.restart()
  }

  Timer {
    id: findSoon
    interval: 1200
    onTriggered: root.find()
  }

  function find() {
    var asked = target, height = big ? 720 : 144
    if (!asked) return
    var key = height + " " + asked
    var known = found[key]
    if (known !== undefined && (!known || !known.expires || known.expires * 1000 > Date.now() + 10 * 60000)) {
      use(known)
      return
    }
    lookups.run(["video", "--height", String(height), "--", asked], "", function(ok, e) {
      var video = ok ? (e.video || null) : null
      if (ok) {
        var next = root.found
        next[key] = video
        root.found = next
      }
      if (asked === root.target && height === (root.big ? 720 : 144)) root.use(video)
    })
  }

  function use(video) {
    if (!video || !video.url) return
    videoId = video.id || ""
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
    delete next["144 " + target]
    delete next["720 " + target]
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
    if (media.playbackRate !== speed * nudge) media.playbackRate = speed * nudge
    if (Date.now() < settledAt || !media.seekable || !player.playing) return
    // The bar's position is up to a second old: ask mpv where it is now.
    player.send(["get_property", "time-pos"], function(value) {
      if (value === null || media.source == "") return
      var ahead = media.position - Number(value) * 1000
      if (Math.abs(ahead) > (root.exact ? 600 : 450)) {
        root.settledAt = Date.now() + 3000
        root.nudge = 1
        // A seek lands about half a second short of where it was asked.
        media.position = Number(value) * 1000 + 400
        return
      }
      if (!root.shown) root.shown = true
      // The music is the video's own sound: a small drift is made up by
      // running the picture a little faster or slower (a seek would stutter),
      // as much as it is out, in steps of 2% so the speed changes only a few
      // times as it comes back in line.
      var nudge = !root.exact || Math.abs(ahead) < 40 ? 1 : 1 - Math.round(Math.max(-0.06, Math.min(0.06, ahead / 2000)) * 50) / 50
      if (nudge !== root.nudge) root.nudge = nudge
    })
  }

  Timer {
    interval: root.exact ? 250 : 1000
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

  // The picture as it comes, drawn only through videoTexture: blurred
  // below, and sharp in Now Playing's card. 16 by 9 at the card's size or
  // the window's, whichever is bigger.
  VideoOutput {
    id: picture
    width: Math.max(root.width, 1280)
    height: width * 9 / 16
    fillMode: VideoOutput.PreserveAspectFit
  }
  ShaderEffectSource {
    id: videoTexture
    width: picture.width
    height: picture.height
    sourceItem: picture
    hideSource: true
    live: true
    visible: false
  }

  // Bigger than the window, so the blur's soft edges fall outside it, and
  // cropped to fill it, like a cover.
  MultiEffect {
    readonly property real edge: 8 + root.blurLevel * 1.3
    anchors.centerIn: parent
    width: Math.max(root.width + 2 * edge, (root.height + 2 * edge) * 16 / 9)
    height: width * 9 / 16
    visible: root.blurred
    source: videoTexture
    autoPaddingEnabled: false
    blurEnabled: root.blurLevel > 0
    blurMax: 128
    blur: root.blurLevel / 100
    saturation: -0.1
    brightness: -0.12
  }
}
