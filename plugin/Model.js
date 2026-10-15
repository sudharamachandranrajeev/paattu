.pragma library

// Pure helpers for Paattu (bar control, desktop widget, app window). Kept free
// of QML so they can be unit tested with node: tests/model.test.mjs in the Paattu repo

var GLYPH_PLAY = "\u{F040A}"        // md-play
var GLYPH_PAUSE = "\u{F03E4}"       // md-pause
var GLYPH_NEXT = "\u{F04AD}"        // md-skip_next
var GLYPH_PREV = "\u{F04AE}"        // md-skip_previous
var GLYPH_SHUFFLE = "\u{F049D}"     // md-shuffle_variant
var GLYPH_REPEAT = "\u{F0456}"      // md-repeat
var GLYPH_REPEAT_ONE = "\u{F0458}"  // md-repeat_once
var GLYPH_REPEAT_OFF = "\u{F0457}"  // md-repeat_off
var GLYPH_NOTE = "\u{F075A}"        // md-music_note
var GLYPH_ALBUM = "\u{F0025}"       // md-album
var GLYPH_PLAYLIST = "\u{F0CB8}"    // md-playlist_music
var GLYPH_USER = "\u{F0803}"        // md-account_music
var GLYPH_USER_ADD = "\u{F0014}"    // md-account_plus
var GLYPH_HOME = "\u{F02DC}"        // md-home
var GLYPH_QUEUE = "\u{F0CB9}"       // md-playlist_play
var GLYPH_SETTINGS = "\u{F0493}"    // md-cog
var GLYPH_SEARCH = "\u{F0349}"      // md-magnify
var GLYPH_VOLUME = "\u{F057E}"      // md-volume_high
var GLYPH_VOLUME_LOW = "\u{F057F}"  // md-volume_medium
var GLYPH_MUTE = "\u{F0581}"        // md-volume_off
var GLYPH_VIDEO = "\u{F05C3}"       // md-youtube
var GLYPH_OPEN = "\u{F03CC}"        // md-open_in_new
var GLYPH_ADD = "\u{F0415}"         // md-plus
var GLYPH_CHECK = "\u{F012C}"       // md-check
var GLYPH_CLOSE = "\u{F0156}"       // md-close
var GLYPH_REFRESH = "\u{F0450}"     // md-refresh
var GLYPH_PALETTE = "\u{F03D8}"     // md-palette
var GLYPH_LIBRARY = "\u{F0331}"     // md-library
var GLYPH_LINK = "\u{F0337}"        // md-link_variant
var GLYPH_DELETE = "\u{F09E7}"      // md-delete_outline
var GLYPH_RESTORE = "\u{F099B}"     // md-restore
var GLYPH_DOWNLOAD = "\u{F01DA}"    // md-download
var GLYPH_HEART = "\u{F02D1}"       // md-heart
var GLYPH_HEART_OUTLINE = "\u{F02D5}"  // md-heart_outline
var GLYPH_PLAYLIST_ADD = "\u{F0412}"  // md-playlist_plus
var GLYPH_EDIT = "\u{F03EB}"        // md-pencil
var GLYPH_SAVED = "\u{F00C2}"       // md-bookmark_music
var GLYPH_SAVE = "\u{F1379}"        // md-bookmark_music_outline
var GLYPH_PLAY_NEXT = "\u{F0411}"   // md-playlist_play
var GLYPH_WEB = "\u{F059F}"         // md-web
var GLYPH_RADIO = "\u{F0439}"       // md-radio
var GLYPH_MADE = "\u{F0674}"        // md-creation

var LANGUAGES = ["Malayalam", "Tamil"]
var STYLES = ["vinyl", "card", "minimal"]
var POSITIONS = ["top-left", "top", "top-right", "left", "center", "right", "bottom-left", "bottom", "bottom-right"]

// ---------------------------------------------------------------- format

function formatTime(seconds) {
  var s = Math.max(0, Math.floor(Number(seconds) || 0))
  var h = Math.floor(s / 3600)
  var m = Math.floor(s / 60) % 60
  var sec = s % 60
  var two = function(n) { return (n < 10 ? "0" : "") + n }
  return h > 0 ? h + ":" + two(m) + ":" + two(sec) : m + ":" + two(sec)
}

function formatCount(n) {
  n = Number(n) || 0
  if (n >= 1e6) return (n / 1e6).toFixed(n >= 1e7 ? 0 : 1).replace(/\.0$/, "") + "M"
  if (n >= 1e3) return (n / 1e3).toFixed(n >= 1e4 ? 0 : 1).replace(/\.0$/, "") + "K"
  return String(n)
}

function plural(n, word) {
  return n + " " + word + (n === 1 ? "" : "s")
}

// ---------------------------------------------------------------- tracks

// A YouTube video id from a watch / youtu.be / shorts link or a bare id.
function videoId(path) {
  var text = String(path || "").trim()
  var m = text.match(/^([\w-]{11})$/) || text.match(/[?&]v=([\w-]{11})/) || text.match(/youtu\.be\/([\w-]{11})/)
    || text.match(/\/(?:shorts|embed|live)\/([\w-]{11})/)
  return m ? m[1] : ""
}

// Songs from other sites (JioSaavn, SoundCloud, any link) are keyed by their
// link: host + path (+ query) made filename-safe, never shaped like a video
// id. Mirrors sources.track_id in the CLI; tests/track_ids.json holds both.
var LINK_RE = /^https?:\/\/([^\/?#]+)([^?#]*)(?:\?([^#]*))?/i
var VIDEO_ID_RE = /^[\w-]{11}$/

function isLink(text) { return LINK_RE.test(String(text || "").trim()) }
function isVideoId(id) { return VIDEO_ID_RE.test(String(id || "")) }

function linkHost(url) {
  var m = String(url || "").trim().match(LINK_RE)
  if (!m) return ""
  var host = m[1].toLowerCase()
  return host.indexOf("www.") === 0 ? host.slice(4) : host
}

function isYoutube(url) { return /(^|\.)(youtube\.com|youtu\.be|youtube-nocookie\.com)$/.test(linkHost(url)) }

function trackId(path) {
  var text = String(path || "").trim()
  var m = text.match(LINK_RE)
  if (!m || isYoutube(text)) return videoId(text)
  var query = m[3] || ""
  var key = (linkHost(text) + m[2].replace(/\/+$/, "") + (query ? "?" + query : ""))
    .replace(/[^A-Za-z0-9._-]+/g, "_").slice(0, 150)
  return isVideoId(key) ? "link." + key : key
}

// ---------------------------------------------------------------- sites and quality

var SITES = { jiosaavn: "JioSaavn", youtube: "YouTube", soundcloud: "SoundCloud" }
var SEARCH_SITES = ["jiosaavn", "youtube", "soundcloud"]
var LOSSLESS = ["flac", "alac", "wav", "aiff", "ape", "wavpack"]
var CODECS = { aac: "AAC", opus: "Opus", mp3: "MP3", vorbis: "Vorbis", flac: "FLAC", alac: "ALAC", wav: "WAV",
  aiff: "AIFF", ape: "APE", wavpack: "WavPack" }

function siteName(site) { return SITES[site] || site || "" }

// Where a song plays from: jiosaavn, youtube, soundcloud or another host.
function siteOf(track) {
  if (!track) return ""
  if (track.site) return track.site
  return track.url ? linkHost(track.url) : "youtube"
}

// A track's own quality, from the site: "Lossless", "320 kbps" or "".
function qualityLabel(track) {
  if (!track) return ""
  if (LOSSLESS.indexOf(String(track.codec || "").toLowerCase()) !== -1) return "Lossless"
  return track.quality ? track.quality + " kbps" : ""
}

// Streams are encoded at a few standard rates; mpv measures a little under.
function snapKbps(kbps) {
  var steps = [64, 96, 128, 160, 192, 256, 320]
  for (var i = 0; i < steps.length; i++)
    if (Math.abs(kbps - steps[i]) <= steps[i] * 0.03) return steps[i]
  return Math.round(kbps)
}

// What's playing, from mpv: codec (audio-codec-name), demux (the container's
// bit rate), live (measured bit rate), rate (sample rate). "AAC · 320 kbps",
// "Opus · ~130 kbps", "FLAC · Lossless · 96 kHz".
function streamQuality(q) {
  var codec = String(q && q.codec || "").toLowerCase()
  if (!codec) return ""
  if (codec.indexOf("pcm") === 0) codec = "wav"
  var name = CODECS[codec] || codec.toUpperCase()
  if (LOSSLESS.indexOf(codec) !== -1)
    return name + " · Lossless" + (q.rate > 48000 ? " · " + Math.round(q.rate / 100) / 10 + " kHz" : "")
  if (q.demux > 0) return name + " · " + snapKbps(q.demux / 1000) + " kbps"
  if (q.live > 0) return name + " · ~" + Math.round(q.live / 10000) * 10 + " kbps"
  return name
}

// The engine titles each entry "Song · Movie" (force-media-title).
function splitMediaTitle(mediaTitle) {
  var text = String(mediaTitle || "")
  var at = text.indexOf(" · ")
  if (at < 0) return { title: text, movie: "" }
  return { title: text.slice(0, at), movie: text.slice(at + 3) }
}

// What's playing, from the library when we know the song, else from mpv.
function nowPlaying(tracks, path, mediaTitle) {
  var id = trackId(path)
  var known = tracks && id ? tracks[id] : null
  if (known) {
    return { id: id, title: known.title || known.rawTitle || "", movie: known.movie || "",
      credits: known.credits || [], channel: known.channel || "", duration: known.duration || 0, known: true }
  }
  var split = splitMediaTitle(mediaTitle)
  return { id: id, title: split.title, movie: split.movie, credits: [], channel: "", duration: 0, known: false }
}

function subtitle(track) {
  if (!track) return ""
  var parts = []
  if (track.movie) parts.push(track.movie)
  if (track.credits && track.credits.length) parts.push(track.credits[0])
  else if (track.channel) parts.push(track.channel)
  return parts.join(" · ")
}

// ---------------------------------------------------------------- art

function artPath(cacheDir, kind, id) {
  return id ? cacheDir + "/art/" + kind + "/" + id + ".jpg" : ""
}

// hqdefault.jpg is 480x360 with the 16:9 frame letterboxed in the middle; the
// square in the centre is clean cover art. Square art (JioSaavn, SoundCloud,
// Bandcamp) is already a cover.
function coverClip(width, height) {
  if (!width || !height) return null
  if (Math.abs(width - height) <= 2) return { x: 0, y: 0, width: width, height: height }
  var frameH = Math.round(width * 9 / 16)
  var top = height > frameH ? Math.round((height - frameH) / 2) : 0
  var side = Math.min(frameH, height)
  return { x: Math.round((width - side) / 2), y: top, width: side, height: side }
}

// The whole picture of a cover, without a YouTube thumbnail's letterbox
// bars (Now Playing's full picture).
function frameClip(width, height) {
  if (!width || !height) return null
  var frameH = Math.round(width * 9 / 16)
  if (Math.abs(width - height) <= 2 || height <= frameH) return { x: 0, y: 0, width: width, height: height }
  return { x: 0, y: Math.round((height - frameH) / 2), width: width, height: frameH }
}

// ---------------------------------------------------------------- library

// A language's saved playlists; `distinct` takes at most one per owner.
function shelfFor(shelf, language, limit, distinct) {
  var list = shelf && shelf.languages && shelf.languages[language] ? shelf.languages[language] : []
  if (distinct) {
    var seen = {}
    list = list.filter(function(p) {
      if (seen[p.owner]) return false
      seen[p.owner] = true
      return true
    })
  }
  return limit ? list.slice(0, limit) : list
}

// Second line for a playlist: "Most played · 200 songs" for auto playlists
// (their title already names the owner), else "Owner · 42 songs".
function playlistDetail(p) {
  var count = p && p.count ? " · " + plural(p.count, "song") : ""
  if (p && p.auto) return (String(p.title).indexOf("New releases") !== -1 ? "New releases" : "Most played") + count
  return (p ? p.ownerName || "" : "") + count
}

// A followed user's playlists: saved, not saved, saved but songs not fetched
// yet (big profiles load them on demand), and removed from the app.
function userStats(lib, userId) {
  var out = { listed: 0, saved: 0, unsaved: 0, waiting: 0, removed: 0 }
  var user = lib && lib.users ? lib.users[userId] : null
  if (!user) return out
  var ids = user.playlists || []
  for (var i = 0; i < ids.length; i++) {
    var p = lib.playlists[ids[i]]
    if (!p) continue
    out.listed++
    if (!p.saved) out.unsaved++
    else {
      out.saved++
      if (p.tracks === null || p.tracks === undefined) out.waiting++
    }
  }
  var removed = lib.removed || {}
  for (var id in removed)
    if (removed[id] && removed[id].owner === userId) out.removed++
  return out
}

// ---------------------------------------------------------------- your own playlists

var FAVOURITES = "paattu-favourites"
var SAVED = "paattu-saved"

// Favourites and Saved songs first (listed even before their first song),
// then the playlists you made. Entries come from shelf.json:
// {id, title, count, favourites, saved, tracks}.
function ownPlaylists(shelf) {
  var mine = shelf && shelf.mine ? shelf.mine : []
  var fav = null
  var saved = null
  var rest = []
  for (var i = 0; i < mine.length; i++) {
    if (mine[i].id === FAVOURITES) fav = mine[i]
    else if (mine[i].id === SAVED) saved = mine[i]
    else rest.push(mine[i])
  }
  return [fav || { id: FAVOURITES, title: "Favourites", count: 0, favourites: true, tracks: [] },
          saved || { id: SAVED, title: "Saved songs", count: 0, saved: true, tracks: [] }].concat(rest)
}

// Song ids in one of your playlists, as a lookup object.
function songSet(shelf, playlistId) {
  var out = {}
  var mine = shelf && shelf.mine ? shelf.mine : []
  for (var i = 0; i < mine.length; i++) {
    if (mine[i].id !== playlistId) continue
    for (var j = 0; j < mine[i].tracks.length; j++) out[mine[i].tracks[j]] = true
  }
  return out
}
function favouriteSet(shelf) { return songSet(shelf, FAVOURITES) }
// Favourites and Saved songs: always there, can't be renamed or deleted.
function isBuiltin(playlistId) { return playlistId === FAVOURITES || playlistId === SAVED }
function ownGlyph(playlistId) {
  return playlistId === FAVOURITES ? GLYPH_HEART : playlistId === SAVED ? GLYPH_SAVED : GLYPH_PLAYLIST
}
function savedSet(shelf) { return songSet(shelf, SAVED) }

function contains(entry, videoId) {
  return !!(entry && entry.tracks && videoId && entry.tracks.indexOf(videoId) !== -1)
}

// Where a playlist's cover comes from: your own playlists show their first
// song's art ({kind: "v"}), YouTube ones their own ({kind: "p"}).
function coverOf(playlist) {
  if (!playlist) return { kind: "p", id: "" }
  if (playlist.local || String(playlist.id).indexOf("paattu-") === 0)
    return { kind: "v", id: playlist.tracks && playlist.tracks.length ? playlist.tracks[0] : "" }
  return { kind: "p", id: playlist.id }
}

// CLI arguments. "--" before the ids: video ids can start with "-".
function favouriteArgs(videoId, on) {
  return on ? ["fav", "--", videoId] : ["fav", "--remove", "--", videoId]
}
function saveArgs(id, on) {
  return on ? ["save", "--", id] : ["save", "--remove", "--", id]
}
function playlistSongArgs(playlistId, videoId, on) {
  if (playlistId === FAVOURITES) return favouriteArgs(videoId, on)
  if (playlistId === SAVED) return saveArgs(videoId, on)
  return ["playlist", on ? "add-songs" : "remove-songs", "--", playlistId, videoId]
}
function newPlaylistArgs(name, videoId) {
  return ["playlist", "new", "--", name].concat(videoId ? [videoId] : [])
}

// Search JioSaavn, YouTube and SoundCloud (or look up a pasted link); sites
// empty means the ones in the config.
function searchArgs(query, sites) {
  return ["search"].concat((sites || []).map(function(s) { return "--site=" + s })).concat(["--", String(query)])
}
// One song: from the library, a search (by id) or a link.
function playSongArgs(id) { return ["play", "--", id] }
function queueSongArgs(id, next) { return ["add"].concat(next ? ["--next"] : []).concat(["--", id]) }

// ---------- the radio and playlists made for you (`paattu radio`, `made`,
// `describe`; keep in step with paattu/made.py)
var MADE = [
  { kind: "daily", title: "Daily mix", blurb: "Songs you love and a few like them", glyph: "\u{F00F6}" },  // md-calendar_today
  { kind: "weekly", title: "Weekly discovery", blurb: "Songs new to you, like what you played lately", glyph: "\u{F0A33}" },  // md-calendar_week
  { kind: "monthly", title: "Monthly top", blurb: "What you played most in the last 30 days", glyph: "\u{F0E17}" }  // md-calendar_month
]
// Start a radio of the song at path (a link the engine plays), or stop it.
function radioArgs(on, path) { return on ? ["radio", "start", "--", path] : ["radio", "stop"] }
function madeArgs(kind, refresh) { return ["made", kind, "--play"].concat(refresh ? ["--refresh"] : []) }
function describeArgs(text, saveAs) {
  return ["describe", "--play"].concat(saveAs ? ["--save", saveAs] : []).concat(["--", text])
}

// ---------- browse: songs, albums, singers and playlists, a page at a time
// (`paattu browse`; keep in step with paattu/browse.py)
var KINDS = [
  { kind: "song", title: "Songs", glyph: GLYPH_NOTE },
  { kind: "album", title: "Albums", glyph: GLYPH_ALBUM },
  { kind: "artist", title: "Artists", glyph: GLYPH_USER },
  { kind: "playlist", title: "Playlists", glyph: GLYPH_PLAYLIST }
]
var KIND_SITES = {
  song: ["jiosaavn", "youtube", "soundcloud"],
  album: ["jiosaavn", "soundcloud"],
  artist: ["jiosaavn", "youtube", "soundcloud"],
  playlist: ["jiosaavn", "youtube", "soundcloud"]
}
// after: the "next" cursors of the page before, or null for the first page.
function browseSearchArgs(query, kind, after) {
  return ["browse", "search", "--kind", kind].concat(after ? ["--after", JSON.stringify(after)] : [])
    .concat(["--", String(query)])
}
function suggestArgs(query) { return ["browse", "suggest", "--", String(query)] }
function openArgs(item, page) {
  return ["browse", "open"].concat(page > 1 ? ["--page", String(page)] : []).concat(["--", JSON.stringify(item)])
}
// Play songs found by browse from index (ids in order).
function browsePlayArgs(tracks, index, shuffle, title, source) {
  return ["browse", "play", "--index", String(index || 0)].concat(shuffle ? ["--shuffle"] : [])
    .concat(["--title", String(title || "Search"), "--source", String(source || ""), "--"])
    .concat((tracks || []).map(function(t) { return t.id }))
}
function saveSongsArgs(tracks) {
  return ["save", "--"].concat((tracks || []).map(function(t) { return t.id }))
}
// What makes two results the same: `browse search` gives each its key
// (browse.result_key: a film song is one song on every site; anything else
// only on its own site).
function resultKey(item) {
  return item.key || (item.type || "song") + "|" + item.site + "|" + item.id
}
// items without those already in have (whose keys are in seen; seen grows).
function freshResults(items, seen) {
  return (items || []).filter(function(item) {
    var key = resultKey(item)
    if (seen[key]) return false
    seen[key] = true
    return true
  })
}
function kindTitle(kind) {
  for (var i = 0; i < KINDS.length; i++) if (KINDS[i].kind === kind) return KINDS[i].title
  return ""
}
function resultGlyph(item) {
  return item.type === "album" ? GLYPH_ALBUM : item.type === "artist" ? GLYPH_USER
    : item.type === "playlist" ? GLYPH_PLAYLIST : item.type === "query" ? GLYPH_SEARCH : GLYPH_NOTE
}
function resultTypeName(item) {
  return { album: "Album", artist: "Artist", playlist: "Playlist", song: "Song" }[item.type] || ""
}

// Search results as lists to show: a looked-up link's songs first, then
// everything found by searching, as one list (which site a song is from
// doesn't matter). results: [{site, ...}] from `paattu search`.
function searchGroups(results) {
  var link = [], found = []
  for (var i = 0; i < (results || []).length; i++) {
    var t = results[i]
    if (SEARCH_SITES.indexOf(t.site) === -1) link.push(t)
    else found.push(t)
  }
  var out = []
  if (link.length) out.push({ site: "link", title: "From the link", tracks: link })
  if (found.length) out.push({ site: "", title: "Songs", tracks: found })
  return out
}

// Why a search failed, a line a site; the site named only when several
// were asked. errors: {site: reason} from `paattu search` / `paattu browse`.
function searchErrors(errors) {
  var sites = Object.keys(errors || {})
  if (sites.length === 1) return ["Couldn't search: " + errors[sites[0]]]
  return sites.map(function(site) { return "Couldn't search " + siteName(site) + ": " + errors[site] })
}

// Optimistic toggles: what a button shows while its command runs. pending
// maps key -> wanted value; settle() drops the ones the files now agree with.
function shown(pending, key, actual) {
  return pending && Object.prototype.hasOwnProperty.call(pending, key) ? pending[key] : actual
}
function settle(pending, actualOf) {
  var out = {}
  for (var key in pending)
    if (pending[key] !== actualOf(key)) out[key] = pending[key]
  return out
}

// ---------------------------------------------------------------- mixes

var GLYPH_LANGUAGE = "\u{F05CA}"    // md-translate
var GLYPH_UP = "\u{F0143}"          // md-chevron_up
var GLYPH_DOWN = "\u{F0140}"        // md-chevron_down

// The shuffle buttons, from shelf.json: {id, title, sources: [{type, id, title}],
// playlists, count, waiting}. A shelf from before mixes gets the language
// mixes they replaced.
function mixesOf(shelf, languages) {
  if (shelf && Array.isArray(shelf.mixes)) return shelf.mixes
  var langs = languages && languages.length ? languages : LANGUAGES
  return langs.map(function(lang) {
    return { id: "mix-" + lang.toLowerCase(), title: lang + " mix",
      sources: [{ type: "language", id: lang, title: lang }], playlists: 0, count: 0, waiting: 0 }
  })
}

function sourceKey(source) { return source.type + ":" + source.id }

function mixHas(mix, source) {
  var sources = mix && mix.sources ? mix.sources : []
  for (var i = 0; i < sources.length; i++)
    if (sources[i].type === source.type && sources[i].id === source.id) return true
  return false
}

function sourceGlyph(source) {
  if (source.type === "language") return GLYPH_LANGUAGE
  if (source.type === "user") return GLYPH_USER
  return source.id === FAVOURITES ? GLYPH_HEART : GLYPH_PLAYLIST
}

// "Malayalam, RayapaN · 304 songs"
function mixDetail(mix) {
  if (!mix || !mix.sources || !mix.sources.length) return "Empty: add languages, profiles or playlists"
  var names = mix.sources.map(function(s) { return s.title || s.id })
  var what = names.slice(0, 3).join(", ") + (names.length > 3 ? " +" + (names.length - 3) : "")
  return what + " · " + (mix.count ? formatCount(mix.count) + (mix.count === 1 ? " song" : " songs")
    : mix.waiting ? "songs not loaded yet" : "nothing saved there yet")
}

// What can go in a mix, filtered by query: languages, followed users, your
// playlists and saved playlists. Items are sources: {type, id, title, detail}.
function mixCandidates(lib, shelf, languages, query) {
  var q = fold(query || "")
  var keep = function(item) { return !q || fold(item.title).indexOf(q) !== -1 }
  var langs = (languages || LANGUAGES).slice()
  for (var lang in (shelf && shelf.languages) || {}) if (langs.indexOf(lang) === -1) langs.push(lang)
  var out = { languages: [], users: [], mine: [], playlists: [] }
  out.languages = langs.map(function(l) {
    var n = shelf && shelf.languages && shelf.languages[l] ? shelf.languages[l].length : 0
    return { type: "language", id: l, title: l, detail: plural(n, "saved playlist") }
  }).filter(keep)
  var users = lib && lib.users ? lib.users : {}
  for (var uid in users)
    out.users.push({ type: "user", id: uid, title: users[uid].name || uid,
      detail: plural(userPlaylists(lib, uid).filter(function(p) { return p.saved }).length, "saved playlist") })
  out.users = out.users.filter(keep).sort(function(a, b) { return fold(a.title) < fold(b.title) ? -1 : 1 })
  out.mine = ownPlaylists(shelf).map(function(p) {
    return { type: "playlist", id: p.id, title: p.title, detail: plural(p.count || 0, "song") }
  }).filter(keep)
  var playlists = lib && lib.playlists ? lib.playlists : {}
  for (var pid in playlists) {
    var p = playlists[pid]
    if (!p.saved || p.local) continue
    out.playlists.push({ type: "playlist", id: pid, title: p.title || pid, owner: ownerName(lib, p),
      detail: ownerName(lib, p) + (p.count ? " · " + plural(p.count, "song") : "") })
  }
  out.playlists = out.playlists.filter(keep).sort(function(a, b) { return fold(a.title) < fold(b.title) ? -1 : 1 })
  return out
}

// CLI arguments. "--flag=value" and "--" before names: ids and names can
// start with "-".
var MIX_FLAGS = { language: "--lang=", user: "--user=", playlist: "--playlist=" }
function playMixArgs(mixId) { return ["play", "--mix=" + mixId, "--shuffle"] }
function mixSourceArgs(mixId, source, on) { return ["mix", on ? "add" : "drop", mixId, MIX_FLAGS[source.type] + source.id] }
function newMixArgs(name, source) {
  return ["mix", "new"].concat(source ? [MIX_FLAGS[source.type] + source.id] : []).concat(["--", name])
}
function renameMixArgs(mixId, name) { return ["mix", "rename", mixId, "--", name] }
// position: 1 is the first button.
function moveMixArgs(mixId, position) { return ["mix", "move", mixId, String(position)] }

function ownerName(lib, playlist) {
  if (!playlist) return ""
  var user = lib && lib.users ? lib.users[playlist.owner] : null
  return (user && user.name) || playlist.ownerName || ""
}

function userPlaylists(lib, userId) {
  var user = lib && lib.users ? lib.users[userId] : null
  if (!user) return []
  var out = []
  for (var i = 0; i < user.playlists.length; i++) {
    var p = lib.playlists[user.playlists[i]]
    if (p) out.push(p)
  }
  return out
}

function usersByLanguage(lib, language) {
  var out = []
  var users = lib && lib.users ? lib.users : {}
  for (var id in users) {
    if (!language || users[id].language === language) out.push(users[id])
  }
  out.sort(function(a, b) { return (b.followers || 0) - (a.followers || 0) })
  return out
}

function playlistTracks(lib, playlistId) {
  var p = lib && lib.playlists ? lib.playlists[playlistId] : null
  if (!p || !p.tracks) return []
  var out = []
  for (var i = 0; i < p.tracks.length; i++) {
    var t = lib.tracks[p.tracks[i]]
    if (t) out.push(t)
  }
  return out
}

// Case- and accent-insensitive search over saved tracks and playlists.
function search(lib, query, limit) {
  var q = fold(query)
  var result = { tracks: [], playlists: [], users: [] }
  if (!q || !lib) return result
  limit = limit || 40
  var seen = {}
  for (var pid in lib.playlists) {
    var p = lib.playlists[pid]
    if (fold(p.title + " " + (p.ownerName || "")).indexOf(q) !== -1 && result.playlists.length < limit)
      result.playlists.push(p)
    if (!p.saved || !p.tracks) continue
    for (var i = 0; i < p.tracks.length && result.tracks.length < limit; i++) {
      var t = lib.tracks[p.tracks[i]]
      if (!t || seen[t.id]) continue
      if (fold(t.title + " " + (t.movie || "") + " " + (t.credits || []).join(" ")).indexOf(q) !== -1) {
        seen[t.id] = true
        result.tracks.push({ track: t, playlist: pid })
      }
    }
  }
  for (var uid in lib.users) {
    var u = lib.users[uid]
    if (fold(u.name + " " + (u.handle || "")).indexOf(q) !== -1) result.users.push(u)
  }
  return result
}

function fold(text) {
  return String(text || "").toLowerCase().normalize("NFD").replace(/[̀-ͯ]/g, "")
}

function queueRows(playlist, tracks) {
  var out = []
  for (var i = 0; i < (playlist || []).length; i++) {
    var entry = playlist[i]
    var info = nowPlaying(tracks, entry.filename, entry.title)
    out.push({ index: i, id: info.id, title: info.title || entry.filename, movie: info.movie,
      current: !!entry.current })
  }
  return out
}

// ---------------------------------------------------------------- theme

function parseHex(hex) {
  var h = String(hex || "").replace("#", "")
  if (h.length === 3) h = h.replace(/(.)/g, "$1$1")
  if (h.length === 8) h = h.slice(2)  // #aarrggbb -> rrggbb
  if (!/^[0-9a-fA-F]{6}$/.test(h)) return null
  return [parseInt(h.slice(0, 2), 16), parseInt(h.slice(2, 4), 16), parseInt(h.slice(4, 6), 16)]
}

function toHex(rgb) {
  return "#" + rgb.map(function(v) {
    var s = Math.max(0, Math.min(255, Math.round(v))).toString(16)
    return s.length < 2 ? "0" + s : s
  }).join("")
}

function mix(a, b, t) {
  var x = parseHex(a), y = parseHex(b)
  if (!x || !y) return a || b
  return toHex([x[0] + (y[0] - x[0]) * t, x[1] + (y[1] - x[1]) * t, x[2] + (y[2] - x[2]) * t])
}

function luminance(hex) {
  var c = parseHex(hex)
  if (!c) return 0
  var f = function(v) { v /= 255; return v <= 0.03928 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4) }
  return 0.2126 * f(c[0]) + 0.7152 * f(c[1]) + 0.0722 * f(c[2])
}

// A palette from a Paattu theme file, or from the live Omarchy colours when
// the theme is "omarchy" (or the file is missing / broken).
function palette(themeName, themeData, omarchy) {
  var base = {
    background: omarchy.background, foreground: omarchy.foreground,
    accent: omarchy.accent,
    // Omarchy's own muted is often too dark to read on a panel.
    muted: mix(omarchy.foreground, omarchy.background, 0.42),
    surface: mix(omarchy.background, omarchy.foreground, 0.07),
    highlight: mix(omarchy.accent, omarchy.foreground, 0.35)
  }
  if (themeName === "omarchy" || !themeData) return base
  var keys = ["background", "surface", "foreground", "muted", "accent", "highlight"]
  var out = {}
  for (var i = 0; i < keys.length; i++) {
    var value = themeData[keys[i]]
    out[keys[i]] = parseHex(value) ? value : base[keys[i]]
  }
  return out
}

// Text that stays readable on top of the accent (the big play button).
function onAccent(pal) {
  return luminance(pal.accent) > 0.45 ? mix(pal.background, "#000000", 0.6) : "#ffffff"
}

// ---------------------------------------------------------------- colours from the cover

function toHsl(rgb) {
  var r = rgb[0] / 255, g = rgb[1] / 255, b = rgb[2] / 255
  var hi = Math.max(r, g, b), lo = Math.min(r, g, b), l = (hi + lo) / 2
  if (hi === lo) return [0, 0, l]
  var d = hi - lo
  var s = l > 0.5 ? d / (2 - hi - lo) : d / (hi + lo)
  var h = hi === r ? (g - b) / d + (g < b ? 6 : 0) : hi === g ? (b - r) / d + 2 : (r - g) / d + 4
  return [h / 6, s, l]
}

function fromHsl(h, s, l) {
  var q = l < 0.5 ? l * (1 + s) : l + s - l * s, p = 2 * l - q
  var f = function(t) {
    t = (t % 1 + 1) % 1
    return 255 * (t < 1 / 6 ? p + (q - p) * 6 * t : t < 1 / 2 ? q : t < 2 / 3 ? p + (q - p) * (2 / 3 - t) * 6 : p)
  }
  return toHex([f(h + 1 / 3), f(h), f(h - 1 / 3)])
}

// The player's colours from a song's cover (Settings › Colours from the
// cover). `pixels`: RGBA bytes of a small copy of the cover (the app takes
// 32×32); `dark`: whether the theme is dark, which the colours keep. The
// accent is the cover's strongest colour, the highlight its next one. Null for
// a cover without a colour to take (black and white, say).
function coverPalette(pixels, dark) {
  var BINS = 24
  var bins = []
  for (var k = 0; k < BINS; k++) bins.push({ w: 0, x: 0, y: 0, s: 0 })
  var counted = 0
  for (var i = 0; i + 3 < (pixels ? pixels.length : 0); i += 4) {
    if (pixels[i + 3] < 128) continue
    counted++
    var c = toHsl([pixels[i], pixels[i + 1], pixels[i + 2]])
    if (c[1] < 0.2 || c[2] < 0.12 || c[2] > 0.9) continue
    // Vivid colours of middling lightness count most (over skin, say).
    var w = c[1] * c[1] * (1 - Math.abs(c[2] - 0.5))
    var bin = bins[Math.floor(c[0] * BINS) % BINS]
    bin.w += w
    bin.x += w * Math.cos(c[0] * 2 * Math.PI)
    bin.y += w * Math.sin(c[0] * 2 * Math.PI)
    bin.s += w * c[1]
  }
  // Each hue with its neighbours, so a colour split between two bins counts whole.
  var around = function(k) {
    var out = { k: k, w: 0, x: 0, y: 0, s: 0 }
    for (var d = -1; d <= 1; d++) {
      var b = bins[(k + d + BINS) % BINS]
      out.w += b.w; out.x += b.x; out.y += b.y; out.s += b.s
    }
    return out
  }
  var best = around(0)
  for (k = 1; k < BINS; k++) if (around(k).w > best.w) best = around(k)
  if (!counted || best.w < counted * 0.012) return null
  var hueOf = function(b) { return (Math.atan2(b.y, b.x) / (2 * Math.PI) + 1) % 1 }
  var next = null
  for (k = 0; k < BINS; k++) {
    var apart = Math.abs(k - best.k)
    if (Math.min(apart, BINS - apart) < 4) continue
    var other = around(k)
    if (other.w >= best.w * 0.2 && (!next || other.w > next.w)) next = other
  }
  var h = hueOf(best)
  var sat = Math.max(0.35, Math.min(0.85, best.s / best.w))
  // Without a second colour, a softer shade of the first.
  var h2 = next ? hueOf(next) : h
  var sat2 = next ? Math.max(0.35, Math.min(0.85, next.s / next.w)) : sat * 0.6
  return dark ? {
    background: fromHsl(h, sat * 0.5, 0.08),
    surface: fromHsl(h, sat * 0.45, 0.14),
    foreground: fromHsl(h, 0.25, 0.94),
    muted: fromHsl(h, 0.15, 0.68),
    accent: fromHsl(h, sat, 0.64),
    highlight: fromHsl(h2, sat2, 0.72)
  } : {
    background: fromHsl(h, sat * 0.55, 0.95),
    surface: fromHsl(h, sat * 0.5, 0.9),
    foreground: fromHsl(h, 0.4, 0.12),
    muted: fromHsl(h, 0.2, 0.38),
    accent: fromHsl(h, sat, 0.4),
    highlight: fromHsl(h2, sat2, 0.34)
  }
}

// ---------------------------------------------------------------- desktop

function anchorsFor(position) {
  var p = String(position || "bottom-left")
  return {
    top: p.indexOf("top") === 0,
    bottom: p.indexOf("bottom") === 0,
    left: /left$/.test(p) || p === "left",
    right: /right$/.test(p) || p === "right"
  }
}

function nextIn(list, value) {
  var i = list.indexOf(value)
  return list[(i + 1) % list.length]
}

function repeatGlyph(mode) {
  return mode === "one" ? GLYPH_REPEAT_ONE : mode === "all" ? GLYPH_REPEAT : GLYPH_REPEAT_OFF
}

function nextRepeat(mode) {
  return mode === "off" ? "all" : mode === "all" ? "one" : "off"
}

// Namaskaram in the morning, in Malayalam or Tamil depending on the day.
function greeting(date, languages) {
  var hour = date.getHours()
  var langs = languages && languages.length ? languages : LANGUAGES
  var lang = langs[date.getDate() % langs.length]
  var part = hour < 5 ? "night" : hour < 12 ? "morning" : hour < 17 ? "afternoon" : hour < 21 ? "evening" : "night"
  var words = {
    Malayalam: { morning: "സുപ്രഭാതം", afternoon: "നമസ്കാരം", evening: "ശുഭ സന്ധ്യ", night: "ശുഭരാത്രി" },
    Tamil: { morning: "காலை வணக்கம்", afternoon: "வணக்கம்", evening: "மாலை வணக்கம்", night: "இனிய இரவு" }
  }
  var english = { morning: "Good morning", afternoon: "Good afternoon", evening: "Good evening", night: "Late night listening" }
  return { native: (words[lang] || words.Malayalam)[part], english: english[part], language: lang }
}

// ---------------------------------------------------------------- jobs

// `paattu --json ...` prints one JSON object per line.
function parseEvent(line) {
  try {
    var e = JSON.parse(String(line || ""))
    return e && typeof e === "object" ? e : null
  } catch (err) {
    return null
  }
}

// ---------------------------------------------------------------- sound

var GLYPH_EQUALIZER = "\u{F0EA2}"   // md-equalizer

// The same numbers as paattu/sound.py (tests/sound_cases.json checks both):
// FFmpeg peaking filters in one lavfi graph, which the Sound page moves live
// with `af-command paattu g <dB> equalizer@<name>` while a control is dragged.
var SOUND_BANDS = [31, 62, 125, 250, 500, 1000, 2000, 4000, 8000, 16000]
var SOUND_LIMIT = 12
var SOUND_SPEED = [0.5, 2]
var SOUND_RATE = 48000
var SOUND_PRESETS = [
  { id: "flat", name: "Flat", bands: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0] },
  { id: "melody", name: "Melody", bands: [-2, -1.5, -1, 0.5, 2, 3.5, 3.5, 2, 0.5, -0.5] },
  { id: "kuthu", name: "Kuthu", bands: [6, 5, 3, 1, 0, 0, 1, 2, 2, 1] },
  { id: "bass", name: "Bass boost", bands: [6, 5, 4.5, 2.5, 0.5, 0, 0, 0, 0, 0] },
  { id: "treble", name: "Treble boost", bands: [0, 0, 0, 0, 0, 0.5, 2, 3.5, 5, 6] },
  { id: "classical", name: "Classical", bands: [0, 0, 0, 0, 0, 0, -3, -3, -3, -4.5] },
  { id: "rock", name: "Rock", bands: [5, 3, -2, -3.5, -1.5, 1.5, 3.5, 4.5, 4.5, 4.5] },
  { id: "pop", name: "Pop", bands: [-1, 2.5, 4, 4.5, 3, 0, -1.5, -1.5, -1, -1] },
  { id: "dance", name: "Dance", bands: [6, 4.5, 1.5, 0, 0, -3, -4, -4, 0, 0] },
  { id: "jazz", name: "Jazz", bands: [3, 2, 1, 2, -1.5, -1.5, 0, 1, 2, 3] },
  { id: "acoustic", name: "Acoustic", bands: [4, 4, 3, 1, 1.5, 1.5, 3, 3.5, 3, 2] },
  { id: "loudness", name: "Loudness", bands: [5, 4, 2, 0, -1, -1, 0, 2, 4, 5] },
  { id: "headphones", name: "Headphones", bands: [3, 2, 1, 0, -0.5, 0, 1, 2, 2.5, 3] },
  { id: "night", name: "Late night", bands: [-1, -1, 0, 1, 1.5, 1, 0, -1, -2, -3] }
]
var SOUND_DEFAULTS = { on: false, preset: "flat", bands: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0], preamp: 0, bass: 0,
  treble: 0, balance: 0, noclip: true, speed: 1, presets: {} }

// The filters that shape the sound: {name, f (Hz), t ("o": w in octaves, "q"), w}.
// ("pre", "left" and "right" are flat gains, so they don't change the shape.)
var SOUND_SHAPE = SOUND_BANDS.map(function(f, i) { return { name: "b" + i, f: f, t: "o", w: 1 } })
  .concat([{ name: "bass", f: 60, t: "o", w: 3 }, { name: "treble", f: 10000, t: "o", w: 2 }])

// To 0.1 dB, halves up (as Python's tenth).
function soundTenth(x) { return Math.floor(x * 10 + 0.5) / 10 }
function soundHundredth(x) { return Math.floor(x * 100 + 0.5) / 100 }

// 2.5 → "2.5", 3 → "3", -0 → "0": af-command's argument.
function soundFmt(x) {
  x = soundTenth(x)
  return x === 0 ? "0" : x.toFixed(1).replace(/\.0$/, "")
}

// A number in [low, high] from a config value (Python's float(): numbers,
// booleans and numeric strings), else the default.
function soundNumber(value, low, high, fallback) {
  var x = typeof value === "number" || typeof value === "boolean" ? Number(value)
    : typeof value === "string" && value.trim() !== "" ? Number(value.trim()) : NaN
  return isNaN(x) ? (fallback === undefined ? 0 : fallback) : Math.min(high, Math.max(low, x))
}

function soundBandsOf(values) {
  var out = []
  for (var i = 0; i < SOUND_BANDS.length; i++)
    out.push(soundTenth(soundNumber(values && i < values.length ? values[i] : 0, -SOUND_LIMIT, SOUND_LIMIT)))
  return out
}

// The settings with every key, each in range (sound.normalize).
function soundNormalize(settings) {
  var s = settings && typeof settings === "object" ? settings : {}
  var get = function(key) { return s[key] === undefined ? SOUND_DEFAULTS[key] : s[key] }
  var presets = {}
  var saved = get("presets") || {}
  for (var name in saved)
    if (name.trim() && Array.isArray(saved[name])) presets[name.trim()] = soundBandsOf(saved[name])
  return {
    on: get("on") === true,
    preset: typeof get("preset") === "string" ? get("preset") : "",
    bands: soundBandsOf(Array.isArray(get("bands")) ? get("bands") : []),
    preamp: soundTenth(soundNumber(get("preamp"), -SOUND_LIMIT, SOUND_LIMIT)),
    bass: soundTenth(soundNumber(get("bass"), -SOUND_LIMIT, SOUND_LIMIT)),
    treble: soundTenth(soundNumber(get("treble"), -SOUND_LIMIT, SOUND_LIMIT)),
    balance: soundHundredth(soundNumber(get("balance"), -1, 1)),
    noclip: get("noclip") !== false,
    speed: soundHundredth(soundNumber(get("speed"), SOUND_SPEED[0], SOUND_SPEED[1], 1)),
    presets: presets
  }
}

function soundSame(a, b) {
  return JSON.stringify(soundNormalize(a)) === JSON.stringify(soundNormalize(b))
}

// The shape filters with their gains: [{f, t, w, g}].
function soundCurve(s) {
  return SOUND_SHAPE.map(function(p, i) {
    return { f: p.f, t: p.t, w: p.w, g: i < SOUND_BANDS.length ? s.bands[i] : s[p.name] }
  })
}

// The level (dB) at freq through peaking filters [{f, t, w, g}]: FFmpeg's
// biquad (RBJ) with its octave width.
function soundResponse(filters, freq) {
  var w = 2 * Math.PI * freq / SOUND_RATE
  var c1 = Math.cos(w), s1 = -Math.sin(w), c2 = Math.cos(2 * w), s2 = -Math.sin(2 * w)
  var total = 0
  for (var i = 0; i < filters.length; i++) {
    var p = filters[i]
    if (!p.g) continue
    var w0 = 2 * Math.PI * p.f / SOUND_RATE
    var sin = Math.sin(w0), cos = Math.cos(w0)
    var alpha = p.t === "q" ? sin / (2 * p.w) : sin * Math.sinh(Math.LN2 / 2 * p.w * w0 / sin)
    var a = Math.pow(10, p.g / 40)
    var nr = 1 + alpha * a - 2 * cos * c1 + (1 - alpha * a) * c2
    var ni = -2 * cos * s1 + (1 - alpha * a) * s2
    var dr = 1 + alpha / a - 2 * cos * c1 + (1 - alpha / a) * c2
    var di = -2 * cos * s1 + (1 - alpha / a) * s2
    total += 10 * Math.log10((nr * nr + ni * ni) / (dr * dr + di * di))
  }
  return total
}

// Where the peak is looked for: 20 Hz … 20 kHz, 24 steps an octave, and the bands.
var SOUND_GRID = (function() {
  var out = SOUND_BANDS.slice()
  for (var i = 0; i < 240; i++) out.push(20 * Math.pow(2, i / 24))
  return out
})()

// The curve's highest boost (dB), 0 if it only cuts.
function soundPeak(s) {
  var shape = soundCurve(s).filter(function(p) { return p.g })
  var top = 0
  if (shape.length)
    for (var i = 0; i < SOUND_GRID.length; i++) top = Math.max(top, soundResponse(shape, SOUND_GRID[i]))
  return top
}

// {filter name: dB} as the graph gets them (sound.gains).
function soundGains(settings) {
  var s = soundNormalize(settings)
  var out = { pre: soundTenth(Math.max(-30, s.preamp - (s.noclip ? soundPeak(s) : 0))) }
  for (var i = 0; i < s.bands.length; i++) out["b" + i] = s.bands[i]
  out.bass = s.bass
  out.treble = s.treble
  out.left = s.balance > 0 ? soundTenth(20 * Math.log10(Math.max(0.01, 1 - s.balance))) : 0
  out.right = s.balance < 0 ? soundTenth(20 * Math.log10(Math.max(0.01, 1 + s.balance))) : 0
  return out
}

// af-commands that move a playing graph from gains `before` to `after`.
function soundCommands(before, after) {
  var out = []
  for (var name in after)
    if (!before || before[name] !== after[name])
      out.push(["af-command", "paattu", "g", soundFmt(after[name]), "equalizer@" + name])
  return out
}

// Built-in presets, then your own: [{id, name, bands, saved}].
function soundPresets(s) {
  var out = SOUND_PRESETS.map(function(p) { return { id: p.id, name: p.name, bands: p.bands, saved: false } })
  for (var name in s.presets) out.push({ id: name, name: name, bands: s.presets[name], saved: true })
  return out
}

// The preset whose bands these are ("" for none): sound's _matching_preset.
function soundMatchingPreset(s) {
  var all = soundPresets(s)
  for (var i = 0; i < all.length; i++)
    if (JSON.stringify(soundBandsOf(all[i].bands)) === JSON.stringify(s.bands)) return all[i].id
  return ""
}

// "31", "1k", "16k".
function soundBandLabel(f) { return f >= 1000 ? f / 1000 + "k" : String(f) }

// "+2.5", "-3", "0".
function soundDb(x) { var t = soundFmt(x); return x > 0 && t !== "0" ? "+" + t : t }
