import QtQuick
import "Model.js" as Model

// Heart (Favourites), save (Saved songs: your library) and add-to-playlist
// buttons for one song. The heart and save flip at once and settle when
// shelf.json catches up.
Row {
  id: root

  required property var store
  property var jobs: null
  property string videoId: ""
  property color color: "#ffffff"
  property color accent: "#ffffff"
  property real size: 30
  property string fontFamily: "monospace"
  property bool showHeart: true
  property bool showSave: false
  property bool showAdd: true

  // id -> wanted state while `paattu fav` / `paattu save` runs.
  property var pending: ({})
  property var savePending: ({})
  readonly property bool favourite: Model.shown(pending, videoId, !!store.favourites[videoId])
  readonly property bool saved: Model.shown(savePending, videoId, !!store.saved[videoId])
  // Something to show even when not hovered.
  readonly property bool marked: favourite || (showSave && saved)

  // anchor: the add button, for placing a picker next to it.
  signal pick(Item anchor)

  spacing: 0
  visible: videoId !== ""

  // which: "pending" (Favourites) or "savePending" (Saved songs).
  function toggle(which, on, args) {
    if (!videoId || !jobs) return
    var id = videoId
    var next = Object.assign({}, root[which])
    next[id] = on
    root[which] = next
    settleTimer.restart()
    jobs.run(args, "", function(ok) {
      if (ok) return
      var back = Object.assign({}, root[which])
      delete back[id]
      root[which] = back
    })
  }
  function toggleFavourite() { toggle("pending", !favourite, Model.favouriteArgs(videoId, !favourite)) }
  function toggleSaved() { toggle("savePending", !saved, Model.saveArgs(videoId, !saved)) }

  Connections {
    target: root.store
    function onFavouritesChanged() {
      root.pending = Model.settle(root.pending, function(id) { return !!root.store.favourites[id] })
    }
    function onSavedChanged() {
      root.savePending = Model.settle(root.savePending, function(id) { return !!root.store.saved[id] })
    }
  }
  // In case the file never changes (a command that failed quietly).
  Timer {
    id: settleTimer
    interval: 15000
    onTriggered: {
      root.pending = ({})
      root.savePending = ({})
    }
  }

  GlyphButton {
    anchors.verticalCenter: parent.verticalCenter
    visible: root.showHeart
    glyph: root.favourite ? Model.GLYPH_HEART : Model.GLYPH_HEART_OUTLINE
    size: root.size
    color: root.favourite ? root.accent : root.color
    fontFamily: root.fontFamily
    tooltip: root.favourite ? "Remove from Favourites" : "Add to Favourites"
    onClicked: root.toggleFavourite()
  }
  GlyphButton {
    anchors.verticalCenter: parent.verticalCenter
    visible: root.showSave
    glyph: root.saved ? Model.GLYPH_SAVED : Model.GLYPH_SAVE
    size: root.size
    color: root.saved ? root.accent : root.color
    fontFamily: root.fontFamily
    tooltip: root.saved ? "Remove from Saved songs" : "Save to your library"
    onClicked: root.toggleSaved()
  }
  GlyphButton {
    id: addButton
    anchors.verticalCenter: parent.verticalCenter
    visible: root.showAdd
    glyph: Model.GLYPH_PLAYLIST_ADD
    size: root.size
    color: root.color
    fontFamily: root.fontFamily
    tooltip: "Add to playlist"
    onClicked: root.pick(addButton)
  }
}
