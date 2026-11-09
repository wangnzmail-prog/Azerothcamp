-- Happy Camper. Copyright (c) 2026 Torridon. All rights reserved; see LICENSE.
local addonName, ns = ...
local L = ns.L

-- Camp network: addon messages over a hidden custom chat channel, so every
-- player running the addon sees camps from everyone else on the realm.
--
-- Messages (fields separated by ";", lists by ","):
--   S;id;mapID;x;y;expires;owned;objects;professions;equipment;layer;faction;slots;p;nameKey;areaID;direction;region
--                                                camp snapshot (creator only); layer is
--                                                the zone UID (see Location.lua), faction
--                                                A or H, slots 3, 5 or 10 (blank if unknown);
--                                                "p" (0.8.5): only seen in passing, roughly
--                                                placed (older versions stop before it and
--                                                take it as a report). The camp's name and
--                                                location (0.8.7), as N has them, when they
--                                                fit (p is then blank if not passing)
--   N;id;nameKey;areaID;direction;region         camp name and location (creator only); the
--                                                area goes as the game's area ID, never as text.
--                                                From 0.8.7 S carries them too, so N goes only
--                                                when a camp is first sent or renamed, for
--                                                versions before it
--   O;id;spellID;skillLine                       an object was placed at a camp
--   E;id;skillLine.tier,...                      all the objects in a Camp Benefits tooltip
--                                                (anything not listed has gone; an empty
--                                                list: no Camp Benefits at all any more)
--   X;id                                         camp is gone (creator only)
--   R;id;mapID;x;y;expires;skillLines;faction;minTiers;brings;buffs;classWants
--                                                Camp Builder request (creator only);
--                                                skillLines the camp objects wanted,
--                                                minTiers and brings (camp objects) are
--                                                skillLine.tier lists, buffs the skillLines
--                                                the requester's class buffs cover,
--                                                classWants the skillLines wanted as a
--                                                class buff (no fire slot; not in
--                                                skillLines, so older versions never see
--                                                them, and drop a request wanting only
--                                                class buffs). From 0.8.5 classWants is
--                                                always there, if empty: it says the
--                                                requester takes class-buff sign-ups.
--                                                (0.7.0-0.8.1 stop at faction, 0.8.2-0.8.4
--                                                at buffs)
--   J;id;skillLine;tier;buffs                    sender signs up to bring a profession's
--                                                object of that tier (no tier: older
--                                                version), and to give the class buffs
--                                                listed (skillLines; left out if none;
--                                                a paladin: one blessing). skillLine 0:
--                                                class buffs only, no object (older
--                                                versions ignore it: they want no 0)
--   L;id                                         sender withdraws from a request
--   C;id                                         request closed (creator only)
--   Q;version;users;nonce                        ask everyone to resend their camps,
--                                                requests and sign-ups; also says the
--                                                sender's version and how many users
--                                                they know of (Stats.lua)
--   P;hello;campID;class;level;skill:rank,...;i  "I'm at this camp" (presence; no position).
--                                                A last field "i" (0.8.6): the sender takes
--                                                layer invite requests (LayerInvites.lua);
--                                                left out with that option off. Older
--                                                versions stop before it
--   Z                                            sender left their camp
--   U;campID;song;n                              a song (or an emote's sound, or "stop") at that
--                                                camp; only players at it play it (Music.lua).
--                                                At a bare fire (not a camp) campID is
--                                                "@mapID:x:y", and players near it play it
--   VQ;version;notFrom                           "what's the latest version?": a release copy's
--                                                question, with its version (at login and every
--                                                few hours); notFrom: a player who already
--                                                answered, so someone else does (Stats.lua)
--   VA;version                                   the answer: a copy newer than the asker's, one
--                                                answer per question (Stats.lua)
--   B;id;ends;key;text;arg;...                   an announcement from one of the developer's
--                                                characters (Broadcast.lua): id "Sender:sentAt",
--                                                ends a server time, key a prepared message every
--                                                copy shows in its own language with up to 3
--                                                arguments (blank key: free text), text the
--                                                English, shown when the key is blank or unknown.
--                                                Text and arguments escape "%", ";", "|" and
--                                                control characters as %XX. Sent again now and
--                                                then until it ends; each is shown once.
--   ZQ;zoneMapID;faction;w                       "which camps are burning here?" (0.8.6): sent by
--                                                itself once on the camp channel at login, and
--                                                after 5 seconds in a zone you enter; each zone at
--                                                most once every 10 minutes. zoneMapID as ns.ZoneOf
--                                                gives it (a capital is its zone's), faction A or H.
--                                                Only players in that zone and of that faction answer,
--                                                and in a busy zone only a few of them, by chance.
--                                                "w" (0.8.7): answer by whisper to the asker, not on
--                                                the channel (older askers take answers only there)
--   ZA;id;mapID;x;y;left;owned;objects;professions;equipment;layer;faction;slots;nameKey;areaID;direction;region;p
--                                                the answer (0.8.6): one camp the answerer knows in
--                                                that zone, whoever reported it (its reporter may
--                                                have logged off), with the fields S and N carry, but
--                                                left, the seconds its fire has left, in place of
--                                                expires, so clocks needn't agree. Camps with at
--                                                least a minute left, not from chat; a last p (after
--                                                0.8.6; the name fields blank if they're left out)
--                                                marks one seen in passing. Answers wait a
--                                                moment, and skip camps someone else has answered
--                                                since the ask, so each goes about once. Taken only
--                                                for a zone you've just asked about, and only to add
--                                                a camp you don't know: never changing one you do
--                                                (the last four fields can be left out)
-- Versions before 0.8.5 ignore VQ, VA and B, and before 0.8.6 ZQ and ZA, as
-- every version ignores kinds it doesn't know. ZA comes by whisper too (0.8.7),
-- to an asker who said "w".
-- Group planning (Group.lua) goes over the party or raid addon channel instead,
-- even with the camp network off:
--   G;skill:rank,...;object;readyAt;placedSkill;placedAt;kit;placedTier;blessing;recipes;carried;benefits
--                                                your status: professions, the camp object
--                                                in your bags (skillLine.tier), when you can
--                                                place one again, what you placed last, when
--                                                and its tier, your best kit's size (0 = none),
--                                                the blessing you keep up (a skillLine, 0
--                                                = none), the best tier you can make and every
--                                                camp object you carry (skillLine.tier lists),
--                                                and when your Camp Benefits ends (server time,
--                                                0 = none; older versions stop at kit, blessing,
--                                                recipes or carried)
--   GQ                                           ask the group for their status
--   GA;skillLine;name                            the leader asks name to place that
--                                                buff's object (no name = nobody)
--   GB;skillLine;name                            the leader asks a paladin to keep up that
--                                                blessing (0 = none)
-- Feedback reports to the developer (F) and receipts (K) go by whisper instead
-- (Feedback.lua), and so does one more (0.8.6; older versions ignore whispers
-- but F and K):
--   LJ;campID                                    "invite me to your layer": to a player
--                                                at that camp who said "i" in their
--                                                presence; they're asked first, and only
--                                                a click on Invite invites (LayerInvites.lua)
-- x and y are sent as integers 0-10000; expires is a server time, 0 if unknown.
-- Fields added later go at the end, so older versions just ignore them.

local Comm = {}
ns.Comm = Comm

local PREFIX = "HappyCamper"
-- The camp channel, then backups for a realm where it's been locked (someone
-- joined it before anyone with the addon and set a password, or banned
-- players). Every copy tries them in this order, so they all end up together.
local CHANNELS = { "HappyCamper", "HappyCamperB", "HappyCamperC", "HappyCamperD", "HappyCamperE" }
local current = 1       -- the channel you're in (or joining)
local bridges = {}      -- [index] = true: backups you're also in, for players locked out of yours
local SEND_INTERVAL = 1       -- seconds between messages, well under Blizzard's throttle
-- Replies to queries go to everyone, so one serves all recent queries. On a
-- quiet realm a reply goes within QUERY_REPLY_COOLDOWN seconds of the last; the
-- more often queries come (players logging in), the longer replies wait, up
-- to QUERY_REPLY_MOST: on a busy realm every camp's creator would otherwise
-- send all their camps every half a minute.
local QUERY_REPLY_COOLDOWN = 30
local QUERY_REPLY_MOST = 600 -- (a player's own zone's camps come at once anyway: zone asks, below)
local QUERY_RATE_SPAN = 300          -- seconds: queries heard over about this long set the wait
local QUERY_SENDER_COOLDOWN = 120    -- each player's queries are answered at most this often
local RETRY_RESULTS = { [3] = true, [8] = true, [11] = true } -- throttled or locked down
local MAX_RETRIES = 5
local MAX_MESSAGE = 255 -- bytes: the most an addon message can hold

local queue = {}
local ticker
local restTicks = 0 -- ticks to wait before the next message (one went to several channels)
local channelGaveUp = false -- no camp channel could be joined this session (UseBackup)
local lastQueryReply        -- when your last reply to a query went out (nil: none yet)
local replyPending = false  -- a reply is waiting to go out
local queryRate, queryRateAt = 0, nil -- queries heard lately (fading over QUERY_RATE_SPAN), and when it was last counted
local replyFor              -- when the first query the waiting reply answers came
local oldAsker = false      -- a query from a version before 0.8.7 came since the last reply (it needs N)
local sentAt = {}           -- [camp or request ID] = when its snapshot or request last went out (GetTime)
-- Players Happy Camper whispered lately ([name] = when): if one has logged off,
-- the game's "No player named ... is currently playing" for them is hidden.
local whispered = {}
local WHISPERED_FOR = 120
local lastQueryFrom = {}
local queryNonce = tostring(math.random(100000, 999999)) -- recognises your own query coming back
local adoptedName = false   -- your name was confirmed or corrected by your own query (once a session)
-- The game can switch the camp channel off: it stays in your channel list,
-- marked disabled, and every message to it is refused (InvalidChannel), as
-- for hours after Forever's launch, for every camping addon at once. That's
-- the server's doing, so nothing moves to a backup channel: CheckChannelOff
-- looks every OFF_CHECK seconds, asks to join again every OFF_REJOIN seconds
-- while it's off, and once it's back asks for camps again, as at login.
local OFF_CHECK = 15
local OFF_REJOIN = 120
local INVALID_HOLD = 120 -- seconds a refused message counts as the channel being off
local INVALID_CHANNEL = Enum and Enum.SendAddonMessageResult and Enum.SendAddonMessageResult.InvalidChannel or 7
local channelOff = false  -- the game has the camp channel switched off
local invalidAt           -- when a message to it was last refused as InvalidChannel (GetTime)
local lastRejoin = 0      -- when a join was last asked for while it was off

local function ChannelID(index)
    local id = GetChannelName(CHANNELS[index or current])
    return id and id > 0 and id or nil
end

-- Whether the game lists a camp channel as disabled (switched off: channelOff).
local function ChannelDisabled(index)
    local name, list = CHANNELS[index or current]:lower(), { GetChannelList() }
    for i = 1, #list, 3 do
        local listed = list[i + 1]
        if type(listed) == "string" and not ns.IsSecret(listed) and listed:lower() == name then return list[i + 2] == true end
    end
    return false
end

-- The numbers of every camp channel you're in: yours, and any you bridge to.
local function JoinedChannels()
    local ids = {}
    for index = 1, #CHANNELS do
        if (index == current or bridges[index]) and ChannelID(index) then ids[#ids + 1] = ChannelID(index) end
    end
    return ids
end

function Comm:IsConnected()
    return ns.db.network and ChannelID() ~= nil and not channelOff
end

-- Whether the game has switched the camp channel off (channelOff).
function Comm:IsChannelOff()
    return channelOff
end

-- Sending -----------------------------------------------------------------------

-- The dev tools' network monitor (HappyCamper_Dev) sets Comm.OnSendResult and
-- Comm.OnSendDropped to hear how each message went; without it, nothing happens.
local function Dropped(message, chatType, target, why)
    if Comm.OnSendDropped then Comm.OnSendDropped(message, chatType, target, why) end
end

-- Drops the camp messages waiting to go (the network turned off, or no camp
-- channel can be joined); party, raid and whisper ones stay.
local function DropChannelMessages(why)
    for i = #queue, 1, -1 do
        if queue[i].chatType == "CHANNEL" then Dropped(table.remove(queue, i).message, "CHANNEL", nil, why) end
    end
end

-- Channel work is paused (Comm.paused, at the end) and you're in no camp
-- channel: none will be joined this session, so camp messages don't wait for
-- one. (Checked as they go: a join the game was still answering when it
-- paused may yet come through, or a kick may leave you in none.)
local function PausedWithoutChannel()
    return Comm.paused and not JoinedChannels()[1]
end

-- The next message to send: the first that can go now, but a low one (zone
-- answers, feedback reports) only when nothing else is waiting. Camp
-- messages can't go until you're in a camp channel: they wait, in order,
-- and party, raid and whisper messages behind them go on ahead.
local function NextIndex(inChannel)
    local firstLow
    for index, item in ipairs(queue) do
        if inChannel or item.chatType ~= "CHANNEL" then
            if not item.low then return index end
            firstLow = firstLow or index
        end
    end
    return firstLow
end

local function ProcessQueue()
    if not queue[1] then
        ticker:Cancel()
        ticker = nil
        return
    end
    -- The last message went to several channels: one tick for each.
    if restTicks > 0 then
        restTicks = restTicks - 1
        return
    end
    if C_ChatInfo.InChatMessagingLockdown and C_ChatInfo.InChatMessagingLockdown() then
        return -- try again next tick
    end
    -- Camp messages go to your camp channel, and any backup you bridge to.
    local channels = JoinedChannels()
    if #channels == 0 and Comm.paused then DropChannelMessages("channel work paused") end
    -- A message made as it goes (zone answers): made again now, or dropped if
    -- it's no longer wanted.
    local index, item
    repeat
        index = NextIndex(#channels > 0)
        if not index then return end
        item = queue[index]
        if item.make then
            local message = item.make()
            if message and #message <= MAX_MESSAGE then
                item.message, item.make = message, nil
            else
                Dropped(table.remove(queue, index).message, item.chatType, item.target, "no longer wanted")
                item = nil
            end
        end
    until item
    local chatType, target = item.chatType, item.target
    if item.group then
        -- Your party or raid as it is now: it may have become a raid since.
        chatType = Comm:GroupChatType()
        if not chatType then
            table.remove(queue, index) -- you've left the group
            Dropped(item.message, item.chatType, target, "left the group")
            return
        end
    end
    -- Each channel is tried until the game takes the message there (or says
    -- it never will): a retry goes only to the channels that were throttled.
    local results, failed = {}, false
    if chatType == "CHANNEL" then
        item.sentTo = item.sentTo or {}
        for _, channel in ipairs(channels) do
            if not item.sentTo[channel] then
                local result = C_ChatInfo.SendAddonMessage(PREFIX, item.message, chatType, tostring(channel))
                if result == INVALID_CHANNEL and channel == ChannelID() then invalidAt = GetTime() end
                results[#results + 1] = { tostring(channel), result }
                if result and result ~= 0 and RETRY_RESULTS[result] then failed = true else item.sentTo[channel] = true end
            end
        end
    else
        local result = C_ChatInfo.SendAddonMessage(PREFIX, item.message, chatType, target)
        results[1] = { target, result }
        if chatType == "WHISPER" and type(target) == "string" then whispered[target] = GetTime() end
        failed = result and result ~= 0 and RETRY_RESULTS[result] and true or false
    end
    local retry = failed and item.tries < MAX_RETRIES
    if Comm.OnSendResult then
        for _, sent in ipairs(results) do
            Comm.OnSendResult(item.message, chatType, sent[1], sent[2], item.tries, retry and true or false)
        end
    end
    restTicks = math.max(0, #results - 1)
    if retry then
        item.tries = item.tries + 1
        return
    end
    table.remove(queue, index)
end

-- A newer message with the same key replaces a queued one (e.g. snapshots).
-- Messages go to the hidden channel unless a whisper target is given; group:
-- to your party or raid, whichever you're in when it goes. make: a function
-- that makes the message again just as it goes (or returns nil if it's no
-- longer wanted); message is what it made now. low: it waits while anything
-- else is waiting (NextIndex).
local function Send(message, key, target, chatType, group, make, low)
    chatType = chatType or (target and "WHISPER" or "CHANNEL")
    if chatType == "CHANNEL" and (not ns.db.network or channelGaveUp) then
        return Dropped(message, chatType, target, ns.db.network and "no camp channel" or "network off")
    end
    if chatType == "CHANNEL" and PausedWithoutChannel() then return Dropped(message, chatType, target, "channel work paused") end
    if chatType == "CHANNEL" and channelOff then return Dropped(message, chatType, target, "camp channel off") end
    -- Test camps and pretend requests (dev tools' /hc test and /hc fakerequest)
    -- and the guide's demo camp are only on your screen: nothing about them is sent.
    if message:find(";HCTest:", 1, true) then return Dropped(message, chatType, target, "test camp") end
    if #message > MAX_MESSAGE then return Dropped(message, chatType, target, "too long") end -- it could never be sent
    if key then
        for _, item in ipairs(queue) do
            if item.key == key then
                item.message, item.chatType, item.target, item.group, item.make = message, chatType, target, group, make
                item.low, item.sentTo = low, nil
                return
            end
        end
    end
    queue[#queue + 1] = { message = message, key = key, tries = 0, chatType = chatType, target = target, group = group,
        make = make, low = low }
    if not ticker then ticker = C_Timer.NewTicker(SEND_INTERVAL, ProcessQueue) end
end

-- A whisper to one player (feedback reports and receipts), even with the camp
-- network turned off. low: it waits while other messages go (a long report's parts).
function Comm:SendWhisper(message, target, low)
    Send(message, nil, target, nil, nil, nil, low)
end

-- The party or raid addon channel you'd plan a camp on, or nil if you're not in a group.
local GROUP_TYPES = { PARTY = true, RAID = true }
function Comm:GroupChatType()
    if IsInRaid() then return "RAID" end
    if IsInGroup() then return "PARTY" end
end

-- A message to your party or raid (group planning).
function Comm:SendGroup(message, key)
    local chatType = self:GroupChatType()
    if chatType then Send(message, key, nil, chatType, true) end
end

-- Presence replaces one still waiting (only the latest counts), but a hello
-- waiting to go stays a hello: a heartbeat for the same camp mustn't lose it.
function Comm:SendPresence(message)
    for _, item in ipairs(queue) do
        if item.key == "P" and item.message:sub(1, 4) == "P;1;" and message:sub(1, 4) == "P;0;"
            and item.message:match("^P;1;([^;]+)") == message:match("^P;0;([^;]+)") then
            message = "P;1;" .. message:sub(5)
        end
    end
    Send(message, "P")
end

-- 0-1 map coordinates travel as integers 0-10000.
local function Coord(v)
    return math.floor(v * 10000 + 0.5)
end

local function EncodeIDs(set)
    local ids = {}
    for spellID in pairs(set) do ids[#ids + 1] = spellID end
    return table.concat(ids, ",")
end

-- "164.1,197.2": profession and object tier.
local function EncodeEquipment(equipment)
    local parts = {}
    for skillLine, tier in pairs(equipment or {}) do parts[#parts + 1] = skillLine .. "." .. tier end
    return table.concat(parts, ",")
end

local function ParseEquipment(text)
    local equipment = {}
    for skillLine, tier in (text or ""):gmatch("(%d+)%.(%d)") do
        skillLine, tier = tonumber(skillLine), tonumber(tier)
        local profession = ns.PROFESSION_BY_ID[skillLine]
        if profession and profession.objects[tier] then equipment[skillLine] = tier end
    end
    return equipment
end

-- "A" or "H" for Alliance or Horde.
local function FactionCode(faction)
    return faction and faction:sub(1, 1) or ""
end

local function Field(text)
    return (ns.CleanText(text) or ""):sub(1, 40)
end

-- A camp's name and location as message fields: nameKey;areaID;direction;region.
local function NameFields(camp)
    local location = camp.location
    return format("%s;%s;%s;%s", camp.nameKey or "", location.areaID or "", Field(location.direction), Field(location.region))
end

-- withName: the name and location go too (if the camp has them).
local function Snapshot(camp, objects, professions, withName)
    local message = format("S;%s;%d;%d;%d;%d;%d;%s;%s;%s;%s;%s;%s", camp.id, camp.mapID, Coord(camp.x), Coord(camp.y),
        camp.expiresAt or 0, camp.owned and 1 or 0,
        EncodeIDs(objects), EncodeIDs(professions), EncodeEquipment(camp.equipment),
        camp.layer or "", FactionCode(camp.faction), camp.slots or "")
    if withName and camp.location then
        message = message .. ";" .. (camp.passing and "p" or "") .. ";" .. NameFields(camp)
    elseif camp.passing then
        message = message .. ";p"
    end
    return message
end

-- An object's tier (1 if unknown).
local function ObjectTier(spellID)
    local key = ns.ObjectInfo(spellID)
    return key and select(4, ns.ObjectByName(key)) or 1
end

-- How well a camp's object can be left out of a snapshot: 2 if a better one of
-- its profession is there (in Camp Benefits or placed), 1 if Camp Benefits
-- shows it, 0 if receivers would miss it.
local function Redundancy(camp, spellID)
    local _, _, skillLine = ns.ObjectInfo(spellID)
    if not skillLine then return 0 end
    local tier, shown = ObjectTier(spellID), (camp.equipment or {})[skillLine] or 0
    if shown > tier then return 2 end
    for other in pairs(camp.objects) do
        local _, _, otherSkill = ns.ObjectInfo(other)
        if other ~= spellID and otherSkill == skillLine and ObjectTier(other) > tier then return 2 end
    end
    return shown == tier and 1 or 0
end

-- A camp's details in one message, made by build(objects, professions).
-- Receivers (every version) work out a camp's professions from its objects
-- and Camp Benefits, so only the others go. A full camp can still be too long
-- for one message: then objects they'd show anyway are left out.
local function FitCamp(camp, build)
    local objects, professions = {}, {}
    for skillLine in pairs(camp.professions) do professions[skillLine] = true end
    for skillLine in pairs(camp.equipment or {}) do professions[skillLine] = nil end
    for spellID in pairs(camp.objects) do
        objects[spellID] = true
        local _, _, skillLine = ns.ObjectInfo(spellID)
        if skillLine then professions[skillLine] = nil end
    end
    local message = build(objects, professions)
    for level = 2, 1, -1 do
        for spellID in pairs(camp.objects) do
            if #message <= MAX_MESSAGE then break end
            if objects[spellID] and Redundancy(camp, spellID) >= level then
                objects[spellID] = nil
                message = build(objects, professions)
            end
        end
    end
    return message
end

function Comm:SendSnapshot(camp, forOld)
    if camp.chat then return end -- camps posted in chat stay yours alone
    if camp.expiresAt and camp.expiresAt <= GetServerTime() then return end -- its fire is out
    local withName = true
    local message = FitCamp(camp, function(objects, professions) return Snapshot(camp, objects, professions, true) end)
    if #message > MAX_MESSAGE then
        withName = false
        message = FitCamp(camp, function(objects, professions) return Snapshot(camp, objects, professions) end)
    end
    Send(message, "S" .. camp.id)
    sentAt[camp.id] = GetTime()
    -- Versions before 0.8.7 take the name only from N: it goes when the camp
    -- is first sent or renamed (not with every snapshot sent again), when it
    -- didn't fit in this one, or (forOld) in a reply to one of those versions.
    if camp.location and (forOld or not withName or camp.nameSent ~= NameFields(camp)) then self:SendName(camp) end
end

-- The name travels as a key (see Names.lua) plus the location parts it's built from.
function Comm:SendName(camp)
    if not camp.location then return end
    camp.nameSent = NameFields(camp)
    Send(format("N;%s;%s", camp.id, camp.nameSent), "N" .. camp.id)
end

-- Objects at someone else's camp: taken only from players known to be there,
-- so your presence goes first if it's been a while (Social:Remind).
function Comm:SendEquipment(campID, equipment)
    ns.Social:Remind(campID)
    Send(format("E;%s;%s", campID, EncodeEquipment(equipment)), "E" .. campID)
end

function Comm:SendObject(campID, spellID, skillLine)
    ns.Social:Remind(campID)
    Send(format("O;%s;%d;%d", campID, spellID, skillLine or 0))
end

function Comm:SendRemove(campID)
    Send("X;" .. campID, "S" .. campID)
end

-- [skillLine] = tier, as "164.2,171.3".
-- Tiers by profession as "164.2,186.3" (requests here, Group.lua's status).
local function EncodeTiers(tiers)
    local parts = {}
    for skillLine, tier in pairs(tiers or {}) do parts[#parts + 1] = skillLine .. "." .. tier end
    table.sort(parts)
    return table.concat(parts, ",")
end
ns.EncodeTiers = EncodeTiers

local function ParseTiers(text)
    local tiers = {}
    for skillLine, tier in (text or ""):gmatch("(%d+)%.(%d)") do
        skillLine, tier = tonumber(skillLine), tonumber(tier)
        if ns.PROFESSION_BY_ID[skillLine] and tier >= 1 and tier <= 3 then tiers[skillLine] = tier end
    end
    return tiers
end

function Comm:SendRequest(request)
    -- Objects and class buffs wanted go in fields of their own (see the top).
    local classWants, objects = request.classWants or {}, {}
    for skillLine in pairs(request.wants) do
        if not classWants[skillLine] then objects[skillLine] = true end
    end
    Send(format("R;%s;%d;%d;%d;%d;%s;%s;%s;%s;%s;%s", request.id, request.mapID, Coord(request.x), Coord(request.y),
        request.expiresAt, EncodeIDs(objects), FactionCode(UnitFactionGroup("player")),
        EncodeTiers(request.minTier), EncodeTiers(request.brings), EncodeIDs(request.buffs or {}),
        EncodeIDs(classWants)), "R" .. request.id)
    sentAt[request.id] = GetTime()
end

-- skillLine 0 (or nil): no object, class buffs only.
function Comm:SendJoin(requestID, skillLine, tier, buffs)
    local message = format("J;%s;%d;%d", requestID, skillLine or 0, tier or 0)
    if buffs and next(buffs) then message = message .. ";" .. EncodeIDs(buffs) end
    Send(message, "J" .. requestID)
end

function Comm:SendLeave(requestID)
    Send("L;" .. requestID, "J" .. requestID)
end

function Comm:SendClose(requestID)
    Send("C;" .. requestID, "R" .. requestID)
end

function Comm:SendMusic(campID, key, index)
    Send(format("U;%s;%s;%d", campID, key, index))
end

function Comm:SendQuery()
    Send(format("Q;%s;%d;%s", ns.Stats:Version(), ns.Stats:Counts().total, queryNonce), "Q")
end

-- "What's the latest version?" and its answer (Stats.lua).
function Comm:SendVersionQuestion(version, notFrom)
    Send(format("VQ;%s;%s", version, notFrom or ""), "VQ")
end

function Comm:SendVersionAnswer(version)
    Send("VA;" .. version, "VA")
end

-- A developer's announcement (Broadcast.lua; sent from the dev tools). Sent
-- again, it replaces the same one still waiting to go.
function Comm:SendBroadcast(broadcast)
    Send(ns.Broadcast:Message(broadcast), "B" .. broadcast.id)
end

-- Receiving ---------------------------------------------------------------------
-- Everything received is untrusted: fields are validated, and only a camp's
-- creator can move it, change its expiry or remove it.

-- A whole number from a message, in range, or nil.
local function Integer(text, low, high)
    local n = tonumber(text)
    return n and n == math.floor(n) and n >= low and n <= high and n or nil
end

-- A set of IDs from a message ("1,2,3"): in range, and only those keep(id)
-- accepts if it's given (e.g. only known campsite objects).
local function ParseIDs(text, keep)
    local ids = {}
    for id in (text or ""):gmatch("%d+") do
        id = Integer(id, 1, 9999999)
        if id and (not keep or keep(id)) then ids[id] = true end
    end
    return ids
end

local function CreatorOf(campID)
    return campID:match("^(.+):%d+$")
end

-- A map point and expiry from a message: numbers, on a real map, 0-10000.
local function ParsePoint(mapID, x, y, expires)
    mapID, x, y, expires = tonumber(mapID), tonumber(x), tonumber(y), tonumber(expires)
    if not (mapID and x and y and expires) or x < 0 or x > 10000 or y < 0 or y > 10000 then return end
    if not ns.IsOutdoorMap(mapID) then return end
    return mapID, x / 10000, y / 10000, expires
end

local FACTIONS = { A = "Alliance", H = "Horde" }

-- The zone you're in (a capital counts as its zone), or nil in an instance
-- or if it can't be read.
local function PlayerZone()
    if IsInInstance and IsInInstance() then return nil end
    local mapID = C_Map.GetBestMapForUnit("player")
    if not mapID or ns.IsSecret(mapID) then return nil end
    local zone = ns.ZoneOf(mapID)
    return ns.IsOutdoorMap(zone) and zone or nil
end

-- Camps and requests are for your own faction: another faction's (when the
-- sender says which) are ignored. Returns the faction, or false to ignore.
local function SameFaction(code)
    local faction = FACTIONS[code or ""]
    if faction and faction ~= UnitFactionGroup("player") then return false end
    return faction
end

local handlers = {}

-- Flood protection: each player can add one new camp and one new request
-- every ns.db.floodLimit seconds (10 minutes). Updates to ones already known
-- aren't limited. A new fire someone lit, or a new request in place of their
-- last one, only waits REPLACE_COOLDOWN: everyone has one of each at most, so
-- these never make the lists longer.
-- Everyone together can add at most 20 new camps and 10 new requests a
-- minute, so many characters working together can't flood the lists either.
-- Camps in the zone you're in have an allowance of their own (30 a minute):
-- on a busy realm, camps elsewhere can't keep the ones near you off your map.
local allowNew = { camp = ns.FloodLimit(20), near = ns.FloodLimit(30), request = ns.FloodLimit(10) }
local REPLACE_COOLDOWN = 30
local SEEN_COOLDOWN = 120 -- new camps seen in passing, from each player: up to SEEN_BURST this often
local SEEN_BURST = 3      -- (busy camping spots have fires side by side, passed seconds apart)
Comm.REPLACE_COOLDOWN = REPLACE_COOLDOWN -- your own requests wait for it too (Requests.lua)
local requestClosedAt = {} -- [sender] = when their request here was closed

local SetName -- below

function handlers.S(sender, id, mapID, x, y, expires, owned, objects, professionList, equipmentList, layer, faction, slots, passing,
                    key, areaID, direction, region)
    if CreatorOf(id or "") ~= sender then return end
    faction = SameFaction(faction)
    if faction == false then return end
    mapID, x, y, expires = ParsePoint(mapID, x, y, expires)
    local now = GetServerTime()
    if not mapID or expires > 0 and (expires < now or expires > now + 4 * 3600) then return end
    if not ns.Camps:Get(id) then
        -- A fire they lit replaces their last one (Camps:Upsert); a camp they
        -- reported adds one.
        local allowed
        local allow = ns.ZoneOf(mapID) == PlayerZone() and allowNew.near or allowNew.camp
        if owned == "1" then
            allowed = allow(sender .. "\0lit", math.min(REPLACE_COOLDOWN, ns.db.floodLimit))
        elseif passing == "p" then
            -- Camps seen riding past: up to SEEN_BURST every few minutes.
            for slot = 1, SEEN_BURST do
                allowed = allow(sender .. "\0seen" .. slot, math.min(SEEN_COOLDOWN, ns.db.floodLimit))
                if allowed then break end
            end
        else
            allowed = allow(sender, ns.db.floodLimit)
        end
        if not allowed then return end
    end

    local camp = ns.Camps:Upsert({
        id = id,
        creator = sender,
        owned = owned == "1",
        mapID = mapID, x = x, y = y,
        placedAt = tonumber(id:match(":(%d+)$")),
        expiresAt = expires > 0 and expires or nil,
        objects = ParseIDs(objects, ns.IsCampObjectSpell),
        professions = ParseIDs(professionList),
        equipment = ParseEquipment(equipmentList),
        layer = Integer(layer, 1, 999999999),
        faction = faction,
        slots = Integer(slots, 1, 20),
        passing = passing == "p" or nil,
    }, sender)
    -- Its name and location, from 0.8.7 (older versions send them in N).
    if camp and key ~= nil then SetName(camp, key, areaID, direction, region) end
end

-- Object claims and Camp Benefits lists are only taken from the camp's
-- fire-lighter or from players who say they're at that camp.
local function AtCamp(sender, id)
    return CreatorOf(id) == sender or ns.Social:IsPersonAtCamp(sender, id)
end

function handlers.O(sender, id, spellID, skillLine)
    local camp = id and AtCamp(sender, id) and ns.Camps:Get(id)
    spellID, skillLine = Integer(spellID, 1, 9999999), Integer(skillLine, 0, 99999)
    if camp and spellID and ns.IsCampObjectSpell(spellID) then
        ns.Camps:AddObject(camp, spellID, ns.PROFESSION_BY_ID[skillLine or 0] and skillLine)
    end
end

-- A Camp Benefits list says what's at a camp now, so anything it leaves out
-- has gone. From its creator that's taken at once. From anyone else (who
-- only says they're at the camp: presence can't prove it) what's new is
-- added, but things are only taken away once a second player at the camp
-- sends a list within GONE_AGREE seconds: one player alone can't empty
-- someone's camp off everyone's map.
local GONE_AGREE = 180
local goneHeard = {} -- [campID] = { name = who sent a list, at = when }

function handlers.E(sender, id, list)
    local camp = id and AtCamp(sender, id) and ns.Camps:Get(id)
    if not camp then return end
    local found = ParseEquipment(list)
    local agreed = CreatorOf(id) == sender
    if not agreed then
        local last, now = goneHeard[id], GetTime()
        agreed = last ~= nil and last.name ~= sender and now - last.at <= GONE_AGREE
        goneHeard[id] = { name = sender, at = now }
    end
    if agreed then
        goneHeard[id] = nil
        if ns.Camps:SetEquipment(camp, found) then ns.OnCampsChanged() end
    else
        for skillLine, tier in pairs(found) do ns.Camps:AddEquipment(camp, skillLine, tier) end
    end
end

local DIRECTIONS = { North = true, Northeast = true, East = true, Southeast = true,
    South = true, Southwest = true, West = true, Northwest = true }

-- A camp's name and location from a message (S, N or a zone answer). The
-- same again (most snapshots repeat it) changes nothing.
SetName = function(camp, key, areaID, direction, region)
    -- Place names come from your own game: the area from its ID, the zone from the map.
    areaID = Integer(areaID, 1, 9999999)
    local area = areaID and C_Map.GetAreaInfo(areaID)
    local map = ns.MapInfo(camp.mapID)
    local location = {
        area = type(area) == "string" and area ~= "" and area or nil,
        areaID = areaID,
        direction = area and DIRECTIONS[direction or ""] and direction or nil,
        zone = map and map.name,
        region = ns.Location.REGIONS[region or ""] and region or nil,
    }
    -- Only names the addon knows are accepted; anything else shows the location name.
    local nameKey = key ~= "" and ns.Names:Render(key, location) and key or nil
    local old = camp.location
    if old and old.area == location.area and old.areaID == location.areaID and old.direction == location.direction
        and old.zone == location.zone and old.region == location.region and camp.nameKey == nameKey then
        return
    end
    camp.location, camp.nameKey = location, nameKey
    ns.OnCampsChanged()
end

function handlers.N(sender, id, key, areaID, direction, region)
    local camp = id and ns.Camps:Get(id)
    if not camp or CreatorOf(id) ~= sender then return end
    SetName(camp, key, areaID, direction, region)
end

local removedCamps = {} -- [id] = true: camps their creators said are gone, this session (never taken back from a zone answer)

function handlers.X(sender, id)
    if id and CreatorOf(id) == sender then
        removedCamps[id] = true
        ns.Campsites:OnCampEnded(ns.Camps:Get(id))
        ns.Camps:Remove(id)
    end
end

local function IsProfession(skillLine) return ns.PROFESSION_BY_ID[skillLine] ~= nil end
local function HasClassBuff(skillLine) return ns.CLASS_BUFFS[skillLine] ~= nil end

function handlers.R(sender, id, mapID, x, y, expires, wantList, faction, tierList, bringList, buffList, classWantList)
    if CreatorOf(id or "") ~= sender or SameFaction(faction) == false then return end
    mapID, x, y, expires = ParsePoint(mapID, x, y, expires)
    local now = GetServerTime()
    if not mapID or expires < now or expires > now + ns.Requests.DURATION + 60 then return end
    if not ns.Requests:Get(id) then
        -- In place of their last request (open, or closed here lately), or a new one?
        local replacing = requestClosedAt[sender] ~= nil and GetTime() - requestClosedAt[sender] < ns.db.floodLimit
        for _, other in pairs(ns.Requests:All()) do
            if other.creator == sender then replacing = true end
        end
        local cooldown = replacing and math.min(REPLACE_COOLDOWN, ns.db.floodLimit) or ns.db.floodLimit
        if not allowNew.request(sender, cooldown) then return end
        requestClosedAt[sender] = nil
    end

    -- Every camp buff wanted, objects and class buffs (those are marked too).
    local wants = ParseIDs(wantList, IsProfession)
    local classWants = ParseIDs(classWantList, HasClassBuff)
    for skillLine in pairs(classWants) do wants[skillLine] = true end
    if not next(wants) then return end

    ns.Requests:Upsert({
        id = id,
        creator = sender,
        mapID = mapID, x = x, y = y,
        createdAt = tonumber(id:match(":(%d+)$")),
        expiresAt = expires,
        wants = wants,
        classWants = classWants,
        minTier = ParseTiers(tierList),
        brings = ParseTiers(bringList),
        buffs = ParseIDs(buffList, IsProfession),
        -- A version before 0.8.5 has no classWants field, and would ignore
        -- class-buff sign-ups: none are offered for its request.
        classBuffSignups = classWantList ~= nil,
    }, sender)
end

-- Requests:AddHelper checks the object (0: none) and the class buffs fit the request.
function handlers.J(sender, id, skillLine, tier, buffList)
    local request = id and ns.Requests:Get(id)
    skillLine, tier = tonumber(skillLine), tonumber(tier)
    if request and skillLine then
        ns.Requests:AddHelper(request, sender, skillLine, tier and tier >= 1 and tier <= 3 and tier or nil,
            ParseIDs(buffList, HasClassBuff))
    end
end

function handlers.L(sender, id)
    local request = id and ns.Requests:Get(id)
    if request then ns.Requests:RemoveHelper(request, sender) end
end

function handlers.C(sender, id)
    if id and CreatorOf(id) == sender and ns.Requests:Get(id) then
        ns.Requests:Remove(id)
        requestClosedAt[sender] = GetTime()
    end
end

-- Presence is handled in Social.lua.
for kind, method in pairs({ P = "OnPresence", Z = "OnLeft" }) do
    handlers[kind] = function(...) ns.Social[method](ns.Social, ...) end
end

function handlers.U(...)
    ns.Music:OnMessage(...)
end

-- The latest version (Stats.lua) and the developer's announcements (Broadcast.lua).
function handlers.VQ(...)
    ns.Stats:OnVersionQuestion(...)
end

function handlers.VA(...)
    ns.Stats:OnVersionAnswer(...)
end

function handlers.B(...)
    ns.Broadcast:OnMessage(...)
end

-- The reply to queries: your camps and requests, then your sign-ups. One
-- that went out after the first query waiting (a change, say) reached every
-- asker already, so it isn't sent again.
local function SendQueryReply()
    local since, forOld = replyFor or 0, oldAsker
    replyPending, replyFor, oldAsker = false, nil, false
    lastQueryReply = GetTime()
    for _, camp in pairs(ns.Camps:All()) do
        if ns.Camps:IsMine(camp) and (sentAt[camp.id] or -math.huge) < since then Comm:SendSnapshot(camp, forOld) end
    end
    for _, request in pairs(ns.Requests:All()) do
        if ns.Requests:IsMine(request) and (sentAt[request.id] or -math.huge) < since then Comm:SendRequest(request) end
    end
    -- Sign-ups go out later, after the requests they refer to have arrived,
    -- with the tier and class buffs you signed up with.
    C_Timer.After(8, function()
        for _, request in pairs(ns.Requests:All()) do
            local skillLine = request.helpers[ns.playerName]
            if skillLine and not ns.Requests:IsMine(request) then
                Comm:SendJoin(request.id, skillLine, (request.helperTiers or {})[ns.playerName],
                    (request.helperBuffs or {})[ns.playerName])
            end
        end
    end)
end

-- How long replies wait after the last one: QUERY_REPLY_COOLDOWN, longer the
-- more queries have come lately (each one counted once it's taken), up to
-- QUERY_REPLY_MOST. Two queries a minute keep it at the shortest; twenty a
-- minute (a busy realm) at the longest.
function Comm:ReplyCooldown()
    local now = GetTime()
    local rate = queryRate * math.exp(-(now - (queryRateAt or now)) / QUERY_RATE_SPAN)
    return math.min(QUERY_REPLY_MOST, math.max(QUERY_REPLY_COOLDOWN, rate * 3))
end

local function CountQuery(now)
    queryRate = queryRate * math.exp(-(now - (queryRateAt or now)) / QUERY_RATE_SPAN) + 1
    queryRateAt = now
end

-- Whether a version is older than 0.8.7 (which takes camp names from S).
local function BeforeNamesInSnapshots(version)
    local a, b, c = (version or ""):match("^(%d+)%.(%d+)%.(%d+)")
    a, b, c = tonumber(a), tonumber(b), tonumber(c)
    if not a then return false end
    return a == 0 and (b < 8 or b == 8 and c < 7)
end

function handlers.Q(sender, version, users)
    version, users = version and version:match("^[%w%.%-]+$"), tonumber(users)
    if version and #version <= 16 then ns.Stats:Seen(sender, version) end
    if users and users >= 1 and users <= 100000 then ns.Stats:OnCensus(sender, math.floor(users)) end
    local now = GetTime()
    if lastQueryFrom[sender] and now - lastQueryFrom[sender] < QUERY_SENDER_COOLDOWN then return end
    lastQueryFrom[sender] = now
    CountQuery(now)
    if BeforeNamesInSnapshots(version) then oldAsker = true end
    -- A reply still waiting to go out answers this query too.
    if replyPending then return end
    replyPending, replyFor = true, now
    -- At most one reply every ReplyCooldown seconds (a query that comes sooner
    -- is answered when that time is up), and a random delay spreads out
    -- replies when many players answer at once.
    local wait = lastQueryReply and math.max(0, lastQueryReply + Comm:ReplyCooldown() - now) or 0
    C_Timer.After(wait + 2 + math.random() * 6, SendQueryReply)
end

-- Zone asks ---------------------------------------------------------------------
-- A query's replies only bring camps whose reporters are online to send them.
-- So at login, and when you enter a zone, you ask the players in your zone (ZQ)
-- for every camp they know there, whoever reported it (ZA). Nothing is said in
-- chat: the camps just appear on the map.
local ZONE_SETTLE = 5           -- seconds in a zone before asking (not while riding along a border)
local ZONE_ASK_AGAIN = 10 * 60  -- each zone is asked about at most this often
local ZONE_ASK_OPEN = 90        -- seconds that answers about a zone you asked about are taken
local ZONE_ANSWER_COOLDOWN = 30 -- answers go out at most this often (one answer serves every ask waiting)
local ZONE_ASKER_COOLDOWN = 60  -- each player's asks are answered at most this often
local ZONE_MIN_LEFT = 60        -- seconds: a fire with less left isn't passed on
local ZONE_MAX_ANSWER = 20      -- camps taken from one player's answers to an ask, at most
local ZONE_MAX_CHANNEL = 5      -- camps in one answer on the channel (to versions before 0.8.7), at most
local ZONE_MAX_WHISPERED = 8    -- camps whispered to one asker at most
local ZONE_MAX_ASKERS = 3       -- askers whispered in one answer at most (the others get theirs from other players)
local ZONE_ANSWERERS = 4        -- about how many players in a zone answer each ask on the channel
local ZONE_WHISPERERS = 2       -- and each ask by whisper (their answers can't be heard by the others, so overlap)
local ZONE_PEOPLE_SPAN = 30 * 60 -- seconds: players heard asking or answering about a zone this lately count as there
local ZONE_ANSWER_WAIT = { 1, 12 } -- seconds an answer waits, at random, so answerers rarely go at once
local zoneAskedAt = {}          -- [zone] = when you last asked about it
local zoneAskFrom = {}          -- [player] = when their last ask was taken
local lastZoneAnswer            -- when your last answer went out (nil: none yet)
local zoneAnswer                -- the answer waiting to go out: { zone =, since = when the latest ask came }
local answerHeard = {}          -- [campID] = when someone else's answer with it was last heard
local zonePeople = {}           -- [zone] = { [player] = when last heard asking or answering about it }
local answersFrom = {}          -- [player] = { at = when their answers began, n = camps taken from them }
local zoneMoves = 0             -- counts zone changes: only the latest one's wait counts
-- Camps from answers are other players' word: everyone's answers together
-- can add at most this many camps a minute.
local allowAnswered = ns.FloodLimit(30)

-- Whether a camp you know goes in an answer about a zone: a real camp there
-- (one seen in passing too, but not from chat, nor a test camp), of your faction, from
-- nobody you've blocked, with something to offer, and its fire's time left
-- known and not about to run out.
local function Answerable(camp, zone)
    local left = ns.Camps:TimeLeft(camp)
    return not camp.chat and not camp.test and not camp.demo
        and not tostring(camp.id):find("^HCTest:") and camp.realm == ns.realm
        and camp.faction ~= nil and camp.faction == UnitFactionGroup("player")
        and left ~= nil and left >= ZONE_MIN_LEFT and ns.ZoneOf(camp.mapID) == zone
        and not ns.IsBlocked(camp.creator or "") and ns.Camps:Offers(camp)
end

-- A camp as an answer (ZA): its name and location go too if there's room.
local function ZoneAnswer(camp)
    local left = math.floor(ns.Camps:TimeLeft(camp))
    local function Build(withName)
        return function(objects, professions)
            local message = format("ZA;%s;%d;%d;%d;%d;%d;%s;%s;%s;%s;%s;%s", camp.id, camp.mapID, Coord(camp.x), Coord(camp.y),
                left, camp.owned and 1 or 0, EncodeIDs(objects), EncodeIDs(professions), EncodeEquipment(camp.equipment),
                camp.layer or "", FactionCode(camp.faction), camp.slots or "")
            local location = withName and camp.location
            if location then
                message = message .. format(";%s;%s;%s;%s", camp.nameKey or "", location.areaID or "",
                    Field(location.direction), Field(location.region))
            elseif camp.passing then
                message = message .. ";;;;"
            end
            -- Seen in passing: it stays that for them (a camp reported at that fire takes its place).
            if camp.passing then message = message .. ";p" end
            return message
        end
    end
    local message = FitCamp(camp, Build(true))
    if #message > MAX_MESSAGE then message = FitCamp(camp, Build(false)) end
    return message
end

-- Asks the players in your zone for its camps, unless you asked about it in
-- the last 10 minutes (again: ask anyway). Never in an instance, or with the
-- camp network off. The answers come by whisper ("w"). Returns whether it asked.
function Comm:AskZone(again)
    local zone = ns.db and self:IsConnected() and PlayerZone()
    if not zone then return false end
    local now = GetTime()
    if not again and zoneAskedAt[zone] and now - zoneAskedAt[zone] < ZONE_ASK_AGAIN then return false end
    zoneAskedAt[zone] = now
    Send(format("ZQ;%d;%s;w", zone, FactionCode(UnitFactionGroup("player"))), "ZQ")
    return true
end

-- A player heard asking or answering about a zone is in it.
local function NoteZonePerson(zone, name)
    local people = zonePeople[zone] or {}
    zonePeople[zone] = people
    people[name] = GetTime()
end

-- About how many players with the addon are in a zone: those heard asking or
-- answering about it lately, and you.
function Comm:ZonePeople(zone)
    local count, now = 1, GetTime()
    for name, at in pairs(zonePeople[zone] or {}) do
        if now - at <= ZONE_PEOPLE_SPAN then count = count + 1 else zonePeople[zone][name] = nil end
    end
    return count
end

-- You entered a zone: you ask once you've been in it ZONE_SETTLE seconds.
function Comm:OnZoneChanged()
    zoneMoves = zoneMoves + 1
    local move, zone = zoneMoves, ns.db and PlayerZone()
    if not zone then return end
    C_Timer.After(ZONE_SETTLE, function()
        if move == zoneMoves and PlayerZone() == zone then Comm:AskZone() end
    end)
end

local function SendZoneAnswer()
    local answer = zoneAnswer
    zoneAnswer = nil
    -- Gone on to another zone meanwhile: players still there answer.
    if not answer or PlayerZone() ~= answer.zone then return end
    lastZoneAnswer = GetTime()
    local ids = {}
    for id, camp in pairs(ns.Camps:All()) do
        if Answerable(camp, answer.zone) then ids[#ids + 1] = id end
    end
    -- In a random order, so players answering at once mostly start on different camps.
    for i = #ids, 2, -1 do
        local j = math.random(i)
        ids[i], ids[j] = ids[j], ids[i]
    end
    -- Askers before 0.8.7: on the channel, skipping camps someone else has
    -- answered since the ask (everyone on the realm hears these: a few only).
    for i = 1, answer.channel and math.min(#ids, ZONE_MAX_CHANNEL) or 0 do
        local id = ids[i]
        -- Made again as it goes: by then someone else may have sent it, and the
        -- time left is up to date.
        local function Make()
            local camp = ns.Camps:Get(id)
            if not camp or not Answerable(camp, answer.zone) or (answerHeard[id] or -1) >= answer.since then return nil end
            return ZoneAnswer(camp)
        end
        local message = Make()
        if message then Send(message, "ZA" .. id, nil, nil, nil, Make, true) end
    end
    -- The others: by whisper, each their own, while their ask is still open
    -- (an asker takes answers for ZONE_ASK_OPEN seconds; some leeway for the way).
    for asker, askedAt in pairs(answer.askers) do
        for i = 1, math.min(#ids, ZONE_MAX_WHISPERED) do
            local id = ids[i]
            local function Make()
                local camp = ns.Camps:Get(id)
                if not camp or not Answerable(camp, answer.zone) or GetTime() - askedAt > ZONE_ASK_OPEN - 10 then return nil end
                return ZoneAnswer(camp)
            end
            local message = Make()
            if message then Send(message, "ZA" .. id .. "\0" .. asker, asker, nil, nil, Make, true) end
        end
    end
end

-- Answered only by players in that zone, of the asker's faction, each
-- asker's at most once a minute, after a random wait, and at most one
-- answer every ZONE_ANSWER_COOLDOWN seconds (an ask that comes sooner is
-- answered when that time is up; one answer serves every ask waiting). In a
-- busy zone each player answers only by chance, so about ZONE_ANSWERERS of
-- them do (ZONE_WHISPERERS for an ask by whisper). An asker who said "w" is whispered.
function handlers.ZQ(sender, zone, faction, flags)
    zone = Integer(zone, 1, 9999999)
    if not zone or FACTIONS[faction or ""] ~= UnitFactionGroup("player") then return end
    NoteZonePerson(zone, sender)
    if PlayerZone() ~= zone then return end
    local now = GetTime()
    if zoneAskFrom[sender] and now - zoneAskFrom[sender] < ZONE_ASKER_COOLDOWN then return end
    zoneAskFrom[sender] = now
    local whisper = flags == "w"
    if math.random() * Comm:ZonePeople(zone) > (whisper and ZONE_WHISPERERS or ZONE_ANSWERERS) then return end
    if zoneAnswer then
        if whisper then
            if ns.Count(zoneAnswer.askers) < ZONE_MAX_ASKERS then zoneAnswer.askers[sender] = now end
        else
            zoneAnswer.channel, zoneAnswer.since = true, now
        end
        return
    end
    zoneAnswer = { zone = zone, since = now, channel = not whisper, askers = whisper and { [sender] = now } or {} }
    local wait = lastZoneAnswer and math.max(0, lastZoneAnswer + ZONE_ANSWER_COOLDOWN - now) or 0
    C_Timer.After(wait + ZONE_ANSWER_WAIT[1] + math.random() * (ZONE_ANSWER_WAIT[2] - ZONE_ANSWER_WAIT[1]), SendZoneAnswer)
end

-- An answer: noted (so you don't send that camp too), and taken only to add a
-- camp you don't know in a zone you've just asked about. It's added as a
-- snapshot from its creator would be, its time left counted from now; a camp
-- you know (your own above all) is never changed by it, nor brought back once
-- its creator said it's gone, and a fire of theirs you know stays the one.
-- A camp's fire burns campDuration seconds, so an answer can't give it longer;
-- and each player's answers can add at most ZONE_MAX_ANSWER camps while an
-- ask is open (anyone can answer, naming anyone as a camp's creator).
function handlers.ZA(sender, id, mapID, x, y, left, owned, objects, professionList, equipmentList, layer, faction,
                     slots, key, areaID, direction, region, passing)
    local creator = CreatorOf(id or "")
    faction = FACTIONS[faction or ""]
    left = Integer(left, ZONE_MIN_LEFT / 2, ns.db.campDuration + 60)
    mapID, x, y = ParsePoint(mapID, x, y, 0)
    if not (creator and faction and left and mapID) then return end
    local now = GetTime()
    answerHeard[id] = now
    local zone = ns.ZoneOf(mapID)
    if faction == UnitFactionGroup("player") then NoteZonePerson(zone, sender) end
    if faction ~= UnitFactionGroup("player") or not zoneAskedAt[zone] or now - zoneAskedAt[zone] > ZONE_ASK_OPEN
        or creator == ns.playerName or ns.IsBlocked(creator) or ns.Camps:Get(id) or removedCamps[id] then
        return
    end
    local from = answersFrom[sender]
    if not from or now - from.at > ZONE_ASK_OPEN then
        from = { at = now, n = 0 }
        answersFrom[sender] = from
    end
    if from.n >= ZONE_MAX_ANSWER then return end
    owned = owned == "1"
    layer = Integer(layer, 1, 999999999)
    if owned then
        for _, other in pairs(ns.Camps:All()) do
            if other.creator == creator and other.owned then return end
        end
    end
    -- A camp you know at that fire already (on that layer) is the one, unless
    -- this is its fire-lighter's and yours is only a report.
    local near = ns.Camps:NearestTo(mapID, x, y, ns.Camps.MERGE_RADIUS, layer)
    if near and not near.passing and (near.owned or not owned) then return end
    if not allowAnswered(id, 0) then return end
    from.n = from.n + 1
    local camp = ns.Camps:Upsert({
        id = id,
        creator = creator,
        owned = owned,
        mapID = mapID, x = x, y = y,
        placedAt = tonumber(id:match(":(%d+)$")),
        expiresAt = GetServerTime() + left,
        objects = ParseIDs(objects, ns.IsCampObjectSpell),
        professions = ParseIDs(professionList),
        equipment = ParseEquipment(equipmentList),
        layer = layer,
        faction = faction,
        slots = Integer(slots, 1, 20),
        passing = passing == "p" or nil,
    }, creator)
    if camp then SetName(camp, key, areaID, direction, region) end
end

-- Whether a sender's name could be yours: it starts with your first name, and
-- the name doesn't go on ("Bob Stone" or "Bob-Realm" for Bob, not "Bobby").
local function MightBeYou(sender)
    local first = (UnitNameUnmodified or UnitName)("player")
    if type(first) ~= "string" or ns.IsSecret(first) or first == "" then return false end
    return sender:sub(1, #first) == first and not sender:sub(#first + 1):find("^%w")
end

function Comm:OnAddonMessage(prefix, text, chatType, sender)
    if prefix ~= PREFIX then return end
    if chatType == "CHANNEL" then Comm:OnChannelHeard() end
    if sender == ns.playerName then
        -- Your own query came back under the name you expected: your name is
        -- confirmed, so no later echo of it can change it.
        if type(text) == "string" and text:match("^Q;[^;]*;[^;]*;(%d+)$") == queryNonce then adoptedName = true end
        return
    end
    if not ns.db.network and chatType ~= "WHISPER" and not GROUP_TYPES[chatType] then return end
    if type(text) ~= "string" or #text > 255 or type(sender) ~= "string" then return end
    if ns.IsBlocked(sender) then return end
    if chatType == "CHANNEL" and Comm:IsRepeat(sender, text) then return end
    local fields = { strsplit(";", text) }
    local kind = fields[1]
    -- Your own query, back from the camp channel under a name you didn't
    -- expect: that's how the game names you, so use it. Anyone can repeat a
    -- query, so only once a session, and only a name starting with your own
    -- first name.
    if kind == "Q" and fields[4] == queryNonce then
        if chatType == "CHANNEL" and not adoptedName and MightBeYou(sender) then
            adoptedName = true
            ns.AdoptPlayerName(sender)
        end
        return
    end
    -- Everything comes over the channel, except feedback (reports to the
    -- developer, picked up by their dev tools, and the receipts they send
    -- back) and layer invite requests.
    -- What other players' messages change is redrawn with the next
    -- once-a-second refresh, not at once (ns.OnCampsChanged).
    ns.receiving = true
    Comm:Handle(sender, chatType, kind, fields, text)
    ns.receiving = false
end

function Comm:Handle(sender, chatType, kind, fields, text)
    if chatType == "WHISPER" then
        if kind == "F" and ns.OnFeedbackPart then ns.OnFeedbackPart(sender, text) end
        if kind == "K" then ns.Feedback:OnReceipt(sender, fields[2]) end
        if kind == "LJ" then ns.LayerInvites:OnRequest(sender, fields[2]) end
        -- Answers to your zone ask (0.8.7), for camps the channel would bring.
        if kind == "ZA" and ns.db.network then handlers.ZA(sender, unpack(fields, 2)) end
        return
    end
    -- Group planning comes only from your party or raid, and nothing else does.
    local isGroupKind = kind == "G" or kind == "GQ" or kind == "GA" or kind == "GB"
    if isGroupKind ~= (GROUP_TYPES[chatType] == true) then return end
    if isGroupKind then
        ns.Group:OnMessage(sender, kind, unpack(fields, 2))
        return
    end
    local handler = handlers[kind]
    if not handler then return end
    ns.Stats:Seen(sender)
    if sender == ns.DEVELOPER then ns.Feedback:OnDeveloperSeen() end
    handler(sender, unpack(fields, 2))
end

-- Channel management ------------------------------------------------------------

-- Which camp channel a chat event is about (its index), or nil.
local function OurChannel(...)
    local channelBaseName = select(9, ...)
    if type(channelBaseName) ~= "string" then return nil end
    for index, name in ipairs(CHANNELS) do
        if channelBaseName:lower() == name:lower() then return index end
    end
end

local function IsOurChannel(...)
    return OurChannel(...) ~= nil
end

-- The camp channels (and other addons', Others.lua) stay in the chat windows'
-- channel lists: chat filters (ChatFilter, below) hide every line from them.
-- The chat windows themselves are never changed (RemoveChannel and the like):
-- an addon writing the game's chat frame tables taints them, and the game then
-- blocks its own chat actions, blaming the addon with a popup.

-- A message heard twice within REPEAT_WINDOW seconds (from two camp channels
-- while bridging) is only handled once.
local REPEAT_WINDOW = 5
local recent, recentCount = {}, 0

function Comm:IsRepeat(sender, text)
    local now, key = GetTime(), sender .. "\0" .. text
    if recent[key] and now - recent[key] < REPEAT_WINDOW then return true end
    recent[key] = now
    recentCount = recentCount + 1
    if recentCount > 200 then
        for k, at in pairs(recent) do
            if now - at >= REPEAT_WINDOW then recent[k] = nil end
        end
        recentCount = 0
    end
    return false
end

-- Hides the camp channels' lines from chat: messages, notices, joins and
-- leaves. With showNotices (dev tools' /hc notices) their notices show
-- (replies to /owner, /password; joins); messages stay hidden.
local function ChatFilter(_, event, ...)
    if Comm.showNotices and event ~= "CHAT_MSG_CHANNEL" then return false end
    return IsOurChannel(...)
end

-- The channel's name, and whether you're in it (its number, or nil). For the dev tools.
function Comm:ChannelInfo()
    return CHANNELS[current], ChannelID()
end

function Comm:Init()
    C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
    C_Timer.NewTicker(OFF_CHECK, function() Comm:CheckChannelOff() end)
    local addFilter = ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter
    if not addFilter then return end
    for _, event in ipairs({ "CHAT_MSG_CHANNEL", "CHAT_MSG_CHANNEL_NOTICE",
        "CHAT_MSG_CHANNEL_NOTICE_USER", "CHAT_MSG_CHANNEL_JOIN", "CHAT_MSG_CHANNEL_LEAVE" }) do
        addFilter(event, ChatFilter)
    end
    -- A whisper (a zone answer, a report) to someone who has just logged off
    -- would show "No player named ... is currently playing": that's hidden,
    -- and nothing more goes to them (a report is sent again later).
    addFilter("CHAT_MSG_SYSTEM", function(_, _, message)
        return Comm:OnPlayerNotFound(message)
    end)
end

-- Whether a system message is the game's "No player named ..." for a player
-- Happy Camper whispered lately (or the developer); their waiting whispers go.
function Comm:OnPlayerNotFound(message)
    if ERR_CHAT_PLAYER_NOT_FOUND_S == nil or type(message) ~= "string" or ns.IsSecret(message) then return false end
    local now = GetTime()
    for name, at in pairs(whispered) do
        if now - at > WHISPERED_FOR then
            whispered[name] = nil
        elseif message == format(ERR_CHAT_PLAYER_NOT_FOUND_S, name) then
            for i = #queue, 1, -1 do
                if queue[i].chatType == "WHISPER" and queue[i].target == name then
                    Dropped(table.remove(queue, i).message, "WHISPER", name, "logged off")
                end
            end
            return true
        end
    end
    return message == format(ERR_CHAT_PLAYER_NOT_FOUND_S, ns.DEVELOPER)
end

-- Every 10 seconds (Core.lua): what's kept about other players is let go once
-- it can no longer matter, so a long session on a busy realm doesn't pile it up.
function Comm:Prune()
    local now = GetTime()
    for name, at in pairs(lastQueryFrom) do if now - at > QUERY_SENDER_COOLDOWN then lastQueryFrom[name] = nil end end
    for name, at in pairs(zoneAskFrom) do if now - at > ZONE_ASKER_COOLDOWN then zoneAskFrom[name] = nil end end
    for name, from in pairs(answersFrom) do if now - from.at > ZONE_ASK_OPEN then answersFrom[name] = nil end end
    for id, at in pairs(answerHeard) do if now - at > ZONE_ASK_OPEN then answerHeard[id] = nil end end
    for id, heard in pairs(goneHeard) do if now - heard.at > GONE_AGREE then goneHeard[id] = nil end end
    for name, at in pairs(whispered) do if now - at > WHISPERED_FOR then whispered[name] = nil end end
    for id in pairs(sentAt) do if not ns.Camps:Get(id) and not ns.Requests:Get(id) then sentAt[id] = nil end end
    for zone, people in pairs(zonePeople) do
        for name, at in pairs(people) do if now - at > ZONE_PEOPLE_SPAN then people[name] = nil end end
        if not next(people) then zonePeople[zone] = nil end
    end
end

-- Chat channels take the lowest free number when they're joined, so the camp
-- channel waits for General: joining first would take General's /1. It checks
-- every 5 seconds. In an instance (no General there) it waits until you're
-- out; outdoors with no General for NO_GENERAL_WAIT tries (you've left General),
-- it joins anyway.
local NO_GENERAL_WAIT = 24 -- tries, 5 seconds apart: 2 minutes
local JOIN_TRIES = 3    -- joins that fail without saying why before trying the next channel
local joinTries = 0
local connecting = 0    -- which Connect is the live one (a new one stops the old one's retries)
local swapped = false   -- KeepBehindGeneral has swapped channels since the camp channel was last joined
local told = {}         -- what the player's been told this session

-- Set when the game blocks something Happy Camper does (OnActionBlocked, at
-- the end): from then on, for the rest of the session, nothing joins, leaves
-- or reorders chat channels, and no retries run; camp messages go only on a
-- camp channel you're still in (PausedWithoutChannel). Others.lua checks it too.
Comm.paused = false

-- General's channel number, or nil if you're not in it (or it can't be told).
local function GeneralID()
    local get = C_ChatInfo.GetGeneralChannelLocalID
    if not get then return nil end
    local ok, id = pcall(get)
    return ok and type(id) == "number" and id > 0 and id or nil
end

local function GeneralJoined()
    if not C_ChatInfo.GetGeneralChannelLocalID then return select("#", GetChannelList()) > 0 end
    return GeneralID() ~= nil
end
Comm.GeneralJoined = GeneralJoined

-- The game saves each channel's number between sessions. If the camp channel
-- ever joined before General (it could before 0.8.1), General is saved at /2
-- and comes back there every login, leaving /1 free for the camp channel again.
-- So when the camp channel is ahead of General, the two swap places, once:
-- General is back at /1 (and saved there), and nothing else moves. At most
-- one swap each time the camp channel is joined.
function Comm:KeepBehindGeneral()
    if self.paused then return end
    local ours, general = ChannelID(), GeneralID()
    if not (ours and general) or ours > general then return end
    local swap = C_ChatInfo.SwapChatChannelsByChannelIndex
    if swap then
        if swapped then return end
        swapped = true
        pcall(swap, ours, general)
    elseif not told.order then
        -- Older clients can't reorder channels: say how to fix it by hand.
        told.order = true
        ns.Print(L["Happy Camper's channel is ahead of General in your chat. To fix it: /leave %s, then /leave General, then /join General."], CHANNELS[current])
    end
end

-- Happy Camper's channels: the camp channel (and any it's bridging) and the
-- other camp addons' channels it listens on (Others.lua).
local function OurChannelNames()
    local names = { [CHANNELS[current]:lower()] = true }
    for index in pairs(bridges) do names[CHANNELS[index]:lower()] = true end
    for _, source in ipairs(ns.Others and ns.Others.SOURCES or {}) do
        if source.channel then names[source.channel:lower()] = true end
    end
    return names
end

-- Every channel you're in: [number] = name, lower case.
local function ChannelNumbers()
    local list, numbers = { GetChannelList() }, {}
    for i = 1, #list, 3 do
        local id, name = list[i], list[i + 1]
        if type(id) == "number" and type(name) == "string" and not ns.IsSecret(id) and not ns.IsSecret(name) then
            numbers[id] = name:lower()
        end
    end
    return numbers
end

-- Happy Camper's channels come after every other channel you're in, the
-- game's own (Trade, LocalDefense...) and any you joined yourself, so those
-- keep the low numbers you know them by. The game gives a new channel the
-- lowest free number and keeps it next login, so ours can end up ahead (it
-- joins as soon as General is in, and Trade only joins in a city): then one of
-- ours and the last of the others swap places, until ours are all behind.
-- Never in a fight, and at most MAX_SWAPS swaps a session, in case something
-- else keeps moving them back.
local MAX_SWAPS = 12
local swapCount = 0
local reorderQueued = false

function Comm:KeepBehindOthers()
    local swap = C_ChatInfo.SwapChatChannelsByChannelIndex
    if self.paused or not swap then return end
    if ns.InCombat() then
        -- After the fight.
        if not reorderQueued then
            reorderQueued = true
            C_Timer.After(10, function() reorderQueued = false; Comm:KeepBehindOthers() end)
        end
        return
    end
    local numbers, ours = ChannelNumbers(), OurChannelNames()
    for _ = 1, 8 do
        local lowestOurs, highestOther
        for id, name in pairs(numbers) do
            if ours[name] then
                if not lowestOurs or id < lowestOurs then lowestOurs = id end
            elseif not highestOther or id > highestOther then
                highestOther = id
            end
        end
        if not (lowestOurs and highestOther) or lowestOurs > highestOther or swapCount >= MAX_SWAPS then return end
        swapCount = swapCount + 1
        if not pcall(swap, lowestOurs, highestOther) then return end
        numbers[lowestOurs], numbers[highestOther] = numbers[highestOther], numbers[lowestOurs]
    end
end

-- Another channel joined (Trade in a city, say): ours move behind it, a moment later.
function Comm:QueueReorder()
    if reorderQueued then return end
    reorderQueued = true
    C_Timer.After(2, function()
        reorderQueued = false
        Comm:KeepBehindOthers()
    end)
end

local function MayJoin(attempt)
    if GeneralJoined() then return true end
    local inInstance = IsInInstance and IsInInstance()
    return not inInstance and attempt > NO_GENERAL_WAIT
end
Comm.MayJoin = MayJoin -- other addons' channels wait the same way (Others.lua)

-- Joins your camp channel, retrying every 5 seconds until it's in. Joins
-- that fail are counted for each new Connect, so earlier ones don't add up.
-- Only one runs at a time: a new Connect stops the last one's retries.
function Comm:Connect(attempt, run)
    if self.paused then return end
    if not run then
        connecting = connecting + 1
        run = connecting
        joinTries, channelGaveUp = 0, false
    elseif run ~= connecting then
        return
    end
    attempt = attempt or 1
    if not ns.db.network then return end
    if ChannelID() then
        self:KeepBehindGeneral()
        self:KeepBehindOthers()
        self:CheckChannelOff()
        -- After a /reload (Core.lua) the camps you knew are still saved, and
        -- you missed a few seconds at most: nobody is asked to send theirs again.
        -- (While the game has the channel off, they're asked for once it's back.)
        if not self.reloaded and not channelOff then
            self:SendQuery()
            self:AskZone() -- and your zone's camps, whoever reported them (once in 10 minutes)
        end
        self.reloaded = nil
        ns.Stats:StartAsking() -- what the latest version is, once a session
        return
    end
    if MayJoin(attempt) then
        joinTries = joinTries + 1
        if joinTries > JOIN_TRIES then return self:UseBackup() end
        swapped = false -- a new join: its number may be ahead of General again
        JoinTemporaryChannel(CHANNELS[current])
        if run ~= connecting then return end -- a notice (or the game blocking it) already moved it on
    end
    -- Until it's in (or a newer Connect takes over).
    C_Timer.After(5, function() Comm:Connect(attempt + 1, run) end)
end

-- Your channel can't be joined: on to the next one (and say so, once).
function Comm:UseBackup()
    if self.paused then return end
    if current >= #CHANNELS then
        -- Camp messages can't go anywhere this session: none are kept waiting.
        channelGaveUp = true
        DropChannelMessages("no camp channel")
        if not told.none then
            told.none = true
            ns.Print(L["Happy Camper couldn't join any of its channels here, so camps won't be shared this session."])
        end
        return
    end
    current, joinTries = current + 1, 0
    if not told.backup then
        told.backup = true
        ns.Print(L["Happy Camper's usual channel is locked on this realm, so it's using a backup. Camps are still shared."])
    end
    self:Connect()
end

-- Someone set a password on a camp channel you're in, or banned or kicked a
-- player from it: players arriving now can't get in and will go to the next
-- one, so you join that too and are heard in both.
function Comm:Bridge(index)
    if self.paused then return end
    local nextIndex = index + 1
    if nextIndex > #CHANNELS or bridges[nextIndex] or nextIndex == current then return end
    bridges[nextIndex] = true
    JoinTemporaryChannel(CHANNELS[nextIndex])
    C_Timer.After(2, function() Comm:SendQuery() end)
end

-- Notices about the camp channels: locked out, locked while you're in, or removed.
local LOCKED_OUT = { WRONG_PASSWORD = true, BANNED = true }
local LOCKED_WHILE_IN = { PASSWORD_CHANGED = true, PLAYER_BANNED = true, PLAYER_KICKED = true }

function Comm:OnChannelNotice(event, notice, ...)
    if self.paused then return end
    if event == "CHAT_MSG_CHANNEL_NOTICE" and (notice == "YOU_JOINED" or notice == "YOU_CHANGED") then self:QueueReorder() end
    local index = OurChannel(notice, ...)
    if not index or not ns.db or not ns.db.network then return end
    if event == "CHAT_MSG_CHANNEL_NOTICE" and LOCKED_OUT[notice] then
        if index == current then self:UseBackup() end
        bridges[index] = nil
    elseif event == "CHAT_MSG_CHANNEL_NOTICE_USER" and LOCKED_WHILE_IN[notice] then
        self:Bridge(index)
    elseif event == "CHAT_MSG_CHANNEL_NOTICE" and notice == "YOU_LEFT" and index == current and not self.leaving then
        -- Kicked (or banned): join again, or move on if that fails.
        C_Timer.After(2, function() Comm:Connect() end)
    end
end

-- Every OFF_CHECK seconds (Init): whether the game has switched the camp
-- channel off, or put it back (channelOff, at the top). Off: what's waiting
-- for it goes, and a join is asked for at once. Still off at the next look,
-- you're told, in one line, once a session; a join is asked for again every
-- OFF_REJOIN seconds. Back: camps are asked for, as at login (nothing is said:
-- the network status shows it).
function Comm:CheckChannelOff()
    if self.paused or not ns.db or not ns.db.network or channelGaveUp or not ChannelID() then
        channelOff = false -- (not in it at all: Connect deals with that)
        return
    end
    local now = GetTime()
    local off = ChannelDisabled() or (invalidAt ~= nil and now - invalidAt < INVALID_HOLD)
    if off and not channelOff then
        channelOff, lastRejoin = true, now
        DropChannelMessages("camp channel off")
        JoinTemporaryChannel(CHANNELS[current])
    elseif off then
        if not told.off then
            told.off = true
            ns.Print("%s", L["Happy Camper tried to reconnect, but Blizzard's addon chat channels are down. Camps will be shared again when they're back."])
        end
        if now - lastRejoin >= OFF_REJOIN then
            lastRejoin = now
            JoinTemporaryChannel(CHANNELS[current])
        end
    elseif channelOff then
        channelOff = false
        self:SendQuery()
        self:AskZone(true) -- (any ask while it was off never got through)
    end
end

-- A message came over a camp channel (your own counts): it's working.
function Comm:OnChannelHeard()
    invalidAt = nil
end

local notices = CreateFrame("Frame")
notices:RegisterEvent("CHAT_MSG_CHANNEL_NOTICE")
notices:RegisterEvent("CHAT_MSG_CHANNEL_NOTICE_USER")
notices:SetScript("OnEvent", function(_, event, ...) Comm:OnChannelNotice(event, ...) end)

-- Entering a zone: its camps are asked for (Zone asks, above).
local zoneEvents = CreateFrame("Frame")
zoneEvents:RegisterEvent("ZONE_CHANGED_NEW_AREA")
zoneEvents:SetScript("OnEvent", function() Comm:OnZoneChanged() end)

function Comm:Disconnect()
    DropChannelMessages("network off") -- group planning still goes without the camp network
    connecting = connecting + 1
    if self.paused then return end -- channels stay as they are for the rest of the session
    self.leaving = true
    for index = 1, #CHANNELS do
        if ChannelID(index) then LeaveChannelByName(CHANNELS[index]) end
    end
    self.leaving = nil
    wipe(bridges)
    channelOff, invalidAt = false, nil
end

-- The game blocked something Happy Camper did: ADDON_ACTION_FORBIDDEN (only
-- the game's own interface may do it: a popup offering to disable the addon)
-- or ADDON_ACTION_BLOCKED (not allowed in a fight). A retry every few seconds
-- would bring the popup straight back, so the first one pauses all channel
-- work for the session (Comm.paused), goes in Happy Camper's recent errors for
-- bug reports, and is explained once in chat. The events come for every
-- addon: only Happy Camper's own folder name counts (the dev copy's too).
-- Nothing here calls anything restricted.
local OWN_FOLDERS = { HappyCamper = true, CampfireCompanion = true }
if type(addonName) == "string" then OWN_FOLDERS[addonName] = true end

function Comm:OnActionBlocked(event, addon, call)
    if self.paused or type(addon) ~= "string" or ns.IsSecret(addon) or not OWN_FOLDERS[addon] then return end
    self.paused = true
    connecting = connecting + 1 -- Connect's retries stop at their next step
    call = type(call) == "string" and not ns.IsSecret(call) and call ~= "" and call or "?"
    -- Camp messages now go only while you're in a camp channel (PausedWithoutChannel).
    if ns.Feedback then ns.Feedback:AddBlocked(event, call) end
    ns.Print(L["The game blocked an action by Happy Camper (%s). Joining its chat channels is paused for this session."], call)
end

local guard = CreateFrame("Frame")
for _, event in ipairs({ "ADDON_ACTION_FORBIDDEN", "ADDON_ACTION_BLOCKED" }) do
    pcall(guard.RegisterEvent, guard, event)
end
guard:SetScript("OnEvent", function(_, event, ...) Comm:OnActionBlocked(event, ...) end)
