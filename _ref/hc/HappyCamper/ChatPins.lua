-- Happy Camper. Copyright (c) 2026 Torridon. All rights reserved; see LICENSE.
local _, ns = ...
local L = ns.L

-- Campfires posted in chat: a map pin in a message that talks about a camp or a
-- fire ("camp at the lake |Hworldmap...|h") adds a camp at that pin, for players
-- without the addon. These are yours alone: never sent to anyone, one per
-- player who posted, gone after CHAT_LIFETIME or as soon as a real camp shows
-- up there. Only outdoor maps; blocked and ignored players are skipped.

local ChatPins = {}
ns.ChatPins = ChatPins

-- How long an unconfirmed camp (from chat, another camp addon, or seen in
-- passing) stays, from when it showed up: less than a real fire's 15 minutes,
-- since nobody with Happy Camper has rested there to say it's still burning.
ChatPins.LIFETIME = 10 * 60
ChatPins.RADIUS = 60 -- yards: a pin this close to a known camp is that camp
local allow = ns.FloodLimit(10) -- at most 10 chat camps a minute, one a minute per player

-- Words for a camp or a fire in the languages Happy Camper knows (Polish
-- players chat in Polish on an English client).
local WORDS = {
    "camp", "fire",                              -- English (campfire, bonfire)
    "lager", "feuer",                            -- German
    "feu", "campement",                          -- French
    "campamento", "hoguera", "fogata", "fuego",  -- Spanish
    "acampamento", "fogueira", "fogo",           -- Portuguese
    "obóz", "oboz", "ognisk", "ogień", "ognia",  -- Polish (oboz: obozie, obozowisko,
    "ogien", "biwak",                            --   and typed without accents)
    "营地", "营火", "篝火",                        -- Chinese
    "야영", "모닥불", "캠프", "화톳불",              -- Korean (야영: 야영지 too)
}

local function TalksAboutCamps(text)
    -- Only the words around the pin count, not the pin's own name.
    text = text:gsub("|H.-|h.-|h", " "):lower()
    for _, word in ipairs(WORDS) do
        if text:find(word, 1, true) then return true end
    end
    return false
end

-- Camp Builder's own request posts ("Seeking a blacksmith to share a campfire
-- near Razor Hill"), in the language in use: they're about a fire to come.
local requestPattern, requestSource
local function IsRequestPost(text)
    local sentence = L["Seeking %s to share a campfire near %s."]
    if sentence ~= requestSource then
        requestSource = sentence
        requestPattern = sentence:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0"):gsub("%%%%s", ".-")
    end
    return text:find(requestPattern) ~= nil
end

-- Whether a spot is a Camp Builder request's meet-up: no fire there yet.
local function AtMeetup(mapID, x, y)
    for _, request in pairs(ns.Requests:All()) do
        local distance = ns.Camps:Distance(request, mapID, x, y)
        if distance and distance <= ChatPins.RADIUS then return true end
    end
    return false
end

-- The camps within RADIUS of a spot, found in one pass: a real one, another
-- camp addon's (Others.lua) and a chat post, each nil if there's none.
local function Nearby(mapID, x, y)
    local continent, wx, wy = ns.Camps.WorldPosition(mapID, x, y)
    if not continent then return end
    local real, addon, post
    for _, camp in pairs(ns.Camps:All()) do
        local distance = ns.Camps.WorldDistance(camp, continent, wx, wy)
        if distance and distance <= ChatPins.RADIUS then
            if not camp.chat then
                real = real or camp
            elseif camp.via then
                addon = addon or camp
            else
                post = post or camp
            end
        end
    end
    return real, addon, post
end

-- A map link in chat, clicked: if Happy Camper knows a camp at that spot, a
-- line in your chat window says how long its fire has left; if one went out
-- there, how long ago. Only for you: nothing is sent. Hooked after the game's
-- own handling of the click (hooksecurefunc), which it never changes.
function ChatPins:OnLinkClicked(link)
    if type(link) ~= "string" then return end
    local mapID, x, y = link:match("^worldmap:(%d+):(%d+):(%d+)")
    if not mapID then return end
    mapID, x, y = tonumber(mapID), tonumber(x) / 10000, tonumber(y) / 10000
    local real, addon, post = Nearby(mapID, x, y)
    local camp = real or addon or post
    if camp then
        local left = ns.Camps:TimeLeft(camp)
        if left and left > 0 then
            ns.Print(L["%s: its fire burns for another %s."], ns.Camps:DisplayName(camp), ns.FormatTime(left))
        else
            ns.Print(L["%s is there. How long its fire has left isn't known."], ns.Camps:DisplayName(camp))
        end
        return
    end
    local ago = ns.Camps:EndedNear(mapID, x, y, ChatPins.RADIUS)
    if ago then ns.Print(L["The camp at that spot went out %d min ago."], math.max(1, math.floor(ago / 60))) end
end
if type(SetItemRef) == "function" then
    hooksecurefunc("SetItemRef", function(link) ChatPins:OnLinkClicked(link) end)
end

-- Reads one chat message (event: the chat event it came in); returns the camp
-- it added, if any.
function ChatPins:OnMessage(text, sender, event)
    -- Campfire Assistant's posts are another addon's camps, under that option
    -- (Others.lua). With it off, a pinned one is read like any other post.
    if type(text) == "string" and not ns.IsSecret(text) and ns.Others.CampfireAssistantKind(text) then
        local camp = ns.Others:OnCampfireAssistant(text, sender, event)
        if camp or ns.db.otherAddons then return camp end
    end
    if not ns.db.chatPins or type(text) ~= "string" or type(sender) ~= "string"
        or ns.IsSecret(text) or ns.IsSecret(sender) or sender == "" then return end
    -- The map, x and y come first; the game's link may carry more fields after them.
    local mapID, px, py = text:match("|Hworldmap:(%d+):(%d+):(%d+)[:|]")
    if not mapID or not TalksAboutCamps(text) or IsRequestPost(text) then return end
    sender = ns.SenderName(sender)
    if sender == ns.playerName or ns.IsBlocked(sender) then return end
    mapID, px, py = tonumber(mapID), tonumber(px) / 10000, tonumber(py) / 10000
    if px <= 0 or px >= 1 or py <= 0 or py >= 1 or not ns.IsOutdoorMap(mapID) then return end
    -- Already known from someone with the addon, or from another camp addon
    -- (whose report says more: burn time, slots, layer), or it's a request's
    -- meet-up (its Say or General post, in another language).
    local real, addon, old = Nearby(mapID, px, py)
    if real or addon or AtMeetup(mapID, px, py) then return end
    if not allow(sender, 60) then return end
    -- The same fire posted again (by anyone) replaces the older post, and a
    -- player's new post replaces their last one, wherever it was.
    if old then ns.Camps:Remove(old.id) end
    ns.Camps:Remove("chat:" .. sender)
    -- Objects the post names ("Mana Well, Lodestone") and its fire's size
    -- ("(2/5 Slots)"), as some camp addons post them.
    local words = text:gsub("|H.-|h.-|h", " ")
    local equipment, professions = ns.Others.ObjectsIn(words)
    local camp = ns.Camps:Upsert({
        equipment = equipment,
        professions = professions,
        slots = tonumber(words:match("%(%d+/(%d+)")),
        id = "chat:" .. sender,
        chat = true,
        creator = sender,
        mapID = mapID, x = px, y = py,
        location = ns.Location:Shared(ns.Location:Describe(mapID, px, py, true)),
        placedAt = GetServerTime(),
    })
    return camp
end

-- A real camp arrived: chat or other addons' camps for the same fire aren't
-- needed any more. One known to be on another layer is another fire.
function ChatPins:OnRealCamp(camp)
    if not camp.continent then return end
    for id, other in pairs(ns.Camps:All()) do
        local distance = other.chat and not (other.layer and camp.layer and other.layer ~= camp.layer)
            and ns.Camps.WorldDistance(other, camp.continent, camp.wx, camp.wy)
        if distance and distance <= self.RADIUS then ns.Camps:Remove(id) end
    end
end

-- Turning it off in Options drops the chat camps. Other addons' camps stay:
-- their own option drops them (Others:Disconnect).
function ChatPins:Clear()
    for id, camp in pairs(ns.Camps:All()) do
        if camp.chat and not camp.via then ns.Camps:Remove(id) end
    end
end

local events = CreateFrame("Frame")
for _, event in ipairs({ "CHAT_MSG_SAY", "CHAT_MSG_YELL", "CHAT_MSG_CHANNEL", "CHAT_MSG_GUILD",
    "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER", "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER" }) do
    events:RegisterEvent(event)
end
events:SetScript("OnEvent", function(_, event, text, sender)
    if ns.db and ns.realm then ChatPins:OnMessage(text, sender, event) end -- not before login (PLAYER_LOGIN)
end)
