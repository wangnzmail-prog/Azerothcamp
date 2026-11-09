-- Happy Camper. Copyright (c) 2026 Torridon. All rights reserved; see LICENSE.
local _, ns = ...
local L = ns.L

-- Who else with the addon is at your camp. Presence goes over the camp network
-- while you're at a camp. (The Social tab's chat lines were here: they're in
-- parked/social-tab/ until the tab is reworked.)

local Social = {}
ns.Social = Social

local CIRCLE_RADIUS = 60      -- yards: players this close share your camp
-- Presence goes to everyone on the realm, but only matters to players at the
-- same camp (and to anyone you take layer invite requests from). So after
-- your hello, it goes again every HEARTBEAT seconds only while someone else
-- with the addon is at your camp, or you take layer invite requests: anyone
-- arriving later says hello, and you answer. (Under PRESENCE_TIMEOUT, which
-- is 150 in older versions too.) Before telling everyone about objects at a
-- camp, you say you're there again if it's been a while (Remind).
local HEARTBEAT = 90          -- seconds between presence updates while it matters
local REMIND_AFTER = 120      -- seconds: presence older than this is sent again before a report
local PRESENCE_TIMEOUT = 150  -- forget players not heard from for this long
local HELLO_REPLY_COOLDOWN = 15
local HELLO_FRESH = 60        -- seconds: your presence this recent already reached a newcomer
local HELLO_REPLIERS = 4      -- at a busy camp, about this many answer each hello
local CAMP_CHECK = 2          -- seconds between looks at which camp you're at (each goes through every known camp)

local people = {} -- [full name] = profile from the network
local atCamp = false
local helloSent = false -- your arrival was announced (needs a known camp)
local helloCampID       -- the camp it was announced at
local pendingCamp       -- another camp (or false: none) seen once; acted on when seen again
local lastHeartbeat = 0
local lastCampCheck = 0
local lastHelloReply = 0
local lastForget = 0

-- Your profile ------------------------------------------------------------------

function Social:MyProfile()
    local _, classFile = UnitClass("player")
    return {
        name = ns.playerName,
        class = classFile,
        level = UnitLevel("player"),
        professions = ns.GetMyProfessions(),
    }
end

-- Presence ------------------------------------------------------------------------

function Social:IsAtCamp()
    return atCamp
end

local function EncodeProfessions(professions)
    local parts = {}
    for skillLine, rank in pairs(professions) do parts[#parts + 1] = skillLine .. ":" .. rank end
    return table.concat(parts, ",")
end

-- The camp you're at, if it's known. A fire only becomes a camp once someone
-- has rested at it and got its buffs (Camps:ConfirmCampHere).
function Social:CampHere()
    local camp = ns.Camps:NearPlayer(CIRCLE_RADIUS)
    return camp and ns.Camps:Offers(camp) and camp or nil
end

-- Presence says which camp you're at (its ID), never where you're standing.
-- False if you're not at a known camp (camp: the one here, if already looked up).
-- A last field "i" says you take layer invite requests (LayerInvites.lua);
-- with the option off there's no such field.
local function Present(hello, camp)
    if not camp then return false end
    -- The last camp you were at, which you can still announce after you leave (Announce.lua).
    if ns.charDB then ns.charDB.lastCampID = camp.id end
    local profile = Social:MyProfile()
    ns.Comm:SendPresence(format("P;%d;%s;%s;%d;%s%s", hello and 1 or 0, camp.id, profile.class or "",
        profile.level or 0, EncodeProfessions(profile.professions), ns.LayerInvites:IsOn() and ";i" or ""))
    if hello then helloCampID = camp.id end
    lastHeartbeat = GetTime()
    return true
end

function Social:SendPresence(hello)
    return Present(hello, self:CampHere())
end

-- How many others with the addon say they're at a camp.
local function OthersAt(campID)
    local n = 0
    for _, person in pairs(people) do
        if person.campID == campID then n = n + 1 end
    end
    return n
end

local function AnyoneElseAt(camp)
    return OthersAt(camp.id) > 0
end

-- You're about to report objects at a camp (Comm's O and E): players only take
-- those from someone they know is there, so if your presence went a while ago
-- (no heartbeats while you're alone), it goes again first.
function Social:Remind(campID)
    if atCamp and helloSent and campID == helloCampID and GetTime() - lastHeartbeat >= REMIND_AFTER then
        Present(false, self:CampHere())
    end
end

-- Called every tick: announces arrival, heartbeats and departure. Which camp
-- you're at is looked at again every CAMP_CHECK seconds.
function Social:Update()
    local now = GetTime()
    local nowAtCamp = ns.state.nearCamp or ns.state.restAuraInstance ~= nil
    if nowAtCamp and not atCamp then
        atCamp, lastCampCheck = true, now
        helloSent = self:SendPresence(true)
    elseif nowAtCamp and now - lastCampCheck >= CAMP_CHECK then
        lastCampCheck = now
        local camp = self:CampHere()
        if not helloSent then
            -- Near a fire the addon didn't know: say hello once it's known or you sit at it.
            helloSent = Present(true, camp)
        elseif (camp and camp.id) ~= helloCampID then
            -- Walked to another camp, or away from this one, still near a fire:
            -- the last camp's song stops, and the new camp hears hello (or, at
            -- no camp, everyone hears you left). Only once it's seen at two
            -- looks in a row: flipping back and forth would repeat a hello or Z
            -- within Comm:IsRepeat's window, which drops it, leaving the others
            -- listing you at the wrong camp.
            local seen = camp and camp.id or false
            if pendingCamp ~= seen then
                pendingCamp = seen
            else
                pendingCamp = nil
                ns.Music:OnLeftCamp()
                helloSent = Present(true, camp)
                if not helloSent then
                    helloCampID = nil
                    ns.Comm:SendPresence("Z")
                end
            end
        else
            pendingCamp = nil
            if now - lastHeartbeat >= HEARTBEAT and camp and (AnyoneElseAt(camp) or ns.LayerInvites:IsOn()) then
                Present(false, camp)
            end
        end
    elseif not nowAtCamp and atCamp then
        local announced = helloSent
        atCamp, helloSent, helloCampID, pendingCamp = false, false, nil, nil
        ns.Music:OnLeftCamp()
        -- Only say you left if you said you were there (a bare or unknown fire sends nothing).
        if announced then ns.Comm:SendPresence("Z") end
    end

    if now - lastForget < CAMP_CHECK then return end
    lastForget = now
    for name, person in pairs(people) do
        if now - person.seen > PRESENCE_TIMEOUT then
            people[name] = nil
            if person.invites then ns.OnCampsChanged() end -- their camp's pin no longer offers to ask
        end
    end
end

-- flags: a last field, "i" if they take layer invite requests (LayerInvites.lua).
function Social:OnPresence(sender, hello, campID, class, level, professionList, flags)
    level = tonumber(level)
    if type(campID) ~= "string" or #campID > 80 or not campID:match("^.+:%d+$") then return end

    local professions = {}
    for skillLine, rank in (professionList or ""):gmatch("(%d+):(%d+)") do
        skillLine, rank = tonumber(skillLine), tonumber(rank)
        if ns.PROFESSION_BY_ID[skillLine] then professions[skillLine] = math.min(rank, 1000) end
    end
    -- None listed: they're the ones last heard (a later version may leave
    -- them out of presence that repeats them).
    local old = people[sender]
    if not next(professions) and old then professions = old.professions end
    local person = {
        name = sender,
        class = type(class) == "string" and class:match("^%u+$") or nil,
        level = level and math.min(level, 100) or 0,
        professions = professions,
        campID = campID,
        invites = type(flags) == "string" and flags:find("i", 1, true) ~= nil or nil,
        seen = GetTime(),
    }
    people[sender] = person
    -- Only someone arriving at or leaving your camp changes what's on screen
    -- straight away, or a camp gaining or losing someone who takes layer
    -- invite requests (its pin); heartbeats from other camps just keep them listed.
    local myCamp = self:MyCamp()
    local function InvitesAt(p) return p and p.invites and p.campID or nil end
    if self:IsNear(person, myCamp) ~= (old ~= nil and self:IsNear(old, myCamp))
        or InvitesAt(person) ~= InvitesAt(old) then ns.OnCampsChanged() end

    -- Someone just arrived: introduce yourself if you're at the same camp, and
    -- send the camp's song if you're playing it.
    -- Presence goes to everyone, so one of yours in the last minute reached
    -- them already; at a busy camp only about HELLO_REPLIERS answer, by chance
    -- (the others' heartbeats follow within HEARTBEAT seconds).
    if hello == "1" and atCamp and self:IsNear(person, self:MyCamp()) then
        ns.Music:OnArrival(campID)
        local now = GetTime()
        if now - lastHelloReply > HELLO_REPLY_COOLDOWN and now - lastHeartbeat >= HELLO_FRESH
            and math.random() * OthersAt(campID) <= HELLO_REPLIERS then
            lastHelloReply = now
            C_Timer.After(1 + math.random() * 2, function() Social:SendPresence(false) end)
        end
    end
end

-- Drops blocked players from the people at your camp.
function Social:ForgetBlocked()
    for name in pairs(people) do
        if ns.IsBlocked(name) then people[name] = nil end
    end
    ns.OnCampsChanged()
end

function Social:OnLeft(sender)
    local person = people[sender]
    if not person then return end
    people[sender] = nil
    if person.invites or self:IsNear(person, self:MyCamp()) then ns.OnCampsChanged() end
end

-- The camp you're at, if the addon knows it.
function Social:MyCamp()
    return atCamp and self:CampHere() or nil
end

-- A person is with you when they say they're at the same camp.
function Social:IsNear(person, myCamp)
    return myCamp ~= nil and person.campID == myCamp.id
end

-- Whether a player says they're at this camp (for accepting what they report about it).
function Social:IsPersonAtCamp(name, campID)
    local person = people[name]
    return person ~= nil and person.campID == campID
end

-- Other addon users at your camp, sorted by name.
function Social:PeopleHere()
    local list, myCamp = {}, self:MyCamp()
    if not myCamp then return list end
    for _, person in pairs(people) do
        if self:IsNear(person, myCamp) then list[#list + 1] = person end
    end
    table.sort(list, function(a, b) return a.name < b.name end)
    return list
end

-- Players at a camp now who take layer invite requests (LayerInvites.lua),
-- sorted by name. Only while they're there: leaving (Z) or going quiet
-- (PRESENCE_TIMEOUT) drops them.
function Social:InvitersAt(campID)
    local list = {}
    for _, person in pairs(people) do
        if person.invites and person.campID == campID then list[#list + 1] = person end
    end
    table.sort(list, function(a, b) return a.name < b.name end)
    return list
end
