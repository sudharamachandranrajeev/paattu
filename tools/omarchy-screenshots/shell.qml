import QtQuick
import Quickshell
import Quickshell.Io
import "paattu"
import "paattu/Model.js" as Model

// Offscreen screenshots of the Paattu plugin: the app window's pages and the
// desktop widget's three styles. OUT names the folder.
ShellRoot {
  id: shellRoot
  readonly property string out: Quickshell.env("OUT")

  Store { id: theStore; full: true }
  Player { id: thePlayer; polling: true }
  Jobs { id: slowJobs }
  Jobs { id: quickJobs }

  readonly property var track: Model.nowPlaying(theStore.full ? theStore.lib.tracks : null, thePlayer.path, thePlayer.mediaTitle)

  AppWindow {
    id: app
    store: theStore
    player: thePlayer
    jobs: slowJobs
    quick: quickJobs
    visible: true
    implicitWidth: 1280
    implicitHeight: 800
  }

  FloatingWindow {
    id: desk
    visible: true
    color: "#2a1a22"
    implicitWidth: 1100
    implicitHeight: 700
    Item {
      id: deskBox
      anchors.fill: parent
      DesktopCard {
        id: card
        anchors.centerIn: parent
        width: implicitWidth
        height: implicitHeight
        player: thePlayer
        store: theStore
        track: shellRoot.track
        fontFamily: app.fontFamily
        forcedStyle: "card"
      }
    }
  }

  property var steps: [
    function() { app.navigate("home") },
    function() { save(app.body, "home") },
    function() { app.navigate("playing") },
    function() { save(app.body, "now-playing") },
    function() { app.navigate("playlist", "paattu-demo0001") },
    function() { save(app.body, "playlist") },
    function() { app.navigate("sound") },
    function() { save(app.body, "sound") },
    function() { app.navigate("mixes") },
    function() { save(app.body, "mixes") },
    function() { app.navigate("settings") },
    function() { save(app.body, "settings") },
    function() { card.forcedStyle = "card" },
    function() { save(card, "desktop-card") },
    function() { card.forcedStyle = "vinyl" },
    function() { save(card, "desktop-vinyl") },
    function() { card.forcedStyle = "minimal" },
    function() { save(card, "desktop-minimal") },
    function() { Qt.quit() },
  ]
  property int step: 0

  function save(item, name) {
    item.grabToImage(function(result) { result.saveToFile(out + "/" + name + ".png") })
  }

  Timer {
    interval: 6000
    running: true
    onTriggered: tick.running = true
  }
  Timer {
    id: tick
    interval: 1800
    repeat: true
    onTriggered: {
      console.log("step", shellRoot.step, "connected", thePlayer.connected, "track", shellRoot.track.title)
      shellRoot.steps[shellRoot.step]()
      shellRoot.step++
    }
  }
}
