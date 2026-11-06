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
        { key = "locked",    type = "boolean", default = false, label = L("锁定位置", "Lock") },
        { key = "patternKit",   type = "string", default = "营火工具包", hidden = true },
        { key = "patternFlint", type = "string", default = "燧石",       hidden = true },
        { key = "patternWood",  type = "string", default = "木柴",       hidden = true },
        { key = "patternTent",  type = "string", default = "营地帐篷",   hidden = true },
        { key = "patternAid",   type = "string", default = "急救包",     hidden = true },
        { key = "patternToy",   type = "string", default = "探险帐篷",   hidden = true },
        { key = "patternAura",  type = "string", default = "帐篷,营地,休息,篝火,火堆,Nearby,Tent,Camp,Rested", hidden = true },
        { key = "auraIDs",      type = "string", default = "1229451,1229741", hidden = true },
        { key = "patternFireAura", type = "string", default = "营火,篝火,Campfire,Fire", hidden = true },
        { key = "campfireIDs", type = "string", default = "1229739,1283391", hidden = true },
        { key = "point",     type = "string", default = "TOPRIGHT", hidden = true },
        { key = "relPoint",  type = "string", default = "TOPRIGHT", hidden = true },
        { key = "x",         type = "number", default = -20, hidden = true },
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

-- 所有营地制品共享同一个 1 小时冷却：取所有候选里剩余时间最大的那个
local function SharedCooldown()
    return math.max(TentCooldown(), CraftCooldown(), AidCooldown())
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
    T:RestorePosition(panel,
        C:GetSetting("Camp", "point"),
        C:GetSetting("Camp", "relPoint"),
        tonumber(C:GetSetting("Camp", "x")) or -20,
        tonumber(C:GetSetting("Camp", "y")) or -120)
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
    local sharedCd = SharedCooldown()
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
            panel.tentStatus:SetText(L("共享冷却", "shared cd") .. " " .. FormatRemain(sharedCd))
        else
            panel.tentStatus:SetText("")
        end
    end

    -- 营火状态行
    if panel.fireStatus then
        if state.fireAura then
            panel.fireStatus:SetText("|cff4dcc59" .. L("营火", "Campfire") .. "|r " .. state.fireAura)
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

    UpdateTentButtons()
end

local function CreatePanel()
    local p = T:CreatePanel("AzerothKitCamp", UIParent, 230, 146)
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

    p.aura = T:CreateText(p, 11, true)
    p.aura:SetPoint("TOPLEFT", 10, -130)
    p.aura:SetPoint("TOPRIGHT", -10, -130)
    p.aura:SetText("")

    T:MakeMovable(p, function(point, relPoint, x, y)
        C:SetSetting("Camp", "point", point)
        C:SetSetting("Camp", "relPoint", relPoint)
        C:SetSetting("Camp", "x", math.floor((x or 0) + 0.5))
        C:SetSetting("Camp", "y", math.floor((y or 0) + 0.5))
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
    C:On("PLAYER_REGEN_ENABLED", UpdateTentButtons)
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
    C:Off("PLAYER_REGEN_ENABLED", UpdateTentButtons)
end

function M:OnSettingChanged(key)
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
