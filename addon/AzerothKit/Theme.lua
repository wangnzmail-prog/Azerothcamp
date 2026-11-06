-- Theme.lua · 主题令牌 + 控件工厂
-- 这是"所有模块长得一样"的唯一来源：颜色、间距、面板、按钮、复选框都从这里出。
local ADDON, ns = ...

local T = {}
ns.Theme = T

T.color = {
    bg     = { 0.05, 0.05, 0.06, 0.94 },
    bg2    = { 0.10, 0.10, 0.12, 0.90 },
    border = { 0.28, 0.28, 0.32, 1.00 },
    accent = { 0.40, 0.78, 1.00, 1.00 },
    text   = { 0.92, 0.92, 0.94, 1.00 },
    dim    = { 0.55, 0.55, 0.60, 1.00 },
    ok     = { 0.30, 0.80, 0.35, 1.00 },
    bad    = { 1.00, 0.30, 0.30, 1.00 },
}

T.spacing = 8
T.padding = 16

local WHITE = "Interface\\Buttons\\WHITE8X8"

function T:ApplyBackdrop(frame, alpha)
    local c = self.color
    frame:SetBackdrop({
        bgFile = WHITE,
        edgeFile = WHITE,
        edgeSize = 1,
    })
    frame:SetBackdropColor(c.bg[1], c.bg[2], c.bg[3], alpha or c.bg[4])
    frame:SetBackdropBorderColor(c.border[1], c.border[2], c.border[3], c.border[4])
end

function T:CreatePanel(name, parent, width, height)
    local f = CreateFrame("Frame", name, parent or UIParent, "BackdropTemplate")
    f:SetSize(width or 400, height or 300)
    self:ApplyBackdrop(f)
    return f
end

function T:CreateTitle(parent, text)
    local fs = parent:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    fs:SetTextColor(unpack(self.color.accent))
    fs:SetText(text or "")
    return fs
end

function T:CreateText(parent, size, dim)
    local fs = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    fs:SetJustifyH("LEFT")
    if dim then
        fs:SetTextColor(unpack(self.color.dim))
    else
        fs:SetTextColor(unpack(self.color.text))
    end
    if size then
        local font, _, flags = fs:GetFont()
        if font then fs:SetFont(font, size, flags) end
    end
    return fs
end

function T:CreateButton(parent, text, width, height)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(width or 100, height or 22)
    b:SetText(text or "")
    return b
end

function T:CreateCheckbox(parent, label)
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetSize(22, 22)
    cb.label = cb:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    cb.label:SetPoint("LEFT", cb, "RIGHT", 4, 0)
    cb.label:SetText(label or "")
    cb.label:SetTextColor(unpack(self.color.text))
    return cb
end

function T:CreateDivider(parent, y)
    local d = parent:CreateTexture(nil, "ARTWORK")
    d:SetColorTexture(unpack(self.color.border))
    d:SetHeight(1)
    d:SetPoint("TOPLEFT", self.padding, y)
    d:SetPoint("TOPRIGHT", -self.padding, y)
    return d
end
