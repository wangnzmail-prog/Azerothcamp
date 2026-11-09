-- Happy Camper. Copyright (c) 2026 Torridon. All rights reserved; see LICENSE.
local _, ns = ...

-- Food, drink, potions, weapon buffs and rest for the Campsite Assistant's slots
-- (Widget.lua): what's in your bags, what you've picked for the kit (food or
-- drink, a potion or elixir, two weapon buffs, and up to three extra slots that
-- Options makes potion, first aid or any-item ones), the Well Fed buff, a
-- sleeping bag's Well-Rested stacks, and whether a weapon is missing its stone,
-- oil or poison. Yours alone: nothing here is sent.

local Supplies = {}
ns.Supplies = Supplies

-- The kit's pick slots, by what each takes. Numbered as they were first made
-- (picks are saved by number): the second was once food, and the extra slots
-- came after the weapon buffs. How many extra slots show, and what each takes
-- (EXTRA_KINDS), is up to Options (KindOf).
Supplies.PICK_KINDS = { "food", "potion", "weapon", "weapon", "extra", "extra", "extra" }
Supplies.PICKS = #Supplies.PICK_KINDS
Supplies.MAX_EXTRAS = 3
Supplies.EXTRA_KINDS = { "potion", "firstaid", "any" }
local CONSUMABLE = 0 -- the item class of potions, elixirs, flasks and bandages
local POTION_SUBCLASSES = { [1] = true, [2] = true, [3] = true } -- Potion, Elixir, Flask
local BANDAGE_SUBCLASS = 7
Supplies.SLEEPING_BAGS = { 211527 } -- Cozy Sleeping Bag (Forever's item data)
Supplies.WELL_RESTED = 429959       -- the sleeping bag's buff, up to 3 stacks
local FOOD_CLASS, FOOD_SUBCLASS = 0, 5 -- Consumable: Food & Drink (numbers, so any client language)
local WELL_FED = 19705  -- a Well Fed spell: the game's name for it finds any food's Well Fed
local DRINK = 430       -- Drink: what a drink's use casts

local function SpellName(spellID)
    local name = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(spellID)
    if not name and GetSpellInfo then name = GetSpellInfo(spellID) end
    return type(name) == "string" and name ~= "" and name or nil
end

-- How many of an item you carry.
function Supplies:Count(itemID)
    if not itemID then return 0 end
    local get = C_Item and C_Item.GetItemCount or GetItemCount
    return get and get(itemID) or 0
end

-- Whether an item is food or drink (by its item class).
function Supplies:IsFoodOrDrink(itemID)
    local get = C_Item and C_Item.GetItemInfoInstant or GetItemInfoInstant
    if not (itemID and get) then return false end
    local _, _, _, _, _, classID, subclassID = get(itemID)
    return classID == FOOD_CLASS and subclassID == FOOD_SUBCLASS
end

-- Whether an item is a potion, elixir or flask (by its item class).
function Supplies:IsPotion(itemID)
    local get = C_Item and C_Item.GetItemInfoInstant or GetItemInfoInstant
    if not (itemID and get) then return false end
    local _, _, _, _, _, classID, subclassID = get(itemID)
    return classID == CONSUMABLE and POTION_SUBCLASSES[subclassID] == true
end

-- Whether an item is a bandage (by its item class): first aid.
function Supplies:IsFirstAid(itemID)
    local get = C_Item and C_Item.GetItemInfoInstant or GetItemInfoInstant
    if not (itemID and get) then return false end
    local _, _, _, _, _, classID, subclassID = get(itemID)
    return classID == CONSUMABLE and subclassID == BANDAGE_SUBCLASS
end

-- Whether an item can be used (it has a "Use:" spell).
local function Usable(itemID)
    local get = C_Item and C_Item.GetItemSpell or GetItemSpell
    return itemID ~= nil and get ~= nil and get(itemID) ~= nil
end

-- What a pick slot takes now: its own kind, or for an extra slot what Options
-- says ("potion", "firstaid" or "any").
function Supplies:KindOf(i)
    local kind = self.PICK_KINDS[i]
    if kind ~= "extra" then return kind end
    local number = i - 4
    local chosen = ns.db["widgetExtra" .. number]
    for _, known in ipairs(self.EXTRA_KINDS) do
        if chosen == known then return chosen end
    end
    return "potion"
end

-- Whether it's a drink rather than food (what its use casts).
function Supplies:IsDrink(itemID)
    local get = C_Item and C_Item.GetItemSpell or GetItemSpell
    local name = itemID and get and get(itemID)
    return name ~= nil and name == SpellName(DRINK)
end

-- What's in your bags for a pick slot's kind ("food", the default, "potion",
-- "firstaid", "weapon", or "any": anything with a use), each once:
-- { { item, count }, ... }, by name.
function Supplies:FoodInBags(kind)
    local list, seen = {}, {}
    if not (C_Container and C_Container.GetContainerNumSlots) then return list end
    for bag = 0, NUM_BAG_SLOTS or 4 do
        for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
            local itemID = C_Container.GetContainerItemID(bag, slot)
            if itemID and not seen[itemID] and self:Fits(kind or "food", itemID)
                and (kind ~= "any" or Usable(itemID)) then
                seen[itemID] = true
                list[#list + 1] = { item = itemID, count = self:Count(itemID) }
            end
        end
    end
    local function Name(entry)
        return C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(entry.item) or tostring(entry.item)
    end
    table.sort(list, function(a, b) return Name(a) < Name(b) end)
    return list
end

-- Weapon buffs: sharpening stones (for blades), weightstones (for blunt
-- weapons), oils (any melee weapon) and poisons (any, for rogues), by item ID
-- (so any client language). The game's Item Enhancement class catches newer
-- ones, for any weapon.
local WEAPON_BUFFS = {}
for kind, ids in pairs({
    sharp = { 2862, 2863, 2871, 7964, 12404, 18262, 23122 },
    blunt = { 3239, 3240, 3241, 7965, 12643 },
    any = { 20744, 20746, 20750, 20749, 23123, 20745, 20747, 20748, 3824, 3829 },
    poison = { 6947, 6949, 6950, 8926, 8927, 8928, 2892, 2893, 8984, 8985, 20844, 3775, 3776, 5237, 6951, 9186,
        10918, 10920, 10921, 10922 },
}) do
    for _, id in ipairs(ids) do WEAPON_BUFFS[id] = kind end
end
local ENHANCEMENT_CLASS, ENHANCEMENT_SUBCLASS = 0, 6 -- Consumable: Item Enhancement
-- Weapon kinds by item subclass (class 2, Weapon): blades and blunt ones.
local SHARP = { [0] = true, [1] = true, [6] = true, [7] = true, [8] = true, [15] = true } -- axes, polearms, swords, daggers
local BLUNT = { [4] = true, [5] = true, [10] = true, [13] = true }                          -- maces, staves, fist weapons

-- A weapon buff's kind ("sharp", "blunt", "any" or "poison"), or nil if it isn't one.
function Supplies:WeaponBuffKind(itemID)
    if not itemID then return nil end
    if WEAPON_BUFFS[itemID] then return WEAPON_BUFFS[itemID] end
    local get = C_Item and C_Item.GetItemInfoInstant or GetItemInfoInstant
    if not get then return nil end
    local _, _, _, _, _, classID, subclassID = get(itemID)
    if classID == ENHANCEMENT_CLASS and subclassID == ENHANCEMENT_SUBCLASS then return "any" end
end

-- Whether an item goes in a pick slot of a kind ("food", "potion", "firstaid",
-- "weapon" or "any": anything at all).
function Supplies:Fits(kind, itemID)
    if kind == "any" then return itemID ~= nil end
    if kind == "weapon" then return self:WeaponBuffKind(itemID) ~= nil end
    if kind == "potion" then return self:IsPotion(itemID) end
    if kind == "firstaid" then return self:IsFirstAid(itemID) end
    return self:IsFoodOrDrink(itemID)
end

-- Whether a weapon buff fits the weapon in a slot (16 main hand, 17 off
-- hand): a stone its edge, a weightstone a blunt one, a poison a rogue's.
local function FitsWeapon(kind, slot)
    local itemID = GetInventoryItemID and GetInventoryItemID("player", slot)
    if not itemID then return false end
    local get = C_Item and C_Item.GetItemInfoInstant or GetItemInfoInstant
    if not get then return false end
    local _, _, _, _, _, classID, subclassID = get(itemID)
    if classID ~= 2 or not (SHARP[subclassID] or BLUNT[subclassID]) then return false end -- a melee weapon
    if kind == "sharp" then return SHARP[subclassID] == true end
    if kind == "blunt" then return BLUNT[subclassID] == true end
    if kind == "poison" then return select(2, UnitClass("player")) == "ROGUE" end
    return true
end

-- How many weapons you hold (main hand and off hand; a shield or an off-hand
-- item isn't one): 0, 1 or 2. Each can take one weapon buff.
function Supplies:WeaponCount()
    local get = C_Item and C_Item.GetItemInfoInstant or GetItemInfoInstant
    if not (get and GetInventoryItemID) then return 0 end
    local n = 0
    for _, slot in ipairs({ 16, 17 }) do
        local itemID = GetInventoryItemID("player", slot)
        if itemID and select(6, get(itemID)) == 2 then n = n + 1 end -- class 2: Weapon
    end
    return n
end

-- Whether a weapon you're holding that this buff fits has none on it now.
function Supplies:WeaponNeeds(itemID)
    local kind = self:WeaponBuffKind(itemID)
    if not kind or not GetWeaponEnchantInfo then return false end
    local ok, hasMain, _, _, _, hasOff = pcall(GetWeaponEnchantInfo)
    if not ok or ns.IsSecret(hasMain) or ns.IsSecret(hasOff) then return false end
    return (not hasMain and FitsWeapon(kind, 16)) or (not hasOff and FitsWeapon(kind, 17)) or false
end

-- A sleeping bag in your bags (its item ID), or nil.
function Supplies:SleepingBag()
    for _, itemID in ipairs(self.SLEEPING_BAGS) do
        if self:Count(itemID) > 0 then return itemID end
    end
end

-- What's picked for a kit slot (PICK_KINDS), or nil. Kept per character. One
-- that doesn't fit the slot (food saved when the second slot was food) is
-- left out.
function Supplies:Pick(i)
    local item = (ns.charDB.foodPicks or {})[i]
    if item and not self:Fits(self:KindOf(i), item) then return nil end
    return item
end

-- Picks one (nil empties the slot); one that doesn't fit the slot's kind isn't
-- taken, and an item already in another slot of its kind moves here. Not in
-- combat: the slots are secure buttons. Returns whether it did.
function Supplies:SetPick(i, itemID)
    if ns.InCombat() then return false end
    local kind = self.PICK_KINDS[i] and self:KindOf(i)
    if not kind or (itemID and not self:Fits(kind, itemID)) then return false end
    local picks = ns.charDB.foodPicks or {}
    ns.charDB.foodPicks = picks
    for j = 1, self.PICKS do
        if j ~= i and itemID and picks[j] == itemID then picks[j] = nil end
    end
    picks[i] = itemID
    if ns.Widget then ns.Widget:Update() end
    return true
end

-- Buffs --------------------------------------------------------------------------------
-- Read again when your buffs change (UNIT_AURA: only as a signal, its details
-- can be secret) or one runs out. While buffs can't be read (combat,
-- instances), the last reading stands.

local dirty = true
local wellFed     -- { icon, expirationTime, duration, auraInstanceID }, or false when not Well Fed
local wellRested  -- { count, expirationTime }, or false

local function ReadWellFed()
    local name = SpellName(WELL_FED)
    if not name then return false end -- not loaded yet: try again next time
    for i = 1, 40 do
        local aura, hidden = ns.AuraByIndex("player", i, "HELPFUL")
        if hidden then return false end
        if not aura then break end
        if ns.IsSecret(aura.name) then return false end
        if aura.name == name then
            local exp, duration = aura.expirationTime, aura.duration
            if ns.IsSecret(exp) then exp = wellFed and wellFed.expirationTime end
            if ns.IsSecret(duration) then duration = wellFed and wellFed.duration end
            wellFed = {
                icon = not ns.IsSecret(aura.icon) and aura.icon or nil,
                expirationTime = exp,
                duration = duration,
                auraInstanceID = not ns.IsSecret(aura.auraInstanceID) and aura.auraInstanceID or nil,
            }
            return true
        end
    end
    wellFed = false
    return true
end

local function ReadWellRested()
    if not (C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID) then return true end
    local ok, aura = pcall(C_UnitAuras.GetPlayerAuraBySpellID, Supplies.WELL_RESTED)
    if not ok then return false end
    if not aura then wellRested = false return true end
    local count, exp = aura.applications, aura.expirationTime
    if ns.IsSecret(count) or ns.IsSecret(exp) then return false end
    wellRested = { count = count, expirationTime = exp }
    return true
end

local function Read()
    -- Read again next time too, if either couldn't be read now.
    local fed, rested = ReadWellFed(), ReadWellRested()
    dirty = not (fed and rested)
end

local function RunOut(buff)
    return buff and buff.expirationTime and buff.expirationTime > 0 and buff.expirationTime <= GetTime()
end

-- Your Well Fed buff ({ icon, expirationTime, duration, auraInstanceID }), or nil.
function Supplies:WellFed()
    if dirty or RunOut(wellFed) then Read() end
    return wellFed or nil
end

-- A sleeping bag's Well-Rested ({ count, expirationTime }), or nil.
function Supplies:WellRested()
    if dirty or RunOut(wellRested) then Read() end
    return wellRested or nil
end

local events = CreateFrame("Frame")
if events.RegisterUnitEvent then
    events:RegisterUnitEvent("UNIT_AURA", "player")
else
    events:RegisterEvent("UNIT_AURA")
end
events:SetScript("OnEvent", function(_, _, unit)
    if unit == nil or unit == "player" then dirty = true end
end)
