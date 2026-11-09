-- Happy Camper. Copyright (c) 2026 Torridon. All rights reserved; see LICENSE.
local _, ns = ...
local L = ns.L

-- Group tab: planning a camp with your party or raid.
--   Camp buffs   one row per camp buff: who in the group carries its object (or
--                can make it), a menu of the whole group where anyone can mark
--                players without Happy Camper who say they have one (grey:
--                the addon can't check), and its Camp Setup: the class buff that already
--                gives the same stat (azure), Applied (placed at your camp), who
--                the leader has asked to place it, Available, or nobody can.
--                Tiers show there: every tier gives the same buff, and tiers 2
--                and 3 add a workspace or service (ns.OBJECT_EXTRAS). Who can
--                make which tier comes from the recipes they know.
--   Blessings    a paladin keeps up one blessing per player, so each paladin
--                covers one of Might, Wisdom and Kings: the one they pick (Your
--                blessing, even solo) or the leader picks for them.
--   Presets      the leader's Melee, Caster and Balanced fill in the plan:
--                paladins' blessings first (they cost no room at the fire), then
--                objects, as many as the fire holds, one per player. Asking
--                someone by hand stops at the fire's size too (Group:FireRoom).
--   Your group   everyone in the group: the camp objects they carry, their Camp
--                Benefits, and when they can place an object again, or that
--                they don't have Happy Camper.
--   The top      Planned, Placed and Camp Benefits at a glance, and Your job
--                (with Place) when the leader has asked you to place something.
-- Members with the addon share their status over the party or raid addon
-- channel (G messages, Comm.lua). Nothing goes to chat unless the leader clicks
-- Say or Party/Raid.

local Group = {}
ns.Group = Group

local WIDTH = 500
local PAD = 16
local QUERY_COOLDOWN = 10    -- seconds: each player's status requests are answered this often
local PLACED_SHOWN = 15 * 60 -- a placed object counts as Applied for this long
local REFRESH_DELAY = 0.2    -- seconds: a burst of group messages redraws the tab once
local PLAN_GRACE = 10        -- seconds out of a group after login before a saved plan is dropped (the roster can be late)
local GREY, GREEN, ORANGE = "|cffaaaaaa", "|cff66ff66", "|cffff9933"
local WHITE = "|cffffffff"
local AZURE = "|cff3399ff"  -- a camp buff covered by a class buff
local RED = "|cffff6f4f"    -- no Camp Benefits
-- The tab's layout (Group:Build, Group:Refresh), as the Camp Builder's (Style.PLAN).
local PLAN = ns.Style.PLAN
local TOP_Y = -22           -- where the tab's content starts
local GAP = PLAN.GAP        -- between its parts
local TILE_HEIGHT = PLAN.TILE_HEIGHT -- Planned, Placed and Camp Benefits
local BANNER_HEIGHT = 46    -- Your job
local PLACE_WIDTH = 96      -- its Place button
local PRESET_WIDTH = 90     -- Melee, Caster, Balanced
local BOTTOM_WIDTH = 100    -- Refresh, Clear plan, Say, Party/Raid
local BUTTON_GAP = 6
local BLESSING_WIDTH = 170  -- Your blessing
local INNER, LIST_TOP, ROW_WIDTH = PLAN.INNER, PLAN.LIST_TOP, PLAN.ROW_WIDTH
-- The plan's columns: a mark for the state, the icon, the buff (its profession
-- under it), Who has it, Camp Setup.
local ROW_HEIGHT = PLAN.ROW_HEIGHT
local BUFF_X, WHO_X, SETUP_X = PLAN.BUFF_X, PLAN.MID_X, PLAN.SETUP_X
local WHO_WIDTH, SETUP_WIDTH = PLAN.MID_WIDTH, PLAN.SETUP_WIDTH
-- Your group's columns: name, what they carry, Camp Benefits, their camp object.
local MEMBER_HEIGHT = 22
local CARRIES_X, BENEFITS_X, OBJECT_X = 166, 254, 330
local MAX_CARRIED = 3       -- object icons shown; more are counted
local SCROLLBAR_SPACE = 16  -- room for the member list's scroll bar, when it has one
local COOKING = 185

-- Paladin blessings that give a camp buff's stat (skillLines), in menu order:
-- Might, Wisdom, Kings. A paladin keeps up one of them on each player.
local BLESSINGS = { 186, 171, 356 }
local IS_BLESSING = { [186] = true, [171] = true, [356] = true }
local KINGS = 356 -- a talent: not every paladin has it
-- Your status is worked out again at most every STATUS_EVERY seconds (your
-- bags, professions and recipes), and sooner when they change.
local STATUS_EVERY = 5
local statusAt, statusStale = -math.huge, true

local members = {}      -- [full name] = their last status (see ParseStatus)
local assignments = {}  -- [skillLine] = full name of who the leader asked to place it
local blessings = {}    -- [full name] = the blessing that paladin keeps up (yours is charDB.blessing)
local claims = {}       -- [skillLine] = { [full name] = true }: players without the addon marked as having one
local lastCovered = {}  -- [full name] = the camp buffs their class buffs gave, last read
local WhoMenu -- the Who has it menu (made with the tab)
local lastSent          -- your last status message, so it's only sent when it changes
local lastQueryFrom = {}
local pendingQuery = {} -- [full name] = true while an answer to their status request waits
local wasInGroup, wasLeader = false, false
local refreshQueued = false
local planLoaded = false -- the saved plan has been brought back (or dropped) this session
local soloSince          -- when you were first seen out of a group before that

-- Names ---------------------------------------------------------------------------
-- Everyone is known by the name their addon messages come from (ns.UnitFullName):
-- "First Surname" in Forever, "Name-Realm" elsewhere.

-- A name as sent (older versions shorten it): a realm is added only where
-- names have one, and only if it has none.
local function FullName(name, realm)
    if not ns.UniqueNames() and not name:find("-", 1, true) then name = name .. "-" .. (realm or ns.realm) end
    return name
end

local function Short(name)
    return Ambiguate(name, "short")
end

-- Whether you're in a party or raid, and whether you lead it. Every check in
-- this file goes through these two, and everyone in the group through Roster,
-- so the dev tools (HappyCamper_Dev, never shipped) can add pretend members
-- that only you see. Without them these are just the game's answers.
function Group:InGroup()
    return IsInGroup() or IsInRaid()
end

function Group:AmLeader()
    return self:InGroup() and UnitIsGroupLeader("player") == true
end

-- Everyone in your group: { { unit, name (full), class }, ... }, you first.
function Group:Roster()
    local list = {}
    local function Add(unit)
        local name = UnitName(unit)
        if type(name) ~= "string" or ns.IsSecret(name) or name == "" then return end
        local full = UnitIsUnit(unit, "player") and ns.playerName or ns.UnitFullName(unit)
        if not full then return end
        local _, class = UnitClass(unit)
        list[#list + 1] = { unit = unit, name = full, class = class }
    end
    Add("player")
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do
            if not UnitIsUnit("raid" .. i, "player") then Add("raid" .. i) end
        end
    elseif IsInGroup() then
        for i = 1, GetNumSubgroupMembers() do Add("party" .. i) end
    end
    return list
end

-- The lowest and highest levels in your group that can be read (nil if none
-- can): each member gets a camp buff at their own level.
local function GroupLevels()
    local low, high
    for _, entry in ipairs(Group:Roster()) do
        local level = ns.KnownLevel(entry.unit)
        if level then low, high = math.min(low or level, level), math.max(high or level, level) end
    end
    return low, high
end

-- Whether someone (a full name) leads your group, asked of their unit.
local function IsLeader(name)
    if name == ns.playerName then return Group:AmLeader() end
    for _, entry in ipairs(Group:Roster()) do
        if entry.name == name then return UnitIsGroupLeader(entry.unit) == true end
    end
    return false
end

local function Paladins(roster)
    local list = {}
    for _, entry in ipairs(roster) do
        if entry.class == "PALADIN" then list[#list + 1] = entry.name end
    end
    return list
end

-- Whether you know a blessing (any rank). Without the API, assume so.
local function KnowsBlessing(skillLine)
    if not IsPlayerSpell then return true end
    for _, spellID in ipairs(ns.PROFESSION_BY_ID[skillLine].conflictSpells or {}) do
        if IsPlayerSpell(spellID) then return true end
    end
    return false
end

-- Your camp recipes -----------------------------------------------------------------
-- charDB.campRecipes[recipeID] = true for each camp recipe you've learned. Only
-- your own profession window decides it (RefreshRecipes): the game's "learned"
-- is about whoever's recipe list is open, and that can be someone else's (a
-- linked profession, a guild's crafters, an NPC's). Everything else only reads it.

-- Every camp recipe, for NEW_RECIPE_LEARNED: [recipeID] = true.
local CAMP_RECIPES = {}
local function AddRecipes(recipes)
    for tier in pairs(recipes or {}) do
        for _, recipeID in ipairs(ns.RecipeIDs(recipes, tier)) do CAMP_RECIPES[recipeID] = true end
    end
end
for _, profession in ipairs(ns.PROFESSIONS) do AddRecipes(profession.recipes) end
AddRecipes(ns.KIT_RECIPES)

-- Whether you've learned a recipe, as your own profession window last said.
function Group:KnowsRecipe(recipeID)
    return (ns.charDB.campRecipes or {})[recipeID] == true
end

-- The best camp object tier you know the recipe for and your skill reaches, by
-- profession ([skillLine] = tier), or nil if you know no camp recipe at all.
-- ranks: your professions (ns.GetMyProfessions), if already looked up.
function Group:KnownRecipes(ranks)
    local known = ns.charDB.campRecipes or {}
    local best, any = {}, false
    ranks = ranks or ns.GetMyProfessions()
    for _, profession in ipairs(ns.PROFESSIONS) do
        for tier in pairs(profession.recipes or {}) do
            for _, recipeID in ipairs(ns.RecipeIDs(profession.recipes, tier)) do
                if known[recipeID] then
                    any = true
                    if ns.ReachesTier(ranks[profession.id], tier) then
                        best[profession.id] = math.max(best[profession.id] or 0, tier)
                    end
                end
            end
        end
    end
    return any and best or nil
end

-- The profession whose list the profession window shows, if it's your own and
-- ready; nil for anyone else's list (linked, a guild's, an NPC's). A check the
-- game can't answer counts as someone else's.
local function OwnOpenProfession()
    local api = C_TradeSkillUI
    if not api then return end
    local function Ask(name)
        if not api[name] then return false, nil end
        return pcall(api[name])
    end
    local ok, ready = Ask("IsTradeSkillReady")
    if api.IsTradeSkillReady and (not ok or not ready) then return end
    local changingOK, changing = Ask("IsDataSourceChanging")
    if api.IsDataSourceChanging and (not changingOK or changing) then return end
    for _, name in ipairs({ "IsTradeSkillLinked", "IsTradeSkillGuild", "IsTradeSkillGuildMember", "IsNPCCrafting" }) do
        local asked, other = Ask(name)
        if not asked or other then return end
    end
    local baseOK, base = Ask("GetBaseProfessionInfo")
    local childOK, child = Ask("GetChildProfessionInfo")
    base = baseOK and type(base) == "table" and base or nil
    child = childOK and type(child) == "table" and child or nil
    local profession = base and ns.PROFESSION_BY_ID[base.professionID]
        or child and ns.PROFESSION_BY_ID[child.parentProfessionID or 0]
    if profession then return profession end
    local name = base and base.professionName or child and child.parentProfessionName
    for _, candidate in ipairs(ns.PROFESSIONS) do
        if name and candidate.name == name then return candidate end
    end
end

-- Checks your camp recipes against your own profession window, when it shows
-- or lists its recipes: the ones it says you've learned are remembered, the
-- others forgotten. Only that profession's (for Cooking, the campfire kits too).
function Group:RefreshRecipes()
    local profession = OwnOpenProfession()
    if not profession then return end
    local known = ns.charDB.campRecipes or {}
    ns.charDB.campRecipes = known
    local function Check(recipes)
        for tier in pairs(recipes or {}) do
            for _, recipeID in ipairs(ns.RecipeIDs(recipes, tier)) do
                local ok, info = pcall(C_TradeSkillUI.GetRecipeInfo, recipeID)
                if ok and type(info) == "table" and not ns.IsSecret(info.learned) and type(info.learned) == "boolean" then
                    known[recipeID] = info.learned or nil
                end
            end
        end
    end
    Check(profession.recipes)
    if profession.id == COOKING then Check(ns.KIT_RECIPES) end
    local checked = ns.charDB.campRecipesChecked or {}
    ns.charDB.campRecipesChecked = checked
    checked[profession.id] = true
    statusStale = true
end

-- Your status ---------------------------------------------------------------------

-- When your Camp Benefits ends (server time), or 0 without it: from the buff
-- last read (Detect.lua keeps it while buffs can't be read). Worked out once
-- per buff, so the status sent to the group doesn't change every second.
local myBenefits = { key = nil, ends = 0 }
local function MyBenefitsEnd()
    local last
    for _, buff in ipairs(ns.state.buffs or {}) do
        if (buff.expirationTime or 0) > 0 and (not last or buff.expirationTime > last.expirationTime) then last = buff end
    end
    local key = last and (tostring(last.auraInstanceID) .. ":" .. last.expirationTime)
    if key ~= myBenefits.key then
        myBenefits.key = key
        myBenefits.ends = last and math.floor(GetServerTime() + last.expirationTime - GetTime() + 0.5) or 0
    end
    return myBenefits.ends
end

-- What you'd tell the group: see the G message in Comm.lua.
function Group:MyStatus()
    local c = ns.charDB
    local _, _, kitSlots, objectSpell = ns.Widget:CampItems()
    local objectSkill, objectTier
    if objectSpell then
        local key = ns.ObjectInfo(objectSpell)
        local _, _, skillLine, tier = ns.ObjectByName(key)
        objectSkill, objectTier = skillLine, tier
    end
    -- Every camp object in your bags (the best tier of each profession's), not
    -- just the one the panel places.
    local carried = {}
    for _, entry in ipairs(ns.Widget:CampObjects()) do
        local _, _, skillLine, tier = ns.ObjectByName(ns.ObjectForSpell(entry.spell))
        if skillLine then carried[skillLine] = math.max(carried[skillLine] or 0, tier or 1) end
    end
    local placedAt = c.objectReadyAt and c.objectReadyAt - ns.db.objectCooldown
    local professions = ns.GetMyProfessions()
    return {
        professions = professions,
        objectSkill = objectSkill, objectTier = objectTier,
        carried = carried,
        readyAt = c.objectReadyAt or 0,
        placedSkill = c.objectSkill, placedAt = placedAt or 0, placedTier = c.placedTier,
        kit = kitSlots or 0,
        blessing = c.blessing,
        recipes = self:KnownRecipes(professions),
        benefitsUntil = MyBenefitsEnd(),
    }
end

-- A [skillLine] = tier table as "skillLine.tier,..." (sorted).
local function EncodeStatus(status)
    local professions = {}
    for skillLine, rank in pairs(status.professions) do professions[#professions + 1] = skillLine .. ":" .. rank end
    table.sort(professions)
    return format("G;%s;%s;%d;%s;%d;%d;%d;%d;%s;%s;%d", table.concat(professions, ","),
        status.objectSkill and (status.objectSkill .. "." .. status.objectTier) or "",
        status.readyAt, status.placedSkill or "", status.placedAt, status.kit,
        status.placedTier or 0, status.blessing or 0, ns.EncodeTiers(status.recipes), ns.EncodeTiers(status.carried),
        status.benefitsUntil or 0)
end

-- "skillLine.tier,..." back to [skillLine] = tier, for camp objects that exist.
local function ParseTiers(text)
    local tiers
    for skillLine, tier in (text or ""):gmatch("(%d+)%.(%d)") do
        skillLine, tier = tonumber(skillLine), tonumber(tier)
        local profession = ns.PROFESSION_BY_ID[skillLine]
        if profession and profession.objects[tier] then
            tiers = tiers or {}
            tiers[skillLine] = tier
        end
    end
    return tiers
end

-- Older versions send only the first six fields: no placed tier, blessing,
-- recipes or carried objects. No recipes means they're not known; no carried
-- objects means only the one in the object field.
local function ParseStatus(professionList, object, readyAt, placedSkill, placedAt, kit, placedTier, blessing, recipes, carried, benefits)
    local status = { professions = {}, seen = GetTime() }
    for skillLine, rank in (professionList or ""):gmatch("(%d+):(%d+)") do
        skillLine = tonumber(skillLine)
        if ns.PROFESSION_BY_ID[skillLine] then status.professions[skillLine] = math.min(tonumber(rank), 1000) end
    end
    local skillLine, tier = (object or ""):match("^(%d+)%.(%d)$")
    skillLine, tier = tonumber(skillLine), tonumber(tier)
    local profession = skillLine and ns.PROFESSION_BY_ID[skillLine]
    if profession and profession.objects[tier] then status.objectSkill, status.objectTier = skillLine, tier end
    status.readyAt = tonumber(readyAt) or 0
    status.placedSkill = ns.PROFESSION_BY_ID[tonumber(placedSkill) or 0] and tonumber(placedSkill) or nil
    status.placedAt = tonumber(placedAt) or 0
    kit = tonumber(kit)
    status.kit = (kit == 3 or kit == 5 or kit == 10) and kit or 0
    placedTier = tonumber(placedTier)
    status.placedTier = (placedTier == 1 or placedTier == 2 or placedTier == 3) and placedTier or nil
    if blessing ~= nil then
        status.sendsBlessing = true
        status.blessing = IS_BLESSING[tonumber(blessing) or 0] and tonumber(blessing) or nil
    end
    -- A tier their skill can't reach doesn't count (older versions remembered
    -- recipes seen in other players' lists).
    for recipeSkill, recipeTier in pairs(ParseTiers(recipes) or {}) do
        local rank = status.professions[recipeSkill]
        if rank == nil or ns.ReachesTier(rank, recipeTier) then
            status.recipes = status.recipes or {}
            status.recipes[recipeSkill] = recipeTier
        end
    end
    if carried ~= nil then
        status.carried = ParseTiers(carried) or {}
    else
        status.carried = status.objectSkill and { [status.objectSkill] = status.objectTier } or {}
    end
    -- When their Camp Benefits ends (0: none); nil from versions that don't say.
    benefits = tonumber(benefits)
    if benefits and benefits >= 0 and benefits <= GetServerTime() + 2 * 3600 then status.benefitsUntil = benefits end
    return status
end

-- Messages to your group -------------------------------------------------------------

local function SendBlessing(name, skillLine)
    ns.Comm:SendGroup(format("GB;%d;%s", skillLine or 0, Ambiguate(name, "none")), "GB" .. name)
end

-- The leader's plan to the group: every assignment, and the blessings picked
-- for paladins without the addon (the others send their own). whole: every
-- buff's row, the empty ones too, so a plan left on someone's screen (from
-- before you reloaded, or from the last leader) is cleared.
local function SendPlan(whole)
    for _, profession in ipairs(ns.PROFESSIONS) do
        local name = assignments[profession.id]
        if name or (whole and not profession.notSearchable) then
            ns.Comm:SendGroup(format("GA;%d;%s", profession.id, name and Ambiguate(name, "none") or ""), "GA" .. profession.id)
        end
    end
    for name, skillLine in pairs(blessings) do
        if not members[name] then SendBlessing(name, skillLine) end
    end
end

-- The leader's plan is kept in this character's saved data, so a /reload or
-- relog doesn't lose it: charDB.groupPlan = { members = { [full name] = true }
-- (the group it was made in), assignments, blessings (those SendPlan sends:
-- picked for paladins without the addon) }. Only the leader keeps one, and
-- only once the last one has been brought back or dropped (RestorePlan; or
-- Update, after logging in out of a group).
local function SavePlan()
    if not planLoaded then return end
    local saved, empty = { members = {}, assignments = {}, blessings = {} }, true
    for skillLine, name in pairs(assignments) do saved.assignments[skillLine], empty = name, false end
    for name, skillLine in pairs(blessings) do
        if not members[name] then saved.blessings[name], empty = skillLine, false end
    end
    if empty or not Group:AmLeader() then
        ns.charDB.groupPlan = nil
        return
    end
    for _, entry in ipairs(Group:Roster()) do saved.members[entry.name] = true end
    ns.charDB.groupPlan = saved
end

-- On joining a group (as after a /reload or relog), a saved plan comes back if
-- you lead it and it's still the group the plan was made in: everyone the plan
-- names is in it, and someone else who was (not just you). Otherwise it's dropped.
local function RestorePlan()
    planLoaded = true
    local saved = ns.charDB.groupPlan
    ns.charDB.groupPlan = nil
    if type(saved) ~= "table" or not Group:AmLeader() then return end
    local here, before = {}, false
    for _, entry in ipairs(Group:Roster()) do
        here[entry.name] = true
        if entry.name ~= ns.playerName and (saved.members or {})[entry.name] then before = true end
    end
    if not before then return end
    for _, name in pairs(saved.assignments or {}) do
        if not here[name] then return end
    end
    for name in pairs(saved.blessings or {}) do
        if not here[name] then return end
    end
    for skillLine, name in pairs(saved.assignments or {}) do
        if ns.PROFESSION_BY_ID[skillLine] and type(name) == "string" then assignments[skillLine] = name end
    end
    for name, skillLine in pairs(saved.blessings or {}) do
        if IS_BLESSING[skillLine] then blessings[name] = skillLine end
    end
end

local statusEvents = CreateFrame("Frame")
for _, event in ipairs({ "BAG_UPDATE_DELAYED", "SKILL_LINES_CHANGED", "UNIT_SPELLCAST_SUCCEEDED" }) do
    pcall(statusEvents.RegisterEvent, statusEvents, event)
end
statusEvents:SetScript("OnEvent", function(_, event, unit)
    if event ~= "UNIT_SPELLCAST_SUCCEEDED" or unit == "player" then statusStale = true end
end)

-- Tells the group your status when it changes (called once a second).
function Group:Update()
    local inGroup = self:InGroup()
    local leader = self:AmLeader()
    if inGroup and not wasInGroup then
        -- Just joined (or reloaded): ask everyone for theirs. A leader's plan
        -- (the saved one, after a reload, if it's still this group's)
        -- replaces whatever the group has.
        lastSent = nil
        ns.Comm:SendGroup("GQ", "GQ")
        RestorePlan()
        if leader then
            SendPlan(true)
            self:QueueRefresh()
        end
        SavePlan()
    elseif leader and not wasLeader then
        SendPlan(true) -- just made leader: the last leader's plan goes
        SavePlan()
    elseif wasLeader and inGroup and not leader then
        SavePlan() -- not the leader any more: the plan isn't yours to keep
    elseif not inGroup and wasInGroup then
        wipe(members)
        wipe(assignments)
        wipe(blessings)
        wipe(lastCovered)
        ns.charDB.groupPlan = nil
    elseif not inGroup and not planLoaded then
        -- Logged in (or reloaded) out of a group: once the roster has had time
        -- to arrive, the saved plan was for a group you've left.
        soloSince = soloSince or GetTime()
        if GetTime() - soloSince >= PLAN_GRACE then
            planLoaded = true
            ns.charDB.groupPlan = nil
        end
    end
    wasInGroup, wasLeader = inGroup, leader
    if not inGroup then return end
    if lastSent and not statusStale and GetTime() - statusAt < STATUS_EVERY then return end
    statusAt, statusStale = GetTime(), false
    local message = EncodeStatus(self:MyStatus())
    if message ~= lastSent then
        lastSent = message
        ns.Comm:SendGroup(message, "G")
    end
end

-- Ready checks ---------------------------------------------------------------------
-- At a ready check, who in your group lacks Camp Benefits, in your own chat
-- window only (Options: readyCheckSummary); nothing is sent. Each member's is
-- read from their buffs where the game lets addons see them, else taken from
-- what their Happy Camper last told the group, else it's not known (out of
-- sight, or buffs hidden in an instance or a fight).
local ENDING_SOON = 10 * 60 -- seconds: Camp Benefits ending this soon is named too
local MAX_NAMES = 8         -- names in one part of the summary; more are counted

-- The game's own name for Camp Benefits (in the client's language).
local function BenefitsName()
    local name = C_Spell.GetSpellName((next(ns.CAMP_SPELLS.buff)))
    if type(name) ~= "string" or ns.IsSecret(name) or name == "" then name = "Camp Benefits" end
    return name
end

-- A unit's Camp Benefits from its buffs: when it ends (server time), false if
-- it has none, or nil if its buffs can't be read.
local function UnitBenefitsEnd(unit)
    local visible = UnitIsVisible(unit)
    if ns.IsSecret(visible) or not visible then return nil end
    local found, unreadable = nil, false
    for i = 1, 40 do
        local aura, secret = ns.AuraByIndex(unit, i, "HELPFUL")
        if secret then return nil end
        if not aura then break end
        if ns.IsSecretAura(aura) then
            unreadable = true
        elseif ns.ClassifyAura(aura) == "buff" then
            local exp = aura.expirationTime or 0
            local ends = exp > 0 and math.floor(GetServerTime() + exp - GetTime() + 0.5) or GetServerTime() + 3600
            found = math.max(found or 0, ends)
        end
    end
    if found then return found end
    if unreadable then return nil end
    return false
end

-- A group member's Camp Benefits: when it ends, false for none, nil if unknown.
local function BenefitsEnd(entry)
    local now = GetServerTime()
    if entry.name == ns.playerName then
        local ends = MyBenefitsEnd()
        return ends > now and ends or false
    end
    local fromBuffs = UnitBenefitsEnd(entry.unit)
    if fromBuffs ~= nil then return fromBuffs end
    local status = members[entry.name]
    local ends = status and status.benefitsUntil
    if ends then return ends > now and ends or false end
    return nil
end

-- "Ann, Bob and 3 more".
local function NameList(names)
    if #names <= MAX_NAMES then return table.concat(names, ", ") end
    local shown = {}
    for i = 1, MAX_NAMES do shown[i] = names[i] end
    return table.concat(shown, ", ") .. " " .. format(L["and %d more"], #names - MAX_NAMES)
end

-- The summary's text, or nil outside a group.
function Group:ReadyCheckText()
    if not self:InGroup() then return nil end
    local now = GetServerTime()
    local missing, soon, unknown = {}, {}, {}
    for _, entry in ipairs(self:Roster()) do
        local name = entry.name == ns.playerName and L["you"] or Short(entry.name)
        local ends = BenefitsEnd(entry)
        if ends == nil then
            unknown[#unknown + 1] = name
        elseif not ends then
            missing[#missing + 1] = name
        elseif ends - now <= ENDING_SOON then
            soon[#soon + 1] = format(L["%s (%d min)"], name, math.max(1, math.floor((ends - now) / 60)))
        end
    end
    local buff = BenefitsName()
    if #missing == 0 and #soon == 0 and #unknown == 0 then return format(L["Ready check: everyone has %s."], buff) end
    local parts = {}
    if #missing > 0 then parts[#parts + 1] = format(L["missing for %s"], NameList(missing)) end
    if #soon > 0 then parts[#parts + 1] = format(L["ending soon for %s"], NameList(soon)) end
    if #unknown > 0 then parts[#parts + 1] = format(L["not known for %s"], NameList(unknown)) end
    return format(L["Ready check, %s: %s."], buff, table.concat(parts, "; "))
end

function Group:OnReadyCheck()
    if not ns.db.readyCheckSummary then return end
    local text = self:ReadyCheckText()
    if text then ns.Print("%s", text) end
end

local readyEvents = CreateFrame("Frame")
readyEvents:RegisterEvent("READY_CHECK")
readyEvents:SetScript("OnEvent", function()
    if ns.db then Group:OnReadyCheck() end
end)

-- Messages from your group ---------------------------------------------------------

-- Your status (and the leader's plan) to the group, answering someone's request.
local function SendStatus(sender)
    lastQueryFrom[sender] = GetTime()
    lastSent = EncodeStatus(Group:MyStatus())
    ns.Comm:SendGroup(lastSent, "G")
    if Group:AmLeader() then SendPlan() end
end

-- Each player's requests are answered at most every QUERY_COOLDOWN seconds;
-- one inside it is answered when it ends (once), so a player who reloads right
-- after asking still gets everyone's status.
local function Resend(sender)
    local since = lastQueryFrom[sender] and GetTime() - lastQueryFrom[sender]
    if not since or since >= QUERY_COOLDOWN then return SendStatus(sender) end
    if pendingQuery[sender] then return end
    pendingQuery[sender] = true
    C_Timer.After(QUERY_COOLDOWN - since, function()
        pendingQuery[sender] = nil
        if Group:InGroup() then SendStatus(sender) end
    end)
end

-- The leader asks someone to place a buff's object (no name: nobody). The plan
-- sent again only tells you what changed.
local function OnAssignment(sender, skillLine, name)
    skillLine = tonumber(skillLine)
    if not skillLine or not ns.PROFESSION_BY_ID[skillLine] or not IsLeader(sender) then return end
    name = type(name) == "string" and name ~= "" and FullName(name:sub(1, 60), sender:match("-(.+)$")) or nil
    if assignments[skillLine] == name then return end
    assignments[skillLine] = name
    -- No alert in Standard mode (Mode.lua), which has no Group tab.
    if name == ns.playerName and ns.IsEnhanced() then
        local profession = ns.PROFESSION_BY_ID[skillLine]
        ns.Alert(format(L["%s asks you to place your %s camp object (%s)."], Short(sender), profession.name, profession.buff))
    end
end

-- The leader picks a paladin's blessing (0 = none).
local function OnBlessing(sender, skillLine, name)
    skillLine = tonumber(skillLine)
    if not skillLine or not IsLeader(sender) or type(name) ~= "string" or name == "" then return end
    if skillLine == 0 then skillLine = nil elseif not IS_BLESSING[skillLine] then return end
    name = FullName(name:sub(1, 60), sender:match("-(.+)$"))
    if name == ns.playerName then
        if skillLine and ns.charDB.blessing ~= skillLine and ns.IsEnhanced() then
            ns.Alert(format(L["%s asks you to keep up %s."], Short(sender), ns.PROFESSION_BY_ID[skillLine].conflicts))
        end
        ns.charDB.blessing = skillLine
        statusStale = true
    else
        blessings[name] = skillLine
    end
end

function Group:OnMessage(sender, kind, ...)
    sender = FullName(sender)
    if kind == "G" then
        local status = ParseStatus(...)
        members[sender] = status
        if status.sendsBlessing then blessings[sender] = status.blessing end
    elseif kind == "GQ" then
        Resend(sender)
    elseif kind == "GA" then
        OnAssignment(sender, ...)
    elseif kind == "GB" then
        OnBlessing(sender, ...)
    end
    self:QueueRefresh()
end

-- Messages come in bursts (everyone answers a status request): the tab is
-- redrawn once, a moment after the first.
function Group:QueueRefresh()
    if refreshQueued then return end
    refreshQueued = true
    C_Timer.After(REFRESH_DELAY, function()
        refreshQueued = false
        Group:Refresh()
    end)
end

-- The leader's plan --------------------------------------------------------------

function Group:Assign(skillLine, name)
    if not self:AmLeader() then return end
    -- Someone new to place an object only while the fire has room (HasRoomFor).
    if name and not self:HasRoomFor(skillLine) then return end
    assignments[skillLine] = name
    SavePlan()
    ns.Comm:SendGroup(format("GA;%d;%s", skillLine, name and Ambiguate(name, "none") or ""), "GA" .. skillLine)
    self:Refresh()
end

-- Clears every assignment and the blessings picked for paladins without the
-- addon (the others pick their own), and so the saved plan.
function Group:ClearPlan()
    for skillLine in pairs(assignments) do self:Assign(skillLine, nil) end
    local picked = {}
    for name in pairs(blessings) do
        if not members[name] then picked[#picked + 1] = name end
    end
    for _, name in ipairs(picked) do self:SetBlessing(name, nil) end
end

-- The blessing a paladin keeps up (a skillLine), or nil.
function Group:BlessingOf(name)
    if name == ns.playerName then return ns.charDB.blessing end
    return blessings[name]
end

-- Sets your own blessing, or (the leader) someone else's.
function Group:SetBlessing(name, skillLine)
    if name == ns.playerName then
        ns.charDB.blessing = skillLine
        statusStale = true
    elseif self:AmLeader() then
        blessings[name] = skillLine
        SavePlan()
        SendBlessing(name, skillLine)
    end
    self:Refresh()
end

-- "Camp plan: Anna - Mana regen, Cai - Blessing of Might" (a click only).
-- Marks (or unmarks) a player without the addon as having a camp buff's object.
function Group:SetClaim(skillLine, name, on)
    claims[skillLine] = claims[skillLine] or {}
    claims[skillLine][name] = on or nil
    self:Refresh()
end

function Group:HasClaim(skillLine, name)
    return (claims[skillLine] or {})[name] == true
end

-- The plan as "Name - buff" parts.
function Group:PlanParts(roster)
    local parts, paladins = {}, Paladins(roster or self:Roster())
    for _, profession in ipairs(ns.PROFESSIONS) do
        local name = assignments[profession.id]
        if name then parts[#parts + 1] = format("%s - %s", Short(name), profession.buff) end
        for _, paladin in ipairs(paladins) do
            if self:BlessingOf(paladin) == profession.id then
                parts[#parts + 1] = format("%s - %s", Short(paladin), profession.conflicts)
            end
        end
    end
    return parts
end

-- The plan as chat messages: one if it fits (255 characters), else numbered
-- parts ("Camp plan (1/2): ..."), each posted with its own click.
function Group:PlanMessages(roster)
    local parts = self:PlanParts(roster)
    if #parts == 0 then return {} end
    local whole = format(L["Camp plan: %s"], table.concat(parts, ", "))
    if #whole <= 255 then return { whole } end
    local room = 255 - #format(L["Camp plan (%d/%d): %s"], 9, 9, "")
    local chunks, current = {}, {}
    for _, part in ipairs(parts) do
        if #current > 0 and #(table.concat(current, ", ") .. ", " .. part) > room then
            chunks[#chunks + 1] = table.concat(current, ", ")
            current = {}
        end
        current[#current + 1] = part
    end
    chunks[#chunks + 1] = table.concat(current, ", ")
    for i, chunk in ipairs(chunks) do chunks[i] = format(L["Camp plan (%d/%d): %s"], i, #chunks, chunk):sub(1, 255) end
    return chunks
end

-- The tier of the camp object someone carries for a buff, or nil.
local function CarriedTier(status, skillLine)
    return status.carried and status.carried[skillLine]
end

-- What to ask someone who's been given a job: place their object, or keep up
-- their blessing.
function Group:AskText(skillLine, name)
    local profession = ns.PROFESSION_BY_ID[skillLine]
    if IS_BLESSING[skillLine] and self:BlessingOf(name) == skillLine then
        return format(L["Could you keep up %s for the camp?"], profession.conflicts)
    end
    local status = self:Statuses()[name]
    local tier = status and CarriedTier(status, skillLine)
    local object = tier and ns.ObjectName(skillLine, tier) or format(L["%s camp object"], profession.buff)
    return format(L["Could you place your %s at the camp?"], object)
end

-- Who has a job on a row (an object to place, or a blessing), if anyone.
function Group:JobHolder(skillLine, roster)
    if assignments[skillLine] then return assignments[skillLine] end
    if IS_BLESSING[skillLine] then
        for _, name in ipairs(Paladins(roster or self:Roster())) do
            if self:BlessingOf(name) == skillLine then return name end
        end
    end
end

-- Planning ------------------------------------------------------------------------

-- Class buffs that give the same stat as a camp buff (ns.CLASS_BUFFS, Data.lua):
-- Arcane Intellect, Power Word: Fortitude, Mark of the Wild, Strength of Earth
-- Totem, and the talents Divine Spirit and Moonkin Aura. Baseline ones count as
-- soon as someone of that class is in the group; talent ones (not every player
-- of the class has them) only once seen on someone. Paladin blessings count
-- by each paladin's pick instead (IS_BLESSING).
local CLASS_COVERS = {}
for skillLine, entry in pairs(ns.CLASS_BUFFS) do
    if not entry.blessing then CLASS_COVERS[skillLine] = entry end
end

-- Your status and everyone else's who has the addon: [full name] = status.
function Group:Statuses(roster)
    local list = { [ns.playerName] = self:MyStatus() }
    for _, entry in ipairs(roster or self:Roster()) do
        if members[entry.name] then list[entry.name] = members[entry.name] end
    end
    return list
end

-- The highest tier someone can make (0 if none), from the recipes they've
-- learned. Skill alone says nothing: some recipes have to be found first.
local function CraftTier(status, skillLine)
    return status.recipes and status.recipes[skillLine] or 0
end

-- Who in the group can bring a camp buff's stat with a class buff: every
-- paladin for Might and Wisdom (Kings only where it's known: their pick, or
-- your own talent), and the class with that buff (Arcane Intellect...).
-- { { name, class, sure } }: sure = known for certain (a talent buff, like
-- Divine Spirit, not every player of the class has).
function Group:Givers(skillLine, roster)
    local givers, rule = {}, CLASS_COVERS[skillLine]
    for _, entry in ipairs(roster or self:Roster()) do
        if IS_BLESSING[skillLine] then
            if entry.class == "PALADIN" then
                local sure = skillLine ~= KINGS or self:BlessingOf(entry.name) == KINGS
                    or (entry.name == ns.playerName and KnowsBlessing(KINGS))
                givers[#givers + 1] = { name = entry.name, class = entry.class, sure = sure }
            end
        elseif rule and entry.class == rule.class then
            givers[#givers + 1] = { name = entry.name, class = entry.class, sure = not rule.talent }
        end
    end
    return givers
end

-- Which camp buffs a class buff in the group already gives:
-- [skillLine] = { buff = its name, givers = { names }, seenOn = { names } }.
-- withoutBlessings leaves paladins' blessings out (the presets pick those).
-- While someone's auras can't be read (combat, instances), what was read
-- last is kept.
function Group:CoveredBuffs(roster, withoutBlessings)
    roster = roster or self:Roster()
    local seen = {}
    for _, entry in ipairs(roster) do
        local buffs, unreadable = ns.UnitCoveredBuffs(entry.unit)
        if unreadable then
            buffs = lastCovered[entry.name] or buffs
        else
            lastCovered[entry.name] = buffs
        end
        for skillLine in pairs(buffs) do
            if not (withoutBlessings and IS_BLESSING[skillLine]) then
                seen[skillLine] = seen[skillLine] or {}
                table.insert(seen[skillLine], Short(entry.name))
            end
        end
    end
    local covered = {}
    for _, profession in ipairs(ns.PROFESSIONS) do
        local rule = CLASS_COVERS[profession.id]
        local givers = {}
        for _, entry in ipairs(roster) do
            if IS_BLESSING[profession.id] then
                if not withoutBlessings and entry.class == "PALADIN" and self:BlessingOf(entry.name) == profession.id then
                    givers[#givers + 1] = Short(entry.name)
                end
            elseif rule and entry.class == rule.class then
                givers[#givers + 1] = Short(entry.name)
            end
        end
        local seenOn = seen[profession.id] or {}
        local counts = #givers > 0 and (IS_BLESSING[profession.id] or (rule and not rule.talent))
        if #seenOn > 0 or counts then
            covered[profession.id] = { buff = profession.conflicts or profession.buff, givers = givers, seenOn = seenOn }
        end
    end
    return covered
end

-- Who could bring a camp buff's object, best first: { name, tier, carries, ready }.
-- Someone carrying one beats someone who'd have to make it; then higher tiers
-- (more workspaces and services); then whoever can place it now.
function Group:Options(skillLine, statuses)
    local now, options = GetServerTime(), {}
    -- Players without the addon someone has marked as having one (tier unknown).
    for name in pairs(claims[skillLine] or {}) do
        if not statuses[name] then
            options[#options + 1] = { name = name, tier = 0, carries = true, ready = true, claimed = true }
        end
    end
    for name, status in pairs(statuses) do
        local ready = status.readyAt <= now
        local carried = CarriedTier(status, skillLine)
        if carried then
            options[#options + 1] = { name = name, tier = carried, carries = true, ready = ready }
        else
            local tier = CraftTier(status, skillLine)
            if tier > 0 then options[#options + 1] = { name = name, tier = tier, carries = false, ready = ready } end
        end
    end
    table.sort(options, function(a, b)
        if a.carries ~= b.carries then return a.carries end
        if a.tier ~= b.tier then return a.tier > b.tier end
        if a.ready ~= b.ready then return a.ready end
        return a.name < b.name
    end)
    return options
end

-- How the one asked to place a buff is getting on: a colour and a sentence.
local function AssignmentState(name, skillLine, statuses)
    local status, now = statuses[name], GetServerTime()
    if not status then
        return GREY, format(L["%s doesn't have Happy Camper, so their bags can't be checked."], Short(name))
    elseif not CarriedTier(status, skillLine) then
        return ORANGE, CraftTier(status, skillLine) > 0 and format(L["%s can make one but isn't carrying it."], Short(name))
            or format(L["%s doesn't have this camp object in their bags."], Short(name))
    elseif status.readyAt > now then
        return ORANGE, format(L["%s can place it in %s."], Short(name), ns.FormatTime(status.readyAt - now))
    end
    return GREEN, format(L["%s has it and can place it now."], Short(name))
end

local function Tiered(text, tier)
    if not tier or tier == 0 then return text end
    return format("%s %s", text, format(L["T%d"], tier))
end
Group.Tiered = Tiered -- the Camp Builder shows tiers the same way

-- How one camp buff stands for the group: { options, covered, applied = { names },
-- assigned, paladins, tier, setup }. setup is the Camp Setup text, coloured.
function Group:BuffPlan(profession, statuses, covered, camp, roster)
    local now = GetServerTime()
    local plan = { options = self:Options(profession.id, statuses), covered = covered[profession.id], paladins = {} }
    if IS_BLESSING[profession.id] then plan.paladins = Paladins(roster or self:Roster()) end
    local placers, placedTier = {}, 0
    for name, status in pairs(statuses) do
        if status.placedSkill == profession.id and now - status.placedAt < PLACED_SHOWN then
            placers[#placers + 1] = Short(name)
            placedTier = math.max(placedTier, status.placedTier or 0)
        end
    end
    table.sort(placers)
    local campTier = camp and (camp.equipment or {})[profession.id]
    local atCamp = camp ~= nil and (camp.professions[profession.id] == true or campTier ~= nil)
    if #placers > 0 or atCamp then plan.applied = placers end
    plan.assigned = assignments[profession.id]

    if plan.covered then
        plan.setup = AZURE .. plan.covered.buff .. "|r"
    elseif plan.applied then
        plan.tier = math.max(placedTier, campTier or 0)
        plan.setup = GREEN .. Tiered(L["Applied"], plan.tier) .. "|r"
    elseif plan.assigned then
        for _, option in ipairs(plan.options) do
            if option.name == plan.assigned then plan.tier = option.tier end
        end
        local who = plan.assigned == ns.playerName and L["You"] or Short(plan.assigned)
        plan.setup = AssignmentState(plan.assigned, profession.id, statuses) .. Tiered(who, plan.tier) .. "|r"
    elseif #plan.options > 0 then
        plan.tier = 0
        for _, option in ipairs(plan.options) do plan.tier = math.max(plan.tier, option.tier) end
        plan.setup = WHITE .. Tiered(L["Available"], plan.tier) .. "|r"
    else
        plan.setup = GREY .. L["Nobody can"] .. "|r"
    end
    return plan
end

-- Matches rows to players, one each, in row order (Kuhn's algorithm), stopping
-- at limit matches: [name] = index in rows. Each row lists its players in
-- rows[i][field] ({ name } entries, best first).
local function Match(rows, field, limit)
    local holder = {}
    local function Try(i, visited)
        for _, option in ipairs(rows[i][field]) do
            if not visited[option.name] then
                visited[option.name] = true
                local other = holder[option.name]
                if not other or Try(other, visited) then
                    holder[option.name] = i
                    return true
                end
            end
        end
        return false
    end
    local matched = 0
    for i = 1, #rows do
        if matched >= limit then break end
        if Try(i, {}) then matched = matched + 1 end
    end
    return holder
end

-- The leader's presets: fills the plan for the preset's buffs. Paladins'
-- blessings go first, since they take no room at the fire; then objects, as
-- many as the fire still has room for, each player placing at most one (one
-- an hour), preferring someone who carries it, then the highest tier. Buffs
-- another class buff covers, or that are already applied, are skipped.
function Group:ApplyPreset(preset)
    if not self:AmLeader() then return end
    local camp, roster = ns.Social:MyCamp(), self:Roster()
    local statuses = self:Statuses(roster)
    local covered = self:CoveredBuffs(roster, true)
    local slots, here = self:Fire(statuses, camp)
    for _ in pairs(here) do slots = slots - 1 end
    slots = math.max(slots, 0)
    local paladins = Paladins(roster)
    local wanted = {}
    for _, skillLine in ipairs(preset.skills) do
        local profession = ns.PROFESSION_BY_ID[skillLine]
        local plan = profession and self:BuffPlan(profession, statuses, covered, camp, roster)
        if plan and not plan.covered and not plan.applied then
            -- Kings only from a paladin known to have it.
            local givers = {}
            for _, name in ipairs(plan.paladins) do
                if skillLine ~= KINGS or self:BlessingOf(name) == KINGS or (name == ns.playerName and KnowsBlessing(KINGS)) then
                    givers[#givers + 1] = { name = name }
                end
            end
            wanted[#wanted + 1] = { skillLine = skillLine, options = plan.options, givers = givers }
        end
    end
    local blessed = Match(wanted, "givers", #paladins)
    local isBlessed, rest = {}, {}
    for _, i in pairs(blessed) do isBlessed[i] = true end
    for i, want in ipairs(wanted) do
        if not isBlessed[i] then rest[#rest + 1] = want end
    end
    local holder = Match(rest, "options", slots)
    self:ClearPlan()
    for name, i in pairs(blessed) do self:SetBlessing(name, wanted[i].skillLine) end
    for name, i in pairs(holder) do self:Assign(rest[i].skillLine, name) end
    self:Refresh()
end

-- The biggest fire anyone in the group can light (0 if nobody has a kit).
function Group:BestKit(statuses)
    local best = 0
    for _, status in pairs(statuses or self:Statuses()) do best = math.max(best, status.kit) end
    return best
end

local FIRE_HOLDS = { 3, 5, 10 } -- objects a campfire of each tier holds

-- The plan's fire: how many objects it holds, and the buffs whose objects are
-- already at it ([skillLine] = true). It's the camp you're at; else the
-- biggest kit in the group; else a Basic one. Every object already at the
-- fire takes a slot, whatever its buff: the camp's, and any just placed that
-- it doesn't list yet.
function Group:Fire(statuses, camp)
    local slots = camp and camp.slots or self:BestKit(statuses)
    if slots == 0 then slots = FIRE_HOLDS[1] end
    local here, now = {}, GetServerTime()
    if camp then
        for skillLine in pairs(camp.professions or {}) do
            if skillLine ~= COOKING then here[skillLine] = true end -- Cooking: the fire itself
        end
        for skillLine in pairs(camp.equipment or {}) do here[skillLine] = true end
    end
    for _, status in pairs(statuses) do
        if status.placedSkill and now - status.placedAt < PLACED_SHOWN then here[status.placedSkill] = true end
    end
    return slots, here
end

-- How many more objects the plan has room for (can be below 0 if the fire got
-- smaller), how many the fire holds, and the buffs already at it. Objects at
-- the fire and objects asked for take a slot each; the fire itself and
-- paladins' blessings take none.
function Group:FireRoom(statuses, camp)
    statuses = statuses or self:Statuses()
    local slots, here = self:Fire(statuses, camp or ns.Social:MyCamp())
    local used = 0
    for _ in pairs(here) do used = used + 1 end
    for skillLine in pairs(assignments) do
        if skillLine ~= COOKING and not here[skillLine] then used = used + 1 end
    end
    return slots - used, slots, here
end

-- Whether someone new can be asked to place this buff's object: the fire
-- itself, a buff someone's already asked for (a swap) or already at the fire,
-- or room left at the fire.
function Group:HasRoomFor(skillLine, statuses, camp)
    if skillLine == COOKING or assignments[skillLine] then return true end
    local room, _, here = self:FireRoom(statuses, camp)
    return here[skillLine] == true or room > 0
end

-- Tab -----------------------------------------------------------------------------

-- Sets text to as many names as fit, then "+N".
local function FitNames(text, names, empty)
    if #names == 0 then return text:SetText(empty) end
    local shown = #names
    repeat
        local line = table.concat(names, ", ", 1, shown)
        if shown < #names then line = format("%s +%d", line, #names - shown) end
        text:SetText(line)
        shown = shown - 1
    until not text:IsTruncated() or shown < 1
end
Group.FitNames = FitNames

-- A camp object as Your group lists it: "Mana Well (Mana regen)".
local function ObjectText(skillLine, tier)
    local profession = ns.PROFESSION_BY_ID[skillLine]
    local name = ns.ObjectName(skillLine, tier)
    return profession.notSearchable and name or format("%s (%s)", name, profession.buff)
end

-- The leader's Camp Setup menu for a buff: nobody, someone to place its
-- object, or (for a blessing) a paladin to keep that blessing up.
local function AssignMenu(root, skillLine)
    local roster = Group:Roster()
    local statuses = Group:Statuses(roster)
    local paladins = IS_BLESSING[skillLine] and Paladins(roster) or {}
    local function ClearBlessings()
        for _, name in ipairs(paladins) do
            if Group:BlessingOf(name) == skillLine then Group:SetBlessing(name, nil) end
        end
    end
    local function IsNobody()
        if assignments[skillLine] then return false end
        for _, name in ipairs(paladins) do
            if Group:BlessingOf(name) == skillLine then return false end
        end
        return true
    end
    root:CreateRadio(L["Nobody"], IsNobody, function()
        ClearBlessings()
        Group:Assign(skillLine, nil)
    end, "")
    local tiers = {}
    for _, option in ipairs(Group:Options(skillLine, statuses)) do tiers[option.name] = option end
    -- A full fire: nobody new can be asked for an object here (blessings still can).
    local room = Group:HasRoomFor(skillLine, statuses)
    if not room then
        root:CreateTitle(format(L["The fire holds %d objects, all planned. Set another row to Nobody first."],
            select(2, Group:FireRoom(statuses))))
    end
    for _, entry in ipairs(roster) do
        local option = tiers[entry.name]
        local label = Short(entry.name)
        if option then
            label = label .. (option.carries and GREEN or GREY) .. " "
                .. format(option.carries and L["(has tier %d)"] or L["(can make tier %d)"], option.tier) .. "|r"
        end
        local item = root:CreateRadio(label, function(name) return assignments[skillLine] == name end, function(name)
            ClearBlessings()
            Group:Assign(skillLine, name)
        end, entry.name)
        if not room and type(item) == "table" and item.SetEnabled then item:SetEnabled(false) end
    end
    if #paladins > 0 then
        root:CreateTitle(L["Or a paladin's blessing:"])
        local blessing = ns.PROFESSION_BY_ID[skillLine].conflicts
        for _, name in ipairs(paladins) do
            root:CreateRadio(Short(name) .. " " .. AZURE .. blessing .. "|r",
                function(paladin) return Group:BlessingOf(paladin) == skillLine end,
                function(paladin)
                    Group:Assign(skillLine, nil)
                    Group:SetBlessing(paladin, skillLine)
                end, name)
        end
    end
end

-- A name in its class colour.
local function ClassName(name, class)
    local color = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    return color and format("|c%s%s|r", color.colorStr, Short(name)) or Short(name)
end

-- Who has it: first whoever can bring it with a class buff (a paladin's
-- blessing, Arcane Intellect...), then the players with Happy Camper who have
-- the item or can make one (their bags and recipes say so; it can't be
-- changed), then everyone without the addon (grey), with a tick for "says
-- they have one".
WhoMenu = function(root, skillLine)
    local classOf = {}
    local roster = Group:Roster()
    local statuses = Group:Statuses(roster)
    for _, entry in ipairs(roster) do classOf[entry.name] = entry.class end
    local buff = ns.PROFESSION_BY_ID[skillLine].conflicts
    for _, giver in ipairs(Group:Givers(skillLine, roster)) do
        local name = giver.sure and ClassName(giver.name, giver.class) or (GREY .. Short(giver.name) .. "|r")
        local item = root:CreateCheckbox(name .. " " .. AZURE .. "(" .. buff .. ")|r",
            function() return giver.sure end, function() end, giver.name)
        if type(item) == "table" and item.SetEnabled then item:SetEnabled(false) end
    end
    for _, option in ipairs(Group:Options(skillLine, statuses)) do
        if not option.claimed then
            local label = ClassName(option.name, classOf[option.name]) .. " " .. GREY
                .. format(option.carries and L["(has tier %d)"] or L["(can make tier %d)"], option.tier) .. "|r"
            local item = root:CreateCheckbox(label, function() return true end, function() end, option.name)
            if type(item) == "table" and item.SetEnabled then item:SetEnabled(false) end
        end
    end
    for _, entry in ipairs(roster) do
        if not statuses[entry.name] then
            root:CreateCheckbox(GREY .. Short(entry.name) .. "|r",
                function(name) return Group:HasClaim(skillLine, name) end,
                function(name) Group:SetClaim(skillLine, name, not Group:HasClaim(skillLine, name)) end, entry.name)
        end
    end
end

-- Your own blessing, for paladins: none, or one you know.
local function BlessingMenu(root)
    local function IsSelected(skillLine) return (ns.charDB.blessing or 0) == skillLine end
    local function Select(skillLine) Group:SetBlessing(ns.playerName, skillLine ~= 0 and skillLine or nil) end
    root:CreateRadio(L["None"], IsSelected, Select, 0)
    for _, skillLine in ipairs(BLESSINGS) do
        if KnowsBlessing(skillLine) or ns.charDB.blessing == skillLine then
            root:CreateRadio(ns.PROFESSION_BY_ID[skillLine].conflicts, IsSelected, Select, skillLine)
        end
    end
end

-- The tab --------------------------------------------------------------------------
-- Along the top, in a group: Planned, Placed and Camp Benefits; then the
-- leader's presets, and Your job when the leader has asked you to place
-- something. Then the plan, a row per camp buff: a mark for its state, the
-- object's icon, the buff and its profession, Who has it, and Camp Setup as a
-- pill in the state's colour. Rows with nothing left to decide (placed,
-- covered by a class buff, nobody can) are dimmed, and your own job is lit
-- gold. Last, Your group as a table.

-- Each state a camp buff's plan can be in: its row's mark, its Camp Setup
-- pill's colour and how bright its row is (as on the Camp Builder).
local STATES = ns.Style.PLAN_STATES

-- A camp buff's state; for one someone's asked to place, also how they're
-- getting on ("ready", "waiting" or "unknown": no Happy Camper).
local function PlanState(plan, skillLine, statuses)
    if plan.covered then return "covered" end
    if plan.applied then return "placed" end
    if plan.assigned then
        local color = AssignmentState(plan.assigned, skillLine, statuses)
        local progress = color == GREEN and "ready" or color == ORANGE and "waiting" or "unknown"
        return plan.assigned == ns.playerName and "yours" or progress, progress
    end
    if #plan.options > 0 then return "open" end
    return "nobody"
end

local function Panel(parent) return ns.Style:Panel(parent) end

-- Sets text to template with as many of names as fit, then "+N".
local function FitInto(text, template, names)
    local shown = #names
    repeat
        local list = table.concat(names, ", ", 1, shown)
        if shown < #names then list = format("%s +%d", list, #names - shown) end
        text:SetText(format(template, list))
        shown = shown - 1
    until not text:IsTruncated() or shown < 1
end

local function Tile(parent, width) return ns.Style:Tile(parent, width) end

local function BuffRow(parent, profession, y)
    local style = ns.Style
    local row = style:PlanRow(parent, profession, y)
    -- Who has it. In a group it opens a menu of everyone: players with Happy
    -- Camper (class colour) show what their bags and recipes say; players
    -- without it (grey) can be marked as having one, since the addon can't check.
    row.who = style:Text(row, "GameFontHighlightSmall", nil, "LEFT")
    row.who:SetPoint("LEFT", WHO_X, 0)
    row.who:SetWidth(WHO_WIDTH)
    row.who:SetWordWrap(false)
    row.whoMenu = style:MenuLabel(row, WHO_WIDTH + 2, function(_, root) WhoMenu(root, profession.id) end)
    row.whoMenu:SetPoint("LEFT", WHO_X - 2, 0)
    style:Tooltip(row.whoMenu, L["Who has it"], L["Players with Happy Camper show what their bags and recipes say. Mark players without it (grey) who say they have one."])
    row.whoMenu:Hide()
    -- Camp Setup: a pill in the state's colour. The leader's opens the menu.
    row.pill = style:Pill(row)
    row.pill:SetPoint("LEFT", SETUP_X, 0)
    row.setup = row.pill.text
    row.assign = style:PillMenu(row.pill, function(_, root) AssignMenu(root, profession.id) end)
    style:Tooltip(row.assign, L["Camp Setup"], L["Ask someone to place it, or a paladin to keep up a blessing."])
    -- How long before whoever was asked can place it.
    row.wait = style:Text(row, "GameFontHighlightSmall", nil, "LEFT")
    row.wait:SetPoint("LEFT", row.pill, "RIGHT", 4, 0)
    -- The leader's nudge to whoever has the job: a whisper, sent on the click.
    row.whisper = CreateFrame("Button", nil, row)
    row.whisper:SetSize(16, 16)
    row.whisper:SetPoint("LEFT", row.pill, "RIGHT", 4, 0)
    row.whisper:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIcon-Chat-Up")
    row.whisper:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
    row.whisper:SetScript("OnClick", function()
        local name = Group:AmLeader() and Group:JobHolder(profession.id)
        if name then ns.Announce:Send(Group:AskText(profession.id, name), "WHISPER", nil, Ambiguate(name, "none")) end
    end)
    style:CustomTooltip(row.whisper, "ANCHOR_RIGHT", function(tooltip)
        local name = Group:JobHolder(profession.id)
        tooltip:SetText(L["Whisper"])
        if name then
            tooltip:AddLine(format(L["Whispers %s: \"%s\""], Short(name),
                Group:AskText(profession.id, name)), 1, 1, 1, true)
        end
    end)
    row.whisper:Hide()
    style:CustomTooltip(row, "ANCHOR_RIGHT", function(tooltip, self)
        local plan = self.plan
        tooltip:SetText(format("%s (%s)", profession.buff, profession.name))
        ns.AddBuffSize(tooltip, profession)
        -- What the others get, where their levels make it differ.
        local low, high = GroupLevels()
        if low and ns.BuffStep(profession, low) ~= ns.BuffStep(profession, high) then
            tooltip:AddLine(format(L["Your group: %s (level %d) to %s (level %d)"], ns.BuffText(profession, low), low,
                ns.BuffText(profession, high), high), 0.7, 0.7, 0.7, true)
        end
        if not plan then return end
        tooltip:AddLine(" ")
        if plan.covered then
            tooltip:AddLine(format(L["%s gives the same, so this adds nothing."], plan.covered.buff), 0.25, 0.65, 1, true)
            if #plan.covered.givers > 0 then
                tooltip:AddLine(format(L["Can give it: %s"], table.concat(plan.covered.givers, ", ")), 1, 1, 1, true)
            end
            if #plan.covered.seenOn > 0 then
                tooltip:AddLine(format(L["On them now: %s"], table.concat(plan.covered.seenOn, ", ")), 0.7, 0.7, 0.7, true)
            end
        elseif plan.applied then
            tooltip:AddLine(#plan.applied > 0 and format(L["Placed by: %s"], table.concat(plan.applied, ", "))
                or L["It's at the camp you're at."], 0.4, 1, 0.4, true)
        end
        if #plan.paladins > 0 and not (plan.covered and #plan.covered.givers > 0) then
            local names = {}
            for _, name in ipairs(plan.paladins) do names[#names + 1] = Short(name) end
            tooltip:AddLine(format(L["Paladins can give it, one blessing each: %s"], table.concat(names, ", ")), 0.25, 0.65, 1, true)
        end
        for _, option in ipairs(plan.options) do
            local line
            if option.carries then
                line = format(L["%s carries one (tier %d)"], Short(option.name), option.tier)
            else
                line = format(L["%s can make tier %d"], Short(option.name), option.tier)
            end
            local shade = option.carries and 1 or 0.7
            tooltip:AddLine(line, shade, shade, shade, true)
        end
        -- Every tier gives the same buff; what the others add.
        local extras = ns.OBJECT_EXTRAS[profession.id] or {}
        for tier = 1, 3 do
            if extras[tier] then
                tooltip:AddLine(format(L["Tier %d: %s"], tier, ns.JoinList(extras[tier])), 0.7, 0.7, 0.7, true)
            end
        end
        if #plan.options == 0 and not plan.covered and not plan.applied then
            tooltip:AddLine(L["Nobody in the group has one or can make one."], 0.7, 0.7, 0.7, true)
        end
        if plan.assigned then
            local _, state = AssignmentState(plan.assigned, profession.id, Group:Statuses())
            tooltip:AddLine(" ")
            tooltip:AddLine(state, 1, 0.82, 0, true)
        end
    end)
    return row
end

-- Camp Setup's pill (Style:FitPill), with room left for the wait and the
-- whisper button after it.
local function FitPill(row, look, menu)
    local room = SETUP_WIDTH - (row.wait:IsShown() and ns.Style:TextWidth(row.wait) + 6 or 0)
        - (row.whisper:IsShown() and 22 or 0)
    ns.Style:FitPill(row.pill, look, menu, room)
    row.whisper:ClearAllPoints()
    row.whisper:SetPoint("LEFT", row.wait:IsShown() and row.wait or row.pill, "RIGHT", 4, 0)
end

local function MemberRow(list, i)
    local row = list.rows[i]
    if row then return row end
    local style = ns.Style
    row = CreateFrame("Frame", nil, list.child)
    row:SetSize(ROW_WIDTH, MEMBER_HEIGHT)
    row:SetPoint("TOPLEFT", 0, -(i - 1) * MEMBER_HEIGHT)
    row.line = row:CreateTexture(nil, "BACKGROUND")
    row.line:SetColorTexture(1, 0.82, 0.4, 0.08)
    row.line:SetHeight(1)
    row.line:SetPoint("BOTTOMLEFT")
    row.line:SetPoint("BOTTOMRIGHT")
    row.name = style:Text(row, "GameFontHighlightSmall", nil, "LEFT")
    row.name:SetPoint("LEFT", 2, 0)
    row.name:SetWidth(CARRIES_X - 8)
    row.name:SetWordWrap(false)
    -- The camp objects they carry: icons, each with its tier.
    row.carried = {}
    for k = 1, MAX_CARRIED do
        local icon = row:CreateTexture(nil, "ARTWORK")
        icon:SetSize(16, 16)
        icon:SetPoint("LEFT", CARRIES_X + (k - 1) * 20, 0)
        icon.tier = row:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
        icon.tier:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 3, -2)
        row.carried[k] = icon
    end
    row.more = style:Text(row, "GameFontHighlightSmall", nil, "LEFT")
    row.more:SetPoint("LEFT", CARRIES_X, 0)
    row.benefits = style:Text(row, "GameFontHighlightSmall", nil, "LEFT")
    row.benefits:SetPoint("LEFT", BENEFITS_X, 0)
    row.benefits:SetWidth(OBJECT_X - BENEFITS_X - 4)
    row.benefits:SetWordWrap(false)
    row.mark = row:CreateTexture(nil, "ARTWORK")
    row.mark:SetSize(12, 12)
    row.mark:SetPoint("LEFT", OBJECT_X, 0)
    row.state = style:Text(row, "GameFontHighlightSmall", nil, "LEFT")
    row.state:SetPoint("LEFT", OBJECT_X + 16, 0)
    row.state:SetWordWrap(false)
    -- Hover: every camp object they carry, in full.
    style:CustomTooltip(row, "ANCHOR_RIGHT", function(tooltip, self)
        tooltip:SetText(self.nameText or "")
        for _, line in ipairs(self.objects or {}) do tooltip:AddLine(line, 1, 1, 1, true) end
        if self.stateText then tooltip:AddLine(self.stateText, 1, 0.82, 0, true) end
    end)
    list.rows[i] = row
    return row
end

-- Place: a button that uses the item, which only the game's secure code may
-- do. It's a frame of its own laid over Your job's spot, never inside the
-- window (a secure button inside would stop the window closing or moving in
-- a fight). It hides as a fight starts, when the game still allows it, and
-- comes back after.
local placeButton
local job -- your job as the tab last showed it: { item, ready, label }, or nil

function Group:SyncPlace()
    if ns.InCombat() then return end
    local page = self.page
    local spot = page and page.placeSpot
    if not placeButton then
        if not (spot and job) then return end
        placeButton = CreateFrame("Button", "HappyCamperGroupPlace", UIParent, "SecureActionButtonTemplate, UIPanelButtonTemplate")
        placeButton:RegisterForClicks("AnyUp", "AnyDown")
        placeButton:SetAttribute("type1", "item")
        placeButton:Hide()
    end
    local item = job and job.item
    if placeButton.item ~= item then
        placeButton:SetAttribute("item", item and ("item:" .. item) or nil)
        placeButton.item = item
    end
    local x, y
    if job and spot:IsVisible() then x, y = spot:GetCenter() end
    if not (x and y) then
        placeButton:Hide()
        return
    end
    -- Its scale and place the spot's, over the window.
    placeButton:SetScale(spot:GetEffectiveScale() / UIParent:GetEffectiveScale())
    placeButton:SetSize(spot:GetWidth(), spot:GetHeight())
    if placeButton.x ~= x or placeButton.y ~= y then
        placeButton:ClearAllPoints()
        placeButton:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x, y)
        placeButton.x, placeButton.y = x, y
    end
    local window = page:GetParent()
    placeButton:SetFrameStrata(window:GetFrameStrata())
    placeButton:SetFrameLevel(window:GetFrameLevel() + 30)
    placeButton:SetText(job.label)
    placeButton:SetEnabled(job.ready and item ~= nil)
    placeButton:Show()
end

local placeEvents = CreateFrame("Frame")
placeEvents:RegisterEvent("PLAYER_REGEN_DISABLED")
placeEvents:RegisterEvent("PLAYER_REGEN_ENABLED")
placeEvents:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_REGEN_DISABLED" then
        if placeButton then placeButton:Hide() end -- still allowed as the fight starts
    else
        Group:SyncPlace()
    end
end)

function Group:Build(page)
    local style = ns.Style
    page.title = style:PageTitle(page, L["Plan a camp with your group"])
    -- Out of a group: what the tab is for.
    page.note = style:Text(page, "GameFontHighlightSmall", nil, "LEFT")
    page.note:SetPoint("TOPLEFT", PAD, TOP_Y)
    page.note:SetWidth(WIDTH - 2 * PAD)

    -- In a group: Planned, Placed and Camp Benefits.
    page.tiles = CreateFrame("Frame", nil, page)
    page.tiles:SetSize(WIDTH - 2 * PAD, TILE_HEIGHT)
    local tileWidth = math.floor((WIDTH - 2 * PAD - 2 * GAP) / 3)
    local tiles = {}
    for i = 1, 3 do
        tiles[i] = Tile(page.tiles, tileWidth)
        tiles[i]:SetPoint("TOPLEFT", (i - 1) * (tileWidth + GAP), 0)
    end
    page.planned, page.placed, page.benefits = tiles[1], tiles[2], tiles[3]
    page.planned.label:SetText(L["Planned"])
    page.placed.label:SetText(L["Placed"])
    -- The biggest campfire kits, on one line: as many names as fit, then "+N";
    -- hover for them all.
    page.kit, page.kitHover = page.planned.sub, page.planned

    -- The leader's presets.
    page.presets = CreateFrame("Frame", nil, page)
    page.presets:SetHeight(22)
    local label = style:Text(page.presets, "GameFontNormalSmall", L["Fill the plan for:"], "LEFT")
    label:SetPoint("LEFT")
    page.presets.label = label
    page.presetButtons = {}
    local previous
    for i, preset in ipairs(ns.Search.PRESETS) do
        local button = style:Button(page.presets, PRESET_WIDTH, L[preset.name], function() Group:ApplyPreset(preset) end, 20)
        if previous then button:SetPoint("LEFT", previous, "RIGHT", 6, 0) else button:SetPoint("LEFT", label, "RIGHT", 8, 0) end
        style:Tooltip(button, L[preset.name], L["Fills the plan for these buffs: paladins' blessings first, then objects, as many as the fire holds, one each, carried ones and the highest tiers first. Change any of it after."])
        page.presetButtons[i] = button
        previous = button
    end
    style:SameWidth(page.presetButtons, PRESET_WIDTH) -- a translation may make one grow

    -- Your job: what the leader asked you to place, and Place.
    local banner = CreateFrame("Frame", nil, page, "BackdropTemplate")
    banner:SetSize(WIDTH - 2 * PAD, BANNER_HEIGHT)
    if banner.SetBackdrop then
        banner:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
        banner:SetBackdropColor(0.13, 0.11, 0.06, 0.95)
        banner:SetBackdropBorderColor(1, 0.82, 0, 0.7)
    end
    banner.icon = banner:CreateTexture(nil, "ARTWORK")
    banner.icon:SetSize(32, 32)
    banner.icon:SetPoint("LEFT", 8, 0)
    page.placeSpot = CreateFrame("Frame", nil, banner)
    page.placeSpot:SetSize(PLACE_WIDTH, 24)
    page.placeSpot:SetPoint("RIGHT", -10, 0)
    banner.label = style:Text(banner, "GameFontNormalSmall", L["Your job"], "LEFT")
    banner.label:SetPoint("TOPLEFT", banner.icon, "TOPRIGHT", 8, 1)
    banner.title = style:Text(banner, "GameFontHighlight", nil, "LEFT")
    banner.title:SetPoint("LEFT", banner.icon, "RIGHT", 8, 0)
    banner.sub = style:Text(banner, "GameFontHighlightSmall", nil, "LEFT")
    banner.sub:SetPoint("BOTTOMLEFT", banner.icon, "BOTTOMRIGHT", 8, -1)
    for _, text in ipairs({ banner.label, banner.title, banner.sub }) do
        text:SetPoint("RIGHT", page.placeSpot, "LEFT", -8, 0)
        text:SetWordWrap(false)
    end
    -- The Place button follows the spot (the window can be dragged), and goes with it.
    local since = 0
    page.placeSpot:SetScript("OnUpdate", function(_, elapsed)
        since = since + elapsed
        if since < 0.1 then return end
        since = 0
        Group:SyncPlace()
    end)
    page.placeSpot:SetScript("OnHide", function() Group:SyncPlace() end)
    banner:Hide()
    page.job = banner

    -- The plan and Your group: placed under whatever the top shows (Refresh).
    local body = CreateFrame("Frame", nil, page)
    page.body = body
    local plan = Panel(body)
    plan:SetPoint("TOPLEFT", PAD, 0)
    plan:SetPoint("TOPRIGHT", -PAD, 0)
    style:Headings(plan, { { L["Camp buff"], BUFF_X }, { L["Who has it"], WHO_X }, { L["Camp Setup"], SETUP_X } })
    page.buffRows = {}
    local y = -LIST_TOP
    for _, profession in ipairs(ns.PROFESSIONS) do
        if not profession.notSearchable then
            page.buffRows[#page.buffRows + 1] = BuffRow(plan, profession, y)
            y = y - ROW_HEIGHT
        end
    end
    local planHeight = -y + INNER
    plan:SetHeight(planHeight)

    -- Everyone in the group, and a paladin's own blessing on the right.
    local groupY = -(planHeight + 10)
    page.membersHeader = style:Text(body, "GameFontNormal", L["Your group"])
    page.membersHeader:SetPoint("TOPLEFT", PAD, groupY)
    page.blessing = style:Dropdown(body, BLESSING_WIDTH, function(_, root) BlessingMenu(root) end)
    page.blessing:SetPoint("RIGHT", body, "TOPRIGHT", -PAD, groupY - 6)
    page.blessingLabel = style:Text(body, "GameFontNormalSmall", L["Your blessing:"], "RIGHT")
    page.blessingLabel:SetPoint("RIGHT", page.blessing, "LEFT", -6, 0)
    style:Tooltip(page.blessing, L["Your blessing:"], L["A paladin keeps up one blessing on each player. Pick yours, and the plan counts it."])
    local membersTop = planHeight + 34
    local panel = Panel(body)
    panel:SetPoint("TOPLEFT", PAD, -membersTop)
    panel:SetPoint("BOTTOMRIGHT", -PAD, 0)
    style:Text(panel, "GameFontNormalSmall", L["Name"], "LEFT"):SetPoint("TOPLEFT", INNER + 2, -6)
    style:Text(panel, "GameFontNormalSmall", L["Carries"], "LEFT"):SetPoint("TOPLEFT", INNER + CARRIES_X, -6)
    page.benefitsHead = style:Text(panel, "GameFontNormalSmall", nil, "LEFT")
    page.benefitsHead:SetPoint("TOPLEFT", INNER + BENEFITS_X, -6)
    style:Text(panel, "GameFontNormalSmall", L["Camp object"], "LEFT"):SetPoint("TOPLEFT", INNER + OBJECT_X, -6)
    local list = CreateFrame("ScrollFrame", nil, panel)
    list:SetPoint("TOPLEFT", INNER, -LIST_TOP)
    list:SetPoint("BOTTOMRIGHT", -INNER, 4)
    style:ScrollArea(list, ROW_WIDTH, MEMBER_HEIGHT)
    list.rows = {}
    page.members = list
    body.membersTop = membersTop

    -- Buttons along the bottom, all one size: Refresh on the left; the leader's
    -- Clear plan and the plan posted to Say or party/raid chat on the right.
    page.refresh = style:Button(page, BOTTOM_WIDTH, L["Refresh"], function()
        ns.Comm:SendGroup("GQ", "GQ")
        if Group:AmLeader() then SendPlan(true) end -- and the whole plan, so everyone has the same
        Group:Refresh()
    end, 22)
    page.refresh:SetPoint("BOTTOMLEFT", PAD, 6)
    style:Tooltip(page.refresh, L["Refresh"], L["Asks everyone in the group with Happy Camper for their camp objects and cooldowns."])
    local function PostTooltip()
        local messages = Group:PlanMessages()
        return #messages > 0 and (L["For players without the addon too:"] .. "\n" .. table.concat(messages, "\n"))
            or L["Pick who places what first (Camp Setup)."]
    end
    -- Posts the plan's next part (one message per click) to a chat.
    local function Post(chatType, key)
        local messages = Group:PlanMessages()
        if #messages == 0 then return end
        page.nextPart = page.nextPart or {}
        local i = math.min(page.nextPart[key] or 1, #messages)
        -- On to the next part only once this one went (not while chat waits).
        if ns.Announce:Send(messages[i], chatType) then page.nextPart[key] = i % #messages + 1 end
        Group:Refresh()
    end
    page.postGroup = style:Button(page, BOTTOM_WIDTH, L["Party"], function() Post(ns.Comm:GroupChatType(), "GROUP") end, 22)
    page.postGroup:SetPoint("BOTTOMRIGHT", -PAD, 6)
    page.postGroup:SetMotionScriptsWhileDisabled(true)
    style:InfoTooltip(page.postGroup, L["Post the plan in group chat"], PostTooltip)
    page.postSay = style:Button(page, BOTTOM_WIDTH, L["Say"], function() Post("SAY", "SAY") end, 22)
    page.postSay:SetPoint("RIGHT", page.postGroup, "LEFT", -BUTTON_GAP, 0)
    page.postSay:SetMotionScriptsWhileDisabled(true)
    style:InfoTooltip(page.postSay, L["Say the plan"], PostTooltip)
    page.clear = style:Button(page, BOTTOM_WIDTH, L["Clear plan"], function() Group:ClearPlan() end, 22)
    page.clear:SetPoint("RIGHT", page.postSay, "LEFT", -BUTTON_GAP, 0)
    style:Tooltip(page.clear, L["Clear plan"], L["Takes everyone off Camp Setup."])
    self.page = page
end

-- The bottom buttons, one size: the widest of them (a translation or a part
-- number, "(1/2)", can make one grow). If all four that wide wouldn't fit the
-- row, Refresh (set apart on the left) keeps its own size, and if it still
-- doesn't fit beside the leader's three it goes just above them. Returns how
-- high the buttons reach from the page's bottom.
local function SizeBottomButtons(page, leader)
    -- Each back to its own width first, so the row can shrink again.
    page.refresh:SetText(L["Refresh"])
    page.clear:SetText(L["Clear plan"])
    local all = { page.refresh, page.clear, page.postSay, page.postGroup }
    local widest = BOTTOM_WIDTH
    for _, button in ipairs(all) do widest = math.max(widest, button:GetWidth()) end
    local onRow = true
    if #all * widest + (#all - 1) * BUTTON_GAP <= WIDTH - 2 * PAD then
        ns.Style:SameWidth(all, BOTTOM_WIDTH)
    else
        local width = ns.Style:SameWidth({ page.clear, page.postSay, page.postGroup }, BOTTOM_WIDTH)
        onRow = not leader or page.refresh:GetWidth() + 3 * (width + BUTTON_GAP) <= WIDTH - 2 * PAD
    end
    page.refresh:ClearAllPoints()
    page.refresh:SetPoint("BOTTOMLEFT", PAD, onRow and 6 or 6 + 22 + BUTTON_GAP)
    return onRow and 28 or 28 + 22 + BUTTON_GAP
end

-- The three figures along the top.
local function FillTiles(page, roster, statuses, camp, placedRows)
    local now = GetServerTime()
    -- Planned: objects asked for or at the fire, of how many it holds; and who has the biggest kit.
    local room, slots = Group:FireRoom(statuses, camp)
    page.planned.big:SetText(format("%d/%d", slots - room, slots))
    local bestKit, kitNames = Group:BestKit(statuses), {}
    for name, status in pairs(statuses) do
        if bestKit > 0 and status.kit == bestKit then kitNames[#kitNames + 1] = Short(name) end
    end
    table.sort(kitNames)
    local kitLine
    if bestKit > 0 then
        FitInto(page.kit, L["Kit: %s"], kitNames)
        kitLine = format(#kitNames > 1 and L["Campfire: %s have kits for fires that hold %d objects."]
            or L["Campfire: %s has a kit for a fire that holds %d objects."], table.concat(kitNames, ", "), bestKit)
    else
        page.kit:SetText(GREY .. L["No campfire kit"] .. "|r")
        kitLine = L["Campfire: nobody has a campfire kit. Cooking makes them."]
    end
    page.planned.tipTitle = L["Planned"]
    page.planned.tipLines = { L["Objects planned or at the fire, of how many it holds."], kitLine }

    -- Placed: camp buffs already at the fire, and the latest the group placed.
    page.placed.big:SetText(tostring(#placedRows))
    local latest
    for _, status in pairs(statuses) do
        if status.placedSkill and now - status.placedAt < PLACED_SHOWN and (not latest or status.placedAt > latest.placedAt) then
            latest = status
        end
    end
    if latest then
        page.placed.sub:SetText(format(L["%s, %d min ago"], ns.ObjectName(latest.placedSkill, latest.placedTier or 1),
            math.max(1, math.floor((now - latest.placedAt) / 60))))
    else
        page.placed.sub:SetText(GREY .. L["Nothing placed yet"] .. "|r")
    end
    page.placed.tipTitle = L["Placed"]
    page.placed.tipLines = {}
    for _, row in ipairs(placedRows) do
        local by = #row.plan.applied > 0 and table.concat(row.plan.applied, ", ") or L["It's at the camp you're at."]
        page.placed.tipLines[#page.placed.tipLines + 1] = format("%s: %s", row.profession.buff, by)
    end

    -- Camp Benefits: who has it, from their buffs or their Happy Camper.
    local buff = BenefitsName()
    page.benefits.label:SetText(buff)
    local have, missing, unknown, soonest, soonName = 0, {}, {}, nil, nil
    page.benefits.tipTitle, page.benefits.tipLines = buff, {}
    for _, entry in ipairs(roster) do
        local name = entry.name == ns.playerName and L["you"] or Short(entry.name)
        local ends, line = BenefitsEnd(entry), nil
        if ends == nil then
            unknown[#unknown + 1] = name
            line = GREY .. format("%s: %s", Short(entry.name), L["not known"]) .. "|r"
        elseif not ends then
            missing[#missing + 1] = name
            line = RED .. format("%s: %s", Short(entry.name), L["none"]) .. "|r"
        else
            have = have + 1
            if not soonest or ends < soonest then soonest, soonName = ends, name end
            line = format("%s: %s", Short(entry.name), format(L["%d min"], math.max(1, math.floor((ends - now) / 60))))
        end
        page.benefits.tipLines[#page.benefits.tipLines + 1] = line
    end
    page.benefits.big:SetText(format("%d/%d", have, #roster))
    if #missing > 0 then
        FitInto(page.benefits.sub, RED .. L["Missing: %s"] .. "|r", missing)
    elseif soonest and soonest - now <= ENDING_SOON then
        page.benefits.sub:SetText(ORANGE .. format(L["Ending soon: %s"], soonName) .. "|r")
    elseif #unknown > 0 then
        FitInto(page.benefits.sub, GREY .. L["not known for %s"] .. "|r", unknown)
    else
        page.benefits.sub:SetText(GREEN .. L["Everyone has it"] .. "|r")
    end
end

function Group:Refresh()
    local page = self.page
    if not page or not page:IsVisible() then return end
    local inGroup = self:InGroup()
    local leader = self:AmLeader()
    local roster = self:Roster()
    local statuses = self:Statuses(roster)
    local covered = self:CoveredBuffs(roster)
    local camp = ns.Social:MyCamp()
    local now = GetServerTime()
    local classOf = {}
    for _, entry in ipairs(roster) do classOf[entry.name] = entry.class end

    -- The plan: a row per camp buff.
    local nobody = GREY .. L["nobody"] .. "|r"
    local placedRows, mine = {}, nil
    for _, row in ipairs(page.buffRows) do
        local skillLine = row.profession.id
        local plan = self:BuffPlan(row.profession, statuses, covered, camp, roster)
        row.plan = plan
        local state, progress = PlanState(plan, skillLine, statuses)
        row.state = state
        if state == "yours" and not mine then mine = row end
        if plan.applied then placedRows[#placedRows + 1] = row end
        -- Who could bring it, best first, each player once: players with Happy
        -- Camper in their class colour, those without it (marked as having
        -- one) in grey. A grey giver (Kings or a talent buff not known for
        -- sure) who has the object is in colour.
        local names, at = {}, {}
        for _, giver in ipairs(self:Givers(skillLine, roster)) do
            names[#names + 1] = giver.sure and ClassName(giver.name, giver.class) or (GREY .. Short(giver.name) .. "|r")
            at[giver.name] = { index = #names, sure = giver.sure }
        end
        for _, option in ipairs(plan.options) do
            local text = option.claimed and (GREY .. Short(option.name) .. "|r") or ClassName(option.name, classOf[option.name])
            local seen = at[option.name]
            if not seen then
                names[#names + 1] = text
                at[option.name] = { index = #names, sure = not option.claimed }
            elseif not seen.sure and not option.claimed then
                names[seen.index] = text
                seen.sure = true
            end
        end
        row.who:SetShown(not inGroup)
        row.whoMenu:SetShown(inGroup)
        FitNames(inGroup and row.whoMenu.label or row.who, names, nobody)
        -- Its state: the mark, how bright, and yours lit gold.
        local look = STATES[state]
        ns.Style:SetPlanState(row, look, progress and STATES[progress].mark)
        -- The leader gets a menu wherever there's a choice to make, and can
        -- nudge whoever has the job.
        local menu = leader and (plan.assigned ~= nil or #plan.paladins > 0
            or (#plan.options > 0 and not plan.covered and not plan.applied))
        row.assign:SetShown(menu)
        local holder = leader and self:JobHolder(skillLine, roster) or nil
        row.whisper:SetShown(holder ~= nil and holder ~= ns.playerName)
        local status = plan.assigned and statuses[plan.assigned]
        local wait = status and not plan.applied and status.readyAt > now and ns.FormatTime(status.readyAt - now)
        row.wait:SetShown(wait ~= nil and wait ~= false)
        row.wait:SetText(wait and (ORANGE .. wait .. "|r") or "")
        row.setup:SetText(plan.setup)
        row.setup:Show()
        FitPill(row, look, menu)
    end

    -- The top, then the plan and Your group under it.
    local y = TOP_Y
    page.note:SetShown(not inGroup)
    page.tiles:SetShown(inGroup)
    if inGroup then
        page.tiles:ClearAllPoints()
        page.tiles:SetPoint("TOPLEFT", PAD, y)
        FillTiles(page, roster, statuses, camp, placedRows)
        y = y - TILE_HEIGHT - GAP
    else
        page.note:SetText(GREY .. L["Join a party or raid to plan a camp together. Everyone with Happy Camper shows up here, with the camp objects they carry."] .. "|r")
        y = y - ns.Style:TextHeight(page.note, 12) - GAP
    end
    page.presets:SetShown(leader)
    if leader then
        local buttons = 0
        for _, button in ipairs(page.presetButtons) do buttons = buttons + button:GetWidth() + 6 end
        page.presets:SetWidth(ns.Style:TextWidth(page.presets.label) + 2 + buttons)
        page.presets:ClearAllPoints()
        page.presets:SetPoint("TOP", page, "TOP", 0, y)
        y = y - 22 - GAP
    end

    -- Your job, if the leader asked you to place something (not yet there).
    job = nil
    if mine then
        local skillLine = mine.profession.id
        local entry = ns.Widget:ObjectsOf(skillLine)[1]
        local tier = entry and entry.tier or mine.plan.tier or 1
        local left = (ns.charDB.objectReadyAt or 0) - now
        job = { item = entry and entry.item, ready = left <= 0, label = left > 0 and ns.FormatTime(left) or L["Place"] }
        local banner = page.job
        banner.icon:SetTexture(mine.profession.objectIcons and mine.profession.objectIcons[tier] or mine.profession.icon)
        banner.title:SetText(format(L["Place your %s"], ns.ObjectName(skillLine, tier)))
        local asker
        for _, member in ipairs(roster) do
            if member.name ~= ns.playerName and IsLeader(member.name) then asker = member.name end
        end
        if not job.item then
            banner.sub:SetText(ORANGE .. L["It isn't in your bags."] .. "|r")
        else
            banner.sub:SetText(format(L["%s for the group"], mine.profession.buff)
                .. (asker and ("  ·  " .. format(L["%s asked you"], Short(asker))) or ""))
        end
        banner:ClearAllPoints()
        banner:SetPoint("TOPLEFT", PAD, y)
        y = y - BANNER_HEIGHT - GAP
    end
    page.job:SetShown(job ~= nil)

    -- Paladins pick the blessing they keep up, in a group or not.
    local _, myClass = UnitClass("player")
    local isPaladin = myClass == "PALADIN"
    page.blessing:SetShown(isPaladin)
    page.blessingLabel:SetShown(isPaladin)
    local blessed = ns.charDB.blessing and ns.PROFESSION_BY_ID[ns.charDB.blessing]
    if isPaladin and page.blessing.OverrideText then page.blessing:OverrideText(blessed and blessed.conflicts or L["None"]) end

    -- The bottom buttons, then the body between.
    page.refresh:SetEnabled(inGroup)
    local messages = self:PlanMessages(roster)
    local hasPlan = #messages > 0
    -- A plan too long for one message goes in parts: each click posts the next.
    local key = table.concat(messages, "\n")
    if page.planKey ~= key then page.planKey, page.nextPart = key, {} end
    local function Label(text, chatType)
        local i = page.nextPart[chatType] or 1
        return #messages > 1 and format("%s (%d/%d)", text, i, #messages) or text
    end
    page.postGroup:SetText(Label(IsInRaid() and L["Raid"] or L["Party"], "GROUP"))
    page.postSay:SetText(Label(L["Say"], "SAY"))
    local bottom = SizeBottomButtons(page, leader)
    for _, button in ipairs({ page.clear, page.postSay, page.postGroup }) do button:SetShown(leader) end
    page.postSay:SetEnabled(hasPlan)
    page.postGroup:SetEnabled(hasPlan)
    page.body:ClearAllPoints()
    page.body:SetPoint("TOPLEFT", page, "TOPLEFT", 0, y)
    page.body:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", 0, bottom + GAP)

    -- Your group: a row each. Past what fits, the list scrolls, and its rows
    -- leave room for the scroll bar.
    page.benefitsHead:SetText(BenefitsName())
    local list = page.members
    local listHeight = (page:GetHeight() or 0) + y - (bottom + GAP) - page.body.membersTop - LIST_TOP - 4
    local rowWidth = ROW_WIDTH - (#roster * MEMBER_HEIGHT > listHeight and SCROLLBAR_SPACE or 0)
    for i, entry in ipairs(roster) do
        local row = MemberRow(list, i)
        row:SetWidth(rowWidth)
        row.state:SetWidth(rowWidth - OBJECT_X - 16)
        local name = ClassName(entry.name, entry.class)
        if IsLeader(entry.name) then name = name .. " |TInterface\\GroupFrame\\UI-Group-LeaderIcon:12|t" end
        if entry.name == ns.playerName then name = name .. " " .. GREY .. "(" .. L["you"] .. ")|r" end
        row.name:SetText(name)
        row.nameText = Short(entry.name)
        row.objects, row.stateText = {}, nil
        local status = statuses[entry.name]
        -- What they carry: an icon each, best tier.
        local carried = {}
        if status then
            for _, profession in ipairs(ns.PROFESSIONS) do
                local tier = CarriedTier(status, profession.id)
                if tier then
                    carried[#carried + 1] = { profession = profession, tier = tier }
                    row.objects[#row.objects + 1] = ObjectText(profession.id, tier)
                end
            end
        end
        for k, icon in ipairs(row.carried) do
            local object = carried[k]
            icon:SetShown(object ~= nil)
            icon.tier:SetShown(object ~= nil)
            if object then
                icon:SetTexture(object.profession.objectIcons and object.profession.objectIcons[object.tier] or object.profession.icon)
                icon.tier:SetText(object.tier)
            end
        end
        row.more:ClearAllPoints()
        row.more:SetPoint("LEFT", CARRIES_X + math.min(#carried, MAX_CARRIED) * 20, 0)
        if #carried > MAX_CARRIED then
            row.more:SetText(GREY .. "+" .. (#carried - MAX_CARRIED) .. "|r")
        elseif status and #carried == 0 then
            row.more:SetText(GREY .. L["none"] .. "|r")
        else
            row.more:SetText("")
        end
        -- Camp Benefits: time left, none (confirmed), or not known.
        local ends = BenefitsEnd(entry)
        if ends == nil then
            row.benefits:SetText(GREY .. L["not known"] .. "|r")
        elseif not ends then
            row.benefits:SetText(RED .. L["none"] .. "|r")
        else
            local left = ends - now
            row.benefits:SetText((left <= ENDING_SOON and ORANGE or WHITE)
                .. format(L["%d min"], math.max(1, math.floor(left / 60))) .. "|r")
        end
        -- Their camp object: placed, when they can place it again, ready, or none.
        local mark
        if not status then
            row.state:SetText(GREY .. L["no Happy Camper"] .. "|r")
        elseif status.placedSkill and now - status.placedAt < PLACED_SHOWN then
            mark = STATES.placed.mark
            row.state:SetText(GREEN .. format(L["placed %d min ago"], math.max(1, math.floor((now - status.placedAt) / 60))) .. "|r")
        elseif status.readyAt > now then
            mark = STATES.waiting.mark
            row.stateText = format(L["can place in %s"], ns.FormatTime(status.readyAt - now))
            row.state:SetText(ORANGE .. row.stateText .. "|r")
            if row.state:IsTruncated() then row.state:SetText(ORANGE .. ns.FormatTime(status.readyAt - now) .. "|r") end
        elseif status.objectSkill then
            mark = STATES.ready.mark
            row.state:SetText(GREEN .. L["ready"] .. "|r")
        else
            row.state:SetText(GREY .. L["no camp object"] .. "|r")
        end
        row.mark:SetShown(mark ~= nil)
        if mark then row.mark:SetTexture(mark) end
        row:Show()
    end
    for i = #roster + 1, #list.rows do list.rows[i]:Hide() end
    list.child:SetHeight(math.max(1, #roster) * MEMBER_HEIGHT)
    page.membersHeader:SetText(inGroup and format(L["Your group (%d)"], #roster) or L["Your group"])

    self:SyncPlace()
end

-- Members who left the group are forgotten, and so are their assignments (on
-- GROUP_ROSTER_UPDATE, and when the dev tools' pretend members change).
function Group:OnRosterChanged()
    local inGroup = {}
    for _, entry in ipairs(self:Roster()) do inGroup[entry.name] = true end
    for name in pairs(members) do
        if not inGroup[name] then members[name] = nil end
    end
    for name in pairs(blessings) do
        if not inGroup[name] then blessings[name] = nil end
    end
    for name in pairs(lastCovered) do
        if not inGroup[name] then lastCovered[name] = nil end
    end
    for skillLine, name in pairs(assignments) do
        if not inGroup[name] then assignments[skillLine] = nil end
    end
    for _, marked in pairs(claims) do
        for name in pairs(marked) do
            if not inGroup[name] then marked[name] = nil end
        end
    end
    SavePlan() -- the saved plan without them, for the group as it is now
    self:QueueRefresh()
end

-- Your camp recipes are checked again when your profession window lists its
-- recipes, and one you learn is remembered (the event is always about you).
local events = CreateFrame("Frame")
for _, event in ipairs({ "TRADE_SKILL_LIST_UPDATE", "TRADE_SKILL_SHOW", "TRADE_SKILL_DATA_SOURCE_CHANGED", "NEW_RECIPE_LEARNED" }) do
    pcall(events.RegisterEvent, events, event)
end
events:RegisterEvent("GROUP_ROSTER_UPDATE")
events:SetScript("OnEvent", function(_, event, ...)
    if not ns.db or not ns.charDB then return end
    if event == "NEW_RECIPE_LEARNED" then
        local recipeID = ...
        if type(recipeID) == "number" and not ns.IsSecret(recipeID) and CAMP_RECIPES[recipeID] then
            ns.charDB.campRecipes = ns.charDB.campRecipes or {}
            ns.charDB.campRecipes[recipeID] = true
        end
        return
    elseif event ~= "GROUP_ROSTER_UPDATE" then
        Group:RefreshRecipes()
        return
    end
    Group:OnRosterChanged()
end)
