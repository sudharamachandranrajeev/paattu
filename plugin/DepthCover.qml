import QtQuick
import QtQuick.Window
import "Model.js" as Model

// A song's cover in 3D (Settings › Cover in 3D). It tilts towards the pointer
// moving over it, drifting slowly when nothing moves it, and the picture has
// depth: `paattu depth` (paattu/depth.py) makes a soft map of how near each
// point of it is, and a shader (shaders/DepthCover.frag) moves each point by
// that as the cover leans, so its subject glides over what is behind it in
// one piece, with no cut-out edge to show. A cover without a subject is
// taken as layers of its own colours, which also drift slowly past each
// other under a slow sheen. On Now Playing the near parts swell a little on
// each beat while the rest breathes with the loudness. The effect eases in
// over the plain cover once the map is ready, and the software renderer
// (which has no shaders) shows the plain cover tilting.
Item {
  id: root

  required property var app
  property string trackId: ""
  property real radius: 32
  property color tint: "#333333"
  property color glyphColor: "#ffffff"
  property string glyph: Model.GLYPH_NOTE
  // The song's loudness and beat, 0 to 1 (NowPlayingPage).
  property real beatLevel: 0
  property real beatPunch: 0

  // `paattu depth`'s answer: {picture, depth, subject, centre: [x, y]}, for `foundFor`.
  property var found: null
  property string foundFor: ""
  readonly property bool fancy: GraphicsInfo.api !== GraphicsInfo.Software
  readonly property bool mapped: fancy && found !== null && foundFor === trackId && trackId !== ""
  // How far the cover leans, -1 to 1 across and down, and where the pointer
  // would have it lean.
  property point tilt: Qt.point(0, 0)
  property point aim: Qt.point(0, 0)
  property real movedAt: 0
  // A song came while another was being looked at.
  property bool again: false

  onTrackIdChanged: findSoon.restart()
  Component.onCompleted: findSoon.restart()

  // Skipping through songs doesn't look at every cover.
  Timer {
    id: findSoon
    interval: 600
    onTriggered: root.find()
  }

  Jobs { id: depthJobs }

  function find() {
    var asked = trackId
    if (!asked || foundFor === asked || !fancy) return
    if (depthJobs.busy) {
      again = true
      return
    }
    // The cover's art may still be on its way: `paattu depth` fetches it then.
    depthJobs.run(["depth", "--", asked], "", function(ok, e) {
      if (ok && e.depth) {
        root.found = e
        root.foundFor = asked
      } else if (!ok) {
        console.warn("paattu: cover in 3D: " + (e && e.message || "failed"))
      }
      if (root.again) {
        root.again = false
        root.find()
      }
    })
  }

  HoverHandler {
    id: hover
    onPointChanged: {
      if (!hovered || root.width <= 0 || root.height <= 0) return
      var at = point.position
      root.aim = Qt.point(Math.max(-1, Math.min(1, at.x / root.width * 2 - 1)),
                          Math.max(-1, Math.min(1, at.y / root.height * 2 - 1)))
      root.movedAt = Date.now()
    }
    onHoveredChanged: if (!hovered) root.aim = Qt.point(0, 0)
  }

  FrameAnimation {
    running: root.visible && root.Window.window !== null && root.Window.window.visible
    onTriggered: {
      // A few still seconds after the pointer left, the cover drifts on its own.
      var still = Date.now() - root.movedAt > 3000
      var aim = still ? Qt.point(Math.sin(elapsedTime * 0.45) * 0.35, Math.cos(elapsedTime * 0.31) * 0.25) : root.aim
      var k = 1 - Math.exp(-frameTime * 5)
      var x = root.tilt.x + (aim.x - root.tilt.x) * k
      var y = root.tilt.y + (aim.y - root.tilt.y) * k
      if (Math.abs(x - root.tilt.x) + Math.abs(y - root.tilt.y) > 0.0004) root.tilt = Qt.point(x, y)
      if (depth.visible) depth.clock = elapsedTime
    }
  }

  Item {
    id: card
    anchors.fill: parent
    // The edge nearest the pointer comes forward (Rotation adds perspective).
    transform: [
      Rotation {
        origin.x: card.width / 2
        origin.y: card.height / 2
        axis { x: 1; y: 0; z: 0 }
        angle: root.tilt.y * 11.5
      },
      Rotation {
        origin.x: card.width / 2
        origin.y: card.height / 2
        axis { x: 0; y: 1; z: 0 }
        angle: -root.tilt.x * 11.5
      }
    ]

    Cover {
      anchors.fill: parent
      visible: depth.opacity < 1
      radius: root.radius
      source: root.trackId ? root.app.store.artFor("v", root.trackId) : ""
      revision: root.app.artRevision
      tint: root.tint
      glyphColor: root.glyphColor
      glyph: root.glyph
      fontFamily: root.app.fontFamily
    }

    // The cover square (as Cover crops it) and its depth map, for the shader:
    // the last song's while the next one's are made.
    Image {
      id: picture
      visible: false
      asynchronous: true
      smooth: true
      mipmap: true
      source: root.found ? "file://" + root.found.picture : ""
    }
    Image {
      id: depthMap
      visible: false
      asynchronous: true
      smooth: true
      source: root.found ? "file://" + root.found.depth : ""
    }

    ShaderEffect {
      id: depth
      readonly property bool ready: root.mapped && picture.status === Image.Ready && depthMap.status === Image.Ready
      anchors.fill: parent
      visible: opacity > 0
      // Fading out (another song) the old cover leaves over the new one.
      opacity: ready ? 1 : 0
      Behavior on opacity { NumberAnimation { duration: 400 } }

      property var picture: picture
      property var depthMap: depthMap
      property point tilt: root.tilt
      property point centre: root.found && root.found.centre ? Qt.point(root.found.centre[0], root.found.centre[1])
                                                             : Qt.point(0.5, 0.5)
      // Eases in over the plain cover, which it matches at 0.
      property real strength: ready ? 1 : 0
      Behavior on strength { NumberAnimation { duration: 1200; easing.type: Easing.InOutCubic } }
      property real punch: root.beatPunch
      property real level: root.beatLevel
      property real clock: 0
      // A subject stands still but for a breath; layers drift.
      property real flow: root.found && !root.found.subject ? 1 : 0.25
      property real corner: width > 0 ? Math.min(0.5, root.radius / width) : 0
      property real side: width
      fragmentShader: "DepthCover.frag.qsb"
    }
  }
}
