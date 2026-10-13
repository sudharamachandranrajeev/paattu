import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.Commons
import "Model.js" as Model

// Paattu's always-loaded half: the desktop widget on the home workspace and
// the app window (summoned from the bar, the launcher or Super+Shift+M).
//
//   omarchy-shell shell summon rajeevrama.paattu '{"view":"users"}'
//   omarchy-shell paattu open|toggle|close|style <vinyl|card|minimal>
Item {
  id: root

  property var shell: null
  property var manifest: null
  property bool opened: false
  property int artRevision: 0

  readonly property var desktop: theStore.desktop
  readonly property string fontFamily: Style.font.family

  // Not named store / player: `store: store` on a child that has a `store`
  // property would bind the child's property to itself.
  Store { id: theStore; full: root.opened }
  Player { id: thePlayer; polling: true }
  Jobs { id: slowJobs }
  Jobs { id: quickJobs }

  readonly property var track: Model.nowPlaying(theStore.full ? theStore.lib.tracks : null, thePlayer.path, thePlayer.mediaTitle)

  // ---------- host lifecycle ----------
  function open(payloadJson) {
    var payload = {}
    try { payload = JSON.parse(payloadJson || "{}") || {} } catch (e) { payload = {} }
    opened = true
    Qt.callLater(function() {
      if (!appLoader.item) return
      appLoader.item.visible = true
      // {view: "search", query}: from the bar panel's search.
      if (payload.view === "search" && payload.query) appLoader.item.searchOnline(String(payload.query))
      else if (payload.view) appLoader.item.navigate(payload.view, payload.arg === undefined ? null : payload.arg)
    })
  }

  function close() {
    if (appLoader.item) appLoader.item.visible = false
    opened = false
  }

  function toggle() { opened ? hideFromUser() : open("{}") }

  // The user closed the window (Esc / close button): tell the host.
  function hideFromUser() {
    opened = false
    if (shell && typeof shell.hide === "function") shell.hide("rajeevrama.paattu")
  }

  // ---------- actions ----------
  function playMix(mixId, title) {
    quickJobs.run(Model.playMixArgs(mixId), "Starting " + (title || "the mix") + "…")
  }
  function cycleStyle() {
    quickJobs.run(["config", "set", "desktop.style", Model.nextIn(Model.STYLES, desktop.style || "vinyl")], "")
  }
  function watch() { quickJobs.run(["watch"], "") }

  Connections {
    target: thePlayer
    function onTrackChanged(id) {
      if (id) quickJobs.run(["art", "--tracks=" + id], "", function() { artTimer.restart() })
    }
  }

  Timer {
    id: artTimer
    interval: 300
    onTriggered: theStore.refreshArt()
  }

  // ---------- app window ----------
  Loader {
    id: appLoader
    active: root.opened
    sourceComponent: AppWindow {
      store: theStore
      player: thePlayer
      jobs: slowJobs
      quick: quickJobs
      visible: false
      onDismissed: if (root.opened) root.hideFromUser()
    }
  }

  // ---------- desktop widget ----------
  Variants {
    id: desktops
    model: Quickshell.screens

    PanelWindow {
      id: deskWindow
      required property var modelData

      readonly property var hyprMonitor: Hyprland.monitorFor(modelData)
      readonly property int homeWorkspace: Number(root.desktop.workspace) || 1
      readonly property bool onHome: !!(hyprMonitor && hyprMonitor.activeWorkspace
        && hyprMonitor.activeWorkspace.id === homeWorkspace)
      readonly property bool wanted: root.desktop.enabled !== false
        && (!root.desktop.monitor || root.desktop.monitor === modelData.name)
      readonly property var edge: Model.anchorsFor(root.desktop.position)
      readonly property int marginX: Number(root.desktop.marginX) || 56
      readonly property int marginY: Number(root.desktop.marginY) || 56

      screen: modelData
      visible: wanted && onHome
      color: "transparent"
      implicitWidth: card.implicitWidth
      implicitHeight: card.implicitHeight

      WlrLayershell.namespace: "paattu-desktop"
      WlrLayershell.layer: WlrLayer.Bottom
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
      // Stay clear of the bar, but don't push windows around.
      exclusionMode: ExclusionMode.Normal
      exclusiveZone: 0

      anchors {
        top: edge.top
        bottom: edge.bottom
        left: edge.left
        right: edge.right
      }
      margins {
        top: edge.top ? marginY : 0
        bottom: edge.bottom ? marginY : 0
        left: edge.left ? marginX : 0
        right: edge.right ? marginX : 0
      }

      onVisibleChanged: if (visible) fadeIn.restart()
      readonly property bool cardWired: card.wired
      readonly property real cardWidth: card.implicitWidth

      DesktopCard {
        id: card
        anchors.fill: parent
        player: thePlayer
        store: theStore
        track: root.track
        artRevision: root.artRevision
        fontFamily: root.fontFamily
        onPlayMix: function(mixId, title) { root.playMix(mixId, title) }
        onOpenApp: root.open(JSON.stringify({ view: "home" }))
        onCycleStyle: root.cycleStyle()
        onWatch: root.watch()

        NumberAnimation on opacity {
          id: fadeIn
          from: 0
          to: 1
          duration: 380
          easing.type: Easing.OutCubic
        }
      }
    }
  }

  // ---------- IPC ----------
  IpcHandler {
    target: "paattu"

    function open(view: string): void { root.open(JSON.stringify({ view: view || "home" })) }
    function toggle(): void { root.toggle() }
    function close(): void { root.hideFromUser() }
    function style(name: string): void {
      if (Model.STYLES.indexOf(name) !== -1) quickJobs.run(["config", "set", "desktop.style", name], "")
    }
    function status(): string {
      return JSON.stringify({ connected: thePlayer.connected, playing: thePlayer.playing, title: root.track.title,
        movie: root.track.movie, videoId: thePlayer.videoId, quality: thePlayer.quality, position: thePlayer.position, duration: thePlayer.duration,
        appOpen: root.opened, desktopStyle: root.desktop.style,
        desktops: desktops.instances.map(function(w) {
          return { screen: w.modelData ? w.modelData.name : "", visible: w.visible, width: w.implicitWidth,
            height: w.implicitHeight, wired: w.cardWired, cardWidth: w.cardWidth }
        }) })
    }
  }
}
