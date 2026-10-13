import QtQuick
import Quickshell
import "Model.js" as Model

// The desktop widget's frame: translucent panel in the chosen style, a small
// toolbar on hover, right-click to change style, wheel for volume, and the
// add-to-playlist picker over the widget.
Item {
  id: root

  required property var player
  required property var store
  required property var track
  property int artRevision: 0
  property string fontFamily: "monospace"

  readonly property bool wired: !!store && !!player
  readonly property var pal: wired ? store.palette : fallbackPalette
  readonly property var settings: wired ? store.desktop : ({})
  readonly property var fallbackPalette: ({ background: "#000000", foreground: "#ffffff", accent: "#ffffff", muted: "#888888" })
  // Previews force a style; otherwise config.json decides.
  property string forcedStyle: ""
  readonly property string style: forcedStyle || (Model.STYLES.indexOf(settings.style) !== -1 ? settings.style : "vinyl")
  readonly property real s: Math.max(0.6, Math.min(2, Number(settings.scale) || 1))

  signal playMix(string mixId, string title)
  signal openApp()
  signal cycleStyle()
  signal watch()

  // Its own runner for heart / add-to-playlist commands.
  Jobs { id: deskJobs }

  // The widget's layer has no keyboard, so a new playlist is named in the app.
  function pickInApp() {
    Quickshell.execDetached(["omarchy-shell", "shell", "summon", "rajeevrama.paattu", JSON.stringify({ view: "pick" })])
  }

  implicitWidth: loader.item ? loader.item.implicitWidth : 400
  implicitHeight: loader.item ? loader.item.implicitHeight : 200

  Rectangle {
    id: panel
    anchors.fill: parent
    radius: 22 * root.s
    color: Qt.rgba(root.pal.background.r, root.pal.background.g, root.pal.background.b,
      Math.max(0, Math.min(1, Number(root.settings.opacity) || 0.92)))
    border.width: 1
    border.color: Qt.rgba(root.pal.foreground.r, root.pal.foreground.g, root.pal.foreground.b, 0.09)

    // A wash of the accent colour in one corner.
    Rectangle {
      anchors.fill: parent
      radius: parent.radius
      opacity: root.player.playing ? 0.16 : 0.08
      gradient: Gradient {
        orientation: Gradient.Horizontal
        GradientStop { position: 0.0; color: root.pal.accent }
        GradientStop { position: 0.55; color: "transparent" }
      }
      Behavior on opacity { NumberAnimation { duration: 600 } }
    }
  }

  // Non-exclusive, so it still sees the pointer over buttons in the style.
  HoverHandler { id: cardHover }

  MouseArea {
    id: hover
    anchors.fill: parent
    acceptedButtons: Qt.RightButton | Qt.MiddleButton
    onClicked: function(e) {
      if (e.button === Qt.RightButton) root.cycleStyle()
      else root.openApp()
    }
    onWheel: function(e) { root.player.changeVolume(e.angleDelta.y > 0 ? 5 : -5) }
  }

  Loader {
    id: loader
    anchors.fill: parent
    // Only once the store and player are wired in, so the style's bindings
    // never see them undefined.
    active: root.wired
    sourceComponent: root.style === "card" ? cardStyle : root.style === "minimal" ? minimalStyle : vinylStyle
  }

  Component {
    id: vinylStyle
    VinylStyle {
      player: root.player; store: root.store; track: root.track; s: root.s
      fontFamily: root.fontFamily; artRevision: root.artRevision; jobs: deskJobs
      onPlayMix: function(mixId, title) { root.playMix(mixId, title) }
      onOpenApp: root.openApp()
      onPick: picker.visible = true
    }
  }
  Component {
    id: cardStyle
    CardStyle {
      player: root.player; store: root.store; track: root.track; s: root.s
      fontFamily: root.fontFamily; artRevision: root.artRevision; jobs: deskJobs
      onPlayMix: function(mixId, title) { root.playMix(mixId, title) }
      onOpenApp: root.openApp()
      onPick: picker.visible = true
    }
  }
  Component {
    id: minimalStyle
    MinimalStyle {
      player: root.player; store: root.store; track: root.track; s: root.s
      fontFamily: root.fontFamily; artRevision: root.artRevision; jobs: deskJobs
      onPlayMix: function(mixId, title) { root.playMix(mixId, title) }
      onOpenApp: root.openApp()
      onPick: picker.visible = true
    }
  }

  // Toolbar, top right, while the pointer is over the widget.
  Row {
    anchors.top: parent.top
    anchors.right: parent.right
    anchors.margins: 8 * root.s
    spacing: 2
    opacity: cardHover.hovered && !picker.visible ? 1 : 0
    visible: opacity > 0
    Behavior on opacity { NumberAnimation { duration: 160 } }

    GlyphButton {
      glyph: Model.GLYPH_PALETTE; size: 24 * root.s; color: root.pal.muted; fontFamily: root.fontFamily
      onClicked: root.cycleStyle()
    }
    GlyphButton {
      glyph: root.player.onYouTube ? Model.GLYPH_VIDEO : Model.GLYPH_WEB
      size: 24 * root.s; color: root.pal.muted; fontFamily: root.fontFamily
      visible: root.player.hasTrack
      onClicked: root.watch()
    }
    GlyphButton {
      glyph: Model.GLYPH_OPEN; size: 24 * root.s; color: root.pal.muted; fontFamily: root.fontFamily
      onClicked: root.openApp()
    }
  }

  // Add to playlist, over the widget; a click elsewhere on it closes it.
  MouseArea {
    anchors.fill: parent
    visible: picker.visible
    acceptedButtons: Qt.AllButtons
    onPressed: picker.visible = false
    onWheel: function(e) { e.accepted = true }
  }
  PlaylistPicker {
    id: picker
    visible: false
    anchors.top: parent.top
    anchors.right: parent.right
    anchors.margins: 10 * root.s
    width: Math.min(290 * root.s, root.width - 20 * root.s)
    maxHeight: root.height - 20 * root.s
    store: root.store
    jobs: deskJobs
    videoId: root.player.videoId
    songTitle: root.track.title || ""
    canType: false
    background: root.pal.background
    foreground: root.pal.foreground
    muted: root.pal.muted
    accent: root.pal.accent
    fontFamily: root.fontFamily
    s: root.s
    onClosed: visible = false
    onNewRequested: {
      visible = false
      root.pickInApp()
    }
    Connections {
      target: root.player
      function onHasTrackChanged() { if (!root.player.hasTrack) picker.visible = false }
    }
  }
}
