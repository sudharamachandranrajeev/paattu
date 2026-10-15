import QtQuick

// A frosted-glass panel (the look since 0.5, like the phone app): a faint
// fill of the text colour, a thin light edge and a sheen from the top, with
// big round corners. `lit` tints it with the accent (the selected one).
Rectangle {
  id: root

  required property var pal
  property bool lit: false
  property bool hovered: false

  radius: 24
  color: lit ? Qt.rgba(pal.accent.r, pal.accent.g, pal.accent.b, 0.18)
    : Qt.rgba(pal.foreground.r, pal.foreground.g, pal.foreground.b, hovered ? 0.09 : 0.05)
  border.width: 1
  border.color: lit ? Qt.rgba(pal.accent.r, pal.accent.g, pal.accent.b, 0.45)
    : Qt.rgba(pal.foreground.r, pal.foreground.g, pal.foreground.b, 0.11)

  // Light catching the top edge.
  Rectangle {
    anchors.fill: parent
    anchors.margins: 1
    radius: Math.max(0, root.radius - 1)
    gradient: Gradient {
      GradientStop { position: 0; color: Qt.rgba(1, 1, 1, 0.05) }
      GradientStop { position: 0.5; color: Qt.rgba(1, 1, 1, 0) }
    }
  }
}
