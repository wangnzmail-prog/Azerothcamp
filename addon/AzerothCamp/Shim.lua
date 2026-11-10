-- Shim.lua · 独立运行用的迷你内核（与 AzerothKit 的 ns.Core / ns.Theme 同名接口）
-- 若已安装 AzerothKit：本插件让位，注册接口变成空壳，避免出现两个面板。
local ADDON, ns = ...

ns.VERSION = "1.0.2"
ns.Platform = {
    locale = GetLocale and GetLocale() or "enUS",
    flavor = "forever",
    IsSecret = function(v)
        return type(issecretvalue) == "function" and issecretvalue(v) or false
    end,
}

-- ---------- 迷你 DB ----------
local DEFAULTS = { schema = 1, modules = {}, campSlots = 0 }
local function CopyDefaults(t, d)
    for k, v in pairs(d) do
        if type(v) == "table" then
            if type(t[k]) ~= "table" then t[k] = {} end
            CopyDefaults(t[k], v)
        elseif t[k] == nil then
            t[k] = v
        end
    end
end

-- ---------- 迷你事件总线 ----------
local listeners = {}
local bus = CreateFrame("Frame")
bus:SetScript("OnEvent", function(_, event, ...)
    local list = listeners[event]
    if not list then return end
    for fn in pairs(list) do xpcall(fn, geterrorhandler(), event, ...) end
end)

local function On(event, fn)
    if not listeners[event] then
        listeners[event] = {}
        pcall(bus.RegisterEvent, bus, event)
    end
    listeners[event][fn] = true
end

local function Off(event, fn)
    local list = listeners[event]
    if not list then return end
    list[fn] = nil
    if not next(list) then
        listeners[event] = nil
        bus:UnregisterEvent(event)
    end
end

-- ---------- 迷你模块表 ----------
local modules, order = {}, {}

local C = { On = On, Off = Off }
ns.Core = C

function C:RegisterModule(name, def)
    def = def or {}
    def.name = name
    def.settings = def.settings or {}
    modules[name] = def
    order[#order + 1] = name
    return def
end

function C:GetModule(name) return modules[name] end
function C:GetModules() return order, modules end

local function Store(name)
    ns.db.modules[name] = ns.db.modules[name] or {}
    return ns.db.modules[name]
end

function C:GetSetting(name, key)
    local s = Store(name)
    if s[key] ~= nil then return s[key] end
    local def = modules[name]
    for _, item in ipairs(def and def.settings or {}) do
        if item.key == key then return item.default end
    end
    return nil
end

function C:SetSetting(name, key, value)
    Store(name)[key] = value
    local def = modules[name]
    if def and def.OnSettingChanged then pcall(def.OnSettingChanged, def, key, value) end
end

-- ---------- 迷你主题 ----------
local WHITE = "Interface\\Buttons\\WHITE8X8"
local T = {}
ns.Theme = T

T.color = { bg = { 0.05, 0.05, 0.06, 0.94 }, border = { 0.28, 0.28, 0.32, 1 },
            text = { 0.92, 0.92, 0.94, 1 }, dim = { 0.55, 0.55, 0.60, 1 }, accent = { 0.4, 0.78, 1, 1 } }

function T:CreatePanel(name, parent, w, h)
    local f = CreateFrame("Frame", name, parent or UIParent, "BackdropTemplate")
    f:SetSize(w or 230, h or 200)
    f:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
    f:SetBackdropColor(0.05, 0.05, 0.06, 0.94)
    f:SetBackdropBorderColor(0.28, 0.28, 0.32, 1)
    return f
end

function T:CreateText(parent, size, dim)
    local fs = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    fs:SetJustifyH("LEFT")
    local c = dim and self.color.dim or self.color.text
    fs:SetTextColor(c[1], c[2], c[3])
    if size then
        local font, _, flags = fs:GetFont()
        if font then fs:SetFont(font, size, flags) end
    end
    return fs
end

function T:RestorePosition(frame, point, relPoint, x, y)
    frame:ClearAllPoints()
    frame:SetPoint(point or "TOPLEFT", UIParent, relPoint or "TOPLEFT", x or 0, y or 0)
end

function T:MakeMovable(frame, onDragStop)
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self)
        if self.akLocked then return end
        self:StartMoving()
    end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relPoint, x, y = self:GetPoint()
        if onDragStop then onDragStop(point, relPoint, x, y) end
    end)
end

-- ---------- 启动 ----------
local boot = CreateFrame("Frame")
boot:RegisterEvent("ADDON_LOADED")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == ADDON then
        AzerothCampDB = AzerothCampDB or {}
        CopyDefaults(AzerothCampDB, DEFAULTS)
        ns.db = AzerothCampDB
        -- 报错记录（只记本插件的）
        if type(seterrorhandler) == "function" then
            local prev = geterrorhandler and geterrorhandler()
            seterrorhandler(function(msg)
                local text = tostring(msg)
                if text:find("AzerothCamp", 1, true) and ns.db then
                    ns.db.errors = ns.db.errors or {}
                    table.insert(ns.db.errors, 1, date("%m-%d %H:%M:%S") .. "  " .. text:sub(1, 500))
                    for i = 21, #ns.db.errors do ns.db.errors[i] = nil end
                end
                if prev then prev(msg) end
            end)
        end
        self:UnregisterEvent("ADDON_LOADED")
    elseif event == "PLAYER_LOGIN" then
        for _, name in ipairs(order) do
            local def = modules[name]
            if def.OnEnable then pcall(def.OnEnable, def) end
        end
    end
end)
