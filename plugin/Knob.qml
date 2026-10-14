import QtQuick

// A rotary knob for the tone controls: drag up or down, scroll, or
// double-click to put it back to `origin`, which sits at the top. `moved`
// follows the pointer; `committed` is the value to keep.
Item {
  id: root

  property real value: 0
  property real from: -12
  property real to: 12
  property real origin: 0
  property real step: 0.5
  property string label: ""
  property string valueText: ""
  property color textColor: "#ffffff"
  property color mutedColor: "#888888"
  property color accent: "#ffffff"
  property string fontFamily: "monospace"
  property real size: 68
  readonly property bool pressed: mouse.pressed

  signal moved(real value)
  signal committed(real value)

  implicitWidth: Math.max(size, caption.implicitWidth)
  implicitHeight: size + 8 + caption.implicitHeight

  // How far round the knob is: -1 (all the way left) … 0 (origin) … 1.
  function turnOf(v) {
    return v >= origin ? (to > origin ? (v - origin) / (to - origin) : 0)
      : (origin > from ? -(origin - v) / (origin - from) : 0)
  }
  function snap(v) { return Math.max(from, Math.min(to, Math.round(v / step) * step)) }
  function valueOf(turn) {
    turn = Math.max(-1, Math.min(1, turn))
    return snap(turn >= 0 ? origin + turn * (to - origin) : origin + turn * (origin - from))
  }

  onValueChanged: dial.requestPaint()
  onAccentChanged: dial.requestPaint()
  onTextColorChanged: dial.requestPaint()

  Canvas {
    id: dial
    anchors.horizontalCenter: parent.horizontalCenter
    width: root.size
    height: root.size
    scale: root.pressed ? 1.04 : 1
    Behavior on scale { NumberAnimation { duration: 90 } }

    onPaint: {
      var ctx = getContext("2d")
      ctx.reset()
      var c = width / 2, r = c - 4
      var deg = Math.PI / 180
      // 270° of travel, from the lower left round to the lower right.
      var at = 270 + root.turnOf(root.value) * 135
      var fg = root.textColor
      ctx.lineCap = "round"
      ctx.lineWidth = 4
      ctx.strokeStyle = Qt.rgba(fg.r, fg.g, fg.b, 0.14)
      ctx.beginPath()
      ctx.arc(c, c, r, 135 * deg, 405 * deg, false)
      ctx.stroke()
      if (Math.abs(at - 270) > 0.5) {
        ctx.strokeStyle = root.accent
        ctx.beginPath()
        ctx.arc(c, c, r, Math.min(at, 270) * deg, Math.max(at, 270) * deg, false)
        ctx.stroke()
      }
      ctx.fillStyle = Qt.rgba(fg.r, fg.g, fg.b, mouse.containsMouse || root.pressed ? 0.12 : 0.07)
      ctx.beginPath()
      ctx.arc(c, c, r - 9, 0, 2 * Math.PI, false)
      ctx.fill()
      ctx.fillStyle = root.accent
      ctx.beginPath()
      ctx.arc(c + Math.cos(at * deg) * (r - 15), c + Math.sin(at * deg) * (r - 15), 3, 0, 2 * Math.PI, false)
      ctx.fill()
    }

    Text {
      anchors.centerIn: parent
      textFormat: Text.PlainText
      text: root.valueText
      color: root.pressed ? root.accent : root.textColor
      font.family: root.fontFamily
      font.pixelSize: 12
      font.bold: true
    }

    MouseArea {
      id: mouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.SizeVerCursor
      property real startY: 0
      property real startTurn: 0
      property bool reset: false
      onContainsMouseChanged: dial.requestPaint()
      onPressed: function(e) {
        startY = e.y
        startTurn = root.turnOf(root.value)
        dial.requestPaint()
      }
      // A full turn either way for 150 px.
      onPositionChanged: function(e) {
        if (!pressed) return
        var v = root.valueOf(startTurn + (startY - e.y) / 150)
        if (v !== root.value) root.moved(v)
      }
      onReleased: {
        if (reset) reset = false
        else root.committed(root.value)
        dial.requestPaint()
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
  }

  Text {
    id: caption
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.bottom: parent.bottom
    textFormat: Text.PlainText
    text: root.label
    color: root.mutedColor
    font.family: root.fontFamily
    font.pixelSize: 12
  }

  Timer {
    id: wheelTimer
    interval: 450
    onTriggered: root.committed(root.value)
  }
}
