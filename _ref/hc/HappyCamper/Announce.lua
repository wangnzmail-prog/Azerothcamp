-- Happy Camper. Copyright (c) 2026 Torridon. All rights reserved; see LICENSE.
local _, ns = ...
local L = ns.L

-- Player-visible chat. Nothing here is ever sent automatically: every message
-- comes from the player clicking a Say or General button (a hardware event, which
-- the game also requires for /say and channel messages).

local Announce = {}
ns.Announce = Announce

local CLICK_INTERVAL = 10 -- seconds between messages, per channel
local MAX_MESSAGE = 255   -- the game's limit for one chat message
local lastSent = {}

-- "a, b and c"
local function JoinList(items)
    if #items <= 1 then return items[1] or "" end
    return format(L["%s and %s"], table.concat(items, ", ", 1, #items - 1), items[#items])
end
ns.JoinList = JoinList

-- "a, b or c" (nil for none)
function ns.OrList(items)
    if #items <= 1 then return items[1] end
    return format(L["%s or %s"], table.concat(items, ", ", 1, #items - 1), items[#items])
end

function ns.PlaceName()
    local place = GetSubZoneText()
    if not place or place == "" then place = GetZoneText() end
    return place ~= "" and place or L["here"]
end

-- A map pin link to a point: the one the game makes when you share a map pin.
-- Anyone can click it for a waypoint, with or without Happy Camper. Chat
-- silently drops a message whose link the game doesn't accept, so the link is
-- the game's own (C_Map.GetUserWaypointHyperlink): the spot is pinned for a
-- moment, then your own waypoint is put back. Remembered per spot, so hovering
-- the buttons doesn't keep moving your pin. Hand-made only if that's missing.
local pinLinks = {}

local function GameMapPinLink(mapID, x, y)
    local set, get = C_Map.SetUserWaypoint, C_Map.GetUserWaypointHyperlink
    if not (set and get and UiMapPoint and UiMapPoint.CreateFromCoordinates) then return nil end
    -- Your own pin, if you have one, and whether the arrow is following it.
    local old = C_Map.GetUserWaypoint and C_Map.GetUserWaypoint()
    local tracked = C_SuperTrack and C_SuperTrack.IsSuperTrackingUserWaypoint and C_SuperTrack.IsSuperTrackingUserWaypoint()
    local link
    if pcall(set, UiMapPoint.CreateFromCoordinates(mapID, x, y)) then
        local ok, made = pcall(get)
        link = ok and made
    end
    -- Put yours back; with none, the one made just now goes.
    if old then
        pcall(set, old)
        if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then
            pcall(C_SuperTrack.SetSuperTrackedUserWaypoint, tracked == true)
        end
    elseif C_Map.ClearUserWaypoint then
        pcall(C_Map.ClearUserWaypoint)
    end
    return type(link) == "string" and link ~= "" and link or nil
end

function Announce:MapPinLink(mapID, x, y)
    if not (mapID and x and y) or not C_Map.CanSetUserWaypointOnMap(mapID) then return nil end
    local key = format("%d:%d:%d", mapID, math.floor(x * 10000 + 0.5), math.floor(y * 10000 + 0.5))
    if not pinLinks[key] then
        pinLinks[key] = GameMapPinLink(mapID, x, y)
            or format("|cffffff00|Hworldmap:%d:%d:%d|h[|A:Waypoint-MapPin-ChatIcon:13:13:0:0|a %s]|h|r", mapID,
                math.floor(x * 10000 + 0.5), math.floor(y * 10000 + 0.5), MAP_PIN_HYPERLINK or "Map Pin Location")
    end
    return pinLinks[key]
end

-- Is there a camp here to talk about?
-- The camp to announce, and whether you're at it: the one here, else the last
-- one you were at (Social.lua), as long as it's still going with buffs to offer.
function Announce:CampToAnnounce()
    local camp = ns.Camps:NearPlayer(ns.Camps.MERGE_RADIUS)
    if camp and ns.Camps:Offers(camp) then return camp, true end
    local id = ns.charDB and ns.charDB.lastCampID
    local last = id and ns.Camps:Get(id)
    if last and not last.chat and ns.Camps:Offers(last) and (ns.Camps:TimeLeft(last) or 1) > 0 then return last, false end
    return nil
end

function Announce:CanAnnounceCamp()
    return self:CampToAnnounce() ~= nil
end

-- What a camp offers, in profession order: the stats its buffs give, what its
-- objects add besides (by their highest tier there, no repeats), and its
-- objects ({ skillLine, name }).
local function CampOffer(camp)
    local tiers = {}
    for _, object in ipairs(camp and ns.Camps:ObjectList(camp) or {}) do
        if object.skillLine then tiers[object.skillLine] = math.max(tiers[object.skillLine] or 0, object.tier or 1) end
    end
    local stats, extras, objects, seen = {}, {}, {}, {}
    for _, profession in ipairs(ns.PROFESSIONS) do
        local tier = tiers[profession.id]
        if ns.STAT_BUFF[profession.id] and (tier or (camp and camp.professions[profession.id])) then
            stats[#stats + 1] = profession.buff
        end
        if tier then
            for _, extra in ipairs((ns.OBJECT_EXTRAS[profession.id] or {})[tier] or {}) do
                if not seen[extra] then
                    seen[extra] = true
                    extras[#extras + 1] = extra
                end
            end
            objects[#objects + 1] = { skillLine = profession.id, name = ns.ObjectName(profession.id, tier) }
        end
    end
    return stats, extras, objects
end

-- The first of the messages (each a list of sentences) that fits in room
-- (one chat message unless less is given); the last one if none does.
local function FirstThatFits(candidates, room)
    room = room or MAX_MESSAGE
    for _, parts in ipairs(candidates) do
        local message = table.concat(parts, " ")
        if #message <= room then return message end
    end
    return table.concat(candidates[#candidates], " "):sub(1, room)
end

-- The same, with the map pin after the sentences. If none fits with it, the
-- first that fits goes without it: a message cut inside its link is dropped whole.
local function FirstThatFitsWithPin(candidates, link, room)
    room = room or MAX_MESSAGE
    for _, parts in ipairs(link and candidates or {}) do
        local message = table.concat(parts, " ")
        if #message + 1 + #link <= room then return message .. " " .. link end
    end
    return FirstThatFits(candidates, room)
end

-- A candidate's sentences, leaving out the missing ones.
local function Parts(...)
    local parts = {}
    for i = 1, select("#", ...) do
        local part = select(i, ...)
        if part then parts[#parts + 1] = part end
    end
    return parts
end

local function Slice(list, n)
    return { unpack(list, 1, n) }
end

-- Where the camp is: its map pin and coordinates, or the place's name.
local function Where(mapID, x, y, place)
    local pin = Announce:MapPinLink(mapID, x, y)
    if not pin then return place end
    return format("%s (%d, %d)", pin, math.floor(x * 100), math.floor(y * 100))
end

-- The name of the place a camp is at: where you are if you're at it, else its
-- own area (or zone), as the camp has it.
local function CampPlace(camp, here)
    if here or not camp then return ns.PlaceName() end
    local location, info = camp.location or {}, C_Map.GetMapInfo(camp.mapID)
    return location.area or location.zone or (info and info.name) or L["here"]
end

-- e.g. "We've placed a camp at [Map Pin Location] (52, 41). Providing Strength
-- and Stamina, plus a reagent vendor." Extras, then stats, are left out if
-- it would be too long for one chat message.
local function ShortMessage(camp, mapID, x, y, place, room)
    local stats, extras = CampOffer(camp)
    local where = format(L["We've placed a camp at %s."], Where(mapID, x, y, place))
    local candidates = {}
    for s = #stats, math.min(#stats, 1), -1 do
        for e = math.min(#extras, 3), 0, -1 do
            local offer
            if s > 0 and e > 0 then
                offer = format(L["Providing %s, plus %s."], JoinList(Slice(stats, s)), JoinList(Slice(extras, e)))
            elseif s > 0 or e > 0 then
                offer = format(L["Providing %s."], JoinList(s > 0 and Slice(stats, s) or Slice(extras, e)))
            end
            candidates[#candidates + 1] = Parts(where, offer)
        end
    end
    candidates[#candidates + 1] = { where }
    return FirstThatFits(candidates, room)
end

-- Your own wording (Options, My own camp announcement; AnnounceEditor.lua):
-- what you wrote, with blanks filled in. At most WORDING_MAX bytes, so the map
-- pin, what the camp offers and the tag still fit in one chat message.
Announce.WORDING_MAX = 120

-- Which camp announcements: "own" (your wording, Options) or "short".
function Announce:Style()
    return ns.db.announceOwn and "own" or "short"
end

-- Happy Camper's short line as a wording, in your language: where yours starts.
function Announce:DefaultWording()
    return format(L["We've placed a camp at %s."], "{where}") .. " " .. format(L["Providing %s."], "{offers}")
end

-- The first n bytes of text, never ending in half a letter.
local function CutBytes(text, n)
    if #text <= n then return text end
    local cut = n
    while cut > 0 and text:byte(cut + 1) >= 128 and text:byte(cut + 1) < 192 do cut = cut - 1 end
    return text:sub(1, cut)
end

-- A wording as it's kept: no "|" (chat won't take one typed), no line breaks,
-- no spaces at either end, at most WORDING_MAX bytes.
function Announce:CleanWording(text)
    text = tostring(text or ""):gsub("|", ""):gsub("[\r\n]+", " ")
    text = text:gsub("^%s+", ""):gsub("%s+$", "")
    return CutBytes(text, self.WORDING_MAX)
end

-- Your wording, or Happy Camper's while you haven't written one.
function Announce:Wording()
    local text = ns.db.announceText
    return type(text) == "string" and text ~= "" and text or self:DefaultWording()
end

-- What a camp offers, for {offers}: from the most it can name to the least
-- ("Strength and Stamina, plus a reagent vendor", ..., "Strength"), or a warm
-- fire if nothing yet. sample: two buffs and a service, for the editor's preview.
local function OfferLists(camp, sample)
    local stats, extras = CampOffer(camp)
    if sample then
        stats, extras = {}, {}
        for _, profession in ipairs(ns.PROFESSIONS) do
            if ns.STAT_BUFF[profession.id] and #stats < 2 then stats[#stats + 1] = profession.buff end
            for _, list in pairs(ns.OBJECT_EXTRAS[profession.id] or {}) do
                if list[1] and #extras == 0 then extras[1] = list[1] end
            end
        end
    end
    local lists = {}
    for s = #stats, math.min(#stats, 1), -1 do
        for e = math.min(#extras, 3), 0, -1 do
            if s > 0 and e > 0 then
                lists[#lists + 1] = format(L["%s, plus %s"], JoinList(Slice(stats, s)), JoinList(Slice(extras, e)))
            elseif s > 0 or e > 0 then
                lists[#lists + 1] = JoinList(s > 0 and Slice(stats, s) or Slice(extras, e))
            end
        end
    end
    if #lists == 0 then lists[1] = L["a warm fire"] end
    return lists
end

-- A wording with its blanks filled in (values: where, place, offers, time).
-- Other braces are left for the game ({skull}). Without {where}, the pin goes
-- at the end: an announcement nobody can find isn't much use.
local function Fill(wording, values)
    local message = wording:gsub("{(%a+)}", function(name) return values[name] end)
    if not wording:find("{where}", 1, true) then message = message .. " " .. values.where end
    return message
end

-- e.g. "Fire's lit at [Map Pin Location] (52, 41)! Strength and Stamina, plus
-- a reagent vendor. Pull up a log." To fit: {offers} names fewer things, then
-- the coordinates go, then the pin (the place's name instead); last of all the
-- line is cut. sample: the editor's preview away from a camp (OfferLists).
local function OwnMessage(wording, camp, mapID, x, y, place, room, sample)
    room = room or MAX_MESSAGE
    local wheres, pin = {}, Announce:MapPinLink(mapID, x, y)
    if pin then
        wheres[1] = format("%s (%d, %d)", pin, math.floor(x * 100), math.floor(y * 100))
        wheres[2] = pin
    end
    wheres[#wheres + 1] = place
    local left = sample and 15 * 60 or camp and ns.Camps:TimeLeft(camp)
    local minutes = left and math.max(1, math.floor(left / 60))
    local time = not minutes and L["a while"] or minutes == 1 and L["a minute"] or format(L["%d minutes"], minutes)
    local message
    for _, where in ipairs(wheres) do
        for _, offers in ipairs(OfferLists(camp, sample)) do
            message = Fill(wording, { where = where, place = place, offers = offers, time = time })
            if #message <= room then return message end
        end
    end
    return CutBytes(message, room)
end

-- The camp here (or the last one you were at, while it's still going),
-- announced in Say or General chat: short and plain, or in your own wording
-- (Options). Each carries the camp's map pin. room: the most it can take (one
-- chat message unless less is given).
function Announce:CampMessage(room)
    local camp, here = self:CampToAnnounce()
    local mapID, x, y
    if camp then mapID, x, y = camp.mapID, camp.x, camp.y else mapID, x, y = ns.GetPlayerLocation() end
    local place = CampPlace(camp, here)
    if self:Style() == "own" then return OwnMessage(self:Wording(), camp, mapID, x, y, place, room) end
    return ShortMessage(camp, mapID, x, y, place, room)
end

-- The editor's preview: wording (as typed) as General would post it, tagged
-- or not, for the camp you'd announce; away from one, for where you stand,
-- with a sample of what a camp offers.
function Announce:Preview(wording, tagged)
    wording = self:CleanWording(wording)
    if wording == "" then wording = self:DefaultWording() end
    local camp, here = self:CampToAnnounce()
    local mapID, x, y
    if camp then mapID, x, y = camp.mapID, camp.x, camp.y else mapID, x, y = ns.GetPlayerLocation() end
    local signed = L["%s - Happy Camper addon"]
    local room = tagged and MAX_MESSAGE - #format(signed, "") or MAX_MESSAGE
    local message = OwnMessage(wording, camp, mapID, x, y, CampPlace(camp, here), room, not camp)
    return tagged and format(signed, message) or message
end

-- The name of the place a meet-up is at: the sub-zone you're in if you're
-- there, else the meet-up's own area (or zone), from the map. Remembered per
-- spot, as finding the area means looking at many points around it.
local NEAR_MEETUP = 100 -- yards
local meetUpPlaces = {}

local function MeetUpPlace(request)
    local yards = ns.Camps:DistanceFromPlayer(request)
    if yards and yards <= NEAR_MEETUP then return ns.PlaceName() end
    local key = format("%d:%d:%d", request.mapID, math.floor(request.x * 10000 + 0.5), math.floor(request.y * 10000 + 0.5))
    if not meetUpPlaces[key] then
        -- elsewhere (true): from the map, not from where you're standing.
        local ok, location = pcall(ns.Location.Describe, ns.Location, request.mapID, request.x, request.y, true)
        local info = C_Map.GetMapInfo(request.mapID)
        meetUpPlaces[key] = ok and location and (location.area or location.zone) or (info and info.name) or L["here"]
    end
    return meetUpPlaces[key]
end

-- e.g. "Seeking a blacksmith and a tailor to share a campfire near Razor Hill.
-- All travelers welcome. [Map Pin Location]" (the pin is the meet-up point).
-- To fit in one chat message: without the welcome, then naming fewer people
-- ("... and others"), then just companions. room as for CampMessage.
function Announce:RequestMessage(request, room)
    -- A class buff wanted asks for its class ("a priest"), once each.
    local people, named = {}, {}
    for _, profession in ipairs(ns.PROFESSIONS) do
        local entry = (request.classWants or {})[profession.id] and ns.CLASS_BUFFS[profession.id]
        local person = entry and ns.CLASS_NAMES[entry.class].person or profession.person
        if request.wants[profession.id] and not named[person] then
            people[#people + 1] = person
            named[person] = true
        end
    end
    local place = MeetUpPlace(request)
    local function Seeking(who) return format(L["Seeking %s to share a campfire near %s."], who, place) end
    local welcome = L["All travelers welcome."]
    local candidates = {}
    if #people > 0 then
        candidates[1] = { Seeking(JoinList(people)), welcome }
        candidates[2] = { Seeking(JoinList(people)) }
        for n = #people - 1, 1, -1 do
            candidates[#candidates + 1] = { Seeking(format(L["%s and others"], table.concat(people, ", ", 1, n))) }
        end
    end
    candidates[#candidates + 1] = { Seeking(L["companions"]), welcome }
    candidates[#candidates + 1] = { Seeking(L["companions"]) }
    return FirstThatFitsWithPin(candidates, self:MapPinLink(request.mapID, request.x, request.y), room)
end

-- The number of your General chat channel, whatever it is (players can reorder
-- their channels, and /1 isn't always General), or nil if you're not in it.
local function GeneralChannel()
    local get = C_ChatInfo.GetGeneralChannelLocalID
    local ok, id = pcall(get or function() end)
    return ok and type(id) == "number" and id > 0 and id or nil
end

-- channel is "SAY", "EMOTE", "PARTY", "RAID" or "GENERAL" (the General chat
-- channel). Returns true if sent.
function Announce:Send(message, channel, interval, target)
    local now, key = GetTime(), target and (channel .. ":" .. target) or channel
    if lastSent[key] and now - lastSent[key] < (interval or CLICK_INTERVAL) then
        ns.Print(L["Please wait a few seconds before announcing again."])
        return false
    end
    if C_ChatInfo.InChatMessagingLockdown and C_ChatInfo.InChatMessagingLockdown() then
        ns.Print(L["Chat is restricted right now."])
        return false
    end

    local send = C_ChatInfo.SendChatMessage
    if not send then return false end
    if channel == "GENERAL" then
        local general = GeneralChannel()
        if not general then
            ns.Print(L["You're not in the General chat channel here."])
            return false
        end
        send(message, "CHANNEL", nil, tostring(general))
    elseif channel == "WHISPER" then
        send(message, "WHISPER", nil, target)
    else
        send(message, (channel == "EMOTE" or channel == "PARTY" or channel == "RAID") and channel or "SAY")
    end
    lastSent[key] = now
    return true
end

-- What a Say or General button posts: getMessage(room)'s text, or nil. In
-- General it ends with " - Happy Camper addon", and the text before it is
-- made to leave room for that; camp buttons in your own wording leave it off
-- if you've said so (the editor's tickbox, announceTag).
local function ButtonMessage(getMessage, channel, camp)
    local untagged = camp and Announce:Style() == "own" and ns.db.announceTag == false
    if channel ~= "GENERAL" or untagged then return getMessage(MAX_MESSAGE) end
    local signed = L["%s - Happy Camper addon"]
    local message = getMessage(MAX_MESSAGE - #format(signed, ""))
    return message and format(signed, message)
end

-- Adds Say and General buttons to a frame. getMessage(room) returns the text
-- (at most room bytes), or nil when there's nothing to announce. camp: they
-- announce a camp, in your own wording if Options says so (their tooltips say where).
-- Both the same size: width and height (80 x 22 unless given).
function Announce:CreateButtons(parent, getMessage, width, height, camp)
    local buttons = {}
    for i, channel in ipairs({ "SAY", "GENERAL" }) do
        local button = ns.Style:Button(parent, width or 80, channel == "SAY" and L["Say"] or L["General"], function()
            local message = ButtonMessage(getMessage, channel, camp)
            if message then Announce:Send(message, channel) end
        end, height or 22)
        ns.Style:InfoTooltip(button, channel == "SAY" and L["Say nearby:"] or L["Post in General chat:"], function()
            local message = ButtonMessage(getMessage, channel, camp)
            if not message then return L["Nothing to announce here."] end
            if camp and ns.Style:ShowHelp() then
                return message .. "\n\n" .. L["Write your own in Options: My own camp announcement."]
            end
            return message
        end)
        buttons[i] = button
    end
    buttons[2]:SetPoint("LEFT", buttons[1], "RIGHT", 6, 0)
    ns.Style:SameWidth(buttons)
    return buttons
end
