-- Happy Camper. Copyright (c) 2026 Torridon. All rights reserved; see LICENSE.
local _, ns = ...
local L = ns.L

-- How many entries a table has.
function ns.Count(t)
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    return n
end

-- A flood limit: Allow(key, cooldown) says whether something from key may go
-- ahead (and counts it if so): at most once per cooldown seconds for each key,
-- and at most perMinute a minute for all keys together.
local FLOOD_KEEP = 3600 -- seconds: no cooldown is longer, so older keys are let go

function ns.FloodLimit(perMinute)
    local last, recent = {}, {} -- [key] = time; times in the last minute
    local added, tidiedAt = 0, 0
    return function(key, cooldown)
        local now = GetTime()
        if last[key] and now - last[key] < cooldown then return false end
        -- Now and then, keys from long ago go (a busy realm has many senders).
        if added >= 200 and now - tidiedAt > 60 then
            for k, at in pairs(last) do
                if now - at > FLOOD_KEEP then last[k] = nil end
            end
            added, tidiedAt = 0, now
        end
        for i = #recent, 1, -1 do
            if now - recent[i] >= 60 then table.remove(recent, i) end
        end
        if #recent >= perMinute then return false end
        recent[#recent + 1] = now
        if not last[key] then added = added + 1 end
        last[key] = now
        return true
    end
end

-- Camp spells and auras by ID, from Forever's spell data (build 1.60.1.70009,
-- looked up on wago.tools). IDs are the same in every client language, so these
-- are checked first; the English names below are only a fallback for spells
-- missing here (a later game build, say). /hc add can teach more IDs.
ns.CAMP_SPELLS = {
    -- Placing a Basic, Journeyman or Expert Campfire, and the objects it holds.
    fire = { [1307227] = 3, [1307252] = 5, [1307237] = 10 },
    rest = { [1229739] = true, [1289723] = true }, -- Welcoming Campfire
    near = { [1283391] = true },                   -- Campfire Nearby
    buff = { [1229741] = true },                   -- Camp Benefits
}

-- Blizzard has no camping API yet, so camp spells and auras missing from
-- CAMP_SPELLS are recognised by name (or by spell ID, if taught with /hc add).
-- Check them in-game with the dev tools' /hc learn. Names are lowercase and matched as
-- whole words.
ns.PATTERNS = {
    -- Spells that light a campfire (Basic, Journeyman and Expert Campfire).
    fire = { "campfire" },

    -- Spells that place a profession campsite object: filled in from
    -- ns.PROFESSIONS below.
    object = {},

    -- Auras that only mean a campfire is close by ("Campfire Nearby", seen in
    -- the beta). Being near isn't resting, so these are otherwise ignored.
    near = { "campfire nearby", "campsite nearby", "camp nearby" },

    -- The aura you get while sitting at a camp ("Welcoming Campfire", seen in
    -- the beta). It counts down 60 seconds, then the camp buffs are applied.
    rest = { "welcoming campfire" },

    -- Timed auras that are campsite rewards. In the beta, every object's stat
    -- boost comes in one "Camp Benefits" buff; its tooltip lists the stats.
    buff = { "camp benefits", "campsite", "camping" },
}

-- Professions and what their campsite objects give, keyed by skill line ID
-- (the classic IDs, which Forever's GetProfessionInfo returns).
--   buff      short label for the benefit, shown on search chips
--   detail    what a buff that's the same at every level gives
--   steps     the size of a buff that grows with your level: { from level,
--             amount[, amount, amount] }, the last step your level reaches
--             applies (ns.BuffStep). The Enchanted Lute adds all stats from
--             level 10 and all resistances from 30, so its steps have 1 to 3.
--   conflicts the class buff it doesn't stack with; conflictSpells that buff's
--             spell IDs, every rank and the group version (from Forever's spell data)
--   objects   the tier 1, 2 and 3 objects (skill 20, 140, 300), by tier: a
--             profession may lack a tier (Cooking has no tier 1). Higher tiers give
--             the same buff (its size goes with your level, not the tier) and add a
--             workspace or service (OBJECT_EXTRAS). Tier 2 and 3 also need a recipe.
--   recipes   the recipe (crafting) spell for each tier's object (a list where
--             there are two, like the Alliance and Horde Faction Banners: see
--             ns.RecipeIDs)
--   objectSpells  the spell that places each of them (a list where there are
--             two, like the Alliance and Horde Faction Banners)
--   icon      the profession's icon; objectIcons each object's item icon, from
--             Wowhead's Forever item database (both under Interface\Icons)
--   person    used in chat messages
--   window    the crafting window's name, where it isn't the profession's: in
--             Forever the gathering professions craft in Gardening, Smelting
--             and Tanning windows
-- Values are from beta data collected by classicwowforever.com and
-- wowhandbook.com (24-26 September 2026) and may change before launch. Camp
-- buff sizes by level are from each tier 1 object's spell description
-- (wago.tools, Forever beta build 1.60.1.70170, 2 October 2026); every tier
-- gives the same buff.
ns.PROFESSIONS = {
    { id = 171, name = "Alchemy", person = "an alchemist", icon = "Trade_Alchemy",
      buff = "Mana regen", conflicts = "Blessing of Wisdom", conflictSpells = { 19742, 19850, 19852, 19853, 19854, 25290, 25894, 25918 },
      steps = { { 1, 10 }, { 24, 15 }, { 34, 20 }, { 44, 24 }, { 54, 29 } }, -- mana every 5 sec
      objects = { "Mana Well", "Fermenter", "Alchemy Laboratory" },
      objectSpells = { 1307259, 1307242, 1307172 },
      recipes = { 1230564, 1263005, 1263078 },
      objectIcons = { "spell_arcane_manatap", "inv_alchemy_90_cauldron", "10prof_portabletable_alchemy01" } },
    { id = 164, name = "Blacksmithing", person = "a blacksmith", icon = "Trade_BlackSmithing",
      buff = "Strength", conflicts = "Strength of Earth Totem", conflictSpells = { 8076, 8162, 8163, 10441, 25362 },
      steps = { { 1, 6 }, { 24, 11 }, { 38, 20 }, { 52, 34 } },
      objects = { "Sharpening Wheel", "Anvil", "Master Forge" },
      objectSpells = { 1307392, 1307175, 1307261 },
      recipes = { 1230171, 1263041, 1263073 },
      objectIcons = { "inv_stone_grindingstone_01", "inv_blacksmith_anvil", "inv_mace_1h_blacksmithing_b_01_black" } },
    { id = 333, name = "Enchanting", person = "an enchanter", icon = "Trade_Engraving",
      buff = "Armor & stats",
      steps = { { 1, 28 }, { 10, 71, 2 }, { 20, 114, 4 }, { 30, 163, 7, 6 }, { 40, 211, 9, 12 }, { 50, 260, 12, 16 }, { 60, 308, 13, 22 } }, -- armor, all stats, all resistances
      conflicts = "Mark of the Wild", conflictSpells = { 1126, 5232, 5234, 5286, 5287, 6756, 8907, 8908, 9884, 9885, 16878, 24752, 364163, 1291335, 1310503, 21849, 21850 }, objects = { "Enchanted Lute", "Arcane Salvager", "Arcane Forge" },
      objectSpells = { 1307234, 1307223, 1307176 },
      recipes = { 1230643, 1263056, 1263082 },
      objectIcons = { "inv_10_enchanting2_magicswirl_bronze", "inv_eng_bottledelements", "inv_enchanting_modifiedcraftingreagent_indigo" } },
    { id = 202, name = "Engineering", person = "an engineer", icon = "Trade_Engineering",
      buff = "Vendor", detail = "A reagent vendor; repairs from the Repair Bot on",
      objects = { "Reagent Bot", "Repair Bot", "Anarchist's Workbench" },
      objectSpells = { 1307266, 1307385, 1307174 },
      recipes = { 1230656, 1263034, 1263083 },
      objectIcons = { "inv_misc_enggizmos_13", "inv_robotpet", "inv_10_specialization_professionbook_engineering_color1" } },
    { id = 182, name = "Herbalism", person = "an herbalist", icon = "Trade_Herbalism", window = "Gardening",
      buff = "Intellect", conflicts = "Arcane Intellect", conflictSpells = { 1459, 1460, 1461, 10156, 10157, 13326, 16876, 364161, 23028 },
      steps = { { 1, 2 }, { 14, 6 }, { 28, 12 }, { 42, 18 }, { 56, 25 } },
      objects = { "Incense Candle", "Greenhouse", "Seed Hybridizer" },
      objectSpells = { 1307251, 1307248, 1307387 },
      recipes = { 1229705, 1262980, 1263070 },
      objectIcons = { "inv_misc_candle_02", "inv_misc_herb_08", "inv_farm_herbseed" } },
    { id = 165, name = "Leatherworking", person = "a leatherworker", icon = "Trade_LeatherWorking",
      buff = "Rested XP", detail = "Tops up rested XP to 5% of a level",
      objects = { "Camp Tent", "Tanning Rack", "Sewing Machine" },
      objectSpells = { 1307230, 1307395, 1307391 },
      recipes = { 1229432, 1263031, 1263079 },
      objectIcons = { "inv_misc_leatherscrap_01", "inv_10_skinning_leather_rarehide_color1", "inv_tailoring_modifiedcraftingreagent_orange" } },
    { id = 186, name = "Mining", person = "a miner", icon = "Trade_Mining", window = "Smelting",
      buff = "Attack power", conflicts = "Blessing of Might", conflictSpells = { 19740, 19834, 19835, 19836, 19837, 19838, 25291, 25782, 25916 },
      steps = { { 1, 12 }, { 12, 20 }, { 22, 32 }, { 32, 49 }, { 42, 67 }, { 52, 90 } },
      objects = { "Lodestone", "Rock Garden", "Molten Foundry" },
      objectSpells = { 1307254, 1307386, 1307264 },
      recipes = { 1230161, 1262975, 1263071 },
      objectIcons = { "inv_misc_rune_06", "inv_misc_powder_iron", "inv_blacksmithingalloys_red" } },
    { id = 393, name = "Skinning", person = "a skinner", icon = "INV_Misc_Pelt_Wolf_01", window = "Tanning",
      buff = "Crit", detail = "+2% critical strike with attacks and spells", conflicts = "Moonkin Aura", conflictSpells = { 24907 },
      objects = { "Camp Chair", "Field Guide", "Trapper's Workbench" },
      objectSpells = { 1307229, 1307243, 1307397 },
      recipes = { 1229517, 1262985, 1262982 },
      objectIcons = { "inv_crate_01", "inv_misc_book_03", "inv_misc_kobysstools_knifetrap_color3" } },
    { id = 197, name = "Tailoring", person = "a tailor", icon = "Trade_Tailoring",
      buff = "Spirit", conflicts = "Divine Spirit", conflictSpells = { 14752, 14818, 14819, 16875, 27841, 27681 },
      steps = { { 1, 14 }, { 40, 19 }, { 50, 27 }, { 60, 32 } },
      objects = { "Faction Banner", "Spinning Wheel", "Loom" },
      objectSpells = { { 1307239, 1307240 }, 1307393, 1307255 },
      recipes = { { 1263425, 1229504 }, 1263032, 1263080 }, -- the Alliance and Horde banners
      objectIcons = { "inv_banner_03", "10prof_table_tailoring01", "inv_tailoring_80_tidespraylinen" } },
    { id = 129, name = "First Aid", person = "a field medic", icon = "Spell_Holy_SealOfSacrifice",
      buff = "Stamina", conflicts = "Power Word: Fortitude", conflictSpells = { 1243, 1244, 1245, 2791, 10937, 10938, 10939, 10940, 13864, 23947, 23948, 21562, 21564, 450086 },
      steps = { { 1, 3 }, { 12, 8 }, { 24, 21 }, { 36, 34 }, { 48, 45 }, { 60, 56 } },
      objects = { "First Aid Kit", "Toxin Study", "Plague Doctor's Laboratory" },
      objectSpells = { 1307244, 1307396, 1307265 },
      recipes = { 1230117, 1262996, 1263001 },
      objectIcons = { "inv_misc_bandage_11", "inv_misc_potiona3", "inv_10_alchemy_incenseholder_color1" } },
    { id = 356, name = "Fishing", person = "an angler", icon = "Trade_Fishing",
      buff = "All stats", detail = "+8% to all attributes", conflicts = "Blessing of Kings", conflictSpells = { 20217, 1213408, 25898 },
      objects = { "Fish Bowl", "Fishing Rack", "Fishing Hut" },
      objectSpells = { 1307245, 1307247, 1307246 },
      recipes = { 1229745, 1262990, 1262998 },
      objectIcons = { "inv_magicalfishpet", "inv_misc_2h_draenorfishingpole_a_01", "inv_fishingchair" } },
    -- Cooking lights the fire itself; upgraded campfires hold more objects.
    -- Its two camp objects share the hour's cooldown but give no camp buff:
    -- Cookie's Feast (skill 140, tier 2) and the Iron Oven (skill 300, its best).
    { id = 185, name = "Cooking", person = "a cook", icon = "INV_Misc_Food_15",
      buff = "Campfire", detail = "Journeyman and Expert Campfires hold 5 or 10 objects instead of 3",
      notSearchable = true, objects = { [2] = "Cookie's Feast", [3] = "Iron Oven" },
      objectSpells = { [2] = 1307257, [3] = 1307226 },
      recipes = { [2] = 1262978, [3] = 1263067 },
      objectIcons = { [2] = "inv_cooking_80_majorfeast", [3] = "achievement_cooking_masteroftheoven" } },
}

-- The skill a recipe needs, by tier: a learned recipe only counts once your
-- skill reaches it (tier 2 and 3 recipes come from blueprints that need 140
-- and 300; from wago, Forever build 1.60.1).
ns.RECIPE_SKILL = { 1, 140, 300 }
-- Cooking's campfire kits by tier (Basic, Journeyman, Expert): their recipes,
-- and the Cooking skill each needs.
ns.KIT_RECIPES = { 1229737, 1283400, 1291341 }
ns.KIT_SKILL = { 1, 90, 200 }

-- A tier's recipes as a list (some tiers have two), from a recipes table
-- (a profession's recipes, or ns.KIT_RECIPES); empty if it has none.
function ns.RecipeIDs(recipes, tier)
    local ids = recipes and recipes[tier]
    if type(ids) == "table" then return ids end
    return { ids }
end

-- Whether a profession skill reaches a tier's recipe (kit: a campfire kit's).
function ns.ReachesTier(rank, tier, kit)
    local needed = (kit and ns.KIT_SKILL or ns.RECIPE_SKILL)[tier]
    return needed ~= nil and (rank or 0) >= needed
end

ns.PROFESSION_BY_ID = {}
local objectProfession = {} -- [lowercase object name] = skill line ID
local objectDisplayName = {} -- [lowercase object name] = "Incense Candle"
local objectTier = {} -- [lowercase object name] = 1, 2 or 3
local objectBySpell = {} -- [placement spell ID] = lowercase (English) object name
for _, profession in ipairs(ns.PROFESSIONS) do
    ns.PROFESSION_BY_ID[profession.id] = profession
    -- Full texture paths; the buff's own icon is its tier 1 object's.
    profession.icon = "Interface\\Icons\\" .. profession.icon
    profession.objectIcons = profession.objectIcons or {}
    for tier, icon in pairs(profession.objectIcons) do
        profession.objectIcons[tier] = "Interface\\Icons\\" .. icon
    end
    profession.buffIcon = not profession.notSearchable and profession.objectIcons[1] or profession.icon
    for tier, object in pairs(profession.objects) do
        local key = object:lower()
        objectProfession[key] = profession.id
        objectDisplayName[key] = object
        objectTier[key] = tier
        table.insert(ns.PATTERNS.object, key)
        local spells = (profession.objectSpells or {})[tier]
        for _, spellID in ipairs(type(spells) == "table" and spells or { spells }) do objectBySpell[spellID] = key end
    end
end

-- The objects' names in this client's language (what Camp Benefits tooltips
-- show), from their placement spells: [lowercase local name] = English key.
local localNames, unnamed = nil, {}
local function LocalObjectKey(name)
    -- Built on first use, and again if a spell whose name wasn't loaded then has
    -- one now (only those are asked again: every unit tooltip looks names up).
    local stale = not localNames
    if not stale and not localNames[name] then
        for _, spellID in ipairs(unnamed) do
            local localName = C_Spell.GetSpellName(spellID)
            if type(localName) == "string" and localName ~= "" then
                stale = true
                break
            end
        end
    end
    if stale then
        localNames, unnamed = {}, {}
        for spellID, key in pairs(objectBySpell) do
            local localName = C_Spell.GetSpellName(spellID)
            if type(localName) == "string" and localName ~= "" then
                localNames[localName:lower()] = key
            else
                unnamed[#unnamed + 1] = spellID
            end
        end
    end
    return localNames[name]
end

-- The game's ID of each placed camp object, { skillLine, tier }: what its
-- placement spell (objectSpells) summons, a world object or, for the bots and
-- some others, a creature (wago.tools SpellEffect, wow_classic_beta, 5 October
-- 2026). Its GUID carries this ID, so a town's Anvil, named like
-- Blacksmithing's, is told apart from a camp's (Tooltips.lua).
ns.CAMP_OBJECT_IDS = {}
for skillLine, tiers in pairs({
    [171] = { { 651948 }, { 612120 }, { 612139 } },                     -- Alchemy
    [164] = { { 651950 }, { 612125 }, { 612136 } },                     -- Blacksmithing
    [333] = { { 651952 }, { 612130 }, { 612143 } },                     -- Enchanting
    [202] = { { 242498 }, { 254695 }, { 612145 } },                     -- Engineering (bots: creatures)
    [182] = { { 651955 }, { 612087, 260078 }, { 260105 } },             -- Herbalism (Greenhouse is both)
    [165] = { { 528996 }, { 612122 }, { 612140 } },                     -- Leatherworking
    [186] = { { 573385, 651956 }, { 654285, 259224 }, { 612134 } },     -- Mining (Rock Garden is both)
    [393] = { { 612275 }, { 612088 }, { 612082 } },                     -- Skinning
    [197] = { { 612351, 612350 }, { 612123 }, { 612142 } },             -- Tailoring (a banner for each faction)
    [129] = { { 651953 }, { 612091 }, { 612110 } },                     -- First Aid
    [356] = { { 651954 }, { 612090 }, { 612092 } },                     -- Fishing
    [185] = { [2] = { 612073 }, [3] = { 612132 } },                     -- Cooking
}) do
    for tier, ids in pairs(tiers) do
        for _, id in ipairs(ids) do ns.CAMP_OBJECT_IDS[id] = { skillLine, tier } end
    end
end

-- What each object adds besides its buff, by profession and tier (from
-- Wowhead's Forever camping guide, 22 September 2026). Engineering and
-- Leatherworking give no stat, so everything they give is here.
ns.OBJECT_EXTRAS = {
    [171] = { [2] = { "reagent making" }, [3] = { "an alchemy lab" } },
    [164] = { [2] = { "an anvil" }, [3] = { "a forge" } },
    [333] = { [2] = { "better disenchanting" }, [3] = { "an arcane forge" } },
    [202] = { { "a reagent vendor" }, { "a reagent vendor", "repairs" }, { "an engineering workbench" } },
    [182] = { [2] = { "an herb garden" }, [3] = { "a seed hybridizer" } },
    [165] = { { "rested XP" }, { "rested XP", "reagent making" }, { "rested XP", "a sewing machine" } },
    [186] = { [2] = { "a mining node" }, [3] = { "a molten foundry" } },
    [393] = { [2] = { "Track Beasts" }, [3] = { "a trap" } },
    [197] = { [2] = { "reagent making" }, [3] = { "a loom" } },
    [129] = { [2] = { "healing potions", "anti-venom" }, [3] = { "healing potions", "poultices" } },
    [356] = { [2] = { "uncommon fishing", "fishing lures" }, [3] = { "rare fishing", "fishing lures" } },
    [185] = { [2] = { "a Stamina feast" }, [3] = { "an iron oven" } }, -- Cooking has no tier 1
}

-- Which camp buffs are stats (the rest are services, listed as extras).
ns.STAT_BUFF = { [171] = true, [164] = true, [333] = true, [182] = true, [186] = true,
    [393] = true, [197] = true, [129] = true, [356] = true }

ns.OnLocale(function(L)
    for _, tiers in pairs(ns.OBJECT_EXTRAS) do
        for _, extras in pairs(tiers) do
            for i, extra in ipairs(extras) do extras[i] = L[extra] end
        end
    end
end)

-- The professions' text in the language in use (Locale.lua). Their English
-- object names stay: they're keys for matching and for the network.
ns.OnLocale(function() ns.LocalizeFields(ns.PROFESSIONS, "name", "person", "buff", "detail", "conflicts", "window") end)

-- Camp buff sizes. Everyone gets a camp buff at their own level, so a size is
-- only shown to the person it's for: chat and messages other players read name
-- the buff alone. These are the words for each growing buff's step, by how
-- many amounts it has (the Enchanted Lute's have 1 to 3).
local AMOUNT_FORMATS = {}
ns.OnLocale(function(L)
    AMOUNT_FORMATS = {
        [171] = { L["%d mana every 5 sec"] },
        [164] = { L["+%d Strength"] },
        [333] = { L["+%d Armor"], L["+%d Armor and +%d all stats"], L["+%d Armor, +%d all stats and +%d all resistances"] },
        [182] = { L["+%d Intellect"] },
        [186] = { L["+%d melee attack power"] },
        [197] = { L["+%d Spirit"] },
        [129] = { L["+%d Stamina"] },
    }
end)

-- A unit's level, or nil when it can't be read: secret, or 0 or less (a group
-- member who's offline, or too far above you to see).
function ns.KnownLevel(unit)
    local level = UnitLevel(unit)
    if ns.IsSecret(level) or type(level) ~= "number" or level < 1 then return nil end
    return level
end

-- A camp buff's step at a level ({ from level, amount[, amount, amount] }), or
-- nil for a buff that's the same at every level. A level that can't be used
-- (unknown, secret) counts as the top one.
function ns.BuffStep(profession, level)
    local steps = profession and profession.steps
    if not steps then return nil end
    if ns.IsSecret(level) or type(level) ~= "number" or level < 1 then level = math.huge end
    local found = steps[1]
    for _, step in ipairs(steps) do
        if step[1] <= level then found = step end
    end
    return found
end

-- What a camp buff gives at a level ("+11 Strength"); for a buff that's the
-- same at every level, its detail.
function ns.BuffText(profession, level)
    local step = ns.BuffStep(profession, level)
    local formats = step and AMOUNT_FORMATS[profession.id]
    if not formats then return profession.detail end
    return format(formats[#step - 1], unpack(step, 2))
end

-- The level a growing camp buff reaches its top size at; nil for a buff
-- that's the same at every level.
function ns.BuffTopLevel(profession)
    local steps = profession and profession.steps
    return steps and steps[#steps][1]
end

-- Adds a camp buff's size to a tooltip of yours: what you'd get at your level,
-- then in grey the most it gives and the level that comes at; one line at the
-- top size, or for a buff that's the same at every level. Tooltips are built
-- each time they show, so a level-up shows at once.
function ns.AddBuffSize(tooltip, profession)
    local topLevel, level = ns.BuffTopLevel(profession), ns.KnownLevel("player")
    if not topLevel or (level and level >= topLevel) then
        tooltip:AddLine(ns.BuffText(profession, level), 1, 1, 1, true)
        return
    end
    if level then tooltip:AddLine(format(L["%s at your level"], ns.BuffText(profession, level)), 1, 1, 1, true) end
    tooltip:AddLine(format(L["%s from level %d"], ns.BuffText(profession, topLevel), topLevel), 0.7, 0.7, 0.7, true)
end

-- Class buffs that give a camp buff's stat (they don't stack with it), by the
-- camp buff's skill line. The Camp Builder (Requests.lua) and the Group tab
-- (Group.lua) both go by this.
--   class     the class that gives it
--   talent    not every player of the class has it: only those who know it give it
--   party     it reaches only the giver's party (a totem, an aura)
--   blessing  a paladin's: a paladin gives each player one blessing, so only one
--             of Might, Wisdom and Kings
ns.CLASS_BUFFS = {
    [171] = { class = "PALADIN", blessing = true },                -- Blessing of Wisdom
    [164] = { class = "SHAMAN", party = true },                    -- Strength of Earth Totem
    [333] = { class = "DRUID" },                                   -- Mark of the Wild
    [182] = { class = "MAGE" },                                    -- Arcane Intellect
    [186] = { class = "PALADIN", blessing = true },                -- Blessing of Might
    [393] = { class = "DRUID", talent = true, party = true },      -- Moonkin Aura
    [197] = { class = "PRIEST", talent = true },                   -- Divine Spirit
    [129] = { class = "PRIEST" },                                  -- Power Word: Fortitude
    [356] = { class = "PALADIN", blessing = true, talent = true }, -- Blessing of Kings
}

-- Those classes as the Camp Builder names them: "Blessing of Might (paladin)",
-- and in a request's chat message, "Seeking a paladin...".
ns.CLASS_NAMES = {
    PALADIN = { name = "paladin", person = "a paladin" },
    PRIEST = { name = "priest", person = "a priest" },
    DRUID = { name = "druid", person = "a druid" },
    MAGE = { name = "mage", person = "a mage" },
    SHAMAN = { name = "shaman", person = "a shaman" },
}
ns.OnLocale(function() ns.LocalizeFields(ns.CLASS_NAMES, "name", "person") end)

-- Class buffs by spell ID: [spellID] = the profession whose camp buff they cover.
local conflictBySpell = {}
for _, profession in ipairs(ns.PROFESSIONS) do
    for _, spellID in ipairs(profession.conflictSpells or {}) do conflictBySpell[spellID] = profession.id end
end

-- Camp buffs a class buff on you already gives: { [skill line] = that buff's
-- name }. They don't stack, so you'd gain nothing from those camp objects.
-- Empty when the option is off, or while buff data can't be read (in combat).
function ns.CoveredCampBuffs()
    if not ns.db.classBuffCheck then return {} end
    return (ns.UnitCoveredBuffs("player"))
end

-- The same for anyone in your group (the Group tab), whatever the option says.
-- Also returns true if some of their auras couldn't be read (secret), so the
-- Group tab can keep what it read last.
function ns.UnitCoveredBuffs(unit)
    local covered, unreadable = {}, false
    for i = 1, 40 do
        local aura, secret = ns.AuraByIndex(unit, i, "HELPFUL")
        if secret then
            unreadable = true
            break
        end
        if not aura then break end
        if ns.IsSecretAura(aura) then
            unreadable = true
        else
            local skillLine = conflictBySpell[aura.spellId]
            if skillLine then covered[skillLine] = aura.name end
        end
    end
    return covered, unreadable
end

-- The object a spell places, by ID (any language): its English key, or nil.
function ns.ObjectForSpell(spellID)
    return objectBySpell[spellID]
end

-- x, y from a map position. Most map APIs return a vector object, but some
-- (e.g. C_Map.GetUserWaypoint's position) return a plain { x, y } table.
function ns.XY(position)
    if not position then return nil end
    if position.GetXY then return position:GetXY() end
    return position.x, position.y
end

-- True if name contains the phrase as whole words ("Loom" but not "Gloom").
local phrasePattern = {} -- [phrase] = its pattern, made once
function ns.ContainsPhrase(name, phrase)
    local pattern = phrasePattern[phrase]
    if not pattern then
        local escaped = phrase:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0")
        pattern = "%f[%w]" .. escaped .. "%f[%W]"
        phrasePattern[phrase] = pattern
    end
    return name:find(pattern) ~= nil
end

-- Identifies a campsite object from any spell that places it. Returns:
--   key          the same for every spell placing the same object, e.g. both
--                "Incense Candle" and "Place Incense Candle" give "incense candle"
--   name         the object's display name, e.g. "Incense Candle"
--   skillLine    its profession, or nil if unknown
function ns.ObjectInfo(spellID)
    local spellName = C_Spell.GetSpellName(spellID)
    local known = objectBySpell[spellID]
    if known then return known, spellName or objectDisplayName[known], objectProfession[known] end
    local lower = spellName and spellName:lower() or ""
    for object, skillLine in pairs(objectProfession) do
        if ns.ContainsPhrase(lower, object) then
            return object, objectDisplayName[object], skillLine
        end
    end

    local skillLine
    local info = C_TradeSkillUI.GetProfessionInfoByRecipeID(spellID)
    if info then
        if ns.PROFESSION_BY_ID[info.professionID] then
            skillLine = info.professionID
        elseif ns.PROFESSION_BY_ID[info.parentProfessionID or 0] then
            skillLine = info.parentProfessionID
        end
    end
    if spellName then return lower, spellName, skillLine end
    return "spell:" .. spellID, "Object " .. spellID, skillLine
end

-- True if a spell places one of the known campsite objects. Object claims from
-- other players are only accepted for these, so no other spell's name can end
-- up in your camp's equipment (or your Say and General message).
function ns.IsCampObjectSpell(spellID)
    if objectBySpell[spellID] then return true end
    local name = C_Spell.GetSpellName(spellID)
    if type(name) ~= "string" then return false end
    name = name:lower()
    for object in pairs(objectProfession) do
        if ns.ContainsPhrase(name, object) then return true end
    end
    return false
end

-- An object by its exact name, in English or this client's language (as the
-- Camp Benefits tooltip shows it): key, display name, skill line, tier, icon;
-- nil if it isn't a known object.
function ns.ObjectByName(name)
    local key = type(name) == "string" and name:lower():match("^%s*(.-)%s*$")
    if key and not objectProfession[key] then key = LocalObjectKey(key) end
    if key and objectProfession[key] then
        local skillLine, tier = objectProfession[key], objectTier[key]
        return key, objectDisplayName[key], skillLine, tier, ns.PROFESSION_BY_ID[skillLine].objectIcons[tier]
    end
end

-- A profession's object of a tier (1-3), named in the client's language (its
-- placement spell's name), or in English if that isn't loaded.
function ns.ObjectName(skillLine, tier)
    local profession = ns.PROFESSION_BY_ID[skillLine]
    local english = profession and profession.objects[tier]
    local spells = profession and (profession.objectSpells or {})[tier]
    local spellID = type(spells) == "table" and spells[1] or spells
    local name = spellID and C_Spell.GetSpellName(spellID)
    return type(name) == "string" and name ~= "" and name or english
end

-- Which profession a campsite object spell belongs to, or nil if unknown.
function ns.ProfessionForObject(spellID)
    local _, _, skillLine = ns.ObjectInfo(spellID)
    return skillLine
end
