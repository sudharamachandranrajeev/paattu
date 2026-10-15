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

  // Navigation: home | playing | language | mixes | mix | users | user | playlist | queue | settings | search
  // | collection (an album, singer or playlist from a search; arg: the result)
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
  // Browsing (`paattu browse search`): the query, the tab showing (a kind, or
  // "library") and a feed per kind that grows a page at a time.
  property var browse: ({ query: "", kind: "song", feeds: ({}) })
  property int browseSerial: 0
  // How far down the results were, for coming back from an album.
  property real searchScroll: 0
  // Suggestions for what's being typed (`paattu browse suggest`).
  property var suggestions: ({ query: "", items: [] })
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
    if (!Model.isLink(text)) {
      startBrowse(text)
      return
    }
    online = { query: text, results: [], errors: ({}), busy: true, error: "" }
    searchJobs.run(Model.searchArgs(text, []), "", function(ok, e) {
      if (win.online.query !== text) return  // a newer search took over
      win.online = { query: text, results: ok && e.results ? e.results : [], errors: ok && e.errors ? e.errors : ({}),
        busy: false, error: ok ? "" : (e.message || "The search didn't work") }
      win.store.refreshArt()
    })
  }

  // ---------- browse: songs, albums, singers and playlists ----------
  function newFeed() {
    return { items: [], seen: ({}), next: null, pages: 0, busy: false, done: false, errors: ({}), error: "" }
  }
  function setFeed(kind, changes) {
    var feeds = Object.assign({}, browse.feeds)
    feeds[kind] = Object.assign({}, feeds[kind] || newFeed(), changes)
    browse = Object.assign({}, browse, { feeds: feeds })
  }
  function startBrowse(text) {
    browseSerial++
    var kind = browse.kind === "library" ? "song" : (browse.kind || "song")
    browse = { query: text, kind: kind, feeds: ({}) }
    searchScroll = 0
    suggestions = { query: "", items: [] }
    loadMore(kind)
  }
  function showKind(kind) {
    browse = Object.assign({}, browse, { kind: kind })
    searchScroll = 0
    if (browse.query && kind !== "library" && !browse.feeds[kind]) loadMore(kind)
  }
  // The next page of a kind (the first, if none yet).
  function loadMore(kind) {
    var query = browse.query
    var feed = browse.feeds[kind] || newFeed()
    if (!query || feed.busy || feed.done) return
    setFeed(kind, { busy: true })
    var serial = browseSerial
    browseJobs.run(Model.browseSearchArgs(query, kind, feed.pages ? feed.next : null), "", function(ok, e) {
      if (serial !== win.browseSerial) return  // a newer search took over
      var now = win.browse.feeds[kind] || win.newFeed()
      var seen = Object.assign({}, now.seen)
      var fresh = ok ? Model.freshResults(e.results, seen) : []
      var next = ok && e.next && Object.keys(e.next).length ? e.next : null
      win.setFeed(kind, { items: now.items.concat(fresh), seen: seen, next: next, pages: now.pages + 1, busy: false,
        done: !next, errors: now.pages === 0 && ok ? (e.errors || ({})) : now.errors,
        error: ok || now.pages > 0 ? "" : (e.message || "The search didn't work") })
      win.store.refreshArt()
    })
  }

  // Suggestions a moment after typing stops.
  function suggestSoon() { suggestTimer.restart() }
  function suggestNow() {
    var q = search.text.trim()
    if (!q || Model.isLink(q) || q === browse.query) return
    if (suggestJobs.busy) {
      suggestTimer.restart()
      return
    }
    suggestJobs.run(Model.suggestArgs(q), "", function(ok, e) {
      if (ok && search.text.trim().indexOf(q) === 0) win.suggestions = { query: q, items: e.suggestions || [] }
    })
  }
  // A suggestion: a phrase searches; a song plays; anything else opens.
  function openSuggestion(item) {
    if (item.type === "query") searchOnline(item.title)
    else if (item.type === "song") playSong({ id: item.url })
    else openResult(item)
  }

  function openResult(item) { if (item && item.type) navigate("collection", item) }
  // An album's or playlist's songs, or a page of a singer's (onDone(ok, event)).
  function loadCollection(item, page, onDone) {
    openJobs.run(Model.openArgs(item, page), "", function(ok, e) {
      win.store.refreshArt()
      onDone(ok, e)
    })
  }
  // Play songs found by browse, from index on.
  function playFound(tracks, index, shuffle, title, source) {
    if (!tracks || tracks.length === 0) return
    quick.run(Model.browsePlayArgs(tracks, index, shuffle, title, source), "Loading…", function(ok, e) {
      if (ok) cacheCurrentArt()
      else showToast(e.message)
    })
  }
  function saveSongs(tracks) {
    if (!tracks || tracks.length === 0) return
    quick.run(Model.saveSongsArgs(tracks), "", function(ok, e) { showToast(e.message) })
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
  readonly property var nowTrack: Model.nowPlaying(store.tracks, player.path, player.mediaTitle)
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

  // ---------- the radio and playlists made for you ----------
  // Songs like the one playing, without end; or the radio off again.
  function toggleRadio() {
    var on = !player.radioOn
    if (on && !player.path) return
    var runner = on ? jobs : quick
    runner.run(Model.radioArgs(on, player.path), on ? "Starting the radio…" : "", function(ok, e) {
      if (ok && on) cacheCurrentArt()
      showToast(e.message)
    })
  }
  // The day's, week's or month's playlist (refresh: a new one).
  function playMade(kind, title, refresh) {
    jobs.run(Model.madeArgs(kind, refresh), "Making your " + title + "…", function(ok, e) {
      if (ok) cacheCurrentArt()
      else showToast(e.message)
    })
  }
  // A playlist from a description, played (and saved as a playlist named saveAs).
  function describePlaylist(text, saveAs) {
    text = String(text || "").trim()
    if (!text) return
    jobs.run(Model.describeArgs(text, saveAs), "Finding songs for " + text + "…", function(ok, e) {
      if (ok) cacheCurrentArt()
      if (!ok) showToast(e.message)
      else if (saveAs) showToast("Saved as " + saveAs)
    })
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
  // Their own runners: a page of results never waits behind an album opening.
  Jobs { id: browseJobs }
  Jobs { id: suggestJobs }
  Jobs { id: openJobs }
  Timer {
    id: suggestTimer
    interval: 250
    onTriggered: win.suggestNow()
  }

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

    Backdrop {
      anchors.fill: parent
      pal: win.pal
    }

    // Now Playing: the song's video behind everything, blurred and silent.
    // Loaded by name, so without Qt Multimedia only the video is missing.
    Loader {
      anchors.fill: parent
      active: win.view === "playing" && win.store.config.videoBackground !== false && GraphicsInfo.api !== GraphicsInfo.Software
      opacity: 0.55
      Component.onCompleted: setSource(Qt.resolvedUrl("VideoBackdrop.qml"), { app: win })
    }

    // Sidebar
    Glass {
      id: sidebar
      pal: win.pal
      x: 12
      width: 220
      anchors.top: parent.top
      anchors.topMargin: 12
      anchors.bottom: nowBar.top
      anchors.bottomMargin: 10
      radius: 28

      Column {
        anchors.fill: parent
        anchors.margins: 16
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
            { view: "playing", arg: null, glyph: Model.GLYPH_NOTE, label: "Now playing" },
            { view: "search", arg: null, glyph: Model.GLYPH_SEARCH, label: "Search" },
            { view: "mixes", arg: null, glyph: Model.GLYPH_SHUFFLE, label: "Mixes" },
            { view: "language", arg: "Malayalam", glyph: "മ", label: "Malayalam" },
            { view: "language", arg: "Tamil", glyph: "த", label: "Tamil" },
            { view: "playlist", arg: Model.FAVOURITES, glyph: Model.GLYPH_HEART, label: "Favourites" },
            { view: "playlist", arg: Model.SAVED, glyph: Model.GLYPH_SAVED, label: "Saved songs" },
            { view: "users", arg: null, glyph: Model.GLYPH_USER, label: "YouTube users" },
            { view: "queue", arg: null, glyph: Model.GLYPH_QUEUE, label: "Queue" },
            { view: "sound", arg: null, glyph: Model.GLYPH_EQUALIZER, label: "Sound" },
            { view: "settings", arg: null, glyph: Model.GLYPH_PALETTE, label: "Look & settings" }
          ]

          Rectangle {
            id: navItem
            required property var modelData
            readonly property bool selected: win.view === modelData.view
              && (modelData.arg === null || win.arg === modelData.arg)
              || (modelData.view === "users" && win.view === "user")
              || (modelData.view === "mixes" && win.view === "mix")
              || (modelData.view === "search" && win.view === "collection")
            width: sidebar.width - 32
            height: 38
            radius: height / 2
            color: selected ? Qt.rgba(win.pal.accent.r, win.pal.accent.g, win.pal.accent.b, 0.2)
              : navMouse.containsMouse ? Qt.rgba(win.pal.foreground.r, win.pal.foreground.g, win.pal.foreground.b, 0.07) : "transparent"
            border.width: selected ? 1 : 0
            border.color: Qt.rgba(win.pal.accent.r, win.pal.accent.g, win.pal.accent.b, 0.45)

            Row {
              anchors.verticalCenter: parent.verticalCenter
              x: 14
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
      anchors.leftMargin: 4
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.bottom: nowBar.top

      Row {
        id: topBar
        x: 24
        y: 16
        spacing: 10
        height: 40

        GlyphButton {
          anchors.verticalCenter: parent.verticalCenter
          glyph: "\u{F0141}"  // md-chevron_left
          size: 32
          color: win.pal.foreground
          fontFamily: win.fontFamily
          enabled: win.history.length > 0
          onClicked: win.back()
        }

        Glass {
          anchors.verticalCenter: parent.verticalCenter
          pal: win.pal
          width: Math.min(440, main.width - 300)
          height: 40
          radius: 20
          hovered: search.activeFocus
          border.color: search.activeFocus ? win.pal.accent
            : Qt.rgba(win.pal.foreground.r, win.pal.foreground.g, win.pal.foreground.b, 0.11)

          Text {
            id: searchGlyph
            x: 16
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
              win.suggestSoon()
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
        sourceComponent: win.view === "playing" ? playingPage
          : win.view === "playlist" ? playlistPage
          : win.view === "users" || win.view === "user" ? usersPage
          : win.view === "queue" ? queuePage
          : win.view === "settings" ? settingsPage
          : win.view === "sound" ? soundPage
          : win.view === "search" ? searchPage
          : win.view === "collection" ? collectionPage
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
      anchors.margins: 12
      app: win
    }

    Rectangle {
      anchors.horizontalCenter: main.horizontalCenter
      anchors.bottom: nowBar.top
      anchors.bottomMargin: 12
      visible: win.toast !== ""
      width: Math.min(toastText.implicitWidth + 32, main.width - 40)
      height: 40
      radius: 20
      color: Qt.tint(win.pal.surface, Qt.rgba(win.pal.foreground.r, win.pal.foreground.g, win.pal.foreground.b, 0.08))
      border.width: 1
      border.color: Qt.rgba(win.pal.foreground.r, win.pal.foreground.g, win.pal.foreground.b, 0.14)
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

  Component { id: playingPage; NowPlayingPage { app: win } }
  Component { id: homePage; HomePage { app: win; language: win.view === "language" ? win.arg : "" } }
  Component { id: usersPage; UsersPage { app: win; userId: win.view === "user" ? win.arg : "" } }
  Component { id: playlistPage; PlaylistPage { app: win; playlistId: win.arg || "" } }
  Component { id: queuePage; QueuePage { app: win } }
  Component { id: settingsPage; SettingsPage { app: win } }
  Component { id: soundPage; SoundPage { app: win } }
  Component { id: searchPage; SearchPage { app: win } }
  Component { id: collectionPage; CollectionPage { app: win; item: win.view === "collection" && win.arg ? win.arg : ({}) } }
  Component { id: mixesPage; MixesPage { app: win } }
  Component { id: mixPage; MixPage { app: win; mixId: win.view === "mix" ? win.arg : "" } }
}
