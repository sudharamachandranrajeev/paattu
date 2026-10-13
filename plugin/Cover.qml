import QtQuick
import QtQuick.Effects
import "Model.js" as Model

// Cover art from the local art cache, cropped to a square (YouTube thumbnails
// are letterboxed 4:3) with rounded corners or a circle. Shows a glyph on a
// tinted tile while the image is missing.
Item {
  id: root

  property string source: ""
  property real radius: 8
  property bool circle: false
  property bool crop: true
  property color tint: "#333333"
  property color glyphColor: "#ffffff"
  property string glyph: Model.GLYPH_NOTE
  property string fontFamily: "monospace"
  // Unused: kept so callers can pass it; the store's art index decides when a
  // cover can load.
  property int revision: 0

  readonly property real cornerRadius: circle ? Math.min(width, height) / 2 : radius
  readonly property bool ready: image.status === Image.Ready
  // The software renderer can't draw layers; show square art there instead.
  readonly property bool masked: GraphicsInfo.api !== GraphicsInfo.Software

  Rectangle {
    anchors.fill: parent
    radius: root.cornerRadius
    color: root.tint
    visible: !root.ready

    Text {
      anchors.centerIn: parent
      textFormat: Text.PlainText
      text: root.glyph
      color: root.glyphColor
      opacity: 0.55
      font.family: root.fontFamily
      font.pixelSize: Math.max(10, Math.min(root.width, root.height) * 0.42)
    }
  }

  Image {
    id: image
    anchors.fill: parent
    visible: root.ready
    asynchronous: true
    cache: true
    smooth: true
    mipmap: true
    fillMode: Image.PreserveAspectCrop
    property size natural: Qt.size(0, 0)
    readonly property var clip: root.crop ? Model.coverClip(natural.width, natural.height) : null
    source: root.source
    // Unset (no clipping) until the size is known.
    sourceClipRect: clip ? Qt.rect(clip.x, clip.y, clip.width, clip.height) : undefined
    onStatusChanged: {
      // Learn the image size once, then crop the centre square out of it.
      if (status === Image.Ready && natural.width === 0 && !clip) natural = Qt.size(implicitWidth, implicitHeight)
    }
    onSourceChanged: natural = Qt.size(0, 0)
    // Rounded corners / circle. Renderers without shader support just show
    // the square image. Never tie this to the image status: a window's first
    // scale change reloads the image mid-walk of the item tree, and turning the
    // layer off then deletes its effect items under Qt (shell crash).
    layer.enabled: root.masked
    layer.smooth: true
    layer.effect: MultiEffect {
      maskEnabled: true
      maskSource: mask
      maskThresholdMin: 0.5
      maskSpreadAtMin: 1.0
    }
  }

  Item {
    id: mask
    anchors.fill: parent
    visible: false
    layer.enabled: true
    Rectangle {
      anchors.fill: parent
      radius: root.cornerRadius
      color: "black"
    }
  }
}
