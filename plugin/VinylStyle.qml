import QtQuick
import "Model.js" as Model

// Desktop widget, "vinyl": the record slides out of its sleeve and spins while
// the song plays; details and controls sit to the right.
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

  readonly property bool playing: player.playing
  readonly property bool hasTrack: player.hasTrack
  readonly property real sleeve: 176 * s
  readonly property real disc: 168 * s

  implicitWidth: 610 * s
  implicitHeight: 220 * s

  // ---------- record + sleeve ----------
  Item {
    id: deck
    x: 22 * root.s
    anchors.verticalCenter: parent.verticalCenter
    width: root.sleeve + 100 * root.s
    height: root.sleeve

    Item {
      id: record
      width: root.disc
      height: root.disc
      anchors.verticalCenter: parent.verticalCenter
      x: root.hasTrack ? (root.playing ? 94 * root.s : 46 * root.s) : 4 * root.s
      Behavior on x { NumberAnimation { duration: 650; easing.type: Easing.OutCubic } }

      Item {
        id: spinner
        anchors.fill: parent

        Rectangle {
          anchors.fill: parent
          radius: width / 2
          gradient: Gradient {
            GradientStop { position: 0.0; color: "#1c1c1f" }
            GradientStop { position: 0.5; color: "#0b0b0c" }
            GradientStop { position: 1.0; color: "#1a1a1d" }
          }
        }

        // Grooves
        Repeater {
          model: 9
          Rectangle {
            required property int index
            anchors.centerIn: parent
            width: root.disc * (0.92 - index * 0.055)
            height: width
            radius: width / 2
            color: "transparent"
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, index % 2 ? 0.035 : 0.06)
          }
        }

        // Sheen
        Rectangle {
          anchors.centerIn: parent
          width: parent.width * 0.96
          height: width
          radius: width / 2
          rotation: 35
          gradient: Gradient {
            GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0.0) }
            GradientStop { position: 0.45; color: Qt.rgba(1, 1, 1, 0.07) }
            GradientStop { position: 0.55; color: Qt.rgba(1, 1, 1, 0.0) }
          }
        }

        Cover {
          anchors.centerIn: parent
          width: root.disc * 0.4
          height: width
          circle: true
          source: root.track.id ? root.store.artFor("v", root.track.id) : ""
          revision: root.artRevision
          tint: root.pal.accent
          glyphColor: root.pal.accentText
          glyph: Model.GLYPH_NOTE
          fontFamily: root.fontFamily
        }

        Rectangle {
          anchors.centerIn: parent
          width: 7 * root.s
          height: width
          radius: width / 2
          color: root.pal.background
          border.width: 1
          border.color: Qt.rgba(1, 1, 1, 0.25)
        }

        RotationAnimator on rotation {
          from: 0
          to: 360
          duration: 1800
          loops: Animation.Infinite
          running: root.playing
          paused: running && !root.playing
        }
      }
    }

    // Sleeve: the cover art, in front of the record.
    Rectangle {
      width: root.sleeve
      height: root.sleeve
      radius: 12 * root.s
      color: Qt.rgba(0, 0, 0, 0.35)
      y: 3 * root.s
      x: 2 * root.s
      opacity: 0.5
    }

    Cover {
      id: sleeveArt
      width: root.sleeve
      height: root.sleeve
      radius: 12 * root.s
      source: root.track.id ? root.store.artFor("v", root.track.id) : ""
      revision: root.artRevision
      tint: Qt.tint(root.pal.accent, Qt.rgba(root.pal.background.r, root.pal.background.g, root.pal.background.b, 0.35))
      glyphColor: root.pal.accentText
      glyph: root.hasTrack ? Model.GLYPH_NOTE : Model.GLYPH_ALBUM
      fontFamily: root.fontFamily
    }

    // Wordmark on the empty sleeve.
    Column {
      anchors.left: sleeveArt.left
      anchors.bottom: sleeveArt.bottom
      anchors.margins: 14 * root.s
      visible: !root.hasTrack
      spacing: 0

      Text {
        textFormat: Text.PlainText
        text: "paattu"
        color: root.pal.accentText
        font.family: root.fontFamily
        font.pixelSize: 22 * root.s
        font.weight: Font.Bold
      }
      Text {
        textFormat: Text.PlainText
        text: "പാട്ട് · பாட்டு"
        color: root.pal.accentText
        opacity: 0.8
        font.family: "Noto Sans Malayalam"
        font.pixelSize: 11 * root.s
      }
    }
  }

  // ---------- details ----------
  Item {
    id: details
    anchors.left: deck.right
    anchors.leftMargin: 26 * root.s
    anchors.right: parent.right
    anchors.rightMargin: 24 * root.s
    anchors.verticalCenter: parent.verticalCenter
    height: root.sleeve

    Column {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      spacing: 6 * root.s
      visible: root.hasTrack

      Item {
        width: parent.width
        height: Math.max(nowRow.height, vinylActions.height)

        Row {
          id: nowRow
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          spacing: 8 * root.s
          PlayingBars {
            anchors.verticalCenter: parent.verticalCenter
            playing: root.playing
            color: root.pal.accent
            bars: 4
            barWidth: 2.5 * root.s
            maxHeight: 11 * root.s
          }
          Text {
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: (root.player.buffering ? "LOADING" : root.playing ? "NOW PLAYING" : "PAUSED")
              + (root.player.source && root.player.source.title ? "  ·  " + String(root.player.source.title).toUpperCase() : "")
            color: root.pal.accent
            font.family: root.fontFamily
            font.pixelSize: 10 * root.s
            font.letterSpacing: 1.4 * root.s
            elide: Text.ElideRight
            width: details.width - 30 * root.s - vinylActions.width
          }
        }

        SongActions {
          id: vinylActions
          anchors.right: parent.right
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
      }

      Text {
        width: parent.width
        textFormat: Text.PlainText
        text: root.track.title || "…"
        color: root.pal.foreground
        font.family: root.fontFamily
        font.pixelSize: 25 * root.s
        font.weight: Font.Bold
        maximumLineCount: 2
        wrapMode: Text.WordWrap
        elide: Text.ElideRight
        lineHeight: 0.95
      }

      Text {
        width: parent.width
        textFormat: Text.PlainText
        text: Model.subtitle(root.track)
        color: root.pal.muted
        font.family: root.fontFamily
        font.pixelSize: 13 * root.s
        elide: Text.ElideRight
        visible: text !== ""
      }

      Item { width: 1; height: 2 * root.s }

      Seekbar {
        width: parent.width
        progress: root.player.progress
        trackColor: Qt.rgba(root.pal.foreground.r, root.pal.foreground.g, root.pal.foreground.b, 0.14)
        fillColor: root.pal.accent
        thickness: 3 * root.s
        onSeek: function(f) { root.player.seekFraction(f) }
      }

      Item {
        width: parent.width
        height: transport.height

        Text {
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          text: Model.formatTime(root.player.position)
          color: root.pal.muted
          font.family: root.fontFamily
          font.pixelSize: 10 * root.s
        }

        Transport {
          id: transport
          anchors.horizontalCenter: parent.horizontalCenter
          player: root.player
          color: root.pal.foreground
          accent: root.pal.accent
          accentText: root.pal.accentText
          size: 30 * root.s
          fontFamily: root.fontFamily
        }

        Text {
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          text: Model.formatTime(root.player.duration)
          color: root.pal.muted
          font.family: root.fontFamily
          font.pixelSize: 10 * root.s
        }
      }
    }

    IdlePicks {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      visible: !root.hasTrack
      store: root.store
      s: root.s
      fontFamily: root.fontFamily
      onPlayMix: function(mixId, title) { root.playMix(mixId, title) }
      onOpenApp: root.openApp()
    }
  }
}
