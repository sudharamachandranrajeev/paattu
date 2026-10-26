import QtQuick
import "Model.js" as Model

// A round icon button: glyph on a soft circle that shows on hover.
Item {
  id: root

  property string glyph: ""
  property color color: "#ffffff"
  property color fill: "transparent"
  property color hoverFill: Qt.rgba(color.r, color.g, color.b, 0.12)
  property real size: 32
  property real glyphScale: 0.55
  property string fontFamily: "monospace"
  property bool active: true
  property string tooltip: ""
  readonly property bool hovered: mouse.containsMouse

  signal clicked()
  signal rightClicked()

  implicitWidth: size
  implicitHeight: size
  opacity: enabled ? (active ? 1 : 0.45) : 0.3

  Rectangle {
    anchors.fill: parent
    radius: width / 2
    color: root.fill.a > 0 ? root.fill : (mouse.containsMouse ? root.hoverFill : "transparent")
    scale: mouse.pressed ? 0.92 : 1
    Behavior on scale { NumberAnimation { duration: 90 } }
    Behavior on color { ColorAnimation { duration: 120 } }
  }

  Text {
    anchors.centerIn: parent
    textFormat: Text.PlainText
    text: root.glyph
    color: root.color
    font.family: root.fontFamily
    font.pixelSize: Math.round(root.size * root.glyphScale)
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: true
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    cursorShape: Qt.PointingHandCursor
    onClicked: function(e) {
      if (e.button === Qt.RightButton) {
        root.rightClicked()
      } else {
        Model.clickSound()
        root.clicked()
      }
    }
  }
}
