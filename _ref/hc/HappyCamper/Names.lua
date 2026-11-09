-- Happy Camper. Copyright (c) 2026 Torridon. All rights reserved; see LICENSE.
local _, ns = ...
local L = ns.L

-- Camp names. Every camp gets a location name by default ("Goldshire
-- Campsite", "South Goldshire Campsite", "Southern Elwynn Forest Campsite");
-- whoever lit the fire can pick another from the Camp tab. Only names that
-- fit are offered: place names where you are, features nearby, your own
-- professions, and local specials near their location.
--
-- Names travel between players as keys ("n:pub1", "l:goldshire:1"), never as
-- free text, so nobody can put arbitrary words on other players' maps.
-- {place} is the area you're in or near, or the zone outside named areas.
-- Names are keys everywhere and only become text (in your language, through
-- L[]) when they're shown; {dir} and {place} let translations reorder them.

local Names = {}
ns.Names = Names

-- Fixed names, by category. Keys must never change once released.
local FIXED = {
    { title = "Campsites", entries = {
        { "sens1", "Sheltered Campsite" }, { "sens2", "Wayfarer's Camp" }, { "sens3", "Prospector's Firepit" },
        { "sens4", "Traveler's Rest" }, { "sens5", "Quiet Campsite" }, { "sens6", "Pathside Camp" },
        { "fun1", "Suspicious Campsite" }, { "fun2", "Definitely Not an Ambush" }, { "fun3", "Mostly Bear-Free Camp" },
        { "fun4", "Probably Haunted Campsite" }, { "fun5", "Totally Legitimate Camp" },
        { "cheek1", "Bring Your Own Log" }, { "cheek2", "Rest Now, Quest Later" },
        { "cheek3", "Borrowed Firewood Camp" }, { "cheek4", "Seat's Taken" },
    } },
    { title = "Painted signs", entries = {
        { "pub1", "The Kettle and Kindling" }, { "pub2", "The Crooked Log" }, { "pub3", "The Sleeping Boar" },
        { "pub4", "The Rusty Lantern" }, { "pub5", "The Soot and Sparrow" }, { "pub6", "The Tipsy Kobold" },
        { "trade1", "Peddler's Stop" }, { "trade2", "The Wandering Stall" }, { "trade3", "Tinker's Wagon" },
        { "trade4", "Merchant's Rest" }, { "trade5", "Bargain Bonfire" },
    } },
}

-- Names with the place in them. "near" ones only make sense just outside a place.
local TEMPLATES = {
    { "camp", "Camp {place}" }, { "wayside", "{place} Wayside Camp" }, { "rest", "{place} Rest" },
    { "trading", "{place} Trading Stop" }, { "market", "{place} Market Camp" },
    { "almost", "Almost {place}", near = true }, { "outside", "Just Outside {place}", near = true },
}

-- Offered when a nearby area's name (or the zone's) contains one of the words
-- (as whole words), or one of FEATURE_WORDS' in the client's language.
local FEATURES = {
    { "lake", "Lakeside Camp", { "lake", "loch", "pond", "pool", "mere" } },
    { "river", "Riverside Camp", { "river", "stream", "creek", "falls", "brook", "rapids" } },
    { "hill", "Hilltop Camp", { "hill", "hills", "peak", "ridge", "summit", "mount", "mountain", "mountains", "bluff", "heights", "highlands" } },
    { "wood", "Woodland Camp", { "wood", "woods", "forest", "grove", "glade", "thicket", "pines" } },
    { "shore", "Shoreline Camp", { "coast", "shore", "beach", "bay", "sea", "cove", "strand", "isle", "port" } },
    { "cross", "Crossroads Camp", { "crossroads", "crossing", "bridge", "road", "pass" } },
    { "valley", "Valley Camp", { "valley", "vale", "canyon", "gulch", "gorge", "hollow" } },
    { "marsh", "Marshside Camp", { "marsh", "swamp", "fen", "bog", "mire", "wallow", "sorrows" } },
    { "ruins", "Camp by the Ruins", { "ruins", "ruin" } },
    { "mine", "Mine Mouth Camp", { "mine", "quarry", "dig", "excavation" } },
    { "farm", "Farmside Camp", { "farm", "farmstead", "orchard", "homestead", "mill", "fields" } },
    { "sand", "Dune Camp", { "sands", "dunes", "desert", "wastes" } },
    { "snow", "Snowbound Camp", { "frost", "snow", "winter", "ice", "frozen", "snowfall" } },
}

-- The same features in the other client languages, for area names as the game
-- shows them (GetLocale(): the addon's own language can be another). French,
-- Spanish and Portuguese words count as whole words; German, Chinese and
-- Korean ones anywhere in a name (German joins words: "Kristallsee"). A word
-- starting with "-" only counts at the end of one ("-see": not "Seelen").
local FEATURE_WORDS = {
    deDE = { anywhere = true,
        lake = { "-see", "teich", "weiher", "tümpel" },
        river = { "fluss", "bach", "wasserfall", "-fälle", "stromschnellen" },
        hill = { "hügel", "gipfel", "-kamm", "-berg", "-berge", "höhe", "spitze", "gebirge", "hochland" },
        wood = { "wald", "wälder", "hain", "gehölz", "lichtung", "forst", "dickicht" },
        shore = { "küste", "ufer", "strand", "bucht", "meer", "insel", "hafen" },
        cross = { "wegekreuz", "kreuzweg", "kreuzung", "brücke", "straße", "-pass" },
        valley = { "-tal", "täler", "schlucht", "klamm", "senke" },
        marsh = { "sumpf", "sümpfe", "-marsch", "moor", "morast" },
        ruins = { "ruine", "trümmer" },
        mine = { "mine", "bergwerk", "steinbruch", "grube", "ausgrabung" },
        farm = { "gehöft", "bauernhof", "obstgarten", "mühle", "felder", "farm" },
        sand = { "-sand", "dünen", "wüste" },
        snow = { "frost", "schnee", "winter", "gefroren", "eisig", "gletscher" },
    },
    frFR = {
        lake = { "lac", "étang", "Étang", "mare" },
        river = { "rivière", "fleuve", "ruisseau", "chutes", "cascade", "rapides", "torrent" },
        hill = { "colline", "collines", "pic", "crête", "sommet", "mont", "monts", "montagne", "montagnes", "hauteurs" },
        wood = { "bois", "forêt", "bosquet", "clairière", "pinède", "sylve" },
        shore = { "côte", "rivage", "plage", "baie", "mer", "crique", "île", "Île", "port", "anse" },
        cross = { "carrefour", "croisée", "pont", "route", "col", "passage" },
        valley = { "vallée", "val", "vallon", "canyon", "gorge", "gorges", "ravin", "défilé" },
        marsh = { "marais", "marécage", "marécages", "tourbière", "bourbier", "fange" },
        ruins = { "ruines", "ruine" },
        mine = { "mine", "mines", "carrière", "fouilles", "excavation" },
        farm = { "ferme", "verger", "moulin", "champs" },
        sand = { "sables", "dunes", "désert" },
        snow = { "givre", "neige", "neiges", "hiver", "glace", "glaces", "gelé", "gelée", "glacé" },
    },
    esES = {
        lake = { "lago", "laguna", "estanque", "charca" },
        river = { "río", "arroyo", "cascada", "cataratas", "rápidos", "riachuelo", "torrente" },
        hill = { "colina", "colinas", "cerro", "pico", "cresta", "cumbre", "monte", "montaña", "montañas", "risco" },
        wood = { "bosque", "arboleda", "claro", "espesura", "pinar", "selva" },
        shore = { "costa", "orilla", "playa", "bahía", "mar", "cala", "isla", "puerto", "ensenada" },
        cross = { "cruce", "encrucijada", "puente", "camino", "paso" },
        valley = { "valle", "cañón", "barranco", "garganta", "hondonada", "desfiladero" },
        marsh = { "pantano", "ciénaga", "marjal", "fangal", "lodazal", "marisma" },
        ruins = { "ruinas", "ruina" },
        mine = { "mina", "minas", "cantera", "excavación" },
        farm = { "granja", "huerto", "molino", "campos", "hacienda" },
        sand = { "arenas", "dunas", "desierto" },
        snow = { "escarcha", "nieve", "nieves", "invierno", "hielo", "helado", "gélido" },
    },
    ptBR = {
        lake = { "lago", "lagoa", "açude" },
        river = { "rio", "riacho", "córrego", "cachoeira", "cataratas", "corredeiras" },
        hill = { "colina", "colinas", "morro", "pico", "cume", "monte", "montanha", "montanhas", "serra", "planalto" },
        wood = { "bosque", "floresta", "mata", "arvoredo", "clareira", "pinheiral" },
        shore = { "costa", "litoral", "praia", "baía", "mar", "enseada", "ilha", "porto" },
        cross = { "encruzilhada", "cruzamento", "ponte", "estrada", "passo", "passagem" },
        valley = { "vale", "cânion", "desfiladeiro", "garganta", "ravina" },
        marsh = { "pântano", "brejo", "charco", "lamaçal", "alagado" },
        ruins = { "ruínas", "ruína" },
        mine = { "mina", "minas", "pedreira", "escavação" },
        farm = { "fazenda", "pomar", "moinho", "campos", "sítio", "granja" },
        sand = { "areias", "dunas", "deserto" },
        snow = { "geada", "neve", "inverno", "gelo", "gélido", "congelado" },
    },
    zhCN = { anywhere = true,
        lake = { "湖", "池", "潭" },
        river = { "河", "溪", "瀑布", "江" },
        hill = { "山", "峰", "岭", "丘", "高地" },
        wood = { "林", "树丛" },
        shore = { "海岸", "海滩", "滩", "湾", "岛", "港" },
        cross = { "路口", "桥", "道路", "关口" },
        valley = { "谷", "峡" },
        marsh = { "沼", "湿地", "泥潭" },
        ruins = { "废墟", "遗迹" },
        mine = { "矿", "采石场", "挖掘" },
        farm = { "农场", "农庄", "果园", "磨坊" },
        sand = { "沙", "荒漠" },
        snow = { "霜", "雪", "冰", "冬" },
    },
    koKR = { anywhere = true,
        lake = { "호수", "연못", "저수지" },
        river = { "-강", "개울", "시냇물", "폭포", "여울" },
        hill = { "언덕", "봉우리", "-산", "산맥", "능선", "고원", "고지" },
        wood = { "숲", "삼림", "수풀", "밀림" },
        shore = { "해안", "해변", "바닷가", "-섬", "항구", "포구" },
        cross = { "교차로", "갈림길", "다리", "고개" },
        valley = { "골짜기", "계곡", "협곡" },
        marsh = { "늪", "습지", "수렁" },
        ruins = { "폐허", "유적" },
        mine = { "광산", "채석장", "발굴" },
        farm = { "농장", "과수원", "방앗간", "농가" },
        sand = { "사막", "모래", "사구" },
        snow = { "서리", "얼음", "겨울", "설원", "빙하" },
    },
}
FEATURE_WORDS.esMX, FEATURE_WORDS.ptPT = FEATURE_WORDS.esES, FEATURE_WORDS.ptBR

-- Whether a lowercase place name has a word in it: as a whole word, or with
-- anywhere, as any part of it ("-word": only where a word ends).
local function HasWord(name, word, anywhere)
    if word:sub(1, 1) == "-" then return (name .. " "):find(word:sub(2) .. " ", 1, true) ~= nil end
    if anywhere then return name:find(word, 1, true) ~= nil end
    local escaped = word:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0")
    -- An edge is only checked at a letter or digit: an accented letter is
    -- several bytes, and none of them counts as one.
    local before = word:find("^%w") and "%f[%w]" or ""
    local after = word:find("%w$") and "%f[%W]" or ""
    return name:find(before .. escaped .. after) ~= nil
end

-- One per profession, offered only if you have it: advertises what you do.
local PROFESSION_NAMES = {
    [171] = "The Bubbling Cauldron", [164] = "The Hammer and Anvil", [333] = "The Glowing Rune",
    [202] = "Sprocket and Spark", [165] = "The Tanned Hide", [197] = "The Needle and Thread",
    [185] = "The Simmering Stewpot", [129] = "The Mended Bandage", [182] = "The Wild Herb",
    [186] = "The Pick and Lantern", [393] = "The Hide and Seek", [356] = "The Tangled Line",
}

-- Local specials: offered in (or just outside) the zone or area they belong to.
-- Keyed by lowercase zone or area name.
local SPECIALS = {
    -- Eastern Kingdoms
    ["dun morogh"] = { "Snowdrift Camp", "Frostbitten Toes Camp" },
    ["kharanos"] = { "Thunderbrew Overflow" },
    ["elwynn forest"] = { "Stormwind Overflow", "Kobold Candle Camp" },
    ["goldshire"] = { "Goldshire Whisky Club", "Lion's Pride Overflow" },
    ["northshire valley"] = { "Fresh Recruits' Camp" },
    ["tirisfal glades"] = { "Totally Not Scarlet Camp", "Pumpkin Patch Camp" },
    ["brill"] = { "Gallows' End Overflow" },
    ["loch modan"] = { "Lochside Brewhouse", "Dam View Camp" },
    ["silverpine forest"] = { "Gloomy Pines Camp", "Worgen-Wary Camp" },
    ["westfall"] = { "Westfall Stew Stop", "Definitely Not Defias", "Scarecrow Watch" },
    ["redridge mountains"] = { "Lakeshire Bridge Camp", "Gnoll-Wary Camp" },
    ["duskwood"] = { "Don't Go Into the Woods", "Nightwatch Fire" },
    ["wetlands"] = { "Soggy Boots Camp", "Raptor-Wary Camp" },
    ["hillsbrad foothills"] = { "Southshore Standoff", "Orchard Camp" },
    ["alterac mountains"] = { "Snowcapped Camp", "Ogre-Free Camp (Probably)" },
    ["arathi highlands"] = { "Highland Watch", "Stromgarde Ruins Camp" },
    ["stranglethorn vale"] = { "Page Hunters' Camp", "Tiger Tracks Camp" },
    ["booty bay"] = { "Booty Bay Overflow", "Bloodsail-Free Zone" },
    ["badlands"] = { "Dust and Bones Camp", "Dry Gulch Camp" },
    ["swamp of sorrows"] = { "Misty Bog Camp", "Mournful Mire Camp" },
    ["the hinterlands"] = { "Gryphon Roost Camp", "Troll-Wary Camp" },
    ["searing gorge"] = { "Sweltering Camp", "Slag Pit Camp" },
    ["blasted lands"] = { "Dark Portal Tailgate", "Scorched Earth Camp" },
    ["burning steppes"] = { "Hotfoot Camp", "Ember Fields Camp" },
    ["western plaguelands"] = { "Plague-Wary Camp", "Scourge-Free Zone" },
    ["eastern plaguelands"] = { "Graveyard Shift Camp", "Last Stand Camp" },
    ["deadwind pass"] = { "Haunted Pass Camp", "In the Tower's Shadow" },
    ["stormwind city"] = { "Canal-Side Camp", "Trade District Stop" },
    ["ironforge"] = { "Great Forge Overflow" },
    ["undercity"] = { "Upstairs from Undercity" },
    -- Kalimdor
    ["durotar"] = { "Durotar Dust Bowl", "Scorpid-Wary Camp" },
    ["razor hill"] = { "Razor Hill Rest Stop" },
    ["mulgore"] = { "Kodo Crossing Camp", "Plainsrunner Camp" },
    ["teldrassil"] = { "Root and Branch Camp", "Treetop Camp" },
    ["darkshore"] = { "Moonlit Shore Camp", "Shipwreck Camp" },
    ["the barrens"] = { "Barrens Chat Lounge", "Savanna Camp" },
    ["the crossroads"] = { "Crossroads Overflow" },
    ["stonetalon mountains"] = { "Harpy-Wary Camp", "Stone Ridge Camp" },
    ["ashenvale"] = { "Ashenvale Lookout", "Satyr-Wary Camp" },
    ["thousand needles"] = { "Needle's Eye Camp", "Shimmering Flats Pit Stop" },
    ["desolace"] = { "Desolate Camp", "Centaur-Wary Camp" },
    ["dustwallow marsh"] = { "Muddy Boots Camp", "Croc-Wary Camp" },
    ["feralas"] = { "Twin Colossals Camp", "Deep Woods Camp" },
    ["tanaris"] = { "Gadgetzan Overflow", "Sand in Everything Camp" },
    ["azshara"] = { "Ruins by the Sea Camp", "Naga-Wary Camp" },
    ["felwood"] = { "Don't Drink the Water", "Corrupted Grove Camp" },
    ["un'goro crater"] = { "Dino Watch Camp", "Crater Rim Camp" },
    ["moonglade"] = { "Tranquil Glade Camp" },
    ["silithus"] = { "Bug Spray Camp", "Sandstorm Shelter" },
    ["winterspring"] = { "Frostsaber Camp", "Snowball Fight Camp" },
    ["orgrimmar"] = { "Valley of Strength Overflow" },
    ["thunder bluff"] = { "Windy Mesa Camp" },
    ["darnassus"] = { "Moonwell Camp" },
    -- Forever's new zones
    ["zephras isle"] = { "Windswept Camp", "Pylon Watch Camp" },
    ["riverglades"] = { "Riverbend Camp", "Powderfuse Pit Stop" },
    ["powderfuse port"] = { "Powderfuse Dockside Camp" },
    ["shen'dralas"] = { "Hidden Vale Camp", "Lost Library Camp" },
    ["mount hyjal"] = { "World Tree View Camp", "Summit Camp" },
}

-- Where the specials belong by IDs, which are the same in every client
-- language (names only match an English client's): zone maps, as Badges.lua
-- lists them, and towns' areas.
local SPECIAL_MAPS = {
    [1426] = "dun morogh", [1429] = "elwynn forest", [1420] = "tirisfal glades", [1432] = "loch modan",
    [1421] = "silverpine forest", [1436] = "westfall", [1433] = "redridge mountains", [1431] = "duskwood",
    [1437] = "wetlands", [1424] = "hillsbrad foothills", [1416] = "alterac mountains", [1417] = "arathi highlands",
    [1434] = "stranglethorn vale", [1418] = "badlands", [1435] = "swamp of sorrows", [1425] = "the hinterlands",
    [1427] = "searing gorge", [1419] = "blasted lands", [1428] = "burning steppes", [1422] = "western plaguelands",
    [1423] = "eastern plaguelands", [1430] = "deadwind pass", [1453] = "stormwind city", [1455] = "ironforge",
    [1458] = "undercity",
    [1411] = "durotar", [1412] = "mulgore", [1438] = "teldrassil", [1439] = "darkshore", [1413] = "the barrens",
    [1442] = "stonetalon mountains", [1440] = "ashenvale", [1441] = "thousand needles", [1443] = "desolace",
    [1445] = "dustwallow marsh", [1444] = "feralas", [1446] = "tanaris", [1447] = "azshara", [1448] = "felwood",
    [1449] = "un'goro crater", [1450] = "moonglade", [1451] = "silithus", [1452] = "winterspring",
    [1454] = "orgrimmar", [1456] = "thunder bluff", [1457] = "darnassus",
    [2521] = "zephras isle", [2665] = "zephras isle", [2548] = "riverglades", [2652] = "shen'dralas",
    [2482] = "mount hyjal",
}
local SPECIAL_AREAS = {
    [131] = "kharanos", [87] = "goldshire", [9] = "northshire valley", [159] = "brill",
    [35] = "booty bay", [362] = "razor hill", [380] = "the crossroads",
}

local fixedByKey = {}
for _, category in ipairs(FIXED) do
    for _, entry in ipairs(category.entries) do fixedByKey[entry[1]] = entry[2] end
end
local templateByKey, featureByKey = {}, {}
for _, t in ipairs(TEMPLATES) do templateByKey[t[1]] = t end
for _, f in ipairs(FEATURES) do featureByKey[f[1]] = f end

-- Puts the place (and direction) into a translated name.
local function Fill(text, place, direction)
    text = text:gsub("{place}", (place:gsub("%%", "%%%%")))
    return (text:gsub("{dir}", direction and L[direction] or ""):gsub("^%s+", ""))
end

-- The place a camp is known by: the area it's in or near, else the zone.
local function PlaceOf(location)
    return location and (location.area or location.zone)
end

-- "Goldshire Campsite", "South Goldshire Campsite" or "Southern Elwynn Forest Campsite".
function Names:Default(location)
    if not location then return nil end
    if location.area and location.direction then
        return Fill(L["{dir} {place} Campsite"], location.area, location.direction)
    elseif location.area then
        return Fill(L["{place} Campsite"], location.area)
    elseif location.zone then
        return Fill(L["{dir} {place} Campsite"], location.zone, location.region)
    end
end

-- A shorter form for the map bar: "South Goldshire", "Southern Elwynn Forest".
function Names:Short(location)
    if not location then return nil end
    if location.area then
        return location.direction and Fill(L["{dir} {place}"], location.area, location.direction) or location.area
    end
    return location.zone and Fill(L["{dir} {place}"], location.zone, location.region)
end

-- The name for a key, or nil if the key is unknown (e.g. from a newer version).
function Names:Render(key, location)
    if type(key) ~= "string" then return nil end
    local kind, id = key:match("^(%a):(.+)$")
    local text
    if kind == "n" then
        text = fixedByKey[id]
    elseif kind == "t" then
        local t, place = templateByKey[id], PlaceOf(location)
        if t and place and (not t.near or location.direction) then return Fill(L[t[2]], place) end
    elseif kind == "f" then
        text = featureByKey[id] and featureByKey[id][2]
    elseif kind == "p" then
        text = PROFESSION_NAMES[tonumber(id)]
    elseif kind == "l" then
        local place, index = id:match("^(.+):(%d+)$")
        local list = place and SPECIALS[place]
        text = list and list[tonumber(index)]
    end
    return text and L[text]
end

-- Lowercase names of everything around the camp: its area, nearby areas, zone.
local function Around(location)
    local around = {}
    for name in pairs(location.nearby or {}) do around[#around + 1] = name end
    if location.area then around[#around + 1] = location.area:lower() end
    if location.zone then around[#around + 1] = location.zone:lower() end
    return around
end

-- The local specials (SPECIALS keys) around the camp: by its area's, nearby
-- areas' and zone's IDs, then by name (camps saved before IDs were kept).
local function SpecialsAround(location, around)
    local keys = {}
    local function Note(key) if key and SPECIALS[key] then keys[#keys + 1] = key end end
    Note(SPECIAL_AREAS[location.areaID or 0])
    for id in pairs(location.nearbyIDs or {}) do Note(SPECIAL_AREAS[id]) end
    Note(SPECIAL_MAPS[location.zoneMap or 0])
    for _, name in ipairs(around) do Note(name) end
    return keys
end

-- Whether any name around the camp has one of a feature's words in it.
local function HasFeature(around, words, anywhere)
    for _, name in ipairs(around) do
        for _, word in ipairs(words or {}) do
            if HasWord(name, word, anywhere) then return true end
        end
    end
    return false
end

-- The names on offer for a camp at location, by category:
-- { { title, entries = { { key, text }, ... } }, ... }. Empty categories are left out.
-- location may also have nearbyIDs (a set of area IDs) and zoneMap (the zone's map).
function Names:Options(location, skills)
    local categories, seen = {}, {}
    local function Category(title)
        local category = { title = title, entries = {} }
        categories[#categories + 1] = category
        return category
    end
    local function Add(category, key, text)
        if text and not seen[text] then
            seen[text] = true
            category.entries[#category.entries + 1] = { key = key, text = text }
        end
    end
    seen[self:Default(location) or ""] = true

    -- This location: names with the place in them, local specials, then
    -- features nearby (a lake, a hill...).
    local here = Category(L["This location"])
    for _, t in ipairs(TEMPLATES) do Add(here, "t:" .. t[1], self:Render("t:" .. t[1], location)) end

    local around = Around(location)
    for _, key in ipairs(SpecialsAround(location, around)) do
        for index, text in ipairs(SPECIALS[key]) do Add(here, format("l:%s:%d", key, index), L[text]) end
    end

    local localWords = FEATURE_WORDS[GetLocale()]
    for _, feature in ipairs(FEATURES) do
        if HasFeature(around, feature[3]) or (localWords and HasFeature(around, localWords[feature[1]], localWords.anywhere)) then
            Add(here, "f:" .. feature[1], L[feature[2]])
        end
    end

    local mine = Category(L["Your professions"])
    for _, profession in ipairs(ns.PROFESSIONS) do
        if (skills or {})[profession.id] then
            Add(mine, "p:" .. profession.id, PROFESSION_NAMES[profession.id] and L[PROFESSION_NAMES[profession.id]])
        end
    end

    for _, fixed in ipairs(FIXED) do
        local category = Category(L[fixed.title])
        for _, entry in ipairs(fixed.entries) do Add(category, "n:" .. entry[1], L[entry[2]]) end
    end

    local result = {}
    for _, category in ipairs(categories) do
        if #category.entries > 0 then result[#result + 1] = category end
    end
    return result
end
