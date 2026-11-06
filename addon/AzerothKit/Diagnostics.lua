-- Diagnostics.lua · /ak 命令、探针、配置导出、整合状态
local ADDON, ns = ...
local P = ns.Platform
local C = ns.Core

local D = {}
ns.Diagnostics = D

local PREFIX = "|cff69ccf0[AzerothKit]|r "

local function out(msg)
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage(PREFIX .. tostring(msg))
    end
end

function D.PrintVersion()
    local order = C:GetModules()
    out(string.format("v0.4.0 · %s · build %s · Interface %d · 模块 %d 个",
        P.GetFlavorLabel(), tostring(P.build), P.toc, #order))
end

function D.PrintModules()
    local order, modules = C:GetModules()
    out(string.format("模块 (%d):", #order))
    for _, name in ipairs(order) do
        local m = modules[name]
        local state = C:IsModuleEnabled(name) and "|cff4dcc59启用|r" or "|cff808080关闭|r"
        local note = C:IsModuleSupported(name) and "" or " |cffff4040(当前客户端不支持)|r"
        out(string.format("  %-12s %s%s", name, state, note))
    end
end

function D.PrintIntegrations()
    local order, list = C:GetIntegrations()
    out(string.format("整合 (%d):", #order))
    for _, name in ipairs(order) do
        local def = list[name]
        local loaded = C:IsAddonLoaded(def.addon)
        local state = loaded and "|cff4dcc59已检测|r" or "|cff808080未安装|r"
        local detail = ""
        if loaded and def.Snapshot then
            local ok, text = pcall(def.Snapshot, def)
            if ok and text then
                detail = "  " .. tostring(text)
            end
        end
        out(string.format("  %-10s %s%s", name, state, detail))
    end
end

function D.PrintSchema()
    local order, modules = C:GetModules()
    out("可调项 schema:")
    for _, name in ipairs(order) do
        local m = modules[name]
        for _, s in ipairs(m.settings) do
            local range = ""
            if s.min or s.max then
                range = string.format("  [%s..%s]", tostring(s.min), tostring(s.max))
            end
            out(string.format("  %s.%s  %s  default=%s%s",
                name, s.key, tostring(s.type or "any"), tostring(s.default), range))
        end
    end

    local iorder, list = C:GetIntegrations()
    for _, name in ipairs(iorder) do
        local def = list[name]
        for _, s in ipairs(def.settings) do
            out(string.format("  %s.%s  %s  default=%s  [integration]",
                name, s.key, tostring(s.type or "any"), tostring(s.default)))
        end
    end
end

function D.ExportProfile()
    if not ns.db then
        out("数据库尚未加载")
        return
    end
    local profile = C:ExportProfile()
    local text = C.Serialize(profile)
    ns.db.exportText = text
    out(string.format("已导出配置（%d 字节）到 SavedVariables.exportText", #text))
    out("下一步：/reload 落盘 → Agent 读取 WTF\\...\\SavedVariables\\AzerothKit.lua")
end

function D.ToggleModule(name)
    if not name or name == "" then
        out("用法: /ak toggle <模块名>")
        return
    end
    local order = C:GetModules()
    local target
    for _, n in ipairs(order) do
        if string.lower(n) == string.lower(name) then
            target = n
            break
        end
    end
    if not target then
        out("没有这个模块: " .. name)
        return
    end
    local now = not C:IsModuleEnabled(target)
    C:SetModuleEnabled(target, now)
    out(target .. (now and " 已启用" or " 已关闭"))
end

function D.PrintProbe()
    D.PrintVersion()
    out(string.format("产品 ID: %s (CAMELOT=%s) · 玩家: %s",
        tostring(WOW_PROJECT_ID), tostring(WOW_PROJECT_CAMELOT), tostring(P.PlayerName())))

    for _, cap in ipairs(P.GetCapabilities()) do
        local mark = cap.ok and "|cff4dcc59OK|r" or "|cffff4040--|r"
        out(string.format("  [%s] %s", mark, cap.label))
    end
    D.PrintModules()
    D.PrintIntegrations()
    out(string.format("已应用配置档案版本: %s", tostring(ns.db and ns.db.appliedProfile or 0)))
end

-- 机密值体检：只打印"是否机密"和"能否做算术"，绝不打印 secret 本身。
function D.PrintSecret()
    local health = UnitHealth("player")
    local isSecret = P.IsSecret(health)
    out(string.format("UnitHealth(player): type=%s, secret=%s",
        type(health), tostring(isSecret)))

    local okArith = pcall(function()
        return health + 1
    end)
    out(string.format("对它做算术: %s", okArith and "允许" or "被拒绝(符合预期)"))

    if C_Secrets and C_Secrets.ShouldAurasBeSecret then
        out(string.format("光环是否被隐藏: %s", tostring(C_Secrets.ShouldAurasBeSecret())))
    end
    if C_RestrictedActions and C_RestrictedActions.IsAddOnRestrictionActive then
        out(string.format("战斗限制(0=Combat): %s",
            tostring(C_RestrictedActions.IsAddOnRestrictionActive(0))))
    end
end

local function PrintHelp()
    out("命令:")
    out("  /ak              开关面板")
    out("  /ak probe        能力矩阵 + 模块 + 整合 + 档案版本")
    out("  /ak modules      模块列表")
    out("  /ak integrations 第三方插件整合状态")
    out("  /ak schema       可调项 schema（Agent 与面板共用）")
    out("  /ak export       导出当前配置到 SavedVariables，供 Agent 读取")
    out("  /ak toggle <名>  开关某个模块")
    out("  /ak secret       机密值体检（战斗中跑一次）")
end

local function Handle(msg)
    local cmd, rest = (msg or ""):match("^%s*(%S*)%s*(.-)%s*$")
    cmd = string.lower(cmd or "")

    if cmd == "" or cmd == "ui" then
        ns.ToggleMainFrame()
    elseif cmd == "version" then
        D.PrintVersion()
    elseif cmd == "probe" then
        D.PrintProbe()
    elseif cmd == "modules" then
        D.PrintModules()
    elseif cmd == "integrations" then
        D.PrintIntegrations()
    elseif cmd == "schema" then
        D.PrintSchema()
    elseif cmd == "export" then
        D.ExportProfile()
    elseif cmd == "toggle" then
        D.ToggleModule(rest)
    elseif cmd == "secret" then
        D.PrintSecret()
    else
        PrintHelp()
    end
end

SLASH_AZEROTHKIT1 = "/ak"
SLASH_AZEROTHKIT2 = "/azerothkit"
SlashCmdList["AZEROTHKIT"] = Handle
