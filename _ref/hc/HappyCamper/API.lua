-- Happy Camper. Copyright (c) 2026 Torridon. All rights reserved; see LICENSE.
local _, ns = ...

-- HappyCamperAPI: a small, read-only lookup that other addons may use without
-- asking (the guide for them, with examples, is API.md), on these terms (also
-- in LICENSE and on the CurseForge page):
-- read-only; Happy Camper credited wherever its data shows; and the data never
-- sent on over chat or addon messages. Anything else (copying code, reading
-- Happy Camper's saved data or internals, or its camp channel) still needs
-- Torridon's permission.
--
-- HappyCamperAPI.version is 1. It goes up only if a call changes in a way
-- that could break an addon using it; new fields can come without it.
--
-- HappyCamperAPI.GetNearbyCamps() returns the camps Happy Camper knows in the
-- zone you're in, on your layer (or whose layer isn't known), nearest first.
-- Never more than Happy Camper shows you: in Standard mode other players'
-- camps show only as smoke, so only your own and the one you're at are listed.
-- Camps posted in chat, from other camp addons or only seen in passing are
-- left out (they're only roughly placed), and so are fires that have gone out.
-- Each camp is a new table, yours to keep:
--   mapID, x, y   the map it's on and its fire's position there (0-1)
--   layer         the layer it's on (the zone's own number), or nil if not known
--   timeLeft      seconds until its fire goes out, or nil if not known
--   distance      yards from you, or nil if it can't be told
--   objects       { { name =, profession =, tier = }, ... }, one per object at
--                 it: its name as the game shows it, its profession's skill
--                 line ID and its tier (1-3). Match on profession and tier, not
--                 the name, which follows the player's language: the Arcane
--                 Salvager is Enchanting (333), tier 2.
-- An empty list if there are none, or if your position can't be read (in an
-- instance, say).

HappyCamperAPI = { version = 1 }

local function ObjectsOf(camp)
    local list = {}
    for _, object in ipairs(ns.Camps:ObjectList(camp)) do
        list[#list + 1] = { name = object.name, profession = object.skillLine, tier = object.tier }
    end
    return list
end

local function NearbyCamps()
    local Camps = ns.Camps
    if not ns.db or not ns.db.camps then return {} end
    local mapID, x, y = ns.GetPlayerLocation()
    if not mapID then return {} end
    local zone = ns.ZoneOf(mapID)
    local continent, wx, wy = Camps.WorldPosition(mapID, x, y)
    -- The camp you're at shows exactly in Standard mode too (Camps:Smoky).
    local here = not ns.IsEnhanced() and (Camps:NearPlayer(Camps.MERGE_RADIUS) or false)
    local list = {}
    for _, camp in pairs(ns.db.camps) do
        local timeLeft = Camps:TimeLeft(camp)
        if ns.ZoneOf(camp.mapID) == zone and not Camps:Unconfirmed(camp) and not camp.demo
            and Camps:Offers(camp) and Camps:LayerStatus(camp) ~= "other" and timeLeft ~= 0
            and not Camps:Smoky(camp, here) then
            list[#list + 1] = {
                mapID = camp.mapID, x = camp.x, y = camp.y,
                layer = camp.layer,
                timeLeft = timeLeft,
                distance = Camps.WorldDistance(camp, continent, wx, wy),
                objects = ObjectsOf(camp),
            }
        end
    end
    table.sort(list, function(a, b)
        if a.distance and b.distance then return a.distance < b.distance end
        return a.distance ~= nil and b.distance == nil
    end)
    return list
end

-- An error inside Happy Camper never reaches the addon asking: it gets an
-- empty list.
function HappyCamperAPI.GetNearbyCamps()
    local ok, list = pcall(NearbyCamps)
    return ok and list or {}
end
