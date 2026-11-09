-- Happy Camper. Copyright (c) 2026 Torridon. All rights reserved; see LICENSE.
local _, ns = ...
local L = ns.L

-- The Campsite Assistant: a round button on screen with Happy Camper's campfire ("the
-- tent" here), your camping toolbar (camps themselves are on the map). Click
-- the tent to open the kit and its slots fan out from it; click again to pack
-- it away. Right-click it for the Happy Camper window; drag it to move it
-- (unless it's locked in Options). It opens flat, its parts in lines going
-- away from the tent: down, or the way Options says, and toward the middle of
-- the screen when it's dropped against a screen edge. Options can make it
-- round instead (away from an edge). /hc panel or Shift-clicking the minimap
-- button shows or hides it; Options can turn it off, start it hidden or size
-- it. In combat it stays up as it was (its slots are secure buttons: they work,
-- but can't change till it's over). Nothing on it is sent to anyone.
--
-- Its parts (the shape of the Camping Kit addon's, written fresh), nearest
-- the tent first (round: the picks above it, the rest below):
--   two dials, Camp Benefits and Well Fed, each a ring timer, and Sit, near a fire;
--   the picks: food or drink, potions (as many as Options says) and a weapon
--     buff for each weapon you hold (one or two; Supplies.lua), each filled by
--     right-clicking it or dropping an item on it;
--   past a gold divider, the camp-object row: one object per profession you
--     carry, with your biggest campfire kit in the middle;
--   past that, a sleeping bag if you carry one, with its Well-Rested stacks.
-- Closed, the tent shows the dials, and a weapon buff pick that's needed
-- pops out, glowing. The minute's rest at a fire fills the tent's ring.
-- Every slot has a key binding (Bindings.xml).

local Widget = {}
ns.Widget = Widget

local SCALE = 0.92       -- the kit's size on screen at Options' Size 100%
local TENT = 54          -- the tent button

-- The kit's size on screen: SCALE times Options' Size (50% to 150%).
local function KitScale()
    local size = tonumber(ns.db.widgetSize) or 100
    return SCALE * math.min(150, math.max(50, size)) / 100
end
Widget.KitScale = KitScale
local DIAL = 30          -- the Camp Benefits and Well Fed dials
local SIT = 26           -- the Sit button
local SLOT = 34          -- an item slot
local SLOT_GAP = 6
local STEP = SLOT + SLOT_GAP
local MAX_OBJECT_SLOTS = 5 -- Fishing, First Aid, Cooking and two main professions make camp objects
local SNAP = 70          -- this close to a screen edge (UI units), the kit sits against it
-- The open kit, around the tent's middle (x right, y up).
local PICK_RADIUS = 64
local PICK_SPREAD = 40   -- degrees between picks on their arc over the tent, centred on its top
local PICK_ARC = 140     -- the most the arc spans (clear of Sit, beside the dials)
local DIAL_X, DIAL_Y = 22, -52
local SIT_X, SIT_Y = 48, -14
local DIVIDER_Y = -90
local ROW_Y = -113
-- Against an edge: each line of parts this far from the tent, toward the middle.
local EDGE_LINES = { dials = 56, picks = 98, divider = 122, objects = 143, bag = 183 }
local DIAL_STEP = 40     -- dials and Sit along their line

local FIRE_ICON = "Interface\\Icons\\Spell_Fire_Fire"          -- no campfire kit; no camp buffs
local OBJECT_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"  -- no camp object
local PICK_ICONS = { -- empty picks, by kind
    food = "Interface\\Icons\\INV_Misc_Food_15",
    potion = "Interface\\Icons\\INV_Potion_51",
    firstaid = "Interface\\Icons\\INV_Misc_Bandage_15",
    any = "Interface\\Icons\\INV_Misc_QuestionMark",
    weapon = "Interface\\Icons\\INV_Stone_SharpeningStone_01",
}
local WELL_FED_ICON = "Interface\\Icons\\Spell_Misc_Food"
local ROUND_MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"

-- Campfire kits and how many objects their fire holds (item IDs from Forever's
-- data), for when an item's spell isn't loaded yet.
local KIT_SLOTS = { [279974] = 10, [279961] = 5, [279981] = 3 }

-- Bags ----------------------------------------------------------------------------------
-- Camp items in your bags, found by the spell they cast (so on any client
-- language): the biggest campfire kit and a camp object, as item IDs.
-- Rescanned when your bags change.
local bags = { dirty = true }

local function ItemSpell(itemID)
    local getItemSpell = C_Item and C_Item.GetItemSpell or GetItemSpell
    if not getItemSpell then return end
    local _, spellID = getItemSpell(itemID)
    return spellID
end

function Widget:ScanBags()
    bags.dirty, bags.kit, bags.object, bags.kitSlots, bags.objectSpell = false, nil, nil, nil, nil
    bags.objects = {} -- every camp object in your bags: { { item, spell, skillLine, tier }, ... }
    bags.kits = {}    -- [objects its fire holds] = true, for every campfire kit in your bags
    bags.slots = {}   -- the kit's object slots: one object per profession (entries of bags.objects)
    if not (C_Container and C_Container.GetContainerNumSlots) then return end
    local best, seen = 0, {}
    for bag = 0, NUM_BAG_SLOTS or 4 do
        for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
            local itemID = C_Container.GetContainerItemID(bag, slot)
            local spellID = itemID and ItemSpell(itemID)
            local slots = itemID and (spellID and ns.CAMP_SPELLS.fire[spellID] or KIT_SLOTS[itemID])
            if slots then
                bags.kits[slots] = true
                if slots > best then bags.kit, bags.kitSlots, best = itemID, slots, slots end
            elseif spellID and ns.ObjectForSpell(spellID) and not seen[itemID] then
                seen[itemID] = true
                local _, _, skillLine, tier = ns.ObjectByName(ns.ObjectForSpell(spellID))
                bags.objects[#bags.objects + 1] = { item = itemID, spell = spellID, skillLine = skillLine, tier = tier or 1 }
            end
        end
    end
    -- Best tier first (then by item, so the order holds).
    table.sort(bags.objects, function(a, b)
        if a.tier ~= b.tier then return a.tier > b.tier end
        return a.item < b.item
    end)
    -- A slot per profession, in the usual order: the object picked for it
    -- (right-click) while it's still in your bags, else its best. Only for
    -- professions you have (you can't place another's), when the game says.
    -- (campObject: the one pick of versions before the slots, still honoured.)
    local picks, mine = ns.charDB.campObjects or {}, ns.GetMyProfessions()
    local anyKnown = next(mine) ~= nil
    for _, profession in ipairs(ns.PROFESSIONS) do
        local chosen
        if mine[profession.id] or not anyKnown then
            for _, entry in ipairs(bags.objects) do
                if entry.skillLine == profession.id then
                    if entry.item == picks[profession.id] or entry.item == ns.charDB.campObject then
                        chosen = entry
                        break
                    end
                    chosen = chosen or entry
                end
            end
        end
        if chosen and #bags.slots < MAX_OBJECT_SLOTS then bags.slots[#bags.slots + 1] = chosen end
    end
    -- What "your camp object" means (the group's plan, a camp request): the
    -- first slot's, else the best you carry.
    local first = bags.slots[1] or bags.objects[1]
    if first then bags.object, bags.objectSpell = first.item, first.spell end
end

-- Every camp object in your bags ({ { item, spell, skillLine, tier }, ... }).
function Widget:CampObjects()
    if bags.dirty then self:ScanBags() end
    return bags.objects or {}
end

-- Every campfire kit in your bags: [how many objects its fire holds] = true.
function Widget:KitsInBags()
    if bags.dirty then self:ScanBags() end
    return bags.kits or {}
end

-- Picks which of a profession's camp objects its slot holds.
function Widget:ChooseObject(itemID)
    local picks = ns.charDB.campObjects or {}
    ns.charDB.campObjects = picks
    for _, entry in ipairs(self:CampObjects()) do
        -- The old single pick becomes its profession's, then this one goes in.
        if entry.item == ns.charDB.campObject and entry.skillLine and not picks[entry.skillLine] then
            picks[entry.skillLine] = entry.item
        end
    end
    ns.charDB.campObject = nil
    for _, entry in ipairs(self:CampObjects()) do
        if entry.item == itemID and entry.skillLine then picks[entry.skillLine] = itemID end
    end
    bags.dirty = true
    self:Update()
end

-- The kit's object slots: one camp object per profession ({ item, spell, skillLine, tier }).
function Widget:ObjectSlots()
    if bags.dirty then self:ScanBags() end
    return bags.slots or {}
end

-- The best campfire kit and the camp object in your bags (item IDs or nil),
-- how many objects that kit's fire holds, and the spell that places the object.
function Widget:CampItems()
    if bags.dirty then self:ScanBags() end
    return bags.kit, bags.object, bags.kitSlots, bags.objectSpell
end

-- A profession's camp objects in your bags (best tier first).
function Widget:ObjectsOf(skillLine)
    local list = {}
    for _, entry in ipairs(self:CampObjects()) do
        if entry.skillLine == skillLine then list[#list + 1] = entry end
    end
    return list
end

local bagEvents = CreateFrame("Frame")
bagEvents:RegisterEvent("BAG_UPDATE_DELAYED")
bagEvents:SetScript("OnEvent", function() bags.dirty = true end)

-- Helpers -------------------------------------------------------------------------------

local function ItemName(itemID)
    return itemID and C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(itemID)
end

-- An item's icon, if the game has it loaded.
local function ItemIcon(itemID)
    local get = C_Item and C_Item.GetItemIconByID or GetItemIcon
    return itemID and get and get(itemID)
end

-- Whether you're at a fire: near one, or resting at one.
local function NearFire()
    return ns.state.nearCamp or ns.state.restAuraInstance ~= nil
end

-- Seconds until your camp object can be placed again, or nil.
local function ObjectCooldown()
    local readyAt = ns.charDB.objectReadyAt
    local left = readyAt and readyAt - GetServerTime()
    return left and left > 0 and left or nil
end

-- A steady highlight on a frame that needs you: a reminder (Glow(frame, on)).
-- A dial's ring turns bright orange; an item slot gets the orange border the
-- minimap button has. It doesn't pulse.
local function Glow(frame, on)
    if not frame.glow then
        if not on then return end
        frame.glow = (frame.top or frame):CreateTexture(nil, "OVERLAY", nil, 7)
        frame.glow:SetBlendMode("ADD")
        frame.glow:SetPoint("CENTER", frame, "CENTER")
        if frame.round then
            -- The dial's own ring again, added over it.
            frame.glow:SetTexture(ns.Style.RING)
            frame.glow:SetSize(frame.ringSize, frame.ringSize)
            frame.glow:SetVertexColor(1, 0.55, 0.1)
        else
            frame.glow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
            frame.glow:SetSize(SLOT * 62 / 36, SLOT * 62 / 36) -- the art is a 36 button's border in 62
            frame.glow:SetVertexColor(1, 0.6, 0.15)
        end
    end
    frame.glow:SetShown(on)
end

-- A round picture in Happy Camper's bronze ring (Style.RING): icon cut round,
-- the ring round its edge. timer: the ring can be a circular timer
-- (frame.cooldown, no numbers; SetRingTimer): a bright arc over the ring,
-- sweeping round it, the picture left clear.
local function RoundArt(frame, size, icon, timer)
    frame:SetSize(size, size)
    frame.round, frame.size = true, size
    frame.icon = frame:CreateTexture(nil, "ARTWORK")
    frame.icon:SetAllPoints()
    frame.icon:SetTexCoord(0.1, 0.9, 0.1, 0.9)
    frame.icon:SetTexture(icon)
    local mask = frame.CreateMaskTexture and frame:CreateMaskTexture()
    if mask then
        mask:SetAllPoints(frame.icon)
        if ns.Style:HasAtlas("talents-node-circle-mask") then
            mask:SetAtlas("talents-node-circle-mask")
        else
            mask:SetTexture(ROUND_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        end
        frame.icon:AddMaskTexture(mask)
    end
    -- The picture fills the ring's hole (Style.RING_HOLE of its size).
    local ring = size / ns.Style.RING_HOLE
    frame.ringSize = ring
    frame.ring = frame:CreateTexture(nil, "OVERLAY")
    frame.ring:SetPoint("CENTER")
    frame.ring:SetTexture(ns.Style.RING)
    frame.ring:SetSize(ring, ring)
    if timer then
        -- The sweep drawn with the ring's own picture, so it covers the ring
        -- and nothing else.
        local cooldown = CreateFrame("Cooldown", nil, frame, "CooldownFrameTemplate")
        cooldown:ClearAllPoints()
        cooldown:SetPoint("CENTER")
        cooldown:SetSize(ring, ring)
        pcall(cooldown.SetSwipeTexture, cooldown, ns.Style.RING)
        pcall(cooldown.SetDrawEdge, cooldown, false)
        pcall(cooldown.SetHideCountdownNumbers, cooldown, true)
        pcall(cooldown.SetDrawBling, cooldown, false)
        frame.cooldown = cooldown
        -- A reminder's highlight sits above the arc.
        frame.top = CreateFrame("Frame", nil, frame)
        frame.top:SetAllPoints()
        frame.top:SetFrameLevel((cooldown:GetFrameLevel() or frame:GetFrameLevel() or 0) + 1)
    end
end

-- An item slot's look: the bag slot behind it, the action button's frame
-- around it, a cooldown swipe and a count (bottom right).
local function SlotArt(button, icon)
    button:SetSize(SLOT, SLOT)
    button.bg = button:CreateTexture(nil, "BACKGROUND")
    button.bg:SetAllPoints()
    button.bg:SetTexture("Interface\\PaperDoll\\UI-Backpack-EmptySlot")
    button.icon = button:CreateTexture(nil, "ARTWORK")
    button.icon:SetAllPoints()
    button.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    button.icon:SetTexture(icon)
    button.frame = button:CreateTexture(nil, "OVERLAY")
    button.frame:SetTexture("Interface\\Buttons\\UI-Quickslot2")
    button.frame:SetPoint("CENTER")
    button.frame:SetSize(SLOT * 64 / 36, SLOT * 64 / 36) -- the art is a 36 button in 64
    button:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    button:SetPushedTexture("Interface\\Buttons\\UI-Quickslot-Depress")
    button.cooldown = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
    button.cooldown:SetAllPoints()
    button.count = button:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    button.count:SetPoint("BOTTOMRIGHT", -2, 2)
end

-- A secure item slot that uses an item on a left-click once SetItemButton
-- says it's ready (a key binding clicks it too). Made and changed out of
-- combat only. sits: food and drink, which sit you down to eat anyway; camp
-- items are placed standing.
local function ItemButton(parent, name, icon, onTooltip, sits)
    local button = CreateFrame("Button", name, parent, "SecureActionButtonTemplate")
    SlotArt(button, icon)
    button:RegisterForClicks("AnyUp", "AnyDown")
    button:SetMotionScriptsWhileDisabled(true)
    -- Items can't be used sitting down: stand up first (an emote) on the
    -- press down, and use the item on the press up, a moment later (not on
    -- the press down, as the game's settings may say). Only when a left-click
    -- will use it.
    button:SetAttribute("useOnKeyDown", false)
    if not sits then
        button:SetScript("PreClick", function(self, mouseButton, down)
            if mouseButton == "LeftButton" and down and self.ready then DoEmote("STAND") end
        end)
    end
    button:Hide()
    ns.Style:CustomTooltip(button, "ANCHOR_TOP", onTooltip)
    return button
end

-- Points an item slot at an item (nil: empty, greyed out). A weapon pick
-- uses its stone, oil or poison through a macro that also opens your
-- character window, so the weapon's right there to click.
local function SetItemButton(button, item, ready)
    if button.item ~= item then
        button.item = item
        button:SetAttribute("item", item and ("item:" .. item) or nil)
        if button.weapon then button:SetAttribute("macrotext", item and ("/use item:" .. item) or nil) end
    end
    button.ready = item ~= nil and ready
    -- Not ready (nothing to use, or on cooldown): a left-click uses nothing.
    -- The button stays enabled, so a right-click still reaches it (its menu).
    local action = button.ready and (button.weapon and "macro" or "item") or nil
    if button.action ~= action then
        button.action = action
        button:SetAttribute("type1", action)
    end
end

-- The cooldown swipe on an item's icon (none when it's ready).
local function ShowCooldown(button, item)
    local get = C_Container and C_Container.GetItemCooldown
    local start, duration = 0, 0
    if item and get then start, duration = get(item) end
    if type(start) == "number" and type(duration) == "number" and duration > 1.5 and not ns.IsSecret(start) then
        button.cooldown:SetCooldown(start, duration)
    else
        button.cooldown:SetCooldown(0, 0)
    end
end

-- Menus ---------------------------------------------------------------------------------

-- Which of a profession's camp objects its slot places, when you carry more
-- than one: a menu (or, without the game's menus, the next one).
function Widget:ObjectMenu(owner)
    local objects = self:ObjectsOf(owner.skillLine)
    if #objects < 2 then return end
    local opened = ns.Menu:Context(owner, function(_, root)
        root:CreateTitle(L["Camp object"])
        for _, entry in ipairs(objects) do
            root:CreateRadio(ItemName(entry.item) or L["campsite object"],
                function(item) return item == owner.item end,
                function(item) Widget:ChooseObject(item) end, entry.item)
        end
    end)
    if opened then return end
    for i, entry in ipairs(objects) do
        if entry.item == owner.item then return self:ChooseObject(objects[i % #objects + 1].item) end
    end
end

-- What a pick slot holds: a menu of what's in your bags for it (food and
-- drink, potions and elixirs, bandages, weapon buffs, or anything with a use;
-- or, without the game's menus, the next one). Not in combat.
function Widget:PickMenu(owner)
    if ns.InCombat() then return end
    local Supplies, i = ns.Supplies, owner.pick
    local kind = Supplies:KindOf(i)
    local text = ({
        food = { L["Food or drink"], L["No food or drink in your bags."] },
        potion = { L["Potion or elixir"], L["No potions or elixirs in your bags."] },
        firstaid = { L["First aid"], L["No bandages in your bags."] },
        any = { L["Any item"], L["Nothing usable in your bags."] },
        weapon = { L["Weapon buff"], L["No stones, oils or poisons in your bags."] },
    })[kind]
    local items = Supplies:FoodInBags(kind)
    local opened = ns.Menu:Context(owner, function(_, root)
        root:CreateTitle(text[1])
        if #items == 0 then root:CreateTitle(text[2]) end
        for _, entry in ipairs(items) do
            root:CreateRadio(format(L["%s (%d)"], ItemName(entry.item) or "?", entry.count),
                function(item) return Supplies:Pick(i) == item end,
                function(item) Supplies:SetPick(i, item) end, entry.item)
        end
        if Supplies:Pick(i) then root:CreateButton(L["Empty this slot"], function() Supplies:SetPick(i, nil) end) end
    end)
    if opened then return end
    if #items == 0 then return end
    local next = items[1].item
    for k, entry in ipairs(items) do
        if entry.item == Supplies:Pick(i) then next = items[k % #items + 1].item end
    end
    Supplies:SetPick(i, next)
end

-- An item dropped on a pick slot goes in it, if it's the slot's kind.
function Widget:DropOnPick(owner)
    local kind, itemID = GetCursorInfo()
    if kind == "item" and ns.Supplies:SetPick(owner.pick, itemID) then ClearCursor() end
end

-- The kit ---------------------------------------------------------------------------------

-- Puts the kit at its saved place, else its first one (the right of the screen).
local function PlaceAtSaved(f)
    local p = ns.db.widgetPoint
    f:ClearAllPoints()
    if p and p[3] and p[4] then
        f:SetPoint(p[1], UIParent, p[2], p[3], p[4])
    else
        f:SetPoint("RIGHT", UIParent, "RIGHT", -120, 120)
    end
end

-- Keeps the whole open kit on screen, not only the tent: the game clamps the
-- holder (the tent's ring), so its clamp is reached out to the parts' places
-- (Positions' at and divider). When that changes, the kit is placed again so
-- it takes hold (near a screen edge it moves in just enough).
local function ClampToKit(f, at, divider, across)
    local half = f.half
    local minX, maxX, minY, maxY = -half, half, -half, half
    local function Cover(x, y, rx, ry)
        minX, maxX = math.min(minX, x - rx), math.max(maxX, x + rx)
        minY, maxY = math.min(minY, y - ry), math.max(maxY, y + ry)
    end
    for frame, spot in pairs(at) do
        local r = (frame.ringSize or SLOT) / 2
        Cover(spot[1], spot[2], r, r)
    end
    if divider then
        if across then Cover(divider[1], divider[2], 1, divider[3] / 2) else Cover(divider[1], divider[2], divider[3] / 2, 1) end
    end
    local l, r = math.floor(minX + half), math.ceil(maxX - half)
    local t, b = math.ceil(maxY - half), math.floor(minY + half)
    local key = l .. "," .. r .. "," .. t .. "," .. b
    if f.clampKey == key then return end
    f.clampKey = key
    f:SetClampRectInsets(l, r, t, b)
    PlaceAtSaved(f)
end

-- Dragging the tent moves the kit (unless it's locked); let go near a screen
-- edge, it sits against it. While it's dragged only the tent is kept on
-- screen, so it can reach an edge; its parts are kept on once it's let go.
local function StartDrag(f)
    if ns.db.widgetLocked or ns.InCombat() then return end
    f.dragging = true
    f.clampKey = nil
    f:SetClampRectInsets(0, 0, 0, 0)
    f:StartMoving()
end

local function StopDrag(f)
    if not f.dragging then return end
    f.dragging = nil
    f:StopMovingOrSizing()
    Widget:Dock()
    Widget:Update()
end

function Widget:Create()
    -- The kit's holder (secure, holding secure slots), with the tent at its
    -- middle and everything else around it. It's the size of the tent's ring,
    -- so the ring sits on screen against an edge.
    local f = CreateFrame("Frame", "HappyCamperWidget", UIParent, "SecureHandlerStateTemplate")
    local holder = TENT / ns.Style.RING_HOLE
    local scale = KitScale()
    f:SetSize(holder, holder)
    f.half = holder / 2
    f:SetScale(scale)
    f.scaled = scale
    -- Above the action bars and other game UI (MEDIUM), below the Happy Camper
    -- window (DIALOG).
    f:SetFrameStrata("HIGH")
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    -- Where it was left (a place saved at another size is moved to this one,
    -- so it stays where it was on screen), else the right of the screen.
    local p, saved = ns.db.widgetPoint, ns.db.widgetPointScale
    if p and p[3] and p[4] then
        local x, y = p[3], p[4]
        if saved and saved ~= scale then x, y = x * saved / scale, y * saved / scale end
        ns.db.widgetPoint, ns.db.widgetPointScale = { p[1], p[2], x, y }, scale
    end
    PlaceAtSaved(f)
    f:Hide()

    -- The tent: click to open or close the kit, right-click for the Happy
    -- Camper window, drag to move it. The rest's minute fills its ring.
    local tent = CreateFrame("Button", nil, f)
    -- Happy Camper's own picture, the one made for the window's round
    -- portrait (all of it: it's already framed for a circle).
    RoundArt(tent, TENT, ns.Style.PORTRAIT, true)
    tent.icon:SetTexCoord(0, 1, 0, 1)
    -- The rest fills its ring (the dials' empty).
    pcall(tent.cooldown.SetReverse, tent.cooldown, true)
    tent:SetPoint("CENTER")
    tent:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    tent:RegisterForDrag("LeftButton")
    local highlight = tent:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetTexture(ROUND_MASK)
    highlight:SetAllPoints(tent.icon)
    highlight:SetBlendMode("ADD")
    highlight:SetAlpha(0.25)
    tent:SetScript("OnDragStart", function() StartDrag(f) end)
    tent:SetScript("OnDragStop", function() StopDrag(f) end)
    tent:SetScript("OnClick", function(_, mouseButton)
        if mouseButton == "RightButton" then
            ns.Hub:Toggle()
        else
            Widget:ToggleOpen()
        end
    end)
    -- No tooltip on it (the guide says what it does).
    f.tent = tent

    -- The dials: Camp Benefits and Well Fed, each its icon (greyed when you
    -- don't have it) in a ring that's its timer: lit for the time left, it
    -- empties round like a clock (the tooltip has the time).
    local function Dial(icon, onTooltip)
        local dial = CreateFrame("Button", nil, f)
        RoundArt(dial, DIAL, icon, true)
        ns.Style:CustomTooltip(dial, "ANCHOR_TOP", onTooltip)
        dial:SetScript("OnClick", function() ns.Hub:Open("camp") end)
        return dial
    end
    f.benefits = Dial(FIRE_ICON, function(tooltip)
        local buff = ns.state.buffs[1]
        if buff and buff.auraInstanceID and ns.SetBuffTooltip(buff.auraInstanceID) then return end
        tooltip:SetText(L["No camp buffs"])
        tooltip:AddLine(L["Rest at a camp for a minute to get its buffs."], 1, 1, 1, true)
    end)
    f.wellFed = Dial(WELL_FED_ICON, function(tooltip)
        local fed = ns.Supplies:WellFed()
        if fed and fed.auraInstanceID and ns.SetBuffTooltip(fed.auraInstanceID) then return end
        tooltip:SetText(L["Well Fed"])
        if fed then return end
        tooltip:AddLine(L["You're not Well Fed."], 1, 0.5, 0.4, true)
        if NearFire() then tooltip:AddLine(L["Eat something before your rest ends."], 1, 1, 1, true) end
    end)

    -- Sit, near a fire: the Camp Chair's picture.
    -- A plain round button in the bronze ring: gold at the top shading to
    -- brown at the bottom (flat gold-brown where the game can't shade it).
    f.sit = CreateFrame("Button", nil, f)
    RoundArt(f.sit, SIT, nil)
    f.sit.icon:SetColorTexture(0.62, 0.43, 0.17)
    if CreateColor and f.sit.icon.SetGradient then
        f.sit.icon:SetColorTexture(1, 1, 1)
        if not pcall(f.sit.icon.SetGradient, f.sit.icon, "VERTICAL", CreateColor(0.42, 0.26, 0.09, 1), CreateColor(0.80, 0.60, 0.26, 1)) then
            f.sit.icon:SetColorTexture(0.62, 0.43, 0.17)
        end
    end
    local sitLight = f.sit:CreateTexture(nil, "HIGHLIGHT")
    sitLight:SetTexture(ROUND_MASK)
    sitLight:SetAllPoints(f.sit.icon)
    sitLight:SetBlendMode("ADD")
    sitLight:SetAlpha(0.25)
    f.sit:SetScript("OnClick", function() DoEmote("SIT") end)
    ns.Style:Tooltip(f.sit, L["Sit"], L["Sit down. At a camp, a minute's rest gets you its buffs."])
    f.sit:Hide()

    -- The gold divider above the camp-object row.
    f.divider = f:CreateTexture(nil, "ARTWORK")
    f.divider:SetColorTexture(1, 0.82, 0.4, 0.6)
    f.divider:Hide()

    -- The item slots (secure buttons).
    f.place = ItemButton(f, "HappyCamperPlaceCampfire", FIRE_ICON, function(tooltip, self)
        tooltip:SetText(L["Place campfire"])
        if self.item then
            tooltip:AddLine(format(L["Uses your %s."], ItemName(self.item) or L["campfire kit"]), 1, 1, 1, true)
        else
            tooltip:AddLine(L["You have no campfire kit. Cooking makes them."], 1, 0.5, 0.4, true)
        end
    end)
    local function ObjectTooltip(tooltip, self)
        tooltip:SetText(self.objectName and format(L["Place %s"], self.objectName) or L["Place camp object"])
        local left = ObjectCooldown()
        if not self.item then
            tooltip:AddLine(L["You have no camp object. Professions make them: a Mana Well, a Loom, a Sharpening Wheel..."], 1, 0.5, 0.4, true)
        elseif left then
            tooltip:AddLine(format(L["You can place it again in %s."], ns.FormatTime(left)), 1, 0.5, 0.4, true)
        elseif not NearFire() then
            tooltip:AddLine(L["Stand by a campfire to place it."], 1, 0.5, 0.4, true)
        else
            tooltip:AddLine(L["Adds it to the camp you're at, for everyone there."], 1, 1, 1, true)
        end
        if self.item then ns.Tooltips:AddPlacingLines(tooltip, ItemSpell(self.item)) end
        if #Widget:ObjectsOf(self.skillLine) > 1 then
            ns.Style:AddHint(tooltip, L["Right-click to pick another camp object."], true)
        end
    end
    f.objectSlots = {}
    for i = 1, MAX_OBJECT_SLOTS do
        local button = ItemButton(f, "HappyCamperPlaceObject" .. i, OBJECT_ICON, ObjectTooltip)
        -- With more than one of its profession's objects in your bags, a
        -- right-click picks which one it places (a left-click places it).
        button:SetScript("PostClick", function(self, mouseButton, down)
            if mouseButton == "RightButton" and not down then Widget:ObjectMenu(self) end
        end)
        f.objectSlots[i] = button
    end
    f.bag = ItemButton(f, "HappyCamperSleepingBag", 134400, function(tooltip, self)
        if self.item then tooltip:SetItemByID(self.item) else tooltip:SetText(L["Sleeping bag"]) end
        local rested = ns.Supplies:WellRested()
        if rested and rested.count then
            local left = rested.expirationTime and rested.expirationTime > 0 and rested.expirationTime - GetTime()
            tooltip:AddLine(left and left > 0 and format(L["Well-Rested: %d, %s left"], rested.count, ns.FormatTime(left))
                or format(L["Well-Rested: %d"], rested.count), 0.4, 1, 0.4, true)
        end
    end)
    -- The picks: food or drink, a potion or elixir, the extra slots Options
    -- adds (each a potion, first aid or any-item slot), and a weapon buff for
    -- each weapon you hold. f.picks by their number (Supplies.PICK_KINDS),
    -- f.pickOrder as they sit on the kit. A button's kind is what it takes now
    -- (Supplies:KindOf, set as the slots fill); its slot is what it is.
    local PICK_TEXT = {
        food = { L["Food or drink"], L["Pick something to eat or drink at camp: right-click, or drop it here."],
            L["Right-click to pick other food or drink."] },
        potion = { L["Potion or elixir"], L["Pick a potion, elixir or flask: right-click, or drop it here."],
            L["Right-click to pick another potion or elixir."] },
        firstaid = { L["First aid"], L["Pick a bandage: right-click, or drop it here."],
            L["Right-click to pick another bandage."] },
        any = { L["Any item"], L["Pick anything you'd like to use: right-click, or drop it here."],
            L["Right-click to pick another item."] },
        weapon = { L["Weapon buff"], L["Pick a sharpening stone, weightstone, oil or poison: right-click, or drop it here."],
            L["Right-click to pick another weapon buff."] },
    }
    local function PickTooltip(tooltip, self)
        local text = PICK_TEXT[self.kind]
        if self.item then
            tooltip:SetItemByID(self.item)
            if self.weapon and ns.Supplies:WeaponNeeds(self.item) then
                tooltip:AddLine(L["Your weapon has none on it."], 1, 0.5, 0.4, true)
            end
            if self.weapon then tooltip:AddLine(L["Click to use it, then click your weapon in the character window."], 1, 1, 1, true) end
            ns.Style:AddHint(tooltip, text[3], true)
        else
            tooltip:SetText(text[1])
            tooltip:AddLine(text[2], 1, 1, 1, true)
        end
    end
    f.picks, f.pickOrder = {}, {}
    local numbers = {}
    local NAMES = { food = "HappyCamperFood", potion = "HappyCamperPotion", weapon = "HappyCamperWeapon", extra = "HappyCamperExtra" }
    for i, slot in ipairs(ns.Supplies.PICK_KINDS) do
        numbers[slot] = (numbers[slot] or 0) + 1
        local number = numbers[slot]
        local weapon = slot == "weapon"
        local kind = ns.Supplies:KindOf(i)
        local button = ItemButton(f, NAMES[slot] .. number, PICK_ICONS[kind], PickTooltip, true)
        button.pick, button.slot, button.kind, button.number, button.weapon = i, slot, kind, number, weapon
        button.hand = weapon and number or nil -- weapon picks: 1 or 2, shown for that many weapons
        if weapon then
            -- Open the character window too (unless it's open), so the weapon
            -- is right there to click.
            button:SetScript("PreClick", function(self, mouseButton)
                if mouseButton ~= "LeftButton" or not self.item or ns.InCombat() then return end
                local open = CharacterFrame and CharacterFrame:IsShown()
                self:SetAttribute("macrotext", "/use item:" .. self.item .. (open and "" or "\n/click CharacterMicroButton"))
            end)
        end
        button:SetScript("PostClick", function(self, mouseButton, down)
            if mouseButton == "RightButton" and not down then Widget:PickMenu(self) end
        end)
        button:SetScript("OnReceiveDrag", function(self) Widget:DropOnPick(self) end)
        f.picks[i] = button
    end
    for _, slot in ipairs({ "food", "potion", "extra", "weapon" }) do
        for _, button in ipairs(f.picks) do
            if button.slot == slot then f.pickOrder[#f.pickOrder + 1] = button end
        end
    end
    f.slots = { f.place }
    for _, button in ipairs(f.objectSlots) do f.slots[#f.slots + 1] = button end
    f.slots[#f.slots + 1] = f.bag
    for _, button in ipairs(f.pickOrder) do f.slots[#f.slots + 1] = button end

    self.frame = f
end

-- Open and closed ------------------------------------------------------------------------

function Widget:IsOpen()
    return ns.db.widgetOpen == true or self.guideShow == true
end

-- Opens or packs away the kit (out of combat: it's hidden then anyway).
function Widget:ToggleOpen()
    if ns.InCombat() then return end
    ns.db.widgetOpen = not ns.db.widgetOpen
    PlaySound(SOUNDKIT.IG_CHARACTER_INFO_TAB)
    self:Update()
end

-- For the key binding (Bindings.xml).
function HappyCamper_ToggleKit() Widget:ToggleOpen() end

-- Docked against a screen edge ("LEFT", "RIGHT", "TOP" or "BOTTOM"), or not:
-- where the kit was let go. It's saved with its place.
function Widget:Dock()
    local f = self.frame
    local x, y = f:GetCenter()
    if not x then return end
    local s = f:GetScale() or KitScale()
    x, y = x * s, y * s -- in UIParent's units
    local w, h = UIParent:GetWidth(), UIParent:GetHeight()
    local edge, best
    if type(w) == "number" and type(h) == "number" and w > 0 and h > 0 then
        for name, distance in pairs({ LEFT = x, RIGHT = w - x, TOP = h - y, BOTTOM = y }) do
            if distance < SNAP and (not best or distance < best) then edge, best = name, distance end
        end
    end
    local point
    if edge == "LEFT" or edge == "RIGHT" then
        point = { edge, edge, 0, (y - h / 2) / s }
    elseif edge == "TOP" or edge == "BOTTOM" then
        point = { edge, edge, (x - w / 2) / s, 0 }
    else
        point = { "CENTER", "BOTTOMLEFT", x / s, y / s }
    end
    f:ClearAllPoints()
    f:SetPoint(point[1], UIParent, point[2], point[3], point[4])
    ns.db.widgetPoint, ns.db.widgetPointScale, ns.db.widgetDock = point, s, edge
end

-- Layout ---------------------------------------------------------------------------------

-- Which way the kit opens: from an edge ("LEFT", "RIGHT", "TOP" or "BOTTOM"),
-- its lines going away from it, or nil for the round layout. Against a screen
-- edge, away from it; elsewhere flat, the way Options says (Down: as if from
-- the top edge), unless Options says Circular.
local DIRECTION_FROM = { DOWN = "TOP", UP = "BOTTOM", RIGHT = "LEFT", LEFT = "RIGHT" }
local function OpensFrom()
    if ns.db.widgetDock then return ns.db.widgetDock end
    if ns.db.widgetShape == "round" then return nil end
    return DIRECTION_FROM[ns.db.widgetDirection] or "TOP"
end

-- Where each part goes, from the tent's middle ({ [frame] = { x, y } }), and the
-- divider's middle and length (nil with no camp-object row). Round (dock nil),
-- the picks arc over the tent, the dials and Sit sit under it, then the
-- divider, the camp-object row and the sleeping bag. Flat, each of those is a
-- line of its own, further and further from the edge it opens from (dock). The
-- picks have their places from parts.pickOrder (all those the open kit shows),
-- so one popped out of the closed kit is where it sits when it's open.
local function Positions(dock, parts)
    local at = {}
    local divider
    if not dock then
        -- Many picks: closer together, on a wider arc so they don't touch.
        local n = #parts.pickOrder
        local spread = n > 1 and math.min(PICK_SPREAD, PICK_ARC / (n - 1)) or PICK_SPREAD
        local radius = math.max(PICK_RADIUS, (STEP / 2) / math.sin(math.rad(spread / 2)))
        for i, button in ipairs(parts.pickOrder) do
            local angle = math.rad(90 + ((n + 1) / 2 - i) * spread)
            at[button] = { radius * math.cos(angle), radius * math.sin(angle) }
        end
        if parts.dials[1] then at[parts.dials[1]] = { -DIAL_X, DIAL_Y } end
        if parts.dials[2] then at[parts.dials[2]] = { DIAL_X, DIAL_Y } end
        if parts.sit then at[parts.sit] = { SIT_X, SIT_Y } end
        local n = #parts.row
        for i, button in ipairs(parts.row) do at[button] = { (i - (n + 1) / 2) * STEP, ROW_Y } end
        if n > 0 then divider = { 0, DIVIDER_Y, math.max(n * STEP, 3 * STEP) } end
        if parts.bag then at[parts.bag] = { 0, ROW_Y - STEP } end
        return at, divider, false
    end
    -- Away from the edge (toward the middle of the screen, when docked), and across.
    local dx, dy = 0, 0
    if dock == "LEFT" then dx = 1 elseif dock == "RIGHT" then dx = -1 elseif dock == "TOP" then dy = -1 else dy = 1 end
    local across = dx ~= 0 -- a line runs up and down (against a side edge) or left to right
    local function Line(frames, distance, step)
        local n = #frames
        for i, frame in ipairs(frames) do
            local offset = ((n + 1) / 2 - i) * step
            at[frame] = across and { dx * distance, offset } or { -offset, dy * distance }
        end
        return n * step
    end
    local dialLine = {}
    for _, dial in ipairs(parts.dials) do dialLine[#dialLine + 1] = dial end
    if parts.sit then dialLine[#dialLine + 1] = parts.sit end
    Line(dialLine, EDGE_LINES.dials, DIAL_STEP)
    local picks = Line(parts.pickOrder, EDGE_LINES.picks, STEP)
    local row = Line(parts.row, EDGE_LINES.objects, STEP)
    if parts.bag then Line({ parts.bag }, EDGE_LINES.bag, STEP) end
    if #parts.row > 0 then
        local length = math.max(picks, row)
        divider = across and { dx * EDGE_LINES.divider, 0, length } or { 0, dy * EDGE_LINES.divider, length }
    end
    return at, divider, across
end

-- Refresh --------------------------------------------------------------------------------

-- A round frame's ring as a timer for an aura (nil: none). While it runs, the
-- ring dims to a dark track and a bright gold arc sweeps round it: burnt
-- orange once you'd be warned it's ending (warn). With none, the ring is
-- plain bronze. Set only when it changes.
local ARC, ARC_WARN = { 1, 0.9, 0.55, 1 }, { 1, 0.45, 0.1, 1 }
local TRACK = 0.3 -- the dimmed ring's brightness
local function SetRingTimer(frame, aura, warn)
    local exp, duration = aura and aura.expirationTime, aura and aura.duration
    local running = exp and duration and not ns.IsSecret(exp) and not ns.IsSecret(duration)
        and duration > 0 and exp > GetTime() or false
    if running then
        if frame.timerUntil ~= exp or frame.timerFor ~= duration then
            frame.timerUntil, frame.timerFor = exp, duration
            frame.cooldown:SetCooldown(exp - duration, duration)
        end
        warn = warn and exp - GetTime() <= ns.db.warnSeconds or false
    else
        if frame.timerUntil then
            frame.timerUntil, frame.timerFor = nil, nil
            frame.cooldown:SetCooldown(0, 0)
        end
        warn = false
    end
    if frame.timing ~= running then
        frame.timing = running
        local shade = running and TRACK or 1
        frame.ring:SetVertexColor(shade, shade, shade)
    end
    if frame.warned ~= warn then
        frame.warned = warn
        local c = warn and ARC_WARN or ARC
        frame.cooldown:SetSwipeColor(c[1], c[2], c[3], c[4])
    end
end

-- The Camp Benefits dial: its icon and its ring's timer (burnt orange once
-- you'd be warned); greyed with none, glowing near a fire you haven't rested at.
local function RefreshBenefits(f)
    local buff = ns.state.buffs[1]
    local dial = f.benefits
    dial.icon:SetTexture(buff and buff.icon or FIRE_ICON)
    dial.icon:SetDesaturated(buff == nil)
    SetRingTimer(dial, buff, true)
    Glow(dial, (buff == nil and ns.state.nearCamp and ns.state.restAuraInstance == nil) and true or false)
end

-- The Well Fed dial, and the reminder: at a fire and not Well Fed, it and your
-- food (not drink) picks glow.
local function RefreshWellFed(f)
    local dial = f.wellFed
    local fed = ns.Supplies:WellFed()
    dial.icon:SetTexture(fed and fed.icon or WELL_FED_ICON)
    dial.icon:SetDesaturated(not fed)
    SetRingTimer(dial, fed, false)
    local nag = not fed and ns.db.widgetWellFed and ns.db.widgetEatReminder and NearFire()
    Glow(dial, nag and true or false)
    return nag
end

-- The minute's rest at a fire, filling the tent's ring.
local function RefreshRest(f)
    local id = ns.state.restAuraInstance
    local aura = id and ns.AuraByInstance and ns.AuraByInstance("player", id)
    SetRingTimer(f.tent, aura, false)
end

-- Points every item slot at what it holds (whether it shows or not: a key
-- binding can use it): { [button] = shown when open }.
function Widget:FillSlots(f)
    if bags.dirty then self:ScanBags() end
    local Supplies = ns.Supplies
    local function Fill(button, item, ready, empty, count, stacks)
        SetItemButton(button, item, ready)
        button.icon:SetTexture(item and ItemIcon(item) or empty)
        button.icon:SetDesaturated(not button.ready)
        -- An empty slot is a faint picture of what goes in it.
        button.icon:SetAlpha(item and 1 or 0.35)
        button.count:SetText(count and (stacks or count ~= 1) and tostring(count) or "")
        ShowCooldown(button, item)
    end
    Fill(f.place, bags.kit, bags.kit ~= nil, FIRE_ICON)
    -- Camp objects are placed at a fire, once an hour (all of them).
    local placeable = NearFire() and not ObjectCooldown()
    for i, button in ipairs(f.objectSlots) do
        local entry = bags.slots[i]
        button.skillLine, button.objectName = entry and entry.skillLine, entry and ItemName(entry.item)
        Fill(button, entry and entry.item, placeable, OBJECT_ICON)
    end
    local bag = Supplies:SleepingBag()
    local rested = bag and Supplies:WellRested()
    Fill(f.bag, bag, true, 134400, rested and rested.count, true)
    for i, button in ipairs(f.picks) do
        button.kind = Supplies:KindOf(i)
        local item = Supplies:Pick(i)
        local have = item and Supplies:Count(item) or 0
        Fill(button, item, have > 0, PICK_ICONS[button.kind], item and have)
    end
end

function Widget:Update()
    -- Starts hidden this session if Options says so.
    if self.hidden == nil then self.hidden = ns.db.widgetStartHidden end
    local want = (ns.db.widget and not self.hidden) or self.guideShow == true
    if not self.frame then
        -- Its slots are secure buttons, which can't be set up in combat: it's
        -- made once that's over (the next update, within a second).
        if not want or ns.InCombat() then return end
        self:Create()
    end
    local f = self.frame
    -- In combat its secure parts can't change (shown or hidden, moved, sized,
    -- or what a slot uses): it stays as it was, its slots still working, and
    -- only what's drawn on it keeps up. It catches up once combat's over.
    if ns.InCombat() then
        if f.shownState then self:RefreshInCombat(f) end
        return
    end
    self:ApplySize()
    self:ApplyShown(want)
    if not want or f.dragging then return end

    RefreshBenefits(f)
    local nag = RefreshWellFed(f)
    RefreshRest(f)
    self:FillSlots(f)

    -- What shows: open, everything Options allows; closed, the tent and dials,
    -- and a weapon buff pick that's needed (popped out, glowing). The open
    -- kit (full) is kept on screen either way, so opening it never runs off it.
    local open, slots = self:IsOpen(), ns.db.widgetButtons == true
    local dials = { f.benefits }
    if ns.db.widgetWellFed then dials[2] = f.wellFed end
    local full = { dials = dials, picks = {}, pickOrder = {}, row = {} }
    local parts = { dials = dials, picks = {}, pickOrder = full.pickOrder, row = {} }
    if slots and NearFire() then
        full.sit = f.sit
        if open then parts.sit = f.sit end
    end
    -- As many extra slots as Options says, and a weapon pick for each weapon
    -- you hold (one with none, so it's there).
    local weapons = math.max(1, ns.Supplies:WeaponCount())
    local extras = math.min(ns.Supplies.MAX_EXTRAS, math.max(0, tonumber(ns.db.widgetExtras) or 0))
    for _, button in ipairs(f.pickOrder) do
        local wanted = (button.slot == "weapon" and button.number <= weapons)
            or (button.slot == "extra" and button.number <= extras) or button.slot == "food" or button.slot == "potion"
        local food = button.kind == "food" and button.item ~= nil and not ns.Supplies:IsDrink(button.item)
        local needed = wanted and ((nag and food) or (button.weapon and button.item ~= nil and button.ready
            and ns.Supplies:WeaponNeeds(button.item)))
        Glow(button, needed and true or false)
        if slots and wanted then
            full.pickOrder[#full.pickOrder + 1] = button
            full.picks[#full.picks + 1] = button
            -- Closed, only a weapon buff that's needed pops out: not food (the
            -- Well Fed dial reminds you).
            if open or (needed and button.weapon) then parts.picks[#parts.picks + 1] = button end
        end
    end
    if slots then
        -- The camp objects, with your campfire kit in the middle.
        local row = {}
        for i, button in ipairs(f.objectSlots) do
            if bags.slots[i] then row[#row + 1] = button end
        end
        table.insert(row, math.floor(#row / 2) + 1, f.place)
        full.row, full.bag = row, f.bag.item and f.bag or nil
        if open then parts.row, parts.bag = full.row, full.bag end
    end
    ClampToKit(f, Positions(OpensFrom(), full))
    local at, divider, across = Positions(OpensFrom(), parts)
    local showing = {}
    for _, button in ipairs(parts.picks) do showing[button] = true end
    for _, button in ipairs(parts.pickOrder) do
        if not showing[button] then at[button] = nil end
    end
    for _, frame in ipairs({ f.benefits, f.wellFed, f.sit, unpack(f.slots) }) do
        local spot = at[frame]
        frame:ClearAllPoints()
        if spot then
            frame:SetPoint("CENTER", f, "CENTER", spot[1], spot[2])
            frame:Show()
        else
            frame:Hide()
        end
    end
    f.divider:ClearAllPoints()
    f.divider:SetShown(divider ~= nil)
    if divider then
        f.divider:SetPoint("CENTER", f, "CENTER", divider[1], divider[2])
        if across then f.divider:SetSize(1, divider[3]) else f.divider:SetSize(divider[3], 1) end
    end
    f.parts = at
end

-- Shows or hides the kit: shown, its state driver hides it in combat (out of
-- combat only, both).
function Widget:ApplyShown(show)
    local f = self.frame
    if f.shownState == show then return end
    f.shownState = show
    f:SetShown(show)
end

-- In combat: what's drawn on the kit, and nothing secure. Its dials' timers and
-- glows, the rest's sweep, how many of each pick you have left (greyed at
-- none), and the slots' cooldowns.
function Widget:RefreshInCombat(f)
    RefreshBenefits(f)
    RefreshWellFed(f)
    RefreshRest(f)
    for _, button in ipairs(f.picks) do
        if button.item then
            local have = ns.Supplies:Count(button.item)
            button.count:SetText(have ~= 1 and tostring(have) or "")
            button.icon:SetDesaturated(have == 0)
        end
    end
    for _, button in ipairs(f.slots) do ShowCooldown(button, button.item) end
end

-- Out of combat: takes on a new size from Options, keeping its place on
-- screen (its saved point is in its own scale, so it's converted).
function Widget:ApplySize()
    local f = self.frame
    local scale = KitScale()
    if not f or f.scaled == scale or ns.InCombat() then return end
    local p = ns.db.widgetPoint
    if p and p[3] and p[4] then
        local ratio = (ns.db.widgetPointScale or f.scaled) / scale
        ns.db.widgetPoint = { p[1], p[2], p[3] * ratio, p[4] * ratio }
    end
    ns.db.widgetPointScale = scale
    f:SetScale(scale)
    f.scaled = scale
    f.clampKey = nil
    PlaceAtSaved(f)
end

-- In combat the kit holds still: it can't be moved, shown, hidden or resized.
function Widget:Frozen()
    return self.frame ~= nil and ns.InCombat()
end

-- The tour shows the kit, open, even if it's turned off or hidden, until it moves on.
function Widget:ShowForGuide(on)
    self.guideShow = on or nil
    self:Update()
end

-- Shows or hides the kit (turning it on in Options if it was off).
function Widget:Toggle()
    -- Not "self.frame and self.frame:IsShown()": before the kit is first made
    -- that's nil, which Update reads as "not decided" and hides it again when
    -- Options says to start hidden.
    local shown = self.frame ~= nil and self.frame:IsShown() == true
    if not ns.db.widget then
        ns.db.widget = true
        ns.Options:Sync()
        shown = false
    end
    if ns.InCombat() then
        if self.frame then return ns.Print(L["The Campsite Assistant can be shown or hidden after combat."]) end
        -- Never made yet: its slots can't be made in combat, so it's made
        -- (and shown) once that's over.
        self.hidden = false
        return ns.Print(L["The Campsite Assistant will show after combat."])
    end
    self.hidden = shown
    self:Update()
end

-- Key bindings (Bindings.xml): the kit, and each slot (a click on its button).
BINDING_HEADER_HAPPYCAMPER = "Happy Camper"
ns.OnLocale(function(L)
    BINDING_NAME_HAPPYCAMPER_KIT = L["Open or close the Campsite Assistant"]
    local names = {
        HappyCamperPlaceCampfire = L["Campfire kit"],
        HappyCamperSleepingBag = L["Sleeping bag"],
        HappyCamperFood1 = L["Food or drink"],
        HappyCamperWeapon1 = format(L["Weapon buff %d"], 1),
        HappyCamperWeapon2 = format(L["Weapon buff %d"], 2),
    }
    for i = 1, MAX_OBJECT_SLOTS do names["HappyCamperPlaceObject" .. i] = format(L["Camp object %d"], i) end
    names.HappyCamperPotion1 = L["Potion or elixir"]
    for i = 1, ns.Supplies.MAX_EXTRAS do names["HappyCamperExtra" .. i] = format(L["Extra slot %d"], i) end
    for button, name in pairs(names) do _G["BINDING_NAME_CLICK " .. button .. ":LeftButton"] = name end
end)
