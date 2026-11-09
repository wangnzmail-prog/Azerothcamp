local addonName, ns = ...

---------------------------------------------------------------------------
-- Camps the kit hears about from outside: Happy Camper's camp channel (with
-- Torridon's permission, Oct 2026) and map pins posted in public chat.
--
-- The kit only listens. Nothing here is ever sent, on Happy Camper's channel
-- or to other kit users: these camps stay on your own map, marked with where
-- they came from. They never change a camp kit users share; a kit camp on the
-- same fire simply hides the report and borrows its list of objects if it has
-- none of its own.
--
-- A chat post doesn't say which layer its fire is on, and layer numbers can
-- only be compared within a zone, so a camp whose layer can't be told shows
-- faded. One known to be on another layer doesn't show.
--
-- Fires burn FIRE_LIFE seconds from when the report says they were placed
-- (Happy Camper's own expiry time isn't used).
--
-- Also here: "no fire here". Campfire Nearby reaches about 100 yards, so
-- standing within NO_FIRE_RADIUS yards of any camp for NO_FIRE_FOR seconds
-- without it means that fire is out or on another layer: the pin goes, for
-- this layer and on this computer only.
---------------------------------------------------------------------------

local Core = ns.Core
local U = Core.U

local Others = {}
ns.CampOthers = Others

local PREFIX = "HappyCamper"
local CHANNEL = "HappyCamper"
local SOURCE = "Happy Camper"
local FIRE_LIFE = 600
local SAME_FIRE = 50       -- yards: as CampNet
local CHAT_NEAR = 60       -- yards: a chat pin this close to a known camp or meet-up is that one
local MAX_CAMPS = 80
local NEW_PER_SENDER = 30  -- seconds between new camps from one player
local CHAT_PER_SENDER = 60 -- ... and new chat pins
local NEW_PER_MINUTE = 20  -- new camps a minute from everyone
local NO_FIRE_RADIUS = 50
local NO_FIRE_FOR = 5
local NO_FIRE_SURE = 10     -- yards: this close with no Campfire Nearby, any camp's pin goes
local NO_FIRE_SURE_FOR = 2  -- seconds (the aura can take a moment to arrive at a new fire)

Others.camps = {}          -- [id] = record, shaped like CampNet's (see Record)
local requests = {}        -- [id] = meet-up spots with no fire yet
local atCamp = {}          -- [sender] = the Happy Camper camp they say they're at

local function Now() return GetServerTime and GetServerTime() or time() end

local function Enabled()
    local kit = ns.kit
    return kit and kit.db and kit.db.campOthers ~= false
end

local function Short(name) return Ambiguate and Ambiguate(name, "short") or name end

---------------------------------------------------------------------------
-- Records
---------------------------------------------------------------------------

local function WorldSpot(map, mx, my)
    if not (C_Map and C_Map.GetWorldPosFromMapPos and CreateVector2D) then return nil end
    local ok, cont, world = pcall(C_Map.GetWorldPosFromMapPos, map, CreateVector2D(mx, my))
    if not ok or not cont or not world then return nil end
    local wx, wy = world:GetXY()
    return cont, wx, wy
end

local function Dist(a, cont, wx, wy)
    if a.cont ~= cont then return nil end
    local dx, dy = a.wx - wx, a.wy - wy
    return math.sqrt(dx * dx + dy * dy)
end

local function Prune()
    local now = Now()
    for id, f in pairs(Others.camps) do
        if not ns.CampNet.Alive(f, now) then Others.camps[id] = nil end
    end
    for id, r in pairs(requests) do
        if now >= r.ends then requests[id] = nil end
    end
end

local function Count()
    local n = 0
    for _ in pairs(Others.camps) do n = n + 1 end
    return n
end

-- Flood limits: one player, and everyone together.
local lastNew, newTimes = {}, {}
local function AllowNew(key, wait)
    local t = GetTime()
    if lastNew[key] and t - lastNew[key] < wait then return false end
    while newTimes[1] and t - newTimes[1] > 60 do table.remove(newTimes, 1) end
    if #newTimes >= NEW_PER_MINUTE then return false end
    lastNew[key] = t
    newTimes[#newTimes + 1] = t
    return true
end

local function TierForSlots(slots)
    for _, fire in ipairs(ns.CAMPFIRES) do
        if fire.slots == slots then return fire.tier end
    end
    return 0
end

local function AddSpell(list, spell)
    if #list >= 12 then return end
    for _, s in ipairs(list) do
        if s == spell then return end
    end
    list[#list + 1] = spell
end

-- "164.1,197.2": a profession's game ID and its object's tier.
local function ReadEquipment(text, list)
    for skill, tier in (text or ""):gmatch("(%d+)%.(%d)") do
        local o = ns.Camp.ObjectByProfession(tonumber(skill), tonumber(tier))
        if o then AddSpell(list, o.spell) end
    end
end

local function ReadSpells(text, list)
    for id in (text or ""):gmatch("%d+") do
        local o = ns.Camp.ObjectFromGame(tonumber(id))
        if o then AddSpell(list, o.spell) end
    end
end

---------------------------------------------------------------------------
-- Happy Camper's channel (only the parts about camps)
---------------------------------------------------------------------------

local function CreatorOf(id) return id and id:match("^(.+):%d+$") end

local function SameFaction(code)
    if code ~= "A" and code ~= "H" then return true end
    return code == ((UnitFactionGroup("player") or ""):sub(1, 1))
end

-- A camp's fields, from a snapshot or a zone answer. Returns the record or nil.
local function ReadCamp(sender, id, mapID, x, y, owned, objects, equipment, layer, faction, slots, passing)
    local creator = CreatorOf(id)
    if not creator or not SameFaction(faction) then return nil end
    local map, px, py = tonumber(mapID), tonumber(x), tonumber(y)
    if not (map and px and py) or px <= 0 or px >= 10000 or py <= 0 or py >= 10000 then return nil end
    local placed = tonumber(id:match(":(%d+)$"))
    local now = Now()
    if not placed or placed > now + 30 or placed + FIRE_LIFE <= now then return nil end
    local mx, my = px / 10000, py / 10000
    local cont, wx, wy = WorldSpot(map, mx, my)
    if not cont then return nil end
    local f = {
        outside = true, source = SOURCE, id = id, from = Short(creator), owned = owned == "1",
        cont = cont, wx = wx, wy = wy, map = map, mx = mx, my = my,
        tier = TierForSlots(tonumber(slots)), spells = {},
        layer = layer and layer ~= "" and tostring(layer) or nil,
        rough = passing == "p" or nil, first = placed, last = placed,
    }
    ReadSpells(objects, f.spells)
    ReadEquipment(equipment, f.spells)
    return f
end

local function Store(f, sender)
    local old = Others.camps[f.id]
    if old then
        f.noFire, f.noFireAt = old.noFire, old.noFireAt
        if #f.spells == 0 then f.spells = old.spells end
    else
        Prune()
        if Count() >= MAX_CAMPS or not AllowNew(sender, NEW_PER_SENDER) then return end
    end
    Others.camps[f.id] = f
    -- A chat post about the same fire isn't needed any more.
    for id, c in pairs(Others.camps) do
        if c.chat then
            local d = Dist(c, f.cont, f.wx, f.wy)
            if d and d <= CHAT_NEAR then Others.camps[id] = nil end
        end
    end
end

local handlers = {}

function handlers.S(sender, id, mapID, x, y, _, owned, objects, _, equipment, layer, faction, slots, passing)
    if CreatorOf(id) ~= sender then return end
    local f = ReadCamp(sender, id, mapID, x, y, owned, objects, equipment, layer, faction, slots, passing)
    if f then Store(f, sender) end
end

-- An answer to someone's "what's burning here?" that went over the channel:
-- only ever adds a camp.
function handlers.ZA(sender, id, mapID, x, y, _, owned, objects, _, equipment, layer, faction, slots, _, _, _, _, passing)
    if not id or Others.camps[id] then return end
    local f = ReadCamp(sender, id, mapID, x, y, owned, objects, equipment, layer, faction, slots, passing)
    if f then Store(f, sender) end
end

-- What's at a camp: its creator's word is final; someone at it can only add.
local function TrustedCamp(sender, id)
    local f = id and Others.camps[id]
    if not f then return nil end
    local creator = CreatorOf(id) == sender
    if creator or atCamp[sender] == id then return f, creator end
end

function handlers.E(sender, id, list)
    local f, creator = TrustedCamp(sender, id)
    if not f then return end
    if creator then f.spells = {} end
    ReadEquipment(list, f.spells)
end

function handlers.O(sender, id, spell)
    local f = TrustedCamp(sender, id)
    local o = f and ns.Camp.ObjectFromGame(tonumber(spell))
    if o then AddSpell(f.spells, o.spell) end
end

function handlers.X(sender, id)
    if id and CreatorOf(id) == sender then Others.camps[id] = nil end
end

function handlers.P(sender, _, id)
    atCamp[sender] = id
end

function handlers.Z(sender)
    atCamp[sender] = nil
end

-- Camp Builder requests: a meet-up, no fire yet, so a chat pin there isn't a camp.
function handlers.R(sender, id, mapID, x, y)
    if CreatorOf(id) ~= sender then return end
    local map, px, py = tonumber(mapID), tonumber(x), tonumber(y)
    if not (map and px and py) then return end
    local cont, wx, wy = WorldSpot(map, px / 10000, py / 10000)
    if cont then requests[id] = { cont = cont, wx = wx, wy = wy, ends = Now() + FIRE_LIFE } end
end

function handlers.C(sender, id)
    if CreatorOf(id) == sender then requests[id] = nil end
end

local function OnAddonMessage(prefix, text, chatType, sender)
    if prefix ~= PREFIX or chatType ~= "CHANNEL" or not Enabled() then return end
    if U.Sealed(text) or U.Sealed(sender) or type(text) ~= "string" or type(sender) ~= "string" or #text > 255 then return end
    if Short(sender) == UnitName("player") then return end
    local fields = { strsplit(";", text) }
    local handler = handlers[fields[1]]
    if not handler then return end
    handler(sender, unpack(fields, 2))
    if ns.CampMap then ns.CampMap.Refresh() end
end

---------------------------------------------------------------------------
-- Map pins in public chat
---------------------------------------------------------------------------

-- Words for a camp or a fire, in lower case. Only the words around the pin count.
local WORDS = { "camp", "fire", "lager", "feuer", "feu", "acampa", "hoguera", "fogata", "fogueira", "ognisk", "obóz", "oboz",
    "营地", "营火", "篝火", "야영", "모닥불", "캠프" }

local function AboutACamp(words)
    for _, word in ipairs(WORDS) do
        if words:find(word, 1, true) then return true end
    end
    return false
end

local function Ignored(name)
    if not (C_FriendList and C_FriendList.IsIgnored) then return false end
    local ok, ignored = pcall(C_FriendList.IsIgnored, name)
    return ok and ignored
end

local function OnChat(text, sender)
    if not Enabled() or U.Sealed(text) or U.Sealed(sender) or type(text) ~= "string" or type(sender) ~= "string" or sender == "" then return end
    local map, px, py = text:match("|Hworldmap:(%d+):(%d+):(%d+)[:|]")
    if not map then return end
    local words = text:gsub("|H.-|h.-|h", " ")
    local lower = words:lower()
    -- Kit users' own announcements come over the kit's channel; a request isn't a fire.
    if text:find("^Camping Kit:") or lower:find("seeking", 1, true) or not AboutACamp(lower) then return end
    local name = Short(sender)
    if name == UnitName("player") or Ignored(name) then return end
    map, px, py = tonumber(map), tonumber(px) / 10000, tonumber(py) / 10000
    if px <= 0 or px >= 1 or py <= 0 or py >= 1 then return end
    if C_Map.CanSetUserWaypointOnMap and not C_Map.CanSetUserWaypointOnMap(map) then return end
    local cont, wx, wy = WorldSpot(map, px, py)
    if not cont then return end
    Prune()
    -- Known already, or someone's meet-up?
    for _, f in ipairs(ns.CampNet.fires) do
        local d = Dist(f, cont, wx, wy)
        if d and d <= CHAT_NEAR then return end
    end
    for _, f in pairs(Others.camps) do
        local d = not f.chat and Dist(f, cont, wx, wy)
        if d and d <= CHAT_NEAR then return end
    end
    for _, r in pairs(requests) do
        local d = Dist(r, cont, wx, wy)
        if d and d <= CHAT_NEAR then return end
    end
    if Count() >= MAX_CAMPS or not AllowNew("chat:" .. name, CHAT_PER_SENDER) then return end
    -- The same fire posted again replaces the older post; so does a player's new post.
    for id, f in pairs(Others.camps) do
        local d = f.chat and Dist(f, cont, wx, wy)
        if d and d <= CHAT_NEAR then Others.camps[id] = nil end
    end
    local now = Now()
    local id = "chat:" .. name
    Others.camps[id] = {
        outside = true, chat = true, id = id, from = name, cont = cont, wx = wx, wy = wy, map = map, mx = px, my = py,
        tier = TierForSlots(tonumber(words:match("%(%d+/(%d+)"))), spells = ns.Camp.ObjectsNamedIn(words),
        first = now, last = now,
    }
    if ns.CampMap then ns.CampMap.Refresh() end
end

---------------------------------------------------------------------------
-- What shows
---------------------------------------------------------------------------

-- "same", "other", or nil when it can't be told: layer numbers only compare
-- within a zone, and you or the camp may not have one yet.
local function LayerStatus(f)
    local mine = ns.CampNet.Layer()
    if not f.layer or not mine then return nil end
    local Map = ns.CampMap
    local here = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    if here and U.Sealed(here) then here = nil end
    if not (Map and here) then return nil end
    local zone = Map.ZoneOf(here)
    if not zone or zone ~= Map.ZoneOf(f.map) then return nil end
    return f.layer == mine and "same" or "other"
end

-- You've been at this spot and found no fire, on this layer (or any, if yours isn't known).
function Others.NoFire(f)
    if f.noFire == nil then return false end
    return f.noFire == false or f.noFire == ns.CampNet.Layer()
end

-- Adds the outside camps to what the maps show. list holds the kit's own so far.
function Others.AddVisible(list)
    for _, k in ipairs(list) do k.report, k.litSpot = nil, nil end
    if not Enabled() then return end
    Prune()
    local kitCount = #list
    for _, f in pairs(Others.camps) do
        local status = LayerStatus(f)
        if status ~= "other" and not Others.NoFire(f) then
            local onKit
            for i = 1, kitCount do
                local k = list[i]
                local d = Dist(k, f.cont, f.wx, f.wy)
                if d and d <= SAME_FIRE then
                    onKit = true
                    if not k.report or #f.spells > #k.report.spells then k.report = f end
                    -- Whoever lit it knows where it is.
                    if ns.CampNet.Known(f) then k.litSpot = f end
                end
            end
            if not onKit then
                f.layerUnknown = status == nil
                f.faded = f.chat or f.rough or f.layerUnknown or nil
                list[#list + 1] = f
            end
        end
    end
end

---------------------------------------------------------------------------
-- No fire here
---------------------------------------------------------------------------

local function CanTell(f)
    if f.mine or f.yours or f.rough then return false end
    if f.outside then return true end
    -- A kit camp's spot has to be more than a first guess.
    return f.exact or f.cooked or f.pinned or (f.n or 0) >= 3
end

local since = {} -- [camp] = when you came near it with no fire

local function CheckOne(f, here, near, t)
    -- Rough spots and camps you were at only count from right on top of them.
    local d = not f.mine and Dist(f, here.cont, here.wx, here.wy)
    local sure = d and d <= NO_FIRE_SURE
    if not d or d > NO_FIRE_RADIUS or not (sure or CanTell(f)) then
        since[f] = nil
    elseif near then
        since[f] = nil
        if f.noFire ~= nil then
            f.noFire, f.noFireAt = nil, nil
            return true
        end
    else
        since[f] = since[f] or t
        if t - since[f] >= (sure and NO_FIRE_SURE_FOR or NO_FIRE_FOR) and not Others.NoFire(f) then
            f.noFire, f.noFireAt = ns.CampNet.Layer() or false, Now()
            return true
        end
    end
end

-- Once a second, out of combat (auras can't be read in a fight).
function Others.CheckNoFire()
    if (InCombatLockdown and InCombatLockdown()) or (UnitAffectingCombat and UnitAffectingCombat("player"))
        or (UnitIsDeadOrGhost and UnitIsDeadOrGhost("player")) or not ns.AtCamp then
        wipe(since)
        return
    end
    local here = ns.CampNet.Here()
    if not here then return end
    local near, t, changed = ns.AtCamp(), GetTime(), false
    for _, f in ipairs(ns.CampNet.fires) do
        if CheckOne(f, here, near, t) then changed = true end
    end
    for _, f in pairs(Others.camps) do
        if CheckOne(f, here, near, t) then changed = true end
    end
    if changed and ns.CampMap then ns.CampMap.Refresh() end
end

---------------------------------------------------------------------------
-- The channel
---------------------------------------------------------------------------

local function HappyCamperLoaded()
    local loaded = C_AddOns and C_AddOns.IsAddOnLoaded or IsAddOnLoaded
    return loaded and loaded("HappyCamper") or false
end

local function InChannel()
    local id = GetChannelName and GetChannelName(CHANNEL) or 0
    return id and id ~= 0
end

-- Happy Camper looks after its channel itself when it's installed.
local function Tidy()
    if HappyCamperLoaded() or not InChannel() then return end
    ns.CampNet.StepBehindWorld(CHANNEL)
    if ChatFrame_RemoveChannel then
        for i = 1, (NUM_CHAT_WINDOWS or 10) do
            local cf = _G["ChatFrame" .. i]
            if cf then pcall(ChatFrame_RemoveChannel, cf, CHANNEL) end
        end
    end
end

-- Joins once the game's own channels are in, so they keep their numbers.
local function JoinWhenSafe(tries)
    tries = tries or 0
    if not Enabled() or HappyCamperLoaded() then return end
    if not InChannel() then
        if ns.CampNet.WorldChannelsIn() == false and tries < 30 and C_Timer then
            C_Timer.After(2, function() JoinWhenSafe(tries + 1) end)
            return
        end
        if JoinTemporaryChannel then pcall(JoinTemporaryChannel, CHANNEL) end
    end
    Tidy()
end

-- The setting changed.
function Others.Apply()
    if Enabled() then
        JoinWhenSafe()
    else
        if not HappyCamperLoaded() and InChannel() and LeaveChannelByName then pcall(LeaveChannelByName, CHANNEL) end
        wipe(Others.camps)
    end
    if ns.CampMap then ns.CampMap.Refresh() end
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------

local ev = CreateFrame("Frame")
local CHAT_EVENTS = { "CHAT_MSG_SAY", "CHAT_MSG_YELL", "CHAT_MSG_CHANNEL", "CHAT_MSG_GUILD", "CHAT_MSG_PARTY",
    "CHAT_MSG_PARTY_LEADER", "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER" }
local isChat = {}
for _, e in ipairs(CHAT_EVENTS) do isChat[e] = true end

ev:SetScript("OnEvent", function(_, event, a, b, c, d)
    if event == "PLAYER_LOGIN" then
        if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then C_ChatInfo.RegisterAddonMessagePrefix(PREFIX) end
        ev:RegisterEvent("CHAT_MSG_ADDON")
        ev:RegisterEvent("CHANNEL_UI_UPDATE")
        for _, e in ipairs(CHAT_EVENTS) do ev:RegisterEvent(e) end
        -- After the kit's own channel, which joins at 5 seconds.
        if C_Timer then C_Timer.After(10, JoinWhenSafe) else JoinWhenSafe() end
    elseif event == "CHAT_MSG_ADDON" then
        OnAddonMessage(a, b, c, d)
    elseif event == "CHANNEL_UI_UPDATE" then
        if Enabled() then Tidy() end
    elseif isChat[event] then
        OnChat(a, b)
    end
end)
ev:RegisterEvent("PLAYER_LOGIN")

local acc = 0
ev:SetScript("OnUpdate", function(_, elapsed)
    acc = acc + elapsed
    if acc < 1 then return end
    acc = 0
    Others.CheckNoFire()
end)
