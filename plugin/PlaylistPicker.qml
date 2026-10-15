import QtQuick
import "Model.js" as Model

// "Add to playlist" for one song: Favourites and your own playlists, ticked
// where the song already is (click to add or take out), and a box to start a
// new playlist with it. Without a keyboard (the desktop widget) the new
// playlist row asks the host to open the app instead.
Rectangle {
  id: root

  required property var store
  property var jobs: null
  property string videoId: ""
  property string songTitle: ""
  property bool canType: true
  property color background: "#202020"
  property color foreground: "#ffffff"
  property color muted: "#999999"
  property color accent: "#ffffff"
  property string fontFamily: "monospace"
  property real s: 1
  // Tallest the picker may be; the list scrolls past it.
  property real maxHeight: 420 * s

  // playlist id -> wanted state while its command runs.
  property var pending: ({})
  // The new-playlist box has the keyboard (the bar panel stops its keys).
  readonly property bool typing: nameInput.activeFocus
  readonly property real rowHeight: 34 * s
  readonly property real listRoom: Math.max(rowHeight * 2, maxHeight - head.height - newRow.height - 12 * s * 2 - 8 * s * 2)

  signal closed()
  signal newRequested()

  function entry(id) {
    for (var i = 0; i < store.mine.length; i++) if (store.mine[i].id === id) return store.mine[i]
    return null
  }
  function inList(item) { return Model.shown(pending, item.id, Model.contains(item, videoId)) }

  function toggle(item) {
    if (!videoId || !jobs) return
    var id = item.id
    var on = !inList(item)
    var next = Object.assign({}, pending)
    next[id] = on
    pending = next
    jobs.run(Model.playlistSongArgs(id, videoId, on), "", function(ok) {
      if (ok) return
      var back = Object.assign({}, root.pending)
      delete back[id]
      root.pending = back
    })
  }

  function create(name) {
    name = String(name || "").trim()
    if (!name || !jobs) return
    jobs.run(Model.newPlaylistArgs(name, videoId), "")
    nameInput.text = ""
  }

  Connections {
    target: root.store
    function onMineChanged() {
      root.pending = Model.settle(root.pending, function(id) { return Model.contains(root.entry(id), root.videoId) })
    }
  }
  onVideoIdChanged: pending = ({})
  onVisibleChanged: if (visible && canType) nameInput.text = ""

  width: 290 * s
  height: column.implicitHeight + 24 * s
  radius: 22 * s
  color: background
  border.width: 1
  border.color: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.12)

  // Keep clicks inside from reaching whatever is underneath.
  MouseArea {
    anchors.fill: parent
    acceptedButtons: Qt.AllButtons
    onWheel: function(e) { e.accepted = true }
  }

  Column {
    id: column
    x: 12 * root.s
    y: 12 * root.s
    width: parent.width - 24 * root.s
    spacing: 8 * root.s

    Item {
      id: head
      width: parent.width
      height: Math.max(headText.implicitHeight, closeButton.height)

      Column {
        id: headText
        anchors.left: parent.left
        anchors.right: closeButton.left
        anchors.rightMargin: 6 * root.s
        anchors.verticalCenter: parent.verticalCenter
        spacing: 1
        Text {
          width: parent.width
          textFormat: Text.PlainText
          text: "Add to playlist"
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: 13 * root.s
          font.bold: true
        }
        Text {
          width: parent.width
          visible: text !== ""
          textFormat: Text.PlainText
          text: root.songTitle
          color: root.muted
          font.family: root.fontFamily
          font.pixelSize: 11 * root.s
          elide: Text.ElideRight
        }
      }
      GlyphButton {
        id: closeButton
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        glyph: Model.GLYPH_CLOSE
        size: 26 * root.s
        color: root.muted
        fontFamily: root.fontFamily
        onClicked: root.closed()
      }
    }

    // New playlist: a name box, or (no keyboard) a row that asks the app.
    Rectangle {
      id: newRow
      width: parent.width
      height: root.rowHeight
      radius: 8 * root.s
      color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b,
        nameInput.activeFocus ? 0.10 : newMouse.containsMouse ? 0.09 : 0.05)
      border.width: nameInput.activeFocus ? 1 : 0
      border.color: root.accent

      Text {
        id: newGlyph
        x: 10 * root.s
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: Model.GLYPH_ADD
        color: root.accent
        font.family: root.fontFamily
        font.pixelSize: 15 * root.s
      }
      TextInput {
        id: nameInput
        visible: root.canType
        anchors.left: newGlyph.right
        anchors.leftMargin: 8 * root.s
        anchors.right: createButton.left
        anchors.rightMargin: 4 * root.s
        anchors.verticalCenter: parent.verticalCenter
        color: root.foreground
        selectionColor: root.accent
        font.family: root.fontFamily
        font.pixelSize: 12 * root.s
        clip: true
        onAccepted: root.create(text)
        Keys.onEscapePressed: root.closed()

        Text {
          anchors.fill: parent
          visible: !nameInput.text
          textFormat: Text.PlainText
          text: "New playlist"
          color: root.muted
          font: nameInput.font
          verticalAlignment: Text.AlignVCenter
        }
      }
      Text {
        visible: !root.canType
        anchors.left: newGlyph.right
        anchors.leftMargin: 8 * root.s
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: "New playlist…"
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: 12 * root.s
      }
      GlyphButton {
        id: createButton
        anchors.right: parent.right
        anchors.rightMargin: 4 * root.s
        anchors.verticalCenter: parent.verticalCenter
        visible: root.canType && nameInput.text.trim() !== ""
        glyph: Model.GLYPH_CHECK
        size: 26 * root.s
        color: root.accent
        fontFamily: root.fontFamily
        tooltip: "Make it"
        onClicked: root.create(nameInput.text)
      }
      MouseArea {
        id: newMouse
        anchors.fill: parent
        z: -1
        hoverEnabled: true
        cursorShape: root.canType ? Qt.IBeamCursor : Qt.PointingHandCursor
        onClicked: root.canType ? nameInput.forceActiveFocus() : root.newRequested()
      }
    }

    ListView {
      id: list
      width: parent.width
      height: Math.min(contentHeight, root.listRoom)
      clip: true
      interactive: contentHeight > height
      boundsBehavior: Flickable.StopAtBounds
      model: root.store.mine

      delegate: Rectangle {
        id: row
        required property var modelData
        readonly property bool builtin: Model.isBuiltin(modelData.id)
        readonly property bool ticked: root.inList(modelData)
        width: list.width
        height: root.rowHeight
        radius: 8 * root.s
        color: rowMouse.containsMouse ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.08) : "transparent"

        Text {
          id: rowGlyph
          x: 10 * root.s
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          text: Model.ownGlyph(row.modelData.id)
          color: row.builtin ? root.accent : root.muted
          font.family: root.fontFamily
          font.pixelSize: 15 * root.s
        }
        Text {
          anchors.left: rowGlyph.right
          anchors.leftMargin: 8 * root.s
          anchors.right: countText.left
          anchors.rightMargin: 8 * root.s
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          text: row.modelData.title
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: 12 * root.s
          elide: Text.ElideRight
        }
        Text {
          id: countText
          anchors.right: tick.left
          anchors.rightMargin: 8 * root.s
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          text: row.modelData.count || ""
          color: root.muted
          font.family: root.fontFamily
          font.pixelSize: 11 * root.s
        }
        Text {
          id: tick
          anchors.right: parent.right
          anchors.rightMargin: 10 * root.s
          anchors.verticalCenter: parent.verticalCenter
          width: 16 * root.s
          horizontalAlignment: Text.AlignHCenter
          textFormat: Text.PlainText
          text: row.ticked ? Model.GLYPH_CHECK : rowMouse.containsMouse ? Model.GLYPH_ADD : ""
          color: row.ticked ? root.accent : root.muted
          font.family: root.fontFamily
          font.pixelSize: 15 * root.s
        }
        MouseArea {
          id: rowMouse
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: root.toggle(row.modelData)
        }
      }
    }
  }
}
