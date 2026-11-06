-- Modules\Infobar.lua · 示例模块：可拖动的顶部信息条（时间 / FPS / 金币）
-- 演示五件事：模块注册、主题复用、设置 schema、拖动 + 位置持久化、Agent 通过 Profile 改配置。
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

function M:ApplyLayout()
    if not bar then return end
    bar:SetScale(tonumber(C:GetSetting("Infobar", "scale")) or 1)
    bar.akLocked = C:GetSetting("Infobar", "locked") and true or false
    T:RestorePosition(bar,
        C:GetSetting("Infobar", "point"),
        C:GetSetting("Infobar", "relPoint"),
        tonumber(C:GetSetting("Infobar", "x")) or 0,
        tonumber(C:GetSetting("Infobar", "y")) or -30)
end

local function SavePosition(point, relPoint, x, y)
    saving = true
    C:SetSetting("Infobar", "point", point)
    C:SetSetting("Infobar", "relPoint", relPoint)
    C:SetSetting("Infobar", "x", math.floor((x or 0) + 0.5))
    C:SetSetting("Infobar", "y", math.floor((y or 0) + 0.5))
    saving = false
    M:ApplyLayout()
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

        bar.hint = bar:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        bar.hint:SetPoint("BOTTOM", bar, "TOP", 0, 2)
        bar.hint:SetText(L("按住左键拖动，松手保存位置", "drag to move, release to save"))
        bar.hint:Hide()

        bar:SetScript("OnEnter", function(self)
            if not self.akLocked then self.hint:Show() end
        end)
        bar:SetScript("OnLeave", function(self)
            self.hint:Hide()
        end)

        T:MakeMovable(bar, SavePosition)
    end

    self:ApplyLayout()
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
        self:ApplyLayout()
    end
end
