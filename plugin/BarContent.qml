import QtQuick
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Body of the bar panel: search, now playing (with heart / save / add to
// playlist), controls, volume, up next, and quick starts: your mixes and a few
// saved playlists. Up next and the quick starts make way for search results.
Column {
  id: root

  required property var widget

  readonly property var player: widget.player
  readonly property var store: widget.store
  readonly property var bar: widget.bar
  readonly property color fg: widget.fg
  readonly property color dim: Qt.darker(fg, 1.45)
  readonly property string fontFamily: widget.fontFamily
  readonly property var track: widget.track
  readonly property var upNext: {
    var rows = Model.queueRows(root.player.playlist, null)
    var at = root.player.index
    return at < 0 ? [] : rows.slice(at + 1, at + 4)
  }

  spacing: Style.space(12)

  // The add-to-playlist picker, shown inline under the song.
  property bool picking: false
  onVisibleChanged: if (!visible) picking = false
  // A box has the keyboard: the panel's keys are text.
  readonly property bool typing: search.typing || nowPicker.typing

  function focusSearch() { search.focusField() }

  // ---------- Search ----------
  BarSearch {
    id: search
    width: parent.width
    widget: root.widget
    onPickIdChanged: if (pickId) root.picking = false
  }

  // ---------- Now playing ----------
  Row {
    width: parent.width
    spacing: Style.space(12)

    Cover {
      width: Style.space(84)
      height: width
      radius: Style.space(10)
      source: root.track.id ? root.store.artFor("v", root.track.id) : ""
      revision: root.widget.artRevision
      tint: Style.normalFillFor(root.fg, Color.accent)
      glyphColor: root.fg
      glyph: root.player.hasTrack ? Model.GLYPH_NOTE : Model.GLYPH_ALBUM
      fontFamily: root.fontFamily
    }

    Column {
      width: parent.width - Style.space(96) - (songActions.visible ? songActions.width + Style.space(12) : 0)
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(3)

      Text {
        width: parent.width
        textFormat: Text.PlainText
        text: (root.player.buffering ? "LOADING" : root.player.playing ? "NOW PLAYING" : root.player.hasTrack ? "PAUSED" : "PAATTU")
          + (root.player.source && root.player.source.title ? " · " + String(root.player.source.title).toUpperCase() : "")
        color: Color.accent
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        font.letterSpacing: 1.2
        elide: Text.ElideRight
      }

      Text {
        width: parent.width
        textFormat: Text.PlainText
        text: root.player.hasTrack ? (root.track.title || "…") : "Nothing playing"
        color: root.fg
        font.family: root.fontFamily
        font.pixelSize: Style.font.heading
        font.bold: true
        elide: Text.ElideRight
      }

      Text {
        width: parent.width
        textFormat: Text.PlainText
        text: root.player.hasTrack ? Model.subtitle(root.track)
          : search.showing ? "Click a song above to play it"
          : (root.store.hasLibrary ? "Pick a mix below, or open Paattu" : "Search for a song above, or add a YouTube profile")
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        elide: Text.ElideRight
        visible: text !== ""
      }

      // What mpv is actually playing: "AAC · 320 kbps", "Opus · ~130 kbps".
      Text {
        width: parent.width
        visible: root.player.hasTrack && text !== ""
        textFormat: Text.PlainText
        text: root.player.quality
        color: Color.accent
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
      }
    }

    SongActions {
      id: songActions
      anchors.verticalCenter: parent.verticalCenter
      visible: root.player.hasTrack && videoId !== ""
      store: root.store
      jobs: root.widget.jobs
      videoId: root.player.videoId
      showSave: true
      color: root.dim
      accent: Color.accent
      size: Style.space(30)
      fontFamily: root.fontFamily
      onPick: {
        search.pickId = ""
        root.picking = !root.picking
      }
    }
  }

  PlaylistPicker {
    id: nowPicker
    width: parent.width
    visible: root.picking && root.player.hasTrack
    store: root.store
    jobs: root.widget.jobs
    videoId: root.player.videoId
    songTitle: root.track.title || ""
    canType: true
    background: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.05)
    foreground: root.fg
    muted: root.dim
    accent: Color.accent
    fontFamily: root.fontFamily
    maxHeight: Style.space(300)
    onClosed: root.picking = false
  }

  Column {
    width: parent.width
    spacing: Style.space(4)
    visible: root.player.hasTrack

    Seekbar {
      width: parent.width
      progress: root.player.progress
      trackColor: Style.selectedFillFor(root.fg, Color.accent)
      fillColor: Color.accent
      thickness: Math.max(3, Style.space(3))
      onSeek: function(f) { root.player.seekFraction(f) }
    }

    Item {
      width: parent.width
      height: Math.max(posText.implicitHeight, transport.height)

      Text {
        id: posText
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: Model.formatTime(root.player.position)
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }

      Transport {
        id: transport
        anchors.centerIn: parent
        player: root.player
        color: root.fg
        accent: Color.accent
        accentText: Color.background
        size: Style.space(30)
        fontFamily: root.fontFamily
      }

      Text {
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: Model.formatTime(root.player.duration)
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }
    }

    Row {
      width: parent.width
      spacing: Style.space(8)

      GlyphButton {
        anchors.verticalCenter: parent.verticalCenter
        glyph: root.player.muted || root.player.volume === 0 ? Model.GLYPH_MUTE
          : root.player.volume < 50 ? Model.GLYPH_VOLUME_LOW : Model.GLYPH_VOLUME
        size: Style.space(26)
        color: root.fg
        fontFamily: root.fontFamily
        onClicked: root.player.toggleMute()
      }

      PanelSlider {
        width: parent.width - Style.space(70)
        anchors.verticalCenter: parent.verticalCenter
        bar: root.bar
        minimum: 0
        maximum: 100
        step: 1
        integer: true
        value: root.player.volume
        onMoved: function(v) { root.player.setVolume(v) }
      }

      Text {
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: Math.round(root.player.volume)
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }
    }
  }

  // ---------- Up next ----------
  Column {
    width: parent.width
    spacing: Style.space(2)
    visible: root.upNext.length > 0 && !search.showing

    PanelSectionHeader {
      text: "UP NEXT"
      foreground: root.fg
      fontFamily: root.fontFamily
    }

    Repeater {
      model: root.upNext

      Rectangle {
        id: row
        required property var modelData
        width: root.width
        height: Style.space(28)
        radius: Style.space(6)
        color: rowMouse.containsMouse ? Style.hoverFillFor(root.fg, Color.accent) : "transparent"

        Row {
          anchors.verticalCenter: parent.verticalCenter
          anchors.left: parent.left
          anchors.leftMargin: Style.space(6)
          width: parent.width - Style.space(12)
          spacing: Style.space(8)

          Text {
            textFormat: Text.PlainText
            text: row.modelData.title
            color: root.fg
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            elide: Text.ElideRight
            width: Math.min(implicitWidth, parent.width * 0.6)
          }
          Text {
            textFormat: Text.PlainText
            text: row.modelData.movie
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
            width: parent.width * 0.4 - Style.space(8)
            anchors.baseline: parent.children[0].baseline
          }
        }

        MouseArea {
          id: rowMouse
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: root.player.playIndex(row.modelData.index)
        }
      }
    }
  }

  PanelSeparator { foreground: root.fg }

  // ---------- Quick starts ----------
  Column {
    width: parent.width
    spacing: Style.space(8)
    visible: root.store.hasLibrary && !search.showing

    PanelSectionHeader {
      text: "PLAY"
      foreground: root.fg
      fontFamily: root.fontFamily
    }

    Flow {
      width: parent.width
      spacing: Style.space(6)

      Repeater {
        model: root.store.mixes
        Chip {
          required property var modelData
          text: modelData.title
          glyph: Model.GLYPH_SHUFFLE
          textColor: root.fg
          accent: Color.accent
          fontSize: Style.font.bodySmall
          fontFamily: root.fontFamily
          onClicked: root.widget.playMix(modelData.id, modelData.title)
        }
      }
      Chip {
        text: root.store.mixes.length ? "Edit mixes" : "Make a mix"
        glyph: Model.GLYPH_EDIT
        textColor: root.fg
        accent: Color.accent
        fontSize: Style.font.bodySmall
        fontFamily: root.fontFamily
        onClicked: root.widget.openApp("mixes")
      }
    }

    Repeater {
      // Two saved playlists per language, from different profiles.
      model: {
        var out = []
        for (var i = 0; i < root.store.languages.length; i++)
          out = out.concat(Model.shelfFor(root.store.shelf, root.store.languages[i], 2, true))
        return out
      }

      Rectangle {
        id: pick
        required property var modelData
        width: root.width
        height: Style.space(40)
        radius: Style.space(8)
        color: pickMouse.containsMouse ? Style.hoverFillFor(root.fg, Color.accent) : "transparent"

        Row {
          anchors.verticalCenter: parent.verticalCenter
          anchors.left: parent.left
          anchors.leftMargin: Style.space(4)
          spacing: Style.space(10)

          Cover {
            width: Style.space(32)
            height: width
            radius: Style.space(6)
            source: root.store.artFor("p", pick.modelData.id)
            tint: Style.normalFillFor(root.fg, Color.accent)
            glyphColor: root.fg
            glyph: Model.GLYPH_PLAYLIST
            fontFamily: root.fontFamily
          }

          Column {
            anchors.verticalCenter: parent.verticalCenter
            width: root.width - Style.space(56)
            Text {
              width: parent.width
              textFormat: Text.PlainText
              text: pick.modelData.title
              color: root.fg
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              elide: Text.ElideRight
            }
            Text {
              width: parent.width
              textFormat: Text.PlainText
              text: Model.playlistDetail(pick.modelData)
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              elide: Text.ElideRight
            }
          }
        }

        MouseArea {
          id: pickMouse
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: root.widget.playPlaylist(pick.modelData.id)
        }
      }
    }
  }

  // ---------- Footer ----------
  Text {
    width: parent.width
    visible: text !== ""
    textFormat: Text.PlainText
    text: root.widget.jobs.busy ? root.widget.jobs.message : root.widget.jobs.lastError
    color: root.widget.jobs.busy ? root.dim : Color.urgent
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
    wrapMode: Text.WordWrap
  }

  // Wraps: three buttons don't fit on one line in the panel.
  Flow {
    width: parent.width
    spacing: Style.space(6)

    Button {
      text: "Open Paattu"
      iconText: Model.GLYPH_LIBRARY
      foreground: root.fg
      fontFamily: root.fontFamily
      onClicked: root.widget.openApp()
    }

    Button {
      text: "Add from YouTube"
      iconText: Model.GLYPH_ADD
      foreground: root.fg
      fontFamily: root.fontFamily
      tooltipText: "Paste a profile (all its playlists) or a playlist link"
      onClicked: root.widget.openApp("add")
    }

    Button {
      visible: root.player.hasTrack
      text: root.player.onYouTube ? "Watch in Brave" : "Open the song's page"
      iconText: root.player.onYouTube ? Model.GLYPH_VIDEO : Model.GLYPH_WEB
      foreground: root.fg
      fontFamily: root.fontFamily
      tooltipText: root.player.onYouTube ? "Opens the video in Brave (Shields blocks the ads) and pauses the audio"
        : "Opens the page the song plays from in Brave"
      onClicked: root.widget.watchVideo()
    }
  }
}
