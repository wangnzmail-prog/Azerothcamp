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
    local icon = CreateFloatingIcon()
    icon:ClearAllPoints()
    icon:SetPoint("TOPLEFT", UIParent, "TOPLEFT",
        tonumber(C:GetSetting("Camp", "iconX")) or 20,
        tonumber(C:GetSetting("Camp", "iconY")) or -120)
    icon:Show()

    if collapsed then
        panel:Hide()
    else
        panel:Show()
        panel:ClearAllPoints()
        local px = tonumber(C:GetSetting("Camp", "x"))
        local py = tonumber(C:GetSetting("Camp", "y"))
        if px and py then
            panel:SetPoint("TOPLEFT", UIParent, "TOPLEFT", px, py)
        else
            panel:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
        end
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

local COL_W = 0
local colCount = { 0, 0, 0 }

local function Add(col, text, color)
    colCount[col] = (colCount[col] or 0) + 1
    local idx = colCount[col]
    local cols = panel.cols
    if not cols or not cols[col] then return end
    cols[col].rows = cols[col].rows or {}
    local fs = cols[col].rows[idx]
    if not fs then
        fs = cols[col]:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        fs:SetJustifyH("LEFT")
        fs:SetWidth(COL_W)
        fs:SetWordWrap(false)
        fs:SetPoint("TOPLEFT", 0, -(idx - 1) * ROW_H)
        cols[col].rows[idx] = fs
    end
    fs:SetText(text)
    if color then fs:SetTextColor(unpack(color)) else fs:SetTextColor(0.9, 0.9, 0.92) end
    fs:Show()
end

local function ClearColumns()
    colCount = { 0, 0, 0 }
    if not panel or not panel.cols then return end
    for i = 1, 3 do
        for _, fs in ipairs(panel.cols[i].rows or {}) do fs:Hide() end
    end
end

local function Refresh()
    if not panel then return end
    ClearColumns()

    -- 列 1：露营物资（可折叠）
    Add(1, "|cffffd700" .. L("露营物资", "Supplies") .. "|r")
    local usedPlus = {}
    local expanded = (ns.db and ns.db.campExpanded) or {}
    if expanded["__base"] == nil then expanded["__base"] = true end
    if ns.db then ns.db.campExpanded = expanded end
    for _, g in ipairs(state.groups or {}) do
        if g.dividerBefore then Add(1, "|cff3a3a3a---------|r") end
        local key = (g.title == L("基础", "Basic")) and "__base" or g.title
        local open = expanded[key]
        Add(1, string.format("      |cff7fb0ff%s|r", g.title))
        local hdrRow = colCount[1]
        if panel.plus then
            local btn = panel.plus[hdrRow]
            if not btn then
                btn = CreateFrame("Button", nil, panel.cols[1], "UIPanelButtonTemplate")
                btn:SetSize(18, 18)
                if btn.GetFontString then
                    local fs = btn:GetFontString()
                    if fs then fs:SetFont(STANDARD_TEXT_FONT, 12, "") end
                end
                panel.plus[hdrRow] = btn
            end
            btn:ClearAllPoints()
            btn:SetPoint("TOPLEFT", 0, -((hdrRow - 1) * ROW_H))
            btn:SetText(open and "-" or "+")
            btn:SetScript("OnClick", function()
                local nowOpen = not expanded[key]
                for k in pairs(expanded) do expanded[k] = false end
                expanded[key] = nowOpen
                if ns.db then ns.db.campExpanded = expanded end
                Refresh()
            end)
            btn:Show()
            usedPlus[hdrRow] = true
        end
        if open then
            for _, it in ipairs(g.items) do
                local owned = (it.count or 0) > 0
                local blocked = (it.group == "fire") and state.nearFire
                local text = string.format("      %s%s|r ×%d %s",
                    (owned and not blocked) and "|cffffffff" or "|cff606060",
                    it.name or tostring(it.id), it.count or 0, it.effect or "")
                Add(1, text, (owned and not blocked) and nil or DIM)
            end
        end
    end

    -- 列 2：露营 buff
    Add(2, "|cffffd700" .. L("露营 buff", "Camp buffs") .. "|r")
    Add(2, state.nearFire and "|cff4dcc59" .. L("营火在附近", "Campfire Nearby") .. "|r"
        or "|cffcc4d4d" .. L("营火在附近", "Campfire Nearby") .. "|r")
    for _, b in ipairs(state.buffs) do
        if b.active then
            Add(2, string.format("%s[%s] %s", b.name, b.src, FullTime(b.remain)))
        end
    end

    -- 列 3：其他经验 buff
    Add(2, " ")
    Add(2, "|cffffd700" .. L("其他经验 buff", "Other XP") .. "|r")
    if #state.xpbuffs == 0 then Add(2, "（无）", DIM) end
    for _, x in ipairs(state.xpbuffs) do
        Add(2, string.format("%s %s", x.name, FullTime(x.remain)))
    end

    -- 列 4：队伍
    Add(3, "|cffffd700" .. L("队伍", "Party") .. "|r")
    local any = false
    for name, p in pairs(state.peers) do
        any = true
        Add(3, string.format("%s %s %s", name, tostring(p.cap or "?"),
            (tonumber(p.cd) or 0) > 0 and FullTime(p.cd) or L("可用", "ready")))
    end
    if not any then Add(3, "（无数据）", DIM) end

    -- 隐藏本轮没用的分组按钮（否则会残留成"多出来的 +/-"）
    if panel.plus then
        for idx, b in pairs(panel.plus) do
            if not usedPlus[idx] then b:Hide() end
        end
    end

    -- 高度随内容增长
    local maxRows = math.max(colCount[1] or 0, colCount[2] or 0, colCount[3] or 0)
    if not (C:GetSetting("Camp", "collapsed") and true or false) then
        local h = math.max(180, maxRows * ROW_H + 54)
        if math.abs((panel:GetHeight() or 0) - h) > 1 then
            panel:SetHeight(h)
            if panel.cols then
                for _, col in ipairs(panel.cols) do col:SetHeight(h - 50) end
            end
        end
    end
end

local floatingIcon

local function SaveIconPos()
    if not floatingIcon then return end
    local es = floatingIcon:GetEffectiveScale() / UIParent:GetEffectiveScale()
    C:SetSetting("Camp", "iconX", math.floor(((floatingIcon:GetLeft() or 0) * es - (UIParent:GetLeft() or 0)) + 0.5))
    C:SetSetting("Camp", "iconY", math.floor(((floatingIcon:GetTop() or 0) * es - (UIParent:GetTop() or 0)) + 0.5))
end

local function CreateFloatingIcon()
    if floatingIcon then return floatingIcon end
    local b = CreateFrame("Button", "AzerothCampIcon", UIParent)
    b:SetSize(32, 32)
    b:SetFrameStrata("MEDIUM")
    b:SetMovable(true)
    b:SetClampedToScreen(true)
    local tex = b:CreateTexture(nil, "ARTWORK")
    tex:SetAllPoints()
    tex:SetTexture((C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(279981))
        or "Interface\\Icons\\INV_Misc_Campfire_01")
    b:RegisterForDrag("RightButton")
    b:SetScript("OnDragStart", function(self) self:StartMoving() end)
    b:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() SaveIconPos() end)
    b:SetScript("OnClick", function(_, button)
        if button == "RightButton" then return end
        C:SetSetting("Camp", "collapsed", not (C:GetSetting("Camp", "collapsed") and true or false))
        ApplyCollapse()
    end)
    floatingIcon = b
    return b
end

local function CreatePanel()
    local f = T:CreatePanel("AzerothCampFrame", UIParent, 1100, 460)
    f:SetFrameStrata("DIALOG")
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local es = self:GetEffectiveScale() / UIParent:GetEffectiveScale()
        C:SetSetting("Camp", "x", math.floor(((self:GetLeft() or 0) * es - (UIParent:GetLeft() or 0)) + 0.5))
        C:SetSetting("Camp", "y", math.floor(((self:GetTop() or 0) * es - (UIParent:GetTop() or 0)) + 0.5))
    end)

    local deco = f:CreateTexture(nil, "ARTWORK")
    deco:SetSize(24, 24)
    deco:SetPoint("TOPLEFT", 10, -4)
    deco:SetTexture((C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(279981))
        or "Interface\\Icons\\INV_Misc_Campfire_01")
    f.deco = deco

    local title = T:CreateText(f, 16, false)
    title:SetPoint("TOPLEFT", 40, -6)
    title:SetText(L("露营管理", "Camping"))

    local xBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    xBtn:SetSize(28, 28)
    xBtn:SetPoint("TOPRIGHT", -2, -2)
    xBtn:SetText("X")
    if xBtn.GetFontString then
        local fs = xBtn:GetFontString(); if fs then fs:SetFont(STANDARD_TEXT_FONT, 14, "") end
    end
    xBtn:SetScript("OnClick", function()
        C:SetSetting("Camp", "collapsed", true)
        ApplyCollapse()
    end)
    f.closeBtn = xBtn

    local reloadBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    reloadBtn:SetSize(28, 28)
    reloadBtn:SetPoint("TOPRIGHT", -34, -2)
    reloadBtn:SetText("R")
    if reloadBtn.GetFontString then
        local fs = reloadBtn:GetFontString(); if fs then fs:SetFont(STANDARD_TEXT_FONT, 14, "") end
    end
    reloadBtn:SetScript("OnClick", function() ReloadUI() end)
    f.reloadBtn = reloadBtn

    local widths = { 350, 430, 250 }
    f.cols = {}
    local x = 8
    for i = 1, 3 do
        local col = CreateFrame("Frame", nil, f)
        col:SetPoint("TOPLEFT", x, -38)
        col:SetSize(widths[i], 410)
        col.rows = {}
        f.cols[i] = col
        x = x + widths[i] + 8
    end
    COL_W = widths[1]

    f.plus = {}
    f.title = title
    panel = f
    CreateFloatingIcon()
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
