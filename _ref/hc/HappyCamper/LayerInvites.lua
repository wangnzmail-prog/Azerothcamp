-- Happy Camper. Copyright (c) 2026 Torridon. All rights reserved; see LICENSE.
local _, ns = ...
local L = ns.L

-- Layer invites: asking a player at a camp on another layer for a group
-- invite, which takes you to their layer.
--
-- Opt-in (Options: layerInvites, off at first). A player who turns it on says
-- so in their presence (a last "i" field on P, Social.lua), which is only sent
-- while they're at a camp, so they can only be asked while they're there.
-- Asking is a click on that camp's map pin (MapPins.lua): a hidden addon
-- whisper, LJ;campID, to one of them. Nothing goes in chat. The player asked
-- sees a small window of our own (not the game's StaticPopup, which an addon
-- can taint) with Invite and Not now; the invite is sent only when they click
-- Invite.

local LayerInvites = {}
ns.LayerInvites = LayerInvites

local ASK_AGAIN = 600     -- seconds before you can ask the same player again
local ASK_WINDOW = 60     -- asks to anyone: at most ASK_LIMIT in this many seconds
local ASK_LIMIT = 3
local PROMPT_AGAIN = 600  -- seconds before the same player's ask is shown again
local PROMPT_TIME = 60    -- the window closes by itself after this long

local asked = {}          -- [name] = when you last asked them
local recentAsks = {}     -- when your recent asks went, oldest first
local prompted = {}       -- [name] = when their ask was last shown to you

-- Whether you take requests: the option is on and camps are shared (your
-- presence, which says so, only goes out on the camp network).
function LayerInvites:IsOn()
    return ns.db.layerInvites == true and ns.db.network == true
end

-- In a fight or an instance: nobody asks or is asked.
function LayerInvites:Busy()
    if ns.InCombat() then return true end
    local inInstance = IsInInstance and IsInInstance()
    return inInstance == true
end

-- Whether a player (a full name, as addon messages give it) is in your party or raid.
function LayerInvites:InGroupWith(name)
    if type(name) ~= "string" or not ns.Group:InGroup() then return false end
    local short = Ambiguate(name, "short")
    for _, member in ipairs(ns.Group:Roster()) do
        if member.name == name or Ambiguate(member.name, "short") == short then return true end
    end
    return false
end

-- The players you could ask at a camp: it's on another layer, and they've
-- said they take requests and are at it now. Sorted by name.
function LayerInvites:Inviters(camp)
    local list = {}
    if not camp or ns.Camps:LayerStatus(camp) ~= "other" then return list end
    for _, person in ipairs(ns.Social:InvitersAt(camp.id)) do
        if not ns.IsBlocked(person.name) and not self:InGroupWith(person.name) then list[#list + 1] = person end
    end
    return list
end

function LayerInvites:CanAsk(camp)
    return self:Inviters(camp)[1] ~= nil
end

-- Lines for a camp pin's tooltip: who can be asked, and how.
function LayerInvites:FillTooltip(tooltip, camp)
    local inviters = self:Inviters(camp)
    if not inviters[1] then return end
    local names = {}
    for _, person in ipairs(inviters) do names[#names + 1] = Ambiguate(person.name, "short") end
    tooltip:AddLine(" ")
    tooltip:AddLine(format(L["Open to layer invite requests: %s"], ns.JoinList(names)), 1, 1, 1, true)
    tooltip:AddLine(L["Click to ask for an invite to their layer"], 0.4, 1, 0.4, true)
end

-- Asks one player at a camp for an invite. Returns true if the ask went.
function LayerInvites:Ask(camp, name)
    if self:Busy() then
        ns.Print("%s", L["You can't ask for an invite in combat or in an instance."])
        return false
    end
    local found = false
    for _, person in ipairs(self:Inviters(camp)) do
        if person.name == name then found = true end
    end
    if not found then return false end
    local now, short = GetTime(), Ambiguate(name, "short")
    if asked[name] and now - asked[name] < ASK_AGAIN then
        ns.Print(L["You asked %s a few minutes ago. Try again later."], short)
        return false
    end
    while recentAsks[1] and now - recentAsks[1] >= ASK_WINDOW do table.remove(recentAsks, 1) end
    if #recentAsks >= ASK_LIMIT then
        ns.Print("%s", L["You've asked several players just now. Try again in a minute."])
        return false
    end
    asked[name] = now
    recentAsks[#recentAsks + 1] = now
    ns.Comm:SendWhisper("LJ;" .. camp.id, name)
    ns.Print(L["Asked %s for an invite to their layer."], short)
    return true
end

-- A click on the camp's pin: asks its one player, or offers a menu of them.
function LayerInvites:AskAt(camp, owner)
    local inviters = self:Inviters(camp)
    if not inviters[1] then return end
    if #inviters == 1 then return self:Ask(camp, inviters[1].name) end
    local opened = ns.Menu:Context(owner, function(_, root)
        root:CreateTitle(L["Ask whom?"])
        for _, person in ipairs(inviters) do
            root:CreateButton(Ambiguate(person.name, "short"), function() LayerInvites:Ask(camp, person.name) end)
        end
    end)
    if not opened then self:Ask(camp, inviters[1].name) end
end

-- Being asked -------------------------------------------------------------------------

-- An LJ whisper: someone on another layer asks you to invite them. Shown only
-- if you take requests, you're at that camp now, out of a fight and an
-- instance, they aren't blocked or in your group already, they haven't been
-- shown in the last PROMPT_AGAIN seconds, and no other ask is on screen.
function LayerInvites:OnRequest(sender, campID)
    if not self:IsOn() or type(sender) ~= "string" or type(campID) ~= "string" or #campID > 80 then return end
    local myCamp = ns.Social:MyCamp()
    if not myCamp or myCamp.id ~= campID then return end
    if self:Busy() or ns.IsBlocked(sender) or self:InGroupWith(sender) then return end
    local now = GetTime()
    if prompted[sender] and now - prompted[sender] < PROMPT_AGAIN then return end
    if self.prompt and self.prompt:IsShown() then return end
    prompted[sender] = now
    self:ShowPrompt(sender)
end

local WIDTH, PAD, BUTTON_WIDTH, BUTTON_GAP = 320, 24, 110, 10
local TEXT_TOP = 64    -- under the portrait and title
local BUTTON_ROOM = 60 -- under the text: the gap, the buttons and the bottom edge

function LayerInvites:Prompt()
    if self.prompt then return self.prompt end
    local style = ns.Style
    local f = style:Window("HappyCamperLayerInvite", WIDTH, 150, "DIALOG", "Happy Camper", style.PORTRAIT)
    f.text = style:Text(f, "GameFontHighlight", nil, "CENTER")
    f.text:SetPoint("TOP", f, "TOP", 0, -TEXT_TOP)
    f.invite = style:Button(f, BUTTON_WIDTH, L["Invite"], function() LayerInvites:Answer(true) end)
    f.later = style:Button(f, BUTTON_WIDTH, L["Not now"], function() LayerInvites:Answer(false) end)
    f:SetScript("OnHide", function() f.asker, f.onInvite, f.showing = nil, nil, nil end)
    self.prompt = f
    return f
end

-- Sizes the window around its text, and its two buttons to the longer label,
-- side by side and centred.
local SIZE = { width = WIDTH, pad = PAD, button = BUTTON_WIDTH, gap = BUTTON_GAP, top = TEXT_TOP, room = BUTTON_ROOM }
local function Layout(f, text)
    ns.Style:PromptLayout(f, text, f.invite, f.later, SIZE)
end

-- Shows the ask. onInvite (the dev tools' preview) runs instead of a real
-- invite when Invite is clicked.
function LayerInvites:ShowPrompt(name, onInvite)
    local f = self:Prompt()
    if f:IsShown() then f:Hide() end
    f.invite:SetText(L["Invite"])
    f.later:SetText(L["Not now"])
    Layout(f, format(L["%s asks to join your layer."], Ambiguate(name, "short")))
    f.asker, f.onInvite = name, onInvite
    local showing = {}
    f.showing = showing
    f:ClearAllPoints()
    f:SetPoint("TOP", UIParent, "TOP", 0, -160)
    f:Show()
    C_Timer.After(PROMPT_TIME, function()
        if f.showing == showing then f:Hide() end
    end)
    local sound = SOUNDKIT and SOUNDKIT.TELL_MESSAGE
    if sound then PlaySound(sound) end
end

-- Closes the ask unanswered (a fight starting, or the option turned off).
function LayerInvites:Close()
    if self.prompt and self.prompt:IsShown() then self.prompt:Hide() end
end

-- Invite or Not now was clicked.
function LayerInvites:Answer(invite)
    local f = self:Prompt()
    local name, onInvite = f.asker, f.onInvite
    f:Hide()
    if not invite or not name then return end
    if onInvite then return onInvite(name) end
    -- Nothing runs in a fight; and they may have joined your group since.
    if ns.InCombat() or self:InGroupWith(name) then return end
    local partyInfo = C_PartyInfo
    local inviteUnit = partyInfo and partyInfo.InviteUnit
    if not inviteUnit or not pcall(inviteUnit, name) then
        ns.Print(L["Couldn't send the invite. Invite %s yourself."], Ambiguate(name, "short"))
    end
end
