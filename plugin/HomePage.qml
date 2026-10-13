import QtQuick
import QtQuick.Controls
import "Model.js" as Model

// Home (language === ""): a greeting, then each language's saved playlists
// and the YouTube users you follow. Language pages show one language in full,
// a page of cards at a time (a whole label's profile can be hundreds).
Flickable {
  id: root

  required property var app
  property string language: ""

  readonly property var pal: app.pal
  readonly property var lib: app.store.lib
  readonly property var languages: language ? [language] : app.store.languages
  readonly property var greet: Model.greeting(new Date(), app.store.languages)
  readonly property real gutter: 28
  readonly property real cardSize: Math.max(140, Math.min(184, (width - gutter * 2 - 24 * 4) / 5))
  readonly property int pageSize: 40
  property int showing: pageSize
  onLanguageChanged: showing = pageSize

  contentWidth: width
  contentHeight: column.implicitHeight + 40
  clip: true
  boundsBehavior: Flickable.StopAtBounds
  ScrollBar.vertical: ScrollBar {}

  Column {
    id: column
    x: root.gutter
    y: 12
    width: root.width - root.gutter * 2
    spacing: 30

    // Header
    Column {
      width: parent.width
      spacing: 4

      Text {
        textFormat: Text.PlainText
        text: root.language
          ? (root.language === "Tamil" ? "தமிழ்" : root.language === "Malayalam" ? "മലയാളം" : root.language)
          : root.greet.native
        color: root.pal.foreground
        font.family: (root.language || root.greet.language) === "Tamil" ? "Noto Serif Tamil" : "Noto Serif Malayalam"
        font.pixelSize: 34
        font.weight: Font.DemiBold
      }
      Text {
        textFormat: Text.PlainText
        text: root.language ? root.language + " — your saved playlists and the YouTube users behind them"
          : root.greet.english
        color: root.pal.muted
        font.family: root.app.fontFamily
        font.pixelSize: 13
      }

      Flow {
        width: parent.width
        spacing: 8
        topPadding: 12
        // Home: your mixes (the shuffle buttons). A language page: that language.
        Repeater {
          model: root.language ? [] : root.app.store.mixes
          Chip {
            required property var modelData
            text: modelData.title
            glyph: Model.GLYPH_SHUFFLE
            textColor: root.pal.foreground
            accent: root.pal.accent
            selected: true
            fontSize: 13
            fontFamily: root.app.fontFamily
            onClicked: root.app.playMix(modelData.id, modelData.title)
          }
        }
        Chip {
          visible: !root.language
          text: root.app.store.mixes.length ? "Edit mixes" : "Make a mix"
          glyph: Model.GLYPH_EDIT
          textColor: root.pal.foreground
          accent: root.pal.accent
          fontSize: 13
          fontFamily: root.app.fontFamily
          onClicked: root.app.navigate("mixes")
        }
        Chip {
          visible: !!root.language
          text: "Shuffle " + root.language
          glyph: Model.GLYPH_SHUFFLE
          textColor: root.pal.foreground
          accent: root.pal.accent
          selected: true
          fontSize: 13
          fontFamily: root.app.fontFamily
          onClicked: root.app.playLanguage(root.language)
        }
        Chip {
          id: languageMixChip
          visible: !!root.language
          text: "Add to mix"
          glyph: Model.GLYPH_PLAYLIST_ADD
          textColor: root.pal.foreground
          accent: root.pal.accent
          fontSize: 13
          fontFamily: root.app.fontFamily
          onClicked: root.app.pickMixes({ type: "language", id: root.language, title: root.language }, languageMixChip)
        }
        Chip {
          visible: !root.language
          text: "Add from YouTube"
          glyph: Model.GLYPH_ADD
          textColor: root.pal.foreground
          accent: root.pal.accent
          fontSize: 13
          fontFamily: root.app.fontFamily
          onClicked: root.app.navigate("add")
        }
      }
    }

    Text {
      visible: !root.app.store.hasLibrary
      width: parent.width
      textFormat: Text.PlainText
      wrapMode: Text.WordWrap
      text: "Your library is empty. Use Add from YouTube with a profile (a label like @Muzik247 or "
        + "@thinkmusicofficial) or a playlist link."
      color: root.pal.muted
      font.family: root.app.fontFamily
      font.pixelSize: 13
    }

    // Your playlists: Favourites and the ones you made (home only).
    Column {
      width: parent.width
      spacing: 14
      visible: !root.language

      Row {
        spacing: 16
        Text {
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          text: "Your playlists"
          color: root.pal.foreground
          font.family: root.app.fontFamily
          font.pixelSize: 19
          font.bold: true
        }
        InputBox {
          id: newPlaylistBox
          anchors.verticalCenter: parent.verticalCenter
          width: 220
          height: 32
          app: root.app
          glyph: Model.GLYPH_ADD
          placeholder: "New playlist"
          onAccepted: {
            root.app.newPlaylist(text)
            text = ""
          }
        }
      }

      Flow {
        width: parent.width
        spacing: 24
        Repeater {
          model: root.app.store.mine
          PlaylistCard {
            required property var modelData
            app: root.app
            playlist: Object.assign({}, root.lib.playlists[modelData.id] || {}, modelData)
            size: root.cardSize * 0.8
          }
        }
      }
    }

    // One shelf per language
    Repeater {
      model: root.languages

      Column {
        id: shelf
        required property string modelData
        readonly property var all: Model.shelfFor(root.app.store.shelf, modelData, 0)
        readonly property var items: all.slice(0, root.language ? root.showing : 10)
        width: column.width
        spacing: 14
        visible: items.length > 0

        Row {
          spacing: 12
          Text {
            textFormat: Text.PlainText
            text: root.language ? "Saved playlists" : modelData
            color: root.pal.foreground
            font.family: root.app.fontFamily
            font.pixelSize: 19
            font.bold: true
          }
          Text {
            anchors.baseline: parent.children[0].baseline
            visible: !root.language
            textFormat: Text.PlainText
            text: "Show all"
            color: root.pal.accent
            font.family: root.app.fontFamily
            font.pixelSize: 12
            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: root.app.navigate("language", shelf.modelData)
            }
          }
        }

        Flow {
          width: parent.width
          spacing: 24
          Repeater {
            model: shelf.items
            PlaylistCard {
              required property var modelData
              app: root.app
              playlist: root.lib.playlists[modelData.id] || modelData
              size: root.cardSize
            }
          }
        }

        Chip {
          visible: !!root.language && shelf.all.length > shelf.items.length
          text: "Show more  ·  " + (shelf.all.length - shelf.items.length) + " left"
          glyph: Model.GLYPH_ADD
          textColor: root.pal.foreground
          accent: root.pal.accent
          fontSize: 12
          fontFamily: root.app.fontFamily
          onClicked: root.showing += root.pageSize
        }
      }
    }

    // Followed users
    Column {
      width: parent.width
      spacing: 14
      readonly property var users: Model.usersByLanguage(root.lib, root.language)
      visible: users.length > 0

      Text {
        textFormat: Text.PlainText
        text: "YouTube users you follow"
        color: root.pal.foreground
        font.family: root.app.fontFamily
        font.pixelSize: 19
        font.bold: true
      }

      Flow {
        width: parent.width
        spacing: 22
        Repeater {
          model: parent.parent.users
          Item {
            id: userTile
            required property var modelData
            width: 108
            height: 146

            Cover {
              id: avatar
              anchors.horizontalCenter: parent.horizontalCenter
              width: 96
              height: 96
              circle: true
              crop: false
              source: root.app.store.artFor("u", userTile.modelData.id)
              revision: root.app.artRevision
              tint: Qt.rgba(root.pal.foreground.r, root.pal.foreground.g, root.pal.foreground.b, 0.08)
              glyphColor: root.pal.muted
              glyph: Model.GLYPH_USER
              fontFamily: root.app.fontFamily
              scale: tileMouse.containsMouse ? 1.04 : 1
              Behavior on scale { NumberAnimation { duration: 120 } }
            }
            Text {
              anchors.top: avatar.bottom
              anchors.topMargin: 8
              width: parent.width
              horizontalAlignment: Text.AlignHCenter
              textFormat: Text.PlainText
              text: userTile.modelData.name
              color: root.pal.foreground
              font.family: root.app.fontFamily
              font.pixelSize: 12
              elide: Text.ElideRight
              maximumLineCount: 2
              wrapMode: Text.WordWrap
            }
            MouseArea {
              id: tileMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.app.openUser(userTile.modelData.id)
            }
          }
        }
      }
    }
  }
}
