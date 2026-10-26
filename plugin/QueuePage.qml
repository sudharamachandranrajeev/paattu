import QtQuick
import QtQuick.Controls
import "Model.js" as Model

// What's queued in the engine. Click to jump, × to drop.
ListView {
  id: root

  required property var app
  readonly property var pal: app.pal
  readonly property var rows: Model.queueRows(app.player.playlist, app.store.tracks)

  clip: true
  model: rows
  leftMargin: 20
  rightMargin: 20
  bottomMargin: 20
  boundsBehavior: Flickable.StopAtBounds
  ScrollBar.vertical: ScrollBar {}

  header: Column {
    x: 8
    width: root.width - 56
    spacing: 4
    bottomPadding: 16
    Text {
      textFormat: Text.PlainText
      text: "Queue"
      color: root.pal.foreground
      font.family: root.app.fontFamily
      font.pixelSize: 28
      font.weight: Font.Black
    }
    Text {
      textFormat: Text.PlainText
      text: root.rows.length
        ? Model.plural(root.rows.length, "song") + (root.app.player.source && root.app.player.source.title ? "  ·  from " + root.app.player.source.title : "")
        : "Nothing queued. Play a playlist or a language mix."
      color: root.pal.muted
      font.family: root.app.fontFamily
      font.pixelSize: 12
    }
  }

  delegate: Item {
    id: row
    required property var modelData
    width: root.width - 40
    height: 46

    TrackRow {
      anchors.fill: parent
      anchors.rightMargin: 40
      app: root.app
      track: root.app.store.tracks[row.modelData.id] || { id: row.modelData.id, title: row.modelData.title, movie: row.modelData.movie }
      number: row.modelData.index + 1
      current: row.modelData.current
      playing: row.modelData.current && root.app.player.playing
      onActivated: root.app.player.playIndex(row.modelData.index)
    }

    GlyphButton {
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      glyph: Model.GLYPH_CLOSE
      size: 30
      color: root.pal.muted
      fontFamily: root.app.fontFamily
      visible: !row.modelData.current
      onClicked: root.app.removeFromQueue(row.modelData.index)
    }
  }
}
