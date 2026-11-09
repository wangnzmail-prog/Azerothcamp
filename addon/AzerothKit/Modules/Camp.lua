-- Modules\Camp.lua · 露营管理：营火工具包 / 燧石火绒 / 帐篷 / 帐篷光环
-- 设计：全部按"名字片段"识别（物品、配方、玩具、光环），不写死 ID，
-- 因此换语言、换小版本都不容易坏；改名字只需要改设置里的 pattern。
local ADDON, ns = ...
local C = ns.Core
local T = ns.Theme

local isCN = (ns.Platform.locale == "zhCN" or ns.Platform.locale == "zhTW")
local function L(zh, en)
    if isCN then return zh end
    return en
end

local M = C:RegisterModule("Camp", {
    label = L("露营管理", "Camping"),
    defaultEnabled = true,
    flavors = { retail = true, forever = true },
    settings = {
        { key = "scale",     type = "number",  default = 1.0,  min = 0.8, max = 1.6, step = 0.05, label = L("缩放", "Scale") },
        { key = "width",     type = "number",  default = 230,  min = 160, max = 420, step = 5, label = L("宽度", "Width") },
        { key = "collapsed", type = "boolean", default = false, label = L("折叠", "Collapsed") },
        { key = "locked",    type = "boolean", default = false, label = L("锁定位置", "Lock") },
        { key = "patternKit",   type = "string", default = "营火工具包", hidden = true },
        { key = "patternFlint", type = "string", default = "燧石",       hidden = true },
        { key = "patternWood",  type = "string", default = "木柴",       hidden = true },
        { key = "patternTent",  type = "string", default = "营地帐篷",   hidden = true },
        { key = "patternAid",   type = "string", default = "急救包",     hidden = true },
        { key = "patternToy",   type = "string", default = "探险帐篷",   hidden = true },
        { key = "patternAura",  type = "string", default = "帐篷,营地,休息,篝火,火堆,Nearby,Tent,Camp,Rested", hidden = true },
        { key = "auraIDs",      type = "string", default = "1229741", hidden = true },
        { key = "patternFireAura", type = "string", default = "营火,篝火,Campfire,Fire", hidden = true },
        { key = "campfireIDs", type = "string", default = "1229739,1283391", hidden = true },
        { key = "point",     type = "string", default = "TOPLEFT", hidden = true },
        { key = "relPoint",  type = "string", default = "TOPLEFT", hidden = true },
        { key = "x",         type = "number", default = 20, hidden = true },
        { key = "y",         type = "number", default = -120, hidden = true },
    },
})

local panel, ticker
local scanPending = false
local state = {
    kit = 0, kitSlot = nil,
    flint = 0, wood = 0,
    tent = 0, tentSlot = nil,
    toyID = nil, toyName = nil,
    recipeID = nil,
    fireAura = nil,     -- 附近营火的光环名
    fireAuraID = nil,   -- 附近营火的光环 spellId
    tentReady = false,  -- 有帐篷 + 附近有营火 + 不在冷却
    toyReady = false,
    craftReady = false,
    aid = 0, aidBag = nil, aidSlot = nil, aidID = nil, aidName = nil,
    sharedCd = 0,
}

local function Needles(pattern)
    local list = {}
    for piece in (pattern or ""):gmatch("[^,]+") do
        local p = piece:match("^%s*(.-)%s*$")
        if p ~= "" then list[#list + 1] = p end
    end
    return list
end

local function ParseIDs(text)
    local list = {}
    for piece in (text or ""):gmatch("%d+") do
        list[#list + 1] = tonumber(piece)
    end
    return list
end

-- ---------- 查询 ----------
local function ItemName(itemID)
    if not itemID then return nil end
    local name = C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(itemID)
    if not name and C_Item and C_Item.GetItemInfo then
        name = C_Item.GetItemInfo(itemID)
    end
    return name
end

local function ScanBag(pattern)
    local total, bagIdx, slotIdx, sampleID, sampleName = 0, nil, nil, nil, nil
    local maxBag = NUM_BAG_SLOTS or 4
    for bag = 0, maxBag do
        local slots = C_Container.GetContainerNumSlots(bag) or 0
        for slot = 1, slots do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.itemID then
                local name = ItemName(info.itemID)
                if name and name:find(pattern, 1, true) then
                    total = total + (info.stackCount or 1)
                    if not bagIdx then
                        bagIdx, slotIdx, sampleID, sampleName = bag, slot, info.itemID, name
                    end
                end
            end
        end
    end
    return total, bagIdx, slotIdx, sampleID, sampleName
end

local function FindRecipe(pattern)
    local api = C_TradeSkillUI
    if not api or not api.GetAllRecipeIDs or not api.GetRecipeInfo then return nil end
    local ok, ids = pcall(api.GetAllRecipeIDs)
    if not ok or type(ids) ~= "table" then return nil end
    for _, id in ipairs(ids) do
        local info = api.GetRecipeInfo(id)
        if info and info.name and info.name:find(pattern, 1, true) then
            return id, info
        end
    end
end

local function FindToy(pattern)
    if not (C_ToyBox and C_ToyBox.GetNumFilteredToys and C_ToyBox.GetToyFromIndex) then
        return nil
    end
    local ok, n = pcall(C_ToyBox.GetNumFilteredToys)
    if not ok or not n then return nil end
    for i = 1, n do
        local itemID = C_ToyBox.GetToyFromIndex(i)
        local name = ItemName(itemID)
        if name and name:find(pattern, 1, true) then
            return itemID, name
        end
    end
end

-- ---------- 状态刷新 ----------
local function Rescan()
    local kit = C:GetSetting("Camp", "patternKit")
    local flint = C:GetSetting("Camp", "patternFlint")
    local wood = C:GetSetting("Camp", "patternWood")
    local tent = C:GetSetting("Camp", "patternTent")
    local toy = C:GetSetting("Camp", "patternToy")

    state.kit, state.kitBag, state.kitSlot, state.kitID, state.kitName = ScanBag(kit)
    state.flint, state.flintBag, state.flintSlot, state.flintID, state.flintName = ScanBag(flint)
    state.wood, state.woodBag, state.woodSlot, state.woodID, state.woodName = ScanBag(wood)
    state.tent, state.tentBag, state.tentSlot, state.tentID, state.tentName = ScanBag(tent)
    state.aid, state.aidBag, state.aidSlot, state.aidID, state.aidName = ScanBag(C:GetSetting("Camp", "patternAid"))
    if not state.recipeID then
        state.recipeID = FindRecipe(kit)
    end
    state.toyID, state.toyName = FindToy(toy)

    -- 按 itemID 识别所有营地制品（不再依赖名字）
    state.others = {}
    local lookup = ns.CampData and ns.CampData.lookup
    if lookup then
        for bag = 0, (NUM_BAG_SLOTS or 4) do
            local slots = C_Container.GetContainerNumSlots(bag) or 0
            for slot = 1, slots do
                local info = C_Container.GetContainerItemInfo(bag, slot)
                if info and info.itemID and lookup[info.itemID] then
                    local e = lookup[info.itemID]
                    local row = state.others[e.prof]
                    if not row then
                        row = { prof = e.prof, effect = e.effect, count = 0, name = ItemName(info.itemID), tier = e.tier }
                        state.others[e.prof] = row
                    end
                    row.count = row.count + (info.stackCount or 1)
                end
            end
        end
    end
end

local function PlayerAuras()
    local list = {}
    local api = C_UnitAuras
    if not api or not api.GetAuraDataByIndex then return list end
    local pattern = C:GetSetting("Camp", "patternAura") or ""
    local needles = Needles(pattern)
    local idSet = {}
    for _, id in ipairs(ParseIDs(C:GetSetting("Camp", "auraIDs"))) do
        idSet[id] = true
    end

    for _, filter in ipairs({ "HELPFUL", "HARMFUL" }) do
        for i = 1, 40 do
            local ok, data = pcall(api.GetAuraDataByIndex, "player", i, filter)
            if not ok or not data then break end
            local sid = data.spellId
            local name = data.name
            local hit = (sid ~= nil and not ns.Platform.IsSecret(sid) and idSet[sid] == true) or false
            if not hit and name then
                for _, needle in ipairs(needles) do
                    if name:find(needle, 1, true) then hit = true break end
                end
            end
            if hit and name then
                local remain = (data.expirationTime or 0) - GetTime()
                list[#list + 1] = { name = name, remain = remain, harmful = filter == "HARMFUL" }
            end
        end
    end
    return list
end

-- 附近营火：帐篷的前置条件
-- 实测 1.60.1：温馨营火 1229739 / 营火在附近 1283391（ID 优先，名字兜底）
local function ScanFireAura()
    local api = C_UnitAuras
    if not api or not api.GetAuraDataByIndex then return nil end

    local idSet = {}
    for _, id in ipairs(ParseIDs(C:GetSetting("Camp", "campfireIDs"))) do
        idSet[id] = true
    end
    local needles = Needles(C:GetSetting("Camp", "patternFireAura"))
    if not next(idSet) and #needles == 0 then return nil end

    for _, filter in ipairs({ "HELPFUL", "HARMFUL" }) do
        for i = 1, 40 do
            local ok, data = pcall(api.GetAuraDataByIndex, "player", i, filter)
            if not ok or not data then break end

            local sid = data.spellId
            if sid and not ns.Platform.IsSecret(sid) and idSet[sid] then
                return data.name, sid
            end

            local name = data.name
            if name then
                for _, n in ipairs(needles) do
                    if name:find(n, 1, true) then
                        return name, sid
                    end
                end
            end
        end
    end
    return nil
end

-- 营火工具包自身的冷却（实测 5 分钟）
local function KitCooldown()
    if not (state.kitBag and state.kitSlot and C_Container.GetContainerItemCooldown) then
        return 0
    end
    local start, duration = C_Container.GetContainerItemCooldown(state.kitBag, state.kitSlot)
    if start and duration and duration > 0 then
        local remain = (start + duration) - GetTime()
        if remain > 0 then return remain end
    end
    return 0
end

-- 帐篷冷却（玩具 1 小时 / 制皮帐篷同）
local function TentCooldown()
    local now = GetTime()
    if state.toyID and C_Item and C_Item.GetItemCooldown then
        local start, duration = C_Item.GetItemCooldown(state.toyID)
        if start and duration and duration > 0 then
            local remain = (start + duration) - now
            if remain > 0 then return remain end
        end
        return 0
    end
    if state.tentBag and state.tentSlot and C_Container.GetContainerItemCooldown then
        local start, duration = C_Container.GetContainerItemCooldown(state.tentBag, state.tentSlot)
        if start and duration and duration > 0 then
            local remain = (start + duration) - now
            if remain > 0 then return remain end
        end
    end
    return 0
end

-- 制皮帐篷冷却（背包物品）
local function CraftCooldown()
    if not (state.tentBag and state.tentSlot and C_Container.GetContainerItemCooldown) then
        return 0
    end
    local start, duration = C_Container.GetContainerItemCooldown(state.tentBag, state.tentSlot)
    if start and duration and duration > 0 then
        local remain = (start + duration) - GetTime()
        if remain > 0 then return remain end
    end
    return 0
end

local function AidCooldown()
    if not (state.aidBag and state.aidSlot and C_Container.GetContainerItemCooldown) then return 0 end
    local start, duration = C_Container.GetContainerItemCooldown(state.aidBag, state.aidSlot)
    if start and duration and duration > 0 then
        local remain = (start + duration) - GetTime()
        if remain > 0 then return remain end
    end
    return 0
end

-- 所有营地制品共享同一个 1 小时冷却，游戏用一个 debuff 表示：强化休息 1229451
local function SharedCooldown()
    local api = C_UnitAuras
    if api and api.GetAuraDataByIndex then
        for i = 1, 40 do
            local ok, data = pcall(api.GetAuraDataByIndex, "player", i, "HARMFUL")
            if not ok or not data then break end
            local sid = data.spellId
            local isIt = (sid ~= nil and not ns.Platform.IsSecret(sid) and sid == 1229451)
                or (data.name ~= nil and tostring(data.name):find("强化休息", 1, true) ~= nil)
            if isIt then
                local remain = (data.expirationTime or 0) - GetTime()
                if remain > 0 then return remain, true end
            end
        end
    end
    return math.max(TentCooldown(), CraftCooldown(), AidCooldown()), false
end

-- ---------- 动作 ----------
local function UseBag(bag, slot)
    if not bag or not slot then return false end
    local ok = pcall(C_Container.UseContainerItem, bag, slot)
    return ok
end

local function CraftKit()
    local recipeID = state.recipeID or FindRecipe(C:GetSetting("Camp", "patternKit"))
    local api = C_TradeSkillUI
    if recipeID and api and api.CraftRecipe then
        local ok = pcall(api.CraftRecipe, recipeID, 1)
        if ok then return true end
    end
    if api and api.OpenTradeSkill then
        pcall(api.OpenTradeSkill, (Enum and Enum.SkillLine and Enum.SkillLine.Cooking) or 185)
        -- 有些客户端要先打开专业窗口，GetAllRecipeIDs 才返回配方；开完再找一次
        C_Timer.After(1, function()
            state.recipeID = nil
            Rescan()
            Refresh()
        end)
    end
    return false
end

local function ToggleFire()
    if state.kit > 0 then
        if UseBag(state.kitBag, state.kitSlot) then return end
        print("|cff69ccf0[露营]|r 无法使用营火工具包，请手动点击。")
        return
    end

    if state.flint == 0 then
        print("|cff69ccf0[露营]|r 背包里既没有营火工具包，也没有燧石和火绒。")
        return
    end

    if state.wood == 0 then
        print("|cff69ccf0[露营]|r 有燧石和火绒，但缺少普通木柴。")
        return
    end

    if CraftKit() then
        print("|cff69ccf0[露营]|r 已制造基础营火工具包。")
    else
        print("|cff69ccf0[露营]|r 无法直接制造，已打开烹饪面板，请手动点一次「基础营火工具包」。")
    end
end

-- ---------- 界面 ----------
local function FormatRemain(sec)
    if not sec or sec <= 0 then return L("剩余?", "?") end
    sec = math.ceil(sec)   -- 与官方冷却显示一致：向上取整，避免比官方快/慢 1 秒
    if sec >= 3600 then
        return string.format("%d:%02d:%02d", math.floor(sec / 3600),
            math.floor((sec % 3600) / 60), sec % 60)
    end
    return string.format("%d:%02d", math.floor(sec / 60), sec % 60)
end

local function ApplyLayout()
    if not panel then return end
    panel:SetScale(tonumber(C:GetSetting("Camp", "scale")) or 1)
    panel:SetWidth(tonumber(C:GetSetting("Camp", "width")) or 230)
    panel.akLocked = C:GetSetting("Camp", "locked") and true or false
    M:ApplyCollapse()
    -- 统一用左上角锚点：折叠/展开只向下生长；位置一律按 x/y 恢复，避免回弹
    T:RestorePosition(panel, "TOPLEFT", "TOPLEFT",
        tonumber(C:GetSetting("Camp", "x")) or 20,
        tonumber(C:GetSetting("Camp", "y")) or -120)
end
function M:ApplyCollapse()
    if not panel then return end
    local collapsed = C:GetSetting("Camp", "collapsed") and true or false
    for _, obj in ipairs(panel.body or {}) do
        if obj then
            if collapsed then obj:Hide() else obj:Show() end
        end
    end
    panel:SetHeight(collapsed and 26 or 268)
    if panel.version then
        if collapsed then panel.version:Hide() else panel.version:Show() end
    end
    if panel.toggle then panel.toggle:SetText(collapsed and "+" or "-") end
end

M.ApplyLayout = ApplyLayout

-- 帐篷行用安全按钮：玩具只能靠安全属性触发，普通 Lua 调不动
local function UpdateTentButtons()
    if InCombatLockdown and InCombatLockdown() then
        return -- 战斗中不能改安全属性，等脱战再刷
    end
    if not panel then return end

    local toyBtn = panel.toyBtn
    if toyBtn then
        if state.toyReady and state.toyID then
            toyBtn:SetAttribute("type", "toy")
            toyBtn:SetAttribute("toy", "item:" .. state.toyID)
        else
            toyBtn:SetAttribute("type", nil)
            toyBtn:SetAttribute("toy", nil)
        end
    end

    local aidBtn = panel.aidBtn
    if aidBtn then
        if state.aidReady and state.aidID then
            aidBtn:SetAttribute("type", "item")
            aidBtn:SetAttribute("item", "item:" .. state.aidID)
        else
            aidBtn:SetAttribute("type", nil)
            aidBtn:SetAttribute("item", nil)
        end
    end

    local craftBtn = panel.craftBtn
    if craftBtn then
        if state.craftReady and state.tentID then
            craftBtn:SetAttribute("type", "item")
            craftBtn:SetAttribute("item", "item:" .. state.tentID)
        else
            craftBtn:SetAttribute("type", nil)
            craftBtn:SetAttribute("item", nil)
        end
    end
end

local function Refresh()
    if not panel then return end

    state.fireAura, state.fireAuraID = ScanFireAura()

    -- 营火行
    local fireText, fireColor
    if state.kit > 0 then
        fireText = string.format("|cffffd700%s|r ×%d",
            state.kitName or L("营火工具包", "Campfire Kit"), state.kit)
        fireColor = { 1, 1, 1 }
    elseif state.flint > 0 then
        fireText = string.format("|cffd8d8d8%s|r ×%d",
            state.flintName or L("燧石和火绒", "Flint and Tinder"), state.flint)
        fireColor = { 1, 1, 1 }
    else
        fireText = "|cff606060" .. L("无营火材料", "No fire kit") .. "|r"
        fireColor = { 0.5, 0.5, 0.5 }
    end
    local kitCd = (state.kit > 0) and KitCooldown() or 0
    if kitCd > 0 then
        fireText = fireText .. "  |cff606060" .. FormatRemain(kitCd) .. "|r"
    end
    panel.fire:SetText(fireText)
    panel.fire:SetTextColor(fireColor[1], fireColor[2], fireColor[3])

    -- 帐篷：玩具(+20%) 与 制皮帐篷(+5%) 各自独立判定
    local sharedCd, cdFromAura = SharedCooldown()
    state.sharedCd = sharedCd
    local readyBase = (state.fireAura ~= nil) and (sharedCd <= 0)
    state.toyReady = readyBase and (state.toyID ~= nil)
    state.craftReady = readyBase and (state.tent > 0 and state.tentID ~= nil)
    state.aidReady = readyBase and (state.aid > 0 and state.aidID ~= nil)

    if panel.tent then
        if state.toyID then
            local text = string.format("|cff69ccf0%s|r |cff808080+20%%|r",
                state.toyName or L("探险帐篷", "Expedition Tent"))
            panel.tent:SetText(text)
        else
            panel.tent:SetText("|cff606060" .. L("无探险帐篷玩具", "No expedition tent") .. "|r")
        end
        panel.tent:SetTextColor(1, 1, 1)
    end

    if panel.tentCraft then
        if state.tent > 0 then
            local text = string.format("|cffd8d8d8%s|r ×%d |cff808080+5%%|r",
                state.tentName or L("营地帐篷", "Camp Tent"), state.tent)
            panel.tentCraft:SetText(text)
        else
            panel.tentCraft:SetText("|cff606060" .. L("无营地帐篷", "No camp tent") .. "|r")
        end
    end

    if panel.aid then
        if state.aid > 0 then
            panel.aid:SetText(string.format("|cffd8d8d8%s|r ×%d",
                state.aidName or L("急救包", "First Aid Kit"), state.aid))
        else
            panel.aid:SetText("|cff606060" .. L("无急救包", "No first aid kit") .. "|r")
        end
    end

    if panel.tentStatus then
        if not state.fireAura then
            panel.tentStatus:SetText(L("需要附近有营火", "needs a campfire"))
        elseif sharedCd > 0 then
            local label = cdFromAura and L("强化休息", "Rested") or L("共享冷却", "shared cd")
            panel.tentStatus:SetText(label .. " " .. FormatRemain(sharedCd))
        else
            panel.tentStatus:SetText("")
        end
    end

    -- 营火状态行
    if panel.fireStatus then
        if state.fireAura then
            local cap = OwnSlots()
            for _, p in pairs(ns.CampPeers or {}) do cap = math.max(cap, tonumber(p.slots) or 0) end
            local suffix = cap > 0 and string.format(" · %d格", cap) or ""
            panel.fireStatus:SetText("|cff4dcc59" .. L("营火", "Campfire") .. "|r " .. state.fireAura .. suffix)
        else
            panel.fireStatus:SetText("|cff606060" .. L("营火：附近没有", "Campfire: none nearby") .. "|r")
        end
    end

    -- 光环行
    local auras = PlayerAuras()
    if #auras == 0 then
        panel.aura:SetText("|cff606060" .. L("无帐篷光环", "No tent aura") .. "|r")
    else
        local parts = {}
        for i = 1, math.min(#auras, 3) do
            local a = auras[i]
            local color = a.harmful and "|cffff5050" or "|cff4dcc59"
            parts[#parts + 1] = string.format("%s%s|r %s", color, a.name, FormatRemain(a.remain))
        end
        panel.aura:SetText(table.concat(parts, "  "))
    end

    -- 小队：谁在冷却、谁能放什么
    if panel.peerLines then
        local peers = ns.CampPeers or {}
        local names = {}
        for name in pairs(peers) do names[#names + 1] = name end
        table.sort(names)
        for i = 1, 3 do
            local fs = panel.peerLines[i]
            local name = names[i]
            if name then
                local info = peers[name]
                local cd = tonumber(info.cd) or 0
                local cdText = (cd > 0) and FormatRemain(cd) or L("可用", "ready")
                fs:SetText(string.format("%s  %s  %s", name, tostring(info.cap or "?"), cdText))
            else
                fs:SetText(i == 1 and L("（等队友数据）", "(waiting for party)") or "")
            end
        end
    end

    UpdateTentButtons()
end

local function CreatePanel()
    local p = T:CreatePanel("AzerothKitCamp", UIParent, 230, 268)
    p:SetFrameStrata("LOW")
    p:SetClampedToScreen(true)

    p.title = T:CreateText(p, 11, true)
    p.title:SetPoint("TOPLEFT", 10, -8)
    p.title:SetText(L("露营管理", "Camping"))

    p.fire = T:CreateText(p, 12, false)
    p.fire:SetPoint("TOPLEFT", 10, -24)
    p.fire:SetPoint("TOPRIGHT", -10, -24)
    p.fire:SetText("")

    -- 行区块：可点击
    local fireBtn = CreateFrame("Button", nil, p)
    fireBtn:SetPoint("TOPLEFT", 6, -20)
    fireBtn:SetPoint("TOPRIGHT", -6, -20)
    fireBtn:SetHeight(18)
    fireBtn:SetScript("OnClick", function() ToggleFire() end)
    p.fireBtn = fireBtn

    p.tent = T:CreateText(p, 12, false)
    p.tent:SetPoint("TOPLEFT", 10, -44)
    p.tent:SetPoint("TOPRIGHT", -10, -44)
    p.tent:SetText("")

    local toyBtn = CreateFrame("Button", nil, p, "SecureActionButtonTemplate")
    toyBtn:SetPoint("TOPLEFT", 6, -40)
    toyBtn:SetPoint("TOPRIGHT", -6, -40)
    toyBtn:SetHeight(16)
    toyBtn:RegisterForClicks("AnyUp")
    p.toyBtn = toyBtn

    p.tentCraft = T:CreateText(p, 12, false)
    p.tentCraft:SetPoint("TOPLEFT", 10, -62)
    p.tentCraft:SetPoint("TOPRIGHT", -10, -62)
    p.tentCraft:SetText("")

    local craftBtn = CreateFrame("Button", nil, p, "SecureActionButtonTemplate")
    craftBtn:SetPoint("TOPLEFT", 6, -58)
    craftBtn:SetPoint("TOPRIGHT", -6, -58)
    craftBtn:SetHeight(16)
    craftBtn:RegisterForClicks("AnyUp")
    p.craftBtn = craftBtn

    p.aid = T:CreateText(p, 12, false)
    p.aid:SetPoint("TOPLEFT", 10, -80)
    p.aid:SetPoint("TOPRIGHT", -10, -80)
    p.aid:SetText("")

    local aidBtn = CreateFrame("Button", nil, p, "SecureActionButtonTemplate")
    aidBtn:SetPoint("TOPLEFT", 6, -76)
    aidBtn:SetPoint("TOPRIGHT", -6, -76)
    aidBtn:SetHeight(16)
    aidBtn:RegisterForClicks("AnyUp")
    p.aidBtn = aidBtn

    p.tentStatus = T:CreateText(p, 10, true)
    p.tentStatus:SetPoint("TOPLEFT", 10, -98)
    p.tentStatus:SetPoint("TOPRIGHT", -10, -98)
    p.tentStatus:SetText("")

    p.fireStatus = T:CreateText(p, 11, true)
    p.fireStatus:SetPoint("TOPLEFT", 10, -114)
    p.fireStatus:SetPoint("TOPRIGHT", -10, -114)
    p.fireStatus:SetText("")

    p.peerTitle = T:CreateText(p, 10, true)
    p.peerTitle:SetPoint("TOPLEFT", 10, -148)
    p.peerTitle:SetText(L("小队露营", "Party camping"))

    p.peerLines = {}
    for i = 1, 3 do
        local fs = T:CreateText(p, 10, true)
        fs:SetPoint("TOPLEFT", 10, -164 - (i - 1) * 14)
        fs:SetText("")
        p.peerLines[i] = fs
    end

    p.aura = T:CreateText(p, 11, true)
    p.aura:SetPoint("TOPLEFT", 10, -208)
    p.aura:SetPoint("TOPRIGHT", -10, -208)
    p.aura:SetText("")

    p.otherTitle = T:CreateText(p, 10, true)
    p.otherTitle:SetPoint("TOPLEFT", 10, -208)
    p.otherTitle:SetText(L("其他营地制品", "Other camp items"))

    p.otherLines = {}
    for i = 1, 3 do
        local fs = T:CreateText(p, 10, true)
        fs:SetPoint("TOPLEFT", 10, -224 - (i - 1) * 14)
        fs:SetText("")
        p.otherLines[i] = fs
    end

    p.version = T:CreateText(p, 9, true)
    p.version:SetPoint("BOTTOMLEFT", 10, 6)
    p.version:SetText("AzerothKit v" .. tostring(ns.VERSION or "?"))

    p.body = { p.fire, fireBtn, p.otherTitle, p.otherLines[1], p.otherLines[2], p.otherLines[3], p.tent, toyBtn, p.tentCraft, craftBtn, p.aid, aidBtn,
        p.tentStatus, p.fireStatus, p.aura, p.peerTitle, p.peerLines[1], p.peerLines[2], p.peerLines[3] }

    local toggle = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
    toggle:SetSize(18, 18)
    toggle:SetPoint("TOPRIGHT", -6, -4)
    toggle:SetScript("OnClick", function()
        local now = not (C:GetSetting("Camp", "collapsed") and true or false)
        C:SetSetting("Camp", "collapsed", now)
        M:ApplyCollapse()
    end)
    p.toggle = toggle

    -- 标题栏快捷按钮：错误 / 小队 / 重载（始终可见，不受折叠影响）
    local function HeaderButton(text, tip, onClick, offsetX)
        local b = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
        b:SetSize(18, 18)
        b:SetPoint("TOPRIGHT", offsetX, -4)
        b:SetText(text)
        local fs = b:GetFontString()
        if fs then fs:SetFont(STANDARD_TEXT_FONT, 10, "") end
        b:SetScript("OnClick", onClick)
        b:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
            GameTooltip:SetText(tip, 1, 1, 1)
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        return b
    end

    p.btnErr = HeaderButton("E", L("查看报错", "Errors"), function()
        if ns.Diagnostics and ns.Diagnostics.PrintErrors then ns.Diagnostics.PrintErrors() end
    end, -28)

    p.btnGroup = HeaderButton("G", L("小队露营状态", "Party camping"), function()
        if ns.Diagnostics and ns.Diagnostics.PrintGroup then ns.Diagnostics.PrintGroup() end
    end, -50)

    p.btnReload = HeaderButton("R", L("重载界面 /reload", "Reload UI"), function()
        ReloadUI()
    end, -72)

    T:MakeMovable(p, function(point, relPoint, x, y)
        -- 不信任 GetPoint 返回的锚点：一律换算成左上角偏移再存，否则会被 ApplyLayout 拉回
        local es = p:GetEffectiveScale() / UIParent:GetEffectiveScale()
        local nx = (p:GetLeft() or 0) * es - (UIParent:GetLeft() or 0)
        local ny = (p:GetTop() or 0) * es - (UIParent:GetTop() or 0)
        C:SetSetting("Camp", "point", "TOPLEFT")
        C:SetSetting("Camp", "relPoint", "TOPLEFT")
        C:SetSetting("Camp", "x", math.floor(nx + 0.5))
        C:SetSetting("Camp", "y", math.floor(ny + 0.5))
        ApplyLayout()
    end)

    return p
end

local function OnBagUpdate()
    if scanPending then return end
    scanPending = true
    C_Timer.After(0.5, function()
        scanPending = false
        Rescan()
        Refresh()
    end)
end

local function OnBagDelayed()
    Rescan()
    Refresh()
end

local function OnSkillLinesChanged()
    state.recipeID = nil
    Rescan()
    Refresh()
end

-- 战斗中整块隐藏：露营只能在战斗外做，避免挡视线
local wasShown = false
local function OnCombatStart()
    if not panel then return end
    wasShown = panel:IsShown()
    if wasShown then panel:Hide() end
end

local function OnCombatEnd()
    if panel and wasShown then
        panel:Show()
        wasShown = false
    end
    -- 其他营地制品（按 itemID 识别，与语言无关）
    if panel.otherLines then
        local list = {}
        for prof, row in pairs(state.others or {}) do
            list[#list + 1] = { prof = prof, row = row }
        end
        table.sort(list, function(a, b) return tostring(a.prof) < tostring(b.prof) end)

        for i = 1, 3 do
            local fs = panel.otherLines[i]
            local entry = list[i]
            if entry then
                fs:SetText(string.format("%s ×%d  |cff808080%s|r",
                    tostring(entry.row.name or entry.prof), entry.row.count or 0,
                    tostring(entry.row.effect or "")))
            elseif i == 1 then
                local peers = ns.CampPeers or {}
                local hasPeer = next(peers) ~= nil
                fs:SetText("|cff606060" .. (hasPeer and L("无其他营地制品", "none") or
                    L("无其他制品（队友未装插件时只能看到自己）", "none (teammates without addon)")) .. "|r")
            else
                fs:SetText("")
            end
        end
    end

    UpdateTentButtons()
end

function M:OnEnable()
    if not panel then
        panel = CreatePanel()
    end
    ApplyLayout()
    panel:Show()

    Rescan()
    Refresh()

    if not ticker then
        ticker = C_Timer.NewTicker(0.5, function()
            if panel and panel:IsShown() then
                Refresh()
            end
        end)
    end

    C:On("BAG_UPDATE", OnBagUpdate)
    C:On("BAG_UPDATE_DELAYED", OnBagDelayed)
    C:On("SKILL_LINES_CHANGED", OnSkillLinesChanged)
    C:On("PLAYER_REGEN_ENABLED", OnCombatEnd)
    C:On("PLAYER_REGEN_DISABLED", OnCombatStart)
end

function M:OnDisable()
    if ticker then
        ticker:Cancel()
        ticker = nil
    end
    if panel then
        panel:Hide()
    end
    C:Off("BAG_UPDATE", OnBagUpdate)
    C:Off("BAG_UPDATE_DELAYED", OnBagDelayed)
    C:Off("SKILL_LINES_CHANGED", OnSkillLinesChanged)
    C:Off("PLAYER_REGEN_ENABLED", OnCombatEnd)
    C:Off("PLAYER_REGEN_DISABLED", OnCombatStart)
end

function M:OnSettingChanged(key)
    if key == "collapsed" then M:ApplyCollapse() return end
    if key == "scale" or key == "width" or key == "locked" or key == "point"
        or key == "relPoint" or key == "x" or key == "y" then
        ApplyLayout()
    else
        Rescan()
        Refresh()
    end
end

-- 给 /ak camp 用的诊断输出
function M:ScanReport()
    local lines = {}
    local function add(text) lines[#lines + 1] = text end

    add("AzerothKit " .. tostring(ns.VERSION or "?"))
    add(string.format("%s: %d  %s: %d  %s: %d  %s: %d",
        "kit", state.kit, "flint", state.flint, "wood", state.wood, "tent", state.tent))
    add(string.format("recipe=%s  toy=%s(%s)",
        tostring(state.recipeID), tostring(state.toyID), tostring(state.toyName)))
    if state.others then
        for prof, row in pairs(state.others) do
            add(string.format("  campItem %s  x%d  %s  (%s)", prof, row.count,
                tostring(row.name), tostring(row.effect)))
        end
    end
    add(string.format("fireAura=%s(%s)  toyReady=%s  craftReady=%s  toyCd=%s  craftCd=%s",
        tostring(state.fireAura), tostring(state.fireAuraID), tostring(state.toyReady),
        tostring(state.craftReady), tostring(math.floor(SharedCooldown())),
        tostring(math.floor(AidCooldown()))))

    for bag = 0, (NUM_BAG_SLOTS or 4) do
        local slots = C_Container.GetContainerNumSlots(bag) or 0
        for slot = 1, slots do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.itemID then
                local name = ItemName(info.itemID)
                if name and (name:find("营火", 1, true) or name:find("帐篷", 1, true)
                    or name:find("木柴", 1, true) or name:find("燧石", 1, true)) then
                    add(string.format("  bag %d slot %d  id=%d  x%d  %s",
                        bag, slot, info.itemID, info.stackCount or 1, name))
                end
            end
        end
    end

    -- 全部光环（不只是匹配到的）：便于定位营火/帐篷光环的真实名字与 spellId
    local api = C_UnitAuras
    if api and api.GetAuraDataByIndex then
        for _, filter in ipairs({ "HELPFUL", "HARMFUL" }) do
            local kind = (filter == "HELPFUL") and "buff" or "debuff"
            for i = 1, 60 do
                local ok, data = pcall(api.GetAuraDataByIndex, "player", i, filter)
                if not ok or not data then break end
                local okText, text = pcall(function()
                    return string.format("  %s id=%s  %s", kind,
                        tostring(data.spellId), tostring(data.name))
                end)
                if okText then
                    add(text)
                else
                    add("  " .. kind .. " (secret)")
                end
            end
        end
    end

    if state.toyID and C_Item and C_Item.GetItemCooldown then
        local okCd, start, duration = pcall(C_Item.GetItemCooldown, state.toyID)
        if okCd then
            add(string.format("  toy cooldown start=%s duration=%s",
                tostring(start), tostring(duration)))
        end
    end

    return lines
end

-- 给小队同步用的对外信息：个人冷却剩余 + 当前最能放的营地制品
function M:GetBroadcastInfo()
    local cd = SharedCooldown()
    local cap = "none"
    if state.toyID then cap = "toy"
    elseif state.tent > 0 then cap = "craft"
    elseif state.aid > 0 then cap = "aid" end
    return cd, cap
end