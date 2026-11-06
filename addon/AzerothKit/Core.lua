-- Core.lua · 生命周期与 SavedVariables
local ADDON, ns = ...
local P = ns.Platform

local DB_DEFAULTS = {
    schema = 1,
    showOnLogin = true,
    pos = nil,
}

local function CopyDefaults(target, defaults)
    for k, v in pairs(defaults) do
        if type(v) == "table" then
            if type(target[k]) ~= "table" then
                target[k] = {}
            end
            CopyDefaults(target[k], v)
        elseif target[k] == nil then
            target[k] = v
        end
    end
end

local function Migrate(db)
    db.schema = db.schema or 0
    if db.schema < 1 then
        -- 未来加字段时在这里写迁移，例：
        -- db.foo = db.foo or true
        db.schema = 1
    end
end

local boot = CreateFrame("Frame", "AzerothKitBoot")
boot:RegisterEvent("ADDON_LOADED")
boot:RegisterEvent("PLAYER_LOGIN")
boot:RegisterEvent("PLAYER_ENTERING_WORLD")

boot:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == ADDON then
        AzerothKitDB = AzerothKitDB or {}
        Migrate(AzerothKitDB)
        CopyDefaults(AzerothKitDB, DB_DEFAULTS)
        ns.db = AzerothKitDB
        self:UnregisterEvent("ADDON_LOADED")

    elseif event == "PLAYER_LOGIN" then
        if ns.OnLogin then
            ns.OnLogin()
        end

    elseif event == "PLAYER_ENTERING_WORLD" then
        if ns.OnEnterWorld then
            ns.OnEnterWorld()
        end
    end
end)

ns.CopyDefaults = CopyDefaults

-- 全局入口：TOC 的 ## AddonCompartmentFunc 会调用它
function ns.Toggle()
    if ns.ToggleMainFrame then
        ns.ToggleMainFrame()
    end
end

AzerothKit_Toggle = ns.Toggle
