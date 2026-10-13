import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import "Model.js" as Model

// The Paattu app: a real window (tile it, float it, move it between
// workspaces) themed by the current Omarchy theme or a Paattu colour scheme.
FloatingWindow {
  id: win

  required property var store
  required property var player
  required property var jobs
  required property var quick

  readonly property var pal: store.palette
  readonly property string fontFamily: Style.font.family
  property int artRevision: 0

  // Navigation: home | language | mixes | mix | users | user | playlist | queue | settings | search
  // ("add" opens users with the link box focused; "pick" opens the
  // add-to-playlist picker for the song playing)
  property string view: "home"
  property var arg: null
  property var history: []
  property string query: ""
  // Set to focus the "add from YouTube" box; the users page clears it.
  property bool focusAdd: false
  // Online search (`paattu search`): the last query and what came back.
  property var online: ({ query: "", results: [], errors: ({}), busy: false, error: "" })
  // Which site's results show ("" for all).
  property string onlineSite: ""
  // A short message over the player bar ("Playing … next").
  property string toast: ""

  // Emitted when the user hides the window (Esc, close button).
  signal dismissed()
  readonly property Item body: bodyScope

  title: "Paattu"
  color: pal.background
  implicitWidth: 1160
  implicitHeight: 760
  minimumSize: Qt.size(860, 560)

  onVisibleChanged: if (!visible) dismissed()

  function navigate(view, arg) {
    if (view === "search") search.forceActiveFocus()
    if (view === "pick") {
      if (player.videoId) pickPlaylists(nowTrack, null)
      return
    }
    if (view === "add") {
      focusAdd = true
      if (win.view === "users") return
      view = "users"
      arg = null
    }
    if (view === win.view && JSON.stringify(arg) === JSON.stringify(win.arg)) return
    history = history.concat([{ view: win.view, arg: win.arg }]).slice(-30)
    win.view = view
    win.arg = arg === undefined ? null : arg
  }

  function back() {
    if (history.length === 0) return
    var last = history[history.length - 1]
    history = history.slice(0, -1)
    view = last.view
    arg = last.arg
  }

  function refreshArt() { artTimer.restart() }

  function showToast(text) {
    toast = text || ""
    toastTimer.restart()
  }

  // ---------- search online ----------
  // JioSaavn, YouTube and SoundCloud at once, or the songs behind a link.
  // Its own runner, so a search never waits behind a slow import.
  function searchOnline(text) {
    text = String(text || "").trim()
    if (view !== "search") navigate("search")
    if (!text) {
      search.forceActiveFocus()
      return
    }
    if (search.text.trim() !== text) search.text = text
    onlineSite = ""
    online = { query: text, results: [], errors: ({}), busy: true, error: "" }
    searchJobs.run(Model.searchArgs(text, []), "", function(ok, e) {
      if (win.online.query !== text) return  // a newer search took over
      win.online = { query: text, results: ok && e.results ? e.results : [], errors: ok && e.errors ? e.errors : ({}),
        busy: false, error: ok ? "" : (e.message || "The search didn't work") }
      win.store.refreshArt()
    })
  }

  // One song (from a search, a link or the library) on its own.
  function playSong(track) {
    if (!track || !track.id) return
    quick.run(Model.playSongArgs(track.id), "Loading…", function(ok, e) {
      if (ok) cacheCurrentArt()
      else showToast(e.message)
    })
  }
  function queueSong(track, next) {
    if (!track || !track.id) return
    quick.run(Model.queueSongArgs(track.id, next), "", function(ok, e) { showToast(e.message) })
  }

  // ---------- favourites & your playlists ----------
  readonly property var nowTrack: Model.nowPlaying(store.lib.tracks, player.path, player.mediaTitle)
  property var pickTrack: ({ id: "", title: "" })
  property var pickSource: ({ type: "", id: "", title: "" })
  // Which picker the layer shows: "song" (add to playlist) or "mix" (add to mix).
  property string pickKind: "song"
  property point pickAt: Qt.point(0, 0)
  property bool pickAbove: false

  // The add-to-playlist picker for a track, next to anchor (or centred).
  function pickPlaylists(track, anchor) {
    if (!track || !track.id) return
    pickTrack = track
    pickKind = "song"
    placePicker(anchor)
  }
  // The add-to-mix picker for a language, profile or playlist.
  function pickMixes(source, anchor) {
    if (!source || !source.id) return
    pickSource = source
    pickKind = "mix"
    placePicker(anchor)
  }
  function placePicker(anchor) {
    if (anchor) {
      var top = anchor.mapToItem(bodyScope, anchor.width / 2, 0)
      pickAbove = top.y > bodyScope.height / 2
      pickAt = pickAbove ? top : Qt.point(top.x, top.y + anchor.height)
    } else {
      pickAbove = false
      pickAt = Qt.point(bodyScope.width / 2, bodyScope.height / 2 - 160)
    }
    pickerLayer.visible = true
  }
  function newPlaylist(name) {
    name = String(name || "").trim()
    if (name) quick.run(Model.newPlaylistArgs(name, ""), "Making " + name + "…")
  }

  function openPlaylist(id) {
    navigate("playlist", id)
    var p = store.lib.playlists[id]
    if (p && p.tracks === null) jobs.run(["playlist", "fetch", id], "Fetching playlist…", function() { refreshArt() })
    else quick.run(["art", "--playlist", id], "", function() { refreshArt() })
  }

  function openUser(id) {
    navigate("user", id)
    quick.run(["art", "--user-playlists", id, "--user", id], "", function() { refreshArt() })
  }

  function playPlaylist(id, shuffle, trackId) {
    var args = ["play", id]
    if (shuffle) args.push("--shuffle")
    // "=": video ids can start with "-", which would read as an option.
    if (trackId) args = args.concat(["--track=" + trackId])
    quick.run(args, "Loading…", function(ok) { if (ok) cacheCurrentArt() })
  }

  function playLanguage(language) {
    quick.run(["play", "--lang", language, "--shuffle"], "Starting the " + language + " mix…", function(ok) { if (ok) cacheCurrentArt() })
  }

  // ---------- mixes (the shuffle buttons) ----------
  function playMix(id, title) {
    // Songs not loaded yet may be fetched first: keep that off the quick queue.
    var waiting = store.mixes.some(function(m) { return m.id === id && m.waiting > 0 })
    var runner = waiting ? jobs : quick
    runner.run(Model.playMixArgs(id), "Starting " + (title || "the mix") + "…", function(ok) { if (ok) cacheCurrentArt() })
  }
  function openMix(id) { navigate("mix", id) }
  // Playlist sources may need their songs fetched, so they go through jobs.
  function changeMix(id, source, on, onDone) {
    var runner = on && source.type === "playlist" ? jobs : quick
    runner.run(Model.mixSourceArgs(id, source, on), on ? "Adding " + (source.title || "it") + "…" : "",
      function(ok) { if (onDone) onDone(ok) })
  }
  function newMix(name, source, open) {
    name = String(name || "").trim()
    if (!name) return
    var runner = source && source.type === "playlist" ? jobs : quick
    runner.run(Model.newMixArgs(name, source), "Making " + name + "…", function(ok, e) {
      if (ok && open && e.mix) openMix(e.mix)
    })
  }
  function renameMix(id, name) { quick.run(Model.renameMixArgs(id, name), "Renaming…") }
  function moveMix(id, position) { quick.run(Model.moveMixArgs(id, position), "") }
  function removeMix(id) {
    quick.run(["mix", "remove", id], "Deleting…", function(ok) {
      if (ok && win.view === "mix" && win.arg === id) back()
    })
  }
  function fetchMix(id) { jobs.run(["mix", "fetch", id], "Loading songs…", function() { refreshArt() }) }

  function playUser(id) {
    quick.run(["play", "--user", id, "--shuffle"], "Loading…", function(ok) { if (ok) cacheCurrentArt() })
  }

  function cacheCurrentArt() { artTimer.restart() }

  function savePlaylist(id, saved) {
    jobs.run(["playlist", saved ? "save" : "unsave", id], saved ? "Saving playlist…" : "Removing…", function() { refreshArt() })
  }

  // A profile link adds all of its playlists; a playlist link adds that one.
  function importLink(link, language) {
    var args = ["import", link]
    if (language) args = args.concat(["--lang", language])
    jobs.run(args, "Looking up " + link + " on YouTube…", function(ok, e) {
      refreshArt()
      if (ok && e.user) openUser(e.user)
      else if (ok && e.playlist) openPlaylist(e.playlist)
    })
  }

  function removePlaylist(id) {
    jobs.run(["playlist", "remove", id], "Removing playlist…", function(ok) {
      if (ok && win.view === "playlist" && win.arg === id) back()
    })
  }
  function restorePlaylists(userId) {
    jobs.run(["playlist", "restore", "--user", userId], "Bringing back removed playlists…", function() { refreshArt() })
  }
  function removeSong(playlistId, trackId, onDone) {
    quick.run(["playlist", "remove-songs", "--", playlistId, trackId], "", function(ok) { if (onDone) onDone(ok) })
  }
  function restoreSongs(playlistId) {
    jobs.run(["playlist", "restore-songs", playlistId], "Bringing back removed songs…", function() { refreshArt() })
  }
  function saveAll(userId) { jobs.run(["user", "save-all", userId], "Adding all playlists…", function() { refreshArt() }) }
  function fetchUser(userId) { jobs.run(["user", "fetch", userId], "Fetching songs…", function() { refreshArt() }) }

  function syncUser(id) { jobs.run(["user", "sync", id], "Checking for new playlists…", function() { refreshArt() }) }
  function removeUser(id) { jobs.run(["user", "remove", id], "Unfollowing…", function() { navigate("users") }) }
  function setConfig(key, value) { quick.run(["config", "set", key, typeof value === "string" ? value : JSON.stringify(value)], "") }
  function watchVideo() { quick.run(["watch"], "Opening in Brave…") }

  Timer {
    id: artTimer
    interval: 900
    onTriggered: win.store.refreshArt()
  }
  Timer {
    id: toastTimer
    interval: 3500
    onTriggered: win.toast = ""
  }

  Jobs { id: searchJobs }

  Connections {
    target: win.player
    function onTrackChanged(id) {
      if (id) win.quick.run(["art", "--tracks=" + id], "", function() { win.refreshArt() })
    }
  }

  // ---------- layout ----------
  FocusScope {
    id: bodyScope
    anchors.fill: parent
    focus: true

    Keys.onPressed: function(e) {
      if (search.activeFocus) return
      if (e.key === Qt.Key_Space) { win.player.togglePause(); e.accepted = true }
      else if (e.key === Qt.Key_Slash || (e.key === Qt.Key_F && (e.modifiers & Qt.ControlModifier))) { search.forceActiveFocus(); e.accepted = true }
      else if (e.key === Qt.Key_Backspace || (e.key === Qt.Key_Left && (e.modifiers & Qt.AltModifier))) { win.back(); e.accepted = true }
      else if (e.key === Qt.Key_Right && (e.modifiers & Qt.ControlModifier)) { win.player.next(); e.accepted = true }
      else if (e.key === Qt.Key_Left && (e.modifiers & Qt.ControlModifier)) { win.player.previous(); e.accepted = true }
      else if (e.key === Qt.Key_Escape) {
        if (pickerLayer.visible) pickerLayer.visible = false
        else win.visible = false
        e.accepted = true
      }
    }

    // Sidebar
    Rectangle {
      id: sidebar
      width: 232
      anchors.top: parent.top
      anchors.bottom: nowBar.top
      color: win.pal.surface

      Column {
        anchors.fill: parent
        anchors.margins: 18
        spacing: 4

        Row {
          spacing: 10
          bottomPadding: 18
          Text {
            textFormat: Text.PlainText
            text: "paattu"
            color: win.pal.foreground
            font.family: win.fontFamily
            font.pixelSize: 24
            font.weight: Font.Black
          }
          Text {
            anchors.baseline: parent.children[0].baseline
            textFormat: Text.PlainText
            text: "പാട്ട് · பாட்டு"
            color: win.pal.accent
            font.family: "Noto Sans Malayalam"
            font.pixelSize: 11
          }
        }

        Repeater {
          model: [
            { view: "home", arg: null, glyph: Model.GLYPH_HOME, label: "Home" },
            { view: "search", arg: null, glyph: Model.GLYPH_SEARCH, label: "Search" },
            { view: "mixes", arg: null, glyph: Model.GLYPH_SHUFFLE, label: "Mixes" },
            { view: "language", arg: "Malayalam", glyph: "മ", label: "Malayalam" },
            { view: "language", arg: "Tamil", glyph: "த", label: "Tamil" },
            { view: "playlist", arg: Model.FAVOURITES, glyph: Model.GLYPH_HEART, label: "Favourites" },
            { view: "playlist", arg: Model.SAVED, glyph: Model.GLYPH_SAVED, label: "Saved songs" },
            { view: "users", arg: null, glyph: Model.GLYPH_USER, label: "YouTube users" },
            { view: "queue", arg: null, glyph: Model.GLYPH_QUEUE, label: "Queue" },
            { view: "settings", arg: null, glyph: Model.GLYPH_PALETTE, label: "Look & settings" }
          ]

          Rectangle {
            id: navItem
            required property var modelData
            readonly property bool selected: win.view === modelData.view
              && (modelData.arg === null || win.arg === modelData.arg)
              || (modelData.view === "users" && win.view === "user")
              || (modelData.view === "mixes" && win.view === "mix")
            width: sidebar.width - 36
            height: 38
            radius: 8
            color: selected ? Qt.rgba(win.pal.accent.r, win.pal.accent.g, win.pal.accent.b, 0.16)
              : navMouse.containsMouse ? Qt.rgba(win.pal.foreground.r, win.pal.foreground.g, win.pal.foreground.b, 0.06) : "transparent"

            Row {
              anchors.verticalCenter: parent.verticalCenter
              x: 12
              spacing: 12
              Text {
                width: 20
                horizontalAlignment: Text.AlignHCenter
                textFormat: Text.PlainText
                text: navItem.modelData.glyph
                color: navItem.selected ? win.pal.accent : win.pal.muted
                font.family: navItem.modelData.view === "language"
                  ? (navItem.modelData.arg === "Tamil" ? "Noto Sans Tamil" : "Noto Sans Malayalam") : win.fontFamily
                font.pixelSize: 16
              }
              Text {
                textFormat: Text.PlainText
                text: navItem.modelData.label
                color: navItem.selected ? win.pal.foreground : win.pal.muted
                font.family: win.fontFamily
                font.pixelSize: 13
                font.bold: navItem.selected
              }
            }

            MouseArea {
              id: navMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: win.navigate(navItem.modelData.view, navItem.modelData.arg)
            }
          }
        }
      }

      // Library size and background work.
      Column {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 18
        spacing: 6

        Text {
          width: parent.width
          visible: win.jobs.busy || win.jobs.lastError !== ""
          textFormat: Text.PlainText
          text: win.jobs.busy ? win.jobs.message + (win.jobs.total ? "  " + win.jobs.step + "/" + win.jobs.total : "") : win.jobs.lastError
          color: win.jobs.busy ? win.pal.accent : Color.urgent
          font.family: win.fontFamily
          font.pixelSize: 11
          wrapMode: Text.WordWrap
          maximumLineCount: 3
          elide: Text.ElideRight
        }
        Text {
          width: parent.width
          textFormat: Text.PlainText
          text: Model.plural(win.store.shelf.counts.saved || 0, "playlist") + " · "
            + Model.formatCount(win.store.shelf.counts.tracks || 0) + " songs\n"
            + Model.plural(win.store.shelf.counts.users || 0, "YouTube user")
          color: win.pal.muted
          font.family: win.fontFamily
          font.pixelSize: 11
          lineHeight: 1.2
        }
      }
    }

    // Main
    Item {
      id: main
      anchors.left: sidebar.right
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.bottom: nowBar.top

      Row {
        id: topBar
        x: 28
        y: 18
        spacing: 10
        height: 36

        GlyphButton {
          anchors.verticalCenter: parent.verticalCenter
          glyph: "\u{F0141}"  // md-chevron_left
          size: 32
          color: win.pal.foreground
          fontFamily: win.fontFamily
          enabled: win.history.length > 0
          onClicked: win.back()
        }

        Rectangle {
          anchors.verticalCenter: parent.verticalCenter
          width: Math.min(420, main.width - 300)
          height: 36
          radius: 18
          color: Qt.rgba(win.pal.foreground.r, win.pal.foreground.g, win.pal.foreground.b, search.activeFocus ? 0.10 : 0.06)
          border.width: search.activeFocus ? 1 : 0
          border.color: win.pal.accent

          Text {
            id: searchGlyph
            x: 14
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: Model.GLYPH_SEARCH
            color: win.pal.muted
            font.family: win.fontFamily
            font.pixelSize: 15
          }

          TextInput {
            id: search
            anchors.left: searchGlyph.right
            anchors.leftMargin: 10
            anchors.right: onlineButton.visible ? onlineButton.left : parent.right
            anchors.rightMargin: onlineButton.visible ? 4 : 14
            anchors.verticalCenter: parent.verticalCenter
            color: win.pal.foreground
            selectionColor: win.pal.accent
            font.family: win.fontFamily
            font.pixelSize: 13
            clip: true
            onTextChanged: {
              win.query = text
              if (text.length > 0 && win.view !== "search") win.navigate("search")
              else if (text.length === 0 && win.view === "search") win.back()
            }
            // Enter searches JioSaavn, YouTube and SoundCloud (or looks up a link).
            onAccepted: win.searchOnline(text)
            Keys.onEscapePressed: { text = ""; focus = false }

            Text {
              anchors.fill: parent
              visible: !search.text
              textFormat: Text.PlainText
              text: search.activeFocus ? "A song, film or singer, then Enter to search online. Or paste a link."
                : "Search songs, films, singers…  ( / )"
              color: win.pal.muted
              font: search.font
              elide: Text.ElideRight
              verticalAlignment: Text.AlignVCenter
            }
          }
          GlyphButton {
            id: onlineButton
            anchors.right: parent.right
            anchors.rightMargin: 4
            anchors.verticalCenter: parent.verticalCenter
            visible: search.text.trim() !== ""
            glyph: Model.isLink(search.text) ? Model.GLYPH_LINK : Model.GLYPH_WEB
            size: 30
            color: win.pal.accent
            fontFamily: win.fontFamily
            tooltip: Model.isLink(search.text) ? "Find the songs at this link (Enter)"
              : "Search JioSaavn, YouTube and SoundCloud (Enter)"
            onClicked: win.searchOnline(search.text)
          }
        }

        Chip {
          anchors.verticalCenter: parent.verticalCenter
          text: "Add from YouTube"
          glyph: Model.GLYPH_ADD
          textColor: win.pal.foreground
          accent: win.pal.accent
          selected: true
          fontSize: 12
          fontFamily: win.fontFamily
          onClicked: win.navigate("add")
        }
      }

      Loader {
        id: page
        anchors.top: topBar.bottom
        anchors.topMargin: 8
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        sourceComponent: win.view === "playlist" ? playlistPage
          : win.view === "users" || win.view === "user" ? usersPage
          : win.view === "queue" ? queuePage
          : win.view === "settings" ? settingsPage
          : win.view === "search" ? searchPage
          : win.view === "mixes" ? mixesPage
          : win.view === "mix" ? mixPage
          : homePage
      }
    }

    NowPlayingBar {
      id: nowBar
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      app: win
    }

    Rectangle {
      anchors.horizontalCenter: main.horizontalCenter
      anchors.bottom: nowBar.top
      anchors.bottomMargin: 12
      visible: win.toast !== ""
      width: Math.min(toastText.implicitWidth + 32, main.width - 40)
      height: 36
      radius: 18
      color: Qt.tint(win.pal.surface, Qt.rgba(win.pal.foreground.r, win.pal.foreground.g, win.pal.foreground.b, 0.08))
      border.width: 1
      border.color: Qt.rgba(win.pal.foreground.r, win.pal.foreground.g, win.pal.foreground.b, 0.12)
      Text {
        id: toastText
        anchors.centerIn: parent
        width: parent.width - 32
        horizontalAlignment: Text.AlignHCenter
        textFormat: Text.PlainText
        text: win.toast
        color: win.pal.foreground
        font.family: win.fontFamily
        font.pixelSize: 12
        elide: Text.ElideRight
      }
    }

    // Add to playlist: floats over everything; a click outside closes it.
    Item {
      id: pickerLayer
      anchors.fill: parent
      visible: false
      z: 100

      MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
        onPressed: pickerLayer.visible = false
        onWheel: function(e) { e.accepted = true }
      }

      PlaylistPicker {
        id: picker
        visible: win.pickKind === "song"
        store: win.store
        jobs: win.quick
        videoId: win.pickTrack.id || ""
        songTitle: win.pickTrack.title || win.pickTrack.rawTitle || ""
        canType: true
        background: Qt.tint(win.pal.surface, Qt.rgba(win.pal.foreground.r, win.pal.foreground.g, win.pal.foreground.b, 0.03))
        foreground: win.pal.foreground
        muted: win.pal.muted
        accent: win.pal.accent
        fontFamily: win.fontFamily
        maxHeight: parent.height - 24
        x: Math.max(12, Math.min(parent.width - width - 12, win.pickAt.x - width / 2))
        y: Math.max(12, Math.min(parent.height - height - 12, win.pickAbove ? win.pickAt.y - height - 8 : win.pickAt.y + 8))
        onClosed: pickerLayer.visible = false
      }

      MixPicker {
        visible: win.pickKind === "mix"
        app: win
        source: win.pickSource
        maxHeight: parent.height - 24
        x: Math.max(12, Math.min(parent.width - width - 12, win.pickAt.x - width / 2))
        y: Math.max(12, Math.min(parent.height - height - 12, win.pickAbove ? win.pickAt.y - height - 8 : win.pickAt.y + 8))
        onClosed: pickerLayer.visible = false
      }
    }
  }

  Component { id: homePage; HomePage { app: win; language: win.view === "language" ? win.arg : "" } }
  Component { id: usersPage; UsersPage { app: win; userId: win.view === "user" ? win.arg : "" } }
  Component { id: playlistPage; PlaylistPage { app: win; playlistId: win.arg || "" } }
  Component { id: queuePage; QueuePage { app: win } }
  Component { id: settingsPage; SettingsPage { app: win } }
  Component { id: searchPage; SearchPage { app: win } }
  Component { id: mixesPage; MixesPage { app: win } }
  Component { id: mixPage; MixPage { app: win; mixId: win.view === "mix" ? win.arg : "" } }
}
