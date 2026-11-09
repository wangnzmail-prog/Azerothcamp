-- Happy Camper. Copyright (c) 2026 Torridon. All rights reserved; see LICENSE.
local _, ns = ...
local L = ns.L

-- Tooltips on camp objects in the world: hover a Mana Well (or any camp object,
-- including the bots, which are creatures) and its tooltip adds the buff it
-- gives, how to get it, and whether a class buff you have already gives that,
-- so you'd gain nothing (the bots, feast and oven: what they add). Only near a
-- campfire: towns have plain objects with the same names ("Anvil", "Loom") that
-- aren't camp objects. Hover a campfire for how many objects it holds, and how
-- many of them the camp here has.

local Tooltips = {}
ns.Tooltips = Tooltips

local NEAR_YARDS = 120 -- the game's Campfire Nearby buff reaches about 100
-- Engineering's bots and Cooking's feast and oven are services: no camp buff,
-- nothing to sit for (like Camps.lua's NOT_IN_BENEFITS).
local SERVICE = { [202] = true, [185] = true }

-- Camp objects named like something every town has: hovering one tells a camp
-- nothing unless its ID shows it was placed ("skillLine:tier").
local TOWN_NAMESAKES = { ["164:2"] = true } -- Blacksmithing's Anvil

local function NearAFire()
    return ns.state.nearCamp or ns.IsRestingAtCamp() or ns.Camps:NearPlayer(NEAR_YARDS) ~= nil
end

-- Adds the camp lines for an object named name (in any client language);
-- returns true if it was a camp object. id: the game's ID of the object or
-- creature, from its GUID, if it could be read: then only a placed camp object
-- (Data.lua's CAMP_OBJECT_IDS) counts, whatever its name. A town's Anvil is
-- named like Blacksmithing's but isn't one.
function Tooltips:AddObjectLines(tooltip, name, id)
    if type(name) ~= "string" or ns.IsSecret(name) then return false end
    local placed = id and ns.CAMP_OBJECT_IDS[id]
    local skillLine, tier
    if placed then
        skillLine, tier = placed[1], placed[2]
    elseif id then
        return false
    else
        -- No ID: by name. Most tooltips aren't camp objects, and it's the cheaper check.
        local _
        _, _, skillLine, tier = ns.ObjectByName(name)
    end
    local profession = skillLine and ns.PROFESSION_BY_ID[skillLine]
    if not profession or not NearAFire() then return false end
    -- Seen there, so it's at the camp you're at (Camp Benefits can leave some
    -- out). Not by name alone where a town has its namesake (the Anvil).
    if placed or not TOWN_NAMESAKES[skillLine .. ":" .. (tier or 1)] then ns.Camps:OnObjectSeen(skillLine, tier) end
    if SERVICE[skillLine] then
        local extras = (ns.OBJECT_EXTRAS[skillLine] or {})[tier or 1]
        if not extras then return false end
        tooltip:AddLine(format(L["Adds %s"], ns.JoinList(extras)), 0.4, 1, 0.4, true)
        return true
    end
    tooltip:AddLine(format(L["Camp buff: %s"], profession.buff), 0.4, 1, 0.4)
    ns.AddBuffSize(tooltip, profession) -- what you'd get, at your level
    local have = ns.CoveredCampBuffs()[skillLine]
    if have then
        tooltip:AddLine(format(L["You already have %s, so this adds nothing."], have), 1, 0.35, 0.3, true)
    elseif profession.conflicts then
        tooltip:AddLine(format(L["Doesn't stack with %s."], profession.conflicts), 0.7, 0.7, 0.7, true)
    end
    tooltip:AddLine(L["Sit by the fire for a minute to get it."], 0.7, 0.7, 0.7, true)
    return true
end

-- How many objects a campfire holds, from its name in any client language (its
-- placement spell's name, like "Journeyman Campfire"), or nil if it isn't one.
local function FireSlots(name)
    for spellID, slots in pairs(ns.CAMP_SPELLS.fire) do
        if C_Spell.GetSpellName(spellID) == name then return slots end
    end
    -- In English, by its size word, but only on a campfire (not a pet called "Expert").
    if ns.NameMatches(name, "fire") then return ns.Camps.KitSlots(name) end
end

-- Whether camp is the only camp you know of near you, so a fire you hover is
-- very likely its own (the game doesn't say where a hovered fire is).
local function OnlyCampHere(camp)
    local continent, wx, wy = ns.Camps:PlayerWorldPosition()
    local layer = ns.SettledLayer()
    for _, other in pairs(ns.Camps:All()) do
        if other ~= camp and not (layer and other.layer and other.layer ~= layer) then
            local distance = ns.Camps.WorldDistance(other, continent, wx, wy)
            if distance and distance <= 2 * ns.Camps.MERGE_RADIUS then return false end
        end
    end
    return true
end

-- Adds a campfire's size and, for the camp here, its name and free slots;
-- returns true if it was a campfire. A camp whose size wasn't known learns it,
-- but only while you're at a fire with no other camp near (the fire hovered
-- could be another), and tells everyone (if you're the one who reported it)
-- only while you sit by it.
function Tooltips:AddFireLines(tooltip, name)
    if type(name) ~= "string" or ns.IsSecret(name) then return false end
    local slots = FireSlots(name)
    if not slots then return false end
    tooltip:AddLine(format(L["Holds %d camp objects"], slots), 0.4, 1, 0.4)
    local camp = ns.Camps:NearPlayer(ns.Camps.MERGE_RADIUS)
    if camp then
        if not camp.slots and (ns.state.nearCamp or ns.IsRestingAtCamp()) and OnlyCampHere(camp) then
            camp.slots = slots
            if (ns.IsRestingAtCamp() or camp.passing) and ns.Camps:IsMine(camp) then ns.Comm:SendSnapshot(camp) end
            ns.OnCampsChanged()
        end
        if camp.slots then
            local used = ns.Camps:SlotsUsed(camp)
            tooltip:AddLine(format(L["%s: %d of %d used"], ns.Camps:DisplayName(camp), used, camp.slots), 1, 1, 1, true)
        end
    end
    return true
end

-- Another player or a pet named like a camp object ("Anvil") isn't one.
local function IsPlayerOrPet(guid)
    return type(guid) == "string" and not ns.IsSecret(guid) and (guid:find("^Player%-") or guid:find("^Pet%-")) ~= nil
end

-- Before placing a camp object (its item in your bags, or the panel's Place
-- button), by its placement spell: a warning when a class buff you have
-- already gives its stat (others at the camp still get it), and, in Enhanced
-- mode, when the camp you're at already has it at that tier or better, or
-- its fire is full. Returns true if it added anything.
function Tooltips:AddPlacingLines(tooltip, spellID)
    local key = spellID and ns.ObjectForSpell(spellID)
    if not key then return false end
    local _, _, skillLine, tier = ns.ObjectByName(key)
    if not skillLine or not ns.PROFESSION_BY_ID[skillLine] then return false end
    tier = tier or 1
    local added = false
    local have = not SERVICE[skillLine] and ns.CoveredCampBuffs()[skillLine]
    if have then
        tooltip:AddLine(format(L["You already have %s, so it adds nothing for you. Others at the camp still get it."], have), 1, 0.35, 0.3, true)
        added = true
    end
    local camp = (not ns.IsEnhanced or ns.IsEnhanced()) and ns.Camps:NearPlayer(ns.Camps.MERGE_RADIUS)
    if camp and not camp.chat then
        local campTier = (camp.equipment or {})[skillLine]
        local used, slots = ns.Camps:SlotsUsed(camp)
        if campTier and campTier >= tier then
            tooltip:AddLine(format(L["%s already has %s: placing this adds nothing more."], ns.Camps:DisplayName(camp),
                ns.ObjectName(skillLine, campTier)), 1, 0.35, 0.3, true)
            added = true
        elseif slots and used >= slots then
            tooltip:AddLine(format(L["This camp's fire is full (%d of %d): there's no room for it."], used, slots), 1, 0.35, 0.3, true)
            added = true
        end
    end
    return added
end

-- A camp object's item (in your bags, the bank, a loot window...): the
-- placing lines, found by the spell it casts (any client language).
local function OnItemTooltip(tooltip, data)
    if tooltip ~= GameTooltip or not ns.db or type(data) ~= "table" or type(data.id) ~= "number" then return end
    local getItemSpell = C_Item and C_Item.GetItemSpell or GetItemSpell
    local spellID = getItemSpell and select(2, getItemSpell(data.id))
    if type(spellID) == "number" and Tooltips:AddPlacingLines(tooltip, spellID) then tooltip:Show() end
end

-- The game's ID of a world object or creature, from its GUID
-- ("GameObject-0-server-instance-zone-<ID>-spawn"); nil if it can't be read.
function Tooltips.GuidID(guid)
    if type(guid) ~= "string" or ns.IsSecret(guid) then return nil end
    local kind, id = guid:match("^(%a+)%-%d+%-%d+%-%d+%-%d+%-(%d+)%-")
    if kind == "GameObject" or kind == "Creature" or kind == "Vehicle" then return tonumber(id) end
end

local function OnTooltip(tooltip, data)
    if tooltip ~= GameTooltip or not ns.db then return end
    local first = data and data.lines and data.lines[1]
    if not first or IsPlayerOrPet(data.guid) then return end
    if Tooltips:AddObjectLines(tooltip, first.leftText, Tooltips.GuidID(data.guid))
        or Tooltips:AddFireLines(tooltip, first.leftText) then
        tooltip:Show()
    end
end

-- World objects, and creatures (the Reagent and Repair Bots, Greenhouse, Rock Garden).
if TooltipDataProcessor and Enum and Enum.TooltipDataType then
    for _, kind in ipairs({ "Object", "Unit" }) do
        if Enum.TooltipDataType[kind] then TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType[kind], OnTooltip) end
    end
    if Enum.TooltipDataType.Item then TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, OnItemTooltip) end
end
