import QtQuick
import "Model.js" as Model

// Desktop widget, "minimal": just type — the song, the movie, a hairline of
// progress and small controls.
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
  readonly property real pad: 22 * s

  implicitWidth: 540 * s
  implicitHeight: (hasTrack ? playingColumn.implicitHeight : idle.implicitHeight) + pad * 2

  Column {
    id: playingColumn
    x: root.pad
    y: root.pad
    width: root.width - root.pad * 2
    spacing: 6 * root.s
    visible: root.hasTrack

    Row {
      spacing: 8 * root.s
      PlayingBars {
        anchors.verticalCenter: parent.verticalCenter
        playing: root.player.playing
        color: root.pal.accent
        barWidth: 2.5 * root.s
        maxHeight: 11 * root.s
      }
      Text {
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: root.player.source && root.player.source.title ? String(root.player.source.title).toUpperCase() : "PAATTU"
        color: root.pal.accent
        font.family: root.fontFamily
        font.pixelSize: 10 * root.s
        font.letterSpacing: 1.6 * root.s
      }
    }

    Text {
      width: parent.width
      textFormat: Text.PlainText
      text: root.track.title || "…"
      color: root.pal.foreground
      font.family: root.fontFamily
      font.pixelSize: 36 * root.s
      font.weight: Font.Black
      elide: Text.ElideRight
    }

    Text {
      width: parent.width
      textFormat: Text.PlainText
      text: Model.subtitle(root.track)
      color: root.pal.muted
      font.family: root.fontFamily
      font.pixelSize: 14 * root.s
      elide: Text.ElideRight
      visible: text !== ""
    }

    Item { width: 1; height: 4 * root.s }

    Item {
      width: parent.width
      height: controls.height

      Seekbar {
        anchors.left: parent.left
        anchors.right: controls.left
        anchors.rightMargin: 16 * root.s
        anchors.verticalCenter: parent.verticalCenter
        progress: root.player.progress
        trackColor: Qt.rgba(root.pal.foreground.r, root.pal.foreground.g, root.pal.foreground.b, 0.14)
        fillColor: root.pal.foreground
        thickness: 2 * root.s
        onSeek: function(f) { root.player.seekFraction(f) }
      }

      Row {
        id: controls
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: 2 * root.s

        SongActions {
          anchors.verticalCenter: parent.verticalCenter
          store: root.store
          jobs: root.jobs
          videoId: root.player.videoId
          color: root.pal.muted
          accent: root.pal.accent
          size: 26 * root.s
          fontFamily: root.fontFamily
          onPick: root.pick()
        }
        Item { width: 6 * root.s; height: 1 }
        Text {
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          text: Model.formatTime(root.player.position) + " / " + Model.formatTime(root.player.duration)
          color: root.pal.muted
          font.family: root.fontFamily
          font.pixelSize: 11 * root.s
          rightPadding: 8 * root.s
        }
        GlyphButton {
          anchors.verticalCenter: parent.verticalCenter
          glyph: Model.GLYPH_PREV; size: 28 * root.s; color: root.pal.foreground; fontFamily: root.fontFamily
          onClicked: root.player.previous()
        }
        GlyphButton {
          anchors.verticalCenter: parent.verticalCenter
          glyph: root.player.playing ? Model.GLYPH_PAUSE : Model.GLYPH_PLAY
          size: 32 * root.s; color: root.pal.accent; fontFamily: root.fontFamily
          onClicked: root.player.togglePause()
        }
        GlyphButton {
          anchors.verticalCenter: parent.verticalCenter
          glyph: Model.GLYPH_NEXT; size: 28 * root.s; color: root.pal.foreground; fontFamily: root.fontFamily
          onClicked: root.player.next()
        }
      }
    }
  }

  IdlePicks {
    id: idle
    x: root.pad
    y: root.pad
    width: root.width - root.pad * 2
    visible: !root.hasTrack
    store: root.store
    s: root.s
    fontFamily: root.fontFamily
    onPlayMix: function(mixId, title) { root.playMix(mixId, title) }
    onOpenApp: root.openApp()
  }
}
