-- Core.lua · 生命周期、数据库、事件总线、模块注册器
local ADDON, ns = ...
local P = ns.Platform

local C = {}
ns.Core = C

-- ---------- 数据库 ----------
local DB_DEFAULTS = {
    schema = 1,
    showOnLogin = true,
    modules = {},
    pos = nil,
}

local function CopyDefaults(target, defaults)
    for k, v in pairs(defaults) do
        if type(v) == "table" then
            if type(target[k]) ~= "table" then target[k] = {} end
            CopyDefaults(target[k], v)
        elseif target[k] == nil then
            target[k] = v
        end
    end
end

local function Migrate(db)
    db.schema = db.schema or 0
    if db.schema < 1 then
        db.schema = 1
    end
end

-- ---------- 模块注册器 ----------
local modules, order = {}, {}

function C:RegisterModule(name, def)
    if modules[name] then
        error("duplicate module: " .. tostring(name))
    end
    def = def or {}
    def.name = name
    def.label = def.label or name
    def.defaultEnabled = def.defaultEnabled ~= false
    def.flavors = def.flavors or { retail = true, forever = true }
    modules[name] = def
    order[#order + 1] = name
    return def
end

function C:GetModules()
    return order, modules
end

function C:GetModule(name)
    return modules[name]
end

function C:IsModuleSupported(name)
    local m = modules[name]
    if not m then return false end
    return m.flavors[P.flavor] == true
end

function C:IsModuleEnabled(name)
    local m = modules[name]
    if not m then return false end
    if not self:IsModuleSupported(name) then return false end
    local saved = ns.db and ns.db.modules and ns.db.modules[name]
    if saved == nil then return m.defaultEnabled end
    return saved and true or false
end

function C:SetModuleEnabled(name, enabled)
    local m = modules[name]
    if not m or not ns.db then return end
    ns.db.modules[name] = enabled and true or false

    if not self:IsModuleSupported(name) then return end
    local handler = enabled and m.OnEnable or m.OnDisable
    if handler then
        local ok, err = pcall(handler, m)
        if not ok then
            print("|cffff4040[AzerothKit]|r module " .. name .. ": " .. tostring(err))
        end
    end
end

function C:ApplyModules()
    for _, name in ipairs(order) do
        local m = modules[name]
        if self:IsModuleEnabled(name) and m.OnEnable then
            local ok, err = pcall(m.OnEnable, m)
            if not ok then
                print("|cffff4040[AzerothKit]|r module " .. name .. ": " .. tostring(err))
            end
        end
    end
end

-- ---------- 事件总线 ----------
local listeners = {}
local bus = CreateFrame("Frame")

bus:SetScript("OnEvent", function(_, event, ...)
    local list = listeners[event]
    if not list then return end
    for fn in pairs(list) do
        xpcall(fn, geterrorhandler(), event, ...)
    end
end)

function C:On(event, fn)
    if not listeners[event] then
        listeners[event] = {}
        pcall(bus.RegisterEvent, bus, event)
    end
    listeners[event][fn] = true
end

function C:Off(event, fn)
    local list = listeners[event]
    if not list then return end
    list[fn] = nil
    if not next(list) then
        listeners[event] = nil
        bus:UnregisterEvent(event)
    end
end

-- ---------- 启动 ----------
local boot = CreateFrame("Frame", "AzerothKitBoot")
boot:RegisterEvent("ADDON_LOADED")
boot:RegisterEvent("PLAYER_LOGIN")

boot:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == ADDON then
        AzerothKitDB = AzerothKitDB or {}
        Migrate(AzerothKitDB)
        CopyDefaults(AzerothKitDB, DB_DEFAULTS)
        ns.db = AzerothKitDB
        self:UnregisterEvent("ADDON_LOADED")

    elseif event == "PLAYER_LOGIN" then
        C:ApplyModules()
        if ns.db.showOnLogin and ns.Diagnostics then
            ns.Diagnostics.PrintVersion()
        end
    end
end)

-- 全局入口：TOC 的 ## AddonCompartmentFunc
function ns.Toggle()
    if ns.ToggleMainFrame then ns.ToggleMainFrame() end
end

AzerothKit_Toggle = ns.Toggle
