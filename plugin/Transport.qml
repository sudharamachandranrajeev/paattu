import QtQuick
import "Model.js" as Model

// Shuffle · previous · play/pause · next · repeat, wired to a Player.
Row {
  id: root

  required property var player
  property color color: "#ffffff"
  property color accent: "#ffffff"
  property color accentText: "#000000"
  property real size: 34
  property bool showModes: true
  property string fontFamily: "monospace"

  spacing: Math.round(size * 0.22)

  GlyphButton {
    anchors.verticalCenter: parent.verticalCenter
    visible: root.showModes
    glyph: Model.GLYPH_SHUFFLE
    size: root.size * 0.82
    color: root.player.shuffle ? root.accent : root.color
    active: root.player.shuffle
    fontFamily: root.fontFamily
    onClicked: root.player.toggleShuffle()
  }

  GlyphButton {
    anchors.verticalCenter: parent.verticalCenter
    glyph: Model.GLYPH_PREV
    size: root.size
    color: root.color
    fontFamily: root.fontFamily
    enabled: root.player.hasTrack
    onClicked: root.player.previous()
  }

  GlyphButton {
    anchors.verticalCenter: parent.verticalCenter
    glyph: root.player.playing ? Model.GLYPH_PAUSE : Model.GLYPH_PLAY
    size: root.size * 1.35
    glyphScale: 0.5
    color: root.accentText
    fill: root.accent
    fontFamily: root.fontFamily
    enabled: root.player.hasTrack
    onClicked: root.player.togglePause()
  }

  GlyphButton {
    anchors.verticalCenter: parent.verticalCenter
    glyph: Model.GLYPH_NEXT
    size: root.size
    color: root.color
    fontFamily: root.fontFamily
    enabled: root.player.hasTrack
    onClicked: root.player.next()
  }

  GlyphButton {
    anchors.verticalCenter: parent.verticalCenter
    visible: root.showModes
    glyph: Model.repeatGlyph(root.player.repeat)
    size: root.size * 0.82
    color: root.player.repeat !== "off" ? root.accent : root.color
    active: root.player.repeat !== "off"
    fontFamily: root.fontFamily
    onClicked: root.player.cycleRepeat()
  }
}
