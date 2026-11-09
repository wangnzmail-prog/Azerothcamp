-- Happy Camper. Copyright (c) 2026 Torridon. All rights reserved; see LICENSE.
local addonName, ns = ...

-- Happy Camper's menus. With a mouse and keyboard they're the game's own. In
-- the game's controller mode they're Happy Camper's: there the game answers
-- each of its menus showing with a protected call, and when an addon opened
-- the menu that call is blocked and blamed on the addon, with a pop-up that
-- can freeze the game when answered with a controller. So in controller mode
-- the same menu builder runs against a stand-in that records what it makes
-- (titles, buttons, radios, checkboxes, dividers, submenus), drawn on a plain
-- frame of Happy Camper's, which the controller layer doesn't watch.

local Menu = {}
ns.Menu = Menu

local ROW = 20          -- a row's height (more for wrapped text)
local DIVIDER = 9       -- a divider row's height
local PAD = 8           -- the panel's border to its rows
local MARK = 18         -- the column for a radio's or checkbox's mark
local ARROW = 14        -- a submenu's arrow
local MAX_TEXT = 300    -- longer text wraps
local GAP = 2           -- between the owner (or a row) and the panel it opens
local GOLD = { 1, 0.82, 0 }
local GREY = { 0.5, 0.5, 0.5 }
local BORDER = { 0.75, 0.62, 0.38 }

-- The stand-in for the game's menu description --------------------------------

local function NoOp() end
local Element = {}
-- Methods the game's menus have and these don't (icons, sorting...) do nothing.
local ElementMeta = { __index = function(_, key)
    if Element[key] ~= nil then return Element[key] end
    if type(key) == "string" and key:find("^%u") then return NoOp end
end }

local function NewElement(kind, text)
    return setmetatable({ kind = kind, text = text, children = {}, enabled = true }, ElementMeta)
end

function Element:Add(kind, text)
    local element = NewElement(kind, text)
    self.children[#self.children + 1] = element
    return element
end
function Element:CreateTitle(text) return self:Add("title", text) end
function Element:CreateDivider() return self:Add("divider") end
function Element:CreateSpacer() return self:Add("divider") end
function Element:CreateButton(text, callback, data)
    local element = self:Add("button", text)
    element.callback, element.data = callback, data
    return element
end
function Element:CreateRadio(text, isSelected, setSelected, data)
    local element = self:Add("radio", text)
    element.isSelected, element.callback, element.data = isSelected, setSelected, data
    return element
end
function Element:CreateCheckbox(text, isSelected, setSelected, data)
    local element = self:Add("checkbox", text)
    element.isSelected, element.callback, element.data = isSelected, setSelected, data
    return element
end
function Element:SetEnabled(enabled) self.enabled = enabled end
function Element:SetTooltip(fill) self.tooltip = fill end
function Element:SetIsSelected(isSelected) self.isSelected = isSelected end

function Element:IsEnabled()
    local enabled = self.enabled
    if type(enabled) == "function" then enabled = enabled(self) end
    return enabled and true or false
end
function Element:IsSelected()
    local isSelected = self.isSelected
    if type(isSelected) == "function" then isSelected = isSelected(self.data) end
    return isSelected and true or false
end
function Element:HasSubmenu() return #self.children > 0 end

-- Drawing ------------------------------------------------------------------------

local panels = {} -- [level] = frame; a submenu's panel is a child of the one before

local function RowEnter(row)
    local element, level = row.element, row:GetParent().level
    if row.clickable and element:HasSubmenu() then
        Menu:ShowLevel(level + 1, element, row)
    else
        Menu:HideFrom(level + 1)
    end
    if row.clickable then row.glow:Show() end
    if element.tooltip then
        GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
        element.tooltip(GameTooltip, element)
        GameTooltip:Show()
    end
end

local function RowLeave(row)
    row.glow:Hide()
    if GameTooltip:IsOwned(row) then GameTooltip:Hide() end
end

-- A click: a submenu opens; anything else does its job, then the menu closes
-- (a checkbox's stays open, as the game's do, unless its job says otherwise).
local function RowClick(row)
    local element = row.element
    if not row.clickable then return end
    if element:HasSubmenu() and not element.callback then
        return Menu:ShowLevel(row:GetParent().level + 1, element, row)
    end
    local owner = Menu.owner
    local response = element.callback and element.callback(element.data)
    -- A dropdown shows what was picked.
    if owner and owner.GenerateMenu then owner:GenerateMenu() end
    local keepOpen = element.kind == "checkbox"
    if MenuResponse and response ~= nil then
        keepOpen = response == MenuResponse.Open or response == MenuResponse.Refresh
    end
    if keepOpen then Menu:Refresh() else Menu:Close() end
end

local function Row(panel, i)
    local row = panel.rows[i]
    if row then return row end
    row = CreateFrame("Button", nil, panel)
    row.glow = row:CreateTexture(nil, "BACKGROUND")
    row.glow:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
    row.glow:SetBlendMode("ADD")
    row.glow:SetAllPoints()
    row.glow:Hide()
    row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.text:SetJustifyH("LEFT")
    row.mark = row:CreateTexture(nil, "ARTWORK")
    row.mark:SetSize(14, 14)
    row.mark:SetPoint("LEFT", row, "LEFT", 0, 0)
    row.tick = row:CreateTexture(nil, "OVERLAY")
    row.tick:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
    row.tick:SetAllPoints(row.mark)
    row.arrow = row:CreateTexture(nil, "ARTWORK")
    row.arrow:SetTexture("Interface\\ChatFrame\\ChatFrameExpandArrow")
    row.arrow:SetSize(12, 12)
    row.arrow:SetPoint("RIGHT", row, "RIGHT", 0, 0)
    row.line = row:CreateTexture(nil, "ARTWORK")
    row.line:SetColorTexture(BORDER[1], BORDER[2], BORDER[3], 0.4)
    row.line:SetHeight(1)
    row.line:SetPoint("LEFT", row, "LEFT", 0, 0)
    row.line:SetPoint("RIGHT", row, "RIGHT", 0, 0)
    row:SetScript("OnEnter", RowEnter)
    row:SetScript("OnLeave", RowLeave)
    row:SetScript("OnClick", RowClick)
    panel.rows[i] = row
    return row
end

-- Sets a row up for its element: its text, colour and mark. Its text's width
-- and the row's height, for the layout.
local function Dress(row, element)
    local kind, enabled = element.kind, element:IsEnabled()
    row.element = element
    row.clickable = enabled and kind ~= "title" and kind ~= "divider"
    row:EnableMouse(kind ~= "title" and kind ~= "divider" or element.tooltip ~= nil)
    row.glow:Hide()
    row.line:SetShown(kind == "divider")
    row.arrow:SetShown(kind ~= "title" and element:HasSubmenu())
    row.arrow:SetDesaturated(not enabled)
    local selected = (kind == "radio" or kind == "checkbox") and element:IsSelected()
    row.mark:SetShown(kind == "radio" or kind == "checkbox")
    row.mark:SetDesaturated(not enabled)
    row.tick:SetShown(kind == "checkbox" and selected)
    row.tick:SetDesaturated(not enabled)
    if kind == "radio" then
        row.mark:SetTexture("Interface\\Buttons\\UI-RadioButton")
        if selected then row.mark:SetTexCoord(0.25, 0.5, 0, 1) else row.mark:SetTexCoord(0, 0.25, 0, 1) end
    elseif kind == "checkbox" then
        row.mark:SetTexture("Interface\\Buttons\\UI-CheckBox-Up")
        row.mark:SetTexCoord(0, 1, 0, 1)
    end
    local text = row.text
    if kind == "divider" then
        text:SetText("")
        text:Hide()
        return 0, DIVIDER
    end
    text:Show()
    text:SetFontObject(kind == "title" and "GameFontNormalSmall" or "GameFontHighlightSmall")
    local colour = kind == "title" and GOLD or (not enabled and GREY) or nil
    if colour then text:SetTextColor(colour[1], colour[2], colour[3]) else text:SetTextColor(1, 1, 1) end
    text:SetWidth(0)
    text:SetWordWrap(false)
    text:SetText(element.text or "")
    local width = ns.Style:TextWidth(text)
    if width <= MAX_TEXT then return width, ROW end
    text:SetWidth(MAX_TEXT)
    text:SetWordWrap(true)
    return MAX_TEXT, math.max(ROW, ns.Style:TextHeight(text, ROW - 6) + 6)
end

-- Fills a panel with an element's children: in one column, or in more where
-- they'd run off the screen. At least least wide (a dropdown's width).
local function Fill(panel, element, least)
    local children, sizes = element.children, {}
    local lead, trail, widest = 0, 0, 0
    for i, child in ipairs(children) do
        local width, height = Dress(Row(panel, i), child)
        sizes[i] = height
        if child.kind == "radio" or child.kind == "checkbox" then lead = MARK end
        if child.kind ~= "title" and child:HasSubmenu() then trail = ARROW end
        widest = math.max(widest, width)
    end
    local columnWidth = math.max(lead + widest + trail, (least or 0) - 2 * PAD)
    local tallest = math.max(ROW * 8, (UIParent:GetHeight() or 768) * 0.85 - 2 * PAD)
    local column, y, height = 0, 0, 0
    for i, child in ipairs(children) do
        local row = panel.rows[i]
        if y > 0 and y + sizes[i] > tallest then column, y = column + 1, 0 end
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD + column * (columnWidth + PAD), -PAD - y)
        row:SetSize(columnWidth, sizes[i])
        row.text:ClearAllPoints()
        row.text:SetPoint("LEFT", row, "LEFT", child.kind == "title" and 0 or lead, 0)
        row:Show()
        y = y + sizes[i]
        height = math.max(height, y)
    end
    for i = #children + 1, #panel.rows do panel.rows[i]:Hide() end
    panel:SetSize((column + 1) * columnWidth + column * PAD + 2 * PAD, height + 2 * PAD)
    panel.element = element
end

-- The space a frame has below it (or to its right), in a panel's units.
local function Room(frame, panel, side)
    local edge = side == "right" and frame:GetRight() or frame:GetBottom()
    if not edge then return nil end
    edge = edge * frame:GetEffectiveScale() / panel:GetEffectiveScale()
    if side == "right" then return (UIParent:GetWidth() or 0) - edge end
    return edge
end

local function Panel(level)
    if panels[level] then return panels[level] end
    local panel = CreateFrame("Frame", "HappyCamperMenu" .. level, level == 1 and UIParent or Panel(level - 1),
        "BackdropTemplate")
    panel:SetFrameStrata("FULLSCREEN_DIALOG")
    panel:SetToplevel(true)
    panel:SetClampedToScreen(true)
    panel:EnableMouse(true)
    panel:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 14, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    panel:SetBackdropColor(0.06, 0.05, 0.04, 0.96)
    panel:SetBackdropBorderColor(BORDER[1], BORDER[2], BORDER[3], 1)
    panel.level, panel.rows = level, {}
    panel:Hide()
    panels[level] = panel
    if level == 1 then
        -- Escape closes it, as it does the game's menus; so does its owner going.
        if UISpecialFrames then tinsert(UISpecialFrames, panel:GetName()) end
        panel:SetScript("OnUpdate", function()
            if Menu.owner and not Menu.owner:IsVisible() then Menu:Close() end
        end)
    end
    return panel
end

-- Opening and closing --------------------------------------------------------------

function Menu:IsOpen(owner)
    local panel = panels[1]
    return panel ~= nil and panel:IsShown() and (owner == nil or self.owner == owner)
end

-- Closes a submenu at level, and any deeper.
function Menu:HideFrom(level)
    for l = level, #panels do panels[l]:Hide() end
end

-- Opens element's submenu beside its row.
function Menu:ShowLevel(level, element, row)
    local panel = Panel(level)
    if panel:IsVisible() and panel.element == element then return end
    self:HideFrom(level)
    Fill(panel, element)
    panel:ClearAllPoints()
    local room = Room(row, panel, "right")
    if room and room < panel:GetWidth() + PAD then
        panel:SetPoint("TOPRIGHT", row, "TOPLEFT", -PAD - GAP, PAD)
    else
        panel:SetPoint("TOPLEFT", row, "TOPRIGHT", PAD + GAP, PAD)
    end
    panel:Show()
end

function Menu:Open(owner, generator)
    self:Close()
    local root = NewElement("root")
    generator(owner, root)
    self.owner, self.generator = owner, generator
    local panel = Panel(1)
    self:HideFrom(2)
    local least = owner and owner.GetWidth and owner:GetWidth()
    if least then least = least * owner:GetEffectiveScale() / panel:GetEffectiveScale() end
    Fill(panel, root, least)
    panel:ClearAllPoints()
    local room = owner and Room(owner, panel, "below")
    if not owner then
        local x, y = GetCursorPosition()
        local scale = UIParent:GetEffectiveScale()
        panel:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x / scale, y / scale)
    elseif room and room < panel:GetHeight() + GAP then
        panel:SetPoint("BOTTOMLEFT", owner, "TOPLEFT", 0, GAP)
    else
        panel:SetPoint("TOPLEFT", owner, "BOTTOMLEFT", 0, -GAP)
    end
    panel:Show()
end

-- Builds the menu again (after a checkbox), its submenus closed.
function Menu:Refresh()
    if not self:IsOpen() then return end
    local root = NewElement("root")
    self.generator(self.owner, root)
    self:HideFrom(2)
    Fill(panels[1], root, panels[1]:GetWidth())
end

function Menu:Close()
    self:HideFrom(1)
    self.owner, self.generator = nil, nil
end

-- Opens owner's menu, or closes it if it's open. A click on the owner closes
-- the menu first (a click outside it), so that click doesn't reopen it.
function Menu:Toggle(owner, generator)
    if self:IsOpen(owner) or (self.closedOwner == owner and self.closedAt == GetTime()) then
        self:Close()
    else
        self:Open(owner, generator)
    end
    return true
end

-- A menu at owner, generator(owner, root) filling it, as the game's
-- MenuUtil.CreateContextMenu. False where there are no menus (the caller then
-- does without one).
function Menu:Context(owner, generator)
    if ns.IsGamepad() then return self:Toggle(owner, generator) end
    if not (MenuUtil and MenuUtil.CreateContextMenu) then return false end
    MenuUtil.CreateContextMenu(owner, generator)
    return true
end

-- A click anywhere but the menu closes it, as the game's.
local watcher = CreateFrame("Frame")
pcall(watcher.RegisterEvent, watcher, "GLOBAL_MOUSE_DOWN")
watcher:SetScript("OnEvent", function()
    if not Menu:IsOpen() then return end
    for _, panel in ipairs(panels) do
        if panel:IsVisible() and panel:IsMouseOver() then return end
    end
    Menu.closedOwner, Menu.closedAt = Menu.owner, GetTime()
    Menu:Close()
end)
