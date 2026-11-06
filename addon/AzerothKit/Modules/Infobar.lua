-- Modules\Infobar.lua · 可拖动信息条（时间 / FPS / 当前金币）
-- 演示：模块注册、主题复用、设置 schema、拖动 + 位置持久化、Agent 通过 Profile 改配置。
local ADDON, ns = ...
local C = ns.Core
local T = ns.Theme

local isCN = (ns.Platform.locale == "zhCN" or ns.Platform.locale == "zhTW")
local function L(zh, en)
    if isCN then return zh end
    return en
end

local M = C:RegisterModule("Infobar", {
    label = L("信息条", "Infobar"),
    defaultEnabled = true,
    flavors = { retail = true, forever = true },
    settings = {
        { key = "scale", type = "number", default = 1.0, min = 0.8, max = 1.6, step = 0.05, label = L("缩放", "Scale") },
        { key = "locked", type = "boolean", default = false, label = L("锁定位置", "Lock") },
        { key = "point", type = "string", default = "TOP", hidden = true },
        { key = "relPoint", type = "string", default = "TOP", hidden = true },
        { key = "x", type = "number", default = 0, hidden = true },
        { key = "y", type = "number", default = -30, hidden = true },
    },
})

local bar
local ticker
local saving = false
local sessionStart

local function Money()
    return (GetMoney and GetMoney()) or 0
end

local function SplitMoney(copper)
    local g = math.floor(copper / 10000)
    local s = math.floor((copper % 10000) / 100)
    local c = copper % 100
    return g, s, c
end

-- 纯文本（用于提示框）
local function PlainMoney(copper)
    local g, s, c = SplitMoney(copper)
    if isCN then
        if g > 0 then return string.format("%d金%d银%d铜", g, s, c) end
        if s > 0 then return string.format("%d银%d铜", s, c) end
        return string.format("%d铜", c)
    end
    return string.format("%dg %ds %dc", g, s, c)
end

-- 带颜色（用于信息条）
local function ColoredMoney(copper)
    local g, s, c = SplitMoney(copper)
    if isCN then
        if g > 0 then return string.format("|cffffd700%d金|r|cffd8d8d8%d银|r", g, s) end
        if s > 0 then return string.format("|cffd8d8d8%d银|r|cffb87333%d铜|r", s, c) end
        return string.format("|cffb87333%d铜|r", c)
    end
    if g > 0 then return string.format("|cffffd700%dg|r |cffd8d8d8%ds|r", g, s) end
    if s > 0 then return string.format("|cffd8d8d8%ds|r |cffb87333%dc|r", s, c) end
    return string.format("|cffb87333%dc|r", c)
end

-- 12.x 的正确接口是 GetFramerate()；GetFPS() 并不存在（旧代码把它当 0 了）
local function ReadFPS()
    local fps = (GetFramerate and GetFramerate()) or (GetFPS and GetFPS()) or 0
    return math.floor(tonumber(fps) or 0)
end

local function ColoredFPS(fps)
    if fps < 15 then
        return "|cffd80909" .. fps .. "|r"
    elseif fps < 30 then
        return "|cffe8da0f" .. fps .. "|r"
    end
    return "|cff0cd809" .. fps .. "|r"
end

local function ApplyLayout()
    if not bar then return end
    bar:SetScale(tonumber(C:GetSetting("Infobar", "scale")) or 1)
    bar.akLocked = C:GetSetting("Infobar", "locked") and true or false
    T:RestorePosition(bar,
        C:GetSetting("Infobar", "point"),
        C:GetSetting("Infobar", "relPoint"),
        tonumber(C:GetSetting("Infobar", "x")) or 0,
        tonumber(C:GetSetting("Infobar", "y")) or -30)
end
M.ApplyLayout = ApplyLayout

local function SavePosition(point, relPoint, x, y)
    saving = true
    C:SetSetting("Infobar", "point", point)
    C:SetSetting("Infobar", "relPoint", relPoint)
    C:SetSetting("Infobar", "x", math.floor((x or 0) + 0.5))
    C:SetSetting("Infobar", "y", math.floor((y or 0) + 0.5))
    saving = false
    ApplyLayout()
end

local function UpdateText()
    if not bar then return end
    local money = Money()
    if not sessionStart then
        sessionStart = money
    end
    bar.text:SetFormattedText("%s    |cff808080FPS|r %s    %s",
        date("%H:%M"), ColoredFPS(ReadFPS()), ColoredMoney(money))
end

local function ShowTooltip(self)
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
    GameTooltip:AddLine("AzerothKit · " .. L("信息条", "Infobar"))
    GameTooltip:AddDoubleLine(L("当前持有", "Held now"), PlainMoney(Money()))
    if sessionStart then
        local delta = Money() - sessionStart
        local sign = delta >= 0 and "+" or "-"
        GameTooltip:AddDoubleLine(L("本次登录变化", "Change this session"),
            sign .. PlainMoney(math.abs(delta)))
    end
    GameTooltip:AddLine(L("按住左键拖动", "Drag with left button"), 0.6, 0.6, 0.6)
    GameTooltip:Show()
end

function M:OnEnable()
    if not bar then
        bar = T:CreatePanel("AzerothKitInfobar", UIParent, 280, 20)
        bar:SetFrameStrata("BACKGROUND")
        bar.text = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        bar.text:SetPoint("CENTER")

        bar.hint = bar:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        bar.hint:SetPoint("BOTTOM", bar, "TOP", 0, 2)
        bar.hint:SetText(L("按住左键拖动，松手保存位置", "drag to move, release to save"))
        bar.hint:Hide()

        bar:SetScript("OnEnter", function(self)
            if not self.akLocked then self.hint:Show() end
            ShowTooltip(self)
        end)
        bar:SetScript("OnLeave", function(self)
            self.hint:Hide()
            GameTooltip:Hide()
        end)

        T:MakeMovable(bar, SavePosition)
    end

    sessionStart = Money()
    ApplyLayout()
    bar:Show()
    if not ticker then
        ticker = C_Timer.NewTicker(1, UpdateText)
    end
    UpdateText()
end

function M:OnDisable()
    if ticker then
        ticker:Cancel()
        ticker = nil
    end
    if bar then
        bar:Hide()
    end
end

function M:OnSettingChanged(key)
    if saving then return end
    if key == "scale" or key == "locked" or key == "point"
        or key == "relPoint" or key == "x" or key == "y" then
        ApplyLayout()
    end
end
