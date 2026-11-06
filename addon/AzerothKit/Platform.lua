-- Platform.lua · 版本与能力探测（正式服 / 无限 / 怀旧服共用）
-- 所有"按版本分支"的判断都应该只出现在这个文件里。
local ADDON, ns = ...

local P = {}
ns.Platform = P

local version, build, buildDate, toc = GetBuildInfo()
P.version = tostring(version or "0.0.0")
P.build   = tonumber(build) or 0
P.buildDate = buildDate
P.toc     = tonumber(toc) or 0
P.locale  = GetLocale and GetLocale() or "enUS"

local PROJECT_MAINLINE = WOW_PROJECT_MAINLINE or 1
local PROJECT_CLASSIC  = WOW_PROJECT_CLASSIC or 2
local PROJECT_CAMELOT  = WOW_PROJECT_CAMELOT   -- 只有无限客户端才定义，值为 18

ns.FlavorLabel = {
    retail  = "正式服 / Mainline",
    forever = "无限 / Forever (Camelot)",
    classic = "怀旧服 / Classic",
    unknown = "未知客户端",
}

-- 判定顺序很重要：先认命名的 Camelot 常量，再兜底 Interface 区间。
-- 早期测试 build 曾把无限报成 WOW_PROJECT_ID = 1，所以不能只信数字。
function P.GetFlavor()
    local id = WOW_PROJECT_ID
    if PROJECT_CAMELOT and id == PROJECT_CAMELOT then
        return "forever"
    end
    if P.toc >= 16000 and P.toc < 20000 then
        return "forever"
    end
    if id == PROJECT_MAINLINE then
        return "retail"
    end
    if id == PROJECT_CLASSIC then
        return "classic"
    end
    return "unknown"
end

P.flavor = P.GetFlavor()

function P.GetFlavorLabel()
    return ns.FlavorLabel[P.flavor] or ns.FlavorLabel.unknown
end

-- 能力探测：直接问客户端"这个 API 在不在"，不要用版本号猜。
-- 例：P.HasAPI("C_DamageMeter.GetAvailableCombatSessions")
function P.HasAPI(path)
    local node = _G
    for key in string.gmatch(path, "[^%.]+") do
        if type(node) ~= "table" then
            return false
        end
        node = node[key]
        if node == nil then
            return false
        end
    end
    return true
end

-- 机密值（secret value）辅助：任何可能拿到 secret 的地方都从这里过一遍。
function P.IsSecret(value)
    if type(issecretvalue) ~= "function" then
        return false
    end
    return issecretvalue(value)
end

function P.SafeNumber(value, fallback)
    if P.IsSecret(value) then
        return fallback
    end
    local n = tonumber(value)
    if n == nil then
        return fallback
    end
    return n
end

-- 玩家名：无限上 DBM 会特意改用 GetUnitName，这里做同样的兜底。
function P.PlayerName()
    if P.flavor == "forever" and type(GetUnitName) == "function" then
        local name = GetUnitName("player")
        if name and not P.IsSecret(name) then
            return name
        end
    end
    if type(UnitName) == "function" then
        local name = UnitName("player")
        if name and not P.IsSecret(name) then
            return name
        end
    end
    return UNKNOWN or "Unknown"
end

-- 12.0 起注册 CLEU 会直接报错；无限同属 Mainline UI 家族，按不可用处理。
-- 这里只是估计值，真正的结论要进游戏实测（见 docs/06 的验证清单）。
function P.CanUseCombatLog()
    if P.flavor == "forever" then
        return false
    end
    return P.toc < 120000
end

-- 能力矩阵：给 /ak probe 与主窗口用
function P.GetCapabilities()
    return {
        { label = "机密值 issecretvalue", ok = type(issecretvalue) == "function" },
        { label = "C_Secrets 谓词", ok = P.HasAPI("C_Secrets.ShouldAurasBeSecret") },
        { label = "C_RestrictedActions", ok = P.HasAPI("C_RestrictedActions.IsAddOnRestrictionActive") },
        { label = "C_DamageMeter 官方统计", ok = P.HasAPI("C_DamageMeter.GetAvailableCombatSessions") },
        { label = "冷却时长对象", ok = P.HasAPI("C_Spell.GetSpellCooldownDuration") },
        { label = "Settings 设置面板", ok = P.HasAPI("Settings.RegisterAddOnCategory") },
        { label = "AddonCompartment 抽屉", ok = P.HasAPI("AddonCompartmentFrame") },
        { label = "战斗日志可注册(估计)", ok = P.CanUseCombatLog() },
    }
end
