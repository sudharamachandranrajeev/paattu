import QtQuick
import QtQuick.Controls
import "Model.js" as Model

// One playlist: header with play / shuffle / save / remove, then its songs,
// each removable from the playlist. Your own playlists (Favourites, Saved
// songs and the ones you made) can be renamed and deleted instead of saved and
// refreshed; Favourites and Saved songs always stay.
ListView {
  id: root

  required property var app
  property string playlistId: ""

  readonly property var pal: app.pal
  readonly property var playlist: app.store.lib.playlists[playlistId] || null
  readonly property bool isFavourites: playlistId === Model.FAVOURITES
  readonly property bool isSaved: playlistId === Model.SAVED
  readonly property bool builtin: isFavourites || isSaved
  readonly property bool own: builtin || !!(playlist && playlist.local)
  readonly property var cover: Model.coverOf(playlist || { id: playlistId, local: own, tracks: [] })
  property bool renaming: false
  onPlaylistIdChanged: { renaming = false; hidden = ({}) }

  function rename(name) {
    name = String(name || "").trim()
    renaming = false
    if (name && playlist && name !== playlist.title)
      app.quick.run(["playlist", "rename", "--", playlistId, name], "Renaming…")
  }
  readonly property var tracks: Model.playlistTracks(app.store.lib, playlistId)
  readonly property int removedSongs: playlist && playlist.removedTracks ? playlist.removedTracks.length : 0
  // Songs removed here but not yet saved by the CLI: hidden right away.
  property var hidden: ({})
  readonly property var shown: tracks.filter(function(t) { return !hidden[t.id] })
  property string shownFor: ""

  // The model is set by hand so a removal (or the library reloading after
  // one) keeps the scroll position; a new playlist starts at the top.
  function showTracks() {
    var same = shownFor === playlistId
    var y = contentY
    model = shown
    shownFor = playlistId
    if (same) {
      contentY = y
      returnToBounds()
    }
  }
  onShownChanged: showTracks()
  Component.onCompleted: showTracks()

  function removeSong(trackId) {
    var next = Object.assign({}, hidden)
    next[trackId] = true
    hidden = next
    app.removeSong(playlistId, trackId, function(ok) {
      if (ok) return
      var back = Object.assign({}, root.hidden)
      delete back[trackId]
      root.hidden = back
    })
  }
  readonly property int totalSeconds: {
    var s = 0
    for (var i = 0; i < tracks.length; i++) s += tracks[i].duration || 0
    return s
  }

  clip: true
  spacing: 0
  boundsBehavior: Flickable.StopAtBounds
  ScrollBar.vertical: ScrollBar {}
  leftMargin: 20
  rightMargin: 20
  bottomMargin: 20

  header: Item {
    width: root.width - 40
    height: head.height + 28

    Row {
      id: head
      x: 8
      y: 4
      spacing: 24
      width: parent.width - 16

      Cover {
        width: 180
        height: 180
        radius: 28
        // Favourites and Saved songs are tiles; your playlists wear their first song's art.
        source: root.builtin ? "" : root.app.store.artFor(root.cover.kind, root.cover.id)
        revision: root.app.artRevision
        tint: root.builtin ? root.pal.accent
          : Qt.rgba(root.pal.foreground.r, root.pal.foreground.g, root.pal.foreground.b, 0.08)
        glyphColor: root.builtin ? root.pal.accentText : root.pal.muted
        glyph: Model.ownGlyph(root.playlistId)
        fontFamily: root.app.fontFamily
      }

      Column {
        anchors.bottom: parent.bottom
        width: parent.width - 204
        spacing: 8

        Text {
          textFormat: Text.PlainText
          text: root.isFavourites ? "YOUR FAVOURITES" : root.isSaved ? "YOUR LIBRARY" : root.own ? "YOUR PLAYLIST"
            : ((root.playlist && root.playlist.language) || "PLAYLIST").toUpperCase()
              + (root.playlist && root.playlist.auto ? "  ·  AUTO" : "")
          color: root.pal.accent
          font.family: root.app.fontFamily
          font.pixelSize: 11
          font.letterSpacing: 1.4
        }
        Text {
          width: parent.width
          visible: !root.renaming
          textFormat: Text.PlainText
          text: root.playlist ? root.playlist.title : root.isFavourites ? "Favourites" : root.isSaved ? "Saved songs" : "Playlist"
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
          text: root.own ? [root.isFavourites ? "Songs you hearted" : root.isSaved ? "Songs you saved" : "Made by you",
            Model.plural(root.tracks.length, "song"),
            root.totalSeconds ? Model.formatTime(root.totalSeconds) : ""].filter(function(x) { return x }).join("  ·  ")
            : root.playlist ? [Model.ownerName(root.app.store.lib, root.playlist),
            root.playlist.tracks ? Model.plural(root.tracks.length, "song") : "fetching songs…",
            root.totalSeconds ? Model.formatTime(root.totalSeconds) : ""].filter(function(x) { return x }).join("  ·  ") : ""
          color: root.pal.muted
          font.family: root.app.fontFamily
          font.pixelSize: 12
          elide: Text.ElideRight
          MouseArea {
            anchors.fill: parent
            enabled: !!(root.playlist && root.playlist.owner && root.app.store.lib.users[root.playlist.owner])
            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: root.app.openUser(root.playlist.owner)
          }
        }

        Row {
          spacing: 8
          topPadding: 6
          GlyphButton {
            glyph: Model.GLYPH_PLAY
            size: 48
            color: root.pal.accentText
            fill: root.pal.accent
            fontFamily: root.app.fontFamily
            enabled: root.tracks.length > 0
            onClicked: root.app.playPlaylist(root.playlistId, false)
          }
          GlyphButton {
            anchors.verticalCenter: parent.verticalCenter
            glyph: Model.GLYPH_SHUFFLE
            size: 38
            color: root.pal.foreground
            fontFamily: root.app.fontFamily
            enabled: root.tracks.length > 0
            onClicked: root.app.playPlaylist(root.playlistId, true)
          }
          Chip {
            anchors.verticalCenter: parent.verticalCenter
            visible: !root.own
            text: root.playlist && root.playlist.saved ? "In your library" : "Save to library"
            glyph: root.playlist && root.playlist.saved ? Model.GLYPH_CHECK : Model.GLYPH_ADD
            textColor: root.pal.foreground
            accent: root.pal.accent
            selected: !!(root.playlist && root.playlist.saved)
            fontSize: 12
            fontFamily: root.app.fontFamily
            onClicked: root.app.savePlaylist(root.playlistId, !(root.playlist && root.playlist.saved))
          }
          Chip {
            anchors.verticalCenter: parent.verticalCenter
            visible: root.own && !root.builtin && !!root.playlist
            text: "Rename"
            glyph: Model.GLYPH_EDIT
            textColor: root.pal.foreground
            accent: root.pal.accent
            fontSize: 12
            fontFamily: root.app.fontFamily
            onClicked: {
              renameInput.text = root.playlist.title
              root.renaming = true
              renameInput.forceActiveFocus()
              renameInput.selectAll()
            }
          }
          Chip {
            anchors.verticalCenter: parent.verticalCenter
            visible: !root.own
            text: "Refresh"
            glyph: Model.GLYPH_REFRESH
            textColor: root.pal.foreground
            accent: root.pal.accent
            fontSize: 12
            fontFamily: root.app.fontFamily
            onClicked: root.app.jobs.run(["playlist", "fetch", root.playlistId], "Refreshing playlist…", function() { root.app.refreshArt() })
          }
          Chip {
            id: mixChip
            anchors.verticalCenter: parent.verticalCenter
            visible: !!root.playlist || root.builtin
            text: "Add to mix"
            glyph: Model.GLYPH_PLAYLIST_ADD
            textColor: root.pal.foreground
            accent: root.pal.accent
            fontSize: 12
            fontFamily: root.app.fontFamily
            onClicked: root.app.pickMixes({ type: "playlist", id: root.playlistId,
              title: root.playlist ? root.playlist.title : root.isSaved ? "Saved songs" : "Favourites" }, mixChip)
          }
          RemoveButton {
            anchors.verticalCenter: parent.verticalCenter
            visible: !!root.playlist && !root.builtin
            label: root.own ? "Delete playlist" : "Remove from app"
            confirmLabel: root.own ? "Click again to delete" : "Click again to remove"
            textColor: root.pal.foreground
            fontSize: 12
            fontFamily: root.app.fontFamily
            onConfirmed: root.app.removePlaylist(root.playlistId)
          }
        }
        Chip {
          visible: root.removedSongs > 0
          text: "Bring back " + Model.plural(root.removedSongs, "removed song")
          glyph: Model.GLYPH_RESTORE
          textColor: root.pal.foreground
          accent: root.pal.accent
          fontSize: 11
          fontFamily: root.app.fontFamily
          onClicked: {
            root.hidden = ({})
            root.app.restoreSongs(root.playlistId)
          }
        }
      }
    }
  }

  delegate: TrackRow {
    required property var modelData
    required property int index
    width: root.width - 40
    app: root.app
    track: modelData
    number: index + 1
    current: root.app.player.videoId === modelData.id
    playing: current && root.app.player.playing
    removable: !!root.playlist
    onActivated: root.app.playPlaylist(root.playlistId, false, modelData.id)
    onRemoveRequested: root.removeSong(modelData.id)
  }

  Text {
    anchors.horizontalCenter: parent.horizontalCenter
    y: Math.max(parent.height / 2, 280)
    width: Math.min(parent.width - 80, 420)
    visible: root.own && root.tracks.length === 0
    horizontalAlignment: Text.AlignHCenter
    wrapMode: Text.WordWrap
    textFormat: Text.PlainText
    text: root.isFavourites
      ? "Press the heart next to any song (or on the player) to keep it here."
      : root.isSaved
      ? "Search for a song (type in the box at the top, then press Enter) and press its save button to keep it here."
      : "Add songs with the add-to-playlist button next to any song, or on the player."
    color: root.pal.muted
    font.family: root.app.fontFamily
    font.pixelSize: 13
  }

  Text {
    anchors.centerIn: parent
    visible: !!root.playlist && root.playlist.tracks === null
    textFormat: Text.PlainText
    text: "Fetching songs from YouTube…"
    color: root.pal.muted
    font.family: root.app.fontFamily
    font.pixelSize: 13
  }
}
