local addonName, ns = ...

---------------------------------------------------------------------------
-- Tent pins for camps on the world map and minimap (camps from CampNet.lua:
-- the one you're at, and those other kit users share on your layer).
-- On a zone's map: the camps in that zone. Zoomed out to a continent or the
-- world: only the camps in the zone you're in, so the big maps stay clear.
-- The world map's filter menu (the magnifying glass) turns them on and off.
-- Mouse over a pin for the campfire, what's at it and how long it has left.
---------------------------------------------------------------------------

local Core = ns.Core
local U = Core.U
local MEDIA = ns.MEDIA

local Map = {}
ns.CampMap = Map

local TEMPLATE = "CampingKitMapPinTemplate"
local MINI_SIZE = 14
local AREA_YARDS = 50 -- a camp's dashed ring on the minimap: how far it reaches

local function Settings()
    local kit = ns.kit
    return kit and kit.db or {}
end

---------------------------------------------------------------------------
-- The tooltip (both maps)
---------------------------------------------------------------------------

local VIOLET = { 0.72, 0.45, 1 } -- a purple fire (Violet Flames)

function Map.Tooltip(f, owner)
    local Camp, Net = ns.Camp, ns.CampNet
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    local fire = Camp.FireByTier(f.tier or 0)
    GameTooltip:AddLine(Camp.FireName(fire))
    if f.violet then GameTooltip:AddLine("Violet Flames: camp benefits last 2 hours", VIOLET[1], VIOLET[2], VIOLET[3]) end
    -- A kit camp nobody's listed yet can borrow what Happy Camper or chat says is there.
    local spells = (#f.spells == 0 and f.report and f.report.spells) or f.spells
    if fire then
        GameTooltip:AddLine(("%d of %d slots known%s"):format(#spells, fire.slots, f.full and ", full" or ""), 1, 1, 1)
    elseif f.full then
        GameTooltip:AddLine("Full", 1, 1, 1)
    end
    for _, spell in ipairs(spells) do
        local o = Camp.ObjectBySpell(spell)
        if o then
            local icon = (o.item and U.ItemIcon(o.item)) or U.SpellIcon(o.spell) or 134400
            GameTooltip:AddDoubleLine(("|T%s:14:14|t %s"):format(icon, Camp.ObjName(o)), Camp.Effect(o) or "",
                1, 1, 1, 0.62, 0.62, 0.62)
        end
    end
    if #spells == 0 then GameTooltip:AddLine("Nothing seen at it yet.", 0.62, 0.62, 0.62) end
    if f.wants and #f.wants > 0 then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Looking for:", 1, 0.82, 0)
        for _, spell in ipairs(f.wants) do
            local o = Camp.ObjectBySpell(spell)
            if o then
                local icon = (o.item and U.ItemIcon(o.item)) or U.SpellIcon(o.spell) or 134400
                local mine = Camp.CanPlace(o)
                GameTooltip:AddDoubleLine(("|T%s:14:14|t %s"):format(icon, Camp.ObjName(o)), mine and "you can place this" or (Camp.Effect(o) or ""),
                    1, 1, 1, mine and 0.25 or 0.62, mine and 0.82 or 0.62, mine and 0.29 or 0.62)
            end
        end
    end
    local left = Net.Left(f)
    if left and (not f.outside or f.owned) then GameTooltip:AddLine(("Burns for about %s more"):format(U.FormatLeft(left)), 1, 0.7, 0.25) end
    if f.mine then
        GameTooltip:AddLine("You're at this camp.", 0.25, 0.82, 0.29)
    elseif f.yours then
        GameTooltip:AddLine("A camp you were at.", 0.62, 0.62, 0.62)
    elseif f.chat then
        GameTooltip:AddLine("Posted in chat by " .. f.from, 0.62, 0.62, 0.62)
    elseif f.outside then
        GameTooltip:AddLine(("Reported by %s through %s"):format(f.from, f.source), 0.62, 0.62, 0.62)
    elseif f.from then
        GameTooltip:AddLine("Shared by " .. f.from, 0.62, 0.62, 0.62)
    end
    if not Net.Known(f) then GameTooltip:AddLine("Somewhere around here: the exact spot isn't known.", 0.62, 0.62, 0.62) end
    if f.layerUnknown then GameTooltip:AddLine("May be on another layer.", 0.62, 0.62, 0.62) end
    GameTooltip:Show()
end

---------------------------------------------------------------------------
-- World map: a data provider with our own pin template (CampMap.xml)
---------------------------------------------------------------------------

CampingKitMapPinMixin = CreateFromMixins and MapCanvasPinMixin and CreateFromMixins(MapCanvasPinMixin) or {}

function CampingKitMapPinMixin:OnLoad()
    if self.UseFrameLevelType then self:UseFrameLevelType("PIN_FRAME_LEVEL_AREA_POI") end
    if self.SetScalingLimits then self:SetScalingLimits(1, 1.0, 1.25) end
    if self.Glow then self.Glow:SetVertexColor(1, 0.7, 0.25) end
end

-- The first thing a camp is looking for that you could put down, if any.
function Map.YouCanHelp(f)
    for _, spell in ipairs(f.wants or {}) do
        local o = ns.Camp.ObjectBySpell(spell)
        if o and ns.Camp.CanPlace(o) then return o end
    end
end

-- A purple fire's pin is violet.
local function Tint(icon, area, f)
    if f.violet then
        icon:SetVertexColor(VIOLET[1], VIOLET[2], VIOLET[3])
        area:SetVertexColor(VIOLET[1], VIOLET[2], VIOLET[3])
    else
        icon:SetVertexColor(1, 1, 1)
        area:SetVertexColor(1, 0.7, 0.25)
    end
end

-- A camp looking for something you can place: its icon in the pin's corner,
-- and a glow.
local function Badge(pin, f)
    local o = not (f.mine or f.yours) and Map.YouCanHelp(f)
    if o then
        pin.Badge:SetTexture((o.item and U.ItemIcon(o.item)) or U.SpellIcon(o.spell) or 134400)
        pin.Badge:Show()
        pin.Glow:Show()
    else
        pin.Badge:Hide()
        pin.Glow:Hide()
    end
end
Map.Badge = Badge

function CampingKitMapPinMixin:OnAcquired(fire, x, y)
    self.fire = fire
    self:SetPosition(x, y)
    local known = ns.CampNet.Known(fire)
    self.Icon:SetShown(known)
    self.Area:SetShown(not known)
    self.Icon:SetDesaturated(fire.faded and true or false)
    self.Icon:SetAlpha(fire.faded and 0.55 or (fire.mine and 1 or 0.9))
    self.Area:SetAlpha(fire.faded and 0.55 or 0.9)
    Tint(self.Icon, self.Area, fire)
    Badge(self, fire)
end

function CampingKitMapPinMixin:OnMouseEnter()
    if self.fire then Map.Tooltip(self.fire, self) end
end

function CampingKitMapPinMixin:OnMouseLeave()
    GameTooltip:Hide()
end

-- Where a camp sits on a given map (0-1), or nil if it's not on that map.
local function OnMap(f, mapID)
    local wx, wy = ns.CampNet.Shown(f)
    if not (C_Map and C_Map.GetMapPosFromWorldPos and CreateVector2D) then
        if f.map == mapID then return f.mx, f.my end
        return nil
    end
    local ok, _, pos = pcall(C_Map.GetMapPosFromWorldPos, f.cont, CreateVector2D(wx, wy), mapID)
    if not ok or not pos then
        if f.map == mapID then return f.mx, f.my end
        return nil
    end
    local x, y = pos:GetXY()
    if x < 0 or x > 1 or y < 0 or y > 1 then return nil end
    return x, y
end

-- The zone a map belongs to (itself, or the zone over a cave or town map);
-- nil for a continent or bigger.
local zoneOf = {}
local function ZoneOf(mapID)
    if not mapID then return nil end
    if zoneOf[mapID] ~= nil then return zoneOf[mapID] or nil end
    local id, zone = mapID, false
    for _ = 1, 8 do
        local info = C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(id)
        if not info or not Enum or not Enum.UIMapType then break end
        if info.mapType == Enum.UIMapType.Zone then zone = id break end
        if info.mapType <= Enum.UIMapType.Continent or not info.parentMapID or info.parentMapID == 0 then break end
        id = info.parentMapID
    end
    zoneOf[mapID] = zone
    return zone or nil
end
Map.ZoneOf = ZoneOf

-- Showing a continent or the world rather than a zone?
local function ZoomedOut(mapID)
    local info = C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(mapID)
    return info and Enum and Enum.UIMapType and info.mapType <= Enum.UIMapType.Continent or false
end

local provider
local function MakeProvider()
    if provider or not (WorldMapFrame and WorldMapFrame.AddDataProvider and MapCanvasDataProviderMixin) then return end
    provider = CreateFromMixins(MapCanvasDataProviderMixin)
    function provider:RemoveAllData()
        self:GetMap():RemoveAllPinsByTemplate(TEMPLATE)
    end
    function provider:RefreshAllData()
        self:RemoveAllData()
        if Settings().campWorldMap == false then return end
        local map = self:GetMap()
        local mapID = map:GetMapID()
        if not mapID then return end
        local onlyZone = ZoomedOut(mapID) and ZoneOf(C_Map.GetBestMapForUnit("player"))
        for _, f in ipairs(ns.CampNet.Visible()) do
            if not onlyZone or ZoneOf(f.map) == onlyZone then
                local x, y = OnMap(f, mapID)
                if x then map:AcquirePin(TEMPLATE, f, x, y) end
            end
        end
    end
    WorldMapFrame:AddDataProvider(provider)
end

---------------------------------------------------------------------------
-- Minimap: pins placed by distance from you, turned with the minimap
---------------------------------------------------------------------------

-- Minimap diameter in yards at each zoom (as other map addons use).
local OUTDOOR = { [0] = 466 + 2 / 3, 400, 333 + 1 / 3, 266 + 2 / 3, 200, 133 + 1 / 3 }
local INDOOR = { [0] = 300, 240, 180, 120, 80, 50 }

local miniPins = {}

local function MiniPin(i)
    local p = miniPins[i]
    if p then return p end
    p = CreateFrame("Frame", nil, Minimap)
    p:SetSize(MINI_SIZE, MINI_SIZE)
    p:SetFrameLevel(Minimap:GetFrameLevel() + 5)
    p.icon = p:CreateTexture(nil, "OVERLAY")
    p.icon:SetAllPoints()
    p.icon:SetTexture(MEDIA .. "tent_closed_32", nil, nil, "LINEAR")
    -- A camp whose exact spot isn't known: a dashed ring, about the fire's reach.
    p.area = p:CreateTexture(nil, "OVERLAY")
    p.area:SetPoint("CENTER")
    p.area:SetTexture(MEDIA .. "ring_dashed_64", nil, nil, "LINEAR")
    p.area:SetVertexColor(1, 0.7, 0.25)
    p.Glow = p:CreateTexture(nil, "BACKGROUND")
    p.Glow:SetPoint("CENTER")
    p.Glow:SetSize(MINI_SIZE * 1.9, MINI_SIZE * 1.9)
    p.Glow:SetTexture(MEDIA .. "glow_ring")
    p.Glow:SetBlendMode("ADD")
    p.Glow:SetVertexColor(1, 0.7, 0.25)
    p.Glow:Hide()
    p.Badge = p:CreateTexture(nil, "OVERLAY", nil, 2)
    p.Badge:SetSize(9, 9)
    p.Badge:SetPoint("CENTER", p, "BOTTOMRIGHT", -1, 1)
    p.Badge:Hide()
    p:EnableMouse(true)
    p:SetScript("OnEnter", function(self) if self.fire then Map.Tooltip(self.fire, self) end end)
    p:SetScript("OnLeave", function() GameTooltip:Hide() end)
    p:Hide()
    miniPins[i] = p
    return p
end

-- One map's east and south, as unit vectors in world coordinates (cached).
local axes = {}
local function Axes(mapID)
    local a = axes[mapID]
    if a ~= nil then return a or nil end
    a = false
    if C_Map and C_Map.GetWorldPosFromMapPos and CreateVector2D then
        local ok0, c0, p0 = pcall(C_Map.GetWorldPosFromMapPos, mapID, CreateVector2D(0, 0))
        local ok1, c1, p1 = pcall(C_Map.GetWorldPosFromMapPos, mapID, CreateVector2D(1, 0))
        local ok2, c2, p2 = pcall(C_Map.GetWorldPosFromMapPos, mapID, CreateVector2D(0, 1))
        if ok0 and ok1 and ok2 and p0 and p1 and p2 then
            local x0, y0 = p0:GetXY()
            local ex, ey = p1:GetXY()
            local sx, sy = p2:GetXY()
            ex, ey, sx, sy = ex - x0, ey - y0, sx - x0, sy - y0
            local el, sl = math.sqrt(ex * ex + ey * ey), math.sqrt(sx * sx + sy * sy)
            if el > 0 and sl > 0 then a = { ex / el, ey / el, sx / sl, sy / sl } end
        end
    end
    axes[mapID] = a
    return a or nil
end

local function PlaceMinimap()
    local list = Settings().campMinimap ~= false and ns.CampNet.Visible() or {}
    local here = #list > 0 and ns.CampNet.Here() or nil
    local ax = here and Axes(here.map)
    local n = 0
    if here and ax then
        local zoom = Minimap:GetZoom() or 0
        local yards = ((IsIndoors and IsIndoors()) and INDOOR or OUTDOOR)[zoom] or 466
        local radius = Minimap:GetWidth() / 2
        local scale = Minimap:GetWidth() / yards
        local rotate = GetCVar and GetCVar("rotateMinimap") == "1"
        local facing = rotate and GetPlayerFacing and GetPlayerFacing() or nil
        if facing and U.Sealed(facing) then facing = nil end
        for _, f in ipairs(list) do
            if f.cont == here.cont then
                local wx, wy = ns.CampNet.Shown(f)
                local dx, dy = wx - here.wx, wy - here.wy
                local east = dx * ax[1] + dy * ax[2]
                local north = -(dx * ax[3] + dy * ax[4])
                if facing then
                    local c, s = math.cos(-facing), math.sin(-facing)
                    east, north = east * c - north * s, east * s + north * c
                end
                local px, py = east * scale, north * scale
                local d = math.sqrt(px * px + py * py)
                if d <= radius - MINI_SIZE / 2 then
                    n = n + 1
                    local p = MiniPin(n)
                    p.fire = f
                    local known = ns.CampNet.Known(f)
                    p.icon:SetShown(known)
                    p.area:SetShown(not known)
                    p.area:SetSize(math.max(MINI_SIZE, AREA_YARDS * 2 * scale), math.max(MINI_SIZE, AREA_YARDS * 2 * scale))
                    p.area:SetAlpha(f.faded and 0.55 or 0.9)
                    p.icon:SetDesaturated(f.faded and true or false)
                    p.icon:SetAlpha(f.faded and 0.55 or 1)
                    Tint(p.icon, p.area, f)
                    Badge(p, f)
                    p:ClearAllPoints()
                    p:SetPoint("CENTER", Minimap, "CENTER", px, py)
                    p:Show()
                end
            end
        end
    end
    for i = n + 1, #miniPins do
        miniPins[i]:Hide()
        miniPins[i].fire = nil
    end
end

local ticker = CreateFrame("Frame")
local acc = 0
ticker:SetScript("OnUpdate", function(_, elapsed)
    acc = acc + elapsed
    if acc < 0.2 then return end
    acc = 0
    if Minimap and Minimap:IsVisible() then PlaceMinimap() end
end)

---------------------------------------------------------------------------

-- The camps changed (or a setting): redraw the world map's pins if it's open.
function Map.Refresh()
    MakeProvider()
    if provider and WorldMapFrame:IsShown() then provider:RefreshAllData() end
    if Minimap then PlaceMinimap() end
end

-- A "Camps" check in the world map's filter menu (the magnifying glass) and
-- in the minimap's tracking menu: the same settings as "Camps on the world
-- map" and "Camps on the minimap" in the kit's settings.
local menuHooked = false
local function HookFilterMenu()
    if menuHooked or not (Menu and Menu.ModifyMenu) then return end
    menuHooked = true
    local function Add(tag, key)
        Menu.ModifyMenu(tag, function(_, root)
            root:CreateDivider()
            root:CreateTitle("Camping Kit")
            root:CreateCheckbox("Camps", function() return Settings()[key] ~= false end, function()
                local kit = ns.kit
                if not kit then return end
                kit.db[key] = kit.db[key] == false
                Map.Refresh()
            end)
        end)
    end
    Add("MENU_WORLD_MAP_TRACKING", "campWorldMap")
    Add("MENU_MINIMAP_TRACKING", "campMinimap")
end

ticker:RegisterEvent("PLAYER_LOGIN")
ticker:RegisterEvent("ZONE_CHANGED_NEW_AREA")
ticker:SetScript("OnEvent", function(_, event)
    MakeProvider()
    HookFilterMenu()
    -- Zoomed out, the camps shown follow the zone you're in.
    if event == "ZONE_CHANGED_NEW_AREA" and provider and WorldMapFrame:IsShown() then provider:RefreshAllData() end
end)
