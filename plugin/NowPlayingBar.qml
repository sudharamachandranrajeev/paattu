import QtQuick
import qs.Ui
import "Model.js" as Model

// The app's bottom bar, floating on glass: track (with heart / add to
// playlist; click it for Now Playing), transport + seek, volume.
Glass {
  id: root

  required property var app
  pal: app.playerPal
  readonly property var player: app.player
  readonly property var track: Model.nowPlaying(app.store.tracks, player.path, player.mediaTitle)

  // Narrow windows (a tiled half or third of the screen): the song and the
  // buttons on top, play controls and the seek bar under them.
  readonly property bool compact: app.compact
  // Narrower still: the heart, save and video buttons are on Now Playing.
  readonly property bool tight: width < 560
  height: compact ? 116 : 84
  radius: 28

  // Under the track (declared first) so its buttons keep their clicks.
  MouseArea {
    x: trackInfo.x
    y: trackInfo.y
    width: trackInfo.width
    height: trackInfo.height
    enabled: root.player.hasTrack
    cursorShape: Qt.PointingHandCursor
    onClicked: root.app.view === "playing" ? root.app.back() : root.app.navigate("playing")
  }

  // Track
  Row {
    id: trackInfo
    x: 14
    y: root.compact ? 10 : (root.height - height) / 2
    width: root.compact ? root.width - 28 - sideButtons.width - 8 : Math.min(360, root.width * 0.3)
    spacing: 12

    Cover {
      width: 56
      height: 56
      radius: 18
      source: root.track.id ? root.app.store.artFor("v", root.track.id) : ""
      revision: root.app.artRevision
      tint: Qt.rgba(root.pal.foreground.r, root.pal.foreground.g, root.pal.foreground.b, 0.08)
      glyphColor: root.pal.muted
      glyph: root.player.hasTrack ? Model.GLYPH_NOTE : Model.GLYPH_ALBUM
      fontFamily: root.app.fontFamily
    }

    Column {
      anchors.verticalCenter: parent.verticalCenter
      width: parent.width - 68 - (songActions.visible ? songActions.width + 12 : 0)
      spacing: 3
      Text {
        width: parent.width
        textFormat: Text.PlainText
        text: root.player.hasTrack ? (root.track.title || "…") : "Nothing playing"
        color: root.pal.foreground
        font.family: root.app.fontFamily
        font.pixelSize: 14
        font.bold: true
        elide: Text.ElideRight
      }
      Text {
        width: parent.width
        textFormat: Text.PlainText
        text: root.player.hasTrack ? Model.subtitle(root.track)
          : (root.player.connected ? "Engine ready" : "Engine starts when you press play")
        color: root.pal.muted
        font.family: root.app.fontFamily
        font.pixelSize: 11
        elide: Text.ElideRight
      }
      // The stream: "AAC · 320 kbps", "Opus · ~130 kbps", "FLAC · Lossless".
      Text {
        width: parent.width
        visible: text !== ""
        textFormat: Text.PlainText
        text: root.player.quality
        color: root.pal.accent
        opacity: 0.85
        font.family: root.app.fontFamily
        font.pixelSize: 10
        elide: Text.ElideRight
      }
    }

    SongActions {
      id: songActions
      anchors.verticalCenter: parent.verticalCenter
      visible: root.player.hasTrack && videoId !== "" && !root.tight
      store: root.app.store
      jobs: root.app.quick
      videoId: root.player.videoId
      showSave: true
      color: root.pal.muted
      accent: root.pal.accent
      size: 30
      fontFamily: root.app.fontFamily
      onPick: function(anchor) { root.app.pickPlaylists(root.track, anchor) }
    }
  }

  // Transport + seek: stacked in the middle, or side by side along the bottom.
  Item {
    id: controls
    x: root.compact ? 14 : (root.width - width) / 2
    y: root.compact ? root.height - height - 8 : (root.height - height) / 2
    // Never under the song or the buttons beside it.
    width: root.compact ? root.width - 28
      : Math.min(520, root.width * 0.42, root.width - 2 * Math.max(trackInfo.x + trackInfo.width, sideButtons.width + 18) - 24)
    height: root.compact ? transport.height : transport.height + 4 + seekRow.height

    Transport {
      id: transport
      x: root.compact ? 0 : (parent.width - width) / 2
      player: root.player
      color: root.pal.foreground
      accent: root.pal.accent
      accentText: root.pal.accentText
      size: 30
      fontFamily: root.app.fontFamily
    }

    Row {
      id: seekRow
      x: root.compact ? transport.width + 8 : 0
      y: root.compact ? (parent.height - height) / 2 : transport.height + 4
      width: parent.width - x
      spacing: 10
      Text {
        width: 40
        horizontalAlignment: Text.AlignRight
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: Model.formatTime(root.player.position)
        color: root.pal.muted
        font.family: root.app.fontFamily
        font.pixelSize: 10
      }
      Seekbar {
        width: parent.width - 100
        anchors.verticalCenter: parent.verticalCenter
        progress: root.player.progress
        interactive: root.player.hasTrack
        trackColor: Qt.rgba(root.pal.foreground.r, root.pal.foreground.g, root.pal.foreground.b, 0.14)
        fillColor: root.pal.accent
        thickness: 3
        onSeek: function(f) { root.player.seekFraction(f) }
      }
      Text {
        width: 40
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: Model.formatTime(root.player.duration)
        color: root.pal.muted
        font.family: root.app.fontFamily
        font.pixelSize: 10
      }
    }
  }

  // Volume, video, queue
  Row {
    id: sideButtons
    anchors.right: parent.right
    anchors.rightMargin: root.compact ? 12 : 18
    y: root.compact ? trackInfo.y + (56 - height) / 2 : (root.height - height) / 2
    spacing: 4

    GlyphButton {
      anchors.verticalCenter: parent.verticalCenter
      visible: !root.tight
      glyph: root.player.hasTrack && !root.player.onYouTube ? Model.GLYPH_WEB : Model.GLYPH_VIDEO
      size: 30
      color: root.pal.muted
      fontFamily: root.app.fontFamily
      enabled: root.player.hasTrack
      tooltip: root.player.hasTrack && !root.player.onYouTube ? "Open the song's page" : "Watch the video"
      onClicked: root.app.watchVideo()
    }
    GlyphButton {
      anchors.verticalCenter: parent.verticalCenter
      glyph: Model.GLYPH_EQUALIZER
      size: 30
      // Lit while the equaliser is on.
      color: root.app.view === "sound" || (root.app.store.config.sound || {}).on === true ? root.pal.accent : root.pal.muted
      fontFamily: root.app.fontFamily
      tooltip: "Sound"
      onClicked: root.app.view === "sound" ? root.app.back() : root.app.navigate("sound")
    }
    GlyphButton {
      anchors.verticalCenter: parent.verticalCenter
      glyph: Model.GLYPH_QUEUE
      size: 30
      color: root.app.view === "queue" ? root.pal.accent : root.pal.muted
      fontFamily: root.app.fontFamily
      onClicked: root.app.view === "queue" ? root.app.back() : root.app.navigate("queue")
    }
    GlyphButton {
      anchors.verticalCenter: parent.verticalCenter
      glyph: root.player.muted || root.player.volume === 0 ? Model.GLYPH_MUTE
        : root.player.volume < 50 ? Model.GLYPH_VOLUME_LOW : Model.GLYPH_VOLUME
      size: 30
      color: root.pal.muted
      fontFamily: root.app.fontFamily
      onClicked: root.player.toggleMute()
    }
    Seekbar {
      anchors.verticalCenter: parent.verticalCenter
      // The mute button stays; the slider needs room.
      visible: !root.compact
      width: 110
      progress: root.player.volume / 100
      trackColor: Qt.rgba(root.pal.foreground.r, root.pal.foreground.g, root.pal.foreground.b, 0.14)
      fillColor: root.pal.foreground
      thickness: 3
      onSeek: function(f) { root.player.setVolume(Math.round(f * 100)) }
    }
  }
}
