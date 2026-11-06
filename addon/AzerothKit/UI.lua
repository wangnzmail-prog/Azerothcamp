-- UI.lua · 主面板：版本信息 + 模块开关 + 能力矩阵
local ADDON, ns = ...
local P = ns.Platform
local C = ns.Core
local T = ns.Theme

local isCN = (P.locale == "zhCN" or P.locale == "zhTW")
local function L(zh, en)
    if isCN then return zh end
    return en
end

local frame
local rows = {}
local caps = {}

local function ApplyPosition(f)
    f:ClearAllPoints()
    local pos = ns.db and ns.db.pos
    if pos and pos.point and pos.relPoint then
        f:SetPoint(pos.point, UIParent, pos.relPoint, pos.x or 0, pos.y or 0)
    else
        f:SetPoint("CENTER")
    end
end

local function CreateMainFrame()
    local f = T:CreatePanel("AzerothKitFrame", UIParent, 470, 440)
    f:SetFrameStrata("DIALOG")
    f:SetToplevel(true)
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relPoint, x, y = self:GetPoint()
        if ns.db then
            ns.db.pos = { point = point, relPoint = relPoint, x = x, y = y }
        end
    end)

    local title = T:CreateTitle(f, "AzerothKit 0.2.0")
    title:SetPoint("TOPLEFT", T.padding, -12)

    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -4, -4)

    f.header = T:CreateText(f, 11, true)
    f.header:SetPoint("TOPLEFT", T.padding, -38)
    f.header:SetPoint("TOPRIGHT", -T.padding, -38)
    f.header:SetText("")

    local mlabel = T:CreateText(f, 11, true)
    mlabel:SetPoint("TOPLEFT", T.padding, -62)
    mlabel:SetText(L("模块", "MODULES"))
    T:CreateDivider(f, -76)

    for i = 1, 10 do
        local cb = T:CreateCheckbox(f, "")
        cb:SetPoint("TOPLEFT", T.padding, -86 - (i - 1) * 22)
        cb:SetScript("OnClick", function(self)
            if self.moduleName then
                C:SetModuleEnabled(self.moduleName, self:GetChecked() and true or false)
                ns.RefreshMainFrame()
            end
        end)
        rows[i] = cb
    end

    local clabel = T:CreateText(f, 11, true)
    clabel:SetPoint("TOPLEFT", T.padding, -312)
    clabel:SetText(L("能力探测", "CAPABILITIES"))
    T:CreateDivider(f, -326)

    for i = 1, 4 do
        local fs = T:CreateText(f, 11, false)
        fs:SetPoint("TOPLEFT", T.padding, -338 - (i - 1) * 17)
        fs:SetText("")
        caps[i] = fs
    end

    local probeBtn = T:CreateButton(f, L("打印诊断", "Print probe"), 110, 22)
    probeBtn:SetPoint("BOTTOMLEFT", T.padding, 16)
    probeBtn:SetScript("OnClick", function()
        if ns.Diagnostics and ns.Diagnostics.PrintProbe then
            ns.Diagnostics.PrintProbe()
        end
    end)

    local hideBtn = T:CreateButton(f, L("关闭", "Close"), 70, 22)
    hideBtn:SetPoint("LEFT", probeBtn, "RIGHT", 8, 0)
    hideBtn:SetScript("OnClick", function() f:Hide() end)

    local cb = T:CreateCheckbox(f, L("登录时提示", "Print on login"))
    cb:SetPoint("BOTTOMRIGHT", -T.padding, 16)
    cb:SetScript("OnClick", function(self)
        if ns.db then ns.db.showOnLogin = self:GetChecked() and true or false end
    end)
    f.showOnLogin = cb

    return f
end

function ns.RefreshMainFrame()
    if not frame then return end

    frame.header:SetText(string.format("%s   |cff808080build %s · Interface %d|r",
        P.GetFlavorLabel(), P.version, P.toc))

    local order, modules = C:GetModules()
    for i, cb in ipairs(rows) do
        local name = order[i]
        if name then
            local m = modules[name]
            local supported = C:IsModuleSupported(name)
            cb.moduleName = name
            cb.label:SetText(m.label or name)
            cb:SetChecked(C:IsModuleEnabled(name))
            if supported then
                cb:Enable()
                cb.label:SetTextColor(unpack(T.color.text))
            else
                cb:Disable()
                cb.label:SetTextColor(unpack(T.color.dim))
            end
            cb:Show()
        else
            cb.moduleName = nil
            cb:Hide()
        end
    end

    local list = P.GetCapabilities()
    for i, fs in ipairs(caps) do
        local cap = list[i]
        if cap then
            local mark = cap.ok and "|cff4dcc59OK|r" or "|cffcc4d4d--|r"
            fs:SetText(mark .. "  " .. cap.label)
        else
            fs:SetText("")
        end
    end

    if frame.showOnLogin and ns.db then
        frame.showOnLogin:SetChecked(ns.db.showOnLogin and true or false)
    end
end

function ns.ToggleMainFrame()
    if not frame then
        frame = CreateMainFrame()
    end
    if frame:IsShown() then
        frame:Hide()
    else
        ApplyPosition(frame)
        ns.RefreshMainFrame()
        frame:Show()
    end
end
