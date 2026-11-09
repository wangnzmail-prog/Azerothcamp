-- Happy Camper. Copyright (c) 2026 Torridon. All rights reserved; see LICENSE.
local _, ns = ...
local L = ns.L

-- The Happy Camper window, the addon's one window outside the map: Camp,
-- Badges, Music, Handbook, Group, Camp Builder and Options tabs down its left
-- side (Group and Camp Builder in Enhanced mode only: Mode.lua). Opens with /hc or the minimap button, and by
-- itself when you sit at a camp. Its position and last tab are saved.

local Hub = {}
ns.Hub = Hub

local WIDTH, HEIGHT = 500, 728
local PAD = 16
local PAGE_TOP = -62
local QUESTION_MARK_ICON = 134400

-- Each tab's icon: a game icon (several are the ones the game's own side tabs
-- use, in its Communities window), or (media) one of Happy Camper's own pictures.
local TABS = {
    { key = "camp", label = "Camp", icon = "Interface\\Icons\\Spell_Fire_Fire" },
    { key = "badges", label = "Badges", icon = "Interface\\Icons\\Achievement_GuildPerk_HonorableMention" },
    { key = "music", label = "Music", icon = "Interface\\Icons\\INV_Misc_Note_01" },
    { key = "handbook", label = "Handbook", icon = "Interface\\Icons\\INV_Misc_Book_09" },
    { key = "group", label = "Group", icon = "Interface\\Icons\\Achievement_GuildPerk_EverybodysFriend" },
    { key = "finder", label = "Camp Builder", icon = "Interface\\Icons\\INV_Misc_Spyglass_03" },
    { key = "options", label = "Options", icon = "Interface\\Icons\\INV_Misc_Gear_01" },
}
-- Tabs only in Enhanced mode (Mode.lua): in Standard their buttons are hidden
-- and the rest close up.
local ENHANCED_TABS = { group = true, finder = true }

function Hub:TabShown(key)
    return not ENHANCED_TABS[key] or ns.IsEnhanced()
end

local autoOpened = false
local RESTED_SHOW = 4       -- seconds the full bar says "Rested!" after resting finishes
local restedAt = -RESTED_SHOW

-- Tabs ------------------------------------------------------------------------------
-- Along the window's bottom, under it, in the style of the Looking For Group
-- window's side tabs: the game's own LargeSideTabButtonTemplate, an icon in a
-- square tab, its name in a tooltip (seven named tabs didn't fit). That art is
-- drawn to hang off a window's right side, so here it's turned a quarter to
-- hang from its bottom; its icon mask can't be turned, so the icons go
-- unmasked, a size that sits inside the frame. The row is centred.

local TAB_TEMPLATE = "LargeSideTabButtonTemplate"
local TAB_GAP = 2            -- as the LFG window's
local TAB_SIZE = 50          -- if the tab art's size can't be read
local TAB_TUCK = 0           -- the LFG window's tabs start right at its edge
local TAB_ICON = 38          -- the icon, inside the tab's frame
local TAB_ATLASES = { Background = "common-sidetab", SelectedTexture = "common-sidetab-selected",
    TabGlow = "common-sidetab-selected", HighlightTexture = "common-sidetab-hover" }

-- Turns one of the tab's atlas textures a quarter clockwise: the side it hangs
-- from, drawn on its left, comes to the top. False if it can't.
local function Turn(texture, atlas)
    local info = texture and C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas)
    local file = info and (info.file or info.filename)
    if not file then return false end
    local l, r, t, b = info.leftTexCoord, info.rightTexCoord, info.topTexCoord, info.bottomTexCoord
    return pcall(function()
        texture:SetTexture(file)
        -- Corners: upper left, lower left, upper right, lower right.
        texture:SetTexCoord(l, b, r, b, l, t, r, t)
        texture:SetSize(info.height, info.width)
    end)
end

local function CreateTab(f, index, tab)
    local name = "HappyCamperHubTab" .. index
    local ok, button = pcall(CreateFrame, "Button", name, f, TAB_TEMPLATE)
    local icon = tab.media and ns.Style.MEDIA .. tab.media or tab.icon
    if ok and button and type(button.Icon) == "table" and type(button.SetFillToInterior) == "function" then
        for key, atlas in pairs(TAB_ATLASES) do
            if button[key] then Turn(button[key], atlas) end
        end
        -- Turned, the tab is as wide as the art was tall (less its clear rows)
        -- and as tall as it was wide.
        local info = C_Texture.GetAtlasInfo(TAB_ATLASES.Background)
        if info and info.width and info.height then button:SetSize(info.height - 5, info.width) end
        -- Unmasked: turned, the mask would hide the icon.
        if button.Mask then
            pcall(button.Icon.RemoveMaskTexture, button.Icon, button.Mask)
            pcall(button.Mask.Hide, button.Mask)
        end
        -- The icon sits off-centre, toward the side the tab hangs from (up).
        button.GetIconAnchorOffsetsForTabArt = function() return 0, 3 end
        button:InitializeIconAnchoring()
        button.Icon:SetTexture(icon)
        button:SetFillToInterior(true, TAB_ICON)
    else
        -- Without the game's tab art: a plain icon button, lit when chosen.
        button = CreateFrame("Button", name, f)
        button:SetSize(TAB_SIZE, TAB_SIZE)
        button.Icon = button:CreateTexture(nil, "ARTWORK")
        button.Icon:SetPoint("TOPLEFT", 6, -6)
        button.Icon:SetPoint("BOTTOMRIGHT", -6, 6)
        button.Icon:SetTexture(icon)
        button.Icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        button:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
        button.lit = button:CreateTexture(nil, "OVERLAY")
        button.lit:SetAllPoints()
        button.lit:SetTexture("Interface\\Buttons\\CheckButtonHilight")
        button.lit:SetBlendMode("ADD")
        button.SetChecked = function(self, checked) self.lit:SetShown(checked) end
        ns.Style:Tooltip(button, function() return tab.label end)
    end
    button:SetID(index)
    button.tooltipText = tab.label -- the template's tooltip
    -- The template's mouse-up plays the tab sound.
    button:SetScript("OnClick", function() Hub:Select(tab.key) end)
    button.key = tab.key
    return button
end

-- The chosen tab is lit, as the LFG window's are.
local function ShowTabChosen(button, chosen)
    button:SetChecked(chosen)
end

-- Changes a tab's icon (the dev tools try others out: /hc tabicons).
function Hub:SetTabIcon(key, texture)
    local f = self.frame
    for _, button in ipairs(f and f.Tabs or {}) do
        if button.key == key and button.Icon then button.Icon:SetTexture(texture) end
    end
end

-- Shows the tabs the mode has, each beside the one before, the row centred
-- under the window; the window stays on screen with them.
local function LayoutTabs(f)
    local shown = {}
    for _, button in ipairs(f.Tabs) do
        button:SetShown(Hub:TabShown(button.key))
        if Hub:TabShown(button.key) then shown[#shown + 1] = button end
    end
    local width, height = f.Tabs[1]:GetWidth(), f.Tabs[1]:GetHeight()
    if type(width) ~= "number" or width <= 0 or width > 200 then width = TAB_SIZE end
    if type(height) ~= "number" or height <= 0 or height > 200 then height = TAB_SIZE end
    local left = -math.floor((#shown * width + (#shown - 1) * TAB_GAP) / 2)
    for i, button in ipairs(shown) do
        button:ClearAllPoints()
        if i > 1 then
            button:SetPoint("TOPLEFT", shown[i - 1], "TOPRIGHT", TAB_GAP, 0)
        else
            button:SetPoint("TOPLEFT", f, "BOTTOM", left, TAB_TUCK)
        end
    end
    f:SetClampRectInsets(0, 0, 0, TAB_TUCK - height)
end

-- Camp tab ------------------------------------------------------------------------
-- Top: your camp buff card. Middle: the rest bar and Say / General (at a camp only)
-- and Find a camp. Bottom: the Happy Campers at your fire.

local CARD_TOP, CARD_BOTTOM = -22, -218 -- room for ten lines in two columns, the time bar and the camp buffs row

-- Shown instead of the rest bar when you're not at a camp; changes every
-- AWAY_ROTATE seconds and each time the window opens.
local AWAY_PHRASES = {
    "Your feet ache for a warm campfire.",
    "Somewhere, a campfire burns without you.",
    "The murlocs have a campfire. Why don't you?",
    "A hunter would have made camp by now.",
    "Zug zug. Fire good. Find fire.",
    "Your bedroll is starting to miss you.",
    "Rumor has it there's a fire nearby...",
}
-- The tab names and away phrases in the language in use (Locale.lua).
ns.OnLocale(function(L)
    ns.LocalizeFields(TABS, "label")
    for i, phrase in ipairs(AWAY_PHRASES) do AWAY_PHRASES[i] = L[phrase] end
end)

local AWAY_ROTATE = 30
local away = { index = nil, since = 0 }

local function AwayPhrase()
    local now = GetTime()
    if not away.index or now - away.since >= AWAY_ROTATE then
        local index
        repeat index = math.random(#AWAY_PHRASES) until index ~= away.index or #AWAY_PHRASES == 1
        away.index, away.since = index, now
    end
    return AWAY_PHRASES[away.index]
end
local MAX_STAT_LINES = 20   -- an Expert Campfire holds 10 objects; room to spare
local ONE_COLUMN_LINES = 5  -- up to this many get the full width
local STAT_ROW_HEIGHT = 16
local LINE_ICON = 14        -- each line's object icon
local STATS_TOP = 48        -- below the buff's icon and name, and the time bar
local STATS_BOTTOM = 54     -- above the camp buffs row and the cooldown line
local BAR_TOP = 40          -- the time bar, under the buff's icon
local BOARD_ICON, BOARD_GAP = 38, 4 -- the camp buffs row: its icons spread across the card
local CARD_WIDTH = WIDTH - 36
local SCROLLBAR_SPACE = 16

local lastLines = { key = nil, lines = {} }

-- Returns the stat lines, or the last ones read for this buff when it can't be
-- read right now (secret aura data, e.g. in combat). A Tent line left from a
-- tent earlier in the hour isn't one (Camps:DropEarlierTent).
local function BuffLines(buff)
    local key = buff.auraInstanceID .. ":" .. (buff.expirationTime or 0)
    local lines = ns.ReadCampBenefits(buff.auraInstanceID, MAX_STAT_LINES)
    if not lines then
        return lastLines.key == key and lastLines.lines or {}, true
    end
    lines = ns.Camps:DropEarlierTent(lines, buff)
    lastLines.key, lastLines.lines = key, lines
    return lines
end

local BuildBoard
-- The camp buffs row: each buff (Find a camp's: not Cooking's) as its icon.
-- Lit: a camp buff you have now. Blue: a class buff on you gives the same
-- stat (they don't stack). Greyed: one you don't have; its tooltip says which
-- objects give it and who at your fire has that profession. A click opens
-- the Handbook on its profession.
local function BoardTooltip(tooltip, self)
    local profession = self.profession
    tooltip:SetText(profession.buff)
    if self.line then
        tooltip:AddLine(format("%s: %s", self.line.object or profession.name, self.line.effect or ""), 0.4, 1, 0.4, true)
    elseif self.covered then
        tooltip:AddLine(format(L["Your %s gives this already: they don't stack."], self.covered), 0.4, 0.7, 1, true)
    else
        local objects = {}
        for tier = 1, 3 do
            if profession.objects[tier] then objects[#objects + 1] = ns.ObjectName(profession.id, tier) end
        end
        tooltip:AddLine(format(L["From %s's camp objects: %s."], profession.name, ns.JoinList(objects)), 1, 1, 1, true)
        if #ns.Widget:ObjectsOf(profession.id) > 0 then
            tooltip:AddLine(L["You have one in your bags."], 0.4, 1, 0.4, true)
        end
        local names = {}
        for _, person in ipairs(ns.Social:PeopleHere()) do
            if (person.professions or {})[profession.id] then names[#names + 1] = ns.FirstName(person.name) end
        end
        if #names > 0 then
            tooltip:AddLine(format(L["At your fire with %s: %s"], profession.name, ns.JoinList(names)), 1, 0.82, 0, true)
        end
    end
    ns.Style:AddHint(tooltip, L["Click for the Handbook."], true)
end

BuildBoard = function(board)
    board.icons = {}
    local professions = {}
    for _, profession in ipairs(ns.PROFESSIONS) do
        if not profession.notSearchable then professions[#professions + 1] = profession end
    end
    -- Across the card: as big as fits with even gaps, the row centred on it.
    local n = #professions
    local size = math.min(BOARD_ICON, math.floor((CARD_WIDTH - BOARD_GAP * (n - 1)) / n))
    local left = math.floor((CARD_WIDTH - n * size - (n - 1) * BOARD_GAP) / 2)
    board.size = size
    board:SetHeight(size)
    for i, profession in ipairs(professions) do
        local button = CreateFrame("Button", nil, board)
        button:SetSize(size, size)
        button:SetPoint("LEFT", left + (i - 1) * (size + BOARD_GAP), 0)
        button.icon = button:CreateTexture(nil, "ARTWORK")
        button.icon:SetAllPoints()
        button.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        button.icon:SetTexture(profession.buffIcon)
        button:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
        button.profession = profession
        ns.Style:CustomTooltip(button, "ANCHOR_TOP", BoardTooltip)
        button:SetScript("OnClick", function()
            ns.Hub:Open("handbook")
            ns.Handbook:Choose(profession.id)
        end)
        board.icons[#board.icons + 1] = button
    end
end

-- Lights the camp buffs row from the buff's lines.
local function RefreshBoard(board, lines)
    local have, covered = {}, ns.CoveredCampBuffs()
    for _, line in ipairs(lines) do
        -- (A line names its object; the profession's from that, if it doesn't say.)
        local skillLine = line and (line.skillLine or (line.object and select(3, ns.ObjectByName(line.object))))
        if skillLine then have[skillLine] = line end
    end
    for _, button in ipairs(board.icons) do
        local id = button.profession.id
        button.line, button.covered = have[id], not have[id] and covered[id] or nil
        local lit = button.line ~= nil
        button.icon:SetDesaturated(not lit and not button.covered)
        button.icon:SetAlpha((lit or button.covered) and 1 or 0.45)
        if button.covered then button.icon:SetVertexColor(0.55, 0.75, 1) else button.icon:SetVertexColor(1, 1, 1) end
    end
end

-- A buff line's icon: its object's, else its profession's buff icon.
local function StatIcon(stat)
    if not stat then return nil end
    local icon = stat.object and select(5, ns.ObjectByName(stat.object))
    if not icon and stat.skillLine then icon = ns.PROFESSION_BY_ID[stat.skillLine].buffIcon end
    return icon
end

local function BuildBuffCard(page, window)
    local style = ns.Style
    style:Inset(page, window, 10, CARD_TOP, 10, CARD_BOTTOM)

    local card = CreateFrame("Frame", nil, page)
    card:SetPoint("TOPLEFT", 18, CARD_TOP - 8)
    card:SetPoint("BOTTOMRIGHT", page, "TOPRIGHT", -18, CARD_BOTTOM + 6)
    card:SetFrameLevel(window:GetFrameLevel() + 4)

    card.icon = card:CreateTexture(nil, "ARTWORK")
    card.icon:SetSize(36, 36)
    card.icon:SetPoint("TOPLEFT")
    card.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    card.name = style:Text(card, "GameFontNormalLarge")
    card.name:SetPoint("LEFT", card.icon, "RIGHT", 10, 0)
    card.time = style:Text(card, "GameFontHighlightLarge")
    card.time:SetPoint("TOPRIGHT", 0, -2)
    card.timeLabel = style:Text(card, "GameFontDisableSmall", L["left"])
    card.timeLabel:SetPoint("TOPRIGHT", card.time, "BOTTOMRIGHT", 0, -4)

    -- The time left as a bar that drains over the buff's hour (orange once
    -- you'd be warned).
    card.bar = CreateFrame("StatusBar", nil, card)
    card.bar:SetPoint("TOPLEFT", 0, -BAR_TOP)
    card.bar:SetPoint("TOPRIGHT", 0, -BAR_TOP)
    card.bar:SetHeight(5)
    card.bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    card.bar.bg = card.bar:CreateTexture(nil, "BACKGROUND")
    card.bar.bg:SetAllPoints()
    card.bar.bg:SetColorTexture(0, 0, 0, 0.5)

    -- One line per object's buff, each with its object's icon (laid out in
    -- RefreshBuffCard); they scroll if needed.
    local stats = CreateFrame("ScrollFrame", nil, card)
    stats:SetPoint("TOPLEFT", 0, -STATS_TOP)
    stats:SetPoint("BOTTOMRIGHT", 0, STATS_BOTTOM)
    style:ScrollArea(stats, 1, 1)
    card.stats = stats

    card.lines, card.lineIcons = {}, {}
    for i = 1, MAX_STAT_LINES do
        card.lines[i] = style:Text(stats.child, "GameFontHighlight", nil, "LEFT")
        card.lineIcons[i] = stats.child:CreateTexture(nil, "ARTWORK")
        card.lineIcons[i]:SetSize(LINE_ICON, LINE_ICON)
        card.lineIcons[i]:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    end

    -- Every camp buff as a small icon: lit for the ones you have, greyed for
    -- the rest (BuildBoard).
    card.board = CreateFrame("Frame", nil, card)
    card.board:SetPoint("BOTTOMLEFT", 0, 14)
    card.board:SetPoint("BOTTOMRIGHT", 0, 14)
    BuildBoard(card.board)

    card.cooldown = style:Text(card, "GameFontHighlightSmall", nil, "LEFT")
    card.cooldown:SetPoint("BOTTOMLEFT")
    card.cooldown:SetPoint("BOTTOMRIGHT")

    -- With no camp buffs: a note in the middle of the box.
    card.empty = style:Text(card, "GameFontDisable", L["No camp buffs right now.\nSit by a campfire for a minute to get them."], "CENTER")
    card.empty:SetPoint("LEFT")
    card.empty:SetPoint("RIGHT")
    card.empty:SetJustifyV("MIDDLE")
    page.card = card
end

-- The camp you're at, if it's yours to manage (you set it up, in its first 15 minutes).
local function ManagedCamp()
    local camp = ns.Social:MyCamp()
    return ns.Camps:CanManage(camp) and camp or nil
end

-- The camp name menu: the location name, then a submenu per category.
local function BuildNameMenu(root)
    local camp = ManagedCamp()
    if not camp then return end
    local function IsSelected(key) return (camp.nameKey or "") == key end
    local function Select(key) ns.Camps:SetName(camp, key ~= "" and key or nil) end
    root:CreateRadio(ns.Names:Default(camp.location) or L["Location name"], IsSelected, Select, "")
    for _, category in ipairs(ns.Camps:NameOptions(camp)) do
        local submenu = root:CreateButton(category.title)
        for _, entry in ipairs(category.entries) do
            submenu:CreateRadio(entry.text, IsSelected, Select, entry.key)
        end
    end
end

-- Camp management, for the camp you're at: its name and song. Its owner picks
-- them (the name in the camp's first 15 minutes, the song any time); everyone
-- else sees them and can mute the song.
local MANAGE_TOP = -284
local TITLE_ROW = 22          -- the "This camp" line, with Play/Stop or Mute at its right end
local ROWS_TOP = -52          -- under the title line and the note's two lines at most
local LABEL_WIDTH = 52        -- the Name: / Song: / Has: column; labels end at its right edge
local MANAGE_ROW = 30         -- one row per line, controls centred on it
local SONG_BUTTON_WIDTH = 100 -- Play and Mute share this slot, at the right end of the title line

-- The camp's own song: its Camp tracks (the game's looping music: your race's
-- and faction's, and any found). Your Repertoire is performed instead
-- (PerformMenu).
local function SongMenu(root, page)
    local function IsChosen(key) return page.songChoice == key end
    local function Choose(key) page.songChoice = key; ns.Music:SetPick(key); Hub:Refresh() end
    root:CreateTitle(L["Camp tracks"])
    for _, song in ipairs(ns.Music:CampTracks()) do root:CreateRadio(song.label, IsChosen, Choose, song.key) end
end

-- Perform: your Repertoire (found songs), one picked plays once for everyone here.
local function PerformMenu(owner)
    ns.Menu:Context(owner, function(_, root)
        root:CreateTitle(L["Repertoire"])
        for _, song in ipairs(ns.Music:Repertoire()) do
            root:CreateButton(song.label, function()
                ns.Music:Perform(song.key)
                Hub:Refresh()
            end)
        end
    end)
end

local function BuildManagement(page)
    local style = ns.Style
    local width = WIDTH - 2 * PAD
    local area = CreateFrame("Frame", nil, page)
    area:SetPoint("TOPLEFT", PAD, MANAGE_TOP)
    area:SetSize(width, -ROWS_TOP + 3 * MANAGE_ROW)
    page.manage = area
    -- The title line: "This camp", and the song's button at its right end,
    -- both centred on it.
    area.title = style:Text(area, "GameFontNormal", L["This camp"])
    area.title:SetPoint("LEFT", area, "TOPLEFT", 0, -TITLE_ROW / 2)
    -- Who set it up, on its own line so it's never cut off (two lines at most).
    area.note = style:Text(area, "GameFontDisableSmall", nil, "LEFT")
    area.note:SetPoint("TOPLEFT", 0, -TITLE_ROW - 4)
    area.note:SetWidth(width)

    -- Rows: a right-aligned label, then its control or text from LABEL_WIDTH to
    -- the right edge; everything on a row is centred on the same line.
    local function RowY(i) return ROWS_TOP - (i - 0.5) * MANAGE_ROW end
    local function Row(i, label)
        local text = style:Text(area, "GameFontNormalSmall", label, "RIGHT")
        text:SetPoint("RIGHT", area, "TOPLEFT", LABEL_WIDTH - 8, RowY(i))
        return text
    end
    local function Value(i, region, height)
        if height then region:SetHeight(height) end
        region:SetPoint("LEFT", area, "TOPLEFT", LABEL_WIDTH, RowY(i))
    end
    local function Plain(i)
        local text = style:Text(area, "GameFontHighlight", nil, "LEFT")
        text:SetPoint("LEFT", area, "TOPLEFT", LABEL_WIDTH + 8, RowY(i))
        text:SetPoint("RIGHT", area, "TOPRIGHT", 0, RowY(i))
        text:SetWordWrap(false)
        return text
    end

    -- Name: a menu for the owner, the name for everyone else.
    Row(1, L["Name:"])
    page.nameDropdown = style:Dropdown(area, width - LABEL_WIDTH, function(_, root) BuildNameMenu(root) end)
    Value(1, page.nameDropdown)
    area.nameText = Plain(1)

    -- Song: a menu for the owner, what's playing for others, the same size as
    -- the Name row's. Its button is on the title line: Play/Stop for the
    -- owner, Mute/Unmute for others.
    Row(2, L["Song:"])
    page.songDropdown = style:Dropdown(area, width - LABEL_WIDTH, function(_, root) SongMenu(root, page) end)
    Value(2, page.songDropdown)
    area.songText = Plain(2)
    page.songButton = style:Button(area, SONG_BUTTON_WIDTH, L["Play"], function()
        if select(2, ns.Music:Current()) then ns.Music:Stop() elseif page.songChoice then ns.Music:PlaySong(page.songChoice) end
        Hub:Refresh()
    end, TITLE_ROW)
    page.songButton:SetPoint("RIGHT", area, "TOPRIGHT", 0, -TITLE_ROW / 2)
    page.songButton:SetMotionScriptsWhileDisabled(true)
    style:InfoTooltip(page.songButton, L["Camp song"], function()
        local ok, why = ns.Music:CanPlaySong()
        if not ok then return why end
        local text = L["Everyone with Happy Camper at this camp hears it, over and over for as long as they're here."]
        if ns.db.autoSong then
            text = text .. "\n\n" .. L["Your pick is saved: it plays by itself at the next fire you light or camp you set up."]
        end
        return text
    end)
    page.muteButton = style:Button(area, SONG_BUTTON_WIDTH, L["Mute"], function()
        if ns.Music:Muted() then ns.Music:Unmute() else ns.Music:Mute() end
        Hub:Refresh()
    end, TITLE_ROW)
    page.muteButton:SetPoint("RIGHT", area, "TOPRIGHT", 0, -TITLE_ROW / 2)
    style:Tooltip(page.muteButton, L["Camp song"], L["Turns this camp's song off or back on, for you only."])
    -- Perform, beside them: anyone here can play one of their found songs.
    page.performButton = style:Button(area, SONG_BUTTON_WIDTH, L["Perform"], function(button) PerformMenu(button) end, TITLE_ROW)
    page.performButton:SetMotionScriptsWhileDisabled(true)
    style:InfoTooltip(page.performButton, L["Perform"], function()
        if #ns.Music:Repertoire() == 0 then return L["Find songs around the world to perform them here. The Music tab has hints."] end
        local ok, why = ns.Music:CanPerform()
        if not ok then return why end
        return L["Plays one of your found songs once for everyone here with Happy Camper, in place of the camp's song. If others are performing, it waits its turn. One song every 5 minutes."]
    end)
    -- They share the row: one width, whichever text they show.
    style:FitTexts({ page.songButton, page.muteButton, page.performButton }, { L["Play"], L["Stop"], L["Mute"], L["Unmute"], L["Perform"] }, SONG_BUTTON_WIDTH)

    -- Has: the camp's own objects, so they aren't mistaken for your buffs
    -- (which may come from another camp). Hover for the full list. Not in
    -- Standard mode, which leaves out camp details (Mode.lua).
    area.hasLabel = Row(3, L["Has:"])
    area.has = CreateFrame("Frame", nil, area)
    area.has:SetPoint("LEFT", area, "TOPLEFT", LABEL_WIDTH + 8, RowY(3))
    area.has:SetPoint("RIGHT", area, "TOPRIGHT", 0, RowY(3))
    area.has:SetHeight(16)
    area.has.text = style:Text(area.has, "GameFontHighlight", nil, "LEFT")
    area.has.text:SetAllPoints()
    area.has.text:SetWordWrap(false)
    style:CustomTooltip(area.has, "ANCHOR_TOP", function(tooltip)
        local camp = ns.Social:MyCamp()
        tooltip:SetText(L["This camp's objects"])
        local objects = camp and ns.Camps:ObjectList(camp) or {}
        for _, object in ipairs(objects) do
            local profession = ns.PROFESSION_BY_ID[object.skillLine]
            tooltip:AddDoubleLine(object.name, profession and profession.buff or "", 1, 1, 1, 0.4, 1, 0.4)
        end
        if #objects == 0 then tooltip:AddLine(L["None reported yet. They show once someone with Happy Camper rests here."], 1, 1, 1, true) end
        tooltip:AddLine(L["Your camp buffs, above, are the ones you have now, which may be from another camp."], 0.7, 0.7, 0.7, true)
    end)
end

local RefreshCampDetails, RefreshSong

local function RefreshManagement(page)
    local area, camp = page.manage, ns.Social:MyCamp()
    -- A bare fire (no camp buffs yet) isn't a camp: only its music is shared.
    local bare = not camp and ns.Music:AtBareFire()
    area:SetShown(camp ~= nil or bare)
    if not camp and not bare then return end
    area.hasLabel:SetShown(ns.IsEnhanced())
    area.has:SetShown(ns.IsEnhanced())
    local song = ns.Music:NowPlaying()
    local isMuted, mutedSong = ns.Music:Muted()
    local owner

    if bare then
        -- Whoever lit it picks its song; it has no name yet.
        owner = ns.Camps:LitFire(true) ~= nil
        area.note:SetText(L["No camp buffs here yet, so this fire isn't on the map. Only its music is shared."])
        page.nameDropdown:Hide()
        area.nameText:Show()
        area.nameText:SetText("|cffaaaaaa" .. L["A bare campfire"] .. "|r")
        area.has.text:SetText("|cffaaaaaa" .. L["No objects reported yet"] .. "|r")
    else
        RefreshCampDetails(page, camp, ns.Camps:CanManage(camp))
        -- Its song stays its owner's to change for as long as it burns.
        owner = ns.Camps:CanPickSong(camp)
    end
    RefreshSong(page, owner, song, isMuted, mutedSong)
end

-- A camp's note, name and objects.
RefreshCampDetails = function(page, camp, owner)
    local area = page.manage
    local timeLeft = ns.Camps:ManageTimeLeft(camp)
    if owner then
        area.note:SetText(format(camp.owned and L["You lit this fire: name it within %s, and pick its song any time."]
            or L["You're the first here with Happy Camper: name it within %s, and pick its song any time."], ns.FormatTime(timeLeft)))
    elseif camp.creator == ns.playerName then
        area.note:SetText(camp.owned and L["You lit this fire. Its name is settled; its song is yours to change any time."]
            or L["You reported this fire. Its name is settled; its song is yours to change any time."])
    else
        area.note:SetText(format(timeLeft <= 0 and L["Set up by %s, who picks its song."] or L["Set up by %s, who picks its name and song."],
            ns.FirstName(camp.creator)))
    end
    page.nameDropdown:SetShown(owner)
    area.nameText:SetShown(not owner)
    if owner and page.nameDropdown.OverrideText then page.nameDropdown:OverrideText(ns.Camps:DisplayName(camp)) end
    area.nameText:SetText(ns.Camps:DisplayName(camp))

    -- The camp's objects, as many names as fit, then "and N more".
    local objects = ns.Camps:ObjectList(camp)
    local text = area.has.text
    if #objects == 0 then
        text:SetText("|cffaaaaaa" .. L["No objects reported yet"] .. "|r")
    else
        local shown = #objects
        repeat
            local names = {}
            for i = 1, shown do names[i] = objects[i].name end
            local line = table.concat(names, ", ")
            if shown < #objects then line = format(L["%s and %d more"], line, #objects - shown) end
            text:SetText(line)
            shown = shown - 1
        until not text:IsTruncated() or shown < 1
    end
end

-- The song row: the owner's menu and Play, or what's playing and Mute (a song
-- performed, with who's performing it). Perform beside them, for everyone.
RefreshSong = function(page, owner, song, isMuted, mutedSong)
    local area = page.manage
    local showMute = not owner and (song ~= nil or isMuted)
    page.songDropdown:SetShown(owner)
    page.songButton:SetShown(owner)
    area.songText:SetShown(not owner)
    page.muteButton:SetShown(showMute)
    page.muteButton:SetText(isMuted and L["Unmute"] or L["Mute"])
    page.performButton:ClearAllPoints()
    local slot = owner and page.songButton or showMute and page.muteButton
    if slot then
        page.performButton:SetPoint("RIGHT", slot, "LEFT", -6, 0)
    else
        page.performButton:SetPoint("RIGHT", area, "TOPRIGHT", 0, -TITLE_ROW / 2)
    end
    page.performButton:SetEnabled(#ns.Music:Repertoire() > 0 and (ns.Music:CanPerform()))
    if owner then
        local available = ns.Music:CampTracks()
        if not page.songChoice then page.songChoice = ns.Music:Pick() or available[1] and available[1].key end
        ns.Style:ShowChoice(page.songDropdown, available, page.songChoice, "key", "label")
        local mine = select(2, ns.Music:Current())
        page.songButton:SetText(mine and L["Stop"] or L["Play"])
        page.songButton:SetEnabled(mine or ns.Music:CanPlaySong())
    elseif isMuted then
        area.songText:SetText(mutedSong and (mutedSong .. " |cffaaaaaa" .. L["(muted)"] .. "|r") or ("|cffaaaaaa" .. L["Muted"] .. "|r"))
    else
        local _, from, performed = ns.Music:NowPlaying()
        if song and performed and from then song = format("%s |cffaaaaaa(%s)|r", song, ns.FirstName(from)) end
        area.songText:SetText(song or ("|cffaaaaaa" .. L["No song playing"] .. "|r"))
    end
end

local ACTION_ROW = -254          -- top of the Say / General / Find a camp row
local ACTION_BUTTON_WIDTH, ACTION_BUTTON_HEIGHT = 100, 22
local PEOPLE_TOP = -434          -- Adventurers at this camp
local PEOPLE_HEIGHT = 192        -- four people, then it scrolls

local function BuildCampPage(page)
    local window, style = page:GetParent(), ns.Style
    page.title = style:PageTitle(page, L["Your camp buffs"])

    BuildBuffCard(page, window)

    -- Rest countdown (follows the Welcoming Campfire aura); only at a camp.
    page.rest = CreateFrame("StatusBar", nil, page)
    page.rest:SetPoint("TOPLEFT", PAD, -228)
    page.rest:SetSize(WIDTH - 2 * PAD, 18)
    page.rest:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    page.rest:SetStatusBarColor(1, 0.55, 0.15)
    page.rest.bg = page.rest:CreateTexture(nil, "BACKGROUND")
    page.rest.bg:SetAllPoints()
    page.rest.bg:SetColorTexture(0, 0, 0, 0.5)
    page.rest.text = style:Text(page.rest, "GameFontHighlightSmall")
    page.rest.text:SetPoint("CENTER")
    -- It fills smoothly while you rest (the page itself refreshes once a second),
    -- and flashes gold when resting finishes (Hub:OnRested).
    page.rest:SetScript("OnUpdate", function(bar)
        local s = ns.state
        if s.restEnd then bar:SetValue(math.min(s.restEnd - s.restStart, GetTime() - s.restStart)) end
    end)
    local flash = page.rest:CreateTexture(nil, "OVERLAY")
    flash:SetAllPoints()
    flash:SetColorTexture(1, 0.85, 0.3)
    flash:SetBlendMode("ADD")
    flash:SetAlpha(0)
    page.rest.flash = flash:CreateAnimationGroup()
    for order, fade in ipairs({ { 0.15, 0, 0.9 }, { 0.8, 0.9, 0 } }) do
        local anim = page.rest.flash:CreateAnimation("Alpha")
        anim:SetOrder(order)
        anim:SetDuration(fade[1])
        anim:SetFromAlpha(fade[2])
        anim:SetToAlpha(fade[3])
    end

    -- One row under the bar, its buttons all the same size: Say and General
    -- about the camp you're at, or the last one you were at while it's still
    -- going (Announce:CampToAnnounce), and Find a camp on the right.
    page.tell = style:Text(page, "GameFontNormalSmall", L["Share this camp:"])
    page.tell:SetPoint("LEFT", page, "TOPLEFT", PAD, ACTION_ROW - ACTION_BUTTON_HEIGHT / 2)
    page.announce = ns.Announce:CreateButtons(page, function(room)
        return ns.Announce:CanAnnounceCamp() and ns.Announce:CampMessage(room) or nil
    end, ACTION_BUTTON_WIDTH, ACTION_BUTTON_HEIGHT, true)
    page.announce[1]:SetPoint("LEFT", page.tell, "RIGHT", 8, 0)

    page.away = style:Text(page, "GameFontHighlight", nil, "CENTER")
    page.away:SetPoint("TOP", page, "TOP", 0, -228)
    page.away:SetWidth(WIDTH - 2 * PAD)
    page.away:SetTextColor(0.8, 0.7, 0.55)

    page.find = style:Button(page, ACTION_BUTTON_WIDTH, L["Find a camp"], function() ns.OpenSearch() end, ACTION_BUTTON_HEIGHT)
    -- In Standard mode it just opens the map (no Find a camp strip there).
    style:Tooltip(page.find, L["Find a camp"], function()
        return ns.IsEnhanced() and L["Open the map and show camps with the buffs you want."] or L["Open the map to see the camps around you."]
    end)
    -- The widest of the three (a translation may make one grow). If that leaves
    -- the label too little room, it goes on two lines rather than under them.
    local each = style:SameWidth({ page.announce[1], page.announce[2], page.find }, ACTION_BUTTON_WIDTH)
    local room = WIDTH - 2 * PAD - 3 * each - 8 - 6 - 8
    -- Room for the longer of its two texts: the camp here, or your last one.
    for _, text in ipairs({ L["Share your last camp:"], L["Share this camp:"] }) do
        page.tell:SetText(text)
        if ns.Style:TextWidth(page.tell) > room then
            page.tell:SetWidth(room)
            page.tell:SetJustifyH("LEFT")
        end
    end

    BuildManagement(page)
    style:Inset(page, window, 10, PEOPLE_TOP - 14, 10, PEOPLE_TOP - 16 - PEOPLE_HEIGHT - 8)
    ns.Circle:BuildPeople(page, PEOPLE_TOP, PEOPLE_HEIGHT)
end

local function StatText(stat, withObject)
    if stat == false then return "|cffaaaaaa" .. L["Stats show after combat"] .. "|r" end
    local effect = "|cff66ff66" .. stat.effect .. "|r"
    return withObject and stat.object and format("|cffffd100%s:|r %s", stat.object, effect) or effect
end

-- Places the stat lines in the card's scroll area; returns their total height.
local function LayoutStats(card, lines, width)
    local columns = #lines > ONE_COLUMN_LINES and 2 or 1
    local columnWidth = width / columns
    local y, col = 0, 0
    local function EndRow()
        if col > 0 then y, col = y + STAT_ROW_HEIGHT, 0 end
    end
    for i, line in ipairs(card.lines) do
        local stat = lines[i]
        local icon = card.lineIcons[i]
        local iconPath = StatIcon(stat)
        local inset = iconPath and LINE_ICON + 4 or 0
        line:ClearAllPoints()
        icon:ClearAllPoints()
        icon:SetShown(stat ~= nil and iconPath ~= nil)
        if iconPath then icon:SetTexture(iconPath) end
        line:SetFontObject(columns == 2 and "GameFontHighlightSmall" or "GameFontHighlight")
        line:SetShown(stat ~= nil)
        -- The line, and its icon in front of it, at x.
        local function At(x)
            icon:SetPoint("TOPLEFT", x, -y)
            line:SetPoint("TOPLEFT", x + inset, -y - 1)
        end
        if stat == nil then
            line:SetText("")
        else
            line:SetWordWrap(false)
            line:SetWidth(columnWidth - 8 - inset)
            line:SetText(StatText(stat, true))
            -- In two columns, drop the object name if that makes it fit.
            if columns == 2 and line:IsTruncated() then line:SetText(StatText(stat, false)) end
            if columns == 2 and not line:IsTruncated() then
                At(col * columnWidth)
                col = col + 1
                if col == columns then EndRow() end
            else
                -- One column, or still too long: a whole row, wrapped.
                EndRow()
                if columns == 2 then
                    line:SetText(StatText(stat, true))
                    line:SetWidth(width - 8 - inset)
                end
                line:SetWordWrap(true)
                At(0)
                y = y + math.max(STAT_ROW_HEIGHT, ns.Style:TextHeight(line) + 3)
            end
        end
    end
    EndRow()
    return y
end

local function RefreshBuffCard(card)
    local now = GetTime()
    local buff = ns.state.buffs[1]
    local c = ns.charDB

    card.auraInstanceID = buff and buff.auraInstanceID
    for _, region in ipairs({ card.icon, card.name, card.time, card.timeLabel, card.bar }) do region:SetShown(buff ~= nil) end
    card.empty:SetShown(buff == nil)

    local lines = {}
    if buff then
        card.icon:SetTexture(buff.icon or QUESTION_MARK_ICON)
        card.name:SetText(buff.name)
        local left = (buff.expirationTime or 0) > 0 and buff.expirationTime - now
        card.time:SetText(left and ns.FormatTime(left) or "")
        local warn = left and left <= ns.db.warnSeconds
        card.time:SetTextColor(1, warn and 0.3 or 1, warn and 0.3 or 1)
        local duration = (buff.duration or 0) > 0 and buff.duration or 3600
        card.bar:SetMinMaxValues(0, duration)
        card.bar:SetValue(left and math.max(0, math.min(duration, left)) or 0)
        if warn then card.bar:SetStatusBarColor(1, 0.5, 0.1) else card.bar:SetStatusBarColor(0.25, 0.8, 0.3) end
        local hidden
        lines, hidden = BuffLines(buff)
        if hidden and #lines == 0 then lines = { false } end
    end
    -- Up to five lines use the full width; more go in two columns. Nothing is
    -- cut off: long lines wrap, and the lines scroll if they don't fit.
    local stats = card.stats
    local full = stats:GetWidth() > 0 and stats:GetWidth() or (WIDTH - 36)
    local visible = (stats:GetHeight() or 0) > 0 and stats:GetHeight() or (CARD_TOP - CARD_BOTTOM - STATS_TOP - STATS_BOTTOM - 14)
    local height = LayoutStats(card, lines, full)
    local scrolls = height > visible + 1
    if scrolls then height = LayoutStats(card, lines, full - SCROLLBAR_SPACE) end
    stats.child:SetSize(scrolls and full - SCROLLBAR_SPACE or full, math.max(1, height))
    stats.scrollBar:SetShown(scrolls)
    if not scrolls then stats:SetVerticalScroll(0) end
    card.statsScroll = scrolls

    RefreshBoard(card.board, lines)
    local cooldownLeft = c.objectReadyAt and (c.objectReadyAt - GetServerTime())
    card.cooldown:SetText(cooldownLeft and cooldownLeft > 0 and ("|cffaaaaaa" .. format(L["Your %s can be placed again in"], c.objectName or L["campsite object"]) .. "|r "
        .. ns.FormatTime(cooldownLeft)) or "")
end

local function RefreshCampPage(page)
    local s = ns.state
    RefreshBuffCard(page.card)

    RefreshManagement(page)

    local atCamp = ns.Social:IsAtCamp()
    -- Say and General: at a camp, or away from the last one you were at while it's still going.
    local shareCamp, here = ns.Announce:CampToAnnounce()
    local share = atCamp or shareCamp ~= nil
    page.rest:SetShown(atCamp)
    page.tell:SetShown(share)
    page.tell:SetText(shareCamp and not here and L["Share your last camp:"] or L["Share this camp:"])
    for _, button in ipairs(page.announce) do
        button:SetShown(share)
        button:SetEnabled(shareCamp ~= nil)
    end
    page.away:SetShown(not atCamp)
    if not atCamp then page.away:SetText(AwayPhrase()) end
    -- Find a camp, only away from a camp: beside Say / General (your last
    -- camp), else centred under the flavour line.
    page.find:SetShown(not atCamp)
    page.find:ClearAllPoints()
    if share then page.find:SetPoint("TOPRIGHT", -PAD, ACTION_ROW) else page.find:SetPoint("TOP", page, "TOP", 0, ACTION_ROW) end

    if s.restEnd then
        local total = s.restEnd - s.restStart
        page.rest:SetMinMaxValues(0, total)
        page.rest:SetValue(math.min(total, GetTime() - s.restStart))
        page.rest.text:SetFormattedText(L["Resting by the fire... %ds"], math.max(0, math.ceil(s.restEnd - GetTime())))
    elseif GetTime() - restedAt < RESTED_SHOW then
        page.rest:SetMinMaxValues(0, 1)
        page.rest:SetValue(1)
        page.rest.text:SetText(L["Rested! Your camp buffs are active."])
    else
        page.rest:SetMinMaxValues(0, 1)
        page.rest:SetValue(0)
        -- Your own fire, only when it's the one you're at.
        local camp = s.myCampID and ns.Camps:Get(s.myCampID)
        local yards = camp and ns.Camps:DistanceFromPlayer(camp)
        if not (yards and yards <= ns.Camps.MERGE_RADIUS) then camp = nil end
        local left = camp and ns.Camps:TimeLeft(camp)
        local lit = not camp and ns.Camps:LitFire(true)
        if lit then
            page.rest.text:SetText(format(L["Your fire burns for another %s. Rest a minute to put it on the map."],
                ns.FormatTime(lit.expiresAt - GetServerTime())))
        else
            page.rest.text:SetText(left and format(L["Your fire burns for another %s. Sit down to rest."], ns.FormatTime(left))
                or L["Sit down by the fire for a minute to get its buffs"])
        end
    end

    ns.Circle:RefreshPeople()
end

-- Window ----------------------------------------------------------------------------

function Hub:Create()
    -- A portrait window, where it was left or else in the middle of the screen.
    local f = ns.Style:Window("HappyCamperHub", WIDTH, HEIGHT, "DIALOG", "Happy Camper",
        ns.Style.PORTRAIT, "hubPoint")
    if not ns.db.hubPoint then f:SetPoint("CENTER") end
    f.Tabs = {}
    for i, tab in ipairs(TABS) do f.Tabs[i] = CreateTab(f, i, tab) end
    LayoutTabs(f)

    -- Pages sit above the background and insets; only the selected one shows.
    f.pages = {}
    for _, tab in ipairs(TABS) do
        local page = CreateFrame("Frame", nil, f)
        page:SetPoint("TOPLEFT", 0, PAGE_TOP)
        page:SetPoint("BOTTOMRIGHT", 0, 8)
        page:SetFrameLevel(f:GetFrameLevel() + 3)
        page:Hide()
        f.pages[tab.key] = page
    end
    BuildCampPage(f.pages.camp)
    ns.Finder:Build(f.pages.finder)
    ns.Group:Build(f.pages.group)
    ns.Badges:Build(f.pages.badges)
    ns.Songbook:Build(f.pages.music)
    ns.Handbook:Build(f.pages.handbook)
    ns.Options:Build(f.pages.options)

    f:SetScript("OnShow", function()
        away.index = nil -- a fresh phrase each time the window opens
        Hub:UpdateBackground()
        Hub:Refresh()
    end)
    -- Only a real close: when the whole UI is hidden (the cinematic camera) the
    -- window is still shown, and still closes when you walk away.
    f:SetScript("OnHide", function(self) if not self:IsShown() then autoOpened = false end end)
    self.frame = f
    self:Select(ns.db.hubTab or "camp")
end

-- The same art behind every tab (Style:ApplyPageBackground).
function Hub:UpdateBackground()
    local f = self.frame
    if not f then return end
    ns.Style:ApplyPageBackground(f)
end

-- A tab the mode doesn't have (Group and Camp Builder in Standard) opens Camp.
function Hub:Select(key)
    local f = self.frame
    if not f.pages[key] or not self:TabShown(key) then key = "camp" end
    self.current = key
    ns.db.hubTab = key
    for _, button in ipairs(f.Tabs) do ShowTabChosen(button, button.key == key) end
    for pageKey, page in pairs(f.pages) do page:SetShown(pageKey == key) end
    self:UpdateBackground()
    if key == "options" then ns.Options:Sync() end
    if key == "finder" and f:IsShown() then ns.MinimapButton:ClearAttention() end
    self:Refresh()
end

-- Standard or Enhanced was picked (Mode.lua): the tabs change at once, and a
-- tab that's gone leaves the Camp tab showing.
function Hub:OnModeChanged()
    local f = self.frame
    if not f then return end
    LayoutTabs(f)
    if not self:TabShown(self.current) then
        self:Select("camp")
    else
        self:Refresh()
    end
end

function Hub:IsShowing(key)
    return self.frame ~= nil and self.frame:IsShown() and (key == nil or self.current == key)
end

function Hub:Open(key)
    if not self.frame then self:Create() end
    if key then self:Select(key) end
    self.frame:Show()
    if self.current == "finder" then ns.MinimapButton:ClearAttention() end
end

function Hub:Close()
    if self.frame then self.frame:Hide() end
end

-- Toggles the window, or switches to another tab if it's already open.
function Hub:Toggle(key)
    if self:IsShowing(key) then self:Close() else self:Open(key) end
end

-- Opens on the Camp tab when you sit at a camp, and closes when you leave.
-- Resting just finished: the bar shows full and flashes.
function Hub:OnRested()
    restedAt = GetTime()
    if self:IsShowing("camp") then self.frame.pages.camp.rest.flash:Play() end
    self:Refresh()
end

function Hub:OnRestStart()
    if ns.db.circleAutoOpen and not self:IsShowing() then
        self:Open("camp")
        autoOpened = true
    end
end

function Hub:Update()
    if autoOpened and self:IsShowing() and not ns.Social:IsAtCamp() then
        -- Cleared here too: with the whole UI hidden, Hide() doesn't fire OnHide.
        autoOpened = false
        self:Close()
    end
    self:Refresh(true)
end

-- periodic: the timer's update, which leaves the Badges and Music tabs alone
-- (they only change when a badge is earned, a song learned or listened to,
-- and are redrawn then).
function Hub:Refresh(periodic)
    local f = self.frame
    if not f or not f:IsShown() then return end
    if self.current == "camp" then
        RefreshCampPage(f.pages.camp)
    elseif self.current == "finder" then
        ns.Finder:Refresh()
    elseif self.current == "group" then
        ns.Group:Refresh()
    elseif self.current == "badges" then
        if not periodic then ns.Badges:Refresh() end
    elseif self.current == "music" then
        if periodic then ns.Songbook:UpdateListen() else ns.Songbook:Refresh() end
    elseif self.current == "handbook" then
        if not periodic then ns.Handbook:Refresh() end -- (it redraws itself when bags, skills or recipes change)
    end
end
