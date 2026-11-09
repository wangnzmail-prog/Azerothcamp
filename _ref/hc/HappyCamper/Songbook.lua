-- Happy Camper. Copyright (c) 2026 Torridon. All rights reserved; see LICENSE.
local _, ns = ...
local L = ns.L

-- The Music tab: your collection of inspired songs (Music.lua), laid out like
-- the Badges tab. One row per song: found ones in gold with where you found
-- them, when, and Listen (at a camp; it plays once, just for you: nothing is sent); the
-- rest greyed out, with the zone they're somewhere in (their titles hint at
-- the place). In both modes.

local Songbook = {}
ns.Songbook = Songbook

local LIST_TOP = -30   -- the panel behind the songs, under the count (as on the Badges tab)
local SCROLLBAR = 14   -- room on the right for the scroll bar, inside the panel
local ICON = 32
local ROW_PAD = 8      -- above and below a row's text
local TEXT_LEFT = 6 + ICON + 10
local BUTTON_WIDTH, BUTTON_HEIGHT = 80, 22
local SONG_ICON = "Interface\\Icons\\INV_Misc_Note_01"

-- Places, as the game names them in your language.

-- The zone (or zones: song.zones) a song is found in.
local function ZoneName(song)
    local names = {}
    for _, mapID in ipairs(song.zones or { song.zone }) do
        local info = C_Map.GetMapInfo(mapID)
        if info and info.name and info.name ~= "" then names[#names + 1] = info.name end
    end
    return ns.OrList(names)
end

-- A song's place and its zone ("Raven Hill, Duskwood": the first, for a song
-- with more than one in the same zone); for one found in several zones, its
-- places ("Booty Bay, Wild Shore or Ratchet").
local function PlaceName(song)
    local ids = {}
    for id in pairs(song.areas or {}) do ids[#ids + 1] = id end
    table.sort(ids)
    local names = {}
    for _, id in ipairs(ids) do
        local area = C_Map.GetAreaInfo(id)
        if type(area) == "string" and area ~= "" then names[#names + 1] = area end
    end
    if song.zones and #names > 1 then return ns.OrList(names) end
    local zone = ZoneName(song)
    if names[1] then return zone and format("%s, %s", names[1], zone) or names[1] end
    return zone or ""
end

function Songbook:Build(page)
    local window = page:GetParent()
    local style = ns.Style
    page.summary = style:PageTitle(page)

    -- The panel stays put; the songs scroll inside it, with the scroll bar
    -- inside its right edge.
    local inset = style:Inset(page, window, 10, LIST_TOP, 10, LIST_TOP)
    inset:ClearAllPoints()
    inset:SetPoint("TOPLEFT", page, "TOPLEFT", 10, LIST_TOP)
    inset:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", -10, 4)
    local scroll = CreateFrame("ScrollFrame", nil, page)
    scroll:SetPoint("TOPLEFT", 16, LIST_TOP - 6)
    scroll:SetPoint("BOTTOMRIGHT", -16, 10)
    scroll:SetFrameLevel(window:GetFrameLevel() + 4)
    local width = window:GetWidth() - 32 - SCROLLBAR
    style:ScrollArea(scroll, width, 1)
    local content = scroll.child
    page.content, page.width = content, width

    -- How songs are found, above them.
    page.intro = style:Text(content, "GameFontHighlightSmall",
        L["Rest at a camp at a song's place to learn it. Songs you've found can be played for everyone at your camp from the Camp tab."], "LEFT")
    page.intro:SetWidth(width - 8)

    -- Camp tracks first, then the Repertoire, each under its heading.
    page.headers = {
        style:Text(content, "GameFontNormalLarge", L["Camp tracks"], "LEFT"),
        style:Text(content, "GameFontNormalLarge", L["Repertoire"], "LEFT"),
    }
    local ordered = {}
    for pass = 1, 2 do
        for _, song in ipairs(ns.Music:Inspired()) do
            if ns.Music:IsRepertoire(song) == (pass == 2) then ordered[#ordered + 1] = song end
        end
    end
    page.rows = {}
    local buttons = {}
    local previous
    for i, song in ipairs(ordered) do
        local group = ns.Music:IsRepertoire(song) and 2 or 1
        local row = CreateFrame("Frame", nil, content)
        row.song = song
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(ICON, ICON)
        row.icon:SetPoint("LEFT", 6, 0)
        row.icon:SetTexture(SONG_ICON)
        row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        row.title = style:Text(row, "GameFontNormal", nil, "LEFT")
        row.place = style:Text(row, "GameFontHighlightSmall", nil, "LEFT")
        row.place:SetPoint("TOPLEFT", row.title, "BOTTOMLEFT", 0, -2)
        row.found = style:Text(row, "GameFontDisableSmall", nil, "LEFT")
        row.found:SetPoint("TOPLEFT", row.place, "BOTTOMLEFT", 0, -2)
        row.listen = style:Button(row, BUTTON_WIDTH, L["Listen"], function() Songbook:Listen(song.key) end, BUTTON_HEIGHT)
        row.listen:SetPoint("RIGHT", -6, 0)
        style:Tooltip(row.listen, function() return song.label end, function()
            local can, why = ns.Music:CanListen()
            if not can and ns.Music:Previewing() ~= song.key then return why end
            local text = L["Plays it once, just for you: nobody else hears it."]
            if ns.Music:IsPlaying() then
                text = text .. "\n\n" .. L["A camp song you're hearing is muted while you listen, and comes back after."]
            end
            return text
        end)
        buttons[#buttons + 1] = row.listen
        -- A thin rule between songs (not above a group's first).
        row.group = group
        if previous == group then
            local rule = row:CreateTexture(nil, "ARTWORK")
            rule:SetColorTexture(1, 0.82, 0.4, 0.2)
            rule:SetHeight(1)
            rule:SetPoint("TOPLEFT", 6, 0)
            rule:SetPoint("TOPRIGHT", -6, 0)
        end
        page.rows[i] = row
        previous = group
    end
    -- Listen and Stop: one width, whichever a button shows.
    local buttonWidth = #buttons > 0 and style:FitTexts(buttons, { L["Listen"], L["Stop"] }, BUTTON_WIDTH) or BUTTON_WIDTH
    -- The text column ends before the buttons, the same for every row.
    local textWidth = width - TEXT_LEFT - buttonWidth - 16
    for _, row in ipairs(page.rows) do
        for _, text in ipairs({ row.title, row.place, row.found }) do text:SetWidth(textWidth) end
    end
    self.page = page
end

-- Places the intro and the rows, each as tall as its text needs.
function Songbook:Layout()
    local page = self.page
    local y = -8
    page.intro:ClearAllPoints()
    page.intro:SetPoint("TOPLEFT", page.content, "TOPLEFT", 4, y)
    y = y - ns.Style:TextHeight(page.intro, 24) - 8
    local group
    for _, header in ipairs(page.headers) do header:Hide() end
    for _, row in ipairs(page.rows) do
        if row.group ~= group then
            group = row.group
            local header = page.headers[group]
            header:Show()
            header:ClearAllPoints()
            header:SetPoint("TOPLEFT", page.content, "TOPLEFT", 6, y - 4)
            y = y - ns.Style:TextHeight(header, 16) - 10
        end
        local text = ns.Style:TextHeight(row.title, 14) + 2 + ns.Style:TextHeight(row.place, 12)
        if row.found:IsShown() then text = text + 2 + ns.Style:TextHeight(row.found, 12) end
        local height = math.max(ICON, text) + 2 * ROW_PAD
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", page.content, "TOPLEFT", 0, y)
        row:SetSize(page.width, height)
        row.title:ClearAllPoints()
        row.title:SetPoint("TOPLEFT", row, "TOPLEFT", TEXT_LEFT, -math.floor((height - text) / 2))
        y = y - height
    end
    page.content:SetHeight(-y + 8)
end

function Songbook:Refresh()
    local page = self.page
    if not page then return end
    local music = ns.Music
    local listening = music:Previewing()
    local found = 0
    for _, row in ipairs(page.rows) do
        local song = row.song
        local learned = music:Learned(song.key)
        if learned then found = found + 1 end
        row.learned = learned
        row.title:SetText(song.label)
        -- Not found yet: grey, its icon too (like an unearned badge).
        row.icon:SetDesaturated(not learned)
        row.icon:SetVertexColor(learned and 1 or 0.45, learned and 1 or 0.45, learned and 1 or 0.45)
        if learned then
            row.title:SetTextColor(1, 0.82, 0)
            row.place:SetTextColor(1, 1, 1)
            row.place:SetText(song.event and L["From the Darkmoon Faire"] or PlaceName(song))
        else
            row.title:SetTextColor(0.55, 0.55, 0.55)
            row.place:SetTextColor(0.7, 0.7, 0.7)
            local zone = ZoneName(song)
            row.place:SetText(song.hint or song.event and zone and format(L["Found in %s during the Darkmoon Faire"], zone)
                or zone and format(L["Found somewhere in %s"], zone) or L["Not found yet"])
        end
        local when = learned and music:LearnedAt(song.key) or nil
        row.found:SetShown(when ~= nil)
        row.found:SetText(when and format(L["Found %s"], date("%Y-%m-%d", when)) or "")
        row.listen:SetShown(learned)
        row.listen:SetText(listening == song.key and L["Stop"] or L["Listen"])
    end
    self:UpdateListen()
    page.summary:SetText(format(L["Songs found: %d of %d"], found, #page.rows))
    self:Layout()
end

-- Listen works only at a camp (Music:CanListen); Stop always does. Looked at
-- again every tick while the tab is open, as you come and go.
function Songbook:UpdateListen()
    local page = self.page
    if not page then return end
    local can = ns.Music:CanListen()
    local listening = ns.Music:Previewing()
    for _, row in ipairs(page.rows) do
        row.listen:SetEnabled(can or listening == row.song.key)
    end
end

-- Listen, or Stop the song you're listening to.
function Songbook:Listen(key)
    if ns.Music:Previewing() == key then ns.Music:StopPreview() else ns.Music:Preview(key) end
    self:Refresh()
end

-- Found! ------------------------------------------------------------------------------
-- A song you find shows a card near the top of the screen in the game's own
-- "new recipe learned" frame (recipetoast-bg, laid out as the game lays it
-- out: the picture in its round window on the left, the heading at the top,
-- the name in the middle of the rest). A sound plays at once, then the song's first seconds, just for
-- you, fading out, unless a camp song is playing (then it's left alone). The
-- card fades away after a while, or at a click, which opens the Music tab.
-- Without that frame's art: the bronze frame of the other windows.
local RECIPE_FRAME = "recipetoast-bg"
local CARD_WIDTH, CARD_HEIGHT = 312, 89
local SHOW_FOR = 10         -- seconds before it starts fading
local SNIPPET = 16          -- seconds of the song that play
local SNIPPET_FADE = 2500   -- milliseconds it takes to fade out
local FOUND_SOUND = 38326   -- a sound kit, played the moment it's found

local function Card()
    if Songbook.card then return Songbook.card end
    local style = ns.Style
    local f = CreateFrame("Button", "HappyCamperSongToast", UIParent)
    f:SetSize(CARD_WIDTH, CARD_HEIGHT)
    f:SetPoint("TOP", UIParent, "TOP", 0, -110)
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:SetFrameLevel(40)
    local recipe = ns.Style:HasAtlas(RECIPE_FRAME)
    if recipe then
        f.bg = f:CreateTexture(nil, "BACKGROUND")
        f.bg:SetAtlas(RECIPE_FRAME, true)
        f.bg:SetPoint("CENTER")
    else
        style:HeavyBronze(f)
    end
    -- Under the frame, seen through its round window.
    f.icon = f:CreateTexture(nil, "BACKGROUND", nil, -1)
    f.icon:SetSize(64, 64)
    f.icon:SetPoint("LEFT", 18, 0)
    f.icon:SetTexture(SONG_ICON)
    if not recipe then f.icon:SetDrawLayer("ARTWORK") end
    f.heading = style:Text(f, "GameFontHighlight", L["Song found"], "CENTER")
    f.heading:SetPoint("TOP", 31, -15)
    -- The title and where, together in the middle of the space right of the picture.
    f.title = style:Text(f, "GameFontNormal", nil, "CENTER")
    f.place = style:Text(f, "GameFontHighlightSmall", nil, "CENTER")
    for _, text in ipairs({ f.title, f.place }) do
        text:SetWidth(CARD_WIDTH - 98 - 32)
        text:SetWordWrap(false)
    end
    f.title:SetPoint("TOP", f, "TOPLEFT", 98 + (CARD_WIDTH - 98 - 32) / 2, -36)
    f.place:SetPoint("TOP", f.title, "BOTTOM", 0, -3)

    -- Fades in, waits, and fades out.
    f.show = f:CreateAnimationGroup()
    local fadeIn = f.show:CreateAnimation("Alpha")
    fadeIn:SetFromAlpha(0)
    fadeIn:SetToAlpha(1)
    fadeIn:SetDuration(0.4)
    local fadeOut = f.show:CreateAnimation("Alpha")
    fadeOut:SetFromAlpha(1)
    fadeOut:SetToAlpha(0)
    fadeOut:SetDuration(1.2)
    fadeOut:SetStartDelay(SHOW_FOR)
    f.show:SetScript("OnFinished", function() f:Hide() end)
    f:SetScript("OnClick", function()
        f.show:Stop()
        f:Hide()
        ns.Hub:Open("music")
    end)
    f:Hide()
    Songbook.card = f
    return f
end

-- The card's title, never cut off: a long one (or translation) takes the
-- smaller font, then two lines.
local function FitTitle(title, text)
    local function Wide()
        local w = title.GetUnboundedStringWidth and title:GetUnboundedStringWidth()
        if type(w) ~= "number" then w = ns.Style:TextWidth(title) end
        return w > CARD_WIDTH - 98 - 32
    end
    title:SetFontObject(GameFontNormal)
    title:SetWordWrap(false)
    title:SetText(text)
    if not Wide() then return end
    title:SetFontObject(GameFontNormalSmall)
    if Wide() then title:SetWordWrap(true) end
end

-- Shows a song just found (Music:Inspire).
function Songbook:Celebrate(song)
    local f = Card()
    FitTitle(f.title, song.label)
    f.place:SetText(PlaceName(song))
    f.song = song
    f:Show()
    f.show:Stop()
    f.show:Play()
    PlaySound(FOUND_SOUND)
    -- Gone once the fade is done (also if the animation never says so).
    local shownAt = GetTime()
    f.shownAt = shownAt
    C_Timer.After(SHOW_FOR + 1.4, function()
        if f.shownAt == shownAt then f:Hide() end
    end)
    -- Its first seconds, over the game's music, fading out; not over a camp song.
    if ns.Music:IsPlaying() or ns.Music:Previewing() then return end
    local file = song.files and song.files[1] and song.files[1][1]
    if not file then return end
    local willPlay, handle = PlaySoundFile(file, "Music")
    if willPlay and handle then
        f.snippet = handle
        C_Timer.After(SNIPPET, function()
            if f.snippet == handle then
                StopSound(handle, SNIPPET_FADE)
                f.snippet = nil
            end
        end)
    end
end
