import QtQuick
import QtQuick.Controls
import "Model.js" as Model

// The songs kept on this computer (`paattu offline`): they play with no
// internet, and take over when it goes. Play or shuffle them, keep the song
// playing, take one off (×), and say how much room they may take.
ListView {
  id: root

  required property var app
  readonly property var pal: app.pal
  readonly property var songs: app.store.offline
  readonly property var settings: app.store.config.offline || ({ dir: "", limitMb: 2048, autoSave: true })
  readonly property var rooms: [{ mb: 1024, label: "1 GB" }, { mb: 2048, label: "2 GB" }, { mb: 5120, label: "5 GB" },
    { mb: 10240, label: "10 GB" }, { mb: 0, label: "No limit" }]

  clip: true
  model: songs
  leftMargin: 20
  rightMargin: 20
  bottomMargin: 20
  boundsBehavior: Flickable.StopAtBounds
  ScrollBar.vertical: ScrollBar {}

  header: Column {
    x: 8
    width: root.width - 56
    spacing: 10
    bottomPadding: 16
    Text {
      textFormat: Text.PlainText
      text: "On this computer"
      color: root.pal.foreground
      font.family: root.app.fontFamily
      font.pixelSize: 28
      font.weight: Font.Black
    }
    Text {
      width: parent.width
      textFormat: Text.PlainText
      wrapMode: Text.WordWrap
      text: (root.songs.length
          ? Model.plural(root.songs.length, "song") + " · " + Model.formatBytes(Model.offlineBytes(root.songs))
            + (root.settings.limitMb > 0 ? " of " + Model.formatMegabytes(root.settings.limitMb) : "")
          : "No songs kept yet. " + (root.settings.autoSave !== false ? "Songs you play to the end are kept here." : ""))
        + "\nThey play with no internet, and take over when it goes. In " + root.app.store.offlineDir
      color: root.pal.muted
      font.family: root.app.fontFamily
      font.pixelSize: 12
      lineHeight: 1.2
    }
    Flow {
      width: parent.width
      spacing: 8
      Chip {
        visible: root.songs.length > 0
        text: "Play"
        glyph: Model.GLYPH_PLAY
        textColor: root.pal.foreground
        accent: root.pal.accent
        selected: true
        fontSize: 13
        fontFamily: root.app.fontFamily
        onClicked: root.app.playOffline(false)
      }
      Chip {
        visible: root.songs.length > 0
        text: "Shuffle"
        glyph: Model.GLYPH_SHUFFLE
        textColor: root.pal.foreground
        accent: root.pal.accent
        fontSize: 13
        fontFamily: root.app.fontFamily
        onClicked: root.app.playOffline(true)
      }
      Chip {
        visible: !!root.app.nowTrack.id
        text: "Keep the song playing"
        glyph: Model.GLYPH_DOWNLOAD
        textColor: root.pal.foreground
        accent: root.pal.accent
        fontSize: 13
        fontFamily: root.app.fontFamily
        onClicked: root.app.keepOffline("current", root.app.nowTrack.title)
      }
      Chip {
        text: "Keep songs played to the end"
        glyph: root.settings.autoSave !== false ? Model.GLYPH_CHECK : ""
        textColor: root.pal.foreground
        accent: root.pal.accent
        selected: root.settings.autoSave !== false
        fontSize: 13
        fontFamily: root.app.fontFamily
        onClicked: root.app.setConfig("offline.autoSave", root.settings.autoSave === false)
      }
    }
    Flow {
      width: parent.width
      spacing: 8
      Text {
        height: 32
        verticalAlignment: Text.AlignVCenter
        textFormat: Text.PlainText
        text: "Room for them"
        color: root.pal.muted
        font.family: root.app.fontFamily
        font.pixelSize: 12
        rightPadding: 4
      }
      Repeater {
        model: root.rooms
        Chip {
          required property var modelData
          text: modelData.label
          textColor: root.pal.foreground
          accent: root.pal.accent
          selected: Number(root.settings.limitMb) === modelData.mb
          fontSize: 12
          fontFamily: root.app.fontFamily
          onClicked: root.app.setConfig("offline.limitMb", modelData.mb)
        }
      }
    }
  }

  delegate: TrackRow {
    required property var modelData
    required property int index
    width: root.width - 40
    app: root.app
    track: modelData.track
    number: index + 1
    badge: Model.formatBytes(modelData.bytes)
    removable: true
    current: root.app.nowTrack.id === modelData.track.id
    playing: current && root.app.player.playing
    onActivated: root.app.playOffline(false, index)
    onRemoveRequested: root.app.dropOffline(modelData.key, modelData.track.title)
  }
}
