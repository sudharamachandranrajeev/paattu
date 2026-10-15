import QtQuick
import QtQuick.Controls
import "Model.js" as Model

// An album, playlist or singer from a search (`paattu browse open`): its
// songs to play, save or add to playlists. A singer's page also lists their
// albums, playlists and similar singers, and more songs as it's scrolled.
Flickable {
  id: root

  required property var app
  property var item: ({})

  readonly property var pal: app.pal
  readonly property bool isArtist: item.type === "artist"
  property var songs: []
  property var albums: []
  property var playlists: []
  property var similar: []
  property string name: ""
  property string about: ""
  property int page: 0
  property bool busy: false
  property bool done: false
  property string error: ""
  property var expanded: ({})
  // Replies for an item that's no longer showing are dropped.
  property var token: ({})
  property string loadedKey: ""

  readonly property int perRow: Math.max(1, Math.floor((column.width + 28) / (150 + 28)))

  contentWidth: width
  contentHeight: column.implicitHeight + 40
  clip: true
  boundsBehavior: Flickable.StopAtBounds
  ScrollBar.vertical: ScrollBar {}

  onItemChanged: reload()
  Component.onCompleted: reload()
  Component.onDestruction: token.gone = true
  onContentYChanged: maybeMore()
  onContentHeightChanged: maybeMore()

  function reload() {
    var key = [item.type, item.site, item.id].join("|")
    if (!item.type || key === loadedKey) return
    loadedKey = key
    token.gone = true
    token = {}
    songs = []
    albums = []
    playlists = []
    similar = []
    expanded = {}
    name = item.title || ""
    about = item.subtitle || ""
    page = 0
    busy = false
    done = false
    error = ""
    contentY = 0
    more()
  }

  function more() {
    if (busy || done || !item.type) return
    busy = true
    var mine = token
    var next = page + 1
    app.loadCollection(item, next, function(ok, e) {
      if (mine.gone) return
      root.busy = false
      if (!ok) {
        if (next === 1) root.error = e.message || "Couldn't open it"
        root.done = true
        return
      }
      root.page = next
      var have = {}
      root.songs.forEach(function(t) { have[t.id] = true })
      var fresh = (e.songs || []).filter(function(t) { return !have[t.id] })
      root.songs = root.songs.concat(fresh)
      var known = {}
      root.albums.forEach(function(a) { known[a.site + a.id] = true })
      root.albums = root.albums.concat((e.albums || []).filter(function(a) { return !known[a.site + a.id] }))
      if (next === 1) {
        if (e.name) root.name = e.name
        if (e.about) root.about = e.about
        root.playlists = e.playlists || []
        root.similar = e.similar || []
      }
      root.done = !root.isArtist || !e.next || fresh.length === 0
    })
  }

  function maybeMore() {
    if (!busy && !done && page > 0 && contentY + height > contentHeight - 700) Qt.callLater(root.more)
  }

  function play(index, shuffle) { app.playFound(songs, index, shuffle, name, item.id || "") }

  Column {
    id: column
    x: 28
    y: 8
    width: root.width - 56
    spacing: 22

    // ---------- header
    Row {
      width: parent.width
      spacing: 24

      Cover {
        width: 200
        height: 200
        radius: 28
        circle: root.isArtist
        source: root.app.store.artFor("c", root.item.artKey)
        revision: root.app.artRevision
        tint: Qt.rgba(root.pal.foreground.r, root.pal.foreground.g, root.pal.foreground.b, 0.08)
        glyphColor: root.pal.foreground
        glyph: Model.resultGlyph(root.item)
        fontFamily: root.app.fontFamily
      }

      Column {
        width: parent.width - 224
        anchors.verticalCenter: parent.verticalCenter
        spacing: 6

        Text {
          textFormat: Text.PlainText
          text: (Model.resultTypeName(root.item) + "  ·  " + Model.siteName(root.item.site)).toUpperCase()
          color: root.pal.muted
          font.family: root.app.fontFamily
          font.pixelSize: 11
          font.letterSpacing: 1.2
        }
        Text {
          width: parent.width
          textFormat: Text.PlainText
          text: root.name
          color: root.pal.foreground
          font.family: root.app.fontFamily
          font.pixelSize: 30
          font.bold: true
          wrapMode: Text.WordWrap
          maximumLineCount: 2
          elide: Text.ElideRight
        }
        Text {
          width: parent.width
          visible: text !== ""
          textFormat: Text.PlainText
          // (A YouTube playlist's details already say how many videos.)
          text: [root.about, root.item.language || "",
                 !root.songs.length || /\d+ (videos?|songs?|tracks?)\b/.test(root.about) ? ""
                   : root.done ? Model.plural(root.songs.length, "song") : root.songs.length + "+ songs"]
            .filter(function(s) { return s }).join("  ·  ")
          color: root.pal.muted
          font.family: root.app.fontFamily
          font.pixelSize: 13
          elide: Text.ElideRight
        }
        Item { width: 1; height: 8 }
        Flow {
          width: parent.width
          spacing: 8

          Chip {
            text: "Play"
            glyph: Model.GLYPH_PLAY
            textColor: root.pal.foreground
            accent: root.pal.accent
            selected: true
            enabled: root.songs.length > 0
            fontSize: 13
            fontFamily: root.app.fontFamily
            onClicked: root.play(0, false)
          }
          Chip {
            text: "Shuffle"
            glyph: Model.GLYPH_SHUFFLE
            textColor: root.pal.foreground
            accent: root.pal.accent
            enabled: root.songs.length > 0
            fontSize: 13
            fontFamily: root.app.fontFamily
            onClicked: root.play(Math.floor(Math.random() * root.songs.length), true)
          }
          Chip {
            text: "Save songs"
            glyph: Model.GLYPH_SAVE
            textColor: root.pal.foreground
            accent: root.pal.accent
            enabled: root.songs.length > 0
            fontSize: 13
            fontFamily: root.app.fontFamily
            onClicked: root.app.saveSongs(root.songs)
          }
          // YouTube playlists and channels can live in the library and stay in sync.
          Chip {
            visible: root.item.site === "youtube"
            text: root.isArtist ? "Follow" : "Save playlist"
            glyph: root.isArtist ? Model.GLYPH_USER_ADD : Model.GLYPH_LIBRARY
            textColor: root.pal.foreground
            accent: root.pal.accent
            fontSize: 13
            fontFamily: root.app.fontFamily
            onClicked: root.app.importLink(root.item.url)
          }
          Chip {
            visible: !!root.item.url
            text: "Open on " + Model.siteName(root.item.site)
            glyph: Model.GLYPH_OPEN
            textColor: root.pal.foreground
            accent: root.pal.accent
            fontSize: 13
            fontFamily: root.app.fontFamily
            onClicked: Qt.openUrlExternally(root.item.url)
          }
        }
      }
    }

    Text {
      width: parent.width
      visible: text !== ""
      textFormat: Text.PlainText
      wrapMode: Text.WordWrap
      text: root.error ? root.error
        : root.busy && root.page === 0 ? "Loading " + (root.name || "it") + "…"
        : root.done && root.songs.length === 0 && root.albums.length === 0 ? "No songs here that can play" : ""
      color: root.error ? root.pal.accent : root.pal.muted
      font.family: root.app.fontFamily
      font.pixelSize: 13
    }

    // ---------- a singer's albums, playlists and similar singers
    Repeater {
      model: [{ key: "albums", title: "Albums and singles", items: root.albums },
              { key: "playlists", title: "Playlists", items: root.playlists },
              { key: "similar", title: "Similar", items: root.similar }]
      Column {
        id: shelf
        required property var modelData
        readonly property bool open: !!root.expanded[modelData.key]
        width: column.width
        spacing: 14
        visible: modelData.items.length > 0

        Row {
          spacing: 12
          Text {
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: shelf.modelData.title
            color: root.pal.foreground
            font.family: root.app.fontFamily
            font.pixelSize: 16
            font.bold: true
          }
          Chip {
            anchors.verticalCenter: parent.verticalCenter
            visible: shelf.modelData.items.length > root.perRow
            text: shelf.open ? "Show fewer" : "Show all " + shelf.modelData.items.length
            textColor: root.pal.foreground
            accent: root.pal.accent
            fontSize: 11
            fontFamily: root.app.fontFamily
            onClicked: {
              var next = Object.assign({}, root.expanded)
              next[shelf.modelData.key] = !shelf.open
              root.expanded = next
            }
          }
        }
        Flow {
          width: parent.width
          spacing: 28
          Repeater {
            model: shelf.open ? shelf.modelData.items : shelf.modelData.items.slice(0, root.perRow)
            ResultCard {
              required property var modelData
              app: root.app
              item: modelData
              size: 150
            }
          }
        }
      }
    }

    // ---------- songs
    Column {
      width: parent.width
      spacing: 2
      visible: root.songs.length > 0

      Text {
        visible: root.isArtist
        textFormat: Text.PlainText
        text: "Songs"
        color: root.pal.foreground
        font.family: root.app.fontFamily
        font.pixelSize: 16
        font.bold: true
        bottomPadding: 8
      }
      Repeater {
        model: root.songs
        TrackRow {
          required property var modelData
          required property int index
          width: column.width
          app: root.app
          track: modelData
          number: index + 1
          found: true
          current: root.app.player.videoId === modelData.id
          playing: current && root.app.player.playing
          onActivated: root.play(index, false)
          onPlayNext: root.app.queueSong(modelData, true)
        }
      }
    }

    Text {
      width: parent.width
      visible: root.page > 0 && root.isArtist && root.songs.length > 0
      horizontalAlignment: Text.AlignHCenter
      textFormat: Text.PlainText
      text: root.busy ? "Loading more…" : root.done ? "That's everything" : ""
      color: root.pal.muted
      font.family: root.app.fontFamily
      font.pixelSize: 12
    }
  }
}
