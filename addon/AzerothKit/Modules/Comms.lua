-- Modules\Comms.lua · 小队露营同步：告诉队友"我能放什么、我还要冷却多久"
-- 只对装了 AzerothKit 的队友生效；没装的显示"未知"。
local ADDON, ns = ...
local C = ns.Core

local M = C:RegisterModule("Comms", {
    label = "小队露营同步",
    defaultEnabled = true,
    flavors = { retail = true, forever = true },
})

local PREFIX = "AZKIT"
local CHANNEL = "PARTY"
local peers = {}          -- [name] = { cd = 0, cap = "none", at = 0 }
ns.CampPeers = peers

local function Camp() return C:GetModule("Camp") end

local function MyInfo()
    local camp = Camp()
    if camp and camp.GetBroadcastInfo then
        local cd, cap = camp:GetBroadcastInfo()
        return math.floor(cd or 0), tostring(cap or "none")
    end
    return 0, "none"
end

function M:Broadcast()
    if not IsInGroup() then return end
    local cd, cap = MyInfo()
    local message = string.format("1|%d|%s", cd, cap)
    local ok = pcall(C_ChatInfo.SendAddonMessage, PREFIX, message, IsInRaid() and "RAID" or CHANNEL)
    return ok
end

local function OnAddonMessage(_, _, sender, _, _, message)
    if not sender or sender == "" then return end
    sender = Ambiguate and Ambiguate(sender, "short") or sender
    local ver, cd, cap = tostring(message):match("^(%d+)|(%d+)|(%w+)$")
    if ver ~= "1" then return end
    peers[sender] = { cd = tonumber(cd) or 0, cap = cap or "none", at = GetTime() }
end

local function OnGroupChanged()
    M:Broadcast()
end

function M:OnEnable()
    C:On("CHAT_MSG_ADDON", OnAddonMessage)
    C:On("GROUP_ROSTER_UPDATE", OnGroupChanged)
    C:On("PLAYER_ENTERING_WORLD", OnGroupChanged)
    C_Timer.NewTicker(30, function()
        if IsInGroup() then M:Broadcast() end
    end)
    M:Broadcast()
end

function M:OnDisable()
    C:Off("CHAT_MSG_ADDON", OnAddonMessage)
    C:Off("GROUP_ROSTER_UPDATE", OnGroupChanged)
    C:Off("PLAYER_ENTERING_WORLD", OnGroupChanged)
end

function M:Roster()
    local rows = {}
    local names = {}
    for name in pairs(peers) do names[#names + 1] = name end
    table.sort(names)
    for _, name in ipairs(names) do
        local p = peers[name]
        local stale = (GetTime() - (p.at or 0)) > 90
        rows[#rows + 1] = string.format("%-14s %s  冷却 %s", name,
            p.cap, (p.cd > 0) and string.format("%d:%02d", math.floor(p.cd / 60), p.cd % 60) or "可用")
        if stale then rows[#rows] = rows[#rows] .. "  (数据过期)" end
    end
    return rows
end
