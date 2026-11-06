-- Core.lua · 数据库 / 事件总线 / 模块注册器 / 设置 schema / Profile 部署
local ADDON, ns = ...
local P = ns.Platform

local C = {}
ns.Core = C

-- Lua 层版本号：/reload 就能反映真实代码版本（TOC 的 ## Version 要重启客户端才更新）
ns.VERSION = "0.8.1"

-- ---------- 数据库 ----------
local DB_DEFAULTS = {
    schema = 2,
    showOnLogin = true,
    modules = {},
    integrations = {},
    pos = nil,
    appliedProfile = 0,
    exportText = nil,
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

    -- schema 1: modules[name] = true/false
    -- schema 2: modules[name] = { enabled = true/false, <settingKey> = value }
    if db.schema < 2 then
        local mods = db.modules or {}
        for name, v in pairs(mods) do
            if type(v) ~= "table" then
                mods[name] = { enabled = v and true or false }
            end
        end
        db.modules = mods
        db.schema = 2
    end
end

local function Store(name)
    local store = ns.db and ns.db.modules[name]
    if type(store) ~= "table" then
        store = {}
        if ns.db then ns.db.modules[name] = store end
    end
    return store
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
    def.settings = def.settings or {}
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
    local store = ns.db and ns.db.modules and ns.db.modules[name]
    local saved = type(store) == "table" and store.enabled or nil
    if saved == nil then return m.defaultEnabled end
    return saved and true or false
end

function C:SetModuleEnabled(name, enabled)
    local m = modules[name]
    if not m or not ns.db then return end
    Store(name).enabled = enabled and true or false

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

-- ---------- 整合层：接管/适配第三方插件 ----------
-- 一个第三方插件一个文件：Integrations\<Addon>.lua
-- 生命周期：登录时若对方已加载 → OnAddonLoaded(def)；改设置 → ApplySetting(def, key, value)
local integrations, iorder = {}, {}

function C:RegisterIntegration(name, def)
    if integrations[name] then
        error("duplicate integration: " .. tostring(name))
    end
    def = def or {}
    def.name = name
    def.label = def.label or name
    def.addon = def.addon or name
    def.settings = def.settings or {}
    integrations[name] = def
    iorder[#iorder + 1] = name
    return def
end

function C:GetIntegrations()
    return iorder, integrations
end

function C:IsAddonLoaded(name)
    if C_AddOns and C_AddOns.IsAddOnLoaded then
        return C_AddOns.IsAddOnLoaded(name) and true or false
    end
    if type(IsAddOnLoaded) == "function" then
        return IsAddOnLoaded(name) and true or false
    end
    return false
end

function C:GetAddonVersion(name)
    if C_AddOns and C_AddOns.GetAddOnMetadata then
        return C_AddOns.GetAddOnMetadata(name, "Version")
    end
    if type(GetAddOnMetadata) == "function" then
        return GetAddOnMetadata(name, "Version")
    end
end

local function IStore(name)
    if not ns.db then return {} end
    ns.db.integrations = ns.db.integrations or {}
    local store = ns.db.integrations[name]
    if type(store) ~= "table" then
        store = {}
        ns.db.integrations[name] = store
    end
    return store
end

function C:GetIntegrationSetting(name, key)
    local store = ns.db and ns.db.integrations and ns.db.integrations[name]
    if type(store) == "table" and store[key] ~= nil then
        return store[key]
    end
    local def = integrations[name]
    if def then
        for _, s in ipairs(def.settings) do
            if s.key == key then return s.default end
        end
    end
end

function C:SetIntegrationSetting(name, key, value)
    if not ns.db then return end
    IStore(name)[key] = value
    local def = integrations[name]
    if def and def.ApplySetting then
        local ok, err = pcall(def.ApplySetting, def, key, value)
        if not ok then
            print("|cffff4040[AzerothKit]|r " .. name .. "." .. key .. ": " .. tostring(err))
        end
    end
end

function C:ApplyIntegrations()
    for _, name in ipairs(iorder) do
        local def = integrations[name]
        if self:IsAddonLoaded(def.addon) and def.OnAddonLoaded then
            local ok, err = pcall(def.OnAddonLoaded, def)
            if not ok then
                print("|cffff4040[AzerothKit]|r integration " .. name .. ": " .. tostring(err))
            end
        end
    end
end

-- ---------- 设置 schema ----------
-- 模块用 settings = { { key, type, default, min, max, step, label, enum } } 声明可调项，
-- Agent 与游戏内面板都以它为唯一事实来源。

function C:FindSetting(moduleName, key)
    local m = modules[moduleName]
    if not m then return nil end
    for _, s in ipairs(m.settings) do
        if s.key == key then return s end
    end
    return nil
end

function C:GetSetting(moduleName, key)
    local store = ns.db and ns.db.modules and ns.db.modules[moduleName]
    if type(store) == "table" and store[key] ~= nil then
        return store[key]
    end
    local s = self:FindSetting(moduleName, key)
    return s and s.default
end

function C:SetSetting(moduleName, key, value)
    if not ns.db then return end
    Store(moduleName)[key] = value
    local m = modules[moduleName]
    if m and m.OnSettingChanged then
        local ok, err = pcall(m.OnSettingChanged, m, key, value)
        if not ok then
            print("|cffff4040[AzerothKit]|r " .. moduleName .. "." .. key .. ": " .. tostring(err))
        end
    end
end

-- ---------- Profile：Agent 的写入口 ----------
-- 文件：Profile.lua（固定文件名，永远在 TOC 里）
-- 结构：AzerothKitProfile = { version = N, modules = { [name] = { enabled=..., <key>=... } } }
-- 语义：version 变了才覆盖，避免每次登录冲掉玩家的手动改动。

function C:ApplyProfile(profile)
    if type(profile) ~= "table" then return 0 end
    local count = 0

    local function merge(section, target)
        if type(section) ~= "table" then return end
        for name, values in pairs(section) do
            if type(values) == "table" then
                local store = target(name)
                for k, v in pairs(values) do
                    if type(v) ~= "table" and type(v) ~= "function" then
                        store[k] = v
                        count = count + 1
                    end
                end
            end
        end
    end

    merge(profile.modules, Store)
    merge(profile.integrations, IStore)

    ns.db.appliedProfile = tonumber(profile.version) or 0
    return count
end

function C:SyncProfile()
    if not ns.db then return 0 end
    local profile = AzerothKitProfile
    if type(profile) ~= "table" then return 0 end
    local incoming = tonumber(profile.version) or 0
    if incoming <= (tonumber(ns.db.appliedProfile) or 0) then return 0 end
    local n = self:ApplyProfile(profile)
    print(string.format("|cff69ccf0[AzerothKit]|r 已应用配置档案 v%d（%d 项）", incoming, n))
    return n
end

-- ---------- 导出（给 Agent 读） ----------
local function Serialize(value, indent)
    indent = indent or ""
    local t = type(value)
    if t == "string" then
        return string.format("%q", value)
    elseif t == "number" or t == "boolean" then
        return tostring(value)
    elseif t == "table" then
        local inner = indent .. "    "
        local parts = {}
        for k, v in pairs(value) do
            local key
            if type(k) == "string" and k:match("^[%a_][%w_]*$") then
                key = k
            else
                key = "[" .. Serialize(k) .. "]"
            end
            parts[#parts + 1] = inner .. key .. " = " .. Serialize(v, inner)
        end
        if #parts == 0 then return "{}" end
        return "{\n" .. table.concat(parts, ",\n") .. "\n" .. indent .. "}"
    end
    return "nil"
end
C.Serialize = Serialize

function C:ExportProfile()
    local out = { version = (tonumber(ns.db.appliedProfile) or 0) + 1, modules = {}, integrations = {} }

    local function copy(section)
        local result = {}
        if type(section) ~= "table" then return result end
        for name, store in pairs(section) do
            if type(store) == "table" then
                local row = {}
                for k, v in pairs(store) do
                    if type(v) ~= "table" and type(v) ~= "function" then
                        row[k] = v
                    end
                end
                result[name] = row
            end
        end
        return result
    end

    out.modules = copy(ns.db.modules)
    out.integrations = copy(ns.db.integrations)
    return out
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

        -- 版本戳：优先用 Lua 常量（/reload 即准），TOC 元数据只作兜底
        ns.db.addonVersion = ns.VERSION
        if C_AddOns and C_AddOns.GetAddOnMetadata then
            ns.db.addonTocVersion = C_AddOns.GetAddOnMetadata(ADDON, "Version") or "?"
        elseif type(GetAddOnMetadata) == "function" then
            ns.db.addonTocVersion = GetAddOnMetadata(ADDON, "Version") or "?"
        end
        self:UnregisterEvent("ADDON_LOADED")

    elseif event == "PLAYER_LOGIN" then
        C:SyncProfile()
        C:ApplyModules()
        C:ApplyIntegrations()
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
