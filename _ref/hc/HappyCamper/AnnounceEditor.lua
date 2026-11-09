-- Happy Camper. Copyright (c) 2026 Torridon. All rights reserved; see LICENSE.
local _, ns = ...
local L = ns.L

-- Your own camp announcement (Options, My own camp announcement): a small
-- window to write the line Share this camp's Say and General buttons post.
-- Its buttons put in the blanks Happy Camper fills in (Announce.lua), the
-- preview shows what General would post as you type, and a tickbox says
-- whether it ends with " - Happy Camper addon" there. Nothing is kept until
-- Save; Cancel, Escape or closing the window leaves it as it was (opened by
-- ticking My own camp announcement, with nothing written yet, it unticks).

local AnnounceEditor = {}
ns.AnnounceEditor = AnnounceEditor

local WIDTH, PAD = 480, 24
local TOP = 66           -- from the window's top to the first line (below its title and portrait)
local BOX_HEIGHT = 58
local GAP = 10
local BUTTON_WIDTH, BUTTON_GAP = 96, 8

-- The blanks: what each button puts in, its label and what it's for. (A
-- function: the labels are read once the language is known.)
local function Blanks()
    return {
        { "{where}", L["Map pin"], L["The camp's map pin and coordinates: anyone can click it for a waypoint."] },
        { "{place}", L["Place name"], L["The name of the place the camp is at."] },
        { "{offers}", L["What it offers"], L["What the camp's buffs and objects give. Shortened if the line runs long."] },
        { "{time}", L["Time left"], L["How long the fire has left."] },
    }
end

function AnnounceEditor:Frame()
    if self.frame then return self.frame end
    local style = ns.Style
    local f = style:Window("HappyCamperAnnounceEditor", WIDTH, 360, "DIALOG", L["Your camp announcement"], style.PORTRAIT)
    f.intro = style:Text(f, "GameFontHighlight",
        L["Write your own line for Share this camp. The buttons below put in blanks that Happy Camper fills in when you post."], "LEFT")

    f.inset = style:Inset(f, f, PAD, -TOP, PAD, -TOP - BOX_HEIGHT)
    local box = CreateFrame("EditBox", nil, f.inset)
    box:SetMultiLine(true)
    box:SetAutoFocus(false)
    box:SetFontObject("ChatFontNormal")
    box:SetPoint("TOPLEFT", f.inset, "TOPLEFT", 8, -8)
    box:SetPoint("BOTTOMRIGHT", f.inset, "BOTTOMRIGHT", -8, 8)
    box:SetMaxBytes(ns.Announce.WORDING_MAX + 1) -- (the count includes the end of the text)
    box:SetScript("OnTextChanged", function() AnnounceEditor:Refresh() end)
    box:SetScript("OnEnterPressed", function() AnnounceEditor:Save() end)
    box:SetScript("OnEscapePressed", function() f:Hide() end)
    f.inset:EnableMouse(true)
    f.inset:SetScript("OnMouseDown", function() box:SetFocus() end)
    f.box = box
    f:SetScript("OnHide", function() AnnounceEditor:OnClosed() end)

    f.blanks = {}
    for i, blank in ipairs(Blanks()) do
        local button = style:Button(f, BUTTON_WIDTH, blank[2], function()
            box:Insert(blank[1])
            box:SetFocus()
            AnnounceEditor:Refresh()
        end)
        style:Tooltip(button, blank[2], blank[3])
        f.blanks[i] = button
    end

    f.heading = style:Text(f, "GameFontNormal", L["Posts in General as:"], "LEFT")
    f.preview = style:Text(f, "GameFontHighlight", nil, "LEFT")
    f.preview:SetWordWrap(true)

    f.tag = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
    f.tag:SetSize(24, 24)
    f.tag.Text:SetFontObject("GameFontHighlight")
    f.tag.Text:ClearAllPoints()
    f.tag.Text:SetPoint("TOPLEFT", f.tag, "TOPRIGHT", -2, -6)
    f.tag.Text:SetJustifyH("LEFT")
    f.tag.Text:SetWordWrap(true)
    local tag = (format(L["%s - Happy Camper addon"], ""):gsub("^%s+", ""))
    f.tag.Text:SetText(format(L["Add \"%s\" in General"], tag))
    f.tag:SetScript("OnClick", function() AnnounceEditor:Refresh() end)
    -- Why it's worth leaving on: the tag is how most players hear of the addon.
    f.tagNote = style:Text(f, "GameFontDisableSmall",
        L["Helps more players find Happy Camper, so there are more camps on everyone's map."], "LEFT")
    f.tagNote:SetWordWrap(true)

    f.actions = {
        style:Button(f, BUTTON_WIDTH, L["Save"], function() AnnounceEditor:Save() end),
        style:Button(f, BUTTON_WIDTH, L["Happy Camper's wording"], function()
            box:SetText(ns.Announce:DefaultWording())
            AnnounceEditor:Refresh()
        end),
        style:Button(f, BUTTON_WIDTH, L["Cancel"], function() f:Hide() end),
    }
    self.frame = f
    return f
end

-- Buttons side by side across the window, centred, y down from its top.
local function PlaceRow(f, buttons, y, total)
    local x = (f:GetWidth() - total) / 2
    for _, button in ipairs(buttons) do
        button:ClearAllPoints()
        button:SetPoint("TOPLEFT", f, "TOPLEFT", x, -y)
        x = x + button:GetWidth() + BUTTON_GAP
    end
end

-- Top to bottom: the intro, the box, the blanks, the preview, the tickbox
-- (with its note) and the buttons. The window grows for a translation's wider buttons and for a
-- preview of more lines; each row of buttons is one size and centred.
function AnnounceEditor:Layout()
    local f, style = self.frame, ns.Style
    local blankWidth = style:SameWidth(f.blanks, BUTTON_WIDTH)
    local actionWidth = style:SameWidth(f.actions, BUTTON_WIDTH)
    local blanksTotal = #f.blanks * blankWidth + (#f.blanks - 1) * BUTTON_GAP
    local actionsTotal = #f.actions * actionWidth + (#f.actions - 1) * BUTTON_GAP
    local width = math.max(WIDTH, blanksTotal + 2 * PAD, actionsTotal + 2 * PAD)
    local inner = width - 2 * PAD
    f:SetWidth(width)
    f.intro:SetWidth(inner)
    f.heading:SetWidth(inner)
    f.preview:SetWidth(inner)
    f.tag.Text:SetWidth(inner - 26)
    f.tagNote:SetWidth(inner - 22)

    local y = TOP
    f.intro:ClearAllPoints()
    f.intro:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, -y)
    y = y + style:TextHeight(f.intro, 14) + GAP
    f.inset:ClearAllPoints()
    f.inset:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, -y)
    f.inset:SetPoint("BOTTOMRIGHT", f, "TOPRIGHT", -PAD, -(y + BOX_HEIGHT))
    y = y + BOX_HEIGHT + GAP
    PlaceRow(f, f.blanks, y, blanksTotal)
    y = y + 22 + GAP + 4
    f.heading:ClearAllPoints()
    f.heading:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, -y)
    y = y + style:TextHeight(f.heading, 12) + 4
    f.preview:ClearAllPoints()
    f.preview:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, -y)
    y = y + style:TextHeight(f.preview, 14) + GAP
    f.tag:ClearAllPoints()
    f.tag:SetPoint("TOPLEFT", f, "TOPLEFT", PAD - 4, -y)
    -- The note under the tickbox's label, lined up with it.
    local noteY = y + 6 + style:TextHeight(f.tag.Text, 14) + 2
    f.tagNote:ClearAllPoints()
    f.tagNote:SetPoint("TOPLEFT", f, "TOPLEFT", PAD + 18, -noteY)
    y = math.max(y + 24, noteY + style:TextHeight(f.tagNote, 12)) + GAP
    PlaceRow(f, f.actions, y, actionsTotal)
    f:SetHeight(y + 22 + 22)
end

-- The preview follows the box and the tickbox.
function AnnounceEditor:Refresh()
    local f = self.frame
    if not f then return end
    f.preview:SetText(ns.Announce:Preview(f.box:GetText(), f.tag:GetChecked() and true or false))
    self:Layout()
end

-- Opens with your wording (Happy Camper's if you have none) and tickbox as
-- saved. fromTick: opened by ticking My own camp announcement, which closing
-- it without saving undoes.
function AnnounceEditor:Open(fromTick)
    local f = self:Frame()
    self.fromTick, self.saved = fromTick and true or false, false
    f.box:SetText(ns.Announce:Wording())
    f.tag:SetChecked(ns.db.announceTag ~= false)
    self:Refresh()
    f:ClearAllPoints()
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
    f:Show()
    f.box:SetFocus()
end

-- Keeps what's in the box (cleaned up: Announce:CleanWording) and the
-- tickbox, and turns your own wording on. Happy Camper's wording, or none, is
-- kept as "" so it follows the language.
function AnnounceEditor:Save()
    local f = self.frame
    if not f then return end
    local text = ns.Announce:CleanWording(f.box:GetText())
    if text == ns.Announce:DefaultWording() then text = "" end
    ns.db.announceText = text
    ns.db.announceTag = f.tag:GetChecked() and true or false
    ns.db.announceOwn = true
    self.saved = true
    f:Hide()
    if ns.Options and ns.Options.Sync then ns.Options:Sync() end
end

-- Closed without saving, after My own camp announcement was ticked to open
-- it: the tickbox goes back off.
function AnnounceEditor:OnClosed()
    if self.saved or not self.fromTick then return end
    self.fromTick = false
    ns.db.announceOwn = false
    if ns.Options and ns.Options.Sync then ns.Options:Sync() end
end
