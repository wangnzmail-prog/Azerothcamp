-- Happy Camper. Copyright (c) 2026 Torridon. All rights reserved; see LICENSE.
local _, ns = ...
local L = ns.L

-- Camp Builder requests: a player asks for camp buffs, players who can place
-- those objects (or give the same stat with a class buff) sign up, and
-- everyone gets the meet-up point on the map. Shared over the camp network
-- like camps.
--
-- request = {
--   id        "<creator full name>:<server time>"
--   creator   full name
--   mapID, x, y, continent, wx, wy   meet-up point
--   createdAt, expiresAt             server times
--   wants     [skillLineID] = true: every camp buff wanted
--   classWants [skillLineID] = true: the wants asked for as a class buff
--             (ns.CLASS_BUFFS: Power Word: Fortitude for Stamina...), which
--             take no slot at the fire; only players who give it can meet one
--   minTier   [skillLineID] = 2 or 3: the lowest tier wanted (1 when not listed).
--             A T1+ object want can also be met by a class buff for its stat;
--             T2+ ones need the object, for its workspace or service
--   brings    [skillLineID] = tier: the camp objects the requester brings
--             (Cooking's tier is the campfire: 1 Basic, 2 Journeyman, 3 Expert)
--   buffs     [skillLineID] = true: class buffs the requester can give that do a
--             camp buff's job (Arcane Intellect for Intellect; a paladin's
--             blessings, one per player)
--   helpers   [full name] = skillLineID of the object they'll bring (0: none,
--             class buffs only); helperTiers [full name] = its tier;
--             helperBuffs [full name] = { [skillLineID] = true }: the wanted
--             stats they give with a class buff (a paladin: one blessing)
--   classBuffSignups  the requester's copy takes class-buff sign-ups (false for
--             a request from a version before 0.8.5, which would ignore them)
--   realm
-- }

local Requests = {}
ns.Requests = Requests

Requests.DURATION = 30 * 60
local MAX_REQUESTS = 50
local MAX_HELPERS = 10
local FULFIL_RADIUS = 60   -- yards: a fire lit this close to the meet-up fulfils it
local NOTIFY_CREATOR_COOLDOWN = 600 -- seconds: at most one notice per requester in this time
local allowNotice = ns.FloodLimit(3) -- at most 3 notices a minute

local function Now() return GetServerTime() end

local Count = ns.Count

function Requests:All()
    return ns.db.requests
end

function Requests:Get(id)
    return ns.db.requests[id]
end

function Requests:Mine()
    return ns.state.myRequestID and ns.db.requests[ns.state.myRequestID]
end

function Requests:IsMine(request)
    return request.creator == ns.playerName
end

function Requests:TimeLeft(request)
    return math.max(0, request.expiresAt - Now())
end

-- Your professions: [skillLineID] = skill level.
function ns.GetMyProfessions()
    local skills = {}
    local indices = { GetProfessions() }
    for i = 1, 6 do
        local index = indices[i]
        if index then
            local name, _, rank, _, _, _, skillLine = GetProfessionInfo(index)
            local profession = ns.PROFESSION_BY_ID[skillLine]
            if not profession then
                for _, candidate in ipairs(ns.PROFESSIONS) do
                    if candidate.name == name then profession = candidate end
                end
            end
            if profession then skills[profession.id] = rank or 0 end
        end
    end
    return skills
end

local COOKING = 185
local KIT_TIER = { [3] = 1, [5] = 2, [10] = 3 }  -- campfire kit size to tier

-- The tier of a profession's camp object in your bags (0 if none). For
-- Cooking, your biggest campfire kit.
function Requests:CarriedTier(skillLine)
    if skillLine == COOKING then
        local _, _, kitSlots = ns.Widget:CampItems()
        return KIT_TIER[kitSlots or 0] or 0
    end
    local best = 0
    for _, entry in ipairs(ns.Widget:CampObjects()) do
        local _, _, objectSkill, tier = ns.ObjectByName(ns.ObjectForSpell(entry.spell))
        if objectSkill == skillLine then best = math.max(best, tier or 1) end
    end
    return best
end

-- The camp object in your bags for a profession (its best tier), as an item
-- ID; for Cooking, your biggest campfire kit.
function Requests:CarriedItem(skillLine)
    if skillLine == COOKING then return (ns.Widget:CampItems()) end
    local best, item = 0, nil
    for _, entry in ipairs(ns.Widget:CampObjects()) do
        local _, _, objectSkill, tier = ns.ObjectByName(ns.ObjectForSpell(entry.spell))
        if objectSkill == skillLine and (tier or 1) > best then best, item = tier or 1, entry.item end
    end
    return item
end

-- The best tier of a profession's camp object whose recipe you've learned and
-- your skill reaches (0 if none), and that recipe. For Cooking, the campfire
-- kits. ranks: your professions (ns.GetMyProfessions), if already looked up.
function Requests:RecipeTier(skillLine, ranks)
    local rank = (ranks or ns.GetMyProfessions())[skillLine] or 0
    if rank == 0 then return 0 end
    local kit = skillLine == COOKING
    local recipes = kit and ns.KIT_RECIPES or ns.PROFESSION_BY_ID[skillLine].recipes or {}
    for tier = 3, 1, -1 do
        if ns.ReachesTier(rank, tier, kit) then
            for _, recipeID in ipairs(ns.RecipeIDs(recipes, tier)) do
                if ns.Group:KnowsRecipe(recipeID) then return tier, recipeID end
            end
        end
    end
    return 0
end

-- The best tier of a profession's camp object you can bring (0 if none): one
-- in your bags, or one whose recipe you've learned. Skill alone says nothing:
-- some recipes have to be found first. For Cooking, the biggest campfire kit.
function Requests:MyTier(skillLine, ranks)
    return math.max(self:CarriedTier(skillLine), (self:RecipeTier(skillLine, ranks)))
end

-- Class buffs that do a camp buff's job are in ns.CLASS_BUFFS (Data.lua).

-- Whether you know any of these spells (any rank); without the game's answer,
-- baseline ones count and talent ones don't.
local function KnowsAny(spells, talent)
    if not IsPlayerSpell then return not talent end
    for _, spellID in ipairs(spells or {}) do
        if IsPlayerSpell(spellID) then return true end
    end
    return false
end

-- What you could bring to a camp, in list order: { key, skillLine, tier,
-- carried, carriedTier, makeTier }, camp objects (you can place one: they share
-- an hour's cooldown) and your campfire kit. carried: it's in your bags, and
-- tier is the one in your bags (not a better one you could make instead).
function Requests:BringOptions()
    local options, ranks = {}, ns.GetMyProfessions()
    for _, profession in ipairs(ns.PROFESSIONS) do
        local makeTier = self:MyTier(profession.id, ranks)
        local carriedTier = self:CarriedTier(profession.id)
        if makeTier > 0 then
            options[#options + 1] = { key = "item:" .. profession.id, skillLine = profession.id,
                tier = carriedTier > 0 and carriedTier or makeTier, carried = carriedTier > 0,
                carriedTier = carriedTier, makeTier = makeTier, kit = profession.id == COOKING }
        end
    end
    return options
end

-- Your class buffs that do a camp buff's job, in list order: { skillLine, buff
-- = its name, blessing, party, talent } (ns.CLASS_BUFFS). Talent ones only if
-- you know them. A paladin can give any blessing they know, one per player, so
-- blessings don't cover a camp buff for everyone.
function Requests:ClassBuffs()
    local list = {}
    local _, class = UnitClass("player")
    for _, profession in ipairs(ns.PROFESSIONS) do
        local entry = ns.CLASS_BUFFS[profession.id]
        if entry and entry.class == class and KnowsAny(profession.conflictSpells, entry.talent) then
            list[#list + 1] = { skillLine = profession.id, buff = profession.conflicts, blessing = entry.blessing,
                party = entry.party, talent = entry.talent }
        end
    end
    return list
end

-- A class buff's name; one that reaches only the giver's party (a totem, an
-- aura) says so, unless plain: "Strength of Earth Totem (needs a party)".
function Requests:BuffName(skillLine, plain)
    local profession, entry = ns.PROFESSION_BY_ID[skillLine], ns.CLASS_BUFFS[skillLine]
    local name = profession and (profession.conflicts or profession.buff) or "?"
    if entry and entry.party and not plain then return format(L["%s (needs a party)"], name) end
    return name
end

-- A set of class buffs ([skillLine] = true) by name, in list order: "Power
-- Word: Fortitude and Divine Spirit".
function Requests:BuffNames(buffs)
    local names = {}
    for _, profession in ipairs(ns.PROFESSIONS) do
        if (buffs or {})[profession.id] then names[#names + 1] = self:BuffName(profession.id) end
    end
    return ns.JoinList(names)
end

-- A class buff with its class, as the Request menu offers it: "Blessing of
-- Might (paladin)", "Strength of Earth Totem (shaman, needs a party)".
function Requests:ClassBuffLabel(skillLine)
    local entry = ns.CLASS_BUFFS[skillLine]
    local class = entry and ns.CLASS_NAMES[entry.class]
    local name = self:BuffName(skillLine, true)
    if not class then return name end
    if entry.party then return format(L["%s (%s, needs a party)"], name, class.name) end
    return format("%s (%s)", name, class.name)
end

-- The lowest tier a request wants of a profession.
function Requests:MinTier(request, skillLine)
    return (request.minTier or {})[skillLine] or 1
end

-- Whether a request wants a camp buff's object (not its class buff).
function Requests:WantsObject(request, skillLine)
    return request.wants[skillLine] == true and not (request.classWants or {})[skillLine]
end

-- Whether a class buff can meet a request's want for its stat: one asked for
-- as a class buff, or an object wanted at T1+ (a T2+ one needs the object, for
-- its workspace or service).
function Requests:BuffMeets(request, skillLine)
    if not (request.wants[skillLine] and ns.CLASS_BUFFS[skillLine]) then return false end
    return (request.classWants or {})[skillLine] == true or self:MinTier(request, skillLine) <= 1
end

-- What you can sign up to a request with, in list order: first the camp
-- objects you can bring, at the tier wanted or better (not ones the requester
-- brings), then the class buffs you give that meet a want (not one the
-- requester gives everyone already; none for a request from a copy that
-- wouldn't take them). Each { id = skillLine, name, person (for chat), and
-- profession for an object; buff = true, blessing, party, talent for a class
-- buff }. ranks: your professions (ns.GetMyProfessions), if already looked up.
function Requests:HelpOptions(request, ranks)
    local options = {}
    ranks = ranks or ns.GetMyProfessions()
    local brings = request.brings or {}
    for _, profession in ipairs(ns.PROFESSIONS) do
        local minTier = self:MinTier(request, profession.id)
        if self:WantsObject(request, profession.id) and (brings[profession.id] or 0) < minTier
            and self:MyTier(profession.id, ranks) >= minTier then
            options[#options + 1] = { id = profession.id, name = profession.name, person = profession.person, profession = profession }
        end
    end
    if request.classBuffSignups == false then return options end
    for _, entry in ipairs(self:ClassBuffs()) do
        local id = entry.skillLine
        local given = (request.buffs or {})[id] and not entry.blessing -- the requester gives everyone it already
        if self:BuffMeets(request, id) and (brings[id] or 0) < self:MinTier(request, id) and not given then
            options[#options + 1] = { id = id, buff = true, name = self:BuffName(id), person = self:BuffName(id),
                blessing = entry.blessing, party = entry.party, talent = entry.talent }
        end
    end
    return options
end

-- Who's meeting a wanted camp buff: the players bringing its object, and those
-- giving its stat with a class buff (full names, in no order).
function Requests:Sources(request, skillLine)
    local objects, givers = {}, {}
    for name, helped in pairs(request.helpers) do
        if helped == skillLine then objects[#objects + 1] = name end
        if ((request.helperBuffs or {})[name] or {})[skillLine] then givers[#givers + 1] = name end
    end
    return objects, givers
end

-- Whether a request's camp buff is met: by someone bringing its object (or
-- the requester, at the tier wanted), or by a class buff from a sign-up (only
-- those count for a class-buff want).
function Requests:Covered(request, skillLine)
    local objects, givers = self:Sources(request, skillLine)
    if (request.classWants or {})[skillLine] then return #givers > 0 end
    return #objects > 0 or #givers > 0 or ((request.brings or {})[skillLine] or 0) >= self:MinTier(request, skillLine)
end

-- Whether a request is for you: in the zone you're in, and wanting something
-- you can bring (or you've already signed up to it). ranks: as HelpOptions.
function Requests:ForMe(request, ranks)
    if self:IsMine(request) then return false end
    local mapID = C_Map.GetBestMapForUnit("player")
    if not mapID or ns.IsSecret(mapID) or ns.ZoneOf(mapID) ~= ns.ZoneOf(request.mapID) then return false end
    return request.helpers[ns.playerName] ~= nil or #self:HelpOptions(request, ranks) > 0
end

-- A tier as shown: "T2", or "T2+" for a minimum.
function Requests:TierText(tier, orBetter)
    return format(orBetter and L["T%d+"] or L["T%d"], tier)
end

-- "Strength T2+, Mana regen T1+, Power Word: Fortitude": what a request wants,
-- with any minimum tier; a class-buff want by the buff's name.
function Requests:WantedNames(request)
    local names = {}
    for _, profession in ipairs(ns.PROFESSIONS) do
        if (request.classWants or {})[profession.id] then
            names[#names + 1] = self:BuffName(profession.id)
        elseif request.wants[profession.id] then
            local tier = self:MinTier(request, profession.id)
            names[#names + 1] = format("%s %s", profession.buff, self:TierText(tier, tier < 3))
        end
    end
    return table.concat(names, ", ")
end

-- "Attack power T1, Campfire (holds 5)": what the requester brings; nil if nothing.
function Requests:BroughtNames(request)
    local names = {}
    for _, profession in ipairs(ns.PROFESSIONS) do
        local tier = (request.brings or {})[profession.id]
        if (request.buffs or {})[profession.id] then
            names[#names + 1] = profession.conflicts or profession.buff
        end
        if tier and tier > 0 then
            names[#names + 1] = profession.id == COOKING and format(L["Campfire (holds %d)"], ({ 3, 5, 10 })[tier] or 3)
                or format("%s %s", profession.buff, self:TierText(tier))
        end
    end
    return #names > 0 and table.concat(names, ", ") or nil
end

function Requests:PlaceText(request)
    local info = C_Map.GetMapInfo(request.mapID)
    return format("%s (%.0f, %.0f)", info and info.name or "?", request.x * 100, request.y * 100)
end

function Requests:OnMap(uiMapID)
    local result = {}
    for _, request in pairs(ns.db.requests) do
        local x, y = ns.Camps:Project(request, uiMapID)
        if x then result[#result + 1] = { request = request, x = x, y = y } end
    end
    return result
end

-- Makes room for a new request when the list is full: drops the one least
-- useful to keep (outside your zone first, then the one ending soonest), but
-- never yours or one you've signed up to. Only on your own copy: nothing is
-- sent. Returns false if a request from someone else (sender) isn't worth that.
function Requests:MakeRoom(data, sender)
    local requests = ns.db.requests
    if Count(requests) < MAX_REQUESTS then return true end
    self:Prune() -- expired ones first
    if Count(requests) < MAX_REQUESTS then return true end
    local here = C_Map.GetBestMapForUnit("player")
    local zone = here and not ns.IsSecret(here) and ns.ZoneOf(here)
    local IN_ZONE = 1e10 -- added to a request's score: those in your zone are kept longest
    local victim, victimScore
    for id, other in pairs(requests) do
        if not self:IsMine(other) and not other.helpers[ns.playerName] then
            local score = (zone and ns.ZoneOf(other.mapID) == zone and IN_ZONE or 0) + (other.expiresAt or 0)
            if not victimScore or score < victimScore then victim, victimScore = id, score end
        end
    end
    -- Your own request always gets in; someone else's only in place of one
    -- less useful to you than it (scored the same way).
    local incomingScore = (zone and ns.ZoneOf(data.mapID) == zone and IN_ZONE or 0) + (data.expiresAt or 0)
    if sender and (not victim or incomingScore <= victimScore) then return false end
    if victim then self:Remove(victim) end
    return true
end

-- Adds or updates a request. Only its creator can change it.
function Requests:Upsert(data, sender)
    if sender and sender ~= data.creator then return end
    local requests = ns.db.requests
    local request = requests[data.id]
    local isNew = not request
    if isNew then
        -- One open request per player: a new one replaces the old.
        for id, other in pairs(requests) do
            if other.creator == data.creator and id ~= data.id then self:Remove(id) end
        end
        if not self:MakeRoom(data, sender) then return end
        request = { id = data.id, helpers = {}, realm = ns.realm }
        requests[data.id] = request
    end
    request.creator = data.creator
    request.createdAt = data.createdAt
    request.expiresAt = data.expiresAt
    request.wants = data.wants
    request.classWants = data.classWants or {}
    request.minTier = data.minTier or {}
    request.brings = data.brings or {}
    request.buffs = data.buffs or {}
    request.classBuffSignups = data.classBuffSignups ~= false
    local moved, oldMap, oldX, oldY = false
    if request.mapID ~= data.mapID or request.x ~= data.x or request.y ~= data.y then
        moved, oldMap, oldX, oldY = not isNew, request.mapID, request.x, request.y
        request.mapID, request.x, request.y = data.mapID, data.x, data.y
        request.continent, request.wx, request.wy = ns.Camps.WorldPosition(data.mapID, data.x, data.y)
    end
    ns.OnCampsChanged()

    if isNew and not self:IsMine(request) then self:MaybeNotify(request) end
    if moved and not self:IsMine(request) and request.helpers[ns.playerName] then
        self:OnMeetupMoved(request, oldMap, oldX, oldY)
    end
    return request
end

-- The meet-up of a request you've signed up to moved: your waypoint follows it
-- if it still marks the old spot (not if you've put it somewhere else since),
-- and a local notice says so, at most once a minute for each requester.
local allowMovedNotice = ns.FloodLimit(3)
local MOVED_NOTICE_COOLDOWN = 60
function Requests:OnMeetupMoved(request, oldMap, oldX, oldY)
    local point = C_Map.GetUserWaypoint and C_Map.GetUserWaypoint()
    local x, y = ns.XY(point and point.position)
    if point and point.uiMapID == oldMap and x and y and oldX and oldY
        and math.abs(x - oldX) < 0.0005 and math.abs(y - oldY) < 0.0005
        and C_Map.CanSetUserWaypointOnMap(request.mapID) then
        C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(request.mapID, request.x, request.y))
    end
    if allowMovedNotice(request.creator, MOVED_NOTICE_COOLDOWN) then
        ns.Notify(format(L["%s moved the meet-up to %s."], Ambiguate(request.creator, "short"), self:PlaceText(request)))
    end
end

-- A local chat-frame note (never sent to anyone) when a request in your zone
-- wants something you can bring.
-- None in Standard mode (Mode.lua), which has no Camp Builder.
function Requests:MaybeNotify(request)
    if not ns.db.notifyRequests or not ns.IsEnhanced() or not self:ForMe(request) then return end
    -- "a blacksmith", or a class buff by name ("Power Word: Fortitude") when
    -- that's all you can help with.
    local options = self:HelpOptions(request)
    -- Limits, so posting and closing requests over and over can't flood your chat.
    if not allowNotice(request.creator, NOTIFY_CREATOR_COOLDOWN) then return end
    ns.Print(L["%s is looking for %s near %s. Open the Camp Builder (/hc finder) to join."],
        Ambiguate(request.creator, "short"), options[1].person, self:PlaceText(request))
end

function Requests:Remove(id)
    if ns.db.requests[id] then
        ns.db.requests[id] = nil
        if ns.state.myRequestID == id then ns.state.myRequestID = nil end
        ns.OnCampsChanged()
    end
end

function Requests:Prune()
    local now = Now()
    -- Pretend requests and sign-ups (dev tools) go too if the dev tools are turned off.
    local devTools = ns.devCommands.fakerequest ~= nil
    for id, request in pairs(ns.db.requests) do
        if now > request.expiresAt or request.realm ~= ns.realm or (request.test and not devTools) then
            self:Remove(id)
        elseif request.testHelpers and not devTools then
            for name in pairs(request.testHelpers) do
                request.helpers[name] = nil
                if request.helperTiers then request.helperTiers[name] = nil end
                if request.helperBuffs then request.helperBuffs[name] = nil end
            end
            request.testHelpers = nil
            ns.OnCampsChanged()
        end
    end
end

-- The class buffs of a sign-up that fit the request ([skillLine] = true): each
-- meets a want (Requests:BuffMeets), all of one class, and one blessing at
-- most (a paladin gives each player one; the first in list order is kept).
-- None for a request from a version that ignores them (before 0.8.5).
function Requests:FittingBuffs(request, buffs)
    local kept, class, blessing = {}, nil, false
    if request.classBuffSignups == false then return kept end
    for _, profession in ipairs(ns.PROFESSIONS) do
        local id = profession.id
        local entry = ns.CLASS_BUFFS[id]
        if (buffs or {})[id] and entry and self:BuffMeets(request, id) and (class == nil or entry.class == class)
            and not (entry.blessing and blessing) then
            kept[id], class = true, entry.class
            blessing = blessing or entry.blessing == true
        end
    end
    return kept
end

local function SameSet(a, b)
    for key in pairs(a or {}) do
        if not (b or {})[key] then return false end
    end
    for key in pairs(b or {}) do
        if not (a or {})[key] then return false end
    end
    return true
end

-- A player signs up (or changes their sign-up): the object they'll bring
-- (skillLine; 0 or nil: none) and its tier, and the class buffs they'll give
-- ([skillLine] = true). Only an object the request wants as an object, and
-- class buffs that fit it (Requests:FittingBuffs); with neither, nothing.
function Requests:AddHelper(request, name, skillLine, tier, buffs)
    skillLine = skillLine or 0
    if skillLine ~= 0 and not (ns.PROFESSION_BY_ID[skillLine] and self:WantsObject(request, skillLine)) then return end
    buffs = self:FittingBuffs(request, buffs)
    if skillLine == 0 and not next(buffs) then return end
    request.helperTiers = request.helperTiers or {}
    request.helperBuffs = request.helperBuffs or {}
    -- A sign-up sent again with no tier (by an older version) keeps the one known.
    if skillLine == 0 then
        tier = nil
    elseif tier == nil and request.helpers[name] == skillLine then
        tier = request.helperTiers[name]
    end
    if request.helpers[name] == skillLine and request.helperTiers[name] == tier
        and SameSet(request.helperBuffs[name], buffs) then return end
    if not request.helpers[name] and Count(request.helpers) >= MAX_HELPERS then return end
    request.helpers[name] = skillLine
    request.helperTiers[name] = tier
    request.helperBuffs[name] = next(buffs) and buffs or nil
    ns.OnCampsChanged()
    -- Only a helper's first sign-up to your request notifies you, so signing
    -- up and withdrawing over and over can't spam you.
    request.notified = request.notified or {}
    if self:IsMine(request) and name ~= ns.playerName and not request.notified[name] then
        request.notified[name] = true
        if skillLine ~= 0 then
            ns.Notify(format(L["%s is coming to your camp as %s."], Ambiguate(name, "short"),
                ns.PROFESSION_BY_ID[skillLine].person))
        else
            ns.Notify(format(L["%s is coming to your camp with %s."], Ambiguate(name, "short"), self:BuffNames(buffs)))
        end
    end
end

function Requests:RemoveHelper(request, name)
    if request.helpers[name] then
        request.helpers[name] = nil
        if request.helperBuffs then request.helperBuffs[name] = nil end
        ns.OnCampsChanged()
        request.left = request.left or {}
        if self:IsMine(request) and not request.left[name] then
            request.left[name] = true
            if ns.IsEnhanced() then ns.Note(L["%s can no longer come to your camp."], Ambiguate(name, "short")) end
        end
    end
end

-- Your own actions ------------------------------------------------------------

-- Players who saw your last request take a new one from you only
-- Comm.REPLACE_COOLDOWN seconds after it (as you do theirs, handlers.R): one
-- posted sooner goes out once that time is up (a few seconds more, for the
-- send queue), if it's still open.
local SEND_MARGIN = 5
local lastNewSent -- when your last new request went out
local function SendNew(request)
    local cooldown = math.min(ns.Comm.REPLACE_COOLDOWN, ns.db.floodLimit)
    local wait = lastNewSent and cooldown > 0 and lastNewSent + cooldown + SEND_MARGIN - GetTime() or 0
    if wait > 0 then
        C_Timer.After(wait, function()
            if Requests:Mine() == request then SendNew(request) end
        end)
        return
    end
    lastNewSent = GetTime()
    ns.Comm:SendRequest(request)
end

-- classWants: the wants asked for as a class buff ([skillLine] = true; they're
-- in wants too).
function Requests:Post(wants, mapID, x, y, minTier, brings, buffs, classWants)
    -- Without the camp network nothing is sent, so nobody would see it.
    if not ns.db.network then
        ns.Print(L["The camp network is off, so nobody would see your request. Turn on sharing in Options to post it."])
        return nil
    end
    -- Nor one on a continent's or a dungeon's map: everyone else drops it (the
    -- Camp Builder says why). Your open request stays.
    if not (mapID and ns.IsOutdoorMap(mapID)) then return nil end
    local old = self:Mine()
    if old then self:Close(old) end
    local now = Now()
    local request = self:Upsert({
        id = ns.playerName .. ":" .. now,
        creator = ns.playerName,
        mapID = mapID, x = x, y = y,
        createdAt = now,
        expiresAt = now + self.DURATION,
        wants = wants, minTier = minTier, brings = brings, buffs = buffs, classWants = classWants,
    })
    if request then
        ns.state.myRequestID = request.id
        SendNew(request)
        ns.Print(L["Camp request posted. Players who can help will see it on their map."])
    end
    return request
end

-- Moves your request's meet-up; only to a zone map (as Post). Returns true if moved.
function Requests:Move(request, mapID, x, y)
    if not (mapID and ns.IsOutdoorMap(mapID)) then return false end
    self:Upsert({
        id = request.id, creator = request.creator,
        mapID = mapID, x = x, y = y,
        createdAt = request.createdAt, expiresAt = request.expiresAt,
        wants = request.wants, minTier = request.minTier, brings = request.brings, buffs = request.buffs,
        classWants = request.classWants,
    })
    ns.Comm:SendRequest(request)
    return true
end

function Requests:Close(request)
    ns.Comm:SendClose(request.id)
    self:Remove(request.id)
end

-- Signs you up with a camp object (skillLine; nil: none) and the class buffs
-- you'll give for wanted stats (buffs: [skillLine] = true; a paladin's: one).
function Requests:SignUp(request, skillLine, buffs)
    skillLine = skillLine or 0
    local tier = skillLine ~= 0 and self:MyTier(skillLine) or nil
    buffs = self:FittingBuffs(request, buffs)
    self:AddHelper(request, ns.playerName, skillLine, tier, buffs)
    ns.Comm:SendJoin(request.id, skillLine, tier, buffs)
    if skillLine ~= 0 then
        local names = { ns.PROFESSION_BY_ID[skillLine].name }
        if next(buffs) then names[2] = self:BuffNames(buffs) end
        ns.Print(L["You're signed up to bring %s. The meet-up is marked on your map."], ns.JoinList(names))
    else
        ns.Print(L["You're signed up to give %s. The meet-up is marked on your map."], self:BuffNames(buffs))
    end
    ns.SetWaypoint(request, format(L["%s's meet-up"], Ambiguate(request.creator, "short")))
end

function Requests:Withdraw(request)
    self:RemoveHelper(request, ns.playerName)
    ns.Comm:SendLeave(request.id)
end

-- A camp lit at your meet-up point by you or a player who signed up fulfils
-- your request (anyone else's fire there doesn't, so it can't be closed on you).
function Requests:OnCampAdded(camp)
    local request = self:Mine()
    if not request or not camp.continent then return end
    if camp.creator ~= ns.playerName and not request.helpers[camp.creator] then return end
    local distance = ns.Camps:Distance(request, camp.mapID, camp.x, camp.y)
    if distance and distance <= FULFIL_RADIUS then
        ns.Notify(L["Your camp is lit. The Camp Builder request is closed."])
        self:Close(request)
    end
end
