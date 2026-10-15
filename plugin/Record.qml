import QtQuick
import "Model.js" as Model

// A record with the song's cover as its label, turning while `spinning`:
// the desktop widget's vinyl style and Now Playing's record style.
Item {
  id: root

  property string source: ""
  property int revision: 0
  property bool spinning: false
  // One turn, in milliseconds.
  property int turn: 1800
  property color labelTint: "#333333"
  property color glyphColor: "#ffffff"
  property color holeColor: "#000000"
  property string fontFamily: "monospace"
  readonly property real disc: Math.min(width, height)

  Item {
    id: spinner
    anchors.centerIn: parent
    width: root.disc
    height: root.disc

    Rectangle {
      anchors.fill: parent
      radius: width / 2
      gradient: Gradient {
        GradientStop { position: 0.0; color: "#1c1c1f" }
        GradientStop { position: 0.5; color: "#0b0b0c" }
        GradientStop { position: 1.0; color: "#1a1a1d" }
      }
    }

    // Grooves
    Repeater {
      model: 9
      Rectangle {
        required property int index
        anchors.centerIn: parent
        width: root.disc * (0.92 - index * 0.055)
        height: width
        radius: width / 2
        color: "transparent"
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, index % 2 ? 0.035 : 0.06)
      }
    }

    // Sheen
    Rectangle {
      anchors.centerIn: parent
      width: parent.width * 0.96
      height: width
      radius: width / 2
      rotation: 35
      gradient: Gradient {
        GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0.0) }
        GradientStop { position: 0.45; color: Qt.rgba(1, 1, 1, 0.07) }
        GradientStop { position: 0.55; color: Qt.rgba(1, 1, 1, 0.0) }
      }
    }

    Cover {
      anchors.centerIn: parent
      width: root.disc * 0.4
      height: width
      circle: true
      source: root.source
      revision: root.revision
      tint: root.labelTint
      glyphColor: root.glyphColor
      glyph: Model.GLYPH_NOTE
      fontFamily: root.fontFamily
    }

    Rectangle {
      anchors.centerIn: parent
      width: Math.max(5, root.disc * 0.042)
      height: width
      radius: width / 2
      color: root.holeColor
      border.width: 1
      border.color: Qt.rgba(1, 1, 1, 0.25)
    }

    RotationAnimator on rotation {
      from: 0
      to: 360
      duration: root.turn
      loops: Animation.Infinite
      running: root.spinning
      paused: running && !root.spinning
    }
  }
}
