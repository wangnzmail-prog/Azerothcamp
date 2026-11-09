-- Happy Camper. Copyright (c) 2026 Torridon. All rights reserved; see LICENSE.
local _, ns = ...

-- The Handbook's recipe data (Handbook.lua): made by tools/make_handbook_data.py,
-- don't edit it by hand. By recipe spell ID: the item it makes, the skill it
-- needs, where it's learned ("trainer", "quest", "both", or recipeItem: the
-- item that teaches it), its reagents ({ item ID, count }), tools (not used
-- up), how many one craft makes, useSkill: the skill needed to place it,
-- where that's more, and foundIn: who drops a recipe item and where
-- ({ area ID, NPC ID }, named in areas and npcs for when the game can't).
ns.HANDBOOK_DATA = {
    from = "Wowhead's Forever database (game data 1.60.1), read 2026-10-12; tools as their usual items (Arclight Spanner 6219, Runed Truesilver Rod 11145, Flint and Tinder 4471); blueprint drop places from Wowhead's loot data, area IDs from wago.tools (2026-10-13)",
    areas = { [36] = "Alterac Mountains", [209] = "Shadowfang Keep", [491] = "Razorfen Kraul", [718] = "Wailing Caverns", [719] = "Blackfathom Deeps", [796] = "Scarlet Monastery", [1581] = "The Deadmines", [16611] = "Ruins of Lordaeron", [17732] = "Excavation Site: Wetlands" },
    npcs = { [643] = "Sneed", [645] = "Cookie", [1763] = "Gilnid", [3671] = "Lady Anacondra", [3673] = "Lord Serpentis", [3886] = "Razorclaw the Butcher", [3974] = "Houndmaster Loksey", [4278] = "Commander Springvale", [4421] = "Charlga Razorflank", [6243] = "Gelihast", [246017] = "Unstable Sentinel", [246020] = "Shade of the Archmage", [250657] = "Rath'mael", [260325] = "Shadetooth", [260326] = "Relic Guardian" },
    recipes = {
        [1229432] = { item = 279978, skill = 20, source = "both", makes = 2, reagents = { { 2318, 5 } } }, -- Leatherworking: Camp Tent
        [1229504] = { item = 279972, skill = 20, source = "both", makes = 2, reagents = { { 2996, 1 }, { 2320, 1 } } }, -- Tailoring: Faction Banner
        [1229517] = { item = 279979, skill = 20, source = "both", makes = 2, reagents = { { 2318, 3 }, { 4470, 2 } } }, -- Skinning: Camp Chair
        [1229705] = { item = 279962, skill = 20, source = "both", makes = 2, reagents = { { 2447, 1 }, { 765, 1 } } }, -- Herbalism: Incense Candle
        [1229737] = { item = 279981, skill = 1, source = "trainer", reagents = { { 4470, 1 } }, tools = { 4471 } }, -- Cooking: campfire kit 1
        [1229745] = { item = 279967, skill = 20, source = "both", makes = 2, reagents = { { 6291, 1 }, { 3371, 1 } } }, -- Fishing: Fish Bowl
        [1230117] = { item = 279968, skill = 20, source = "both", makes = 2, reagents = { { 1251, 3 }, { 159, 1 } } }, -- First Aid: First Aid Kit
        [1230161] = { item = 279960, skill = 20, source = "both", makes = 2, reagents = { { 2835, 1 }, { 2840, 1 } } }, -- Mining: Lodestone
        [1230171] = { item = 279944, skill = 20, source = "trainer", makes = 2, reagents = { { 2835, 1 }, { 2840, 1 } } }, -- Blacksmithing: Sharpening Wheel
        [1230564] = { item = 279956, skill = 20, source = "both", makes = 2, reagents = { { 2447, 1 }, { 3371, 1 } } }, -- Alchemy: Mana Well
        [1230643] = { item = 279976, skill = 20, source = "both", makes = 2, reagents = { { 4470, 1 }, { 10940, 1 } } }, -- Enchanting: Enchanted Lute
        [1230656] = { item = 279950, skill = 20, source = "both", makes = 2, reagents = { { 4359, 1 }, { 4361, 1 } } }, -- Engineering: Reagent Bot
        [1262975] = { item = 279948, skill = 140, recipeItem = 273097, makes = 2, reagents = { { 2838, 2 }, { 2772, 1 }, { 2842, 1 } }, foundIn = { { 17732, 260326 } } }, -- Mining: Rock Garden
        [1262978] = { item = 279957, skill = 140, recipeItem = 273102, makes = 2, reagents = { { 12037, 2 }, { 12204, 1 }, { 3713, 1 } }, foundIn = { { 1581, 645 } } }, -- Cooking: Cookie's Feast
        [1262980] = { item = 279964, skill = 140, recipeItem = 273106, makes = 2, reagents = { { 4470, 2 }, { 8836, 1 }, { 8831, 1 } }, foundIn = { { 17732, 260325 } } }, -- Herbalism: Greenhouse
        [1262982] = { item = 279938, skill = 300, recipeItem = 273109, makes = 2, reagents = { { 4470, 2 }, { 4234, 4 }, { 3575, 1 } }, foundIn = { { 796, 3974 } } }, -- Skinning: Trapper's Workbench
        [1262985] = { item = 279969, skill = 140, recipeItem = 273098, makes = 2, reagents = { { 2319, 3 }, { 5784, 2 }, { 2321, 1 } }, foundIn = { { 718, 3671 } } }, -- Skinning: Field Guide
        [1262990] = { item = 279965, skill = 140, recipeItem = 273141, makes = 2, reagents = { { 4470, 2 }, { 8925, 1 }, { 8365, 2 } }, foundIn = { { 719, 6243 } } }, -- Fishing: Fishing Rack
        [1262996] = { item = 279940, skill = 140, recipeItem = 273105, makes = 2, reagents = { { 6452, 1 }, { 8544, 2 }, { 4470, 2 } }, foundIn = { { 209, 4278 } } }, -- First Aid: Toxin Study
        [1262998] = { item = 279966, skill = 300, recipeItem = 273119, makes = 2, reagents = { { 4470, 5 }, { 14048, 2 }, { 273295, 1 } }, foundIn = {} }, -- Fishing: Fishing Hut
        [1263001] = { item = 279951, skill = 300, recipeItem = 273118, makes = 2, reagents = { { 4470, 2 }, { 6453, 2 }, { 14530, 5 } }, foundIn = {} }, -- First Aid: Plague Doctor's Laboratory
        [1263005] = { item = 279970, skill = 140, recipeItem = 273085, makes = 2, reagents = { { 3372, 1 }, { 3356, 1 }, { 2452, 1 } }, foundIn = { { 16611, 250657 } } }, -- Alchemy: Fermenter
        [1263031] = { item = 279941, skill = 140, recipeItem = 273096, makes = 2, reagents = { { 2319, 5 }, { 2321, 3 }, { 4470, 2 } }, foundIn = { { 209, 3886 } } }, -- Leatherworking: Tanning Rack
        [1263032] = { item = 279943, skill = 140, recipeItem = 273099, makes = 2, reagents = { { 4470, 2 }, { 4305, 5 }, { 2321, 3 } }, foundIn = { { 36, 246017 } } }, -- Tailoring: Spinning Wheel
        [1263034] = { item = 279949, skill = 140, recipeItem = 273092, makes = 2, reagents = { { 4375, 2 }, { 4371, 1 }, { 4234, 1 } }, tools = { 6219 }, foundIn = { { 1581, 643 } } }, -- Engineering: Repair Bot
        [1263041] = { item = 279988, skill = 140, recipeItem = 273086, makes = 2, reagents = { { 2841, 5 }, { 3478, 2 }, { 2319, 2 } }, foundIn = { { 1581, 1763 } } }, -- Blacksmithing: Anvil
        [1263056] = { item = 279985, skill = 140, recipeItem = 273103, makes = 2, reagents = { { 11137, 2 }, { 11174, 1 } }, tools = { 11145 }, foundIn = { { 491, 4421 }, { 36, 246020 }, { 16611, 250657 } } }, -- Enchanting: Arcane Salvager
        [1263067] = { item = 279982, skill = 300, recipeItem = 273115, makes = 2, reagents = { { 10284, 10 }, { 159, 5 }, { 3713, 4 } }, foundIn = {} }, -- Cooking: Iron Oven
        [1263070] = { item = 279947, skill = 300, recipeItem = 273120, makes = 2, reagents = { { 13465, 4 }, { 8925, 1 }, { 14047, 2 } }, foundIn = {} }, -- Herbalism: Seed Hybridizer
        [1263071] = { item = 279952, skill = 300, recipeItem = 273122, makes = 2, reagents = { { 12359, 5 }, { 12365, 2 }, { 6037, 1 } }, foundIn = {} }, -- Mining: Molten Foundry
        [1263073] = { item = 279955, skill = 300, recipeItem = 273113, makes = 2, reagents = { { 273127, 1 }, { 12359, 5 }, { 8170, 2 } }, foundIn = {} }, -- Blacksmithing: Master Forge
        [1263078] = { item = 279990, skill = 300, recipeItem = 273112, makes = 2, reagents = { { 273125, 1 }, { 8925, 1 }, { 13463, 2 } }, foundIn = {} }, -- Alchemy: Alchemy Laboratory
        [1263079] = { item = 279945, skill = 300, recipeItem = 273121, makes = 2, reagents = { { 273130, 1 }, { 8170, 5 }, { 14341, 1 } }, foundIn = {} }, -- Leatherworking: Sewing Machine
        [1263080] = { item = 279959, skill = 300, recipeItem = 273124, makes = 2, reagents = { { 273131, 1 }, { 14048, 4 }, { 4470, 4 } }, foundIn = {} }, -- Tailoring: Loom
        [1263082] = { item = 279987, skill = 300, recipeItem = 273116, makes = 2, reagents = { { 273128, 1 }, { 14344, 2 }, { 16203, 4 } }, foundIn = {} }, -- Enchanting: Arcane Forge
        [1263083] = { item = 279989, skill = 300, recipeItem = 273117, makes = 2, reagents = { { 273129, 1 }, { 15994, 2 } }, tools = { 6219 }, foundIn = {} }, -- Engineering: Anarchist's Workbench
        [1263425] = { item = 279973, skill = 20, source = "both", makes = 2, reagents = { { 2996, 1 }, { 2320, 1 } } }, -- Tailoring: Faction Banner
        [1283400] = { item = 279961, skill = 90, recipeItem = 273087, makes = 2, useSkill = 140, reagents = { { 11291, 1 } }, tools = { 4471 }, foundIn = { { 718, 3673 } } }, -- Cooking: campfire kit 2
        [1291341] = { item = 279974, skill = 200, recipeItem = 273101, makes = 2, useSkill = 220, reagents = { { 272941, 1 } }, tools = { 4471 }, foundIn = {} }, -- Cooking: campfire kit 3
    },
}
