-- Happy Camper. Copyright (c) 2026 Torridon. All rights reserved; see LICENSE.
local _, ns = ...
local L = ns.L

-- Known campsites: yours and other players'. Saved across /reload.
-- camp = {
--   id          "<creator full name>:<server time>", tied to the sender
--   creator, realm, owned (the creator lit the fire, so expiresAt is exact)
--   location    { area, direction, zone, region } for its name (Location.lua)
--   nameKey     a name picked by the fire-lighter (Names.lua); nil = location name
--   nearby      (your own camps) nearby area names, and nearbyIDs their area
--               IDs, for the name choices
--   mapID, x, y / continent, wx, wy   map and world position
--   placedAt, expiresAt, updated      server times
--   objects     [spellID] = true, objects placed by players with the addon
--   professions [skillLineID] = true
--   equipment   [skillLineID] = tier (1-3), read from Camp Benefits tooltips
--   chat        unconfirmed: posted as a map pin in chat (ChatPins.lua), or
--               from another camp addon (via): yours alone, never sent
--   via         the other camp addon it came from (Others.lua)
--   approximate said in chat near you (no pin): placed where you were
--   passing     seen in passing (its objects hovered, nobody rested there yet):
--               where the player who saw it stood, so only roughly placed
-- }

local Camps = {}
ns.Camps = Camps

local MAX_CAMPS = 200
local MAX_UNCONFIRMED = 50 -- of them, from chat and other addons (they never push out real ones)
local MAX_ENTRIES = 12 -- objects kept per camp
Camps.MERGE_RADIUS = 40 -- yards: an object or buff this close belongs to the camp

local function Now() return GetServerTime() end

-- While Upsert takes in a camp, its own changes don't each ask for a redraw:
-- Upsert asks once, at the end, and only if something changed.
local quietCamp

-- A camp changed: note when, and redraw.
local function Touch(camp)
    camp.updated = Now()
    if camp ~= quietCamp then ns.OnCampsChanged() end
end

-- Who lit or reported a camp, without the realm.
local function CreatorName(camp)
    return Ambiguate(camp.creator or "?", "short")
end

function Camps:All()
    return ns.db.camps
end

function Camps:Get(id)
    return ns.db.camps[id]
end

local Count = ns.Count

-- One vector reused for every map lookup: a new one per call (hundreds a
-- second while the map, panel and minimap update) would only make garbage.
local scratch
local function Vector(x, y)
    scratch = scratch or CreateVector2D(0, 0)
    scratch.x, scratch.y = x, y
    return scratch
end

local function WorldPosition(mapID, x, y)
    local continent, pos = C_Map.GetWorldPosFromMapPos(mapID, Vector(x, y))
    if continent and pos then
        local wx, wy = ns.XY(pos)
        return continent, wx, wy
    end
end
Camps.WorldPosition = WorldPosition

-- Distance in yards from a world position (continent, wx, wy) to a camp or
-- request, or nil if either isn't known or they're on different continents.
local function WorldDistance(record, continent, wx, wy)
    if not continent or continent ~= record.continent or not record.wx then return end
    local dx, dy = wx - record.wx, wy - record.wy
    return math.sqrt(dx * dx + dy * dy)
end
Camps.WorldDistance = WorldDistance

-- Where a record (camp or request) appears on a map, as 0-1 coordinates, or
-- nil if it isn't on that map.
function Camps:Project(record, uiMapID)
    local x, y
    if record.mapID == uiMapID then
        x, y = record.x, record.y
    elseif record.continent then
        local _, pos = C_Map.GetMapPosFromWorldPos(record.continent, Vector(record.wx, record.wy), uiMapID)
        if pos then x, y = ns.XY(pos) end
    end
    if x and x >= 0 and x <= 1 and y >= 0 and y <= 1 then return x, y end
end

-- A map's size in yards: width, height (worked out from its corners if the
-- game can't say), or nil if it can't be told.
local mapYards = {}
function ns.MapYards(mapID)
    if not mapYards[mapID] then
        local width, height
        if C_Map.GetMapWorldSize then width, height = C_Map.GetMapWorldSize(mapID) end
        if not width or width == 0 then
            local c0, x0, y0 = WorldPosition(mapID, 0, 0)
            local c1, x1, y1 = WorldPosition(mapID, 1, 0)
            local c2, x2, y2 = WorldPosition(mapID, 0, 1)
            if not (c0 and c1 and c2) then return end
            width = math.sqrt((x1 - x0) ^ 2 + (y1 - y0) ^ 2)
            height = math.sqrt((x2 - x0) ^ 2 + (y2 - y0) ^ 2)
        end
        if not width or width <= 0 or not height or height <= 0 then return end
        mapYards[mapID] = { width, height }
    end
    return mapYards[mapID][1], mapYards[mapID][2]
end

-- Smoke: in Standard mode (Mode.lua) other players' camps show on the maps as
-- a haze of smoke about the fire, not an exact spot: you can see roughly where
-- it is. The fire is somewhere inside the smoke but never in its middle: the
-- smoke drifts off it by a share of its radius, in a direction worked out from
-- the camp's ID, so everyone sees the same smoke for a camp, and it stays put.
Camps.SMOKE_RADIUS = 100 -- yards: the smoke is about 200 yards across
local SMOKE_NEAREST, SMOKE_FARTHEST = 0.25, 0.6 -- how far the smoke's middle is from the fire, in radii
local SMOKE_MAP_YARDS = 4000 -- a zone's size, for a map whose size can't be told

-- A number from a camp's ID, the same on every player's computer.
local function Hash(text)
    local hash = 5381
    for i = 1, #text do hash = (hash * 33 + text:byte(i)) % 4294967296 end
    return hash
end

-- Whether a camp shows as smoke: in Standard mode, every camp but your own and
-- the one you're at (here: the camp you're at, or false if none; worked out if
-- not given).
function Camps:Smoky(camp, here)
    if ns.IsEnhanced() or self:IsMine(camp) then return false end
    if here == nil then here = self:NearPlayer(self.MERGE_RADIUS) or false end
    return not (here and here.id == camp.id)
end

-- Yards east and north from a camp's fire to the middle of its smoke.
function Camps:SmokeOffset(camp)
    local hash = Hash(tostring(camp.id))
    local angle = (hash % 360) / 180 * math.pi
    local share = SMOKE_NEAREST + (SMOKE_FARTHEST - SMOKE_NEAREST) * (math.floor(hash / 360) % 101) / 100
    local distance = share * self.SMOKE_RADIUS
    return distance * math.cos(angle), distance * math.sin(angle)
end

-- A camp's smoke on a map, where the camp is at x, y on it: its middle (x, y)
-- and its radius across and down the map (each a share of the map's size).
function Camps:SmokeOnMap(camp, mapID, x, y)
    local width, height = ns.MapYards(mapID)
    if not width then width, height = SMOKE_MAP_YARDS, SMOKE_MAP_YARDS end
    local east, north = self:SmokeOffset(camp)
    return x + east / width, y - north / height, self.SMOKE_RADIUS / width, self.SMOKE_RADIUS / height
end

-- A camp's smoke on a continent's or the world's map: the same middle as on
-- its own zone's map, carried over through the world position, so it never
-- gives away the fire's spot either; and its radius across and down that map
-- (0 if the map's size can't be told: MapPins draws it no smaller than a dot).
-- nil if the smoke isn't on that map.
function Camps:SmokeOnWideMap(camp, mapID)
    local sx, sy = self:SmokeOnMap(camp, camp.mapID, camp.x, camp.y)
    local continent, wx, wy = WorldPosition(camp.mapID, sx, sy)
    if not continent then return end
    local x, y = self:Project({ continent = continent, wx = wx, wy = wy }, mapID)
    if not x then return end
    local width, height = ns.MapYards(mapID)
    return x, y, width and self.SMOKE_RADIUS / width or 0, height and self.SMOKE_RADIUS / height or 0
end

-- A map's details (name, type, parent), as C_Map.GetMapInfo gives them. They
-- never change, so each map's are asked for once and kept: the map, the panel
-- and the minimap look them up for every camp, every second. A map the game
-- doesn't know is asked about again each time. Don't change the table.
local mapInfo = {}
function ns.MapInfo(mapID)
    if type(mapID) ~= "number" or ns.IsSecret(mapID) then return mapID and C_Map.GetMapInfo(mapID) or nil end
    local info = mapInfo[mapID]
    if not info then
        info = C_Map.GetMapInfo(mapID)
        if info then mapInfo[mapID] = info end
    end
    return info
end

-- Camps, requests and meet-ups are only on outdoor zone maps: not continents,
-- the world or dungeons (so nobody can be lured into an instance).
local OUTDOOR_MAP_TYPES = { [3] = true, [5] = true } -- Enum.UIMapType.Zone, Micro

function ns.IsOutdoorMap(mapID)
    local info = ns.MapInfo(mapID)
    return info ~= nil and (info.mapType == nil or OUTDOOR_MAP_TYPES[info.mapType] == true)
end

-- Continent and world maps: how they show camps is an Options choice
-- (worldMapCamps, ns.WideMapStyle): every camp, smaller (MapPins.lua); one pin
-- per zone with its count; or none.
-- Meet-ups and the minimap stay on zone maps.
local WIDE_MAP_TYPES = { [1] = true, [2] = true } -- Enum.UIMapType.World, Continent
local CONTINENT_MAP_TYPE = 2

function ns.IsWideMap(mapID)
    local info = mapID and ns.MapInfo(mapID)
    return info ~= nil and info ~= false and WIDE_MAP_TYPES[info.mapType] == true
end

-- "all", "grouped" or "none". Until the player picks one it goes with the
-- mode: grouped in Enhanced, none in Standard (whose map is about the camps
-- around you). A setting from before the choice was on (now: the mode's) or off.
function ns.WideMapStyle()
    local style = ns.db and ns.db.worldMapCamps
    if style == "all" or style == "grouped" or style == "none" then return style end
    if style == false then return "none" end
    return ns.IsEnhanced() and "grouped" or "none"
end

-- Maps that are another map of the same zone.
ns.ZONE_ALIASES = { [2665] = 2521 } -- Zephras Isle's second map
-- Each capital is a zone map of its own in the game (under the continent), but
-- it's part of the zone around it (wago.tools UiMap and UiMapAssignment,
-- wow_classic_beta: each city's map is on its zone's continent and over it).
ns.CITY_ZONES = {
    [1453] = 1429, -- Stormwind City: Elwynn Forest
    [1454] = 1411, -- Orgrimmar: Durotar
    [1455] = 1426, -- Ironforge: Dun Morogh
    [1456] = 1412, -- Thunder Bluff: Mulgore
    [1457] = 1438, -- Darnassus: Teldrassil
    [1458] = 1420, -- Undercity: Tirisfal Glades
}

-- The zone a map is in: a sub-zone or area map's parent zone, or the map
-- itself, with a capital part of the zone around it. With cityApart a capital
-- is a zone of its own, as the game has it: for badges (a city has none), and
-- layers (the game numbers a city's apart from its zone's).
function ns.ZoneOf(mapID, cityApart)
    local info = mapID and ns.MapInfo(mapID)
    for _ = 1, 5 do
        if not info or not info.mapType or info.mapType <= 3 or not info.parentMapID or info.parentMapID == 0 then break end
        local parent = ns.MapInfo(info.parentMapID)
        if not parent then break end
        mapID, info = info.parentMapID, parent
    end
    mapID = ns.ZONE_ALIASES[mapID] or mapID
    if not cityApart then mapID = ns.CITY_ZONES[mapID] or mapID end
    return mapID
end

function ns.GetPlayerLocation()
    local mapID = C_Map.GetBestMapForUnit("player")
    if not mapID or ns.IsSecret(mapID) then return end
    local pos = C_Map.GetPlayerMapPosition(mapID, "player")
    if not pos then return end
    local x, y = ns.XY(pos)
    if ns.IsSecret(x) or not x or (x == 0 and y == 0) then return end
    return mapID, x, y
end

function Camps:TimeLeft(camp)
    local deadline = camp.expiresAt
    -- An unconfirmed camp goes ChatPins.LIFETIME after it showed up, whatever it says.
    if deadline and self:Unconfirmed(camp) then
        deadline = math.min(deadline, (camp.placedAt or camp.updated or 0) + ns.ChatPins.LIFETIME)
    end
    return deadline and math.max(0, deadline - Now())
end

-- Fires that just went out, kept for a moment by where they were. Only the
-- fire gives camp buffs (its objects can outlast it, giving nothing), but a
-- rest begun before it went out still ends in Camp Benefits: that mustn't put
-- the dead fire back on the map as a new camp.
local ENDED_FOR = 120 -- seconds: a rest is a minute, with room to spare
local ENDED_KEEP = 30 * 60 -- fires that went out are remembered this long (for map links in chat)
local ENDED_MAX = 50
local ended = {}      -- { mapID, x, y, continent, wx, wy, at }

local function NoteEnded(record)
    if not record.continent or not record.wx then return end
    ended[#ended + 1] = { mapID = record.mapID, x = record.x, y = record.y,
        continent = record.continent, wx = record.wx, wy = record.wy, at = Now() }
    if #ended > ENDED_MAX then table.remove(ended, 1) end
end

local function ForgetOldEnded()
    local now = Now()
    for i = #ended, 1, -1 do
        if now - ended[i].at > ENDED_KEEP then table.remove(ended, i) end
    end
end

-- Whether a fire went out where you are in the last ENDED_FOR seconds.
function Camps:JustEndedHere()
    ForgetOldEnded()
    local now = Now()
    for _, fire in ipairs(ended) do
        local distance = now - fire.at <= ENDED_FOR and self:DistanceFromPlayer(fire)
        if distance and distance <= self.MERGE_RADIUS then return true end
    end
    return false
end

-- How many seconds ago a fire within radius yards of a spot went out (the
-- latest), if one did in the last ENDED_KEEP; else nil.
function Camps:EndedNear(mapID, x, y, radius)
    ForgetOldEnded()
    for i = #ended, 1, -1 do
        local distance = self:Distance(ended[i], mapID, x, y)
        if distance and distance <= radius then return Now() - ended[i].at end
    end
end

function Camps:IsMine(camp)
    return camp.creator == ns.playerName
end

-- Sums standing for a set of IDs ([id] = true) or tiers ([id] = tier): the
-- same for the same contents, whatever order they were added in.
local function SetSum(set)
    local sum, n = 0, 0
    for id, value in pairs(set or {}) do
        sum, n = sum + (tonumber(id) or 0) * (type(value) == "number" and value + 7 or 1), n + 1
    end
    return sum, n
end

-- Everything about a camp that's shown, in one string: a snapshot sent again
-- (query replies, zone answers) mostly changes nothing, and needs no redraw.
local function Signature(camp)
    local objects, objectCount = SetSum(camp.objects)
    local professions, professionCount = SetSum(camp.professions)
    local equipment, equipmentCount = SetSum(camp.equipment)
    return format("%s;%s;%s;%s;%s;%s;%s;%s;%s;%s;%s;%s;%d;%d;%d;%d;%d;%d", tostring(camp.mapID), tostring(camp.x),
        tostring(camp.y), tostring(camp.expiresAt), tostring(camp.owned), tostring(camp.passing), tostring(camp.layer),
        tostring(camp.faction), tostring(camp.slots), tostring(camp.chat), tostring(camp.location), tostring(camp.nameKey),
        objects, objectCount, professions, professionCount, equipment, equipmentCount)
end

-- Adds or updates a camp. Only the creator may change position or expiry;
-- objects from anyone are merged in.
function Camps:Upsert(data, sender)
    local camps = ns.db.camps
    local camp = camps[data.id]
    local isNew = not camp
    if isNew then
        -- One lit fire per player: a new one from them replaces the old.
        if data.owned and sender then
            for id, other in pairs(camps) do
                if other.creator == data.creator and other.owned then self:Remove(id) end
            end
        end
        -- Unconfirmed camps only ever make room by pushing out each other.
        if data.chat then
            local unconfirmed = 0
            for _, other in pairs(camps) do
                if other.chat then unconfirmed = unconfirmed + 1 end
            end
            if unconfirmed >= MAX_UNCONFIRMED then self:Prune(true, true) end
        end
        if Count(camps) >= MAX_CAMPS then self:Prune(true, data.chat, data.mapID, sender ~= nil and not data.chat) end
        if Count(camps) >= MAX_CAMPS then return end
        camp = { id = data.id, objects = {}, professions = {}, equipment = {}, realm = ns.realm }
        camps[data.id] = camp
    end
    local before = not isNew and Signature(camp)
    quietCamp = camp

    if sender == nil or sender == data.creator then
        camp.creator = data.creator
        camp.owned = data.owned
        camp.chat = data.chat
        camp.via = data.via -- the other addon an unconfirmed camp came from (Others.lua)
        camp.approximate = data.approximate
        camp.passing = data.passing
        camp.layer = data.layer or camp.layer
        camp.faction = data.faction or camp.faction
        camp.slots = data.slots or camp.slots
        camp.location = data.location or camp.location
        camp.placedAt = data.placedAt
        camp.expiresAt = data.expiresAt
        if camp.mapID ~= data.mapID or camp.x ~= data.x or camp.y ~= data.y then
            camp.mapID, camp.x, camp.y = data.mapID, data.x, data.y
            camp.continent, camp.wx, camp.wy = WorldPosition(data.mapID, data.x, data.y)
            if not camp.chat then ns.ChatPins:OnRealCamp(camp) end
        end
    end

    -- The fire-lighter's camp replaces reports of the same fire, keeping what
    -- they knew about its objects; any camp from a rest replaces one only seen
    -- in passing. A report from another layer is another fire.
    if isNew and (camp.owned or not camp.passing) and not camp.chat and camp.continent then
        for id, other in pairs(camps) do
            if other ~= camp and not other.owned and not other.chat and (camp.owned or other.passing)
                and not (other.layer and camp.layer and other.layer ~= camp.layer) then
                local distance = WorldDistance(other, camp.continent, camp.wx, camp.wy)
                if distance and distance <= self.MERGE_RADIUS then
                    for spellID in pairs(other.objects or {}) do data.objects = data.objects or {}; data.objects[spellID] = true end
                    for skillLine in pairs(other.professions or {}) do data.professions = data.professions or {}; data.professions[skillLine] = true end
                    for skillLine, tier in pairs(other.equipment or {}) do data.equipment = data.equipment or {}; data.equipment[skillLine] = tier end
                    self:Remove(id)
                end
            end
        end
    end

    -- A snapshot from the camp's creator is the whole list: what's left out is gone.
    if sender ~= nil and sender == data.creator and not isNew then
        camp.objects, camp.professions, camp.equipment = {}, {}, {}
    end
    for spellID in pairs(data.objects or {}) do self:AddObject(camp, spellID) end
    for skillLine in pairs(data.professions or {}) do self:AddProfession(camp, skillLine) end
    for skillLine, tier in pairs(data.equipment or {}) do self:AddEquipment(camp, skillLine, tier) end

    quietCamp = nil
    camp.updated = Now()
    if isNew or Signature(camp) ~= before then ns.OnCampsChanged() end
    if isNew and camp.owned then ns.Requests:OnCampAdded(camp) end
    return camp
end

-- skillLine is the object's profession when the sender knows it.
function Camps:AddObject(camp, spellID, skillLine)
    self:AddProfession(camp, skillLine or ns.ProfessionForObject(spellID))
    if camp.objects[spellID] or Count(camp.objects) >= MAX_ENTRIES then return false end
    -- Placing an object can fire more than one spell; keep one per object.
    local key = ns.ObjectInfo(spellID)
    for existing in pairs(camp.objects) do
        if ns.ObjectInfo(existing) == key then return false end
    end
    camp.objects[spellID] = true
    Touch(camp)
    return true
end

-- An object seen in a Camp Benefits tooltip (by profession and tier). Keeps the
-- highest tier per profession. Returns true if anything changed.
function Camps:AddEquipment(camp, skillLine, tier)
    local profession = ns.PROFESSION_BY_ID[skillLine]
    if not profession or not profession.objects[tier] then return false end
    camp.equipment = camp.equipment or {}
    self:AddProfession(camp, skillLine)
    if (camp.equipment[skillLine] or 0) >= tier then return false end
    camp.equipment[skillLine] = tier
    Touch(camp)
    return true
end

-- Professions whose objects may not show in Camp Benefits (their buff is a
-- service, not a stat), so a Camp Benefits list can't tell they're gone.
local NOT_IN_BENEFITS = { [202] = true, [185] = true } -- Engineering, Cooking

-- The objects in a Camp Benefits tooltip are everything at the camp right now
-- ([skillLine] = tier). Anything else is gone: its object, equipment entry and
-- buff are removed. Returns true if anything changed.
-- keep: professions whose objects the list can't prove gone (your class buff
-- covers their stat: Camp Benefits may leave out an object it overrides).
function Camps:SetEquipment(camp, found, keep)
    local changed = false
    keep = keep or {}
    local function Gone(skillLine) return not found[skillLine] and not NOT_IN_BENEFITS[skillLine] and not keep[skillLine] end
    camp.equipment = camp.equipment or {}
    for skillLine in pairs(camp.equipment) do
        if Gone(skillLine) then camp.equipment[skillLine], changed = nil, true end
    end
    for spellID in pairs(camp.objects) do
        local _, _, skillLine = ns.ObjectInfo(spellID)
        if skillLine and Gone(skillLine) then
            camp.objects[spellID], changed = nil, true
        end
    end
    for skillLine in pairs(camp.professions) do
        if Gone(skillLine) then camp.professions[skillLine], changed = nil, true end
    end
    for skillLine, tier in pairs(found) do
        local profession = ns.PROFESSION_BY_ID[skillLine]
        if profession and profession.objects[tier] and camp.equipment[skillLine] ~= tier then
            camp.equipment[skillLine], changed = tier, true
        end
        self:AddProfession(camp, skillLine)
    end
    if changed then
        Touch(camp)
    end
    return changed
end

function Camps:AddProfession(camp, skillLine)
    if not skillLine or not ns.PROFESSION_BY_ID[skillLine] or camp.professions[skillLine] then return end
    camp.professions[skillLine] = true
    if camp ~= quietCamp then ns.OnCampsChanged() end
end

-- The objects at a camp, one per object: { { name, skillLine, icon }, ... }
function Camps:ObjectList(camp)
    local list, seen = {}, {}
    for spellID in pairs(camp.objects) do
        local key, name, skillLine = ns.ObjectInfo(spellID)
        if not seen[key] then
            seen[key] = true
            local _, _, _, tier, icon = ns.ObjectByName(name)
            list[#list + 1] = { name = name, skillLine = skillLine, icon = icon, tier = tier }
        end
    end
    -- Objects known only from Camp Benefits tooltips.
    for skillLine, tier in pairs(camp.equipment or {}) do
        local profession = ns.PROFESSION_BY_ID[skillLine]
        local name = ns.ObjectName(skillLine, tier)
        local key = profession.objects[tier]:lower()
        if not seen[key] then
            seen[key] = true
            list[#list + 1] = { name = name, skillLine = skillLine, icon = profession.objectIcons[tier], tier = tier }
        end
    end
    table.sort(list, function(a, b) return a.name < b.name end)
    return list
end

function Camps:Remove(id)
    if not ns.db.camps[id] then return end
    ns.db.camps[id] = nil
    if ns.state.myCampID == id then ns.state.myCampID = nil end
    ns.OnCampsChanged()
end

-- How far a camp is from where it matters, when the list is full and one
-- must go: 0 in the zone you're in (or the new camp's), 1 elsewhere on your
-- continent, 2 on another continent. Ties go by age.
local function Remoteness(camp, zone, continent)
    if zone and ns.ZoneOf(camp.mapID) == zone then return 0 end
    if continent and camp.continent == continent then return 1 end
    return 2
end

-- A camp whose fire nobody with Happy Camper saw lit (so its time left isn't
-- known) is taken to have gone out this long after it was last reported: a
-- fire burns 15 minutes, but this one may have been burning a while already.
Camps.UNKNOWN_LIFE = 10 * 60

-- Drops burnt-out camps (or, with no known expiry, ones not reported for
-- UNKNOWN_LIFE). With force, also drops the oldest unconfirmed camp (from chat or
-- another addon), or if there's none, another player's camp (not with
-- unconfirmedOnly): one on another continent first, then in another zone,
-- then the oldest. forMap: the map of the camp that needs the room. With
-- refuseFarther, a camp from another player that's no nearer than any kept
-- (unless in your zone) makes no room: on a busy realm, far camps would only
-- keep pushing each other out. Returns whether one went.
function Camps:Prune(force, unconfirmedOnly, forMap, refuseFarther)
    local now, oldestChat, oldestReal = Now(), nil, nil
    local zone, continent, realRank
    if force then
        local playerMap = C_Map.GetBestMapForUnit("player")
        if playerMap and not ns.IsSecret(playerMap) then
            zone = ns.ZoneOf(playerMap)
            continent = WorldPosition(playerMap, 0.5, 0.5)
        end
        if not zone and forMap then zone, continent = ns.ZoneOf(forMap), WorldPosition(forMap, 0.5, 0.5) end
    end
    local left, unconfirmed = 0, 0
    for id, camp in pairs(ns.db.camps) do
        local deadline = camp.chat and (camp.expiresAt or (camp.placedAt or 0) + ns.ChatPins.LIFETIME)
            or camp.expiresAt or ((camp.updated or 0) + Camps.UNKNOWN_LIFE)
        -- Unconfirmed camps (from chat, another addon, or seen in passing) last
        -- 10 minutes at most from when they first showed up, whatever they say.
        if self:Unconfirmed(camp) then
            deadline = math.min(deadline, (camp.placedAt or camp.updated or 0) + ns.ChatPins.LIFETIME)
        end
        -- Test camps (dev tools) go too if the dev tools are turned off.
        if now > deadline or camp.realm ~= ns.realm or (camp.test and not ns.devCommands.test)
            or (camp.demo and not ns.Guide.running) then
            if now > deadline and not camp.chat and camp.expiresAt then
                NoteEnded(camp)
                ns.Campsites:OnCampEnded(camp)
            end
            self:Remove(id)
        else
            left = left + 1
            if camp.chat then
                unconfirmed = unconfirmed + 1
                if not oldestChat or (camp.updated or 0) < (oldestChat.updated or 0) then oldestChat = camp end
            elseif force and not self:IsMine(camp) then
                local rank = Remoteness(camp, zone, continent)
                if not oldestReal or rank > realRank
                    or rank == realRank and (camp.updated or 0) < (oldestReal.updated or 0) then
                    oldestReal, realRank = camp, rank
                end
            end
        end
    end
    -- Only if the burnt-out ones going didn't already make room.
    local full = left >= MAX_CAMPS or (unconfirmedOnly and unconfirmed >= MAX_UNCONFIRMED)
    local victim = force and full and (oldestChat or not unconfirmedOnly and oldestReal)
    if victim and refuseFarther and victim == oldestReal and forMap then
        local newRank = Remoteness({ mapID = forMap, continent = WorldPosition(forMap, 0.5, 0.5) }, zone, continent)
        if newRank > 0 and newRank >= realRank then victim = nil end
    end
    if victim then self:Remove(victim.id) end
    return victim ~= nil
end

-- Distance in yards from a map point to a camp or request, or nil if unknown.
function Camps:Distance(record, mapID, x, y)
    return WorldDistance(record, WorldPosition(mapID, x, y))
end

-- Your world position (continent, wx, wy), or nil if it can't be read.
function Camps:PlayerWorldPosition()
    local mapID, x, y = ns.GetPlayerLocation()
    if mapID then return WorldPosition(mapID, x, y) end
end

function Camps:DistanceFromPlayer(record)
    return WorldDistance(record, self:PlayerWorldPosition())
end

-- Yards from you to a point on a map, or nil.
function Camps:DistanceTo(mapID, x, y)
    local continent, wx, wy = WorldPosition(mapID, x, y)
    if continent then return self:DistanceFromPlayer({ continent = continent, wx = wx, wy = wy }) end
end

-- Whether a camp offers anything: an object or a camp buff. One that doesn't
-- (a bare fire, as older versions report them, or a camp whose objects have
-- all gone) isn't shown anywhere. Camps posted in chat are shown faded anyway.
function Camps:Offers(camp)
    if camp.chat or camp.test or next(camp.objects or {}) or next(camp.equipment or {}) then return true end
    for skillLine in pairs(camp.professions or {}) do
        if skillLine ~= 185 then return true end -- 185: Cooking, the fire itself
    end
    return false
end

-- The nearest camp within radius yards (not counting camps posted in chat,
-- which are only roughly where the fire is). With layer, camps known to be on
-- another layer don't count either: their fire isn't the one there.
function Camps:NearestTo(mapID, x, y, radius, layer)
    local continent, wx, wy = WorldPosition(mapID, x, y)
    if not continent then return end
    local best, bestDistance
    for _, camp in pairs(ns.db.camps) do
        local distance = not camp.chat and not (layer and camp.layer and camp.layer ~= layer)
            and WorldDistance(camp, continent, wx, wy)
        if distance and distance <= radius and (not bestDistance or distance < bestDistance) then
            best, bestDistance = camp, distance
        end
    end
    return best, bestDistance
end

-- The nearest camp within radius yards of you, on your layer (or one whose
-- layer isn't known). Until your layer is settled, a camp on any layer.
-- Many things ask several times a second (music, presence, the windows), so
-- the answer is kept until you move, your layer changes or camps change.
local nearKept = {} -- [radius] = { camp, distance, mapID, x, y, layer, version }
function Camps:NearPlayer(radius)
    local mapID, x, y = ns.GetPlayerLocation()
    if not mapID then return end
    local layer, kept = ns.SettledLayer(), nearKept[radius]
    if kept and kept.version == ns.campsVersion and kept.mapID == mapID and kept.x == x and kept.y == y
        and kept.layer == layer and (not kept.camp or ns.db.camps[kept.camp.id] == kept.camp) then
        return kept.camp, kept.distance
    end
    local camp, distance = self:NearestTo(mapID, x, y, radius, layer)
    nearKept[radius] = { camp = camp, distance = distance, mapID = mapID, x = x, y = y, layer = layer, version = ns.campsVersion }
    return camp, distance
end

-- Returns { {camp=, x=, y=}, ... } for camps visible on the given map.
function Camps:OnMap(uiMapID)
    local result = {}
    for _, camp in pairs(ns.db.camps) do
        local x, y = self:Project(camp, uiMapID)
        if x then result[#result + 1] = { camp = camp, x = x, y = y } end
    end
    table.sort(result, function(a, b)
        return (a.camp.placedAt or 0) > (b.camp.placedAt or 0)
    end)
    return result
end

-- At most this many camps show on a map, nearest first: a zone's map, and a
-- continent's or the world's (their pins are smaller: MapPins.lua).
Camps.MAX_ON_MAP = 25
Camps.MAX_ON_WIDE_MAP = 60

-- Why no camps show on a map: "zoomed" (a continent or the world with no
-- camps on them in Options, or a map that isn't outdoors), or nil when camps
-- can show (any zone's map, or a part of one; continents and the world unless
-- Options says none).
function Camps:MapHidesCamps(uiMapID)
    if ns.IsOutdoorMap(uiMapID) then return end
    if ns.IsWideMap(uiMapID) and ns.WideMapStyle() ~= "none" then return end
    return "zoomed"
end

-- A zone's map (or a sub-zone's, or its city's): the camps in that zone, each
-- with its distance from you on your own zone's map, else from the map's middle.
local function ZoneMapCamps(self, uiMapID, searching)
    local zone = ns.ZoneOf(uiMapID)
    local playerMap = C_Map.GetBestMapForUnit("player")
    local continent, wx, wy
    if playerMap and not ns.IsSecret(playerMap) and ns.ZoneOf(playerMap) == zone then
        continent, wx, wy = self:PlayerWorldPosition()
    else
        continent, wx, wy = WorldPosition(uiMapID, 0.5, 0.5)
    end
    -- Only that zone's camps are placed on its map (placing a camp is a map
    -- lookup; most known camps are elsewhere).
    local list = {}
    for _, camp in pairs(ns.db.camps) do
        if ns.ZoneOf(camp.mapID) == zone and self:Visible(camp) and (not searching or ns.Search:Match(camp)) then
            local x, y = self:Project(camp, uiMapID)
            if x then
                list[#list + 1] = { camp = camp, x = x, y = y, distance = WorldDistance(camp, continent, wx, wy) }
            end
        end
    end
    return list
end

-- A continent's or the world's map: every camp on it, placed from its world
-- position, each with its distance across the map from you if you're on it,
-- else from the map's middle. A continent's map leaves out camps on another
-- continent (the game may still place them somewhere on it); the world's
-- holds both.
local function WideMapCamps(self, uiMapID, searching)
    local info = ns.MapInfo(uiMapID)
    local mapContinent
    if info and info.mapType == CONTINENT_MAP_TYPE then mapContinent = WorldPosition(uiMapID, 0.5, 0.5) end
    -- Yards across and down the map, so distances on it are fair both ways.
    local width, height = ns.MapYards(uiMapID)
    width, height = width or 1, height or 1
    local fromX, fromY = 0.5, 0.5
    local continent, wx, wy = self:PlayerWorldPosition()
    if continent and (not mapContinent or continent == mapContinent) then
        local x, y = self:Project({ continent = continent, wx = wx, wy = wy }, uiMapID)
        if x then fromX, fromY = x, y end
    end
    local list = {}
    for _, camp in pairs(ns.db.camps) do
        if (not mapContinent or camp.continent == mapContinent) and self:Visible(camp)
            and (not searching or ns.Search:Match(camp)) then
            local x, y = self:Project(camp, uiMapID)
            if x then
                local dx, dy = (x - fromX) * width, (y - fromY) * height
                list[#list + 1] = { camp = camp, x = x, y = y, distance = math.sqrt(dx * dx + dy * dy) }
            end
        end
    end
    return list
end

-- The camps to show on a map: a zone's map (or a sub-zone's, or its city's)
-- shows the camps in that zone, wherever you are; a continent's or the world's
-- every camp on it (with the option on). Only matches while Find a camp is
-- open; at most MAX_ON_MAP of them (MAX_ON_WIDE_MAP zoomed out), nearest you
-- on a map you're on, else nearest the map's middle. The camp selected on the
-- panel always shows, so its pin can ping. Returns { {camp=, x=, y=}, ... },
-- how many there were before the limit, and why there are none if the map
-- hides camps (MapHidesCamps).
function Camps:ShownOnMap(uiMapID)
    local hidden = self:MapHidesCamps(uiMapID)
    if hidden then return {}, 0, hidden end
    local searching = ns.Search:IsActive()
    local list, limit
    if ns.IsWideMap(uiMapID) then
        -- Grouped, every camp counts (there's one pin per group, whatever the number).
        list, limit = WideMapCamps(self, uiMapID, searching), ns.WideMapStyle() == "grouped" and math.huge or self.MAX_ON_WIDE_MAP
    else
        list, limit = ZoneMapCamps(self, uiMapID, searching), self.MAX_ON_MAP
    end
    table.sort(list, function(a, b)
        if a.distance and b.distance then return a.distance < b.distance end
        if a.distance or b.distance then return a.distance ~= nil end
        return (a.camp.placedAt or 0) > (b.camp.placedAt or 0)
    end)
    local total = #list
    for i = limit + 1, total do
        if list[i].camp.id == ns.state.selectedCampID then
            list[limit] = list[i]
            break
        end
    end
    for i = total, limit + 1, -1 do list[i] = nil end
    return list, total
end

local function PickedName(camp)
    return camp.nameKey and ns.Names:Render(camp.nameKey, camp.location)
end

-- The fire-lighter's picked name, else the location name ("Goldshire Campsite"),
-- else (before the location arrives) who lit or saw it.
function Camps:DisplayName(camp)
    local name = PickedName(camp) or ns.Names:Default(camp.location)
    if name then return name end
    return format(camp.owned and L["%s's camp"] or L["Camp (seen by %s)"], CreatorName(camp))
end

-- A shorter name: a picked name in full, else "South Goldshire".
function Camps:ShortName(camp)
    return PickedName(camp) or ns.Names:Short(camp.location)
        or (camp.owned and CreatorName(camp)) or L["Campsite"]
end

-- Renames a camp you lit (key from Names:Options; nil = the location name).
function Camps:SetName(camp, key)
    camp.nameKey = key
    Touch(camp)
    ns.Comm:SendName(camp)
end

-- The names you can pick for a camp you lit.
function Camps:NameOptions(camp)
    local location = CopyTable(camp.location or {})
    -- A city's own map: its local specials (Names.lua) are its own, not its zone's.
    location.nearby, location.nearbyIDs, location.zoneMap = camp.nearby, camp.nearbyIDs, ns.ZoneOf(camp.mapID, true)
    return ns.Names:Options(location, ns.GetMyProfessions())
end

-- A new camp: the fire you lit (lit, from OnFireLit: where and when, its size
-- and burn time), or else one you're reporting where you're standing.
local function NewCamp(lit, passing)
    local mapID, x, y = ns.GetPlayerLocation()
    if lit then mapID, x, y = lit.mapID, lit.x, lit.y end
    -- Camps are only on zone maps (never shown or shared on a continent's).
    if not mapID or not ns.IsOutdoorMap(mapID) then return end
    local now = Now()
    local location = ns.Location:Describe(mapID, x, y)
    local camp = Camps:Upsert({
        id = ns.playerName .. ":" .. (lit and lit.placedAt or now),
        creator = ns.playerName,
        owned = lit ~= nil,
        layer = lit and lit.layer or ns.SettledLayer(),
        faction = UnitFactionGroup("player"),
        slots = lit and lit.slots,
        mapID = mapID, x = x, y = y,
        location = ns.Location:Shared(location),
        placedAt = lit and lit.placedAt or now,
        expiresAt = lit and lit.expiresAt,
        passing = passing or nil,
    })
    if camp then camp.nearby, camp.nearbyIDs = location.nearby, location.nearbyIDs end
    return camp
end

-- The second line under a camp's name: who lit it or reported it.
function Camps:CreatorText(camp)
    if camp.chat then
        local minutes = math.max(1, math.floor((Now() - (camp.placedAt or Now())) / 60))
        if camp.approximate then
            return format(L["Posted in chat near you by %s (%s addon), %d min ago"], CreatorName(camp), camp.via or "?", minutes)
        end
        if camp.via then return format(L["Shared by %s (%s addon), %d min ago"], CreatorName(camp), camp.via, minutes) end
        return format(L["Posted in chat by %s, %d min ago"], CreatorName(camp), minutes)
    end
    if camp.passing then
        return self:IsMine(camp) and L["Seen in passing by you"] or format(L["Seen in passing by %s"], CreatorName(camp))
    end
    if self:IsMine(camp) then return camp.owned and L["Your fire"] or L["Reported by you"] end
    return format(camp.owned and L["Lit by %s"] or L["Reported by %s"], CreatorName(camp))
end

-- Your own actions ------------------------------------------------------------

-- How many objects a fire holds, from its kit's spell name: Basic 3,
-- Journeyman 5, Expert 10; nil if the name doesn't say.
function Camps.KitSlots(spellName)
    local name = (spellName or ""):lower()
    return name:find("expert") and 10 or name:find("journeyman") and 5 or name:find("basic") and 3 or nil
end

-- You lit a fire. It isn't a camp yet: a fire becomes one when someone gets
-- camp buffs from it, or places an object at it (ConfirmCampHere). Until then
-- it's a bare fire: its details (where, when, size and burn time) wait on your
-- character, and nothing about it is sent, except music played at it.
function Camps:OnFireLit(slots)
    local mapID, x, y = ns.GetPlayerLocation()
    if not mapID then return end
    -- Only one fire per player; lighting a new one replaces the old one.
    if ns.state.myCampID then
        ns.Comm:SendRemove(ns.state.myCampID)
        self:Remove(ns.state.myCampID)
    end
    local now = Now()
    local continent, wx, wy = WorldPosition(mapID, x, y)
    ns.charDB.litFire = { mapID = mapID, x = x, y = y, continent = continent, wx = wx, wy = wy,
        placedAt = now, expiresAt = now + ns.db.campDuration, slots = slots, layer = ns.SettledLayer() }
    ns.Note(L["Fire lit. Sit at it for a minute: once you have its camp buffs, it goes on the map."])
end

-- The fire you lit, if it's still burning (and, with near, within reach).
function Camps:LitFire(near)
    local lit = ns.charDB.litFire
    if lit and Now() >= (lit.expiresAt or 0) then
        NoteEnded(lit)
        ns.charDB.litFire, lit = nil, nil
    end
    if lit and near then
        local distance = self:DistanceFromPlayer(lit)
        if not distance or distance > self.MERGE_RADIUS then return nil end
    end
    return lit
end

-- Someone got camp buffs from a fire, or placed an object at it: now it's a
-- camp. Your own lit
-- fire goes on the map with its exact burn time; any other fire the addon
-- doesn't know yet is reported by you. Returns the camp.
function Camps:ConfirmCampHere()
    local camp = self:NearPlayer(self.MERGE_RADIUS)
    local lit = self:LitFire(true)
    if lit and not (camp and camp.owned) then
        -- If it can't be made (full list), a report of it here still counts.
        local made = NewCamp(lit)
        if made then
            camp = made
            ns.charDB.litFire = nil
            ns.state.myCampID = camp.id
            ns.Comm:SendSnapshot(camp)
        end
    elseif camp and camp.passing and self:IsMine(camp) then
        -- Your own camp seen in passing: now it's confirmed.
        camp.passing = nil
        ns.Comm:SendSnapshot(camp)
    elseif not camp or camp.passing then
        -- A fire that just went out here: the buffs are from a rest begun before.
        if self:JustEndedHere() then return nil end
        -- Someone else's camp seen in passing gives way to yours, from a rest.
        camp = NewCamp() or camp
        if camp and not camp.passing then ns.Comm:SendSnapshot(camp) end
    end
    return camp
end

-- Your layer just became settled (or changed): camps you lit or reported in
-- this zone without knowing it get it now, and everyone is told.
function Camps:OnLayerKnown(layer)
    for _, camp in pairs(ns.db.camps) do
        if camp.creator == ns.playerName and not camp.layer and not camp.test
            and ns.ZoneOf(camp.mapID, true) == ns.ZoneOf(C_Map.GetBestMapForUnit("player"), true) then
            camp.layer = layer
            ns.Comm:SendSnapshot(camp)
        end
    end
    ns.OnCampsChanged()
end

-- Whether a camp is on your layer: "same", "other", or nil if either isn't
-- known. Each zone numbers its layers its own way (Location.lua), so a camp in
-- another zone can't be told.
function Camps:LayerStatus(camp)
    -- You were at its spot and there was no fire (CheckFireHere): it's taken
    -- as on another layer (it may have gone out).
    if self:MissingHere(camp) then return "other" end
    local mine = ns.CurrentLayer()
    if not camp.layer or not mine then return nil end
    local here = C_Map.GetBestMapForUnit("player")
    if not here or ns.IsSecret(here) or ns.ZoneOf(camp.mapID, true) ~= ns.ZoneOf(here, true) then return nil end
    return camp.layer == mine and "same" or "other"
end

-- Why a camp in your zone can't be told to be on your layer or not: "camp"
-- (its layer isn't known: an older version's, or one seen in passing or posted
-- in chat) or "you" (yours isn't yet: it's read from NPCs near you); nil if it
-- can be, or it's in another zone (layers are only compared within one).
function Camps:LayerUnknown(camp)
    if self:LayerStatus(camp) then return nil end
    local here = C_Map.GetBestMapForUnit("player")
    if not here or ns.IsSecret(here) or ns.ZoneOf(camp.mapID, true) ~= ns.ZoneOf(here, true) then return nil end
    if not camp.layer then return "camp" end
    if not ns.CurrentLayer() then return "you" end
end

-- A fire you'd see but don't. Campfire Nearby reaches about 100 yards, so
-- standing within FIRE_SEEN_RADIUS of a camp with none for FIRE_MISSING_FOR
-- seconds (out of combat, buffs readable) means its fire isn't on your layer,
-- or is out. The camp is marked so for the layer you're on (on this computer
-- only: never sent); coming near a fire there again takes the mark off.
-- Unconfirmed camps, only roughly placed, and your own aren't marked.
Camps.FIRE_SEEN_RADIUS = 50
Camps.FIRE_MISSING_FOR = 5
local missingSince = {} -- [camp ID] = when you came that near with no fire
local lastFireCheck = 0

function Camps:MissingHere(camp)
    local missing = camp.missingHere
    if not missing then return false end
    return missing.layer == false or missing.layer == ns.CurrentLayer()
end

-- Once a second (Core's tick).
function Camps:CheckFireHere()
    local t = GetTime()
    if t - lastFireCheck < 1 then return end
    lastFireCheck = t
    if ns.InCombat() or ns.state.aurasDirty then
        missingSince = {}
        return
    end
    local continent, wx, wy = self:PlayerWorldPosition()
    if not continent then return end
    local now, near = Now(), ns.state.nearCamp
    for id, camp in pairs(ns.db.camps) do
        local distance = not self:IsMine(camp) and not self:Unconfirmed(camp) and not camp.test and not camp.demo
            and WorldDistance(camp, continent, wx, wy)
        if distance and distance <= self.FIRE_SEEN_RADIUS then
            if near then
                missingSince[id] = nil
                if camp.missingHere then
                    camp.missingHere = nil
                    ns.OnCampsChanged()
                end
            else
                missingSince[id] = missingSince[id] or now
                if now - missingSince[id] >= self.FIRE_MISSING_FOR and not self:MissingHere(camp) then
                    camp.missingHere = { layer = ns.CurrentLayer() or false, at = now }
                    ns.OnCampsChanged()
                end
            end
        else
            missingSince[id] = nil
        end
    end
end

-- Whether a camp shows on the map and the panel: not on another layer, unless
-- Options says to show those (faded).
function Camps:Visible(camp)
    if not self:Offers(camp) then return false end
    return ns.db.showOtherLayers or self:LayerStatus(camp) ~= "other"
end

-- How many of a fire's object slots are taken, and how many it has (nil if
-- unknown). Objects from an earlier fire here can still be listed, so it's
-- never more than the fire holds.
-- A camp's quality, coloured like an item's. Each profession's object counts
-- its tier (1-3) in points; a buff known only from Camp Benefits counts as a
-- tier 1 object. With only tier 1 objects a camp is Poor (0-2 of them) or
-- Common (3 or more). With a tier 2 or 3 object it's Uncommon, or better by
-- points (QUALITY_POINTS: Rare, Epic, Legendary). A fire holds at most 10
-- objects (30 points); Legendary takes five tier 3 objects with the other five
-- slots at tier 2 or better.
Camps.QUALITY_POINTS = { 8, 15, 25 }
Camps.QUALITIES = {
    { name = "Poor camp" },
    { name = "Common camp" },
    { name = "Uncommon camp" },
    { name = "Rare camp" },
    { name = "Epic camp" },
    { name = "Legendary camp" },
}
-- The game's item quality colours, exactly: { r, g, b } from each hex.
local QUALITY_HEX = { "9d9d9d", "ffffff", "1eff00", "0070dd", "a335ee", "ff8000" }
for q, quality in ipairs(Camps.QUALITIES) do
    quality.color = {}
    for i = 1, 3 do quality.color[i] = tonumber(QUALITY_HEX[q]:sub(2 * i - 1, 2 * i), 16) / 255 end
end
ns.OnLocale(function() ns.LocalizeFields(Camps.QUALITIES, "name") end)

-- Returns the quality (1 Poor to 6 Legendary) and the points.
function Camps:Quality(camp)
    local tiers, points, count = {}, 0, 0
    for _, object in ipairs(self:ObjectList(camp)) do
        if object.skillLine then
            tiers[object.skillLine] = math.max(tiers[object.skillLine] or 0, object.tier or 1)
        else
            points, count = points + 1, count + 1
        end
    end
    for skillLine in pairs(camp.professions or {}) do
        if skillLine ~= 185 then tiers[skillLine] = tiers[skillLine] or 1 end -- 185: Cooking, the fire itself
    end
    local best = 1
    for _, tier in pairs(tiers) do
        points, count, best = points + tier, count + 1, math.max(best, tier)
    end
    if best < 2 then return count >= 3 and 2 or 1, points end
    local quality = 3
    for i, need in ipairs(self.QUALITY_POINTS) do
        if points >= need then quality = 3 + i end
    end
    return quality, points
end

function Camps:SlotsUsed(camp)
    local used = #self:ObjectList(camp)
    return camp.slots and math.min(used, camp.slots) or used, camp.slots
end

-- A camp whose fire was lit by someone without the addon: report it ourselves.
function Camps:ReportCampHere()
    return NewCamp()
end

-- A camp's owner (whoever lit its fire or first reported it) can pick its name
-- for its first MANAGE_TIME seconds (its song, any time: CanPickSong).
Camps.MANAGE_TIME = 15 * 60

function Camps:CanManage(camp)
    return camp ~= nil and camp.creator == ns.playerName and Now() - (camp.placedAt or 0) < self.MANAGE_TIME
end

-- Its song is yours to pick for as long as it burns.
function Camps:CanPickSong(camp)
    return camp ~= nil and camp.creator == ns.playerName
end

function Camps:ManageTimeLeft(camp)
    return math.max(0, self.MANAGE_TIME - (Now() - (camp.placedAt or 0)))
end

-- An object you placed is added to the camp here. A bare fire becomes a camp:
-- it has something to offer now (some objects, like the Repair Bot, never show
-- in Camp Benefits). Your own fire becomes your camp even if someone has
-- already reported it.
function Camps:OnObjectPlaced(spellID)
    local camp = self:ConfirmCampHere()
    if not camp then return end

    local skillLine = ns.ProfessionForObject(spellID)
    if not self:AddObject(camp, spellID, skillLine) then return end
    if self:IsMine(camp) then ns.Comm:SendSnapshot(camp) else ns.Comm:SendObject(camp.id, spellID, skillLine) end
end

-- The tent's rested XP comes once an hour, and for that hour the game keeps a
-- Tent line in Camp Benefits at every camp, tent or not. So a Tent line only
-- proves there's a tent when that hour isn't running (and then it starts it);
-- during it, a camp keeps what it's already known to have.
local TENT = 165 -- Leatherworking: the Camp Tent
Camps.TENT_LOCKOUT = 60 * 60

-- Whether a Camp Benefits line's object is the tent's "Tent", in the client's
-- language: part of its local "Camp Tent" name (German "Zelt" in "Lagerzelt",
-- Chinese 帐篷 in 营地帐篷), as words aren't always apart.
local function IsLocalTentName(object)
    local name = type(object) == "string" and object:lower():match("^%s*(.-)%s*$")
    if not name or #name < 3 then return false end
    local tent = ns.ObjectName(TENT, 1)
    return type(tent) == "string" and tent:lower():find(name, 1, true) ~= nil
end

-- The game's own record of that hour: Boosted Rest, which the tent's rested XP
-- puts on you (its spell ID from Forever's data, by way of the Camping Kit
-- addon). Seconds since it began, or nil if it can't be read (then this
-- character's own record of the hour, tentXPUntil, stands in).
Camps.BOOSTED_REST = 1229451
local TENT_SLACK = 90 -- seconds: Boosted Rest and Camp Benefits from one rest begin together
local function BoostedRestAgo()
    local get = C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID
    if not get then return nil end
    local ok, aura = pcall(get, Camps.BOOSTED_REST)
    if not ok or type(aura) ~= "table" then return nil end
    local exp, duration = aura.expirationTime, aura.duration
    if ns.IsSecret(exp) or ns.IsSecret(duration) or type(exp) ~= "number" or type(duration) ~= "number" or duration <= 0 then
        return nil
    end
    return GetTime() - (exp - duration)
end

-- Seconds since a buff began (0 if it can't be told).
local function BuffAgo(aura)
    local exp, duration = aura and aura.expirationTime, aura and aura.duration
    if ns.IsSecret(exp) or ns.IsSecret(duration) or type(exp) ~= "number" or type(duration) ~= "number" or duration <= 0 then
        return 0
    end
    return math.max(0, GetTime() - (exp - duration))
end

-- Whether Camp Benefits' Tent line is left from a tent earlier in the hour,
-- not one here: the tent's hour began well before this rest did (benefitsAgo:
-- seconds since this Camp Benefits began).
function Camps:TentFromEarlier(benefitsAgo)
    local hourAgo = BoostedRestAgo()
    if not hourAgo then
        local untilAt = ns.charDB.tentXPUntil
        if not untilAt or Now() >= untilAt then return false end
        hourAgo = Now() - (untilAt - self.TENT_LOCKOUT)
    end
    return hourAgo - (benefitsAgo or 0) > TENT_SLACK
end

-- Whether a Camp Benefits line is the tent's.
function Camps:IsTentLine(line)
    if not line then return false end
    local _, _, skillLine = ns.ObjectByName(line.object)
    return skillLine == TENT or line.skillLine == TENT or (not skillLine and IsLocalTentName(line.object))
end

-- A Camp Benefits buff's lines without a Tent line left from an earlier tent
-- (unless the camp here is known to have a tent of its own): for showing them.
function Camps:DropEarlierTent(lines, buff)
    local tentLine
    for _, line in ipairs(lines) do
        if self:IsTentLine(line) then tentLine = line end
    end
    if not tentLine or not self:TentFromEarlier(BuffAgo(buff)) then return lines end
    local camp = self:NearPlayer(self.MERGE_RADIUS)
    if camp and camp.professions[TENT] then return lines end
    local kept = {}
    for _, line in ipairs(lines) do
        if line ~= tentLine then kept[#kept + 1] = line end
    end
    return kept
end

function Camps:CheckTentLine(found, benefitsAgo)
    local c = ns.charDB
    if not self:TentFromEarlier(benefitsAgo) then
        -- A tent here, and this rest its hour's start (kept in case the game's
        -- Boosted Rest can't be read later).
        if Now() >= (c.tentXPUntil or 0) then c.tentXPUntil = Now() + self.TENT_LOCKOUT end
        return
    end
    local camp = self:NearPlayer(self.MERGE_RADIUS)
    local tier = camp and camp.equipment and camp.equipment[TENT]
    if not tier and camp and camp.professions[TENT] then
        -- Placed but not yet seen in Camp Benefits: the highest one placed.
        for spellID in pairs(camp.objects) do
            local key, _, skillLine = ns.ObjectInfo(spellID)
            if skillLine == TENT then tier = math.max(tier or 0, select(4, ns.ObjectByName(key)) or 1) end
        end
        tier = tier or 1
    end
    found[TENT] = tier
end

-- The tier a camp is known to have for a profession: from Camp Benefits, else
-- the highest object placed, else 1.
local function KnownTier(camp, skillLine)
    local tier = (camp.equipment or {})[skillLine]
    if tier then return tier end
    for spellID in pairs(camp.objects) do
        local key, _, objectSkill = ns.ObjectInfo(spellID)
        if objectSkill == skillLine then tier = math.max(tier or 0, select(4, ns.ObjectByName(key)) or 1) end
    end
    return tier or 1
end

-- Your Camp Benefits tooltip lists every object at the camp you rested at,
-- including ones placed by players without the addon, and leaves out ones that
-- have gone. It's applied each time you sit for a minute, so it's up to date.
function Camps:OnCampBenefits(auraInstanceID)
    local lines = ns.ReadCampBenefits(auraInstanceID)
    if not lines then return end
    local found = {}
    for _, line in ipairs(lines) do
        local _, _, skillLine, tier = ns.ObjectByName(line.object)
        if not skillLine and (line.skillLine or IsLocalTentName(line.object)) then skillLine, tier = TENT, 1 end -- "Tent"
        if skillLine then found[skillLine] = math.max(found[skillLine] or 0, tier) end
    end
    if found[TENT] then self:CheckTentLine(found, BuffAgo(ns.AuraByInstance("player", auraInstanceID))) end
    -- Having camp buffs from its objects is what makes a fire a camp.
    if not next(found) then return end
    local camp = self:ConfirmCampHere()
    if not camp then return end
    ns.Music:Inspire(camp.mapID)
    -- A class buff you have (Blessing of Might...) can leave the object whose
    -- stat it covers out of your list: what the camp already has for that stat
    -- stays, and is passed on as part of the list. Someone without the buff
    -- resting there sees whether it's really gone.
    for skillLine in pairs((ns.UnitCoveredBuffs("player"))) do
        if not found[skillLine] and camp.professions[skillLine] then found[skillLine] = KnownTier(camp, skillLine) end
    end
    if not self:SetEquipment(camp, found) then return end
    if self:IsMine(camp) then ns.Comm:SendSnapshot(camp) else ns.Comm:SendEquipment(camp.id, camp.equipment) end
end

-- An object you hover in the world (Tooltips.lua) is at the camp you're at:
-- it's added, never taking anything away. This finds objects Camp Benefits
-- doesn't list: ones your class buff overrides, and the bots and other services.
--
-- With no camp known here, near a fire (Campfire Nearby), it's a camp seen in
-- passing: on the map where you stand, marked as only seen, until someone
-- rests there. Not at a fire you lit (that waits for your rest), nor one that
-- just went out.
function Camps:OnObjectSeen(skillLine, tier)
    local camp = self:NearPlayer(self.MERGE_RADIUS)
    if not camp and ns.state.nearCamp and not ns.IsRestingAtCamp() and not self:LitFire(true)
        and not self:JustEndedHere() and ns.db.network then
        camp = NewCamp(nil, true)
        if not camp then return end
        self:AddEquipment(camp, skillLine, tier or 1)
        ns.Comm:SendSnapshot(camp)
        ns.OnCampsChanged()
        return
    end
    if not camp or camp.chat or not self:AddEquipment(camp, skillLine, tier or 1) then return end
    if self:IsMine(camp) then ns.Comm:SendSnapshot(camp) else ns.Comm:SendEquipment(camp.id, camp.equipment) end
    ns.OnCampsChanged()
end

-- Grey and faded everywhere: posted in chat, or only seen in passing.
function Camps:Unconfirmed(camp)
    return camp.chat == true or camp.passing == true
end

-- You rested a full minute. Camp Benefits comes as the rest ends if the fire
-- has objects (OnCampBenefits). If it doesn't come, the fire has no camp buffs:
-- a camp here loses the objects its Camp Benefits would list, and if nothing's
-- left it drops off the map (until someone places an object again).
local function AurasReadable()
    for i = 1, 40 do
        local aura, secret = ns.AuraByIndex("player", i, "HELPFUL")
        if secret then return false end
        if not aura then return true end
        if ns.IsSecretAura(aura) then return false end
    end
    return true
end

-- Whether you have a Camp Benefits that started since then (one that came in
-- a fight was never seen coming: UNIT_AURA waits for the fight to end).
local function CampBuffSince(since)
    for i = 1, 40 do
        local aura = ns.AuraByIndex("player", i, "HELPFUL")
        if not aura then return false end
        if not ns.IsSecretAura(aura) and ns.ClassifyAura(aura) == "buff" and (aura.duration or 0) > 0
            and (aura.expirationTime or 0) - aura.duration >= since then
            return true
        end
    end
    return false
end

function Camps:OnRested()
    local restedAt = GetTime()
    C_Timer.After(5, function()
        -- In a fight, a Camp Benefits that came isn't seen (UNIT_AURA waits for
        -- it to end), so its not being seen proves nothing.
        if (ns.state.campBuffAt or 0) >= restedAt - 2 or ns.InCombat() or ns.state.aurasDirty
            or not AurasReadable() or CampBuffSince(restedAt - 2) then return end
        local camp = self:NearPlayer(self.MERGE_RADIUS)
        -- (what your class buffs cover may only have been left out: it stays)
        if not camp or camp.chat or not self:SetEquipment(camp, {}, (ns.UnitCoveredBuffs("player"))) then return end
        if self:IsMine(camp) then ns.Comm:SendSnapshot(camp) else ns.Comm:SendEquipment(camp.id, camp.equipment) end
        ns.OnCampsChanged()
    end)
end

-- If the fire shows up as a totem, its exact expiry is readable by the owner.
function Camps:OnTotemUpdate()
    local camp = ns.state.myCampID and self:Get(ns.state.myCampID)
    local lit = self:LitFire()
    if not camp and not lit then return end

    for slot = 1, MAX_TOTEMS or 4 do
        local haveTotem, name, startTime, duration, _, _, spellID = GetTotemInfo(slot)
        -- While totem slots are secret (in a fight) nothing here can be read or
        -- tested: look again once it's over, rather than deciding the fire went out.
        if ns.IsSecret(haveTotem) or ns.IsSecret(name) or ns.IsSecret(startTime)
            or ns.IsSecret(duration) or ns.IsSecret(spellID) then
            ns.state.totemsDirty = true
            return
        end
        if haveTotem and duration and duration > 0
            and (ns.ClassifySpell(spellID) == "fire" or ns.NameMatches(name, "fire")) then
            local expiresAt = math.floor(Now() + (startTime + duration - GetTime()) + 0.5)
            ns.state.myFireTotemSlot = slot
            if not camp then
                lit.expiresAt = expiresAt
            elseif math.abs(expiresAt - (camp.expiresAt or 0)) > 5 then
                camp.expiresAt = expiresAt
                ns.Comm:SendSnapshot(camp)
                ns.OnCampsChanged()
            end
            return
        end
    end

    if ns.state.myFireTotemSlot then
        -- The fire we were tracking went out.
        ns.state.myFireTotemSlot = nil
        ns.charDB.litFire = nil
        if camp then
            NoteEnded(camp)
            ns.Campsites:OnCampEnded(camp)
            ns.Comm:SendRemove(camp.id)
            self:Remove(camp.id)
        end
    end
end
