-- Happy Camper. Copyright (c) 2026 Torridon. All rights reserved; see LICENSE.
local _, ns = ...
local L = ns.L

-- Keeping your progress safe. Happy Camper's data lives in the game's WTF
-- folder, not the addon's, so deleting or reinstalling the addon keeps it. Two
-- more safeguards:
--   * A backup code (Options -> Backup, or /hc backup): your badges, found
--     songs, settings, own Social lines, Find a camp picks and blocked players as one line of
--     text to keep anywhere, and to restore from later (on any PC).
--   * A copy in each character's own saved file, made at every logout and
--     reload. If the account's file is lost, logging in restores from it.
-- Codes are read by a small parser of our own, never run as code, and a
-- checksum turns away damaged or edited ones.
-- Codes and copies are marked with the game they were made in ("beta" or
-- "live", Season.lua). On the live game, a code from the beta (or from before
-- they were marked) that shows camping asks the launch question for itself:
-- its progress too, or only its settings and lines. A character's copy from
-- the beta follows the account's answer. Either way, beta camping gives the
-- Beta Camper badge.

local Backup = {}
ns.Backup = Backup

local VERSION = "HC1"
local MAX_CODE = 200000 -- characters
local MAX_DEPTH = 8

-- Settings that travel: every Options setting, plus these.
local EXTRA_SETTINGS = { "search", "blocked", "minimapAngle", "guideSeen", "announceText", "announceTag" }

local function SettingKeys()
    local keys = {}
    for _, setting in ipairs(ns.Options.SETTINGS) do
        if setting.key then keys[#keys + 1] = setting.key end
    end
    for _, key in ipairs(EXTRA_SETTINGS) do keys[#keys + 1] = key end
    return keys
end

-- Text form --------------------------------------------------------------------------
-- A value as text: n<number>; s<length>:<text> t f, and tables as {key value ...}.

local function Write(value, out)
    local kind = type(value)
    if kind == "number" then
        out[#out + 1] = "n" .. format("%.17g", value) .. ";"
    elseif kind == "string" then
        out[#out + 1] = "s" .. #value .. ":" .. value
    elseif kind == "boolean" then
        out[#out + 1] = value and "t" or "f"
    elseif kind == "table" then
        out[#out + 1] = "{"
        for k, v in pairs(value) do
            local keyKind, valueKind = type(k), type(v)
            if (keyKind == "string" or keyKind == "number")
                and (valueKind == "string" or valueKind == "number" or valueKind == "boolean" or valueKind == "table") then
                Write(k, out)
                Write(v, out)
            end
        end
        out[#out + 1] = "}"
    end
end

-- Reads one value at pos; returns it and the next position, or nil on bad text.
local function Read(text, pos, depth)
    local tag = text:sub(pos, pos)
    if tag == "n" then
        local stop = text:find(";", pos, true)
        local number = stop and tonumber(text:sub(pos + 1, stop - 1))
        if not number then return nil end
        return number, stop + 1
    elseif tag == "s" then
        local colon = text:find(":", pos, true)
        local length = colon and tonumber(text:sub(pos + 1, colon - 1))
        if not length or length < 0 or colon + length > #text then return nil end
        return text:sub(colon + 1, colon + length), colon + length + 1
    elseif tag == "t" then
        return true, pos + 1
    elseif tag == "f" then
        return false, pos + 1
    elseif tag == "{" then
        if depth >= MAX_DEPTH then return nil end
        local result = {}
        pos = pos + 1
        while text:sub(pos, pos) ~= "}" do
            if pos > #text then return nil end
            local key, value
            key, pos = Read(text, pos, depth + 1)
            if key == nil or type(key) == "table" or type(key) == "boolean" then return nil end
            value, pos = Read(text, pos, depth + 1)
            if value == nil then return nil end
            result[key] = value
        end
        return result, pos + 1
    end
    return nil
end

-- Base64, so the code is plain letters and digits (chat boxes treat "|" as a code).
local LETTERS = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local VALUE = {}
for i = 1, #LETTERS do VALUE[LETTERS:sub(i, i)] = i - 1 end

local function Encode(data)
    local out = {}
    for i = 1, #data, 3 do
        local a, b, c = data:byte(i, i + 2)
        local n = a * 65536 + (b or 0) * 256 + (c or 0)
        local d1, d2 = math.floor(n / 262144), math.floor(n / 4096) % 64
        local d3, d4 = math.floor(n / 64) % 64, n % 64
        out[#out + 1] = LETTERS:sub(d1 + 1, d1 + 1) .. LETTERS:sub(d2 + 1, d2 + 1)
            .. (b and LETTERS:sub(d3 + 1, d3 + 1) or "=") .. (c and LETTERS:sub(d4 + 1, d4 + 1) or "=")
    end
    return table.concat(out)
end

local function Decode(text)
    text = text:gsub("[^%w%+/=]", "")
    if #text % 4 ~= 0 then return nil end
    local out = {}
    for i = 1, #text, 4 do
        local chunk = text:sub(i, i + 3)
        local pad = select(2, chunk:gsub("=", ""))
        local n = 0
        for j = 1, 4 do
            local ch = chunk:sub(j, j)
            local v = ch == "=" and 0 or VALUE[ch]
            if not v then return nil end
            n = n * 64 + v
        end
        local bytes = string.char(math.floor(n / 65536), math.floor(n / 256) % 256, n % 256)
        out[#out + 1] = bytes:sub(1, 3 - pad)
    end
    return table.concat(out)
end

-- Adler-32 as hex: changes if a single character of the code does.
local function Checksum(data)
    local a, b = 1, 0
    for i = 1, #data do
        a = (a + data:byte(i)) % 65521
        b = (b + a) % 65521
    end
    return format("%04x%04x", b, a)
end

local function Copy(value)
    return type(value) == "table" and CopyTable(value) or value
end

-- Making and reading codes ------------------------------------------------------------

-- Everything a backup holds, as a fresh table.
function Backup:Payload()
    local settings = {}
    for _, key in ipairs(SettingKeys()) do settings[key] = Copy(ns.db[key]) end
    return { v = 1, made = GetServerTime(), season = ns.Season:Mark(), badges = Copy(ns.db.badges or {}),
        songs = Copy(ns.db.songs or {}), settings = settings, lines = Copy(ns.db.customMessages or {}) }
end

-- Whether a code's or copy's contents are from the beta, here on the live
-- game: then its progress stays behind.
local function BetaOnLive(payload)
    return ns.Season:IsLive() and payload.season ~= "live"
end

function Backup:Code()
    local out = {}
    Write(self:Payload(), out)
    local data = table.concat(out)
    return VERSION .. ":" .. Checksum(data) .. ":" .. Encode(data)
end

-- A code's contents, or nil and why not.
function Backup:Read(code)
    if type(code) ~= "string" or #code > MAX_CODE then return nil, L["That isn't a Happy Camper backup code."] end
    local version, sum, body = code:match("^%s*(HC%d+):(%x+):(.-)%s*$")
    if version ~= VERSION or not body then return nil, L["That isn't a Happy Camper backup code."] end
    local data = Decode(body)
    if not data or Checksum(data) ~= sum:lower() then
        return nil, L["That backup code is damaged: copy it again, all of it."]
    end
    local payload, stop = Read(data, 1, 0)
    if type(payload) ~= "table" or stop ~= #data + 1 or payload.v ~= 1 then
        return nil, L["That backup code is damaged: copy it again, all of it."]
    end
    return payload
end

-- Restoring -------------------------------------------------------------------------

-- Badges from a backup join yours: the higher count, the higher tier and the
-- earlier date win, so restoring twice (or an older code) loses nothing.
local function MergeBadges(from)
    ns.db.badges = ns.db.badges or {}
    for key, progress in pairs(from) do
        if (type(key) == "string" or type(key) == "number") and type(progress) == "table" then
            local into = ns.db.badges[key]
            if not into then
                into = { tier = 0, earned = {} }
                ns.db.badges[key] = into
            end
            for field, value in pairs(progress) do
                if field == "earned" and type(value) == "table" then
                    into.earned = into.earned or {}
                    for tier, at in pairs(value) do
                        if type(tier) == "number" and type(at) == "number" then
                            into.earned[tier] = math.min(into.earned[tier] or at, at)
                        end
                    end
                elseif type(field) == "string" and type(value) == "number" then
                    into[field] = math.max(into[field] or 0, math.min(math.floor(value), 1e6))
                end
            end
            into.tier = math.min(into.tier or 0, 3)
        end
    end
end

-- Found songs from a backup join yours (Music.lua's db.songs): the earlier
-- date wins; a song known without a date stays known. Older codes have none.
local MAX_SONG_KEY = 40
local function MergeSongs(from)
    if type(ns.db.songs) ~= "table" then ns.db.songs = {} end
    local songs = ns.db.songs
    for key, when in pairs(from) do
        if type(key) == "string" and #key <= MAX_SONG_KEY and (when == true or type(when) == "number") then
            local had = songs[key]
            if type(when) == "number" then
                if type(had) ~= "number" or when < had then songs[key] = math.floor(when) end
            elseif had == nil then
                songs[key] = true
            end
        end
    end
end

-- The same for the dev tools' restore of the beta archive (Season.lua).
function Backup:MergeBadges(from)
    MergeBadges(from)
end

-- Settings from a backup, where they're the same kind as yours. Find a camp
-- picks keep only buffs it shows, each at any tier or a tier the buff has.
local function RestoreSettings(from)
    for _, key in ipairs(SettingKeys()) do
        local value = from[key]
        if value ~= nil and type(value) == type(ns.db[key]) then
            ns.db[key] = key == "search" and ns.Search:CleanSettings(value) or Copy(value)
        end
    end
    if type(from.announceText) == "string" then ns.db.announceText = ns.Announce:CleanWording(from.announceText) end
end

-- Your own lines from the Social tab (parked: they're kept, and go on in
-- backups, for its return), from a backup, added to yours (no repeats, up to
-- the tab's limit of 6 lines of 70 characters).
local MAX_LINES, MAX_LINE_LENGTH = 6, 70
local function RestoreLines(from)
    local have = {}
    for _, entry in ipairs(ns.db.customMessages) do have[entry.text] = true end
    for _, entry in ipairs(from) do
        if type(entry) == "table" and type(entry.text) == "string" and entry.text ~= "" and not have[entry.text]
            and #ns.db.customMessages < MAX_LINES then
            table.insert(ns.db.customMessages, { text = entry.text:sub(1, MAX_LINE_LENGTH), emote = entry.emote == true or nil })
            have[entry.text] = true
        end
    end
end

local function Refresh()
    if ns.Options.frame then ns.Options:Sync() end
    if ns.Widget and ns.Widget.Update then ns.Widget:Update() end
    if ns.Hub.frame then ns.Hub:Refresh() end
end

-- The Backup window's status line: green when restored, red when not, gold
-- while waiting for an answer (ok nil).
function Backup:ShowStatus(ok, message)
    local f = self.frame
    if not f then return end
    f.status:SetText(message)
    if ok then
        f.status:SetTextColor(0.4, 1, 0.4)
    elseif ok == false then
        f.status:SetTextColor(1, 0.4, 0.4)
    else
        f.status:SetTextColor(1, 0.82, 0)
    end
end

-- Restores from a code; returns true or false and a message for the player.
-- A code from the beta, on the live game, that shows camping asks first
-- (Season:ShowChoice): then this returns nil and a message, and the answer
-- (choice "keep": its progress too; "fresh": settings and lines only)
-- restores it and shows how it went in the Backup window.
function Backup:Restore(code, choice)
    local payload, why = self:Read(code)
    if not payload then return false, why end
    local fromBeta = BetaOnLive(payload)
    local camped = fromBeta and ns.Season:Camped(payload.badges)
    if camped and choice == nil then
        ns.Season:ShowChoice("code", function(answer) Backup:ShowStatus(Backup:Restore(code, answer)) end,
            function() Backup:ShowStatus(false, L["Nothing was restored."]) end)
        return nil, L["This backup code is from the beta: choose what to restore."]
    end
    local withProgress = not camped or choice == "keep"
    local before = {}
    for _, setting in ipairs(ns.Options.SETTINGS) do
        if setting.key then before[setting.key] = ns.db[setting.key] end
    end
    if type(payload.badges) == "table" and next(payload.badges) and withProgress then
        MergeBadges(payload.badges)
        -- The two sets together may have earned a collection badge.
        ns.Badges:UpdateCollections()
    end
    if type(payload.songs) == "table" and withProgress then MergeSongs(payload.songs) end
    if type(payload.settings) == "table" then RestoreSettings(payload.settings) end
    if type(payload.lines) == "table" then RestoreLines(payload.lines) end
    -- Settings that changed take effect now, as if ticked in Options (joining
    -- or leaving the camp channel, showing the minimap button...).
    for _, setting in ipairs(ns.Options.SETTINGS) do
        if setting.onChange and ns.db[setting.key] ~= before[setting.key] then setting.onChange(ns.db[setting.key]) end
    end
    -- Beta camping gives Beta Camper either way (a player whose live install
    -- starts fresh can still have it).
    if camped and ns.Badges:AwardBetaCamper() then ns.Badges:ThankBetaCamper() end
    Refresh()
    if not withProgress then return true, L["Settings and lines restored, without the code's beta progress."] end
    return true, L["Backup restored. A few settings (like the language) apply after /reload."]
end

-- The copy in each character's file ----------------------------------------------------

-- Made at logout and reload, when the game saves.
function Backup:SaveCopy()
    if ns.db and ns.charDB then ns.charDB.backup = self:Payload() end
end

-- At login: what the account's file is missing comes back from this
-- character's copy. accountIsNew: the account's file wasn't there at all.
-- A copy from the beta, on the live game, follows the account's answer to the
-- launch question: its progress can come back if the account kept its beta
-- progress; otherwise (started fresh, or nothing from the beta to keep) only
-- its settings and lines. Then it gives Beta Camper if it shows camping and is
-- dropped (the next save makes a live one). While the question is unanswered
-- it waits: no progress comes back from it yet.
function Backup:RestoreIfLost(accountIsNew)
    local copy = ns.charDB.backup
    if type(copy) ~= "table" then return end
    local fromBeta = BetaOnLive(copy)
    local waiting = fromBeta and ns.db.season == "pending"
    local withProgress = not fromBeta or (ns.db.betaChoice == "keep" and not waiting)
    local restored = false
    if type(copy.badges) == "table" and next(copy.badges) and not next(ns.db.badges or {}) and withProgress then
        MergeBadges(copy.badges)
        restored = true
    end
    if type(copy.songs) == "table" and next(copy.songs) and not next(ns.db.songs or {}) and withProgress then
        MergeSongs(copy.songs)
        restored = true
    end
    if type(copy.lines) == "table" and #copy.lines > 0 and #ns.db.customMessages == 0 then
        RestoreLines(copy.lines)
        restored = true
    end
    if accountIsNew and type(copy.settings) == "table" then
        RestoreSettings(copy.settings)
        restored = true
    end
    if fromBeta and not waiting then
        if ns.Season:Camped(copy.badges) and ns.Badges:AwardBetaCamper() then
            C_Timer.After(10, function() ns.Badges:ThankBetaCamper() end)
        end
        ns.charDB.backup = nil
    end
    if restored then
        C_Timer.After(5, function() ns.Print(L["Happy Camper's saved data was missing, so it was restored from this character's copy."]) end)
    end
end

-- The Backup window ---------------------------------------------------------------------

local WIDTH, HEIGHT, PAD = 460, 380, 16
local BUTTON_WIDTH = 170

function Backup:Create()
    local style = ns.Style
    local f = style:Window("HappyCamperBackup", WIDTH, HEIGHT, "DIALOG", L["Backup"], style.PORTRAIT, "backupPoint")
    if not ns.db.backupPoint then f:SetPoint("CENTER") end

    f.intro = style:Text(f, "GameFontHighlight",
        L["Your badges, songs, settings and own lines as one code. Keep it somewhere safe (a note, a message to yourself). To restore, paste a code here and click Restore."],
        "LEFT")
    f.intro:SetPoint("TOPLEFT", PAD + 4, -66)
    f.intro:SetWidth(WIDTH - 2 * PAD - 8)

    local inset = style:Inset(f, f, 12, -118, 12, -(HEIGHT - 86))
    inset:ClearAllPoints()
    inset:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -118)
    inset:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -12, 86)
    local scroll = CreateFrame("ScrollFrame", nil, f)
    scroll:SetPoint("TOPLEFT", inset, "TOPLEFT", 8, -8)
    scroll:SetPoint("BOTTOMRIGHT", inset, "BOTTOMRIGHT", -8, 8)
    scroll:SetFrameLevel(f:GetFrameLevel() + 4)
    local box = CreateFrame("EditBox", nil, scroll)
    box:SetMultiLine(true)
    box:SetAutoFocus(false)
    box:SetFontObject("ChatFontSmall")
    box:SetWidth(WIDTH - 2 * PAD - 24)
    box:SetMaxLetters(MAX_CODE)
    box:SetScript("OnEscapePressed", box.ClearFocus)
    scroll:SetScrollChild(box)
    scroll:EnableMouse(true)
    scroll:SetScript("OnMouseDown", function() box:SetFocus() end)
    f.box = box

    f.status = style:Text(f, "GameFontNormal", nil, "CENTER")
    f.status:SetPoint("BOTTOM", f, "BOTTOM", 0, 62)
    f.status:SetWidth(WIDTH - 2 * PAD)

    f.make = style:Button(f, BUTTON_WIDTH, L["Make backup code"], function()
        box:SetText(Backup:Code())
        box:HighlightText()
        box:SetFocus()
        f.status:SetText(L["Press Ctrl+C to copy it, then keep it somewhere safe."])
    end)
    f.restore = style:Button(f, BUTTON_WIDTH, L["Restore from code"], function()
        Backup:ShowStatus(Backup:Restore(box:GetText()))
    end)
    style:SameWidth({ f.make, f.restore }, BUTTON_WIDTH)
    f.make:SetPoint("BOTTOMRIGHT", f, "BOTTOM", -5, 24)
    f.restore:SetPoint("BOTTOMLEFT", f, "BOTTOM", 5, 24)
    self.frame = f
end

function Backup:Open()
    if not self.frame then self:Create() end
    self.frame.status:SetText("")
    self.frame.status:SetTextColor(1, 0.82, 0)
    self.frame:Show()
end

function Backup:Toggle()
    if self.frame and self.frame:IsShown() then self.frame:Hide() else self:Open() end
end
