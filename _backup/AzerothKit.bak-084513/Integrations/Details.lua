-- Integrations\Details.lua · 第一个整合适配器
-- 目标：把 Details 的窗口纳入我们的缩放体系，并在 /ak integrations 里报告它的状态。
-- 原则：只调用 Details 自己公开的 API（GetNumWindows / GetWindow），不做侵入式改表。
local ADDON, ns = ...
local C = ns.Core

local M = C:RegisterIntegration("Details", {
    addon = "Details",
    label = "Details! 统计",
    settings = {
        { key = "scale", type = "number", default = 1.0, min = 0.7, max = 1.5, step = 0.05, label = "窗口缩放" },
    },
})

local function DetailsAPI()
    return _G.Details
end

local function ApplyScale()
    local D = DetailsAPI()
    if not D or type(D.GetNumWindows) ~= "function" or type(D.GetWindow) ~= "function" then
        return 0
    end

    local scale = tonumber(C:GetIntegrationSetting("Details", "scale")) or 1
    local count = tonumber(D:GetNumWindows()) or 0
    local applied = 0

    for i = 1, count do
        local w = D:GetWindow(i)
        if w and w.SetScale then
            local ok = pcall(w.SetScale, w, scale)
            if ok then applied = applied + 1 end
        end
    end
    return applied
end

function M:OnAddonLoaded()
    ApplyScale()
end

function M:ApplySetting(key)
    if key == "scale" then
        ApplyScale()
    end
end

function M:Snapshot()
    local D = DetailsAPI()
    if not D then return "未就绪" end
    local parts = {}
    parts[#parts + 1] = "版本 " .. tostring(C:GetAddonVersion("Details") or "?")
    if type(D.GetNumWindows) == "function" then
        parts[#parts + 1] = "窗口 " .. tostring(D:GetNumWindows() or 0)
    end
    if type(D.GetSkin) == "function" then
        local ok, skin = pcall(D.GetSkin, D)
        if ok and skin then parts[#parts + 1] = "皮肤 " .. tostring(skin) end
    end
    parts[#parts + 1] = "缩放 " .. tostring(C:GetIntegrationSetting("Details", "scale"))
    return table.concat(parts, " · ")
end
