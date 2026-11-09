-- Happy Camper. Copyright (c) 2026 Torridon. All rights reserved; see LICENSE.
local _, ns = ...
local L = ns.L

-- Feedback: Options -> Send feedback (or /hc feedback) opens a small form for a
-- bug report or an idea; and who the developer is (ns.DEVELOPER, ns.IsDeveloper).
-- A report is sent privately to the developer's character by
-- addon whisper, never over the camp channel, with the addon's version and,
-- if ticked, Happy Camper's recent errors. Reports wait (saved) until the
-- developer is seen online on the camp network, and are deleted once the
-- developer's dev tools send a receipt. Received by HappyCamper_Dev (Inbox).
--
-- Messages (whispers only):
--   F;id;part;total;text     one piece of a report (the text may contain ";"). The
--                            report is encoded first (Encode) and split after,
--                            so pieces can be any length and hold any text.
--   K;id                     the developer's receipt for a whole report

local Feedback = {}
ns.Feedback = Feedback

-- The character feedback goes to (and whose dev tools send receipts).
ns.DEVELOPER = "Lightwarden Torridon"

-- Every one of the developer's characters on the live game ("First Surname":
-- unique across the region in Forever). Only these are trusted for what only
-- the developer may say: announcements (Broadcast.lua), and a newer version on
-- their word alone (Stats.lua). The beta's names aren't: anyone may take them now.
ns.DEVELOPERS = {
    "Lightwarden Torridon",
    "Mindflayer Atheaa",
}

-- Whether a name (a message's sender, as the game gives it) is one of the
-- developer's characters. A realm after the name ("-Realm") is dropped, as
-- ns.SenderName does; case doesn't matter.
function ns.IsDeveloper(name)
    if type(name) ~= "string" or ns.IsSecret(name) or name == "" then return false end
    local short = (Ambiguate(name, "short") or name):gsub("%-.*$", ""):lower()
    for _, developer in ipairs(ns.DEVELOPERS) do
        if developer:lower() == short then return true end
    end
    return false
end

local MAX_NOTE = 500
local MAX_QUEUED = 3
local SEND_COOLDOWN = 5 * 60   -- seconds between reports from one player
local RETRY_AFTER = 10 * 60    -- a report not yet receipted is sent again after this
local RECENTLY_SEEN = 5 * 60   -- the developer counts as online if heard from this recently
local CHUNK = 200              -- characters of report text per message
local MAX_ERRORS = 3
local MAX_ERROR_TEXT = 600     -- characters of each error, with its first stack lines
local STACK_LINES = 6

-- Recent errors from Happy Camper's own files, this session, for bug reports:
-- the message and where it happened.
local recentErrors = {}

function Feedback:AddError(message, stack)
    message = tostring(message)
    if not message:find("HappyCamper") or #recentErrors >= MAX_ERRORS then return end
    for _, seen in ipairs(recentErrors) do
        if seen:sub(1, #message) == message then return end
    end
    local text = message
    if type(stack) == "string" and stack ~= "" then text = text .. "\n" .. stack end
    recentErrors[#recentErrors + 1] = text:sub(1, MAX_ERROR_TEXT)
end

-- The game blocked a call Happy Camper made (Comm:OnActionBlocked): no Lua
-- error, so the error handler never sees it. It goes first in the list, even
-- when the list is full, so a bug report names it.
function Feedback:AddBlocked(event, call)
    local text = format("HappyCamper: the game blocked its call to %s (%s)", tostring(call), tostring(event))
    for _, seen in ipairs(recentErrors) do
        if seen == text then return end
    end
    table.insert(recentErrors, 1, text)
end

-- Other error handlers (the default one, BugGrabber) still get every error.
if geterrorhandler and seterrorhandler then
    local ok, previous = pcall(geterrorhandler)
    if ok and previous then
        pcall(seterrorhandler, function(message, ...)
            pcall(function()
                local stack = debugstack and debugstack(3, STACK_LINES, 0)
                Feedback:AddError(message, stack)
            end)
            return previous(message, ...)
        end)
    end
end

-- Addon messages can't safely hold every character (line breaks, "|" chat
-- codes, "%"): anything but plain printable text travels as %XX.
function Feedback.Encode(text)
    return (text:gsub("[^\032-\036\038-\123\125\126]", function(c) return format("%%%02X", c:byte()) end))
end

function Feedback.Decode(text)
    return (text:gsub("%%(%x%x)", function(hex) return string.char(tonumber(hex, 16)) end))
end

function Feedback:RecentErrors()
    return recentErrors
end

local function Queue()
    ns.db.feedback = ns.db.feedback or { queue = {}, lastSent = 0 }
    return ns.db.feedback
end

-- The text of a report, as the developer will see it.
local function ReportText(kind, note, errors)
    local build, buildNumber = GetBuildInfo()
    local mapID = C_Map.GetBestMapForUnit("player")
    local map = mapID and not ns.IsSecret(mapID) and C_Map.GetMapInfo(mapID)
    local lines = {
        format("%s | Happy Camper %s | game %s (%s) | %s", kind, ns.Stats:Version(), build or "?", buildNumber or "?",
            map and map.name or "?"),
        note,
    }
    if errors and #recentErrors > 0 then
        lines[#lines + 1] = "Errors:"
        for _, message in ipairs(recentErrors) do lines[#lines + 1] = message end
    end
    return table.concat(lines, "\n")
end

-- Why a report can't be sent now, or nil.
function Feedback:CantSend()
    local q = Queue()
    local wait = SEND_COOLDOWN - (GetServerTime() - (q.lastSent or 0))
    if wait > 0 then return format(L["You can send another in %s."], ns.FormatTime(wait)) end
    if #q.queue >= MAX_QUEUED then return L["A few reports are still waiting for the developer to come online."] end
end

-- The first n letters of a text. The note box counts letters, and a Chinese
-- or Korean letter is several bytes: a cut by bytes could split one.
local function FirstLetters(text, n)
    local letters, i = 0, 1
    while i <= #text do
        letters = letters + 1
        if letters > n then return text:sub(1, i - 1) end
        local byte = text:byte(i)
        i = i + (byte >= 240 and 4 or byte >= 224 and 3 or byte >= 192 and 2 or 1)
    end
    return text
end

-- Queues a report ("Bug" or "Idea") and sends it if the developer is around.
-- Returns true, or false and why not.
function Feedback:Submit(kind, note, withErrors)
    note = FirstLetters((note or ""):gsub("^%s+", ""):gsub("%s+$", ""), MAX_NOTE)
    if note == "" then return false, L["Write a few words first."] end
    local why = self:CantSend()
    if why then return false, why end
    local q = Queue()
    q.lastSent = GetServerTime()
    local report = { id = tostring(GetServerTime() % 100000000), text = ReportText(kind, note, withErrors), lastTry = 0 }
    q.queue[#q.queue + 1] = report
    self:Deliver()
    return true
end

-- Whether the developer has been heard on the camp network lately.
local function DeveloperOnline()
    local user = ns.db.users[ns.DEVELOPER]
    return user ~= nil and GetServerTime() - (user.l or 0) <= RECENTLY_SEEN
end

-- Sends every waiting report that's due, in pieces. The developer testing it
-- on their own character gets it straight into their inbox.
function Feedback:Deliver()
    local q, now = Queue(), GetServerTime()
    local selfTest = ns.playerName == ns.DEVELOPER
    if not selfTest and not DeveloperOnline() then return end
    for i = #q.queue, 1, -1 do
        local report = q.queue[i]
        if selfTest then
            if ns.Inbox then ns.Inbox:Add(ns.playerName, report.id, report.text) end
            table.remove(q.queue, i)
        elseif now - (report.lastTry or 0) >= RETRY_AFTER then
            report.lastTry = now
            local encoded = self.Encode(report.text)
            local total = math.ceil(#encoded / CHUNK)
            for part = 1, total do
                ns.Comm:SendWhisper(format("F;%s;%d;%d;%s", report.id, part, total,
                    encoded:sub((part - 1) * CHUNK + 1, part * CHUNK)), ns.DEVELOPER, true) -- after anything else waiting
            end
        end
    end
end

-- The developer was heard on the camp network: send anything waiting.
function Feedback:OnDeveloperSeen()
    if #Queue().queue > 0 then self:Deliver() end
end

-- The developer's dev tools got a whole report.
function Feedback:OnReceipt(sender, id)
    if sender ~= ns.DEVELOPER then return end
    local q = Queue()
    for i = #q.queue, 1, -1 do
        if q.queue[i].id == id then
            table.remove(q.queue, i)
            ns.Print(L["Your feedback reached the developer. Thank you!"])
        end
    end
end

-- The form -----------------------------------------------------------------------

local WIDTH, HEIGHT = 400, 340
local PAD = 18

function Feedback:Create()
    local style = ns.Style
    local f = style:Window("HappyCamperFeedback", WIDTH, HEIGHT, "DIALOG", L["Send feedback"],
        "Interface\\Icons\\INV_Letter_15")
    f:SetPoint("CENTER")

    local intro = style:Text(f, "GameFontHighlightSmall", format(L["Found a bug or have an idea? It goes privately to the developer (%s) with your character's name and the addon's version, next time they're online."],
        ns.FirstName(ns.DEVELOPER)), "LEFT")
    intro:SetPoint("TOPLEFT", 70, -30)
    intro:SetPoint("RIGHT", -PAD, 0)

    f.kind = "Bug"
    f.kindMenu = style:Dropdown(f, 150, function(_, root)
        for _, kind in ipairs({ "Bug", "Idea" }) do
            root:CreateRadio(kind == "Bug" and L["Bug report"] or L["Idea or feedback"],
                function(k) return f.kind == k end, function(k) f.kind = k; Feedback:Refresh() end, kind)
        end
    end)
    f.kindMenu:SetPoint("TOPLEFT", PAD, -86)

    -- The note: a box you can type several lines in.
    f.note = CreateFrame("ScrollFrame", nil, f, "InputScrollFrameTemplate")
    f.note:SetPoint("TOPLEFT", PAD + 4, -122)
    f.note:SetSize(WIDTH - 2 * PAD - 8, 110)
    local box = type(f.note.EditBox) == "table" and f.note.EditBox or nil
    f.box = box
    if box then
        box:SetMaxLetters(MAX_NOTE)
        box:SetWidth(WIDTH - 2 * PAD - 26)
        if type(box.Instructions) == "table" then box.Instructions:SetText(L["What happened, or what would you like?"]) end
    end
    if type(f.note.CharCount) == "table" then f.note.CharCount:Show() end

    f.errors = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
    f.errors:SetSize(24, 24)
    f.errors:SetPoint("TOPLEFT", PAD - 4, -242)
    f.errors.Text:SetFontObject("GameFontHighlightSmall")
    f.errors:SetChecked(true)

    f.status = style:Text(f, "GameFontNormalSmall", nil, "LEFT")
    f.status:SetPoint("TOPLEFT", PAD, -272)
    f.status:SetPoint("RIGHT", -PAD, 0)

    local send = style:Button(f, 90, L["Send"], function()
        local ok, why = Feedback:Submit(f.kind, box and box:GetText(), f.kind == "Bug" and f.errors:GetChecked())
        if ok then
            if box then box:SetText("") end
            f.status:SetText("|cff66ff66" .. L["Thanks! It's on its way to the developer."] .. "|r")
        else
            f.status:SetText("|cffff6666" .. why .. "|r")
        end
    end)
    send:SetPoint("BOTTOMRIGHT", -PAD, 14)
    style:Button(f, 90, L["Close"], function() f:Hide() end):SetPoint("RIGHT", send, "LEFT", -6, 0)
    self.frame = f
end

function Feedback:Refresh()
    local f = self.frame
    if not f then return end
    if f.kindMenu.OverrideText then f.kindMenu:OverrideText(f.kind == "Bug" and L["Bug report"] or L["Idea or feedback"]) end
    f.errors.Text:SetText(format(L["Include Happy Camper's recent errors (%d)"], #recentErrors))
    f.errors:SetShown(f.kind == "Bug")
end

function Feedback:Open()
    if not self.frame then self:Create() end
    self.frame.status:SetText(self:CantSend() or "")
    self:Refresh()
    self.frame:Show()
end
