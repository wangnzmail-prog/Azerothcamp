-- Happy Camper. Copyright (c) 2026 Torridon. All rights reserved; see LICENSE.
local _, ns = ...
local L = ns.L

-- How many people use Happy Camper. Every player with the addon notes each
-- other user it hears on the camp network: name, first and last seen, and
-- their version. Nothing extra is sent for this: the query everyone sends when
-- they log in (Q) carries the sender's version and how many users they know
-- of, so everyone also learns the biggest count anyone has reported.
-- Saved account-wide in HappyCamperDB.users and HappyCamperDB.census.
-- Also newer versions: the notice, and asking which version is the latest.

local Stats = {}
ns.Stats = Stats

local MAX_USERS = 10000
local FORGET_AFTER = 180 * 24 * 3600 -- users not seen for 180 days are dropped
local DAY = 24 * 3600

function Stats:Version()
    local get = C_AddOns and C_AddOns.GetAddOnMetadata
    return (get and get("HappyCamper", "Version")) or "?"
end

-- Newer versions ----------------------------------------------------------------
-- Other users' versions arrive with their login query, their "what's the latest
-- version?" question and its answer (below), and the developer's update
-- announcement (Broadcast.lua). When a newer one is heard, a line in your chat
-- window (no one else sees it) says so, once a session. Anyone could claim any
-- version, so it's believed only once two different players report it, or one
-- of the developer's characters does (ns.IsDeveloper), and only if it's at most
-- one major version ahead. Once one is believed, your copy knows it isn't the
-- latest (ns.db.notLatest, until your own version changes).

local reporters = {} -- [version] = { [name] = true }
local believed = {}  -- [version] = true: believed this session
local announced      -- the version you were told about this session

-- "0.8.3" -> { 0, 8, 3, 0 }, "0.8.3.1" (a fix release between features) ->
-- { 0, 8, 3, 1 }, or nil if it isn't a plain version number: a development
-- copy ("0.8.4-dev") is never compared, so it neither hears nor causes notices.
local function Parse(version)
    local a, b, c, d = tostring(version or ""):match("^(%d+)%.(%d+)%.(%d+)%.?(%d*)$")
    return a and { tonumber(a), tonumber(b), tonumber(c), tonumber(d) or 0 }
end

local function IsNewer(a, b)
    for i = 1, 4 do
        if a[i] ~= b[i] then return a[i] > b[i] end
    end
    return false
end

-- How a version compares with yours: 1 newer, 0 the same, -1 older; nil if
-- either isn't a plain version (a development copy's).
function Stats:Compare(version)
    local mine, theirs = Parse(self:Version()), Parse(version)
    if not (mine and theirs) then return nil end
    return IsNewer(theirs, mine) and 1 or IsNewer(mine, theirs) and -1 or 0
end

-- Your copy knows it isn't the latest (a newer version was believed): it no
-- longer answers "what's the latest version?". Kept with your version, so
-- updating clears it (CheckOwnVersion).
function Stats:IsOutdated()
    local mark = ns.db.notLatest
    return type(mark) == "table" and mark.version == self:Version()
end

local pendingAnswer -- your answer waiting to go (OnVersionQuestion)

local function MarkOutdated(version)
    local mark = ns.db.notLatest
    if Stats:IsOutdated() and Parse(mark.newer) and not IsNewer(Parse(version), Parse(mark.newer)) then return end
    ns.db.notLatest = { version = Stats:Version(), newer = version }
    pendingAnswer = nil
end

-- At login: a mark made while you ran another version is forgotten.
function Stats:CheckOwnVersion()
    local mark = ns.db.notLatest
    if mark ~= nil and (type(mark) ~= "table" or mark.version ~= self:Version()) then ns.db.notLatest = nil end
end

-- A player reports a version. told: the developer's announcement already
-- said so (no notice of its own). Returns true if a newer version is believed.
function Stats:CheckVersion(name, version, told)
    local mine, theirs = Parse(self:Version()), Parse(version)
    if not (mine and theirs) or not IsNewer(theirs, mine) or theirs[1] > mine[1] + 1 then return false end
    reporters[version] = reporters[version] or {}
    reporters[version][name] = true
    if ns.Count(reporters[version]) < 2 and not ns.IsDeveloper(name) then return false end
    believed[version] = true
    MarkOutdated(version)
    if announced and not IsNewer(theirs, Parse(announced)) then return true end
    announced = version
    if not told then
        ns.Print(L["A new version of Happy Camper (%s) is out. You have %s: update it from CurseForge."], version, self:Version())
    end
    return true
end

-- "What's the latest version?" ---------------------------------------------------
-- Release copies (not "-dev" ones) ask the camp network (VQ, with their own
-- version) once they've joined the camp channel, and every few hours after. A
-- copy newer than the asker's answers with its version (VA), unless it has
-- learned it isn't the latest itself (IsOutdated). Only one answer should go
-- out: each copy that could answer waits a random moment, and stays quiet if
-- it hears an answer as new as its own first; with many copies about, only
-- about ANSWERERS of them take part at all. Answers are believed like any
-- other report (CheckVersion): when one player's word isn't enough, the asker
-- asks once more, naming them (notFrom), so someone else answers. Each
-- player's questions are answered at most every QUESTION_COOLDOWN seconds (a
-- follow-up apart), and nothing is asked or answered while channel work is
-- paused (Comm.paused). Development copies never ask, answer or count.

local ASK_DELAY = 30            -- seconds after joining the camp channel (plus up to 30 more)
local ASK_EVERY = 3 * 3600      -- and again this often while online (plus up to 10 minutes)
local ANSWER_WAIT = { 2, 30 }   -- seconds an answer waits, at random, for someone else's
local ANSWERERS = 8             -- about how many copies take part in answering one question
local LIKELY_ONLINE = 3 * 3600  -- users heard this recently count as maybe online
local QUESTION_COOLDOWN = 10 * 60
local FOLLOW_UP_DELAY = 10      -- seconds before asking again for a second opinion
local FOLLOW_UP_WINDOW = 120    -- an answer this long after your question can lead to one
local allowQuestion = ns.FloodLimit(10) -- everyone's questions together: 10 a minute
local asking = false            -- the questions are under way this session
local askedAt                   -- when you last asked (GetTime)
local followedUp = {}           -- [version] = true: asked again about it this session

-- A version from a message, or nil.
local function ValidVersion(version)
    return type(version) == "string" and not ns.IsSecret(version) and #version <= 16
        and version:match("^[%w%.%-]+$") and version or nil
end
Stats.ValidVersion = ValidVersion

function Stats:AskLatest(notFrom)
    if not Parse(self:Version()) or ns.Comm.paused then return end
    askedAt = GetTime()
    ns.db.versionAskedAt = GetServerTime()
    ns.Comm:SendVersionQuestion(self:Version(), notFrom)
end

-- You've joined the camp channel: the first question goes a little later, then
-- one every few hours. Joining again (a kick, a backup channel) doesn't start
-- another round, and nor does a /reload or another character: when the
-- account last asked is saved, and the next question waits for its turn.
function Stats:StartAsking()
    if asking or not Parse(self:Version()) then return end
    asking = true
    local function Ask()
        Stats:AskLatest()
        C_Timer.After(ASK_EVERY + math.random(0, 600), Ask)
    end
    local since = GetServerTime() - (ns.db.versionAskedAt or 0)
    C_Timer.After(since >= 0 and since < ASK_EVERY and ASK_EVERY - since or ASK_DELAY + math.random(0, 30), Ask)
end

-- About how many copies could answer a question: users heard lately whose
-- version is as new as yours, and you.
function Stats:LikelyAnswerers()
    local now, count, mine = GetServerTime(), 1, Parse(self:Version())
    if not mine then return count end
    for name, user in pairs(ns.db.users) do
        if name ~= ns.playerName and now - (user.l or 0) <= LIKELY_ONLINE then
            local theirs = Parse(user.v)
            if theirs and not IsNewer(mine, theirs) then count = count + 1 end
        end
    end
    return count
end

function Stats:OnVersionQuestion(sender, version, notFrom)
    version = ValidVersion(version)
    if not version then return end
    self:Seen(sender, version) -- the asker's version counts like a login query's
    -- Only a copy newer than the asker's has news for them (never a development copy).
    if self:Compare(version) ~= -1 or ns.Comm.paused or self:IsOutdated() then return end
    if type(notFrom) == "string" and notFrom ~= "" and notFrom == ns.playerName then return end
    if pendingAnswer then return end -- the answer already waiting answers this question too
    local followUp = type(notFrom) == "string" and notFrom ~= ""
    if not allowQuestion(sender .. (followUp and "\0again" or ""), QUESTION_COOLDOWN) then return end
    if math.random() * self:LikelyAnswerers() > ANSWERERS then return end
    local answer = {}
    pendingAnswer = answer
    C_Timer.After(ANSWER_WAIT[1] + math.random() * (ANSWER_WAIT[2] - ANSWER_WAIT[1]), function()
        if pendingAnswer ~= answer then return end -- someone else answered first
        pendingAnswer = nil
        if ns.Comm.paused or Stats:IsOutdated() then return end
        ns.Comm:SendVersionAnswer(Stats:Version())
    end)
end

function Stats:OnVersionAnswer(sender, version)
    version = ValidVersion(version)
    if not version then return end
    self:Seen(sender, version) -- believed under the usual rule (CheckVersion)
    local mine, theirs = Parse(self:Version()), Parse(version)
    if not (mine and theirs) or theirs[1] > mine[1] + 1 then return end
    -- An answer as new as yours: yours isn't needed.
    if not IsNewer(mine, theirs) then pendingAnswer = nil end
    -- A newer version on one player's word, just after you asked: ask once
    -- more, naming them, so someone else answers.
    if IsNewer(theirs, mine) and not believed[version] and not followedUp[version] and askedAt
        and GetTime() - askedAt <= FOLLOW_UP_WINDOW and not ns.Comm.paused then
        followedUp[version] = true
        C_Timer.After(FOLLOW_UP_DELAY, function()
            if not believed[version] then Stats:AskLatest(sender) end
        end)
    end
end

-- The counts (Counts) as last worked out, for up to COUNTS_FOR seconds: the
-- Camp Builder shows them on every refresh. Cleared when they may have changed.
local COUNTS_FOR = 60
local counts, countedAt
local userCount -- how many users are saved (counted once, then kept up to date)

-- Records that a user was heard from (version only when they said): when they
-- were last heard (l) and their version (v).
function Stats:Seen(name, version)
    if version and name ~= ns.playerName then self:CheckVersion(name, version) end
    local users = ns.db.users
    local user = users[name]
    local now = GetServerTime()
    if not user then
        userCount = userCount or ns.Count(users)
        if userCount >= MAX_USERS then return end
        user = {}
        users[name] = user
        userCount = userCount + 1
        counts = nil
    elseif now - (user.l or 0) > DAY then
        counts = nil -- back after a while: today's and this week's counts change
    end
    user.l = now
    if version then user.v = version end
end

-- Forgets a user (a name that turned out to be yours under another spelling).
function Stats:Forget(name)
    if ns.db.users[name] and userCount then userCount = userCount - 1 end
    ns.db.users[name] = nil
    counts = nil
end

-- A user's reported count: keeps the biggest one heard.
function Stats:OnCensus(name, count)
    local census = ns.db.census
    if count > (census.n or 0) then
        census.n, census.by, census.at = count, name, GetServerTime()
        counts = nil
    end
end

-- Drops users not seen for a long time.
-- (Versions before 0.8.7 also saved when each was first heard: no longer kept.)
function Stats:Prune()
    local cutoff = GetServerTime() - FORGET_AFTER
    for name, user in pairs(ns.db.users) do
        if (user.l or 0) < cutoff then ns.db.users[name] = nil else user.f = nil end
    end
    userCount, counts = nil, nil
end

-- { total, day, week, largest }: users you know of, seen in the last day and
-- week, and the biggest count anyone has reported (at least your own). Don't
-- change the table: it's kept for the next call.
function Stats:Counts()
    local now = GetServerTime()
    if counts and now - countedAt < COUNTS_FOR then return counts end
    local total, day, week = 0, 0, 0
    for _, user in pairs(ns.db.users) do
        total = total + 1
        if now - (user.l or 0) <= DAY then day = day + 1 end
        if now - (user.l or 0) <= 7 * DAY then week = week + 1 end
    end
    counts, countedAt = { total = total, day = day, week = week, largest = math.max(total, ns.db.census.n or 0) }, now
    return counts
end

function Stats:Summary()
    local c = self:Counts()
    return format(L["Happy Campers seen: %d (%d today, %d this week)"], c.total, c.day, c.week)
end
