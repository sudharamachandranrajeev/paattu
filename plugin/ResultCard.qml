import QtQuick
import "Model.js" as Model

// An album, singer or playlist from a search (`paattu browse`): cover (round
// for singers), title, details and site. Click opens it.
Item {
  id: root

  required property var app
  required property var item
  property real size: 150

  readonly property var pal: app.pal
  readonly property bool round: item.type === "artist"
  readonly property bool hovered: mouse.containsMouse

  implicitWidth: size
  implicitHeight: size + 50

  Rectangle {
    anchors.fill: parent
    anchors.margins: -8
    radius: 12
    color: root.hovered ? Qt.rgba(root.pal.foreground.r, root.pal.foreground.g, root.pal.foreground.b, 0.06) : "transparent"
    Behavior on color { ColorAnimation { duration: 120 } }
  }

  Cover {
    id: art
    width: root.size
    height: root.size
    radius: 10
    circle: root.round
    source: root.app.store.artFor("c", root.item.artKey)
    revision: root.app.artRevision
    tint: Qt.rgba(root.pal.foreground.r, root.pal.foreground.g, root.pal.foreground.b, 0.08)
    glyphColor: root.pal.foreground
    glyph: Model.resultGlyph(root.item)
    fontFamily: root.app.fontFamily
  }

  Rectangle {
    anchors.left: art.left
    anchors.top: art.top
    anchors.margins: root.round ? 14 : 8
    radius: 4
    color: Qt.rgba(0, 0, 0, 0.55)
    width: site.implicitWidth + 10
    height: site.implicitHeight + 4
    Text {
      id: site
      anchors.centerIn: parent
      textFormat: Text.PlainText
      text: Model.siteName(root.item.site)
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
      horizontalAlignment: root.round ? Text.AlignHCenter : Text.AlignLeft
      textFormat: Text.PlainText
      text: root.item.title || ""
      color: root.pal.foreground
      font.family: root.app.fontFamily
      font.pixelSize: 13
      font.bold: true
      elide: Text.ElideRight
    }
    Text {
      width: parent.width
      horizontalAlignment: root.round ? Text.AlignHCenter : Text.AlignLeft
      textFormat: Text.PlainText
      text: [root.item.subtitle || "",
             root.item.count && String(root.item.subtitle || "").indexOf(String(root.item.count)) === -1
               ? Model.plural(root.item.count, "song") : ""].filter(function(s) { return s }).join(" · ")
      color: root.pal.muted
      font.family: root.app.fontFamily
      font.pixelSize: 11
      elide: Text.ElideRight
    }
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: root.app.openResult(root.item)
  }
}
