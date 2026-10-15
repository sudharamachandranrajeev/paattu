import QtQuick
import QtQuick.Controls
import "Model.js" as Model

// YouTube users: paste a profile link (a label, a composer, a friend) and all
// of its public playlists are added; or paste one playlist link. Followed
// profiles list here with their playlists to play, remove or bring back.
Item {
  id: root

  required property var app
  property string userId: ""

  readonly property var pal: app.pal
  readonly property var lib: app.store.lib
  // Grouped by language (the list's sections), biggest first within each.
  readonly property var users: Model.usersByLanguage(lib, "").sort(function(a, b) {
    return (a.language || "~").localeCompare(b.language || "~") || (b.followers || 0) - (a.followers || 0)
  })
  readonly property var user: userId ? lib.users[userId] || null : null
  readonly property var playlists: user ? Model.userPlaylists(lib, userId) : []
  readonly property var stats: Model.userStats(lib, userId)
  property string newLanguage: ""

  function takeFocusRequest() {
    if (!root.app.focusAdd) return
    root.app.focusAdd = false
    linkInput.focusInput()
  }
  Component.onCompleted: takeFocusRequest()
  Connections {
    target: root.app
    function onFocusAddChanged() { root.takeFocusRequest() }
  }

  // ---------- left: follow form + users ----------
  Glass {
    id: left
    pal: root.pal
    width: 300
    anchors.top: parent.top
    anchors.bottom: parent.bottom
    anchors.left: parent.left
    anchors.leftMargin: 20
    anchors.bottomMargin: 16
    radius: 28

    Column {
      id: form
      x: 16
      y: 16
      width: parent.width - 32
      spacing: 10

      Text {
        textFormat: Text.PlainText
        text: "Add from YouTube"
        color: root.pal.foreground
        font.family: root.app.fontFamily
        font.pixelSize: 15
        font.bold: true
      }
      Text {
        width: parent.width
        textFormat: Text.PlainText
        wrapMode: Text.WordWrap
        text: "Paste a profile link or @handle to add all of its public playlists, or a playlist link to add just that one."
        color: root.pal.muted
        font.family: root.app.fontFamily
        font.pixelSize: 11
      }

      InputBox {
        id: linkInput
        width: parent.width
        app: root.app
        glyph: Model.GLYPH_LINK
        placeholder: "youtube.com/@…  or a playlist link"
        onAccepted: addButton.clicked()
      }

      Flow {
        width: parent.width
        spacing: 6
        Repeater {
          model: [{ v: "", l: "Auto" }, { v: "Malayalam", l: "Malayalam" }, { v: "Tamil", l: "Tamil" }, { v: "Other", l: "Other" }]
          Chip {
            required property var modelData
            text: modelData.l
            textColor: root.pal.foreground
            accent: root.pal.accent
            selected: root.newLanguage === modelData.v
            fontSize: 11
            fontFamily: root.app.fontFamily
            onClicked: root.newLanguage = modelData.v
          }
        }
      }

      Chip {
        id: addButton
        text: root.app.jobs.busy ? "Working…" : "Add"
        glyph: Model.GLYPH_ADD
        textColor: root.pal.foreground
        accent: root.pal.accent
        selected: true
        fontSize: 12
        fontFamily: root.app.fontFamily
        opacity: linkInput.text.trim() ? 1 : 0.5
        onClicked: {
          if (!linkInput.text.trim()) return
          root.app.importLink(linkInput.text.trim(), root.newLanguage)
          linkInput.text = ""
        }
      }

      Text {
        width: parent.width
        visible: root.app.jobs.busy || root.app.jobs.lastError !== ""
        textFormat: Text.PlainText
        wrapMode: Text.WordWrap
        text: root.app.jobs.busy ? root.app.jobs.message : root.app.jobs.lastError
        color: root.app.jobs.busy ? root.pal.accent : "#e06c75"
        font.family: root.app.fontFamily
        font.pixelSize: 11
      }
    }

    ListView {
      anchors.top: form.bottom
      anchors.topMargin: 16
      anchors.bottom: parent.bottom
      anchors.bottomMargin: 8
      anchors.left: parent.left
      anchors.right: parent.right
      clip: true
      model: root.users
      spacing: 2
      ScrollBar.vertical: ScrollBar {}
      section.property: "language"
      section.delegate: Text {
        required property string section
        x: 16
        topPadding: 10
        bottomPadding: 4
        textFormat: Text.PlainText
        text: (section || "Other").toUpperCase()
        color: root.pal.muted
        font.family: root.app.fontFamily
        font.pixelSize: 10
        font.letterSpacing: 1.2
      }

      delegate: Rectangle {
        id: userRow
        required property var modelData
        readonly property bool selected: modelData.id === root.userId
        x: 8
        width: ListView.view.width - 16
        height: 48
        radius: 8
        color: selected ? Qt.rgba(root.pal.accent.r, root.pal.accent.g, root.pal.accent.b, 0.16)
          : rowMouse.containsMouse ? Qt.rgba(root.pal.foreground.r, root.pal.foreground.g, root.pal.foreground.b, 0.06) : "transparent"

        Cover {
          id: avatar
          x: 8
          anchors.verticalCenter: parent.verticalCenter
          width: 34
          height: 34
          circle: true
          crop: false
          source: root.app.store.artFor("u", userRow.modelData.id)
          revision: root.app.artRevision
          tint: Qt.rgba(root.pal.foreground.r, root.pal.foreground.g, root.pal.foreground.b, 0.08)
          glyphColor: root.pal.muted
          glyph: Model.GLYPH_USER
          fontFamily: root.app.fontFamily
        }
        Column {
          anchors.left: avatar.right
          anchors.leftMargin: 10
          anchors.right: parent.right
          anchors.rightMargin: 8
          anchors.verticalCenter: parent.verticalCenter
          Text {
            width: parent.width
            textFormat: Text.PlainText
            text: userRow.modelData.name
            color: userRow.selected ? root.pal.accent : root.pal.foreground
            font.family: root.app.fontFamily
            font.pixelSize: 12
            font.bold: userRow.selected
            elide: Text.ElideRight
          }
          Text {
            width: parent.width
            textFormat: Text.PlainText
            text: Model.plural(userRow.modelData.playlists.length, "playlist")
              + (userRow.modelData.followers ? " · " + Model.formatCount(userRow.modelData.followers) + " subscribers" : "")
            color: root.pal.muted
            font.family: root.app.fontFamily
            font.pixelSize: 10
            elide: Text.ElideRight
          }
        }
        MouseArea {
          id: rowMouse
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: root.app.openUser(userRow.modelData.id)
        }
      }
    }
  }

  // ---------- right: the selected user ----------
  Item {
    anchors.left: left.right
    anchors.leftMargin: 24
    anchors.right: parent.right
    anchors.rightMargin: 24
    anchors.top: parent.top
    anchors.bottom: parent.bottom

    Column {
      anchors.centerIn: parent
      visible: !root.user
      spacing: 8
      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        textFormat: Text.PlainText
        text: Model.GLYPH_USER
        color: root.pal.muted
        font.family: root.app.fontFamily
        font.pixelSize: 48
      }
      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        textFormat: Text.PlainText
        text: root.users.length ? "Pick a user to see their public playlists" : "Follow someone to get started"
        color: root.pal.muted
        font.family: root.app.fontFamily
        font.pixelSize: 13
      }
    }

    Row {
      id: header
      visible: !!root.user
      width: parent.width
      spacing: 18

      Cover {
        width: 96
        height: 96
        circle: true
        crop: false
        source: root.user ? root.app.store.artFor("u", root.user.id) : ""
        revision: root.app.artRevision
        tint: Qt.rgba(root.pal.foreground.r, root.pal.foreground.g, root.pal.foreground.b, 0.08)
        glyphColor: root.pal.muted
        glyph: Model.GLYPH_USER
        fontFamily: root.app.fontFamily
      }

      Column {
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width - 120
        spacing: 6
        Text {
          width: parent.width
          textFormat: Text.PlainText
          text: root.user ? root.user.name : ""
          color: root.pal.foreground
          font.family: root.app.fontFamily
          font.pixelSize: 26
          font.bold: true
          elide: Text.ElideRight
        }
        Text {
          width: parent.width
          elide: Text.ElideRight
          textFormat: Text.PlainText
          text: root.user ? [root.user.handle, root.user.language,
            root.user.followers ? Model.formatCount(root.user.followers) + " subscribers" : "",
            Model.plural(root.playlists.length, "public playlist")].filter(function(x) { return x }).join("  ·  ") : ""
          color: root.pal.muted
          font.family: root.app.fontFamily
          font.pixelSize: 12
        }
        Flow {
          width: parent.width
          spacing: 6
          topPadding: 4
          Chip {
            text: "Shuffle saved"
            glyph: Model.GLYPH_SHUFFLE
            textColor: root.pal.foreground; accent: root.pal.accent; selected: true
            fontSize: 11; fontFamily: root.app.fontFamily
            onClicked: root.app.playUser(root.userId)
          }
          Chip {
            id: userMixChip
            text: "Add to mix"
            glyph: Model.GLYPH_PLAYLIST_ADD
            textColor: root.pal.foreground; accent: root.pal.accent
            fontSize: 11; fontFamily: root.app.fontFamily
            onClicked: root.app.pickMixes({ type: "user", id: root.userId, title: root.user ? root.user.name : "" }, userMixChip)
          }
          Chip {
            visible: root.stats.unsaved > 0
            text: "Add the other " + Model.plural(root.stats.unsaved, "playlist")
            glyph: Model.GLYPH_ADD
            textColor: root.pal.foreground; accent: root.pal.accent
            fontSize: 11; fontFamily: root.app.fontFamily
            onClicked: root.app.saveAll(root.userId)
          }
          Chip {
            visible: root.stats.waiting > 0
            text: "Load songs for " + Model.plural(root.stats.waiting, "playlist")
            glyph: Model.GLYPH_DOWNLOAD
            textColor: root.pal.foreground; accent: root.pal.accent
            fontSize: 11; fontFamily: root.app.fontFamily
            onClicked: root.app.fetchUser(root.userId)
          }
          Chip {
            text: "Check for new playlists"
            glyph: Model.GLYPH_REFRESH
            textColor: root.pal.foreground; accent: root.pal.accent
            fontSize: 11; fontFamily: root.app.fontFamily
            onClicked: root.app.syncUser(root.userId)
          }
          Chip {
            visible: root.stats.removed > 0
            text: "Bring back " + Model.plural(root.stats.removed, "removed playlist")
            glyph: Model.GLYPH_RESTORE
            textColor: root.pal.foreground; accent: root.pal.accent
            fontSize: 11; fontFamily: root.app.fontFamily
            onClicked: root.app.restorePlaylists(root.userId)
          }
          RemoveButton {
            label: "Unfollow"
            confirmLabel: root.user && root.user.saveAll ? "Click again to unfollow and remove its playlists"
              : "Click again to unfollow (saved playlists stay)"
            textColor: root.pal.foreground
            fontSize: 11; fontFamily: root.app.fontFamily
            onConfirmed: root.app.removeUser(root.userId)
          }
        }
      }
    }

    ListView {
      id: list
      visible: !!root.user
      anchors.top: header.bottom
      anchors.topMargin: 20
      anchors.bottom: parent.bottom
      anchors.bottomMargin: 12
      width: parent.width
      clip: true
      spacing: 2
      model: root.playlists
      ScrollBar.vertical: ScrollBar {}

      delegate: Rectangle {
        id: plRow
        required property var modelData
        required property int index
        width: list.width - 12
        height: 58
        radius: 8
        color: plMouse.containsMouse ? Qt.rgba(root.pal.foreground.r, root.pal.foreground.g, root.pal.foreground.b, 0.06) : "transparent"

        Cover {
          id: plArt
          x: 8
          anchors.verticalCenter: parent.verticalCenter
          width: 44
          height: 44
          radius: 6
          source: root.app.store.artFor("p", plRow.modelData.id)
          revision: root.app.artRevision
          tint: Qt.rgba(root.pal.foreground.r, root.pal.foreground.g, root.pal.foreground.b, 0.08)
          glyphColor: root.pal.muted
          glyph: plRow.modelData.auto ? Model.GLYPH_USER : Model.GLYPH_PLAYLIST
          fontFamily: root.app.fontFamily
        }
        Column {
          anchors.left: plArt.right
          anchors.leftMargin: 12
          anchors.right: actions.left
          anchors.rightMargin: 12
          anchors.verticalCenter: parent.verticalCenter
          spacing: 2
          Text {
            width: parent.width
            textFormat: Text.PlainText
            text: plRow.modelData.title
            color: root.pal.foreground
            font.family: root.app.fontFamily
            font.pixelSize: 13
            font.bold: !!plRow.modelData.saved
            elide: Text.ElideRight
          }
          Text {
            width: parent.width
            textFormat: Text.PlainText
            text: [plRow.modelData.language,
              plRow.modelData.tracks ? Model.plural(plRow.modelData.tracks.length, "song")
                : plRow.modelData.saved ? "songs load when opened" : "",
              plRow.modelData.saved ? "in your library" : ""].filter(function(x) { return x }).join(" · ")
            color: root.pal.muted
            font.family: root.app.fontFamily
            font.pixelSize: 11
            elide: Text.ElideRight
          }
        }
        Row {
          id: actions
          anchors.right: parent.right
          anchors.rightMargin: 8
          anchors.verticalCenter: parent.verticalCenter
          spacing: 4
          z: 1
          Chip {
            anchors.verticalCenter: parent.verticalCenter
            text: plRow.modelData.saved ? "Saved" : "Save"
            glyph: plRow.modelData.saved ? Model.GLYPH_CHECK : Model.GLYPH_ADD
            textColor: root.pal.foreground; accent: root.pal.accent
            selected: !!plRow.modelData.saved
            fontSize: 11; fontFamily: root.app.fontFamily
            onClicked: root.app.savePlaylist(plRow.modelData.id, !plRow.modelData.saved)
          }
          RemoveButton {
            anchors.verticalCenter: parent.verticalCenter
            label: ""
            confirmLabel: "Remove?"
            textColor: root.pal.muted
            fontSize: 11; fontFamily: root.app.fontFamily
            onConfirmed: root.app.removePlaylist(plRow.modelData.id)
          }
          GlyphButton {
            anchors.verticalCenter: parent.verticalCenter
            glyph: Model.GLYPH_PLAY
            size: 34
            color: root.pal.accentText
            fill: root.pal.accent
            fontFamily: root.app.fontFamily
            onClicked: root.app.playPlaylist(plRow.modelData.id, false)
          }
        }
        MouseArea {
          id: plMouse
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: root.app.openPlaylist(plRow.modelData.id)
        }
      }
    }
  }
}
