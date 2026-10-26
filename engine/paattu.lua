-- Paattu's engine script: runs inside the engine's mpv (install.sh puts it in
-- ~/.config/paattu/mpv/scripts with the path of the paattu command).
--
--  * Play history: when a song ends (or is skipped) it tells `paattu played`
--    how long it was listened to, which the made-for-you playlists and the
--    radio use.
--  * Radio: with two songs or fewer left (and repeat off) it asks
--    `paattu radio more` for songs like the one playing, when the radio is
--    on or auto radio is (paattu decides).
--  * Failover: a song that won't load is looked for on the other sites
--    (`paattu failover`) and the copy found plays in its place. With no
--    internet, the songs kept on this computer play instead.
--  * Kept songs: a song kept on this computer (`paattu offline`, the folder's
--    paattu-offline.json) plays from its file in place of the link; the queue
--    and the history still see the link.
--  * Fades: a song fades out over its last few seconds and the next fades in
--    (config.json "fade", 3 s by default; mpv plays one song at a time, so
--    the two don't overlap).
--  * Sleep timer: `script-message paattu-sleep MINUTES|+MINUTES|end|off`.
--    When the time is up the song quiets over 8 s and pauses; "end" pauses
--    once the song playing has finished. The state is in
--    user-data/paattu/sleep ({mode = "time", at = epoch seconds} or
--    {mode = "end"}; {} when off) for the bar and the CLI.
--  * Video mode (config.json "videoMode"): a song that has a video
--    (`paattu video --id`) plays the video's own sound, so the singing
--    matches the lips of the video Now Playing shows; the video's id is in
--    user-data/paattu/video ("" for none). A video that won't play gives way
--    to the song's own sound. `script-message paattu-video-mode on|off`
--    changes the song playing where it is.

local utils = require "mp.utils"

local PAATTU = "@PAATTU@"
local CONFIG = (os.getenv("XDG_CONFIG_HOME") or (os.getenv("HOME") .. "/.config")) .. "/paattu/config.json"
local FADE_LABEL = "paattufade"
local TICK = 0.1
local LEAD = 0.3

local DATA = (os.getenv("XDG_DATA_HOME") or (os.getenv("HOME") .. "/.local/share")) .. "/paattu"
local settings = { fade = 3, autoRadio = true, offlineDir = DATA .. "/offline", videoMode = false }

local function read_settings()
    local f = io.open(CONFIG, "r")
    if not f then return end
    local text = f:read("*a")
    f:close()
    local parsed = utils.parse_json(text or "")
    if type(parsed) ~= "table" then return end
    local fade = tonumber(parsed.fade)
    settings.fade = fade and math.max(0, math.min(12, fade)) or 3
    settings.autoRadio = parsed.autoRadio ~= false
    settings.videoMode = parsed.videoMode == true
    local dir = type(parsed.offline) == "table" and parsed.offline.dir or ""
    if type(dir) ~= "string" or dir == "" then
        settings.offlineDir = DATA .. "/offline"
    else
        settings.offlineDir = dir:gsub("^~", os.getenv("HOME") or "~")
    end
end

local function run(args, done)
    mp.command_native_async({
        name = "subprocess", args = args, playback_only = false,
        capture_stdout = true, capture_stderr = true,
    }, function(ok, result)
        result = result or {}
        local fine = ok and result.status == 0
        if not fine then
            mp.msg.warn(table.concat(args, " ", 2) .. ": " .. (result.stderr or result.error_string or "failed"))
        end
        if done then done(fine, result.stdout or "") end
    end)
end

local function last_line(text)
    local last = nil
    for line in (text or ""):gmatch("[^\n]+") do last = line end
    return last
end

local function entry_by_id(id)
    for index, entry in ipairs(mp.get_property_native("playlist") or {}) do
        if entry.id == id then return index - 1, entry end
    end
end

local function looping()
    local file, list = mp.get_property("loop-file"), mp.get_property("loop-playlist")
    return (file ~= "no" and file ~= nil) or (list ~= "no" and list ~= nil)
end

-- ---------------------------------------------------------------- play history

local song = nil     -- {url, title, length, heard} of the song playing
local last_end = nil -- how the last song ended

local function note_play()
    if not song or song.heard < 1 then return end
    local args = { PAATTU, "played", song.url, tostring(math.floor(song.heard)) }
    if song.length and song.length > 0 then
        table.insert(args, "--length=" .. tostring(math.floor(song.length)))
    end
    if song.title and song.title ~= "" then table.insert(args, "--title=" .. song.title) end
    run(args)
end

-- ---------------------------------------------------------------- kept songs

local kept = { path = nil, mtime = nil, files = {} } -- link or "youtube:id" -> file

local function youtube_id(url)
    if not url:find("youtu", 1, true) then return nil end
    return url:match("[?&]v=([%w_-]+)") or url:match("youtu%.be/([%w_-]+)") or url:match("/shorts/([%w_-]+)")
end

local function read_kept()
    local path = settings.offlineDir .. "/paattu-offline.json"
    local info = utils.file_info(path)
    if not info then
        kept = { path = path, mtime = nil, files = {} }
        return
    end
    if kept.path == path and kept.mtime == info.mtime then return end
    kept = { path = path, mtime = info.mtime, files = {} }
    local f = io.open(path, "r")
    if not f then return end
    local parsed = utils.parse_json(f:read("*a") or "")
    f:close()
    if type(parsed) ~= "table" or type(parsed.songs) ~= "table" then return end
    for key, entry in pairs(parsed.songs) do
        if type(entry) == "table" and type(entry.file) == "string" and entry.file ~= "" then
            local file = settings.offlineDir .. "/" .. entry.file
            kept.files[key] = file
            local track = type(entry.track) == "table" and entry.track or {}
            if type(track.url) == "string" and track.url ~= "" then kept.files[track.url] = file end
        end
    end
end

-- ---------------------------------------------------------------- video mode

local video_off = {}       -- links whose video wouldn't play: their own sound
local swapped = false      -- whether the song playing is its video's sound
local resume_at = nil      -- where a song changing to (or from) its video starts
local switching = nil      -- the listen carried over by that change

local function publish_video(id)
    mp.set_property_native("user-data/paattu/video", id or "")
end

-- The id of the song's video, or nil. It waits (the song is loading anyway):
-- quick once the song's video is known, a search the first time.
local function video_of(url)
    local result = mp.command_native({
        name = "subprocess", playback_only = false, capture_stdout = true, capture_stderr = true,
        args = { "timeout", "15", PAATTU, "--json", "video", "--id", "--", url },
    })
    local found = result and result.status == 0 and utils.parse_json(last_line(result.stdout) or "") or nil
    return type(found) == "table" and type(found.id) == "string" and found.id ~= "" and found.id or nil
end

-- Before yt-dlp looks at it (its hook runs at 10), so a kept song needs no
-- network, and a song in video mode is its video's link when yt-dlp sees it.
mp.add_hook("on_load", 5, function()
    if resume_at then
        mp.set_property("file-local-options/start", tostring(resume_at))
        resume_at = nil
    end
    swapped = false
    local url = mp.get_property("stream-open-filename", "")
    if not url:find("://", 1, true) then
        publish_video(nil)
        return
    end
    read_settings()
    if settings.videoMode and not video_off[url] then
        local id = video_of(url)
        publish_video(id)
        if id then
            if id ~= youtube_id(url) then
                swapped = true
                mp.set_property("stream-open-filename", "https://www.youtube.com/watch?v=" .. id)
                mp.msg.info("video mode: playing the sound of video " .. id)
            end
            return
        end
    else
        publish_video(nil)
    end
    read_kept()
    local id = youtube_id(url)
    local file = kept.files[url] or (id and kept.files["youtube:" .. id])
    if file and utils.file_info(file) then
        mp.set_property("stream-open-filename", file)
        mp.msg.info("playing the copy kept on this computer: " .. file)
    end
end)

-- ---------------------------------------------------------------- radio

local extending = false

local function maybe_extend()
    if extending or looping() then return end
    local count, pos = mp.get_property_number("playlist-count", 0), mp.get_property_number("playlist-pos", -1)
    if pos < 0 or count - pos - 1 > 2 then return end
    local station = mp.get_property_native("user-data/paattu/radio")
    local on = type(station) == "table" and station.id ~= nil
    if not on and (not settings.autoRadio or mp.get_property_native("user-data/paattu/radio-stopped")) then return end
    extending = true
    run({ PAATTU, "radio", "more" }, function() extending = false end)
end

-- ---------------------------------------------------------------- failover

local replaced = {} -- links played in place of another (not failed over again)

local function fail_over(entry_id)
    local _, entry = entry_by_id(entry_id)
    if not entry or replaced[entry.filename] then return end
    replaced[entry.filename] = true
    -- Hold the next song while the same one is looked for elsewhere.
    local was_paused = mp.get_property_bool("pause")
    mp.set_property_bool("pause", true)
    local args = { PAATTU, "--json", "failover", entry.filename }
    if entry.title then table.insert(args, "--title=" .. entry.title) end
    run(args, function(ok, out)
        local found = ok and utils.parse_json(last_line(out) or "") or nil
        local index = entry_by_id(entry_id)
        if type(found) == "table" and found.url and index then
            -- No internet: the kept songs (found and found.more) go in after it.
            local songs = { { url = found.url, title = found.title } }
            for _, more in ipairs(type(found.more) == "table" and found.more or {}) do
                if type(more) == "table" and more.url then table.insert(songs, more) end
            end
            for n, item in ipairs(songs) do
                replaced[item.url] = true
                local count = mp.get_property_number("playlist-count", 0)
                mp.command_native({ name = "loadfile", url = item.url, flags = "append",
                                    options = { ["force-media-title"] = item.title or "" } })
                mp.commandv("playlist-move", tostring(count), tostring(index + n))
            end
            mp.commandv("playlist-play-index", tostring(index + 1))
            mp.msg.info((found.offline and "no internet, playing kept songs from " or "failed over to ") .. found.url)
        end
        mp.set_property_bool("pause", was_paused or false)
    end)
end

-- ---------------------------------------------------------------- fades

local fade_in = false
local applied = 1

local function ensure_filter()
    for _, f in ipairs(mp.get_property_native("af") or {}) do
        if f.label == FADE_LABEL then return true end
    end
    return mp.commandv("af", "add", "@" .. FADE_LABEL .. ":lavfi=[volume=volume=1]")
end

local function set_gain(gain)
    if math.abs(gain - applied) < 0.01 and not (gain == 1 and applied ~= 1) then return end
    -- (Sent to the volume filter alone: the graph's resampler would refuse it.)
    if ensure_filter() and mp.commandv("af-command", FADE_LABEL, "volume", string.format("%.3f", gain), "volume") then
        applied = gain
    end
end

local function gain_now()
    local fade = settings.fade
    if fade <= 0 then return 1 end
    local pos, duration = mp.get_property_number("time-pos"), mp.get_property_number("duration")
    if not pos or not duration or duration <= fade * 3 then return 1 end
    local gain = 1
    if fade_in then gain = math.min(gain, math.sin(math.min(1, pos / fade) * math.pi / 2)) end
    local count, index = mp.get_property_number("playlist-count", 0), mp.get_property_number("playlist-pos", -1)
    local next_song = index >= 0 and (index + 1 < count or mp.get_property("loop-playlist") ~= "no")
    if next_song and mp.get_property("loop-file") == "no" then
        -- Silent a moment before the end: what's playing left the filter a
        -- little earlier (the audio output's buffer).
        gain = math.min(gain, math.sin(math.max(0, math.min(1, (duration - pos - LEAD) / fade)) * math.pi / 2))
    end
    return gain
end

-- ---------------------------------------------------------------- sleep timer

local SLEEP_FADE = 8
local sleep = nil         -- {mode = "time", at = epoch seconds} or {mode = "end"}
local sleep_fading = nil  -- mp.get_time() the fade-out began

local function publish_sleep()
    mp.set_property_native("user-data/paattu/sleep", sleep or {})
end

local function sleep_off()
    sleep, sleep_fading = nil, nil
    publish_sleep()
end

local function sleep_gain()
    if not sleep_fading then return 1 end
    local left = 1 - (mp.get_time() - sleep_fading) / SLEEP_FADE
    return math.sin(math.max(0, math.min(1, left)) * math.pi / 2)
end

local function fall_asleep()
    sleep_off()
    mp.set_property_bool("pause", true)
end

mp.register_script_message("paattu-video-mode", function(arg)
    settings.videoMode = arg == "on"
    if not song or mp.get_property_bool("idle-active") then return end
    local video = mp.get_property_native("user-data/paattu/video") or ""
    -- Off: back to the song's own sound if it was its video's. On: to its
    -- video's, unless it already is (a YouTube song that is its own video).
    if settings.videoMode and video ~= "" then return end
    if not settings.videoMode and not swapped then
        publish_video(nil)
        return
    end
    switching = song.heard
    resume_at = mp.get_property_number("time-pos")
    mp.commandv("playlist-play-index", "current")
end)

mp.register_script_message("paattu-sleep", function(arg)
    arg = arg or "off"
    local now = os.time()
    if arg == "end" then
        sleep, sleep_fading = { mode = "end" }, nil
    elseif arg:sub(1, 1) == "+" and tonumber(arg:sub(2)) then
        -- Add to a countdown that's running (or start one).
        local base = (sleep and sleep.mode == "time") and math.max(sleep.at, now) or now
        sleep, sleep_fading = { mode = "time", at = base + tonumber(arg:sub(2)) * 60 }, nil
    elseif tonumber(arg) and tonumber(arg) > 0 then
        sleep, sleep_fading = { mode = "time", at = now + tonumber(arg) * 60 }, nil
    else
        sleep, sleep_fading = nil, nil
    end
    publish_sleep()
end)

-- Pausing during the fade-out is the listener taking over: the timer is done.
mp.observe_property("pause", "bool", function(_, paused)
    if paused and sleep_fading then sleep_off() end
end)

mp.add_periodic_timer(1, function()
    if not sleep or sleep.mode ~= "time" or sleep_fading or os.time() < sleep.at then return end
    if mp.get_property_bool("pause") or mp.get_property_bool("idle-active") then
        sleep_off() -- nothing playing to stop
    else
        sleep_fading = mp.get_time()
    end
end)

-- ---------------------------------------------------------------- events

mp.register_event("file-loaded", function()
    read_settings()
    song = {
        url = mp.get_property("path") or "",
        title = mp.get_property("media-title") or "",
        length = mp.get_property_number("duration"),
        heard = switching or 0,
    }
    switching = nil
    -- Fade in only after a song that played to its end (not a skip or a pick).
    fade_in = last_end == "eof"
    applied = -1
    set_gain(gain_now() * sleep_gain())
    maybe_extend()
end)

mp.register_event("end-file", function(event)
    -- The song's video wouldn't play: its own sound, from where it was.
    if event.reason == "error" and swapped and event.playlist_entry_id then
        local index, entry = entry_by_id(event.playlist_entry_id)
        if index then
            video_off[entry.filename] = true
            swapped = false
            switching = song and song.heard or nil
            resume_at = mp.get_property_number("time-pos")
            song = nil
            mp.commandv("playlist-play-index", tostring(index))
            return
        end
    end
    -- Changing to (or from) its video's sound is the same listen.
    if switching then
        song = nil
        return
    end
    if song then
        song.length = song.length or mp.get_property_number("duration")
        note_play()
    end
    song = nil
    last_end = event.reason
    -- "End of this song": a skip doesn't count, the song finishing does.
    if event.reason == "eof" and sleep and sleep.mode == "end" then fall_asleep() end
    if event.reason == "error" and event.playlist_entry_id then fail_over(event.playlist_entry_id) end
end)

mp.observe_property("duration", "number", function(_, value)
    if song and value and value > 0 then song.length = value end
end)

mp.observe_property("playlist-count", "number", function()
    if song then maybe_extend() end
end)

mp.add_periodic_timer(TICK, function()
    if not song or mp.get_property_bool("pause") or mp.get_property_bool("core-idle") then return end
    song.heard = song.heard + TICK
    if sleep_fading and mp.get_time() - sleep_fading >= SLEEP_FADE then
        fall_asleep()
        set_gain(gain_now())
        return
    end
    set_gain(gain_now() * sleep_gain())
end)
