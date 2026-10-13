import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import "Model.js" as Model

// Paattu's files, watched so every surface updates the moment they change:
//   ~/.local/share/paattu/shelf.json    saved playlists per language, your own, mixes (small)
//   ~/.local/share/paattu/library.json  everything (loaded only when `full`)
//   ~/.config/paattu/config.json        looks and behaviour
//   ~/.config/paattu/themes/<name>.json colour schemes (Spicetify-style)
Item {
  id: root

  readonly property string home: Quickshell.env("HOME")
  readonly property string dataDir: (Quickshell.env("XDG_DATA_HOME") || home + "/.local/share") + "/paattu"
  readonly property string configDir: (Quickshell.env("XDG_CONFIG_HOME") || home + "/.config") + "/paattu"
  readonly property string cacheDir: (Quickshell.env("XDG_CACHE_HOME") || home + "/.cache") + "/paattu"

  // Load the whole library (the app window needs it; the bar doesn't).
  property bool full: false

  property var shelf: ({ languages: {}, users: [], counts: { users: 0, tracks: 0, saved: 0 } })
  property var lib: ({ users: {}, playlists: {}, tracks: {} })
  property int libRevision: 0
  property var config: defaults
  property var themeData: null

  readonly property var defaults: ({
    theme: "omarchy",
    desktop: { enabled: true, workspace: 1, monitor: "", style: "vinyl", position: "bottom-left",
      marginX: 56, marginY: 56, scale: 1.0, opacity: 0.92, showQuickPicks: true, showUpNext: true },
    languages: ["Malayalam", "Tamil"]
  })
  readonly property var desktop: config.desktop || defaults.desktop
  readonly property var languages: config.languages && config.languages.length ? config.languages : Model.LANGUAGES
  readonly property string themeName: config.theme || "omarchy"
  readonly property var rawPalette: Model.palette(themeName, themeData, {
    background: String(Color.background), foreground: String(Color.foreground),
    accent: String(Color.accent), muted: String(Color.muted)
  })
  // QML colours, so surfaces can use .r/.g/.b and Util.alpha().
  readonly property QtObject palette: QtObject {
    property color background: root.rawPalette.background
    property color surface: root.rawPalette.surface
    property color foreground: root.rawPalette.foreground
    property color muted: root.rawPalette.muted
    property color accent: root.rawPalette.accent
    property color highlight: root.rawPalette.highlight
    property color accentText: Model.onAccent(root.rawPalette)
  }
  readonly property bool hasLibrary: (shelf.counts && shelf.counts.saved > 0) || false
  // Your own playlists (Favourites and Saved songs first) and the songs in Favourites.
  readonly property var mine: Model.ownPlaylists(shelf)
  // The shuffle buttons, in order.
  readonly property var mixes: Model.mixesOf(shelf, languages)
  readonly property var favourites: Model.favouriteSet(shelf)
  // Songs saved to the library (Saved songs), mostly from searches.
  readonly property var saved: Model.savedSet(shelf)

  // Which covers are cached, so images are only requested once they exist.
  property var artIndex: ({})
  property bool artRescan: false

  function artFor(kind, id) {
    if (!id || !artIndex[kind + "/" + id]) return ""
    return "file://" + Model.artPath(cacheDir, kind, id)
  }

  // Call after `paattu art` has cached something.
  function refreshArt() {
    if (artProc.running) artRescan = true
    else artProc.running = true
  }

  Process {
    id: artProc
    command: ["find", root.cacheDir + "/art", "-name", "*.jpg", "-size", "+0", "-printf", "%P\\n"]
    stdout: StdioCollector {
      onStreamFinished: {
        var index = {}
        var lines = String(text || "").split("\n")
        for (var i = 0; i < lines.length; i++) {
          var line = lines[i]
          if (line.length > 4) index[line.slice(0, -4)] = true
        }
        root.artIndex = index
      }
    }
    onExited: if (root.artRescan) { root.artRescan = false; running = true }
  }

  Component.onCompleted: refreshArt()

  function merge(base, over) {
    var out = {}
    for (var k in base) out[k] = base[k]
    for (var key in over) {
      if (over[key] && typeof over[key] === "object" && !Array.isArray(over[key]) && base[key] && typeof base[key] === "object")
        out[key] = merge(base[key], over[key])
      else
        out[key] = over[key]
    }
    return out
  }

  function parse(text, fallback) {
    try { return JSON.parse(text) } catch (e) { return fallback }
  }

  FileView {
    id: shelfFile
    path: root.dataDir + "/shelf.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.shelf = root.parse(text(), root.shelf)
  }

  FileView {
    id: libFile
    path: root.full ? root.dataDir + "/library.json" : ""
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      root.lib = root.parse(text(), root.lib)
      root.libRevision++
    }
  }

  // Drop the big library when the app closes.
  onFullChanged: if (!full) lib = ({ users: {}, playlists: {}, tracks: {} })

  FileView {
    id: configFile
    path: root.configDir + "/config.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.config = root.merge(root.defaults, root.parse(text(), {}))
    onLoadFailed: root.config = root.defaults
  }

  FileView {
    id: themeFile
    path: root.themeName !== "omarchy" ? root.configDir + "/themes/" + root.themeName + ".json" : ""
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.themeData = root.parse(text(), null)
    onLoadFailed: root.themeData = null
    onPathChanged: if (path === "") root.themeData = null
  }
}
