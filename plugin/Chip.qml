import QtQuick

// A pill button: optional glyph + label.
Rectangle {
  id: root

  property string text: ""
  property string glyph: ""
  property color textColor: "#ffffff"
  property color accent: "#ffffff"
  property bool selected: false
  property real fontSize: 12
  property string fontFamily: "monospace"
  readonly property bool hovered: mouse.containsMouse

  signal clicked()

  implicitWidth: row.implicitWidth + fontSize * 1.6
  implicitHeight: Math.round(fontSize * 2.3)
  radius: height / 2
  color: selected ? Qt.rgba(accent.r, accent.g, accent.b, 0.22)
    : Qt.rgba(textColor.r, textColor.g, textColor.b, mouse.containsMouse ? 0.14 : 0.07)
  border.width: 1
  border.color: selected ? Qt.rgba(accent.r, accent.g, accent.b, 0.7) : Qt.rgba(textColor.r, textColor.g, textColor.b, 0.12)
  scale: mouse.pressed ? 0.96 : 1
  opacity: enabled ? 1 : 0.45
  Behavior on color { ColorAnimation { duration: 120 } }
  Behavior on scale { NumberAnimation { duration: 90 } }

  Row {
    id: row
    anchors.centerIn: parent
    spacing: root.fontSize * 0.45

    Text {
      anchors.verticalCenter: parent.verticalCenter
      visible: root.glyph !== ""
      textFormat: Text.PlainText
      text: root.glyph
      color: root.selected ? root.accent : root.textColor
      font.family: root.fontFamily
      font.pixelSize: root.fontSize * 1.15
    }

    Text {
      anchors.verticalCenter: parent.verticalCenter
      visible: root.text !== ""
      textFormat: Text.PlainText
      text: root.text
      color: root.selected ? root.accent : root.textColor
      font.family: root.fontFamily
      font.pixelSize: root.fontSize
    }
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: root.clicked()
  }
}
