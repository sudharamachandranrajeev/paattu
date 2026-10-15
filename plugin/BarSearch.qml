import QtQuick
import qs.Commons
import qs.Ui
import "Model.js" as Model

// The bar panel's search: a box (/ to get to it, Enter to search JioSaavn,
// YouTube and SoundCloud, or paste a link to a song on any site), then the
// results. Click one to play it; its buttons heart it, save it to your
// library, add it to a playlist or play it next.
Column {
  id: root

  required property var widget

  readonly property var player: widget.player
  readonly property var store: widget.store
  readonly property color fg: widget.fg
  readonly property color dim: Qt.darker(fg, 1.45)
  readonly property string fontFamily: widget.fontFamily
  readonly property var online: widget.online
  readonly property bool showing: online.query !== ""
  readonly property var groups: Model.searchGroups(online.results)
  // A few from a link and a few found; more when there's only one list.
  readonly property int perGroup: groups.length > 1 ? 4 : 10
  readonly property int shownCount: groups.reduce(function(n, g) { return n + Math.min(g.tracks.length, perGroup) }, 0)
  readonly property var errors: Model.searchErrors(online.errors)

  // The song whose add-to-playlist picker is open, and whether its
  // new-playlist box has the keyboard.
  property string pickId: ""
  property bool pickTyping: false
  readonly property bool typing: field.activeFocus || pickTyping

  function focusField() {
    field.forceActiveFocus()
    field.selectAll()
  }
  function clear() {
    field.text = ""
    pickId = ""
    widget.clearSearch()
  }

  onVisibleChanged: if (!visible) pickId = ""
  onOnlineChanged: pickId = ""

  spacing: Style.space(6)

  TextField {
    id: field
    width: parent.width
    foreground: root.fg
    accent: Color.accent
    font.family: root.fontFamily
    font.pixelSize: Style.font.bodySmall
    leftPadding: Style.space(30)
    rightPadding: clearButton.visible ? Style.space(32) : horizontalPadding
    placeholderText: activeFocus ? "A song, film or singer, or a link" : "Search for songs   /"
    onAccepted: root.widget.searchOnline(text)
    // Esc: clear the search, then give the keys back to the panel.
    Keys.onEscapePressed: function(e) {
      if (text !== "" || root.showing) root.clear()
      else root.widget.focusKeys()
      e.accepted = true
    }

    Text {
      x: Style.space(10)
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      text: Model.isLink(field.text.trim()) ? Model.GLYPH_LINK : Model.GLYPH_SEARCH
      color: field.activeFocus ? Color.accent : root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
    }

    GlyphButton {
      id: clearButton
      anchors.right: parent.right
      anchors.rightMargin: Style.space(4)
      anchors.verticalCenter: parent.verticalCenter
      visible: field.text !== "" || root.showing
      glyph: Model.GLYPH_CLOSE
      size: Style.space(24)
      color: root.dim
      fontFamily: root.fontFamily
      tooltip: "Clear the search"
      onClicked: root.clear()
    }
  }

  // ---------- results ----------
  Column {
    width: parent.width
    spacing: Style.space(4)
    visible: root.showing

    Text {
      width: parent.width
      visible: text !== ""
      textFormat: Text.PlainText
      wrapMode: Text.WordWrap
      text: root.online.busy
        ? (Model.isLink(root.online.query) ? "Looking up the link…" : "Searching…")
        : root.online.error ? root.online.error
        : [root.online.results.length === 0 ? "Nothing found for “" + root.online.query + "”" : ""]
            .concat(root.errors).filter(function(x) { return x }).join("  ·  ")
      color: !root.online.busy && (root.online.error || root.errors.length) && root.online.results.length === 0 ? Color.urgent : root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }

    Repeater {
      model: root.groups

      Column {
        id: group
        required property var modelData
        width: root.width
        spacing: Style.space(2)

        PanelSectionHeader {
          visible: root.groups.length > 1 || group.modelData.site === "link"
          text: group.modelData.title.toUpperCase()
          foreground: root.fg
          fontFamily: root.fontFamily
        }

        Repeater {
          model: group.modelData.tracks.slice(0, root.perGroup)

          Column {
            id: result
            required property var modelData
            readonly property bool current: root.player.videoId === modelData.id
            readonly property bool picking: root.pickId === modelData.id
            width: root.width

            Rectangle {
              width: parent.width
              height: Style.space(44)
              radius: Style.space(8)
              color: rowHover.hovered || result.picking ? Style.hoverFillFor(root.fg, Color.accent) : "transparent"

              HoverHandler { id: rowHover }
              // Under the buttons, so they get their own clicks.
              MouseArea {
                anchors.fill: parent
                z: -1
                cursorShape: Qt.PointingHandCursor
                onClicked: root.widget.playSong(result.modelData)
              }

              Cover {
                id: cover
                x: Style.space(4)
                anchors.verticalCenter: parent.verticalCenter
                width: Style.space(34)
                height: width
                radius: Style.space(6)
                source: root.store.artFor("v", result.modelData.id)
                tint: Style.normalFillFor(root.fg, Color.accent)
                glyphColor: root.fg
                glyph: Model.GLYPH_NOTE
                fontFamily: root.fontFamily
              }

              Column {
                anchors.left: cover.right
                anchors.leftMargin: Style.space(10)
                anchors.right: actions.visible ? actions.left : parent.right
                anchors.rightMargin: Style.space(6)
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(1)

                Text {
                  width: parent.width
                  textFormat: Text.PlainText
                  text: result.modelData.title || result.modelData.rawTitle || "…"
                  color: result.current ? Color.accent : root.fg
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  elide: Text.ElideRight
                }
                Text {
                  width: parent.width
                  textFormat: Text.PlainText
                  text: [Model.subtitle(result.modelData) || result.modelData.channel || "", Model.qualityLabel(result.modelData)]
                    .filter(function(x) { return x }).join(" · ")
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  elide: Text.ElideRight
                }
              }

              Row {
                id: actions
                anchors.right: parent.right
                anchors.rightMargin: Style.space(2)
                anchors.verticalCenter: parent.verticalCenter
                visible: rowHover.hovered || result.picking || songActions.marked

                SongActions {
                  id: songActions
                  anchors.verticalCenter: parent.verticalCenter
                  store: root.store
                  jobs: root.widget.jobs
                  videoId: result.modelData.id
                  showSave: true
                  color: root.dim
                  accent: Color.accent
                  size: Style.space(26)
                  fontFamily: root.fontFamily
                  onPick: root.pickId = result.picking ? "" : result.modelData.id
                }
                GlyphButton {
                  anchors.verticalCenter: parent.verticalCenter
                  visible: rowHover.hovered
                  glyph: Model.GLYPH_PLAY_NEXT
                  size: Style.space(26)
                  color: root.dim
                  fontFamily: root.fontFamily
                  tooltip: "Play next"
                  onClicked: root.widget.queueSong(result.modelData, true)
                }
              }
            }

            Loader {
              width: parent.width
              active: result.picking
              visible: active
              sourceComponent: PlaylistPicker {
                width: result.width
                store: root.store
                jobs: root.widget.jobs
                videoId: result.modelData.id
                songTitle: result.modelData.title || ""
                canType: true
                background: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.05)
                foreground: root.fg
                muted: root.dim
                accent: Color.accent
                fontFamily: root.fontFamily
                maxHeight: Style.space(260)
                onClosed: root.pickId = ""
                onTypingChanged: root.pickTyping = typing
                Component.onDestruction: root.pickTyping = false
              }
            }
          }
        }
      }
    }

    Chip {
      visible: !root.online.busy && root.online.results.length > 0
      text: root.shownCount < root.online.results.length
        ? "All " + root.online.results.length + " in Paattu" : "Open in Paattu"
      glyph: Model.GLYPH_LIBRARY
      textColor: root.fg
      accent: Color.accent
      fontSize: Style.font.caption
      fontFamily: root.fontFamily
      onClicked: root.widget.searchInApp(root.online.query)
    }
  }
}
