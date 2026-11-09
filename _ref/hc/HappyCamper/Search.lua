-- Happy Camper. Copyright (c) 2026 Torridon. All rights reserved; see LICENSE.
local _, ns = ...
local L = ns.L

-- Find a camp: pick the buffs you want and how many a camp must have (Any,
-- 2+, ... All). The strip is always in the map dock, under the camp bar; with
-- buffs picked, only camps that match show on the map and the camp bar.
-- Clicking a buff again asks for a higher tier of its object.
--
-- db.search.wants[skillLine] is true (any tier) or 2 or 3: the lowest tier
-- of that buff's object a camp must have.

local Search = {}
ns.Search = Search

-- Logic --------------------------------------------------------------------------

-- The lowest tier wanted for a buff: 1 for any tier, 0 if it isn't picked.
function Search:MinTier(skillLine)
    local want = ns.db.search.wants[skillLine]
    if type(want) == "number" then return want end
    return want and 1 or 0
end

-- A buff's highest tier (Cooking has no tier 1, so tiers are looked up one by one).
local function TopTier(profession)
    for tier = 3, 1, -1 do
        if profession.objects[tier] then return tier end
    end
    return 1
end

-- What a click on a buff picks next: any tier, then each higher tier it has
-- an object for, then nothing (nil).
function Search:NextPick(skillLine)
    local current = self:MinTier(skillLine)
    if current == 0 then return true end
    local profession = ns.PROFESSION_BY_ID[skillLine]
    for tier = math.max(current + 1, 2), 3 do
        if profession.objects[tier] then return tier end
    end
end

-- The best tier of a buff's object a camp is known to have: from Camp
-- Benefits or the objects seen placed there. A camp known to give the buff
-- with neither counts as tier 1; 0 if it doesn't give it.
function Search:CampTier(camp, skillLine)
    if not (camp.professions and camp.professions[skillLine]) then return 0 end
    local tier = (camp.equipment or {})[skillLine] or 1
    for spellID in pairs(camp.objects or {}) do
        local key, _, objectSkill = ns.ObjectInfo(spellID)
        if objectSkill == skillLine then tier = math.max(tier, select(4, ns.ObjectByName(key)) or 1) end
    end
    return tier
end

-- Whether a camp has a wanted buff at the tier wanted (or better).
function Search:CampHas(camp, skillLine)
    local wanted = self:MinTier(skillLine)
    if wanted == 0 or not (camp.professions and camp.professions[skillLine]) then return false end
    return wanted <= 1 or self:CampTier(camp, skillLine) >= wanted
end

-- Find a camp settings from a backup code, kept only where they make sense:
-- picks of buffs it shows, each any tier (true) or a tier the buff has.
function Search:CleanSettings(from)
    local clean = { enabled = from.enabled ~= false, wants = {}, minimum = 1 }
    local minimum = from.minimum
    if type(minimum) == "number" and minimum >= 1 and minimum <= #ns.PROFESSIONS then clean.minimum = math.floor(minimum) end
    if type(from.wants) == "table" then
        for skillLine, want in pairs(from.wants) do
            local profession = ns.PROFESSION_BY_ID[skillLine]
            if profession and not profession.notSearchable then
                if want == true or want == 1 then
                    clean.wants[skillLine] = true
                elseif (want == 2 or want == 3) and profession.objects[want] then
                    clean.wants[skillLine] = want
                end
            end
        end
    end
    return clean
end

-- A search is on while the Find a camp strip shows and buffs are picked; never
-- in Standard mode (Mode.lua), which has no Find a camp.
function Search:IsActive()
    local search = ns.db.search
    return ns.IsEnhanced() and search.enabled and next(search.wants) ~= nil and self:IsOpen()
end

function Search:WantedCount()
    return ns.Count(ns.db.search.wants)
end

-- How many of the wanted buffs a camp needs, clamped to how many are wanted.
function Search:Required()
    return math.max(1, math.min(ns.db.search.minimum, self:WantedCount()))
end

-- Returns matches, have: whether the camp passes, and how many wanted buffs it
-- has (each at the tier wanted, or better).
function Search:Match(camp)
    local have = 0
    for skillLine in pairs(ns.db.search.wants) do
        if self:CampHas(camp, skillLine) then have = have + 1 end
    end
    return have >= self:Required(), have
end

-- Only camps the map can show count (not ones hidden on another layer).
function Search:MatchCount()
    local count = 0
    for _, camp in pairs(ns.Camps:All()) do
        if ns.Camps:Visible(camp) and self:Match(camp) then count = count + 1 end
    end
    return count
end

-- How many of the picks a camp needs, for the camp bar's count: "(all 2)" or
-- "(at least 2 of 3)"; nil with one buff picked, or Any.
function Search:ThresholdText()
    local wanted, required = self:WantedCount(), self:Required()
    if wanted < 2 or required == 1 then return nil end
    if required == wanted then return format(L["(all %d)"], wanted) end
    return format(L["(at least %d of %d)"], required, wanted)
end

-- Buff name, what it does (at your level), where it comes from and what it
-- doesn't stack with.
function ns.AddProfessionTooltip(tooltip, profession)
    tooltip:AddLine(profession.buff, 1, 0.82, 0)
    ns.AddBuffSize(tooltip, profession)
    -- Named in the client's language (Cooking has no tier 1 object).
    local objects = {}
    for tier = 1, 3 do
        if profession.objects[tier] then objects[#objects + 1] = ns.ObjectName(profession.id, tier) end
    end
    if #objects > 0 then
        tooltip:AddLine(format("%s: %s", profession.name, table.concat(objects, ", ")), 0.7, 0.7, 0.7, true)
    end
    if profession.conflicts then
        tooltip:AddLine(format(L["Doesn't stack with %s"], profession.conflicts), 1, 0.5, 0.5, true)
    end
end

local function Changed()
    ns.OnCampsChanged()
    Search:RefreshPanel()
end

-- Strip ------------------------------------------------------------------------------

-- Rows, from the top: how many of the picks a camp needs, or a hint; the buff
-- chips; the preset buttons.
local ROW2_Y = -14       -- the middle of the top row: the hint, or how many a camp needs
local CHIPS_TOP = -38   -- room above the rings for the stars
local CHIP_HEIGHT = 80   -- the ringed icon, and room for a label on two lines
local PRESETS_TOP = CHIPS_TOP - CHIP_HEIGHT - 2
local HEIGHT = 146       -- down to just under the preset buttons
Search.HEIGHT = HEIGHT
local PAD = 18
local CHIP_MAX_WIDTH = 86
local ICON = 40         -- the round icon inside its gold ring
-- The talent tree's round buttons: a thin gold ring (green once picked) around
-- an icon cut round by its mask, sharp at any size. The ring is 50 for a 40
-- icon there. Older art (the minimap buttons' ring) if those atlases are missing.
local RING = ICON * 1.25
local RING_GOLD, RING_PICKED = "talents-node-circle-gray", "talents-node-circle-green"
-- The plain ring tinted the warm bronze-gold of the map window's portrait ring.
local BRONZE = { 1, 0.78, 0.48 }

local ICON_MASK = "talents-node-circle-mask"

-- A picked buff's tier: lit stars just above its ring (clear of it, so they're easy to see), as the profession
-- window shows recipe ranks (1 any tier, 2 tier 2 or better, 3 tier 3). The
-- atlas is 20 by 19. Small gold dots if it's missing.
local STAR = "tradeskills-star"
local STAR_W, STAR_H = 12, 11
local STAR_X = { { 0 }, { -7, 7 }, { -14, 0, 14 } } -- across the ring's top, by how many show
local STAR_RADIUS = RING / 2 + STAR_H / 2 + 1 -- just outside the ring's edge

-- A chip's ring: bronze, or green while picked.
local function SetRing(chip, picked)
    if not ns.Style:HasAtlas(RING_PICKED) then return end
    chip.border:SetAtlas(picked and RING_PICKED or RING_GOLD)
    if picked then chip.border:SetVertexColor(1, 1, 1) else chip.border:SetVertexColor(BRONZE[1], BRONZE[2], BRONZE[3]) end
end

local ORANGE = { 0.9, 0.55, 0.2 }

local function SetWanted(skillLine, wanted)
    ns.db.search.wants[skillLine] = wanted or nil
    ns.db.search.enabled = true
    Changed()
end

-- One-click picks of the buffs for a kind of character (by skill line):
-- camps with any of them match.
Search.PRESETS = {
    { name = "Melee", skills = { 164, 186, 393, 129, 356 } },         -- Strength, attack power, crit, Stamina, all stats
    { name = "Caster", skills = { 171, 182, 197, 393, 129, 356 } },   -- Mana regen, Intellect, Spirit, crit, Stamina, all stats
    { name = "Balanced", skills = { 129, 356, 333, 393 } },           -- Stamina, all stats, armor, crit
}

function Search:ApplyPreset(preset)
    wipe(ns.db.search.wants)
    for _, skillLine in ipairs(preset.skills) do ns.db.search.wants[skillLine] = true end
    ns.db.search.minimum = 1
    ns.db.search.enabled = true
    Changed()
end

-- "Strength, Attack power, Crit..." for a preset's tooltip.
local function PresetBuffs(preset)
    local names = {}
    for _, skillLine in ipairs(preset.skills) do names[#names + 1] = ns.PROFESSION_BY_ID[skillLine].buff end
    return table.concat(names, ", ")
end

local function CreateChip(parent, profession)
    local chip = CreateFrame("Button", nil, parent)
    chip:SetSize(CHIP_MAX_WIDTH, CHIP_HEIGHT)
    chip.profession = profession

    -- A round icon in a thin gold ring, like the talent tree's round buttons.
    chip.icon = chip:CreateTexture(nil, "ARTWORK")
    chip.icon:SetSize(ICON, ICON)
    chip.icon:SetPoint("TOP", 0, -(RING - ICON) / 2 - 2)
    chip.icon:SetTexture(profession.buffIcon)
    -- Zoomed in past the dark edge every icon has, so it doesn't show at the circle's sides.
    chip.icon:SetTexCoord(0.1, 0.9, 0.1, 0.9)
    local mask = chip.CreateMaskTexture and chip:CreateMaskTexture()
    if mask then
        mask:SetAllPoints(chip.icon)
        if ns.Style:HasAtlas(ICON_MASK) then
            mask:SetAtlas(ICON_MASK)
        else
            mask:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        end
        chip.icon:AddMaskTexture(mask)
    end
    chip.border = chip:CreateTexture(nil, "OVERLAY")
    chip.border:SetSize(RING, RING)
    chip.border:SetPoint("CENTER", chip.icon, "CENTER")
    if ns.Style:HasAtlas(RING_GOLD) then
        chip.border:SetAtlas(RING_GOLD)
        chip.border:SetVertexColor(BRONZE[1], BRONZE[2], BRONZE[3])
    else
        -- The minimap buttons' ring: drawn for a 20-pixel disc at (7, -5) in 53.
        local scale = ICON / 20
        chip.border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
        chip.border:ClearAllPoints()
        chip.border:SetSize(53 * scale, 53 * scale)
        chip.border:SetPoint("TOPLEFT", chip.icon, "TOPLEFT", -7 * scale, 5 * scale)
    end

    -- Picked: the ring turns green, with a soft green glow around it.
    chip.ring = chip:CreateTexture(nil, "BACKGROUND")
    chip.ring:SetSize(RING * 1.6, RING * 1.6)
    chip.ring:SetPoint("CENTER", chip.icon, "CENTER")
    if ns.Style:HasAtlas("talents-node-circle-greenglow") then
        chip.ring:SetAtlas("talents-node-circle-greenglow")
    else
        chip.ring:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
        chip.ring:SetBlendMode("ADD")
        chip.ring:SetVertexColor(0.3, 1, 0.3)
    end

    -- Hovered: a faint light over the icon, cut round like it.
    chip.hover = chip:CreateTexture(nil, "HIGHLIGHT")
    chip.hover:SetAllPoints(chip.icon)
    chip.hover:SetColorTexture(1, 1, 1, 0.15)
    if mask then chip.hover:AddMaskTexture(mask) end

    chip.label = ns.Style:Text(chip, "GameFontHighlightSmall", profession.buff)
    chip.label:SetPoint("TOP", chip.border, "BOTTOM", 0, -2)
    chip.label:SetWordWrap(false)

    -- Picked: one to three stars for the tier, made once and placed by UpdateChip.
    chip.stars = {}
    local starAtlas = ns.Style:HasAtlas(STAR)
    for i = 1, 3 do
        local star = chip:CreateTexture(nil, "OVERLAY", nil, 7)
        if starAtlas then
            star:SetAtlas(STAR)
            star:SetSize(STAR_W, STAR_H)
        else
            star:SetColorTexture(1, 0.82, 0)
            star:SetSize(5, 5)
        end
        star:Hide()
        chip.stars[i] = star
    end

    -- Click: any tier, then each higher tier, then off. Right-click: off.
    chip:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    chip:SetScript("OnClick", function(self, button)
        if button == "RightButton" then
            SetWanted(profession.id, nil)
        else
            SetWanted(profession.id, Search:NextPick(profession.id))
        end
    end)
    ns.Style:CustomTooltip(chip, "ANCHOR_TOP", function(tooltip)
        ns.AddProfessionTooltip(tooltip, profession)
        local tier = Search:MinTier(profession.id)
        if tier > 0 then tooltip:AddLine(Search:PickText(profession, tier), 0.4, 1, 0.4, true) end
        if ns.Style:ShowHelp() then tooltip:AddLine(" ") end
        local hint = L["Click to look for this"]
        if tier > 0 then
            hint = Search:NextPick(profession.id) and L["Click for a higher tier. Right-click to stop looking for this."]
                or L["Click to stop looking for this"]
        end
        ns.Style:AddHint(tooltip, hint, true)
    end, true)
    return chip
end

-- Shows count stars along the top of a chip's ring, centred on it and
-- following its curve (one in the middle, two side by side, three in an arc).
local function ShowStars(chip, count)
    local places = STAR_X[count]
    for i, star in ipairs(chip.stars) do
        local x = places and places[i]
        if x then
            star:ClearAllPoints()
            star:SetPoint("CENTER", chip.icon, "CENTER", x, math.sqrt(STAR_RADIUS * STAR_RADIUS - x * x))
        end
        star:SetShown(x ~= nil)
    end
end

-- The pick, for a chip's tooltip: "Any tier", "Tier 2 or better: Anvil,
-- Master Forge" or "Tier 3: Master Forge" (objects named in the client's language).
function Search:PickText(profession, tier)
    if tier <= 1 then return L["Any tier"] end
    local names = {}
    for each = tier, 3 do
        if profession.objects[each] then names[#names + 1] = ns.ObjectName(profession.id, each) end
    end
    return format(tier < TopTier(profession) and L["Tier %d or better: %s"] or L["Tier %d: %s"], tier, table.concat(names, ", "))
end

local function UpdateChip(chip)
    local profession = chip.profession
    local tier = Search:MinTier(profession.id)
    local selected = tier > 0
    chip.ring:SetShown(selected)
    SetRing(chip, selected)
    chip.icon:SetDesaturated(not selected)
    chip.icon:SetAlpha(selected and 1 or 0.55)
    chip.label:SetTextColor(selected and 0.5 or 0.65, selected and 1 or 0.65, selected and 0.5 or 0.65)
    -- The lowest object that counts: the tier 1 one for any tier (and unpicked).
    local higher = tier > 1 and profession.objectIcons[tier] ~= nil
    chip.icon:SetTexture(higher and profession.objectIcons[tier] or profession.buffIcon)
    ShowStars(chip, math.min(tier, 3))
end

-- A small flat button (thresholds, Clear, the quick picks).
local function CreateFlatButton(parent, width, text, onClick)
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(width, 18)
    button.bg = button:CreateTexture(nil, "BACKGROUND")
    button.bg:SetAllPoints()
    button.text = ns.Style:Text(button, "GameFontHighlightSmall", text)
    button.text:SetPoint("CENTER")
    button.hover = button:CreateTexture(nil, "HIGHLIGHT")
    button.hover:SetAllPoints()
    button.hover:SetColorTexture(1, 1, 1, 0.1)
    button:SetScript("OnClick", onClick)
    return button
end

-- Makes a flat button wide enough for its text (a translation can be longer),
-- never narrower than least.
local function FitFlat(button, least)
    button:SetWidth(math.max(least, math.ceil(ns.Style:TextWidth(button.text)) + 14))
end

local function SetFlatSelected(button, selected)
    button.selected = selected
    if selected then
        button.bg:SetColorTexture(ORANGE[1], ORANGE[2], ORANGE[3], 0.85)
    else
        button.bg:SetColorTexture(1, 1, 1, 0.08)
    end
    button.text:SetTextColor(selected and 1 or 0.8, selected and 1 or 0.8, selected and 1 or 0.8)
end

-- Every frame while the map is open (MapBar:Watch): the buff chips laid out
-- again for a new width, and on the map's first frame open (opened), the
-- strip shows what's picked now.
function Search:Watch(opened)
    local bar = self.bar
    if not bar or not bar:IsShown() then return end
    if opened then self:RefreshPanel() end
    local width = bar:GetWidth()
    if width ~= bar.laidWidth then
        bar.laidWidth = width
        self:LayoutChips()
    end
end

function Search:CreateStrip()
    local bar = CreateFrame("Frame", "HappyCamperSearch", WorldMapFrame)
    bar:SetHeight(HEIGHT)
    bar:SetFrameStrata("HIGH")
    bar:SetFrameLevel(WorldMapFrame.BorderFrame:GetFrameLevel() + 12)
    bar:EnableMouse(true)
    bar:Hide()

    -- The top row: with two or more buffs picked, how many of them a camp needs
    -- (UpdateThresholds adds the buttons); with none, a hint. How many camps
    -- match is on the camp bar above (MapBar).
    bar.needs = ns.Style:Text(bar, "GameFontNormalSmall", L["Needs:"])
    bar.needs:SetPoint("LEFT", bar, "TOPLEFT", PAD, ROW2_Y)
    bar.thresholds = {}
    bar.hint = ns.Style:Text(bar, "GameFontHighlightSmall",
        L["Pick the buffs you want. Only camps that have them show on the map."], "CENTER")
    bar.hint:SetTextColor(0.67, 0.67, 0.67)
    bar.hint:SetWordWrap(true)
    bar.hint:SetMaxLines(2)
    bar.hint:SetPoint("LEFT", bar, "TOPLEFT", PAD, ROW2_Y)
    bar.hint:SetPoint("RIGHT", bar, "TOPRIGHT", -PAD, ROW2_Y)

    -- Bottom row: one chip per buff.
    bar.chips = {}
    for _, profession in ipairs(ns.PROFESSIONS) do
        if not profession.notSearchable then
            bar.chips[#bar.chips + 1] = CreateChip(bar, profession)
        end
    end

    -- Under the chips: Melee, Caster and Balanced, each picking its buffs in one
    -- click (lit while the picks are exactly those), and Clear after them, all
    -- one size (wide enough for the longest translation), centred as a row.
    local presets = CreateFrame("Frame", nil, bar)
    presets:SetPoint("TOP", bar, "TOP", 0, PRESETS_TOP)
    local label = ns.Style:Text(presets, "GameFontNormalSmall", L["Quick picks:"])
    label:SetPoint("LEFT")
    bar.presetButtons = {}
    local row = {}
    for i, preset in ipairs(Search.PRESETS) do
        local button = CreateFlatButton(presets, 90, L[preset.name], function() Search:ApplyPreset(preset) end)
        button.preset = preset
        ns.Style:InfoTooltip(button, L[preset.name], format(L["Look for: %s. Camps with any of them show."], PresetBuffs(preset)))
        bar.presetButtons[i] = button
        row[i] = button
    end
    bar.clear = CreateFlatButton(presets, 90, L["Clear"], function()
        wipe(ns.db.search.wants)
        ns.db.search.minimum = 1
        Changed()
    end)
    SetFlatSelected(bar.clear, false)
    row[#row + 1] = bar.clear
    local each = 90
    for _, button in ipairs(row) do
        FitFlat(button, 90)
        each = math.max(each, button:GetWidth())
    end
    local labelWidth = math.ceil(ns.Style:TextWidth(label)) + 8
    for i, button in ipairs(row) do
        button:SetWidth(each)
        button:SetPoint("LEFT", presets, "LEFT", labelWidth + (i - 1) * (each + 4), 0)
    end
    presets:SetSize(labelWidth + #row * (each + 4), 20)

    -- No scripts as it shows or resizes (it's in the map, which runs nothing
    -- of Happy Camper's as it opens: MapBar.lua): Search:Watch follows it.
    -- Controller cursors stay off the strip and everything in it (Style:SkipControllerCursor).
    ns.Style:SkipControllerCursor(bar)
    for _, chip in ipairs(bar.chips) do ns.Style:SkipControllerCursor(chip) end
    for _, button in ipairs(row) do ns.Style:SkipControllerCursor(button) end
    self.bar = bar
end

-- The strip lives in the map dock, under the camp bar.
function Search:Layout()
    if not self.bar then return end
    ns.MapBar:LayoutDock()
    self:LayoutChips()
end

-- Spreads the chips evenly across the strip, shrinking them on narrow maps.
function Search:LayoutChips()
    local bar = self.bar
    if not bar then return end
    local count = #bar.chips
    local width = math.min(CHIP_MAX_WIDTH, (bar:GetWidth() - 2 * PAD) / count)
    local start = (bar:GetWidth() - width * count) / 2
    for i, chip in ipairs(bar.chips) do
        chip:SetWidth(width)
        -- Never cut a label off: on a narrow map it goes onto a second line
        -- (where Chinese, and long words like "Erholungs-EP", can break
        -- anywhere), and only if that isn't enough is it made a little smaller.
        local label = chip.label
        label:SetWidth(width - 2)
        label:SetTextScale(1)
        label:SetWordWrap(false)
        label:SetText(chip.profession.buff)
        if label:IsTruncated() then
            label:SetWordWrap(true)
            label:SetNonSpaceWrap(true)
            label:SetMaxLines(2)
            if label:IsTruncated() then label:SetTextScale(0.85) end
        end
        chip:ClearAllPoints()
        chip:SetPoint("TOPLEFT", bar, "TOPLEFT", start + (i - 1) * width, CHIPS_TOP)
    end
end

-- Threshold buttons: Any, 2+, 3+ ... All, for however many buffs are picked.
-- All one size: the widest label's (a translation of Any or All can be longer).
local function UpdateThresholds(bar)
    local wanted, required = Search:WantedCount(), Search:Required()
    local anchor = bar.needs
    local shown = {}
    for i = 1, math.max(wanted, #bar.thresholds) do
        local button = bar.thresholds[i]
        if i <= wanted and wanted > 1 then
            if not button then
                button = CreateFlatButton(bar, 38, nil, function(self)
                    ns.db.search.minimum = self.value
                    Changed()
                end)
                ns.Style:SkipControllerCursor(button)
                bar.thresholds[i] = button
            end
            button.value = i
            button.text:SetText(i == 1 and L["Any"] or i == wanted and L["All"] or (i .. "+"))
            FitFlat(button, 38)
            SetFlatSelected(button, i == required)
            button:ClearAllPoints()
            button:SetPoint("LEFT", anchor, "RIGHT", i == 1 and 6 or 2, 0)
            button:Show()
            anchor = button
            shown[#shown + 1] = button
        elseif button then
            button:Hide()
        end
    end
    ns.Style:SameWidth(shown, 38)
    bar.needs:SetShown(wanted > 1)
    bar.hint:SetShown(wanted == 0)
end

-- Only while it can be seen: the strip stays "shown" with the map closed, and
-- it refreshes itself when the map opens (OnShow).
function Search:RefreshPanel()
    local bar = self.bar
    if not bar or not bar:IsVisible() then return end

    for _, chip in ipairs(bar.chips) do UpdateChip(chip) end
    UpdateThresholds(bar)

    -- A preset is lit while the picks are exactly its buffs, at any tier.
    for _, button in ipairs(bar.presetButtons) do
        local same = #button.preset.skills == self:WantedCount()
        for _, skillLine in ipairs(button.preset.skills) do same = same and ns.db.search.wants[skillLine] == true end
        SetFlatSelected(button, same)
    end
end

function Search:IsOpen()
    return self.bar ~= nil and self.bar:IsShown()
end

-- The strip always shows with the camp bar (MapBar:Refresh), and goes with it
-- when Options turns the bar off or picks Standard mode.
function Search:SetOpen(open)
    if not self.bar then
        if not open then return end
        self:CreateStrip()
    end
    self.bar:SetShown(open)
    self:Layout()
    -- Showing or hiding it changes which camps show.
    ns.MapPins:Refresh()
end
