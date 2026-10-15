import QtQuick
import "Model.js" as Model

// One song in a list: number (or playing bars), title, movie, credits, length.
// A heart shows on favourites; hovering adds the add-to-playlist button, and
// on removable rows a remove button in place of the length. Search results
// (`found`) also get save-to-library and play-next, and show their quality.
Rectangle {
  id: root

  required property var app
  required property var track
  property int number: 0
  property bool current: false
  property bool playing: false
  property bool removable: false
  // A search result: not in the library yet.
  property bool found: false
  // In a narrow list (Now Playing's up next): no film or kind columns.
  property bool compact: false
  // Small text before the length: the kind of video, or a result's quality.
  property string badge: Model.qualityLabel(track) || (!found && track.kind && track.kind !== "video" ? track.kind : "")

  readonly property var pal: app.pal
  // A HoverHandler, not the row's MouseArea: the remove button takes the
  // MouseArea's hover, which would hide the button under the pointer.
  readonly property bool hovered: hover.hovered

  signal activated()
  signal removeRequested()
  signal playNext()

  HoverHandler { id: hover }

  // A pill, lit with the accent while it plays.
  height: 46
  radius: height / 2
  color: root.hovered ? Qt.rgba(pal.foreground.r, pal.foreground.g, pal.foreground.b, 0.07)
    : current ? Qt.rgba(pal.accent.r, pal.accent.g, pal.accent.b, 0.14) : "transparent"
  border.width: current ? 1 : 0
  border.color: Qt.rgba(pal.accent.r, pal.accent.g, pal.accent.b, 0.4)

  Item {
    id: lead
    x: 10
    width: 34
    height: parent.height

    Text {
      anchors.centerIn: parent
      visible: !root.current
      textFormat: Text.PlainText
      text: root.hovered ? Model.GLYPH_PLAY : root.number
      color: root.pal.muted
      font.family: root.app.fontFamily
      font.pixelSize: root.hovered ? 16 : 12
    }
    PlayingBars {
      anchors.centerIn: parent
      visible: root.current
      playing: root.playing
      color: root.pal.accent
      bars: 3
      barWidth: 3
      maxHeight: 14
    }
  }

  Cover {
    id: thumb
    anchors.left: lead.right
    anchors.leftMargin: 6
    anchors.verticalCenter: parent.verticalCenter
    width: 34
    height: 34
    radius: 12
    source: root.app.store.artFor("v", root.track.id)
    revision: root.app.artRevision
    tint: Qt.rgba(root.pal.foreground.r, root.pal.foreground.g, root.pal.foreground.b, 0.08)
    glyphColor: root.pal.muted
    fontFamily: root.app.fontFamily
  }

  Column {
    anchors.left: thumb.right
    anchors.leftMargin: 12
    anchors.right: movieText.left
    anchors.rightMargin: 12
    anchors.verticalCenter: parent.verticalCenter
    spacing: 1

    Text {
      width: parent.width
      textFormat: Text.PlainText
      text: root.track.title || root.track.rawTitle || root.track.id
      color: root.current ? root.pal.accent : root.pal.foreground
      font.family: root.app.fontFamily
      font.pixelSize: 13
      font.bold: root.current
      elide: Text.ElideRight
    }
    Text {
      width: parent.width
      textFormat: Text.PlainText
      text: (root.track.credits || []).slice(0, 3).join(", ") || root.track.channel || ""
      color: root.pal.muted
      font.family: root.app.fontFamily
      font.pixelSize: 11
      elide: Text.ElideRight
      visible: text !== ""
    }
  }

  Text {
    id: movieText
    anchors.right: actionSlot.left
    anchors.rightMargin: 12
    anchors.verticalCenter: parent.verticalCenter
    width: root.compact ? 0 : Math.min(220, root.width * 0.26)
    visible: !root.compact
    textFormat: Text.PlainText
    text: root.track.movie || ""
    color: root.pal.muted
    font.family: root.app.fontFamily
    font.pixelSize: 12
    elide: Text.ElideRight
  }

  // Heart (+ save) + add to playlist (+ play next); a fixed slot so the
  // columns don't shift on hover.
  Item {
    id: actionSlot
    anchors.right: kindText.left
    anchors.rightMargin: 4
    anchors.verticalCenter: parent.verticalCenter
    width: root.found ? 120 : 60
    height: 30

    // Anchored left so the heart stays put when the add button appears.
    SongActions {
      id: songActions
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      visible: !!root.track.id && (root.hovered || marked)
      store: root.app.store
      jobs: root.app.quick
      videoId: root.track.id || ""
      showSave: root.found
      showAdd: root.hovered
      color: root.pal.muted
      accent: root.pal.accent
      size: 30
      fontFamily: root.app.fontFamily
      onPick: function(anchor) { root.app.pickPlaylists(root.track, anchor) }
    }
    GlyphButton {
      anchors.left: songActions.right
      anchors.verticalCenter: parent.verticalCenter
      visible: root.found && root.hovered && songActions.visible
      glyph: Model.GLYPH_PLAY_NEXT
      size: 30
      color: root.pal.muted
      fontFamily: root.app.fontFamily
      tooltip: "Play next"
      onClicked: root.playNext()
    }
  }

  Text {
    id: kindText
    anchors.right: durationText.left
    anchors.rightMargin: 12
    anchors.verticalCenter: parent.verticalCenter
    width: root.compact ? 0 : 56
    visible: !root.compact
    textFormat: Text.PlainText
    text: root.badge
    color: root.pal.muted
    opacity: 0.7
    font.family: root.app.fontFamily
    font.pixelSize: 10
    horizontalAlignment: Text.AlignRight
  }

  Text {
    id: durationText
    anchors.right: parent.right
    anchors.rightMargin: 14
    anchors.verticalCenter: parent.verticalCenter
    width: 44
    textFormat: Text.PlainText
    text: root.track.duration ? Model.formatTime(root.track.duration) : ""
    visible: !removeButton.visible
    color: root.pal.muted
    font.family: root.app.fontFamily
    font.pixelSize: 12
    horizontalAlignment: Text.AlignRight
  }

  // Under the buttons (z -1), or it would take their clicks and play the song.
  MouseArea {
    id: mouse
    anchors.fill: parent
    z: -1
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: root.activated()
  }

  GlyphButton {
    id: removeButton
    anchors.right: parent.right
    anchors.rightMargin: 10
    anchors.verticalCenter: parent.verticalCenter
    visible: root.removable && root.hovered
    glyph: Model.GLYPH_DELETE
    size: 30
    color: root.pal.muted
    fontFamily: root.app.fontFamily
    tooltip: "Remove from this playlist"
    onClicked: root.removeRequested()
  }
}
