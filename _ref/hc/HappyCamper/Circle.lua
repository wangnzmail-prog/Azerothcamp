-- Happy Camper. Copyright (c) 2026 Torridon. All rights reserved; see LICENSE.
local _, ns = ...
local L = ns.L

-- Campfire Circle: the Camp tab's list of the other addon users at your fire,
-- with Inspect and Whisper. (The Social tab's page was here too: it's in
-- parked/social-tab/ until the tab is reworked.)

local Circle = {}
ns.Circle = Circle

local WIDTH = 500
local PAD = 16
local PEOPLE_ROWS = 4 -- visible at once; more scroll
local LIST_WIDTH = WIDTH - 2 * PAD
local SCROLLBAR_SPACE = 16
local PERSON_HEIGHT = 46
local BUTTON_WIDTH = 70 -- a row's Inspect and Whisper, at least

local function ClassColored(person, text)
    local color = person.class and C_ClassColor.GetClassColor(person.class)
    return color and color:WrapTextInColorCode(text) or text
end

local function ShortName(person)
    return Ambiguate(person.name, "short")
end

-- The person's professions, in the usual order.
local function PersonProfessions(person)
    local list = {}
    for _, profession in ipairs(ns.PROFESSIONS) do
        if person.professions[profession.id] then list[#list + 1] = profession end
    end
    return list
end

-- Icons with ranks, so they fit on one line ("full" adds names, for the tooltip).
local function ProfessionText(person, full)
    local parts = {}
    for _, profession in ipairs(PersonProfessions(person)) do
        parts[#parts + 1] = format("|T%s:14:14|t %s%d", profession.icon, full and (profession.name .. " ") or "",
            person.professions[profession.id])
    end
    return parts
end

-- People ----------------------------------------------------------------------------

-- A unit token for someone at the fire, if the game gives them one. Addons
-- can't target players themselves, so otherwise you have to click them first.
local UNITS = { "target", "mouseover", "focus", "softfriend" }
for i = 1, 4 do UNITS[#UNITS + 1] = "party" .. i end
for i = 1, 40 do UNITS[#UNITS + 1] = "raid" .. i end
for i = 1, 40 do UNITS[#UNITS + 1] = "nameplate" .. i end

function Circle:UnitFor(person)
    for _, unit in ipairs(UNITS) do
        if UnitExists(unit) and UnitIsPlayer(unit) and ns.UnitFullName(unit) == person.name then return unit end
    end
end

local function Inspect(person)
    local unit = not ns.InCombat() and Circle:UnitFor(person)
    if ns.InCombat() then
        UIErrorsFrame:AddMessage(L["You can't inspect while in combat."], 1, 0.1, 0.1)
    elseif not unit then
        UIErrorsFrame:AddMessage(format(L["Click on %s first, then Inspect."], ShortName(person)), 1, 0.82, 0)
    elseif not CanInspect(unit) or not CheckInteractDistance(unit, 1) then
        UIErrorsFrame:AddMessage(format(L["%s is too far away to inspect."], ShortName(person)), 1, 0.82, 0)
    else
        InspectUnit(unit)
    end
end

local function CreatePersonRow(parent, i)
    local style = ns.Style
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(LIST_WIDTH, PERSON_HEIGHT - 4)
    row:SetPoint("TOPLEFT", 0, -(i - 1) * PERSON_HEIGHT)
    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints()
    row.bg:SetColorTexture(1, 1, 1, i % 2 == 0 and 0.04 or 0.08)

    -- The buttons sit to the right, one size (a translation may make one grow).
    row.whisper = style:Button(row, BUTTON_WIDTH, L["Whisper"], function() ns.Whisper(row.person.name) end)
    row.whisper:SetPoint("RIGHT", -4, 0)
    row.inspect = style:Button(row, BUTTON_WIDTH, L["Inspect"], function() Inspect(row.person) end)
    row.inspect:SetPoint("RIGHT", row.whisper, "LEFT", -4, 0)
    style:SameWidth({ row.whisper, row.inspect }, BUTTON_WIDTH)

    -- Three lines: name, level and class, professions; they end before the buttons.
    local function Line(font, y)
        local text = style:Line(row, font)
        text:SetPoint("TOPLEFT", 6, y)
        text:SetPoint("RIGHT", row.inspect, "LEFT", -8, 0)
        return text
    end
    row.name = Line("GameFontNormal", -4)
    row.details = Line("GameFontDisableSmall", -17)
    row.details:SetTextColor(0.67, 0.67, 0.67)
    row.professions = Line("GameFontHighlightSmall", -28)

    style:CustomTooltip(row.inspect, "ANCHOR_RIGHT", function(tooltip)
        tooltip:SetText(L["Inspect"])
        tooltip:AddLine(format(L["See %s's gear."], ShortName(row.person)), 1, 1, 1, true)
        if not Circle:UnitFor(row.person) then
            tooltip:AddLine(L["Click on them first (or have them in your group)."], 1, 0.82, 0, true)
        end
    end)
    row.inspect:SetScript("OnLeave", GameTooltip_Hide or function() GameTooltip:Hide() end)

    -- Hovering the row lists their professions by name.
    row:EnableMouse(true)
    style:CustomTooltip(row, "ANCHOR_RIGHT", function(tooltip, self)
        tooltip:SetText(ClassColored(self.person, ShortName(self.person)))
        for _, line in ipairs(ProfessionText(self.person, true)) do tooltip:AddLine(line, 1, 1, 1) end
    end)
    return row
end

-- Adds the people list to the Camp tab, starting at y = top.
function Circle:BuildPeople(page, top, height)
    page.peopleHeader = ns.Style:Text(page, "GameFontNormal", L["Adventurers at this camp"])
    page.peopleHeader:SetPoint("TOPLEFT", PAD, top)

    -- Rows are made as people arrive; the scroll bar shows only when needed.
    local list = CreateFrame("ScrollFrame", nil, page)
    list:SetPoint("TOPLEFT", PAD, top - 20)
    list:SetSize(LIST_WIDTH, height or PEOPLE_ROWS * PERSON_HEIGHT)
    ns.Style:ScrollArea(list, LIST_WIDTH, PERSON_HEIGHT)
    page.list = list

    page.rows = {}
    -- With nobody else here: a note in the middle of the box.
    page.empty = ns.Style:Text(page, "GameFontDisable", nil, "CENTER")
    page.empty:SetPoint("CENTER", list, "CENTER")
    page.empty:SetWidth(LIST_WIDTH - 24)

    self.people = page
end

function Circle:RefreshPeople()
    local page = self.people
    if not page or not page:IsVisible() then return end

    local people = ns.Social:PeopleHere()
    page.peopleHeader:SetText(#people > 0 and format(L["Adventurers at this camp (%d)"], #people) or L["Adventurers at this camp"])

    -- Rows narrow to make room for the scroll bar only when it's needed.
    local scrolls = #people > PEOPLE_ROWS
    local rowWidth = scrolls and LIST_WIDTH - SCROLLBAR_SPACE or LIST_WIDTH
    page.list.child:SetSize(rowWidth, math.max(1, #people) * PERSON_HEIGHT)
    page.list.scrollBar:SetShown(scrolls and page.list:IsShown())
    if not scrolls then page.list:SetVerticalScroll(0) end
    for i = #page.rows + 1, #people do page.rows[i] = CreatePersonRow(page.list.child, i) end

    for i, row in ipairs(page.rows) do
        local person = people[i]
        row:SetWidth(rowWidth)
        row:SetShown(person ~= nil)
        if person then
            row.person = person
            local className = person.class and LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[person.class] or ""
            row.name:SetText(ClassColored(person, ShortName(person)))
            row.details:SetText((format(L["Level %d %s"], person.level, className):gsub("%s$", "")))
            local professions = ProfessionText(person)
            row.professions:SetText(#professions > 0 and table.concat(professions, "   ") or L["No professions"])
        end
    end
    page.empty:SetShown(#people == 0)
    page.empty:SetText(ns.Social:IsAtCamp()
        and L["No other adventurers with Happy Camper here yet. They'll show up when they come to this fire."]
        or L["Sit down at a camp to see who else is there."])
end
