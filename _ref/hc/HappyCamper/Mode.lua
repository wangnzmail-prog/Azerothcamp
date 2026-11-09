-- Happy Camper. Copyright (c) 2026 Torridon. All rights reserved; see LICENSE.
local _, ns = ...
local L = ns.L

-- Standard and Enhanced. Enhanced is everything Happy Camper does. Standard
-- shows less: camps on the map with their time left, badges, camp music, the
-- Camp tab, the panel and Options, without camp details, Find a camp, the
-- Camp Builder or the Group tab. Only what you see changes: the camp network,
-- reading Camp Benefits and everything shared in the background work the same
-- in both, so a Standard player's camps still reach everyone.
--
-- Each account is asked once (ns.db.mode: nil until the player chooses, then
-- "standard" or "enhanced"), in a window of our own a little after login,
-- never in a fight and never on top of the launch question (Season.lua).
-- Closing it without choosing asks again at the next login; until then it's
-- Enhanced. Options can switch it any time, at once (no reload).

local Mode = {}
ns.Mode = Mode

-- True unless the player chose Standard (not chosen yet counts as Enhanced).
function ns.IsEnhanced()
    return not (ns.db and ns.db.mode == "standard")
end

function Mode:Current()
    return ns.IsEnhanced() and "enhanced" or "standard"
end

-- Switches to "standard" or "enhanced", at once.
function Mode:Set(mode)
    if mode ~= "standard" and mode ~= "enhanced" then return end
    ns.db.mode = mode
    self:Apply()
end

-- Everything that looks different in the other mode, redrawn now: the window's
-- tabs, the map's camp bar and Find a camp strip, the pins, the panel and the
-- minimap button.
function Mode:Apply()
    if not ns.IsEnhanced() then ns.MinimapButton:ClearAttention() end
    ns.Hub:OnModeChanged()
    ns.MapBar:Refresh()
    ns.MapPins:Refresh()
    if ns.MinimapPins then ns.MinimapPins:Refresh() end
    if ns.Widget then ns.Widget:Update() end
    ns.Options:Sync()
    ns.OnCampsChanged()
end

-- The question -------------------------------------------------------------------------

local ASK_DELAY = 10 -- as the launch question: once the chat window and the world are up
local RETRY = 3      -- while the launch question is up or still to come

-- Core, at login: asks a little later if this account hasn't chosen yet.
function Mode:OnLogin()
    if ns.db.mode == nil then C_Timer.After(ASK_DELAY, function() Mode:Ask() end) end
end

-- Asks, unless it's been answered; in a fight it waits for the fight to end
-- (OnCombatEnd), and it waits for the launch question to close.
function Mode:Ask()
    if ns.db.mode ~= nil then return end
    if ns.InCombat() then
        self.askAfterCombat = true
        return
    end
    self.askAfterCombat = nil
    if ns.Season:IsAsking() then
        if not self.retrying then
            self.retrying = true
            C_Timer.After(RETRY, function()
                Mode.retrying = nil
                Mode:Ask()
            end)
        end
        return
    end
    self:ShowChoice()
end

-- Core, when a fight ends.
function Mode:OnCombatEnd()
    if self.askAfterCombat then self:Ask() end
end

-- The player's answer. The guide starts after it, the first time.
function Mode:Choose(mode)
    self:Set(mode)
    ns.Guide:MaybeAutoStart()
end

-- The question, in the look of the game's own ruleset choice (Normal or
-- PvP): the screen dimmed, a large title and a gold line under it, and two
-- tall cards side by side, each with its name, a round picture in a gold ring
-- and what it gives. Clicking a card chooses it. A note under them says
-- Options can change it.
local CARD_WIDTH, CARD_HEIGHT, CARD_GAP, CARD_PAD = 250, 340, 70, 22
local ICON = 88
-- Standard: a campfire; Enhanced: the same campfire with a scroll and potions.
local CARD_ICONS = { standard = ns.Style.MODE_STANDARD, enhanced = ns.Style.MODE_ENHANCED }

-- What each card gives, as a list (each line translated on its own).
local CARD_POINTS = {
    standard = { "See the smoke from camps on your map", "Collect badges from camping around Azeroth", "Discover new camp songs in interesting places", "See other Happy Campers at your camp", "See which camp benefits you have" },
    enhanced = { "All Standard features", "More detail about camps on the map", "Organize your group's camp and choose who brings what", "Request items from other Happy Campers in your zone" },
}

local function Points(mode)
    local lines = {}
    for i, line in ipairs(CARD_POINTS[mode]) do lines[i] = "\226\128\162 " .. L[line] end -- a bullet
    return table.concat(lines, "\n")
end

-- A font that may not be in every client, else one that is.
local function Font(name, fallback)
    return _G[name] and name or fallback
end

-- One card: a bronze frame (Style:HeavyBronze), its name in gold, a round
-- picture in the gold ring the minimap's buttons wear, and what it gives.
local function Card(parent, mode, name, text)
    local style = ns.Style
    local card = CreateFrame("Button", nil, parent)
    card:SetSize(CARD_WIDTH, CARD_HEIGHT)
    -- The metal frame of the panel under the world map (Style:MetalFrame).
    style:MetalFrame(card)
    card.title = style:Text(card, Font("GameFontNormalHuge", "GameFontNormalLarge"), name, "CENTER")
    card.title:SetPoint("TOP", 0, -CARD_PAD - 6)
    -- The picture, filling the bronze ring, cut round by a mask.
    card.icon = card:CreateTexture(nil, "ARTWORK")
    card.icon:SetSize(ICON, ICON)
    card.icon:SetPoint("TOP", card.title, "BOTTOM", 0, -26)
    card.icon:SetTexture(CARD_ICONS[mode])
    local mask = card.CreateMaskTexture and card:CreateMaskTexture()
    if mask then
        mask:SetAllPoints(card.icon)
        if C_Texture and C_Texture.GetAtlasInfo("talents-node-circle-mask") then
            mask:SetAtlas("talents-node-circle-mask")
        else
            mask:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        end
        card.icon:AddMaskTexture(mask)
    end
    -- Happy Camper's own bronze ring, drawn big so it's sharp at this size.
    card.ring = card:CreateTexture(nil, "OVERLAY")
    card.ring:SetSize(ICON / style.RING_HOLE, ICON / style.RING_HOLE)
    card.ring:SetPoint("CENTER", card.icon, "CENTER")
    card.ring:SetTexture(style.RING)
    card.text = style:Text(card, Font("GameFontHighlightMedium", "GameFontHighlight"), text, "LEFT")
    card.text:SetPoint("TOP", card.icon, "BOTTOM", 0, -26)
    card.text:SetSpacing(4)
    card.text:SetWordWrap(true)
    -- Hovered: a faint gold wash over the card.
    local glow = card:CreateTexture(nil, "HIGHLIGHT")
    glow:SetAllPoints()
    glow:SetColorTexture(1, 0.82, 0.3, 0.08)
    card:SetScript("OnClick", function() Mode:Answer(mode) end)
    return card
end

function Mode:Window()
    if self.frame then return self.frame end
    local style = ns.Style
    local f = CreateFrame("Frame", "HappyCamperModeChoice", UIParent)
    f:SetAllPoints(UIParent)
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:SetToplevel(true)
    f:EnableMouse(true) -- the dimmed screen behind takes clicks, so nothing under it is clicked by mistake
    f:Hide()
    f.dim = f:CreateTexture(nil, "BACKGROUND")
    f.dim:SetAllPoints()
    f.dim:SetColorTexture(0, 0, 0, 0.75)
    f.title = style:Text(f, Font("GameFontHighlightHuge", "GameFontHighlightLarge"), L["Choose your Happy Camper"], "CENTER")
    f.text = style:Text(f, "GameFontNormalLarge", L["How much should Happy Camper show you? Either way, it shares camps with other players."], "CENTER")
    f.text:SetWordWrap(true)
    f.standard = Card(f, "standard", L["Standard"], Points("standard"))
    f.enhanced = Card(f, "enhanced", L["Enhanced"], Points("enhanced"))
    -- The cards' texts, by the names the rest of the addon (and its tests) use.
    f.standardText, f.enhancedText = f.standard.text, f.enhanced.text
    f.note = style:Text(f, "GameFontDisable", L["You can change this any time in Options."], "CENTER")
    f.close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    f.close:SetPoint("TOPRIGHT", -20, -20)
    -- Closed without a choice (the close button or Escape), nothing changes:
    -- it's asked again at the next login.
    if UISpecialFrames then tinsert(UISpecialFrames, "HappyCamperModeChoice") end
    self.frame = f
    return f
end

-- Lays it out around its text: both cards one size (wider for a long name in
-- a translation, taller for a long description), side by side and centred,
-- the title and its line above them and the note below.
function Mode:Layout(f)
    local width = CARD_WIDTH
    for _, card in ipairs({ f.standard, f.enhanced }) do width = math.max(width, math.ceil(ns.Style:TextWidth(card.title)) + 2 * CARD_PAD) end
    local textWidth = width - 2 * CARD_PAD
    local height = CARD_HEIGHT
    for _, card in ipairs({ f.standard, f.enhanced }) do
        card.text:SetWidth(textWidth)
        local needed = CARD_PAD + 6 + ns.Style:TextHeight(card.title, 20) + 26 + ICON + 26 + ns.Style:TextHeight(card.text, 14) + CARD_PAD
        height = math.max(height, needed)
    end
    local row = 2 * width + CARD_GAP
    f.text:SetWidth(math.max(row, 500))
    local top = (height + ns.Style:TextHeight(f.text, 16) + 60) / 2 + 40
    f.title:ClearAllPoints()
    f.title:SetPoint("BOTTOM", f, "CENTER", 0, top)
    f.text:ClearAllPoints()
    f.text:SetPoint("TOP", f.title, "BOTTOM", 0, -12)
    for side, card in ipairs({ f.standard, f.enhanced }) do
        card:SetSize(width, height)
        card:ClearAllPoints()
        card:SetPoint("TOP", f.text, "BOTTOM", (side == 1 and -1 or 1) * (width + CARD_GAP) / 2, -40)
    end
    f.note:ClearAllPoints()
    f.note:SetPoint("TOP", f.text, "BOTTOM", 0, -40 - height - 20)
end

function Mode:ShowChoice()
    local f = self:Window()
    f.standard.title:SetText(L["Standard"])
    f.enhanced.title:SetText(L["Enhanced"])
    self:Layout(f)
    f:Show()
    f:Raise()
end

-- A button was clicked.
function Mode:Answer(mode)
    local f = self:Window()
    f:Hide()
    self:Choose(mode)
end
