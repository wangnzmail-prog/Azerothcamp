-- Happy Camper. Copyright (c) 2026 Torridon. All rights reserved; see LICENSE.
local _, ns = ...
local L = ns.L

-- Something on the map between live camps, while there are few: ashes where
-- camps burned out lately, and popular campsites, spots where players often
-- camp. Neither is a camp: each has its own look on the map (MapPins.lua) and
-- says what it is in its tooltip, and neither ever counts as a camp (the camp
-- bar's count, Find a camp, the camp you're at). Both are kept on this
-- computer only: nothing here is sent.
--
-- Ashes (db.ashes): a confirmed camp that burns out, or whose creator says it's
-- gone, leaves ashes for ASH_FOR, with its name and what it had.
-- Popular campsites: the beta's (CampsiteData.lua), and spots learned here
-- (db.campsites): each camp that ends counts for its spot, for SPOT_FOR, and
-- one where MIN_PLAYERS different players have camped in that time is popular.
-- So a spot fades as camping there stops, and one nobody has camped at for
-- SPOT_FOR is forgotten.
-- Each is for its own faction (and a learned one for its realm). A live camp
-- at a spot hides its ashes or campsite, and ashes hide a campsite.

local Campsites = {}
ns.Campsites = Campsites

Campsites.ASH_FOR = 3 * 60 * 60
Campsites.SPOT_RADIUS = 40     -- yards: one spot, as for one camp (Camps.MERGE_RADIUS)
Campsites.MIN_PLAYERS = 2      -- different players' camps that make a spot popular
Campsites.SPOT_FOR = 14 * 24 * 60 * 60 -- how long a camp at a spot counts for it
Campsites.PER_MAP = 15         -- at most this many ashes, and as many campsites, on a zone's map
local MAX_ASHES = 100
local MAX_SPOTS = 300
local MAX_MARKS = 10           -- players a learned spot keeps a mark of (only how many matters)

local function Now() return GetServerTime() end

-- A number for a player's name, the same each time: a spot keeps these, not names.
local function Mark(name)
    local hash = 5381
    for i = 1, #name do hash = (hash * 33 + name:byte(i)) % 2147483647 end
    return hash
end

-- Fills in a record's world position from its map spot, if it hasn't one;
-- returns whether it has one.
local function Placed(record)
    if not record.continent and record.mapID then
        record.continent, record.wx, record.wy = ns.Camps.WorldPosition(record.mapID, record.x, record.y)
    end
    return record.continent ~= nil and record.wx ~= nil
end

local function Near(a, b, radius)
    local distance = Placed(a) and Placed(b) and ns.Camps.WorldDistance(a, b.continent, b.wx, b.wy)
    return distance and distance <= radius or false
end

-- The beta's popular spots (CampsiteData.lua), as records: made once (again if
-- the list is swapped, as the tests do).
local seed, seedFrom
local function Seed()
    if not seed or seedFrom ~= ns.CAMPSITE_SEED then
        seed, seedFrom = {}, ns.CAMPSITE_SEED
        for i, spot in ipairs(ns.CAMPSITE_SEED or {}) do
            seed[i] = { id = "seed:" .. i, mapID = spot[1], x = spot[2], y = spot[3], faction = spot[4], seed = true }
        end
    end
    return seed
end

-- The ashes kept, with any older than ASH_FOR gone.
function Campsites:Ashes()
    local ashes, cutoff = ns.db.ashes, Now() - self.ASH_FOR
    for i = #ashes, 1, -1 do
        if (ashes[i].at or 0) < cutoff then table.remove(ashes, i) end
    end
    return ashes
end

-- A learned spot's players who camped there in the last SPOT_FOR, as
-- { m = their mark, at = when }, with the older ones gone. (Before marks had
-- times they were bare numbers: those count from the spot's last camp.)
local function RecentMarks(spot)
    local cutoff, kept = Now() - Campsites.SPOT_FOR, {}
    for _, entry in ipairs(spot.marks or {}) do
        if type(entry) == "number" then entry = { m = entry, at = spot.last or 0 } end
        if (entry.at or 0) >= cutoff then kept[#kept + 1] = entry end
    end
    spot.marks = kept
    return kept
end

-- Counts a camp for its spot (a learned campsite), by who camped there.
-- Spots nobody has camped at for SPOT_FOR are forgotten first.
function Campsites:CountCamp(camp)
    local spots, spot = ns.db.campsites, nil
    for i = #spots, 1, -1 do
        if #RecentMarks(spots[i]) == 0 then table.remove(spots, i) end
    end
    for _, known in ipairs(spots) do
        if known.realm == camp.realm and known.faction == camp.faction and Near(known, camp, self.SPOT_RADIUS) then
            spot = known
            break
        end
    end
    if not spot then
        spot = { mapID = camp.mapID, x = camp.x, y = camp.y, continent = camp.continent, wx = camp.wx, wy = camp.wy,
            realm = camp.realm, faction = camp.faction, marks = {} }
        spot.id = format("spot:%s:%d:%d", tostring(spot.mapID), math.floor(spot.x * 1000), math.floor(spot.y * 1000))
        spots[#spots + 1] = spot
        if #spots > MAX_SPOTS then
            -- The one seen longest ago makes room.
            local oldest = 1
            for i, known in ipairs(spots) do
                if (known.last or 0) < (spots[oldest].last or 0) then oldest = i end
            end
            table.remove(spots, oldest)
        end
    end
    local now = Now()
    spot.last = now
    local mark, marks = Mark(tostring(camp.creator or camp.id)), RecentMarks(spot)
    for i, known in ipairs(marks) do
        if known.m == mark then
            -- Camped there again: theirs counts from now, and goes last.
            table.remove(marks, i)
            break
        end
    end
    marks[#marks + 1] = { m = mark, at = now }
    if #marks > MAX_MARKS then table.remove(marks, 1) end
end

-- A camp has ended (burnt out, or its creator said it's gone): its ashes, in
-- place of any older ones at its spot, and it counts for its spot. Not a camp
-- that was never confirmed (from chat, or seen in passing), or a test one.
function Campsites:OnCampEnded(camp)
    if not camp or camp.test or camp.demo or ns.Camps:Unconfirmed(camp) then return end
    if not (camp.mapID and camp.x and camp.continent and camp.wx) then return end
    local ash = { id = "ash:" .. tostring(camp.id), mapID = camp.mapID, x = camp.x, y = camp.y,
        continent = camp.continent, wx = camp.wx, wy = camp.wy, at = Now(),
        name = ns.Camps:DisplayName(camp), realm = camp.realm, faction = camp.faction, objects = {} }
    for _, object in ipairs(ns.Camps:ObjectList(camp)) do ash.objects[#ash.objects + 1] = object.name end
    local ashes = self:Ashes()
    for i = #ashes, 1, -1 do
        if Near(ashes[i], ash, self.SPOT_RADIUS) then table.remove(ashes, i) end
    end
    ashes[#ashes + 1] = ash
    while #ashes > MAX_ASHES do table.remove(ashes, 1) end
    self:CountCamp(camp)
    ns.OnCampsChanged()
end

-- How many different players have camped at a learned spot lately (in
-- SPOT_FOR): it's popular with MIN_PLAYERS.
local function Players(spot)
    return #RecentMarks(spot)
end
local function Popular(spot)
    return Players(spot) >= Campsites.MIN_PLAYERS
end

-- The ashes and popular campsites to show on a zone's map (none on a
-- continent's or the world's), each as { kind = "ash" or "spot", record, x, y }:
-- the newest ashes and the most camped spots first, PER_MAP of each at most.
function Campsites:OnMap(uiMapID)
    local list = {}
    if not uiMapID or ns.IsWideMap(uiMapID) then return list end
    local showAshes, showSpots = ns.db.mapAshes, ns.db.mapCampsites
    if not showAshes and not showSpots then return list end
    local zone, faction = ns.ZoneOf(uiMapID), UnitFactionGroup("player")
    local function InZone(record)
        return ns.ZoneOf(record.mapID) == zone and (record.faction == nil or record.faction == faction)
    end
    -- Nothing where a camp is now.
    local function ByACamp(record)
        for _, camp in pairs(ns.db.camps) do
            if camp.continent and Near(record, camp, Campsites.SPOT_RADIUS) then return true end
        end
        return false
    end

    local ashes = {}
    if showAshes then
        for _, ash in ipairs(self:Ashes()) do
            if (ash.realm == nil or ash.realm == ns.realm) and InZone(ash) and not ByACamp(ash) then ashes[#ashes + 1] = ash end
        end
        table.sort(ashes, function(a, b) return a.at > b.at end)
        for i = 1, math.min(#ashes, self.PER_MAP) do
            local x, y = ns.Camps:Project(ashes[i], uiMapID)
            if x then list[#list + 1] = { kind = "ash", record = ashes[i], x = x, y = y } end
        end
    end
    if showSpots then
        local spots = {}
        local function Add(spot, players)
            if not InZone(spot) or ByACamp(spot) then return end
            for _, ash in ipairs(ashes) do
                if Near(spot, ash, self.SPOT_RADIUS) then return end
            end
            for _, other in ipairs(spots) do
                if Near(spot, other.record, self.SPOT_RADIUS) then return end
            end
            spots[#spots + 1] = { record = spot, players = players }
        end
        for _, spot in ipairs(ns.db.campsites) do
            if spot.realm == ns.realm and Popular(spot) then Add(spot, Players(spot)) end
        end
        for _, spot in ipairs(Seed()) do Add(spot, self.MIN_PLAYERS) end
        table.sort(spots, function(a, b) return a.players > b.players end)
        for i = 1, math.min(#spots, self.PER_MAP) do
            local x, y = ns.Camps:Project(spots[i].record, uiMapID)
            if x then list[#list + 1] = { kind = "spot", record = spots[i].record, x = x, y = y } end
        end
    end
    return list
end

-- How long ago, in words: "12 min" or "2 h 5 min".
local function Ago(seconds)
    local minutes = math.max(1, math.floor(seconds / 60))
    if minutes < 60 then return format(L["%d min"], minutes) end
    return format(L["%d h %d min"], math.floor(minutes / 60), minutes % 60)
end

-- An ash's or campsite's tooltip: what it is, and that a fire lit there shows.
function Campsites:FillTooltip(tooltip, kind, record)
    if kind == "ash" then
        tooltip:AddLine(L["A camp burned out here"], 0.85, 0.65, 0.45)
        tooltip:AddLine(format(L["%s ago"], Ago(Now() - (record.at or Now()))), 1, 1, 1)
        if record.name then tooltip:AddLine(record.name, 0.75, 0.75, 0.75) end
        if ns.IsEnhanced() and record.objects and #record.objects > 0 then
            tooltip:AddLine(format(L["It had: %s"], ns.JoinList(record.objects)), 0.75, 0.75, 0.75, true)
        end
    else
        tooltip:AddLine(L["Popular campsite"], 0.9, 0.75, 0.45)
        tooltip:AddLine(L["Players often camp here. There's no fire here right now."], 1, 1, 1, true)
    end
    tooltip:AddLine(L["Light a fire here, and other campers will see it."], 0.6, 0.8, 1, true)
end
