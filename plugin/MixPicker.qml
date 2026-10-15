import QtQuick
import "Model.js" as Model

// "Add to mix" for a language, a profile or a playlist: the mixes, ticked
// where it's already in (click to add or take out), and a box to start a new
// mix with it.
Rectangle {
  id: root

  required property var app
  // {type: language | user | playlist, id, title}
  property var source: ({ type: "", id: "", title: "" })
  property real maxHeight: 420
  readonly property var pal: app.pal
  readonly property var mixes: app.store.mixes

  // mix id -> wanted state while its command runs.
  property var pending: ({})
  readonly property real rowHeight: 34
  readonly property real listRoom: Math.max(rowHeight * 2, maxHeight - head.height - newRow.height - 24 - 16)

  signal closed()

  function mixOf(id) {
    for (var i = 0; i < mixes.length; i++) if (mixes[i].id === id) return mixes[i]
    return null
  }
  function inMix(mix) { return Model.shown(pending, mix.id, Model.mixHas(mix, source)) }

  function toggle(mix) {
    var id = mix.id
    var on = !inMix(mix)
    var next = Object.assign({}, pending)
    next[id] = on
    pending = next
    app.changeMix(id, source, on, function(ok) {
      if (ok) return
      var back = Object.assign({}, root.pending)
      delete back[id]
      root.pending = back
    })
  }

  function create(name) {
    name = String(name || "").trim()
    if (!name) return
    app.newMix(name, source, false)
    nameInput.text = ""
  }

  Connections {
    target: root.app.store
    function onMixesChanged() {
      root.pending = Model.settle(root.pending, function(id) { return Model.mixHas(root.mixOf(id), root.source) })
    }
  }
  onSourceChanged: pending = ({})
  onVisibleChanged: if (visible) nameInput.text = ""

  width: 300
  height: column.implicitHeight + 24
  radius: 22
  color: Qt.tint(pal.surface, Qt.rgba(pal.foreground.r, pal.foreground.g, pal.foreground.b, 0.03))
  border.width: 1
  border.color: Qt.rgba(pal.foreground.r, pal.foreground.g, pal.foreground.b, 0.12)

  // Keep clicks inside from reaching whatever is underneath.
  MouseArea {
    anchors.fill: parent
    acceptedButtons: Qt.AllButtons
    onWheel: function(e) { e.accepted = true }
  }

  Column {
    id: column
    x: 12
    y: 12
    width: parent.width - 24
    spacing: 8

    Item {
      id: head
      width: parent.width
      height: Math.max(headText.implicitHeight, closeButton.height)

      Column {
        id: headText
        anchors.left: parent.left
        anchors.right: closeButton.left
        anchors.rightMargin: 6
        anchors.verticalCenter: parent.verticalCenter
        spacing: 1
        Text {
          width: parent.width
          textFormat: Text.PlainText
          text: "Add to mix"
          color: root.pal.foreground
          font.family: root.app.fontFamily
          font.pixelSize: 13
          font.bold: true
        }
        Text {
          width: parent.width
          visible: text !== ""
          textFormat: Text.PlainText
          text: root.source.title || ""
          color: root.pal.muted
          font.family: root.app.fontFamily
          font.pixelSize: 11
          elide: Text.ElideRight
        }
      }
      GlyphButton {
        id: closeButton
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        glyph: Model.GLYPH_CLOSE
        size: 26
        color: root.pal.muted
        fontFamily: root.app.fontFamily
        onClicked: root.closed()
      }
    }

    Rectangle {
      id: newRow
      width: parent.width
      height: root.rowHeight
      radius: 8
      color: Qt.rgba(root.pal.foreground.r, root.pal.foreground.g, root.pal.foreground.b, nameInput.activeFocus ? 0.10 : 0.05)
      border.width: nameInput.activeFocus ? 1 : 0
      border.color: root.pal.accent

      Text {
        id: newGlyph
        x: 10
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: Model.GLYPH_ADD
        color: root.pal.accent
        font.family: root.app.fontFamily
        font.pixelSize: 15
      }
      TextInput {
        id: nameInput
        anchors.left: newGlyph.right
        anchors.leftMargin: 8
        anchors.right: createButton.left
        anchors.rightMargin: 4
        anchors.verticalCenter: parent.verticalCenter
        color: root.pal.foreground
        selectionColor: root.pal.accent
        font.family: root.app.fontFamily
        font.pixelSize: 12
        clip: true
        onAccepted: root.create(text)
        Keys.onEscapePressed: root.closed()

        Text {
          anchors.fill: parent
          visible: !nameInput.text
          textFormat: Text.PlainText
          text: "New mix"
          color: root.pal.muted
          font: nameInput.font
          verticalAlignment: Text.AlignVCenter
        }
      }
      GlyphButton {
        id: createButton
        anchors.right: parent.right
        anchors.rightMargin: 4
        anchors.verticalCenter: parent.verticalCenter
        visible: nameInput.text.trim() !== ""
        glyph: Model.GLYPH_CHECK
        size: 26
        color: root.pal.accent
        fontFamily: root.app.fontFamily
        tooltip: "Make it"
        onClicked: root.create(nameInput.text)
      }
      MouseArea {
        anchors.fill: parent
        z: -1
        cursorShape: Qt.IBeamCursor
        onClicked: nameInput.forceActiveFocus()
      }
    }

    ListView {
      id: list
      width: parent.width
      height: Math.min(contentHeight, root.listRoom)
      clip: true
      interactive: contentHeight > height
      boundsBehavior: Flickable.StopAtBounds
      model: root.mixes

      delegate: Rectangle {
        id: row
        required property var modelData
        readonly property bool ticked: root.inMix(modelData)
        width: list.width
        height: root.rowHeight
        radius: 8
        color: rowMouse.containsMouse ? Qt.rgba(root.pal.foreground.r, root.pal.foreground.g, root.pal.foreground.b, 0.08) : "transparent"

        Text {
          id: rowGlyph
          x: 10
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          text: Model.GLYPH_SHUFFLE
          color: row.ticked ? root.pal.accent : root.pal.muted
          font.family: root.app.fontFamily
          font.pixelSize: 15
        }
        Text {
          anchors.left: rowGlyph.right
          anchors.leftMargin: 8
          anchors.right: tick.left
          anchors.rightMargin: 8
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          text: row.modelData.title
          color: root.pal.foreground
          font.family: root.app.fontFamily
          font.pixelSize: 12
          elide: Text.ElideRight
        }
        Text {
          id: tick
          anchors.right: parent.right
          anchors.rightMargin: 10
          anchors.verticalCenter: parent.verticalCenter
          width: 16
          horizontalAlignment: Text.AlignHCenter
          textFormat: Text.PlainText
          text: row.ticked ? Model.GLYPH_CHECK : rowMouse.containsMouse ? Model.GLYPH_ADD : ""
          color: row.ticked ? root.pal.accent : root.pal.muted
          font.family: root.app.fontFamily
          font.pixelSize: 15
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
