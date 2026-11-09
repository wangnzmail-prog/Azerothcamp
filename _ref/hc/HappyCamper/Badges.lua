-- Happy Camper. Copyright (c) 2026 Torridon. All rights reserved; see LICENSE.
local _, ns = ...
local L = ns.L

-- Badges: challenge coins in bronze, then silver, then gold. A zone badge for
-- each outdoor zone, earned by camping there, a profession badge for each
-- profession with camp objects, earned by placing them, a class badge for each
-- class, earned by camping on that class as it levels, and collection badges
-- for earning the others (All Gold, every badge in gold, is the finale), and
-- keepsakes (Beta Camper). They're your
-- account's: every character adds to the same badges. Kept in the saved
-- variables and never sent to anyone. Badges whose art isn't drawn yet are
-- hidden (Badges:Hidden): the class badges, landmarks not in LANDMARK_ART, and
-- Beta Camper.

local Badges = {}
ns.Badges = Badges

-- Every outdoor zone in Forever (the beta's UiMap table): its map ID and its
-- art's file name, Media\Badges\<art>_<tier>.tga (1 bronze, 2 silver, 3 gold).
-- Map IDs are the same on every client language; names (the zones' and each
-- region's, from its map) come from the game.
Badges.REGIONS = {
    { map = 1415, zones = { -- Eastern Kingdoms
        { 1416, "alterac_mountains" }, { 1417, "arathi_highlands" }, { 1418, "badlands" },
        { 1419, "blasted_lands" }, { 1428, "burning_steppes" }, { 1430, "deadwind_pass" },
        { 1426, "dun_morogh" }, { 1431, "duskwood" }, { 1423, "eastern_plaguelands" },
        { 1429, "elwynn_forest" }, { 1424, "hillsbrad_foothills" }, { 1432, "loch_modan" },
        { 1433, "redridge_mountains" }, { 2548, "riverglades" }, { 1427, "searing_gorge" },
        { 1421, "silverpine_forest" }, { 1434, "stranglethorn_vale" }, { 1435, "swamp_of_sorrows" },
        { 1425, "the_hinterlands" }, { 1420, "tirisfal_glades" }, { 1422, "western_plaguelands" },
        { 1436, "westfall" }, { 1437, "wetlands" },
    } },
    { map = 1414, zones = { -- Kalimdor
        { 1440, "ashenvale" }, { 1447, "azshara" }, { 1439, "darkshore" },
        { 1443, "desolace" }, { 1411, "durotar" }, { 1445, "dustwallow_marsh" },
        { 1448, "felwood" }, { 1444, "feralas" }, { 1450, "moonglade" },
        { 2482, "mount_hyjal" }, { 1412, "mulgore" }, { 2652, "shendralas" },
        { 1451, "silithus" }, { 1442, "stonetalon_mountains" }, { 1446, "tanaris" },
        { 1438, "teldrassil" }, { 1413, "the_barrens" }, { 1441, "thousand_needles" },
        { 1449, "ungoro_crater" }, { 1452, "winterspring" },
    } },
    { map = 2521, zones = { -- Zephras Isle
        { 2521, "zephras_isle" },
    } },
}

-- Other maps that are one of those zones (Camps.lua: Zephras Isle's second map).
local ALIASES = ns.ZONE_ALIASES

-- Each profession with camp objects (skill line ID) and its art's file name,
-- Media\Badges\profession_<art>_<tier>.tga.
local PROFESSION_ART = {
    [171] = "alchemy", [164] = "blacksmithing", [333] = "enchanting", [202] = "engineering",
    [182] = "herbalism", [165] = "leatherworking", [186] = "mining", [393] = "skinning",
    [197] = "tailoring", [129] = "first_aid", [356] = "fishing", [185] = "cooking",
}
-- The profession coins are drawn (false would show each profession's icon instead).
Badges.PROFESSION_ART_READY = true

-- The three tiers: names and colours.
Badges.TIERS = {
    { name = "Bronze", color = { 0.80, 0.50, 0.25 } },
    { name = "Silver", color = { 0.78, 0.80, 0.85 } },
    { name = "Gold", color = { 1.00, 0.82, 0.25 } },
}

-- What each tier asks.
-- Zone badges, all in the zone:
--   rests: rest a full minute at a fire;
--   camps: rest at camps, each fire once, whoever lit it.
Badges.ZONE_RULES = { { rests = 1 }, { camps = 15 }, { camps = 50 } }
-- Profession badges, placing that profession's camp objects (anywhere):
--   placed: any of them; better: tier 2 or 3; top: its top tier (tier 3, or
--   Cooking's Iron Oven, tier 2).
Badges.PROFESSION_RULES = { { placed = 1 }, { placed = 25, better = 5 }, { placed = 100, top = 20 } }
-- Class badges, resting at a fire (anywhere) as that class:
--   level: the highest level you've rested at as it.
Badges.CLASS_RULES = { { level = 15 }, { level = 40 }, { level = 60 } }

-- Cooking's campfires count too: Basic (tier 1), Journeyman (2) and Expert (3);
-- its Cookie's Feast is tier 2 and its Iron Oven tier 4, its best. For gold,
-- tier 3 or better counts as its top tier, as for every profession.
local COOKING = 185
local KIT_SPELLS = { 1307227, 1307252, 1307237 } -- Basic, Journeyman, Expert Campfire
local COOKING_OBJECT_TIERS = { ["cookie's feast"] = 2, ["iron oven"] = 4 }
local TOP_TIER = 3

-- The order a tier's needs are listed in.
local NEED_ORDER = { "rests", "camps", "placed", "better", "top", "level", "count", "allBronze", "allSilver", "allGold", "found" }
-- How each reads: needing one, and needing several (with your progress).
local NEED_TEXT = {
    rests = { "Rest at a fire here", "Rest at a fire here (%d/%d)" },
    camps = { "Rest at a camp here", "Rest at different camps here (%d/%d)" },
    placed = { "Place one of its camp objects", "Place its camp objects (%d/%d)" },
    better = { "Place a tier 2 or better one", "Place tier 2 or better ones (%d/%d)" },
    top = { "Place its top-tier object", "Place its top-tier object (%d/%d)" },
    -- The class's name, then the level.
    level = { "Rest at a fire as a %s at level %d or higher", "Rest at a fire as a %s at level %d or higher" },
    count ={ "Earn a badge", "Earn badges (%d/%d)" },
    allBronze = { "Earn every badge in bronze or better", "Earn every badge in bronze or better (%d/%d)" },
    allSilver = { "Earn every badge in silver or better", "Earn every badge in silver or better (%d/%d)" },
    allGold = { "Earn every badge in gold", "Earn every badge in gold (%d/%d)" },
    found = { "Rest at a fire in this place to discover it", "Rest at a fire in this place to discover it" },
}

-- Every badge: { kind, id, key (its saved progress), art, rules, ... }.
local all, byZone, byProfession = {}, {}, {}
for _, region in ipairs(Badges.REGIONS) do
    for _, zone in ipairs(region.zones) do
        zone.kind, zone.id, zone.art, zone.region = "zone", zone[1], zone[2], region
        zone.key, zone.rules = zone.id, Badges.ZONE_RULES
        byZone[zone.id] = zone
        all[#all + 1] = zone
    end
end
Badges.PROFESSIONS = {}
for _, profession in ipairs(ns.PROFESSIONS) do
    local art = PROFESSION_ART[profession.id]
    if art and profession.objects then
        local badge = { kind = "profession", id = profession.id, key = "p" .. profession.id,
            art = "profession_" .. art, rules = Badges.PROFESSION_RULES, profession = profession }
        byProfession[profession.id] = badge
        Badges.PROFESSIONS[#Badges.PROFESSIONS + 1] = badge
        all[#all + 1] = badge
    end
end

-- The badges collections count: every zone and profession badge.
local countable = {}
for i, badge in ipairs(all) do countable[i] = badge end

-- Collection badges, for earning the others. Collector goes bronze, silver,
-- gold by how many badges you have; each "All" badge is one coin in its metal,
-- for every badge in that metal or better. All Gold, the finale, is drawn a
-- little bigger than every other coin and comes with a joke coin, Touch Grass.
-- Zephras Isle (a starting zone players can't go back to) only needs bronze for
-- them.
local ALL_KEY = { "allBronze", "allSilver", "allGold" }
local BRONZE_ONLY = { [2521] = true } -- Zephras Isle
Badges.COLLECTIONS = {
    { id = "collector", art = "collection_collector", rules = { { count = 10 }, { count = 25 }, { count = 50 } } },
    { id = "all_bronze", art = "collection_all_bronze", metal = 1 },
    { id = "all_silver", art = "collection_all_silver", metal = 2 },
    { id = "all_gold", art = "collection_all_gold", metal = 3, special = true, scale = 1.2 },
    { id = "touch_grass", art = "collection_touch_grass", metal = 3, secret = true }, -- an easter egg
}
-- The collection coins are drawn (false would show the emblem in the metal instead).
Badges.COLLECTION_ART_READY = true
for _, badge in ipairs(Badges.COLLECTIONS) do
    badge.kind, badge.key = "collection", "c:" .. badge.id
    if badge.metal then
        badge.rules = { [badge.metal] = { [ALL_KEY[badge.metal]] = #countable } }
    end
    all[#all + 1] = badge
end

-- Landmarks: one-time badges in verdigris copper for camping at a special
-- place: rest at a fire inside the area. They're secret: the Landmarks section
-- only appears once one is found (one shown: see LANDMARK_ART), and then shows
-- the others as outlines.
-- They don't count toward the collections. Each is the game's area (an ID,
-- so any client language; the name comes from the game), with any other IDs
-- the same place has across zone borders. Art: landmark_<art>_1.
Badges.LANDMARK_STYLE = { name = "Landmark", color = { 0.42, 0.72, 0.62 } }
-- The landmarks drawn so far. Only these ship: one not listed is hidden (not
-- shown, said or counted), but resting there still finds it, quietly, so once
-- its coin is drawn and listed here it simply appears, already found (no
-- pop-up then). The dev tools' previews show the rest as the emblem in
-- verdigris, marked as hidden.
Badges.LANDMARK_ART = {
    brewnall_village = true, forests_edge = true, frostsaber_rock = true,
    furlbrows_pumpkin_farm = true, grim_batol = true, gurubashi_arena = true,
    moonwell = true, ravenholdt_manor = true, red_rocks = true,
}
Badges.LANDMARKS = {
    { "forests_edge", 60 },               -- Elwynn Forest
    { "furlbrows_pumpkin_farm", 109 },    -- Westfall
    { "gurubashi_arena", 1741 },          -- Stranglethorn Vale
    { "twilight_grove", 856 },            -- Duskwood
    { "brewnall_village", 137 },          -- Dun Morogh
    { "grim_batol", 1037 },               -- Wetlands
    { "dalaran", 279, 17707 },            -- Alterac Mountains, and its ruins
    { "shadraalor", 353 },                -- The Hinterlands
    { "thoradins_wall", 293, 1057, 1857 },-- Hillsbrad and Arathi
    { "corins_crossing", 2264 },          -- Eastern Plaguelands
    { "plaguewood", 2277 },               -- Eastern Plaguelands
    { "agamand_mills", 157 },             -- Tirisfal Glades
    { "the_decrepit_ferry", 237 },        -- Silverpine Forest
    { "southfury_river", 377, 814, 815, 878, 879 }, -- Durotar, the Barrens, Azshara, Ashenvale
    { "the_stagnant_oasis", 388 },        -- The Barrens
    { "red_rocks", 225 },                 -- Mulgore
    { "the_charred_vale", 465 },          -- Stonetalon Mountains
    { "xavian", 429 },                    -- Ashenvale
    { "moonwell", 425 },                  -- Ashenvale
    { "frostsaber_rock", 2241 },          -- Winterspring
    { "the_masters_glaive", 449 },        -- Darkshore
    { "the_twin_colossals", 1119 },       -- Feralas
    { "pyrewood_village", 204 },          -- Silverpine Forest
    { "alcaz_island", 2079 },             -- Dustwallow Marsh
    { "jaguero_isle", 297 },              -- Stranglethorn Vale
    { "ravenholdt_manor", 3486 },         -- Alterac Mountains
    { "uthers_tomb", 196 },               -- Western Plaguelands
    { "darrowshire", 2262 },              -- Eastern Plaguelands
}
for _, badge in ipairs(Badges.LANDMARKS) do
    badge.kind, badge.id, badge.art = "landmark", badge[1], "landmark_" .. badge[1]
    badge.key, badge.metal, badge.style = "l:" .. badge[1], 1, Badges.LANDMARK_STYLE
    badge.areas = {}
    for i = 2, #badge do badge.areas[badge[i]] = true end
    badge.areaID = badge[2]
    badge.rules = { [1] = { found = 1 } }
    all[#all + 1] = badge
end

-- Classes: a badge for camping on each class. Rest at a fire as that class at
-- level 15 for bronze, 40 for silver and 60 for gold (a rest at 60 earns gold
-- at once). Whichever of your characters is that class earns it. Like the
-- landmarks, they don't count toward the collections: Summit would need a
-- level 60 of every class. Each is { art, the game's class token (UnitClass's
-- second value), class ID }; names come from the game. Art: class_<art>_<tier>.
-- The art script (art/badges/split_badges.py) reads the art names from this
-- table, up to its closing brace: one class per line, nothing else in it.
Badges.CLASSES = {
    { "warrior", "WARRIOR", 1 },
    { "paladin", "PALADIN", 2 },
    { "hunter", "HUNTER", 3 },
    { "rogue", "ROGUE", 4 },
    { "priest", "PRIEST", 5 },
    { "shaman", "SHAMAN", 7 },
    { "mage", "MAGE", 8 },
    { "warlock", "WARLOCK", 9 },
    { "druid", "DRUID", 11 },
}
-- The class coins aren't drawn yet, so the class badges are hidden until they
-- are: no Classes section, no chat line, pop-up or sound when one is earned,
-- no "Class badges: N" on the tab and no note about them on the collections.
-- Resting still records them, quietly (tiers and dates in ns.db.badges, kept
-- in backups). To switch them on, put the 27 coins (class_<art>_1-3) in
-- Media\Badges and set this to true: the tab, pop-ups, count and note come
-- back (and the guide's Badges step names them), and the tiers already earned
-- simply appear (no pop-ups for them). Then describe them again in the
-- README, the CurseForge description and the patch notes. Until then the dev
-- tools' previews show each class's own icon, tinted in the metal, marked as
-- hidden.
Badges.CLASS_ART_READY = false
local byClass = {}
for _, badge in ipairs(Badges.CLASSES) do
    badge.kind, badge.id, badge.token, badge.classID = "class", badge[1], badge[2], badge[3]
    badge.art, badge.key, badge.rules = "class_" .. badge[1], "class:" .. badge[1], Badges.CLASS_RULES
    byClass[badge.token] = badge
    all[#all + 1] = badge
end

-- Keepsakes: one-time badges for something that can't be done again. Beta
-- Camper thanks everyone who camped in the beta: it's given once on the live
-- game, with the answer to the launch question (keep the beta progress or
-- start fresh: Season.lua), or there from a beta backup code that shows
-- camping. Like a landmark it's one coin in a colour of its own, and it
-- doesn't count toward the collections or the badge count. It's shown only
-- once earned (a secret), in a Keepsakes section of its own. Art: <art>_1.
Badges.KEEPSAKE_STYLE = { name = "Keepsake", color = { 1.00, 0.68, 0.45 } } -- the colour of first light
Badges.KEEPSAKES = {
    { id = "beta_camper", art = "beta_camper" },
}
-- The Beta Camper coin isn't drawn yet, so it's hidden until it is, as the
-- class badges are: it's still given (saved, and kept in backups), but
-- quietly, with no thank-you line, pop-up or Keepsakes section. To switch it
-- on, put its coin (beta_camper_1) in Media\Badges and set this to true:
-- players who have it then simply see it. Until then the dev tools' previews
-- show the emblem in its colour, marked as hidden.
Badges.BETA_ART_READY = false
for _, badge in ipairs(Badges.KEEPSAKES) do
    badge.kind, badge.key, badge.metal, badge.style = "keepsake", "k:" .. badge.id, 1, Badges.KEEPSAKE_STYLE
    badge.rules, badge.secret = { [1] = { given = 1 } }, true
    all[#all + 1] = badge
end
Badges.BETA_CAMPER = Badges.KEEPSAKES[1]

ns.OnLocale(function(L)
    ns.LocalizeFields(Badges.TIERS, "name")
    Badges.LANDMARK_STYLE.name = L["Landmark"]
    for _, text in pairs(NEED_TEXT) do text[1], text[2] = L[text[1]], L[text[2]] end
    -- Explorer, then the road ahead: Trailblazer, Pathfinder, Summit.
    local names = { L["Explorer"], L["Trailblazer"], L["Pathfinder"], L["Summit"], L["Touch Grass"] }
    for i, badge in ipairs(Badges.COLLECTIONS) do badge.name = names[i] end
    Badges.COLLECTIONS[5].description = L["All this camping. Maybe go outside."]
    Badges.KEEPSAKE_STYLE.name = L["Keepsake"]
    Badges.BETA_CAMPER.name = L["Beta Camper"]
    Badges.BETA_CAMPER.description = L["For camping in the beta. Thank you!"]
end)

-- Data ------------------------------------------------------------------------------

function Badges:Zone(mapID)
    return byZone[ALIASES[mapID] or mapID]
end

function Badges:Profession(skillLine)
    return byProfession[skillLine]
end

-- A class's badge by the game's class token ("WARRIOR"), or nil.
function Badges:Class(token)
    return byClass[token]
end

-- Your character's class badge, or nil (its class can't be read right now).
function Badges:ClassHere()
    local _, token = UnitClass("player")
    if ns.IsSecret(token) or type(token) ~= "string" then return nil end
    return byClass[token]
end

-- The badge zone you're in, or nil (cities, dungeons, unknown maps). A city
-- earns nothing for the zone around it.
function Badges:ZoneHere()
    local mapID = C_Map.GetBestMapForUnit("player")
    if not mapID or ns.IsSecret(mapID) then return nil end
    return self:Zone(ns.ZoneOf(mapID, true))
end

-- A class's name in the game's language: its own list, else its class info,
-- else in English (the art name, capitalised).
local function ClassName(badge)
    local name = LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[badge.token]
    if type(name) ~= "string" or name == "" then
        local info = C_CreatureInfo and C_CreatureInfo.GetClassInfo and C_CreatureInfo.GetClassInfo(badge.classID)
        name = info and info.className
    end
    if type(name) ~= "string" or name == "" then name = badge.id:sub(1, 1):upper() .. badge.id:sub(2) end
    return name
end

-- A badge's name in the game's language: its zone, profession or class.
function Badges:Name(badge)
    if badge.kind == "profession" then return badge.profession.name end
    if badge.kind == "class" then return ClassName(badge) end
    if badge.kind == "landmark" then return C_Map.GetAreaInfo(badge.areaID) or badge.id end
    if badge.kind == "collection" or badge.kind == "keepsake" then return badge.name or badge.id end
    local info = C_Map.GetMapInfo(badge.id)
    return info and info.name or badge.art
end
Badges.ZoneName = Badges.Name

-- Puts badges in alphabetical order by their names ({ [badge] = name }), the
-- game's language's own order where the game has it: comparing the bytes
-- would put German's Ödland after Westfall.
function Badges:SortByName(badges, names)
    local compare = C_Intl and C_Intl.CompareStrings
    local strength = Enum and Enum.CollationStrength and Enum.CollationStrength.Tertiary or 2
    table.sort(badges, function(a, b)
        local x, y = names[a], names[b]
        local order = compare and compare(x, y, strength)
        if order and order ~= 0 then return order < 0 end
        return x < y
    end)
end

-- A badge's progress: its counts, tier and earned = { [tier] = time }.
function Badges:Progress(badge)
    local saved = ns.db.badges
    if not saved then
        saved = {}
        ns.db.badges = saved
    end
    local progress = saved[badge.key]
    if not progress then
        progress = { tier = 0, earned = {} }
        for _, needs in pairs(badge.rules) do
            for key in pairs(needs) do progress[key] = 0 end
        end
        saved[badge.key] = progress
    end
    return progress
end

-- The tier earned (0 = none yet).
function Badges:Tier(badge)
    local progress = ns.db.badges and ns.db.badges[badge.key]
    return progress and progress.tier or 0
end

-- The tier a badge earns next, or nil when it's done. An "All" badge has just
-- its own metal.
function Badges:NextTier(badge, tier)
    if badge.metal then return tier == 0 and badge.metal or nil end
    return tier < #self.TIERS and tier + 1 or nil
end

function Badges:Meets(badge, progress, tier)
    for key, count in pairs(badge.rules[tier]) do
        if (progress[key] or 0) < count then return false end
    end
    return true
end

-- The lines under a tier's name: what it asks, with your progress.
function Badges:NeedLines(badge, progress, tier)
    local lines = {}
    local needs = badge.rules[tier]
    for _, key in ipairs(NEED_ORDER) do
        local count = needs[key]
        if count then
            local have = math.min(progress[key] or 0, count)
            local text
            if key == "level" then -- names the class: "as a Warrior at level 40"
                text = format(NEED_TEXT.level[1], self:Name(badge), count)
            else
                text = count == 1 and NEED_TEXT[key][1] or format(NEED_TEXT[key][2], have, count)
            end
            lines[#lines + 1] = { text = text, done = have >= count }
        end
    end
    return lines
end

-- A class icon for a class coin not drawn yet: the game's round class icon
-- (an atlas) where this client has one, else the class's picture on the
-- older sheet of class circles.
local CLASS_CIRCLES = "Interface\\TargetingFrame\\UI-Classes-Circles"
-- Each class's place on that sheet (left, right, top, bottom), for a client
-- without the game's own CLASS_ICON_TCOORDS.
local CIRCLE_COORDS = {
    WARRIOR = { 0, 0.25, 0, 0.25 }, MAGE = { 0.25, 0.49609375, 0, 0.25 },
    ROGUE = { 0.49609375, 0.7421875, 0, 0.25 }, DRUID = { 0.7421875, 0.98828125, 0, 0.25 },
    HUNTER = { 0, 0.25, 0.25, 0.5 }, SHAMAN = { 0.25, 0.49609375, 0.25, 0.5 },
    PRIEST = { 0.49609375, 0.7421875, 0.25, 0.5 }, WARLOCK = { 0.7421875, 0.98828125, 0.25, 0.5 },
    PALADIN = { 0, 0.25, 0.5, 0.75 },
}

local function ClassIcon(badge)
    local info = C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo("classicon-" .. badge.id)
    local file = info and (info.file or info.filename)
    if file then
        return file, { info.leftTexCoord or 0, info.rightTexCoord or 1, info.topTexCoord or 0, info.bottomTexCoord or 1 }
    end
    local coords = CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[badge.token]
    if type(coords) ~= "table" or #coords < 4 then coords = CIRCLE_COORDS[badge.token] end
    return CLASS_CIRCLES, coords
end

-- The coin's picture for a tier (1-3). Every badge with art has all three (a
-- test checks), since a missing file would show nothing.
-- Coins not drawn yet show something else: a profession's icon, a class's icon
-- tinted in the metal, or the emblem tinted in the metal (the tint is the
-- second value). A class icon is part of a bigger file: the third value is
-- the part to show (left, right, top, bottom texture coordinates). Class
-- badges and landmarks with no art are hidden, so only the dev tools'
-- previews show those.
function Badges:Texture(badge, tier)
    tier = badge.metal or tier
    if badge.kind == "profession" and not self.PROFESSION_ART_READY then return badge.profession.icon end
    if badge.kind == "class" and not self.CLASS_ART_READY then
        local file, coords = ClassIcon(badge)
        return file, self.TIERS[tier].color, coords
    end
    if badge.kind == "collection" and not self.COLLECTION_ART_READY then return ns.Style.EMBLEM, self.TIERS[tier].color end
    if badge.kind == "landmark" and not self.LANDMARK_ART[badge.id] then return ns.Style.EMBLEM, badge.style.color end
    if badge.kind == "keepsake" and not self.BETA_ART_READY then return ns.Style.EMBLEM, badge.style.color end
    return ns.Style.MEDIA .. "Badges\\" .. badge.art .. "_" .. tier
end

-- Puts a coin's picture on a texture, showing only its part of the file (or
-- all of it), and returns its tint.
function Badges:SetCoin(texture, badge, tier)
    local file, tint, coords = self:Texture(badge, tier)
    texture:SetTexture(file)
    if coords then
        texture:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
    else
        texture:SetTexCoord(0, 1, 0, 1)
    end
    return tint
end

-- How a badge's tier looks: its name and colour (a landmark has its own).
function Badges:Style(badge, tier)
    return badge.style or self.TIERS[tier]
end

-- Whether a badge is hidden in this build because its art isn't drawn yet:
-- every class badge until CLASS_ART_READY, each landmark not in LANDMARK_ART,
-- and Beta Camper until BETA_ART_READY. A hidden badge isn't shown, said or
-- counted, but it's still earned, quietly, so it appears with its tier once
-- its art ships.
function Badges:Hidden(badge)
    if badge.kind == "class" then return not self.CLASS_ART_READY end
    if badge.kind == "landmark" then return not self.LANDMARK_ART[badge.id] end
    if badge.kind == "keepsake" then return not self.BETA_ART_READY end
    return false
end

-- Landmarks found (they're counted on their own, not with the rest): the
-- ones shown, or withHidden, hidden ones too (the dev tools).
function Badges:LandmarksFound(withHidden)
    local found = 0
    for _, badge in ipairs(self.LANDMARKS) do
        if self:Tier(badge) > 0 and (withHidden or not self:Hidden(badge)) then found = found + 1 end
    end
    return found
end

-- Class badges earned (counted on their own too, like the landmarks): none
-- while they're hidden, unless withHidden (the dev tools).
function Badges:ClassesEarned(withHidden)
    local earned = 0
    for _, badge in ipairs(self.CLASSES) do
        if self:Tier(badge) > 0 and (withHidden or not self:Hidden(badge)) then earned = earned + 1 end
    end
    return earned
end

-- Badges counted on their own, or not at all: not in "Badges earned" or the total.
local COUNTED_APART = { landmark = true, class = true, keepsake = true }

-- Badges earned, and how many in each metal: every one but the landmarks and
-- class badges, which have counts of their own, and the keepsakes.
function Badges:Count()
    local earned, byTier = 0, { 0, 0, 0 }
    for _, badge in ipairs(all) do
        local tier = not COUNTED_APART[badge.kind] and self:Tier(badge) or 0
        if tier > 0 then
            earned = earned + 1
            byTier[tier] = byTier[tier] + 1
        end
    end
    return earned, byTier
end

-- Whether any badge in a list has been earned.
function Badges:AnyEarned(list)
    for _, badge in ipairs(list) do
        if self:Tier(badge) > 0 then return true end
    end
    return false
end

-- A secret badge (Touch Grass) isn't shown or counted until it's earned.
-- Landmarks and collections show (as outlines) once any one of them is earned.
-- A hidden badge (no art yet) never shows; the dev tools' preview shows them all.
-- anyLandmark, anyCollection: whether any is, when already known.
function Badges:Visible(badge, anyLandmark, anyCollection)
    if self.preview ~= nil then return true end
    if self:Hidden(badge) then return false end
    if badge.kind == "landmark" then
        if anyLandmark == nil then anyLandmark = self:LandmarksFound() > 0 end
        return anyLandmark
    end
    if badge.kind == "collection" then
        if anyCollection == nil then anyCollection = self:AnyEarned(self.COLLECTIONS) end
        if not anyCollection then return false end
    end
    return not badge.secret or self:Tier(badge) > 0
end

-- Badges there are to earn: every one but the landmarks, class badges,
-- keepsakes and unearned secrets.
function Badges:Total()
    local total = 0
    for _, badge in ipairs(all) do
        if not COUNTED_APART[badge.kind] and (not badge.secret or self:Tier(badge) > 0) then total = total + 1 end
    end
    return total
end

-- Earned on screen ----------------------------------------------------------------------
-- The new coin drops in over the middle of the screen with a slowly turning glow
-- in its metal's colour, its name and tier under it, then fades. Click it to see
-- the Badges tab. Several earned at once show one after another.

local SHOW_FOR = 8       -- seconds before it fades
local TOAST_COIN = 200   -- the coin's size on screen, at most (UI units)
Badges.ART_SIZE = 256    -- the coin files' size in pixels (Media/Badges)
local MAX_STRETCH = 1.6  -- how far the art may be enlarged before it looks soft
local queue = {}

-- The sound for earning a badge, by tier: SOUNDKIT names (the dev tools' sound
-- board plays the candidates).
Badges.EARN_SOUNDS = { "UI_DIG_SITE_COMPLETION_TOAST", "UI_GARRISON_TOAST_BUILDING_COMPLETE", "UI_LEGENDARY_LOOT_TOAST",
    complete = "UI_LEGENDARY_LOOT_TOAST" } -- complete: All Gold

function Badges:PlayEarnSound(tier, special)
    local kit = special and self.EARN_SOUNDS.complete or self.EARN_SOUNDS[tier]
    PlaySound(SOUNDKIT[kit or ""] or SOUNDKIT.UI_BNET_TOAST or SOUNDKIT.TELL_MESSAGE)
end
local FINALE_SHOW_FOR = 15 -- All Gold stays longer

-- The coin's size on the toast: TOAST_COIN, or smaller where that many UI
-- units is more real pixels than the art can fill (4K screens, a big UI
-- scale). A frame with an effective scale of 1 is 768 units tall.
function Badges:ToastCoinSize(frame)
    local _, height = GetPhysicalScreenSize()
    local scale = frame:GetEffectiveScale()
    if type(height) ~= "number" or type(scale) ~= "number" or height <= 0 or scale <= 0 then return TOAST_COIN end
    local pixelsPerUnit = height / 768 * scale
    return math.min(TOAST_COIN, math.floor(self.ART_SIZE * MAX_STRETCH / pixelsPerUnit))
end

-- Sizes the toast around a coin of that size.
local function Layout(f, size)
    f:SetSize(440, size + 150)
    f.glow:SetSize(size * 2, size * 2)
    f.glow:ClearAllPoints()
    f.glow:SetPoint("CENTER", f, "TOP", 0, -(size / 2 + 36))
    f.glow2:SetSize(size * 2.6, size * 2.6)
    f.coin:SetSize(size, size)
end

local function Toast()
    if Badges.toast then return Badges.toast end
    local style = ns.Style
    -- Only the coin takes clicks, so the rest doesn't get in the way of the world.
    local f = CreateFrame("Frame", "HappyCamperBadgeToast", UIParent)
    f:EnableMouse(false)
    f:SetPoint("CENTER", 0, 160)
    f:SetFrameStrata("FULLSCREEN_DIALOG") -- over the Happy Camper window
    f:SetFrameLevel(50)

    f.glow = f:CreateTexture(nil, "BACKGROUND")
    f.glow:SetTexture("Interface\\Cooldown\\star4")
    f.glow:SetBlendMode("ADD")
    -- The finale's second, bigger glow, turning the other way.
    f.glow2 = f:CreateTexture(nil, "BACKGROUND", nil, -1)
    f.glow2:SetTexture("Interface\\Cooldown\\star4")
    f.glow2:SetBlendMode("ADD")
    f.glow2:SetPoint("CENTER", f.glow)
    f.glow2:Hide()
    f.coin = f:CreateTexture(nil, "ARTWORK")
    f.coin:SetPoint("CENTER", f.glow)
    Layout(f, TOAST_COIN)
    f.heading = style:Text(f, "GameFontNormal", L["Badge earned"])
    f.heading:SetPoint("BOTTOM", f.coin, "TOP", 0, 14)
    f.zone = style:Text(f, "GameFontNormalHuge")
    f.zone:SetPoint("TOP", f.coin, "BOTTOM", 0, -12)
    f.tier = style:Text(f, "GameFontHighlight")
    f.tier:SetPoint("TOP", f.zone, "BOTTOM", 0, -4)

    -- The glow turns for as long as it shows.
    f.spin = f.glow:CreateAnimationGroup()
    f.spin:SetLooping("REPEAT")
    local turn = f.spin:CreateAnimation("Rotation")
    turn:SetDegrees(-360)
    turn:SetDuration(12)
    f.spin2 = f.glow2:CreateAnimationGroup()
    f.spin2:SetLooping("REPEAT")
    local turnBack = f.spin2:CreateAnimation("Rotation")
    turnBack:SetDegrees(360)
    turnBack:SetDuration(20)

    -- The coin drops in a little too big and settles.
    f.drop = f.coin:CreateAnimationGroup()
    local grow = f.drop:CreateAnimation("Scale")
    grow:SetScaleFrom(0.2, 0.2)
    grow:SetScaleTo(1.15, 1.15)
    grow:SetDuration(0.35)
    grow:SetSmoothing("OUT")
    local settle = f.drop:CreateAnimation("Scale")
    settle:SetScaleFrom(1.15, 1.15)
    settle:SetScaleTo(1, 1)
    settle:SetDuration(0.2)
    settle:SetStartDelay(0.35)

    -- The whole thing fades in, waits, and fades out.
    f.show = f:CreateAnimationGroup()
    local fadeIn = f.show:CreateAnimation("Alpha")
    fadeIn:SetFromAlpha(0)
    fadeIn:SetToAlpha(1)
    fadeIn:SetDuration(0.3)
    local fadeOut = f.show:CreateAnimation("Alpha")
    fadeOut:SetFromAlpha(1)
    fadeOut:SetToAlpha(0)
    fadeOut:SetDuration(1.2)
    fadeOut:SetStartDelay(SHOW_FOR)
    f.fadeOut = fadeOut
    f.show:SetScript("OnFinished", function() Badges:NextToast() end)

    f.click = CreateFrame("Button", nil, f)
    f.click:SetAllPoints(f.coin)
    f.click:SetScript("OnClick", function()
        wipe(queue)
        Badges:NextToast()
        ns.Hub:Open("badges")
    end)
    f:Hide()
    Badges.toast = f
    return f
end

-- Shows the next earned badge waiting, or hides the toast.
function Badges:NextToast()
    local f = Toast()
    local nextOne = table.remove(queue, 1)
    if not nextOne then
        f.spin:Stop()
        f.spin2:Stop()
        f:Hide()
        return
    end
    local badge, tierIndex, replay = nextOne[1], nextOne[2], nextOne[3]
    local tier = self:Style(badge, tierIndex)
    -- Shown again from the Badges tab: when it was earned, and no sound.
    local earned = replay and self:Progress(badge).earned[tierIndex]
    f.heading:SetText(earned and format(L["Earned %s"], date("%Y-%m-%d", earned))
        or badge.special and L["Every badge in gold!"] or L["Badge earned"])
    -- Sized each time: the resolution or UI scale may have changed.
    Layout(f, math.floor(self:ToastCoinSize(f) * (badge.scale or 1)))
    local tint = self:SetCoin(f.coin, badge, tierIndex)
    f.coin:SetVertexColor(tint and tint[1] or 1, tint and tint[2] or 1, tint and tint[3] or 1)
    -- The finale: a second glow, and it stays longer.
    f.glow2:SetShown(badge.special == true)
    f.glow2:SetVertexColor(tier.color[1], tier.color[2], tier.color[3])
    f.glow2:SetAlpha(0.5)
    if badge.special then f.spin2:Play() else f.spin2:Stop() end
    f.fadeOut:SetStartDelay(badge.special and FINALE_SHOW_FOR or SHOW_FOR)
    f.glow:SetVertexColor(tier.color[1], tier.color[2], tier.color[3])
    f.glow:SetAlpha(0.7)
    f.zone:SetText(self:Name(badge))
    f.zone:SetTextColor(tier.color[1], tier.color[2], tier.color[3])
    local text = badge.description or format(L["%s badge"], tier.name)
    -- Only the dev tools show a hidden badge here, and say so under it.
    local note = self.DevNote and self.DevNote(badge)
    f.tier:SetText(note and text .. "\n|cffff6666" .. note .. "|r" or text)
    f.shown = { badge = badge, tier = tierIndex }
    f:Show()
    f.spin:Play()
    f.drop:Stop()
    f.drop:Play()
    f.show:Stop()
    f.show:Play()
    if not replay then self:PlayEarnSound(tierIndex, badge.special) end
end

function Badges:Celebrate(badge, tier)
    queue[#queue + 1] = { badge, tier }
    local f = Toast()
    if not f:IsShown() then self:NextToast() end
end

-- The dev tools can show every badge as earned in one tier (1-3), to look at
-- the art: only the display changes, nothing is earned or saved. nil = off.
Badges.preview = nil
-- The dev tools mark badges hidden in this build wherever they show them:
-- DevNote(badge) is a line for its tooltip and pop-up (and its name on the
-- tab turns red), or nil. Unset without the dev tools.
Badges.DevNote = nil

-- The tier a badge shows: the previewed one, or the one earned.
function Badges:ShownTier(badge)
    if self.preview then return badge.metal or self.preview end
    return self:Tier(badge)
end

function Badges:SetPreview(tier)
    self.preview = tier
    self:Refresh()
end

-- Shows an earned badge big again (clicked on the Badges tab), right away.
function Badges:ShowAgain(badge)
    local tier = self:ShownTier(badge)
    if tier == 0 then return end
    wipe(queue)
    queue[1] = { badge, tier, true }
    self:NextToast()
end

-- Counts that are a tally of other badges (a collection's), a yes/no (a
-- landmark found) or a best so far (a class's level), not a running total:
-- merging keeps the higher.
local TALLIES = { count = true, allBronze = true, allSilver = true, allGold = true, found = true, level = true }

-- Badges were each character's own before: a character's progress is added
-- to the account's once (counts added up, the higher tier, the earlier date).
function Badges:MergeCharacter()
    local mine = ns.charDB.badges
    if not mine then return end
    ns.db.badges = ns.db.badges or {}
    for key, progress in pairs(mine) do
        local into = ns.db.badges[key]
        if not into then
            ns.db.badges[key] = progress
        else
            for field, value in pairs(progress) do
                if field == "tier" then
                    into.tier = math.max(into.tier or 0, value)
                elseif field == "earned" then
                    into.earned = into.earned or {}
                    for tier, at in pairs(value) do into.earned[tier] = math.min(into.earned[tier] or at, at) end
                elseif type(value) == "number" and TALLIES[field] then
                    into[field] = math.max(into[field] or 0, value)
                elseif type(value) == "number" then
                    into[field] = (into[field] or 0) + value
                end
            end
        end
    end
    ns.charDB.badges = nil
end

-- Earning -----------------------------------------------------------------------------

local UpdateCollections

-- Moves a badge up to every tier it now meets, and says so; then the
-- collections catch up. quiet: the Badges tab is redrawn by the caller.
-- A class badge goes straight to the best tier it meets (a first rest at level
-- 60 is gold), said once; the tiers it passed get the same date. A hidden
-- badge (no art yet) is earned without a word, to appear once its art ships.
local function Check(badge, quiet)
    local progress = Badges:Progress(badge)
    local nextTier = Badges:NextTier(badge, progress.tier)
    local hidden = Badges:Hidden(badge)
    while nextTier and Badges:Meets(badge, progress, nextTier) do
        progress.tier = nextTier
        nextTier = Badges:NextTier(badge, progress.tier)
        progress.earned[progress.tier] = GetServerTime()
        if not hidden and not (badge.kind == "class" and nextTier and Badges:Meets(badge, progress, nextTier)) then
            local tier = Badges:Style(badge, progress.tier)
            local hex = format("%02x%02x%02x", tier.color[1] * 255, tier.color[2] * 255, tier.color[3] * 255)
            if badge.metal then -- one coin, its name says it all
                ns.Print(L["Badge earned: |cff%s%s|r. See it on the Badges tab."], hex, Badges:Name(badge))
            else
                ns.Print(L["Badge earned: |cff%s%s %s|r. See it on the Badges tab."], hex, Badges:Name(badge), tier.name)
            end
            if ns.db.badgeToast then
                Badges:Celebrate(badge, progress.tier)
            else
                Badges:PlayEarnSound(progress.tier, badge.special)
            end
        end
    end
    -- Only zone and profession badges count toward the collections.
    if badge.kind == "zone" or badge.kind == "profession" then UpdateCollections() end
    if not quiet and ns.Hub:IsShowing("badges") then ns.Hub:Refresh() end
end

-- Counts the badges for the collections, and checks each (the Badges tab is
-- redrawn once, after).
function UpdateCollections()
    local earnedCount, done = 0, { 0, 0, 0 }
    for _, badge in ipairs(countable) do
        local tier = Badges:Tier(badge)
        if tier > 0 then earnedCount = earnedCount + 1 end
        for metal = 1, 3 do
            if tier >= metal or (tier >= 1 and badge.kind == "zone" and BRONZE_ONLY[badge.id]) then
                done[metal] = done[metal] + 1
            end
        end
    end
    for _, badge in ipairs(Badges.COLLECTIONS) do
        local progress = Badges:Progress(badge)
        if badge.metal then progress[ALL_KEY[badge.metal]] = done[badge.metal] else progress.count = earnedCount end
        Check(badge, true)
    end
end

-- Counts the collections again now, earning any they've reached (after a
-- backup's badges are added to yours).
function Badges:UpdateCollections()
    UpdateCollections()
end

local function Add(badge, key)
    local progress = Badges:Progress(badge)
    progress[key] = (progress[key] or 0) + 1
end

-- The fire you're resting at, by a key that's the same each time: the camp's
-- ID, or for your own fire not yet a camp, the ID it gets (Camps.lua's NewCamp).
local function FireHere()
    local camp = ns.Social:MyCamp()
    if camp then return camp.id end
    local lit = ns.Camps:LitFire(true)
    local mine = ns.state.myCampID and ns.Camps:Get(ns.state.myCampID)
    if not lit and mine and mine.owned then
        local distance = ns.Camps:DistanceFromPlayer(mine)
        if distance and distance <= ns.Camps.MERGE_RADIUS then return mine.id end
    end
    return lit and lit.placedAt and ns.playerName .. ":" .. lit.placedAt or nil
end

-- Each fire counts once as a camp: the fires counted lately
-- (charDB.badgeCampAt, [fire] = server time), kept longer than any fire burns.
local CAMP_MEMORY = 2 * 3600
local function NewCamp(fire)
    local seen = ns.charDB.badgeCampAt
    if type(seen) ~= "table" then
        seen = {}
        ns.charDB.badgeCampAt = seen
    end
    local now = GetServerTime()
    for key, at in pairs(seen) do
        if type(at) ~= "number" or now - at > CAMP_MEMORY then seen[key] = nil end
    end
    if seen[fire] then return false end
    seen[fire] = now
    return true
end

-- You rested a full minute at a fire (a rest a fight broke off never gets
-- here): a camp in this zone, once per fire, whoever lit it. Anywhere, it
-- counts for your class's badge.
function Badges:OnRested()
    local zone = self:ZoneHere()
    if zone then
        Add(zone, "rests")
        local fire = FireHere()
        if fire and NewCamp(fire) then Add(zone, "camps") end
        Check(zone, true)
    end
    self:CheckClass(true)
    if ns.Hub:IsShowing("badges") then ns.Hub:Refresh() end -- once for both
    self:CheckLandmarks()
end

-- Resting as your class at your level: its badge's best tier for that level.
-- A level or class that can't be read (secret, unknown) counts nothing.
-- quiet: the Badges tab is redrawn by the caller.
function Badges:CheckClass(quiet)
    local badge, level = self:ClassHere(), ns.KnownLevel("player")
    if not badge or not level then return end
    local progress = self:Progress(badge)
    if level > (progress.level or 0) then progress.level = level end
    Check(badge, quiet)
end

-- Resting at a fire inside a landmark's area finds it.
function Badges:CheckLandmarks()
    local here = ns.Location:AreaIDsHere()
    for _, badge in ipairs(self.LANDMARKS) do
        for id in pairs(badge.areas) do
            if here[id] and self:Tier(badge) == 0 then
                Badges:Progress(badge).found = 1
                Check(badge)
                break
            end
        end
    end
end

-- Gives Beta Camper, once (Season.lua, Backup.lua); true if it's new. Quietly:
-- the caller thanks the player (ThankBetaCamper) when the time is right.
function Badges:AwardBetaCamper()
    local progress = self:Progress(self.BETA_CAMPER)
    if progress.tier > 0 then return false end
    progress.given, progress.tier = 1, 1
    progress.earned[1] = GetServerTime()
    return true
end

-- The thank-you for Beta Camper: a line in your own chat window and its coin
-- on screen. Nothing while the coin isn't drawn (hidden).
function Badges:ThankBetaCamper()
    local badge = self.BETA_CAMPER
    if self:Hidden(badge) or self:Tier(badge) == 0 then return end
    ns.Print(L["Thank you for camping in the beta! You've earned the %s badge."], self:Name(badge))
    if ns.db.badgeToast then
        self:Celebrate(badge, 1)
    else
        self:PlayEarnSound(1)
    end
    if ns.Hub:IsShowing("badges") then ns.Hub:Refresh() end
end

-- You placed a camp object (your own cast finished: nobody else's shows here).
-- It counts toward its profession's badge, by its tier.
local function Placed(badge, tier)
    Add(badge, "placed")
    if tier >= 2 then Add(badge, "better") end
    if tier >= TOP_TIER then Add(badge, "top") end
    Check(badge)
end

function Badges:OnObjectPlaced(spellID)
    local key = ns.ObjectInfo(spellID)
    local _, _, skillLine, tier = ns.ObjectByName(key)
    local badge = skillLine and self:Profession(skillLine)
    if not badge then return end
    if skillLine == COOKING then tier = COOKING_OBJECT_TIERS[key] or tier end
    Placed(badge, tier or 1)
end

-- You lit a campfire (slots: 3, 5 or 10). Its kit is Cooking's: Basic, Journeyman
-- or Expert.
function Badges:OnFirePlaced(slots)
    local badge = self:Profession(COOKING)
    if not badge then return end
    Placed(badge, (slots or 3) >= 10 and 3 or (slots or 3) >= 5 and 2 or 1)
end

-- A profession's camp objects for its tooltip, lowest tier first (Cooking's
-- campfire kits, then its objects), in the client's language.
function Badges:ObjectNames(badge)
    local names = {}
    if badge.id == COOKING then
        for _, spellID in ipairs(KIT_SPELLS) do
            local name = C_Spell.GetSpellName(spellID)
            if type(name) == "string" and name ~= "" then names[#names + 1] = name end
        end
    end
    for tier = 1, 3 do
        if badge.profession.objects[tier] then names[#names + 1] = ns.ObjectName(badge.id, tier) end
    end
    return names
end

-- Badges tab ------------------------------------------------------------------------------
-- A coin for every badge, zones by region and then professions and classes,
-- each with its name under it: earned ones in their metal, the rest a dark
-- silhouette (the shape only, so the design is a surprise). Hovering one shows
-- what it took and what the next tier asks; clicking an earned one shows it
-- big again. Hidden badges (no art yet) have coins too, shown only in the dev
-- tools' preview, so a section with nothing else (Classes) has no heading.

local COIN, CELL, NAME_ROOM, PER_ROW = 88, 112, 40, 4 -- NAME_ROOM: three lines of small text
local LIST_TOP = -30 -- the panel behind the coins, under the count
local SCROLLBAR = 14 -- room on the right for the scroll bar, inside the panel

local function CoinTooltip(tooltip, button)
    local badge = button.badge
    local progress = Badges:Progress(badge)
    local tier = progress.tier
    local color = tier > 0 and Badges:Style(badge, tier).color or { 0.6, 0.6, 0.6 }
    -- Not earned yet: no name (the dev tools' preview shows them).
    local known = tier > 0 or Badges.preview ~= nil
    tooltip:SetText(known and Badges:Name(badge) or L["Undiscovered badge"], color[1], color[2], color[3])
    if badge.kind == "zone" and Badges:ZoneHere() == badge then tooltip:AddLine(L["You're here."], 0.5, 0.8, 1) end
    if badge.description then tooltip:AddLine(badge.description, 1, 1, 1, true) end
    if badge.kind == "profession" then
        tooltip:AddLine(format(L["Camp objects: %s"], table.concat(Badges:ObjectNames(badge), ", ")), 0.8, 0.8, 0.8, true)
    end
    if tier > 0 then
        local when = date("%Y-%m-%d", progress.earned[tier] or 0)
        if badge.kind == "keepsake" then -- no metal to name
            tooltip:AddLine(format(L["Earned %s"], when), 1, 1, 1)
        else
            tooltip:AddLine(format(L["%s badge, earned %s"], Badges:Style(badge, tier).name, when), 1, 1, 1)
        end
    end
    local nextIndex = Badges:NextTier(badge, tier)
    if nextIndex then
        local nextTier = Badges:Style(badge, nextIndex)
        tooltip:AddLine(" ")
        tooltip:AddLine(format(L["For %s:"], nextTier.name), nextTier.color[1], nextTier.color[2], nextTier.color[3])
        for _, line in ipairs(Badges:NeedLines(badge, progress, nextIndex)) do
            if line.done then tooltip:AddLine(line.text, 0.4, 1, 0.4, true) else tooltip:AddLine(line.text, 1, 1, 1, true) end
        end
        if badge.kind == "collection" and (badge.metal or 0) >= 2 then
            tooltip:AddLine(L["Zephras Isle only needs bronze: players can't go back there."], 0.7, 0.7, 0.7, true)
        end
    end
    -- Even once earned: the class coins beside it may still be grey. Not
    -- while the class badges are hidden (no art yet).
    if badge.kind == "collection" and Badges.CLASS_ART_READY then
        tooltip:AddLine(L["Class badges don't count toward collections."], 0.7, 0.7, 0.7, true)
    end
    -- A hidden badge, shown by the dev tools' preview: they say so.
    local note = Badges.DevNote and Badges.DevNote(badge)
    if note then tooltip:AddLine(note, 1, 0.4, 0.4, true) end
end

function Badges:Build(page)
    local window = page:GetParent()
    local style = ns.Style
    page.summary = style:PageTitle(page)

    -- The panel stays put; the coins scroll inside it, with the scroll bar
    -- inside its right edge.
    local inset = style:Inset(page, window, 10, LIST_TOP, 10, LIST_TOP)
    inset:ClearAllPoints()
    inset:SetPoint("TOPLEFT", page, "TOPLEFT", 10, LIST_TOP)
    inset:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", -10, 4)
    local scroll = CreateFrame("ScrollFrame", nil, page)
    scroll:SetPoint("TOPLEFT", 16, LIST_TOP - 6)
    scroll:SetPoint("BOTTOMRIGHT", -16, 10)
    scroll:SetFrameLevel(window:GetFrameLevel() + 4)
    local width = window:GetWidth() - 32 - SCROLLBAR
    style:ScrollArea(scroll, width, 1)
    local content = scroll.child
    local left = math.floor((width - PER_ROW * CELL) / 2)

    -- Sections: each region's zones, then the professions and classes;
    -- alphabetical in the game's language.
    local sections = { { title = L["Collections"], badges = self.COLLECTIONS, inOrder = true } }
    for _, region in ipairs(self.REGIONS) do
        local info = C_Map.GetMapInfo(region.map)
        sections[#sections + 1] = { title = info and info.name or "", badges = region.zones }
    end
    sections[#sections + 1] = { title = L["Professions"], badges = self.PROFESSIONS }
    sections[#sections + 1] = { title = L["Classes"], badges = self.CLASSES }
    sections[#sections + 1] = { title = L["Landmarks"], badges = self.LANDMARKS, hidden = true }
    sections[#sections + 1] = { title = L["Keepsakes"], badges = self.KEEPSAKES, inOrder = true }

    page.coins, page.sections = {}, {}
    page.content, page.left = content, left
    for _, section in ipairs(sections) do
        local placed = { header = style:Text(content, "GameFontNormal", section.title), buttons = {}, hidden = section.hidden }
        page.sections[#page.sections + 1] = placed
        local badges, names = {}, {}
        for _, badge in ipairs(section.badges) do
            badges[#badges + 1] = badge
            names[badge] = self:Name(badge)
        end
        if not section.inOrder then self:SortByName(badges, names) end
        for _, badge in ipairs(badges) do
            local button = CreateFrame("Button", nil, content)
            local size = math.floor(COIN * (badge.scale or 1)) -- Summit is a little bigger
            button:SetSize(size, size)
            placed.buttons[#placed.buttons + 1] = button
            button.icon = button:CreateTexture(nil, "ARTWORK")
            button.icon:SetAllPoints()
            button.glow = button:CreateTexture(nil, "HIGHLIGHT") -- shows on hover
            button.glow:SetAllPoints()
            button.glow:SetTexture("Interface\\Buttons\\UI-Common-MouseHilight")
            button.glow:SetBlendMode("ADD")
            button.name = style:Text(content, "GameFontHighlightSmall", names[badge])
            button.name:SetWidth(CELL - 6)
            button.name:SetPoint("TOP", button, "BOTTOM", 0, -3)
            button.badge = badge
            style:CustomTooltip(button, "ANCHOR_RIGHT", CoinTooltip)
            button:SetScript("OnClick", function() self:ShowAgain(badge) end)
            page.coins[#page.coins + 1] = button
        end
    end
    self.page = page
    self:Layout()
end

-- Places the sections' headers and coins in their grids, leaving out secret
-- badges not yet earned.
function Badges:Layout()
    local page = self.page
    local y = -8
    -- Worked out once here, not for every coin.
    local anyLandmark, anyCollection = self:LandmarksFound() > 0, self:AnyEarned(self.COLLECTIONS)
    for _, section in ipairs(page.sections) do
        -- A secret section (Landmarks, Collections) shows once anything in it does.
        local any = false
        for _, button in ipairs(section.buttons) do any = any or self:Visible(button.badge, anyLandmark, anyCollection) end
        section.header:SetShown(any)
        if any then
            section.header:ClearAllPoints()
            section.header:SetPoint("TOPLEFT", page.content, "TOPLEFT", 4, y)
            y = y - 22
        end
        local shown = 0
        for _, button in ipairs(section.buttons) do
            local visible = self:Visible(button.badge, anyLandmark, anyCollection)
            button:SetShown(visible)
            -- Names only once earned (or in the dev tools' preview).
            button.name:SetShown(visible and self:ShownTier(button.badge) > 0)
            if visible then
                local column, row = shown % PER_ROW, math.floor(shown / PER_ROW)
                button:ClearAllPoints()
                button:SetPoint("CENTER", page.content, "TOPLEFT", page.left + column * CELL + CELL / 2,
                    y - row * (COIN + NAME_ROOM) - COIN / 2)
                shown = shown + 1
            end
        end
        if any then y = y - math.ceil(shown / PER_ROW) * (COIN + NAME_ROOM) - 10 end
    end
    page.content:SetHeight(-y + 8)
end

function Badges:Refresh()
    local page = self.page
    if not page then return end
    self:Layout()
    for _, button in ipairs(page.coins) do
        local tier = self:ShownTier(button.badge)
        local tint = self:SetCoin(button.icon, button.badge, math.max(tier, 1))
        -- Not earned yet: black, so only the outline shows.
        button.silhouette = tier == 0
        button.glow:SetShown(tier > 0)
        button.icon:SetDesaturated(tier == 0)
        if tier == 0 then
            button.icon:SetVertexColor(0, 0, 0)
        else
            button.icon:SetVertexColor(tint and tint[1] or 1, tint and tint[2] or 1, tint and tint[3] or 1)
        end
        button.icon:SetAlpha(tier == 0 and 0.7 or 1)
        if tier == 0 then
            button.name:SetTextColor(0.6, 0.6, 0.6)
        elseif self.DevNote and self.DevNote(button.badge) then -- hidden, in the dev tools' preview
            button.name:SetTextColor(1, 0.4, 0.4)
        else
            button.name:SetTextColor(1, 1, 1)
        end
    end
    -- Hidden badges (no art yet) aren't counted.
    local text = format(L["Badges earned: %d"], (self:Count()))
    local classes = self:ClassesEarned()
    if classes > 0 then text = text .. "  " .. format(L["Class badges: %d"], classes) end
    local found = self:LandmarksFound()
    if found > 0 then text = text .. "  " .. format(L["Landmarks found: %d"], found) end
    page.summary:SetText(text)
end
