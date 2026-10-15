import QtQuick
import "Model.js" as Model

// The player's colours (Settings › Colours from the cover): the song's cover's
// (Model.coverPalette), keeping the theme dark or light, or the theme's own
// when the setting is off or the cover has no colour to take. The colours
// change slowly from one song to the next. A small hidden canvas reads the
// cover's pixels.
Item {
  id: root

  // The cover: a local file, "" for the theme's colours.
  property string source: ""
  // The theme's palette (Store.rawPalette): hex strings.
  required property var base

  // From the cover, or null.
  property var taken: null
  readonly property var raw: taken || base
  readonly property QtObject palette: QtObject {
    property color background: root.raw.background
    property color surface: root.raw.surface
    property color foreground: root.raw.foreground
    property color muted: root.raw.muted
    property color accent: root.raw.accent
    property color highlight: root.raw.highlight
    property color accentText: Model.onAccent(root.raw)

    Behavior on background { ColorAnimation { duration: 700 } }
    Behavior on surface { ColorAnimation { duration: 700 } }
    Behavior on foreground { ColorAnimation { duration: 700 } }
    Behavior on muted { ColorAnimation { duration: 700 } }
    Behavior on accent { ColorAnimation { duration: 700 } }
    Behavior on highlight { ColorAnimation { duration: 700 } }
    Behavior on accentText { ColorAnimation { duration: 700 } }
  }

  width: 32
  height: 32
  // Drawn, so it paints, but never seen.
  opacity: 0

  onSourceChanged: {
    if (!source) {
      taken = null
    } else if (sampler.isImageLoaded(source)) {
      sampler.requestPaint()
    } else {
      sampler.asked = sampler.asked.concat([source])
      sampler.loadImage(source)
    }
  }
  // Light or dark may have changed.
  onBaseChanged: if (source) sampler.requestPaint()

  Canvas {
    id: sampler
    anchors.fill: parent
    renderTarget: Canvas.Image
    renderStrategy: Canvas.Immediate

    onImageLoaded: requestPaint()
    onPaint: {
      var want = root.source
      if (!want || !isImageLoaded(want)) return
      var ctx = getContext("2d")
      var whole = ctx.createImageData(want)
      // The square the app shows of it (YouTube thumbnails are letterboxed).
      var clip = Model.coverClip(whole.width, whole.height)
      if (!clip) return
      ctx.clearRect(0, 0, 32, 32)
      ctx.drawImage(want, clip.x, clip.y, clip.width, clip.height, 0, 0, 32, 32)
      root.taken = Model.coverPalette(ctx.getImageData(0, 0, 32, 32).data, Model.luminance(root.base.background) < 0.5)
      // Covers come and go with the songs; keep only the one showing.
      for (var i = 0; i < asked.length; i++) if (asked[i] !== want) unloadImage(asked[i])
      asked = [want]
    }
    // Covers loaded (or loading).
    property var asked: []
  }
}
