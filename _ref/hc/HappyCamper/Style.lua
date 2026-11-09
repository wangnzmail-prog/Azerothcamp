-- Happy Camper. Copyright (c) 2026 Torridon. All rights reserved; see LICENSE.
local addonName, ns = ...

-- Shared look, built from Forever's own art so it matches the game:
--   window      portrait frame (the Character/Professions frame, gallery A)
--   background  the Professions quality window art, fitted (PAGE_BACKGROUND);
--               the dev tools' gallery (/hc gallery) can try other art
--   sections    inset panels (gallery K) and thin gold dividers
--   tabs        classic bottom tabs (gallery N)
--   Find a camp heavy bronze, from Forever's character creation (gallery H)

local Style = {}
ns.Style = Style

-- Happy Camper's own art, in the Media folder (TGA; WoW can't load PNG).
Style.MEDIA = "Interface\\AddOns\\" .. addonName .. "\\Media\\"
Style.EMBLEM = Style.MEDIA .. "Emblem"     -- the HC campfire, close up: the addon list, badges not drawn yet
Style.PORTRAIT = Style.MEDIA .. "Portrait" -- the same, wider, so it fits a window's round portrait
Style.MODE_STANDARD = Style.MEDIA .. "ModeStandard" -- the mode cards' round pictures (art/tools/make_mode_cards.py)
Style.MODE_ENHANCED = Style.MEDIA .. "ModeEnhanced"
Style.MINIMAP_ICON = Style.MEDIA .. "MinimapIcon" -- the Standard card's campfire, small and round
Style.RING = Style.MEDIA .. "Ring"         -- a bronze ring for round pictures, sharp at any size (art/ring/make_ring.py)
Style.RING_HOLE = 0.82                     -- a picture inside it is this much of the ring's size

-- Forever's per-profession background art ("Profession-background-card-<name>").
Style.PROFESSION_CARDS = { "Alchemy", "Blacksmithing", "Enchanting", "Engineering", "Herbalism",
    "Leatherworking", "Mining", "Skinning", "Tailoring", "Cooking", "Fishing", "FirstAid" }
Style.FALLBACK_BACKGROUND = "Profession-Background-Overview"

-- Whether this client has an atlas.
function Style:HasAtlas(atlas)
    return atlas ~= nil and C_Texture ~= nil and C_Texture.GetAtlasInfo ~= nil and C_Texture.GetAtlasInfo(atlas) ~= nil
end

local function HasAtlas(atlas)
    return Style:HasAtlas(atlas)
end

-- A random profession card that exists in this client, or the Professions
-- window background if none do.
function Style:RandomCard()
    local cards = {}
    for _, name in ipairs(self.PROFESSION_CARDS) do
        local atlas = "Profession-background-card-" .. name
        if HasAtlas(atlas) then cards[#cards + 1] = atlas end
    end
    return cards[math.random(math.max(1, #cards))] or self.FALLBACK_BACKGROUND
end

-- The dark fill under the window's art (the template's own Bg is hidden).
Style.BACKGROUND_FILL = { 0.082, 0.086, 0.059 }

-- The part of an atlas that covers a width x height area without stretching:
-- its middle, cropped to that shape. Left, right, top, bottom texture coordinates.
function Style:AtlasCoords(info, width, height)
    local l, r = info.leftTexCoord or 0, info.rightTexCoord or 1
    local t, b = info.topTexCoord or 0, info.bottomTexCoord or 1
    local have = (info.width or 1) / math.max(1, info.height or 1)
    local want = (width and height and height > 0) and width / height or have
    if have > want then
        local cut = (r - l) * (1 - want / have) / 2
        l, r = l + cut, r - cut
    else
        local cut = (b - t) * (1 - have / want) / 2
        t, b = t + cut, b - cut
    end
    return l, r, t, b
end

-- A layer for game art over the whole window, fitted to its shape.
local function AtlasLayer(frame)
    if not frame.hcAtlas then
        local layer = frame:CreateTexture(nil, "BACKGROUND", nil, 1)
        layer:SetAllPoints(frame.Bg)
        frame.hcAtlas = layer
    end
    return frame.hcAtlas
end

-- A solid fill under the art, on a layer of its own: the window's Bg tiles its
-- texture (horizTile/vertTile in the template), and a flat colour or a
-- stretched picture on it can show nothing at all, so it's hidden instead.
local function FillLayer(frame)
    if not frame.hcFill then
        local fill = frame:CreateTexture(nil, "BACKGROUND", nil, 0)
        fill:SetAllPoints(frame.Bg)
        fill:SetColorTexture(unpack(Style.BACKGROUND_FILL))
        frame.hcFill = fill
    end
    frame.Bg:Hide()
    frame.hcFill:Show()
    return frame.hcFill
end

-- A window's background art (an atlas): with fit, cropped to the window's
-- shape instead of stretched (a wide picture on a tall window looks empty).
-- Keeps Blizzard's rock texture if the art is missing.
function Style:ApplyBackground(frame, atlas, fit)
    if not frame.Bg then return end
    if atlas and HasAtlas(atlas) then
        if fit then
            FillLayer(frame)
            local layer = AtlasLayer(frame)
            layer:SetAtlas(atlas)
            local width, height = layer:GetWidth(), layer:GetHeight()
            if not (width and width > 0 and height and height > 0) then width, height = frame:GetWidth(), frame:GetHeight() end
            layer:SetTexCoord(self:AtlasCoords(C_Texture.GetAtlasInfo(atlas), width, height))
            layer.atlasName = atlas
            layer:Show()
        else
            SetTextureWithAddressModeOptions(frame.Bg, atlas)
            frame.Bg:Show()
            if frame.hcAtlas then frame.hcAtlas:Hide() end
            if frame.hcFill then frame.hcFill:Hide() end
        end
    else
        return
    end
    if frame.TopTileStreaks then frame.TopTileStreaks:Hide() end
end

-- The art behind every tab of the Happy Camper window and the panel: the
-- game's Professions quality window art, fitted to the frame (a profession
-- card if a client lacks it), or whatever the gallery picked.
Style.PAGE_BACKGROUND = "Professions-QualityWindow-Background"

function Style:ApplyPageBackground(frame)
    local atlas = ns.db.background or self.PAGE_BACKGROUND
    if not HasAtlas(atlas) then atlas = self:RandomCard() end
    self:ApplyBackground(frame, atlas, true)
end

-- A recessed panel behind a section. Sits just above the window background and
-- below the page's own content.
-- Filled with heavy bronze (Forever's character creation art), or a warm brown
-- where that's missing, instead of the template's black.
Style.INSET_FILL = { 0.20, 0.13, 0.07, 0.95 }

function Style:Inset(page, window, left, top, right, bottom)
    local inset = CreateFrame("Frame", nil, page, "InsetFrameTemplate")
    inset:SetPoint("TOPLEFT", left, top)
    inset:SetPoint("BOTTOMRIGHT", page, "TOPRIGHT", -right, bottom)
    inset:SetFrameLevel(window:GetFrameLevel() + 2)
    local fill = inset:CreateTexture(nil, "BACKGROUND", nil, 2)
    if type(inset.Bg) == "table" then fill:SetAllPoints(inset.Bg) else fill:SetAllPoints() end
    if HasAtlas("heavybronze-frame-background") then
        fill:SetAtlas("heavybronze-frame-background")
    else
        fill:SetColorTexture(unpack(self.INSET_FILL))
    end
    inset.fill = fill
    return inset
end

-- A thin gold rule across a page.
function Style:Divider(parent, y, inset)
    inset = inset or 16
    local divider = parent:CreateTexture(nil, "ARTWORK")
    divider:SetColorTexture(1, 0.82, 0.4, 0.35)
    divider:SetHeight(1)
    divider:SetPoint("LEFT", parent, "TOPLEFT", inset, y)
    divider:SetPoint("RIGHT", parent, "TOPRIGHT", -inset, y)
    return divider
end

-- A standard red panel button.
function Style:Button(parent, width, text, onClick, height)
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetSize(width, height or 22)
    Style:FitText(button, width)
    button:SetText(text)
    if onClick then button:SetScript("OnClick", onClick) end
    return button
end

-- Makes a button grow to fit its text whenever the text changes (translations
-- can be longer than the English), never narrower than width.
function Style:FitText(button, width)
    button.hcMinWidth = width
    local setText = button.SetText
    button.SetText = function(self, text)
        setText(self, text)
        local label = self.GetFontString and self:GetFontString()
        local needed = label and Style:TextWidth(label) + 20 or 0
        self:SetWidth(math.max(self.hcMinWidth or width, math.ceil(needed)))
    end
end

-- A font string's width, or 0 where it can't be measured.
function Style:TextWidth(text)
    local width = text and text.GetStringWidth and text:GetStringWidth()
    return type(width) == "number" and width or 0
end

-- A font string's height, rounded up, and at least least (also where it can't
-- be measured).
function Style:TextHeight(text, least)
    local height = text and text.GetStringHeight and text:GetStringHeight()
    least = least or 0
    if type(height) ~= "number" or height < least then height = least end
    return math.ceil(height)
end

-- A small question window (Season's launch choice, a layer invite): sized
-- around its text, its two buttons the size of the longer label, side by side
-- and centred at the bottom. size: { width, pad, button, gap, top, room }
-- (the least width, the text's side margins, the least button width, the gap
-- between the buttons, the room above the text and below it).
function Style:PromptLayout(f, text, left, right, size)
    local width = self:SameWidth({ left, right }, size.button)
    width = math.max(size.width, 2 * width + size.gap + 2 * size.pad)
    f.text:SetWidth(width - 2 * size.pad)
    f.text:SetText(text)
    f:SetSize(width, math.ceil(size.top + self:TextHeight(f.text, 14) + size.room))
    left:ClearAllPoints()
    left:SetPoint("BOTTOMRIGHT", f, "BOTTOM", -size.gap / 2, 22)
    right:ClearAllPoints()
    right:SetPoint("BOTTOMLEFT", f, "BOTTOM", size.gap / 2, 22)
end

-- Buttons side by side are one size: the widest of them (a translation may
-- have made one grow). Returns that width.
function Style:SameWidth(buttons, least)
    local width = least or 0
    for _, button in ipairs(buttons) do
        local w = button:GetWidth()
        if type(w) == "number" and w > width then width = w end
    end
    for _, button in ipairs(buttons) do button:SetWidth(width) end
    return width
end

-- Buttons (made with Style:Button) whose text changes, like Play / Stop, keep
-- one width whatever they say: the widest any of texts needs, at least least.
-- Every button in the list gets it, and keeps its text. Returns that width.
function Style:FitTexts(buttons, texts, least)
    local width = least or 0
    local measure = buttons[1]
    local before = measure:GetText()
    for _, text in ipairs(texts) do
        measure:SetText(text)
        local w = measure:GetWidth()
        if type(w) == "number" and w > width then width = w end
    end
    measure:SetText(before)
    for _, button in ipairs(buttons) do button.hcMinWidth = width end
    return self:SameWidth(buttons, width)
end

-- A font string, optionally with text and justification ("LEFT").
function Style:Text(parent, font, text, justify)
    local label = parent:CreateFontString(nil, "OVERLAY", font)
    if text then label:SetText(text) end
    if justify then label:SetJustifyH(justify) end
    return label
end

-- A tab's title: centred in the space between the window's title bar and the
-- page, a little larger than GameFontNormal (same font, so every client
-- language has its letters). The page's width keeps a long translation from
-- running past the window's edges.
Style.PAGE_TITLE_Y = 17 -- its middle, above the page's top
function Style:PageTitle(page, text)
    local title = self:Text(page, "GameFontNormal", text, "CENTER")
    local base = _G.GameFontNormal
    local font, size, flags
    if base and base.GetFont then font, size, flags = base:GetFont() end
    if font and size then title:SetFont(font, size + 2, flags) end
    title:SetPoint("CENTER", page, "TOP", 0, self.PAGE_TITLE_Y)
    title:SetWidth((page:GetWidth() or 0) > 0 and page:GetWidth() - 32 or 460)
    title:SetWordWrap(false)
    return title
end

-- A left-aligned font string on one line: cut off rather than wrapped.
function Style:Line(parent, font, text)
    local label = self:Text(parent, font, text, "LEFT")
    label:SetWordWrap(false)
    return label
end

-- Lets a frame be dragged around. With pointKey its position is saved in
-- ns.db[pointKey] and put back from there; canMove can veto a drag.
function Style:Movable(frame, pointKey, canMove)
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", canMove and function(self) if canMove() then self:StartMoving() end end
        or frame.StartMoving)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        if pointKey then
            local point, _, relativePoint, x, y = self:GetPoint()
            ns.db[pointKey] = { point, relativePoint, x, y }
        end
    end)
    local p = pointKey and ns.db[pointKey]
    if p then frame:SetPoint(p[1], UIParent, p[2], p[3], p[4]) end
end

-- A movable portrait window (like the Character and Professions windows) that
-- Escape closes. Starts hidden.
function Style:Window(name, width, height, strata, title, icon, pointKey)
    local f = CreateFrame("Frame", name, UIParent, "PortraitFrameTemplate")
    f:SetSize(width, height)
    f:SetFrameStrata(strata)
    f:SetToplevel(true)
    self:Movable(f, pointKey)
    f:SetTitle(title)
    f:SetPortraitToAsset(icon)
    f:Hide()
    if UISpecialFrames then tinsert(UISpecialFrames, name) end
    return f
end

-- Sets up a scroll frame (already placed): a scroll child of the given size,
-- and a thin scroll bar down its right edge that shows only when needed.
function Style:ScrollArea(scroll, childWidth, childHeight)
    scroll.child = CreateFrame("Frame", nil, scroll)
    scroll.child:SetSize(childWidth, childHeight)
    scroll:SetScrollChild(scroll.child)
    scroll.scrollBar = CreateFrame("EventFrame", nil, scroll:GetParent(), "MinimalScrollBar")
    scroll.scrollBar:SetPoint("TOPRIGHT", scroll, "TOPRIGHT", 0, 0)
    scroll.scrollBar:SetPoint("BOTTOMRIGHT", scroll, "BOTTOMRIGHT", 0, 0)
    scroll.scrollBar:SetHideIfUnscrollable(true)
    ScrollUtil.InitScrollFrameWithScrollBar(scroll, scroll.scrollBar)
end

-- A dropdown menu button; setup(owner, root) builds its menu each time it opens.
-- In the game's controller mode the menu is Happy Camper's own (Menu.lua).
function Style:Dropdown(parent, width, setup)
    local dropdown = CreateFrame("DropdownButton", nil, parent, "WowStyle1DropdownTemplate")
    dropdown:SetWidth(width)
    dropdown:SetupMenu(setup)
    local setMenuOpen = dropdown.SetMenuOpen
    dropdown.SetMenuOpen = function(self, open)
        if ns.IsGamepad() then return ns.Menu:Toggle(self, self.menuGenerator) end
        return setMenuOpen(self, open)
    end
    return dropdown
end

-- Shows a dropdown's chosen entry on its button (the menu marks it too): the
-- entry in list whose [key] is value, by its [text].
function Style:ShowChoice(dropdown, list, value, key, text)
    for _, entry in ipairs(list) do
        if entry[key] == value and dropdown.OverrideText then dropdown:OverrideText(entry[text]) end
    end
end

local function HideTooltip() GameTooltip:Hide() end

-- A hover tooltip that fill(tooltip, frame) builds each time it shows. A live
-- one is rebuilt every second while shown (ns.ShowLiveTooltip), for countdowns.
function Style:CustomTooltip(frame, anchor, fill, live)
    frame:SetScript("OnEnter", function(self)
        if live then return ns.ShowLiveTooltip(self, anchor, function(tooltip) fill(tooltip, self) end) end
        GameTooltip:SetOwner(self, anchor)
        fill(GameTooltip, self)
        GameTooltip:Show()
    end)
    frame:SetScript("OnLeave", HideTooltip)
end

-- A simple hover tooltip. title and body may be functions, for text that changes.
-- Help tips (what a button or menu does) show while Options says so; they're
-- for new players. Info tooltips (buffs, items, camps, messages, why something
-- is greyed out) always show.
function Style:ShowHelp()
    return not ns.db or ns.db.helpTips ~= false
end

-- An info tooltip: a title and a line or two, always shown.
function Style:InfoTooltip(frame, title, body, anchor)
    self:CustomTooltip(frame, anchor or "ANCHOR_TOP", function(tooltip)
        tooltip:AddLine(type(title) == "function" and title() or title)
        local text = type(body) == "function" and body() or body
        if text then tooltip:AddLine(text, 1, 1, 1, true) end
    end)
end

-- A help tip: a title and what it does. With help tips off, a button with a
-- label shows none, and an icon-only button (frame.hcIconOnly) just its name.
function Style:Tooltip(frame, title, body, anchor)
    self:CustomTooltip(frame, anchor or "ANCHOR_TOP", function(tooltip)
        tooltip:AddLine(type(title) == "function" and title() or title)
        local text = Style:ShowHelp() and (type(body) == "function" and body() or body)
        if text then tooltip:AddLine(text, 1, 1, 1, true) end
    end)
    self:OnlyWithHelp(frame)
end

-- Makes a frame's tooltip a help tip: none with help tips off (icon-only
-- frames still show theirs, as it's their name).
function Style:OnlyWithHelp(frame)
    local enter = frame:GetScript("OnEnter")
    if not enter then return end
    frame:SetScript("OnEnter", function(self, ...)
        if not Style:ShowHelp() and not self.hcIconOnly then return end
        return enter(self, ...)
    end)
end

-- A "Click to..." hint at the end of an info tooltip: a help tip.
function Style:AddHint(tooltip, text, wrap)
    if self:ShowHelp() then tooltip:AddLine(text, 0.5, 0.8, 1, wrap) end
end

-- Keeps a controller addon's cursor (ConsolePort's) off a frame and everything
-- in it. That cursor runs a frame's own scripts outside the game's protected
-- path, so on the world map, landing on one of Happy Camper's frames as the map
-- opened tied its own next protected action to Happy Camper, and the game
-- blocked it. Only that cursor reads these attributes (nodeignore: skip this
-- frame; nodesingleton: and don't look inside it): with a mouse nothing changes.
function Style:SkipControllerCursor(frame)
    pcall(frame.SetAttribute, frame, "nodeignore", true)
    pcall(frame.SetAttribute, frame, "nodesingleton", true)
end

-- A square icon button with a highlight and a tooltip.
function Style:IconButton(parent, size, texture, onClick, title, body)
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(size, size)
    button:SetNormalTexture(texture)
    button:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    button:SetScript("OnClick", onClick)
    button.hcIconOnly = true
    self:Tooltip(button, title, body)
    return button
end

-- Heavy bronze frame: background, border and the four corner brackets.
-- The game's metal window frame, the world map's, so a frame docked under the
-- map matches it: over HeavyBronze's dark fill. Its top is the frame's bottom
-- edge and corners turned upside down (a window's own top is its title bar).
-- Offsets are the map's (NineSliceLayouts' PortraitFrameTemplateMinimizable,
-- with Forever's overrides): the left side 13 pixels out, the right 2, the
-- bottom 8 down, and so the top 8 up. Falls back to HeavyBronze's border.
local METAL_CORNERS = {
    -- key, atlas, point, x, y, upside down
    { "BL", "UI-Frame-Metal-CornerBottomLeft", "BOTTOMLEFT", -13, -8 },
    { "BR", "UI-Frame-Metal-CornerBottomRight", "BOTTOMRIGHT", 2, -8 },
    { "TL", "UI-Frame-Metal-CornerBottomLeft", "TOPLEFT", -13, 8, true },
    { "TR", "UI-Frame-Metal-CornerBottomRight", "TOPRIGHT", 2, 8, true },
}
Style.METAL_OVERHANG = 8 -- how far the metal top and bottom reach past the frame
Style.METAL_LEFT, Style.METAL_RIGHT = -METAL_CORNERS[1][4], METAL_CORNERS[2][4] -- and its sides

function Style:MetalFrame(frame, fitsItself)
    self:HeavyBronze(frame)
    if frame.metal or not HasAtlas("UI-Frame-Metal-CornerBottomLeft") or not HasAtlas("_UI-Frame-Metal-EdgeBottom")
        or not HasAtlas("!UI-Frame-Metal-EdgeLeft") then
        return
    end
    local b = frame.bronze
    b.border:Hide()
    for _, t in pairs(b.corners) do t:Hide() end
    local m = {}
    frame.metal = m
    local function Piece(atlas, upsideDown)
        local t = frame:CreateTexture(nil, "OVERLAY")
        -- Flipped before the atlas is set, as the game's own frames do.
        if upsideDown then t:SetTexCoord(0, 1, 1, 0) end
        local info = C_Texture.GetAtlasInfo(atlas)
        t:SetHorizTile(info and info.tilesHorizontally or false)
        t:SetVertTile(info and info.tilesVertically or false)
        t:SetAtlas(atlas, true)
        return t
    end
    for _, corner in ipairs(METAL_CORNERS) do
        m[corner[1]] = Piece(corner[2], corner[6])
        m[corner[1]]:SetPoint(corner[3], frame, corner[3], corner[4], corner[5])
    end
    m.bottom = Piece("_UI-Frame-Metal-EdgeBottom")
    m.bottom:SetPoint("BOTTOMLEFT", m.BL, "BOTTOMRIGHT")
    m.bottom:SetPoint("BOTTOMRIGHT", m.BR, "BOTTOMLEFT")
    m.top = Piece("_UI-Frame-Metal-EdgeBottom", true)
    m.top:SetPoint("TOPLEFT", m.TL, "TOPRIGHT")
    m.top:SetPoint("TOPRIGHT", m.TR, "TOPLEFT")
    m.left = Piece("!UI-Frame-Metal-EdgeLeft")
    m.left:SetPoint("TOPLEFT", m.TL, "BOTTOMLEFT")
    m.left:SetPoint("BOTTOMLEFT", m.BL, "TOPLEFT")
    m.right = Piece("!UI-Frame-Metal-EdgeRight")
    m.right:SetPoint("TOPRIGHT", m.TR, "BOTTOMRIGHT")
    m.right:SetPoint("BOTTOMRIGHT", m.BR, "TOPRIGHT")
    Style:FitMetal(frame)
    -- Refitted as it changes size, unless its owner does that (fitsItself: the
    -- map dock, which runs nothing while the map opens or resizes).
    if not fitsItself then frame:HookScript("OnSizeChanged", function(self) Style:FitMetal(self) end) end
end

-- On a frame too short for two corners (the map dock with only its camp bar),
-- the corners would reach past each other and out of the frame: each is
-- trimmed by half the overlap, from the side away from its own corner, and the
-- side edges (with no room left) hide. The same across, on a frame too narrow
-- for two (the window's side tabs), and the top and bottom edges hide. The
-- game does the same for its own windows (NineSliceUtil.UpdateCornerCropping).
local METAL_ACROSS = Style.METAL_LEFT + Style.METAL_RIGHT -- how far the metal reaches past both sides

function Style:FitMetal(frame)
    local m = frame.metal
    local width, height = frame:GetWidth(), frame:GetHeight()
    if not m or type(height) ~= "number" or height <= 0 then return end
    local info = C_Texture.GetAtlasInfo(METAL_CORNERS[1][2])
    local file = info and (info.file or info.filename)
    if not file or not info.height or info.height <= 0 then return end
    local overlap = 2 * info.height - height - 2 * self.METAL_OVERHANG
    local crop = math.max(0, math.min(info.height - 1, math.ceil(overlap / 2)))
    local across = (type(width) == "number" and width > 0 and info.width) and 2 * info.width - width - METAL_ACROSS or -1
    local cropX = math.max(0, math.min((info.width or 1) - 1, math.ceil(across / 2)))
    for _, corner in ipairs(METAL_CORNERS) do
        local t = m[corner[1]]
        local cornerInfo = C_Texture.GetAtlasInfo(corner[2]) or info
        local range = cornerInfo.bottomTexCoord - cornerInfo.topTexCoord
        local cut = cornerInfo.topTexCoord + (crop / cornerInfo.height) * range
        -- Across, a left corner keeps its left columns, a right one its right.
        local left, right = cornerInfo.leftTexCoord, cornerInfo.rightTexCoord
        if cropX > 0 then
            local cutX = (cropX / cornerInfo.width) * (right - left)
            if corner[3]:find("LEFT") then right = right - cutX else left = left + cutX end
        end
        t:SetTexture(cornerInfo.file or cornerInfo.filename or file)
        -- The kept part is the one at the frame's edge: a bottom corner's
        -- lower rows; an upside-down top corner shows the same rows, flipped.
        if corner[6] then
            t:SetTexCoord(left, right, cornerInfo.bottomTexCoord, cut)
        else
            t:SetTexCoord(left, right, cut, cornerInfo.bottomTexCoord)
        end
        t:SetSize(cornerInfo.width - cropX, cornerInfo.height - crop)
    end
    m.left:SetShown(overlap < 0)
    m.right:SetShown(overlap < 0)
    m.top:SetShown(across < 0)
    m.bottom:SetShown(across < 0)
end

function Style:HeavyBronze(frame)
    frame.bronze = frame.bronze or {}
    local b = frame.bronze
    if not b.bg then
        b.bg = frame:CreateTexture(nil, "BACKGROUND")
        b.bg:SetAllPoints()
        b.border = frame:CreateTexture(nil, "BORDER")
        b.border:SetAllPoints()
        b.corners = {}
        for _, corner in ipairs({ "TL", "TR", "BL", "BR" }) do
            local t = frame:CreateTexture(nil, "ARTWORK")
            t:SetPoint((corner:sub(1, 1) == "T" and "TOP" or "BOTTOM") .. (corner:sub(2) == "L" and "LEFT" or "RIGHT"))
            b.corners[corner] = t
        end
    end
    if HasAtlas("heavybronze-frame-basic") then
        b.bg:SetAtlas("heavybronze-frame-background")
        b.border:SetAtlas("heavybronze-frame-basic")
        for corner, t in pairs(b.corners) do
            t:SetAtlas("heavybronze-horz-cornerbracket-" .. corner, true)
            t:Show()
        end
    else
        -- Fallback if the atlas is ever renamed: a plain dark panel.
        b.bg:SetColorTexture(0.08, 0.06, 0.04, 0.95)
        b.border:SetColorTexture(0, 0, 0, 0)
        for _, t in pairs(b.corners) do t:Hide() end
    end
end

-- Planning tabs (the Group tab and the Camp Builder) ---------------------------------
-- Both read the same way: figures in tiles along the top, then a panel with a
-- row per camp buff (a mark for where it stands, the object's icon, the buff
-- with its profession under it, the tab's own column, and Camp Setup as a pill
-- in the state's colour; rows with nothing left to decide are dimmed), then
-- a second panel below.

-- Where things go: a panel's rows and their columns (from the row's left).
Style.PLAN = {
    INNER = 6,         -- a panel's edge to its rows
    LIST_TOP = 20,     -- a panel's top to its first row (its headings above)
    ROW_HEIGHT = 26,   -- a camp buff's row: the buff, its profession under it
    ICON_X = 16, BUFF_X = 42, MID_X = 150, SETUP_X = 292,
    TILE_HEIGHT = 38,
    GAP = 8,           -- between a tab's parts
}
local PLAN = Style.PLAN
PLAN.ROW_WIDTH = 500 - 2 * 16 - 2 * PLAN.INNER
PLAN.BUFF_WIDTH = PLAN.MID_X - PLAN.BUFF_X - 6
PLAN.MID_WIDTH = PLAN.SETUP_X - PLAN.MID_X - 6
PLAN.SETUP_WIDTH = PLAN.ROW_WIDTH - PLAN.SETUP_X

-- Each state a camp buff's row can be in: its mark, its Camp Setup pill's
-- colour (pill: a wash and a border; else plain text) and how bright the row is.
Style.PLAN_STATES = {
    placed = { mark = "Interface\\RaidFrame\\ReadyCheck-Ready", color = { 0.4, 1, 0.4 }, pill = true, alpha = 0.65 },
    coming = { mark = "Interface\\RaidFrame\\ReadyCheck-Ready", color = { 0.4, 1, 0.4 }, alpha = 1 },
    ready = { mark = "Interface\\COMMON\\Indicator-Green", color = { 0.4, 1, 0.4 }, pill = true, alpha = 1 },
    waiting = { mark = "Interface\\COMMON\\Indicator-Yellow", color = { 1, 0.6, 0.2 }, pill = true, alpha = 1 },
    unknown = { mark = "Interface\\COMMON\\Indicator-Gray", color = { 0.67, 0.67, 0.67 }, pill = true, alpha = 1 },
    yours = { color = { 1, 0.82, 0 }, pill = true, alpha = 1, tint = true }, -- its mark: ready's or waiting's
    open = { mark = "Interface\\RaidFrame\\ReadyCheck-Waiting", color = { 1, 1, 1 }, pill = true, alpha = 1 },
    offer = { color = { 1, 1, 1 }, pill = true, alpha = 1 },          -- you could bring it
    canmake = { color = { 0.67, 0.67, 0.67 }, pill = true, alpha = 1 },
    covered = { color = { 0.2, 0.6, 1 }, alpha = 0.55 },
    nobody = { color = { 0.67, 0.67, 0.67 }, alpha = 0.45 },
}

-- A dark inset panel, as the game's windows have, placed by its parent.
function Style:Panel(parent)
    local panel = CreateFrame("Frame", nil, parent, "InsetFrameTemplate")
    local fill = panel:CreateTexture(nil, "BACKGROUND", nil, 2)
    if type(panel.Bg) == "table" then fill:SetAllPoints(panel.Bg) else fill:SetAllPoints() end
    if HasAtlas("heavybronze-frame-background") then
        fill:SetAtlas("heavybronze-frame-background")
    else
        fill:SetColorTexture(unpack(self.INSET_FILL))
    end
    return panel
end

-- A figure along the top: a number (big), what it counts beside it, a line
-- under them, and a tooltip (tile.tipTitle, tile.tipLines) for the rest.
function Style:Tile(parent, width)
    local tile = self:Panel(parent)
    tile:SetSize(width, PLAN.TILE_HEIGHT)
    tile.big = self:Text(tile, "GameFontHighlightLarge", nil, "LEFT")
    tile.big:SetPoint("TOPLEFT", 9, -6)
    tile.label = self:Text(tile, "GameFontNormalSmall", nil, "LEFT")
    tile.label:SetPoint("LEFT", tile.big, "RIGHT", 5, 0)
    tile.label:SetPoint("RIGHT", tile, "RIGHT", -6, 0)
    tile.label:SetWordWrap(false)
    tile.sub = self:Text(tile, "GameFontHighlightSmall", nil, "LEFT")
    tile.sub:SetPoint("BOTTOMLEFT", 9, 6)
    tile.sub:SetPoint("RIGHT", tile, "RIGHT", -6, 0)
    tile.sub:SetWordWrap(false)
    self:CustomTooltip(tile, "ANCHOR_BOTTOM", function(tooltip, frame)
        tooltip:SetText(frame.tipTitle or "")
        for _, line in ipairs(frame.tipLines or {}) do tooltip:AddLine(line, 1, 1, 1, true) end
    end)
    return tile
end

-- A panel's column headings: { { text, x }, ... }, x from a row's left.
function Style:Headings(panel, headings)
    local texts = {}
    for i, heading in ipairs(headings) do
        texts[i] = self:Text(panel, "GameFontNormalSmall", heading[1], "LEFT")
        texts[i]:SetPoint("TOPLEFT", PLAN.INNER + heading[2], -6)
    end
    return texts
end

-- A camp buff's row in a panel: row.tint (your own, lit gold), row.mark,
-- row.icon, row.buff and row.trade (its profession) under it.
function Style:PlanRow(parent, profession, y)
    local row = CreateFrame("Frame", nil, parent)
    row:SetPoint("TOPLEFT", PLAN.INNER, y)
    row:SetSize(PLAN.ROW_WIDTH, PLAN.ROW_HEIGHT)
    row.profession = profession
    row.tint = row:CreateTexture(nil, "BACKGROUND")
    row.tint:SetAllPoints()
    row.tint:SetColorTexture(1, 0.82, 0, 0.08)
    row.tint:Hide()
    row.mark = row:CreateTexture(nil, "ARTWORK")
    row.mark:SetSize(12, 12)
    row.mark:SetPoint("LEFT", 1, 0)
    row.mark:Hide()
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(20, 20)
    row.icon:SetPoint("LEFT", PLAN.ICON_X, 0)
    row.icon:SetTexture(profession.icon) -- the profession: its item depends on the tier
    row.buff = self:Text(row, "GameFontHighlightSmall", profession.buff, "LEFT")
    row.buff:SetPoint("TOPLEFT", PLAN.BUFF_X, -3)
    row.buff:SetWidth(PLAN.BUFF_WIDTH)
    row.buff:SetWordWrap(false)
    row.trade = self:Text(row, "GameFontDisableSmall", profession.name, "LEFT")
    row.trade:SetPoint("TOPLEFT", row.buff, "BOTTOMLEFT", 0, -1)
    row.trade:SetWidth(PLAN.BUFF_WIDTH)
    row.trade:SetWordWrap(false)
    return row
end

-- A row's state: how bright, lit gold for yours, and its mark (or mark, for
-- a state that takes another's).
function Style:SetPlanState(row, look, mark)
    row:SetAlpha(look.alpha)
    row.tint:SetShown(look.tint == true)
    mark = look.mark or mark
    row.mark:SetShown(mark ~= nil)
    if mark then row.mark:SetTexture(mark) end
end

local PILL_EDGE = { bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    edgeSize = 10, insets = { left = 2, right = 2, top = 2, bottom = 2 } }

-- Camp Setup's pill: pill.text, in a wash and border of the state's colour.
function Style:Pill(parent)
    local pill = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    pill:SetHeight(18)
    if pill.SetBackdrop then pill:SetBackdrop(PILL_EDGE) end
    pill.text = self:Text(pill, "GameFontHighlightSmall", nil, "LEFT")
    pill.text:SetPoint("LEFT", 8, 0)
    pill.text:SetWordWrap(false)
    return pill
end

-- A button over a pill that opens a menu (generator), with a small arrow.
function Style:PillMenu(pill, generator)
    local button = CreateFrame("Button", nil, pill)
    button:SetAllPoints()
    button:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    button.arrow = button:CreateTexture(nil, "OVERLAY")
    button.arrow:SetTexture("Interface\\Buttons\\Arrow-Down-Up")
    button.arrow:SetSize(10, 10)
    button.arrow:SetPoint("RIGHT", -5, -2)
    button.menuGenerator = generator
    button:SetScript("OnClick", function(self) ns.Menu:Context(self, self.menuGenerator) end)
    button:Hide()
    return button
end

-- Fits a pill to its text and state, within room: a wash and border in the
-- state's colour (none for a plain one), room for a menu's arrow, and a text
-- too long made smaller rather than cut off.
function Style:FitPill(pill, look, menu, room)
    local r, g, b = unpack(look.color)
    if pill.SetBackdropColor then
        pill:SetBackdropColor(r, g, b, look.pill and 0.14 or 0)
        pill:SetBackdropBorderColor(r, g, b, look.pill and 0.75 or 0)
    end
    local text = pill.text
    local left = look.pill and 8 or 2
    local right = menu and 18 or left
    if text.SetTextScale then text:SetTextScale(1) end
    local width = self:TextWidth(text)
    if width > 0 and left + width + right > room and text.SetTextScale then
        local scale = math.max(0.75, (room - left - right) / width)
        text:SetTextScale(scale)
        width = width * scale
    end
    text:ClearAllPoints()
    text:SetPoint("LEFT", left, 0)
    pill:SetWidth(math.max(24, math.min(room, left + width + right)))
end

-- A small menu as a label with an arrow (no box): menu.label, opened with a
-- click (generator fills it, as for the game's menus).
function Style:MenuLabel(parent, width, generator)
    local menu = CreateFrame("Button", nil, parent)
    menu:SetSize(width, 20)
    menu:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    menu.label = self:Text(menu, "GameFontHighlightSmall", nil, "LEFT")
    menu.label:SetPoint("LEFT", 2, 0)
    menu.label:SetPoint("RIGHT", -14, 0)
    menu.label:SetWordWrap(false)
    menu.arrow = menu:CreateTexture(nil, "ARTWORK")
    menu.arrow:SetTexture("Interface\\ChatFrame\\ChatFrameExpandArrow")
    menu.arrow:SetSize(10, 10)
    menu.arrow:SetPoint("RIGHT", -2, 0)
    menu.menuGenerator = generator
    menu:SetScript("OnClick", function(self) ns.Menu:Context(self, self.menuGenerator) end)
    return menu
end
