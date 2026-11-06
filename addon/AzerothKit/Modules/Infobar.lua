-- Modules\Infobar.lua · 示例模块：顶部信息条（时间 / FPS / 金币）
-- 这个模块的作用是证明"注册 → 主题 → 开关 → 持久化"这条链路是通的。
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
})

local bar
local ticker

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
        bar:SetPoint("TOP", UIParent, "TOP", 0, -6)
        bar:SetFrameStrata("BACKGROUND")
        bar.text = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        bar.text:SetPoint("CENTER")
    end

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
