local addonName, ns = ...

---------------------------------------------------------------------------
-- What's at this camp.
--
-- The game doesn't tell addons what a camp holds, so the kit pieces it
-- together while you're there (you have Campfire Nearby):
--   * Mouse over the campfire: its name says its tier, so how many objects
--     the camp takes (Basic 3, Journeyman 5, Expert 10).
--   * Mouse over a camp object: its name says which one it is. The Camp
--     Chair just says "Chair": that name is known for English and learned
--     for other languages (ns.CAMP_WORLD_NAMED), and only counts at a camp.
--   * Anything you or your group place (or a campfire you build) adds itself.
--   * "No room for more features at this camp." means every slot is taken.
--   * Camp objects run out and new ones go down at the same camp. The game
--     doesn't say when one goes, so each spot remembers when it was last
--     seen (placed, or moused over). When something new turns up at a camp
--     that's already full, it takes the spot seen longest ago.
-- Names are matched against the client's own names for the camp spells and
-- kit items (by ID), so it works in any game language. Leaving the camp
-- (Campfire Nearby gone) starts over.
--
-- Shown as: small pips under the closed tent; a row over the open kit (its
-- campfire's name and count above, the announce button at the end); on a
-- screen edge, a column between the camp objects and your picks. The tent's
-- right-click menu opens "This campfire..." with the full list.
---------------------------------------------------------------------------

local Core = ns.Core
local U = Core.U
local MEDIA = ns.MEDIA

local Camp = {}
ns.Camp = Camp

local OPEN_SIZE, PIP_SIZE, CHAT_SIZE = 26, 16, 18
local OPEN_GAP, PIP_GAP = 4, 3
local PER_COL = 5     -- on a screen edge: this many to a column
local MAX_ICONS = 12  -- two camps side by side can add up past 10
local ROW_Y = 120     -- the open row's centre, over the pick arc (clear of the middle pick)
local HEADER_GAP = 11 -- from the row's top edge to the header's centre
local ORANGE, GREY, GREEN = { 1, 0.55, 0.25 }, { 0.62, 0.62, 0.62 }, { 0.25, 0.82, 0.29 }

---------------------------------------------------------------------------
-- What we know about the camp you're at
---------------------------------------------------------------------------

local camp = {
    fire = nil,  -- an entry of ns.CAMPFIRES, once known
    list = {},   -- objects seen, in the order seen (catalog entries; a repeat means two placed)
    seen = {},   -- GetTime() each of those was last placed or moused over (same index as list)
    full = false,
    started = nil, -- server time the fire was built, when a kit user saw it built
    wants = {},  -- objects someone at the camp is looking for ("This campfire..."), shared on the map
    wantsAt = 0, -- server time of the last change to that list (the newest change wins)
    casts = {},  -- cast GUIDs already counted (a raid member's cast can arrive for several units)
}
local wasAtCamp = false
local heldAura   -- Campfire Nearby's instance while you're at a camp: a new one means another fire

local function Reset()
    camp.fire, camp.full, camp.started, camp.wantsAt = nil, false, nil, 0
    wipe(camp.list)
    wipe(camp.seen)
    wipe(camp.wants)
    wipe(camp.casts)
    camp.violet = nil
end

local function Has(o)
    for _, e in ipairs(camp.list) do
        if e == o then return true end
    end
    return false
end

-- The spot seen longest ago (of one object, if given).
local function Stalest(o)
    local best
    for i, e in ipairs(camp.list) do
        if (not o or e == o) and (not best or (camp.seen[i] or 0) < (camp.seen[best] or 0)) then best = i end
    end
    return best
end

local function Drop(i)
    table.remove(camp.list, i)
    table.remove(camp.seen, i)
end

-- Never more objects than the camp holds: once its size is known, anything
-- past it goes, longest-unseen first (it has run out since).
local function Trim()
    local cap = camp.fire and camp.fire.slots or MAX_ICONS
    while #camp.list > cap do Drop(Stalest()) end
end

-- One more object at the camp. If the camp was full, one of the old ones must
-- have run out to make room: the one seen longest ago goes.
local function Add(o)
    local cap = camp.fire and camp.fire.slots or MAX_ICONS
    if #camp.list >= cap then Drop(Stalest()) end
    camp.list[#camp.list + 1] = o
    camp.seen[#camp.list] = GetTime()
end

---------------------------------------------------------------------------
-- The catalog: every camp object and campfire, found by the client's own
-- names (what its tooltip shows) and by the spell its kit item casts.
---------------------------------------------------------------------------

local byName, bySpell, objects = {}, {}, {}
local catalogDone, catalogAt = false, 0

local function ItemName(id)
    local name = C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(id)
    if not name and C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, id) end
    return name
end

local function ItemSpellID(id)
    if not (C_Item and C_Item.GetItemSpell) then return nil end
    local ok, _, sid = pcall(C_Item.GetItemSpell, id)
    return ok and sid or nil
end

local function BuildCatalog()
    if catalogDone then return end
    local now = GetTime()
    if now - catalogAt < 3 then return end -- names still loading: try again shortly
    catalogAt = now
    local missing = false
    local function Name(name, entry)
        if name and name ~= "" then byName[name] = entry else missing = true end
    end
    local function Item(id, entry)
        if not id then return end
        Name(ItemName(id), entry)
        local sid = ItemSpellID(id)
        if sid then bySpell[sid] = entry else missing = true end
    end
    local function Obj(key, spell, item, tier, effect)
        local o = objects[spell]
        if not o then
            o = {
                key = key, spell = spell, item = item, tier = tier,
                buff = (tier == 1 and ns.CAMP_BUFF_PROFS[key]) and true or false,
                effect = effect or (tier == 1 and ns.CAMP_EFFECTS[key]) or nil,
            }
            objects[spell] = o
        end
        Name(U.SpellName(spell), o)
        Item(item, o)
        return o
    end
    for key, p in pairs(ns.PROFESSIONS) do
        if key ~= "cooking" then
            local n = #p.recipes
            for i, spell in ipairs(p.recipes) do Obj(key, spell, p.items[i], n - i + 1) end
            -- More items than recipes: the other faction's tier 1 (Tailoring's banners).
            for i = n + 1, #(p.items or {}) do Item(p.items[i], objects[p.recipes[n]]) end
        end
    end
    for _, c in ipairs(ns.COOKING_OBJECTS) do Obj("cooking", c.spell, c.item, nil, c.effect) end
    for _, f in ipairs(ns.CAMPFIRES) do
        local entry = { fire = f }
        for _, sid in ipairs(f.spells) do
            local name = U.SpellName(sid)
            if name then byName[name] = entry end
        end
        Item(f.item, entry)
    end
    catalogDone = not missing
end

local function ObjName(o)
    return U.SpellName(o.spell) or (o.item and U.ItemName(o.item)) or "?"
end

-- What an object does for you, with its amounts at your level where they
-- scale (ns.CAMP_SCALING).
-- A profession's tier 1 bonus at a level (ns.CAMP_SCALING), or nil.
local function ScaledAt(key, lvl)
    local parts = ns.CAMP_SCALING[key]
    if not parts then return nil end
    local out = {}
    for _, part in ipairs(parts) do
        if #part == 1 then
            out[#out + 1] = part[1]
        else
            local amount
            for i = 2, #part do
                if lvl >= part[i][1] then amount = part[i][2] end
            end
            if amount then out[#out + 1] = part[1]:format(amount) end
        end
    end
    return #out > 0 and table.concat(out, ", ") or nil
end

function Camp.Effect(o)
    if not (o and o.tier == 1) then return o and o.effect end
    return ScaledAt(o.key, UnitLevel("player") or 1) or o.effect
end

-- How a profession's bonus changes with level: { from, to, text } per level
-- range, lowest first. Nil when it never changes.
local MAX_LEVEL = 60
function Camp.Brackets(key)
    local parts = ns.CAMP_SCALING[key]
    if not parts then return nil end
    local starts, seen = {}, {}
    for _, part in ipairs(parts) do
        for i = 2, #part do
            local from = part[i][1]
            if not seen[from] then seen[from] = true starts[#starts + 1] = from end
        end
    end
    if #starts < 2 then return nil end
    table.sort(starts)
    local list = {}
    for i, from in ipairs(starts) do
        list[i] = { from = from, to = starts[i + 1] and starts[i + 1] - 1 or MAX_LEVEL, text = ScaledAt(key, from) }
    end
    return list
end

local function AddEffect(o)
    local text = Camp.Effect(o)
    if text then GameTooltip:AddLine(text, 1, 1, 1, true) end
end

local function FireName(f)
    return f and U.SpellName(f.spells[1]) or "Campfire"
end

-- Room left at the camp: 0 when it's full; at least 1 while its size isn't known.
local function OpenSlots()
    if camp.full then return 0 end
    if not camp.fire then return 1 end
    return camp.fire.slots - #camp.list
end

-- What's asked for clears itself: an object that's turned up, or everything
-- once the camp has no room left.
local function PruneWants()
    if #camp.wants == 0 then return end
    if OpenSlots() <= 0 then
        wipe(camp.wants)
        return
    end
    for i = #camp.wants, 1, -1 do
        if Has(camp.wants[i]) then table.remove(camp.wants, i) end
    end
end

-- What can be asked for: each profession's tier 1 camp object.
local WANT_ORDER = { "alchemy", "blacksmithing", "enchanting", "engineering", "firstaid", "fishing",
    "herbalism", "leatherworking", "mining", "skinning", "tailoring" }
local function WantChoices()
    BuildCatalog()
    local list = {}
    for _, key in ipairs(WANT_ORDER) do
        local p = ns.PROFESSIONS[key]
        local o = p and objects[p.recipes[#p.recipes]]
        if o then list[#list + 1] = o end
    end
    return list
end

local function Wanted(o)
    for _, w in ipairs(camp.wants) do
        if w == o then return true end
    end
    return false
end

-- You could put this one down: its kit is in your bags, or you know its recipe.
function Camp.CanPlace(o)
    return (o.item and U.Owned(o.item)) or U.Known(o.spell) or false
end

-- The class buff an object's bonus doesn't stack with, if any (ns.CAMP_CONFLICTS),
-- by the client's own name for it.
function Camp.Competes(o)
    local ids = o and ns.CAMP_CONFLICTS[o.key]
    if not ids or o.tier ~= 1 then return nil end
    local names = {}
    for _, id in ipairs(ns.CAMP_COMPETES_SHOW[o.key] or { ids[1] }) do
        local name = U.SpellName(id)
        if name then names[#names + 1] = name end
    end
    return #names > 0 and table.concat(names, " or ") or nil
end

local COMPETE = "Doesn't stack with %s"

local function ProfLabel(o)
    local p = ns.PROFESSIONS[o.key]
    return p and p.label or nil
end

---------------------------------------------------------------------------
-- Learning about the camp
---------------------------------------------------------------------------

local panel -- "This campfire...", made when first opened
local FillPanel

local function Changed(kit)
    PruneWants()
    -- Out of combat the layout can change (how many slots, an edge column);
    -- in combat just repaint, and the end of combat lays it out.
    if InCombatLockdown() then kit:PaintAll() else kit:Refresh(false) end
    if panel and panel:IsShown() then FillPanel(kit) end
    if ns.CampNet then ns.CampNet.CampChanged() end
end

-- The last world object moused over, for /ck object.
Camp.lastObject = nil

-- An object whose world name isn't its own name, just placed: the next
-- unknown object moused over at the camp is taken to be it.
local learning -- { spell = , at = GetTime() }
local LEARN_WINDOW = 90

local function LearnedNames(kit)
    local loc = GetLocale and GetLocale() or "enUS"
    kit.db.worldNames = kit.db.worldNames or {}
    kit.db.worldNames[loc] = kit.db.worldNames[loc] or {}
    return kit.db.worldNames[loc], ns.CAMP_WORLD_NAMES[loc]
end

-- A camp object known by its world name ("Chair"), or nil.
local function ByWorldName(kit, text)
    local learned, known = LearnedNames(kit)
    local spell = learned[text] or (known and known[text])
    if spell then return objects[spell] end
    if learning and GetTime() - learning.at <= LEARN_WINDOW then
        local o = objects[learning.spell]
        learning = nil
        -- Only while its name isn't known yet: otherwise an unknown object
        -- moused over after placing one would be learned as it too.
        for _, names in ipairs({ learned, known or {} }) do
            for _, sp in pairs(names) do
                if o and sp == o.spell then o = nil end
            end
        end
        if o then
            learned[text] = o.spell
            return o
        end
    end
end

-- Mousing over something in the world: a campfire or a camp object?
local function OnObjectTooltip(_, data)
    if type(data) ~= "table" then return end
    local line = data.lines and data.lines[1]
    local text = line and line.leftText
    if not text or U.Sealed(text) then return end
    local lines = {}
    for i = 2, #(data.lines or {}) do
        local t = data.lines[i].leftText
        if t and not U.Sealed(t) and t ~= "" then lines[#lines + 1] = t end
    end
    Camp.lastObject = { name = text, guid = (not U.Sealed(data.guid)) and data.guid or nil, lines = lines }
    local kit = ns.kit
    if not (kit and kit.built and ns.AtCamp()) then return end
    BuildCatalog()
    local e = byName[text] or ByWorldName(kit, text)
    if not e then return end
    -- Standing where another fire is about as close as yours: what you're
    -- looking at could belong to either camp, so it isn't counted.
    if ns.CampNet and ns.CampNet.Ambiguous() then return end
    if e.fire then
        if camp.fire == e.fire then return end
        camp.fire = e.fire
        Trim()
    else
        -- Already listed: it's still there, so it's the last to go.
        if Has(e) then
            camp.seen[Stalest(e)] = GetTime()
            return
        end
        Add(e)
        camp.full = false
    end
    Changed(kit)
end

function Camp.OnCast(kit, unit, castGUID, spellID)
    if U.Sealed(unit) or U.Sealed(spellID) or type(unit) ~= "string" then return end
    if not (unit == "player" or unit:match("^party%d$") or unit:match("^raid%d+$")) then return end
    BuildCatalog()
    local e = bySpell[spellID]
    if not e then return end
    if castGUID and not U.Sealed(castGUID) then
        if camp.casts[castGUID] then return end
        camp.casts[castGUID] = true
    end
    if e.fire then
        -- Your own fire starts a new camp; someone else's only says the tier
        -- of the one you're at, if you don't know it yet.
        if unit == "player" or UnitIsUnit(unit, "player") then
            -- Built well away from the fire you're at (you're still inside its
            -- range): a camp of its own, not this one.
            if ns.CampNet and not ns.CampNet.FireBuilt(e.fire.tier) then return end
            if not ns.AtCamp() then Reset() end
            camp.fire = e.fire
        elseif not camp.fire then
            camp.fire = e.fire
        else
            return
        end
        camp.started = GetServerTime and GetServerTime() or nil
        Trim()
    else
        if ns.CAMP_WORLD_NAMED[e.spell] then learning = { spell = e.spell, at = GetTime() } end
        -- A cast is one more object even if one like it is there already.
        -- It went down, so there was room: if the camp looked full, the
        -- object seen longest ago has run out.
        Add(e)
        camp.full = false
    end
    Changed(kit)
end

function Camp.OnError(kit, _, msg)
    if U.Sealed(msg) or not msg then return end
    local full = _G[ns.CAMP_FULL_ERROR]
    if full and msg == full and ns.AtCamp() and not camp.full then
        camp.full = true
        Changed(kit)
    end
end

-- For the shared camp pins (CampNet.lua, CampMap.lua).
function Camp.Snapshot()
    PruneWants()
    local spells, wants = {}, {}
    for _, o in ipairs(camp.list) do spells[#spells + 1] = o.spell end
    for _, o in ipairs(camp.wants) do wants[#wants + 1] = o.spell end
    return { tier = camp.fire and camp.fire.tier or 0, full = camp.full, started = camp.started, spells = spells,
        wants = wants, wantsAt = camp.wantsAt, violet = camp.violet }
end

-- Whether the fire you're at is purple: you've been close enough to have
-- Violet Flames (its range is shorter than Campfire Nearby's, so not having
-- it says nothing), or another kit user has.
function Camp.IsViolet()
    return (camp.violet or (ns.CampNet and ns.CampNet.MineViolet and ns.CampNet.MineViolet())) and true or false
end

-- Ask for an object at this camp, or stop asking.
function Camp.SetWant(kit, o, on)
    if on == Wanted(o) then return end
    if on then
        if Has(o) or OpenSlots() <= 0 then return end
        camp.wants[#camp.wants + 1] = o
    else
        for i = #camp.wants, 1, -1 do
            if camp.wants[i] == o then table.remove(camp.wants, i) end
        end
    end
    camp.wantsAt = GetServerTime and GetServerTime() or time()
    Changed(kit)
end

-- Someone else at this camp changed what it's looking for (CampNet.lua).
function Camp.ApplyWants(spells, at)
    if not at or at <= camp.wantsAt or not ns.AtCamp() then return end
    wipe(camp.wants)
    for _, spell in ipairs(spells) do
        local o = Camp.ObjectBySpell(spell)
        if o and not Wanted(o) then camp.wants[#camp.wants + 1] = o end
    end
    camp.wantsAt = at
    if ns.kit then Changed(ns.kit) end
end

function Camp.ObjectBySpell(spell)
    BuildCatalog()
    return objects[spell]
end

-- An object from a spell the game uses for it: its recipe, or its item's.
function Camp.ObjectFromGame(spell)
    BuildCatalog()
    if not spell then return nil end
    local o = objects[spell] or bySpell[spell]
    return o and objects[o.spell] == o and o or nil
end

-- A profession's object of a tier, by the profession's ID in the game data.
function Camp.ObjectByProfession(skillLine, tier)
    BuildCatalog()
    for key, p in pairs(ns.PROFESSIONS) do
        if key ~= "cooking" and p.skillLine == skillLine then
            local spell = tier and p.recipes[#p.recipes - tier + 1]
            return spell and objects[spell] or nil
        end
    end
end

-- The spells of the objects a chat message names, in your game's language.
function Camp.ObjectsNamedIn(text)
    BuildCatalog()
    local list, seen = {}, {}
    for name, o in pairs(byName) do
        if #list < 12 and o.spell and objects[o.spell] == o and not seen[o.spell] and text:find(name, 1, true) then
            seen[o.spell] = true
            list[#list + 1] = o.spell
        end
    end
    return list
end

function Camp.FireByTier(tier)
    for _, f in ipairs(ns.CAMPFIRES) do
        if f.tier == tier then return f end
    end
end

Camp.ObjName, Camp.FireName = function(o) return ObjName(o) end, function(f) return FireName(f) end

function Camp.HasCamp()
    return ns.AtCamp() or #camp.list > 0
end

---------------------------------------------------------------------------
-- Frames: the icons (pips closed, larger open), the header, the announce
-- button and the divider under the open row.
---------------------------------------------------------------------------

local icons = {}
local header, chat, divider, listBtn, mergedLabel
-- Closed in a Kit Dock box: one button in the box's row, and with the mouse
-- over it, the camp in a row of its own past the box's blocks.
local fireBtn, rowBox
local rowOpen = false
local boxedClosed = false
local extras = {}
local shownCount, mode, size = 0, nil, OPEN_SIZE

-- How many spots to show: the camp's slots once its tier is known, else
-- just what's been seen (both, if two camps add up to more).
local function SlotCount()
    local n = camp.fire and camp.fire.slots or (#camp.list + #camp.wants) -- size unknown: room for what's asked for
    return math.min(MAX_ICONS, math.max(n, #camp.list))
end

-- "closed", "open", or nil (not at a camp, or turned off, or shrunk on the dock).
local function Mode(kit)
    if not ns.AtCamp() or kit.db.shown == false or kit.tucked or kit.compactAngle then return nil end
    if kit.open then return kit.db.campRow and "open" or nil end
    return kit.db.campPips and "closed" or nil
end

local function ClashFor(kit, o)
    return kit.db.campClash and ns.clashes[o.key] or nil
end

local function IconTooltip(kit, f)
    kit:TipOwner(f)
    local o = camp.list[f.index]
    if o then
        GameTooltip:AddLine(ObjName(o))
        local prof = ProfLabel(o)
        if prof then GameTooltip:AddLine(prof, GREY[1], GREY[2], GREY[3]) end
        AddEffect(o)
        local competes = Camp.Competes(o)
        if competes then GameTooltip:AddLine(COMPETE:format(competes), ORANGE[1], ORANGE[2], ORANGE[3], true) end
        local clash = ClashFor(kit, o)
        if clash then
            GameTooltip:AddLine("You have " .. clash.name .. ", so you won't get this one's bonus.", 1, 0.82, 0, true)
        elseif o.buff and not ns.auras.benefits then
            GameTooltip:AddLine("Sit by the fire for about a minute to get its bonus.", GREEN[1], GREEN[2], GREEN[3], true)
        end
    else
        local w = camp.wants[f.index - #camp.list]
        if w then
            GameTooltip:AddLine("Looking for: " .. ObjName(w))
            AddEffect(w)
            local competes = Camp.Competes(w)
            if competes then GameTooltip:AddLine(COMPETE:format(competes), ORANGE[1], ORANGE[2], ORANGE[3], true) end
            GameTooltip:AddLine("Asked for in This campfire... and shown on the camp's map pin.", GREY[1], GREY[2], GREY[3], true)
        else
            GameTooltip:AddLine("Not seen yet")
            GameTooltip:AddLine("Mouse over the camp's objects to see what's here.", 1, 1, 1, true)
        end
    end
    GameTooltip:Show()
end

local function MakeIcon(kit, i)
    local f = CreateFrame("Frame", "CampingKitCamp_" .. i, kit.holder)
    f:SetSize(OPEN_SIZE, OPEN_SIZE)
    f:SetFrameLevel(14)
    f:EnableMouse(true)
    f.index = i
    f.icon = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetPoint("TOPLEFT", 2, -2)
    f.icon:SetPoint("BOTTOMRIGHT", -2, 2)
    local mask = f:CreateMaskTexture()
    mask:SetTexture(MEDIA .. "circle_mask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mask:SetAllPoints(f.icon)
    f.icon:AddMaskTexture(mask)
    f.ring = f:CreateTexture(nil, "OVERLAY", nil, 6)
    f.ring:SetAllPoints()
    f.dash = f:CreateTexture(nil, "OVERLAY", nil, 6)
    f.dash:SetAllPoints()
    f.dash:SetTexture(MEDIA .. "ring_dashed_64", nil, nil, "LINEAR")
    f.dash:SetAlpha(0.8)
    kit:AddGlow(f, "glow_ring", 1.35)
    f:SetScript("OnEnter", function(self) kit:Hover(true) IconTooltip(kit, self) end)
    f:SetScript("OnLeave", function() kit:Hover(false) end)
    f:SetScale(kit.db.scale)
    f:Hide()
    return f
end

local function MakeFrames(kit)
    for i = 1, MAX_ICONS do icons[i] = MakeIcon(kit, i) end

    header = CreateFrame("Frame", "CampingKitCampHeader", kit.holder)
    header:SetSize(160, 14)
    header:SetFrameLevel(14)
    header.name = header:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    header.count = header:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    header.name:SetPoint("LEFT")
    header.count:SetPoint("LEFT", header.name, "RIGHT", 6, 0)
    header:SetScale(kit.db.scale)
    header:Hide()

    -- The campfire's name, and a list button beside it, open "This campfire...".
    local function PanelTip(self)
        kit:Hover(true)
        kit:TipOwner(self)
        GameTooltip:AddLine("This campfire\226\128\166")
        GameTooltip:AddLine("Everything at this camp, and what to ask for.", 1, 1, 1, true)
        GameTooltip:AddLine("Click: open or close", 0.3, 1, 0.4)
        GameTooltip:Show()
    end
    header:EnableMouse(true)
    header:SetScript("OnMouseUp", function(_, button) if button == "LeftButton" then Camp.TogglePanel(kit) end end)
    header:SetScript("OnEnter", function(self) header.name:SetTextColor(1, 1, 1) PanelTip(self) end)
    header:SetScript("OnLeave", function() header.name:SetTextColor(1, 0.82, 0) kit:Hover(false) end)

    listBtn = CreateFrame("Button", "CampingKitCampListButton", kit.holder)
    listBtn:SetSize(16, 16)
    listBtn:SetFrameLevel(14)
    listBtn:SetPoint("LEFT", header, "RIGHT", 6, 0)
    listBtn:SetNormalTexture(MEDIA .. "camp_list")
    listBtn:SetHighlightTexture(MEDIA .. "camp_list", "ADD")
    listBtn:RegisterForClicks("LeftButtonUp")
    listBtn:SetScript("OnClick", function() Camp.TogglePanel(kit) end)
    listBtn:SetScript("OnEnter", PanelTip)
    listBtn:SetScript("OnLeave", function() kit:Hover(false) end)
    listBtn:SetScale(kit.db.scale)
    listBtn:Hide()

    chat = CreateFrame("Button", "CampingKitCampAnnounce", kit.holder)
    chat:SetSize(CHAT_SIZE, CHAT_SIZE)
    chat:SetFrameLevel(14)
    chat:SetNormalTexture(MEDIA .. "chat_bubble")
    chat:SetHighlightTexture(MEDIA .. "chat_bubble", "ADD")
    chat:RegisterForClicks("LeftButtonUp")
    chat:SetScript("OnClick", function() Camp.Announce(kit) end)
    chat:SetScript("OnEnter", function(self)
        kit:Hover(true)
        kit:TipOwner(self)
        GameTooltip:AddLine("Announce this camp")
        GameTooltip:AddLine("Posts the campfire and what's at it in General chat, with a map pin link for players without Camping Kit. Kit users on your layer see the camp on their map already.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    chat:SetScript("OnLeave", function() kit:Hover(false) end)
    chat:SetScale(kit.db.scale)
    chat:Hide()

    divider = CreateFrame("Frame", "CampingKitCampDivider", kit.holder)
    divider:SetSize(200, 16)
    divider:SetFrameLevel(11)
    divider.tex = divider:CreateTexture(nil, "ARTWORK")
    divider.tex:SetPoint("CENTER")
    divider.tex:SetTexture(MEDIA .. "divider", nil, nil, "LINEAR")
    divider:SetScale(kit.db.scale)
    divider:Hide()

    -- Merged on the dock pin the camp doesn't show; a "Campfire..." label beside
    -- the tent says you're at one, and opens This campfire...
    mergedLabel = CreateFrame("Button", "CampingKitCampLabel", kit.holder)
    mergedLabel:SetSize(70, 14)
    mergedLabel:SetFrameLevel(14)
    mergedLabel.text = mergedLabel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    mergedLabel.text:SetAllPoints()
    mergedLabel.text:SetText("Campfire\226\128\166")
    mergedLabel:RegisterForClicks("LeftButtonUp")
    mergedLabel:SetScript("OnClick", function() Camp.TogglePanel(kit) end)
    mergedLabel:SetScript("OnEnter", function(self) self.text:SetTextColor(1, 1, 1) PanelTip(self) end)
    mergedLabel:SetScript("OnLeave", function(self) self.text:SetTextColor(1, 0.82, 0) kit:Hover(false) end)
    mergedLabel:SetScale(kit.db.scale)
    mergedLabel:Hide()

    fireBtn = CreateFrame("Button", "CampingKitCampFire", kit.holder)
    fireBtn:SetSize(22, 22)
    fireBtn:SetFrameLevel(14)
    fireBtn.icon = fireBtn:CreateTexture(nil, "ARTWORK")
    fireBtn.icon:SetAllPoints()
    fireBtn.icon:SetTexture(U.SpellIcon(ns.AURA.nearby) or 134400)
    local fireMask = fireBtn:CreateMaskTexture()
    fireMask:SetTexture(MEDIA .. "circle_mask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    fireMask:SetAllPoints(fireBtn.icon)
    fireBtn.icon:AddMaskTexture(fireMask)
    fireBtn.ring = fireBtn:CreateTexture(nil, "OVERLAY", nil, 6)
    fireBtn.ring:SetAllPoints()
    fireBtn.count = fireBtn:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    fireBtn.count:SetPoint("BOTTOMRIGHT", 4, -2)
    fireBtn:RegisterForClicks("LeftButtonUp")
    fireBtn:SetScript("OnClick", function() Camp.TogglePanel(kit) end)
    fireBtn:SetScript("OnEnter", function() kit:Hover(true) Camp.ShowBoxRow(kit) end)
    fireBtn:SetScript("OnLeave", function() kit:Hover(false) end)
    fireBtn:SetScale(kit.db.scale)
    fireBtn:Hide()

    rowBox = CreateFrame("Frame", "CampingKitCampRow", kit.holder, "BackdropTemplate")
    rowBox:SetFrameLevel(8)
    rowBox:SetClampedToScreen(true)
    if rowBox.SetBackdrop then
        rowBox:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
        rowBox:SetBackdropColor(0.05, 0.04, 0.03, 0.92)
        rowBox:SetBackdropBorderColor(0.36, 0.3, 0.17)
    end
    local away = 0
    rowBox:SetScript("OnShow", function() away = 0 end)
    rowBox:SetScript("OnUpdate", function(self, elapsed)
        if fireBtn:IsMouseOver() or self:IsMouseOver(6, -6, -6, 6) then
            away = 0
        else
            away = away + elapsed
            if away >= 0.5 then Camp.HideBoxRow(kit) end
        end
    end)
    rowBox:SetScale(kit.db.scale)
    rowBox:Hide()

    for _, f in ipairs(icons) do extras[#extras + 1] = f end
    extras[#extras + 1] = header
    extras[#extras + 1] = listBtn
    extras[#extras + 1] = chat
    extras[#extras + 1] = divider
    extras[#extras + 1] = mergedLabel
end

-- The frames Kit Core scales and glides along with the kit: just the timers.
-- The camp's own pieces are left out on purpose. They're anchored to the
-- tent, so they move with it anyway, and Kit Dock's re-layouts (another kit
-- changing, say making a healthstone) would otherwise replay a glide on them
-- each time, so they jumped and floated back. They're scaled here instead
-- (BeforeRefresh), and glide only when this kit opens or closes (PlayGlide).
function Camp.Extras(kit)
    return ns.dials
end

local function SizeIcon(f, s)
    if f.sized == s then return end
    f.sized = s
    f:SetSize(s, s)
    if f.glow then f.glow:SetSize(s * 1.35, s * 1.35) end
end

---------------------------------------------------------------------------
-- Which pieces show (before the slots are placed, out of combat)
---------------------------------------------------------------------------

-- Floating, when the kit opens or closes, the camp's pieces glide between
-- where they were (pips under the tent, the row over the kit) and where they
-- go, growing or shrinking on the way; new ones come out of the tent. Noted
-- here, played once they're placed. Any other refresh (something seen, asked
-- for, a buff) just places them.
local glideFrom, lastOpen

local function NoteGlide(kit)
    glideFrom = nil
    local opened = lastOpen ~= nil and lastOpen ~= kit.open
    lastOpen = kit.open
    if not opened or kit.edgeSide or kit.compactAngle or not (kit.Dock and kit.Dock.Glide) then return end
    local tx, ty = kit.kit:GetCenter()
    if not tx then return end
    glideFrom = { tent = { tx, ty, kit.kit:GetEffectiveScale() }, at = GetTime() }
    for _, f in ipairs(extras) do
        if f:IsShown() then
            local x, y = f:GetCenter()
            if x then glideFrom[f] = { x, y, f:GetEffectiveScale(), f:GetWidth() } end
        end
    end
end

local function PlayGlide(kit)
    local from = glideFrom
    glideFrom = nil
    -- Only for the refresh that noted it: one left over from a refresh that
    -- never placed the camp mustn't replay on a later, unrelated one.
    if not from or from.at ~= GetTime() then return end
    for _, f in ipairs(extras) do
        -- Only the slots and the announce button glide. The campfire's name,
        -- its list button and the divider just show where they belong, like
        -- the kit's own divider: they never come out of the tent.
        if f:IsShown() and f ~= mergedLabel and f ~= header and f ~= listBtn and f ~= divider then
            local eff, w = f:GetEffectiveScale(), f:GetWidth()
            local b, ratio = from[f], 0.4
            if b then
                if f.sized and b[4] and w > 0 then ratio = b[4] / w else ratio = 1 end
            else
                b = from.tent
            end
            -- Kit Dock's glide grows from (start scale / now); start the size where it was.
            local fake = eff * ratio
            kit.Dock.Glide(f, b[1] * b[3] / fake, b[2] * b[3] / fake, fake)
        end
    end
end

-- Kit Core v5 works out the kit's other layout (for opening and closing in
-- combat) by running its updates and placement with kit.open flipped and
-- kit.trial set, without moving anything. The camp's pieces aren't part of
-- that (only slots are), so they sit it out: otherwise the flip looked like
-- the kit opening or closing, and the camp's name and divider glided out of
-- the tent on every refresh.
-- Fade when left open: the camp's row fades with the kit's slots.
function Camp.SetFaded(alpha)
    for _, f in ipairs(extras) do f:SetAlpha(alpha) end
end

function Camp.BeforeRefresh(kit)
    if not header or kit.trial then return end
    for _, f in ipairs(extras) do f:SetScale(kit.db.scale) end
    fireBtn:SetScale(kit.db.scale)
    rowBox:SetScale(kit.db.scale)
    NoteGlide(kit)
    BuildCatalog()
    local at = ns.AtCamp()
    -- You keep a fire's Campfire Nearby until you walk out of its range; inside
    -- another's, you get that one's straight away. Seen as one refresh, that's
    -- a new instance of the aura: a different fire, so a different camp.
    local inst = at and ns.auras.nearby.instance or nil
    local swapped = at and wasAtCamp and heldAura and inst and inst ~= heldAura
    if (wasAtCamp and not at) or swapped then Reset() end
    if swapped and ns.CampNet then ns.CampNet.Leave() end
    heldAura = inst
    local arrived = at ~= wasAtCamp or swapped
    wasAtCamp = at
    if at and ns.auras.violet and not camp.violet then
        camp.violet = true
        arrived = true -- (tells the other kit users, below)
        if panel and panel:IsShown() then FillPanel(kit) end
    end
    mode = Mode(kit)
    shownCount = mode and SlotCount() or 0
    boxedClosed = (mode == "closed" and kit.parked and kit.edgeSide) and true or false
    local fireOn = boxedClosed and not kit.quiet
    fireBtn:SetShown(fireOn)
    if rowOpen and not fireOn then
        rowOpen = false
        rowBox:Hide()
    end
    local pieces = not boxedClosed or rowOpen
    size = (mode == "open" or boxedClosed) and OPEN_SIZE or PIP_SIZE
    for i, f in ipairs(icons) do
        SizeIcon(f, size)
        f:SetShown(i <= shownCount and pieces)
    end
    header:SetShown(mode == "open")
    listBtn:SetShown(mode == "open")
    -- The "Campfire..." label: with the kit closed at a camp, in front of the pips
    -- (or on its own, before anything's known); merged on the pin, beside the tent.
    mergedLabel:SetShown(((mode == "closed" and pieces) or (kit.compactAngle and ns.AtCamp() and kit.db.campPips
        and kit.db.shown ~= false and not kit.tucked)) and true or false)
    if mergedLabel:IsShown() then mergedLabel:SetWidth(mergedLabel.text:GetStringWidth() + 4) end
    chat:SetShown(mode ~= nil and pieces and kit.db.campAnnounce and (mode == "open" or shownCount > 0) and true or false)
    divider:SetShown(mode == "open" and not kit.edgeSide)
    if arrived and ns.CampNet then ns.CampNet.CampChanged() end -- got to a camp, or left it
end

---------------------------------------------------------------------------
-- Painting (any time, combat too)
---------------------------------------------------------------------------

function Camp.Paint(kit)
    if not header or not mode or kit.trial then return end
    PruneWants()
    if boxedClosed then
        fireBtn.ring:SetTexture(kit:SmallRingArt(fireBtn), nil, nil, "LINEAR")
        if Camp.IsViolet() then fireBtn.ring:SetVertexColor(0.72, 0.45, 1) else fireBtn.ring:SetVertexColor(1, 1, 1) end
        fireBtn.count:SetText(camp.fire and (#camp.list .. "/" .. camp.fire.slots) or (#camp.list > 0 and #camp.list or ""))
    end
    for i = 1, shownCount do
        local f, o = icons[i], camp.list[i]
        f.ring:SetTexture(kit:SmallRingArt(f), nil, nil, "LINEAR")
        if o then
            f.icon:SetTexture((o.item and U.ItemIcon(o.item)) or U.SpellIcon(o.spell) or 134400)
            local clash = ClashFor(kit, o)
            f.icon:SetDesaturated(clash and true or false)
            f.icon:Show()
            f.ring:Show()
            f.dash:Hide()
            kit:SetGlow(f, false) -- the camp's objects never glow
        else
            -- An empty slot: what's being looked for, faded, else just the dashed ring.
            local w = camp.wants[i - #camp.list]
            if w then
                f.icon:SetTexture((w.item and U.ItemIcon(w.item)) or U.SpellIcon(w.spell) or 134400)
                f.icon:SetDesaturated(true)
                f.icon:SetAlpha(0.5)
                f.icon:Show()
            else
                f.icon:Hide()
            end
            f.ring:Hide()
            f.dash:Show()
            kit:SetGlow(f, false)
        end
        if o then f.icon:SetAlpha(1) end
    end
    if header:IsShown() then
        header.name:SetText(FireName(camp.fire))
        local count = camp.fire and (#camp.list .. "/" .. camp.fire.slots) or (#camp.list > 0 and tostring(#camp.list) or "")
        if camp.full then count = count .. (count ~= "" and "  " or "") .. "full" end
        header.count:SetText(count)
        header:SetWidth(header.name:GetStringWidth() + 6 + header.count:GetStringWidth())
    end
end

function Camp.Tick(kit)
    if panel and panel:IsShown() then FillPanel(kit) end
end

---------------------------------------------------------------------------
-- Placing: floating (PlaceExtras), and on a screen edge (Kit Core's edge
-- layout, extended below)
---------------------------------------------------------------------------

local function Below(kit)
    -- How far under the tent the closed pips go: clear of any timer or the
    -- sleeping bag that's out.
    local low = kit:KitHalfUnits() + 4
    for _, f in ipairs(ns.dials) do
        if f:IsShown() then low = math.max(low, -f.def.y + ns.DIAL / 2 + 14) end
    end
    local bag = kit.slots.bag
    if bag and bag:IsShown() and not bag.closing then
        low = math.max(low, -bag.slot.pos[2] + kit.BTN / 2 + 4)
    end
    local sit = kit.slots.sit
    if sit and sit:IsShown() and not sit.closing then
        low = math.max(low, -sit.slot.pos[2] + 11 + 2) -- (a small button: 22 across)
    end
    return low + PIP_SIZE / 2 + 2
end

local function PlaceRow(kit, y, step, n)
    for i = 1, n do
        kit:PlaceAt(icons[i], kit:Face((i - (n + 1) / 2) * step, y))
    end
    return n * step / 2
end

-- Merged on the dock pin: the label just outside the tent, the way its slots
-- fan out (past them, if any are out), reading outward.
local function PlaceMergedLabel(kit, angle)
    if not mergedLabel:IsShown() then return end
    local half = kit:KitHalfUnits()
    local fanned = false
    for _, btn in pairs(kit.slots) do
        if btn:IsShown() and not btn.closing and not btn.slot.rim then fanned = true end
    end
    local r = fanned and (half + kit.BTN + 14) or (half + 6)
    local c, sn = math.cos(math.rad(angle)), math.sin(math.rad(angle))
    local point = math.abs(c) >= math.abs(sn) and (c > 0 and "LEFT" or "RIGHT") or (sn > 0 and "BOTTOM" or "TOP")
    mergedLabel:ClearAllPoints()
    mergedLabel.placedX, mergedLabel.placedY = nil, nil
    mergedLabel:SetPoint(point, kit.kit, "CENTER", r * c, r * sn)
end

function Camp.Place(kit, angle)
    if not header or kit.trial or kit.edgeSide then return end
    if angle then PlaceMergedLabel(kit, angle) return end
    if not mode then glideFrom = nil return end
    if mode == "open" then
        local step = OPEN_SIZE + OPEN_GAP
        local half = PlaceRow(kit, ROW_Y, step, shownCount)
        kit:PlaceAt(header, kit:Face(-11, ROW_Y + OPEN_SIZE / 2 + HEADER_GAP)) -- (centred with the list button beside it)
        local cx = shownCount > 0 and (half + CHAT_SIZE / 2 + 2) or (header:GetWidth() / 2 + CHAT_SIZE / 2 + 6)
        local cy = shownCount > 0 and ROW_Y or (ROW_Y + OPEN_SIZE / 2 + HEADER_GAP)
        kit:PlaceAt(chat, kit:Face(cx, cy))
        local w = math.max(half * 2 + CHAT_SIZE, header:GetWidth(), 120) + 20
        local side = kit:Sideways()
        divider:SetSize(side and 16 or w, side and w or 16)
        divider.tex:SetSize(w, 16)
        divider.tex:SetRotation(side and math.pi / 2 or 0)
        kit:PlaceAt(divider, kit:Face(0, ROW_Y - OPEN_SIZE / 2 - 7))
    else
        -- "Campfire..." then the pips, then the announce button, centred under the tent.
        local y = -Below(kit)
        local step = PIP_SIZE + PIP_GAP
        local lw = mergedLabel:GetWidth()
        local total = lw + 6 + shownCount * step + (chat:IsShown() and (CHAT_SIZE + 2) or 0)
        local x = -total / 2
        kit:PlaceAt(mergedLabel, kit:Face(x + lw / 2, y)) -- (only re-anchored when its spot changes)
        x = x + lw + 6
        for i = 1, shownCount do kit:PlaceAt(icons[i], kit:Face(x + PIP_SIZE / 2 + (i - 1) * step, y)) end
        kit:PlaceAt(chat, kit:Face(x + shownCount * step + CHAT_SIZE / 2 + 2, y))
    end
    PlayGlide(kit)
end

-- On a screen edge the camp gets a section of its own, along the edge, where
-- it doesn't get lost among the columns: right of the tent on the top or
-- bottom edge, under everything on a side edge. The campfire's name (and its
-- list button) on top, then its slots in rows of five, the announce button
-- after the last. Open in a Kit Dock box the box's other kits are beside the
-- tent, so it goes past everything the kit has open instead (see PlaceSection).
local SECTION_GAP = 12  -- right of the tent, on the top or bottom edge
local SIDE_GAP = 26     -- under the kit, on a side edge
local BOX_GAP = 12      -- past the open slots, in a Kit Dock box
local BOX_INSET = 8     -- the box's inner edge, past the tent (Kit Core's PARKED_INSET)
local HEADER_H = 18

local function Along(side) return side == "top" or side == "bottom" end

-- What the section holds: slot count, icon size, header?, announce button?
-- hypothetical: what it would hold (for the dock's spacing).
local function SectionParts(kit, asOpen, hypothetical)
    if hypothetical then
        if not ns.AtCamp() or kit.db.shown == false then return 0 end
        if asOpen and not kit.db.campRow then return 0 end
        if not asOpen and not kit.db.campPips then return 0 end
        local n = SlotCount()
        return n, asOpen and OPEN_SIZE or PIP_SIZE, true, (kit.db.campAnnounce and (asOpen or n > 0)) and true or false
    end
    if not mode then return 0 end
    return shownCount, size, header:IsShown() or mergedLabel:IsShown(), chat:IsShown()
end

-- Its width and height, and the step from one slot to the next.
local function SectionSize(n, s, withHeader, withChat)
    if n == 0 and not withHeader and not withChat then return 0, 0, 0 end
    local step = s + (s == OPEN_SIZE and OPEN_GAP or PIP_GAP)
    local rowsN = n > 0 and math.ceil(n / PER_COL) or 0
    local w = math.min(n, PER_COL) * step + (withChat and (CHAT_SIZE + 4) or 0)
    if withHeader then w = math.max(w, header:IsShown() and (header:GetWidth() + 22) or mergedLabel:GetWidth()) end
    local h = (withHeader and HEADER_H or 0) + rowsN * step
    if rowsN == 0 and withChat then h = h + CHAT_SIZE end
    return w, h, step
end

-- The row for a closed kit in a box: past everything the box's kits show
-- (as far in as the deepest of them), level with the fire button.
local function PlaceBoxRow(kit)
    local step = OPEN_SIZE + OPEN_GAP
    local withChat = chat:IsShown()
    mergedLabel:SetWidth(mergedLabel.text:GetStringWidth() + 4)
    local w, h = SectionSize(shownCount, OPEN_SIZE, true, withChat)
    local pad = 8
    rowBox:SetSize(w + pad * 2, h + pad * 2)
    mergedLabel:ClearAllPoints()
    mergedLabel.placedX, mergedLabel.placedY = nil, nil
    mergedLabel:SetPoint("TOPLEFT", rowBox, "TOPLEFT", pad, -pad)
    local function Put(f, x, y)
        f:ClearAllPoints()
        f.placedX, f.placedY = nil, nil
        f:SetPoint("CENTER", rowBox, "TOPLEFT", x, y)
    end
    local top = -pad - HEADER_H
    for i = 1, shownCount do
        local r, c = math.floor((i - 1) / PER_COL), (i - 1) % PER_COL
        Put(icons[i], pad + OPEN_SIZE / 2 + c * step, top - OPEN_SIZE / 2 - r * step)
    end
    if withChat then
        local r, c = math.floor(math.max(shownCount - 1, 0) / PER_COL), shownCount > 0 and ((shownCount - 1) % PER_COL + 1) or 0
        Put(chat, pad + c * step + CHAT_SIZE / 2 + 2, top - OPEN_SIZE / 2 - r * step)
    end
    -- How far past the fire button the box's rows reach (in the row's own units).
    local side = kit.edgeSide
    local mine = rowBox:GetEffectiveScale()
    local function Edge(f, which)
        local v = f[which](f)
        return v and v * f:GetEffectiveScale() or nil
    end
    local WHICH = { top = "GetBottom", bottom = "GetTop", left = "GetRight", right = "GetLeft" }
    local deeper = (side == "top" or side == "right") and math.min or math.max
    local from = Edge(fireBtn, WHICH[side])
    local reach = from
    local D = kit.Dock
    if D and D.notices and from then
        for _, list in pairs(D.notices) do
            for _, f in ipairs(list) do
                if f:IsShown() then
                    local v = Edge(f, WHICH[side])
                    if v then reach = deeper(reach, v) end
                end
            end
        end
    end
    local off = from and (math.abs(reach - from) / mine + 6) or 6
    rowBox:ClearAllPoints()
    if side == "top" then rowBox:SetPoint("TOP", fireBtn, "BOTTOM", 0, -off)
    elseif side == "bottom" then rowBox:SetPoint("BOTTOM", fireBtn, "TOP", 0, off)
    elseif side == "left" then rowBox:SetPoint("LEFT", fireBtn, "RIGHT", off, 0)
    else rowBox:SetPoint("RIGHT", fireBtn, "LEFT", -off, 0) end
end

-- (no kit refresh: these work in combat too)
function Camp.ShowBoxRow(kit)
    if rowOpen or not boxedClosed then return end
    rowOpen = true
    for i, f in ipairs(icons) do f:SetShown(i <= shownCount) end
    mergedLabel:Show()
    chat:SetShown((kit.db.campAnnounce and shownCount > 0) and true or false)
    rowBox:Show()
    PlaceBoxRow(kit)
    Camp.Paint(kit)
end

function Camp.HideBoxRow()
    if not rowOpen then return end
    rowOpen = false
    rowBox:Hide()
    for _, f in ipairs(icons) do f:Hide() end
    mergedLabel:Hide()
    chat:Hide()
end

-- On an edge: the timers on the tent's rim, either side of it on the half
-- toward the middle of the screen. The sleeping bag: under the tent on
-- a side edge; on the top or bottom, beside the timers, further out.
local function RimSpots(kit)
    local side = kit.edgeSide
    local mid = Along(side) and 180 or 90
    local half = kit:KitHalfUnits()
    return mid, half + ns.DIAL_EDGE / 2 + 4, half + kit.BTN / 2 + 4
end

local function PlaceRim(kit)
    if kit.parked then return end -- (in a Kit Dock box: an extra column instead, see EdgeExtraCol)
    local mid, rd, rb = RimSpots(kit)
    local shown = {}
    for _, f in ipairs(ns.dials) do
        if f:IsShown() then shown[#shown + 1] = f end
    end
    -- On the half of the rim toward the middle of the screen (a kit on an
    -- edge tucks half off it until the mouse comes over): one each side of
    -- the tent, first on the left (or the top, on a side edge).
    local IN = { top = 270, bottom = 90, left = 0, right = 180 }
    local inward = IN[kit.edgeSide] or 270
    local spots = {}
    for _, d in ipairs({ -60, 60 }) do
        local a = math.rad(inward + d)
        spots[#spots + 1] = { rd * math.cos(a), rd * math.sin(a) }
    end
    if Along(kit.edgeSide) then
        table.sort(spots, function(p, q) return p[1] < q[1] end)
    else
        table.sort(spots, function(p, q) return p[2] > q[2] end)
    end
    for k, f in ipairs(shown) do
        local p = spots[k] or spots[#spots]
        kit:PlaceAt(f, p[1], p[2])
    end
    local bag = kit.slots.bag
    if bag then
        if Along(kit.edgeSide) then
            kit:PlaceAt(bag, -(rd + ns.DIAL_EDGE / 2 + 4 + kit.BTN / 2), 0)
        else
            kit:PlaceAt(bag, 0, -rb)
        end
    end
end

local function PlaceSection(kit)
    if kit.trial then return end -- (see BeforeRefresh)
    header:ClearAllPoints()
    header.placedX, header.placedY = nil, nil
    if not mode then return end
    if boxedClosed then
        kit:PlaceAt(fireBtn, 0, 0) -- (noted for the box's row)
        if rowOpen then PlaceBoxRow(kit) end
        return
    end
    local n, s, withHeader, withChat = SectionParts(kit, kit.open, false)
    local w, h, step = SectionSize(n, s, withHeader, withChat)
    local side, half = kit.edgeSide, kit:KitHalfUnits()
    local x0, y, dir
    local boxed = kit.parked and kit.open
    local centred = boxed and Along(side)
    if boxed then
        -- How far the open slots and timers reach, up and down.
        local low, high = -half, half
        local function Reaches(f, edge)
            if f:IsShown() and not f.closing and f.placedY then
                low = math.min(low, f.placedY - edge / 2)
                high = math.max(high, f.placedY + edge / 2)
            end
        end
        for _, btn in pairs(kit.slots) do Reaches(btn, kit.BTN) end
        for _, f in ipairs(ns.dials) do Reaches(f, ns.DIAL_EDGE) end
        if centred then
            -- Under the slots (over them on the bottom edge), centred on the tent.
            local across = math.min(n, PER_COL) * step + (withChat and (CHAT_SIZE + 4) or 0)
            x0, dir = -across / 2, 1
            y = side == "bottom" and (high + BOX_GAP + h) or (low - BOX_GAP)
        else
            -- Under the slots, starting past the box and the kits stacked in it.
            dir = side == "right" and -1 or 1
            x0, y = dir * (half + BOX_INSET / kit.db.scale), low - BOX_GAP
        end
    elseif Along(side) then
        x0, y, dir = half + SECTION_GAP, h / 2, 1 -- right of the tent, level with it
    else
        local low = -half
        for _, btn in pairs(kit.slots) do
            if btn:IsShown() and not btn.closing and btn.placedY then low = math.min(low, btn.placedY - kit.BTN / 2) end
        end
        for _, f in ipairs(ns.dials) do
            if f:IsShown() and f.placedY then low = math.min(low, f.placedY - ns.DIAL_EDGE / 2) end
        end
        dir = side == "right" and -1 or 1 -- inward, from the tent's outer side
        x0, y = -dir * half, low - SIDE_GAP
    end
    if withHeader then
        -- Open: the campfire's name and list button. Closed: "Campfire...".
        local top = header:IsShown() and header or mergedLabel
        local room = top == header and 22 or 0 -- (the list button sits on the header's right)
        top:ClearAllPoints()
        top.placedX, top.placedY = nil, nil
        if centred then
            top:SetPoint("TOP", kit.kit, "CENTER", -room / 2, y)
        elseif dir == 1 then
            top:SetPoint("TOPLEFT", kit.kit, "CENTER", x0, y)
        else
            top:SetPoint("TOPRIGHT", kit.kit, "CENTER", x0 - room, y)
        end
        y = y - HEADER_H
    end
    for i = 1, n do
        local r, c = math.floor((i - 1) / PER_COL), (i - 1) % PER_COL
        kit:PlaceAt(icons[i], x0 + dir * (s / 2 + c * step), y - s / 2 - r * step)
    end
    if withChat then
        if n > 0 then
            local r, c = math.floor((n - 1) / PER_COL), (n - 1) % PER_COL
            kit:PlaceAt(chat, x0 + dir * ((c + 1) * step + CHAT_SIZE / 2 + 2), y - s / 2 - r * step)
        else
            kit:PlaceAt(chat, x0 + dir * CHAT_SIZE / 2, y - CHAT_SIZE / 2)
        end
    end
end

---------------------------------------------------------------------------
-- Hooking into Kit Core's layout (methods on this kit only)
---------------------------------------------------------------------------

local function HookLayout(kit)
    local PlaceEdge, EdgeExtent, Reach = kit.PlaceEdge, kit.EdgeExtent, kit.Reach

    function kit:PlaceEdge()
        PlaceEdge(self)
        PlaceRim(self)
        PlaceSection(self)
    end

    -- Room along the edge for the rim pieces and the camp's section.
    function kit:EdgeExtent(side, asOpen)
        local ext = EdgeExtent(self, side, asOpen)
        local any = self.slots.food
        local k = any and (any:GetEffectiveScale() / UIParent:GetEffectiveScale()) or self.db.scale
        local half = self:KitHalfUnits()
        local rd, rb = half + ns.DIAL_EDGE / 2 + 4, half + self.BTN / 2 + 4
        local dialsOn = false
        for _, f in ipairs(ns.dials) do
            if (asOpen and self.db[f.def.showSetting] ~= false) or f.wouldShow then dialsOn = true end
        end
        local bag = self.slots.bag
        local bagOn = bag and ((asOpen and not bag.hidden) or bag.wouldShow) or false
        local w, h = SectionSize(SectionParts(self, asOpen, true))
        local need
        if Along(side) then
            local left = math.max(half, dialsOn and (rd + ns.DIAL_EDGE / 2) or 0, bagOn and (rd + ns.DIAL_EDGE / 2 + 4 + self.BTN) or 0)
            local right = math.max(w > 0 and (half + SECTION_GAP + w) or half, dialsOn and (rd + ns.DIAL_EDGE / 2) or 0)
            need = 2 * math.max(left, right)
        else
            local up = dialsOn and (rd + ns.DIAL_EDGE / 2) or half
            local low = math.max(ext / k / 2, half, bagOn and (rb + self.BTN / 2) or 0, dialsOn and (rd + ns.DIAL_EDGE / 2) or 0)
            need = 2 * math.max(up, h > 0 and (low + SIDE_GAP + h + 8) or low)
        end
        return math.max(ext, need * k)
    end

    -- Keep room on screen for the open camp row and its header.
    function kit:Reach()
        local l, r, t, b = Reach(self)
        if not (self.db.campRow and ns.AtCamp()) then return l, r, t, b end
        local s = self.db.scale
        local w = math.max(SlotCount() * (OPEN_SIZE + OPEN_GAP) / 2 + CHAT_SIZE + 4, 80)
        local top = ROW_Y + OPEN_SIZE / 2 + HEADER_GAP + 8
        for _, p in ipairs({ { -w, top }, { w, top } }) do
            local x, y = self:Face(p[1], p[2])
            l = math.max(l, -x * s)
            r = math.max(r, x * s)
            t = math.max(t, y * s)
            b = math.max(b, -y * s)
        end
        return l, r, t, b
    end
end

---------------------------------------------------------------------------
-- Announcing the camp in General chat
---------------------------------------------------------------------------

-- A map pin link to the camp's spot, for players without the kit. Announcing
-- also pins the camp (CampNet's PinSpot), so the link and every kit user's
-- tent pin show the same place. Built like the game's own "share pin" link,
-- without moving your own map pin.
local function MapPin()
    if not C_Map then return nil end
    local map, x, y
    if ns.CampNet and ns.CampNet.PinSpot then map, x, y = ns.CampNet.PinSpot() end
    if not map then
        -- Not at a camp the kit knows: where you're standing.
        if not (C_Map.GetBestMapForUnit and C_Map.GetPlayerMapPosition) then return nil end
        map = C_Map.GetBestMapForUnit("player")
        if not map or U.Sealed(map) then return nil end
        local pos = C_Map.GetPlayerMapPosition(map, "player")
        if not pos then return nil end
        x, y = pos:GetXY()
    end
    if not x or U.Sealed(x) or U.Sealed(y) then return nil end
    if C_Map.CanSetUserWaypointOnMap and not C_Map.CanSetUserWaypointOnMap(map) then return nil end
    return ("|cffffff00|Hworldmap:%d:%d:%d|h[%s]|h|r"):format(map, math.floor(x * 10000 + 0.5),
        math.floor(y * 10000 + 0.5), MAP_PIN_HYPERLINK or "Map Pin Location")
end

function Camp.Message()
    local pin = MapPin()
    local head = "Camping Kit: " .. FireName(camp.fire) .. (pin and (" at " .. pin) or "")
    local tail = camp.fire and (" (" .. #camp.list .. "/" .. camp.fire.slots .. ")") or ""
    if camp.full then tail = tail .. " Full." end
    if Camp.IsViolet() then tail = tail .. " Violet Flames: 2-hour benefits." end
    PruneWants()
    local wants = {}
    for _, o in ipairs(camp.wants) do wants[#wants + 1] = ObjName(o) end
    if #wants > 0 then tail = tail .. " Looking for: " .. table.concat(wants, ", ") .. "." end
    local names = {}
    for _, o in ipairs(camp.list) do names[#names + 1] = ObjName(o) end
    -- Chat messages are capped at 255 bytes: drop names from the end to fit.
    while true do
        local text = #names > 0 and (head .. ": " .. table.concat(names, ", ") .. tail) or (head .. tail)
        if #text <= 255 or #names == 0 then return text:sub(1, 255) end
        names[#names] = nil
    end
end

function Camp.Announce(kit)
    local id = ns.CampNet and ns.CampNet.GeneralChannel and ns.CampNet.GeneralChannel()
    if not id then
        kit:Print("Couldn't find General chat to post in.", true)
        return
    end
    local send = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
    if send then send(Camp.Message(), "CHANNEL", nil, id) end
end

---------------------------------------------------------------------------
-- "This campfire...": the full list, from the tent's right-click menu
---------------------------------------------------------------------------

local ROW_H = 24
local WANT_SIZE, WANT_PER_ROW = 26, 9
local rows = {}

local function MakeRow(i)
    local r = CreateFrame("Frame", nil, panel)
    r:SetSize(272, ROW_H)
    r:SetPoint("TOPLEFT", panel, "TOPLEFT", 14, -58 - (i - 1) * ROW_H)
    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetSize(22, 22)
    r.icon:SetPoint("LEFT")
    r.dash = r:CreateTexture(nil, "ARTWORK")
    r.dash:SetSize(22, 22)
    r.dash:SetPoint("LEFT")
    r.dash:SetTexture(MEDIA .. "ring_dashed_64", nil, nil, "LINEAR")
    r.name = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.name:SetPoint("LEFT", r.icon, "RIGHT", 8, 0)
    r.name:SetPoint("RIGHT")
    r.name:SetJustifyH("LEFT")
    r.name:SetWordWrap(false)
    rows[i] = r
    return r
end

-- The same frame as the game's right-click menus (the tent's own menu is
-- one), so the panel it opens looks like part of it: the game's menu style
-- itself where the client has it, else its menu background art, else a plain
-- dark box with a thin grey edge.
local function MenuSkin(f)
    if MenuStyle1Mixin and MenuStyle1Mixin.Generate and Mixin then
        local style = CreateFrame("Frame", nil, f)
        style:SetAllPoints()
        style:SetFrameLevel(math.max(0, f:GetFrameLevel() - 1))
        Mixin(style, MenuStyle1Mixin)
        if style.OnLoad then pcall(style.OnLoad, style) end
        if pcall(style.Generate, style) and style:GetNumRegions() > 0 then return end
        style:Hide()
    end
    local atlas = "common-dropdown-bg"
    if C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas) then
        local bg = f:CreateTexture(nil, "BACKGROUND")
        bg:SetAtlas(atlas)
        bg:SetPoint("TOPLEFT", -10, 10)
        bg:SetPoint("BOTTOMRIGHT", 10, -12)
        return
    end
    if f.SetBackdrop then
        f:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12,
            insets = { left = 3, right = 3, top = 3, bottom = 3 },
        })
        f:SetBackdropColor(0.05, 0.05, 0.09, 0.95)
        f:SetBackdropBorderColor(0.36, 0.37, 0.43)
    end
end

local function MakePanel(kit)
    panel = CreateFrame("Frame", "CampingKitCampPanel", UIParent, "BackdropTemplate")
    panel:SetSize(300, 200)
    panel:SetPoint("CENTER", UIParent, "CENTER", 0, 120)
    panel:SetFrameStrata("DIALOG")
    panel:SetClampedToScreen(true)
    panel:SetMovable(true)
    panel:EnableMouse(true)
    panel:RegisterForDrag("LeftButton")
    panel:SetScript("OnDragStart", panel.StartMoving)
    panel:SetScript("OnDragStop", panel.StopMovingOrSizing)
    MenuSkin(panel)
    panel.title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    panel.title:SetPoint("TOPLEFT", 14, -12)
    panel.title:SetText("This campfire")
    local close = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 2, 2)
    panel.announce = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    panel.announce:SetSize(92, 22)
    panel.announce:SetPoint("TOPRIGHT", -30, -6)
    panel.announce:SetText("Announce")
    panel.announce:SetScript("OnClick", function() Camp.Announce(kit) end)
    panel.fire = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    panel.fire:SetPoint("TOPLEFT", 14, -38)
    panel.count = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    panel.count:SetPoint("TOPRIGHT", -14, -38)
    panel.foot = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    panel.foot:SetWidth(272)
    panel.foot:SetJustifyH("LEFT")
    panel.hint = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    panel.hint:SetWidth(272)
    panel.hint:SetJustifyH("LEFT")
    panel.hint:SetText("Mouse over the campfire and the camp's objects to fill this in. Sit by the fire for about a minute to pick up the bonuses.")

    -- Looking for: a button per object that can be asked for.
    panel.wantLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    panel.wantLabel:SetJustifyH("LEFT")
    panel.wantNote = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    panel.wantNote:SetPoint("LEFT", panel.wantLabel, "RIGHT", 8, 0)
    panel.wants = {}
    for i, o in ipairs(WantChoices()) do
        local b = CreateFrame("Button", nil, panel)
        b:SetSize(WANT_SIZE, WANT_SIZE)
        b.object = o
        b.icon = b:CreateTexture(nil, "ARTWORK")
        b.icon:SetPoint("TOPLEFT", 2, -2)
        b.icon:SetPoint("BOTTOMRIGHT", -2, 2)
        b.icon:SetTexture((o.item and U.ItemIcon(o.item)) or U.SpellIcon(o.spell) or 134400)
        local mask = b:CreateMaskTexture()
        mask:SetTexture(MEDIA .. "circle_mask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        mask:SetAllPoints(b.icon)
        b.icon:AddMaskTexture(mask)
        b.ring = b:CreateTexture(nil, "OVERLAY")
        b.ring:SetAllPoints()
        b.ring:SetTexture(MEDIA .. "ring_prof_64", nil, nil, "LINEAR")
        b:SetHighlightTexture(MEDIA .. "glow_ring", "ADD")
        b:RegisterForClicks("LeftButtonUp")
        b:SetScript("OnClick", function(self) Camp.SetWant(kit, self.object, not Wanted(self.object)) end)
        b:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(ObjName(self.object))
            local prof = ProfLabel(self.object)
            if prof then GameTooltip:AddLine(prof, GREY[1], GREY[2], GREY[3]) end
            AddEffect(self.object)
            local competes = Camp.Competes(self.object)
            if competes then GameTooltip:AddLine(COMPETE:format(competes), ORANGE[1], ORANGE[2], ORANGE[3], true) end
            GameTooltip:AddLine(Wanted(self.object) and "Click: stop asking for it"
                or "Click: ask for it. Kit users on your layer see it on this camp's map pin.", 0.3, 1, 0.4, true)
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        panel.wants[i] = b
    end
    panel:Hide()
    if UISpecialFrames then table.insert(UISpecialFrames, "CampingKitCampPanel") end
end

FillPanel = function(kit)
    PruneWants()
    local n = math.max(camp.fire and camp.fire.slots or (#camp.list + #camp.wants), #camp.list)
    panel.fire:SetText(FireName(camp.fire))
    local count = camp.fire and (#camp.list .. " of " .. camp.fire.slots .. " known") or (#camp.list .. " seen")
    if camp.full then count = count .. ", full" end
    panel.count:SetText(count)
    local benefits = ns.auras.benefits
    for i = 1, math.max(n, #rows) do
        local r = rows[i] or (i <= n and MakeRow(i))
        if r then
            local o = camp.list[i]
            r:SetShown(i <= n)
            if o then
                -- A bonus you won't get (you have the class buff it doesn't
                -- stack with) is greyed, and says why in place of its effect.
                local clash = ClashFor(kit, o)
                r.icon:SetTexture((o.item and U.ItemIcon(o.item)) or U.SpellIcon(o.spell) or 134400)
                r.icon:SetDesaturated(clash and true or false)
                r.icon:SetAlpha(1)
                r.icon:Show()
                r.dash:Hide()
                local effect = Camp.Effect(o)
                local note = clash and ("  |cffff8c40" .. clash.name .. " on you|r")
                    or (effect and ("  |cff9e9e9e" .. effect .. "|r")) or ""
                r.name:SetText(ObjName(o) .. note)
            else
                -- An empty slot: what's being looked for, faded, else "Not seen yet".
                local w = camp.wants[i - #camp.list]
                r.dash:Show()
                if w then
                    r.icon:SetTexture((w.item and U.ItemIcon(w.item)) or U.SpellIcon(w.spell) or 134400)
                    r.icon:SetDesaturated(true)
                    r.icon:SetAlpha(0.5)
                    r.icon:Show()
                    r.name:SetText("|cffffd100Looking for:|r " .. ObjName(w))
                else
                    r.icon:Hide()
                    r.name:SetText("|cff9e9e9eNot seen yet|r")
                end
            end
        end
    end
    local bottom = -58 - n * ROW_H - 8

    -- Looking for
    PruneWants()
    local open = OpenSlots() > 0
    panel.wantLabel:ClearAllPoints()
    panel.wantLabel:SetPoint("TOPLEFT", 14, bottom - 2)
    panel.wantLabel:SetText("Looking for")
    panel.wantNote:SetText(open and (#camp.wants > 0 and "" or "click to ask") or "no room left")
    local k = 0
    for _, b in ipairs(panel.wants) do
        local o = b.object
        local show = open and not Has(o)
        b:SetShown(show)
        if show then
            local col, row = k % WANT_PER_ROW, math.floor(k / WANT_PER_ROW)
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", 14 + col * (WANT_SIZE + 4), bottom - 18 - row * (WANT_SIZE + 4))
            local on = Wanted(o)
            b.icon:SetDesaturated(not on)
            b.icon:SetAlpha(on and 1 or 0.55)
            b.ring:SetVertexColor(on and 1 or 0.55, on and 0.82 or 0.55, on and 0.3 or 0.55)
            k = k + 1
        end
    end
    local wantRows = k > 0 and math.ceil(k / WANT_PER_ROW) or 0
    bottom = bottom - 18 - wantRows * (WANT_SIZE + 4) - 6

    local a = benefits
    local left = a and a.exp and a.exp > 0 and (a.exp - GetTime()) or nil
    panel.foot:ClearAllPoints()
    panel.foot:SetPoint("TOPLEFT", 14, bottom)
    local violet = Camp.IsViolet()
    panel.foot:SetText((violet and "|cffb873ffViolet Flames: benefits last 2 hours|r\n" or "")
        .. "Camp Benefits: " .. (left and left > 0 and U.FormatLeft(left) or (a and "on" or "not yet")))
    panel.hint:ClearAllPoints()
    panel.hint:SetPoint("TOPLEFT", panel.foot, "BOTTOMLEFT", 0, -6)
    panel:SetHeight(-bottom + 18 + (violet and 12 or 0) + panel.hint:GetStringHeight() + 18)
end

function Camp.OpenPanel(kit)
    if not panel then MakePanel(kit) end
    FillPanel(kit)
    panel:Show()
end

function Camp.TogglePanel(kit)
    if panel and panel:IsShown() then panel:Hide() else Camp.OpenPanel(kit) end
end

---------------------------------------------------------------------------
-- Setting up
---------------------------------------------------------------------------

function Camp.Init(kit)
    MakeFrames(kit)
    HookLayout(kit)
    BuildCatalog()
    if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType
        and Enum.TooltipDataType.Object then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Object, OnObjectTooltip)
    end
end
