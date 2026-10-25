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

    // Made for you (home only): the day's, week's and month's playlists from
    // what you play, and a playlist from a description.
    Column {
      width: parent.width
      spacing: 14
      visible: !root.language

      Text {
        textFormat: Text.PlainText
        text: "Made for you"
        color: root.pal.foreground
        font.family: root.app.fontFamily
        font.pixelSize: 19
        font.bold: true
      }

      Flow {
        width: parent.width
        spacing: 24
        Repeater {
          model: Model.MADE
          MadeTile {
            onPlay: function(refresh) { root.app.playMade(modelData.kind, modelData.title, refresh) }
          }
        }
      }

      // A playlist from a description: Enter (or Play) plays it.
      Flow {
        width: parent.width
        spacing: 8
        InputBox {
          id: describeBox
          width: Math.min(460, parent.width)
          app: root.app
          glyph: Model.GLYPH_MADE
          placeholder: "Describe a playlist: Ilaiyaraaja melodies, rain songs, Premam…"
          onAccepted: root.app.describePlaylist(text, "")
        }
        Chip {
          text: "Play"
          glyph: Model.GLYPH_PLAY
          textColor: root.pal.foreground
          accent: root.pal.accent
          selected: true
          enabled: describeBox.text.trim() !== ""
          fontSize: 13
          fontFamily: root.app.fontFamily
          onClicked: root.app.describePlaylist(describeBox.text, "")
        }
        Chip {
          text: "Play and save"
          glyph: Model.GLYPH_PLAYLIST_ADD
          textColor: root.pal.foreground
          accent: root.pal.accent
          enabled: describeBox.text.trim() !== ""
          fontSize: 13
          fontFamily: root.app.fontFamily
          onClicked: root.app.describePlaylist(describeBox.text, describeBox.text.trim())
        }
      }
    }

    // The charts (home only): what's played most this week in your languages.
    Column {
      width: parent.width
      spacing: 14
      visible: !root.language

      Text {
        textFormat: Text.PlainText
        text: "Charts"
        color: root.pal.foreground
        font.family: root.app.fontFamily
        font.pixelSize: 19
        font.bold: true
      }

      Flow {
        width: parent.width
        spacing: 24
        Repeater {
          model: Model.chartTiles(root.app.store.languages)
          MadeTile {
            onPlay: function(refresh) { root.app.playChart(modelData.kind, modelData.language, modelData.name, refresh) }
          }
        }
      }
    }

    // On this computer (home only): the songs kept to play with no internet.
    Column {
      width: parent.width
      spacing: 14
      visible: !root.language

      Row {
        spacing: 16
        Text {
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          text: "On this computer"
          color: root.pal.foreground
          font.family: root.app.fontFamily
          font.pixelSize: 19
          font.bold: true
        }
        Text {
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          text: root.app.store.offline.length
            ? Model.plural(root.app.store.offline.length, "song") + " · " + Model.formatBytes(Model.offlineBytes(root.app.store.offline))
            : "Songs you play to the end are kept here, to play with no internet"
          color: root.pal.muted
          font.family: root.app.fontFamily
          font.pixelSize: 12
        }
      }

      Flow {
        width: parent.width
        spacing: 8
        Chip {
          visible: root.app.store.offline.length > 0
          text: "Play"
          glyph: Model.GLYPH_PLAY
          textColor: root.pal.foreground
          accent: root.pal.accent
          selected: true
          fontSize: 13
          fontFamily: root.app.fontFamily
          onClicked: root.app.playOffline(false)
        }
        Chip {
          visible: root.app.store.offline.length > 0
          text: "Shuffle"
          glyph: Model.GLYPH_SHUFFLE
          textColor: root.pal.foreground
          accent: root.pal.accent
          fontSize: 13
          fontFamily: root.app.fontFamily
          onClicked: root.app.playOffline(true)
        }
        Chip {
          text: root.app.store.offline.length ? "See all" : "Manage"
          glyph: Model.GLYPH_DOWNLOAD
          textColor: root.pal.foreground
          accent: root.pal.accent
          fontSize: 13
          fontFamily: root.app.fontFamily
          onClicked: root.app.navigate("offline")
        }
      }

      Column {
        width: Math.min(parent.width, 720)
        visible: root.app.store.offline.length > 0
        Repeater {
          model: root.app.store.offline.slice(0, 3)
          TrackRow {
            required property var modelData
            required property int index
            width: parent.width
            app: root.app
            track: modelData.track
            number: index + 1
            current: root.app.nowTrack && root.app.nowTrack.id === modelData.track.id
            playing: current && root.app.player.playing
            onActivated: root.app.playOffline(false, index)
          }
        }
      }
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

  // A tile that plays a playlist made when it's opened: a made-for-you
  // playlist or a chart. Refresh (bottom left) makes it again first.
  component MadeTile: Item {
    id: madeTile
    required property var modelData
    signal play(bool refresh)
    readonly property bool hovered: madeMouse.containsMouse || madePlay.hovered || madeNew.hovered
    width: root.cardSize * 0.8
    height: width + 52

    Rectangle {
      anchors.fill: parent
      anchors.margins: -8
      radius: 26
      color: madeTile.hovered ? Qt.rgba(root.pal.foreground.r, root.pal.foreground.g, root.pal.foreground.b, 0.06) : "transparent"
      Behavior on color { ColorAnimation { duration: 120 } }
    }
    Rectangle {
      id: madeArt
      width: parent.width
      height: width
      radius: 20
      gradient: Gradient {
        GradientStop { position: 0; color: root.pal.accent }
        GradientStop { position: 1; color: Qt.darker(root.pal.accent, 1.8) }
      }
      Text {
        anchors.centerIn: parent
        textFormat: Text.PlainText
        text: madeTile.modelData.glyph
        color: root.pal.accentText
        font.family: root.app.fontFamily
        font.pixelSize: madeArt.width * 0.3
      }
      GlyphButton {
        id: madeNew
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        anchors.margins: 8
        size: 32
        glyph: Model.GLYPH_REFRESH
        color: root.pal.accentText
        fontFamily: root.app.fontFamily
        tooltip: "Make a new one"
        opacity: madeTile.hovered ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: 140 } }
        onClicked: madeTile.play(true)
      }
      GlyphButton {
        id: madePlay
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 8
        size: 40
        glyph: Model.GLYPH_PLAY
        color: root.pal.accent
        fill: root.pal.accentText
        fontFamily: root.app.fontFamily
        opacity: madeTile.hovered ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: 140 } }
        onClicked: madeTile.play(false)
      }
    }
    Column {
      anchors.top: madeArt.bottom
      anchors.topMargin: 8
      width: parent.width
      spacing: 2
      Text {
        width: parent.width
        textFormat: Text.PlainText
        text: madeTile.modelData.title
        color: root.pal.foreground
        font.family: root.app.fontFamily
        font.pixelSize: 13
        font.bold: true
        elide: Text.ElideRight
      }
      Text {
        width: parent.width
        textFormat: Text.PlainText
        text: madeTile.modelData.blurb
        color: root.pal.muted
        font.family: root.app.fontFamily
        font.pixelSize: 11
        elide: Text.ElideRight
      }
    }
    MouseArea {
      id: madeMouse
      anchors.fill: parent
      z: -1
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: madeTile.play(false)
    }
  }
}
