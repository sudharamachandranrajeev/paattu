import QtQuick
import QtQuick.Effects
import "Model.js" as Model

// Now Playing: the cover big and glowing, the song, and what's up next, in
// one of four looks (Settings › Now Playing): the cover (in 3D when that's
// on), the cover making way for the song's video, the picture across the
// window (AppWindow draws it), or the cover on a turning record. AppWindow
// shows the song's video behind it all, blurred (VideoBackdrop).
Item {
  id: root

  required property var app
  readonly property var pal: app.playerPal
  readonly property string style: app.nowPlayingStyle
  readonly property bool depth: app.store.config.coverDepth !== false
  readonly property var player: app.player
  readonly property var track: app.nowTrack
  readonly property var upNext: Model.queueRows(player.playlist, app.store.tracks)
    .filter(function(row) { return row.index > player.index }).slice(0, 6)
  readonly property bool videoOn: app.store.config.videoBackground !== false
  readonly property real artSize: Math.max(160, Math.min(420, height - 64, (width - 84) * 0.45))

  // The cover, with the accent glowing under it.
  Item {
    id: art
    x: 28
    anchors.verticalCenter: parent.verticalCenter
    visible: root.style !== "full"
    width: visible ? root.artSize : 0
    height: root.artSize
    // The video takes the cover's place once it shows.
    opacity: root.style === "video" && root.app.videoShown ? 0 : 1
    Behavior on opacity { NumberAnimation { duration: 900; easing.type: Easing.InOutQuad } }

    Rectangle {
      anchors.fill: parent
      anchors.margins: 18
      anchors.topMargin: 36
      radius: root.style === "record" ? width / 2 : 40
      color: root.pal.accent
      opacity: 0.55
      visible: GraphicsInfo.api !== GraphicsInfo.Software
      layer.enabled: visible
      layer.effect: MultiEffect {
        blurEnabled: true
        blurMax: 64
        blur: 1
        autoPaddingEnabled: true
      }
    }
    Cover {
      anchors.fill: parent
      visible: root.style !== "record" && !root.depth
      radius: 32
      source: visible && root.track.id ? root.app.store.artFor("v", root.track.id) : ""
      revision: root.app.artRevision
      tint: Qt.rgba(root.pal.foreground.r, root.pal.foreground.g, root.pal.foreground.b, 0.08)
      glyphColor: root.pal.muted
      glyph: root.player.hasTrack ? Model.GLYPH_NOTE : Model.GLYPH_ALBUM
      fontFamily: root.app.fontFamily
    }
    Loader {
      anchors.fill: parent
      active: root.style !== "record" && root.style !== "full" && root.depth
      sourceComponent: DepthCover {
        app: root.app
        trackId: root.track.id || ""
        radius: 32
        tint: Qt.rgba(root.pal.foreground.r, root.pal.foreground.g, root.pal.foreground.b, 0.08)
        glyphColor: root.pal.muted
        glyph: root.player.hasTrack ? Model.GLYPH_NOTE : Model.GLYPH_ALBUM
      }
    }
    Record {
      anchors.fill: parent
      visible: root.style === "record"
      source: visible && root.track.id ? root.app.store.artFor("v", root.track.id) : ""
      revision: root.app.artRevision
      spinning: visible && root.player.playing
      turn: 6000
      labelTint: root.pal.accent
      glyphColor: root.pal.accentText
      holeColor: root.pal.background
      fontFamily: root.app.fontFamily
    }
  }

  Column {
    id: info
    anchors.left: art.right
    anchors.leftMargin: root.style === "full" ? 8 : 36
    anchors.right: parent.right
    anchors.rightMargin: 28
    anchors.verticalCenter: parent.verticalCenter
    spacing: 10

    Text {
      textFormat: Text.PlainText
      text: "NOW PLAYING"
      color: root.pal.accent
      font.family: root.app.fontFamily
      font.pixelSize: 11
      font.weight: Font.Bold
      font.letterSpacing: 2
    }
    Text {
      width: parent.width
      textFormat: Text.PlainText
      text: root.player.hasTrack ? (root.track.title || "…") : "Nothing playing"
      color: root.pal.foreground
      font.family: root.app.fontFamily
      font.pixelSize: 34
      font.weight: Font.Black
      wrapMode: Text.WordWrap
      maximumLineCount: 2
      elide: Text.ElideRight
    }
    Text {
      width: parent.width
      visible: text !== ""
      textFormat: Text.PlainText
      text: root.player.hasTrack ? [Model.subtitle(root.track)].concat((root.track.credits || []).slice(1, 3))
        .filter(function(s) { return s }).join(" · ") : "Pick a song, a playlist or a mix to start."
      color: root.pal.muted
      font.family: root.app.fontFamily
      font.pixelSize: 15
      elide: Text.ElideRight
    }

    Row {
      spacing: 8
      topPadding: 4
      visible: root.player.hasTrack

      // The stream: "AAC · 320 kbps".
      Glass {
        pal: root.pal
        visible: root.player.quality !== ""
        anchors.verticalCenter: parent.verticalCenter
        width: qualityText.implicitWidth + 24
        height: 30
        radius: 15
        Text {
          id: qualityText
          anchors.centerIn: parent
          textFormat: Text.PlainText
          text: root.player.quality
          color: root.pal.foreground
          font.family: root.app.fontFamily
          font.pixelSize: 11
        }
      }
      SongActions {
        anchors.verticalCenter: parent.verticalCenter
        visible: root.player.videoId !== ""
        store: root.app.store
        jobs: root.app.quick
        videoId: root.player.videoId
        showSave: true
        color: root.pal.foreground
        accent: root.pal.accent
        size: 34
        fontFamily: root.app.fontFamily
        onPick: function(anchor) { root.app.pickPlaylists(root.track, anchor) }
      }
      Chip {
        anchors.verticalCenter: parent.verticalCenter
        text: "Video"
        glyph: Model.GLYPH_VIDEO
        textColor: root.pal.foreground
        accent: root.pal.accent
        selected: root.videoOn
        fontSize: 12
        fontFamily: root.app.fontFamily
        onClicked: root.app.setConfig("videoBackground", !root.videoOn)
      }
      // Songs like this one, without end (on by itself when a queue runs
      // out, unless auto radio is off in Settings).
      Chip {
        anchors.verticalCenter: parent.verticalCenter
        text: root.player.radioOn ? "Radio on" : "Start radio"
        glyph: Model.GLYPH_RADIO
        textColor: root.pal.foreground
        accent: root.pal.accent
        selected: root.player.radioOn
        fontSize: 12
        fontFamily: root.app.fontFamily
        onClicked: root.app.toggleRadio()
      }
    }

    Item { width: 1; height: 10 }

    // Up next
    Glass {
      pal: root.pal
      visible: root.upNext.length > 0
      width: Math.min(parent.width, 560)
      height: nextColumn.implicitHeight + 20
      radius: 28

      Column {
        id: nextColumn
        x: 10
        y: 10
        width: parent.width - 20
        Text {
          leftPadding: 12
          topPadding: 4
          bottomPadding: 6
          textFormat: Text.PlainText
          text: "Up next"
          color: root.pal.muted
          font.family: root.app.fontFamily
          font.pixelSize: 12
          font.bold: true
        }
        Repeater {
          model: root.upNext
          TrackRow {
            required property var modelData
            width: nextColumn.width
            app: root.app
            compact: true
            track: root.app.store.tracks[modelData.id] || { id: modelData.id, title: modelData.title, movie: modelData.movie }
            number: modelData.index + 1
            onActivated: root.player.playIndex(modelData.index)
          }
        }
      }
    }
  }
}
