-- Happy Camper. Copyright (c) 2026 Torridon. All rights reserved; see LICENSE.
local _, ns = ...
local L = ns.L

-- Camp pins on the world map. They're Happy Camper's own frames, on a layer of
-- its own laid over the map's canvas, and they look after themselves: none of
-- this runs inside the game's map code.
--
-- (They used to be the map's own kind of pin, from a data provider. The map
-- calls every provider as it opens, closes and changes map, and running addon
-- code there taints the rest of that run: the game's own pins, made after
-- ours, then had a protected call blocked and blamed on Happy Camper.)
--
-- The game's map frames are only ever read here (GetMapID, GetCanvas, sizes
-- and scales), never written to. The pin template is in MapPins.xml.
--
-- In Standard mode (Mode.lua) other players' camps show as a haze of smoke
-- instead (Camps:Smoky): the same pins, drawn as smoke covering about 200 yards
-- of the map, with the fire somewhere in it (zoomed out to a continent or the
-- world, a small faint dot of it).

local TEMPLATE = "HappyCamperPinTemplate"
local PIN_SIZE = 22 -- as the template

-- Pins keep one size on screen as the map zooms, growing a little (by a
-- quarter) from all the way out to all the way in, like the map's own markers.
-- They're drawn at 80% of the template's size, so they sit lightly on the map.
local SCALE_OUT, SCALE_IN = 0.8, 1.0
-- On a continent's or the world's map (ns.IsWideMap) they're smaller, so dozens
-- of camps don't run together into one blob.
local WIDE_SCALE = 0.6

-- The overlay's frame level: the one the map gives its own area markers
-- (PIN_FRAME_LEVEL_AREA_POI), read from its frame levels manager. That's a
-- lookup that changes nothing. The map's pins start at level 2000 (its art,
-- explored areas and other overlays lowest, then flight paths, area markers
-- and the like, quests, group members and you on top), so camps go over the
-- map's art and under its quests. If the level can't be read, just above the
-- map's lowest pins.
local AREA_POI = "PIN_FRAME_LEVEL_AREA_POI"
local FALLBACK_LEVEL = 2100

local function OverlayLevel()
    local get = WorldMapFrame.GetPinFrameLevelsManager
    if type(get) == "function" then
        local ok, manager = pcall(get, WorldMapFrame)
        if ok and type(manager) == "table" and type(manager.GetValidFrameLevel) == "function" then
            local found, level = pcall(manager.GetValidFrameLevel, manager, AREA_POI)
            if found and type(level) == "number" and level > 0 then return level end
        end
    end
    return FALLBACK_LEVEL
end

local MapPins = {}
ns.MapPins = MapPins
MapPins.pins = {} -- [camp or request ID] = its pin on the open map
local active = {} -- ["camp:" or "request:" .. ID] = each pin on the map (a camp and a meet-up may share an ID)
local spare = {}  -- pins not in use, hidden, to use again
local overlay, canvas
-- What the pins were last laid out for: the map, the canvas's size and scale,
-- and the pins' scale.
local laid = {}

local PinMethods = {}

-- MiniMap-TrackingBorder's round hole isn't in the middle of its texture: its
-- centre is about 33% in from the left and 30% down (the game's minimap buttons'
-- layout, nudged a pixel by eye in game). Anchored so the hole is centred on
-- frame, around its icon and quality ring, with no crescent showing on one side.
local BORDER_HOLE_X, BORDER_HOLE_Y = 0.326, 0.296
ns.RING_SIZE = 24 -- a camp pin's quality ring, on a 22 pin (the border's hole is about 22)
function ns.CentreTrackingBorder(border, frame, size)
    border:ClearAllPoints()
    border:SetPoint("TOPLEFT", frame, "CENTER", -BORDER_HOLE_X * size, BORDER_HOLE_Y * size)
end

-- Standard mode's smoke: soft round discs, one inside another, so the haze is
-- thickest in its middle and thins out to its edge (each disc a share of the
-- smoke's width; together about half opaque in the middle). No fire
-- symbol: only the smoke shows, and hovering it says whose camp it is.
local SMOKE_LAYERS = { 1, 0.84, 0.68, 0.52, 0.36 }
local SMOKE_COLOUR = { 0.32, 0.3, 0.29, 0.14 } -- a dark smoke grey, to stand out on the light parchment
-- A solid line round the smoke's edge, so it's easy to see without darkening
-- the map under it (Media/SmokeRing: art/tools/make_smoke_ring.py).
local SMOKE_EDGE = ns.Style.MEDIA .. "SmokeRing"
local SMOKE_EDGE_COLOUR = { 0.24, 0.21, 0.19, 0.8 }
-- Hovering the smoke: its square, less this share of it on each side, which
-- is about its round part.
local SMOKE_HIT = 0.15
-- Zoomed out to a continent or the world, 200 yards of smoke is only a few
-- pixels: it's drawn at least this wide (at the pins' size), a faint dot of
-- smoke a little bigger than a pin.
local SMOKE_LEAST = 24

-- Once, when a pin is made.
function PinMethods:Setup()
    ns.CentreTrackingBorder(self.Border, self, 38)
    -- The icon above the border (and a camp's quality ring, between them).
    self.Icon:SetDrawLayer("OVERLAY", 2)
    -- The smoke, under everything else; shown only for a camp seen by its smoke (Update).
    self.smoke = {}
    for i in ipairs(SMOKE_LAYERS) do
        local puff = self:CreateTexture(nil, "BACKGROUND", nil, -8 + i)
        puff:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask")
        puff:SetVertexColor(unpack(SMOKE_COLOUR))
        puff:SetPoint("CENTER")
        puff:Hide()
        self.smoke[i] = puff
    end
    self.smokeEdge = self:CreateTexture(nil, "BACKGROUND", nil, -1)
    self.smokeEdge:SetTexture(SMOKE_EDGE)
    self.smokeEdge:SetVertexColor(unpack(SMOKE_EDGE_COLOUR))
    self.smokeEdge:SetAllPoints()
    self.smokeEdge:Hide()
    -- A ring spreading out from the camp selected in the on-screen panel
    -- (played by MapPins:Ripple).
    local ring = self:CreateTexture(nil, "BACKGROUND", nil, -2)
    ring:SetSize(44, 44)
    ring:SetPoint("CENTER")
    ring:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask")
    ring:SetVertexColor(1, 0.6, 0.2)
    ring:SetBlendMode("ADD")
    ring:SetAlpha(0)
    self.ripple = ring:CreateAnimationGroup()
    local grow = self.ripple:CreateAnimation("Scale")
    grow:SetScaleFrom(0.3, 0.3)
    grow:SetScaleTo(1.4, 1.4)
    local fade = self.ripple:CreateAnimation("Alpha")
    fade:SetFromAlpha(0.8)
    fade:SetToAlpha(0)
    grow:SetDuration(1.2)
    fade:SetDuration(1.2)
    -- A group's count (on a continent's or the world's map).
    self.count = self:CreateFontString(nil, "OVERLAY", _G[COUNT_FONT] and COUNT_FONT or "GameFontNormal")
    self.count:SetPoint("LEFT", self, "RIGHT", -1, 0)
    self.count:Hide()
    self:SetScript("OnEnter", self.OnMouseEnter)
    self:SetScript("OnLeave", self.OnMouseLeave)
    -- Only meet-up pins, and camp pins where you can ask for a layer invite,
    -- take clicks (Update); other camp pins' go through to the map.
    self:SetScript("OnMouseUp", function(pin, button, upInside)
        if upInside ~= false then pin:OnClick(button) end
    end)
end

local CAMP_ICON = "Interface\\Icons\\Spell_Fire_Fire"
-- Its count, beside a group's pin (on a continent's or the world's map).
local COUNT_FONT = "NumberFontNormalLarge"
local REQUEST_ICON = "Interface\\Icons\\INV_Misc_Map_01"

-- Where a pin goes on the canvas (x and y from 0 to 1), at the pins' scale. A
-- frame's offsets are in its own scale, so they're divided by it. Smoke covers
-- its share of the map at any zoom, so its size is divided by the scale too
-- (on a continent's or the world's map, no smaller than SMOKE_LEAST).
local function Place(pin)
    -- A group's pin is a zone map's size, so its count can be read.
    local scale = pin.kind == "group" and laid.wide and laid.scale / WIDE_SCALE or laid.scale
    pin:SetScale(scale)
    pin:ClearAllPoints()
    pin:SetPoint("CENTER", overlay, "TOPLEFT", pin.x * laid.width / scale, -pin.y * laid.height / scale)
    if pin.hazy then
        local width, height = 2 * pin.rx * laid.width / scale, 2 * pin.ry * laid.height / scale
        if laid.wide then width, height = math.max(width, SMOKE_LEAST), math.max(height, SMOKE_LEAST) end
        pin:SetSize(width, height)
        pin:SetHitRectInsets(width * SMOKE_HIT, width * SMOKE_HIT, height * SMOKE_HIT, height * SMOKE_HIT)
        for i, share in ipairs(SMOKE_LAYERS) do pin.smoke[i]:SetSize(width * share, height * share) end
    end
end

-- Places and styles the pin for its camp or meet-up (kind is "camp" or
-- "request"): when it's put on the map, and again on each refresh while it
-- stays there. With rx and ry the camp shows as smoke (Camps:Smoky): x, y is
-- the smoke's middle, and rx, ry its radius across and down the map.
function PinMethods:Update(record, x, y, kind, rx, ry)
    self.record, self.kind = record, kind
    MapPins.pins[record.id] = self
    self.x, self.y = x, y
    if kind == "ash" or kind == "spot" then return self:UpdateMark() end
    local hazy = rx ~= nil
    self.hazy, self.rx, self.ry = hazy, rx, ry
    if not hazy then
        self:SetSize(PIN_SIZE, PIN_SIZE)
        self:SetHitRectInsets(0, 0, 0, 0)
    end
    for _, puff in ipairs(self.smoke) do puff:SetShown(hazy) end
    self.smokeEdge:SetShown(hazy)
    self.Border:SetShown(not hazy)
    self.Background:SetShown(not hazy)
    -- Smoke has no fire symbol: just the haze (hovering it still names the camp).
    self.Icon:SetSize(18, 18)
    self.Icon:SetShown(not hazy)
    -- Smoke goes under the exact pins, so a pin in someone's smoke can be hovered.
    self:SetFrameLevel(overlay:GetFrameLevel() + (hazy and 1 or 2))
    Place(self)
    self.Icon:SetTexture(kind == "request" and REQUEST_ICON or CAMP_ICON)
    -- A camp on another layer with someone there who takes layer invite
    -- requests: a click asks them (LayerInvites.lua).
    self.askable = kind == "camp" and ns.LayerInvites:CanAsk(record)
    if self.SetMouseClickEnabled then self:SetMouseClickEnabled(kind == "request" or kind == "group" or self.askable) end
    self.count:SetShown(kind == "group")
    if kind == "group" then self.count:SetText(record.count) end
    local mine = kind == "camp" and ns.Camps:IsMine(record) or kind == "request" and ns.Requests:IsMine(record)
    self.Icon:SetVertexColor(1, mine and 0.85 or 1, mine and 0.6 or 1)
    -- A camp on another layer is faded: you may not see its fire. One posted in
    -- chat is grey and faded: nobody with the addon has rested there yet.
    local unconfirmed = kind == "camp" and ns.Camps:Unconfirmed(record)
    self.Icon:SetDesaturated(unconfirmed)
    self:SetAlpha(unconfirmed and 0.5 or kind == "camp" and ns.Camps:LayerStatus(record) == "other" and 0.4 or 1)
    -- Camps are ringed in their quality's colour (Camps:Quality); meet-ups, and
    -- camps in Standard mode (Mode.lua: no camp details), keep the plain dark
    -- backing.
    -- The ring is drawn over the border's inner edge, a little wider than its
    -- hole, so it's centred on the icon whatever pixel the border lands on.
    if kind == "camp" and ns.IsEnhanced() then
        local quality = ns.Camps.QUALITIES[ns.Camps:Quality(record)]
        self.Background:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask")
        self.Background:SetVertexColor(unpack(quality.color))
        self.Background:SetDrawLayer("OVERLAY", 1)
        self.Background:SetSize(ns.RING_SIZE, ns.RING_SIZE)
    else
        self.Background:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
        self.Background:SetVertexColor(1, 1, 1)
        self.Background:SetDrawLayer("BACKGROUND", 0)
        self.Background:SetSize(22, 22)
    end
end

-- Ashes and popular campsites (Campsites.lua): small and quiet, under the
-- camps, never mistaken for one. Ashes are Happy Camper's campfire gone grey;
-- a campsite is a soft orange disc, like a fire's glow, in a gold ring. No
-- border, no smoke, no clicks.
local ASH_ICON = ns.Style.MINIMAP_ICON
local MARK_SIZE = 16
local CAMPSITE_ORANGE = { 1, 0.55, 0.2, 0.85 }
local CAMPSITE_GOLD = { 1, 0.84, 0.3 }

-- A campsite's look, on the map and on the camp bar's button alike: ring (a
-- texture) is Happy Camper's ring, greyed and tinted gold, round fill, a soft
-- orange disc. off: both grey (the button while campsites are hidden).
function ns.StyleCampsiteMark(ring, fill, off)
    ring:SetTexture(ns.Style.RING)
    ring:SetDesaturated(true)
    fill:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask")
    if off then
        ring:SetVertexColor(1, 1, 1)
        fill:SetVertexColor(0.6, 0.6, 0.6, 0.5)
    else
        ring:SetVertexColor(unpack(CAMPSITE_GOLD))
        fill:SetVertexColor(unpack(CAMPSITE_ORANGE))
    end
end

function PinMethods:UpdateMark()
    local ash = self.kind == "ash"
    self.hazy = false
    self:SetSize(MARK_SIZE, MARK_SIZE)
    self:SetHitRectInsets(0, 0, 0, 0)
    for _, puff in ipairs(self.smoke) do puff:Hide() end
    self.smokeEdge:Hide()
    self.count:Hide()
    self.Border:Hide()
    self.askable = false
    if self.SetMouseClickEnabled then self:SetMouseClickEnabled(false) end
    self:SetFrameLevel(overlay:GetFrameLevel() + 1)
    Place(self)
    self.Icon:Show()
    self.Icon:SetSize(MARK_SIZE, MARK_SIZE)
    self.Background:SetShown(not ash)
    if ash then
        self.Icon:SetTexture(ASH_ICON)
        self.Icon:SetDesaturated(true)
        self.Icon:SetVertexColor(1, 1, 1)
    else
        ns.StyleCampsiteMark(self.Icon, self.Background)
        self.Background:SetDrawLayer("BACKGROUND", 0)
        self.Background:SetSize(MARK_SIZE * ns.Style.RING_HOLE, MARK_SIZE * ns.Style.RING_HOLE)
    end
    self:SetAlpha(ash and 0.75 or 1)
end

function PinMethods:OnMouseEnter()
    ns.ShowLiveTooltip(self, "ANCHOR_RIGHT", function(tooltip)
        if self.kind == "ash" or self.kind == "spot" then
            ns.Campsites:FillTooltip(tooltip, self.kind, self.record)
        elseif self.kind == "request" then
            ns.Finder:FillRequestTooltip(tooltip, self.record, true) -- a click opens the Camp Builder
        elseif self.kind == "group" then
            tooltip:AddLine(self.record.name or L["Camps"], 1, 0.82, 0)
            tooltip:AddLine(format(L["Camps: %d"], self.record.count), 1, 1, 1)
            tooltip:AddLine(L["Click to see them on its map."], 0.7, 0.7, 0.7)
        else
            ns.MapBar:FillCampTooltip(tooltip, self.record, self.hazy)
            ns.LayerInvites:FillTooltip(tooltip, self.record)
        end
    end)
end

function PinMethods:OnMouseLeave()
    GameTooltip:Hide()
end

-- Meet-up pins open the Camp Builder when clicked; a camp pin on another layer
-- with someone there who takes layer invite requests asks them. Other camp
-- pins just show their tooltip; clicks go through to the map (on a continent's
-- or the world's map, the game's own click then opens the zone under it).
function PinMethods:OnClick(button)
    if button ~= "LeftButton" then return end
    if self.kind == "request" then
        ns.Finder:Open()
    elseif self.kind == "group" then
        WorldMapFrame:SetMapID(self.record.target)
    elseif self.kind == "camp" and self.askable then
        ns.LayerInvites:AskAt(self.record, self)
    end
end

-- A pin to show: a spare one, or a new one.
local function Acquire()
    local pin = table.remove(spare)
    if not pin then
        pin = CreateFrame("Frame", nil, overlay, TEMPLATE)
        for name, method in pairs(PinMethods) do pin[name] = method end
        pin:Setup()
        ns.Style:SkipControllerCursor(pin)
    end
    -- A spare pin may still be playing another camp's ripple.
    pin.ripple:Stop()
    pin:Show()
    return pin
end

-- Takes a pin off the map and keeps it for later.
local function Release(pin)
    if GameTooltip:IsOwned(pin) then GameTooltip:Hide() end
    pin.ripple:Stop()
    pin:Hide()
    pin.record, pin.kind = nil, nil
    spare[#spare + 1] = pin
end

-- A number the map gives, or nil if it hasn't one (yet).
local function MapNumber(method)
    local get = WorldMapFrame[method]
    if type(get) ~= "function" then return nil end
    local ok, value = pcall(get, WorldMapFrame)
    if ok and type(value) == "number" then return value end
end

-- The pins' scale, inside the canvas: the canvas is scaled up as you zoom in,
-- so this undoes that, then grows them a little with the zoom. Smaller on a
-- continent's or the world's map (laid.wide).
local function PinScale()
    local canvasScale = MapNumber("GetCanvasScale") or canvas:GetScale() or 1
    if canvasScale <= 0 then canvasScale = 1 end
    local zoom = math.min(1, math.max(0, MapNumber("GetCanvasZoomPercent") or 0))
    local global = MapNumber("GetGlobalPinScale") or 1
    return (SCALE_OUT + (SCALE_IN - SCALE_OUT) * zoom) * global / canvasScale * (laid.wide and WIDE_SCALE or 1)
end

-- Camps on a continent's or the world's map, grouped by zone. Each group is a
-- pin at the middle of its zone on the map (or, if the game can't say where
-- that is, at the middle of its camps), with how many camps it has; a click
-- opens the zone's map. Largest first.
function MapPins:Groups(camps, mapID)
    local groups, list = {}, {}
    for _, entry in ipairs(camps) do
        local target = ns.ZoneOf(entry.camp.mapID) or entry.camp.mapID
        if target then
            local group = groups[target]
            if not group then
                local name = C_Map.GetMapInfo(target)
                group = { id = "group:" .. target, target = target, name = name and name.name, count = 0, sx = 0, sy = 0 }
                groups[target] = group
                list[#list + 1] = group
            end
            group.count = group.count + 1
            group.sx, group.sy = group.sx + entry.x, group.sy + entry.y
        end
    end
    for _, group in ipairs(list) do
        local left, right, top, bottom
        if C_Map.GetMapRectOnMap then left, right, top, bottom = C_Map.GetMapRectOnMap(group.target, mapID) end
        if type(left) == "number" and type(right) == "number" and type(top) == "number" and type(bottom) == "number"
            and right > left and bottom > top then
            group.x, group.y = (left + right) / 2, (top + bottom) / 2
        else
            group.x, group.y = group.sx / group.count, group.sy / group.count
        end
    end
    table.sort(list, function(a, b) return a.count > b.count end)
    return list
end

-- Pins already on the map are moved and restyled where they are, so a hovered
-- pin keeps its tooltip and the selected camp's keeps rippling; only camps and
-- meet-ups that left or arrived are taken off or put on.
function MapPins:Refresh()
    if not overlay or not WorldMapFrame:IsShown() then return end
    local level = OverlayLevel()
    if overlay:GetFrameLevel() ~= level then overlay:SetFrameLevel(level) end
    local mapID = WorldMapFrame:GetMapID()
    laid.mapID, laid.width, laid.height = mapID, canvas:GetWidth(), canvas:GetHeight()
    laid.wide = ns.IsWideMap(mapID)
    laid.canvasScale, laid.scale = canvas:GetScale(), PinScale()

    -- In Standard mode, other players' camps are smoke (Camps:Smoky), all but
    -- the one you're at: that's looked up once for them all.
    local here = not ns.IsEnhanced() and (ns.Camps:NearPlayer(ns.Camps.MERGE_RADIUS) or false)
    laid.here = here and here.id or false

    local wanted, order = {}, {}
    local function Want(kind, record, x, y, rx, ry)
        local key = kind .. ":" .. tostring(record.id)
        if wanted[key] then return end
        wanted[key] = { record, x, y, kind, rx, ry }
        order[#order + 1] = key
    end
    local camps, total, hidden
    if mapID then
        -- Show camps off hides every camp; Camp Builder meet-ups still show
        -- (in Enhanced mode only: Standard has no Camp Builder).
        -- Camps show on any zone's map (and continents' and the world's, with
        -- the option on), nearest first up to a limit, and only matches while
        -- Find a camp is open (Camps:ShownOnMap).
        if ns.db.mapPins then camps, total, hidden = ns.Camps:ShownOnMap(mapID) end
        -- Grouped on a continent's or the world's map: one pin per zone.
        local grouped = laid.wide and ns.WideMapStyle() == "grouped"
        if grouped then
            for _, group in ipairs(MapPins:Groups(camps or {}, mapID)) do Want("group", group, group.x, group.y) end
        end
        for _, entry in ipairs(not grouped and camps or {}) do
            if not ns.Camps:Smoky(entry.camp, here) then
                Want("camp", entry.camp, entry.x, entry.y)
            elseif laid.wide then
                -- Zoomed out, the smoke keeps its middle from the camp's own
                -- zone map; if that can't be placed, nothing is (never the fire).
                local x, y, rx, ry = ns.Camps:SmokeOnWideMap(entry.camp, mapID)
                if x then Want("camp", entry.camp, x, y, rx, ry) end
            else
                Want("camp", entry.camp, ns.Camps:SmokeOnMap(entry.camp, mapID, entry.x, entry.y))
            end
        end
        if ns.IsEnhanced() then
            for _, entry in ipairs(ns.Requests:OnMap(mapID)) do Want("request", entry.request, entry.x, entry.y) end
        end
        -- Ashes and popular campsites, with Show camps on, and not while Find
        -- a camp is looking for matches (they never match).
        if ns.db.mapPins and not ns.Search:IsActive() then
            for _, entry in ipairs(ns.Campsites:OnMap(mapID)) do Want(entry.kind, entry.record, entry.x, entry.y) end
        end
    end
    for key, pin in pairs(active) do
        if not wanted[key] then
            active[key] = nil
            if MapPins.pins[pin.record.id] == pin then MapPins.pins[pin.record.id] = nil end
            Release(pin)
        end
    end
    for _, key in ipairs(order) do
        local pin = active[key]
        if not pin then
            pin = Acquire()
            active[key] = pin
        end
        pin:Update(unpack(wanted[key]))
    end
    -- The camp bar counts the same camps (worked out once).
    ns.MapBar:Refresh(camps, total, hidden)
end

-- Whether the open map needs its pins redrawn though no camp changed (Core's
-- tick, once a second): in Standard mode, when you've come to a camp or left
-- it, as the camp you're at shows exactly, not as smoke.
function MapPins:NeedsRefresh()
    if ns.IsEnhanced() then return false end
    local here = ns.Camps:NearPlayer(ns.Camps.MERGE_RADIUS)
    return (here and here.id or false) ~= laid.here
end

-- Every frame while the map is open (the overlay's OnUpdate): a new map or
-- canvas size lays the pins out again; a zoom just rescales them.
-- The map's first frame open (a gap since the last frame: it was closed) lays
-- the pins out and refreshes the camp bar: nothing of Happy Camper's runs as
-- the map opens (MapBar.lua says why), only here, a frame later.
local OPENED_GAP = 0.25 -- seconds without a frame: the map was closed
-- Core's tick, while the map is closed: its next frame open is its first.
function MapPins:Closed() laid.seen = nil end
local function Watch()
    local now = GetTime()
    local opened = not laid.seen or now - laid.seen > OPENED_GAP
    laid.seen = now
    ns.MapBar:Watch(opened)
    if opened or WorldMapFrame:GetMapID() ~= laid.mapID or canvas:GetWidth() ~= laid.width
        or canvas:GetHeight() ~= laid.height then
        return MapPins:Refresh()
    end
    local canvasScale = canvas:GetScale()
    if canvasScale == laid.canvasScale then return end
    laid.canvasScale = canvasScale
    local scale = PinScale()
    if scale == laid.scale then return end
    laid.scale = scale
    for _, pin in pairs(active) do Place(pin) end
end

function MapPins:Init()
    if not WorldMapFrame then C_AddOns.LoadAddOn("Blizzard_WorldMap") end
    canvas = WorldMapFrame and WorldMapFrame.GetCanvas and WorldMapFrame:GetCanvas()
    if not canvas then
        ns.Print(L["The world map isn't available, so camps won't show on it."])
        return false
    end
    -- On the canvas, so it pans and zooms with the map and shows only with it.
    -- It takes no mouse itself: only its pins do.
    overlay = CreateFrame("Frame", "HappyCamperMapOverlay", canvas)
    overlay:SetAllPoints(canvas)
    overlay:SetFrameLevel(OverlayLevel())
    overlay:SetScript("OnUpdate", Watch)
    -- Controller cursors stay off the pins (Style:SkipControllerCursor).
    ns.Style:SkipControllerCursor(overlay)
    self.overlay = overlay
    return true
end

-- The Show camps toggle (map bar button and Options): all camps on the map, or none.
function ns.SetShowCamps(on)
    ns.db.mapPins = on and true or false
    MapPins:Refresh()
    ns.MapBar:Refresh()
    ns.Options:Sync()
end

-- How often the selected camp's pin ripples (MapPins:Ripple).
local RIPPLE_EVERY = 2
local lastRipple = -RIPPLE_EVERY

-- record is anything with mapID, x and y (a camp or a request).
function ns.SetWaypoint(record, label)
    if not C_Map.CanSetUserWaypointOnMap(record.mapID) then
        ns.Print(L["Waypoints can't be placed on this map."])
        return
    end
    C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(record.mapID, record.x, record.y))
    C_SuperTrack.SetSuperTrackedUserWaypoint(true)
    ns.Print(L["Waypoint set to %s."], label)
end

-- Selects a camp to find on the map (from the on-screen panel), or unselects
-- it if it's already selected. No waypoint: its pin just ripples.
function ns.SelectCamp(camp)
    ns.state.selectedCampID = ns.state.selectedCampID ~= camp.id and camp.id or nil
    lastRipple = -RIPPLE_EVERY
    ns.OnCampsChanged()
end

-- The selected camp's pin ripples once every RIPPLE_EVERY seconds while the
-- map is open (the addon's tick calls this), and straight away when it's shown.
-- A camp shown as smoke ripples from the smoke's middle, not its fire.
function MapPins:Ripple()
    local pin = self.pins[ns.state.selectedCampID or ""]
    if not pin or pin.kind ~= "camp" or not pin:IsVisible() then return end
    if GetTime() - lastRipple < RIPPLE_EVERY then return end
    lastRipple = GetTime()
    pin.ripple:Stop()
    pin.ripple:Play()
end
