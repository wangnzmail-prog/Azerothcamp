-- Happy Camper. Copyright (c) 2026 Torridon. All rights reserved; see LICENSE.
local _, ns = ...

-- Camps on the minimap: the same camps the world map shows for the zone
-- you're in, as small fire icons. A camp past the minimap's edge (but within EDGE_RANGE
-- yards) sits on the edge, faded, pointing the way. Hover one for its
-- tooltip. Options can turn them off.

local MinimapPins = {}
ns.MinimapPins = MinimapPins

local SIZE = 14
local EDGE_SIZE = 11
local EDGE_RANGE = 1000 -- yards
local MOVE_EVERY = 0.05 -- seconds between position updates
local REFRESH_EVERY = 2 -- seconds: camps picked again at least this often (layers, smoke) when nothing else asks

-- How many yards across the minimap is at each zoom level (0-5), outdoors and indoors.
local OUTDOOR = { 466.67, 400, 333.33, 266.67, 200, 133.33 }
local INDOOR = { 300, 240, 180, 120, 80, 50 }

local SMOKY_ALPHA = 0.6 -- a camp seen only by its smoke (Standard mode)

local RING = "Interface\\CharacterFrame\\TempPortraitAlphaMask"   -- coloured by the camp's quality
local PLAIN_BACKING = "Interface\\Minimap\\UI-Minimap-Background" -- Standard mode's plain pin
local WHITE = { 1, 1, 1 }

local pins, shown = {}, {} -- the icons, and { camp, x, y } for each camp to show
local zone -- the map shown's camps are placed on (your zone)
local placed = {} -- what the pins were last placed for: where you were, facing, zoom (Move)
local lastMap, lastRefresh = nil, -math.huge

-- Sizes a pin's parts: like the world map's pins (MapPins.xml), scaled down to
-- size - a round backing, the fire icon in a circle, and the tracking border.
local function SizePin(pin, size)
    if pin.size == size then return end
    pin.size = size
    pin:SetSize(size, size)
    pin.background:SetSize(size * ns.RING_SIZE / 22, size * ns.RING_SIZE / 22)
    pin.icon:SetSize(size * 18 / 22, size * 18 / 22)
    local border = size * 38 / 22
    pin.border:SetSize(border, border)
    ns.CentreTrackingBorder(pin.border, pin, border)
end

local function Pin(i)
    local pin = pins[i]
    if not pin then
        pin = CreateFrame("Frame", nil, Minimap)
        pin:SetFrameLevel(Minimap:GetFrameLevel() + 5)
        pin.background = pin:CreateTexture(nil, "BACKGROUND")
        pin.background:SetPoint("CENTER")
        -- A ring in the camp's quality colour (Camps:Quality) around the icon,
        -- over the border's inner edge (so it's centred on the icon), under the icon.
        pin.background:SetTexture(RING)
        pin.background:SetDrawLayer("OVERLAY", 1)
        pin.icon = pin:CreateTexture(nil, "OVERLAY", nil, 2)
        pin.icon:SetPoint("CENTER")
        pin.icon:SetTexture("Interface\\Icons\\Spell_Fire_Fire")
        local mask = pin.CreateMaskTexture and pin:CreateMaskTexture()
        if mask then
            mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
            mask:SetAllPoints(pin.icon)
            pin.icon:AddMaskTexture(mask)
        end
        pin.border = pin:CreateTexture(nil, "OVERLAY")
        pin.border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
        SizePin(pin, SIZE)
        pin:EnableMouse(true)
        -- Hover only: clicks go through to the minimap.
        if pin.SetMouseClickEnabled then pin:SetMouseClickEnabled(false) end
        pin:SetScript("OnEnter", function(self)
            ns.ShowLiveTooltip(self, "ANCHOR_RIGHT", function(tooltip) ns.MapBar:FillCampTooltip(tooltip, self.camp, self.smoky) end)
        end)
        pin:SetScript("OnLeave", function() GameTooltip:Hide() end)
        pins[i] = pin
    end
    return pin
end

local function HideFrom(first)
    for i = first, #pins do pins[i]:Hide() end
end

-- Places the icons for where you are now and which way the minimap faces.
function MinimapPins:Move()
    if not zone then return HideFrom(1) end
    local pos = C_Map.GetPlayerMapPosition(zone, "player")
    if not pos then return HideFrom(1) end
    local px, py = ns.XY(pos)
    local width, height = ns.MapYards(zone)
    if not px or ns.IsSecret(px) or not width then return HideFrom(1) end

    local zoom = Minimap:GetZoom() or 0
    local indoors = IsIndoors()
    local diameter = (indoors and INDOOR or OUTDOOR)[zoom + 1] or OUTDOOR[1]
    local radius = Minimap:GetWidth() / 2
    local scale = radius / (diameter / 2) -- pixels per yard
    local facing = C_CVar and C_CVar.GetCVar("rotateMinimap") == "1" and GetPlayerFacing() or nil
    if facing and ns.IsSecret(facing) then facing = nil end
    local square = GetMinimapShape and GetMinimapShape() == "SQUARE"
    -- Standing still, with nothing new to show: the pins are where they were.
    if not placed.stale and placed.px == px and placed.py == py and placed.facing == facing and placed.zoom == zoom
        and placed.indoors == indoors and placed.radius == radius and placed.square == square then
        return
    end
    placed.stale, placed.px, placed.py, placed.facing, placed.zoom = false, px, py, facing, zoom
    placed.indoors, placed.radius, placed.square = indoors, radius, square

    local n = 0
    for _, entry in ipairs(shown) do
        -- Yards east and north of you.
        local east, north = (entry.x - px) * width, (py - entry.y) * height
        if facing then
            local c, s = math.cos(facing), math.sin(facing)
            east, north = east * c + north * s, -east * s + north * c
        end
        local distance = math.sqrt(east * east + north * north)
        if distance <= EDGE_RANGE then
            local sx, sy = east * scale, north * scale
            local edge = false
            local limit = radius - EDGE_SIZE / 2
            if square then
                local over = math.max(math.abs(sx), math.abs(sy)) / limit
                if over > 1 then sx, sy, edge = sx / over, sy / over, true end
            elseif distance * scale > limit then
                local shrink = limit / (distance * scale)
                sx, sy, edge = sx * shrink, sy * shrink, true
            end
            n = n + 1
            local pin = Pin(n)
            pin.camp, pin.smoky = entry.camp, entry.smoky
            SizePin(pin, edge and EDGE_SIZE or SIZE)
            pin:ClearAllPoints()
            pin:SetPoint("CENTER", Minimap, "CENTER", sx, sy)
            -- Its look, worked out in Refresh.
            pin.icon:SetDesaturated(entry.unconfirmed)
            if pin.plain ~= entry.plain then
                pin.plain = entry.plain
                pin.background:SetTexture(entry.plain and PLAIN_BACKING or RING)
                pin.background:SetDrawLayer(entry.plain and "BACKGROUND" or "OVERLAY", entry.plain and 0 or 1)
            end
            pin.background:SetVertexColor(unpack(entry.color))
            pin:SetAlpha((edge and 0.6 or 1) * (entry.faded and 0.5 or 1) * (entry.smoky and SMOKY_ALPHA or 1))
            pin:Show()
        end
    end
    HideFrom(n + 1)
end

-- Picks the camps to show.
function MinimapPins:Refresh()
    wipe(shown)
    zone = nil
    placed.stale = true
    lastRefresh = GetTime()
    local playerMap = C_Map.GetBestMapForUnit("player")
    lastMap = playerMap and not ns.IsSecret(playerMap) and playerMap or nil
    if ns.db.minimapPins and playerMap and not ns.IsSecret(playerMap) then
        -- In a city, its own map: you're on it (the zone's camps around show on it too).
        zone = ns.ZoneOf(playerMap, true)
        if ns.IsOutdoorMap(zone) then
            for _, entry in ipairs((ns.Camps:ShownOnMap(zone))) do shown[#shown + 1] = entry end
        else
            zone = nil
        end
    end
    -- Each camp's look, once a second here rather than on every move: faded on
    -- another layer, grey and faded if unconfirmed (posted in chat), ringed in
    -- its quality's colour; in Standard mode (Mode.lua: no camp details), the
    -- plain dark backing instead.
    -- In Standard mode other players' camps are smoke on the world map (Camps:Smoky),
    -- so here they're not at the fire either: at the middle of the smoke, fainter.
    local plain = not ns.IsEnhanced()
    local here = plain and (ns.Camps:NearPlayer(ns.Camps.MERGE_RADIUS) or false)
    for _, entry in ipairs(shown) do
        local camp = entry.camp
        entry.unconfirmed = ns.Camps:Unconfirmed(camp)
        entry.faded = entry.unconfirmed or ns.Camps:LayerStatus(camp) == "other"
        entry.smoky = plain and ns.Camps:Smoky(camp, here)
        if entry.smoky then entry.x, entry.y = ns.Camps:SmokeOnMap(camp, zone, entry.x, entry.y) end
        entry.plain = plain
        entry.color = plain and WHITE or ns.Camps.QUALITIES[ns.Camps:Quality(camp)].color
    end
    self:Move()
end

-- Once a second, from Core's tick: the camps are picked again when they've
-- changed (campsChanged), when you're on another map, or every REFRESH_EVERY
-- seconds; not every second regardless.
function MinimapPins:Tick(campsChanged)
    local playerMap = C_Map.GetBestMapForUnit("player")
    if playerMap and ns.IsSecret(playerMap) then playerMap = nil end
    if campsChanged or playerMap ~= lastMap or GetTime() - lastRefresh >= REFRESH_EVERY then self:Refresh() end
end

local driver = CreateFrame("Frame")
local since = 0
driver:SetScript("OnUpdate", function(_, elapsed)
    since = since + elapsed
    if since >= MOVE_EVERY and #shown > 0 then
        since = 0
        MinimapPins:Move()
    end
end)
