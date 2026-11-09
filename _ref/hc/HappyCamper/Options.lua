-- Happy Camper. Copyright (c) 2026 Torridon. All rights reserved; see LICENSE.
local _, ns = ...
local L = ns.L

-- Options tab of the Happy Camper window.

local Options = {}
ns.Options = Options

local ROW = 23
local BUTTON_WIDTH, BUTTON_GAP = 140, 10
local BUTTON_ROW = 28     -- from one row of buttons under the settings to the next
local SCROLLBAR = 14      -- room on the right for the scroll bar, inside the panel
local SECTION_GAP = 10

-- { key, label, tip, onChange } in display order; "header" rows are section
-- titles. Labels stay short; tip (shown on hover with help tips on) says more.
-- enhanced: only in Enhanced mode (Mode.lua); the rows close up without it.
local SETTINGS = {
    { header = "General" },
    { key = "language", label = "Language:", reload = true,
      choices = { { "auto", "The game's language" } } },
    -- Standard or Enhanced (Mode.lua): applies at once. Not chosen yet shows as Enhanced.
    { key = "mode", label = "Mode:",
      choices = { { "standard", "Standard" }, { "enhanced", "Enhanced" } },
      get = function() return ns.Mode:Current() end, onChange = function(value) ns.Mode:Set(value) end },
    { key = "helpTips", label = "Help tips on hover", tip = "Show help tips on hover (what buttons and menus do)" },
    { key = "minimapButton", label = "Minimap button", tip = "Show the minimap button",
      onChange = function() ns.MinimapButton:Refresh() end },
    { key = "chatNotes", label = "Status messages in chat", tip = "Show status messages in chat (like \"camp buffs active\")" },
    { header = "Campsite Assistant" },
    { key = "widget", label = "Show the Campsite Assistant", tip = "Show the Happy Camper icon with your campfire, camp objects, food and weapon buffs, and your camp buff and Well Fed timers", onChange = function(on)
        if not ns.Widget then return end
        if on then ns.Widget.hidden = false end
        ns.Widget:Update()
    end },
    { key = "widgetStartHidden", label = "Start hidden at login", tip = "Start it hidden when I log in", indent = true },
    { key = "widgetLocked", label = "Lock its position", indent = true },
    { key = "widgetSize", label = "Size:", indent = true, tip = "How big the Campsite Assistant is on screen",
      slider = { min = 50, max = 150, step = 5, format = "%d%%" },
      onChange = function() if ns.Widget then ns.Widget:Update() end end },
    { key = "widgetShape", label = "Layout:", indent = true,
      choices = { { "flat", "Flat" }, { "round", "Circular" } },
      onChange = function() if ns.Widget then ns.Widget:Update() end end },
    { key = "widgetDirection", label = "Away from an edge:", indent = true,
      choices = { { "DOWN", "Opens down" }, { "UP", "Opens up" }, { "LEFT", "Opens left" }, { "RIGHT", "Opens right" } },
      onChange = function() if ns.Widget then ns.Widget:Update() end end },
    { key = "widgetButtons", label = "Item slots and Sit", tip = "Show your campfire kit, camp objects, sleeping bag, food and drink, potions, weapon buffs, and Sit",
      indent = true, onChange = function() if ns.Widget then ns.Widget:Update() end end },
    -- Extra slots after the potion one, each a potion, first aid or any-item
    -- slot (its row shows once it's added).
    { key = "widgetExtras", label = "Extra slots:", indent = true,
      choices = { { 0, "None" }, { 1, "1 slot" }, { 2, "2 slots" }, { 3, "3 slots" } },
      onChange = function() if ns.Widget then ns.Widget:Update() end end },
    { key = "widgetExtra1", label = "Extra slot 1:", indent = true, shownIf = function() return (ns.db.widgetExtras or 0) >= 1 end,
      choices = { { "potion", "Potion or elixir" }, { "firstaid", "First aid" }, { "any", "Any item" } },
      onChange = function() if ns.Widget then ns.Widget:Update() end end },
    { key = "widgetExtra2", label = "Extra slot 2:", indent = true, shownIf = function() return (ns.db.widgetExtras or 0) >= 2 end,
      choices = { { "potion", "Potion or elixir" }, { "firstaid", "First aid" }, { "any", "Any item" } },
      onChange = function() if ns.Widget then ns.Widget:Update() end end },
    { key = "widgetExtra3", label = "Extra slot 3:", indent = true, shownIf = function() return (ns.db.widgetExtras or 0) >= 3 end,
      choices = { { "potion", "Potion or elixir" }, { "firstaid", "First aid" }, { "any", "Any item" } },
      onChange = function() if ns.Widget then ns.Widget:Update() end end },
    { key = "widgetWellFed", label = "Well Fed timer", tip = "Show how long Well Fed has left",
      indent = true, onChange = function() if ns.Widget then ns.Widget:Update() end end },
    { key = "widgetEatReminder", label = "Remind me to eat at camp", tip = "At a camp, the Well Fed timer and your food glow while you're not Well Fed",
      indent = true, onChange = function() if ns.Widget then ns.Widget:Update() end end },
    { header = "Map" },
    { key = "mapBar", label = "Camp bar under the world map", tip = "Show the camp bar under the world map",
      onChange = function() ns.MapBar:Refresh() end },
    { key = "campersSeen", label = "Campers seen today", tip = "Show on the camp bar how many other Happy Campers were seen today",
      indent = true, onChange = function() ns.MapBar:Refresh() end },
    { key = "mapPins", label = "Camps on the world map", tip = "Show camps on the world map", onChange = function(on) ns.SetShowCamps(on) end },
    -- Continents' and the world's maps (ns.WideMapStyle): the open map changes at once.
    { key = "worldMapCamps", label = "Continent and world maps:", indent = true, get = function() return ns.WideMapStyle() end,
      choices = { { "grouped", "Grouped, with counts" }, { "all", "Every camp" }, { "none", "No camps" } }, onChange = function()
        ns.MapPins:Refresh()
        ns.MapBar:Refresh()
    end },
    { key = "showOtherLayers", label = "Camps on other layers (faded)", tip = "Show camps on other layers (faded)", indent = true,
      onChange = function() ns.OnCampsChanged() end },
    -- Ashes and popular campsites (Campsites.lua); the camp bar has them too.
    { key = "mapAshes", label = "Recent camps (ashes)", tip = "Show where camps burned out in the last 3 hours, as ashes", indent = true,
      onChange = function() ns.OnCampsChanged() end },
    { key = "mapCampsites", label = "Popular campsites", tip = "Show spots where players often camp, as orange circles", indent = true,
      onChange = function() ns.OnCampsChanged() end },
    { key = "minimapPins", label = "Camps on the minimap", tip = "Show nearby camps on the minimap", onChange = function() ns.OnCampsChanged() end },
    { header = "Sharing" },
    { key = "network", label = "Share camps with other players",
      tip = "Share camps with other players using the addon, over a hidden chat channel (HappyCamper). Untick to leave it.", onChange = function(on)
        if on then ns.Comm:Connect() else ns.Comm:Disconnect() end
    end },
    -- Said in your presence at once (LayerInvites.lua); turned off, an ask on screen closes.
    { key = "layerInvites", label = "Let other layers ask to join mine", tip = "Let players on other layers ask to join my layer",
      indent = true, onChange = function(on)
        if not on then ns.LayerInvites:Close() end
        if ns.Social:IsAtCamp() then ns.Social:SendPresence(false) end
    end },
    { key = "chatPins", label = "Camps from map pins in chat", tip = "Add camps from campfire map pins posted in chat", onChange = function(on)
        if not on then ns.ChatPins:Clear() end
    end },
    -- Their camps are under this option only, chat posts included (Others.lua);
    -- the chat pins option above is for players' own posts.
    { key = "otherAddons", label = "Camps from other camp addons",
      tip = "Show camps shared by other camp addons (Camping Kit, CozyFire, Campfire Assistant)", onChange = function(on)
        if on then ns.Others:Connect() else ns.Others:Disconnect() end
    end },
    -- Each channel takes one of the player's chat channel slots (Others.lua).
    { key = "otherChannels", label = "Join Camping Kit's channel", indent = true,
      tip = "Camping Kit shares camps on a hidden chat channel (CampingKitNet). Untick to leave it and free a chat channel for your own.",
      onChange = function(on) ns.Others:SetChannels(on) end },
    { header = "At camp" },
    { key = "circleAutoOpen", label = "Open this window when I sit", tip = "Open this window when I sit at a camp" },
    { key = "classBuffCheck", label = "Mark buffs my class already gives (red)", tip = "Mark camp buffs my class buffs already give me (red)" },
    -- Share this camp's Say and General buttons in your own words: the editor
    -- (AnnounceEditor.lua) opens at once the first time it's ticked.
    { key = "announceOwn", label = "My own camp announcement",
      tip = "Share this camp's Say and General buttons post a line you write, with the map pin and buffs filled in",
      button = { text = "Edit wording...", onClick = function() ns.AnnounceEditor:Open() end },
      onChange = function(on)
        if on and (ns.db.announceText or "") == "" then ns.AnnounceEditor:Open(true) end
    end },
    { key = "notifyRequests", label = "Tell me about camp requests nearby", tip = "Tell me about nearby camp requests I can help with",
      enhanced = true },
    { header = "Music" },
    { key = "campMusic", label = "Hear others' songs and lute", tip = "Play songs and lute from others at my camp" },
    { key = "autoSong", label = "Play my song at my fires", tip = "Play my song at fires I light and camps I set up" },
    { header = "Alerts" },
    { key = "nearbyNotice", label = "Campfire nearby notice", tip = "Tell me on screen when I'm near a campfire" },
    { key = "badgeToast", label = "New badges on screen", tip = "Show badges I earn on screen" },
    { key = "songToast", label = "New songs on screen", tip = "Show songs I find on screen, with a few seconds of each" },
    { key = "buffWarning", label = "Warn before camp buffs end", tip = "Warn me before my camp buffs end" },
    { key = "readyCheckSummary", label = "Camp buffs at ready checks",
      tip = "At a ready check, tell me (only me) who in my group has no camp buffs" },
    { key = "warnSeconds", label = "How long before:", indent = true,
      choices = { { 60, "1 minute" }, { 120, "2 minutes" }, { 300, "5 minutes" }, { 600, "10 minutes" }, { 900, "15 minutes" } } },
    { header = "Cinematic camera" },
    { key = "cinematic", label = "Start when resting at a camp", tip = "Cinematic camera when resting at a camp", onChange = function(on)
        if not on then ns.Cinematic:Stop() end
    end },
    { key = "cinematicPan", label = "Slowly pan around", tip = "Slowly pan around the camp", indent = true },
    { key = "cinematicHideUI", label = "Hide the interface", tip = "Hide the interface while it plays (untick to keep it)", indent = true },
    { key = "cinematicHideNames", label = "Hide player names",
      tip = "Your name and other players' names are hidden while it plays, and come back after.", indent = true },
    { key = "cinematicZoom", label = "Zoom out", tip = "Zoom the camera out", indent = true },
}

Options.SETTINGS = SETTINGS -- for backups (Backup.lua)

-- The languages to pick from, each in its own language.
for _, language in ipairs(ns.LANGUAGES) do table.insert(SETTINGS[2].choices, { language[1], language[2] }) end

-- The settings' text in the language in use (Locale.lua).
ns.OnLocale(function(L)
    ns.LocalizeFields(SETTINGS, "label", "header", "tip")
    for _, setting in ipairs(SETTINGS) do
        for _, choice in ipairs(setting.choices or {}) do choice[2] = L[choice[2]] end
        if setting.button then setting.button.text = L[setting.button.text] end
    end
end)

-- Labelled rows, a dropdown or a slider, are two columns: the label on the
-- left (wrapping if it's long, a translation), and the control on the right,
-- every one the same width and starting at the same place, CONTROL_RIGHT in
-- from the panel's right edge. A tickbox's button (setting.button) lines up with them.
local CONTROL_WIDTH = 190
local CONTROL_RIGHT = 6

-- How much taller than one line a wrapped label is (0 for one line).
local function ExtraLines(text)
    local height, line = text:GetStringHeight(), select(2, text:GetFont())
    if type(height) ~= "number" or type(line) ~= "number" or height - line < line / 2 then return 0 end
    return math.ceil(height - line)
end

-- A checkbox and its label. Returns it, and how much more than a row it takes:
-- a long label (a translation) wraps within the panel instead of running
-- under its edge. With setting.button, a button sits where the dropdowns are,
-- level with the box, and the label wraps before it.
local function CreateCheckbox(parent, setting, y)
    local check = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    local x = setting.indent and 24 or 4
    check:SetSize(24, 24)
    check:SetPoint("TOPLEFT", x, y)
    check.Text:SetFontObject("GameFontHighlight")
    -- Its first line level with the box, any more below it.
    check.Text:ClearAllPoints()
    check.Text:SetPoint("TOPLEFT", check, "TOPRIGHT", -2, -6)
    local right = parent:GetWidth() - 4
    if setting.button then
        -- Its right edge where the dropdowns' is: a longer translation grows it leftwards.
        check.button = ns.Style:Button(parent, CONTROL_WIDTH, setting.button.text, setting.button.onClick, 22)
        check.button:SetPoint("RIGHT", check, "LEFT", parent:GetWidth() - CONTROL_RIGHT - x, 0)
        if setting.tip then ns.Style:Tooltip(check.button, setting.button.text, setting.tip) end
        right = parent:GetWidth() - CONTROL_RIGHT - check.button:GetWidth() - 10
    end
    check.Text:SetWidth(right - (x + 22))
    check.Text:SetJustifyH("LEFT")
    check.Text:SetWordWrap(true)
    check.Text:SetText(setting.label)
    check:SetScript("OnClick", function(self)
        local on = self:GetChecked()
        ns.db[setting.key] = on
        if setting.onChange then setting.onChange(on) end
    end)
    if setting.tip then ns.Style:Tooltip(check, setting.label, setting.tip, "ANCHOR_RIGHT") end
    check.setting = setting
    return check, ExtraLines(check.Text)
end

-- A setting's value: its own get, else what's saved.
local function Value(setting)
    if setting.get then return setting.get() end
    return ns.db[setting.key]
end

-- A dropdown's or slider's label, and where across the panel its control
-- starts (its label wraps before it).
local function RowLabel(parent, setting, y, x)
    local column = parent:GetWidth() - CONTROL_RIGHT - CONTROL_WIDTH
    local label = ns.Style:Text(parent, "GameFontHighlight", setting.label)
    label:SetPoint("TOPLEFT", x, y - 5)
    label:SetWidth(column - x - 10)
    label:SetJustifyH("LEFT")
    label:SetWordWrap(true)
    return label, column
end

-- A labelled dropdown for a setting with a few choices ({ value, text }, ...).
-- Returns it, and how much more than a row it takes (a label on two lines).
local function CreateChoice(parent, setting, y)
    local x = setting.indent and 30 or 10
    local label, column = RowLabel(parent, setting, y, x)
    local dropdown = ns.Style:Dropdown(parent, CONTROL_WIDTH, function(_, root)
        for _, choice in ipairs(setting.choices) do
            root:CreateRadio(choice[2], function(value) return Value(setting) == value end,
                function(value)
                    ns.db[setting.key] = value
                    Options:Sync()
                    if setting.onChange then setting.onChange(value) end
                end, choice[1])
        end
    end)
    dropdown:SetPoint("LEFT", label, "LEFT", column - x, 0)
    dropdown.setting, dropdown.label = setting, label
    -- The language changes on a reload (it's picked as the addon loads): Reload
    -- now goes under its menu, and has a row only while it shows.
    if setting.reload then
        local menuHeight = dropdown:GetHeight()
        menuHeight = type(menuHeight) == "number" and menuHeight > 0 and menuHeight or 22
        dropdown.reload = ns.Style:Button(parent, 110, L["Reload now"], function() ReloadUI() end, menuHeight)
        ns.Style:Tooltip(dropdown.reload, L["Reload now"], L["The new language shows after reloading the interface."])
        dropdown.reload:SetPoint("TOPRIGHT", dropdown, "BOTTOMRIGHT", 0, -2)
        dropdown.reload:Hide()
        dropdown.reloadRow = menuHeight + 2
    end
    -- A button under its menu, the menu's width (or wider for a translation),
    -- with a row of its own while setting.button.shownIf() says so (Layout).
    if setting.button then
        local menuHeight = dropdown:GetHeight()
        menuHeight = type(menuHeight) == "number" and menuHeight > 0 and menuHeight or 22
        dropdown.below = ns.Style:Button(parent, CONTROL_WIDTH, setting.button.text, setting.button.onClick, menuHeight)
        dropdown.below:SetPoint("TOPRIGHT", dropdown, "BOTTOMRIGHT", 0, -2)
        dropdown.below:Hide()
        dropdown.belowRow = menuHeight + 2
    end
    return dropdown, ExtraLines(label)
end

-- A labelled slider for a setting with a range (setting.slider = { min, max,
-- step, format }), its value beside it: a dark groove edged in gold, and the
-- game's slider knob. Returns it, and how much more than a row it takes.
local SLIDER_VALUE = 44 -- room at its right for its value ("150%")
local function CreateSlider(parent, setting, y)
    local spec = setting.slider
    local x = setting.indent and 30 or 10
    local label, column = RowLabel(parent, setting, y, x)
    local slider = CreateFrame("Slider", nil, parent)
    slider:SetOrientation("HORIZONTAL")
    slider:SetSize(CONTROL_WIDTH - SLIDER_VALUE - 6, 16)
    slider:SetPoint("LEFT", label, "LEFT", column - x + 6, 0)
    slider:SetMinMaxValues(spec.min, spec.max)
    slider:SetValueStep(spec.step)
    if slider.SetObeyStepOnDrag then slider:SetObeyStepOnDrag(true) end
    local edge = slider:CreateTexture(nil, "BACKGROUND", nil, 0)
    edge:SetColorTexture(1, 0.82, 0.4, 0.35)
    edge:SetPoint("LEFT", -1, 0)
    edge:SetPoint("RIGHT", 1, 0)
    edge:SetHeight(8)
    local groove = slider:CreateTexture(nil, "BACKGROUND", nil, 1)
    groove:SetColorTexture(0.08, 0.06, 0.04, 0.95)
    groove:SetPoint("LEFT")
    groove:SetPoint("RIGHT")
    groove:SetHeight(6)
    slider:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
    slider.value = ns.Style:Text(parent, "GameFontHighlightSmall")
    slider.value:SetPoint("LEFT", slider, "RIGHT", 10, 0)
    slider:SetScript("OnValueChanged", function(self, value)
        value = math.floor(value / spec.step + 0.5) * spec.step
        self.value:SetText(format(spec.format or "%d", value))
        if self.syncing or ns.db[setting.key] == value then return end
        ns.db[setting.key] = value
        if setting.onChange then setting.onChange(value) end
    end)
    if setting.tip then ns.Style:Tooltip(slider, setting.label, setting.tip, "ANCHOR_RIGHT") end
    slider.setting, slider.label = setting, label
    return slider, ExtraLines(label)
end

-- A section title: centred, in larger text, with a fine line either side.
local HEADER_ROW = 30
local function SectionHeader(parent, text)
    local title = ns.Style:Text(parent, "GameFontNormalLarge", text)
    title.lines = {}
    for i, side in ipairs({ "RIGHT", "LEFT" }) do
        local line = parent:CreateTexture(nil, "ARTWORK")
        line:SetColorTexture(1, 0.82, 0.4, 0.35)
        line:SetHeight(1)
        line:SetPoint(side, title, i == 1 and "LEFT" or "RIGHT", i == 1 and -10 or 10, 0)
        title.lines[i] = line
    end
    return title
end

-- Each section title's lines reach from it to the panel's sides.
local function SizeHeaderLines(title, width)
    local each = math.max(0, (width - ns.Style:TextWidth(title)) / 2 - 18)
    for _, line in ipairs(title.lines) do line:SetWidth(each) end
end

local function CreateButton(parent, text, onClick)
    return ns.Style:Button(parent, BUTTON_WIDTH, text, onClick)
end

-- The buttons under the settings, in rows of one width, each centred: three
-- to a row when they fit in the window, else two (a long translation).
-- Returns how tall they are, from the bottom of the page.
local function PlaceButtons(page, window)
    local function Row(buttons, bottom)
        local each = ns.Style:SameWidth(buttons, BUTTON_WIDTH)
        local width = #buttons * each + (#buttons - 1) * BUTTON_GAP
        for i, button in ipairs(buttons) do
            button:SetPoint("BOTTOMLEFT", page, "BOTTOM", -width / 2 + (i - 1) * (each + BUTTON_GAP), bottom)
        end
    end
    local top = { page.cinematic, page.forget, page.guide }
    local each = ns.Style:SameWidth(top, BUTTON_WIDTH)
    local rows
    if #top * each + (#top - 1) * BUTTON_GAP <= window:GetWidth() - 20 then
        rows = { top, { page.feedback, page.backup } }
    else
        ns.Style:SameWidth({ page.cinematic, page.forget, page.guide, page.feedback, page.backup }, BUTTON_WIDTH)
        rows = { { page.cinematic, page.guide }, { page.forget, page.backup }, { page.feedback } }
    end
    for i, buttons in ipairs(rows) do Row(buttons, 6 + (#rows - i) * BUTTON_ROW) end
    return #rows * BUTTON_ROW + 8
end

-- Builds the tab's contents inside the Happy Camper window's page frame. The
-- settings scroll inside a panel that stays put (its scroll bar inside its
-- right edge); the buttons sit under it, always in view.
function Options:Build(page)
    local window = page:GetParent()
    page.cinematic = CreateButton(page, L["Try cinematic now"], function()
        -- It can't start mounted, moving, in combat or dead: say so, and keep the window open.
        if not ns.Cinematic:CanStart() and not ns.Cinematic:IsActive() then
            return ns.Print(L["The cinematic camera can't start while mounted, moving, in combat or dead."])
        end
        ns.Hub:Close()
        ns.Cinematic:Start()
    end)
    page.forget = CreateButton(page, L["Forget known camps"], function()
        -- Your own camps stay: nobody else can send them back to you, and
        -- resting at your fire again would report it as a second camp.
        for id, camp in pairs(ns.db.camps) do
            if not ns.Camps:IsMine(camp) then ns.db.camps[id] = nil end
        end
        if ns.state.selectedCampID and not ns.Camps:Get(ns.state.selectedCampID) then ns.state.selectedCampID = nil end
        ns.OnCampsChanged()
        ns.Print(L["Other players' camps cleared. Yours stay."])
    end)
    page.guide = CreateButton(page, L["Show the guide"], function() ns.Guide:Start() end)
    page.feedback = CreateButton(page, L["Send feedback"], function() ns.Feedback:Open() end)
    ns.Style:Tooltip(page.feedback, L["Send feedback"], L["Report a bug or share an idea with the developer."])
    page.backup = CreateButton(page, L["Backup"], function() ns.Backup:Open() end)
    ns.Style:Tooltip(page.backup, L["Backup"], L["Save your badges, songs, settings and own lines as a code, or restore them from one."])
    local buttonsHeight = PlaceButtons(page, window)

    local inset = ns.Style:Inset(page, window, 10, 0, 10, 0)
    inset:ClearAllPoints()
    inset:SetPoint("TOPLEFT", page, "TOPLEFT", 10, 0)
    inset:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", -10, buttonsHeight)
    local scroll = CreateFrame("ScrollFrame", nil, page)
    scroll:SetPoint("TOPLEFT", 16, -6)
    scroll:SetPoint("BOTTOMRIGHT", -16, buttonsHeight + 6)
    scroll:SetFrameLevel(window:GetFrameLevel() + 4)
    ns.Style:ScrollArea(scroll, window:GetWidth() - 32 - SCROLLBAR, 1)
    page.scroll, page.inset = scroll, inset
    local content = scroll.child

    page.checks, page.choices, page.sliders, page.rows = {}, {}, {}, {}
    for _, setting in ipairs(SETTINGS) do
        local row = { setting = setting, extra = 0 }
        if setting.header then
            row.header = SectionHeader(content, setting.header)
            SizeHeaderLines(row.header, window:GetWidth() - 32 - SCROLLBAR)
        elseif setting.slider then
            row.widget, row.extra = CreateSlider(content, setting, 0)
            page.sliders[#page.sliders + 1] = row.widget
        elseif setting.choices then
            row.widget, row.extra = CreateChoice(content, setting, 0)
            page.choices[#page.choices + 1] = row.widget
        else
            row.widget, row.extra = CreateCheckbox(content, setting, 0)
            page.checks[#page.checks + 1] = row.widget
        end
        page.rows[#page.rows + 1] = row
    end
    self.frame = page
    self:Layout()
end

-- Places the rows top to bottom; Enhanced-only ones (setting.enhanced) are
-- left out in Standard mode, and ones whose shownIf says no (an extra slot not
-- added yet), the rest closing up.
function Options:Layout()
    local page = self.frame
    if not page then return end
    local enhanced = not ns.IsEnhanced or ns.IsEnhanced()
    local content = page.scroll.child
    local y = -4
    for i, row in ipairs(page.rows) do
        local setting = row.setting
        local shown = (enhanced or not setting.enhanced) and (not setting.shownIf or setting.shownIf())
        if row.header then
            -- A little room above each section but the first.
            if i > 1 then y = y - SECTION_GAP end
            row.header:ClearAllPoints()
            row.header:SetPoint("TOP", content, "TOP", 0, y - 6)
            y = y - HEADER_ROW
        else
            -- A dropdown or slider hangs off its label; a checkbox is placed itself.
            local labelled = setting.choices or setting.slider
            local anchor = labelled and row.widget.label or row.widget
            anchor:SetShown(shown)
            if labelled then row.widget:SetShown(shown) end
            if row.widget.value then row.widget.value:SetShown(shown) end
            local below = row.widget.below
            if below then below:SetShown(shown and setting.button.shownIf()) end
            if row.widget.button then row.widget.button:SetShown(shown) end
            if shown then
                local x = labelled and (setting.indent and 30 or 10) or (setting.indent and 24 or 4)
                anchor:ClearAllPoints()
                anchor:SetPoint("TOPLEFT", x, labelled and y - 5 or y)
                y = y - ROW - row.extra - (row.widget.reload and row.widget.reload:IsShown() and row.widget.reloadRow or 0)
                    - (below and below:IsShown() and row.widget.belowRow or 0)
            end
        end
    end
    -- Tall enough for every setting; the scroll bar shows only if the panel isn't.
    content:SetHeight(-y + 8)
end

function Options:Sync()
    if not self.frame then return end
    for _, dropdown in ipairs(self.frame.choices) do
        if dropdown.reload then dropdown.reload:SetShown((ns.db.language or "auto") ~= ns.localeChoice) end
    end
    self:Layout()
    for _, check in ipairs(self.frame.checks) do
        check:SetChecked(ns.db[check.setting.key])
    end
    for _, dropdown in ipairs(self.frame.choices) do
        ns.Style:ShowChoice(dropdown, dropdown.setting.choices, Value(dropdown.setting), 1, 2)
    end
    for _, slider in ipairs(self.frame.sliders) do
        local spec, value = slider.setting.slider, Value(slider.setting) or slider.setting.slider.min
        slider.syncing = true
        slider:SetValue(value)
        slider.syncing = false
        slider.value:SetText(format(spec.format or "%d", value))
    end
end

function Options:Toggle()
    ns.Hub:Toggle("options")
end
