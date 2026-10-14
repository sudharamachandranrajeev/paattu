import QtQuick
import QtQuick.Controls
import "Model.js" as Model

// Search. While typing: suggestions (YouTube phrases; JioSaavn songs, albums,
// singers and playlists) and what's already in your library. After Enter:
// songs, albums, singers and playlists from JioSaavn, YouTube and SoundCloud,
// one tab each, loading more as the end comes into view, and a tab of library
// matches. A pasted link shows the songs behind it.
Flickable {
  id: root

  required property var app
  readonly property var pal: app.pal
  readonly property string query: app.query.trim()
  readonly property bool isLink: Model.isLink(query)
  readonly property var results: isLink ? { tracks: [], playlists: [], users: [] } : Model.search(app.store.lib, app.query, 60)
  readonly property int libraryCount: results.tracks.length + results.playlists.length + results.users.length
  readonly property bool inLibrary: libraryCount > 0

  // ---------- browsing
  readonly property var browse: app.browse
  // Something typed that hasn't been searched yet.
  readonly property bool typing: query !== "" && !isLink && query !== browse.query
  readonly property bool browsing: !isLink && browse.query !== "" && !typing
  readonly property string kind: browse.kind || "song"
  readonly property var feed: kind !== "library" ? browse.feeds[kind] || null : null
  readonly property var shown: !feed ? [] : app.onlineSite
    ? feed.items.filter(function(i) { return i.site === root.app.onlineSite }) : feed.items
  readonly property var feedErrors: feed ? Object.keys(feed.errors || {}).map(function(site) {
    return "Couldn't search " + Model.siteName(site) + ": " + feed.errors[site]
  }) : []
  readonly property var suggestions: app.suggestions.query !== "" && query.indexOf(app.suggestions.query) === 0
    ? app.suggestions.items : []

  // ---------- a pasted link (`paattu search`)
  readonly property var online: app.online
  readonly property bool fresh: isLink && online.query !== "" && online.query === query
  readonly property var groups: fresh ? Model.searchGroups(online.results, "") : []

  contentWidth: width
  contentHeight: column.implicitHeight + 40
  clip: true
  boundsBehavior: Flickable.StopAtBounds
  ScrollBar.vertical: ScrollBar {}

  // Ask for the next page while the end is within a screen or so.
  function maybeMore() {
    if (!browsing || !feed || feed.busy || feed.done) return
    if (contentY + height > contentHeight - 900) Qt.callLater(root.app.loadMore, root.kind)
  }
  onContentYChanged: {
    maybeMore()
    if (browsing) app.searchScroll = contentY
  }
  onHeightChanged: maybeMore()
  onContentHeightChanged: maybeMore()
  onFeedChanged: maybeMore()
  onKindChanged: contentY = 0
  // Back from an album: where the list was.
  Component.onCompleted: if (browsing && app.searchScroll > 0) Qt.callLater(function() {
    root.contentY = Math.min(root.app.searchScroll, Math.max(0, root.contentHeight - root.height))
  })

  // Inline components can't see this file's ids, so they take `app`.
  component Heading: Text {
    required property var app
    textFormat: Text.PlainText
    color: app.pal.foreground
    font.family: app.fontFamily
    font.pixelSize: 16
    font.bold: true
  }
  component Note: Text {
    required property var app
    textFormat: Text.PlainText
    wrapMode: Text.WordWrap
    color: app.pal.muted
    font.family: app.fontFamily
    font.pixelSize: 12
  }

  Column {
    id: column
    x: 28
    y: 8
    width: root.width - 56
    spacing: 18

    Note {
      app: root.app
      width: column.width
      visible: !root.query && !root.browsing && !root.fresh
      font.pixelSize: 13
      lineHeight: 1.25
      text: "Type a song, a film or a singer in the box above: suggestions show as you type, and Enter searches "
        + "JioSaavn, YouTube and SoundCloud for songs, albums, singers and playlists. Or paste a link to a song "
        + "or an album on any site (JioSaavn, YouTube, SoundCloud, Bandcamp, Audiomack, archive.org, an mp3 or "
        + "flac file…)."
    }

    // ---------- typing: search for it, suggestions
    Column {
      width: parent.width
      spacing: 2
      visible: root.typing || (root.isLink && root.online.query !== root.query)

      SuggestionRow {
        app: root.app
        width: column.width
        glyph: root.isLink ? Model.GLYPH_LINK : Model.GLYPH_SEARCH
        title: root.isLink ? "Find the songs at this link" : "Search for “" + root.query + "”"
        detail: root.isLink ? "" : "Songs, albums, singers and playlists on JioSaavn, YouTube and SoundCloud  ·  Enter"
        accent: true
        onClicked: root.app.searchOnline(root.query)
      }
      Repeater {
        model: root.typing ? root.suggestions : []
        SuggestionRow {
          app: root.app
          width: column.width
          required property var modelData
          glyph: Model.resultGlyph(modelData)
          title: modelData.title
          detail: modelData.type === "query" ? "" : [Model.resultTypeName(modelData), modelData.subtitle || ""]
            .filter(function(s) { return s }).join("  ·  ")
          art: modelData.type === "query" ? "" : root.app.store.artFor("c", modelData.artKey)
          round: modelData.type === "artist"
          onClicked: root.app.openSuggestion(modelData)
        }
      }
    }

    // ---------- browsing: tabs
    Flow {
      width: parent.width
      spacing: 8
      visible: root.browsing

      Repeater {
        model: Model.KINDS.concat(root.libraryCount ? [{ kind: "library", title: "In your library  " + root.libraryCount,
                                                          glyph: Model.GLYPH_LIBRARY }] : [])
        Chip {
          required property var modelData
          text: modelData.title
          glyph: modelData.glyph
          textColor: root.pal.foreground
          accent: root.pal.accent
          selected: root.kind === modelData.kind
          fontSize: 13
          fontFamily: root.app.fontFamily
          onClicked: root.app.showKind(modelData.kind)
        }
      }
      Item { width: 16; height: 1 }
      // Which site's results show.
      Repeater {
        model: root.kind === "library" ? [] : [{ site: "", title: "All sites" }].concat(
          (Model.KIND_SITES[root.kind] || []).map(function(s) { return { site: s, title: Model.siteName(s) } }))
        Chip {
          required property var modelData
          text: modelData.title
          textColor: root.pal.foreground
          accent: root.pal.accent
          selected: root.app.onlineSite === modelData.site
          fontSize: 11
          fontFamily: root.app.fontFamily
          onClicked: root.app.onlineSite = modelData.site
        }
      }
    }

    Note {
      app: root.app
      width: column.width
      visible: root.browsing && root.kind !== "library" && text !== ""
      color: root.feed && (root.feed.error || root.feedErrors.length) ? root.pal.accent : root.pal.muted
      text: !root.feed || (root.feed.busy && root.feed.pages === 0)
          ? "Searching for " + Model.kindTitle(root.kind).toLowerCase() + " matching “" + root.browse.query + "”…"
        : root.feed.error ? root.feed.error
        : root.feed.items.length === 0 ? "No " + Model.kindTitle(root.kind).toLowerCase() + " found for “" + root.browse.query + "”"
          + (root.feedErrors.length ? "  ·  " + root.feedErrors.join("  ·  ") : "")
        : root.feedErrors.join("  ·  ")
    }

    // ---------- songs
    Column {
      width: parent.width
      spacing: 2
      visible: root.browsing && root.kind === "song" && root.shown.length > 0

      Row {
        spacing: 10
        bottomPadding: 6
        Heading {
          app: root.app
          anchors.verticalCenter: parent.verticalCenter
          text: root.feed && root.feed.done ? Model.plural(root.shown.length, "song") : root.shown.length + "+ songs"
        }
        Chip {
          anchors.verticalCenter: parent.verticalCenter
          text: "Play all"
          glyph: Model.GLYPH_PLAY
          textColor: root.pal.foreground
          accent: root.pal.accent
          selected: true
          fontSize: 12
          fontFamily: root.app.fontFamily
          onClicked: root.app.playFound(root.shown, 0, false, "“" + root.browse.query + "”", "")
        }
        Chip {
          anchors.verticalCenter: parent.verticalCenter
          text: "Shuffle"
          glyph: Model.GLYPH_SHUFFLE
          textColor: root.pal.foreground
          accent: root.pal.accent
          fontSize: 12
          fontFamily: root.app.fontFamily
          onClicked: root.app.playFound(root.shown, Math.floor(Math.random() * root.shown.length), true,
                                        "“" + root.browse.query + "”", "")
        }
      }
      Repeater {
        model: root.kind === "song" ? root.shown : []
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
          // From this song on through the results.
          onActivated: root.app.playFound(root.shown, index, false, "“" + root.browse.query + "”", "")
          onPlayNext: root.app.queueSong(modelData, true)
        }
      }
    }

    // ---------- albums, singers, playlists
    Flow {
      width: parent.width
      spacing: 28
      visible: root.browsing && root.kind !== "song" && root.kind !== "library" && root.shown.length > 0
      Repeater {
        model: root.kind !== "song" && root.kind !== "library" ? root.shown : []
        ResultCard {
          required property var modelData
          app: root.app
          item: modelData
          size: 150
        }
      }
    }

    Note {
      app: root.app
      width: column.width
      visible: root.browsing && !!root.feed && root.feed.items.length > 0
      horizontalAlignment: Text.AlignHCenter
      text: root.feed && root.feed.busy ? "Loading more…" : root.feed && root.feed.done ? "That's everything" : ""
    }

    // ---------- a pasted link
    Note {
      app: root.app
      width: column.width
      visible: root.isLink && root.online.query === root.query && text !== ""
      color: root.fresh && !root.online.busy && root.online.error ? root.pal.accent : root.pal.muted
      text: root.online.busy ? "Looking up the link…"
        : root.online.error ? root.online.error
        : root.online.results.length === 0 ? "No songs at that link"
        : Model.plural(root.online.results.length, "song") + " at the link"
    }
    Repeater {
      model: root.groups
      Column {
        id: group
        required property var modelData
        width: column.width
        spacing: 2
        Repeater {
          model: group.modelData.tracks
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
            onActivated: root.app.playSong(modelData)
            onPlayNext: root.app.queueSong(modelData, true)
          }
        }
      }
    }

    // ---------- your library (while typing, or its own tab)
    Rectangle {
      width: parent.width
      height: 1
      visible: root.typing
      color: Qt.rgba(root.pal.foreground.r, root.pal.foreground.g, root.pal.foreground.b, 0.08)
    }

    Column {
      width: parent.width
      spacing: 22
      visible: root.query !== "" && !root.isLink && (root.typing || root.kind === "library")

      Text {
        visible: root.typing
        textFormat: Text.PlainText
        text: "In your library"
        color: root.pal.foreground
        font.family: root.app.fontFamily
        font.pixelSize: 22
        font.bold: true
      }

      Note {
        app: root.app
        width: column.width
        visible: !root.inLibrary
        font.pixelSize: 13
        text: "Nothing in your library matches “" + root.app.query + "”."
      }

      Column {
        width: parent.width
        spacing: 4
        visible: root.results.tracks.length > 0
        Heading {
          app: root.app
          text: "Songs"
          bottomPadding: 6
        }
        Repeater {
          model: root.results.tracks
          TrackRow {
            required property var modelData
            required property int index
            width: column.width
            app: root.app
            track: modelData.track
            number: index + 1
            current: root.app.player.videoId === modelData.track.id
            playing: current && root.app.player.playing
            onActivated: root.app.playPlaylist(modelData.playlist, false, modelData.track.id)
          }
        }
      }

      Column {
        width: parent.width
        spacing: 14
        visible: root.results.playlists.length > 0
        Heading { app: root.app; text: "Playlists" }
        Flow {
          width: parent.width
          spacing: 24
          Repeater {
            model: root.results.playlists.slice(0, 15)
            PlaylistCard {
              required property var modelData
              app: root.app
              playlist: modelData
              size: 150
            }
          }
        }
      }

      Column {
        width: parent.width
        spacing: 6
        visible: root.results.users.length > 0
        Heading { app: root.app; text: "YouTube users" }
        Flow {
          width: parent.width
          spacing: 8
          Repeater {
            model: root.results.users
            Chip {
              required property var modelData
              text: modelData.name
              glyph: Model.GLYPH_USER
              textColor: root.pal.foreground
              accent: root.pal.accent
              fontSize: 12
              fontFamily: root.app.fontFamily
              onClicked: root.app.openUser(modelData.id)
            }
          }
        }
      }
    }
  }

  // One line of the suggestions: glyph or cover, title, details.
  component SuggestionRow: Rectangle {
    id: row
    required property var app
    property string glyph: ""
    property string title: ""
    property string detail: ""
    property string art: ""
    property bool round: false
    property bool accent: false
    signal clicked()

    height: 46
    radius: 8
    color: rowMouse.containsMouse ? Qt.rgba(row.app.pal.foreground.r, row.app.pal.foreground.g, row.app.pal.foreground.b, 0.06)
      : "transparent"

    Cover {
      id: rowArt
      x: 8
      anchors.verticalCenter: parent.verticalCenter
      width: 32
      height: 32
      radius: 6
      circle: row.round
      source: row.art
      tint: row.accent ? Qt.rgba(row.app.pal.accent.r, row.app.pal.accent.g, row.app.pal.accent.b, 0.22)
        : Qt.rgba(row.app.pal.foreground.r, row.app.pal.foreground.g, row.app.pal.foreground.b, 0.06)
      glyphColor: row.accent ? row.app.pal.accent : row.app.pal.foreground
      glyph: row.glyph
      fontFamily: row.app.fontFamily
    }
    Column {
      anchors.left: rowArt.right
      anchors.leftMargin: 12
      anchors.right: parent.right
      anchors.rightMargin: 12
      anchors.verticalCenter: parent.verticalCenter
      spacing: 1
      Text {
        width: parent.width
        textFormat: Text.PlainText
        text: row.title
        color: row.accent ? row.app.pal.accent : row.app.pal.foreground
        font.family: row.app.fontFamily
        font.pixelSize: 13
        font.bold: row.accent
        elide: Text.ElideRight
      }
      Text {
        width: parent.width
        visible: row.detail !== ""
        textFormat: Text.PlainText
        text: row.detail
        color: row.app.pal.muted
        font.family: row.app.fontFamily
        font.pixelSize: 11
        elide: Text.ElideRight
      }
    }
    MouseArea {
      id: rowMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: row.clicked()
    }
  }
}
