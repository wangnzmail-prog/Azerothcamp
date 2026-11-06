# 07 · NDui 与 Details 解剖：能不能自己取代，怎么取代

> 结论先行：
> **NDui 可以"模块级"取代，但不该"整体"重写**——6.6 万行、10 个模块、自研配置框架 + oUF/cargBags 两大基座。
> **Details 只是官方伤害统计的一层前端**（`Details.DM = C_DamageMeter`），24 万行里 8 万行是自带框架；自研的目标应是"一个只读的轻量统计面板"，而不是重写它。

数据来源：本机 `_retail_` / `_forever_` 两份安装（2026-11-06 实测，逐文件统计）。

## 1. 规模对比

| 指标 | NDui | Details |
| --- | --- | --- |
| 文件总数 | 354 | 562 |
| Lua 文件 | 295 | 295 |
| 总行数 | **65,758** | **241,695** |
| 体积 | 2.85 MB | 43.48 MB |
| 自带库行数 | 14,404（21%） | 80,096（33%） |
| 最大子目录 | Modules 36,646 行 | Libs 80,096 / frames 53,721 行 |
| 配置体积（SavedVariables） | 10–20 KB | 120–200 KB |
| TOC 策略 | 空壳 `NDui.toc` + `NDui_Mainline.toc`(120105) + `NDui_Camelot.toc`(16001) | 空壳 + 7 个 flavor TOC（Mainline/Camelot/Classic/Cata/Mists/TBC/Wrath） |

两个插件都用了我们在 [04 篇](04-dual-flavor-architecture.md)里说的**方案 B（按 flavor 分 TOC）**，可以直接拿来当参考实现。

## 2. NDui 解剖

### 2.1 整体骨架

```
NDui.toc                 (空壳，只为 CurseForge 抓取)
NDui_Mainline.toc        ## Interface: 120105  Version 10.2.7
NDui_Camelot.toc         ## Interface: 16001   Version 0.0.8
Init.lua                 → 命名空间、事件总线、模块注册器、UI 缩放
Locales\Locales.xml      → 6 个语言文件，5,194 行
Core\Core.xml            → 数据库/工具/定位器/配置界面/教学/更新日志
Config\Config.xml        → 各模块的静态配置表
Libs\Libs.xml            → 7 个库
Modules\Modules.xml      → 10 个模块，顺序固定
Plugins\Plugins.xml      → 5 个可选扩展
```

`Init.lua` 里定义了 4 个命名空间槽，全插件共用：

```lua
ns[1] = {}   -- B, Basement（核心工具）
ns[2] = {}   -- C, Config（静态配置）
ns[3] = {}   -- L, Locales（本地化）
ns[4] = {}   -- DB, Database（运行时数据）
```

### 2.2 自研的两套基础设施

**事件总线**——不直接用 `frame:RegisterEvent`，而是集中注册、分发给多个回调：

```lua
function B:RegisterEvent(event, func, unit1, unit2)
    if event == "CLEU" then event = "COMBAT_LOG_EVENT_UNFILTERED" end
    ...
end
```

**模块注册器**——每个模块自己注册，登录后统一 `OnLogin`：

```lua
local module = B:RegisterModule("ActionBar")
function module:OnLogin() ... end
```

这套"事件总线 + 模块注册"结构很值得抄，不比 Ace3 差，而且没有 Ace3 的历史包袱。

### 2.3 十个模块（retail 版行数）

| 模块 | 行数 | 关键文件 | 说明 |
| --- | --- | --- | --- |
| Skins | **13,997**（133 文件） | Blizzard/*、AddOns/* | 重绘暴雪界面 + 20 多个常见插件，占了整个插件的 38% |
| Misc | 4,768（20 文件） | Misc、RaidTool、Notifications、ItemLevel、Mail | 自动修理/售卖、团队工具、打断通报、装等、邮件 |
| UFs | 4,624（7 文件） | Functions 2,050、Nameplates 1,079、Spawns 710 | 单位框架 + 姓名板，基于 oUF |
| Maps | 3,637（3 文件） | Minimap、WorldMap、RawMapData 3,440 | 小地图 + 世界地图（含 3,440 行地图数据） |
| Infobar | 2,556（10 文件） | 金币/时间/公会/专精/好友… | 信息条，12 个小组件 |
| ActionBar | 1,734（11 文件） | Bars、Keybind | 动作条重绘，基于 LibActionButton-1.0 |
| Bags | 1,723（3 文件） | Core 1,429 | 背包重构，基于 cargBags |
| Tooltip | 1,526（7 文件） | Tip、ItemLevel | 鼠标提示增强 |
| Chat | 1,436（6 文件） | Core、Filter、ChannelRename | 聊天框重写 |
| Auras | 645（3 文件） | Auras | 光环/冷却图标 |

### 2.4 基座依赖

| 库 | 用在哪 | 引用密度 | 含义 |
| --- | --- | --- | --- |
| **oUF** | 单位框架、姓名板 | 142 处 | 想自研单位框架，要么继续用 oUF 写布局，要么自己处理单位事件/血量/光环的脏活 |
| **cargBags** | 背包 | 5 处 | 背包的分类/排序/搜索框架 |
| **LibActionButton-1.0** | 动作条按钮 | 2 处 | 处理安全模板、冷却、计数 |
| LibCustomGlow / CallbackHandler / LibBase64 | 高亮、回调、编解码 | — | 通用小库 |

### 2.5 它已经在适配机密值

`Core/Functions.lua` 里有现成封装：

```lua
local issecretvalue, issecrettable = issecretvalue, issecrettable
function B:IsSecretValue(value) return issecretvalue and issecretvalue(value) end
function B:IsNotSecretValue(value) return not issecretvalue or not issecretvalue(value) end
```

UFs 里对 `guid`、控件宽高等位置都做了 secret 保护。这说明 **NDui 0.0.8 是认真适配过 12.x 规则的**，不是硬套旧代码。

### 2.6 一个遗留风险点

`Modules/Misc/Notifications.lua:211` 仍然保留：

```lua
B:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED", M.InterruptAlert_Update)
```

这是"打断通报"功能。如果它默认开启，在 12.x / 无限上注册就会抛错。是否真的触发，取决于该功能开关——正好是 [06 篇](06-roadmap-and-checklist.md) 里 Q1 的实测点。

## 3. Details 解剖

### 3.1 它已经不是"解析战斗日志"的插件了

`boot.lua:71`：

```lua
Details.DM = C_DamageMeter
```

`Details.toc`（Mainline/Camelot）里加载的是 `core\parser_nocleu.lua`，而那个 6,663 行的老解析器 `core\parser.lua` **根本不在清单里**——它只服务 Classic 系列。

所以现在的 Details 是：**官方伤害统计的会话数据 + 自己的一套展示/配置/上报框架**。

### 3.2 官方统计的数据模型（从代码里读出来的）

```lua
-- 会话（一个战斗片段）
C_DamageMeter.GetCombatSessionFromType(type, index)      --> session
C_DamageMeter.GetCombatSessionFromID(sessionID, index)   --> session
C_DamageMeter.GetAvailableCombatSessions()               --> { {sessionID=...}, ... }
C_DamageMeter.GetSessionDurationSeconds(type)            --> 秒

-- 会话对象
session = {
    combatSources  = { { name = "...", ... }, ... },  -- 每个玩家/宠物一条
    totalAmount    = 0,
    maxAmount      = 0,
    durationSeconds = 0,
}

-- 单个来源的明细
C_DamageMeter.GetCombatSessionSourceFromType(type, index, guid, x)
```

Details 在 `boot.lua` 里又包了一层 `Details222.B.GetSegment/GetSpells/GetSegmentInfo`，就是为了把两套入口（Type / ID）抹平。

### 3.3 战斗中的"闭眼"机制

`Details222.Apocalypse.IsServerInCombat()` 会去检查 `session.combatSources[1].name` 是不是 `issecretvalue`。是——就认为服务器处于"数据加密"状态，停止更新显示。

这就是 12.x 下第三方统计的真实处境：**数据在战斗中不可读，只能战斗结束后读聚合值**。全插件 80 处 `issecretvalue` 里，26 处在 `parser_nocleu1.lua`、16 处在 `parser_nocleu_tp.lua`，正好都在数据入口。

### 3.4 分层

| 层 | 行数 | 内容 |
| --- | --- | --- |
| Libs | 80,096 | 自带 DetailsFramework（窗口/表格/编辑器/皮肤）+ 20 多个第三方库 |
| functions | 28,330 | 命令、配置档、皮肤、报告、WCL 上传、MDT 集成、存储调度 |
| classes | 25,967 | 伤害/治疗/资源/战斗/实例/宠物等统计模型，`class_damage.lua` 一个文件 6,623 行 |
| frames | 53,721 | 主窗口、明细窗口、时间轴、窗口设计器 |
| core | 21,649 | parser、control、plugins、网络同步、时光机 |

**这意味着：想复刻 Details，等于复刻一个 GUI 框架 + 一套统计模型 + 一个窗口设计器。** 这不是"写个插件"的量级。

## 4. 替代可行性矩阵

| 能力 | 现在由谁提供 | 自研难度 | 主要风险 | 建议 |
| --- | --- | --- | --- | --- |
| 鼠标提示增强 | NDui Tooltip | ★☆☆ | 低 | **先做**，纯 `TooltipDataProcessor` |
| 信息条（金币/耐久/坐标/帧数…） | NDui Infobar | ★☆☆ | 低 | **先做**，纯读取 |
| 背包整理/分类/搜索 | NDui Bags（cargBags） | ★★☆ | 中：容器 API 多、要处理银行/公会银行 | 可自研，或直接用 cargBags 写自己的布局 |
| 小地图 | NDui Maps | ★★☆ | 中：按钮收纳、追踪点 | 可自研 |
| 世界地图/任务追踪 | NDui Maps | ★★☆ | 中 | 后续 |
| 聊天框 | NDui Chat | ★★☆ | 中：频道、过滤、超链接 | 后续 |
| 单位框架 | NDui UFs（oUF） | ★★★ | 高：单位事件量、光环、连击点、载具 | **基于 oUF 写布局**，别自己造基座 |
| 姓名板 | NDui UFs | ★★★ | 高：12.x 下施法条状态是 secret | 只做外观，不读状态 |
| 动作条 | NDui ActionBar（LibActionButton） | ★★★★ | 很高：安全模板、翻页、按键、载具、姿态 | **先只做皮肤**，别重写 |
| 光环/冷却 | NDui Auras | ★★★ | 高：12.1 的 `AuraContainer` 是新体系 | 先做皮肤 |
| 皮肤层（暴雪界面重绘） | NDui Skins（8,000+ 行） | ★★☆ 但极耗人力 | 低技术风险、高工作量 | 只 skin 自己常用的 3–5 个窗口 |
| 团队工具/检查 | NDui Misc | ★★☆ | 中 | 按需 |
| **伤害/治疗统计** | Details | ★★★★ | 战斗中数据 secret，只能战后聚合 | **做"只读统计面板"**，不做解析器 |
| 统计明细/时间轴/报告 | Details | ★★★★★ | 等于重写 GUI 框架 | 不做 |

## 5. 推荐路线

### Phase A（低风险，2–3 周，能独立上线）

`AzerothKit` 升级成模块化套件，先落三个模块：

1. **Tooltip**（`TooltipDataProcessor.AddTooltipPostCall`）
2. **Infobar**（金币/耐久/坐标/帧数/延迟，纯读取）
3. **Bags**（分类 + 搜索 + 一键整理，容器 API）

这三个不碰战斗数值、不碰安全模板，两个客户端都能跑，能最快跑通"开发 → 打包 → 上架 → 收反馈"的闭环。

### Phase B（中风险，4–6 周）

4. **UnitFrames**：基于 oUF 写一套自己的布局（不重写 oUF）
5. **Minimap**
6. **Chat**

### Phase C（高风险，按需）

7. 动作条**皮肤**（不重写行为）
8. 光环**皮肤**
9. **Stats 面板**：只读 `C_DamageMeter`，战后刷新，战斗中显示"--"

### 明确不做

- 整体重写 NDui（6.6 万行 ≈ 人月级）
- 重写 Details / DetailsFramework（24 万行 ≈ 人年级）
- 复刻 Details 的窗口设计器、时间轴、WCL 上传

## 6. 与 AzerothKit 的整合设计

新增一个模块注册器（约 40 行），把现在的单文件插件升级成套件：

```lua
-- Core.lua 里增加
local modules = {}

function ns:RegisterModule(name, def)
    assert(not modules[name], "duplicate module: " .. name)
    def.name = name
    def.enabled = def.defaultEnabled ~= false
    def.flavors = def.flavors or { "retail", "forever" }
    modules[name] = def
    return def
end

function ns:IsModuleEnabled(name)
    local m = modules[name]
    if not m or not m.enabled then return false end
    for _, f in ipairs(m.flavors) do
        if f == ns.Platform.flavor then return true end
    end
    return false
end
```

模块文件示例（`Modules/Tooltip.lua`）：

```lua
local ADDON, ns = ...
local M = ns:RegisterModule("Tooltip", {
    defaultEnabled = true,
    flavors = { "retail", "forever" },
})

function M:OnEnable()
    -- TooltipDataProcessor.AddTooltipPostCall(...)
end

function M:OnDisable() end
```

要点：

- **模块开关进 SavedVariables**（`AzerothKitDB.modules.Tooltip = true`）
- **flavor 声明**让同一套代码在正式服/无限各自启用不同模块
- **事件总线**沿用 NDui 的思路：集中注册、按事件分发、单次 `xpcall` 包住（别让一个模块的错拖垮整个套件）
- **皮肤层拆成独立 addon**（`AzerothKit_Skins`），用 `## OptionalDeps` 挂接，避免主包被暴雪界面改动拖下水

## 7. 一句话建议

> 不要把目标定成"取代 NDui / Details"，那是一场人年级的仗。
> 定成"**用 3–5 个自己写的轻量模块，替掉 NDui 里你最常用的那部分，再用一个只读面板替掉 Details 的查看需求**"——三个 Phase 之后，你会发现那两个插件已经被你"用不上"了，而不是"被重写"了。

## 8. 待实测（补进 06 篇清单）

| # | 问题 | 验证 |
| --- | --- | --- |
| Q9 | 无限上 `C_DamageMeter` 返回的 `combatSources[].name` 是否 secret？ | `/run local s=C_DamageMeter.GetCombatSessionFromType(0,0); print(s and s.combatSources[1] and tostring(issecretvalue(s.combatSources[1].name)))` |
| Q10 | 战斗中第三方统计能否"透传"数值到 StatusBar？ | 用 `SetValue(secret)` 试 |
| Q11 | NDui 的打断通报在无限上是否报错？ | 开启该功能后 `/reload` 看是否红字 |
| Q12 | 无限上 oUF 是否可用？ | NDui UFs 在无限正常运行即证明 |
