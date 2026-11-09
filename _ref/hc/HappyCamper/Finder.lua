-- Happy Camper. Copyright (c) 2026 Torridon. All rights reserved; see LICENSE.
local _, ns = ...
local L = ns.L

-- Camp Builder tab, laid out like the Group tab (Style's planning pieces): a
-- title, quick picks, the fire as a figure along the top, then a panel with a
-- row per camp buff (its mark, icon, buff and profession, Request, and Camp
-- Setup as a pill; rows with nothing to do dimmed).
--   Build a camp   tick the buffs you'd like and their lowest tier, or ask for a
--                  buff's class buff instead (Power Word: Fortitude for Stamina),
--                  which takes no slot at the fire. Camp Setup shows what you're
--                  bringing, filled in from your bags (one camp object, since
--                  they share an hour's cooldown, and your campfire kit), and the
--                  class buffs you give. Then a meet-up.
--   Your request   the same rows, read-only: how the camp will look, with who
--                  has signed up to bring each buff, or give it with a class buff.
-- Below: other players' requests in your zone, each with its buffs as icons
-- (lit once someone's bringing or giving it), and Whisper, Map and Join (with
-- a camp object, your class buffs, or both).

local Finder = {}
ns.Finder = Finder

local WIDTH = 500
local PAD = 16
local PLAN = ns.Style.PLAN  -- rows, columns and tiles, as on the Group tab
local STATES = ns.Style.PLAN_STATES
local TOP_Y = -22           -- the quick picks (or your request's meet-up line)
local FIRE_Y = -52          -- the fire, as a figure
local PANEL_Y = FIRE_Y - PLAN.TILE_HEIGHT - PLAN.GAP -- the camp buffs' panel
local ROW_HEIGHT = PLAN.ROW_HEIGHT
local WANT_X = PLAN.MID_X   -- the Request column: its tick box and lowest tier
local SETUP_X = PLAN.SETUP_X
local TIER_WIDTH = PLAN.MID_WIDTH - 22 -- the lowest tier's menu, after the tick box
local PANEL_HEIGHT = PLAN.LIST_TOP + #ns.PROFESSIONS * ROW_HEIGHT + PLAN.INNER
local BELOW_Y = PANEL_Y - PANEL_HEIGHT - PLAN.GAP -- under the panel: Meet at and Post, or your request's buttons
local PRESET_WIDTH = 90     -- Melee, Caster, Balanced
local REQUEST_HEIGHT = 42   -- a request in the list: its name, then its buff icons below
local LIST_ROWS = 3         -- requests shown at once; more scroll
local ROW_BUTTON_WIDTH = 70 -- Whisper, Map and Join on each request: one width, at least this
local MINI = 14             -- a request's buff icons
local MINI_GAP = 2
local SCROLLBAR_SPACE = 12
local COOKING = 185         -- its row is the campfire itself (Campfire)
local FIRE_HOLDS = { 3, 5, 10 } -- objects a campfire of each tier holds
local CAMPFIRE_KITS = { 279981, 279961, 279974 } -- Basic, Journeyman and Expert campfire kits
local GREY, GREEN, WHITE, ORANGE = "|cffaaaaaa", "|cff66ff66", "|cffffffff", "|cffff9933"
local AZURE = "|cff3399ff"  -- a camp buff a class buff gives (as on the Group tab)
-- Whisper, Map and Join (or Leave) on a request: one width, the widest label's
-- (Finder:Build measures them), and the room the three take at the row's right.
local rowButtonWidth = ROW_BUTTON_WIDTH
local buttonsWidth = 3 * ROW_BUTTON_WIDTH + 2 * 6 + 10

local function ShortName(name)
    return Ambiguate(name, "short")
end

-- "Name T2", as on the Group tab.
local function Tiered(text, tier)
    return ns.Group.Tiered(text, tier)
end

local function FireHolds(tier)
    return FIRE_HOLDS[tier] or FIRE_HOLDS[1]
end

-- "Bram Stone (Blacksmithing T2, Power Word: Fortitude)": who's coming, with
-- the object they bring and the class buffs they give.
local function HelperList(request)
    local names = {}
    for name, skillLine in pairs(request.helpers) do
        local what = {}
        if skillLine ~= 0 and ns.PROFESSION_BY_ID[skillLine] then
            local tier = (request.helperTiers or {})[name]
            what[1] = ns.PROFESSION_BY_ID[skillLine].name
            if tier then what[1] = format("%s %s", what[1], ns.Requests:TierText(tier)) end
        end
        for _, profession in ipairs(ns.PROFESSIONS) do
            if ((request.helperBuffs or {})[name] or {})[profession.id] then
                what[#what + 1] = ns.Requests:BuffName(profession.id)
            end
        end
        names[#names + 1] = format("%s (%s)", ShortName(name), table.concat(what, ", "))
    end
    table.sort(names)
    return names
end

-- clickHint: the request is a map pin, which opens the Camp Builder when clicked.
function Finder:FillRequestTooltip(tooltip, request, clickHint)
    local R = ns.Requests
    tooltip:AddLine(format(L["%s's camp request"], ShortName(request.creator)), 0.5, 0.8, 1)
    tooltip:AddLine(format(L["Wants: %s"], R:WantedNames(request)), 1, 1, 1, true)
    local brings = R:BroughtNames(request)
    if brings then tooltip:AddLine(format(L["Brings: %s"], brings), 0.7, 0.7, 0.7, true) end
    tooltip:AddDoubleLine(L["Meet-up"], R:PlaceText(request), 1, 1, 1, 1, 1, 1)
    local distance = ns.Camps:DistanceFromPlayer(request)
    if distance then
        tooltip:AddDoubleLine(L["Distance"], format(L["%d yards"], distance), 1, 1, 1, 1, 1, 1)
    end
    tooltip:AddDoubleLine(L["Closes in"], ns.FormatTime(R:TimeLeft(request)), 1, 1, 1, 1, 1, 1)
    local helpers = HelperList(request)
    if #helpers > 0 then
        tooltip:AddLine(" ")
        tooltip:AddLine(format(L["Coming: %s"], table.concat(helpers, ", ")), 0.4, 1, 0.4, true)
    end
    if clickHint and ns.Style:ShowHelp() then
        tooltip:AddLine(" ")
        ns.Style:AddHint(tooltip, L["Click to open the Camp Builder"])
    end
end

local function CreateCheck(parent, text)
    local check = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    check:SetSize(22, 22)
    check.Text:SetText(text)
    return check
end

local function Text(parent, font, text, x, y, justify)
    local label = ns.Style:Text(parent, font, text, justify)
    label:SetPoint("TOPLEFT", x, y)
    return label
end

-- The top of the tab: the composer, or your own request.
local function TopPanel(f)
    local panel = CreateFrame("Frame", nil, f)
    panel:SetPoint("TOPLEFT", 0, 0)
    panel:SetSize(WIDTH, -BELOW_Y + 24)
    return panel
end

-- The fire, as a figure: how many of its slots are taken, of how many, and
-- the fire line under it (the composer's or your request's); hover for it
-- in full.
local function FireTile(panel)
    local tile = ns.Style:Tile(panel, WIDTH - 2 * PAD)
    tile:SetPoint("TOPLEFT", PAD, FIRE_Y)
    tile.label:SetText(L["Fire slots"])
    tile.tipTitle = L["Fire slots"]
    return tile
end

-- The figure's number, orange when the fire would be too full.
local function SetFireFigure(tile, taken, holds, line)
    tile.big:SetText(format(taken > holds and (ORANGE .. "%d/%d|r") or "%d/%d", taken, holds))
    tile.tipLines = { line }
end

-- Shows an item's name on a menu; if it's too long, its first words go
-- ("Laboratory (T3)"). Hovering shows it in full.
local function FitMenuText(menu, text)
    local label = menu.label
    label:SetText(text)
    while label:IsTruncated() do
        local rest = text:match("^%S+%s+(.+)$")
        if not rest then return end
        text = rest
        label:SetText(text)
    end
end

-- The camp buffs' panel, with its headings where the Group tab has them.
local function PlanPanel(panel, want)
    local plan = ns.Style:Panel(panel)
    plan:SetPoint("TOPLEFT", PAD, PANEL_Y)
    plan:SetPoint("TOPRIGHT", -PAD, PANEL_Y)
    plan:SetHeight(PANEL_HEIGHT)
    ns.Style:Headings(plan, { { L["Camp buff"], PLAN.BUFF_X }, { want, WANT_X }, { L["Camp Setup"], SETUP_X } })
    return plan
end

-- A camp buff's row: its mark, icon, buff and profession, then the columns
-- filled in by the composer or your request; Camp Setup is a pill. Hover it
-- for the buff and its objects.
local function BuffRow(panel, profession, y)
    local style = ns.Style
    local row = style:PlanRow(panel, profession, y)
    row.pill = style:Pill(row)
    row.pill:SetPoint("LEFT", SETUP_X, 0)
    row.setup = row.pill.text
    style:CustomTooltip(row, "ANCHOR_RIGHT", function(tooltip, self)
        ns.AddProfessionTooltip(tooltip, profession)
        if self.coming then
            tooltip:AddLine(" ")
            tooltip:AddLine(format(L["Coming: %s"], self.coming), 0.4, 1, 0.4, true)
        end
    end)
    return row
end

-- The ways you can sign up to a request (Requests:HelpOptions): one camp
-- object at most (they share an hour's cooldown), with every class buff of
-- yours it wants but one blessing at most (a paladin gives each player one),
-- and never two for one stat. { { object = option or nil, buffs = { options } } },
-- objects first.
local function SignUpChoices(options)
    local objects, blessings, buffs = {}, {}, {}
    for _, option in ipairs(options) do
        if not option.buff then
            objects[#objects + 1] = option
        elseif option.blessing then
            blessings[#blessings + 1] = option
        else
            buffs[#buffs + 1] = option
        end
    end
    local choices = {}
    for i = 1, #objects + 1 do
        local object = objects[i] -- the last time round: no object
        local with = {}
        for _, buff in ipairs(buffs) do
            if not (object and object.id == buff.id) then with[#with + 1] = buff end
        end
        local blessed = 0
        for _, blessing in ipairs(blessings) do
            if not (object and object.id == blessing.id) then
                local list = { unpack(with) }
                list[#list + 1] = blessing
                choices[#choices + 1] = { object = object, buffs = list }
                blessed = blessed + 1
            end
        end
        if blessed == 0 and (object or #with > 0) then choices[#choices + 1] = { object = object, buffs = with } end
    end
    return choices
end

-- "Blacksmithing and Power Word: Fortitude"
local function ChoiceLabel(choice)
    local names = {}
    if choice.object then names[1] = choice.object.name end
    for _, buff in ipairs(choice.buffs) do names[#names + 1] = buff.name end
    return ns.JoinList(names)
end

-- Signs up, asking which object and class buffs to bring when there's a choice.
local function Join(request, options, owner)
    local choices = SignUpChoices(options)
    if #choices == 0 then return end
    local function SignUp(choice)
        local buffs = {}
        for _, buff in ipairs(choice.buffs) do buffs[buff.id] = true end
        ns.Requests:SignUp(request, choice.object and choice.object.id, buffs)
        Finder:Refresh()
    end
    if #choices == 1 then return SignUp(choices[1]) end
    local objectsOnly = true
    for _, choice in ipairs(choices) do
        if #choice.buffs > 0 then objectsOnly = false end
    end
    local opened = ns.Menu:Context(owner, function(_, root)
        root:CreateTitle(objectsOnly and L["Bring which profession?"] or L["Sign up with:"])
        for _, choice in ipairs(choices) do
            root:CreateButton(ChoiceLabel(choice), function() SignUp(choice) end)
        end
    end)
    if not opened then SignUp(choices[1]) end
end

-- The camp object you're bringing: one, since camp objects share an hour's
-- cooldown. Your pick (false: none), else the one in your bags.
local function PickedObject(composer, options)
    if composer.objectPick ~= nil then return composer.objectPick or nil end
    for _, option in ipairs(options) do
        if not option.kit and option.carried then return option.skillLine end
    end
end

-- Whether you're bringing something: your campfire kit (your pick, else: it's
-- in your bags), or the camp object you picked.
local function Bringing(composer, option, options)
    if option.kit then
        if composer.kitPick ~= nil then return composer.kitPick end
        return option.carried == true
    end
    return PickedObject(composer, options) == option.skillLine
end

-- Class buffs that cover a camp buff for the whole group (not a paladin's
-- blessings, which are one per player). It can still be asked for, at any
-- tier (someone may want the workspace or service), but the quick picks leave
-- it out.
local function GroupBuffs()
    local covered = {}
    for _, entry in ipairs(ns.Requests:ClassBuffs()) do
        if not entry.blessing then covered[entry.skillLine] = true end
    end
    return covered
end

-- Whether a buff can be asked for as a class buff (ns.CLASS_BUFFS) instead
-- of its object: not one your own class buffs give everyone already (covered:
-- GroupBuffs, if already looked up).
local function HasClassOption(skillLine, covered)
    return ns.CLASS_BUFFS[skillLine] ~= nil and not (covered or GroupBuffs())[skillLine]
end

local function PostRequest(composer)
    -- Tidies the ticks first (what you bring can't be asked for too).
    Finder:RefreshComposer()
    local options = ns.Requests:BringOptions()
    local brings, buffs = {}, {}
    for _, option in ipairs(options) do
        if Bringing(composer, option, options) then brings[option.skillLine] = option.tier end
    end
    for _, entry in ipairs(ns.Requests:ClassBuffs()) do buffs[entry.skillLine] = true end
    local wants, minTier, classWants = {}, {}, {}
    for _, check in ipairs(composer.checks) do
        local id = check.profession.id
        local tier = math.max(composer.minTier[id] or 1, check.low or 1)
        if check:GetChecked() and composer.wantBuff[id] then
            wants[id], classWants[id] = true, true -- asked for as a class buff: no fire slot
        elseif check:GetChecked() and (brings[id] or 0) < tier then
            wants[id] = true
            if tier > 1 then minTier[id] = tier end
        end
    end
    if not next(wants) then
        ns.Print(L["Pick at least one profession to ask for."])
        return
    end
    -- More than the fire holds (it got smaller after they were ticked). Class
    -- buffs take no slot.
    if composer.asking > composer.room then
        ns.Print(format(L["Too many for the fire, which holds %d objects: untick %d."], composer.holds, composer.asking - composer.room))
        return
    end

    local mapID, x, y
    if composer.usePin:GetChecked() then
        if not C_Map.HasUserWaypoint() then
            ns.Print(L["You don't have a map pin. Place one on the world map, or meet where you're standing."])
            return
        end
        local point = C_Map.GetUserWaypoint()
        mapID = point and point.uiMapID
        x, y = ns.XY(point and point.position)
        if not (mapID and x and y) then
            ns.Print(L["Couldn't read your map pin's position. Try placing it again."])
            return
        end
    else
        mapID, x, y = ns.GetPlayerLocation()
        if not mapID then
            ns.Print(L["Your location isn't available here."])
            return
        end
    end
    -- Everyone else drops a meet-up on a continent's or a dungeon's map.
    if not ns.IsOutdoorMap(mapID) then
        ns.Print(L["Meet-ups must be on a zone map, not a continent or dungeon map."])
        return
    end
    ns.Requests:Post(wants, mapID, x, y, minTier, brings, buffs, classWants)
    Finder:Refresh()
end

-- A requested tier, the lowest taken: "T1+", "T2+" or "T3".
local function TierLabel(tier)
    return ns.Requests:TierText(tier, tier < 3)
end

-- A camp buff's item at a tier, by the game's own name: its camp object, or
-- for Cooking (a bigger fire) the campfire kit.
local function ItemName(profession, tier)
    if profession.id == COOKING then
        local name = C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(CAMPFIRE_KITS[tier])
        return type(name) == "string" and name ~= "" and name or format(L["Campfire (holds %d)"], FireHolds(tier))
    end
    return ns.ObjectName(profession.id, tier) or profession.buff
end

-- "Mana Well (T1+)", "Fermenter (T2+)", "Alchemy Laboratory (T3)": the
-- Request menu's choices, each the lowest tier taken.
local function RequestLabel(profession, tier)
    return format("%s (%s)", ItemName(profession, tier), TierLabel(tier))
end

-- The spell an item casts when used: placing its camp object, or for Cooking
-- the campfire kit's fire.
local function ItemSpell(profession, tier)
    if profession.id == COOKING then
        local get = C_Item and C_Item.GetItemSpell
        if not get then return end
        local _, spellID = get(CAMPFIRE_KITS[tier])
        return spellID
    end
    local spells = (profession.objectSpells or {})[tier]
    if type(spells) ~= "table" then return spells end
    -- The Alliance and Horde Faction Banners: your side's (its text names it).
    return UnitFactionGroup("player") == "Horde" and spells[2] or spells[1]
end

-- The game's own description of an item (its "Use:" text, as the profession
-- window shows it), in the client's language; nil until the game has it.
local function ItemDescription(profession, tier)
    local spellID = ItemSpell(profession, tier)
    local get = C_Spell and C_Spell.GetSpellDescription
    local text = spellID and get and get(spellID)
    return type(text) == "string" and text ~= "" and text or nil
end

-- A class buff's spell (its first rank), for its description and icon.
local function ClassBuffSpell(skillLine)
    return ns.CLASS_BUFFS[skillLine] and (ns.PROFESSION_BY_ID[skillLine].conflictSpells or {})[1]
end

-- Asks the game to load the items' and class buffs' descriptions, so tooltips have them.
local function LoadDescriptions()
    local load = C_Spell and C_Spell.RequestLoadSpellData
    if not load then return end
    for _, profession in ipairs(ns.PROFESSIONS) do
        for tier = 1, 3 do
            local spellID = ItemSpell(profession, tier)
            if spellID then load(spellID) end
        end
        if ClassBuffSpell(profession.id) then load(ClassBuffSpell(profession.id)) end
    end
end

-- A class buff's icon (the spell's), or its camp buff's.
local function ClassBuffIcon(profession)
    local get = C_Spell and C_Spell.GetSpellTexture
    local icon = ClassBuffSpell(profession.id) and get and get(ClassBuffSpell(profession.id))
    return (type(icon) == "number" or type(icon) == "string") and icon or profession.icon
end

-- A class buff offered instead of an object: what it is, the game's own
-- description of it, and whether it needs a party or a talent.
local function ClassBuffTooltip(tooltip, profession)
    local entry = ns.CLASS_BUFFS[profession.id]
    tooltip:SetText(ns.Requests:ClassBuffLabel(profession.id))
    tooltip:AddLine(format(L["A class buff for %s: it takes no slot at the fire."], profession.buff), 1, 1, 1, true)
    local get = C_Spell and C_Spell.GetSpellDescription
    local description = get and get(ClassBuffSpell(profession.id))
    if type(description) == "string" and description ~= "" then tooltip:AddLine(description, 0.4, 1, 0.4, true) end
    if entry.party then tooltip:AddLine(L["Needs a party: it only reaches the giver's party."], 1, 0.6, 0.2, true) end
    if entry.talent then tooltip:AddLine(L["A talent: not every player of the class has it."], 1, 0.6, 0.2, true) end
    if entry.blessing then tooltip:AddLine(L["A paladin gives each player one blessing."], 0.7, 0.7, 0.7, true) end
end

-- Sets a Camp Setup text to "open", or "open (needs a party)" for a class
-- buff that reaches only the giver's party (just "open" if that doesn't fit).
local function SetOpen(text, skillLine, classWant)
    local entry = classWant and ns.CLASS_BUFFS[skillLine]
    if entry and entry.party then
        text:SetText(GREY .. format(L["%s (needs a party)"], L["open"]) .. "|r")
        if not text:IsTruncated() then return end
    end
    text:SetText(GREY .. L["open"] .. "|r")
end

-- A fire line on one line: the full text, else a shorter one if it would be cut off.
local function SetFireLine(text, full, short, orange)
    for _, line in ipairs({ full, short }) do
        text:SetText(orange and (ORANGE .. line .. "|r") or line)
        if not text:IsTruncated() then return end
    end
end

-- What an item does: the camp buff every tier gives (at your level), then the
-- game's own description of the item (or, before it has loaded, what its tier
-- adds).
local function ItemTooltip(tooltip, profession, tier)
    tooltip:SetText(RequestLabel(profession, tier))
    ns.AddBuffSize(tooltip, profession)
    local description = ItemDescription(profession, tier)
    local extras = profession.id ~= COOKING and (ns.OBJECT_EXTRAS[profession.id] or {})[tier]
    if description then
        tooltip:AddLine(description, 0.4, 1, 0.4, true)
    elseif extras then
        tooltip:AddLine(format(L["Tier %d: %s"], tier, ns.JoinList(extras)), 0.4, 1, 0.4, true)
    end
end

-- Build a camp ----------------------------------------------------------------------

-- Each row's Camp Setup: what you're bringing (green), a buff you'd like (open),
-- a class buff you give (azure), something you could bring (Available), or a dash.
-- A buff can be asked for as a class buff instead of its object (Power Word:
-- Fortitude for Stamina): it takes no slot at the fire.
function Finder:RefreshComposer()
    local composer = self.frame and self.frame.composer
    if not composer then return end
    local options = ns.Requests:BringOptions()
    local optionFor, gives = {}, {}
    for _, option in ipairs(options) do optionFor[option.skillLine] = option end
    for _, entry in ipairs(ns.Requests:ClassBuffs()) do gives[entry.skillLine] = entry.buff end
    local covered = GroupBuffs()
    local kitTier, objects, asking, classAsking = 0, 0, 0, 0
    for _, row in ipairs(composer.rows) do
        local id, check = row.profession.id, row.want
        local option = optionFor[id]
        local brought = option ~= nil and Bringing(composer, option, options)
        -- What you bring can't be asked for too, except the campfire: someone
        -- may have a bigger one than yours, so its menu starts above your kit.
        -- What your class buffs give can be asked for at any tier: others may
        -- want to bring it, or a higher tier's extras.
        local better = id == COOKING and brought and option.tier < 3
        check.open = not brought or better
        if brought and not better then check:SetChecked(false) end
        local wanted = check:GetChecked() and true or false
        -- Asked for as a class buff: only while ticked, and where there is one.
        check.classOption = HasClassOption(id, covered)
        if not (wanted and check.classOption) then composer.wantBuff[id] = nil end
        local classWant = composer.wantBuff[id] == true
        check.low = better and option.tier + 1 or 1
        local tier = math.max(composer.minTier[id] or 1, check.low)
        check.tier:SetShown(wanted)
        check.tier.shownTier, check.tier.classWant = tier, classWant
        FitMenuText(check.tier, classWant and ns.Requests:BuffName(id, true) or RequestLabel(row.profession, tier))
        row.option = option
        local text
        if brought then
            text = GREEN .. Tiered(L["You"], option.tier) .. "|r"
        elseif wanted then
            text = GREY .. L["open"] .. "|r" -- (with "needs a party" where it fits: below)
        elseif gives[id] then
            text = AZURE .. gives[id] .. "|r"
        elseif option and option.carried then
            text = WHITE .. Tiered(L["In your bags"], option.carriedTier) .. "|r"
        elseif option then
            text = GREY .. Tiered(L["Can make"], option.makeTier) .. "|r"
        else
            text = GREY .. "-|r"
        end
        -- What you request, you're not bringing: its Camp Setup says it's open
        -- (but a campfire you bring stays, beside the bigger one you ask for).
        row.setup:SetText(text)
        if wanted and not brought then SetOpen(row.setup, id, classWant) end
        local menu = option ~= nil and (not wanted or brought)
        row.bring:SetShown(menu)
        local state = brought and "ready" or wanted and "open" or gives[id] and "covered"
            or option and (option.carried and "offer" or "canmake") or "nobody"
        ns.Style:SetPlanState(row, STATES[state])
        ns.Style:FitPill(row.pill, STATES[state], menu, PLAN.SETUP_WIDTH)
        if id == COOKING then
            if brought then kitTier = math.max(kitTier, option.tier) end
            if wanted then kitTier = math.max(kitTier, tier) end
        else
            if brought then objects = objects + 1 end
            if wanted and classWant then
                classAsking = classAsking + 1 -- no fire slot
            elseif wanted then
                asking = asking + 1
            end
        end
    end
    local holds = FireHolds(kitTier)
    local orange = asking + objects > holds
    local full
    if classAsking > 0 then
        full = format(L["Fire holds %d objects: asking for %d and bringing %d. Class buffs asked for: %d."], holds, asking, objects, classAsking)
        SetFireLine(composer.fire, full,
            format(L["Fire: %d slots, %d asked for, %d brought. Class buffs: %d."], holds, asking, objects, classAsking), orange)
    else
        full = format(L["Fire holds %d objects: you're asking for %d and bringing %d."], holds, asking, objects)
        composer.fire:SetText(orange and (ORANGE .. full .. "|r") or full)
    end
    SetFireFigure(composer.fireTile, asking + objects, holds, full)
    -- Requests fit the fire (yours, or the bigger one you ask for): once its
    -- slots that you aren't filling are all asked for, no more objects can be
    -- ticked. Untick one, or ask for a bigger campfire. A buff with a class
    -- buff can still be ticked: it's asked for as that class buff, which takes
    -- no slot (check.toClassBuff).
    composer.holds, composer.room, composer.asking, composer.kitTier = holds, holds - objects, asking, kitTier
    composer.classAsking = classAsking
    for _, row in ipairs(composer.rows) do
        local check = row.want
        check.full = row.profession.id ~= COOKING and not check:GetChecked() and asking >= holds - objects
        check.toClassBuff = check.full and check.classOption
        check:SetEnabled(check.open and (not check.full or check.toClassBuff))
    end
end

-- Camp Setup's menu on a row you can bring: Nobody, or You.
local function BringMenu(composer, row, root)
    local options = ns.Requests:BringOptions()
    local option
    for _, entry in ipairs(options) do
        if entry.skillLine == row.profession.id then option = entry end
    end
    if not option then return end
    local function IsPicked(on) return Bringing(composer, option, options) == on end
    local function Pick(on)
        if option.kit then
            composer.kitPick = on
        elseif on then
            composer.objectPick = option.skillLine -- one camp object: this one
        elseif PickedObject(composer, options) == option.skillLine then
            composer.objectPick = false
        end
        Finder:RefreshComposer()
    end
    root:CreateRadio(L["Nobody"], IsPicked, Pick, false)
    root:CreateRadio(L["You"] .. " " .. (option.carried and GREEN or GREY)
        .. format(option.carried and L["(has tier %d)"] or L["(can make tier %d)"],
            option.carried and option.carriedTier or option.makeTier) .. "|r", IsPicked, Pick, true)
end

-- The quick picks: tick a preset's buffs, as many as the fire holds (your kit's,
-- or the bigger one you're asking for), leaving out what you bring and what your
-- class buffs already give. Then the rest of the preset's buffs that a class
-- buff can give are asked for as class buffs, which take no slot. The campfire
-- request isn't a buff: it stays as it is.
function Finder:ApplyPreset(preset)
    local composer = self.frame and self.frame.composer
    if not composer then return end
    local options = ns.Requests:BringOptions()
    local brought, kitTier, objects = {}, 0, 0
    for _, option in ipairs(options) do
        if Bringing(composer, option, options) then
            brought[option.skillLine] = true
            if option.kit then kitTier = option.tier else objects = objects + 1 end
        end
    end
    for _, check in ipairs(composer.checks) do
        if check.profession.id == COOKING and check:GetChecked() then
            kitTier = math.max(kitTier, composer.minTier[COOKING] or 1, check.low or 1)
        end
    end
    local covered, picked, asBuff = GroupBuffs(), {}, {}
    local room = FireHolds(kitTier) - objects
    for _, skillLine in ipairs(preset.skills) do
        if not brought[skillLine] and not covered[skillLine] then
            if room > 0 then
                picked[skillLine] = true
                room = room - 1
            elseif HasClassOption(skillLine, covered) then
                picked[skillLine], asBuff[skillLine] = true, true
            end
        end
    end
    for _, check in ipairs(composer.checks) do
        local id = check.profession.id
        if id ~= COOKING then
            check:SetChecked(picked[id] == true)
            composer.wantBuff[id] = asBuff[id]
        end
    end
    self:RefreshComposer()
end

local function CreateComposer(f)
    local style = ns.Style
    local composer = TopPanel(f)
    composer.title = style:PageTitle(composer, L["Build a camp"])

    -- Quick picks, as on the Group tab: in the middle.
    local presets = CreateFrame("Frame", nil, composer)
    presets:SetHeight(22)
    local label = style:Text(presets, "GameFontNormalSmall", L["Fill the plan for:"], "LEFT")
    label:SetPoint("LEFT")
    composer.presetButtons = {}
    local previous
    for i, preset in ipairs(ns.Search.PRESETS) do
        local button = style:Button(presets, PRESET_WIDTH, L[preset.name], function() Finder:ApplyPreset(preset) end, 20)
        if previous then button:SetPoint("LEFT", previous, "RIGHT", 6, 0) else button:SetPoint("LEFT", label, "RIGHT", 8, 0) end
        style:Tooltip(button, L[preset.name], L["Ticks the camp buffs for this kind of group, as many as the fire holds, leaving out what you bring or give. The rest are asked for as class buffs, which take no slot. Change any of it after."])
        composer.presetButtons[i] = button
        previous = button
    end
    style:SameWidth(composer.presetButtons, PRESET_WIDTH) -- a translation may make one grow
    local width = style:TextWidth(label) + 8
    for _, button in ipairs(composer.presetButtons) do width = width + button:GetWidth() + 6 end
    presets:SetWidth(width - 6)
    presets:SetPoint("TOP", composer, "TOP", 0, TOP_Y)

    -- The fire: its line on one line (a shorter one if it would be cut off).
    composer.fireTile = FireTile(composer)
    composer.fire = composer.fireTile.sub

    local plan = PlanPanel(composer, L["Request"])
    composer.rows, composer.checks, composer.minTier = {}, {}, {}
    composer.wantBuff = {} -- [skillLine] = true: asked for as a class buff
    local y = -PLAN.LIST_TOP
    for i, profession in ipairs(ns.PROFESSIONS) do
        local row = BuffRow(plan, profession, y)
        -- Request: a tick box, then the lowest tier, by its item's name:
        -- "Mana Well (T1)", "Fermenter (T2)" (adds a workspace or service)...
        local check = CreateCheck(row, "")
        check:SetPoint("LEFT", WANT_X - 3, 0)
        check.profession = profession
        check:SetScript("OnClick", function()
            -- Ticked with the fire's slots all asked for: its class buff instead.
            if check:GetChecked() and check.toClassBuff then composer.wantBuff[profession.id] = true end
            Finder:RefreshComposer()
        end)
        check:SetMotionScriptsWhileDisabled(true) -- a full fire says why on hover
        style:CustomTooltip(check, "ANCHOR_RIGHT", function(tooltip)
            ns.AddProfessionTooltip(tooltip, profession)
            if check.full and check.open and check.toClassBuff then
                tooltip:AddLine(" ")
                tooltip:AddLine(format(L["The fire's slots are all asked for: ticking this asks for %s, which takes no slot."],
                    ns.Requests:ClassBuffLabel(profession.id)), 0.2, 0.6, 1, true)
            elseif check.full and check.open then
                tooltip:AddLine(" ")
                tooltip:AddLine(format(L["The fire holds %d objects, all taken. Untick one to ask for this."], composer.holds), 1, 0.6, 0.2, true)
                if (composer.kitTier or 0) < 3 then
                    tooltip:AddLine(L["Or ask for a bigger campfire, which holds more."], 1, 0.6, 0.2, true)
                end
            end
        end)
        -- The lowest tier of its object, or (where there is one) its class buff,
        -- which takes no slot at the fire.
        check.tier = style:MenuLabel(row, TIER_WIDTH, function(_, root)
            for tier = check.low or 1, 3 do
                local choice = root:CreateRadio(RequestLabel(profession, tier),
                    function(t) return not composer.wantBuff[profession.id] and math.max(composer.minTier[profession.id] or 1, check.low or 1) == t end,
                    function(t)
                        composer.minTier[profession.id] = t
                        composer.wantBuff[profession.id] = nil
                        Finder:RefreshComposer()
                    end, tier)
                -- Hover a choice for what that item does.
                if type(choice) == "table" and choice.SetTooltip then
                    choice:SetTooltip(function(tooltip) ItemTooltip(tooltip, profession, tier) end)
                end
            end
            if HasClassOption(profession.id) then
                local choice = root:CreateRadio(ns.Requests:ClassBuffLabel(profession.id),
                    function() return composer.wantBuff[profession.id] == true end,
                    function()
                        composer.wantBuff[profession.id] = true
                        Finder:RefreshComposer()
                    end, "class")
                if type(choice) == "table" and choice.SetTooltip then
                    choice:SetTooltip(function(tooltip) ClassBuffTooltip(tooltip, profession) end)
                end
            end
        end)
        check.tier:SetPoint("LEFT", WANT_X + 20, 0)
        style:CustomTooltip(check.tier, "ANCHOR_RIGHT", function(tooltip, self)
            if self.classWant then return ClassBuffTooltip(tooltip, profession) end
            ItemTooltip(tooltip, profession, self.shownTier or 1)
        end)
        check.tier:Hide()
        row.want = check
        -- Camp Setup: what you're bringing, picked from a menu where you can.
        row.bring = style:PillMenu(row.pill, function(_, root) BringMenu(composer, row, root) end)
        -- Hover: where it comes from, the item in your bags or the recipe learned.
        style:CustomTooltip(row.bring, "ANCHOR_RIGHT", function(tooltip)
            tooltip:SetText(L["I'm bringing"])
            local option = row.option
            if option and option.carried then
                local item = ns.Requests:CarriedItem(profession.id)
                local name = item and C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(item)
                name = type(name) == "string" and name ~= "" and name or ItemName(profession, option.carriedTier)
                tooltip:AddLine(format(L["In your bags: %s"], format("%s (%s)", name, ns.Requests:TierText(option.carriedTier))), 1, 1, 1, true)
            end
            local tier, recipeID = ns.Requests:RecipeTier(profession.id)
            if tier > 0 then
                local recipe = C_Spell.GetSpellName(recipeID)
                recipe = type(recipe) == "string" and recipe ~= "" and recipe or ItemName(profession, tier)
                tooltip:AddLine(format(L["Recipe learned: %s"], format("%s (%s)", recipe, ns.Requests:TierText(tier))), 1, 1, 1, true)
            end
        end)
        row.bring:Hide()
        composer.rows[i], composer.checks[i] = row, check
        y = y - ROW_HEIGHT
    end

    -- Meet at (two checkboxes that work as a pair of radio buttons), and Post.
    local meetY = BELOW_Y - 11
    local meet = style:Text(composer, "GameFontNormalSmall", L["Meet at:"])
    meet:SetPoint("LEFT", composer, "TOPLEFT", PAD, meetY)
    composer.useHere = CreateCheck(composer, L["Where I'm standing"])
    composer.useHere:SetPoint("LEFT", meet, "RIGHT", 4, 0)
    composer.usePin = CreateCheck(composer, L["My map pin"])
    composer.usePin:SetPoint("LEFT", composer.useHere.Text, "RIGHT", 12, 0)
    composer.useHere:SetChecked(true)
    local function Pick(pin)
        composer.usePin:SetChecked(pin)
        composer.useHere:SetChecked(not pin)
    end
    composer.useHere:SetScript("OnClick", function() Pick(false) end)
    composer.usePin:SetScript("OnClick", function() Pick(true) end)

    composer.post = style:Button(composer, 140, L["Post request"], function() PostRequest(composer) end)
    composer.post:SetPoint("RIGHT", composer, "TOPRIGHT", -PAD, meetY)
    -- Greyed out while the camp network is off (Refresh): its tooltip says why,
    -- always; what it does is a help tip.
    composer.post:SetMotionScriptsWhileDisabled(true)
    style:CustomTooltip(composer.post, "ANCHOR_TOP", function(tooltip)
        tooltip:AddLine(L["Post request"])
        tooltip:AddLine(ns.db.network and format(L["Players with the addon who can help will see it. Requests close after %d minutes or when a fire is lit at the meet-up."],
            ns.Requests.DURATION / 60) or L["The camp network is off, so nobody would see your request. Turn on sharing in Options to post it."], 1, 1, 1, true)
    end)
    local showTooltip = composer.post:GetScript("OnEnter")
    composer.post:SetScript("OnEnter", function(self, ...)
        if ns.db.network and not style:ShowHelp() then return end
        return showTooltip(self, ...)
    end)
    return composer
end

-- Your request --------------------------------------------------------------------

local function CreateStatus(f)
    local style = ns.Style
    local status = TopPanel(f)
    status.title = style:PageTitle(status, L["Your camp request"])
    status.info = Text(status, "GameFontHighlightSmall", nil, PAD, TOP_Y - 4, "LEFT")
    status.info:SetWidth(WIDTH - 2 * PAD)
    -- The fire, one line as in the composer.
    status.fireTile = FireTile(status)
    status.fire = status.fireTile.sub

    local plan = PlanPanel(status, L["Request"])
    status.rows = {}
    local y = -PLAN.LIST_TOP
    for i, profession in ipairs(ns.PROFESSIONS) do
        local row = BuffRow(plan, profession, y)
        row.wantText = style:Text(row, "GameFontHighlightSmall", nil, "LEFT")
        row.wantText:SetPoint("LEFT", WANT_X, 0)
        status.rows[i] = row
        y = y - ROW_HEIGHT
    end

    -- Say and General on the left; Move and Close on the right.
    local buttonY = BELOW_Y - 11
    local announce = ns.Announce:CreateButtons(status, function(room)
        local request = ns.Requests:Mine()
        return request and ns.Announce:RequestMessage(request, room)
    end)
    announce[1]:SetPoint("LEFT", status, "TOPLEFT", PAD, buttonY)
    status.close = style:Button(status, 130, L["Close request"], function()
        local request = ns.Requests:Mine()
        if request then ns.Requests:Close(request) end
        Finder:Refresh()
    end)
    status.close:SetPoint("RIGHT", status, "TOPRIGHT", -PAD, buttonY)
    status.move = style:Button(status, 130, L["Move meet-up here"], function()
        local request = ns.Requests:Mine()
        if not request then return end
        local mapID, x, y2 = ns.GetPlayerLocation()
        if not mapID then
            ns.Print(L["Your location isn't available here."])
        elseif not ns.IsOutdoorMap(mapID) then
            ns.Print(L["Meet-ups must be on a zone map, not a continent or dungeon map."])
        else
            ns.Requests:Move(request, mapID, x, y2)
            Finder:Refresh()
        end
    end)
    status.move:SetPoint("RIGHT", status.close, "LEFT", -6, 0)
    style:SameWidth({ status.move, status.close })
    return status
end

-- Camp Setup for a row with sign-ups: who brings its object ("Bram Stone T2",
-- green), then who gives its stat with a class buff ("Bram Stone: Blessing of
-- Might", azure). What doesn't fit is shortened: first names, then without
-- "(needs a party)", then the givers' names alone (hover the row for all of
-- it), then "+N".
local function FitSetup(text, objects, givers, skillLine)
    local R = ns.Requests
    local styles = {
        function(name) return format("%s: %s", ShortName(name), R:BuffName(skillLine)) end,
        function(name) return format("%s: %s", ns.FirstName(name), R:BuffName(skillLine)) end,
        function(name) return format("%s: %s", ns.FirstName(name), R:BuffName(skillLine, true)) end,
        function(name) return ns.FirstName(name) end,
    }
    local shown
    for _, style in ipairs(styles) do
        shown = {}
        for _, name in ipairs(objects) do shown[#shown + 1] = GREEN .. name .. "|r" end
        for _, name in ipairs(givers) do shown[#shown + 1] = AZURE .. style(name) .. "|r" end
        text:SetText(table.concat(shown, ", "))
        if not text:IsTruncated() then return end
    end
    ns.Group.FitNames(text, shown, "")
end

-- How your camp will look: what you bring, who's signed up for each buff (with
-- an object, or its stat with a class buff), and what's still open.
local function RefreshStatus(status, request)
    local R = ns.Requests
    local brings, helperTiers = request.brings or {}, request.helperTiers or {}
    local classWants = request.classWants or {}
    local coming = {} -- [skillLine] = { "Name T2", ... }
    for name, skillLine in pairs(request.helpers) do
        if skillLine ~= 0 then
            coming[skillLine] = coming[skillLine] or {}
            table.insert(coming[skillLine], Tiered(ShortName(name), helperTiers[name]))
        end
    end
    local kitTier, objects, open, buffsComing, buffsOpen = brings[COOKING] or 0, 0, 0, 0, 0
    for _, row in ipairs(status.rows) do
        local id = row.profession.id
        local names = coming[id] or {}
        local _, givers = R:Sources(request, id)
        table.sort(names)
        table.sort(givers)
        local brought, wanted, classWant = brings[id], request.wants[id], classWants[id]
        local all = { unpack(names) }
        for _, name in ipairs(givers) do all[#all + 1] = format("%s: %s", ShortName(name), R:BuffName(id)) end
        row.coming = #all > 0 and table.concat(all, ", ") or nil
        if classWant then
            row.wantText:SetText(WHITE .. R:BuffName(id, true) .. "|r")
        else
            row.wantText:SetText(wanted and (WHITE .. TierLabel(R:MinTier(request, id)) .. "|r") or (GREY .. "-|r"))
        end
        local state
        row.setup:SetWidth(0)
        if brought and brought > 0 and not (wanted and #all > 0) then
            local text = GREEN .. Tiered(L["You"], brought) .. "|r"
            if wanted then text = text .. GREY .. ", " .. L["open"] .. "|r" end -- a bigger fire, asked for
            row.setup:SetText(text)
            state = "ready"
        elseif #all > 0 then
            -- Who's coming: names, as many as fit the column.
            row.setup:SetWidth(PLAN.SETUP_WIDTH - 4)
            FitSetup(row.setup, names, givers, id)
            state = "coming"
        elseif wanted then
            SetOpen(row.setup, id, classWant)
            state = "open"
        elseif (request.buffs or {})[id] then
            row.setup:SetText(AZURE .. (row.profession.conflicts or row.profession.buff) .. "|r")
            state = "covered"
        else
            row.setup:SetText(GREY .. "-|r")
            state = "nobody"
        end
        ns.Style:SetPlanState(row, STATES[state])
        ns.Style:FitPill(row.pill, STATES[state], false, PLAN.SETUP_WIDTH)
        if id == COOKING then
            for name, skillLine in pairs(request.helpers) do
                if skillLine == COOKING then kitTier = math.max(kitTier, helperTiers[name] or 1) end
            end
        else
            -- Objects coming take a slot; a stat met by a class buff doesn't.
            objects = objects + #names + ((brought and brought > 0) and 1 or 0)
            if wanted and (classWant or #names == 0) then
                if #givers > 0 then
                    buffsComing = buffsComing + 1
                elseif classWant then
                    buffsOpen = buffsOpen + 1
                else
                    open = open + 1
                end
            end
        end
    end
    status.info:SetText(format(L["Meet-up: %s, closes in %s"], R:PlaceText(request), ns.FormatTime(R:TimeLeft(request))))
    local full
    if buffsComing + buffsOpen > 0 then
        full = format(L["Fire holds %d objects: %d coming, %d still open; class buffs: %d coming, %d open."],
            FireHolds(kitTier), objects, open, buffsComing, buffsOpen)
        SetFireLine(status.fire, full,
            format(L["Fire: %d slots, %d coming, %d open. Class buffs: %d coming, %d open."],
                FireHolds(kitTier), objects, open, buffsComing, buffsOpen))
    else
        full = format(L["Fire holds %d objects: %d coming, %d still open."], FireHolds(kitTier), objects, open)
        status.fire:SetText(full)
    end
    SetFireFigure(status.fireTile, objects, FireHolds(kitTier), full)
end

-- Players looking for a camp ---------------------------------------------------

-- A request's buffs as small icons, lit once someone's bringing them, faded
-- while open, ringed in gold where you could bring one.
local function Mini(row, i)
    local mini = row.minis[i]
    if mini then return mini end
    mini = CreateFrame("Frame", nil, row)
    mini:SetSize(MINI, MINI)
    mini:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 6 + (i - 1) * (MINI + MINI_GAP), 4)
    mini.ring = mini:CreateTexture(nil, "BACKGROUND")
    mini.ring:SetPoint("TOPLEFT", -1, 1)
    mini.ring:SetPoint("BOTTOMRIGHT", 1, -1)
    mini.ring:SetColorTexture(1, 0.82, 0, 0.9)
    mini.icon = mini:CreateTexture(nil, "ARTWORK")
    mini.icon:SetAllPoints()
    mini.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    row.minis[i] = mini
    return mini
end

local function RequestRow(list, i)
    local row = list.rows[i]
    if row then return row end
    row = CreateFrame("Frame", nil, list.child)
    row:SetSize(list.rowWidth, REQUEST_HEIGHT - 4)
    row:SetPoint("TOPLEFT", 0, -(i - 1) * REQUEST_HEIGHT)
    row:EnableMouse(true)

    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints()
    row.bg:SetColorTexture(1, 1, 1, i % 2 == 0 and 0.04 or 0.08)

    row.title = ns.Style:Line(row, "GameFontNormal")
    row.title:SetPoint("TOPLEFT", 6, -4)
    row.title:SetPoint("RIGHT", row, "RIGHT", -buttonsWidth, 0)
    row.minis = {}
    row.count = ns.Style:Text(row, "GameFontHighlightSmall", nil, "LEFT")

    row.join = ns.Style:Button(row, rowButtonWidth, L["Join"], function(self)
        local request, options = row.request, row.options
        if request.helpers[ns.playerName] then
            ns.Requests:Withdraw(request)
            Finder:Refresh()
        elseif #options > 0 then
            Join(request, options, self)
        end
    end)
    row.join:SetPoint("RIGHT", -4, 0)
    ns.Style:CustomTooltip(row.join, "ANCHOR_RIGHT", function(tooltip)
        if row.request.helpers[ns.playerName] then
            tooltip:AddLine(L["Withdraw from this camp"])
        elseif #row.options > 0 then
            -- Objects by profession, class buffs by name ("(needs a party)" too).
            local names = {}
            for _, option in ipairs(row.options) do names[#names + 1] = option.name end
            tooltip:AddLine(format(L["Sign up to bring %s"], table.concat(names, L[" or "])), 1, 1, 1, true)
        else
            tooltip:AddLine(L["You need one of the wanted camp objects in your bags, or its recipe."], 1, 1, 1, true)
        end
    end)

    -- Map: a waypoint on the meet-up, and the map opened on it (its zone's map),
    -- where the waypoint shows. Not in a fight: the game guards its windows then.
    row.map = ns.Style:Button(row, rowButtonWidth, L["Map"], function()
        local request = row.request
        ns.SetWaypoint(request, format(L["%s's meet-up"], ShortName(request.creator)))
        if C_Map.CanSetUserWaypointOnMap(request.mapID) then
            local zone = ns.ZoneOf(request.mapID)
            ns.OpenMap(ns.Camps:Project(request, zone) and zone or request.mapID)
        end
    end)
    row.map:SetPoint("RIGHT", row.join, "LEFT", -6, 0)
    ns.Style:Tooltip(row.map, L["Map"], L["Opens the map with a waypoint on the meet-up."])

    row.whisper = ns.Style:Button(row, rowButtonWidth, L["Whisper"], function() ns.Whisper(row.request.creator) end)
    row.whisper:SetPoint("RIGHT", row.map, "LEFT", -6, 0)
    ns.Style:CustomTooltip(row.whisper, "ANCHOR_RIGHT", function(tooltip)
        tooltip:SetText(L["Whisper"])
        tooltip:AddLine(format(L["Opens a whisper to %s in your chat box. Nothing is sent until you press Enter."],
            ShortName(row.request.creator)), 1, 1, 1, true)
    end)
    ns.Style:OnlyWithHelp(row.whisper)

    ns.Style:CustomTooltip(row, "ANCHOR_RIGHT", function(tooltip, self) Finder:FillRequestTooltip(tooltip, self.request) end, true)
    list.rows[i] = row
    return row
end

-- A request's buff icons: what the requester brings and every buff wanted (a
-- class-buff want by the class buff's icon), with how many of the wanted ones
-- are covered, by an object or a class buff.
local function FillRequestRow(row, request)
    local canBring = {} -- objects you could bring, and class buffs you could give
    for _, option in ipairs(row.options) do canBring[option.id] = true end
    local brings = request.brings or {}
    local count, wanted, filled = 0, 0, 0
    for _, profession in ipairs(ns.PROFESSIONS) do
        local id = profession.id
        local brought = (brings[id] or 0) > 0
        if brought or request.wants[id] then
            -- What the requester brings covers it only at the tier wanted (their
            -- own small fire doesn't cover the bigger one they ask for).
            local lit = ns.Requests:Covered(request, id)
            count = count + 1
            local mini = Mini(row, count)
            mini.icon:SetTexture((request.classWants or {})[id] and ClassBuffIcon(profession) or profession.icon)
            mini.icon:SetDesaturated(not lit)
            mini:SetAlpha(lit and 1 or 0.45)
            mini.ring:SetShown(not lit and canBring[id] == true)
            mini:Show()
            if request.wants[id] then
                wanted = wanted + 1
                if lit then filled = filled + 1 end
            end
        end
    end
    for i = count + 1, #row.minis do row.minis[i]:Hide() end
    -- How many are covered, after the icons, if it fits before the buttons.
    row.count:SetText(format(L["%d of %d"], filled, wanted))
    row.count:ClearAllPoints()
    local x = 6 + count * (MINI + MINI_GAP) + 4
    row.count:SetPoint("LEFT", row, "BOTTOMLEFT", x, 3 + MINI / 2)
    local width = ns.Style:TextWidth(row.count)
    row.count:SetShown(x + width <= row:GetWidth() - buttonsWidth)
end

-- A request's title: who, and how far (Map shows where). If it doesn't fit
-- before the buttons, the surname goes, then the distance. Hover the row for
-- all of it.
local function FitTitle(title, request, distance)
    local full, first = ShortName(request.creator), ns.FirstName(request.creator)
    local near = distance and format(L["%d yd"], distance)
    for _, try in ipairs({ { full, near }, { first, near }, { first } }) do
        title:SetText(try[2] and format("%s  |cffaaaaaa%s|r", try[1], try[2]) or try[1])
        if not title:IsTruncated() then return end
    end
end

-- Builds the tab's contents inside the Happy Camper window's page frame.
function Finder:Build(page)
    local style = ns.Style
    page.composer = CreateComposer(page)
    page.status = CreateStatus(page)
    LoadDescriptions()

    local listHead = BELOW_Y - 22 - 12
    local header = Text(page, "GameFontNormal", L["Players looking for a camp"], PAD, listHead)
    -- What the list holds, after the heading, never past the list's right edge.
    page.listNote = style:Line(page, "GameFontDisableSmall", L["in your zone, wanting something you can bring"])
    page.listNote:SetPoint("LEFT", header, "RIGHT", 8, 0)
    page.listNote:SetWidth(WIDTH - 2 * PAD - ns.Style:TextWidth(header) - 8)
    local listTop = listHead - 18
    local panel = style:Panel(page)
    panel:SetPoint("TOPLEFT", PAD, listTop)
    panel:SetPoint("TOPRIGHT", -PAD, listTop)
    panel:SetHeight(LIST_ROWS * REQUEST_HEIGHT + 8)
    local list = CreateFrame("ScrollFrame", nil, panel)
    list:SetPoint("TOPLEFT", 4, -4)
    list:SetSize(WIDTH - 2 * PAD - 8, LIST_ROWS * REQUEST_HEIGHT)
    style:ScrollArea(list, WIDTH - 2 * PAD - 8, REQUEST_HEIGHT)
    list.rows, list.rowWidth = {}, WIDTH - 2 * PAD - 8 - SCROLLBAR_SPACE
    -- Whisper, Map and Join are one width, the widest label's, Leave's too (so
    -- Join doesn't change size when it says Leave). Their font is GameFontNormal.
    local probe, widest = style:Text(page, "GameFontNormal"), 0
    for _, label in ipairs({ L["Whisper"], L["Map"], L["Join"], L["Leave"] }) do
        probe:SetText(label)
        widest = math.max(widest, ns.Style:TextWidth(probe))
    end
    probe:Hide()
    rowButtonWidth = math.max(ROW_BUTTON_WIDTH, math.ceil(widest) + 20)
    buttonsWidth = 3 * rowButtonWidth + 2 * 6 + 10
    for i = 1, LIST_ROWS do RequestRow(list, i):Hide() end
    page.list, page.rows = list, list.rows
    -- With nothing to list: a note in the middle of the box.
    page.empty = style:Text(page, "GameFontDisable", nil, "CENTER")
    page.empty:SetPoint("CENTER", list, "CENTER")
    page.empty:SetWidth(WIDTH - 2 * PAD - 24)
    -- Footer: network status on the left, how many Happy Campers on the right
    -- (hover it for today and this week).
    page.network = style:Text(page, "GameFontHighlightSmall")
    page.network:SetPoint("BOTTOMLEFT", PAD, 6)
    page.users = CreateFrame("Frame", nil, page)
    page.users:SetPoint("BOTTOMRIGHT", -PAD, 4)
    page.users:SetSize(1, 14)
    page.users:EnableMouse(true)
    page.users.text = style:Text(page.users, "GameFontHighlightSmall")
    page.users.text:SetPoint("RIGHT")
    style:InfoTooltip(page.users, function() return ns.Stats:Summary() end,
        L["Players with Happy Camper your addon has heard from on the camp network."])
    self.frame = page
end

function Finder:IsShown()
    return ns.Hub:IsShowing("finder")
end

function Finder:Open()
    ns.Hub:Open("finder")
end

function Finder:Toggle()
    ns.Hub:Toggle("finder")
end

function Finder:Refresh()
    local f = self.frame
    if not f or not f:IsVisible() then return end
    local R = ns.Requests

    local mine = R:Mine()
    f.composer:SetShown(not mine)
    f.status:SetShown(mine ~= nil)
    if mine then
        RefreshStatus(f.status, mine)
    else
        self:RefreshComposer()
        f.composer.post:SetEnabled(ns.db.network and true or false)
        f.composer.usePin:SetEnabled(C_Map.HasUserWaypoint())
        if not C_Map.HasUserWaypoint() and f.composer.usePin:GetChecked() then
            f.composer.usePin:SetChecked(false)
            f.composer.useHere:SetChecked(true)
        end
    end

    local list, ranks = {}, ns.GetMyProfessions() -- your professions, looked up once for every request
    for _, request in pairs(R:All()) do
        if R:ForMe(request, ranks) then
            list[#list + 1] = { request = request, distance = ns.Camps:DistanceFromPlayer(request) }
        end
    end
    table.sort(list, function(a, b)
        if a.distance and b.distance then return a.distance < b.distance end
        if a.distance or b.distance then return a.distance ~= nil end
        return a.request.createdAt > b.request.createdAt
    end)

    for i, entry in ipairs(list) do
        local row = RequestRow(f.list, i)
        local request = entry.request
        row.request = request
        row.options = R:HelpOptions(request, ranks)
        row:Show()
        FitTitle(row.title, request, entry.distance)
        FillRequestRow(row, request)
        local joined = request.helpers[ns.playerName] ~= nil
        row.join:SetText(joined and L["Leave"] or L["Join"])
        row.join:SetEnabled(joined or #row.options > 0)
    end
    for i = #list + 1, #f.list.rows do f.list.rows[i]:Hide() end
    f.list.child:SetHeight(math.max(1, #list) * REQUEST_HEIGHT)
    f.empty:SetShown(#list == 0)

    local camps, requests = ns.Count(ns.Camps:All()), ns.Count(R:All())
    local connected = ns.Comm:IsConnected()
    f.network:SetText(connected
        and format("|cff66ff66%s|r  |cffaaaaaa%s, %s|r", L["Camp network connected"],
            format(camps == 1 and L["%d camp"] or L["%d camps"], camps), format(requests == 1 and L["%d request"] or L["%d requests"], requests))
        or ns.Comm:IsChannelOff() and format("|cffff6666%s|r |cffaaaaaa%s|r", L["Camp network paused."], L["The game has switched off addon channels."])
        or format("|cffff6666%s|r |cffaaaaaa%s|r", L["Camp network off."], L["Turn it on in Options."]))
    f.users.text:SetText(format("|cffaaaaaa%s|r %d", L["Happy Campers seen:"], ns.Stats:Counts().total))
    f.users:SetWidth(math.max(1, ns.Style:TextWidth(f.users.text)))
    f.empty:SetText(ns.db.network and L["No one in your zone is looking for a camp you can help with."]
        or L["The camp network is off. Turn on sharing in Options to see requests."])
end
