# 02 · 插件运行模型与 API 基础

## 1. 插件是什么

插件是放在 `Interface\AddOns\<插件名>\` 下的一组 **Lua + XML** 文件，由客户端在启动时加载，运行在游戏自带的 Lua 解释器里（语义接近 Lua 5.1）。

它能做的：创建/修改界面、读客户端通过 API 暴露的数据、响应事件、把少量数据存到本地。
它不能做的：读写磁盘任意文件、联网、访问进程内存、调用系统 API。唯一的持久化通道是 `SavedVariables`。

## 2. TOC 文件：插件的清单

文件名必须与文件夹同名（`AzerothKit/AzerothKit.toc`），常用字段：

| 字段 | 作用 | 备注 |
| --- | --- | --- |
| `## Interface` | 目标客户端版本号 | 支持逗号分隔多值，如 `120105, 16001` |
| `## Title` / `## Title-zhCN` | 插件列表显示名 | 支持 `|cff...` 颜色码 |
| `## Notes` / `## Notes-zhCN` | 说明 | 同上 |
| `## Version` | 版本 | 打包工具会替换 |
| `## Author` | 作者 | |
| `## SavedVariables` | 账号级持久化变量名 | 逗号分隔多个 |
| `## SavedVariablesPerCharacter` | 角色级持久化变量名 | |
| `## Dependencies` / `## RequiredDeps` | 强依赖 | 缺失则不加载 |
| `## OptionalDeps` / `## OptionalDependencies` | 弱依赖 | 只影响加载顺序 |
| `## LoadOnDemand` | 按需加载 | `1` 时不随登录加载 |
| `## AddonCompartmentFunc` | 小地图插件抽屉的点击回调 | Mainline 家族用它替代小地图图标 |
| `## AddonCompartmentFuncOnEnter/OnLeave` | 抽屉悬停回调 | 可选 |
| `## IconTexture` | 图标 | |
| `## Category` / `## Group` | 插件列表分组 | |
| `## DefaultState` | 默认启用状态 | |

`Interface` 写法是双版本共存的第一道坎：

- **单文件多值**（推荐起步）：`## Interface: 120105, 16001`——DBM 就是这么干的（它列了 9 个值）。
- **按 flavor 分 TOC**：`Foo_Mainline.toc`、`Foo_Camelot.toc`、`Foo_Vanilla.toc`——Details 用的方案，适合不同版本文件清单差异很大的情况。
- 版本号落后于客户端时，插件会被标记"过期"，默认不加载（玩家需勾选"加载过期插件"）。每次客户端小版本更新都要跟号。

## 3. 加载顺序

```
读取 TOC → 按 TOC 内文件顺序执行 Lua/XML → ADDON_LOADED(自身) → 其余插件 → PLAYER_LOGIN → PLAYER_ENTERING_WORLD
```

- `SavedVariables` 在 `ADDON_LOADED` 之前就已就位，这是初始化数据库的正确时机。
- `PLAYER_LOGIN` 之后才适合做依赖其他插件/服务器数据的初始化。
- 每个文件顶部固定写 `local ADDON, ns = ...`，用 `ns` 做插件内命名空间，避免污染全局表。

## 4. 事件模型

```lua
local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_ENTERING_WORLD" then ... end
end)
```

- 12.0 起新增了 `RegisterEventCallback` / `RegisterUnitEventCallback`（免建 frame 的写法），新代码可以采用，老写法仍然有效。
- 高频事件（`UNIT_AURA`、`UNIT_HEALTH`、`NAME_PLATE_UNIT_ADDED`）要节流，不要在里面做全表遍历。
- `OnUpdate` 能少用就少用；用 `C_Timer.After` / `C_Timer.NewTicker` 替代轮询。

## 5. SavedVariables

- 落盘位置：`WTF\Account\<账号>\SavedVariables\<插件名>.lua`（角色级在 `WTF\Account\<账号>\<服务器>\<角色>\SavedVariables\`）。
- 写入时机：登出、`/reload`、客户端正常退出。**运行中不会实时写盘**，崩溃会丢数据。
- 必须自带 schema 版本与迁移逻辑：

```lua
AzerothKitDB = AzerothKitDB or {}
if (AzerothKitDB.schema or 0) < 1 then
    AzerothKitDB.schema = 1
    AzerothKitDB.showOnLogin = true
end
```

- **绝对不要把机密值（secret value）写进 SavedVariables**：它既不能序列化，也会在下次登录时变成奇怪的东西。

## 6. 污染（taint）与安全执行环境

WoW 用"污染传播"来防止插件替玩家做受保护的操作（施法、换装、移动、目标选择）：

- 暴雪的安全代码是"干净"的；插件代码是"被污染"的。
- 被污染的执行路径调用受保护函数（如 `CastSpellByName`、`UseAction`）会被拒绝或报"blocked from an action only available to the Blizzard UI"。
- `SecureActionButtonTemplate`、`SecureHandler*` 这类安全模板允许"玩家点击 → 由安全代码执行"，是插件能合法触发受保护行为的唯一正路。
- 安全模板的代码在受限环境中运行，不能用普通 Lua 库、不能读普通变量，只能通过 `Attributes` 传参。
- 12.x 在此之上再叠加"机密值"（见 03 篇），进一步限制战斗信息的**计算**。

实践准则：**能只做展示就不要碰受保护逻辑**；必须碰时用安全模板，把决策交给玩家点击。

## 7. 界面：Lua 为主，XML 为辅

- 纯 Lua `CreateFrame` 已能覆盖绝大多数需求，XML 主要价值是模板复用与可视化编辑。
- 现代通用模板：`BackdropTemplate`（背景/边框）、`SecureActionButtonTemplate`、`UIDropDownMenuTemplate`（旧）/ `Menu`（新）。
- 12.x 的界面基建：`Settings`（设置面板，10.0 重写）、`AddonCompartment`（小地图插件抽屉）、`MenuUtil`（右键菜单）、`EditMode`（编辑模式）。

## 8. 调试手段（必备）

| 手段 | 用法 |
| --- | --- |
| 打开 Lua 报错 | `/console scriptErrors 1` |
| 重载界面 | `/reload` |
| 求值 | `/dump UnitName("player")` |
| 查控件 | `/fstack`（鼠标悬停看层级与所属插件） |
| 事件追踪 | `/eventtrace` |
| 污染日志 | `/console taintLog 2` → `Logs\taint.log` |
| 报错收集 | 装 BugSack + BugGrabber，比默认错误框好用得多 |
| API 探测 | `/run print(type(C_Secrets), type(issecretvalue))` |

## 9. 常用库与它们的现状

| 库 | 用途 | 现状 |
| --- | --- | --- |
| Ace3（AceAddon/AceDB/AceConfig/AceGUI/AceEvent） | 插件骨架、配置、事件 | 仍是主流，但 AceConfig 面板在 12.x 需适配 Settings |
| LibStub / CallbackHandler-1.0 | 库注册与回调 | 稳定 |
| LibSharedMedia-3.0 | 共享材质/字体/音效 | 稳定 |
| LibDataBroker-1.1 + LibDBIcon-1.0 | 数据源与小地图图标 | Mainline 家族更推荐 AddonCompartment |
| LibSpecialization / LibOpenRaid | 专精、团队信息 | DBM/Details 在用，无限有分支处理 |

新项目建议：**少依赖库**。Ace3 的学习成本不低，而 Settings API + 原生 frame 已经够用；依赖越少，双版本适配越省事。

## 10. API 文档去哪查

| 来源 | 说明 |
| --- | --- |
| [Warcraft Wiki](https://warcraft.wiki.gg/wiki/World_of_Warcraft_API) | 最全的社区文档，含每个补丁的 API changes |
| [Gethe/wow-ui-source](https://github.com/Gethe/wow-ui-source) | 暴雪界面源码镜像，**有 `forever` 分支**，可 diff 正式服与无限 |
| `Blizzard_APIDocumentation` | 客户端内自带的 API 文档数据（townlong-yak 有在线镜像） |
| [wago.tools](https://wago.tools) | DB2 数据表浏览（物品、法术、地图 ID） |
| 游戏内 `/dump` + `/api`（部分版本） | 现场确认函数是否存在、返回什么 |
