import QtQuick
import QtQuick.Controls
import "Model.js" as Model

// One mix: what's in it (click a source to take it out) and everything that
// could go in: languages, YouTube profiles, your playlists, saved playlists.
Flickable {
  id: root

  required property var app
  property string mixId: ""

  readonly property var pal: app.pal
  readonly property var mix: {
    var mixes = app.store.mixes
    for (var i = 0; i < mixes.length; i++) if (mixes[i].id === mixId) return mixes[i]
    return null
  }
  readonly property int position: mix ? app.store.mixes.indexOf(mix) + 1 : 0
  property bool renaming: false
  property string query: ""
  // source key -> wanted state while its command runs.
  property var pending: ({})
  readonly property var candidates: Model.mixCandidates(app.store.lib, app.store.shelf, app.store.languages, query)
  readonly property int playlistLimit: 60
  readonly property var sources: mix ? mix.sources.filter(function(s) { return root.inMix(s) }) : []

  onMixIdChanged: {
    pending = ({})
    renaming = false
    query = ""
    filterBox.text = ""
  }

  function inMix(source) { return Model.shown(pending, Model.sourceKey(source), Model.mixHas(mix, source)) }

  function toggle(source) {
    if (!mix) return
    var key = Model.sourceKey(source)
    var on = !inMix(source)
    var next = Object.assign({}, pending)
    next[key] = on
    pending = next
    root.app.changeMix(mixId, source, on, function(ok) {
      if (ok) return
      var back = Object.assign({}, root.pending)
      delete back[key]
      root.pending = back
    })
  }

  function rename(name) {
    name = String(name || "").trim()
    renaming = false
    if (name && mix && name !== mix.title) app.renameMix(mixId, name)
  }

  Connections {
    target: root.app.store
    function onMixesChanged() {
      root.pending = Model.settle(root.pending, function(key) {
        var at = key.indexOf(":")
        return Model.mixHas(root.mix, { type: key.slice(0, at), id: key.slice(at + 1) })
      })
    }
  }

  contentWidth: width
  contentHeight: column.implicitHeight + 40
  clip: true
  boundsBehavior: Flickable.StopAtBounds
  ScrollBar.vertical: ScrollBar {}

  Column {
    id: column
    x: 28
    y: 4
    width: root.width - 56
    spacing: 26

    // ---------- header ----------
    Row {
      width: parent.width
      spacing: 24
      visible: !!root.mix

      Rectangle {
        width: 180
        height: 180
        radius: 12
        color: root.pal.accent
        Text {
          anchors.centerIn: parent
          textFormat: Text.PlainText
          text: Model.GLYPH_SHUFFLE
          color: root.pal.accentText
          opacity: 0.85
          font.family: root.app.fontFamily
          font.pixelSize: 76
        }
      }

      Column {
        anchors.bottom: parent.bottom
        width: parent.width - 204
        spacing: 8

        Text {
          textFormat: Text.PlainText
          text: "MIX  ·  BUTTON " + root.position
          color: root.pal.accent
          font.family: root.app.fontFamily
          font.pixelSize: 11
          font.letterSpacing: 1.4
        }
        Text {
          width: parent.width
          visible: !root.renaming
          textFormat: Text.PlainText
          text: root.mix ? root.mix.title : ""
          color: root.pal.foreground
          font.family: root.app.fontFamily
          font.pixelSize: 32
          font.weight: Font.Black
          wrapMode: Text.WordWrap
          maximumLineCount: 2
          elide: Text.ElideRight
        }
        TextInput {
          id: renameInput
          width: parent.width
          visible: root.renaming
          color: root.pal.foreground
          selectionColor: root.pal.accent
          font.family: root.app.fontFamily
          font.pixelSize: 32
          font.weight: Font.Black
          clip: true
          onAccepted: root.rename(text)
          onActiveFocusChanged: if (!activeFocus && root.renaming) root.rename(text)
          Keys.onEscapePressed: root.renaming = false
          Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.bottom
            height: 2
            color: root.pal.accent
          }
        }
        Text {
          width: parent.width
          textFormat: Text.PlainText
          text: !root.mix ? "" : root.mix.sources.length === 0 ? "Empty: add something below"
            : !root.mix.playlists ? "No saved playlists in it yet: add a profile or playlist from YouTube, or pick more below"
            : [Model.plural(root.mix.playlists || 0, "playlist"), Model.plural(root.mix.count || 0, "song"),
               root.mix.waiting ? root.mix.waiting + " not loaded yet" : ""].filter(function(x) { return x }).join("  ·  ")
          color: root.pal.muted
          font.family: root.app.fontFamily
          font.pixelSize: 12
          elide: Text.ElideRight
        }

        Row {
          spacing: 8
          topPadding: 6
          GlyphButton {
            glyph: Model.GLYPH_SHUFFLE
            size: 48
            color: root.pal.accentText
            fill: root.pal.accent
            fontFamily: root.app.fontFamily
            enabled: root.sources.length > 0 && !!root.mix && root.mix.playlists > 0
            tooltip: "Shuffle " + (root.mix ? root.mix.title : "")
            onClicked: root.app.playMix(root.mixId, root.mix.title)
          }
          Chip {
            anchors.verticalCenter: parent.verticalCenter
            text: "Rename"
            glyph: Model.GLYPH_EDIT
            textColor: root.pal.foreground
            accent: root.pal.accent
            fontSize: 12
            fontFamily: root.app.fontFamily
            onClicked: {
              renameInput.text = root.mix.title
              root.renaming = true
              renameInput.forceActiveFocus()
              renameInput.selectAll()
            }
          }
          Chip {
            anchors.verticalCenter: parent.verticalCenter
            visible: !!root.mix && root.mix.waiting > 0
            text: "Load songs for " + Model.plural(root.mix ? root.mix.waiting : 0, "playlist")
            glyph: Model.GLYPH_DOWNLOAD
            textColor: root.pal.foreground
            accent: root.pal.accent
            fontSize: 12
            fontFamily: root.app.fontFamily
            onClicked: root.app.fetchMix(root.mixId)
          }
          RemoveButton {
            anchors.verticalCenter: parent.verticalCenter
            label: "Delete mix"
            confirmLabel: "Click again to delete"
            textColor: root.pal.foreground
            fontSize: 12
            fontFamily: root.app.fontFamily
            onConfirmed: root.app.removeMix(root.mixId)
          }
        }
      }
    }

    Column {
      visible: !root.mix
      spacing: 12
      Text {
        textFormat: Text.PlainText
        text: "This mix is gone."
        color: root.pal.muted
        font.family: root.app.fontFamily
        font.pixelSize: 14
      }
      Chip {
        text: "All mixes"
        glyph: Model.GLYPH_SHUFFLE
        textColor: root.pal.foreground
        accent: root.pal.accent
        fontSize: 12
        fontFamily: root.app.fontFamily
        onClicked: root.app.navigate("mixes")
      }
    }

    // ---------- in this mix ----------
    Column {
      width: parent.width
      spacing: 10
      visible: !!root.mix

      Text {
        textFormat: Text.PlainText
        text: "In this mix"
        color: root.pal.foreground
        font.family: root.app.fontFamily
        font.pixelSize: 19
        font.bold: true
      }
      Text {
        width: parent.width
        textFormat: Text.PlainText
        wrapMode: Text.WordWrap
        text: root.sources.length
          ? "A language or a profile brings in all its saved playlists, including ones saved later. Click one to take it out."
          : "Nothing yet. Pick languages, profiles or playlists below."
        color: root.pal.muted
        font.family: root.app.fontFamily
        font.pixelSize: 12
      }
      Flow {
        width: parent.width
        spacing: 8
        Repeater {
          model: root.sources
          Chip {
            required property var modelData
            text: modelData.title || modelData.id
            glyph: hovered ? Model.GLYPH_CLOSE : Model.sourceGlyph(modelData)
            textColor: root.pal.foreground
            accent: root.pal.accent
            selected: true
            fontSize: 13
            fontFamily: root.app.fontFamily
            onClicked: root.toggle(modelData)
          }
        }
      }
    }

    // ---------- add ----------
    Column {
      width: parent.width
      spacing: 14
      visible: !!root.mix

      Row {
        spacing: 16
        Text {
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          text: "Add to this mix"
          color: root.pal.foreground
          font.family: root.app.fontFamily
          font.pixelSize: 19
          font.bold: true
        }
        InputBox {
          id: filterBox
          anchors.verticalCenter: parent.verticalCenter
          width: 260
          height: 32
          app: root.app
          glyph: Model.GLYPH_SEARCH
          placeholder: "Find a profile or playlist"
          onTextChanged: root.query = text
        }
      }

      Repeater {
        model: [
          { key: "languages", label: "LANGUAGES" },
          { key: "users", label: "YOUTUBE PROFILES" },
          { key: "mine", label: "YOUR PLAYLISTS" },
          { key: "playlists", label: "SAVED PLAYLISTS" }
        ]

        Column {
          id: group
          required property var modelData
          readonly property var all: root.candidates[modelData.key]
          readonly property var items: modelData.key === "playlists" && !root.query ? all.slice(0, root.playlistLimit) : all
          width: column.width
          spacing: 8
          visible: all.length > 0

          Text {
            textFormat: Text.PlainText
            text: group.modelData.label
            color: root.pal.muted
            font.family: root.app.fontFamily
            font.pixelSize: 11
            font.letterSpacing: 1.4
          }
          Flow {
            width: parent.width
            spacing: 8
            Repeater {
              model: group.items
              Chip {
                required property var modelData
                readonly property bool picked: root.inMix(modelData)
                text: modelData.title + (modelData.owner ? "  ·  " + modelData.owner : "")
                glyph: picked ? Model.GLYPH_CHECK : Model.GLYPH_ADD
                textColor: root.pal.foreground
                accent: root.pal.accent
                selected: picked
                fontSize: 12
                fontFamily: root.app.fontFamily
                onClicked: root.toggle(modelData)
              }
            }
          }
          Text {
            visible: group.items.length < group.all.length
            textFormat: Text.PlainText
            text: (group.all.length - group.items.length) + " more: type above to find them"
            color: root.pal.muted
            font.family: root.app.fontFamily
            font.pixelSize: 11
          }
        }
      }

      Text {
        visible: !!root.query && root.candidates.languages.length + root.candidates.users.length
          + root.candidates.mine.length + root.candidates.playlists.length === 0
        textFormat: Text.PlainText
        text: "Nothing called \"" + root.query + "\" in your library"
        color: root.pal.muted
        font.family: root.app.fontFamily
        font.pixelSize: 12
      }
    }
  }
}
