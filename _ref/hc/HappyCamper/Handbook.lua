-- Happy Camper. Copyright (c) 2026 Torridon. All rights reserved; see LICENSE.
local _, ns = ...
local L = ns.L

-- The Handbook tab: every camp object and campfire kit in one place to browse
-- (design: research/2026-10-12-handbook-design.md). Professions down the left,
-- then Campfires; the chosen one's page on the right: what every tier gives,
-- the class buff with the same stat, then a card per tier: what it's for, how
-- to get it, its materials and your status. In both modes. Reference only:
-- nothing is sent. Materials, skills and recipe sources come from
-- HandbookData.lua (ns.HANDBOOK_DATA, by recipe spell ID); item names and
-- icons from the game, in your language.

local Handbook = {}
ns.Handbook = Handbook

local LIST_TOP = -30      -- the panels' top, under the page's title
local LIST_LEAST = 130    -- the list's width at least (it grows to fit its names)
local ENTRY_HEIGHT = 24
local ENTRY_ICON = 18
local SCROLLBAR = 14
local CARD_ICON = 32
local CARD_TEXT = CARD_ICON + 12  -- where a card's text starts, from its left
local MATERIAL_ICON = 16
local MATERIAL_ROW = 18
local COOKING = 185
local FIRE = "fire"        -- the Campfires entry
local GREEN, WHITE, GREY = { 0.4, 1, 0.4 }, { 1, 1, 1 }, { 0.6, 0.6, 0.6 }

-- What each tier's extras let you do, by profession and tier (the extras are
-- Data.lua's OBJECT_EXTRAS): one text each, shown on that tier's card. From
-- the objects' own descriptions (Wowhead's Forever database and camping guide,
-- 12 October 2026); check them in game with the dev tools' /hc handbookcheck.
Handbook.EXTRA_TEXT = {
    [171] = {
        [2] = "Alchemists at the camp can make certain reagents here; some Alchemy recipes need it.",
        [3] = "Works as an alchemy lab: alchemists at the camp can make the recipes that need one.",
    },
    [164] = {
        [2] = "A working anvil: blacksmiths at the camp can make the recipes that need one, without going back to town.",
        [3] = "Works as a forge: blacksmiths at the camp can make the recipes that need one.",
    },
    [333] = {
        [2] = "Makes disenchanting at the camp more efficient.",
        [3] = "Works as an arcane forge: enchanters at the camp can make the recipes that need one.",
    },
    [202] = {
        "A bot that sells reagents to anyone at the camp.",
        "A bot that sells reagents and repairs anyone's gear, like a town vendor.",
        "A workbench: engineers at the camp can make the recipes that need one.",
    },
    [182] = {
        [2] = "A herb garden: seeds planted in it grow into herbs over time.",
        [3] = "Multiplies seeds, or combines them into rarer kinds.",
    },
    [165] = {
        "Tops up your rested XP to 5% of a level.",
        "Tops up your rested XP, and leatherworkers at the camp can make certain reagents here.",
        "Tops up your rested XP, and works as a sewing machine for the Leatherworking recipes that need one.",
    },
    [186] = {
        [2] = "A common mining node appears in it over time.",
        [3] = "Works as a molten foundry for the recipes that need one.",
    },
    [393] = {
        [2] = "Anyone at the camp can read it to gain Track Beasts.",
        [3] = "Holds a trap.",
    },
    [197] = {
        [2] = "Tailors at the camp can make certain reagents here; some newer Tailoring recipes need it.",
        [3] = "Works as a loom: tailors at the camp can make the recipes that need one.",
    },
    [129] = {
        [2] = "Holds healing potions and anti-venom for anyone at the camp.",
        [3] = "Holds healing potions and poultices for anyone at the camp.",
    },
    [356] = {
        [2] = "For an hour you can catch uncommon fish, and it gives lures that raise your Fishing skill.",
        [3] = "For an hour you can catch rare fish, and it gives lures that raise your Fishing skill.",
    },
    [185] = {
        [2] = "Lays out food that boosts Stamina, for anyone at the camp. Needs a cooking fire nearby.",
        [3] = "Needed for the most advanced Cooking recipes. Needs a cooking fire nearby.",
    },
}

-- The kits' names until the game has loaded their items' (Basic, Journeyman,
-- Expert), and how many objects each one's fire holds.
Handbook.KITS = {
    { name = "Basic Campfire", slots = 3 },
    { name = "Journeyman Campfire", slots = 5 },
    { name = "Expert Campfire", slots = 10 },
}

ns.OnLocale(function()
    ns.LocalizeFields(Handbook.KITS, "name")
    for _, tiers in pairs(Handbook.EXTRA_TEXT) do
        for tier, text in pairs(tiers) do tiers[tier] = L[text] end
    end
end)

-- Data --------------------------------------------------------------------------------

-- A recipe's data (HandbookData.lua), or nil if it has none.
local function RecipeData(recipeID)
    local data = ns.HANDBOOK_DATA
    return data and data.recipes and data.recipes[recipeID]
end

-- The recipes of a profession's tier as a list, and the one shown: your
-- faction's where a tier has one per faction (Tailoring's Faction Banner).
local function TierRecipes(recipes, tier)
    local ids = ns.RecipeIDs(recipes, tier)
    local shown = ids[1]
    if #ids > 1 and UnitFactionGroup("player") == "Horde" then shown = ids[2] end
    return ids, shown
end

-- An item's name from the game, or nil until it has loaded (it's asked for:
-- the page is drawn again when it arrives).
local asked = {}
local function ItemName(itemID)
    if not itemID then return nil end
    local name = C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(itemID)
    if type(name) == "string" and name ~= "" then return name end
    if not asked[itemID] and C_Item and C_Item.RequestLoadItemDataByID then
        asked[itemID] = true
        pcall(C_Item.RequestLoadItemDataByID, itemID)
    end
end

local function ItemIcon(itemID)
    local icon = itemID and C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(itemID)
    return icon or 134400 -- the question mark
end

-- Whether a camp object (by profession and tier) is in your bags.
local function ObjectInBags(skillLine, tier)
    for _, entry in ipairs(ns.Widget:CampObjects()) do
        local key = ns.ObjectForSpell(entry.spell)
        local _, _, objectSkill, objectTier = ns.ObjectByName(key)
        if objectSkill == skillLine and objectTier == tier then return true end
    end
    return false
end

-- Your status for a recipe: its text and colour, or nil for a profession you
-- don't have. In your bags; you can make it (your own profession window has
-- shown the recipe learned: never guessed from your skill); no recipe yet (it
-- has shown it isn't); or, if that window hasn't been opened since Happy
-- Camper began keeping track, a hint to open it.
local function Status(skillLine, recipeIDs, inBags)
    if not ns.GetMyProfessions()[skillLine] then return nil end
    if inBags then return L["In your bags"], GREEN end
    local known = ns.charDB.campRecipes or {}
    for _, id in ipairs(recipeIDs) do
        if known[id] then return L["You can make it"], WHITE end
    end
    if (ns.charDB.campRecipesChecked or {})[skillLine] then return L["No recipe yet"], GREY end
    local profession = ns.PROFESSION_BY_ID[skillLine]
    -- (Its crafting window's name: Herbalism's is Gardening.)
    return format(L["Open your %s window once to check."], profession and (profession.window or profession.name) or "?"), GREY
end

-- "Skill 140 · Learned from Blueprint: Anvil", and the recipe item it names (for its tooltip).
local function HowText(data, skill)
    skill = data and data.skill or skill
    local source
    if data and data.recipeItem then
        source = format(L["Learned from %s"], ItemName(data.recipeItem) or L["a recipe"])
    elseif data and data.source == "trainer" then
        source = L["Taught by a trainer"]
    elseif data and data.source == "quest" then
        source = L["Taught on a quest"]
    elseif data and data.source == "both" then
        source = L["Taught by a trainer, or on a quest"]
    end
    if not skill then return source, data and data.recipeItem end
    return source and format(L["Skill %d · %s"], skill, source) or format(L["Skill %d"], skill), data and data.recipeItem
end

-- An NPC's name as this game client has it (its tooltip), once the game has
-- seen it; nil before that.
local function NpcName(npcID)
    local get = C_TooltipInfo and C_TooltipInfo.GetHyperlink
    if not get then return nil end
    local ok, data = pcall(get, format("unit:Creature-0-0-0-0-%d-0000000000", npcID))
    local line = ok and data and data.lines and data.lines[1]
    local name = line and line.leftText
    if type(name) == "string" and name ~= "" and not ns.IsSecret(name) then return name end
end

-- Who drops a recipe item, and where ("Dropped by Gilnid in The Deadmines.":
-- the game's names, in your language, where it has them), or that nobody
-- knows yet; nil for a recipe a trainer teaches.
local function FoundText(data)
    if not (data and data.recipeItem and data.foundIn) then return nil end
    if #data.foundIn == 0 then return L["Where it drops isn't known yet."] end
    local parts, areas, npcs = {}, ns.HANDBOOK_DATA.areas or {}, ns.HANDBOOK_DATA.npcs or {}
    for _, drop in ipairs(data.foundIn) do
        local areaID, npcID = drop[1], drop[2]
        local place = C_Map and C_Map.GetAreaInfo and C_Map.GetAreaInfo(areaID)
        place = (type(place) == "string" and place ~= "") and place or areas[areaID] or "?"
        local who = npcID and (NpcName(npcID) or npcs[npcID])
        parts[#parts + 1] = who and format(L["%s in %s"], who, place) or place
    end
    return format(L["Dropped by %s."], ns.JoinList(parts))
end

-- What every tier of a profession's objects gives, at your level ("Every tier
-- gives +20 Strength at your level."); a service's detail.
local function GivesText(profession)
    if not ns.STAT_BUFF[profession.id] then return profession.detail end
    local level = ns.KnownLevel("player")
    local text, top = ns.BuffText(profession, level), ns.BuffTopLevel(profession)
    if top and level and level < top then text = format(L["%s at your level"], text) end
    return format(L["Every tier gives %s."], text)
end

-- The class buff that gives the same stat, and that they don't stack; nil if none.
local function SameStatText(profession)
    if not profession.conflicts then return nil end
    local info = ns.CLASS_BUFFS and ns.CLASS_BUFFS[profession.id]
    local className = info and LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[info.class]
    if not className then return format(L["Same stat as %s: they don't stack."], profession.conflicts) end
    if info.talent then
        return format(L["Same stat as %s (a %s talent): they don't stack."], profession.conflicts, className)
    end
    return format(L["Same stat as %s (from a %s): they don't stack."], profession.conflicts, className)
end

-- The entries down the left: the professions in their usual order, then Campfires.
local function Entries()
    local list = {}
    for _, profession in ipairs(ns.PROFESSIONS) do
        list[#list + 1] = { key = profession.id, name = profession.name, icon = profession.icon, profession = profession }
    end
    list[#list + 1] = { key = FIRE, name = L["Campfires"], icon = "Interface\\Icons\\Spell_Fire_Fire" }
    return list
end

-- The cards for an entry: { title, icon, item, status, statusColor, lines =
-- { { text, colour }, ... }, how, howItem, materials = { { itemID, count }, ... },
-- tools = { itemID, ... } (not used up), makes (how many one craft makes) }.
function Handbook:Cards(key)
    local cards = {}
    if key == FIRE then
        local cooking = ns.PROFESSION_BY_ID[COOKING]
        local kitsInBags = ns.Widget.KitsInBags and ns.Widget:KitsInBags() or {}
        for tier, kit in ipairs(self.KITS) do
            local recipeID = ns.KIT_RECIPES[tier]
            local data = RecipeData(recipeID)
            local how, howItem = HowText(data, ns.KIT_SKILL[tier])
            local status, color = Status(COOKING, { recipeID }, kitsInBags[kit.slots])
            local lines = { { format(L["Its fire holds %d objects."], kit.slots), WHITE } }
            if data and data.useSkill then
                lines[#lines + 1] = { format(L["Needs %s %d to place it."], cooking.name, data.useSkill), WHITE }
            end
            cards[#cards + 1] = {
                title = data and ItemName(data.item) or kit.name, tier = tier,
                icon = data and data.item and ItemIcon(data.item) or "Interface\\Icons\\Spell_Fire_Fire", item = data and data.item,
                status = status, statusColor = color, lines = lines,
                how = how, howItem = howItem, found = FoundText(data), materials = data and data.reagents or {},
                tools = data and data.tools or {}, makes = data and data.makes,
            }
        end
        -- A sleeping bag: not a camp object, but for resting at camp.
        local bag = ns.Supplies.SLEEPING_BAGS[1]
        local inBags = ns.Supplies:SleepingBag() ~= nil
        cards[#cards + 1] = {
            title = ItemName(bag) or L["Cozy Sleeping Bag"], icon = ItemIcon(bag), item = bag,
            status = inBags and L["In your bags"] or nil, statusColor = GREEN,
            lines = { { L["Gives Well-Rested, up to 3 stacks (hover it for what they do). The Campsite Assistant shows them on its sleeping bag slot."], WHITE } },
            materials = {}, tools = {},
        }
        return cards, cooking
    end
    local profession = ns.PROFESSION_BY_ID[key]
    for tier = 1, 3 do
        if profession.objects[tier] then
            local recipeIDs, shown = TierRecipes(profession.recipes, tier)
            local data = RecipeData(shown)
            local how, howItem = HowText(data, ns.RECIPE_SKILL[tier])
            local status, color = Status(profession.id, recipeIDs, ObjectInBags(profession.id, tier))
            local lines = {}
            local extra = self.EXTRA_TEXT[profession.id] and self.EXTRA_TEXT[profession.id][tier]
            if extra then lines[#lines + 1] = { extra, WHITE } end
            cards[#cards + 1] = {
                title = ns.ObjectName(profession.id, tier), tier = tier,
                icon = profession.objectIcons[tier] or profession.icon, item = data and data.item,
                status = status, statusColor = color, lines = lines,
                how = how, howItem = howItem, found = FoundText(data), materials = data and data.reagents or {},
                tools = data and data.tools or {}, makes = data and data.makes,
            }
        end
    end
    return cards, profession
end

-- The page ----------------------------------------------------------------------------

local function ItemTooltip(frame)
    frame:SetScript("OnEnter", function(self)
        if not self.itemID then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetItemByID(self.itemID)
        GameTooltip:Show()
    end)
    frame:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

local function NewCard(content)
    local style = ns.Style
    local card = CreateFrame("Frame", nil, content)
    card.rule = card:CreateTexture(nil, "ARTWORK")
    card.rule:SetColorTexture(1, 0.82, 0.4, 0.2)
    card.rule:SetHeight(1)
    card.rule:SetPoint("TOPLEFT", 4, 0)
    card.rule:SetPoint("TOPRIGHT", -4, 0)
    card.iconButton = CreateFrame("Button", nil, card)
    card.iconButton:SetSize(CARD_ICON, CARD_ICON)
    card.icon = card.iconButton:CreateTexture(nil, "ARTWORK")
    card.icon:SetAllPoints()
    card.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    ItemTooltip(card.iconButton)
    card.title = style:Text(card, "GameFontNormal", nil, "LEFT")
    card.status = style:Text(card, "GameFontHighlightSmall", nil, "LEFT")
    card.lines = {}
    card.how = CreateFrame("Button", nil, card)
    card.how.text = style:Text(card.how, "GameFontDisableSmall", nil, "LEFT")
    card.how.text:SetPoint("TOPLEFT")
    ItemTooltip(card.how)
    card.found = style:Text(card, "GameFontDisableSmall", nil, "LEFT")
    card.heading = style:Text(card, "GameFontNormalSmall", L["Materials"], "LEFT")
    card.materials = {}
    return card
end

local function Material(card, i)
    local row = card.materials[i]
    if not row then
        row = CreateFrame("Button", nil, card)
        row:SetHeight(MATERIAL_ROW)
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(MATERIAL_ICON, MATERIAL_ICON)
        row.icon:SetPoint("LEFT")
        row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        row.text = ns.Style:Text(row, "GameFontHighlightSmall", nil, "LEFT")
        row.text:SetPoint("LEFT", MATERIAL_ICON + 6, 0)
        ItemTooltip(row)
        card.materials[i] = row
    end
    return row
end

local function CardLine(card, i)
    card.lines[i] = card.lines[i] or ns.Style:Text(card, "GameFontHighlightSmall", nil, "LEFT")
    return card.lines[i]
end

function Handbook:Build(page)
    local window = page:GetParent()
    local style = ns.Style
    page.title = style:PageTitle(page)

    -- The list down the left, as wide as its longest name needs.
    local entries = Entries()
    local measure = style:Text(page, "GameFontHighlightSmall", nil, "LEFT")
    local listWidth = LIST_LEAST
    for _, entry in ipairs(entries) do
        measure:SetText(entry.name)
        listWidth = math.max(listWidth, ns.Style:TextWidth(measure) + ENTRY_ICON + 26)
    end
    measure:Hide()
    local listInset = style:Inset(page, window, 10, LIST_TOP, 10, LIST_TOP)
    listInset:ClearAllPoints()
    listInset:SetPoint("TOPLEFT", page, "TOPLEFT", 10, LIST_TOP)
    listInset:SetPoint("BOTTOMLEFT", page, "BOTTOMLEFT", 10, 4)
    listInset:SetWidth(listWidth)
    page.entries = {}
    for i, entry in ipairs(entries) do
        local button = CreateFrame("Button", nil, page)
        button:SetSize(listWidth - 8, ENTRY_HEIGHT)
        button:SetPoint("TOPLEFT", page, "TOPLEFT", 14, LIST_TOP - 6 - (i - 1) * ENTRY_HEIGHT)
        button:SetFrameLevel(window:GetFrameLevel() + 4)
        button.entry = entry
        button.selected = button:CreateTexture(nil, "BACKGROUND")
        button.selected:SetAllPoints()
        button.selected:SetColorTexture(1, 0.82, 0, 0.18)
        button:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
        button.icon = button:CreateTexture(nil, "ARTWORK")
        button.icon:SetSize(ENTRY_ICON, ENTRY_ICON)
        button.icon:SetPoint("LEFT", 4, 0)
        button.icon:SetTexture(entry.icon)
        button.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        button.label = style:Text(button, "GameFontHighlightSmall", entry.name, "LEFT")
        button.label:SetPoint("LEFT", ENTRY_ICON + 10, 0)
        button.label:SetWordWrap(false)
        button:SetScript("OnClick", function() Handbook:Choose(entry.key) end)
        page.entries[i] = button
    end

    -- The chosen page on the right, scrolling.
    local left = 10 + listWidth + 8
    local inset = style:Inset(page, window, left, LIST_TOP, 10, LIST_TOP)
    inset:ClearAllPoints()
    inset:SetPoint("TOPLEFT", page, "TOPLEFT", left, LIST_TOP)
    inset:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", -10, 4)
    local scroll = CreateFrame("ScrollFrame", nil, page)
    scroll:SetPoint("TOPLEFT", page, "TOPLEFT", left + 6, LIST_TOP - 6)
    scroll:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", -16, 10)
    scroll:SetFrameLevel(window:GetFrameLevel() + 4)
    local width = window:GetWidth() - left - 10 - 12 - SCROLLBAR
    style:ScrollArea(scroll, width, 1)
    page.scroll, page.content, page.width = scroll, scroll.child, width
    page.header = style:Text(page.content, "GameFontHighlight", nil, "LEFT")
    page.sameStat = style:Text(page.content, "GameFontHighlightSmall", nil, "LEFT")
    page.sameStat:SetTextColor(1, 0.5, 0.5)
    page.cards = {}
    self.page = page
end

-- Shows an entry (a profession's ID, or "fire"); it's remembered for next time.
function Handbook:Choose(key)
    ns.db.handbookEntry = key
    if self.page and self.page.scroll.SetVerticalScroll then self.page.scroll:SetVerticalScroll(0) end
    self:Refresh()
end

-- The entry shown: the last one chosen, else your first profession, else Alchemy.
function Handbook:Current()
    local key = ns.db.handbookEntry
    if key == FIRE or ns.PROFESSION_BY_ID[key] then return key end
    local mine = ns.GetMyProfessions()
    for _, profession in ipairs(ns.PROFESSIONS) do
        if mine[profession.id] then return profession.id end
    end
    return ns.PROFESSIONS[1].id
end

-- Places a card's parts and returns its height.
local function LayoutCard(card, spec, width)
    local textWidth = width - CARD_TEXT - 4
    local y = -10
    card.iconButton:ClearAllPoints()
    card.iconButton:SetPoint("TOPLEFT", card, "TOPLEFT", 4, y)
    card.iconButton.itemID = spec.item
    card.icon:SetTexture(spec.icon)
    card.title:SetWidth(textWidth)
    -- (A card with no tier, the sleeping bag, has just its name.)
    card.title:SetText(spec.tier and format("%s  |cff999999%s|r", spec.title or "?", format(L["T%d"], spec.tier)) or spec.title or "?")
    card.title:ClearAllPoints()
    card.title:SetPoint("TOPLEFT", card, "TOPLEFT", CARD_TEXT, y)
    y = y - ns.Style:TextHeight(card.title, 14) - 3
    card.status:SetShown(spec.status ~= nil)
    if spec.status then
        card.status:SetWidth(textWidth)
        card.status:SetText(spec.status)
        card.status:SetTextColor(unpack(spec.statusColor))
        card.status:ClearAllPoints()
        card.status:SetPoint("TOPLEFT", card, "TOPLEFT", CARD_TEXT, y)
        y = y - ns.Style:TextHeight(card.status, 12) - 4
    end
    for i, line in ipairs(spec.lines) do
        local text = CardLine(card, i)
        text:Show()
        text:SetWidth(textWidth)
        text:SetText(line[1])
        text:SetTextColor(unpack(line[2]))
        text:ClearAllPoints()
        text:SetPoint("TOPLEFT", card, "TOPLEFT", CARD_TEXT, y)
        y = y - ns.Style:TextHeight(text, 12) - 4
    end
    for i = #spec.lines + 1, #card.lines do card.lines[i]:Hide() end
    y = math.min(y, -10 - CARD_ICON - 6)
    card.how:SetShown(spec.how ~= nil)
    if spec.how then
        card.how.itemID = spec.howItem
        card.how.text:SetWidth(textWidth)
        card.how.text:SetText(spec.how)
        local height = ns.Style:TextHeight(card.how.text, 12)
        card.how:SetSize(textWidth, height)
        card.how:ClearAllPoints()
        card.how:SetPoint("TOPLEFT", card, "TOPLEFT", CARD_TEXT, y)
        y = y - height - (spec.found and 2 or 6)
    end
    -- Where its recipe item drops, under how it's learned.
    card.found:SetShown(spec.found ~= nil)
    if spec.found then
        card.found:SetWidth(textWidth)
        card.found:SetText(spec.found)
        card.found:ClearAllPoints()
        card.found:SetPoint("TOPLEFT", card, "TOPLEFT", CARD_TEXT, y)
        y = y - ns.Style:TextHeight(card.found, 12) - 6
    end
    -- The materials, then any tools (needed, not used up): one row each.
    local rows = {}
    for _, reagent in ipairs(spec.materials) do
        rows[#rows + 1] = { reagent[1], format(L["%d× %s"], reagent[2], ItemName(reagent[1]) or L["(loading)"]) }
    end
    for _, itemID in ipairs(spec.tools or {}) do
        rows[#rows + 1] = { itemID, format(L["%s (a tool, not used up)"], ItemName(itemID) or L["(loading)"]) }
    end
    card.heading:SetShown(#rows > 0)
    if #rows > 0 then
        card.heading:SetText(spec.makes and spec.makes > 1 and format(L["Materials (makes %d)"], spec.makes) or L["Materials"])
        card.heading:SetWidth(textWidth)
        card.heading:ClearAllPoints()
        card.heading:SetPoint("TOPLEFT", card, "TOPLEFT", CARD_TEXT, y)
        y = y - ns.Style:TextHeight(card.heading, 12) - 3
    end
    for i, info in ipairs(rows) do
        local row = Material(card, i)
        row.itemID = info[1]
        row.icon:SetTexture(ItemIcon(info[1]))
        row.text:SetWidth(textWidth - MATERIAL_ICON - 6)
        row.text:SetText(info[2])
        -- A long name (or translation) wraps onto a second line rather than being cut off.
        local height = math.max(MATERIAL_ROW, ns.Style:TextHeight(row.text, 12) + 4)
        row:SetSize(textWidth, height)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", card, "TOPLEFT", CARD_TEXT, y)
        row:Show()
        y = y - height
    end
    for i = #rows + 1, #card.materials do card.materials[i]:Hide() end
    return -y + 10
end

function Handbook:Refresh()
    local page = self.page
    if not page then return end
    local key = self:Current()
    for _, button in ipairs(page.entries) do
        local chosen = button.entry.key == key
        button.selected:SetShown(chosen)
        if chosen then button.label:SetTextColor(1, 0.82, 0) else button.label:SetTextColor(1, 1, 1) end
    end
    local cards, profession = self:Cards(key)
    page.title:SetText(key == FIRE and L["Campfires"] or profession.name)

    local width, y = page.width, -6
    page.header:ClearAllPoints()
    page.header:SetPoint("TOPLEFT", page.content, "TOPLEFT", 4, y)
    page.header:SetWidth(width - 8)
    local header = key == FIRE
        and L["Cooking makes the campfires. A camp object stands for 15 minutes, and placing one starts an hour's cooldown for all of yours. Only a burning fire gives camp buffs."]
        or GivesText(profession) or ""
    -- A gathering profession crafts in a window of its own name (Gardening...).
    if key ~= FIRE and profession.window then
        header = header .. "\n" .. format(L["Its camp objects are made in your %s window."], profession.window)
    end
    page.header:SetText(header)
    y = y - ns.Style:TextHeight(page.header, 14) - 4
    local same = key ~= FIRE and SameStatText(profession)
    page.sameStat:SetShown(same ~= nil and same ~= false)
    if same then
        page.sameStat:ClearAllPoints()
        page.sameStat:SetPoint("TOPLEFT", page.content, "TOPLEFT", 4, y)
        page.sameStat:SetWidth(width - 8)
        page.sameStat:SetText(same)
        y = y - ns.Style:TextHeight(page.sameStat, 12) - 4
    end
    y = y - 6
    for i, spec in ipairs(cards) do
        local card = page.cards[i] or NewCard(page.content)
        page.cards[i] = card
        card:Show()
        card:ClearAllPoints()
        card:SetPoint("TOPLEFT", page.content, "TOPLEFT", 0, y)
        local height = LayoutCard(card, spec, width)
        card:SetSize(width, height)
        y = y - height
    end
    for i = #cards + 1, #page.cards do page.cards[i]:Hide() end
    page.content:SetHeight(-y + 8)
end

-- Drawn again (soon, once for several at a time) when what it shows may have
-- changed: your bags, skills or recipes, or an item's name arriving.
local pending = false
local function Later()
    if pending then return end
    pending = true
    C_Timer.After(0.2, function()
        pending = false
        local page = Handbook.page
        if page and page:IsVisible() then Handbook:Refresh() end
    end)
end
local events = CreateFrame("Frame")
for _, event in ipairs({ "BAG_UPDATE_DELAYED", "SKILL_LINES_CHANGED", "ITEM_DATA_LOAD_RESULT", "TRADE_SKILL_LIST_UPDATE" }) do
    pcall(events.RegisterEvent, events, event)
end
events:SetScript("OnEvent", Later)
