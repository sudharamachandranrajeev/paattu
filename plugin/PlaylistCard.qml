import QtQuick
import "Model.js" as Model

// A playlist tile: cover, title, owner. Click opens it; the round button plays.
Item {
  id: root

  required property var app
  required property var playlist
  property real size: 168

  readonly property var pal: app.pal
  // Favourites and Saved songs are tiles of their own.
  readonly property bool builtin: Model.isBuiltin(playlist.id)
  readonly property var cover: Model.coverOf(playlist)
  readonly property bool own: cover.kind === "v"
  readonly property bool saved: !!playlist.saved || own
  readonly property bool hovered: mouse.containsMouse || playButton.hovered

  implicitWidth: size
  implicitHeight: size + 52

  Rectangle {
    anchors.fill: parent
    anchors.margins: -8
    radius: 26
    color: root.hovered ? Qt.rgba(root.pal.foreground.r, root.pal.foreground.g, root.pal.foreground.b, 0.06) : "transparent"
    Behavior on color { ColorAnimation { duration: 120 } }
  }

  Cover {
    id: art
    width: root.size
    height: root.size
    radius: 20
    // Favourites and Saved songs are tiles; your playlists wear their first song's art.
    source: root.builtin ? "" : root.app.store.artFor(root.cover.kind, root.cover.id)
    revision: root.app.artRevision
    tint: root.builtin ? root.pal.accent : Qt.rgba(root.pal.foreground.r, root.pal.foreground.g, root.pal.foreground.b, 0.08)
    glyphColor: root.builtin ? root.pal.accentText : root.pal.foreground
    glyph: root.builtin ? Model.ownGlyph(root.playlist.id) : root.playlist.auto ? Model.GLYPH_USER : Model.GLYPH_PLAYLIST
    fontFamily: root.app.fontFamily
  }

  GlyphButton {
    id: playButton
    anchors.right: art.right
    anchors.bottom: art.bottom
    anchors.margins: 8
    size: 40
    glyph: Model.GLYPH_PLAY
    color: root.pal.accentText
    fill: root.pal.accent
    fontFamily: root.app.fontFamily
    opacity: root.hovered && (root.playlist.count || !root.own) ? 1 : 0
    visible: opacity > 0
    Behavior on opacity { NumberAnimation { duration: 140 } }
    onClicked: root.app.playPlaylist(root.playlist.id, false)
  }

  Rectangle {
    anchors.left: art.left
    anchors.top: art.top
    anchors.margins: 8
    visible: !root.saved
    radius: height / 2
    color: Qt.rgba(0, 0, 0, 0.4)
    border.width: 1
    border.color: Qt.rgba(1, 1, 1, 0.18)
    width: notSaved.implicitWidth + 16
    height: notSaved.implicitHeight + 6
    Text {
      id: notSaved
      anchors.centerIn: parent
      textFormat: Text.PlainText
      text: "not saved"
      color: "#ffffff"
      font.family: root.app.fontFamily
      font.pixelSize: 9
    }
  }

  Column {
    anchors.top: art.bottom
    anchors.topMargin: 8
    width: root.size
    spacing: 2

    Text {
      width: parent.width
      textFormat: Text.PlainText
      // Auto playlists ("Muzik247 — Most played") lead with the owner.
      text: root.playlist.auto ? Model.ownerName(root.app.store.lib, root.playlist) || root.playlist.title
        : (root.playlist.title || "Untitled")
      color: root.pal.foreground
      font.family: root.app.fontFamily
      font.pixelSize: 13
      font.bold: true
      elide: Text.ElideRight
    }
    Text {
      width: parent.width
      textFormat: Text.PlainText
      text: root.own ? (root.playlist.id === Model.FAVOURITES ? "Songs you hearted" : "Your playlist") + " · " + Model.plural(root.playlist.count || 0, "song")
        : (root.playlist.auto ? (root.playlist.title.indexOf("New releases") !== -1 ? "New releases" : "Most played")
          : Model.ownerName(root.app.store.lib, root.playlist))
        + (root.playlist.count ? " · " + root.playlist.count : "")
      color: root.pal.muted
      font.family: root.app.fontFamily
      font.pixelSize: 11
      elide: Text.ElideRight
    }
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    z: -1
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: root.app.openPlaylist(root.playlist.id)
  }
}
