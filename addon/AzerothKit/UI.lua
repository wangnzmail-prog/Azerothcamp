-- UI.lua · 纯展示层：一个可拖动的小面板，显示版本与能力矩阵
local ADDON, ns = ...
local P = ns.Platform

local isCN = (P.locale == "zhCN" or P.locale == "zhTW")
local function T(zh, en)
    if isCN then return zh end
    return en
end

local frame

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
    local f = CreateFrame("Frame", "AzerothKitFrame", UIParent, "BackdropTemplate")
    f:SetSize(460, 340)
    f:SetFrameStrata("DIALOG")
    f:SetToplevel(true)
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self)
        self:StartMoving()
    end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relPoint, x, y = self:GetPoint()
        if ns.db then
            ns.db.pos = { point = point, relPoint = relPoint, x = x, y = y }
        end
    end)

    f:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true,
        tileSize = 32,
        edgeSize = 32,
        insets = { left = 8, right = 8, top = 8, bottom = 8 },
    })

    local title = f:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 20, -16)
    title:SetText("AzerothKit 0.1.0")

    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -4, -4)

    local header = f:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    header:SetPoint("TOPLEFT", 22, -44)
    header:SetPoint("TOPRIGHT", -22, -44)
    header:SetJustifyH("LEFT")
    f.header = header

    f.caps = {}
    for i = 1, 8 do
        local fs = f:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        fs:SetPoint("TOPLEFT", 28, -74 - (i - 1) * 18)
        fs:SetJustifyH("LEFT")
        f.caps[i] = fs
    end

    local hint = f:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", 22, -232)
    hint:SetPoint("TOPRIGHT", -22, -232)
    hint:SetJustifyH("LEFT")
    hint:SetText(T(
        "战斗数值在 12.x 是“机密值”：可显示、不可计算。本面板只显示能力探测结果。",
        "Combat numbers are secret values in 12.x: displayable, not computable."))
    f.hint = hint

    local probeBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    probeBtn:SetSize(120, 24)
    probeBtn:SetPoint("BOTTOMLEFT", 20, 18)
    probeBtn:SetText(T("打印诊断", "Print probe"))
    probeBtn:SetScript("OnClick", function()
        if ns.Diagnostics and ns.Diagnostics.PrintProbe then
            ns.Diagnostics.PrintProbe()
        end
    end)

    local hideBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    hideBtn:SetSize(80, 24)
    hideBtn:SetPoint("LEFT", probeBtn, "RIGHT", 8, 0)
    hideBtn:SetText(T("关闭", "Close"))
    hideBtn:SetScript("OnClick", function()
        f:Hide()
    end)

    local cb = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
    cb:SetSize(24, 24)
    cb:SetPoint("BOTTOMRIGHT", -20, 18)
    local cbLabel = cb:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    cbLabel:SetPoint("LEFT", cb, "RIGHT", 4, 0)
    cbLabel:SetText(T("登录时提示", "Print on login"))
    cb:SetScript("OnClick", function(self)
        if ns.db then
            ns.db.showOnLogin = self:GetChecked() and true or false
        end
    end)
    f.showOnLogin = cb

    return f
end

function ns.RefreshMainFrame()
    if not frame then return end
    frame.header:SetText(string.format("%s  |cff808080build %s · Interface %d|r",
        P.GetFlavorLabel(), P.version, P.toc))

    local caps = P.GetCapabilities()
    for i, fs in ipairs(frame.caps) do
        local cap = caps[i]
        if cap then
            local mark = cap.ok and "|cff40c040[OK]|r" or "|cffff4040[--]|r"
            fs:SetText(mark .. " " .. cap.label)
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

function ns.OnLogin()
    if ns.db and ns.db.showOnLogin and ns.Diagnostics and ns.Diagnostics.PrintVersion then
        ns.Diagnostics.PrintVersion()
    end
end
