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
        { key = "locked",    type = "boolean", default = false, label = L("锁定位置", "Lock") },
        { key = "patternKit",   type = "string", default = "营火工具包", hidden = true },
        { key = "patternFlint", type = "string", default = "燧石",       hidden = true },
        { key = "patternWood",  type = "string", default = "木柴",       hidden = true },
        { key = "patternTent",  type = "string", default = "营地帐篷",   hidden = true },
        { key = "patternToy",   type = "string", default = "探险帐篷",   hidden = true },
        { key = "patternAura",  type = "string", default = "帐篷,营地,休息,Tent,Camp,Rested", hidden = true },
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
}

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
    local total, bagIdx, slotIdx, sampleID = 0, nil, nil, nil
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
                        bagIdx, slotIdx, sampleID = bag, slot, info.itemID
                    end
                end
            end
        end
    end
    return total, bagIdx, slotIdx, sampleID
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

    state.kit, state.kitBag, state.kitSlot = ScanBag(kit)
    state.flint = ScanBag(flint)
    state.wood = ScanBag(wood)
    state.tent, state.tentBag, state.tentSlot = ScanBag(tent)
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
    local needles = {}
    for piece in pattern:gmatch("[^,]+") do
        needles[#needles + 1] = piece
    end

    for _, filter in ipairs({ "HELPFUL", "HARMFUL" }) do
        for i = 1, 40 do
            local ok, data = pcall(api.GetAuraDataByIndex, "player", i, filter)
            if not ok or not data then break end
            local name = data.name
            if name then
                local hit = false
                for _, needle in ipairs(needles) do
                    if name:find(needle, 1, true) then hit = true break end
                end
                if hit then
                    local remain = (data.expirationTime or 0) - GetTime()
                    list[#list + 1] = { name = name, remain = remain, harmful = filter == "HARMFUL" }
                end
            end
        end
    end
    return list
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

local function ToggleTent()
    if state.toyID then
        local name = state.toyName or ""
        local ok = pcall(UseItemByName, name)
        if ok then return end
        print("|cff69ccf0[露营]|r 玩具无法直接使用，请在玩具箱里点击它。")
        return
    end

    if state.tent > 0 then
        if UseBag(state.tentBag, state.tentSlot) then return end
        print("|cff69ccf0[露营]|r 无法使用营地帐篷，请手动点击。")
        return
    end

    print("|cff69ccf0[露营]|r 没有可用的帐篷（玩具或制皮产品都没有）。")
end

-- ---------- 界面 ----------
local function FormatRemain(sec)
    if sec <= 0 then return L("剩余?", "?") end
    if sec >= 3600 then return string.format("%dh", math.floor(sec / 3600)) end
    if sec >= 60 then return string.format("%dm", math.floor(sec / 60)) end
    return string.format("%ds", math.floor(sec))
end

local function ApplyLayout()
    if not panel then return end
    panel:SetScale(tonumber(C:GetSetting("Camp", "scale")) or 1)
    panel.akLocked = C:GetSetting("Camp", "locked") and true or false
    T:RestorePosition(panel,
        C:GetSetting("Camp", "point"),
        C:GetSetting("Camp", "relPoint"),
        tonumber(C:GetSetting("Camp", "x")) or -20,
        tonumber(C:GetSetting("Camp", "y")) or -120)
end
M.ApplyLayout = ApplyLayout

local function Refresh()
    if not panel then return end

    -- 营火行
    local fireText, fireColor
    if state.kit > 0 then
        fireText = string.format("|cffffd700%s|r ×%d", L("营火工具包", "Campfire Kit"), state.kit)
        fireColor = { 1, 1, 1 }
    elseif state.flint > 0 then
        fireText = string.format("|cffd8d8d8%s|r ×%d", L("燧石和火绒", "Flint and Tinder"), state.flint)
        fireColor = { 1, 1, 1 }
    else
        fireText = "|cff606060" .. L("无营火材料", "No fire kit") .. "|r"
        fireColor = { 0.5, 0.5, 0.5 }
    end
    panel.fire:SetText(fireText)
    panel.fire:SetTextColor(fireColor[1], fireColor[2], fireColor[3])

    -- 帐篷行
    local tentText, tentColor
    if state.toyID then
        tentText = string.format("|cff69ccf0%s|r ×∞", state.toyName or L("探险帐篷", "Expedition Tent"))
        tentColor = { 1, 1, 1 }
    elseif state.tent > 0 then
        tentText = string.format("|cffd8d8d8%s|r ×%d", L("营地帐篷", "Camp Tent"), state.tent)
        tentColor = { 1, 1, 1 }
    else
        tentText = "|cff606060" .. L("无帐篷", "No tent") .. "|r"
        tentColor = { 0.5, 0.5, 0.5 }
    end
    panel.tent:SetText(tentText)
    panel.tent:SetTextColor(tentColor[1], tentColor[2], tentColor[3])

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
end

local function CreatePanel()
    local p = T:CreatePanel("AzerothKitCamp", UIParent, 300, 96)
    p:SetFrameStrata("LOW")
    p:SetClampedToScreen(true)

    p.title = T:CreateText(p, 11, true)
    p.title:SetPoint("TOPLEFT", 10, -8)
    p.title:SetText(L("露营管理", "Camping"))

    p.fire = T:CreateText(p, 12, false)
    p.fire:SetPoint("TOPLEFT", 10, -26)
    p.fire:SetPoint("TOPRIGHT", -10, -26)
    p.fire:SetText("")

    -- 行区块：可点击
    local fireBtn = CreateFrame("Button", nil, p)
    fireBtn:SetPoint("TOPLEFT", 6, -22)
    fireBtn:SetPoint("TOPRIGHT", -6, -22)
    fireBtn:SetHeight(18)
    fireBtn:SetScript("OnClick", function() ToggleFire() end)
    p.fireBtn = fireBtn

    p.tent = T:CreateText(p, 12, false)
    p.tent:SetPoint("TOPLEFT", 10, -50)
    p.tent:SetPoint("TOPRIGHT", -10, -50)
    p.tent:SetText("")

    local tentBtn = CreateFrame("Button", nil, p)
    tentBtn:SetPoint("TOPLEFT", 6, -46)
    tentBtn:SetPoint("TOPRIGHT", -6, -46)
    tentBtn:SetHeight(18)
    tentBtn:SetScript("OnClick", function() ToggleTent() end)
    p.tentBtn = tentBtn

    p.aura = T:CreateText(p, 11, true)
    p.aura:SetPoint("TOPLEFT", 10, -72)
    p.aura:SetPoint("TOPRIGHT", -10, -72)
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

function M:OnEnable()
    if not panel then
        panel = CreatePanel()
    end
    ApplyLayout()
    panel:Show()

    Rescan()
    Refresh()

    if not ticker then
        ticker = C_Timer.NewTicker(1, function()
            if panel and panel:IsShown() then
                Refresh()
            end
        end)
    end

    C:On("BAG_UPDATE", OnBagUpdate)
    C:On("BAG_UPDATE_DELAYED", OnBagDelayed)
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
end

function M:OnSettingChanged(key)
    if key == "scale" or key == "locked" or key == "point"
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

    add(string.format("%s: %d  %s: %d  %s: %d  %s: %d",
        "kit", state.kit, "flint", state.flint, "wood", state.wood, "tent", state.tent))
    add(string.format("recipe=%s  toy=%s(%s)",
        tostring(state.recipeID), tostring(state.toyID), tostring(state.toyName)))

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

    for _, a in ipairs(PlayerAuras()) do
        add(string.format("  aura %s %s", a.harmful and "debuff" or "buff", a.name))
    end

    return lines
end
