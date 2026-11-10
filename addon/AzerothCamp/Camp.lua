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
        { key = "width",     type = "number",  default = 280, min = 200, max = 460, step = 10, label = L("宽度", "Width") },
        { key = "collapsed", type = "boolean", default = false, label = L("折叠", "Collapsed") },
        { key = "locked",    type = "boolean", default = false, label = L("锁定位置", "Lock") },
        { key = "point",     type = "string",  default = "TOPLEFT", hidden = true },
        { key = "relPoint",  type = "string",  default = "TOPLEFT", hidden = true },
        { key = "x",         type = "number",  default = 20,   hidden = true },
        { key = "y",         type = "number",  default = -120, hidden = true },
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
    { id = AURA.welcoming, name = L("温馨营火", "Welcoming Campfire"), src = L("营火", "Campfire") },
    { id = AURA.nearby,    name = L("营火在附近", "Campfire Nearby"), src = L("营火", "Campfire") },
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
                effect = p.effect .. string.format(" T%d", tier), group = "prof", prof = p.key }
        end
    end
    for _, o in ipairs(ns.CampData.cooking) do
        local row = bags[o.item]
        items[#items + 1] = { id = o.item, name = ItemName(o.item), count = row and row.count or 0,
            bag = row and row.bag, slot = row and row.slot, effect = o.effect, group = "prof", prof = "cooking" }
    end
    state.items = items
    state.toy = toy

    -- buff
    local buffs = {}
    for _, b in ipairs(BUFFS) do
        local a = AuraByID(b.id)
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
local ROW_H = 14

local function ApplyCollapse()
    if not panel then return end
    local collapsed = C:GetSetting("Camp", "collapsed") and true or false
    if scroll then
        if collapsed then scroll:Hide() else scroll:Show() end
    end
    panel:SetHeight(collapsed and 26 or 320)
    if panel.toggle then panel.toggle:SetText(collapsed and "+" or "-") end
end

local function ApplyLayout()
    if not panel then return end
    panel:SetScale(tonumber(C:GetSetting("Camp", "scale")) or 1)
    panel:SetWidth(tonumber(C:GetSetting("Camp", "width")) or 280)
    panel.akLocked = C:GetSetting("Camp", "locked") and true or false
    ApplyCollapse()
    T:RestorePosition(panel, "TOPLEFT", "TOPLEFT",
        tonumber(C:GetSetting("Camp", "x")) or 20,
        tonumber(C:GetSetting("Camp", "y")) or -120)
end

local function Row(i)
    if not rows[i] then
        local fs
        if i == 1 or rows[i - 1] then fs = panel.content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall") end
        fs = fs or panel.content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        fs:SetJustifyH("LEFT")
        fs:SetWidth(260)
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

local function Refresh()
    if not panel then return end
    panel.lineCount = 0

    Header(L("1、露营物资", "1. Camping supplies"))
    for _, it in ipairs(state.items) do
        local owned = (it.count or 0) > 0
        local text = string.format("%s%s|r ×%d  |cff808080%s|r",
            owned and "|cffffffff" or "|cff606060", it.name or ("item:" .. tostring(it.id)),
            it.count or 0, it.effect or "")
        AddLine(text, owned and nil or DIM)
    end

    AddLine(" ")
    Header(L("2、露营 buff", "2. Camp buffs"))
    for _, b in ipairs(state.buffs) do
        local text = string.format("%s%s[%s]|r", b.active and "|cffffffff" or "|cff606060", b.name, b.src)
        if b.active then text = text .. "  " .. FullTime(b.remain) end
        AddLine(text, b.active and nil or DIM)
    end

    AddLine(" ")
    Header(L("3、其他经验 buff", "3. Other XP buffs"))
    if #state.xpbuffs == 0 then
        AddLine("  " .. L("（无）", "(none)"), DIM)
    else
        for _, x in ipairs(state.xpbuffs) do
            AddLine(string.format("|cffffffff%s|r  %s", x.name, FullTime(x.remain)))
        end
    end

    AddLine(" ")
    Header(L("4、队伍", "4. Party"))
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

    panel.content:SetHeight(math.max(10, panel.lineCount * ROW_H))
end

local function OnWheel(_, delta)
    local smax = math.max(0, (panel.content:GetHeight() or 0) - 300)
    panel.offset = math.min(smax, math.max(0, (panel.offset or 0) - delta * 24))
    panel.content:SetPoint("TOPLEFT", panel.scrollChild or panel.scroll, "TOPLEFT", 0, panel.offset)
end

local function CreatePanel()
    local f = T:CreatePanel("AzerothCampFrame", UIParent, 280, 320)
    f:SetFrameStrata("DIALOG")
    f:SetClampedToScreen(true)

    local title = T:CreateText(f, 12, false)
    title:SetPoint("TOPLEFT", 10, -8)
    title:SetText(L("露营管理", "Camping"))

    local toggle = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    toggle:SetSize(18, 18)
    toggle:SetPoint("TOPRIGHT", -6, -4)
    toggle:SetText("-")
    toggle:SetScript("OnClick", function()
        C:SetSetting("Camp", "collapsed", not (C:GetSetting("Camp", "collapsed") and true or false))
        ApplyCollapse()
    end)
    f.toggle = toggle

    local sf = CreateFrame("ScrollFrame", "AzerothCampScroll", f)
    sf:SetPoint("TOPLEFT", 6, -26)
    sf:SetPoint("BOTTOMRIGHT", -6, 6)
    sf:EnableMouseWheel(true)
    sf:SetScript("OnMouseWheel", OnWheel)

    local content = CreateFrame("Frame", nil, sf)
    content:SetSize(260, 10)
    sf:SetScrollChild(content)

    f.scroll = sf
    f.content = content
    f.offset = 0
    panel = f

    T:MakeMovable(f, function()
        local es = f:GetEffectiveScale() / UIParent:GetEffectiveScale()
        local nx = (f:GetLeft() or 0) * es - (UIParent:GetLeft() or 0)
        local ny = (f:GetTop() or 0) * es - (UIParent:GetTop() or 0)
        C:SetSetting("Camp", "x", math.floor(nx + 0.5))
        C:SetSetting("Camp", "y", math.floor(ny + 0.5))
        ApplyLayout()
    end)
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
