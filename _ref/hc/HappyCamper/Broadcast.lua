-- Happy Camper. Copyright (c) 2026 Torridon. All rights reserved; see LICENSE.
local _, ns = ...
local L = ns.L

-- Announcements from the developer: a line in your chat window, "Happy Camper
-- (from the developer): ...". No sound and nothing on screen, just the line.
-- The developer sends them from the dev tools (HappyCamper_Dev's Broadcast
-- window) over the camp channel: the B message (Comm.lua). Each is one of the
-- prepared messages below, shown in your own language with its blanks filled
-- in, or free text, shown as written. A prepared one also carries its English,
-- which a copy that doesn't know it (one from before it was added) shows
-- instead. Only taken from one of the developer's characters (ns.IsDeveloper).
-- Each has an ID (who sent it and when) and an end time: it's shown once (the
-- IDs seen are kept in ns.db.broadcasts until they end), and not at all once
-- it has ended. Until then the developer's copy sends it again every so often,
-- for players who log in later; everyone who has seen it ignores those.

local Broadcast = {}
ns.Broadcast = Broadcast

-- The prepared messages: a key (sent instead of the text, so each copy shows
-- its own language), the English text (translated in the Locales files), and
-- what goes in each %s, for the dev tools' Broadcast window. To add one: a new
-- entry here, and its text's translation in each Locales file. version: that
-- argument is a version number: the message is only shown to copies older
-- than it, and tells them the developer reports it (Stats.lua).
Broadcast.TEMPLATES = {
    { key = "update", text = "Happy Camper %s is out: update it from CurseForge.", args = { "Version" }, version = 1 },
    { key = "issue", text = "Known issue: %s. A fix is on the way.", args = { "The issue" } },
    { key = "thanks", text = "Thanks for testing Happy Camper! Report bugs with /hc feedback.", args = {} },
    { key = "quiet", text = "The camp network may be quiet for a while: %s", args = { "Why" } },
}
local TEMPLATE_BY_KEY = {}
for _, template in ipairs(Broadcast.TEMPLATES) do TEMPLATE_BY_KEY[template.key] = template end

Broadcast.MAX_ARGS = 3
Broadcast.MAX_DURATION = 7 * 24 * 3600 -- seconds from its sending to its end, at most
local CLOCK_SLACK = 5 * 60             -- a send time this far ahead of now is still believed
local MAX_SEEN = 50                    -- IDs remembered at once

function Broadcast:Template(key)
    return TEMPLATE_BY_KEY[key]
end

-- How many blanks (%s) a text has.
function Broadcast.Blanks(text)
    local _, count = text:gsub("%%s", "")
    return count
end

-- Control characters, by byte (%c can depend on the system's locale, and
-- take in bytes of accented, Chinese or Korean letters).
local CONTROL = "[%z\1-\31\127]"
local ESCAPED = "[%%;|%z\1-\31\127]" -- the same, with "%", ";" and "|"

-- On the wire, "%", the ";" between fields, "|" and control characters travel
-- as %XX; anything else (accents, Chinese, Korean) as it is.
function Broadcast.Escape(text)
    return (text:gsub(ESCAPED, function(c) return format("%%%02X", c:byte()) end))
end

function Broadcast.Unescape(text)
    return (text:gsub("%%(%x%x)", function(hex) return string.char(tonumber(hex, 16)) end))
end

-- The message for a broadcast: { id = "Sender:sentAt", ends, key ("" for
-- free text), text (its English, or the free text), args }.
function Broadcast:Message(broadcast)
    local fields = { "B", broadcast.id, format("%d", broadcast.ends), broadcast.key or "", self.Escape(broadcast.text or "") }
    local args = broadcast.args or {}
    for i = 1, math.min(#args, self.MAX_ARGS) do fields[#fields + 1] = self.Escape(args[i]) end
    return table.concat(fields, ";")
end

-- A text in a language (a locale code), or in the one in use.
local function Translate(text, locale)
    if not locale then return L[text] end
    local strings = ns.Translations()[locale]
    return strings and strings[text] or text
end

-- A broadcast's text: its prepared message in a language (a locale code; nil:
-- the one in use) with the arguments filled in, or else the text it came with
-- (free text, or the English of a message this copy doesn't know). nil if
-- there's nothing to show.
function Broadcast:Render(broadcast, locale)
    local template = TEMPLATE_BY_KEY[broadcast.key or ""]
    local args = broadcast.args or {}
    local blanks = template and self.Blanks(template.text)
    if template and #args >= blanks then
        return format(Translate(template.text, locale), unpack(args, 1, blanks))
    end
    local text = broadcast.text
    return type(text) == "string" and text ~= "" and text or nil
end

-- Text shown as written: a "|" would start a link, colour or picture, so it
-- shows as itself, and line breaks and other control characters as spaces.
local function AsWritten(text)
    return (text:gsub(CONTROL, " "):gsub("|", "||"))
end

-- The chat line a broadcast's text is shown in, in a language (nil: the one in
-- use). Its key is listed in tests/l10n_extra.txt.
local CHAT_LINE = "|cffff9933Happy Camper (from the developer):|r %s"

function Broadcast:ChatLine(text, locale)
    return format(Translate(CHAT_LINE, locale), AsWritten(text))
end

-- Forgets the IDs of broadcasts that have ended.
function Broadcast:Prune()
    local seen, now = ns.db.broadcasts, GetServerTime()
    for id, ends in pairs(seen) do
        if type(ends) ~= "number" or ends <= now then seen[id] = nil end
    end
end

-- Remembers an ID until its end time (making room by forgetting the one that
-- ends soonest, if need be).
local function Remember(id, ends)
    local seen = ns.db.broadcasts
    Broadcast:Prune()
    if ns.Count(seen) >= MAX_SEEN then
        local soonest
        for other, otherEnds in pairs(seen) do
            if not soonest or otherEnds < seen[soonest] then soonest = other end
        end
        seen[soonest] = nil
    end
    seen[id] = ends
end

function Broadcast:OnMessage(sender, id, ends, key, text, ...)
    if type(sender) ~= "string" or ns.IsSecret(sender) or ns.IsBlocked(sender) or not ns.IsDeveloper(sender) then return end
    if type(id) ~= "string" or #id > 80 then return end
    local creator, sentAt = id:match("^(.+):(%d+)$")
    sentAt, ends = tonumber(sentAt), tonumber(ends)
    if not (creator and ns.IsDeveloper(creator) and sentAt and ends) or ends ~= math.floor(ends) then return end
    -- Ended, or sent at an unlikely time (from the future, or too long before its end).
    local now = GetServerTime()
    if ends <= now or ends < sentAt or ends - sentAt > self.MAX_DURATION or sentAt > now + CLOCK_SLACK then return end
    if ns.db.broadcasts[id] then return end -- shown already (this is it again, for players who came later)
    Remember(id, ends)

    local args = {}
    for i = 1, math.min(select("#", ...), self.MAX_ARGS) do
        local arg = select(i, ...)
        args[i] = type(arg) == "string" and self.Unescape(arg) or ""
    end
    local broadcast = { id = id, ends = ends, key = type(key) == "string" and key or "",
        text = type(text) == "string" and self.Unescape(text) or "", args = args }
    -- A new version's announcement is only for copies older than it, and tells
    -- them the developer reports it (no notice of its own, then).
    local template = TEMPLATE_BY_KEY[broadcast.key]
    if template and template.version then
        local version = ns.Stats.ValidVersion(args[template.version])
        local compared = version and ns.Stats:Compare(version)
        if compared and compared <= 0 then return end
        if compared == 1 then ns.Stats:CheckVersion(sender, version, true) end
    end
    local shown = self:Render(broadcast)
    if shown then print(self:ChatLine(shown)) end
end
