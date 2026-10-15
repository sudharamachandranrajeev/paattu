import QtQuick
import QtQuick.Shapes

// Behind the window: the background, lit from the top right by the accent
// and a little from the left by the highlight.
Rectangle {
  id: root

  required property var pal
  readonly property bool dark: 0.299 * pal.background.r + 0.587 * pal.background.g + 0.114 * pal.background.b < 0.5
  readonly property real reach: Math.max(width, height)

  color: pal.background

  // A soft round light at (cx, cy), fading out by `r`.
  component Glow: Shape {
    id: glow
    property real cx: 0
    property real cy: 0
    property real r: 100
    property color tint: "transparent"
    anchors.fill: parent

    ShapePath {
      strokeWidth: -1
      strokeColor: "transparent"
      fillGradient: RadialGradient {
        centerX: glow.cx
        centerY: glow.cy
        centerRadius: glow.r
        focalX: glow.cx
        focalY: glow.cy
        GradientStop { position: 0; color: glow.tint }
        GradientStop { position: 1; color: Qt.rgba(glow.tint.r, glow.tint.g, glow.tint.b, 0) }
      }
      startX: 0; startY: 0
      PathLine { x: glow.width; y: 0 }
      PathLine { x: glow.width; y: glow.height }
      PathLine { x: 0; y: glow.height }
      PathLine { x: 0; y: 0 }
    }
  }

  Glow {
    cx: root.width * 0.85
    cy: -root.height * 0.2
    r: root.reach * 0.75
    tint: Qt.rgba(root.pal.accent.r, root.pal.accent.g, root.pal.accent.b, root.dark ? 0.32 : 0.16)
  }
  Glow {
    cx: -root.width * 0.1
    cy: root.height * 0.4
    r: root.reach * 0.45
    tint: Qt.rgba(root.pal.highlight.r, root.pal.highlight.g, root.pal.highlight.b, root.dark ? 0.12 : 0.06)
  }
}
