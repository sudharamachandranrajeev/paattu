import QtQuick
import QtQuick.Controls
import "Model.js" as Model

// Mixes: the shuffle buttons on the bar, the desktop widget and Home, in
// button order. Each shuffles everything in it; open one to change what.
Flickable {
  id: root

  required property var app
  readonly property var pal: app.pal
  readonly property var mixes: app.store.mixes
  readonly property real gutter: 28

  contentWidth: width
  contentHeight: column.implicitHeight + 40
  clip: true
  boundsBehavior: Flickable.StopAtBounds
  ScrollBar.vertical: ScrollBar {}

  Column {
    id: column
    x: root.gutter
    y: 12
    width: root.width - root.gutter * 2
    spacing: 22

    Column {
      width: parent.width
      spacing: 4

      Text {
        textFormat: Text.PlainText
        text: "Mixes"
        color: root.pal.foreground
        font.family: root.app.fontFamily
        font.pixelSize: 34
        font.weight: Font.DemiBold
      }
      Text {
        width: parent.width
        textFormat: Text.PlainText
        wrapMode: Text.WordWrap
        text: "The shuffle buttons on the bar, the desktop widget and Home. Each one shuffles everything "
          + "you put in it: languages, YouTube profiles and playlists."
        color: root.pal.muted
        font.family: root.app.fontFamily
        font.pixelSize: 13
      }
    }

    InputBox {
      width: 280
      app: root.app
      glyph: Model.GLYPH_ADD
      placeholder: "New mix"
      onAccepted: {
        root.app.newMix(text, null, true)
        text = ""
      }
    }

    Column {
      width: parent.width
      spacing: 8

      Repeater {
        model: root.mixes

        Rectangle {
          id: row
          required property var modelData
          required property int index
          // No sources, or none with saved playlists yet: nothing to shuffle.
          readonly property bool empty: !modelData.sources || modelData.sources.length === 0 || !modelData.playlists
          width: column.width
          height: 72
          radius: 24
          color: Qt.rgba(root.pal.foreground.r, root.pal.foreground.g, root.pal.foreground.b, rowHover.hovered ? 0.08 : 0.04)

          HoverHandler { id: rowHover }
          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: root.app.openMix(row.modelData.id)
          }

          GlyphButton {
            id: playButton
            x: 14
            anchors.verticalCenter: parent.verticalCenter
            glyph: Model.GLYPH_SHUFFLE
            size: 44
            color: root.pal.accentText
            fill: root.pal.accent
            fontFamily: root.app.fontFamily
            enabled: !row.empty
            tooltip: "Shuffle " + row.modelData.title
            onClicked: root.app.playMix(row.modelData.id, row.modelData.title)
          }

          Column {
            anchors.left: playButton.right
            anchors.leftMargin: 14
            anchors.right: actions.left
            anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            spacing: 3

            Text {
              width: parent.width
              textFormat: Text.PlainText
              text: row.modelData.title
              color: root.pal.foreground
              font.family: root.app.fontFamily
              font.pixelSize: 15
              font.bold: true
              elide: Text.ElideRight
            }
            Text {
              width: parent.width
              textFormat: Text.PlainText
              text: Model.mixDetail(row.modelData)
              color: root.pal.muted
              font.family: root.app.fontFamily
              font.pixelSize: 12
              elide: Text.ElideRight
            }
          }

          Row {
            id: actions
            anchors.right: parent.right
            anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            spacing: 4

            GlyphButton {
              anchors.verticalCenter: parent.verticalCenter
              glyph: Model.GLYPH_UP
              size: 30
              color: root.pal.muted
              fontFamily: root.app.fontFamily
              enabled: row.index > 0
              tooltip: "Move left on the buttons"
              // Positions are 1-based: this row is index + 1.
              onClicked: root.app.moveMix(row.modelData.id, row.index)
            }
            GlyphButton {
              anchors.verticalCenter: parent.verticalCenter
              glyph: Model.GLYPH_DOWN
              size: 30
              color: root.pal.muted
              fontFamily: root.app.fontFamily
              enabled: row.index < root.mixes.length - 1
              tooltip: "Move right on the buttons"
              onClicked: root.app.moveMix(row.modelData.id, row.index + 2)
            }
            GlyphButton {
              anchors.verticalCenter: parent.verticalCenter
              glyph: Model.GLYPH_EDIT
              size: 30
              color: root.pal.muted
              fontFamily: root.app.fontFamily
              tooltip: "Change what's in it"
              onClicked: root.app.openMix(row.modelData.id)
            }
            RemoveButton {
              anchors.verticalCenter: parent.verticalCenter
              label: ""
              confirmLabel: "Delete?"
              textColor: root.pal.foreground
              fontSize: 12
              fontFamily: root.app.fontFamily
              onConfirmed: root.app.removeMix(row.modelData.id)
            }
          }
        }
      }
    }

    Text {
      visible: root.mixes.length === 0
      width: parent.width
      textFormat: Text.PlainText
      wrapMode: Text.WordWrap
      text: "No mixes. Name one above, then add languages, YouTube profiles or playlists to it."
      color: root.pal.muted
      font.family: root.app.fontFamily
      font.pixelSize: 13
    }
  }
}
