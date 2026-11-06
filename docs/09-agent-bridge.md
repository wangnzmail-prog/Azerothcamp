# 09 · Agent 接入设计：让插件"可被 AI 调整、保存、更新"

## 1. 先把目标拆成两件事

1. **整合**：我们的插件当"控制台"，统一管理/换皮其他插件（NDui 的 `Skins/AddOns/*.lua` 就是这个模式的现成范例）。
2. **Agent 接入**：AI 能读插件状态、改配置、保存、更新代码——而不是在游戏里陪聊。

这两件事的耦合点只有一个：**一份机器可读的配置 schema + 一个稳定的写入口**。本文就是这份协议。

## 2. 硬约束：Agent 不可能"住在游戏里"

WoW 插件运行在客户端的 Lua 沙箱里：

| 能力 | 插件能否做到 |
| --- | --- |
| 联网（HTTP/WebSocket） | ❌ |
| 读写任意文件 | ❌ 唯一持久化是 SavedVariables |
| 启动进程 / 调用系统 API | ❌ |
| 模拟键盘鼠标 | ❌（且违反插件政策） |
| 读其他插件的 SavedVariables 全局表 | ✅（同一 Lua 环境，是普通全局表） |
| 写自己的 SavedVariables | ✅（登出 / `/reload` 时落盘） |

所以 Agent **必须运行在游戏外**（就在这台机器上，用 DSH / 本地进程）。它和游戏之间只有"文件"这一条路。

## 3. 三条通道（已经跑通第一条）

| 方向 | 通道 | 延迟 | 用途 |
| --- | --- | --- | --- |
| Agent → 游戏 | **`Profile.lua`**（固定文件，常驻 TOC） | 一次 `/reload`（约 1–2 秒） | 改配置、开关模块、换主题参数 |
| Agent → 游戏 | 直接改模块 `.lua` / 新增文件 | 一次 `/reload`（新增文件建议重启客户端） | 改功能、修 bug、加新模块 |
| 游戏 → Agent | **SavedVariables**（`WTF\...\SavedVariables\AzerothKit.lua`） | 登出 / `/reload` 后 | 读当前状态、读 `/ak export` 的导出 |
| 游戏 → Agent | `Logs\`（`/chatlog` 打开后近实时写 `WoWChatLog.txt`） | 秒级 | 实时看报错/探针输出（可选） |
| 人工 | 聊天框粘贴、剪贴板 | 即时 | 兜底 |

关键点：**游戏只在"加载时"读文件**。所以 Agent 的写操作天然是"改文件 → 让玩家 `/reload`"，这是机制决定的，不是设计缺陷。反过来，这个延迟对"改配置/装更新"这种低频操作完全够用。

## 4. 架构

```
┌────────────────────────────── 游戏外（Agent 侧） ──────────────────────────────┐
│  DSH / 本地 Agent                                                              │
│    ├─ 读：WTF\...\SavedVariables\AzerothKit.lua（状态）                          │
│    ├─ 读：Logs\WoWChatLog.txt（可选，近实时）                                     │
│    ├─ 改：profiles\*.json  ──►  tools\ak-config.ps1  ──►  addon\...\Profile.lua │
│    ├─ 改：Modules\*.lua / Theme.lua（代码与主题）                                 │
│    ├─ 验：tools\check.ps1（Interface + Lua 语法）                                 │
│    └─ 发：git commit（每次改动可回滚、可 diff）                                    │
└───────────────────────────────────┬───────────────────────────────────────────┘
                                    │ 文件（AddOns 目录联接）
┌───────────────────────────────────▼───────────────────────────────────────────┐
│ 游戏内：AzerothKit                                                             │
│   Platform ─ Theme ─ Core(schema/profile/export) ─ UI ─ Integrations ─ Modules │
└───────────────────────────────────────────────────────────────────────────────┘
```

## 5. 协议三件套

### 5.1 Schema（模块声明自己能改什么）

每个模块在注册时声明可调项，Agent 和游戏内面板**共用这一份**：

```lua
C:RegisterModule("Infobar", {
    settings = {
        { key = "scale",   type = "number", default = 1.0, min = 0.8, max = 1.6, step = 0.05 },
        { key = "offsetY", type = "number", default = -6,  min = -200, max = 0,   step = 1 },
    },
})
```

`/ak schema` 会把全部可调项打印出来（Agent 也能从代码里静态解析）。

### 5.2 Profile（Agent 的写入口）

固定文件 `Profile.lua`，永远在 TOC 里：

```lua
AzerothKitProfile = {
    version = 3,
    modules = {
        Infobar = { enabled = true, scale = 1.1, offsetY = -8 },
    },
}
```

**版本化覆盖语义**：只有 `version > AzerothKitDB.appliedProfile` 时才覆盖，避免每次登录冲掉玩家刚在游戏里调好的值。Agent 每次生成都自增版本，玩家手动改的值保持"最后写入者获胜"。

生成命令（已实现）：

```powershell
powershell -ExecutionPolicy Bypass -File tools\ak-config.ps1 -Json profiles\default.json
# 自动：JSON → Profile.lua，版本 +1，并跑 check.ps1
```

### 5.3 Export（游戏 → Agent）

游戏内 `/ak export`：

1. 把当前全部模块状态序列化成 Lua 文本；
2. 写进 `AzerothKitDB.exportText`；
3. `/reload` 后落盘，Agent 直接读 `WTF\...\SavedVariables\AzerothKit.lua`。

这样 Agent 就有了"读现状 → 改 → 写回"的完整闭环。

## 6. 整合层怎么落地（对所有其他插件）

新增 `Integrations/` 目录，一个第三方插件一个适配文件，形态与 NDui 的皮肤文件一致：

```lua
-- Integrations/Details.lua
local I = ns:RegisterIntegration("Details", {
    addon = "Details",          -- 检测该插件是否加载
    panel = true,               -- 是否在我们的面板里给它一页
})

function I:OnAddonLoaded()
    -- 1) 换皮：读它的窗口句柄，套我们的 Theme
    -- 2) 暴露设置：把 _detalhes_global 里关心的字段映射成我们的 schema
    -- 3) 可选：屏蔽它自己的设置入口，统一到我们的面板
end

function I:ApplySetting(key, value)
    -- 写回它自己的 SavedVariables（注意它可能缓存了值，改完提示 /reload）
end
```

能这么做的前提：**第三方插件的 SavedVariables 是普通全局表**（`_detalhes_global`、`DBM_AllSavedOptions`、`NDuiADB`…），我们可读可写。风险在于对方可能缓存了值，所以"改完 → `/reload`"是标准动作。

建议的整合优先级（按"你实际在用"和"改起来安全"排）：

| 目标 | 能整合什么 | 风险 |
| --- | --- | --- |
| Details | 配色/字体/窗口位置/是否显示某列 | 低（纯显示字段） |
| DBM | 计时条外观、提示音、位置 | 低 |
| NDui（并存期） | 关掉它的同名模块、复用它的材质 | 低 |
| 各类小插件 | 统一开关、统一放到我们的面板 | 低 |

## 7. 四个真实工作流

**A. 调信息条（已实现，可当场验证）**

> 你：「信息条往下一行，放大 10%」
> 我：改 `profiles/default.json` → 跑 `ak-config.ps1`（版本 +1）→ 你 `/reload`

**B. 换整套主题**

> 你：「整体换成冷灰 + 细边框」
> 我：只改 `Theme.lua` 里的 8 个颜色令牌与 2 个间距常量 → 所有模块同时变 → `/reload`

**C. 统一第三方插件外观**

> 你：「Details 也换成同一套配色」
> 我：写 `Integrations/Details.lua`，把它的窗口套 `Theme:ApplyBackdrop`，颜色映射到 `Theme.color` → `/reload`

**D. 更新插件**

> 你：「更新到新版本」
> 我：拉取/生成新代码 → 跑 `check.ps1` → 写回 `AddOns`（联接目录即改即生效）→ 你 `/reload`；TOC 变更则提示重启客户端

## 8. 安全与边界（自己用也要守）

- 只写 `D:\ai\wow\` + 白名单内的 `WTF\...\SavedVariables\`，不碰游戏二进制与 CASC。
- 所有改动进 git：`git diff` 就是"这次 Agent 改了什么"的审计记录。
- 不做输入模拟、不读内存、不绕过安全模板——这条线一旦越，账号风险不可控。
- Agent 生成的 Lua 必须过 `check.ps1`（语法）+ 游戏内 `/reload` 冒烟（运行时）。

## 9. 现状与下一步

**已完成（v0.4.0）**

- `Core`：settings schema、`GetSetting/SetSetting`、`ApplyProfile/SyncProfile`、`ExportProfile`
- 固定写入口 `Profile.lua` + 版本化覆盖
- `tools\ak-config.ps1`：JSON → Profile.lua（自动 +1 版本、自动校验），已跑通
- `/ak schema`、`/ak export`、`/ak integrations`
- **整合层框架**：`C:RegisterIntegration(name, def)` + `ApplyIntegrations()`（登录时按"对方是否加载"分派）
- **第一个适配器** `Integrations\Details.lua`：检测 Details、读版本/窗口数/皮肤、把我们的 `scale` 设置应用到它所有窗口

**待做**

1. `tools\ak-read.ps1`：解析 `AzerothKit.lua`，把 `exportText` 提取成 JSON（补齐"读"这一环）
2. 面板里渲染 settings（滑块/下拉），让游戏内也能改，不必只靠 JSON
3. 第二个适配器（DBM 计时条 / NDui 同名模块接管）
4. `/chatlog` 实时通道（可选，用于看报错流）

## 10. 实战记录：两个已经踩过的坑

**坑 1：PowerShell 写文件带 BOM。**
用 `Set-Content -Encoding UTF8`（Windows PowerShell 5.1）会写入 **BOM**，并且会把源码里的中文按 ANSI 读成乱码。后果很隐蔽：`## Interface` 前的 BOM 让整份 TOC 失效（`check.ps1` 报 `NO-INTERFACE`），Lua 文件首字节也过不了语法检查。

现在 `check.ps1` 会扫描 `addon/` 下所有 `.lua/.toc/.xml` 的 BOM 并直接判失败；写文件请用 `[System.IO.File]::WriteAllText($p, $text, (New-Object System.Text.UTF8Encoding($false)))`。

**坑 2：首次加载的 DB 是旧 schema。**
`WTF\...\SavedVariables\AzerothKit.lua` 里如果还是 `["schema"] = 1`，说明客户端跑的是 0.2 及以前的构建；0.4 会把 schema 迁到 2 并应用 `Profile.lua`（聊天框会打印"已应用配置档案 vN"）。看到这行才算真正验证了新内核。
