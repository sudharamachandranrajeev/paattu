import QtQuick
import QtQuick.Window
import "Model.js" as Model

// A song's cover in 3D (Settings › Cover in 3D). It tilts towards the pointer
// moving over it, drifting slowly when nothing moves it, and its subject (cut
// out by `paattu depth`, paattu/depth.py) stands out of the picture: sharp, a
// little bigger and nearer, over the rest of the cover, softened, with the
// subject's shadow on it. A cover without a subject to lift only tilts.
Item {
  id: root

  required property var app
  property string trackId: ""
  property real radius: 32
  property color tint: "#333333"
  property color glyphColor: "#ffffff"
  property string glyph: Model.GLYPH_NOTE

  // `paattu depth`'s answer: {subject, back, centre: [x, y]}, for `foundFor`.
  property var found: null
  property string foundFor: ""
  readonly property bool lifted: found !== null && foundFor === trackId && trackId !== ""
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
    if (!asked || foundFor === asked) return
    if (depthJobs.busy) {
      again = true
      return
    }
    // The cover's art may still be on its way: `paattu depth` fetches it then.
    depthJobs.run(["depth", "--", asked], "", function(ok, e) {
      if (ok && e.subject) {
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
      radius: root.radius
      source: root.trackId ? root.app.store.artFor("v", root.trackId) : ""
      revision: root.app.artRevision
      tint: root.tint
      glyphColor: root.glyphColor
      glyph: root.glyph
      fontFamily: root.app.fontFamily
      opacity: back.shown ? 0 : 1
      Behavior on opacity { NumberAnimation { duration: 600 } }
    }

    // The rest of the cover, softened, with the subject's shadow.
    Cover {
      id: back
      readonly property bool shown: root.lifted && ready && subject.status === Image.Ready
      anchors.fill: parent
      radius: root.radius
      crop: false
      source: root.lifted ? "file://" + root.found.back : ""
      tint: "transparent"
      glyph: ""
      opacity: shown ? 1 : 0
      Behavior on opacity { NumberAnimation { duration: 600 } }
    }

    // The subject, nearer: bigger, and moving further as the cover leans.
    Image {
      id: subject
      readonly property var centre: root.lifted && root.found.centre ? root.found.centre : [0.5, 0.5]
      anchors.fill: parent
      asynchronous: true
      smooth: true
      mipmap: true
      source: root.lifted ? "file://" + root.found.subject : ""
      opacity: back.opacity
      transform: [
        Scale {
          origin.x: subject.centre[0] * subject.width
          origin.y: subject.centre[1] * subject.height
          xScale: 1.06
          yScale: 1.06
        },
        Translate {
          x: root.tilt.x * card.width * 0.02
          y: root.tilt.y * card.height * 0.02
        }
      ]
    }
  }
}
