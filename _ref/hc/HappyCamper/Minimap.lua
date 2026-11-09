-- Happy Camper. Copyright (c) 2026 Torridon. All rights reserved; see LICENSE.
local _, ns = ...
local L = ns.L

-- Classic round minimap button that can be dragged around the minimap edge.
-- Left-click: the Happy Camper window. Right-click: options.

local MinimapButton = {}
ns.MinimapButton = MinimapButton

local function UpdatePosition(button)
    local angle = math.rad(ns.db.minimapAngle)
    local radius = Minimap:GetWidth() / 2 + 10
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
end

local function OnDragUpdate(button)
    local mx, my = Minimap:GetCenter()
    local cx, cy = GetCursorPosition()
    local scale = Minimap:GetEffectiveScale()
    ns.db.minimapAngle = math.deg(math.atan2(cy / scale - my, cx / scale - mx))
    UpdatePosition(button)
end

function MinimapButton:Init()
    local button = CreateFrame("Button", "HappyCamperMinimapButton", Minimap)
    button:SetSize(31, 31)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(8)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:RegisterForDrag("LeftButton")
    button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    local background = button:CreateTexture(nil, "BACKGROUND")
    background:SetSize(20, 20)
    background:SetPoint("TOPLEFT", 7, -5)
    background:SetTexture("Interface\\Minimap\\UI-Minimap-Background")

    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetSize(17, 17)
    icon:SetPoint("TOPLEFT", 7, -6)
    icon:SetTexture(ns.Style.MINIMAP_ICON)

    -- Glows while there's Camp Builder news you haven't looked at (ns.Notify).
    button.glow = button:CreateTexture(nil, "OVERLAY", nil, 2)
    button.glow:SetSize(46, 46)
    button.glow:SetPoint("CENTER", icon, "CENTER")
    button.glow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
    button.glow:SetBlendMode("ADD")
    button.glow:SetVertexColor(1, 0.75, 0.2)
    button.glow:Hide()
    -- Its own frame for the pulse: the button's OnUpdate is used for dragging.
    button.pulse = CreateFrame("Frame", nil, button)
    button.pulse:Hide()
    local t = 0
    button.pulse:SetScript("OnUpdate", function(_, elapsed)
        t = t + elapsed
        button.glow:SetAlpha(0.45 + 0.55 * math.abs(math.sin(t * 2.5)))
    end)

    local border = button:CreateTexture(nil, "OVERLAY")
    border:SetSize(53, 53)
    border:SetPoint("TOPLEFT")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

    button:SetScript("OnClick", function(_, mouseButton)
        if mouseButton == "RightButton" then
            ns.Options:Toggle()
        elseif IsShiftKeyDown() then
            ns.Widget:Toggle()
        elseif MinimapButton.attention and ns.IsEnhanced() then
            ns.Hub:Open("finder") -- the news is there
        else
            ns.Hub:Toggle()
        end
    end)
    button:SetScript("OnDragStart", function(self) self:SetScript("OnUpdate", OnDragUpdate) end)
    button:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
    ns.Style:CustomTooltip(button, "ANCHOR_LEFT", function(tooltip)
        tooltip:AddLine("Happy Camper", 1, 0.6, 0.2)
        -- Camp requests are the Camp Builder's: not in Standard mode (Mode.lua).
        if ns.IsEnhanced() then
            tooltip:AddLine(format(L["Known camps: %d   Camp requests: %d"], ns.Count(ns.Camps:All()),
                ns.Count(ns.Requests:All())), 1, 1, 1)
        else
            tooltip:AddLine(format(L["Known camps: %d"], ns.Count(ns.Camps:All())), 1, 1, 1)
        end
        tooltip:AddLine(ns.Comm:IsConnected() and L["Camp network: connected"]
            or ns.Comm:IsChannelOff() and L["Camp network: paused by the game"] or L["Camp network: off"], 0.7, 0.7, 0.7)
        tooltip:AddLine(ns.Stats:Summary(), 0.7, 0.7, 0.7)
        for _, message in ipairs(MinimapButton.attention or {}) do tooltip:AddLine(message, 1, 0.82, 0, true) end
        if ns.Style:ShowHelp() then
            tooltip:AddLine(" ")
            tooltip:AddLine(MinimapButton.attention and L["Left-click: see it in the Camp Builder"] or L["Left-click: Happy Camper window"], 0.5, 0.8, 1)
            tooltip:AddLine(L["Right-click: options"], 0.5, 0.8, 1)
            tooltip:AddLine(L["Shift-click: show or hide the Campsite Assistant"], 0.5, 0.8, 1)
            tooltip:AddLine(L["Drag: move this button"], 0.5, 0.8, 1)
        end
    end)

    self.button = button
    UpdatePosition(button)
    self:Refresh()
end

-- Camp Builder news: the button glows (pulsing) and its tooltip lists the
-- messages, until you open the Camp Builder. Never in Standard mode (ns.Notify).
function MinimapButton:SetAttention(message)
    self.attention = self.attention or {}
    table.insert(self.attention, 1, message)
    self.attention[4] = nil
    local button = self.button
    if not button then return end
    button.glow:Show()
    button.pulse:Show()
end

function MinimapButton:ClearAttention()
    self.attention = nil
    if not self.button then return end
    self.button.glow:Hide()
    self.button.pulse:Hide()
end

function MinimapButton:Refresh()
    if self.button then self.button:SetShown(ns.db.minimapButton) end
end

-- Opens the world map with the Find a camp filter showing, under the camp bar
-- (ns.OpenMap: not in a fight or with a controller; then it's there when you
-- open the map). Standard mode (Mode.lua) has no Find a camp: just the map,
-- with its camps.
function ns.OpenSearch()
    if not ns.MapBar.bar then return end
    ns.OpenMap()
    if ns.IsEnhanced() and not ns.db.mapBar then
        ns.db.mapBar = true
        ns.MapBar:Refresh()
        if ns.Options.Sync then ns.Options:Sync() end
    end
    if not ns.db.mapPins then ns.SetShowCamps(true) end
end

-- Entry in the minimap's addon compartment menu (declared in the TOC).
function HappyCamper_OnAddonCompartmentClick()
    ns.Hub:Toggle()
end
