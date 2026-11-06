-- Modules\Infobar.lua · 示例模块：顶部信息条（时间 / FPS / 金币）
-- 演示四件事：模块注册、主题复用、设置 schema、Agent 通过 Profile.lua 改配置。
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
        { key = "offsetY", type = "number", default = -6, min = -200, max = 0, step = 1, label = L("垂直偏移", "Offset Y") },
    },
})

local bar
local ticker

local function ApplyLayout()
    if not bar then return end
    bar:SetScale(C:GetSetting("Infobar", "scale") or 1)
    bar:ClearAllPoints()
    bar:SetPoint("TOP", UIParent, "TOP", 0, C:GetSetting("Infobar", "offsetY") or -6)
end

local function UpdateText()
    if not bar then return end
    local clock = date("%H:%M")
    local fps = (GetFPS and GetFPS()) or 0
    local copper = (GetMoney and GetMoney()) or 0
    local gold = math.floor(copper / 10000)
    bar.text:SetFormattedText("%s    |cff808080FPS|r %d    |cffffd700%d|r %s",
        clock, fps, gold, L("金", "g"))
end

function M:OnEnable()
    if not bar then
        bar = T:CreatePanel("AzerothKitInfobar", UIParent, 280, 20)
        bar:SetFrameStrata("BACKGROUND")
        bar.text = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        bar.text:SetPoint("CENTER")
    end

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
    if key == "scale" or key == "offsetY" then
        ApplyLayout()
    end
end
