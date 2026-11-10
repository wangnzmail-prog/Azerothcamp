-- Camp.lua · 露营管理（四段式：物资 / 露营buff / 其他buff / 队伍）
local ADDON, ns = ...
local C = ns.Core
local T = ns.Theme

local isCN = (ns.Platform.locale == "zhCN")
local function L(zh, en)
    local loc = ns.Platform.locale
    if loc == "zhTW" then return (ns.TW and ns.TW[zh]) or zh end
    if loc == "zhCN" then return zh end
    return en
end

local M = C:RegisterModule("Camp", {
    label = L("露营管理", "Camping"),
    defaultEnabled = true,
    flavors = { forever = true },
    settings = {
        { key = "scale",     type = "number",  default = 1.0, min = 0.8, max = 1.6, step = 0.05, label = L("缩放", "Scale") },
        { key = "width",     type = "number",  default = 340, min = 240, max = 640, step = 10, label = L("宽度", "Width") },
        { key = "collapsed", type = "boolean", default = false, label = L("折叠", "Collapsed") },
        { key = "locked",    type = "boolean", default = false, label = L("锁定位置", "Lock") },
        { key = "point",     type = "string",  default = "TOPLEFT", hidden = true },
        { key = "relPoint",  type = "string",  default = "TOPLEFT", hidden = true },
        { key = "x",         type = "number",  default = 20,   hidden = true },
        { key = "y",         type = "number",  default = -120, hidden = true },
        { key = "iconX",     type = "number",  default = 20,   hidden = true },
        { key = "iconY",     type = "number",  default = -120, hidden = true },
    },
})

-- ---------- 常量 ----------
local AURA = { benefits = 1229741, wellRested = 429959, welcoming = 1289723, nearby = 1283391, boosted = 1229451 }
local BAG_ITEM = 211527
local TENT_ITEM = 279978
local TOY_ITEM = 288185

local BUFFS = {
    { id = AURA.benefits,  name = L("露营增益", "Camp Benefits"),    src = L("营火", "Campfire") },
    { id = AURA.wellRested, name = L("精神饱满", "Well-Rested"),     src = L("舒适的睡袋", "Sleeping Bag") },
    { id = AURA.welcoming, ids = { 1229739 }, name = L("温馨营火", "Welcoming Campfire"), src = L("营火", "Campfire") },

    { id = AURA.boosted,   name = L("强化休息", "Boosted Rest"),      src = L("营地制品", "Camp object") },
}

-- ---------- 工具 ----------
local function ItemName(id)
    if not id then return nil end
    if C_Item and C_Item.GetItemNameByID then
        local n = C_Item.GetItemNameByID(id)
        if n then return n end
    end
    if C_Item and C_Item.GetItemInfo then return C_Item.GetItemInfo(id) end
end

local function AuraByID(spellID)
    local api = C_UnitAuras
    if not api or not api.GetAuraDataByIndex then return nil end
    for _, filter in ipairs({ "HELPFUL", "HARMFUL" }) do
        for i = 1, 60 do
            local ok, data = pcall(api.GetAuraDataByIndex, "player", i, filter)
            if not ok or not data then break end
            local sid = data.spellId
            if sid and not ns.Platform.IsSecret(sid) and sid == spellID then return data end
        end
    end
    return nil
end

local function FullTime(sec)
    sec = math.max(0, math.floor((sec or 0) + 0.5))
    return string.format("%d:%02d:%02d", math.floor(sec / 3600), math.floor((sec % 3600) / 60), sec % 60)
end

-- ---------- 扫描 ----------
local state = { items = {}, buffs = {}, xpbuffs = {}, others = {}, peers = {}, toy = nil, aura = nil }

local function ScanBags()
    -- 返回 itemID -> {count, bag, slot, name}
    local found = {}
    for bag = 0, (NUM_BAG_SLOTS or 4) do
        local slots = C_Container.GetContainerNumSlots(bag) or 0
        for slot = 1, slots do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.itemID then
                local row = found[info.itemID]
                if not row then
                    row = { count = 0, bag = bag, slot = slot, name = ItemName(info.itemID), id = info.itemID }
                    found[info.itemID] = row
                end
                row.count = row.count + (info.stackCount or 1)
            end
        end
    end
    return found
end

local function FindToy(id, pattern)
    local bags = ScanBags()
    if bags[id] then return bags[id] end
    if C_ToyBox and C_ToyBox.GetNumFilteredToys and C_ToyBox.GetToyFromIndex then
        local ok, n = pcall(C_ToyBox.GetNumFilteredToys)
        if ok and n then
            for i = 1, n do
                local toyID = C_ToyBox.GetToyFromIndex(i)
                if toyID == id then
                    return { count = 1, name = ItemName(toyID), id = toyID, toy = true }
                end
            end
        end
    end
end

local SECONDARY = { cooking = true, fishing = true, firstaid = true }

local PROF_SKILLLINE = {
    alchemy = 171, blacksmithing = 164, enchanting = 333, engineering = 202,
    herbalism = 182, leatherworking = 165, mining = 186, skinning = 393,
    tailoring = 197, fishing = 356, firstaid = 129, cooking = 185,
}

local function LearnedSkillLines()
    local list = {}
    if type(GetProfessions) ~= "function" or type(GetProfessionInfo) ~= "function" then
        return list
    end
    local p = { GetProfessions() }
    for _, idx in ipairs(p) do
        if idx then
            local ok, skillLine = pcall(function() return select(7, GetProfessionInfo(idx)) end)
            if ok and skillLine then list[#list + 1] = skillLine end
        end
    end
    return list
end

local PROF_LABEL = {}

local function Rescan()
    local bags = ScanBags()
    local items = {}

    -- 营火
    for _, f in ipairs(ns.CampData.campfires) do
        local row = bags[f.item]
        items[#items + 1] = { id = f.item, name = ItemName(f.item), count = row and row.count or 0,
            bag = row and row.bag, slot = row and row.slot, effect = string.format("%d格", f.slots), group = "fire" }
    end
    -- 帐篷
    local toy = FindToy(TOY_ITEM)
    items[#items + 1] = { id = TOY_ITEM, name = ItemName(TOY_ITEM) or L("探险帐篷", "Expedition Tent"),
        count = toy and 1 or 0, effect = "+20%经验", group = "tent", toy = toy }
    local tent = bags[TENT_ITEM]
    items[#items + 1] = { id = TENT_ITEM, name = ItemName(TENT_ITEM) or L("营地帐篷", "Camp Tent"),
        count = tent and tent.count or 0, bag = tent and tent.bag, slot = tent and tent.slot,
        effect = "+5%经验", group = "tent" }
    -- 睡袋
    local bagItem = bags[BAG_ITEM]
    items[#items + 1] = { id = BAG_ITEM, name = ItemName(BAG_ITEM) or L("舒适的睡袋", "Sleeping Bag"),
        count = bagItem and bagItem.count or 0, bag = bagItem and bagItem.bag, slot = bagItem and bagItem.slot,
        effect = L("经验+3%/层", "+3% XP/stack"), group = "bag" }
    -- 专业制品
    for _, p in ipairs(ns.CampData.professions) do
        for tier, id in ipairs(p.items) do
            local row = bags[id]
            items[#items + 1] = { id = id, name = ItemName(id), count = row and row.count or 0,
                bag = row and row.bag, slot = row and row.slot,
                effect = p.effect, group = "prof", prof = p.key }
        end
    end
    for _, o in ipairs(ns.CampData.cooking) do
        local row = bags[o.item]
        items[#items + 1] = { id = o.item, name = ItemName(o.item), count = row and row.count or 0,
            bag = row and row.bag, slot = row and row.slot, effect = o.effect, group = "prof", prof = "cooking" }
    end
    state.items = items
    state.toy = toy

    -- 分组：基础 + 各专业
    local groups, byProf = {}, {}
    local base = { title = L("基础", "Basic"), items = {} }
    groups[1] = base
    for _, it in ipairs(items) do
        if it.group == "fire" or it.group == "tent" or it.group == "bag" then
            base.items[#base.items + 1] = it
        else
            local key = it.prof or "other"
            local g = byProf[key]
            if not g then
                g = { title = PROF_LABEL[key] or key, items = {} }
                byProf[key] = g
                groups[#groups + 1] = g
            end
            g.items[#g.items + 1] = it
        end
    end
    -- 已学专业优先，其余用分隔线隔开
    local learnedOrder = LearnedSkillLines()
    local learnedSet = {}
    for _, sl in ipairs(learnedOrder) do learnedSet[sl] = true end

    local ordered, rest = {}, {}
    for _, g in ipairs(groups) do
        if g ~= base then
            local key = nil
            for k, v in pairs(PROF_SKILLLINE) do
                if PROF_LABEL[k] == g.title then key = k end
            end
            if key and not SECONDARY[key] and learnedSet[PROF_SKILLLINE[key]] then
                ordered[#ordered + 1] = g
            else
                rest[#rest + 1] = g
            end
        end
    end
    -- 按已学顺序重排
    local byKey = {}
    for _, g in ipairs(ordered) do
        for k, v in pairs(PROF_SKILLLINE) do
            if PROF_LABEL[k] == g.title then byKey[PROF_SKILLLINE[k]] = g end
        end
    end
    local function keyOfGroup(g)
        for k, v in pairs(PROF_SKILLLINE) do
            if PROF_LABEL[k] == g.title then return k end
        end
    end

    local sec, others = {}, {}
    for _, g in ipairs(rest) do
        local k = keyOfGroup(g)
        if k and SECONDARY[k] then sec[#sec + 1] = g else others[#others + 1] = g end
    end

    local secSorted = {}
    for _, want in ipairs({ "cooking", "fishing", "firstaid" }) do
        for _, g in ipairs(sec) do
            if keyOfGroup(g) == want then secSorted[#secSorted + 1] = g end
        end
    end

    local final = { base }
    for _, sl in ipairs(learnedOrder) do
        if byKey[sl] then final[#final + 1] = byKey[sl] end
    end
    if #secSorted > 0 then
        secSorted[1].dividerBefore = true
        for _, g in ipairs(secSorted) do final[#final + 1] = g end
    end
    if #others > 0 then
        others[1].dividerBefore = true
        for _, g in ipairs(others) do final[#final + 1] = g end
    end
    state.groups = final

    -- 附近是否已有营火（100 码规则）
    state.nearFire = (AuraByID(1283391) or AuraByID(1289723) or AuraByID(1229739)) ~= nil

    -- buff
    local buffs = {}
    for _, b in ipairs(BUFFS) do
        local a = AuraByID(b.id)
        if not a and b.ids then
            for _, alt in ipairs(b.ids) do
                a = AuraByID(alt)
                if a then break end
            end
        end
        buffs[#buffs + 1] = { id = b.id, name = b.name, src = b.src, active = a ~= nil,
            remain = a and (a.expirationTime or 0) - GetTime() or 0,
            stacks = a and a.applications or nil }
    end
    state.buffs = buffs

    -- 其他经验 buff：名字含“经验”的光环
    local xp = {}
    for _, filter in ipairs({ "HELPFUL" }) do
        for i = 1, 60 do
            local ok, data = pcall(C_UnitAuras.GetAuraDataByIndex, "player", i, filter)
            if not ok or not data then break end
            local name = data.name
            if name and (name:find("经验", 1, true) or name:find("Experience", 1, true)) then
                xp[#xp + 1] = { name = name, remain = (data.expirationTime or 0) - GetTime() }
            end
        end
    end
    state.xpbuffs = xp

    -- 队伍
    state.peers = ns.CampPeers or {}
end

-- ---------- 面板 ----------
local panel, rows, ticker, scroll
local ROW_H = 22

local function ApplyCollapse()
    if not panel then return end
    local collapsed = C:GetSetting("Camp", "collapsed") and true or false
    local w = tonumber(C:GetSetting("Camp", "width")) or 340

    if collapsed then
        panel:SetSize(32, 32)
        if panel.title then panel.title:Hide() end
        if panel.reloadBtn then panel.reloadBtn:Hide() end
        if panel.scroll then panel.scroll:Hide() end
        if panel.icon then
            panel.icon:ClearAllPoints()
            panel.icon:SetPoint("CENTER", panel, "CENTER", 0, 0)
        end
        T:RestorePosition(panel, "TOPLEFT", "TOPLEFT",
            tonumber(C:GetSetting("Camp", "iconX")) or 20,
            tonumber(C:GetSetting("Camp", "iconY")) or -120)
    else
        panel:SetSize(w, 660)
        if panel.title then panel.title:Show() end
        if panel.reloadBtn then panel.reloadBtn:Show() end
        if panel.scroll then panel.scroll:Show() end
        if panel.icon then
            panel.icon:ClearAllPoints()
            panel.icon:SetPoint("TOPRIGHT", -2, -2)
        end
        panel:ClearAllPoints()
        panel:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end
end

local function ApplyLayout()
    if not panel then return end
    panel:SetScale(tonumber(C:GetSetting("Camp", "scale")) or 1)
    panel:SetWidth(tonumber(C:GetSetting("Camp", "width")) or 340)
    panel.akLocked = C:GetSetting("Camp", "locked") and true or false
    ApplyCollapse()
    T:RestorePosition(panel, "TOPLEFT", "TOPLEFT",
        tonumber(C:GetSetting("Camp", "x")) or 20,
        tonumber(C:GetSetting("Camp", "y")) or -120)
end

local function Row(i)
    if not rows[i] then
        local fs
        if i == 1 or rows[i - 1] then fs = panel.content:CreateFontString(nil, "ARTWORK", "GameFontHighlight") end
        fs = fs or panel.content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        fs:SetJustifyH("LEFT")
        fs:SetWidth(320)
        fs:SetWordWrap(false)
        fs:SetPoint("TOPLEFT", 4, -(i - 1) * ROW_H)
        rows[i] = fs
    end
    return rows[i]
end

local function AddLine(text, color)
    panel.lineCount = (panel.lineCount or 0) + 1
    local fs = Row(panel.lineCount)
    fs:SetText(text)
    if color then fs:SetTextColor(unpack(color)) else fs:SetTextColor(0.9, 0.9, 0.92) end
end

local function Header(text)
    AddLine("|cffffd700" .. text .. "|r")
end

local DIM = { 0.45, 0.45, 0.48 }
PROF_LABEL = {
    alchemy = L("炼金", "Alchemy"), blacksmithing = L("锻造", "Blacksmithing"),
    enchanting = L("附魔", "Enchanting"), engineering = L("工程", "Engineering"),
    herbalism = L("草药", "Herbalism"), leatherworking = L("制皮", "Leatherworking"),
    mining = L("采矿", "Mining"), skinning = L("剥皮", "Skinning"),
    tailoring = L("裁缝", "Tailoring"), fishing = L("钓鱼", "Fishing"),
    firstaid = L("急救", "First Aid"), cooking = L("烹饪", "Cooking"),
}

local function Refresh()
    if not panel then return end
    panel.lineCount = 0

    Header(L("露营物资", "Camping supplies"))
    local expanded = (ns.db and ns.db.campExpanded) or {}
    local usedPlus, usedItem = {}, {}
    if expanded["__base"] == nil then expanded["__base"] = true end
    if ns.db then ns.db.campExpanded = expanded end

    for _, g in ipairs(state.groups or {}) do
        if g.dividerBefore then
            AddLine("|cff3a3a3a--------------------------------------|r")
        end
        local key = (g.title == L("基础", "Basic")) and "__base" or g.title
        local open = expanded[key]
        local headerIdx = (panel.lineCount or 0) + 1
        AddLine(string.format("       |cff7fb0ff%s|r", g.title))

        if panel.plus then
            local btn = panel.plus[headerIdx]
            if not btn then
                btn = CreateFrame("Button", nil, panel.content, "UIPanelButtonTemplate")
                btn:SetSize(20, 20)
                if btn.GetFontString then
                    local fs = btn:GetFontString()
                    if fs then fs:SetFont(STANDARD_TEXT_FONT, 14, "") end
                end
                panel.plus[headerIdx] = btn
            end
            btn:ClearAllPoints()
            btn:SetPoint("TOPLEFT", 3, -((headerIdx - 1) * ROW_H - 1))
            btn:SetText(open and "-" or "+")
            btn:SetScript("OnClick", function()
                expanded[key] = not expanded[key]
                Refresh()
            end)
            btn:Show()
            usedPlus[headerIdx] = true
        end
        -- 给标题行挂一个点击区
        if panel.hit then
            local b = panel.hit[headerIdx]
            if not b then
                b = CreateFrame("Button", nil, panel.content)
                b:SetHeight(20)
                b:SetWidth(290)
                panel.hit[headerIdx] = b
            end
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", 2, -((headerIdx - 1) * ROW_H))
            b:SetWidth(300)
            b:SetScript("OnClick", function()
                expanded[key] = not expanded[key]
                Refresh()
            end)
            b:Show()
        end
        if open then
        for _, it in ipairs(g.items) do
            local owned = (it.count or 0) > 0
            local blocked = (it.group == "fire") and state.nearFire
            local rowIdx = (panel.lineCount or 0) + 1
            local text = string.format("    %s%s|r ×%d  |cff808080%s|r",
                (owned and not blocked) and "|cffffffff" or "|cff606060",
                it.name or ("item:" .. tostring(it.id)),
                it.count or 0, it.effect or "")
            if blocked then
                text = text .. "  |cffcc8040" .. L("（附近已有营火）", "(campfire nearby)") .. "|r"
            end
            AddLine(text, owned and nil or DIM)

            -- 安全按钮：玩家点击才触发，合规且战斗可用
            local btn = panel.itemBtns[rowIdx]
            if not btn then
                btn = CreateFrame("Button", nil, panel.content, "SecureActionButtonTemplate")
                btn:SetHeight(ROW_H - 2)
                btn:SetWidth(320)
                panel.itemBtns[rowIdx] = btn
            end
            btn:ClearAllPoints()
            btn:SetPoint("TOPLEFT", 2, -((rowIdx - 1) * ROW_H))
            btn:RegisterForClicks("AnyUp")
            if not (InCombatLockdown and InCombatLockdown()) then
                if owned and blocked then
                    btn:SetAttribute("type", nil)
                    btn:SetAttribute("item", nil)
                    btn:SetAttribute("toy", nil)
                elseif owned and it.toy then
                    btn:SetAttribute("type", "toy")
                    btn:SetAttribute("toy", "item:" .. it.id)
                    btn:SetAttribute("item", nil)
                elseif owned then
                    btn:SetAttribute("type", "item")
                    btn:SetAttribute("item", "item:" .. it.id)
                    btn:SetAttribute("toy", nil)
                else
                    btn:SetAttribute("type", nil)
                    btn:SetAttribute("item", nil)
                    btn:SetAttribute("toy", nil)
                end
            end
            btn:Show()
            usedItem[rowIdx] = true
        end
        end
    end


    AddLine(" ")
    Header(L("露营 buff", "Camp buffs"))
    if state.nearFire then
        AddLine("  " .. L("营火在附近", "Campfire Nearby"), { 0.30, 0.80, 0.35 })
    else
        AddLine("  " .. L("营火在附近", "Campfire Nearby"), { 0.90, 0.30, 0.30 })
    end

    local shown = 0
    for _, b in ipairs(state.buffs) do
        if b.active then
            shown = shown + 1
            AddLine(string.format("  |cffffffff%s[%s]|r  %s", b.name, b.src, FullTime(b.remain)))
        end
    end
    if shown == 0 then
        AddLine("  " .. L("（无）", "(none)"), DIM)
    end

    AddLine(" ")
    Header(L("其他经验 buff", "Other XP buffs"))
    if #state.xpbuffs == 0 then
        AddLine("  " .. L("（无）", "(none)"), DIM)
    else
        for _, x in ipairs(state.xpbuffs) do
            AddLine(string.format("|cffffffff%s|r  %s", x.name, FullTime(x.remain)))
        end
    end

    AddLine(" ")
    Header(L("队伍", "Party"))
    local any = false
    for name, p in pairs(state.peers) do
        any = true
        local cd = tonumber(p.cd) or 0
        AddLine(string.format("%s  %s  %s", name, tostring(p.cap or "?"), cd > 0 and FullTime(cd) or L("可用", "ready")))
    end
    if not any then
        AddLine("  " .. L("（队友未装插件或无数据）", "(no peer data)"), DIM)
    else
        -- 缺什么：队友都没有的专业制品
        local covered = {}
        for _, p in pairs(state.peers) do covered[p.cap or ""] = true end
        for _, it in ipairs(state.items) do
            if it.group == "prof" and (it.count or 0) > 0 and it.prof and not covered[it.prof] then
                AddLine("  " .. L("建议你放", "suggest") .. ": " .. tostring(it.name), { 0.4, 0.8, 1 })
                break
            end
        end
    end

    if panel.plus then
        for idx, b in pairs(panel.plus) do if not usedPlus[idx] then b:Hide() end end
    end
    if panel.itemBtns then
        for idx, b in pairs(panel.itemBtns) do if not usedItem[idx] then b:Hide() end end
    end
    if panel.hit then
        for idx, b in pairs(panel.hit) do if not usedPlus[idx] then b:Hide() end end
    end

    for i = (panel.lineCount or 0) + 1, #rows do
        if rows[i] then rows[i]:Hide() end
    end
    for i = 1, (panel.lineCount or 0) do
        if rows[i] then rows[i]:Show() end
    end
    panel.content:SetHeight(math.max(10, panel.lineCount * ROW_H))
end

local function OnWheel(_, delta)
    local smax = math.max(0, (panel.content:GetHeight() or 0) - 620)
    panel.offset = math.min(smax, math.max(0, (panel.offset or 0) - delta * 24))
    panel.content:SetPoint("TOPLEFT", panel.scrollChild or panel.scroll, "TOPLEFT", 0, panel.offset)
end

local function CreatePanel()
    local f = T:CreatePanel("AzerothCampFrame", UIParent, 340, 660)
    f:SetFrameStrata("DIALOG")
    f:SetMovable(true)
    f:SetClampedToScreen(true)

    local title = T:CreateText(f, 12, false)
    title:SetPoint("TOPLEFT", 10, -8)
    title:SetText(L("露营管理", "Camping"))

    f.title = title

    local icon = CreateFrame("Button", nil, f)
    icon:SetSize(28, 28)
    icon:SetPoint("TOPRIGHT", -2, -2)
    local tex = icon:CreateTexture(nil, "ARTWORK")
    tex:SetAllPoints()
    local iconPath = (C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(279981))
        or "Interface\\Icons\\INV_Misc_Campfire_01"
    tex:SetTexture(iconPath)
    icon:RegisterForDrag("RightButton")
    icon:SetScript("OnDragStart", function()
        if C:GetSetting("Camp", "collapsed") then
            f.dragging = true
            f:StartMoving()
        else
            f.dragging = false
        end
    end)
    icon:SetScript("OnDragStop", function()
        if not f.dragging then return end   -- 展开态右键不应改写图标坐标
        f.dragging = false
        f:StopMovingOrSizing()
        local es = f:GetEffectiveScale() / UIParent:GetEffectiveScale()
        C:SetSetting("Camp", "iconX", math.floor(((f:GetLeft() or 0) * es - (UIParent:GetLeft() or 0)) + 0.5))
        C:SetSetting("Camp", "iconY", math.floor(((f:GetTop() or 0) * es - (UIParent:GetTop() or 0)) + 0.5))
    end)
    icon:SetScript("OnClick", function(_, button)
        if button == "RightButton" then return end
        C:SetSetting("Camp", "collapsed", not (C:GetSetting("Camp", "collapsed") and true or false))
        ApplyCollapse()
    end)
    icon:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText(L("露营管理（点击折叠/展开）", "Camping (click to collapse)"))
        GameTooltip:Show()
    end)
    icon:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f.icon = icon

    local reloadBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    reloadBtn:SetSize(18, 18)
    reloadBtn:SetPoint("TOPRIGHT", -26, -4)
    reloadBtn:SetText("R")
    if reloadBtn.GetFontString then
        local fs = reloadBtn:GetFontString()
        if fs then fs:SetFont(STANDARD_TEXT_FONT, 14, "") end
    end
    reloadBtn:SetScript("OnClick", function() ReloadUI() end)
    reloadBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM"); GameTooltip:SetText("Reload UI"); GameTooltip:Show()
    end)
    reloadBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f.reloadBtn = reloadBtn

    local sf = CreateFrame("ScrollFrame", "AzerothCampScroll", f)
    sf:SetPoint("TOPLEFT", 6, -26)
    sf:SetPoint("BOTTOMRIGHT", -6, 6)
    sf:EnableMouseWheel(true)
    sf:SetScript("OnMouseWheel", OnWheel)

    local content = CreateFrame("Frame", nil, sf)
    content:SetSize(260, 10)
    sf:SetScrollChild(content)

    f.scroll = sf
    f.hit = {}
    f.plus = {}
    f.itemBtns = {}
    f.content = content
    f.offset = 0
    panel = f

    f:SetMovable(true)
    f:SetClampedToScreen(true)
    return f
end

function M:OnEnable()
    if not panel then
        rows = {}
        CreatePanel()
    end
    ApplyLayout()
    panel:Show()

    Rescan()
    Refresh()

    C:On("PLAYER_REGEN_ENABLED", Refresh)

    if not ticker then
        ticker = C_Timer.NewTicker(1, function()
            if panel and panel:IsShown() then
                Rescan()
                Refresh()
            end
        end)
    end
end

function M:OnDisable()
    C:Off("PLAYER_REGEN_ENABLED", Refresh)
    if ticker then ticker:Cancel() ticker = nil end
    if panel then panel:Hide() end
end

function M:OnSettingChanged(key)
    if key == "collapsed" then ApplyCollapse() return end
    if key == "scale" or key == "width" or key == "locked" or key == "point"
        or key == "relPoint" or key == "x" or key == "y" then
        ApplyLayout()
    end
end

function M:ScanReport()
    Rescan()
    local lines = { "AzerothCamp " .. tostring(ns.VERSION) }
    for _, it in ipairs(state.items) do
        lines[#lines + 1] = string.format("  item %s x%d %s", tostring(it.id), it.count or 0, tostring(it.name))
    end
    for _, b in ipairs(state.buffs) do
        lines[#lines + 1] = string.format("  buff %s %s", tostring(b.id), b.active and "ON" or "off")
    end
    return lines
end
