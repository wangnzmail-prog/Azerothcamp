-- Happy Camper. Copyright (c) 2026 Torridon. All rights reserved; see LICENSE.
local _, ns = ...
local L = ns.L

-- The user guide: a guided tour in its own window. Each step opens the real
-- window or tab and puts a pulsing highlight around the part it describes.
-- Starts by itself the first time you log in with the addon (never in combat),
-- once Standard or Enhanced has been chosen (Mode.lua); again from Options
-- ("Show the guide") or /hc guide. Skip ends it for good. In Standard mode it
-- leaves out the steps about what that mode doesn't have.

local Guide = {}
ns.Guide = Guide

local WIDTH, HEIGHT = 380, 230
local ORANGE = { 1, 0.6, 0.15 }

-- For the steps: a Happy Camper window page, opening a tab, and opening the map.
local function Page(key) return ns.Hub.frame.pages[key] end
local function OpenTab(key) return function() ns.Hub:Open(key) end end
-- Never in a fight, or with a controller (ns.OpenMap): the game guards its
-- windows then (opening or closing the map from an addon is blocked and
-- blamed on it).
local function OpenMap() ns.OpenMap() end
local function CloseMap()
    if not ns.InCombat() and not ns.IsGamepad() and WorldMapFrame and WorldMapFrame:IsShown() then HideUIPanel(WorldMapFrame) end
end

-- A demonstration camp for the "Camps on the map" step: only on your screen
-- (its ID starts "HCTest:", which is never sent), removed when you move on.
local demoCamp

local function AddDemoCamp()
    local mapID = WorldMapFrame:GetMapID()
    if not mapID then return end
    local playerMap, px, py = ns.GetPlayerLocation()
    local x, y = 0.5, 0.5
    if playerMap == mapID then x, y = math.min(0.95, px + 0.04), py end
    local now = GetServerTime()
    local ok, location = pcall(ns.Location.Describe, ns.Location, mapID, x, y, true)
    demoCamp = {
        id = "HCTest:guide:" .. now, demo = true,
        creator = "Brambleton-" .. ns.realm, owned = true,
        mapID = mapID, x = x, y = y,
        location = ok and ns.Location:Shared(location) or nil,
        nameKey = "n:pub1", placedAt = now, expiresAt = now + 11 * 60, updated = now,
        objects = {}, realm = ns.realm,
        professions = { [164] = true, [197] = true, [356] = true },
        equipment = { [164] = 1, [197] = 1, [356] = 1 },
    }
    demoCamp.continent, demoCamp.wx, demoCamp.wy = ns.Camps.WorldPosition(mapID, x, y)
    ns.db.camps[demoCamp.id] = demoCamp
    ns.MapPins:Refresh()
end

local function DemoPin()
    return demoCamp and ns.MapPins.pins[demoCamp.id]
end

local function RemoveDemoCamp()
    if not demoCamp then return end
    ns.db.camps[demoCamp.id] = nil
    demoCamp = nil
    GameTooltip:Hide()
    ns.MapPins:Refresh()
end

-- Each step: title, text, show (opens what it's about), leave (tidies up when
-- you move on) and target (what to highlight: a frame, or first and last frames
-- of an area). place = "above" puts the guide above the target, not beside it.
-- enhanced = true: only in Enhanced mode; standardText: said instead in Standard.
local STEPS = {
    {
        title = "Welcome to Happy Camper",
        text = "Happy Camper makes camps social. It shares campfires with other players who have the addon, shows them on your map, and helps you find the buffs you want.\n\nThis short tour shows you around. Skip it any time.",
    },
    {
        title = "The minimap button",
        text = "This is the Happy Camper button. Click it to open the Happy Camper window. Right-click it for Options, Shift-click it to show or hide the Campsite Assistant, and drag it to move it.",
        target = function() local b = ns.MinimapButton.button return b and b:IsShown() and b end,
    },
    {
        title = "Your camp buffs",
        text = "The Camp tab shows the buffs from the last camp you rested at, and how long they last. Sit by a fire for a minute to get them.\n\nThe row of icons under them is every camp buff, lit for the ones you have. Hover one for the objects that give it; click it for the Handbook.",
        show = OpenTab("camp"),
        target = function() return Page("camp").card end,
    },
    {
        title = "Tell others, or find a camp",
        text = "At a camp, Say and General post a short message about it. Nothing is ever posted unless you click.\n\nFind a camp opens the map and shows only camps with the buffs you want.",
        standardText = "At a camp, Say and General post a short message about it. Nothing is ever posted unless you click.\n\nFind a camp opens the map, with the camps around you.",
        show = OpenTab("camp"),
        target = function()
            local page = Page("camp")
            if page.tell:IsShown() then return page.tell, page.find end
            return page.find
        end,
    },
    {
        title = "At a camp",
        text = "At a camp, this tab shows its name and song, and the other Happy Campers there with their level, class and professions. Inspect or whisper them from the list.\n\nWhoever set up the camp names it in its first 15 minutes, and picks its song any time. Anyone can mute the song, or perform a song they've found.",
        show = OpenTab("camp"),
        -- The camp's name and song only show at a camp; the people list always does.
        target = function()
            local page = Page("camp")
            if page.manage:IsShown() then return page.manage, page.list end
            return page.peopleHeader, page.list
        end,
    },
    {
        title = "Badges",
        text = "Camping earns badges: bronze, silver and gold for every zone and for placing each profession's camp objects. They're shared by all your characters.\n\nSome places are worth a visit. Rest by a fire somewhere unusual and you may find something special.",
        -- Said instead once the class badges show (Badges.CLASS_ART_READY).
        classText = "Camping earns badges: bronze, silver and gold for every zone, for placing each profession's camp objects, and for resting as each class at levels 15, 40 and 60. They're shared by all your characters.\n\nSome places are worth a visit. Rest by a fire somewhere unusual and you may find something special.",
        show = OpenTab("badges"),
        target = function() return Page("badges") end,
    },
    {
        title = "Music",
        text = "Happy Camper has songs of its own, each found at one place in the world: rest at a camp there to learn it. The Music tab lists the songs you've found, and hints at where the rest are.\n\nAt a camp, listen to one here, just for you, or perform it for everyone there from the Camp tab.",
        show = OpenTab("music"),
        target = function() return Page("music") end,
    },
    {
        title = "Handbook",
        text = "Every camp object and campfire kit in one place: what each one gives and what it lets you do, which profession makes it and from what, where its recipe or blueprint comes from, and whether you can make it.",
        show = OpenTab("handbook"),
        target = function() return Page("handbook") end,
    },
    {
        title = "Group",
        text = "Planning a camp with your party or raid? Everyone with Happy Camper shows up here with the camp objects they carry. It shows which buffs are worth bringing and which add nothing because a class buff already gives them.\n\nThe leader picks who places what, and can post the plan in group chat.",
        show = OpenTab("group"),
        target = function() return Page("group") end,
        enhanced = true,
    },
    {
        title = "Camp Builder",
        text = "Want a camp with certain buffs? Pick the camp benefits you'd like and post a request with a meet-up point. Players who can bring them get a heads-up and can sign up.\n\nBelow, you can join other players' camps.",
        show = OpenTab("finder"),
        target = function() return Page("finder") end,
        enhanced = true,
    },
    {
        title = "The camp bar",
        text = "This bar shows how many camps are on the map, and how many other Happy Campers were seen today. Its buttons show or hide camps, camps on other layers, recent camps (ashes) and popular campsites, and open the Camp Builder and Options. Your camp buff and object cooldown are on the right.",
        standardText = "This bar shows how many camps are on the map, and how many other Happy Campers were seen today. Its buttons show or hide camps, camps on other layers, recent camps (ashes) and popular campsites, and open Options. Your camp buff and object cooldown are on the right.",
        show = function()
            ns.Hub:Close()
            OpenMap()
        end,
        target = function() return ns.MapBar.bar and ns.MapBar.bar:IsShown() and ns.MapBar.bar end,
        place = "above",
    },
    {
        title = "Camps on the map",
        text = "Each camp shows as a fire on the map. Hover one to see its name, how long the fire will burn, and the equipment there with the buffs it gives.\n\nA grey campfire is ashes, where a camp burned out lately. An orange circle is a popular campsite, where players often camp: light a fire there, and others will see it.\n\nThis one is just an example. It goes away when you move on.",
        standardText = "Each camp shows as smoke on the map: its fire is somewhere in it. Hover one to see its name and how long the fire will burn.\n\nA grey campfire is ashes, where a camp burned out lately. An orange circle is a popular campsite, where players often camp: light a fire there, and others will see it.\n\nThis one is just an example. It goes away when you move on.",
        show = function()
            OpenMap()
            AddDemoCamp()
            local pin = DemoPin()
            if pin then
                ns.ShowLiveTooltip(pin, "ANCHOR_LEFT", function(tooltip) ns.MapBar:FillCampTooltip(tooltip, demoCamp, pin.hazy) end)
            end
        end,
        leave = RemoveDemoCamp,
        target = DemoPin,
    },
    {
        title = "Find a camp",
        text = "Pick the camp benefits you're looking for, or a quick pick for Melee, Caster or Balanced, and only camps that have them show on the map. You can also choose how many of them a camp needs.",
        show = function()
            OpenMap()
        end,
        target = function() return ns.Search.bar end,
        place = "above",
        enhanced = true,
    },
    {
        title = "The Campsite Assistant",
        text = "The Happy Camper icon on your screen is your Campsite Assistant. Click it to open it: your campfire kit, your camp objects, a sleeping bag, and slots for food and drink, potions and elixirs, and weapon buffs (right-click a slot to pick what goes in it). Its two dials show your camp buffs and Well Fed, their rings counting down the time left. Near a fire, Sit sits you down.\n\nRight-click the icon for the Happy Camper window. Drag it anywhere; near a screen edge it sits against it. Options can turn it off, start it hidden, resize it, hide the slots, add extra ones, or lay it out in a circle or open it another way.\n\nKeys: in Esc > Options > Keybindings > AddOns, Happy Camper has one to open or close the Assistant and one for each slot. A slot's key uses what's in it, even with the Assistant closed.",
        show = function()
            CloseMap()
            ns.Widget:ShowForGuide(true)
        end,
        leave = function() ns.Widget:ShowForGuide(false) end,
        target = function() return ns.Widget.frame end,
    },
    {
        title = "Send feedback",
        text = "Found a bug, or have an idea? Send feedback here in Options (or type /hc feedback). It goes straight to the developer.",
        show = function()
            ns.Widget:ShowForGuide(false)
            ns.Hub:Open("options")
        end,
        target = function() return Page("options").feedback end,
    },
    {
        title = "That's it. Happy camping!",
        text = "Type /hc to open the Happy Camper window, or /hc help for all commands. To see this guide again, use Show the guide in Options, or type /hc guide.\n\nThe more campers, the merrier: tell your friends about Happy Camper!",
        show = function()
            CloseMap()
        end,
    },
}
Guide.STEPS = STEPS

-- The steps in the language in use (Locale.lua).
ns.OnLocale(function() ns.LocalizeFields(STEPS, "title", "text", "classText", "standardText") end)

-- The steps for the mode in use (Mode.lua).
local function ActiveSteps()
    local steps = {}
    for _, step in ipairs(STEPS) do
        if not step.enhanced or ns.IsEnhanced() then steps[#steps + 1] = step end
    end
    return steps
end

-- The pulsing highlight around the step's target.
local function CreateHighlight()
    local h = CreateFrame("Frame", "HappyCamperGuideHighlight", UIParent, "BackdropTemplate")
    h:SetFrameStrata("FULLSCREEN_DIALOG")
    h:EnableMouse(false)
    h:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 3 })
    h:SetBackdropBorderColor(ORANGE[1], ORANGE[2], ORANGE[3], 1)
    h.glow = h:CreateTexture(nil, "BACKGROUND")
    h.glow:SetAllPoints()
    h.glow:SetColorTexture(ORANGE[1], ORANGE[2], ORANGE[3], 0.12)
    local t = 0
    h:SetScript("OnUpdate", function(self, elapsed)
        t = t + elapsed
        self:SetAlpha(0.6 + 0.4 * math.sin(t * 4))
    end)
    h:Hide()
    return h
end

function Guide:Create()
    local style = ns.Style
    local f = style:Window("HappyCamperGuide", WIDTH, HEIGHT, "FULLSCREEN_DIALOG", L["Happy Camper Guide"],
        "Interface\\Icons\\INV_Misc_Book_09")

    f.heading = style:Text(f, "GameFontNormalLarge", nil, "LEFT")
    f.heading:SetPoint("TOPLEFT", 70, -34)
    f.heading:SetPoint("RIGHT", -16, 0)
    f.body = style:Text(f, "GameFontHighlight", nil, "LEFT")
    f.body:SetPoint("TOPLEFT", 20, -64)
    f.body:SetWidth(WIDTH - 40)
    f.body:SetSpacing(2)
    f.counter = style:Text(f, "GameFontDisableSmall")
    f.counter:SetPoint("BOTTOM", 0, 40)

    f.skip = style:Button(f, 90, L["Skip guide"], function() Guide:Finish() end)
    f.skip:SetPoint("BOTTOMLEFT", 14, 12)
    f.next = style:Button(f, 90, L["Next"], function() Guide:Go(Guide.step + 1) end)
    f.next:SetPoint("BOTTOMRIGHT", -14, 12)
    f.back = style:Button(f, 90, L["Back"], function() Guide:Go(Guide.step - 1) end)
    f.back:SetPoint("RIGHT", f.next, "LEFT", -6, 0)

    -- Closing the window (X or Escape) counts as skipping; the whole UI being
    -- hidden (the cinematic camera) doesn't: the window itself is still shown.
    f:SetScript("OnHide", function(self) if Guide.running and not self:IsShown() then Guide:Finish() end end)

    self.frame = f
    self.highlight = CreateHighlight()
end

-- Puts the guide beside the target (or above it), else near the top of the screen.
local function Place(f, first, last, place)
    f:ClearAllPoints()
    local left, right = first and first:GetLeft(), last and last:GetRight()
    local screen = UIParent:GetWidth() or 0
    if first and place == "above" then
        f:SetPoint("BOTTOM", first, "TOP", 0, 24)
    elseif right and right + 20 + WIDTH < screen then
        f:SetPoint("TOPLEFT", last, "TOPRIGHT", 20, 0)
    elseif left and left - 20 - WIDTH > 0 then
        f:SetPoint("TOPRIGHT", first, "TOPLEFT", -20, 0)
    else
        f:SetPoint("TOP", UIParent, "TOP", 0, -120)
    end
end

function Guide:Go(index)
    local steps = self.steps or ActiveSteps()
    if index < 1 then return end
    if index > #steps then return self:Finish() end
    local previous = self.step and steps[self.step]
    if previous and previous.leave and self.step ~= index then previous.leave() end
    self.step = index
    local step, f, h = steps[index], self.frame, self.highlight
    if step.show then step.show() end

    f.heading:SetText(step.title)
    local text = step.classText and ns.Badges.CLASS_ART_READY and step.classText or step.text
    if step.standardText and not ns.IsEnhanced() then text = step.standardText end
    f.body:SetText(text)
    -- Grow to fit the text, so nothing is cut off.
    f:SetHeight(math.max(HEIGHT, 64 + ns.Style:TextHeight(f.body) + 76))
    f.counter:SetText(format(L["Step %d of %d"], index, #steps))
    f.back:SetEnabled(index > 1)
    -- Back and Next side by side: one size, the wider of their texts' (Next's changes).
    f.back:SetText(L["Back"])
    f.next:SetText(index == #steps and L["Finish"] or L["Next"])
    ns.Style:SameWidth({ f.back, f.next }, 90)
    f.skip:SetShown(index < #steps)

    local first, last
    if step.target then first, last = step.target() end
    last = last or first
    h:ClearAllPoints()
    if first then
        h:SetPoint("TOPLEFT", first, "TOPLEFT", -6, 6)
        h:SetPoint("BOTTOMRIGHT", last, "BOTTOMRIGHT", 6, -6)
        h:Show()
    else
        h:Hide()
    end
    Place(f, first, last, step.place)
    f:Show()
end

function Guide:Start()
    if not self.frame then self:Create() end
    if self.running then return self:Go(self.step) end
    -- Remember what was open, to put it back afterwards.
    self.before = {
        hub = ns.Hub:IsShowing() and (ns.Hub.current or "camp"),
        map = WorldMapFrame and WorldMapFrame:IsShown(),
    }
    self.running = true
    self.steps = ActiveSteps()
    self:Go(1)
end

-- Ends the guide (finished or skipped); it won't start by itself again.
function Guide:Finish()
    ns.db.guideSeen = true
    if not self.running then return end
    self.running = false
    local current = (self.steps or STEPS)[self.step or 0]
    if current and current.leave then current.leave() end
    self.highlight:Hide()
    self.frame:Hide()
    local before = self.before or {}
    if not before.map then CloseMap() end
    if before.hub then ns.Hub:Open(before.hub) else ns.Hub:Close() end
end

-- First login with the addon: start the guide once you're out of combat, and
-- once Standard or Enhanced is chosen (the question starts it after its answer,
-- so it never covers it).
function Guide:MaybeAutoStart()
    if ns.db.guideSeen or self.running or ns.db.mode == nil then return end
    if ns.InCombat() then
        C_Timer.After(10, function() Guide:MaybeAutoStart() end)
        return
    end
    self:Start()
end
