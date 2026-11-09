-- Happy Camper. Copyright (c) 2026 Torridon. All rights reserved; see LICENSE.
local _, ns = ...

-- Works out where a camp is, for its name:
--   area       the named area it's in ("Goldshire"), or the nearest one
--   direction  set when it's just outside that area: "South" of Goldshire
--   zone       "Elwynn Forest"; region: which part of the zone ("Southern")
--   nearby     lowercase names of all areas within NEAR_YARDS, and nearbyIDs
--              their area IDs (a set) (not shared; only used for the
--              fire-lighter's name choices)
-- Nearby areas come from the map's exploration data, so only areas the player
-- has discovered count.

local Location = {}
ns.Location = Location

local NEAR_YARDS = 250
local STEP_YARDS = 25
local DIRECTIONS = 16 -- sample points per ring

local COMPASS = { "East", "Southeast", "South", "Southwest", "West", "Northwest", "North", "Northeast" }

-- Compass direction of a map offset (map y grows southwards).
local function Compass(dx, dy)
    local angle = math.deg(math.atan2(dy, dx)) % 360
    return COMPASS[math.floor((angle + 22.5) / 45) % 8 + 1]
end

-- "Northern", "Southeastern", "Central"...: which part of the zone map x, y is in.
-- REGIONS: every one it can be (another player's camp name can only use these).
Location.REGIONS = { Central = true, Northern = true, Southern = true, Eastern = true, Western = true,
    Northeastern = true, Northwestern = true, Southeastern = true, Southwestern = true }
local function Region(x, y)
    local northSouth = y < 0.34 and "North" or y > 0.66 and "South" or ""
    local eastWest = x < 0.34 and "west" or x > 0.66 and "east" or ""
    if northSouth == "" and eastWest == "" then return "Central" end
    if northSouth == "" then return eastWest == "west" and "Western" or "Eastern" end
    return northSouth .. eastWest .. "ern"
end

-- Yards per map unit across and down the map, or nil if unknown.
local function MapScale(mapID)
    local function Yards(ax, ay, bx, by)
        local c1, p1 = C_Map.GetWorldPosFromMapPos(mapID, CreateVector2D(ax, ay))
        local _, p2 = C_Map.GetWorldPosFromMapPos(mapID, CreateVector2D(bx, by))
        if not (c1 and p1 and p2) then return nil end
        local x1, y1 = ns.XY(p1)
        local x2, y2 = ns.XY(p2)
        local d = math.sqrt((x1 - x2) ^ 2 + (y1 - y2) ^ 2)
        return d > 0 and d or nil
    end
    return Yards(0, 0.5, 1, 0.5), Yards(0.5, 0, 0.5, 1)
end

-- The explored areas at a point: { { id = areaID, name = "Goldshire" }, ... }
local function AreasAt(mapID, x, y)
    local ok, ids = pcall(C_MapExplorationInfo.GetExploredAreaIDsAtPosition, mapID, CreateVector2D(x, y))
    local areas = {}
    for _, id in ipairs(ok and ids or {}) do
        local name = C_Map.GetAreaInfo(id)
        if name and name ~= "" then areas[#areas + 1] = { id = id, name = name } end
    end
    return areas
end

-- The area IDs you're standing in (a set), or an empty set if your position
-- can't be read. Areas are IDs in every client language.
function Location:AreaIDsHere()
    local ids = {}
    local mapID, x, y = ns.GetPlayerLocation()
    if mapID then
        for _, area in ipairs(AreasAt(mapID, x, y)) do ids[area.id] = true end
    end
    return ids
end

-- elsewhere: the point isn't where you're standing (other players' camps from
-- chat or other addons, dev tools' test camps), so the zone and area come from
-- the map rather than your current zone text. Those only need the shared parts
-- (Shared), so the search stops at the first named area: nearby isn't complete.
function Location:Describe(mapID, x, y, elsewhere)
    local info = C_Map.GetMapInfo(mapID)
    local zone = not elsewhere and GetZoneText() or nil
    -- Only a zone map's own name will do, never a continent's or the world's.
    if (not zone or zone == "") and info and (info.mapType or 3) >= 3 then zone = info.name end
    if zone == "" then zone = nil end
    local location = { zone = zone, region = Region(x, y), nearby = {}, nearbyIDs = {} }

    -- The area you're in (its ID too, which is what's shared with others).
    local here = AreasAt(mapID, x, y)
    local subzone = not elsewhere and GetSubZoneText() or nil
    for _, area in ipairs(here) do
        if area.name ~= zone then location.nearbyIDs[area.id] = true end
    end
    for _, area in ipairs(here) do
        if area.name ~= zone and (elsewhere or area.name == subzone) then
            location.area, location.areaID = area.name, area.id
            break
        end
    end
    if not location.area and subzone and subzone ~= "" and subzone ~= zone then location.area = subzone end
    if location.area then location.nearby[location.area:lower()] = true end
    if elsewhere and location.area then return location end

    -- Rings of sample points out to NEAR_YARDS: the first named area found is
    -- the nearest, and the camp is on the opposite side of it from that point.
    local width, height = MapScale(mapID)
    if width and height then
        for ring = 1, NEAR_YARDS / STEP_YARDS do
            local radius = ring * STEP_YARDS
            for step = 0, DIRECTIONS - 1 do
                local theta = step * 2 * math.pi / DIRECTIONS
                local sx, sy = x + math.cos(theta) * radius / width, y + math.sin(theta) * radius / height
                if sx >= 0 and sx <= 1 and sy >= 0 and sy <= 1 then
                    for _, area in ipairs(AreasAt(mapID, sx, sy)) do
                        if area.name ~= zone then
                            location.nearby[area.name:lower()] = true
                            location.nearbyIDs[area.id] = true
                            if not location.area then
                                location.area, location.areaID = area.name, area.id
                                location.direction = Compass(x - sx, y - sy)
                                if elsewhere then return location end
                            end
                        end
                    end
                end
            end
        end
    end
    return location
end

-- The parts of a location that are shared with other players.
function Location:Shared(location)
    return {
        area = location.area, areaID = location.areaID, direction = location.direction,
        zone = location.zone, region = location.region,
    }
end

-- Layers ---------------------------------------------------------------------------
-- Forever splits busy zones into layers: copies of the world where you only see
-- the players and fires on your own. The game doesn't say which layer you're on,
-- but every NPC's GUID carries it ("Creature-0-server-instance-zoneUID-npcID-spawn"),
-- so it's read from the NPCs you see: nameplates, your mouseover and your target.
-- It's only trusted in the zone it was seen in. An NPC across a zone border
-- carries its own zone's ID, so the first one in a zone only gives your layer
-- for now: two others that agree can change it. Once a second NPC agrees with
-- it, it's settled, and you're only taken to be on another layer once clearly
-- more NPCs lately say so than say yours.

local layer -- { id = zoneUID, zone = zone map ID, seen = time, settled = 2 NPCs agreed }
local recent = {}      -- the NPCs seen lately in this zone, oldest first: { guid, id, seen }
local RECENT_MAX = 8   -- NPCs that count
local RECENT_TIME = 180 -- seconds a sighting counts
local SWITCH_VOTES = 3 -- different NPCs it takes to change a settled layer (and 2 more than say it)

-- A city counts apart from its zone here: its NPCs carry the city's own IDs.
local function PlayerZone()
    local mapID = C_Map.GetBestMapForUnit("player")
    return mapID and not ns.IsSecret(mapID) and ns.ZoneOf(mapID, true) or nil
end

-- The layer you're on (a number), or nil until an NPC here has been seen.
function ns.CurrentLayer()
    local zone = layer and PlayerZone()
    return zone and zone == layer.zone and layer.id or nil
end

-- Your layer once it's settled, or nil. Only this one decides which camp is
-- the one you're at, and is given to your camps: one NPC alone may be the
-- next zone's.
function ns.SettledLayer()
    return layer and layer.settled and ns.CurrentLayer() or nil
end

-- For the dev tools: the layer, its zone and when it was last seen.
function ns.LayerInfo()
    return layer
end

function ns.ObserveLayer(unit)
    if not UnitExists(unit) or UnitIsPlayer(unit) then return end
    -- Players' pets and companions follow them across borders with their old ID.
    local controlled = UnitPlayerControlled and UnitPlayerControlled(unit)
    if controlled and not ns.IsSecret(controlled) then return end
    local guid = UnitGUID(unit)
    if type(guid) ~= "string" or ns.IsSecret(guid) then return end
    local kind, _, _, _, zoneUID = strsplit("-", guid)
    zoneUID = tonumber(zoneUID)
    local zone = PlayerZone()
    if kind ~= "Creature" or not zoneUID or zoneUID == 0 or not zone then return end
    local now = GetTime()
    if not layer or layer.zone ~= zone then
        -- New to this zone: the first NPC says which layer, for now.
        wipe(recent)
        recent[1] = { guid = guid, id = zoneUID, seen = now }
        layer = { id = zoneUID, zone = zone, seen = now }
        ns.OnCampsChanged()
        return
    end
    -- Each NPC counts once (seen again, it's only newer), for RECENT_TIME.
    for i = #recent, 1, -1 do
        if recent[i].guid == guid or now - recent[i].seen > RECENT_TIME then table.remove(recent, i) end
    end
    recent[#recent + 1] = { guid = guid, id = zoneUID, seen = now }
    if #recent > RECENT_MAX then table.remove(recent, 1) end
    local mine, theirs = 0, 0
    for _, entry in ipairs(recent) do
        if entry.id == layer.id then mine = mine + 1 elseif entry.id == zoneUID then theirs = theirs + 1 end
    end
    if zoneUID == layer.id then
        layer.seen = now
        if not layer.settled and mine >= 2 then
            layer.settled = true
            ns.Camps:OnLayerKnown(zoneUID)
        end
        return
    end
    -- One NPC's word gives way to two that agree; a settled layer only to
    -- SWITCH_VOTES that outnumber it by 2.
    if layer.settled and theirs >= SWITCH_VOTES and theirs >= mine + 2 or not layer.settled and theirs >= 2 then
        layer.id, layer.seen, layer.settled = zoneUID, now, true
        ns.Camps:OnLayerKnown(zoneUID)
    end
end
