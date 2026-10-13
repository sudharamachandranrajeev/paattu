import QtQuick
import "Model.js" as Model

// Desktop widget, "card": big cover art with the details underneath.
Item {
  id: root

  required property var player
  required property var store
  required property var track
  property var pal: store.palette
  property real s: 1
  property string fontFamily: "monospace"
  property int artRevision: 0

  // Runs `paattu fav`; pick() asks the frame for the add-to-playlist picker.
  property var jobs: null

  signal playMix(string mixId, string title)
  signal openApp()
  signal pick()

  readonly property bool hasTrack: player.hasTrack
  readonly property real pad: 18 * s

  implicitWidth: 300 * s
  implicitHeight: column.implicitHeight + pad * 2

  Column {
    id: column
    x: root.pad
    y: root.pad
    width: root.width - root.pad * 2
    spacing: 10 * root.s

    Item {
      width: parent.width
      height: width

      Cover {
        id: art
        anchors.fill: parent
        radius: 14 * root.s
        source: root.track.id ? root.store.artFor("v", root.track.id) : ""
        revision: root.artRevision
        tint: Qt.tint(root.pal.accent, Qt.rgba(root.pal.background.r, root.pal.background.g, root.pal.background.b, 0.35))
        glyphColor: root.pal.accentText
        glyph: root.hasTrack ? Model.GLYPH_NOTE : Model.GLYPH_ALBUM
        fontFamily: root.fontFamily
        scale: root.player.playing || !root.hasTrack ? 1 : 0.94
        Behavior on scale { NumberAnimation { duration: 400; easing.type: Easing.OutBack } }
      }

      PlayingBars {
        anchors.left: art.left
        anchors.bottom: art.bottom
        anchors.margins: 12 * root.s
        visible: root.hasTrack
        playing: root.player.playing
        color: "#ffffff"
        bars: 4
        barWidth: 3 * root.s
        maxHeight: 16 * root.s
      }

      Column {
        anchors.left: art.left
        anchors.bottom: art.bottom
        anchors.margins: 16 * root.s
        visible: !root.hasTrack
        Text {
          textFormat: Text.PlainText
          text: "paattu"
          color: root.pal.accentText
          font.family: root.fontFamily
          font.pixelSize: 30 * root.s
          font.weight: Font.Bold
        }
        Text {
          textFormat: Text.PlainText
          text: "പാട്ട് · பாட்டு"
          color: root.pal.accentText
          opacity: 0.8
          font.family: "Noto Sans Malayalam"
          font.pixelSize: 13 * root.s
        }
      }
    }

    Item {
      width: parent.width
      height: titleColumn.height
      visible: root.hasTrack

      Column {
        id: titleColumn
        anchors.left: parent.left
        anchors.right: cardActions.left
        anchors.rightMargin: 6 * root.s
        spacing: 4 * root.s

        Text {
          width: parent.width
          textFormat: Text.PlainText
          text: root.track.title || "…"
          color: root.pal.foreground
          font.family: root.fontFamily
          font.pixelSize: 19 * root.s
          font.weight: Font.Bold
          elide: Text.ElideRight
        }

        Text {
          width: parent.width
          textFormat: Text.PlainText
          text: Model.subtitle(root.track) || " "
          color: root.pal.muted
          font.family: root.fontFamily
          font.pixelSize: 12 * root.s
          elide: Text.ElideRight
        }
      }

      SongActions {
        id: cardActions
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        store: root.store
        jobs: root.jobs
        videoId: root.player.videoId
        color: root.pal.muted
        accent: root.pal.accent
        size: 28 * root.s
        fontFamily: root.fontFamily
        onPick: root.pick()
      }
    }

    Seekbar {
      width: parent.width
      visible: root.hasTrack
      progress: root.player.progress
      trackColor: Qt.rgba(root.pal.foreground.r, root.pal.foreground.g, root.pal.foreground.b, 0.14)
      fillColor: root.pal.accent
      thickness: 3 * root.s
      onSeek: function(f) { root.player.seekFraction(f) }
    }

    Item {
      width: parent.width
      height: transport.height
      visible: root.hasTrack

      Transport {
        id: transport
        anchors.centerIn: parent
        player: root.player
        color: root.pal.foreground
        accent: root.pal.accent
        accentText: root.pal.accentText
        size: 30 * root.s
        fontFamily: root.fontFamily
      }
    }

    IdlePicks {
      width: parent.width
      visible: !root.hasTrack
      store: root.store
      s: root.s
      compact: true
      fontFamily: root.fontFamily
      onPlayMix: function(mixId, title) { root.playMix(mixId, title) }
      onOpenApp: root.openApp()
    }
  }
}
