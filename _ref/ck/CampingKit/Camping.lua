local addonName, ns = ...

---------------------------------------------------------------------------
-- Camping Kit: a tent that opens into your camping gear.
--
-- Over the tent: five "your pick" slots (food, drink or a weapon buff).
-- Under it: the Camp Benefits and Well Fed timers with the sleeping bag
-- between them. Below a gold divider: the camp-object row (Fishing, First
-- Aid, the campfire, your two professions), each with its profession button
-- under it. At a camp, what's there shows too (Camp.lua). Kit Core runs the
-- kit (opening, flyouts, pinning, dragging, screen edges, settings); this
-- file says what each slot does.
---------------------------------------------------------------------------

local Core = ns.Core
local U = Core.U
local MEDIA = ns.MEDIA

local BTN = 37
local RADIUS = 72          -- slot distance from the tent centre
local ROW_GAP = 8
local ROW_Y = RADIUS + 52  -- the camp-object row, below a gold divider clear of the timers and the bag
local DIVIDER_Y = -94      -- the divider, between the timers and bag and that row
local GLOW = { 1, 0.7, 0.25 } -- firelight

-- Screen degrees (-90 = up) to offsets (+y = up).
local function Offset(angleDeg, r)
    local a = math.rad(angleDeg)
    return r * math.cos(a), -r * math.sin(a)
end

-- Where a slot sits relative to the tent centre: on the ring, or in the row below.
local function SlotOffset(slot)
    if slot.row then
        return (slot.row - 3) * (BTN + ROW_GAP), -ROW_Y -- five across, centred
    end
    if slot.pos then return slot.pos[1], slot.pos[2] end
    return Offset(slot.angle, slot.radius or RADIUS)
end

---------------------------------------------------------------------------
-- State
---------------------------------------------------------------------------

local assigned = {}       -- [slotKey] = itemID the slot uses
local auras = {}          -- [key from ns.AURA] = { exp, dur, count, ... } or nil

---------------------------------------------------------------------------
-- Professions: which camp objects this character can place
---------------------------------------------------------------------------

local function HasProfession(key)
    local p = ns.PROFESSIONS[key]
    for _, id in ipairs(p.recipes) do if U.Known(id) then return true end end
    for _, id in ipairs(p.items) do if U.Owned(id) then return true end end
    return false
end

-- Your two primary professions, in the game's order when it can tell us.
local function PrimaryProfessions()
    local list, seen = {}, {}
    if GetProfessions and GetProfessionInfo then
        local ok, p1, p2 = pcall(GetProfessions)
        if ok then
            for _, index in ipairs({ p1 or 0, p2 or 0 }) do
                if index ~= 0 then
                    local okInfo, _, _, _, _, _, _, skillLine = pcall(GetProfessionInfo, index)
                    if okInfo then
                        for key, p in pairs(ns.PROFESSIONS) do
                            if p.skillLine == skillLine and not seen[key] then
                                list[#list + 1], seen[key] = key, true
                            end
                        end
                    end
                end
            end
        end
    end
    for _, key in ipairs(ns.PRIMARY_ORDER) do
        if #list >= 2 then break end
        if not seen[key] and HasProfession(key) then
            list[#list + 1], seen[key] = key, true
        end
    end
    return list
end

-- Point each profession slot at its item list. Out of combat only.
local function ResolveProfessions()
    local primaries = PrimaryProfessions()
    for _, slot in ipairs(ns.SLOTS) do
        local key = slot.profession or (slot.primary and primaries[slot.primary])
        if slot.profession or slot.primary then
            local p = key and ns.PROFESSIONS[key]
            slot.items = p and p.items or {}
            slot.profLabel = p and p.label or nil
            slot.profKey = p and key or nil
        end
    end
end

-- Highest rank spell you know for a profession (casting it opens the window).
local function KnownRank(key)
    for _, id in ipairs(ns.PROFESSIONS[key].ranks or {}) do
        if U.Known(id) then return id end
    end
end

-- Every profession the game lists for you (skill line IDs).
local function LearnedSkillLines()
    local set = {}
    if not (GetProfessions and GetProfessionInfo) then return set end
    local ok, a, b, c, d, e, f = pcall(GetProfessions)
    if not ok then return set end
    for _, index in ipairs({ a or 0, b or 0, c or 0, d or 0, e or 0, f or 0 }) do
        if index ~= 0 then
            local okInfo, _, _, _, _, _, _, skillLine = pcall(GetProfessionInfo, index)
            if okInfo and skillLine then set[skillLine] = true end
        end
    end
    return set
end

-- Learned the profession at all: the game's list, a rank spell, a known camp
-- recipe or a camp object in your bags.
local function ProfessionKnown(key)
    if not key then return false end
    local p = ns.PROFESSIONS[key]
    if p and LearnedSkillLines()[p.skillLine] then return true end
    return KnownRank(key) ~= nil or HasProfession(key)
end

-- For professions without a rank spell to cast (gathering, fishing).
local function OpenProfession(kit, key)
    local p = key and ns.PROFESSIONS[key]
    if not p then return end
    local api = C_TradeSkillUI and C_TradeSkillUI.OpenTradeSkill
    if api and pcall(api, p.skillLine) then return end
    kit:Print("Couldn't open " .. p.label .. " from here. Try your spellbook's Professions tab.")
end

---------------------------------------------------------------------------
-- Camp auras
---------------------------------------------------------------------------

local function ReadAura(spellID)
    if not (C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID) then return false end
    local ok, a = pcall(C_UnitAuras.GetPlayerAuraBySpellID, spellID)
    if not ok then return false end
    if not a then return true, nil end
    local exp, dur, count = a.expirationTime, a.duration, a.applications
    if U.Sealed(exp) or U.Sealed(dur) then exp, dur = nil, nil end
    if U.Sealed(count) then count = nil end
    local inst = a.auraInstanceID
    if U.Sealed(inst) then inst = nil end
    local icon = a.icon
    if U.Sealed(icon) then icon = nil end
    return true, { exp = exp, dur = dur, count = count, instance = inst, harmful = a.isHarmful, icon = icon }
end

-- Well Fed: any helpful aura with the client's name for Well Fed.
local wellFedName
local function ScanWellFed()
    if not (C_UnitAuras and C_UnitAuras.GetAuraDataByIndex) then return end
    wellFedName = wellFedName or U.SpellName(ns.WELL_FED_SPELL) or "Well Fed"
    for i = 1, 40 do
        local ok, a = pcall(C_UnitAuras.GetAuraDataByIndex, "player", i, "HELPFUL")
        if not ok then return end -- hidden right now: keep what we had
        if not a then break end
        if not U.Sealed(a.name) and a.name == wellFedName then
            local entry
            if a.spellId and not U.Sealed(a.spellId) then _, entry = ReadAura(a.spellId) end
            auras.wellFed = entry or { icon = a.icon }
            return
        end
    end
    auras.wellFed = nil
end

-- The client's own name for each buff in ns.CAMP_CONFLICTS, by spell ID.
-- Kept once found; one the client can't name yet is asked again next scan.
local conflictNames = {}
local function ConflictName(spellID)
    local name = conflictNames[spellID]
    if not name then
        name = U.SpellName(spellID)
        conflictNames[spellID] = name
    end
    return name
end

-- Buffs on you that cancel a camp object's bonus (ns.CAMP_CONFLICTS), by
-- profession: clashes[key] = { name, icon }, or nil. A buff counts if it has
-- one of the listed spell IDs, or the same name as one (any other rank).
local clashes = {}
local function ScanClashes()
    if not (C_UnitAuras and C_UnitAuras.GetAuraDataByIndex) then return end
    local byName, byID = {}, {}
    for i = 1, 40 do
        local ok, a = pcall(C_UnitAuras.GetAuraDataByIndex, "player", i, "HELPFUL")
        if not ok or (a and U.Sealed(a.name)) then return end -- hidden right now: keep what we had
        if not a then break end
        if a.name then
            local entry = { name = a.name, icon = not U.Sealed(a.icon) and a.icon or nil }
            byName[a.name] = entry
            if a.spellId and not U.Sealed(a.spellId) then byID[a.spellId] = entry end
        end
    end
    for key, ids in pairs(ns.CAMP_CONFLICTS) do
        local found
        for _, id in ipairs(ids) do
            local name = ConflictName(id)
            found = found or byID[id] or (name and byName[name])
        end
        clashes[key] = found
    end
end

-- Keeps what it last knew when the client won't say (usually in combat).
local function ScanAuras()
    for key, id in pairs(ns.AURA) do
        local ok, a = ReadAura(id)
        if ok then auras[key] = a end
    end
    ScanWellFed()
    ScanClashes()
end

local function AtCamp() return auras.nearby ~= nil end
ns.auras, ns.clashes, ns.AtCamp = auras, clashes, AtCamp

-- The buff on you, if any, that would cancel this camp object's bonus.
local function ClashFor(kit, btn)
    local key = btn.slot.data.profKey
    return kit.db.campClash and key and clashes[key] or nil
end

---------------------------------------------------------------------------
-- Food, drink and weapon buffs
---------------------------------------------------------------------------

local FOOD_SUBCLASS = (Enum and Enum.ItemConsumableSubclass and Enum.ItemConsumableSubclass.Fooddrink) or 5
local foodNames
local function IsFoodDrink(id)
    if not (id and C_Item and C_Item.GetItemInfoInstant) then return false end
    local _, _, _, _, _, classID, subClassID = C_Item.GetItemInfoInstant(id)
    local consumable = Enum and Enum.ItemClass and Enum.ItemClass.Consumable or 0
    if classID ~= consumable then return false end
    if subClassID == FOOD_SUBCLASS then return true end
    if not foodNames then
        foodNames = {}
        for _, sid in ipairs(ns.FOOD_SPELLS) do
            local name = U.SpellName(sid)
            if name then foodNames[name] = true end
        end
    end
    local spellName = C_Item.GetItemSpell and C_Item.GetItemSpell(id)
    return spellName and foodNames[spellName] or false
end

-- Weapon buffs: known IDs, or the game's Item Enhancement category (found by
-- its enum key, so no hard-coded number or English text).
local weaponIDs, ENHANCE_SUBCLASS
local function IsWeaponBuff(id)
    if not id then return false end
    if not weaponIDs then
        weaponIDs = {}
        for _, i in ipairs(ns.WEAPON_BUFFS) do weaponIDs[i] = true end
        if Enum and Enum.ItemConsumableSubclass then
            for k, v in pairs(Enum.ItemConsumableSubclass) do
                if type(k) == "string" and k:lower():find("enhanc") then ENHANCE_SUBCLASS = v end
            end
        end
    end
    if weaponIDs[id] then return true end
    if ENHANCE_SUBCLASS and C_Item and C_Item.GetItemInfoInstant then
        local _, _, _, _, _, classID, subClassID = C_Item.GetItemInfoInstant(id)
        local consumable = Enum and Enum.ItemClass and Enum.ItemClass.Consumable or 0
        return classID == consumable and subClassID == ENHANCE_SUBCLASS
    end
    return false
end

local function Accepts(id) return IsFoodDrink(id) or IsWeaponBuff(id) end

local function BagItems()
    local list, seen = {}, {}
    if not C_Container then return list end
    local lastBag = NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4
    for bag = 0, lastBag do
        for s = 1, C_Container.GetContainerNumSlots(bag) or 0 do
            local id = C_Container.GetContainerItemID(bag, s)
            if id and not seen[id] then
                seen[id] = true
                if Accepts(id) then list[#list + 1] = id end
            end
        end
    end
    return list -- unsorted and uncapped: PickChoices orders and trims it
end

-- Weapon subclass IDs, from the game's enum where it has one.
local WS = Enum and Enum.ItemWeaponSubclass or {}
local function Sub(name, fallback) return WS[name] or fallback end
local SHARP = { [Sub("Axe1H", 0)] = true, [Sub("Axe2H", 1)] = true, [Sub("Polearm", 6)] = true,
                [Sub("Sword1H", 7)] = true, [Sub("Sword2H", 8)] = true, [Sub("Dagger", 15)] = true }
local BLUNT = { [Sub("Mace1H", 4)] = true, [Sub("Mace2H", 5)] = true, [Sub("Staff", 10)] = true }
local NOT_MELEE = { [Sub("Bows", 2)] = true, [Sub("Guns", 3)] = true, [Sub("Thrown", 16)] = true,
                    [Sub("Crossbow", 18)] = true, [Sub("Wand", 19)] = true, [Sub("Fishingpole", 20)] = true }

-- The melee weapon in a hand (16 main, 17 off): its subclass, or nil.
local function HeldWeapon(invSlot)
    local id = GetInventoryItemID and GetInventoryItemID("player", invSlot)
    if not id then return nil end
    local _, _, _, _, _, classID, subClassID = C_Item.GetItemInfoInstant(id)
    local weapon = Enum and Enum.ItemClass and Enum.ItemClass.Weapon or 2
    if classID ~= weapon or NOT_MELEE[subClassID] then return nil end
    return subClassID
end

local function Fits(itemID, subClassID)
    if not subClassID then return false end
    local kind = ns.WEAPON_BUFF_KIND[itemID]
    if kind == "sharp" then return SHARP[subClassID] or false end
    if kind == "blunt" then return BLUNT[subClassID] or false end
    return true -- oils, poisons and anything newer: any melee weapon
end

-- Weapon enchants. Forever lets a poison sit on a weapon alongside a stone or
-- oil, so each hand can carry several; C_Item.GetWeaponEnchantInfo lists them
-- all (the old global GetWeaponEnchantInfo returns false in Forever).
local WEAPON_SLOT = { [16] = Enum and Enum.WeaponSlot and Enum.WeaponSlot.MainHand or 0,
                      [17] = Enum and Enum.WeaponSlot and Enum.WeaponSlot.OffHand or 1 }
local ET = Enum and Enum.ItemEnchantType or {}
local TEMPORARY = ET.Temporary or 2

-- Poison enchants, by ID (Instant, Deadly, Crippling, Mind-numbing, Wound,
-- every rank), so no names are needed. Any enchant showing a poison item's
-- icon counts too, in case Forever gives them new IDs.
local POISON_ENCHANTS = {}
for _, e in ipairs({ 323, 324, 325, 623, 624, 625, 7, 8, 626, 627, 2630, 22, 603,
                     35, 23, 643, 703, 704, 705, 706 }) do POISON_ENCHANTS[e] = true end
local poisonIcons, poisonIconsDone = {}, false
local function IsPoisonEnchant(e)
    if e.enchantID and POISON_ENCHANTS[e.enchantID] then return true end
    if not poisonIconsDone and C_Item and C_Item.GetItemIconByID then
        local all = true
        for id, kind in pairs(ns.WEAPON_BUFF_KIND) do
            if kind == "poison" then
                local icon = C_Item.GetItemIconByID(id)
                if icon then poisonIcons[icon] = true else all = false end
            end
        end
        poisonIconsDone = all
    end
    return e.enchantIconID and poisonIcons[e.enchantIconID] or false
end

-- The enchants on the weapon in a hand, each { enchantType, timeLeft (seconds
-- or nil), enchantID, enchantIconID }; empty while the client won't say.
local function HandEnchants(invSlot)
    local list = {}
    if not (C_Item and C_Item.GetWeaponEnchantInfo) then return list end
    local ok, enchants = pcall(C_Item.GetWeaponEnchantInfo, WEAPON_SLOT[invSlot])
    if not ok or type(enchants) ~= "table" or U.Sealed(enchants) then return list end
    for _, e in ipairs(enchants) do
        if type(e) == "table" and e.hasEnchant and not U.Sealed(e.hasEnchant) then
            local ms = not U.Sealed(e.timeLeft) and e.timeLeft or nil
            list[#list + 1] = {
                enchantType = not U.Sealed(e.enchantType) and e.enchantType or nil,
                timeLeft = (ms and ms > 0) and ms / 1000 or nil, -- milliseconds, as the old call gave
                enchantID = not U.Sealed(e.enchantID) and e.enchantID or nil,
                enchantIconID = not U.Sealed(e.enchantIconID) and e.enchantIconID or nil,
            }
        end
    end
    return list
end

-- Both hands: { sub = weapon subclass or nil, stone = seconds left on a
-- temporary enchant that isn't a poison (a stone or oil) or false, poison =
-- seconds left on a poison or false }. A time of 0 means on, time unknown.
local handsCache, handsAt
local function Hands()
    local now = GetTime()
    if handsCache and handsAt == now then return handsCache end
    local hands = {}
    for _, slot in ipairs({ 16, 17 }) do
        local h = { sub = HeldWeapon(slot), slot = slot, stone = false, poison = false }
        if h.sub then
            for _, e in ipairs(HandEnchants(slot)) do
                local secs = e.timeLeft or 0
                if IsPoisonEnchant(e) then
                    h.poison = math.max(h.poison or 0, secs)
                elseif e.enchantType == TEMPORARY or e.enchantType == nil then
                    h.stone = math.max(h.stone or 0, secs)
                end
            end
        end
        hands[#hands + 1] = h
    end
    handsCache, handsAt = hands, now
    return hands
end

local function IsPoison(id) return id and ns.WEAPON_BUFF_KIND[id] == "poison" or false end

-- The time left on the first weapon this item fits (main hand first), and
-- whether a weapon it fits is missing it. A poison looks for a poison
-- enchant; a stone or oil for any other temporary enchant.
local function WeaponBuffState(id)
    local poison = IsPoison(id)
    local left, bare = nil, false
    for _, h in ipairs(Hands()) do
        if Fits(id, h.sub) then
            local mine = poison and h.poison or (not poison and h.stone)
            if mine then
                if mine > 0 then left = left or mine end
            else
                bare = true
            end
        end
    end
    return left, bare
end

-- Snoozing (from the tent's right-click menu): every reminder glow, and the
-- pop-outs that come with them, stays off until then. Saved per character
-- as a clock time, so it carries through a reload.
local function Snoozed(kit)
    return (kit.cdb.snoozeUntil or 0) > time()
end

ns.Snoozed = Snoozed

local function SnoozeLeft(kit)
    return math.max(0, (kit.cdb.snoozeUntil or 0) - time())
end

-- The glow setting that covers this item: poisons have their own.
local function WeaponGlowOn(kit, id)
    if Snoozed(kit) then return false end
    local poison = IsPoison(id)
    return (poison and kit.db.poisonGlow or (not poison and kit.db.weaponGlow)) and true or false
end

-- A pick slot holding a stone, oil or poison (that you have) which a weapon
-- it fits is missing.
local function SlotNeedsWeaponBuff(kit, btn)
    local id = btn.itemID
    if not (id and IsWeaponBuff(id) and U.Owned(id) and WeaponGlowOn(kit, id)) then return false end
    local _, bare = WeaponBuffState(id)
    return bare
end


---------------------------------------------------------------------------
-- Which item a slot holds
---------------------------------------------------------------------------

local function ChooseItem(kit, slot)
    if slot.pick then return kit.cdb.picks[slot.key] end -- keeps your pick even at 0
    local pick = kit.cdb.picks[slot.key]
    if pick and U.Owned(pick) and U.InList(slot.items, pick) then return pick end
    for _, id in ipairs(slot.items) do
        if U.Owned(id) then return id end
    end
    -- Nothing owned: show the entry-level one greyed out (a profession's tier 1
    -- object; your faction's banner for Tailoring).
    if slot.empty then return slot.empty end
    if slot.profKey == "tailoring" then
        return (UnitFactionGroup and UnitFactionGroup("player") == "Horde") and 279972 or 279973
    end
    return slot.items[#slot.items]
end

---------------------------------------------------------------------------
-- Camp timers: Camp Benefits and Well Fed under the tent. The rest
-- countdown sweeps over the tent itself.
---------------------------------------------------------------------------

local DIAL = 30
local DIAL_DOCKED = 20
local DIAL_EDGE = 24 -- on a screen edge (or in a Kit Dock box): a little smaller, so the two on the rim don't touch
local dials = {}
ns.dials, ns.DIAL, ns.DIAL_EDGE = dials, DIAL, DIAL_EDGE

local function AuraTooltip(kit, owner, key)
    kit:TipOwner(owner)
    local a = auras[key]
    if not a and key == "benefits" then
        GameTooltip:AddLine("No camp benefits")
        GameTooltip:AddLine("Place camp objects at a campfire and /sit by it for about a minute to get their buffs.", 1, 1, 1, true)
        return
    elseif not a and key == "wellFed" then
        GameTooltip:AddLine("Not Well Fed")
        GameTooltip:AddLine("Eat food that makes you Well Fed (cooked food, or Cookie's Feast at camp).", 1, 1, 1, true)
        return
    end
    -- The live aura tooltip, same as your buff bar.
    if a and a.instance then
        local fn = a.harmful and GameTooltip.SetUnitDebuffByAuraInstanceID or GameTooltip.SetUnitBuffByAuraInstanceID
        if fn and pcall(fn, GameTooltip, "player", a.instance, a.harmful and "HARMFUL" or "HELPFUL")
            and GameTooltip:NumLines() > 0 then
            return
        end
        kit:TipOwner(owner)
    end
    GameTooltip:SetSpellByID(ns.AURA[key] or ns.WELL_FED_SPELL)
end

local function ToggleDialPin(kit, key)
    if InCombatLockdown() then return end
    local k = "dial_" .. key
    kit.cdb.pinned[k] = not kit.cdb.pinned[k]
    for _, t in ipairs(ns.DIALS) do
        if t.key == key then kit:Print(t.label .. (kit.cdb.pinned[k] and ": always shown." or ": shows when it's missing.")) end
    end
    kit:Refresh(false)
    kit:SettingsChanged()
end

local function MakeDials(kit)
    for _, t in ipairs(ns.DIALS) do
        local f = CreateFrame("Frame", "CampingKitDial_" .. t.key, kit.holder)
        f:SetSize(DIAL, DIAL)
        f:SetFrameLevel(14)
        f:SetPoint("CENTER", kit.kit, "CENTER", t.x, t.y)
        f:EnableMouse(true)
        f.icon = f:CreateTexture(nil, "ARTWORK")
        f.icon:SetPoint("TOPLEFT", 2, -2)
        f.icon:SetPoint("BOTTOMRIGHT", -2, 2)
        local mask = f:CreateMaskTexture()
        mask:SetTexture(MEDIA .. "circle_mask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        mask:SetAllPoints(f.icon)
        f.icon:AddMaskTexture(mask)
        f.time = f:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
        f.ring = f:CreateTexture(nil, "OVERLAY", nil, 6)
        f.ring:SetAllPoints()
        f.ring:SetTexture(MEDIA .. "ring_prof_64", nil, nil, "LINEAR")
        f.def = t
        f.key, f.label = t.key, t.label
        f.stack = f:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
        f.stack:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 1)
        if t.always then
            -- A tight halo whose brightest band sits on the border, plus the
            -- border itself brightened, pulsing together.
            kit:AddGlow(f, "glow_ring", 1.3)
            f.glowBorder = f:CreateTexture(nil, "OVERLAY", nil, 7)
            f.glowBorder:SetAllPoints(f.ring)
            f.glowBorder:SetTexture(MEDIA .. "ring_prof_64", nil, nil, "LINEAR")
            f.glowBorder:SetBlendMode("ADD")
            f.glowBorder:SetVertexColor(GLOW[1], GLOW[2], GLOW[3])
            f.glowBorder:Hide()
            f.glow:HookScript("OnShow", function() f.glowBorder:Show() end)
            f.glow:HookScript("OnHide", function() f.glowBorder:Hide() end)
        end
        f.pin = f:CreateTexture(nil, "OVERLAY", nil, 7)
        f.pin:SetTexture(MEDIA .. "pin_dot", nil, nil, "LINEAR")
        f.pin:SetSize(9, 9)
        f.pin:SetPoint("CENTER", f, "CENTER", -10, 10)
        f.pin:Hide()
        f:SetScript("OnEnter", function(self)
            kit:Hover(true)
            AuraTooltip(kit, self, self.key)
            GameTooltip:AddLine(kit.cdb.pinned["dial_" .. self.key] and "Shift-right-click: stop always showing"
                or "Shift-right-click: always show, even with the kit closed", 0.6, 0.6, 0.6)
            GameTooltip:Show()
        end)
        f:SetScript("OnLeave", function() kit:Hover(false) end)
        f:SetScript("OnMouseUp", function(self, button)
            if button == "RightButton" and IsShiftKeyDown() then ToggleDialPin(kit, self.key) end
        end)
        f:Hide()
        dials[#dials + 1] = f
    end
end

-- Time text: beside the timer off an edge (below it, turned with the layout);
-- on an edge, inside its bottom so the timers stack in a column.
local TIME_POINT = { up = { "BOTTOM", "TOP", 0, 1 }, down = { "TOP", "BOTTOM", 0, -1 },
                     left = { "RIGHT", "LEFT", -3, 0 }, right = { "LEFT", "RIGHT", 3, 0 } }
local function SizeDial(kit, f, compact)
    local size = compact and DIAL_DOCKED or (kit.edgeSide and DIAL_EDGE) or DIAL
    local where = kit.edgeSide and "edge" or kit:FaceDir("down")
    if f.timeAt ~= where then
        f.timeAt = where
        f.time:ClearAllPoints()
        if where == "edge" then
            f.time:SetPoint("BOTTOM", f, "BOTTOM", 0, -2)
        else
            local p = TIME_POINT[where]
            f.time:SetPoint(p[1], f, p[2], p[3], p[4])
        end
    end
    if f.sizedFor == size then return end
    f.sizedFor = size
    f:SetSize(size, size)
    if f.glow then f.glow:SetSize(size * 1.3, size * 1.3) end
    local p = size / DIAL * 10
    f.pin:ClearAllPoints()
    f.pin:SetPoint("CENTER", f, "CENTER", -p, p)
    f.pin:SetSize(compact and 7 or 9, compact and 7 or 9)
    f.time:SetShown(not compact)
end

local function DialText(f)
    local a = auras[f.key]
    local left = a and a.exp and a.exp > 0 and (a.exp - GetTime()) or nil
    f.time:SetText(left and left > 0 and U.FormatLeft(left) or "")
end

-- Which timers show. Camp Benefits and Well Fed are always in view with the
-- kit open: greyed out (and glowing, if that setting is on) while you don't
-- have the buff. With the kit closed, a timer shows if it's pinned, or while
-- its buff is missing and glowing as a reminder. Returns true if any came or went.
local function PaintTimers(kit)
    -- (not for Kit Core's trial layout of the other state, open or closed:
    -- the timers aren't secure, so they don't need one, and painting them for
    -- it showed and hid them on every refresh, flashing on a screen edge)
    if not kit.built or #dials == 0 or kit.trial then return false end
    local changed = false
    for _, f in ipairs(dials) do
        local t = f.def
        local a = auras[f.key]
        local always = t.always and (not t.needsItem or U.Owned(t.needsItem))
        if t.showSetting and not kit.db[t.showSetting] then a, always = nil, false end -- turned off
        f.stack:SetText(a and a.count and a.count > 1 and a.count or "")
        f.wantGlow = (not a and always and kit.db[t.glowSetting] and not Snoozed(kit)) and true or false
        local compact = kit.compactAngle ~= nil
        local wasShown = f:IsShown()
        local pinned = kit.cdb.pinned["dial_" .. f.key]
        local wanted = kit.open or pinned or f.wantGlow
        f.wouldShow = (a or always) and (pinned or f.wantGlow) and kit.db.shown ~= false and true or false
        if (a or always) and wanted and not kit.tucked and not kit.quiet and kit.db.shown ~= false then
            f.icon:SetTexture(a and a.icon or U.SpellIcon(ns.AURA[f.key] or ns.WELL_FED_SPELL))
            f.icon:SetDesaturated(not a)
            f.ring:SetTexture(kit:SmallRingArt(f), nil, nil, "LINEAR")
            if f.glowBorder then f.glowBorder:SetTexture(kit:SmallRingArt(f), nil, nil, "LINEAR") end
            DialText(f)
            SizeDial(kit, f, compact)
            f:SetScale(kit.db.scale)
            f:Show()
            if f.quietFade then f.quietFade = nil end
            if (compact or kit.edgeSide) and not wasShown and kit.Dock and kit.Dock.Fade then kit.Dock.Fade(f, false) end
        elseif kit.quiet and wasShown and kit.Dock and kit.Dock.Fade and not InCombatLockdown() then
            -- Put away in a Kit Dock box while another kit from it is open: fade.
            if not f.quietFade then
                f.quietFade = true
                kit.Dock.Fade(f, true, function()
                    f.quietFade = nil
                    if kit.quiet then f:Hide() end
                end)
            end
        else
            f:Hide()
        end
        if f:IsShown() ~= wasShown then changed = true end
        f.pin:SetShown(pinned and true or false)
        kit:SetGlow(f, f.wantGlow)
    end
    return changed
end

---------------------------------------------------------------------------
-- What wants your attention: a missing buff (with its glow on), or a weapon
-- that needs a stone, oil or poison a pick slot holds. When that set
-- changes, the kit refreshes so the right things pop out.
---------------------------------------------------------------------------

local function AttentionReasons(kit)
    local why = {}
    for _, f in ipairs(dials) do
        if f.wantGlow then why[#why + 1] = (f.label or f.key) .. " missing" end
    end
    local stone, poison
    for _, slot in ipairs(ns.SLOTS) do
        local btn = slot.pick and kit.slots[slot.key]
        if btn and SlotNeedsWeaponBuff(kit, btn) then
            if IsPoison(btn.itemID) then poison = true else stone = true end
        end
    end
    if stone then why[#why + 1] = "a weapon needs its stone or oil" end
    if poison then why[#why + 1] = "a weapon needs poison" end
    return why
end

local lastAttention
local function CheckAttention(kit)
    local sig = table.concat(AttentionReasons(kit), "|")
    if sig ~= lastAttention then
        lastAttention = sig
        if C_Timer and not InCombatLockdown() then
            C_Timer.After(0, function() if not InCombatLockdown() then kit:Refresh(false) end end)
        end
    end
end

---------------------------------------------------------------------------
-- Painting helpers
---------------------------------------------------------------------------

-- Pick slot extras: the time left on the weapon its item fits, below it, and
-- a glow while that weapon has no buff. Food never glows: the Well Fed
-- timer is the reminder to eat.
local function PaintWeaponSlot(kit, btn)
    local id = btn.itemID
    if not (id and IsWeaponBuff(id)) then
        btn.note:SetText("")
        kit:SetGlow(btn, false)
        return
    end
    local left, bare = WeaponBuffState(id)
    btn.note:SetText(left and U.FormatLeft(left) or "")
    kit:SetGlow(btn, (WeaponGlowOn(kit, id) and bare and U.Owned(id)) and true or false)
end

-- Seconds until an item is off cooldown (the global cooldown doesn't count).
local function CooldownLeft(id)
    local start, dur = U.ItemCooldown(id)
    if U.Sealed(start) or U.Sealed(dur) or not start or not dur or start == 0 or dur <= 1.5 then return 0 end
    return math.max(0, start + dur - GetTime())
end

-- A camp object's heads-up badge: the icon of a buff you already have that
-- cancels the object's bonus, in a small gold ring on the slot's corner.
-- Shown at a campfire while the camping cooldown is up.
local function AddClashBadge(kit, btn)
    local b = CreateFrame("Frame", nil, btn)
    b:SetSize(18, 18)
    b:SetFrameLevel(btn:GetFrameLevel() + 3) -- over the cooldown swipe
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetPoint("TOPLEFT", 2, -2)
    b.icon:SetPoint("BOTTOMRIGHT", -2, 2)
    local mask = b:CreateMaskTexture()
    mask:SetTexture(MEDIA .. "circle_mask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mask:SetAllPoints(b.icon)
    b.icon:AddMaskTexture(mask)
    b.ring = b:CreateTexture(nil, "OVERLAY")
    b.ring:SetAllPoints()
    b:SetPoint("CENTER", btn, "CENTER", -15, 15)
    b:Hide()
    btn.clash = b
end

local function PaintClash(kit, btn)
    local c, id = ClashFor(kit, btn), btn.itemID
    local wanted = c and id and U.Owned(id) and AtCamp() or false
    local left = wanted and CooldownLeft(id) or 0
    local show = wanted and left == 0
    if show then
        btn.clash.icon:SetTexture(c.icon or 134400)
        btn.clash.ring:SetTexture(kit:SmallRingArt(btn.clash), nil, nil, "LINEAR")
        btn.clash:ClearAllPoints()
        btn.clash:SetPoint("CENTER", btn, "CENTER", btn.isRound and -13 or -15, btn.isRound and 13 or 15)
    end
    btn.clash:SetShown(show and true or false)
    if wanted and left > 0 and C_Timer then
        local at = GetTime() + left
        if not btn.clashAt or math.abs(btn.clashAt - at) > 1 then
            btn.clashAt = at
            C_Timer.After(left + 0.2, function()
                if btn.clashAt ~= at then return end
                btn.clashAt = nil
                kit:PaintAll()
            end)
        end
    end
end

---------------------------------------------------------------------------
-- Profession buttons: small round buttons under each camp object (Cooking
-- under the campfire).
---------------------------------------------------------------------------

local function ApplyProfShape(kit, sb)
    sb.ring:SetTexture(kit:SmallRingArt(sb), nil, nil, "LINEAR") -- (ring art for its size on screen)
end

local function ApplyProfShapes(kit)
    for _, btn in pairs(kit.slots) do
        if btn.sub then ApplyProfShape(kit, btn.sub) end
    end
end

local function ProfKey(data) return data.campfire and "cooking" or data.profKey end

local function ProfSub(data)
    return {
        key = "prof_" .. data.key, label = "Profession", below = true,
        binding = data.campfire and "Open Cooking" or ("Open " .. data.label:lower() .. " profession"),
        Update = function(kit, sb)
            local key = ProfKey(data)
            local known = ProfessionKnown(key)
            sb.profKey, sb.unknown = key, not known
            -- Fishing and First Aid (anyone can learn them) always show, greyed
            -- out until you do. Others only once learned.
            if not kit.db.showProfButtons or kit.compactAngle or not (known or data.profession ~= nil) then
                sb.hidden = true
                return
            end
            if not sb.hasOpen then
                sb:SetAttribute("_ckprof", function(b)
                    if kit:Debounced() then OpenProfession(kit, b.profKey) end
                end)
                sb.hasOpen = true
            end
            local rank = known and KnownRank(key)
            if rank then
                sb:SetAttribute("type", "spell")
                sb:SetAttribute("spell", rank)
            elseif known then
                sb:SetAttribute("type", "ckprof")
                sb:SetAttribute("spell", nil)
            else
                sb:SetAttribute("type", nil) -- not learned: the click does nothing
                sb:SetAttribute("spell", nil)
            end
        end,
        Paint = function(kit, sb)
            local p = sb.profKey and ns.PROFESSIONS[sb.profKey]
            sb.icon:SetTexture(p and U.SpellIcon(p.icon) or 134400)
            sb.icon:SetDesaturated(sb.unknown and true or false)
        end,
        Tooltip = function(kit, sb)
            local p = sb.profKey and ns.PROFESSIONS[sb.profKey]
            GameTooltip:AddLine(p and p.label or "Profession")
            if sb.unknown then
                GameTooltip:AddLine("You haven't learned " .. (p and p.label or "this profession")
                    .. " yet. Any " .. (p and p.label or "profession") .. " trainer can teach it.", 1, 0.3, 0.3, true)
            else
                GameTooltip:AddLine("Click: open " .. (p and (p.window or p.label) or "the profession") .. " to craft", 0.3, 1, 0.4)
            end
        end,
    }
end

---------------------------------------------------------------------------
-- The slots (Data.lua)
---------------------------------------------------------------------------

local CLEAR = "clear"

local function SlotUpdate(kit, btn)
    local data = btn.slot.data
    local id = ChooseItem(kit, data)
    assigned[data.key] = id
    btn.itemID = id
    if data.pick then
        -- A macro: "/use" the item, and for a weapon buff also open the
        -- character panel (see the slot's PreClick).
        btn:SetAttribute("type", "macro")
    else
        btn:SetAttribute("type", "item")
        btn:SetAttribute("item", id and ("item:" .. id) or nil)
    end
    if data.onlyIfOwned and not (id and U.Owned(id)) then btn.hidden = true end
end

local function SlotPaint(kit, btn)
    local data, id = btn.slot.data, btn.itemID
    local n = U.ItemCount(id)
    local uses = U.ItemUses(id)
    btn.icon:SetTexture(id and U.ItemIcon(id) or nil) -- nothing chosen: just the empty slot
    btn.count:SetText(uses > 1 and uses or "")
    if id then U.SetCooldown(btn.cooldown, U.ItemCooldown(id)) else btn.cooldown:Clear() end
    local blocked = n == 0
    btn.icon:SetDesaturated(blocked)
    btn.icon:SetVertexColor(blocked and 0.6 or 1, blocked and 0.6 or 1, blocked and 0.6 or 1)
    if data.pick then PaintWeaponSlot(kit, btn) else kit:SetGlow(btn, false) end
    if btn.clash then PaintClash(kit, btn) end
end

local function SlotTooltip(kit, btn)
    local data, id = btn.slot.data, btn.itemID
    if data.pick and not id then
        GameTooltip:AddLine("Your pick")
        GameTooltip:AddLine("Drag food, drink or a weapon buff (sharpening stone, weightstone, oil, poison) here, or right-click to choose from what you carry.", 1, 1, 1, true)
    elseif id then
        GameTooltip:SetItemByID(id)
        if not U.Owned(id) then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("None in your bags.", 1, 0.3, 0.3)
        end
    else
        GameTooltip:AddLine(data.profLabel or data.label)
        GameTooltip:AddLine(data.primary and "No second profession with camp objects yet." or "Nothing for this slot yet.", 1, 0.3, 0.3, true)
    end
    local clash = id and ClashFor(kit, btn)
    if clash then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("You already have " .. clash.name .. ", so you won't get this one's bonus.", 1, 0.82, 0, true)
    elseif id and data.profKey and ns.CAMP_CONFLICTS[data.profKey] then
        -- A tier 1 object (the one with a bonus): say which class buff it doesn't stack with.
        local p = ns.PROFESSIONS[data.profKey]
        for i = #p.recipes, #p.items do
            if p.items[i] == id then
                local name = ns.Camp.Competes(ns.Camp.ObjectBySpell(p.recipes[#p.recipes]))
                if name then
                    GameTooltip:AddLine(" ")
                    GameTooltip:AddLine("Doesn't stack with " .. name .. ".", 1, 0.55, 0.25, true)
                end
                break
            end
        end
    end
    -- A camp object you can place: its bonus at each level, yours highlighted.
    local brackets = id and data.profKey and ns.Camp.Brackets(data.profKey)
    if brackets then
        local lvl = UnitLevel("player") or 1
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Bonus by level")
        for _, b in ipairs(brackets) do
            local range = b.to > b.from and (b.from .. "-" .. b.to) or tostring(b.from)
            local mine = lvl >= b.from and lvl <= b.to
            if mine then
                GameTooltip:AddDoubleLine(range, b.text, 0.25, 0.82, 0.29, 0.25, 0.82, 0.29)
            else
                GameTooltip:AddDoubleLine(range, b.text, 0.62, 0.62, 0.62, 0.62, 0.62, 0.62)
            end
        end
    end
end

-- Kit Core shows at most this many choices in a slot's grid and drops the rest.
local MAX_CHOICES = 24

-- What a pick slot's grid offers, most useful first, trimmed to fit with
-- room left for "Clear this slot": the slot's current item, then stones,
-- oils and poisons for the weapons you're holding, then food and drink,
-- then weapon buffs for weapons you aren't. Alphabetical within each.
local function PickChoices(kit, data)
    local current = kit.cdb.picks[data.key]
    local hands = Hands()
    local function Rank(id)
        if id == current then return 1 end
        if IsWeaponBuff(id) then
            for _, h in ipairs(hands) do
                if Fits(id, h.sub) then return 2 end
            end
            return 4
        end
        return 3
    end
    local rank, name = {}, {}
    local list = BagItems()
    for _, id in ipairs(list) do
        rank[id] = Rank(id)
        name[id] = U.ItemName(id) or tostring(id)
    end
    table.sort(list, function(a, b)
        if rank[a] ~= rank[b] then return rank[a] < rank[b] end
        if name[a] ~= name[b] then return name[a] < name[b] end
        return a < b
    end)
    local room = MAX_CHOICES - (current and 1 or 0)
    while #list > room do table.remove(list) end
    if current then list[#list + 1] = false end -- "clear", always last and always there
    return list
end

local function SlotChoices(kit, btn)
    local data = btn.slot.data
    local opts = {}
    if data.pick then
        opts = PickChoices(kit, data)
    else
        for _, id in ipairs(data.items or {}) do if U.Owned(id) then opts[#opts + 1] = id end end
    end
    local list = {}
    for _, id in ipairs(opts) do
        if id then
            list[#list + 1] = {
                icon = U.ItemIcon(id), item = id, pick = id, close = true,
                selected = function() return assigned[data.key] == id end,
                count = function() return U.ItemUses(id) end,
                hint = "Click to put this in the slot",
            }
        else
            list[#list + 1] = {
                icon = "Interface\\Buttons\\UI-GroupLoot-Pass-Up", label = "Clear this slot", pick = CLEAR, close = true,
                hint = "Click to empty the slot",
            }
        end
    end
    return list
end

-- Using a weapon buff also opens the character panel, so your weapons are
-- right there to click ("/click" on the character button; opening it from
-- addon code taints it).
local function PickSetup(kit, btn)
    btn:SetScript("PreClick", function(self, mouse)
        if InCombatLockdown() or mouse ~= "LeftButton" then return end
        local id = self.itemID
        local text = id and ("/use item:" .. id) or ""
        if id and IsWeaponBuff(id) and CharacterMicroButton and not (CharacterFrame and CharacterFrame:IsShown()) then
            text = text .. "\n/click CharacterMicroButton"
        end
        self:SetAttribute("macrotext", text)
    end)
end

local function DropOnPick(kit, btn)
    if InCombatLockdown() then return end
    local kind, id = GetCursorInfo()
    if kind ~= "item" or not id then return end
    if not Accepts(id) then
        if UIErrorsFrame then UIErrorsFrame:AddMessage("That slot takes food, drink or a weapon buff.", 1, 0.3, 0.3) end
        return
    end
    kit.cdb.picks[btn.slot.key] = id
    ClearCursor()
    kit:Refresh(false)
end

-- The sit button: the game's own command for the Sit emote, in this client's
-- language (found by the emote's token), or /sit if the client doesn't list it.
local sitCommand
local function SitCommand()
    if sitCommand then return sitCommand end
    sitCommand = "/sit"
    for i = 1, 1000 do
        if _G["EMOTE" .. i .. "_TOKEN"] == "SIT" then
            sitCommand = _G["EMOTE" .. i .. "_CMD1"] or sitCommand
            break
        end
    end
    return sitCommand
end

local function SitSlot(s, x, y)
    return {
        key = s.key, label = s.label, pos = { x, y }, data = s, small = true, rim = true, noPin = true,
        binding = "Sit",
        Pop = function() return AtCamp() end,
        Update = function(kit, btn)
            btn:SetAttribute("type", "macro")
            btn:SetAttribute("macrotext", SitCommand())
            if not AtCamp() then btn.hidden = true end
        end,
        Paint = function(kit, btn)
            U.SetIcon(btn, "Interface\\Icons\\Spell_Nature_Sleep")
            btn.cooldown:Clear()
        end,
        Tooltip = function()
            GameTooltip:AddLine("Sit")
            GameTooltip:AddLine("Sit by the fire for about a minute to get the camp's bonuses.", 1, 1, 1, true)
        end,
    }
end

local slots = {}
for _, s in ipairs(ns.SLOTS) do
    local x, y = SlotOffset(s)
    local d = {
        key = s.key, label = s.label, pos = { x, y }, grid = s.grid, data = s,
        Update = SlotUpdate, Paint = SlotPaint, Tooltip = SlotTooltip,
        Choices = SlotChoices, flyout = "right", perRow = 3,
        flyoutHint = s.pick and "Right-click: choose food, drink or weapon buff" or "Right-click: choose type",
        nothing = s.pick and "No food, drink or weapon buffs in your bags."
            or ("You have nothing for the " .. s.label:lower() .. " slot to choose from."),
        OnPick = function(kit, btn, value)
            kit.cdb.picks[btn.slot.key] = (value ~= CLEAR) and value or nil
        end,
        binding = "Use " .. s.label:lower() .. " slot",
    }
    if s.row then
        d.noPin = true -- camp objects: placed at a camp, not kept out
        d.sub = ProfSub(s)
        d.flyGap = 24 -- the flyout clears the profession button under it
        d.Setup = AddClashBadge
    end
    if s.pick then
        d.Setup = PickSetup
        d.OnDrop = DropOnPick
        -- With the kit closed, a pick slot whose stone, oil or poison a
        -- weapon needs (or food, while you're not Well Fed) pops out.
        d.Pop = function(kit, btn) return SlotNeedsWeaponBuff(kit, btn) end
    end
    if s.sit then d = SitSlot(s, x, y) end
    slots[#slots + 1] = d
end

---------------------------------------------------------------------------
-- The kit
---------------------------------------------------------------------------

local function Repaint(kit) kit:PaintAll() end
local function Refresh(kit) kit:Refresh(false) end

local function TentGlows(kit)
    return (kit.db.campGlow and not Snoozed(kit) and AtCamp() and not auras.benefits) and true or false
end

-- What shows and glows changes with a snooze: redo it now (after combat,
-- if need be; the glows go at once either way).
local function AfterSnooze(kit)
    if InCombatLockdown() then kit.pending = true kit:PaintAll() else kit:Refresh(false) end
end

-- Wake up when the snooze runs out. An older wake-up for a snooze since
-- replaced finds it still snoozed and does nothing.
local function WakeLater(kit)
    if not (C_Timer and Snoozed(kit)) then return end
    C_Timer.After(SnoozeLeft(kit) + 1, function()
        if not Snoozed(kit) then
            kit.cdb.snoozeUntil = nil
            AfterSnooze(kit)
        end
    end)
end

-- seconds, or nil to wake the reminders now.
local function Snooze(kit, seconds)
    kit.cdb.snoozeUntil = seconds and (time() + seconds) or nil
    if seconds then
        kit:Print(("Reminder glows snoozed for %s."):format(U.FormatLeft(seconds)))
        WakeLater(kit)
    else
        kit:Print("Reminder glows are back on.")
    end
    AfterSnooze(kit)
end

local SNOOZES = { { 5 * 60, "5 minutes" }, { 30 * 60, "30 minutes" }, { 60 * 60, "1 hour" } }

ns.kit = Core.NewKit({
    addon = addonName,
    key = "ck",
    name = "Camping Kit",
    prefix = "CampingKit",
    color = "e0a040",
    media = MEDIA,
    db = "CampingKitDB",
    charDb = "CampingKitCharDB",
    glowColor = GLOW,
    defaults = {
        point = { "CENTER", "CENTER", -220, -180 },
        weaponGlow = true,    -- glow a stone/oil slot while a weapon it fits has no buff
        poisonGlow = true,    -- same for poisons (separate, for rogues who'd rather not)
        showProfButtons = true, -- the small buttons that open each profession's window
        showBenefits = true,  -- the timer icons under the tent, each can be turned off
        showWellFed = true,
        benefitsGlow = true,  -- glow the Camp Benefits icon while you don't have the buff
        campGlow = true,      -- glow the tent while you're near a campfire without Camp Benefits
        wellFedGlow = true,   -- same for Well Fed
        campClash = true,     -- badge a camp object whose bonus a buff you already have cancels
        hideInCombat = true,  -- camping can't be done in a fight (always: alwaysHideInCombat below)
        campPips = true,      -- closed kit at a camp: a small pip per camp slot
        campRow = true,       -- open kit at a camp: what's there, in a row over the kit
        campAnnounce = true,  -- the chat button that announces the camp
        campShare = true,     -- share camps with other kit users on your layer (CampNet.lua)
        campOthers = true,    -- camps from Happy Camper's channel and map pins in chat (CampOthers.lua)
        campWorldMap = true,  -- tent pins for camps on the world map
        campMinimap = true,   -- ... and on the minimap
    },
    dock = ns.Dock,
    alwaysHideInCombat = true, -- (Kit Core v7: no "Hide in combat" setting; older copies keep it, on by default)
    staysInBox = true, -- ... except in a Kit Dock box (Kit Core v12)
    slots = slots,
    menuOrder = ns.MENU_ORDER,
    divider = {
        y = DIVIDER_Y, width = 260, texture = "divider",
        below = { "fishing", "firstaid", "campfire", "prof1", "prof2" },
        edgeAfter = 1, -- on a screen edge: between the camp objects and your picks
    },
    -- On a screen edge the camp's own column goes between these two (Camp.lua),
    -- and the timers and sleeping bag sit on the tent's rim.
    edgeCols = {
        { "fishing", "firstaid", "campfire", "prof1", "prof2" },
        { "food", "food2", "pick5", "weapon", "weapon2" },
    },
    extraFrames = function(kit) return ns.Camp.Extras(kit) end,
    -- Open in a Kit Dock box: the timers (and sleeping bag) go in a column of
    -- their own after the others, not on the tent's rim (the box is there).
    EdgeExtraCol = function(kit, hypothetical, asOpen)
        local col = {}
        if not kit.parked then return col end
        for _, f in ipairs(dials) do
            if (hypothetical and ((asOpen and kit.db[f.def.showSetting] ~= false) or f.wouldShow))
                or (not hypothetical and f:IsShown()) then
                col[#col + 1] = { frame = f, size = DIAL_EDGE }
            end
        end
        local bag = kit.slots.bag
        if bag and ((hypothetical and ((asOpen and not bag.hidden) or bag.wouldShow)) or (not hypothetical and bag:IsShown() and not bag.closing)) then
            col[#col + 1] = { frame = bag, size = kit.BTN }
        end
        return col
    end,
    -- The timers: under the tent (turned with the layout); shrunk on the
    -- dock, small on the tent's rim a quarter turn either side of the fan.
    -- Then what's at the camp (Camp.lua).
    PlaceExtras = function(kit, angle)
        local half = kit:KitHalfUnits()
        for k, f in ipairs(dials) do
            if angle then
                if f:IsShown() then
                    local a = math.rad(angle + (k == 1 and -90 or 90))
                    kit:PlaceAt(f, (half - 2) * math.cos(a), (half - 2) * math.sin(a))
                end
            else
                kit:PlaceAt(f, kit:Face(f.def.x, f.def.y))
            end
        end
        ns.Camp.Place(kit, angle)
    end,
    slash = { "/ck", "/campingkit" },
    bindingHeader = "CAMPINGKIT",
    helpLines = { "/ck auras - list your buffs with spell IDs", "/ck layer - which layer the kit thinks you're on",
        "/ck object - what the game tells addons about the last object you moused over" },
    minimapArt = MEDIA .. "tent_closed_48",

    AfterBuild = function(kit)
        local db, cdb = kit.db, kit.cdb
        cdb.hideEmpty = nil -- option removed in 0.1.11
        db.campObjectGlow = nil -- camp object glow removed in 1.5.7
        db.popAtCamp = nil  -- auto pop-out at a camp removed in 0.1.26
        if (db.settingsVersion or 0) < 1 then
            db.hideInCombat = true -- make sure it's on after the 0.1.20 fix
            db.settingsVersion = 1
            kit:ApplyCombatHide()
        end
        if db.settingsVersion < 2 then
            db.roundSlots = true -- round slots are now the default (square is the opt-in)
            db.settingsVersion = 2
            kit:ApplyShapes()
        end
        for _, t in ipairs(ns.DIALS) do
            cdb.pinned["dial_" .. t.key] = cdb.pinned["dial_" .. t.key] and true or false
        end
        if not Snoozed(kit) then cdb.snoozeUntil = nil end
        WakeLater(kit)
        MakeDials(kit)
        for _, f in ipairs(dials) do f:SetScale(db.scale) end
        -- The rest countdown sweeps over the tent.
        local cd = CreateFrame("Cooldown", nil, kit.kit, "CooldownFrameTemplate")
        cd:SetPoint("TOPLEFT", 6, -6)
        cd:SetPoint("BOTTOMRIGHT", -6, 6)
        pcall(cd.SetSwipeTexture, cd, MEDIA .. "circle_mask")
        pcall(cd.SetUseCircularEdge, cd, true)
        kit.kit.cooldown = cd
        ApplyProfShapes(kit)
        ns.Camp.Init(kit)
    end,
    OnShapes = ApplyProfShapes,
    KitArt = function(kit)
        local b = kit.kit
        local px = U.ScreenPx(b, b:GetWidth())
        b.icon:SetTexture(MEDIA .. (kit.open and "tent_open_" or "tent_closed_") .. U.ArtSize(px, Core.ART_SIZES), nil, nil, "LINEAR")
        -- Timers (and the rest countdown on the tent).
        if PaintTimers(kit) and (kit.compactAngle or kit.edgeSide) then
            if InCombatLockdown() then kit.pending = true else kit:PlaceSlots() end
        end
        local cd, a = b.cooldown, auras.welcoming
        if cd then
            if a and a.exp and a.dur and a.exp > 0 and a.dur > 0 then
                if cd.lastExp ~= a.exp then
                    cd:SetCooldown(a.exp - a.dur, a.dur)
                    cd.lastExp = a.exp
                end
            else
                cd:Clear()
                cd.lastExp = nil
            end
        end
        -- The tent glows near a fire without Camp Benefits.
        kit:SetGlow(b, TentGlows(kit))
        ns.Camp.Paint(kit)
        CheckAttention(kit)
    end,
    KitTooltip = function(kit)
        if AtCamp() and not auras.benefits then
            GameTooltip:AddLine("There's a fire nearby, get the camping benefit.", GLOW[1], GLOW[2], GLOW[3], true)
        elseif AtCamp() then
            GameTooltip:AddLine("You're at a camp.", GLOW[1], GLOW[2], GLOW[3])
        end
        if Snoozed(kit) then
            GameTooltip:AddLine("Reminder glows snoozed: " .. U.FormatLeft(SnoozeLeft(kit)) .. " left", 0.6, 0.6, 0.6)
        end
    end,
    Menu = function(kit, root)
        if ns.Camp.HasCamp() then
            root:CreateButton("This campfire…", function() ns.Camp.OpenPanel(kit) end)
        end
        -- (no "Hide in combat" here: the kit always hides in combat)
        local snoozed = Snoozed(kit)
        local sub = root:CreateButton(snoozed and ("Reminder glows snoozed (" .. U.FormatLeft(SnoozeLeft(kit)) .. ")")
            or "Snooze reminder glows")
        for _, o in ipairs(SNOOZES) do
            sub:CreateButton(o[2], function() Snooze(kit, o[1]) end)
        end
        if snoozed then
            sub:CreateDivider()
            sub:CreateButton("Turn them back on", function() Snooze(kit, nil) end)
        end
    end,
    -- The tent and pinned slots fade (if that's on) only away from a camp.
    Busy = function() return AtCamp() end,
    -- The timers and the camp's row aren't slots: they fade with the kit here.
    OnFade = function(kit, faded, alpha)
        local a = alpha or (faded and 0.4 or 1)
        for _, f in ipairs(dials) do f:SetAlpha(a) end
        ns.Camp.SetFaded(a)
    end,
    BeforeRefresh = function(kit)
        ScanAuras()
        ResolveProfessions()
        -- Which timers show decides where everything sits on an edge, so
        -- they're sorted out before the slots are placed. So does what's at
        -- the camp.
        PaintTimers(kit)
        ns.Camp.BeforeRefresh(kit)
    end,
    Tick = function(kit)
        for _, f in ipairs(dials) do
            if f:IsShown() then DialText(f) end
        end
        for _, slot in ipairs(ns.SLOTS) do
            local w = slot.pick and kit.slots[slot.key]
            if w and w:IsShown() then PaintWeaponSlot(kit, w) end
        end
        kit:SetGlow(kit.kit, TentGlows(kit))
        ns.Camp.Tick(kit)
        CheckAttention(kit)
    end,
    events = {
        UI_ERROR_MESSAGE = function(kit, ...) ns.Camp.OnError(kit, ...) end,
        UNIT_SPELLCAST_SUCCEEDED = function(kit, ...) ns.Camp.OnCast(kit, ...) end,
        SKILL_LINES_CHANGED = Refresh,
        BAG_UPDATE_COOLDOWN = Refresh,
        PLAYER_EQUIPMENT_CHANGED = Repaint, -- weapon swapped
        UNIT_INVENTORY_CHANGED = function(kit, unit) if unit == "player" then kit:PaintAll() end end, -- weapon buff on/off
    },
    unitEvents = {
        UNIT_AURA = { units = { "player" }, fn = Refresh },
    },

    Settings = function(kit, S)
        local db = kit.db
        local refresh = function() kit:Refresh(false) end
        local paint = function() kit:PaintAll() end
        S.Header("Profession buttons")
        S.Checkbox(db, "showProfButtons", "Show profession buttons",
            "The small buttons under the camp-object row that open each profession's window.", true, refresh)
        S.Header("Timers under the tent")
        S.Checkbox(db, "showBenefits", "Camp Benefits", "Show the Camp Benefits icon and time under the tent.", true, refresh)
        S.Checkbox(db, "benefitsGlow", "Glow when Camp Benefits is missing",
            "The Camp Benefits icon by the tent is greyed out while you don't have the buff; this makes it glow too, as a reminder to camp.",
            true, refresh)
        S.Checkbox(db, "showWellFed", "Well Fed", "Show the Well Fed icon and time under the tent.", true, refresh)
        S.Checkbox(db, "wellFedGlow", "Glow when Well Fed is missing",
            "While you don't have Well Fed, its timer shows by the tent (even unpinned), greyed out; this makes it glow too, as a reminder to eat.",
            true, refresh)
        S.Header("At a camp")
        S.Checkbox(db, "campPips", "Show the camp's slots when the kit is closed",
            "At a camp, small pips under the tent show how many objects the camp takes and which you've seen. Off: the camp only shows with the kit open, or from the tent's right-click menu (This campfire...).",
            true, refresh)
        S.Checkbox(db, "campRow", "Show the camp when the kit is open",
            "At a camp, what's there shows in a row over the kit (in a column on a screen edge). Mouse over the camp's objects in the world to fill it in. Off: use the tent's right-click menu (This campfire...) instead.",
            true, refresh)
        S.Checkbox(db, "campAnnounce", "Show the announce button",
            "The chat bubble by the camp's slots. Click it to post the camp in General chat, with a map pin link for players without Camping Kit.",
            true, refresh)
        S.Header("Camps on the map")
        S.Checkbox(db, "campShare", "Share camps with other Camping Kit users",
            "While you're at a camp, other Camping Kit users on your layer see it on their map, with what's at it, and you see theirs. Sent over a hidden channel of the kit's own; nothing shows in chat. Off: you don't send or see other players' camps.",
            true, function() ns.CampNet.Apply() end)
        S.Checkbox(db, "campOthers", "Show camps from Happy Camper and chat",
            "Adds camps from Happy Camper's camp channel and map pins players post about a camp in chat. Listening only: the kit sends nothing there, and these camps stay on your map. Faded means it can't tell if that camp is on your layer, or it was only posted in chat or roughly placed.",
            true, function() ns.CampOthers.Apply() end)
        S.Checkbox(db, "campWorldMap", "Camps on the world map",
            "A tent pin for each camp on your layer: on a zone's map, the camps in it; on a continent or the world, just the ones in your zone. Mouse over a pin for the campfire, what's at it and how long it burns. Also in the world map's filter menu (the magnifying glass).",
            true, function() ns.CampMap.Refresh() end)
        S.Checkbox(db, "campMinimap", "Camps on the minimap",
            "The same tent pins on the minimap, for camps close by. Also in the minimap's tracking menu.", true, function() ns.CampMap.Refresh() end)
        S.Header("Reminders")
        S.Checkbox(db, "campGlow", "Glow the tent near a campfire",
            "While you have Campfire Nearby but not Camp Benefits, the tent glows: there's a fire close by, and sitting at it gets you the buffs.",
            true, paint)
        S.Checkbox(db, "campClash", "Flag camp objects your buffs would cancel",
            "Some camp objects give a bonus that doesn't stack with a class buff (the Fish Bowl and Blessing of Kings, for one). At a campfire with the camping cooldown up, such an object shows the buff you already have on its corner, and its tooltip says so. You can still place it.",
            true, paint)
        S.Checkbox(db, "weaponGlow", "Glow when a weapon needs a stone or oil",
            "A 'your pick' slot holding a sharpening stone, weightstone or oil glows while a weapon it fits (blades for sharpening stones, maces and staves for weightstones, any for oils) has no buff on it. The time left shows below it.",
            true, refresh)
        S.Checkbox(db, "poisonGlow", "Glow when a weapon needs poison",
            "A 'your pick' slot holding a poison glows while either of your weapons has no buff on it.", true, refresh)
    end,
    PinSettings = function(kit, S)
        for _, t in ipairs(ns.DIALS) do
            S.Checkbox(kit.cdb.pinned, "dial_" .. t.key, "Always show: " .. t.label .. " timer",
                "Keep this timer beside the tent when the kit is closed, even while you have the buff. Unpinned, it only shows while the buff is missing (glowing, if that's turned on). You can also shift-right-click the timer.",
                false, function() kit:Refresh(false) end, "pin_dial_" .. t.key)
        end
    end,

    Slash = function(kit, cmd)
        if cmd == "layer" then
            local layer, cont, guid = ns.CampNet.LayerInfo()
            if layer then
                kit:Print(("Layer %s (continent %s), from %s"):format(layer, tostring(cont), tostring(guid)), true)
            else
                kit:Print("Layer not known yet: target or mouse over an NPC (not a player).", true)
            end
            local n = 0
            for _, f in ipairs(ns.CampNet.fires) do
                n = n + 1
                kit:Print(("  camp: layer %s, tier %d, %d objects, fire at %.0f, %.0f (%s)%s"):format(tostring(f.layer),
                    f.tier or 0, #f.spells, f.wx or 0, f.wy or 0, f.exact and "built here" or f.cooked and "found by cooking range" or f.pinned and "pinned by an announce" or ("estimate, " .. (f.n or 0) .. " samples"),
                    f.mine and " (you're here)" or (f.yours and " (yours)" or (f.from and (", from " .. f.from) or ""))), true)
            end
            for _, f in pairs(ns.CampOthers.camps) do
                n = n + 1
                kit:Print(("  %s: layer %s, tier %d, %d objects, at %.0f, %.0f, from %s%s"):format(f.chat and "chat" or f.source,
                    tostring(f.layer), f.tier or 0, #f.spells, f.wx, f.wy, tostring(f.from), f.noFire ~= nil and " (no fire found)" or ""), true)
            end
            if n == 0 then kit:Print("  No camps known.", true) end
            return true
        end
        if cmd == "object" then
            local o = ns.Camp.lastObject
            if not o then
                kit:Print("Mouse over an object in the world first.", true)
            else
                kit:Print(o.name, true)
                if o.guid then kit:Print("  " .. o.guid, true) end
                for _, t in ipairs(o.lines) do kit:Print("  " .. t, true) end
            end
            return true
        end
        if cmd == "auras" then
            if not (C_UnitAuras and C_UnitAuras.GetAuraDataByIndex) then
                kit:Print("Aura API not available on this client.")
                return true
            end
            for _, filter in ipairs({ "HELPFUL", "HARMFUL" }) do
                for i = 1, 40 do
                    local ok, a = pcall(C_UnitAuras.GetAuraDataByIndex, "player", i, filter)
                    if not ok then kit:Print("Auras are hidden from addons right now.") return true end
                    if not a then break end
                    if U.Sealed(a.name) or U.Sealed(a.spellId) then
                        kit:Print(("  %s #%d: hidden"):format(filter:lower(), i))
                    else
                        kit:Print(("  %s  id=%s  (%s)"):format(tostring(a.name), tostring(a.spellId), filter:lower()))
                    end
                end
            end
            return true
        end
    end,
})
