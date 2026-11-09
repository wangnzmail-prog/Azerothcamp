local addonName, ns = ...

---------------------------------------------------------------------------
-- Sharing camps with other Camping Kit users.
--
-- While you're at a camp, the kit tells other kit users where it is and
-- what's at it, over a hidden chat channel of its own (addon messages only,
-- nothing in your chat). Everyone keeps the camps they hear about until the
-- fire burns out, and shows them as tent pins on the world map and minimap
-- (CampMap.lua).
--
-- Layers: players on another layer can't see your fire, so every camp is
-- tagged with the layer it's on, and only camps on your own layer show. The
-- game has no "which layer" call; like other Forever layer addons, the kit
-- reads it from the GUIDs of NPCs you see (nameplates, target, mouseover).
-- Until it has seen one since you last changed zone or group, your layer is
-- unknown: nothing is shared and only camps you're at show.
--
-- Where a camp is: the fire itself, not where someone stood. Campfire Nearby
-- reaches about RANGE yards and the game says nothing about which fire it
-- comes from, so a camp's spot is worked out:
--   * You built it: exactly where you cast it.
--   * Otherwise: the average of where you stood while at it (people stand
--     and sit by the fire), counting spots you stood still at; your arrival
--     point, on the range's edge, only until there's better.
--   * Every kit user's estimate for a camp is averaged; a built one wins.
--   * The game says when you're next to a cooking fire (about 15 yards), so a
--     kit user at a camp who's that close knows the spot (Net.CheckCooking).
-- Only a spot someone actually knows gets a tent pin: built, found by cooking
-- range, announced, or reported by whoever lit the fire through Happy Camper
-- (Net.Known). The rest
-- show as a dashed ring, "somewhere around here", that keeps improving but only
-- moves when the estimate has really changed (Net.Shown), and your own camp
-- shows nothing until it's settled, so no pin ever trails you around.
-- The aura is sticky: you keep your first fire's until you walk out of its
-- range, then pick up the next one's a second later. A swap like that marks
-- the two as different fires, never shown as one pin.
---------------------------------------------------------------------------

local Core = ns.Core
local U = Core.U

local Net = {}
ns.CampNet = Net

local PREFIX = "CampingKit"
local CHANNEL = "CampingKitNet"
local VERSION = 2
local FIRE_LIFE = 600     -- seconds a campfire burns
local STILL_THERE = 90    -- a camp someone's still at lives at least this long past their last word
local HEARTBEAT = 60      -- while at a camp, say so this often
local RANGE = 100         -- yards Campfire Nearby reaches from its fire (about; measured on the beta)
local SAME_FIRE = 50      -- yards: camps whose fires are this close (same layer and continent) are one camp
local SAMPLE = 5          -- seconds between position samples while at a camp
local REJOIN = 60        -- seconds: back in range of the camp you just left this soon, it's the same camp
local SWAP = 3            -- seconds: losing one fire's aura and getting another's this fast is a swap

Net.fires = {}            -- every camp known: see Record below

---------------------------------------------------------------------------
-- Your layer
---------------------------------------------------------------------------

local layer, layerContinent, layerGUID

local function Continent()
    local _, _, _, instance = UnitPosition("player")
    if U.Sealed(instance) then return nil end
    return instance
end

-- A creature's GUID: Creature-0-server-instance-zoneUID-npcID-spawnUID. The
-- zoneUID part differs between layers of the same zone.
local function LayerFromGUID(guid)
    if not guid or U.Sealed(guid) or type(guid) ~= "string" then return nil end
    local kind, _, _, _, zone = strsplit("-", guid)
    if kind ~= "Creature" and kind ~= "Vehicle" then return nil end
    if not zone or zone == "" or zone == "0" then return nil end
    return zone
end

local function SeeUnit(unit)
    if not UnitExists(unit) or UnitIsPlayer(unit) then return end
    local ok, guid = pcall(UnitGUID, unit)
    if not ok then return end
    local l = LayerFromGUID(guid)
    if not l then return end
    local cont = Continent()
    if l ~= layer or cont ~= layerContinent then
        layer, layerContinent, layerGUID = l, cont, guid
        if ns.CampMap then ns.CampMap.Refresh() end
        Net.CampChanged()
    end
end

local function ForgetLayer()
    if layer then
        layer, layerContinent, layerGUID = nil, nil, nil
        if ns.CampMap then ns.CampMap.Refresh() end
    end
end

function Net.Layer() return layer end

function Net.LayerInfo() return layer, layerContinent, layerGUID end

---------------------------------------------------------------------------
-- Where you are, in world yards (to compare camps) and on the map
---------------------------------------------------------------------------

function Net.Here()
    if not (C_Map and C_Map.GetBestMapForUnit and C_Map.GetPlayerMapPosition and C_Map.GetWorldPosFromMapPos) then return nil end
    local map = C_Map.GetBestMapForUnit("player")
    if not map or U.Sealed(map) then return nil end
    local pos = C_Map.GetPlayerMapPosition(map, "player")
    if not pos then return nil end
    local ok, cont, world = pcall(C_Map.GetWorldPosFromMapPos, map, pos)
    if not ok or not cont or not world then return nil end
    local wx, wy = world:GetXY()
    local mx, my = pos:GetXY()
    return { cont = cont, wx = wx, wy = wy, map = map, mx = mx, my = my }
end

local function Dist(a, b)
    local dx, dy = a.wx - b.wx, a.wy - b.wy
    return math.sqrt(dx * dx + dy * dy)
end

---------------------------------------------------------------------------
-- Camps: one record per fire
--   { layer, cont, wx, wy, map, mx, my, tier, full, spells = { spellID, ... },
--     wants = { spellID, ... } (what it's looking for), wantsAt,
--     started (server time or nil), first, last (server times), from, mine }
---------------------------------------------------------------------------

local function Now() return GetServerTime and GetServerTime() or time() end

function Net.Alive(f, now)
    now = now or Now()
    local deadline = (f.started or f.first) + FIRE_LIFE
    return now < deadline or now < f.last + STILL_THERE
end

-- Seconds of burn left, if it can be told.
function Net.Left(f)
    local left = (f.started or f.first) + FIRE_LIFE - Now()
    return left > 0 and left or nil
end

-- Two camps known to be different fires (your aura swapped between them, or
-- you built one while at the other): never merged, whatever the distance.
local function Distinct(a, b) return a.distinct[b] or b.distinct[a] end
local function MarkDistinct(a, b)
    if a and b and a ~= b then a.distinct[b], b.distinct[a] = true, true end
end
local function NewRecord(f)
    f.est = f.est or {}
    f.distinct = setmetatable({}, { __mode = "k" })
    f.spells, f.wants = f.spells or {}, f.wants or {}
    return f
end

-- The fire's spot from everyone's estimates: a built one's exact spot, else
-- an announced (pinned) spot, else the average weighted by how many samples
-- each took. The map spot follows.
local function SetCentre(f)
    local sx, sy, n, exact, cooked, pinned = 0, 0, 0, nil, nil, nil
    for _, e in pairs(f.est) do
        if e.exact then exact = e elseif e.cooked then cooked = e elseif e.pinned then pinned = e end
        local w = math.max(1, e.n or 1)
        sx, sy, n = sx + e.wx * w, sy + e.wy * w, n + w
    end
    local fixed = exact or cooked or pinned
    if fixed then f.wx, f.wy = fixed.wx, fixed.wy
    elseif n > 0 then f.wx, f.wy = sx / n, sy / n end
    f.exact, f.cooked = exact and true or false, (not exact and cooked) and true or false
    f.pinned, f.n = (not exact and not cooked and pinned) and true or false, n
    if C_Map and C_Map.GetMapPosFromWorldPos and CreateVector2D and f.map then
        local ok, _, pos = pcall(C_Map.GetMapPosFromWorldPos, f.cont, CreateVector2D(f.wx, f.wy), f.map)
        if ok and pos then f.mx, f.my = pos:GetXY() end
    end
end

-- The nearest camp whose fire is within SAME_FIRE of this one.
local function Find(r)
    local best, bd
    for _, f in ipairs(Net.fires) do
        if f ~= r and f.layer == r.layer and f.cont == r.cont and not (r.distinct and Distinct(f, r)) then
            local d = Dist(f, r)
            if d <= SAME_FIRE and (not bd or d < bd) then best, bd = f, d end
        end
    end
    return best
end

local function Remove(f)
    for i, g in ipairs(Net.fires) do
        if g == f then table.remove(Net.fires, i) return end
    end
end

-- Two records turned out to be one fire: keep one with what both knew.
local function Absorb(keep, gone)
    for who, e in pairs(gone.est) do
        if not keep.est[who] then keep.est[who] = e end
    end
    keep.tier = math.max(keep.tier or 0, gone.tier or 0)
    if not keep.mine and (gone.mine or #gone.spells > #keep.spells) then keep.spells, keep.full = gone.spells, gone.full end
    if (gone.wantsAt or 0) > (keep.wantsAt or 0) then keep.wants, keep.wantsAt = gone.wants, gone.wantsAt end
    if gone.started and (not keep.started or gone.started < keep.started) then keep.started = gone.started end
    keep.first = math.min(keep.first or gone.first, gone.first or keep.first)
    if (gone.last or 0) > (keep.last or 0) then keep.last, keep.from = gone.last, gone.from end
    keep.yours = keep.yours or gone.yours
    keep.violet = keep.violet or gone.violet
    for g in pairs(gone.distinct) do MarkDistinct(keep, g) end
    Remove(gone)
    SetCentre(keep)
end

-- A camp's spot moved: fold in any record now on the same fire. Your own
-- camp is always the one kept.
local function Fold(f)
    while true do
        local g = Find(f)
        if not g then return f end
        if g.mine then f, g = g, f end
        Absorb(f, g)
    end
end

-- A sender is at one camp at a time: their estimate leaves any other camp.
local function DropSender(who, except)
    for _, f in ipairs(Net.fires) do
        if f ~= except and f.est[who] then
            f.est[who] = nil
            if next(f.est) then SetCentre(f) end -- with nobody's estimate left, it keeps its spot
        end
    end
end

-- Someone else's report about a camp: new, or an update.
local function Merge(r)
    DropSender(r.from)
    local e = { wx = r.wx, wy = r.wy, n = r.n or 1, exact = r.exact or nil, cooked = r.cooked or nil, pinned = r.pinned or nil }
    local f = Find(r)
    if not f then
        f = NewRecord(r)
        f.est[r.from] = e
        f.first = r.first or Now()
        Net.fires[#Net.fires + 1] = f
        SetCentre(f)
        return f
    end
    -- Someone's there since you found no fire at its spot: its spot was off.
    if f.noFireAt and r.last > f.noFireAt + 30 then f.noFire, f.noFireAt = nil, nil end
    -- Newer word wins on what's there; the oldest times stay.
    if r.last >= (f.last or 0) then
        f.tier = math.max(f.tier or 0, r.tier or 0)
        f.full = r.full
        if #r.spells >= #f.spells and not f.mine then f.spells = r.spells end
        f.from, f.last = r.from, r.last
    end
    if r.started and (not f.started or r.started < f.started) then f.started = r.started end
    f.violet = f.violet or r.violet
    -- What it's looking for: the newest change wins, here and at the camp itself.
    if (r.wantsAt or 0) > (f.wantsAt or 0) then
        f.wants, f.wantsAt = r.wants, r.wantsAt
        if f.mine and ns.Camp.ApplyWants then ns.Camp.ApplyWants(r.wants, r.wantsAt) end
    end
    f.est[r.from] = e
    SetCentre(f)
    return Fold(f)
end

local function Prune()
    local now, keep = Now(), {}
    for _, f in ipairs(Net.fires) do
        if Net.Alive(f, now) then keep[#keep + 1] = f end
    end
    Net.fires = keep
end

-- The camps to show: on your layer (and faction), or the one you're at.
function Net.Visible()
    Prune()
    local list, Others = {}, ns.CampOthers
    for _, f in ipairs(Net.fires) do
        if f.mine then
            if Net.Settled(f) then list[#list + 1] = f end
        elseif layer and f.layer == layer and not (Others and Others.NoFire(f)) then
            list[#list + 1] = f
        end
    end
    if Others then Others.AddVisible(list) end -- Happy Camper's and chat's (CampOthers.lua)
    return list
end

---------------------------------------------------------------------------
-- The channel
---------------------------------------------------------------------------

local function Enabled()
    local kit = ns.kit
    return kit and kit.db and kit.db.campShare ~= false
end

local channelID
local function ChannelID()
    if not channelID or channelID == 0 then
        channelID = GetChannelName and GetChannelName(CHANNEL) or 0
    end
    return channelID ~= 0 and channelID or nil
end

-- Keep it out of every chat window: it only carries addon messages.
local function HideChannel()
    if not ChatFrame_RemoveChannel then return end
    for i = 1, (NUM_CHAT_WINDOWS or 10) do
        local cf = _G["ChatFrame" .. i]
        if cf then pcall(ChatFrame_RemoveChannel, cf, CHANNEL) end
    end
end

-- The kit's channel must always sit behind the game's own channels, or it
-- takes General's /1 (or Trade's /2) and players can't talk there. The game
-- hands a new channel the lowest free number, so if the kit joins before
-- General does it gets slot 1. Built-in channels are found by category, never
-- by name, so this works in every game language and wherever the player has
-- moved them.

-- Highest number held by a built-in world/zone channel (General, Trade,
-- LocalDefense...), 0 if none are joined yet, nil if we can't tell.
local function LastWorldSlot()
    if not (GetNumDisplayChannels and GetChannelDisplayInfo) then return nil end
    local last = 0
    for i = 1, GetNumDisplayChannels() or 0 do
        local ok, _, header, _, number, _, _, category = pcall(GetChannelDisplayInfo, i)
        if ok and not header and number and category == "CHANNEL_CATEGORY_WORLD" then
            last = math.max(last, number)
        end
    end
    return last
end

-- False while none of the game's own channels are in yet.
function Net.WorldChannelsIn()
    return LastWorldSlot() ~= 0
end

-- If a hidden channel sits in front of a built-in one, move it to the back.
-- Swapping keeps everyone else's numbers in order; leaving and rejoining
-- wouldn't help, since a rejoin takes the same (lowest free) number again.
local fixing = false
local function ChannelNumber(name)
    local id = GetChannelName and GetChannelName(name) or 0
    return id ~= 0 and id or nil
end

function Net.StepBehindWorld(name)
    if fixing then return end
    local last = LastWorldSlot()
    local id = ChannelNumber(name)
    if not (last and id and id < last) then return end
    local swap = C_ChatInfo and C_ChatInfo.SwapChatChannelsByChannelIndex
    fixing = true
    if swap then
        for _ = 1, 10 do
            if not (id and id < last) then break end
            if not pcall(swap, id, id + 1) then break end
            channelID = nil
            local now = ChannelNumber(name)
            if now == id then break end -- swap didn't take
            id = now
        end
    end
    channelID = nil
    id = ChannelNumber(name)
    if id and id < last then
        -- No way to move it: give the slot back to the game's channels rather
        -- than keep General's number. It's back at the next login.
        if LeaveChannelByName then pcall(LeaveChannelByName, name) end
        channelID = nil
    end
    fixing = false
end

local function MoveBehindWorld() Net.StepBehindWorld(CHANNEL) end

local function JoinChannel()
    if not Enabled() then return end
    if not ChannelID() and JoinTemporaryChannel then
        pcall(JoinTemporaryChannel, CHANNEL)
        channelID = nil
    end
    MoveBehindWorld()
    HideChannel()
end

-- Join once the game's own channels are in. Some places (instances, some
-- cities) never join them; after a minute the kit joins anyway, and
-- MoveBehindWorld steps it back if General turns up later.
local function JoinWhenSafe(tries)
    tries = tries or 0
    if not Enabled() then return end
    if LastWorldSlot() == 0 and tries < 30 and C_Timer then
        C_Timer.After(2, function() JoinWhenSafe(tries + 1) end)
        return
    end
    JoinChannel()
end

local function LeaveChannel()
    if ChannelID() and LeaveChannelByName then pcall(LeaveChannelByName, CHANNEL) end
    channelID = nil
end

local function Faction()
    local f = UnitFactionGroup and UnitFactionGroup("player")
    return f == "Horde" and "H" or (f == "Alliance" and "A" or "N")
end

local function Send(msg)
    local id = ChannelID()
    if not id then return end
    local send = C_ChatInfo and C_ChatInfo.SendAddonMessage or SendAddonMessage
    if send then pcall(send, PREFIX, msg, "CHANNEL", id) end
end

-- F|version|faction|layer|continent|wx|wy|map|mx|my|tier|full|started|spell,spell,...|want,want,...|wantsAt|exact|samples|violet
-- wx, wy (and mx, my) are the fire's spot as the sender works it out; exact = they built it.
local function Encode(f, est)
    est = est or f
    return ("F|%d|%s|%s|%d|%.1f|%.1f|%d|%.4f|%.4f|%d|%d|%d|%s|%s|%d|%d|%d|%d"):format(VERSION, Faction(), f.layer, f.cont,
        est.wx, est.wy, f.map, f.mx, f.my, f.tier or 0, f.full and 1 or 0, f.started or 0, table.concat(f.spells, ","),
        -- exact: 1 built here, 2 pinned by an announce, 3 found by cooking range (older kits read 2 and 3 as plain estimates)
        table.concat(f.wants or {}, ","), f.wantsAt or 0, est.exact and 1 or (est.cooked and 3 or (est.pinned and 2 or 0)),
        math.min(999, est.n or 1), f.violet and 1 or 0) -- (older kits ignore the last field)
end

local function Decode(msg, sender)
    local parts = { strsplit("|", msg) }
    if parts[1] ~= "F" or tonumber(parts[2]) ~= VERSION then return nil end
    if parts[3] ~= Faction() then return nil end
    local r = {
        layer = parts[4], cont = tonumber(parts[5]), wx = tonumber(parts[6]), wy = tonumber(parts[7]),
        map = tonumber(parts[8]), mx = tonumber(parts[9]), my = tonumber(parts[10]),
        tier = tonumber(parts[11]) or 0, full = parts[12] == "1", started = tonumber(parts[13]),
        spells = {}, wants = {}, wantsAt = tonumber(parts[16]) or 0, from = sender, last = Now(),
    }
    if not (r.layer and r.layer ~= "" and r.cont and r.wx and r.wy and r.map and r.mx and r.my) then return nil end
    if r.tier < 0 or r.tier > 3 then return nil end
    if r.started == 0 then r.started = nil end
    -- A start time from the future, or older than a fire lasts, isn't believed.
    if r.started and (r.started > r.last + 30 or r.started < r.last - FIRE_LIFE) then r.started = nil end
    for id in (parts[14] or ""):gmatch("%d+") do
        if #r.spells >= 12 then break end
        local spell = tonumber(id)
        if ns.Camp.ObjectBySpell(spell) then r.spells[#r.spells + 1] = spell end
    end
    for id in (parts[15] or ""):gmatch("%d+") do
        if #r.wants >= 11 then break end
        local spell = tonumber(id)
        if ns.Camp.ObjectBySpell(spell) then r.wants[#r.wants + 1] = spell end
    end
    if r.wantsAt > r.last + 30 then r.wantsAt = r.last end -- not from the future
    r.exact = parts[17] == "1"
    r.pinned = parts[17] == "2"
    r.cooked = parts[17] == "3"
    r.n = math.max(1, math.min(999, tonumber(parts[18]) or 1))
    r.violet = parts[19] == "1" or nil
    return r
end

local me
local function IsMe(sender)
    if not me then
        local name, realm = UnitFullName("player")
        me = name and (name .. "-" .. (realm or (GetNormalizedRealmName and GetNormalizedRealmName()) or "")) or nil
    end
    return sender == me or (Ambiguate and Ambiguate(sender or "", "none") == UnitName("player"))
end

local function OnMessage(prefix, msg, _, sender)
    if prefix ~= PREFIX or not Enabled() or IsMe(sender) then return end
    if U.Sealed(msg) or type(msg) ~= "string" then return end
    local r = Decode(msg, Ambiguate and Ambiguate(sender, "short") or sender)
    if not r or not r.from then return end
    Merge(r)
    if ns.CampMap then ns.CampMap.Refresh() end
end

---------------------------------------------------------------------------
-- Your camp: tagged with your layer and where you stood when you got there
---------------------------------------------------------------------------

local mine         -- this camp's record, while you're at it
local sentAt = 0
local sendQueued = false
local lastLeft     -- { f = the camp you just left, at = GetTime() }: a quick new one is a swap
local castAt       -- { pos = Here(), at = GetTime() }: your last campfire cast, for the camp it makes
local lastPos      -- the last position sample, to tell standing still from walking
local ME = "\0me" -- your own estimate's key in est (never a player name)

-- Good enough to share: you built it, or you've stood around a while.
local function Settled(f)
    return f.cast ~= nil or f.cook ~= nil or f.pin ~= nil or (f.still or 0) >= 2 or (f.walked or 0) >= 6
end

Net.Settled = Settled

-- Whether a camp's exact spot is known, not worked out.
function Net.Known(f)
    if f.outside then return f.owned and not f.rough end
    return (f.exact or f.cooked or f.pinned or f.cast or f.cook or f.pin or f.litSpot) and true or false
end

-- Where a camp shows, in world yards. A known spot as it is (Happy Camper's,
-- when it's the only one who knows); an estimate only once it has moved
-- ESTIMATE_MOVE yards from where it shows.
local ESTIMATE_MOVE = 15
function Net.Shown(f)
    if not (f.exact or f.cooked or f.pinned or f.cast or f.cook or f.pin) and f.litSpot then return f.litSpot.wx, f.litSpot.wy end
    if Net.Known(f) then return f.wx, f.wy end
    if not f.shownX or math.sqrt((f.wx - f.shownX) ^ 2 + (f.wy - f.shownY) ^ 2) >= ESTIMATE_MOVE then
        f.shownX, f.shownY = f.wx, f.wy
    end
    return f.shownX, f.shownY
end

-- Your own estimate of where your camp's fire is.
local function MyEstimate(f)
    if f.cast then return { wx = f.cast.wx, wy = f.cast.wy, n = 20, exact = true } end
    if f.cook then return { wx = f.cook.sx / f.cook.n, wy = f.cook.sy / f.cook.n, n = 20, cooked = true } end
    if f.pin then return { wx = f.pin.wx, wy = f.pin.wy, n = 20, pinned = true } end
    if (f.still or 0) > 0 then return { wx = f.sx / f.still, wy = f.sy / f.still, n = f.still } end
    return { wx = f.ax / f.walked, wy = f.ay / f.walked, n = 1 }
end

local function SendMine()
    sendQueued = false
    if not (mine and Enabled() and layer and Settled(mine)) then return end
    sentAt = GetTime()
    Send(Encode(mine, mine.est[ME]))
end

-- A position sample while you're at your camp.
local function Sample(here)
    if not (mine and here and here.cont == mine.cont) then return end
    mine.ax, mine.ay, mine.walked = mine.ax + here.wx, mine.ay + here.wy, mine.walked + 1
    if lastPos and Dist(here, lastPos) < 1.5 then
        mine.sx, mine.sy, mine.still = mine.sx + here.wx, mine.sy + here.wy, mine.still + 1
    end
    lastPos = here
    mine.est[ME] = MyEstimate(mine)
    SetCentre(mine)
    if Settled(mine) then Fold(mine) end
end

---------------------------------------------------------------------------
-- Finding the fire by cooking range
---------------------------------------------------------------------------

local COOK_SPREAD = 35 -- yards: readings further apart than this are two cooking sources (range is about 15)
local COOK_SOURCE = 20 -- yards: a remembered cooking source covers this far
local COOK_FORGET = 30 -- yards: a fire known this close accounts for the reading
local otherCooking = {} -- this session: spots with a cooking source but no Campfire Nearby (town fires and so on)

-- A recipe that needs a cooking fire: its requirement reads true in range of
-- one. (IsNearProfessionSpellFocus reads false at a camp's fire on Forever.)
local FIRE_RECIPE = 20626
local function NearCooking()
    local check = C_TradeSkillUI and C_TradeSkillUI.GetRecipeRequirements
    if not check then return false end
    local ok, reqs = pcall(check, FIRE_RECIPE)
    local req = ok and type(reqs) == "table" and reqs[1]
    return req and not U.Sealed(req.met) and req.met == true or false
end

-- Once a second, out of combat. Next to a cooking source: with Campfire Nearby
-- it's taken to be your camp's fire, unless it's a source already known or
-- another fire's; without it, it's a source to ignore from now on.
function Net.CheckCooking()
    if InCombatLockdown and InCombatLockdown() then return end
    if not NearCooking() then return end
    local here = Net.Here()
    if not here then return end
    if not (ns.AtCamp and ns.AtCamp()) then
        for _, s in ipairs(otherCooking) do
            if s.cont == here.cont and Dist(s, here) <= COOK_SOURCE then return end
        end
        if #otherCooking < 50 then otherCooking[#otherCooking + 1] = here end
        return
    end
    if not mine or mine.cast or mine.cookMixed then return end
    for _, s in ipairs(otherCooking) do
        if s.cont == here.cont and Dist(s, here) <= COOK_SOURCE then return end
    end
    for _, f in ipairs(Net.fires) do
        if f ~= mine and f.cont == here.cont and (f.exact or f.cooked) and Dist(f, here) <= COOK_FORGET then return end
    end
    local cook = mine.cook
    if cook and math.sqrt((here.wx - cook.sx / cook.n) ^ 2 + (here.wy - cook.sy / cook.n) ^ 2) > COOK_SPREAD then
        -- Two sources here: this can't tell which is the fire, so it's a ring again.
        mine.cook, mine.cookMixed = nil, true
    elseif cook then
        cook.sx, cook.sy, cook.n = cook.sx + here.wx, cook.sy + here.wy, cook.n + 1
    else
        mine.cook = { sx = here.wx, sy = here.wy, n = 1 }
    end
    local first = cook == nil or mine.cook == nil
    mine.est[ME] = MyEstimate(mine)
    SetCentre(mine)
    Fold(mine)
    if first then
        if C_Timer then C_Timer.After(0, SendMine) else SendMine() end
        if ns.CampMap then ns.CampMap.Refresh() end
    end
end

-- You got to a camp: a record of your own (merged with others' once its spot settles).
local function Arrive()
    local here = Net.Here()
    if not here then return end
    -- Back in range of the camp you just left: the same camp, not a new one.
    -- (Campfire Nearby comes and goes on the edge of its range. It's a new
    -- aura each time, so only where you are can tell. Another fire's aura
    -- would start further than its range from a spot you stood at.)
    local left = lastLeft
    if left and not (castAt and GetTime() - castAt.at <= 20) and GetTime() - left.at <= REJOIN
        and left.f.cont == here.cont and Net.Alive(left.f) and Dist(here, left.f) <= RANGE then
        for _, f in ipairs(Net.fires) do
            if f == left.f then
                mine = f
                mine.mine, mine.yours = true, nil
                lastLeft, lastPos = nil, nil
                Sample(here)
                return
            end
        end
    end
    mine = NewRecord({ layer = layer or "?", cont = here.cont, map = here.map, wx = here.wx, wy = here.wy,
        mx = here.mx, my = here.my, first = Now(), last = Now(), mine = true, wantsAt = 0,
        ax = 0, ay = 0, walked = 0, sx = 0, sy = 0, still = 0 })
    if castAt and GetTime() - castAt.at <= 20 and Dist(castAt.pos, here) <= RANGE + 10 then
        mine.cast = castAt.pos
    end
    castAt, lastPos = nil, nil
    Net.fires[#Net.fires + 1] = mine
    -- Left one fire's range and got another's at once: two different fires.
    if lastLeft and GetTime() - lastLeft.at <= SWAP then MarkDistinct(mine, lastLeft.f) end
    lastLeft = nil
    Sample(here)
end

-- Whether your camp's fire is known to be purple (Camp.IsViolet).
function Net.MineViolet() return mine and mine.violet end

-- You left your camp (or walked out of its fire's range into another's).
-- It stays on the map until it burns out, still marked as yours (so it never
-- glows at you for what it's asking for).
function Net.Leave()
    if mine then
        mine.mine, mine.yours = nil, true
        lastLeft = { f = mine, at = GetTime() }
        mine = nil
    end
    if ns.CampMap then ns.CampMap.Refresh() end
end

-- You built a campfire. Returns false if it's a different fire from the one
-- you're at (you keep the first fire's aura while inside its range), so the
-- camp you're at isn't changed by it.
function Net.FireBuilt(tier)
    local here = Net.Here()
    if not here then return true end
    if mine and Settled(mine) and here.cont == mine.cont and Dist(here, mine) > SAME_FIRE then
        local f = NewRecord({ layer = mine.layer, cont = here.cont, map = here.map, wx = here.wx, wy = here.wy,
            mx = here.mx, my = here.my, tier = tier, started = Now(), first = Now(), last = Now(), yours = true,
            wantsAt = 0 })
        f.est[ME] = { wx = here.wx, wy = here.wy, n = 20, exact = true }
        Net.fires[#Net.fires + 1] = f
        MarkDistinct(f, mine)
        SetCentre(f)
        if Enabled() and layer and f.layer ~= "?" then Send(Encode(f, f.est[ME])) end
        if ns.CampMap then ns.CampMap.Refresh() end
        return false
    end
    if mine then
        mine.cast = here
        Sample(here)
    else
        castAt = { pos = here, at = GetTime() }
    end
    return true
end

-- You're standing clearly nearer another fire than the one whose buff you
-- hold (it sticks until you leave its range): a camp object you mouse over
-- is more likely that fire's, so don't credit it to yours. Near your own
-- fire everything counts, even with another fire close by. Until your
-- fire's spot is known (built, or you've stood still at it), nothing is held back.
local CLEARLY_NEARER = 15 -- yards
function Net.Ambiguous()
    if not (mine and (mine.cast or mine.cook or mine.pin or (mine.still or 0) > 0)) then return false end
    local here = Net.Here()
    if not here then return false end
    local dMine = Dist(here, mine)
    for _, f in ipairs(Net.fires) do
        if f ~= mine and f.cont == here.cont and (f.yours or f.layer == mine.layer) and Net.Alive(f) then
            local d = Dist(here, f)
            if d <= RANGE and d + CLEARLY_NEARER < dMine then return true end
        end
    end
    return false
end

-- Something about your camp changed (or you got there, or left).
function Net.CampChanged()
    local Camp = ns.Camp
    if not (Camp and ns.AtCamp) then return end
    if not ns.AtCamp() then
        if mine then Net.Leave() end
        return
    end
    if not mine then Arrive() end
    if not mine then return end
    if layer and mine.layer == "?" then
        mine.layer = layer
        Fold(mine)
    end
    local s = Camp.Snapshot()
    mine.tier, mine.full, mine.spells, mine.last = s.tier, s.full, s.spells, Now()
    mine.violet = mine.violet or s.violet
    if (s.wantsAt or 0) >= (mine.wantsAt or 0) then mine.wants, mine.wantsAt = s.wants, s.wantsAt end
    if s.started and (not mine.started or s.started < mine.started) then mine.started = s.started end
    mine.from = UnitName("player")
    if ns.CampMap then ns.CampMap.Refresh() end
    -- Tell the others shortly (a few changes in a row go as one message).
    if not sendQueued and C_Timer then
        sendQueued = true
        C_Timer.After(math.max(2, 5 - (GetTime() - sentAt)), SendMine)
    end
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------

local ev = CreateFrame("Frame")
local heartbeat, cookTick = 0, 0

ev:SetScript("OnEvent", function(_, event, ...)
    if event == "PLAYER_LOGIN" then
        if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then C_ChatInfo.RegisterAddonMessagePrefix(PREFIX) end
        for _, e in ipairs({ "CHAT_MSG_ADDON", "NAME_PLATE_UNIT_ADDED", "PLAYER_TARGET_CHANGED",
            "UPDATE_MOUSEOVER_UNIT", "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA", "GROUP_JOINED",
            "GROUP_LEFT", "CHANNEL_UI_UPDATE" }) do
            pcall(ev.RegisterEvent, ev, e)
        end
        -- Join after the game's own channels, so General and Trade keep their numbers.
        if C_Timer then C_Timer.After(5, JoinWhenSafe) else JoinChannel() end
    elseif event == "CHAT_MSG_ADDON" then
        OnMessage(...)
    elseif event == "NAME_PLATE_UNIT_ADDED" then
        SeeUnit((...))
    elseif event == "PLAYER_TARGET_CHANGED" then
        SeeUnit("target")
    elseif event == "UPDATE_MOUSEOVER_UNIT" then
        SeeUnit("mouseover")
    elseif event == "CHANNEL_UI_UPDATE" then
        channelID = nil
        -- A built-in channel may have joined behind ours (e.g. General after
        -- leaving an instance): step back so it keeps its number.
        if Enabled() then MoveBehindWorld() end
        HideChannel()
    elseif event == "PLAYER_ENTERING_WORLD" or event == "GROUP_JOINED" or event == "GROUP_LEFT" then
        -- A loading screen or a group change can put you on another layer.
        ForgetLayer()
    elseif event == "ZONE_CHANGED_NEW_AREA" then
        if Continent() ~= layerContinent then ForgetLayer() end
    end
end)
ev:RegisterEvent("PLAYER_LOGIN")

-- While you're at a camp, say so now and then (so others joining the layer
-- see it, and know it's still burning).
ev:SetScript("OnUpdate", function(_, elapsed)
    cookTick = cookTick + elapsed
    if cookTick >= 1 then
        cookTick = 0
        Net.CheckCooking()
    end
    heartbeat = heartbeat + elapsed
    if heartbeat < SAMPLE then return end
    heartbeat = 0
    if not mine then return end
    local wasSettled = Settled(mine)
    Sample(Net.Here())
    if ns.CampMap then ns.CampMap.Refresh() end
    -- Just settled: say so now. Otherwise now and then.
    if (Settled(mine) and not wasSettled) or GetTime() - sentAt >= HEARTBEAT then
        mine.last = Now()
        SendMine()
    end
end)

-- Announcing pins the camp: the announce's map pin becomes THE spot for the
-- fire, for you and every kit user, and the tent pin stops following people
-- around it. A spot already fixed (built, or someone's earlier announce) is
-- kept, so everyone's link points at the same place; otherwise it's where
-- you're standing. Returns the map and spot for the chat link, or nil.
function Net.PinSpot()
    if not mine then return nil end
    if not (mine.cast or mine.cook or mine.pin or mine.exact or mine.cooked or mine.pinned) then
        local here = Net.Here()
        if not (here and here.cont == mine.cont) then return nil end
        mine.pin = { wx = here.wx, wy = here.wy }
        mine.map = here.map -- the map you're on now, for the link
        mine.est[ME] = MyEstimate(mine)
        SetCentre(mine)
        Fold(mine)
        if C_Timer then C_Timer.After(0, SendMine) else SendMine() end
        if ns.CampMap then ns.CampMap.Refresh() end
    end
    if not (mine.map and mine.mx and mine.my) then return nil end
    return mine.map, mine.mx, mine.my
end

-- General chat's number, found without its (localized) name and wherever the
-- player has moved it: the built-in channel with zone channel ID 1, else the
-- lowest-numbered built-in world channel, else /1. Never the kit's own channel.
function Net.GeneralChannel()
    local own = ChannelID()
    local lowest
    if GetNumDisplayChannels and GetChannelDisplayInfo then
        for i = 1, GetNumDisplayChannels() or 0 do
            local ok, name, header, _, number, _, _, category = pcall(GetChannelDisplayInfo, i)
            if ok and not header and number and number ~= own and category == "CHANNEL_CATEGORY_WORLD" then
                local info = C_ChatInfo and C_ChatInfo.GetChannelInfoFromIdentifier
                    and select(2, pcall(C_ChatInfo.GetChannelInfoFromIdentifier, name))
                if type(info) == "table" and info.zoneChannelID == 1 then return number end
                if not lowest or number < lowest then lowest = number end
            end
        end
    end
    if lowest then return lowest end
    local id = GetChannelName and GetChannelName(1)
    if id and id ~= 0 and id ~= own then return 1 end
    return nil
end

-- The share setting changed.
function Net.Apply()
    if Enabled() then JoinChannel() else LeaveChannel() end
    if ns.CampMap then ns.CampMap.Refresh() end
end
