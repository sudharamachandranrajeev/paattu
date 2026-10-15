import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Paattu in the status bar: what's playing, with a panel of controls, the
// queue, one-tap mixes (keys 1-9 start mix N) and an online search (/).
//
//   left click   open the panel        middle click   play / pause
//   right click  next track            scroll         volume
Panel {
  id: root
  moduleName: "rajeevrama.paattu"
  ipcTarget: "rajeevrama.paattu"

  readonly property string labelMode: setting("label", "title")
  readonly property int maxLabelWidth: Number(setting("maxWidth", 170)) || 170
  readonly property string scrollAction: setting("scroll", "volume")
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property color fg: bar ? bar.foreground : Color.foreground
  readonly property var track: Model.nowPlaying(null, player.path, player.mediaTitle)
  property int artRevision: 0

  Store { id: theStore }
  Player { id: thePlayer; polling: root.opened }
  Jobs { id: theJobs }
  // Searches get their own runner so they don't wait behind other commands.
  Jobs { id: searchJobs }

  property alias player: thePlayer
  property alias store: theStore
  property alias jobs: theJobs

  // The panel's online search: what was searched and what came back.
  readonly property var noSearch: ({ query: "", results: [], errors: ({}), busy: false, error: "" })
  property var online: noSearch

  function searchOnline(text) {
    text = String(text || "").trim()
    if (!text) return
    online = { query: text, results: [], errors: ({}), busy: true, error: "" }
    searchJobs.run(Model.searchArgs(text, []), "", function(ok, e) {
      if (root.online.query !== text) return  // a newer search took over
      root.online = { query: text, results: ok && e.results ? e.results : [], errors: ok && e.errors ? e.errors : ({}),
        busy: false, error: ok ? "" : (e.message || "The search didn't work") }
      theStore.refreshArt()
    })
  }
  function clearSearch() {
    online = noSearch
  }
  // The same search in the app, with room for every result.
  function searchInApp(text) {
    Quickshell.execDetached(["omarchy-shell", "shell", "summon", "rajeevrama.paattu", JSON.stringify({ view: "search", query: text })])
    close()
  }
  function playSong(track) { if (track && track.id) run(Model.playSongArgs(track.id), "Loading " + (track.title || "the song") + "…") }
  function queueSong(track, next) {
    if (track && track.id) jobs.run(Model.queueSongArgs(track.id, next), next ? "Playing it next…" : "Adding to the queue…")
  }
  // Back to the panel's keys (after typing in a box).
  function focusKeys() { keyCatcher.forceActiveFocus() }

  function playMix(id, title) { run(Model.playMixArgs(id), "Starting " + (title || "the mix") + "…") }
  // Mix n (1-based) on the buttons.
  function playMixAt(n) {
    var mix = store.mixes[n - 1]
    if (mix) playMix(mix.id, mix.title)
  }
  function playPlaylist(id) { run(["play", id], "Loading playlist…") }
  function openApp(view) {
    Quickshell.execDetached(["omarchy-shell", "shell", "summon", "rajeevrama.paattu", JSON.stringify({ view: view || "home" })])
    close()
  }
  function watchVideo() { if (player.hasTrack) { run(["watch"], "Opening in Brave…"); close() } }
  function run(args, label) { jobs.run(args, label, function(ok) { if (ok) root.cacheArt() }) }

  // Make sure the cover of whatever plays is in the art cache.
  function cacheArt() {
    if (player.videoId) Quickshell.execDetached(["paattu", "art", "--tracks=" + player.videoId])
    artRefresh.restart()
  }

  Connections {
    target: thePlayer
    function onTrackChanged(id) { if (id) root.cacheArt() }
  }

  Timer {
    id: artRefresh
    interval: 1500
    onTriggered: theStore.refreshArt()
  }

  onOpenedChanged: if (opened) player.pollPosition()

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  // ---------- Bar button ----------
  Row {
    id: button
    spacing: 0

    readonly property string label: root.labelMode === "none" || !player.hasTrack ? ""
      : root.track.title + (root.track.movie ? "  ·  " + root.track.movie : "")
    readonly property string tooltip: (player.hasTrack
        ? root.track.title + (root.track.movie ? " — " + root.track.movie : "") + (player.paused ? "  (paused)" : "")
        : (player.connected ? "Paattu — nothing playing" : "Paattu"))
      + "\nClick: controls · Middle: play/pause · Right: next · Scroll: "
      + (root.scrollAction === "track" ? "previous/next" : "volume")

    function press(b) {
      if (b === Qt.MiddleButton) {
        if (player.hasTrack) player.togglePause()
        else if (store.mixes.length) root.playMixAt(1)
        else root.openApp("mixes")
      } else if (b === Qt.RightButton) {
        player.next()
      } else {
        root.toggle()
      }
    }

    BarIconButton {
      id: iconButton
      bar: root.bar
      tooltipText: button.tooltip
      onPressed: function(b) { button.press(b) }

      iconComponent: Item {
        OpticalGlyph {
          anchors.fill: parent
          visible: !player.playing
          text: Model.GLYPH_NOTE
          fontFamily: root.fontFamily
          fontSize: Style.bar.iconFont
          color: player.hasTrack ? (root.bar ? root.bar.barForeground : Color.foreground)
            : Qt.darker(root.bar ? root.bar.barForeground : Color.foreground, 1.5)
        }

        PlayingBars {
          anchors.centerIn: parent
          visible: player.playing
          playing: player.playing
          color: Color.accent
          bars: 3
          barWidth: Math.max(2, Math.round(Style.bar.iconFont * 0.2))
          maxHeight: Math.round(Style.bar.iconFont * 0.95)
        }
      }
    }

    Item {
      id: labelClip
      visible: button.label !== "" && !iconButton.vertical
      width: Math.min(root.maxLabelWidth, labelText.implicitWidth)
      height: iconButton.height
      clip: true

      Text {
        id: labelText
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: button.label
        color: player.paused ? Qt.darker(root.bar ? root.bar.barForeground : Color.foreground, 1.4)
          : (root.bar ? root.bar.barForeground : Color.foreground)
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        readonly property bool needsScroll: implicitWidth > labelClip.width

        NumberAnimation on x {
          running: labelText.needsScroll && player.playing && !root.opened
          loops: Animation.Infinite
          from: labelClip.width
          to: -labelText.implicitWidth
          duration: Math.max(7000, labelText.implicitWidth * 28)
        }
        onNeedsScrollChanged: if (!needsScroll) x = 0
      }

      MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
        cursorShape: Qt.PointingHandCursor
        hoverEnabled: true
        onClicked: function(e) { button.press(e.button) }
        onWheel: function(e) { wheelHandler.handle(e.angleDelta.y) }
        onEntered: if (root.bar) root.bar.showTooltip(labelClip, button.tooltip)
        onExited: if (root.bar) root.bar.hideTooltip(labelClip)
      }
    }

    Item {
      visible: labelClip.visible
      width: Style.space(8)
      height: 1
    }
  }

  // Scroll on the icon too.
  WheelHandler {
    id: wheelHandler
    target: null
    parent: button
    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
    function handle(dy) {
      if (!player.connected || dy === 0) return
      if (root.scrollAction === "track") { if (dy > 0) player.previous(); else player.next() }
      else player.changeVolume(dy > 0 ? 5 : -5)
    }
    onWheel: function(e) { handle(e.angleDelta.y) }
  }

  // ---------- Panel ----------
  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(380))
    contentHeight: panel.fittedContentHeight(content.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      // Typing in the search or new-playlist box: the keys are text.
      blocked: content.typing
      onMoveRequested: function(dx, dy) {
        if (dx !== 0) player.seekBy(dx * 10)
        else if (dy !== 0) player.changeVolume(-dy * 5)
      }
      onActivateRequested: player.togglePause()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (t === " ") player.togglePause()
        else if (t === "n") player.next()
        else if (t === "p") player.previous()
        else if (t === "s") player.toggleShuffle()
        else if (t === "r") player.cycleRepeat()
        else if (t === "o") root.openApp()
        else if (t === "w") root.watchVideo()
        else if (t === "/") {
          scroll.contentY = 0
          content.focusSearch()
        }
        else if (t >= "1" && t <= "9") root.playMixAt(Number(t))
      }

      Flickable {
        id: scroll
        anchors.fill: parent
        contentWidth: width
        contentHeight: content.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height

        BarContent {
          id: content
          width: scroll.width
          widget: root
        }
      }
    }
  }
}
