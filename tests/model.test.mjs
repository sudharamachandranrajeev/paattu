// Unit tests for the plugin's Model.js: node --test tests/*.test.mjs
import { test } from "node:test"
import assert from "node:assert/strict"
import { readFileSync } from "node:fs"
import vm from "node:vm"

const source = readFileSync(new URL("../plugin/Model.js", import.meta.url), "utf8")
  .replace(/^\.pragma library\s*$/m, "")
const M = {}
vm.runInNewContext(source, M)

// Values built inside the VM have its own prototypes; compare their JSON shape.
const eq = (actual, expected) => assert.deepEqual(JSON.parse(JSON.stringify(actual)), expected)

const LIB = {
  users: { UC1: { id: "UC1", name: "Saregama Malayalam", handle: "@saregamamalayalam", language: "Malayalam", followers: 2650000, playlists: ["PL1", "PL2"] },
           UC2: { id: "UC2", name: "Think Music India", language: "Tamil", followers: 23000000, playlists: [] } },
  playlists: {
    PL1: { id: "PL1", title: "Hits of Sushin Shyam", owner: "UC1", saved: true, tracks: ["hvqnG6VjqV0", "eC7ZXijy_8Y"] },
    PL2: { id: "PL2", title: "Karam", owner: "UC1", saved: false, tracks: null },
  },
  tracks: {
    hvqnG6VjqV0: { id: "hvqnG6VjqV0", title: "Thalatherichavar", movie: "Romancham", credits: ["Sushin Shyam"], duration: 276 },
    eC7ZXijy_8Y: { id: "eC7ZXijy_8Y", title: "Pakaliravukal", movie: "Kurup", credits: ["Dulquer Salmaan"], duration: 238 },
  },
}

test("formatTime and counts", () => {
  assert.equal(M.formatTime(0), "0:00")
  assert.equal(M.formatTime(276.9), "4:36")
  assert.equal(M.formatTime(3725), "1:02:05")
  assert.equal(M.formatCount(2650000), "2.6M")
  assert.equal(M.formatCount(23000000), "23M")
  assert.equal(M.formatCount(9400), "9.4K")
  assert.equal(M.plural(1, "track"), "1 track")
})

test("videoId from engine paths", () => {
  assert.equal(M.videoId("https://www.youtube.com/watch?v=hvqnG6VjqV0"), "hvqnG6VjqV0")
  assert.equal(M.videoId("https://youtu.be/hvqnG6VjqV0"), "hvqnG6VjqV0")
  assert.equal(M.videoId("/tmp/a.webm"), "")
})

test("nowPlaying prefers the library, falls back to the engine title", () => {
  const known = M.nowPlaying(LIB.tracks, "https://www.youtube.com/watch?v=hvqnG6VjqV0", "x")
  assert.equal(known.title, "Thalatherichavar")
  assert.equal(M.subtitle(known), "Romancham · Sushin Shyam")
  const unknown = M.nowPlaying(LIB.tracks, "https://www.youtube.com/watch?v=AAAAAAAAAAA", "Malare · Premam")
  eq({ title: unknown.title, movie: unknown.movie, known: unknown.known }, { title: "Malare", movie: "Premam", known: false })
})

test("coverClip crops the centre square of a letterboxed thumbnail", () => {
  eq(M.coverClip(500, 500), { x: 0, y: 0, width: 500, height: 500 })
  eq(M.coverClip(480, 360), { x: 105, y: 45, width: 270, height: 270 })
  eq(M.coverClip(480, 270), { x: 105, y: 0, width: 270, height: 270 })
  assert.equal(M.coverClip(0, 0), null)
})

test("library helpers", () => {
  eq(M.userPlaylists(LIB, "UC1").map(p => p.id), ["PL1", "PL2"])
  eq(M.usersByLanguage(LIB, "").map(u => u.id), ["UC2", "UC1"])
  eq(M.usersByLanguage(LIB, "Malayalam").map(u => u.id), ["UC1"])
  eq(M.playlistTracks(LIB, "PL1").map(t => t.title), ["Thalatherichavar", "Pakaliravukal"])
  eq(M.playlistTracks(LIB, "PL2"), [])
  assert.equal(M.ownerName(LIB, LIB.playlists.PL1), "Saregama Malayalam")
})

test("search folds case and covers movies and credits", () => {
  const r = M.search(LIB, "kurup")
  eq(r.tracks.map(t => t.track.id), ["eC7ZXijy_8Y"])
  eq(M.search(LIB, "SUSHIN").playlists.map(p => p.id), ["PL1"])
  eq(M.search(LIB, "think").users.map(u => u.id), ["UC2"])
  eq(M.search(LIB, ""), { tracks: [], playlists: [], users: [] })
})

test("queueRows marks the current entry", () => {
  const rows = M.queueRows([
    { filename: "https://www.youtube.com/watch?v=hvqnG6VjqV0", title: "Thalatherichavar · Romancham" },
    { filename: "https://www.youtube.com/watch?v=eC7ZXijy_8Y", title: "Pakaliravukal · Kurup", current: true },
  ], LIB.tracks)
  eq(rows.map(r => [r.title, r.current]), [["Thalatherichavar", false], ["Pakaliravukal", true]])
})

test("palette follows Omarchy or a theme file, and fills gaps", () => {
  const omarchy = { background: "#101315", foreground: "#cacccc", accent: "#7aa2f7", muted: "#707880" }
  const live = M.palette("omarchy", null, omarchy)
  assert.equal(live.accent, "#7aa2f7")
  assert.match(live.surface, /^#[0-9a-f]{6}$/)
  const kasavu = M.palette("kasavu", { background: "#F6F0E1", accent: "#B8901F", foreground: "nope" }, omarchy)
  assert.equal(kasavu.background, "#F6F0E1")
  assert.equal(kasavu.foreground, "#cacccc")
  assert.equal(M.onAccent({ accent: "#ffffff", background: "#000000" }), "#000000")
  assert.equal(M.onAccent({ accent: "#1e0a14", background: "#000000" }), "#ffffff")
  assert.equal(M.mix("#000000", "#ffffff", 0.5), "#808080")
  assert.equal(M.parseHex("#ff101315").join(","), "16,19,21")
})

test("desktop anchors and cycling", () => {
  eq(M.anchorsFor("bottom-left"), { top: false, bottom: true, left: true, right: false })
  eq(M.anchorsFor("top"), { top: true, bottom: false, left: false, right: false })
  eq(M.anchorsFor("right"), { top: false, bottom: false, left: false, right: true })
  eq(M.anchorsFor("center"), { top: false, bottom: false, left: false, right: false })
  assert.equal(M.nextIn(["vinyl", "card", "minimal"], "minimal"), "vinyl")
  assert.equal(M.nextRepeat("off"), "all")
  assert.equal(M.nextRepeat("one"), "off")
})

test("greeting alternates Malayalam and Tamil by day", () => {
  const a = M.greeting(new Date(2026, 9, 12, 8), ["Malayalam", "Tamil"])
  const b = M.greeting(new Date(2026, 9, 13, 20), ["Malayalam", "Tamil"])
  eq([a.language, a.native, a.english], ["Malayalam", "സുപ്രഭാതം", "Good morning"])
  eq([b.language, b.native], ["Tamil", "மாலை வணக்கம்"])
})

test("parseEvent reads paattu --json lines", () => {
  eq(M.parseEvent('{"event":"progress","message":"x"}'), { event: "progress", message: "x" })
  assert.equal(M.parseEvent("not json"), null)
})

test("shelf picks one playlist per owner on request", () => {
  const shelf = { languages: { Tamil: [
    { id: "a", owner: "UC1", title: "A. R. Rahman — Most played", auto: true, count: 200 },
    { id: "b", owner: "UC1", title: "A. R. Rahman — New releases", auto: true },
    { id: "c", owner: "UC2", title: "Best of Ilaiyaraaja", ownerName: "Ilaiyaraaja Official", count: 123 },
  ] } }
  eq(M.shelfFor(shelf, "Tamil", 2).map(p => p.id), ["a", "b"])
  eq(M.shelfFor(shelf, "Tamil", 2, true).map(p => p.id), ["a", "c"])
  assert.equal(M.playlistDetail(shelf.languages.Tamil[0]), "Most played · 200 songs")
  assert.equal(M.playlistDetail(shelf.languages.Tamil[1]), "New releases")
  assert.equal(M.playlistDetail(shelf.languages.Tamil[2]), "Ilaiyaraaja Official · 123 songs")
})

test("userStats counts saved, unsaved, waiting and removed playlists", () => {
  const lib = {
    users: { UC1: { id: "UC1", playlists: ["PL1", "PL2", "PL3", "PL4"] } },
    playlists: {
      PL1: { id: "PL1", owner: "UC1", saved: true, tracks: ["a"] },
      PL2: { id: "PL2", owner: "UC1", saved: true, tracks: null },
      PL3: { id: "PL3", owner: "UC1", saved: false, tracks: null },
      PL4: { id: "PL4", owner: "UC1", saved: true },
    },
    removed: { PL5: { owner: "UC1" }, PL6: { owner: "UC2" } },
  }
  eq(M.userStats(lib, "UC1"), { listed: 4, saved: 3, unsaved: 1, waiting: 2, removed: 1 })
  eq(M.userStats({ users: {}, playlists: {} }, "UC1"), { listed: 0, saved: 0, unsaved: 0, waiting: 0, removed: 0 })
  eq(M.userStats(LIB, "UC1").removed, 0)
})

test("own playlists: Favourites and Saved songs first and always there", () => {
  eq(M.ownPlaylists({}).map(p => p.id), ["paattu-favourites", "paattu-saved"])
  const shelf = { mine: [
    { id: "paattu-1", title: "Car songs", tracks: ["a"] },
    { id: "paattu-saved", title: "Saved songs", tracks: ["jiosaavn.com_song_x_y"] },
    { id: "paattu-favourites", title: "Favourites", tracks: ["b", "c"] },
  ] }
  eq(M.ownPlaylists(shelf).map(p => p.id), ["paattu-favourites", "paattu-saved", "paattu-1"])
  eq(M.favouriteSet(shelf), { b: true, c: true })
  eq(M.savedSet(shelf), { "jiosaavn.com_song_x_y": true })
  assert.equal(M.contains(shelf.mine[0], "a"), true)
  assert.equal(M.contains(shelf.mine[0], "b"), false)
  eq(M.coverOf({ id: "paattu-1", local: true, tracks: ["a", "b"] }), { kind: "v", id: "a" })
  eq(M.coverOf({ id: "paattu-favourites", tracks: [] }), { kind: "v", id: "" })
  eq(M.coverOf({ id: "PL1", tracks: ["a"] }), { kind: "p", id: "PL1" })
})

test("song commands keep dash-leading video ids out of option parsing", () => {
  eq(M.favouriteArgs("-abcdefghij", true), ["fav", "--", "-abcdefghij"])
  eq(M.favouriteArgs("x", false), ["fav", "--remove", "--", "x"])
  eq(M.playlistSongArgs("paattu-favourites", "x", true), ["fav", "--", "x"])
  eq(M.playlistSongArgs("paattu-1", "x", false), ["playlist", "remove-songs", "--", "paattu-1", "x"])
  eq(M.newPlaylistArgs("-chill", "x"), ["playlist", "new", "--", "-chill", "x"])
  eq(M.newPlaylistArgs("Car", ""), ["playlist", "new", "--", "Car"])
  eq(M.playlistSongArgs("paattu-saved", "x", true), ["save", "--", "x"])
  eq(M.saveArgs("-abcdefghij", false), ["save", "--remove", "--", "-abcdefghij"])
  eq(M.playSongArgs("-abcdefghij"), ["play", "--", "-abcdefghij"])
  eq(M.queueSongArgs("x", true), ["add", "--next", "--", "x"])
  eq(M.queueSongArgs("x", false), ["add", "--", "x"])
  eq(M.searchArgs("-malare premam", []), ["search", "--", "-malare premam"])
  eq(M.searchArgs("malare", ["jiosaavn"]), ["search", "--site=jiosaavn", "--", "malare"])
})

test("track ids match the CLI's for every shared case", () => {
  const cases = JSON.parse(readFileSync(new URL("./track_ids.json", import.meta.url), "utf8"))
  for (const [url, want] of Object.entries(cases)) assert.equal(M.trackId(url) || null, want, url)
  assert.equal(M.isVideoId("hvqnG6VjqV0"), true)
  assert.equal(M.isVideoId("jiosaavn.com_song_x"), false)
  assert.equal(M.isLink("https://a.b/c"), true)
  assert.equal(M.isLink("malare premam"), false)
})

test("now playing a song from another site", () => {
  const tracks = { "jiosaavn.com_song_malare_Oj8MATF0B2I": { title: "Malare", movie: "Premam", credits: ["Rajesh Murugesan"] } }
  const np = M.nowPlaying(tracks, "https://www.jiosaavn.com/song/malare/Oj8MATF0B2I", "Malare · Premam")
  eq([np.id, np.title, np.known], ["jiosaavn.com_song_malare_Oj8MATF0B2I", "Malare", true])
  const other = M.nowPlaying({}, "https://soundcloud.com/a/b", "Cover · Premam")
  eq([other.id, other.title, other.movie, other.known], ["soundcloud.com_a_b", "Cover", "Premam", false])
})

test("quality: from the site, and from the stream", () => {
  assert.equal(M.qualityLabel({ quality: 320, codec: "aac" }), "320 kbps")
  assert.equal(M.qualityLabel({ quality: 1000, codec: "flac" }), "Lossless")
  assert.equal(M.qualityLabel({ id: "hvqnG6VjqV0" }), "")
  assert.equal(M.streamQuality({ codec: "aac", demux: 314742, live: 245000 }), "AAC · 320 kbps")
  assert.equal(M.streamQuality({ codec: "opus", live: 133400 }), "Opus · ~130 kbps")
  assert.equal(M.streamQuality({ codec: "flac", rate: 96000 }), "FLAC · Lossless · 96 kHz")
  assert.equal(M.streamQuality({ codec: "flac", rate: 44100 }), "FLAC · Lossless")
  assert.equal(M.streamQuality({ codec: "pcm_s16le" }), "WAV · Lossless")
  assert.equal(M.streamQuality({ codec: "mp3", demux: 256000 }), "MP3 · 256 kbps")
  assert.equal(M.streamQuality({}), "")
  assert.equal(M.siteName("jiosaavn"), "JioSaavn")
  assert.equal(M.siteOf({ url: "https://www.artist.bandcamp.com/track/x" }), "artist.bandcamp.com")
  assert.equal(M.siteOf({ id: "hvqnG6VjqV0" }), "youtube")
})

test("search results show as one list, a link's songs first", () => {
  const results = [{ id: "a", site: "youtube" }, { id: "b", site: "jiosaavn" }, { id: "c", site: "artist.bandcamp.com" },
    { id: "d", site: "jiosaavn" }]
  eq(M.searchGroups(results).map(g => [g.site, g.title, g.tracks.map(t => t.id)]),
     [["link", "From the link", ["c"]], ["", "Songs", ["a", "b", "d"]]])
  eq(M.searchGroups([]), [])
})

test("optimistic toggles settle once the files agree", () => {
  const pending = { a: true, b: false }
  assert.equal(M.shown(pending, "a", false), true)
  assert.equal(M.shown(pending, "c", true), true)
  eq(M.settle(pending, k => true), { b: false })
  eq(M.settle(pending, k => false), { a: true })
})

test("mixes: from the shelf, or the language mixes they replaced", () => {
  eq(M.mixesOf({ languages: {} }, ["Malayalam"]).map(m => [m.id, m.title, m.sources]),
     [["mix-malayalam", "Malayalam mix", [{ type: "language", id: "Malayalam", title: "Malayalam" }]]])
  const shelf = { mixes: [], languages: { Malayalam: [{ id: "PL1" }], Other: [] }, mine: [] }
  eq(M.mixesOf(shelf, ["Malayalam", "Tamil"]), [])  // all deleted stays deleted
  const mix = { id: "mix-1", title: "Road trip", count: 1234, waiting: 0,
    sources: [{ type: "language", id: "Malayalam", title: "Malayalam" }, { type: "user", id: "UC1", title: "Saregama Malayalam" },
              { type: "playlist", id: M.FAVOURITES, title: "Favourites" }, { type: "playlist", id: "PL1", title: "Hits" }] }
  assert.equal(M.mixDetail(mix), "Malayalam, Saregama Malayalam, Favourites +1 · 1.2K songs")
  assert.equal(M.mixDetail({ sources: [] }), "Empty: add languages, profiles or playlists")
  assert.equal(M.mixDetail({ sources: [{ type: "language", id: "Tamil" }], count: 0, waiting: 3 }), "Tamil · songs not loaded yet")
  assert.equal(M.mixHas(mix, { type: "user", id: "UC1" }), true)
  assert.equal(M.mixHas(mix, { type: "playlist", id: "UC1" }), false)
  assert.equal(M.sourceGlyph(mix.sources[2]), M.GLYPH_HEART)
})

test("mix candidates: languages, users, your playlists, saved playlists", () => {
  const shelf = { languages: { Malayalam: [{ id: "PL1" }], Other: [] }, mine: [] }
  const all = M.mixCandidates(LIB, shelf, ["Malayalam", "Tamil"], "")
  eq(all.languages.map(s => [s.id, s.detail]), [["Malayalam", "1 saved playlist"], ["Tamil", "0 saved playlists"], ["Other", "0 saved playlists"]])
  eq(all.users.map(s => s.id), ["UC1", "UC2"])
  eq(all.mine.map(s => s.id), [M.FAVOURITES, M.SAVED])
  eq(all.playlists.map(s => [s.id, s.detail]), [["PL1", "Saregama Malayalam"]])  // unsaved PL2 left out
  const sushin = M.mixCandidates(LIB, shelf, ["Malayalam"], "sushin")
  eq([sushin.languages.length, sushin.users.length, sushin.playlists.map(s => s.id)], [0, 0, ["PL1"]])
})

test("mix commands keep ids and names that start with a dash safe", () => {
  eq(M.playMixArgs("mix-tamil"), ["play", "--mix=mix-tamil", "--shuffle"])
  eq(M.mixSourceArgs("mix-1", { type: "playlist", id: "-PLx" }, true), ["mix", "add", "mix-1", "--playlist=-PLx"])
  eq(M.mixSourceArgs("mix-1", { type: "language", id: "Tamil" }, false), ["mix", "drop", "mix-1", "--lang=Tamil"])
  eq(M.newMixArgs("-90s", { type: "user", id: "UC1" }), ["mix", "new", "--user=UC1", "--", "-90s"])
  eq(M.newMixArgs("Chill", null), ["mix", "new", "--", "Chill"])
  eq(M.renameMixArgs("mix-1", "-x"), ["mix", "rename", "mix-1", "--", "-x"])
  eq(M.moveMixArgs("mix-1", 2), ["mix", "move", "mix-1", "2"])
})

test("browse commands keep queries and ids that start with a dash safe", () => {
  eq(M.browseSearchArgs("-malare", "album", null), ["browse", "search", "--kind", "album", "--", "-malare"])
  eq(M.browseSearchArgs("malare", "song", { youtube: "T" }),
     ["browse", "search", "--kind", "song", "--after", '{"youtube":"T"}', "--", "malare"])
  eq(M.suggestArgs("-chi"), ["browse", "suggest", "--", "-chi"])
  eq(M.openArgs({ type: "artist", site: "jiosaavn", id: "455" }, 1),
     ["browse", "open", "--", '{"type":"artist","site":"jiosaavn","id":"455"}'])
  eq(M.openArgs({ type: "album" }, 2), ["browse", "open", "--page", "2", "--", '{"type":"album"}'])
  eq(M.browsePlayArgs([{ id: "-abcdefghij" }, { id: "x" }], 1, true, "Premam", "123"),
     ["browse", "play", "--index", "1", "--shuffle", "--title", "Premam", "--source", "123", "--", "-abcdefghij", "x"])
  eq(M.saveSongsArgs([{ id: "-abcdefghij" }]), ["save", "--", "-abcdefghij"])
})

test("later pages leave out results already shown", () => {
  const seen = {}
  const first = [{ key: "song|malare|premam", id: "a" }, { type: "album", site: "jiosaavn", id: "1" }]
  eq(M.freshResults(first, seen).map(r => r.id), ["a", "1"])
  const next = [{ key: "song|malare|premam", id: "b" }, { type: "album", site: "soundcloud", id: "1" },
                { type: "album", site: "jiosaavn", id: "1" }]
  eq(M.freshResults(next, seen).map(r => r.site || r.id), ["soundcloud"])
  assert.equal(M.kindTitle("artist"), "Artists")
  assert.equal(M.resultTypeName({ type: "playlist" }), "Playlist")
})

test("sound: the same numbers as paattu/sound.py", () => {
  const cases = JSON.parse(readFileSync(new URL("./sound_cases.json", import.meta.url), "utf8"))
  for (const c of cases) {
    eq(M.soundNormalize(c.settings), c.normalized)
    eq(M.soundGains(c.settings), c.gains)
  }
})

test("sound: live moves, labels and presets", () => {
  const flat = M.soundGains({ on: true })
  const louder = M.soundGains({ on: true, bands: [0, 0, 0, 2.5, 0, 0, 0, 0, 0, 0] })
  // Only what changed: the preamp that makes room for the boost, and the band.
  eq(M.soundCommands(flat, louder), [["af-command", "paattu", "g", M.soundFmt(louder.pre), "equalizer@pre"],
                                     ["af-command", "paattu", "g", "2.5", "equalizer@b3"]])
  assert.ok(louder.pre < -2 && louder.pre > -3)
  assert.equal(M.soundCommands(flat, flat).length, 0)
  assert.equal(M.soundFmt(-0.04), "0")
  assert.equal(M.soundDb(2.5), "+2.5")
  assert.equal(M.soundDb(-3), "-3")
  assert.equal(M.soundBandLabel(16000), "16k")
  assert.equal(M.soundBandLabel(62), "62")
  const s = M.soundNormalize({ bands: [6, 5, 4.5, 2.5, 0.5, 0, 0, 0, 0, 0], presets: { Car: [1, 1] } })
  assert.equal(M.soundMatchingPreset(s), "bass")
  assert.equal(M.soundMatchingPreset(M.soundNormalize({ bands: [1, 1] , presets: { Car: [1, 1] } })), "Car")
  eq(M.soundPresets(s).slice(-1), [{ id: "Car", name: "Car", bands: [1, 1, 0, 0, 0, 0, 0, 0, 0, 0], saved: true }])
  assert.ok(M.soundSame({ on: false }, {}))
  assert.ok(!M.soundSame({ on: true }, {}))
})
