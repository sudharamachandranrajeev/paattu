import QtQuick
import "Model.js" as Model

// A rounded single-line text field with a glyph and a placeholder.
Rectangle {
  id: root

  required property var app
  property string placeholder: ""
  property string glyph: Model.GLYPH_USER
  property alias text: input.text
  property alias echoMode: input.echoMode
  readonly property var pal: app.pal

  signal accepted()

  function focusInput() { input.forceActiveFocus() }

  height: 36
  radius: 18
  color: Qt.rgba(pal.foreground.r, pal.foreground.g, pal.foreground.b, input.activeFocus ? 0.10 : 0.06)
  border.width: input.activeFocus ? 1 : 0
  border.color: pal.accent

  Text {
    id: icon
    x: 12
    anchors.verticalCenter: parent.verticalCenter
    textFormat: Text.PlainText
    text: root.glyph
    color: root.pal.muted
    font.family: root.app.fontFamily
    font.pixelSize: 14
  }

  TextInput {
    id: input
    anchors.left: icon.right
    anchors.leftMargin: 8
    anchors.right: parent.right
    anchors.rightMargin: 12
    anchors.verticalCenter: parent.verticalCenter
    color: root.pal.foreground
    selectionColor: root.pal.accent
    font.family: root.app.fontFamily
    font.pixelSize: 12
    clip: true
    onAccepted: root.accepted()
    Keys.onEscapePressed: focus = false

    Text {
      anchors.fill: parent
      visible: !input.text
      textFormat: Text.PlainText
      text: root.placeholder
      color: root.pal.muted
      font: input.font
      verticalAlignment: Text.AlignVCenter
      elide: Text.ElideRight
    }
  }

  MouseArea {
    anchors.fill: parent
    z: -1
    cursorShape: Qt.IBeamCursor
    onClicked: input.forceActiveFocus()
  }
}
