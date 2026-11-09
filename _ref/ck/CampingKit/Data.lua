local addonName, ns = ...

-- Item and spell IDs checked against Wowhead's Forever database (beta, October 2026).
--
-- Slots sit at fixed angles around the tent, in screen degrees:
-- -90 = straight up, 0 = right, 90 = straight down, 180 = left.
-- Item lists run best-first.

-- Camp objects by profession: tier 3, tier 2, tier 1. Each object needs its
-- profession to place, so a character has at most fishing, first aid and two
-- primary professions. skillLine is the profession's ID in the game data;
-- recipes are the tier 1-3 recipe spells (knowing one means you have the profession).
ns.PROFESSIONS = {
    alchemy        = { label = "Alchemy",        skillLine = 171, items = { 279990, 279970, 279956 }, recipes = { 1263078, 1263005, 1230564 }, ranks = { 11611, 3464, 3101, 2259 }, icon = 2259 }, -- Laboratory, Fermenter, Mana Well
    blacksmithing  = { label = "Blacksmithing",  skillLine = 164, items = { 279955, 279988, 279944 }, recipes = { 1263073, 1263041, 1230171 }, ranks = { 9785, 3538, 3100, 2018 }, icon = 2018 }, -- Master Forge, Anvil, Sharpening Wheel
    enchanting     = { label = "Enchanting",     skillLine = 333, items = { 279987, 279985, 279976 }, recipes = { 1263082, 1263056, 1230643 }, ranks = { 13920, 7413, 7412, 7411 }, icon = 7411 }, -- Arcane Forge, Arcane Salvager, Enchanted Lute
    engineering    = { label = "Engineering",    skillLine = 202, items = { 279989, 279949, 279950 }, recipes = { 1263083, 1263034, 1230656 }, ranks = { 12656, 4038, 4037, 4036 }, icon = 4036 }, -- Anarchist's Workbench, Repair Bot, Reagent Bot
    herbalism      = { label = "Herbalism",      skillLine = 182, items = { 279947, 279964, 279962 }, recipes = { 1263070, 1262980, 1229705 }, ranks = {}, icon = 2366, window = "Gardening" }, -- Seed Hybridizer, Greenhouse, Incense Candle
    leatherworking = { label = "Leatherworking", skillLine = 165, items = { 279945, 279941, 279978 }, recipes = { 1263079, 1263031, 1229432 }, ranks = { 10662, 3811, 3104, 2108 }, icon = 2108 }, -- Sewing Machine, Tanning Rack, Camp Tent
    mining         = { label = "Mining",         skillLine = 186, items = { 279952, 279948, 279960 }, recipes = { 1263071, 1262975, 1230161 }, ranks = {}, icon = 2575, window = "Smelting" }, -- Molten Foundry, Rock Garden, Lodestone
    skinning       = { label = "Skinning",       skillLine = 393, items = { 279938, 279969, 279979 }, recipes = { 1262982, 1262985, 1229517 }, ranks = {}, icon = 8613, window = "Tanning" }, -- Trapper's Workbench, Field Guide, Camp Chair
    tailoring      = { label = "Tailoring",      skillLine = 197, items = { 279959, 279943, 279973, 279972 }, recipes = { 1263080, 1263032, 1263425 }, ranks = { 12180, 3910, 3909, 3908 }, icon = 3908 }, -- Loom, Spinning Wheel, Faction Banner (Alliance, Horde)
    fishing        = { label = "Fishing",        skillLine = 356, items = { 279966, 279965, 279967 }, recipes = { 1262998, 1262990, 1229745 }, ranks = {}, icon = 7620 }, -- Fishing Hut, Fishing Rack, Fish Bowl
    firstaid       = { label = "First Aid",      skillLine = 129, items = { 279951, 279940, 279968 }, recipes = { 1263001, 1262996, 1230117 }, ranks = { 10846, 7924, 3274, 3273 }, icon = 3273 }, -- Plague Doctor's Lab, Toxin Study, First Aid Kit
    -- Cooking makes the campfires; its button sits above the campfire slot.
    cooking        = { label = "Cooking",        skillLine = 185, items = {}, recipes = { 1291341, 1283400, 1229737, 1263067, 1262978 }, ranks = { 18260, 3413, 3102, 2550 }, icon = 2550 },
}

-- window: the name of the crafting window it opens, where that differs from
-- the profession (Forever: Herbalism -> Gardening, Mining -> Smelting,
-- Skinning -> Tanning).
-- ranks: the profession's rank spells, highest first. Casting one opens its
-- window. Professions without one (gathering, fishing) open through the
-- trade skill API instead. icon: a spell whose icon stands for the profession.

-- Primary professions, in the order the two profession slots fill when the
-- game can't say which you learned first.
ns.PRIMARY_ORDER = {
    "alchemy", "blacksmithing", "enchanting", "engineering", "herbalism",
    "leatherworking", "mining", "skinning", "tailoring",
}

ns.SLOTS = {
    {
        -- In the middle of the camp-object row, Cooking's button under it.
        key = "campfire", label = "Campfire", angle = 90, row = 3,
        empty = 279981, -- shown greyed when you have none: Basic Campfire Kit
        -- Expert, Journeyman, Basic campfire kits; then Cooking's own camp
        -- objects (Iron Oven, Cookie's Feast), reachable with right-click.
        items = { 279974, 279961, 279981, 279982, 279957 },
        campfire = true,
    },
    {
        -- Sleeping bag: just under the tent, between the Camp Benefits and
        -- Well Fed timers (ns.DIALS), the three curving round the tent's foot.
        -- On a screen edge it sits on the tent's rim, opposite the timers.
        key = "bag", label = "Cozy Sleeping Bag", angle = 90, pos = { 0, -62 },
        onlyIfOwned = true, -- hidden unless it's in your bags
        items = { 211527 },
    },
    -- The five "your pick" slots fan out in an arc over the tent, left to
    -- right. Each takes any food, drink or weapon buff (stone, oil, poison);
    -- right-click opens a grid away from the tent (left, up, up, up, right).
    -- (Keys kept from older versions so saved picks carry over; pick5 is the
    -- one added in the middle.)
    -- radius 66: the same distance as First Aid Kit's slots.
    { key = "food",    label = "Your Pick 1", angle = -165,   radius = 66, pick = true, grid = "left", items = {} },
    { key = "food2",   label = "Your Pick 2", angle = -127.5, radius = 66, pick = true, grid = "up", items = {} },
    { key = "pick5",   label = "Your Pick 3", angle = -90,    radius = 66, pick = true, grid = "up", items = {} },
    { key = "weapon",  label = "Your Pick 4", angle = -52.5,  radius = 66, pick = true, grid = "up", items = {} },
    { key = "weapon2", label = "Your Pick 5", angle = -15,    radius = 66, pick = true, grid = "right", items = {} },
    -- The four camp-object slots sit in a straight row under the tent;
    -- row = position from the left (1-5); the campfire sits in the middle (3).
    { key = "fishing",  label = "Fishing",        row = 1, profession = "fishing" },
    { key = "firstaid", label = "First Aid",      row = 2, profession = "firstaid" },
    { key = "prof1",    label = "Profession 1",   row = 4, primary = 1 },
    { key = "prof2",    label = "Profession 2",   row = 5, primary = 2 },
    -- Small round button on the tent's rim, out only near a campfire.
    { key = "sit", label = "Sit", sit = true, pos = { 0, -27 } },
}

-- Settings and key bindings list slots in this order.
ns.MENU_ORDER = { "campfire", "food", "food2", "pick5", "weapon", "weapon2", "fishing", "firstaid", "prof1", "prof2", "bag", "sit" }

-- Camping auras on the player (Wowhead's Forever database).
ns.AURA = {
    nearby    = 1283391, -- Campfire Nearby: you're inside a camp
    welcoming = 1289723, -- Welcoming Campfire: the rest countdown
    benefits  = 1229741, -- Camp Benefits: the combined buffs from camp objects
    boosted   = 1229451, -- Boosted Rest: Camp Tent rested XP (debuff, blocks it for an hour)
    wellRested = 429959, -- Well-Rested: Cozy Sleeping Bag, up to 3 stacks
    violet    = 1328375, -- Violet Flames: close to a fire turned purple (Pouch of Violet Dust), camp benefits last 2 hours
}

-- Timer icons hugging the tent (offsets from the tent centre). timeDx nudges
-- the time text sideways, away from the tent. always = shown
-- greyed out while you don't have the buff (glowing if glowSetting is on).
ns.DIALS = {
    -- Under the tent either side of the sleeping bag, each with its time below it.
    { key = "benefits", label = "Camp Benefits", x = -30, y = -44, timeSide = "BELOW", always = true, glowSetting = "benefitsGlow", showSetting = "showBenefits" },
    { key = "wellFed",  label = "Well Fed",      x = 30,  y = -44, timeSide = "BELOW", always = true, glowSetting = "wellFedGlow", showSetting = "showWellFed" },
}

-- Well Fed comes from many foods, each with its own spell, so it's found by
-- name: the client's own (localized) name for this Well Fed spell.
ns.WELL_FED_SPELL = 19705

-- Class buffs each profession's camp objects don't stack with (the object's
-- tooltip says "mutually exclusive with ..."): with one of these on you, that
-- object adds nothing to Camp Benefits. The group and greater versions count
-- too. One spell ID per buff (rank 1); the client turns each into its own
-- name for the buff, and buffs are matched on that, so every rank counts in
-- any game language.
ns.CAMP_CONFLICTS = {
    alchemy    = { 19742, 25894 }, -- Blessing of Wisdom, Greater Blessing of Wisdom
    enchanting = { 1126, 21849 },  -- Mark of the Wild, Gift of the Wild
    herbalism  = { 1459, 23028 },  -- Arcane Intellect, Arcane Brilliance
    mining     = { 19740, 25782 }, -- Blessing of Might, Greater Blessing of Might
    tailoring  = { 14752, 27681 }, -- Divine Spirit, Prayer of Spirit
    firstaid   = { 1243, 21562 },  -- Power Word: Fortitude, Prayer of Fortitude
    fishing    = { 20217, 25898 }, -- Blessing of Kings, Greater Blessing of Kings
    blacksmithing = { 8075, 8076 }, -- Strength of Earth Totem, and its buff (original-game ID, unchecked on Forever)
    skinning   = { 17007, 24932, 24858, 24907 }, -- Leader of the Pack (talent, buff), Moonkin Form, Moonkin Aura (original-game IDs, unchecked on Forever)
}

-- Which of those to name when saying what an object doesn't stack with
-- (default: the first).
ns.CAMP_COMPETES_SHOW = {
    skinning = { 17007, 24907 }, -- "Leader of the Pack or Moonkin Aura"
}

-- Weapon buffs offered by the weapon slot (language-neutral by ID; the game's
-- Item Enhancement category is checked too, to catch anything newer).
ns.WEAPON_BUFFS = {
    2862, 2863, 2871, 7964, 12404, 18262, 23122,       -- sharpening stones: Rough .. Dense, Elemental, Consecrated
    3239, 3240, 3241, 7965, 12643,                     -- weightstones: Rough .. Dense
    20744, 20746, 20750, 20749, 23123,                 -- wizard oils: Minor, Lesser, Wizard, Brilliant, Blessed
    20745, 20747, 20748,                               -- mana oils: Minor, Lesser, Brilliant
    3824, 3829,                                        -- Shadow Oil, Frost Oil
    6947, 6949, 6950, 8926, 8927, 8928,                -- Instant Poison I-VI
    2892, 2893, 8984, 8985, 20844,                     -- Deadly Poison I-V
    3775, 3776,                                        -- Crippling Poison I-II
    5237, 6951, 9186,                                  -- Mind-numbing Poison I-III
    10918, 10920, 10921, 10922,                        -- Wound Poison I-IV
}

-- What each weapon buff goes on: "sharp" (blades), "blunt", or "poison";
-- anything else (oils, newer items) goes on any melee weapon.
ns.WEAPON_BUFF_KIND = {}
for _, id in ipairs({ 2862, 2863, 2871, 7964, 12404, 18262, 23122 }) do ns.WEAPON_BUFF_KIND[id] = "sharp" end
for _, id in ipairs({ 3239, 3240, 3241, 7965, 12643 }) do ns.WEAPON_BUFF_KIND[id] = "blunt" end
for _, id in ipairs({ 6947, 6949, 6950, 8926, 8927, 8928, 2892, 2893, 8984, 8985, 20844,
                      3775, 3776, 5237, 6951, 9186, 10918, 10920, 10921, 10922 }) do
    ns.WEAPON_BUFF_KIND[id] = "poison"
end

-- Campfires by tier: the spells whose (localized) names the fire shows when
-- you mouse over it, the kit item that builds it, and how many camp objects
-- it takes. Basic Campfire has two spell IDs in the data; either name counts.
ns.CAMPFIRES = {
    { tier = 1, spells = { 1229737, 818 }, item = 279981, slots = 3 },  -- Basic Campfire
    { tier = 2, spells = { 1283400 }, item = 279961, slots = 5 },       -- Journeyman Campfire
    { tier = 3, spells = { 1291341 }, item = 279974, slots = 10 },      -- Expert Campfire
}

-- Cooking's own camp objects (not campfires): spell, kit item.
ns.COOKING_OBJECTS = {
    { spell = 1263067, item = 279957, effect = "Cooking station" }, -- Iron Oven
    { spell = 1262978, item = 279982, effect = "Stamina when eaten" }, -- Cookie's Feast
}

-- Camp objects whose name in the world isn't their item or spell name (the
-- Camp Chair just says "Chair"), and the client gives addons nothing else
-- about the object. Their world name is learned instead: after one is placed
-- by you or your group, the next object at the camp you mouse over that the
-- kit doesn't know is taken to be it, and remembered for that game language.
-- Value: the object's spell.
ns.CAMP_WORLD_NAMED = { [1229517] = true } -- Camp Chair
-- World names already known, by game language, so they work before any are learned.
ns.CAMP_WORLD_NAMES = {
    enUS = { ["Chair"] = 1229517 },
    enGB = { ["Chair"] = 1229517 },
}

-- The error a camp object gets when the camp has no room left, as the name of
-- the client's own (localized) string: "No room for more features at this camp."
ns.CAMP_FULL_ERROR = "SPELL_FAILED_CUSTOM_ERROR_6004"

-- What each profession's tier 1 camp object does for you, shown in the camp
-- list. Tier 2 and 3 objects are workstations.
ns.CAMP_EFFECTS = {
    alchemy = "Mana regeneration", blacksmithing = "Strength", enchanting = "Stats and resistances",
    engineering = "Vendor and bag cleanup", firstaid = "Stamina", fishing = "All stats",
    herbalism = "Intellect", leatherworking = "Rested experience", mining = "Attack power",
    skinning = "Critical strike", tailoring = "Spirit",
}

-- How big each tier 1 object's bonus is at your level (the buff follows the
-- level of whoever sits at the fire). From the objects' spell tooltips on
-- Wowhead's Forever database (beta, October 2026). Each part is a format and
-- { from level, amount } steps; a part with no step at your level is left out.
-- Objects not listed here show their CAMP_EFFECTS text instead.
ns.CAMP_SCALING = {
    firstaid      = { { "+%d Stamina", { 1, 3 }, { 12, 8 }, { 24, 21 }, { 36, 34 }, { 48, 45 }, { 60, 56 } } },     -- First Aid Kit 1307244
    herbalism     = { { "+%d Intellect", { 1, 2 }, { 14, 6 }, { 28, 12 }, { 42, 18 }, { 56, 25 } } },               -- Incense Candle 1307251
    mining        = { { "+%d melee attack power", { 1, 12 }, { 12, 20 }, { 22, 32 }, { 32, 49 }, { 42, 67 }, { 52, 90 } } }, -- Lodestone 1307254
    alchemy       = { { "+%d mana every 5 sec", { 1, 10 }, { 24, 15 }, { 34, 20 }, { 44, 24 }, { 54, 29 } } },     -- Mana Well 1307259
    blacksmithing = { { "+%d Strength", { 1, 6 }, { 24, 11 }, { 38, 20 }, { 52, 34 } } },                           -- Sharpening Wheel 1307392
    tailoring     = { { "+%d Spirit", { 1, 14 }, { 40, 19 }, { 50, 27 }, { 60, 32 } } },                             -- Faction Banner 1307239/1307240
    enchanting    = {                                                                                                -- Enchanted Lute 1307234
        { "+%d armor", { 1, 28 }, { 10, 71 }, { 20, 114 }, { 30, 163 }, { 40, 211 }, { 50, 260 }, { 60, 308 } },
        { "+%d all stats", { 10, 2 }, { 20, 4 }, { 30, 7 }, { 40, 9 }, { 50, 12 }, { 60, 13 } },
        -- Wowhead garbles this part of the tooltip; read as 30-39: 6 ... 60: 22.
        { "+%d all resistances", { 30, 6 }, { 40, 12 }, { 50, 16 }, { 60, 22 } },
    },
    fishing       = { { "+8% all stats" } },               -- Fish Bowl 1307245: the same at every level
    skinning      = { { "+2% critical strike chance" } },  -- Camp Chair 1307229: the same at every level
}

-- Tier 1 objects whose bonus comes through Camp Benefits (sit by the fire).
ns.CAMP_BUFF_PROFS = {
    alchemy = true, blacksmithing = true, enchanting = true, firstaid = true, fishing = true,
    herbalism = true, mining = true, skinning = true, tailoring = true,
}

ns.CAMP_TENT_ITEM = 279978   -- its icon is the tent button

-- Spells whose (localized) names mark an item as food or drink: Food, Drink.
ns.FOOD_SPELLS = { 433, 430 }

ns.MEDIA = "Interface\\AddOns\\" .. addonName .. "\\media\\"
