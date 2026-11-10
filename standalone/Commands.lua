-- Commands.lua · 独立版的 /ac 命令（套件里由 Diagnostics 承担）
local ADDON, ns = ...
local C = ns.Core

local PREFIX = "|cff69ccf0[AzerothCamp]|r "

local function out(msg)
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage(PREFIX .. tostring(msg))
    end
end

local function Camp() return C.GetModule and C:GetModule("Camp") end
local function Comms() return C.GetModule and C:GetModule("Comms") end

local function PrintCamp()
    local m = Camp()
    if not m or not m.ScanReport then out("露营模块未加载") return end
    local lines = m:ScanReport()
    for _, line in ipairs(lines) do out("  " .. tostring(line)) end
    if ns.db then
        lines[#lines + 1] = "at " .. date("%Y-%m-%d %H:%M:%S")
        ns.db.campReport = table.concat(lines, "\n")
        out("已写入 AzerothCampDB.campReport（/reload 后 Agent 可读）")
    end
end

local function PrintGroup()
    local m = Comms()
    if not m then out("同步模块未加载") return end
    m:Broadcast()
    local rows = m:Roster()
    if #rows == 0 then
        out("暂未收到队友数据（对方也需装本插件，并在同一队伍）")
        return
    end
    out("小队露营:")
    for _, line in ipairs(rows) do out("  " .. line) end
    if m.Persist then m:Persist() end
end

local function PrintErrors()
    local list = ns.db and ns.db.errors or {}
    if #list == 0 then out("没有记录到错误") return end
    out(string.format("最近 %d 条错误:", #list))
    for i, line in ipairs(list) do out(string.format("  %d. %s", i, tostring(line))) end
end

local function Handle(msg)
    local cmd = string.lower((msg or ""):match("^%s*(%S*)") or "")
    if cmd == "camp" then
        PrintCamp()
    elseif cmd == "group" then
        PrintGroup()
    elseif cmd == "errors" then
        PrintErrors()
    elseif cmd == "clearerrors" then
        if ns.db then ns.db.errors = nil end
        out("已清空错误记录")
    else
        out("命令: /ac camp | /ac group | /ac errors | /ac clearerrors")
    end
end

SLASH_AZEROTHCAMP1 = "/ac"
SLASH_AZEROTHCAMP2 = "/azerothcamp"
SlashCmdList["AZEROTHCAMP"] = Handle
