-- Happy Camper. Copyright (c) 2026 Torridon. All rights reserved; see LICENSE.
local _, ns = ...
local L = ns.L

local function MatchesAny(name, fragments)
    if type(name) ~= "string" then return false end
    name = name:lower()
    for _, fragment in ipairs(fragments) do
        if ns.ContainsPhrase(name, fragment) then return true end
    end
    return false
end

function ns.NameMatches(name, kind)
    return MatchesAny(name, ns.PATTERNS[kind])
end

-- Whether a spell is a profession recipe (crafting a campfire kit or a camp
-- object shares its name with placing one, but isn't placing it).
local function IsRecipe(spellID)
    local ok, info = pcall(C_TradeSkillUI.GetProfessionInfoByRecipeID, spellID)
    return ok and info ~= nil and (info.professionID or 0) ~= 0
end

-- Returns "fire", "object" or nil for a spell the player cast: by its ID first
-- (any client language), then by its English name.
function ns.ClassifySpell(spellID)
    local known = ns.db.known[spellID]
    if known == "fire" or known == "object" then return known end
    if known or ns.db.ignored[spellID] then return nil end
    if ns.CAMP_SPELLS.fire[spellID] then return "fire" end
    if ns.ObjectForSpell(spellID) then return "object" end

    local name = C_Spell.GetSpellName(spellID)
    if (MatchesAny(name, ns.PATTERNS.fire) or MatchesAny(name, ns.PATTERNS.object)) and IsRecipe(spellID) then return nil end
    if MatchesAny(name, ns.PATTERNS.fire) then return "fire" end
    if MatchesAny(name, ns.PATTERNS.object) then return "object" end
end

-- Returns "buff", "rest", "near" or nil for a helpful aura on the player.
local AURA_KINDS = { "near", "buff", "rest" }
local auraNameKind = {} -- [aura name] = what the name says it is (false: nothing), worked out once
function ns.ClassifyAura(aura)
    local known = ns.db.known[aura.spellId]
    if known == "buff" or known == "rest" or known == "near" then return known end
    if known or ns.db.ignored[aura.spellId] then return nil end
    for _, kind in ipairs(AURA_KINDS) do
        if ns.CAMP_SPELLS[kind][aura.spellId] then return kind end
    end

    -- Every aura is checked on every change, so each name's match is kept.
    local name = aura.name
    if type(name) ~= "string" then return nil end
    local kind = auraNameKind[name]
    if kind == nil then
        kind = MatchesAny(name, ns.PATTERNS.near) and "near" or MatchesAny(name, ns.PATTERNS.buff) and "buff"
            or MatchesAny(name, ns.PATTERNS.rest) and "rest" or false
        auraNameKind[name] = kind
    end
    return kind or nil
end

-- Rebuilds the camp buff list and tracks the rest aura. Only call out of
-- combat: aura data can be secret in combat.
function ns.ScanAuras()
    local s = ns.state
    -- Aura changes went unseen (in combat, or unreadable): this scan catches up.
    local catchUp = s.aurasDirty
    local buffs, restAura, near = {}, nil, false
    local benefits -- the camp buff that started last

    local i = 1
    while true do
        local aura, secret = ns.AuraByIndex("player", i, "HELPFUL")
        if secret then
            -- Can't be read now: keep what was last read, and try again later.
            s.aurasDirty = true
            return
        end
        if not aura then break end
        if not ns.IsSecretAura(aura) then
            local kind = ns.ClassifyAura(aura)
            if kind == "buff" then
                buffs[#buffs + 1] = aura
                if (aura.duration or 0) > 0 and (aura.expirationTime or 0) > 0 and (not benefits
                    or aura.expirationTime - aura.duration > benefits.expirationTime - benefits.duration) then
                    benefits = aura
                end
            elseif kind == "rest" then
                restAura = aura
            elseif kind == "near" then
                near = true
            end
        end
        i = i + 1
    end
    -- Used to offer the Say and General buttons and the "Campfire nearby" notice;
    -- being near isn't resting.
    if near and not s.nearCamp then ns.OnCampfireNearby() end
    s.nearCamp = near

    table.sort(buffs, function(a, b)
        return (a.expirationTime or 0) < (b.expirationTime or 0)
    end)
    s.buffs = buffs
    s.aurasDirty = false

    if restAura then
        if s.restAuraInstance ~= restAura.auraInstanceID then
            s.restAuraInstance = restAura.auraInstanceID
            if restAura.auraInstanceID ~= s.restDoneFor then
                ns.StartRest("aura", restAura)
            end
        end
    elseif s.restAuraInstance then
        s.restAuraInstance = nil
        if s.restSource == "aura" then
            -- Gone when its countdown ran out means you rested; gone early
            -- means you stood up or walked away. Gone while auras couldn't be
            -- read (a fight), it's only a finished rest if Camp Benefits came
            -- as it ended: that was missed too, so it's handled now.
            local done
            if catchUp then
                done = benefits ~= nil and benefits.expirationTime - benefits.duration >= s.restEnd - 2
                -- The camp is confirmed where you stand, so only if the fight
                -- didn't carry you away from the fire. Either way you had its
                -- buffs, so Camps:OnRested doesn't empty it.
                local distance = done and s.restMap and ns.Camps:DistanceTo(s.restMap, s.restX, s.restY)
                if distance and distance <= ns.Camps.MERGE_RADIUS then
                    ns.OnCampBuff(benefits)
                elseif done then
                    s.campBuffAt = GetTime()
                end
            else
                done = GetTime() >= s.restEnd - 1
            end
            ns.StopRest(done)
        end
    end
end

-- Handles one newly gained aura: ends resting when the camp buff arrives.
function ns.OnAuraAdded(aura)
    if ns.IsSecret(aura) or ns.IsSecretAura(aura) or not aura.isHelpful then return end

    if ns.ClassifyAura(aura) == "buff" then
        if ns.state.restEnd then ns.StopRest(true) end
        ns.OnCampBuff(aura)
    end
end

-- Camp Benefits was applied or refreshed: its tooltip lists every object at
-- the camp, which is recorded on the camp and shared. A moment's delay lets the
-- tooltip load.
function ns.OnCampBuff(aura)
    if ns.IsSecretAura(aura) or ns.ClassifyAura(aura) ~= "buff" then return end
    local id = aura.auraInstanceID
    ns.state.campBuffAt = GetTime()
    C_Timer.After(1, function() ns.Camps:OnCampBenefits(id) end)
end

-- Makes text from other players safe to show: strips colour and
-- texture codes and the message separator, and caps the length.
function ns.CleanText(text)
    if type(text) ~= "string" then return nil end
    text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("[|;%c]", " "):gsub("%s+", " ")
    text = text:match("^%s*(.-)%s*$")
    return #text > 0 and text:sub(1, 180) or nil
end

function ns.OnSpellCast(spellID)
    if ns.IsSecret(spellID) then return end

    local kind = ns.ClassifySpell(spellID)
    local name = C_Spell.GetSpellName(spellID) or ("spell " .. spellID)

    if kind == "fire" then
        local slots = ns.CAMP_SPELLS.fire[spellID] or ns.Camps.KitSlots(name)
        ns.Camps:OnFireLit(slots)
        ns.Badges:OnFirePlaced(slots)
    elseif kind == "object" then
        ns.Camps:OnObjectPlaced(spellID)
        ns.Badges:OnObjectPlaced(spellID)
        local c = ns.charDB
        c.objectReadyAt = GetServerTime() + ns.db.objectCooldown
        c.objectName = name
        c.objectSkill = ns.ProfessionForObject(spellID)
        local key = ns.ObjectForSpell(spellID)
        c.placedTier = key and select(4, ns.ObjectByName(key)) or nil
        c.objectIcon = C_Spell.GetSpellTexture(spellID)
        c.objectAlerted = false
    end
end

-- Sitting at a camp: the "Welcoming Campfire" aura is up.
function ns.IsRestingAtCamp()
    return ns.state.restAuraInstance ~= nil
end

-- Starts the rest bar. With the rest aura, the bar follows its own countdown.
function ns.StartRest(source, aura)
    local s = ns.state
    if s.restEnd then return end
    local now = GetTime()
    s.restStart, s.restEnd, s.restSource = now, now + ns.db.restSeconds, source
    if aura and (aura.expirationTime or 0) > now and (aura.duration or 0) > 0 then
        s.restStart, s.restEnd = aura.expirationTime - aura.duration, aura.expirationTime
    end
    -- Where you sat: a rest that ends in a fight is checked against it (ScanAuras).
    s.restMap, s.restX, s.restY = ns.GetPlayerLocation()
    ns.Cinematic:Arm()
    if source == "aura" then ns.Hub:OnRestStart() end
end

function ns.StopRest(completed)
    local s = ns.state
    if not s.restEnd then return end
    s.restStart, s.restEnd, s.restSource = nil, nil, nil
    s.restMap, s.restX, s.restY = nil, nil, nil
    s.restDoneFor = s.restAuraInstance
    if completed then
        ns.Badges:OnRested()
        ns.Camps:OnRested()
        ns.Note(L["Rested. Your camp buffs should be active."])
        ns.Hub:OnRested()
    end
end

-- Camp Benefits tooltip ----------------------------------------------------------

-- Whether a tooltip line is the buff's time left ("59 minutes remaining"), in
-- any client language: matched against the game's own phrases for it.
local timeLeftPatterns, timeLeftSource
local function IsTimeLeftLine(text)
    if not timeLeftPatterns or timeLeftSource ~= SPELL_TIME_REMAINING_MIN then
        timeLeftPatterns, timeLeftSource = {}, SPELL_TIME_REMAINING_MIN
        for _, name in ipairs({ "SPELL_TIME_REMAINING_DAYS", "SPELL_TIME_REMAINING_HOURS",
            "SPELL_TIME_REMAINING_MIN", "SPELL_TIME_REMAINING_SEC" }) do
            local phrase = _G[name]
            if type(phrase) == "string" then
                -- "%d |4minute:minutes; remaining" -> "^%d+ .- remaining$"
                local pattern = phrase:gsub("|4[^;]*;", "\001"):gsub("%%d", "\002")
                pattern = pattern:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0")
                pattern = pattern:gsub("\001", ".-"):gsub("\002", "%%d+")
                timeLeftPatterns[#timeLeftPatterns + 1] = "^" .. pattern .. "$"
            end
        end
    end
    text = text:match("^%s*(.-)%s*$")
    for _, pattern in ipairs(timeLeftPatterns) do
        if text:match(pattern) then return true end
    end
    return text:lower():find("remaining", 1, true) ~= nil
end

-- Several stats in one sentence, each clause shortened: "Armor increased by
-- 163, all attributes increased by 7, and all resistances increased by 6" ->
-- "Armor +163, all attributes +7, all resistances +6" (the Enchanted Lute's).
-- Stats it gives none of at your level are left out. nil if a clause isn't
-- "X increased by N".
local function ShortStats(effect)
    local parts, zero = {}, nil
    for clause in (effect .. ","):gmatch("%s*(.-)%s*,") do
        local stat, amount = clause:gsub("^and%s+", ""):match("^(.-) increased by (%d+%%?)$")
        if not stat then return nil end
        local short = format("%s +%s", (stat:gsub("^[Yy]our ", "")), amount)
        if amount:match("^0%%?$") then zero = zero or short else parts[#parts + 1] = short end
    end
    local text = #parts > 0 and table.concat(parts, ", ") or zero
    return text:sub(1, 1):upper() .. text:sub(2)
end

-- Parses one Camp Benefits tooltip line into the object and a short effect:
--   "Faction Banner: Spirit increased by 14." -> { object = "Faction Banner", effect = "Spirit +14" }
-- Header lines such as "Gained the following camp benefits:" return nil.
function ns.ParseBenefitLine(text)
    -- Tooltips can use non-breaking spaces; treat them as plain spaces.
    text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("\194\160", " ")
    -- Chinese clients use a full-width colon (headers end in one too) and full stop.
    text = text:gsub("\239\188\154", ":"):gsub("\227\128\130%s*$", "")
    text = text:match("^%s*(.-)%.?%s*$")
    if text == "" or text:match(":$") then return nil end

    -- "Object: effect"
    local object, effect = text:match("^([^:]+):%s*(.+)$")
    effect = effect or text
    local stat, amount = effect:match("^(.-) increased by (%d+%%?)$")
    if not stat then stat, amount = effect:match("^[Ii]ncreases? (.-) by (%d+%%?)$") end
    local several = select(2, effect:gsub(" increased by ", "")) > 1 and ShortStats(effect)
    local short, skillLine
    local lower, whole = effect:lower(), text:lower()
    if lower:find("rest experience", 1, true) or lower:find("rested experience", 1, true) then
        -- The Camp Tent (its line may call it just "Tent").
        short, skillLine = L["Rested XP"], 165
    elseif whole:match("once%s+per") or whole:match("once%s+every") or whole:match("only receive") then
        -- "You can only receive this effect once per 1 hour": the game's small
        -- print, not a benefit of its own.
        return { note = true }
    elseif lower:find("critical strike", 1, true) and effect:match("(%d+%%)") then
        short = format(L["Crit +%s"], effect:match("(%d+%%)"))
    elseif lower:match("(%d+) mana every 5 sec") then
        -- The game's line is "Restores 24 Mana every 5 seconds".
        short = format(L["Mana +%s / 5 sec"], lower:match("(%d+) mana every 5 sec"))
    elseif several then
        short = several
    elseif stat then
        stat = stat:gsub("^[Yy]our ", "")
        short = format("%s +%s", stat:sub(1, 1):upper() .. stat:sub(2), amount)
    else
        short = effect
    end
    return { object = object, effect = short, plain = short == effect, skillLine = skillLine }
end

-- What a Camp Benefits buff's tooltip said, by buff: the panel and the Camp
-- tab ask every second for the hour it lasts, and it only changes when you
-- rest again (a new expiry). Only lists with something in them are kept.
local benefitsRead = {} -- [auraInstanceID:expiry:maxLines] = lines
local benefitsReadCount = 0

-- When a buff of yours ends (ns.state.buffs), or nil if it isn't one of them.
local function BuffExpiry(auraInstanceID)
    for _, buff in ipairs(ns.state.buffs or {}) do
        if buff.auraInstanceID == auraInstanceID then return buff.expirationTime end
    end
end

-- Reads your Camp Benefits buff's tooltip: a list of { object, effect }, one
-- per object at the camp you rested at. nil when it can't be read right now
-- (secret aura data, e.g. in combat). Don't change the list.
function ns.ReadCampBenefits(auraInstanceID, maxLines)
    if not ns.CanReadAura(auraInstanceID) then return nil end
    local expiry = BuffExpiry(auraInstanceID)
    local key = expiry and (auraInstanceID .. ":" .. expiry .. ":" .. (maxLines or 20))
    if key and benefitsRead[key] then return benefitsRead[key] end
    local lines = ns.ReadCampBenefitsNow(auraInstanceID, maxLines)
    if key and lines and #lines > 0 then
        if benefitsReadCount >= 8 then wipe(benefitsRead); benefitsReadCount = 0 end
        benefitsRead[key], benefitsReadCount = lines, benefitsReadCount + 1
    end
    return lines
end

-- Your buffs changed: Camp Benefits is read afresh.
function ns.ForgetCampBenefits()
    wipe(benefitsRead)
    benefitsReadCount = 0
end

-- The same, read from the tooltip every time.
function ns.ReadCampBenefitsNow(auraInstanceID, maxLines)
    local ok, data = pcall(C_TooltipInfo.GetUnitBuffByAuraInstanceID, "player", auraInstanceID)
    if not ok then return nil end
    local lines = {}
    for i = 2, data and data.lines and #data.lines or 0 do
        local text = data.lines[i].leftText
        if type(text) == "string" and not ns.IsSecret(text) and text ~= "" and not IsTimeLeftLine(text) then
            -- A tooltip line can hold several sentences; each is one stat.
            text = text:gsub("\194\160", " ")
            local first = true
            for sentence in (text:gsub("%.%s+", ".\n") .. "\n"):gmatch("(.-)\n") do
                local stat = ns.ParseBenefitLine(sentence)
                -- A later sentence with no object name and no stat in it is small
                -- print about the one before; it stays in the game's own tooltip.
                local smallPrint = stat and not first and not stat.object and stat.plain
                if stat then first = false end
                if smallPrint then
                    -- left out
                elseif stat and stat.note then
                    -- left out too
                elseif stat and #lines < (maxLines or 20) then
                    lines[#lines + 1] = stat
                end
            end
        end
    end
    return lines
end
