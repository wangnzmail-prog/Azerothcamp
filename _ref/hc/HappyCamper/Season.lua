-- Happy Camper. Copyright (c) 2026 Torridon. All rights reserved; see LICENSE.
local _, ns = ...
local L = ns.L

-- The launch choice. WoW Forever is in beta until it launches (4 November
-- 2026). At the first login on the live game:
--   * The beta world's data goes, since it describes beta realms: known camps,
--     requests, players seen, the user count and announcements seen; for each
--     character, its remembered recipes, group plan, fire, object cooldown and
--     session. Quietly, every time.
--   * If the account camped in the beta, the player is asked (a window of our
--     own, ShowChoice): keep the beta badges and camp progress, or start
--     fresh (the beta's badges are archived, read-only, in db.betaArchive, and
--     cleared). Either way they're given the Beta Camper badge as a thank-you
--     (Badges.lua). Until they choose, nothing about progress changes and the
--     account is "pending": closing the window asks again at the next login.
--   * Every setting, your own lines, Find a camp picks and blocked players stay.
--
-- It never happens in the beta: any one sign of the beta keeps it the beta,
-- and a sign that can't be read counts as one. Saved data is marked with the
-- game it's from (db.season: "beta", "pending" or "live"; charDB.season:
-- "beta" or "live"; db.betaChoice: "keep" or "fresh"). Data with no mark is
-- older than this file, so it's the beta's. A live mark is never changed back.

local Season = {}
ns.Season = Season

-- Before this it's the beta, whatever else says: a week before launch, in case
-- of a head start. 2026-10-28 00:00 UTC.
Season.LIVE_FROM = 1793145600

-- What's cleared, and what each starts again as (NEW: an empty table; nil:
-- nothing). The beta world's data, at the first live login whatever the
-- choice; and the progress, only on "Start fresh". Everything else is kept:
-- every Options setting, your own lines (customMessages), Find a camp picks
-- (search), blocked players, camp spells learned (known, ignored), unsent
-- feedback, window places, the open tab, the song and object you picked, your
-- blessing, the language, and the marks of one-time changes. This character's
-- backup copy (charDB.backup) is the Backup's to deal with
-- (Backup:RestoreIfLost): from the beta, it follows the account's choice.
local NEW = {}
Season.ACCOUNT_WORLD = {
    { "camps", NEW },      -- camps known
    { "ashes", NEW },      -- where camps burned out
    { "campsites", NEW },  -- campsites learned from camps seen
    { "requests", NEW },   -- Camp Builder requests
    { "users", NEW },      -- other Happy Camper users seen
    { "census", NEW },     -- the biggest user count anyone reported
    { "broadcasts", NEW }, -- the developer's announcements already shown
}
Season.ACCOUNT_PROGRESS = {
    { "badges", NEW },     -- every badge's progress and counts (archived first)
    { "songs" },           -- found songs (Music.lua)
}
Season.CHARACTER_WORLD = {
    { "campRecipes", NEW },   -- camp recipes remembered (Group.lua)
    { "groupPlan" },          -- the Group tab's plan
    { "litFire" },            -- the fire you lit last
    { "badgeCampAt" },        -- the beta fires counted lately as camps
    { "objectReadyAt" },      -- your camp object's cooldown...
    { "objectName" },
    { "objectSkill" },
    { "placedTier" },
    { "objectIcon" },
    { "objectAlerted", true }, -- ...and its "off cooldown" alert (none due)
    { "tentXPUntil" },        -- the tent's rested XP note
    { "sessionStart" },       -- when this session began (set again at login)
}
-- A character's badges from before they were account-wide: beta progress.
-- They join the account's (Badges:MergeCharacter) while it keeps its beta
-- progress or is still to choose; otherwise they're archived and cleared.
Season.CHARACTER_PROGRESS = {
    { "badges" },
    { "songs" },              -- found songs from before they were the account's (Music.lua)
}

-- The question waits until the chat window and the world are up.
local ASK_DELAY = 10

-- What shows someone camped: a full rest at a fire, a camp made, a camp object
-- placed or a fire lit, a level rested at as a class, or a landmark found.
local EVIDENCE = { "rests", "camps", "placed", "level", "found" }

local function Clear(saved, list)
    for _, entry in ipairs(list) do
        local fresh = entry[2]
        if fresh == NEW then fresh = {} end
        saved[entry[1]] = fresh
    end
end

-- Telling -----------------------------------------------------------------------------

-- Reads the signs. Returns "beta" or "live"; whether it's sure (if a sign
-- couldn't be read, it's the beta for now: never a change on a guess); and the
-- signs, for the dev tools (/hc season):
--   build: IsBetaBuild()'s answer, or nil if this client has none;
--   realms: the realm's names read, and realmBeta: one has "beta" in it;
--   time: the server's time, and early: it's before LIVE_FROM.
function Season:Detect()
    local signs = { realms = {} }
    if type(IsBetaBuild) == "function" then
        local ok, value = pcall(IsBetaBuild)
        if ok and not ns.IsSecret(value) then signs.build = value == true end
    end
    for _, getter in ipairs({ "GetRealmName", "GetNormalizedRealmName" }) do
        local get = _G[getter]
        if type(get) == "function" then
            local ok, realm = pcall(get)
            if ok and not ns.IsSecret(realm) and type(realm) == "string" and realm ~= "" then
                signs.realms[#signs.realms + 1] = realm
                if realm:lower():find("beta", 1, true) then signs.realmBeta = true end
            end
        end
    end
    local ok, now = pcall(GetServerTime)
    if ok and not ns.IsSecret(now) and type(now) == "number" and now > 0 then
        signs.time = now
        signs.early = now < self.LIVE_FROM
    end
    if signs.build or signs.realmBeta or signs.early then return "beta", true, signs end
    if #signs.realms == 0 or not signs.time then return "beta", false, signs end
    return "live", true, signs
end

-- Whether this is the live game: decided so at this login, or the account's
-- data is marked live or still to choose (only ever done there).
function Season:IsLive()
    if self.current == "live" then return true end
    local season = ns.db and ns.db.season
    return season == "live" or season == "pending"
end

-- The mark for data made now (backup codes and copies): "live" once the
-- account's progress is the live game's (chosen, or none from the beta), else
-- "beta" (in the beta, or still to choose).
function Season:Mark()
    return ns.db and ns.db.season == "live" and "live" or "beta"
end

-- Whether beta progress stays: the account chose to keep it, or hasn't chosen yet.
function Season:KeepsBeta()
    return ns.db.season == "pending" or ns.db.betaChoice == "keep"
end

-- Whether a set of badges (saved, archived or from a backup) shows someone
-- camped: any tier earned, or any of the EVIDENCE counts. Beta Camper itself
-- doesn't count.
function Season:Camped(badges)
    if type(badges) ~= "table" then return false end
    local own = ns.Badges.BETA_CAMPER.key
    for key, progress in pairs(badges) do
        if key ~= own and type(progress) == "table" then
            if type(progress.tier) == "number" and progress.tier > 0 then return true end
            for _, field in ipairs(EVIDENCE) do
                local value = progress[field]
                if type(value) == "number" and value > 0 then return true end
            end
        end
    end
    return false
end

-- At login ---------------------------------------------------------------------------

-- Core, at ADDON_LOADED: once the saved data is loaded and before anything
-- reads it. accountIsNew, charIsNew: the saved files weren't there. thenRun:
-- what reads progress next (old character badges, the character's backup
-- copy), run once the game is known: now, or at PLAYER_LOGIN if a sign
-- couldn't be read yet (the realm's name).
function Season:Start(accountIsNew, charIsNew, thenRun)
    self.accountIsNew, self.charIsNew, self.thenRun = accountIsNew, charIsNew, thenRun
    self.current, self.sure, self.signs = self:Detect()
    if self.sure then
        self:Settle()
    else
        self.waiting = true
    end
end

-- Core, at PLAYER_LOGIN: a second look if the first couldn't tell. Still
-- unsure: the beta for this session, with nothing marked, so the next login
-- looks again.
function Season:Resume()
    if not self.waiting then return end
    self.waiting = nil
    self.current, self.sure, self.signs = self:Detect()
    if self.sure then
        self:Settle()
    else
        self:Finish()
    end
end

function Season:Settle()
    if self.current == "live" then
        self:GoLive()
    else
        -- The beta: unmarked data is the beta's. A live mark is never undone.
        ns.db.season = ns.db.season or "beta"
        ns.charDB.season = ns.charDB.season or "beta"
    end
    self:Finish()
end

function Season:Finish()
    local run = self.thenRun
    self.thenRun = nil
    if run then run() end
end

-- A login on the live game. The first one for the account, and for each
-- character, clears the beta world's data (a new saved file has none); an
-- account that camped in the beta is then asked, at this login and each one
-- after until the player chooses.
function Season:GoLive()
    local db, char = ns.db, ns.charDB
    local legacy = char.season ~= "live" and not self.charIsNew and type(char.badges) == "table" and char.badges or nil
    if db.season ~= "live" and db.season ~= "pending" then
        if self.accountIsNew then
            db.season = "live"
        else
            Clear(db, self.ACCOUNT_WORLD)
            self.worldCleared = true
            db.season = (self:Camped(db.badges) or self:Camped(legacy)) and "pending" or "live"
        end
    end
    if char.season ~= "live" then
        if not self.charIsNew then
            Clear(char, self.CHARACTER_WORLD)
            self.characterCleared = true
            if legacy and not self:KeepsBeta() then
                self:ArchiveCharacter()
                Clear(char, self.CHARACTER_PROGRESS)
                if self:Camped(legacy) and ns.Badges:AwardBetaCamper() then
                    C_Timer.After(ASK_DELAY, function() ns.Badges:ThankBetaCamper() end)
                end
            end
        end
        char.season = "live"
    end
    if db.season == "pending" then
        self.askDue = true
        C_Timer.After(ASK_DELAY, function() Season:Ask() end)
    end
end

-- Asks, unless it's been answered or you're in a fight (then it waits for the
-- fight to end: OnCombatEnd).
function Season:Ask()
    if ns.db.season ~= "pending" then
        self.askDue = nil
        return
    end
    if ns.InCombat() then
        self.askAfterCombat = true
        return
    end
    self.askAfterCombat, self.askDue = nil, nil
    self:ShowChoice("account", function(choice) Season:Choose(choice) end)
end

-- Whether the question is on screen, or still to come this session: the
-- Standard or Enhanced question (Mode.lua) waits until it's closed.
function Season:IsAsking()
    return (self.popup ~= nil and self.popup:IsShown()) or self.askDue == true
end

-- Core, when a fight ends.
function Season:OnCombatEnd()
    if self.askAfterCombat then self:Ask() end
end

-- The player's answer: "keep" or "fresh". Either way the account is live now,
-- with the Beta Camper badge, and a line in your own chat window says so.
function Season:Choose(choice)
    local db = ns.db
    if db.season ~= "pending" then return end
    if choice == "fresh" then
        self:ArchiveAccount()
        Clear(db, self.ACCOUNT_PROGRESS)
        ns.Print("%s", L["Welcome to the live game! Happy Camper has started fresh; your beta badges are archived."])
    else
        ns.Print("%s", L["Your beta progress is kept. Happy camping!"])
    end
    db.betaChoice, db.season = choice, "live"
    if ns.Badges:AwardBetaCamper() then ns.Badges:ThankBetaCamper() end
    if ns.Hub:IsShowing("badges") then ns.Hub:Refresh() end
end

-- The question ------------------------------------------------------------------------
-- A window of our own in the middle of the screen (not the game's StaticPopup,
-- which an addon can taint), with two buttons of one size. mode "account":
-- the first live login; "code": a beta backup code pasted on live. onChoose
-- gets "keep" or "fresh"; onClose runs if it's closed without a choice (the
-- close button or Escape), which changes nothing.

local WIDTH, PAD, BUTTON_WIDTH, BUTTON_GAP = 440, 24, 150, 10
local TEXT_TOP = 72   -- under the portrait and title
local BUTTON_ROOM = 64 -- under the text: the gap, the buttons and the bottom edge

-- The question's text, its buttons and what each does, in the player's language.
local function Texts(mode)
    if mode == "code" then
        return L["This backup code is from the beta. Restore its badges and camp progress too, or only its settings and lines?"],
            L["Restore progress too"], L["Restores everything in the code: its beta badges and their progress, settings and own lines."],
            L["Settings and lines only"], L["Restores the code's settings, own lines, Find a camp picks and blocked players, but not its badges."]
    end
    return L["You camped with Happy Camper in the beta. Keep your beta badges and camp progress, or start fresh?"],
        L["Keep my progress"], L["Keeps every badge and badge count from the beta. Beta camps and players seen are cleared either way."],
        L["Start fresh"], L["Clears your badges to start again from nothing. Your beta badges are archived; your settings and own lines stay."]
end

function Season:Popup()
    if self.popup then return self.popup end
    local style = ns.Style
    local f = style:Window("HappyCamperLaunchChoice", WIDTH, 200, "FULLSCREEN_DIALOG", L["WoW Forever is live!"], style.PORTRAIT)
    f.text = style:Text(f, "GameFontHighlight", nil, "CENTER")
    f.text:SetPoint("TOP", f, "TOP", 0, -TEXT_TOP)
    f.keep = style:Button(f, BUTTON_WIDTH, L["Keep my progress"], function() Season:Answer("keep") end)
    f.fresh = style:Button(f, BUTTON_WIDTH, L["Start fresh"], function() Season:Answer("fresh") end)
    style:InfoTooltip(f.keep, function() return f.labels[1] end, function() return f.labels[2] end)
    style:InfoTooltip(f.fresh, function() return f.labels[3] end, function() return f.labels[4] end)
    f:SetScript("OnHide", function()
        local onClose = not f.answered and f.onClose
        f.onChoose, f.onClose = nil, nil
        if onClose then onClose() end
    end)
    self.popup = f
    return f
end

-- Sizes the window around its text, and its buttons to the longer label (both
-- the same width), centred side by side on their row.
local SIZE = { width = WIDTH, pad = PAD, button = BUTTON_WIDTH, gap = BUTTON_GAP, top = TEXT_TOP, room = BUTTON_ROOM }
local function Layout(f, text)
    ns.Style:PromptLayout(f, text, f.keep, f.fresh, SIZE)
end

function Season:ShowChoice(mode, onChoose, onClose)
    local f = self:Popup()
    if f:IsShown() then f:Hide() end -- the question before goes unanswered
    local text, keep, keepTip, fresh, freshTip = Texts(mode)
    -- The thank-you is mentioned only once its coin is drawn (it's hidden till then).
    if ns.Badges.BETA_ART_READY then text = text .. "\n\n" .. L["You get the Beta Camper badge either way."] end
    f.mode, f.onChoose, f.onClose, f.answered = mode, onChoose, onClose, nil
    f.labels = { keep, keepTip, fresh, freshTip }
    f.keep:SetText(keep)
    f.fresh:SetText(fresh)
    Layout(f, text)
    f:ClearAllPoints()
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 60)
    f:Show()
end

-- A button was clicked.
function Season:Answer(choice)
    local f = self:Popup()
    local onChoose = f.onChoose
    f.answered = true
    f:Hide()
    if onChoose then onChoose(choice) end
end

-- The archive -------------------------------------------------------------------------
-- A read-only copy of the beta's progress when the player starts fresh, made
-- once and never overwritten: the badges (never the camps list), and a few
-- totals.

-- Totals from a set of badges: badges earned (landmarks and class badges
-- counted on their own), rests, camps made and objects placed.
function Season:Totals(badges)
    local totals = { earned = 0, landmarks = 0, classes = 0, rests = 0, camps = 0, placed = 0 }
    for key, progress in pairs(badges) do
        if type(progress) == "table" then
            if type(progress.tier) == "number" and progress.tier > 0 then
                local kind = type(key) == "string" and key:match("^(%a+):") or nil
                if kind == "l" then
                    totals.landmarks = totals.landmarks + 1
                elseif kind == "class" then
                    totals.classes = totals.classes + 1
                elseif kind ~= "k" then
                    totals.earned = totals.earned + 1
                end
            end
            for _, field in ipairs({ "rests", "camps", "placed" }) do
                if type(progress[field]) == "number" then totals[field] = totals[field] + progress[field] end
            end
        end
    end
    return totals
end

function Season:ArchiveAccount()
    local db = ns.db
    if type(db.betaArchive) ~= "table" then
        local badges = CopyTable(type(db.badges) == "table" and db.badges or {})
        db.betaArchive = { made = GetServerTime(), badges = badges, totals = self:Totals(badges) }
    end
    return db.betaArchive
end

-- A character's: its badges from before they were account-wide.
function Season:ArchiveCharacter()
    local char = ns.charDB
    if type(char.betaArchive) ~= "table" then
        local badges = CopyTable(type(char.badges) == "table" and char.badges or {})
        char.betaArchive = { made = GetServerTime(), badges = badges, totals = self:Totals(badges) }
    end
    return char.betaArchive
end

-- For the dev tools -------------------------------------------------------------------

-- The saved fields in a list that are there, sorted.
local function Present(saved, list)
    local keys = {}
    for _, entry in ipairs(list) do
        if saved[entry[1]] ~= nil then keys[#keys + 1] = entry[1] end
    end
    table.sort(keys)
    return keys
end

-- What the first live login would do with the saved data as it is now,
-- changing nothing (/hc season preview). For the account and this character:
-- first (not done yet), world (the beta world's fields it would clear),
-- progress (the progress fields), keep (every other field, kept whatever the
-- choice); and for the account, ask (whether it camped in the beta, so the
-- player is asked), state (its season mark) and choice; award (whether Beta
-- Camper would be given).
function Season:Plan()
    local db, char = ns.db, ns.charDB
    local plan = {}
    local parts = {
        { "account", db, self.ACCOUNT_WORLD, self.ACCOUNT_PROGRESS },
        { "character", char, self.CHARACTER_WORLD, self.CHARACTER_PROGRESS },
    }
    for _, part in ipairs(parts) do
        local saved, listed = part[2], {}
        for _, list in ipairs({ part[3], part[4] }) do
            for _, entry in ipairs(list) do listed[entry[1]] = true end
        end
        local result = { world = Present(saved, part[3]), progress = Present(saved, part[4]), keep = {} }
        for key in pairs(saved) do
            if not listed[key] then result.keep[#result.keep + 1] = tostring(key) end
        end
        table.sort(result.keep)
        plan[part[1]] = result
    end
    plan.account.first = db.season ~= "live" and db.season ~= "pending"
    plan.character.first = char.season ~= "live"
    plan.account.state, plan.account.choice = db.season, db.betaChoice
    local legacy = plan.character.first and char.badges or nil
    plan.account.ask = db.season == "pending" or (plan.account.first and (self:Camped(db.badges) or self:Camped(legacy)))
    plan.award = ns.Badges:Tier(ns.Badges.BETA_CAMPER) == 0 and plan.account.ask
    return plan
end
