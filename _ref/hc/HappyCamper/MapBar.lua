-- Happy Camper. Copyright (c) 2026 Torridon. All rights reserved; see LICENSE.
local _, ns = ...
local L = ns.L

-- The camp bar: how many camps are on the map you're looking at (left), the
-- Show camps, other layers, Camp Builder (Enhanced mode only) and options
-- buttons (middle), and your own camp buffs and object cooldown (right).
--
-- It sits in a dock just below the map window, framed in the same metal as the
-- map (Style:MetalFrame), or along the bottom of a full-screen map, with the
-- Find a camp strip underneath it when that's open.

local MapBar = {}
ns.MapBar = MapBar

local HEIGHT = 28
local PAD = 6
local EDGE = 14           -- the dock's border
local SEARCH_PADDING = 10 -- below the Find a camp strip (its height is Search.HEIGHT)
local ICON_SIZE = 22
local BUTTON_SIZE = 24    -- the Show camps, Find a camp, Camp Builder and options icons
local BUTTON_GAP = 6
local QUESTION_MARK_ICON = 134400
local CAMPERS_ICON = "Interface\\Icons\\Achievement_GuildPerk_EverybodysFriend"

local function ShortTime(seconds)
    if seconds >= 60 then return format("%dm", math.floor(seconds / 60)) end
    return format("%ds", math.max(0, math.floor(seconds)))
end

-- A camp's tooltip (map pins, minimap pins and the panel). In Standard mode
-- (Mode.lua) only its name, whether it's unconfirmed, its time left and its
-- layer: no camp details. smoky: the camp shows as smoke there, not its exact
-- spot (Camps:Smoky).
function MapBar:FillCampTooltip(tooltip, camp, smoky)
    local camps = ns.Camps
    local enhanced = ns.IsEnhanced()
    tooltip:AddLine(camps:DisplayName(camp), 1, 0.6, 0.2)
    if smoky then tooltip:AddLine(L["Somewhere around here: you can see the smoke."], 0.8, 0.8, 0.8, true) end
    if camp.chat then
        tooltip:AddLine(L["Unconfirmed camp"], 1, 0.5, 0.25)
        tooltip:AddLine(camp.approximate and L["Said in chat near you, with no map pin: it's only roughly here, and nobody with Happy Camper has rested here yet."]
            or camp.via and L["Shared by another camp addon: nobody with Happy Camper has rested here yet, so it may have changed."]
            or L["Only a map pin posted in chat: nobody with Happy Camper has rested here yet, so the fire may not be there."], 0.9, 0.9, 0.9, true)
    elseif camp.passing then
        tooltip:AddLine(L["Unconfirmed camp"], 1, 0.5, 0.25)
        tooltip:AddLine(L["Seen in passing: it's only roughly here, and nobody with Happy Camper has rested here yet."], 0.9, 0.9, 0.9, true)
    end
    if enhanced then tooltip:AddLine(camps:CreatorText(camp), 0.7, 0.7, 0.7) end

    local left = camps:TimeLeft(camp)
    if left then
        tooltip:AddDoubleLine(L["Burns out in"], ns.FormatTime(left), 1, 1, 1, 1, 1, 1)
    elseif not camp.chat then
        tooltip:AddLine(L["Time left unknown: only the player who lit the fire knows it."], 0.7, 0.7, 0.7, true)
    end

    local mapID, x, y = ns.GetPlayerLocation()
    local distance = enhanced and mapID and camps:Distance(camp, mapID, x, y)
    if distance then
        tooltip:AddDoubleLine(L["Distance"], format(L["%d yards"], distance), 1, 1, 1, 1, 1, 1)
    end

    local used, slots = camps:SlotsUsed(camp)
    if slots and enhanced then
        tooltip:AddDoubleLine(L["Object slots"], used >= slots and format(L["Full (%d of %d)"], used, slots)
            or format(L["%d of %d used"], used, slots), 1, 1, 1, used >= slots and 1 or 0.4, used >= slots and 0.5 or 1, 0.4)
    end
    local layer = camps:LayerStatus(camp)
    if camps:MissingHere(camp) then
        tooltip:AddLine(L["You were there and saw no fire: it's on another layer, or it's out"], 1, 0.5, 0.25, true)
    elseif layer == "same" then
        tooltip:AddLine(L["On your layer"], 0.4, 1, 0.4)
    elseif layer == "other" then
        tooltip:AddLine(L["On another layer: you may not see this fire"], 1, 0.5, 0.25, true)
    else
        -- In your zone, say why it can't be told (elsewhere layers aren't compared).
        local unknown = camps:LayerUnknown(camp)
        if unknown == "camp" then
            tooltip:AddLine(L["Its layer isn't known: you may not see this fire"], 0.8, 0.8, 0.8, true)
        elseif unknown == "you" then
            tooltip:AddLine(L["Your layer isn't known yet (it's read from NPCs near you): you may not see this fire"], 0.8, 0.8, 0.8, true)
        end
    end
    if not enhanced then return end

    if ns.Search:IsActive() then
        local matches, have = ns.Search:Match(camp)
        tooltip:AddLine(format(L["Has %d of the %d buffs you're looking for"], have, ns.Search:WantedCount()),
            matches and 0.4 or 1, matches and 1 or 0.5, matches and 0.4 or 0.5)
    end

    -- Each item, its tier, the buff it gives, and what a higher tier adds.
    local equipment = camps:ObjectList(camp)
    if #equipment > 0 then
        tooltip:AddLine(" ")
        local quality, points = camps:Quality(camp)
        local r, g, b = unpack(camps.QUALITIES[quality].color)
        tooltip:AddDoubleLine(L["Camp Equipment"], format(L["%s (%d points)"], camps.QUALITIES[quality].name, points),
            1, 0.82, 0, r, g, b)
        -- In red, with the class buff, where a buff you have already gives that stat.
        local covered = ns.CoveredCampBuffs()
        for _, object in ipairs(equipment) do
            local profession = object.skillLine and ns.PROFESSION_BY_ID[object.skillLine]
            local icon = object.icon and format("|T%s:16:16:0:0:64:64:5:59:5:59|t ", object.icon) or "  "
            local name = object.name .. (object.tier and format(" |cffaaaaaa%s|r", format(L["T%d"], object.tier)) or "")
            local have = object.skillLine and covered[object.skillLine]
            local buff = profession and not profession.notSearchable and profession.buff or ""
            if have then
                tooltip:AddDoubleLine(icon .. name, format(L["%s (you have %s)"], buff, have), 1, 1, 1, 1, 0.35, 0.3)
            else
                tooltip:AddDoubleLine(icon .. name, buff, 1, 1, 1, 0.4, 1, 0.4)
            end
            local extras = object.skillLine and (ns.OBJECT_EXTRAS[object.skillLine] or {})[object.tier or 1]
            if extras and ((object.tier or 1) > 1 or not ns.STAT_BUFF[object.skillLine]) then
                tooltip:AddLine("      " .. format(L["Adds %s"], ns.JoinList(extras)), 0.7, 0.7, 0.7, true)
            end
        end
    end
end

local function CreateStatusIcon(parent)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetSize(ICON_SIZE + 30, HEIGHT - 6)
    frame:EnableMouse(true)
    ns.Style:SkipControllerCursor(frame)

    frame.icon = frame:CreateTexture(nil, "ARTWORK")
    frame.icon:SetSize(ICON_SIZE, ICON_SIZE)
    frame.icon:SetPoint("LEFT")
    frame.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    frame.text = ns.Style:Text(frame, "GameFontHighlightSmall")
    frame.text:SetPoint("LEFT", frame.icon, "RIGHT", 3, 0)

    ns.Style:CustomTooltip(frame, "ANCHOR_TOP", function(tooltip, self)
        if self.auraInstanceID and ns.SetBuffTooltip(self.auraInstanceID) then
            -- Shows your actual buff, including the camp's stat boosts.
        elseif self.spellID then
            tooltip:SetSpellByID(self.spellID)
        else
            tooltip:AddLine(self.tooltipText or "")
        end
    end)
    return frame
end

-- The icon buttons, together in the middle of the bar: in Standard mode
-- (Mode.lua) without the Camp Builder's, the others closing up.
local function LayoutButtons(bar)
    local enhanced = ns.IsEnhanced()
    if bar.laidFor == enhanced then return end
    bar.laidFor = enhanced
    bar.finder:SetShown(enhanced)
    local shown = {}
    for _, button in ipairs(bar.buttons) do
        if button:IsShown() then shown[#shown + 1] = button end
    end
    for i, button in ipairs(shown) do
        button:ClearAllPoints()
        if i == 1 then
            button:SetPoint("LEFT", bar, "CENTER", -(#shown * BUTTON_SIZE + (#shown - 1) * BUTTON_GAP) / 2, 0)
        else
            button:SetPoint("LEFT", shown[i - 1], "RIGHT", BUTTON_GAP, 0)
        end
    end
end

local function IsMapMaximized()
    return WorldMapFrame.IsMaximized and WorldMapFrame:IsMaximized()
end

function MapBar:Init()
    -- The dock: one frame, in the map's metal, holding the camp bar and the Find a camp strip.
    local dock = CreateFrame("Frame", "HappyCamperMapDock", WorldMapFrame)
    dock:SetFrameStrata("HIGH")
    dock:SetFrameLevel(WorldMapFrame.BorderFrame:GetFrameLevel() + 10)
    dock:EnableMouse(true)
    ns.Style:MetalFrame(dock, true) -- refitted in MapBar:Watch
    dock.divider = dock:CreateTexture(nil, "ARTWORK")
    dock.divider:SetHeight(1)
    dock.divider:SetColorTexture(0.9, 0.55, 0.2, 0.5)
    self.dock = dock

    local bar = CreateFrame("Frame", "HappyCamperMapBar", dock)
    bar:SetHeight(HEIGHT)
    bar:SetFrameLevel(dock:GetFrameLevel() + 2)
    bar:EnableMouse(true)

    bar.label = ns.Style:Text(bar, "GameFontNormalSmall")
    bar.label:SetPoint("LEFT", PAD, 0)

    -- The icon buttons, together in the middle of the bar.
    local style = ns.Style
    bar.showCamps = style:IconButton(bar, BUTTON_SIZE, "Interface\\Icons\\Spell_Fire_Fire", function(self)
        ns.SetShowCamps(not ns.db.mapPins)
        self:GetScript("OnEnter")(self)
    end, function() return ns.db.mapPins and L["Show camps: on"] or L["Show camps: off"] end,
    function() return ns.db.mapPins and L["Click to hide all camps from the map."] or L["Click to show camps on the map again."] end)
    -- Camps on other layers: faded on the map, or hidden (Options has it too).
    bar.layers = style:IconButton(bar, BUTTON_SIZE, "Interface\\Icons\\Spell_Nature_Invisibilty", function(self)
        ns.db.showOtherLayers = not ns.db.showOtherLayers
        ns.OnCampsChanged()
        if ns.Options.Sync then ns.Options:Sync() end
        MapBar:Refresh()
        self:GetScript("OnEnter")(self)
    end, function() return ns.db.showOtherLayers and L["Other layers: shown"] or L["Other layers: hidden"] end,
    function() return ns.db.showOtherLayers and L["Camps on other layers show faded: you may not see their fire. Click to hide them."]
        or L["Camps on other layers are hidden. Click to show them, faded."] end)
    -- Ashes where camps burned out lately, and popular campsites (Campsites.lua;
    -- Options has them too).
    local function Switch(key)
        return function(self)
            ns.db[key] = not ns.db[key]
            ns.OnCampsChanged()
            if ns.Options.Sync then ns.Options:Sync() end
            ns.MapPins:Refresh()
            MapBar:Refresh()
            self:GetScript("OnEnter")(self)
        end
    end
    bar.ashes = style:IconButton(bar, BUTTON_SIZE, ns.Style.MINIMAP_ICON, Switch("mapAshes"),
        function() return ns.db.mapAshes and L["Recent camps: shown"] or L["Recent camps: hidden"] end,
        function() return ns.db.mapAshes and L["Where camps burned out in the last 3 hours shows as ashes. Click to hide them."]
            or L["Click to show where camps burned out in the last 3 hours, as ashes."] end)
    bar.campsites = style:IconButton(bar, BUTTON_SIZE, ns.Style.RING, Switch("mapCampsites"),
        function() return ns.db.mapCampsites and L["Popular campsites: shown"] or L["Popular campsites: hidden"] end,
        function() return ns.db.mapCampsites and L["Spots where players often camp show as orange circles. Click to hide them."]
            or L["Click to show spots where players often camp, as orange circles."] end)
    -- Its orange middle, inside the ring (the ring's the button's own picture).
    bar.campsites.fill = bar.campsites:CreateTexture(nil, "BACKGROUND")
    bar.campsites.fill:SetPoint("CENTER")
    bar.campsites.fill:SetSize(BUTTON_SIZE * ns.Style.RING_HOLE, BUTTON_SIZE * ns.Style.RING_HOLE)
    bar.finder = style:IconButton(bar, BUTTON_SIZE, "Interface\\Icons\\INV_Misc_Map_01",
        function() ns.Finder:Toggle() end, L["Camp Builder"], L["Build a camp with the buffs you want, or join someone's."])
    bar.options = style:IconButton(bar, BUTTON_SIZE, "Interface\\Icons\\INV_Misc_Gear_01",
        function() ns.Options:Toggle() end, L["Happy Camper options"])
    bar.buttons = { bar.showCamps, bar.layers, bar.ashes, bar.campsites, bar.finder, bar.options }
    -- Controller cursors stay off the dock, the bar and its buttons (Style:SkipControllerCursor).
    for _, frame in ipairs({ dock, bar, unpack(bar.buttons) }) do style:SkipControllerCursor(frame) end
    LayoutButtons(bar)
    -- The count stops short of the buttons, on two lines if it needs them (a
    -- translation on the windowed map).
    bar.label:SetPoint("RIGHT", bar.showCamps, "LEFT", -8, 0)
    bar.label:SetJustifyH("LEFT")
    bar.label:SetWordWrap(true)
    bar.label:SetMaxLines(2)

    bar.statusIcons = {}
    self.bar = bar

    -- No hooks on the map, and no scripts that run as it opens, closes or
    -- changes size: Happy Camper code running in those steps had the game
    -- block the map's own protected calls and blame Happy Camper (with a
    -- controller, the call that points the controller at the map). The
    -- pins' check every frame while the map is open, a step of its own,
    -- follows it instead (MapBar:Watch).

    self:Refresh()
    ns.Search:SetOpen(ns.db.mapBar and ns.IsEnhanced())
end

-- Every frame while the map is open (MapPins' check, its own step): the dock
-- follows the map between windowed and full screen, its metal refits as it
-- changes size, and Find a camp lays out its buff chips again for a new width.
-- opened: the map's first frame open (Find a camp shows what's picked now).
function MapBar:Watch(opened)
    local dock = self.dock
    if not dock then return end
    self:LayoutDock()
    local width, height = dock:GetWidth(), dock:GetHeight()
    if width ~= self.dockWidth or height ~= self.dockHeight then
        self.dockWidth, self.dockHeight = width, height
        ns.Style:FitMetal(dock)
    end
    ns.Search:Watch(opened)
end

-- Places the dock below the map window, or along the bottom of a full-screen
-- map, and stacks the camp bar and the Find a camp strip inside it.
function MapBar:LayoutDock()
    local dock, bar = self.dock, self.bar
    if not dock then return end
    local strip = ns.Search.bar
    local showBar = ns.db.mapBar
    local showSearch = strip ~= nil and strip:IsShown()
    -- Only re-anchor when something changed (this runs every second while the map is open).
    local layout = format("%s:%s:%s", tostring(showBar), tostring(showSearch), tostring(IsMapMaximized()))
    if layout == self.dockLayout then return end
    self.dockLayout = layout
    if not showBar and not showSearch then
        dock:Hide()
        return
    end

    -- The metal reaches past the dock (Style:MetalFrame): below the map its top
    -- edge meets the map's bottom edge; on a full-screen map it stays inside the map.
    local overhang = dock.metal and ns.Style.METAL_OVERHANG or 0
    dock:ClearAllPoints()
    if IsMapMaximized() then
        local container = WorldMapFrame.ScrollContainer
        local left, right = dock.metal and 13 or 0, dock.metal and 2 or 0
        dock:SetPoint("BOTTOMLEFT", container, "BOTTOMLEFT", left, overhang)
        dock:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", -right, overhang)
    else
        local gap = dock.metal and 0 or 2
        dock:SetPoint("TOPLEFT", WorldMapFrame, "BOTTOMLEFT", 0, -gap)
        dock:SetPoint("TOPRIGHT", WorldMapFrame, "BOTTOMRIGHT", 0, -gap)
    end

    local barHeight = showBar and (EDGE + HEIGHT) or 0
    local stripTop = showBar and barHeight or 4
    bar:ClearAllPoints()
    bar:SetPoint("TOPLEFT", dock, "TOPLEFT", EDGE, -EDGE)
    bar:SetPoint("TOPRIGHT", dock, "TOPRIGHT", -EDGE, -EDGE)
    if showSearch then
        strip:ClearAllPoints()
        strip:SetPoint("TOPLEFT", dock, "TOPLEFT", 0, -stripTop)
        strip:SetPoint("TOPRIGHT", dock, "TOPRIGHT", 0, -stripTop)
        strip:SetFrameLevel(dock:GetFrameLevel() + 2)
    end
    dock.divider:SetShown(showBar and showSearch)
    dock.divider:ClearAllPoints()
    dock.divider:SetPoint("TOPLEFT", dock, "TOPLEFT", EDGE + 6, -barHeight - 2)
    dock.divider:SetPoint("TOPRIGHT", dock, "TOPRIGHT", -EDGE - 6, -barHeight - 2)
    dock:SetHeight(showSearch and (stripTop + ns.Search.HEIGHT + SEARCH_PADDING) or (barHeight + EDGE))
    dock:Show()
end

-- camps, total and hidden are the displayed map's Camps:ShownOnMap, when the
-- map pins have just worked them out; otherwise they're worked out here.
function MapBar:Refresh(camps, total, hidden)
    local bar = self.bar
    if not bar then return end
    bar:SetShown(ns.db.mapBar)
    LayoutButtons(bar)
    -- Find a camp always shows under the bar, and goes with it; Standard mode
    -- (Mode.lua) has none.
    local search = ns.db.mapBar == true and ns.IsEnhanced()
    if ns.Search:IsOpen() ~= search then ns.Search:SetOpen(search) end
    self:LayoutDock()
    if not ns.db.mapBar then return end

    local now = GetTime()

    -- Right side: your buffs, then your object cooldown, laid out leftwards.
    local statusCount = 0
    local function NextStatus()
        statusCount = statusCount + 1
        local icon = bar.statusIcons[statusCount] or CreateStatusIcon(bar)
        bar.statusIcons[statusCount] = icon
        return icon
    end

    local c = ns.charDB
    local cooldownLeft = c.objectReadyAt and (c.objectReadyAt - GetServerTime())
    if cooldownLeft and cooldownLeft > 0 then
        local icon = NextStatus()
        icon.icon:SetTexture(c.objectIcon or QUESTION_MARK_ICON)
        icon.icon:SetDesaturated(true)
        icon.text:SetText(ShortTime(cooldownLeft))
        icon.spellID, icon.auraInstanceID = nil, nil
        icon.tooltipText = format(L["%s can be placed again in %s"], c.objectName or L["Your object"], ns.FormatTime(cooldownLeft))
    end
    for _, buff in ipairs(ns.state.buffs) do
        local icon = NextStatus()
        icon.icon:SetTexture(buff.icon or QUESTION_MARK_ICON)
        icon.icon:SetDesaturated(false)
        local expires = buff.expirationTime or 0
        icon.text:SetText(expires > 0 and ShortTime(expires - now) or "")
        icon.spellID, icon.auraInstanceID = buff.spellId, buff.auraInstanceID
    end
    -- How many other Happy Campers were seen today (Stats.lua), so the camping
    -- community shows even when there are few camps.
    local seen = ns.db.campersSeen and ns.Stats:Counts()
    if seen and seen.day > 0 then
        local icon = NextStatus()
        icon.icon:SetTexture(CAMPERS_ICON)
        icon.icon:SetDesaturated(false)
        icon.text:SetText(tostring(seen.day))
        icon.spellID, icon.auraInstanceID = nil, nil
        icon.tooltipText = format(L["Happy Campers seen today: %d (this week: %d)"], seen.day, seen.week)
    end

    local right = -PAD
    for i = 1, #bar.statusIcons do
        local icon = bar.statusIcons[i]
        if i <= statusCount then
            icon:ClearAllPoints()
            icon:SetPoint("RIGHT", bar, "RIGHT", right, 0)
            icon:Show()
            right = right - icon:GetWidth() - 2
        else
            icon:Hide()
        end
    end

    -- Left side: how many camps are on the displayed map.
    local mapID = WorldMapFrame:GetMapID()
    local showCamps = ns.db.mapPins
    bar.showCamps:GetNormalTexture():SetDesaturated(not showCamps)
    bar.showCamps:GetNormalTexture():SetAlpha(showCamps and 1 or 0.5)
    -- Ashes are grey either way; off, both are faint.
    bar.ashes:GetNormalTexture():SetDesaturated(true)
    bar.ashes:GetNormalTexture():SetAlpha(ns.db.mapAshes and 1 or 0.4)
    -- The campsites' mark as on the map (ns.StyleCampsiteMark), grey and faint when off.
    local ring = bar.campsites:GetNormalTexture()
    ns.StyleCampsiteMark(ring, bar.campsites.fill, not ns.db.mapCampsites)
    ring:SetAlpha(ns.db.mapCampsites and 1 or 0.4)
    bar.campsites.fill:SetAlpha(ns.db.mapCampsites and 1 or 0.4)
    -- The same camps as the map shows (Camps:ShownOnMap).
    if not camps then
        camps, total = {}, 0
        if showCamps and mapID then
            camps, total, hidden = ns.Camps:ShownOnMap(mapID)
        else
            hidden = mapID and ns.Camps:MapHidesCamps(mapID)
        end
    end
    -- Camp Builder meet-ups: not in Standard mode.
    local requests = mapID and ns.IsEnhanced() and ns.Requests:OnMap(mapID) or {}
    local requestText = #requests > 0 and ("  |cff88ccff" .. format(L["Requests: %d"], #requests) .. "|r") or ""
    local searching = ns.Search:IsActive()
    -- With more than one of the Find a camp picks needed: how many, "(all 2)".
    local needs = searching and ns.Search:ThresholdText()
    needs = needs and (" " .. needs) or ""

    local text
    if not showCamps then
        text = L["Camps hidden"]
    elseif hidden == "zoomed" then
        text = L["Zoom in to a zone to see camps"]
    elseif not ns.db.network and #camps == 0 then
        text, requestText = L["Camp network off"], ""
    elseif #camps == 0 then
        text = searching and (L["No matching camps on this map"] .. needs) or L["No known camps on this map"]
    elseif total > #camps then
        text = format(searching and L["Matching camps: %d nearest of %d"] or L["Camps: %d nearest of %d"], #camps, total) .. needs
    else
        text = format(searching and L["Matching camps: %d"] or L["Camps: %d"], #camps) .. needs
    end
    bar.label:SetText(text .. requestText)
end
