-- Happy Camper. Copyright (c) 2026 Torridon. All rights reserved; see LICENSE.
local _, ns = ...

-- Camps from other camp addons. Some players share camps with addons other
-- than Happy Camper; while there are few of us, their camps help fill the map.
-- Happy Camper only listens: it joins their channel and reads their camp
-- messages, but never sends anything on them or pretends to be them. Their
-- camps are like camps posted in chat: yours alone (never sent on), faded and
-- "unconfirmed" until someone with Happy Camper rests there. Only outdoor maps;
-- blocked and ignored players are skipped.
--
-- A channel takes one of the player's chat channel slots, which they need for
-- their own (a guild's or friends' channel), so only an addon many players use
-- is worth one, and the player can leave it in Options. Campfire (CampfireNet),
-- S'more Skills (SmoreSkills) and Smoke Signals (SmokeSignal) were dropped on
-- 2026-11-08: a few dozen downloads in launch week, and no update in weeks.
--
-- Read from each addon's published messages, and CozyFire's published source
-- (only to read its messages; none of it is used here):
--   Campfire Assistant (1.05): public chat posts only, each one sent when its
--   player clicks (see "Campfire Assistant" below).
--   Camping Kit (1.5.7, protocol 2): prefix "CampingKit" on channel "CampingKitNet",
--   sent on arriving at a camp, on a change, and every minute while there.
--     F|2|faction (A/H)|layer|continent|worldX|worldY|map|x|y|fire tier (0-3)|full|litAt
--     |object spells|wanted spells|wantedAt|exact|samples   (litAt 0: not known)
--   CozyFire (0.7): prefix "CozyFire" to your guild and your party or raid; no channel.
--     CF1:instance:worldX:worldY:roughPlace:roughTime:secondsLeft:map:layer:placedBy
--     (HereBeDragons' world X and Y: the game's world position the other way round)

local Others = {}
ns.Others = Others

-- channel: the chat channel its messages come on; addon: its folder, so the
-- channel isn't left while you run that addon (it needs it). chatTypes: where
-- its messages come, if not only its channel.
Others.SOURCES = {
    { key = "cozy", name = "CozyFire", prefix = "CozyFire", chatTypes = { GUILD = true, PARTY = true, RAID = true } },
    { key = "kit", name = "Camping Kit", prefix = "CampingKit", channel = "CampingKitNet", addon = "CampingKit" },
}
local byPrefix, byChannel = {}, {}
for _, source in ipairs(Others.SOURCES) do
    byPrefix[source.prefix] = source
    if source.channel then byChannel[source.channel:lower()] = source end
end

-- Whether a source's message came where it sends them (CHAT_MSG_ADDON's chat type).
function Others.Accepts(source, chatType)
    if source.chatTypes then return source.chatTypes[chatType] == true end
    return chatType == "CHANNEL"
end

local allow = ns.FloodLimit(30) -- at most 30 camps a minute from other addons
local allowPost = ns.FloodLimit(10) -- Campfire Assistant's chat posts (see below)
local JOIN_TRIES = 6            -- joins that don't take before giving up (5 seconds apart)
local OURS_FIRST = 2            -- checks their channels wait for ours once they could join

-- Their continents (instance IDs) and the map that shows each.
local CONTINENT_MAPS = { [0] = 1415, [1] = 1414 } -- Eastern Kingdoms, Kalimdor

local KIT_SLOTS = { 3, 5, 10 } -- Camping Kit's fire tiers' sizes
local KIT_FACTIONS = { Alliance = "A", Horde = "H" }

-- Campfire Assistant (1.05) names some objects its own way: [its label,
-- lowercase] = the object's English name here, or the profession (skill line)
-- of one Happy Camper doesn't know (its "Robot Repair Anvil" isn't
-- Blacksmithing's Anvil). Its "Enchanted Focus" and "Lexicon of Power" are no
-- object in Forever, so they're left out. Harmless in any other chat.
Others.ALIASES = {
    ["alchemy lab"] = "Alchemy Laboratory",
    ["skinning chair"] = "Camp Chair",
    ["plague doctor's lab"] = "Plague Doctor's Laboratory",
    ["cookies feast"] = "Cookie's Feast",
    ["robot repair anvil"] = 202, -- Engineering
}

-- A name as whole words ("Loom", not "gloom" or "Anvilmar"). A word's edge is
-- only checked where the name starts or ends with a letter or digit, so
-- Chinese, Korean and accented names still match.
local namePattern = {} -- [lowercase name] = its pattern, made once
local function NamePattern(name)
    local pattern = namePattern[name]
    if not pattern then
        local escaped = name:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0")
        pattern = (name:find("^%w") and "%f[%w]" or "") .. escaped .. (name:find("%w$") and "%f[%W]" or "")
        namePattern[name] = pattern
    end
    return pattern
end

local function NamesObject(text, name)
    return text:find(NamePattern(name)) ~= nil
end

-- Camp objects named in a message ("Mana Well, Lodestone"), in English or the
-- client's language: { [skill line] = highest tier }, and the professions of
-- objects named with no tier known ({ [skill line] = true }); each nil if
-- there are none. Also used for chat posts.
function Others.ObjectsIn(text)
    local found, professions = nil, nil
    if type(text) ~= "string" then return nil end
    local lower = text:lower()
    -- Other addons' own names first, taken out so their words aren't read again.
    for alias, object in pairs(Others.ALIASES) do
        if NamesObject(lower, alias) then
            lower = lower:gsub(NamePattern(alias), " ")
            local _, _, skillLine, tier = ns.ObjectByName(type(object) == "string" and object or nil)
            if skillLine then
                found = found or {}
                found[skillLine] = math.max(found[skillLine] or 0, tier)
            elseif type(object) == "number" then
                professions = professions or {}
                professions[object] = true
            end
        end
    end
    for _, profession in ipairs(ns.PROFESSIONS) do
        for tier, english in pairs(profession.objects or {}) do
            local localName = ns.ObjectName(profession.id, tier)
            if NamesObject(lower, english:lower()) or (localName and NamesObject(lower, localName:lower())) then
                found = found or {}
                found[profession.id] = math.max(found[profession.id] or 0, tier)
            end
        end
    end
    return found, professions
end

-- A world position to a zone map (a city's own, in a city) and 0-1
-- coordinates, or nil.
local function MapFromWorld(continent, wx, wy)
    local top = CONTINENT_MAPS[continent]
    if not top or not C_Map.GetMapInfoAtPosition then return nil end
    local where = CreateVector2D(wx, wy)
    local _, pos = C_Map.GetMapPosFromWorldPos(continent, where, top)
    if not pos then return nil end
    local info = C_Map.GetMapInfoAtPosition(top, ns.XY(pos))
    local mapID = info and info.mapID and ns.ZoneOf(info.mapID, true)
    if not mapID then return nil end
    local _, zone = C_Map.GetMapPosFromWorldPos(continent, where, mapID)
    if not zone then return nil end
    local x, y = ns.XY(zone)
    return mapID, x, y
end

-- Whether a camp is known to be on another layer than one seen on mapID.
-- Each zone (and each city) numbers its layers its own way (Location.lua), so
-- a camp in another zone can't be told apart.
local function OnOtherLayer(camp, layer, mapID)
    return layer ~= nil and camp.layer ~= nil and camp.layer ~= layer
        and ns.ZoneOf(camp.mapID, true) == ns.ZoneOf(mapID, true)
end

-- A real camp and an unconfirmed one (from chat or another addon) near a
-- spot, either nil, found in one pass. With layer, a camp known to be on
-- another layer doesn't count: it's another fire.
local function Nearby(mapID, x, y, layer)
    local continent, wx, wy = ns.Camps.WorldPosition(mapID, x, y)
    if not continent then return end
    local reach, real, unconfirmed = ns.ChatPins.RADIUS ^ 2, nil, nil
    for _, camp in pairs(ns.Camps:All()) do
        if camp.continent == continent and camp.wx then
            local dx, dy = wx - camp.wx, wy - camp.wy
            if dx * dx + dy * dy <= reach and not OnOtherLayer(camp, layer, mapID) then
                if camp.chat then
                    unconfirmed = unconfirmed or camp
                else
                    real = real or camp
                end
            end
        end
    end
    return real, unconfirmed
end

-- Adds a post's objects and fire size to an unconfirmed camp (never one
-- someone with Happy Camper has seen: what's added to it could be sent on).
local function AddTo(camp, info)
    for skillLine, tier in pairs(info.equipment or {}) do ns.Camps:AddEquipment(camp, skillLine, tier) end
    for skillLine in pairs(info.professions or {}) do ns.Camps:AddProfession(camp, skillLine) end
    camp.slots = camp.slots or info.slots
    ns.OnCampsChanged()
    return camp
end

-- Adds (or updates) a camp another addon told us about. info: { slots,
-- equipment = { [skill line] = tier }, professions = { [skill line] = true },
-- placedAt, expiresAt, layer, approximate (said near you: placed where you were),
-- poster (a chat post with a pin: one camp per poster) }.
function Others:AddCamp(source, sender, mapID, x, y, info)
    if not (mapID and x and y) or x <= 0 or x >= 1 or y <= 0 or y >= 1 or not ns.IsOutdoorMap(mapID) then return end
    local real, old = Nearby(mapID, x, y, info.layer)
    -- Someone with Happy Camper has it already (on its layer): theirs is better.
    if real then return end
    -- A camp said near you is only roughly where you were: it never takes over
    -- or moves another camp, and there's one per poster, like a chat post.
    if info.approximate then old = nil end
    -- Only another addon's own camp is taken over. A poster's ("chat:", "near:"
    -- or "ca:<poster>") isn't: their next post would replace this.
    local theirs = old and old.id:find("^addon:") and old
    -- A post with a pin at another addon's camp only adds to it: theirs says more.
    if info.poster and theirs then return AddTo(theirs, info) end
    local id = info.approximate and "near:" .. sender
        or info.poster and "ca:" .. sender
        or theirs and theirs.id
        or format("addon:%d:%d:%d", mapID, math.floor(x * 1000), math.floor(y * 1000))
    -- Their players answer a request with several camps at once, so the limit
    -- is per camp (and 30 new ones a minute overall), not per player.
    if not old and not allow(id, 5) then return end
    -- The same camp heard again keeps its place name: working it out is the slow part.
    local location = old and old.via and old.mapID == mapID and old.x == x and old.y == y and old.location
        or ns.Location:Shared(ns.Location:Describe(mapID, x, y, true))
    -- A chat post, a rough camp or another poster's camp of the same fire: this says more.
    if old and not theirs then ns.Camps:Remove(old.id) end
    -- A poster's new camp replaces their last one, wherever it was.
    if info.approximate or info.poster then ns.Camps:Remove(id) end
    local now = GetServerTime()
    return ns.Camps:Upsert({
        id = id,
        chat = true,
        via = source.name,
        creator = sender,
        mapID = mapID, x = x, y = y,
        location = location,
        placedAt = now, -- when it was heard: unconfirmed camps last ChatPins.LIFETIME from it
        expiresAt = info.expiresAt,
        slots = info.slots,
        layer = info.layer,
        approximate = info.approximate,
        equipment = info.equipment,
        professions = info.professions,
    })
end

-- Camping Kit --------------------------------------------------------------------------
-- A camp a kit user is at (or just built): the fire's world position, its size,
-- and the objects there, by the spells that place them.

function Others:OnKit(source, text, sender)
    local f = { strsplit("|", text) }
    if f[1] ~= "F" or f[2] ~= "2" then return end
    local faction = UnitFactionGroup and UnitFactionGroup("player")
    if f[3] ~= KIT_FACTIONS[faction] then return end
    local continent, wx, wy = tonumber(f[5]), tonumber(f[6]), tonumber(f[7])
    if not (continent and wx and wy) then return end
    local mapID, x, y = MapFromWorld(continent, wx, wy)
    if not mapID then return end
    local layer = tonumber(f[4])
    local info = { slots = KIT_SLOTS[tonumber(f[11]) or 0], layer = layer and layer > 0 and layer or nil }
    local litAt, now = tonumber(f[13]), GetServerTime()
    if litAt and litAt > 0 and litAt <= now + 60 and litAt >= now - ns.db.campDuration then
        info.expiresAt = litAt + ns.db.campDuration
    end
    for id in (f[14] or ""):gmatch("%d+") do
        local _, _, skillLine, tier = ns.ObjectByName(ns.ObjectForSpell(tonumber(id)))
        if skillLine then
            info.equipment = info.equipment or {}
            info.equipment[skillLine] = math.max(info.equipment[skillLine] or 0, tier or 1)
        end
    end
    return self:AddCamp(source, sender, mapID, x, y, info)
end

-- CozyFire ---------------------------------------------------------------------------
-- A fire and its time left: no objects or size.

function Others:OnCozy(source, text, sender)
    local tag, instance, wx, wy, _, _, left, _, layer = strsplit(":", text)
    instance, wx, wy, left = tonumber(instance), tonumber(wx), tonumber(wy), tonumber(left)
    if tag ~= "CF1" or not (instance and wx and wy and left) or left <= 0 or left > ns.db.campDuration then return end
    local mapID, x, y = MapFromWorld(instance, wy, wx)
    if not mapID then return end
    layer = tonumber(layer)
    return self:AddCamp(source, sender, mapID, x, y, {
        expiresAt = GetServerTime() + math.floor(left),
        layer = layer and layer > 0 and layer or nil,
    })
end

-- Campfire Assistant -----------------------------------------------------------------
-- It posts only in public chat, one post per click of its button (nothing
-- hidden to listen to): the objects its player hovered lately, each its label
-- and effect, joined by "  •  ", after how many of the fire's slots they take.
--   Say:     Campsite Bonuses: (2/3 Slots) Lodestone (+AP)  •  Fish Bowl (+8% All Stats)
--   General: Camp buffs (2/3 Slots) at <the game's map pin>: Lodestone (+AP)  •  ...
--            Camp buffs (2/3 Slots) at my location: ...    (no pin: where isn't known)
--   Say, not in General: Camp buffs (General Muted) (2/3 Slots) : ...
-- A pinned post goes at its pin, one camp per poster. Say is only heard nearby
-- (and on your layer), so a post in Say is about a camp near you.

Others.CAMPFIRE_ASSISTANT = { key = "campfireassistant", name = "Campfire Assistant" }

-- Which of its posts a chat line is: "say", "pin", "location", or nil.
function Others.CampfireAssistantKind(text)
    if type(text) ~= "string" then return nil end
    if text:find("^Campsite Bonuses: %(%d+/%d+ Slots%)") or text:find("^Camp buffs %(General Muted%) %(%d+/%d+ Slots%)") then
        return "say"
    end
    if text:find("^Camp buffs %(%d+/%d+ Slots%) at my location: ") then return "location" end
    if text:find("^Camp buffs %(%d+/%d+ Slots%) at .-|Hworldmap:%d+:%d+:%d+[:|]") then return "pin" end
end

-- The camp nearest a world position (on mapID) within radius yards, of any
-- kind, not one known to be on another layer.
local function NearestCamp(mapID, continent, wx, wy, radius, layer)
    local best, bestDistance
    for _, camp in pairs(ns.Camps:All()) do
        local distance = ns.Camps.WorldDistance(camp, continent, wx, wy)
        if distance and distance <= radius and (not bestDistance or distance < bestDistance)
            and not OnOtherLayer(camp, layer, mapID) then
            best, bestDistance = camp, distance
        end
    end
    return best
end

-- A camp said to be near you (no pin): its objects and size go to the camp
-- you're at or one near you if it's unconfirmed. One someone with Happy Camper
-- has seen (yours too) is left as it is: their Camp Benefits say better, and
-- it's shared. With none, a camp goes where you're standing, approximate.
function Others:AddNearYou(source, sender, info)
    local mapID, x, y = ns.GetPlayerLocation()
    if not mapID or not ns.IsOutdoorMap(mapID) then return end
    local layer = ns.SettledLayer()
    local continent, wx, wy = ns.Camps.WorldPosition(mapID, x, y)
    local camp = ns.Social:MyCamp() or continent and NearestCamp(mapID, continent, wx, wy, ns.ChatPins.RADIUS, layer)
    if not camp then
        info.layer, info.approximate = layer, true
        return self:AddCamp(source, sender, mapID, x, y, info)
    end
    if camp.chat then return AddTo(camp, info) end
end

-- One chat line that may be Campfire Assistant's (event: the chat event it
-- came in). Returns the camp it added or changed, if any. Nothing is sent.
function Others:OnCampfireAssistant(text, sender, event)
    if not ns.db.otherAddons or type(text) ~= "string" or type(sender) ~= "string"
        or ns.IsSecret(text) or ns.IsSecret(sender) or sender == "" or #text > 255 then return end
    local kind = Others.CampfireAssistantKind(text)
    -- "At my location" in General says nowhere; only Say is heard nearby.
    if not kind or kind == "location" or kind == "say" and event ~= "CHAT_MSG_SAY" then return end
    sender = ns.SenderName(sender)
    if sender == ns.playerName or ns.IsBlocked(sender) then return end
    local source = Others.CAMPFIRE_ASSISTANT
    if ns.Comm:IsRepeat(sender, source.key .. text) then return end
    -- A post takes a click: one every 5 seconds from a player, 10 a minute in all.
    if not allowPost(sender, 5) then return end
    -- The fire's size (3, 5 or 10) and its objects, by name or its own labels.
    local slots = tonumber(text:match("%(%d+/(%d+) Slots%)"))
    local info = { slots = (slots == 3 or slots == 5 or slots == 10) and slots or nil }
    info.equipment, info.professions = Others.ObjectsIn((text:gsub("|H.-|h.-|h", " ")))
    if kind == "say" then return self:AddNearYou(source, sender, info) end
    -- One camp per poster, like a chat post: their next post replaces it.
    info.poster = true
    local mapID, px, py = text:match("|Hworldmap:(%d+):(%d+):(%d+)[:|]")
    return self:AddCamp(source, sender, tonumber(mapID), tonumber(px) / 10000, tonumber(py) / 10000, info)
end

-- Listening ----------------------------------------------------------------------------

-- One message from another addon.
function Others:OnMessage(source, text, sender)
    if not ns.db.otherAddons or type(text) ~= "string" or type(sender) ~= "string"
        or ns.IsSecret(text) or ns.IsSecret(sender) or sender == "" or #text > 255 then return end
    sender = ns.SenderName(sender)
    if sender == ns.playerName or ns.IsBlocked(sender) then return end
    if ns.Comm:IsRepeat(sender, source.key .. text) then return end
    if source.key == "cozy" then return self:OnCozy(source, text, sender) end
    return self:OnKit(source, text, sender)
end

-- Your number for a channel, or nil if you're not in it.
local function ChannelID(name)
    local id = GetChannelName(name)
    return type(id) == "number" and id > 0 and id or nil
end

-- Joins their channels, checking every 5 seconds until they're in. They wait
-- for General as the camp channel does (Comm.MayJoin: in an instance until
-- you're out), then a little for the camp channel, so it keeps the lower
-- number. A channel that still isn't in after JOIN_TRIES joins (some clients
-- only allow it from a click) is joined when the option is ticked. Their
-- channels are left in the chat windows; chat filters hide their lines (Init).
-- Nothing joins once the game has blocked an action (ns.Comm.paused), nor with
-- their channels' option off (otherChannels).
local checking -- the check running now: { attempt, joins, held }, or nil

local function Check()
    local run = checking
    if not run then return end
    if ns.Comm.paused or not ns.db.otherAddons or not ns.db.otherChannels then
        checking = nil
        return
    end
    local mayJoin = ns.Comm.MayJoin(run.attempt)
    if mayJoin and ns.db.network and not ns.Comm:IsConnected() and run.held < OURS_FIRST then
        mayJoin, run.held = false, run.held + 1
    end
    local waiting, tried = false, false
    for _, source in ipairs(Others.SOURCES) do
        if source.channel and not ChannelID(source.channel) then
            waiting = true
            -- (The game may have blocked the last join: then no more.)
            if mayJoin and not ns.Comm.paused then
                JoinTemporaryChannel(source.channel)
                tried = true
            end
        end
    end
    if tried then run.joins = run.joins + 1 end
    if waiting and run.joins < JOIN_TRIES and not ns.Comm.paused then
        run.attempt = run.attempt + 1
        C_Timer.After(5, Check)
    else
        checking = nil
    end
end

-- One check at a time: ticking the option while one runs gives it a fresh set
-- of joins rather than starting a second.
function Others:Connect()
    if ns.Comm.paused then return end
    if checking then
        checking.joins = 0
        return
    end
    checking = { attempt = 1, joins = 0, held = 0 }
    Check()
end

-- Whether you run a source's own addon, which needs its channel.
local function ItsAddonRuns(source)
    local loaded = C_AddOns and C_AddOns.IsAddOnLoaded or IsAddOnLoaded
    return source.addon ~= nil and type(loaded) == "function" and loaded(source.addon) == true
end

-- Leaves their channels, but not one an addon you run uses. Once the game has
-- blocked an action, the channels stay as they are.
function Others:LeaveChannels()
    if ns.Comm.paused then return end
    for _, source in ipairs(self.SOURCES) do
        if source.channel and ChannelID(source.channel) and not ItsAddonRuns(source) then
            LeaveChannelByName(source.channel)
        end
    end
end

-- Their channels' option (otherChannels): joined, or left. Their camps stay
-- either way, and any still heard (on a channel their own addon keeps you in,
-- or from guild, group and chat) keep coming.
function Others:SetChannels(on)
    if on then self:Connect() else self:LeaveChannels() end
end

-- Leaves their channels and drops their camps (the option turned off).
function Others:Disconnect()
    self:LeaveChannels()
    for id, camp in pairs(ns.Camps:All()) do
        if camp.via then ns.Camps:Remove(id) end
    end
    ns.OnCampsChanged()
end

-- Their channels' lines stay out of chat: messages, notices, joins and leaves.
local function IsTheirChannel(...)
    local name = select(9, ...)
    return type(name) == "string" and byChannel[name:lower()] ~= nil
end

function Others:Init()
    for prefix in pairs(byPrefix) do C_ChatInfo.RegisterAddonMessagePrefix(prefix) end
    local addFilter = ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter
    if not addFilter then return end
    for _, event in ipairs({ "CHAT_MSG_CHANNEL", "CHAT_MSG_CHANNEL_NOTICE",
        "CHAT_MSG_CHANNEL_NOTICE_USER", "CHAT_MSG_CHANNEL_JOIN", "CHAT_MSG_CHANNEL_LEAVE" }) do
        addFilter(event, function(_, _, ...) return IsTheirChannel(...) end)
    end
end

local events = CreateFrame("Frame")
events:RegisterEvent("CHAT_MSG_ADDON")
events:SetScript("OnEvent", function(_, _, prefix, text, chatType, sender)
    if not ns.db or not ns.realm then return end -- not before login (PLAYER_LOGIN sets ns.realm)
    local source = byPrefix[prefix]
    if source and Others.Accepts(source, chatType) and Others:OnMessage(source, text, sender) then
        ns.OnCampsChanged()
    end
end)
