-- Happy Camper. Copyright (c) 2026 Torridon. All rights reserved; see LICENSE.
local addonName, ns = ...
local L = ns.L

-- Camp music: sounds for some emotes (lute strums, stoking the fire), and camp songs from the game's
-- own tavern and festival music. What's played is heard by players with the
-- addon at the same camp (never anyone else), through their own Music volume,
-- unless they've turned camp music off. A camp's song is picked by its owner
-- (Camps:CanPickSong, for as long as it burns), on the Camp tab, and loops through its tracks for as long
-- as you stay at the camp; it stops when you leave. When someone arrives, the
-- owner sends them the song, so they hear it too.
--
-- Most songs are the game's built-in music, by file ID (only music from the original
-- game: Forever's client doesn't have later music, such as Brewfest's), and
-- anyone can play any of them. Inspired songs are Happy Camper's own
-- (Media\Music), each found at one place: resting at a camp inside it
-- teaches you its song. The game's songs loop through their tracks, as the
-- camp's own song. Found songs (the Repertoire) are performed: anyone at a
-- camp can play one of theirs, once, for everyone there (Music:Perform).

local Music = {}
ns.Music = Music

-- The game's bard lute strums (sound/doodad/fx_bardluteperiodic_01..08).
Music.LUTE = { 1512550, 1512551, 1512552, 1512553, 1512554, 1512555, 1512556, 1512557 }

-- Sounds for emotes, by the line's sound key (the parked Social tab's lines:
-- other players' older copies may still send them): file IDs, one picked at random. stoke is the campfire flare (sound/spells/campfirecreateprecast);
-- drum the troll drums (sound/doodad/trolldrumloop1, fx_trollbattle_drumloop1/2_single).
Music.SOUNDS = {
    lute = Music.LUTE,
    stoke = { 569159 },
    drum = { 567027, 840238, 840240 },
}
-- Sounds cut off (with a short fade) after this many seconds: the drum files are long.
Music.SOUND_LIMIT = { drum = 8 }

-- Plays an emote's sound file, cut off at its limit.
local function PlayEffect(kind, file)
    local willPlay, handle = PlaySoundFile(file, "SFX")
    local limit = Music.SOUND_LIMIT[kind]
    if willPlay and handle and limit then
        C_Timer.After(limit, function() StopSound(handle, 500) end)
    end
end

-- A song's files, { file ID, length in seconds }: each song's files are
-- numbered in a row, from first; lengths are measured from the game's files.
local function Tracks(first, ...)
    local files = {}
    for i = 1, select("#", ...) do files[i] = { first + i - 1, (select(i, ...)) } end
    return files
end

-- An inspired song's files, { path, length in seconds }, from pairs of track
-- number and length: song_<zone>_<number>.ogg. Numbers can have gaps (each
-- song ships only some of its four tracks); lengths are the exact ones in
-- art/source/music/MUSIC.md.
local MUSIC_FOLDER = "Interface\\AddOns\\" .. (addonName or "HappyCamper") .. "\\Media\\Music\\"
local function Own(name, ...)
    local files = {}
    for i = 1, select("#", ...), 2 do
        local number, length = select(i, ...)
        files[#files + 1] = { format("%s%s_%d.ogg", MUSIC_FOLDER, name, number), length }
    end
    return files
end

-- label is the menu's; hint, for a song to be found, a riddle about where
-- (the Music tab shows it until it's found). race is UnitRace's second value ("Scourge" is Undead),
-- faction UnitFactionGroup's: a song with either is only for those players.
-- event: a found song learned by resting at a camp in one of its zones while
-- that event is on in the game (Music:CheckEvents). later: held back for a
-- later release: left out of the game (below) and its file out of the zip
-- (release.py); taking the mark off releases it.
Music.SONGS = {
    { key = "darkmoon", label = "Darkmoon Faire", hint = "When moon-marked tents rise in the fields near the great cities.", event = "darkmoon", game = true,
      zone = 1429, zones = { 1429, 1412 }, -- Elwynn Forest, Mulgore: where the Faire sets up
      files = Tracks(53256, 29, 75, 59, 38) },
    { key = "quiet", label = "Quiet night", files = Tracks(53495, 54, 43, 60, 55) },
    { key = "alliance", label = "Alliance tavern", faction = "Alliance", files = Tracks(53737, 48, 52) },
    { key = "horde", label = "Horde tavern", faction = "Horde", files = Tracks(53744, 49, 40, 48) },
    { key = "human", label = "Human tavern", race = { Human = true }, files = Tracks(53748, 93, 80, 87, 82, 71, 73) },
    { key = "dwarf", label = "Dwarven tavern", race = { Dwarf = true, Gnome = true }, files = Tracks(53739, 80, 83, 87, 92, 103) },
    { key = "nightelf", label = "Temple of the Moon", race = { NightElf = true }, files = Tracks(53754, 113, 120) },
    { key = "orc", label = "Orc rest area", race = { Orc = true, Troll = true }, files = Tracks(53756, 100, 92, 88, 87, 86, 82) },
    { key = "tauren", label = "Tauren rest stop", race = { Tauren = true }, files = Tracks(53768, 90, 97, 86, 81, 94, 94) },
    { key = "undead", label = "Undead tavern", race = { Scourge = true }, files = Tracks(53774, 94, 88, 125, 84, 94) },
    -- Inspired songs, each found at one place: resting at a camp inside it
    -- teaches it. areas: the game's area IDs (wago.tools AreaTable,
    -- wow_classic_beta), as in Badges.LANDMARKS; zone: the map ID of the zone
    -- it's in (Badges.REGIONS). Titles hint at the place without naming it.
    { key = "elwynn", label = "The Kobold's Candle Jig", hint = "Below the hills, where little thieves hoard their wax and wick.", zone = 1429, areas = { [57] = true }, -- Fargodeep Mine
      files = Own("song_elwynn", 1, 60.000) },
    { key = "dunmorogh", label = "The Ewe's First Snow in Dun Morogh", hint = "Where horned mounts are raised among the snows.", zone = 1426, areas = { [803] = true }, -- Amberstill Ranch
      files = Own("song_dunmorogh", 1, 60.000) },
    { key = "lochmodan", label = "The Dam Builder's Dram", hint = "Atop the great wall that holds back the waters.", zone = 1432, areas = { [146] = true }, -- Stonewrought Dam
      files = Own("song_lochmodan", 1, 60.000) },
    { key = "teldrassil", label = "The Lazy Wisp", hint = "In the glade where the children of the great tree first wake.", zone = 1438, areas = { [188] = true }, -- Shadowglen
      files = Own("song_teldrassil", 1, 59.402) },
    { key = "tirisfal", label = "Waltz for the Risen", hint = "Where the millstones stopped and the family never left.", zone = 1420, areas = { [157] = true }, -- Agamand Mills
      files = Own("song_tirisfal", 1, 59.611) },
    { key = "silverpine", label = "Bar the Shutters", hint = "A quiet village by day. Ask what it becomes by night.", zone = 1421, areas = { [204] = true }, -- Pyrewood Village
      files = Own("song_silverpine", 1, 59.585) },
    { key = "duskwood", label = "The Gravedigger's Jig", hint = "On the hill where black birds keep watch over the graves.", zone = 1431, areas = { [94] = true, [492] = true }, -- Raven Hill, Raven Hill Cemetery
      files = Own("song_duskwood", 1, 60.000) },
    { key = "barrens", label = "Raptors' Last Hunt", hint = "Where thunder walks on scaled feet across the long grass.", zone = 1413, areas = { [390] = true }, -- Field of Giants
      files = Own("song_barrens", 1, 60.000) },
    { key = "westernplaguelands", later = true, label = "The Bulwark at Dawn", hint = "Where the Light still holds, at the far end of the plagued lands.", zone = 1423, areas = { [2268] = true }, -- Light's Hope Chapel (Eastern Plaguelands)
      files = Own("song_westernplaguelands", 1, 60.000) },
    { key = "decrepitferry", label = "The Last Crossing", hint = "Where an old boat waits at the water's edge for one last fare.", zone = 1421, areas = { [237] = true }, -- The Decrepit Ferry
      files = Own("song_decrepitferry", 1, 60.000) },
    -- The second batch: places the author picked, landmarks and others.
    { key = "lastonestanding", later = true, label = "Last One Standing", hint = "Where the crowd roars and only one walks out with the prize.", zone = 1434, areas = { [1741] = true }, -- Gurubashi Arena (Stranglethorn Vale)
      files = Own("song_lastonestanding", 1, 60.000) },
    { key = "spotsmoonlight", later = true, label = "Spots in the Moonlight", hint = "On the cats' island, where spotted hunters prowl at night.", zone = 1434, areas = { [297] = true }, -- Jaguero Isle (Stranglethorn Vale)
      files = Own("song_spotsmoonlight", 1, 59.820) },
    { key = "dragonsdream", label = "The Dream Is All That Remains", hint = "In the grove where great green sleepers dream beneath the trees.", zone = 1431, areas = { [856] = true }, -- Twilight Grove (Duskwood)
      files = Own("song_dragonsdream", 1, 60.000) },
    { key = "violetdome", later = true, label = "Behind the Violet Glass", hint = "Where a city of mages hides beneath a shimmering dome.", zone = 1416, areas = { [279] = true, [17707] = true }, -- Dalaran and its old ruins (Alterac Mountains)
      files = Own("song_violetdome", 1, 60.000) },
    { key = "paladinsrest", later = true, label = "The Paladin's Rest", hint = "Where a fallen champion of the Light lies at rest.", zone = 1422, areas = { [196] = true }, -- Uther's Tomb (Western Plaguelands)
      files = Own("song_paladinsrest", 1, 55.745) },
    { key = "lonelytower", later = true, label = "The Lonely Tower in the Mist", hint = "On an island off the marsh, where a tower stands in the fog.", zone = 1445, areas = { [2079] = true }, -- Alcaz Island (Dustwallow Marsh)
      files = Own("song_lonelytower", 1, 60.000) },
    { key = "mirageraceway", label = "Full Throttle, Then Kaboom", hint = "Where rockets race across the salt flats and rarely finish.", zone = 1441, areas = { [2240] = true }, -- Mirage Raceway (Thousand Needles)
      files = Own("song_mirageraceway", 1, 60.000) },
    { key = "ziatajairuins", later = true, label = "Where the Jungle Took the Temple", hint = "Among jungle ruins where vines have swallowed old stone gods.", zone = 1434, areas = { [128] = true }, -- Ziata'jai Ruins (Stranglethorn Vale)
      files = Own("song_ziatajairuins", 1, 60.000) },
    -- The game's own pirate music, found like an inspired song at any of the
    -- pirate ports (game: it loops through its tracks like the game's songs;
    -- zones: every zone its places are in).
    { key = "pirate", label = "Pirate shanty", hint = "In any goblin port where sailors drink and coin changes hands.", game = true, zone = 1434, zones = { 1434, 1413 },
      areas = { [35] = true, [43] = true, [392] = true }, -- Booty Bay, Wild Shore (Stranglethorn Vale), Ratchet (the Barrens)
      files = Tracks(53762, 83, 82, 83, 82, 89, 86) },
}
-- Everyone at the camp sees the same emote whichever song it is.
Music.SONG_EMOTE = "strikes up a familiar tune."

-- Song names and the emote in the language in use (Locale.lua).
ns.OnLocale(function(L)
    ns.LocalizeFields(Music.SONGS, "label", "hint")
    Music.SONG_EMOTE = L[Music.SONG_EMOTE]
end)

-- Songs held back for a later release aren't in the game at all.
for i = #Music.SONGS, 1, -1 do
    if Music.SONGS[i].later then table.remove(Music.SONGS, i) end
end

local SONG_BY_KEY = {}
for _, song in ipairs(Music.SONGS) do SONG_BY_KEY[song.key] = song end

-- No song spam: only the camp's owner picks its song, at most every
-- SONG_CHANGE seconds; everyone else can mute it for themselves. PlayMusic
-- repeats one track, so when a track ends the song's next one starts.
local SONG_CHANGE = 60
local RESEND = 10         -- the same song again (for someone arriving): at most this often
local STRUM_COOLDOWN = 2
local lastFrom = {}       -- ["name|kind"] = { time, key }
local playing             -- { from = name, campID, song, index, ends } while a camp song plays
local muted               -- { campID, from, song, index }: the camp whose song you muted, and its song
-- Each camp's own song ([spot] = { song, from }): the last of the game's songs
-- played there (not a found one), which comes back when a found song ends.
-- Every client keeps it from the same messages, so they all go back together.
local campSong = {}
local preview             -- { song, paused } while you listen to a song on the Music tab (Music:Preview)
-- Performances (Music:Perform): the one playing at your camp, heard or not
-- ({ song, from, campID, ends }), and those waiting their turn, in the order
-- they arrived.
local performing
local queue = {}
local PERFORM_COOLDOWN = 300 -- yours: one song every 5 minutes
local PERFORM_HEARD = 240    -- someone else's, at most this often (a little less: clocks differ)
local lastOwnSong = -SONG_CHANGE
local lastResend = -RESEND

-- The songs you can play: everyone's, your faction's, your race's, and the
-- found songs you've learned.
function Music:Available()
    local _, race = UnitRace("player")
    local faction = UnitFactionGroup("player")
    local list = {}
    for _, song in ipairs(self.SONGS) do
        if (not song.race or song.race[race or ""]) and (not song.faction or song.faction == faction)
            and self:Learned(song.key) then
            list[#list + 1] = song
        end
    end
    return list
end

-- Whether you know a song: the game's always (your race's and faction's are
-- Available's to sort out), and a found one once a camp at its place (or, for
-- an event's, in its zones while the event is on) has inspired you
-- (db.songs, account-wide like badges: when, by the server's clock; true
-- from before that was kept).
function Music:Learned(key)
    local song = SONG_BY_KEY[key or ""]
    if not song then return false end
    if not song.zone then return true end
    local learned = ns.db and ns.db.songs
    return type(learned) == "table" and learned[key] ~= nil and learned[key] ~= false
end

-- Songs a character found before they were the account's (charDB.songs) join
-- the account's, at login: the earlier date wins; the character's copy goes.
function Music:MergeCharacterSongs()
    local mine = ns.charDB and ns.charDB.songs
    if type(mine) ~= "table" then return end
    if type(ns.db.songs) ~= "table" then ns.db.songs = {} end
    local songs = ns.db.songs
    for key, when in pairs(mine) do
        local had = songs[key]
        if type(when) == "number" and (type(had) ~= "number" or when < had) then
            songs[key] = when
        elseif had == nil and when then
            songs[key] = when
        end
    end
    ns.charDB.songs = nil
end

-- When you learned a found song (server time), if that's known.
function Music:LearnedAt(key)
    local learned = ns.db and ns.db.songs
    local when = type(learned) == "table" and learned[key or ""]
    return type(when) == "number" and when or nil
end

-- Two kinds of song. Camp tracks: the game's own music, looping through its
-- tracks (your race's and faction's, and found ones: the pirate shanty and
-- the Darkmoon Faire, song.game); the last one played at a camp is the camp's
-- own song. Repertoire: Happy Camper's own songs (found, song.zone, not
-- song.game), each played once, after which the camp's own song comes back.
function Music:IsRepertoire(song)
    return song ~= nil and song.zone ~= nil and not song.game
end

-- The songs you can play, by kind: camp tracks (the camp's own song, picked
-- by its owner) or your Repertoire (performed by anyone).
function Music:CampTracks()
    local list = {}
    for _, song in ipairs(self:Available()) do
        if not self:IsRepertoire(song) then list[#list + 1] = song end
    end
    return list
end

function Music:Repertoire()
    local list = {}
    for _, song in ipairs(self:Available()) do
        if self:IsRepertoire(song) then list[#list + 1] = song end
    end
    return list
end

-- The songs that have to be found, learned or not, in order: the Music tab's
-- collection.
function Music:Inspired()
    local list = {}
    for _, song in ipairs(self.SONGS) do
        if song.zone then list[#list + 1] = song end
    end
    return list
end

-- The game's calendar lists the Darkmoon Faire as a holiday, named in the
-- client's language. Looked at once, at login (Core.lua): whether it's on
-- today (Music.events.darkmoon), so resting at a camp in its zones finds its song.
local FAIRE_WORDS = { "darkmoon", "dunkelmond", "sombrelune", "luna negra", "negraluna", "暗月", "다크문" }
Music.events = {}

local function IsFaire(event)
    local title = type(event) == "table" and event.title
    if type(title) ~= "string" or ns.IsSecret(title) then return false end
    if event.calendarType and event.calendarType ~= "HOLIDAY" then return false end
    title = title:lower()
    for _, word in ipairs(FAIRE_WORDS) do
        if title:find(word, 1, true) then return true end
    end
    return false
end

local function FaireIsOn()
    local calendar, clock = C_Calendar, C_DateAndTime
    if not (calendar and calendar.GetNumDayEvents and calendar.GetDayEvent and calendar.SetAbsMonth
        and clock and clock.GetCurrentCalendarTime) then
        return false
    end
    -- The game's own calendar window, open, is left on its month.
    if CalendarFrame and CalendarFrame:IsShown() then return false end
    local today = clock.GetCurrentCalendarTime()
    if type(today) ~= "table" or not today.month then return false end
    calendar.SetAbsMonth(today.month, today.year)
    for i = 1, calendar.GetNumDayEvents(0, today.monthDay) or 0 do
        if IsFaire(calendar.GetDayEvent(0, today.monthDay, i)) then return true end
    end
    return false
end

function Music:CheckEvents()
    local ok, on = pcall(FaireIsOn)
    self.events.darkmoon = ok and on or nil
end

-- Resting at a camp (its Camp Benefits) inspires you: the song of the place
-- the camp is inside, if you don't know it yet, is yours from now on (found
-- by its areas wherever they are; an event's anywhere in its zones while the
-- event is on; a song with neither would be its whole zone's). A strum and a
-- line in your chat window say so; nothing is sent.
local function InZones(song, zone)
    for _, mapID in ipairs(song.zones or { song.zone }) do
        if mapID == zone then return true end
    end
    return false
end

function Music:Inspire(mapID)
    local zone = mapID and ns.ZoneOf(mapID)
    if not zone or not ns.db then return end
    local areas
    for _, song in ipairs(self.SONGS) do
        if song.zone and not self:Learned(song.key) then
            local here
            if song.event then
                here = self.events[song.event] and InZones(song, zone)
            elseif song.areas then
                areas = areas or ns.Location:AreaIDsHere()
                for id in pairs(song.areas) do here = here or areas[id] ~= nil end
            else
                here = song.zone == zone
            end
            if here then
                if type(ns.db.songs) ~= "table" then ns.db.songs = {} end
                ns.db.songs[song.key] = GetServerTime()
                if ns.db.songToast and ns.Songbook and ns.Songbook.Celebrate then
                    ns.Songbook:Celebrate(song)
                else
                    PlayEffect("lute", self.LUTE[math.random(#self.LUTE)])
                end
                ns.Print(L["You've found a song here: %s. Play it from the Camp tab."], song.label)
                if ns.Hub:IsShowing("camp") or ns.Hub:IsShowing("music") then ns.Hub:Refresh() end
            end
        end
    end
end

local function MyCampID()
    local camp = ns.Social:MyCamp()
    return camp and camp.id
end

local BARE_RADIUS = 30 -- yards: players this close to a bare fire's music hear it

-- Whether you're at a fire that isn't a camp (no camp buffs yet). Only its
-- music is shared, for roleplay.
function Music:AtBareFire()
    return ns.state.nearCamp and MyCampID() == nil
end

-- Where your music goes: the camp you're at (its ID); or at a bare fire, which
-- is never sent to the network, your rough position ("@mapID:x:y"), so only
-- players near it hear it.
local function MySpot()
    local id = MyCampID()
    if id or not ns.state.nearCamp then return id end
    local mapID, x, y = ns.GetPlayerLocation()
    if not mapID then return nil end
    return format("@%d:%d:%d", mapID, math.floor(x * 10000 + 0.5), math.floor(y * 10000 + 0.5))
end

-- Whether music for a spot (see MySpot) is where you are.
local function AtSpot(spot)
    if type(spot) ~= "string" then return false end
    local mapID, x, y = spot:match("^@(%d+):(%d+):(%d+)$")
    if not mapID then return spot == MyCampID() end
    if not Music:AtBareFire() then return false end
    local distance = ns.Camps:DistanceTo(tonumber(mapID), tonumber(x) / 10000, tonumber(y) / 10000)
    return distance ~= nil and distance <= BARE_RADIUS
end

local function StopPlaying()
    StopMusic()
    playing = nil
end

-- The Music tab shows whether you're listening; the Camp tab, a song paused for it.
local function PreviewChanged()
    if ns.Hub:IsShowing("music") or ns.Hub:IsShowing("camp") then ns.Hub:Refresh() end
end

local function Start(song, index, from, campID)
    local file, length = song.files[index][1], song.files[index][2]
    if not Music:IsRepertoire(song) and type(campID) == "string" then campSong[campID] = { song = song, from = from } end
    -- A camp song takes over from one you were listening to on the Music tab.
    if preview then
        preview = nil
        PreviewChanged()
    end
    PlayMusic(file)
    local this = { from = from, campID = campID, song = song, index = index, ends = GetTime() + length }
    playing = this
    -- When the track ends, while you're still at the camp (unless another song
    -- took over): a camp track goes on to its next track. A performance's own
    -- timer (NextPerformance) says what comes after it. Where it plays can move
    -- meanwhile: a bare fire's song goes on at the camp it becomes (Music:Update).
    C_Timer.After(length, function()
        if playing ~= this then return end
        if not AtSpot(this.campID) then
            StopPlaying()
        elseif not Music:IsRepertoire(song) then
            Start(song, index % #song.files + 1, from, this.campID)
        end
        if ns.Hub:IsShowing("camp") then ns.Hub:Refresh() end
    end)
end

-- Performances ---------------------------------------------------------------------------
-- Anyone at a camp can perform one of their found songs (the Repertoire) from
-- the Camp tab, at most every PERFORM_COOLDOWN: it plays once, in place of the
-- camp's own song, for everyone there with Happy Camper, whether they've found
-- it or not. Songs performed while one plays wait their turn, in the order they
-- arrived; after the last, the camp's own song comes back. Muted, or listening
-- on the Music tab, you hear none of it; unmuted mid-song, you hear from the
-- next one on.

-- Whether a song at a spot is heard now.
local function Audible(campID)
    return not preview and not (muted and muted.campID == campID) and AtSpot(campID)
end

-- After the last performance: the camp's own song, if it has one (or, muted,
-- the one Unmute brings back).
local function CampTrackBack(campID)
    local own = campSong[campID]
    if muted and muted.campID == campID then
        muted.song, muted.from, muted.index = own and own.song, own and own.from, 1
        return
    end
    if playing and Music:IsRepertoire(playing.song) then StopPlaying() end
    if own and Audible(campID) then Start(own.song, 1, own.from, campID) end
end

-- The next song waiting, if there is one (false if not).
local function NextPerformance()
    local entry
    repeat entry = table.remove(queue, 1) until not entry or AtSpot(entry.campID)
    if not entry then return false end
    local length = entry.song.files[1][2]
    entry.ends = GetTime() + length
    performing = entry
    C_Timer.After(length, function()
        if performing ~= entry then return end
        performing = nil
        if not NextPerformance() then CampTrackBack(entry.campID) end
        if ns.Hub:IsShowing("camp") then ns.Hub:Refresh() end
    end)
    if Audible(entry.campID) then
        Start(entry.song, 1, entry.from, entry.campID)
    elseif preview and not muted then
        -- Listening on the Music tab: the camp's song comes back when you're done.
        local own = campSong[entry.campID]
        muted = { campID = entry.campID, from = own and own.from, song = own and own.song, index = 1 }
        preview.paused = true
    end
    return true
end

-- A performance joins the queue (and plays at once if none is playing).
local function Enqueue(song, from, campID)
    queue[#queue + 1] = { song = song, from = from, campID = campID }
    if not performing then NextPerformance() end
    if ns.Hub:IsShowing("camp") then ns.Hub:Refresh() end
end

-- Whether you can perform now; if not, why.
function Music:CanPerform()
    if not ns.Social:IsAtCamp() or not MySpot() then return false, L["Go to a camp to play this song."] end
    local wait = (ns.charDB.performedAt or 0) + PERFORM_COOLDOWN - GetServerTime()
    if wait > 0 then return false, format(L["You can perform again in %s."], ns.FormatTime(wait)) end
    return true
end

-- You perform one of your found songs: it joins the queue, for you and
-- everyone at your camp, with the 'familiar tune' emote (it's a click).
-- Performing unmutes the camp for you.
function Music:Perform(key)
    local song = SONG_BY_KEY[key or ""]
    if not self:IsRepertoire(song) or not self:Learned(key) or not self:CanPerform() then return false end
    if preview then self:StopPreview() end
    local campID = MySpot()
    if muted and muted.campID == campID then muted = nil end
    ns.charDB.performedAt = GetServerTime()
    Enqueue(song, ns.playerName, campID)
    ns.Announce:Send(self.SONG_EMOTE, "EMOTE", 3)
    ns.Comm:SendMusic(campID, key, 1)
    return true
end

-- The song being performed at your camp, who's performing it, and how many
-- wait after it; or nil.
function Music:Performing()
    if not performing then return nil end
    return performing.song.label, performing.from, #queue
end

-- Whether you can start a song now; if not, why.
function Music:CanPlaySong()
    local camp = ns.Social:MyCamp()
    if not camp then
        -- At a bare fire, whoever lit it picks its song.
        if not self:AtBareFire() then return false, L["Sit at a camp to play its song."] end
        if not ns.Camps:LitFire(true) then return false, L["Only whoever lit this fire can pick its song."] end
    elseif not ns.Camps:CanPickSong(camp) then
        return false, format(L["Only %s, who set up this camp, can pick its song."], ns.FirstName(camp.creator))
    end
    local wait = SONG_CHANGE - (GetTime() - lastOwnSong)
    if wait > 0 then
        return false, format(L["You can change the song in %s."], ns.FormatTime(wait))
    end
    return true
end

-- What's playing: its name and who started it; or nil.
function Music:NowPlaying()
    if not playing then return nil end
    return playing.song.label, playing.from, self:IsRepertoire(playing.song)
end

-- Whether you muted the song of the camp you're at; and its name, if it has one.
function Music:Muted()
    if not muted or not AtSpot(muted.campID) then return false end
    return true, muted.song and muted.song.label
end

-- Your own camp song, paused for you while you listen on the Music tab: it
-- goes on for everyone else, and is still yours to stop.
local function PausedOwnSong()
    if preview and preview.paused and muted and muted.song and muted.from == ns.playerName and AtSpot(muted.campID) then
        return muted
    end
end

-- The camp's own song now: who started it, and whether it's yours (while
-- songs are performed, the one that comes back after them).
function Music:Current()
    local song = playing or PausedOwnSong()
    if song and self:IsRepertoire(song.song) then song = campSong[song.campID] end
    return song and song.from, song ~= nil and song.from == ns.playerName
end

-- Turns the camp's song off for you only, until you unmute it (a new song
-- from the owner stays muted too).
function Music:Mute()
    if not playing then return end
    muted = { campID = playing.campID, from = playing.from, song = playing.song, index = playing.index, ends = playing.ends }
    StopPlaying()
end

-- Plays the camp's song again for you.
function Music:Unmute()
    local was = muted
    muted = nil
    if not was or not AtSpot(was.campID) then return end
    -- During a performance: heard from the next song on.
    if performing and performing.campID == was.campID then return end
    if was.song and not Music:IsRepertoire(was.song) then
        Start(was.song, was.index, was.from, was.campID)
    else
        local own = campSong[was.campID]
        if own then Start(own.song, 1, own.from, was.campID) end
    end
end

-- Listening on the Music tab: an inspired song you've learned plays once, just
-- for you (nothing is sent). A camp song you're hearing is muted for you
-- meanwhile, and comes back when you stop or the song ends; one that starts
-- while you listen waits too. Playing a camp song yourself, or Unmute on the
-- Camp tab, ends the listening instead. It starts only at a camp (or a fire),
-- and plays to its end if you walk away.
function Music:CanListen()
    if ns.Social:IsAtCamp() then return true end
    return false, L["Go to a camp to play this song."]
end

function Music:Preview(key)
    local song = SONG_BY_KEY[key or ""]
    if not song or not song.zone or not self:Learned(key) or not self:CanListen() then return false end
    local paused = preview ~= nil and preview.paused -- from one song to the next, the camp's stays paused
    if playing then
        self:Mute()
        paused = true
    end
    local this = { song = song, paused = paused }
    preview = this
    PlayMusic(song.files[1][1])
    C_Timer.After(song.files[1][2], function()
        if preview == this then Music:StopPreview() end
    end)
    PreviewChanged()
    return true
end

function Music:StopPreview()
    local was = preview
    if not was then return end
    preview = nil
    StopMusic()
    if was.paused and muted then self:Unmute() end
    PreviewChanged()
end

-- The key of the song you're listening to on the Music tab, or nil.
function Music:Previewing()
    return preview and preview.song.key
end

-- Your picked camp track (charDB.campSong), if you can still play it; or nil.
function Music:Pick()
    local key = ns.charDB and ns.charDB.campSong
    for _, song in ipairs(self:CampTracks()) do
        if song.key == key then return key end
    end
end

function Music:SetPick(key)
    if SONG_BY_KEY[key or ""] then ns.charDB.campSong = key end
end

-- The fire you set up and are at, by its camp ID: your lit fire's is the ID
-- its camp gets (Camps.lua's NewCamp). nil anywhere else.
local function OwnFireKey()
    local camp = ns.Social:MyCamp()
    if camp then return ns.Camps:CanPickSong(camp) and camp.id or nil end
    local lit = Music:AtBareFire() and ns.Camps:LitFire(true)
    return lit and ns.playerName .. ":" .. lit.placedAt or nil
end

local autoPlayed = {} -- [fire key] = true: fires whose song has had its chance to start

-- You play a song: it starts for you, and for others at your camp, and it's
-- your pick from now on. Started by itself (auto), it has no emote: nothing
-- others can read is ever sent without a click.
function Music:PlaySong(key, auto)
    local song = SONG_BY_KEY[key]
    if not song or not self:CanPlaySong() then return end
    local allowed = false
    for _, available in ipairs(self:CampTracks()) do allowed = allowed or available == song end
    if not allowed then return end
    lastOwnSong = GetTime()
    muted = nil
    self:SetPick(key)
    local fire = OwnFireKey()
    if fire then autoPlayed[fire] = true end
    local index = math.random(#song.files)
    local campID = MySpot()
    if performing and performing.campID == campID then
        -- Songs are being performed: it's the camp's song after them.
        campSong[campID] = { song = song, from = ns.playerName }
    else
        Start(song, index, ns.playerName, campID)
    end
    if not auto then ns.Announce:Send(self.SONG_EMOTE, "EMOTE", 3) end
    if campID then ns.Comm:SendMusic(campID, key, index) end
end

-- Called every tick. Your picked song starts by itself once at each fire you
-- light and each camp you're the first with the addon to set up (the autoSong
-- option). A song you play at your bare fire carries on when the fire becomes
-- your camp, and everyone there hears it.
function Music:Update()
    local fire = OwnFireKey()
    if not fire then return end
    if playing and playing.from == ns.playerName and not self:IsRepertoire(playing.song) then
        local campID = MyCampID()
        if campID and type(playing.campID) == "string" and playing.campID:sub(1, 1) == "@" then
            playing.campID = campID
            ns.Comm:SendMusic(campID, playing.song.key, playing.index)
        end
        autoPlayed[fire] = true
        return
    end
    if autoPlayed[fire] then return end
    autoPlayed[fire] = true
    local pick = self:Pick()
    if ns.db.autoSong and pick and not playing and not self:Muted() and self:CanPlaySong() then
        self:PlaySong(pick, true)
    end
end

-- Someone arrived at your camp: if you're playing its song, send it again so
-- they hear it (the others already playing it ignore it). At most every
-- RESEND seconds: someone arriving sooner gets it when that's up.
local resendPending = false

-- Your camp song at a camp, if it's yours: its song and track (while songs
-- are performed, the one that comes back after them).
local function OwnTrack(campID)
    local own = playing or PausedOwnSong()
    if not own or own.campID ~= campID then return end
    if Music:IsRepertoire(own.song) then
        local track = campSong[campID]
        if track and track.from == ns.playerName then return track.song, 1 end
    elseif own.from == ns.playerName then
        return own.song, own.index
    end
end

function Music:OnArrival(campID)
    if not OwnTrack(campID) then return end
    if resendPending then return end -- the one on its way reaches them too
    resendPending = true
    C_Timer.After(math.max(1 + math.random() * 2, lastResend + RESEND - GetTime()), function()
        resendPending = false
        local song, index = OwnTrack(campID)
        if song then
            lastResend = GetTime()
            ns.Comm:SendMusic(campID, song.key, index)
        end
    end)
end

function Music:Stop()
    -- Others stop too if it was your song (even paused while you listen on
    -- the Music tab, which then plays on).
    -- While songs are performed they play on: only what comes after them goes.
    local paused = not playing and PausedOwnSong()
    local own = playing or paused
    local performance = own and self:IsRepertoire(own.song)
    local track = performance and campSong[own.campID] or own
    local campID = track and track.from == ns.playerName and own.campID
    if performance then
        if muted and muted.campID == own.campID and campID then muted.song = nil end
    elseif paused then
        muted = nil
    elseif playing or not preview then
        StopPlaying()
    end
    -- Stopped by its owner, the camp has no song of its own any more.
    if campID then
        campSong[campID] = nil
        ns.Comm:SendMusic(campID, "stop", 0)
    end
end

-- Music from another player: only if they're at your camp (or, for its song,
-- own it), you're at it too, camp music is on, and they're not playing too
-- often. Only known songs and strums are played; only whoever started a camp
-- song can stop it. Camp songs only from the camp's owner; a performance from
-- anyone there, found by you or not.
function Music:OnMessage(sender, campID, key, index)
    if not ns.db.campMusic or type(campID) ~= "string" then return end
    if not AtSpot(campID) then return end
    -- lute: any emote sound (they share a cooldown).
    local lute = self.SOUNDS[key or ""] ~= nil
    local song = not lute and SONG_BY_KEY[key or ""]
    local perform = song and self:IsRepertoire(song)
    -- At a camp, only from someone who says they're at it, or the owner's song
    -- (sent to someone just arriving, maybe before the owner's presence
    -- reached them); a bare fire has no presence (or owner) to check, only the
    -- distance and the rate limits.
    local bare = campID:sub(1, 1) == "@"
    local camp = not bare and ns.Camps:Get(campID)
    local owner = camp and camp.creator == sender
    if not bare and not (owner and song and not perform) and not ns.Social:IsPersonAtCamp(sender, campID) then return end
    index = tonumber(index)
    if key == "stop" then
        if playing and playing.from == sender and not self:IsRepertoire(playing.song) then StopPlaying() end
        if campSong[campID] and campSong[campID].from == sender then campSong[campID] = nil end
        if muted and muted.from == sender and muted.campID == campID then muted.song = nil end
        return
    end
    local files = lute and self.SOUNDS[key] or song and song.files
    if not files or not index or not files[index] then return end
    -- A camp song you're already hearing (sent again for someone arriving)
    -- changes nothing, except where it is: a bare fire's song moves to the camp it became.
    if song and not perform and playing and playing.from == sender and playing.song == song then
        playing.campID = campID
        return
    end
    local limitKey = sender .. (lute and "|lute" or perform and "|perform" or "|song")
    local now, last = GetTime(), lastFrom[limitKey]
    local wait = lute and STRUM_COOLDOWN or perform and PERFORM_HEARD or last and last[2] == key and RESEND or SONG_CHANGE
    if last and now - last[1] < wait then return end
    if not lute and not perform and not bare and not owner then return end
    lastFrom[limitKey] = { now, key }
    if lute then
        PlayEffect(key, files[index])
    elseif perform then
        Enqueue(song, sender, campID)
    elseif performing and performing.campID == campID then
        -- Songs are being performed: it's the camp's song after them.
        campSong[campID] = { song = song, from = sender }
        if muted and muted.campID == campID then muted.from, muted.song, muted.index = sender, song, index end
    elseif muted and muted.campID == campID then
        campSong[campID] = { song = song, from = sender }
        muted.from, muted.song, muted.index, muted.ends = sender, song, index, GetTime() + files[index][2]
    elseif preview then
        -- You're listening on the Music tab: the camp's song waits until you're done.
        campSong[campID] = { song = song, from = sender }
        muted = { campID = campID, from = sender, song = song, index = index, ends = GetTime() + files[index][2] }
        preview.paused = true
    else
        Start(song, index, sender, campID)
    end
end

-- Leaving the camp stops its music. A song you're listening to on the Music
-- tab plays to its end (only starting one needs a camp).
function Music:OnLeftCamp()
    if playing then StopPlaying() end
    wipe(campSong)
    wipe(queue)
    performing = nil
    if ns.Hub:IsShowing("music") then ns.Hub:Refresh() end
end

function Music:IsPlaying()
    return playing ~= nil
end
