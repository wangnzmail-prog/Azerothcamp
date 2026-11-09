-- Happy Camper. Copyright (c) 2026 Torridon. All rights reserved; see LICENSE.
local _, ns = ...
local L = ns.L

-- Cinematic camp camera: after you sit down at a camp, hide the interface and
-- player names, zoom out and slowly pan around the fire. Moving, combat, a key press or a click
-- brings everything back. Purely cosmetic: it never moves your character.

local Cinematic = {}
ns.Cinematic = Cinematic

-- The game's name settings turned off while it plays (cinematicHideNames):
-- your own name and other players'. What they were is kept in the
-- character's saved data until put back, so a reload or a crash mid-way
-- still restores them at the next login.
local NAME_CVARS = { "UnitNameOwn", "UnitNameFriendlyPlayerName", "UnitNameEnemyPlayerName" }

local function SetCVarSafely(name, value)
    local set = C_CVar and C_CVar.SetCVar or SetCVar
    return set ~= nil and pcall(set, name, value) == true
end

local function HideNames()
    if ns.charDB.cinematicNames then return end -- still hidden from before
    local saved = {}
    for _, name in ipairs(NAME_CVARS) do
        local value = C_CVar and C_CVar.GetCVar(name)
        if value ~= nil and value ~= "0" and SetCVarSafely(name, "0") then saved[name] = value end
    end
    if next(saved) then ns.charDB.cinematicNames = saved end
end

-- Puts the names back as they were. Anything the game won't change right now
-- (in a fight) waits for the next try: when the fight ends, or at login.
function Cinematic:RestoreNames()
    local saved = ns.charDB and ns.charDB.cinematicNames
    if type(saved) ~= "table" then return end
    for name, value in pairs(saved) do
        if SetCVarSafely(name, value) then saved[name] = nil end
    end
    if not next(saved) then ns.charDB.cinematicNames = nil end
end

local SETTLE_TIME = 30 -- seconds sitting still at a camp before it starts
local ZOOM_OUT = 8
local HINT_TIME = 4

local active = false
local hidUI = false -- the interface's alpha before it was faded out, or false
local zoomBefore
local lastMoved = 0
local catcher

-- Whether keys go on to the game's bindings as well. The game blocks setting
-- it in a fight (an error for the addon), so it's left as it is then.
local function Propagate(on)
    if InCombatLockdown() or ns.InCombat() then return end
    catcher:SetPropagateKeyboardInput(on)
end

local function CreateCatcher()
    -- Parented to WorldFrame because UIParent is hidden while this is showing.
    catcher = CreateFrame("Frame", nil, WorldFrame)
    catcher:SetAllPoints()
    catcher:SetFrameStrata("FULLSCREEN_DIALOG")
    catcher:EnableMouse(true)
    catcher:EnableKeyboard(true)
    Propagate(true)
    catcher:Hide()

    catcher:SetScript("OnKeyDown", function(_, key)
        -- Escape only leaves cinematic mode instead of also opening the game menu.
        Propagate(key ~= "ESCAPE")
        Cinematic:Stop()
    end)
    catcher:SetScript("OnMouseDown", function() Cinematic:Stop() end)

    catcher.hint = catcher:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    catcher.hint:SetPoint("BOTTOM", 0, 80)
    catcher.hint:SetText(L["Resting by the fire. Move, click or press any key to return."])
end

function Cinematic:IsActive()
    return active
end

function Cinematic:CanStart()
    return not active and not ns.InCombat() and not IsPlayerMoving()
        and not IsMounted() and not IsFlying("player") and not UnitIsDeadOrGhost("player")
end

function Cinematic:Start()
    if not self:CanStart() then return end
    if not catcher then CreateCatcher() end
    active = true

    local db = ns.db
    zoomBefore = GetCameraZoom()
    if db.cinematicZoom then CameraZoomOut(ZOOM_OUT) end
    if db.cinematicPan then MoveViewLeftStart(db.cinematicSpeed) end
    -- Faded out, not hidden: hiding UIParent would run the OnHide (and then
    -- OnShow) of every window on it as Happy Camper's own code, tainting the
    -- game's (the map's, the action bars'...), which then has protected calls
    -- blocked. The catcher above it takes every click and key meanwhile.
    if db.cinematicHideUI and UIParent:IsShown() and not hidUI then
        hidUI = UIParent:GetAlpha() or 1
        UIParent:SetAlpha(0)
    end
    if db.cinematicHideNames then HideNames() end

    Propagate(true)
    catcher:Show()
    catcher.hint:Show()
    C_Timer.After(HINT_TIME, function()
        if catcher then catcher.hint:Hide() end
    end)
end

function Cinematic:Stop()
    if not active then return end
    active = false

    MoveViewLeftStop()
    if zoomBefore then
        local extra = GetCameraZoom() - zoomBefore
        if extra > 0 then CameraZoomIn(extra) end
        zoomBefore = nil
    end
    if hidUI then
        UIParent:SetAlpha(hidUI)
        hidUI = false
    end
    self:RestoreNames()
    catcher:Hide()
end

function Cinematic:Toggle()
    if active then self:Stop() else self:Start() end
end

-- Called whenever you might have settled at a camp. Starts only if you're
-- still standing there after SETTLE_TIME.
function Cinematic:Arm()
    if not ns.db.cinematic or active then return end
    local armedAt = GetTime()
    C_Timer.After(SETTLE_TIME, function()
        if ns.db.cinematic and lastMoved < armedAt and ns.IsRestingAtCamp() then
            Cinematic:Start()
        end
    end)
end

function Cinematic:OnStartedMoving()
    lastMoved = GetTime()
    self:Stop()
end
