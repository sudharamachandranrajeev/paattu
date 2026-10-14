import QtQuick

// A vertical equaliser slider: its value on top, the band underneath. Drag
// or scroll to move it, double-click to put it back to `origin`. `moved`
// follows the pointer; `committed` is the value to keep.
Item {
  id: root

  property real value: 0
  property real from: -12
  property real to: 12
  property real origin: 0
  property real step: 0.5
  property string valueText: ""
  property string label: ""
  property color textColor: "#ffffff"
  property color mutedColor: "#888888"
  property color accent: "#ffffff"
  property string fontFamily: "monospace"
  readonly property bool pressed: mouse.pressed
  // Where the track is, so a curve drawn behind can share its scale.
  readonly property real trackTop: track.y
  readonly property real trackHeight: track.height

  signal moved(real value)
  signal committed(real value)

  implicitWidth: 44
  implicitHeight: 220

  function snap(v) { return Math.max(from, Math.min(to, Math.round(v / step) * step)) }
  function yOf(v) { return (to - v) / (to - from) * track.height }

  Text {
    id: valueLabel
    anchors.horizontalCenter: parent.horizontalCenter
    textFormat: Text.PlainText
    text: root.valueText
    color: root.pressed ? root.accent : root.textColor
    font.family: root.fontFamily
    font.pixelSize: 11
    font.bold: root.pressed
  }

  Item {
    id: track
    anchors.top: valueLabel.bottom
    anchors.topMargin: 12
    anchors.bottom: bandLabel.top
    anchors.bottomMargin: 12
    anchors.horizontalCenter: parent.horizontalCenter
    width: 4

    Rectangle {
      anchors.fill: parent
      radius: 2
      color: Qt.rgba(root.textColor.r, root.textColor.g, root.textColor.b, 0.12)
    }
    // Filled from the origin to the value.
    Rectangle {
      readonly property real fillTop: root.yOf(Math.max(root.value, root.origin))
      y: fillTop
      width: parent.width
      height: Math.max(2, root.yOf(Math.min(root.value, root.origin)) - fillTop)
      radius: 2
      color: root.accent
    }
  }

  Rectangle {
    x: (root.width - width) / 2
    y: track.y + root.yOf(root.value) - height / 2
    width: 16
    height: 16
    radius: 8
    color: root.accent
    border.width: 2
    border.color: Qt.rgba(root.textColor.r, root.textColor.g, root.textColor.b, 0.9)
    scale: root.pressed ? 1.25 : mouse.containsMouse ? 1.1 : 1
    Behavior on scale { NumberAnimation { duration: 90 } }
  }

  Text {
    id: bandLabel
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.bottom: parent.bottom
    textFormat: Text.PlainText
    text: root.label
    color: root.mutedColor
    font.family: root.fontFamily
    font.pixelSize: 11
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    // The release that ends a double-click keeps the reset.
    property bool reset: false
    function at(y) { return root.snap(root.to - (y - track.y) / Math.max(1, track.height) * (root.to - root.from)) }
    onPressed: function(e) { root.moved(at(e.y)) }
    onPositionChanged: function(e) { if (pressed) root.moved(at(e.y)) }
    onReleased: function(e) {
      if (reset) reset = false
      else root.committed(at(e.y))
    }
    onDoubleClicked: {
      reset = true
      root.moved(root.origin)
      root.committed(root.origin)
    }
    onWheel: function(w) {
      root.moved(root.snap(root.value + (w.angleDelta.y > 0 ? root.step : -root.step)))
      wheelTimer.restart()
    }
  }

  // Scrolling saves once it stops.
  Timer {
    id: wheelTimer
    interval: 450
    onTriggered: root.committed(root.value)
  }
}
