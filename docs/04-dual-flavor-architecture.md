# 04 · 一套代码同时跑正式服与无限

## 1. 三种可选架构

| 方案 | 做法 | 优点 | 缺点 | 适用 |
| --- | --- | --- | --- | --- |
| A. 单 TOC 多 Interface | 一个 `.toc` 写 `## Interface: 120105, 16001`，运行时判定 | 结构最简单，一份包两个客户端通用 | 文件清单无法差异化 | **推荐起步**（DBM 在用） |
| B. 按 flavor 分 TOC | `Foo_Mainline.toc` + `Foo_Camelot.toc`，各自列文件 | 文件级隔离，差异大时清爽 | 两份清单要同步维护；部分旧 build 未必识别 `_Camelot` 后缀 | 差异变大之后（Details 在用） |
| C. 拆成两个插件 | 共用 `Foo_Core` 依赖包 + 两个薄壳 | 完全隔离 | 分发、版本、玩家安装都变复杂 | 不推荐 |

本仓库的 `addon/AzerothKit` 用方案 A。文档末尾给了迁移到 B 的步骤。

## 2. 版本判定：命名常量 + 兜底 + 能力探测

```lua
local PROJECT_MAINLINE = WOW_PROJECT_MAINLINE or 1
local PROJECT_CLASSIC  = WOW_PROJECT_CLASSIC  or 2
local PROJECT_CAMELOT  = WOW_PROJECT_CAMELOT   -- 只有无限客户端才定义

local function GetFlavor()
    local id = WOW_PROJECT_ID
    if PROJECT_CAMELOT and id == PROJECT_CAMELOT then return "forever" end
    if toc >= 16000 and toc < 20000 then return "forever" end   -- 兜底：早期 build 报 1
    if id == PROJECT_MAINLINE then return "retail" end
    if id == PROJECT_CLASSIC  then return "classic" end
    return "unknown"
end
```

判定完**必须再问能力**，不要用版本号推断功能：

```lua
function HasAPI(path)            -- "C_DamageMeter.GetAvailableCombatSessions"
    local node = _G
    for key in path:gmatch("[^%.]+") do
        node = type(node) == "table" and node[key] or nil
        if node == nil then return false end
    end
    return true
end

HasAPI("C_Secrets.ShouldAurasBeSecret")   -- 有，就按新规则写
HasAPI("C_DamageMeter")                   -- 有，就能做"只读统计"展示
type(issecretvalue) == "function"         -- 机密值体系是否存在
```

## 3. 已知的两版本差异点（照抄即可）

| 场景 | 正式服 12.1.5 | 无限 1.60.1 | 写法 |
| --- | --- | --- | --- |
| 取玩家名 | `UnitName` 仍可用（战斗中非队友为 secret） | 用 `GetUnitName`（DBM 在无限上专门切到它） | 封装 `Compat.PlayerName()`，优先 `GetUnitName`，再退 `UnitName`，都 secret 则用 `UNKNOWN` |
| 战斗日志 | 禁止注册 | 社区报告不可用 | 直接不写 CLEU 相关代码 |
| 物品/法术查询 | `C_Item.*` / `C_Spell.*` 命名空间 | 同 | 用 `C_*` 新命名空间，别用 `GetItemInfo` 老式全局（部分已弃用） |
| 播放音效 | `PlaySound(SOUNDKIT.xxx)` | 同 | 不要用 `PlaySoundFile("Interface\\...ogg")` |
| 阵营判断 | `UnitIsEnemy` 语义变化 | 同 | 用 `UnitIsPlayer` + `UnitIsFriend` + `C_PvP.IsPVPMap()` 组合 |
| 小地图入口 | AddonCompartment | 客户端已带 AddonCompartment | TOC 写 `## AddonCompartmentFunc` |
| 设置面板 | `Settings` API（10.0 重写） | 同 | `Settings.RegisterVerticalLayoutCategory` |
| 光环 | 12.1 起受限上下文直接抛错 | 同 | 不读光环数据做判断；只渲染 Blizzard 给的对象 |
| 姓名板 | `NAME_PLATE_UNIT_ADDED` 可能早于单位填充 | 同（社区实测） | 事件里延后一帧再读 |

## 4. 目录分层（推荐）

```
addon/AzerothKit/
  AzerothKit.toc
  Platform.lua        -- 版本/能力探测，唯一的"if 版本"集中地
  Compat.lua          -- API 垫片：名字、音效、物品、阵营的统一入口
  Core.lua            -- 生命周期、SavedVariables、迁移
  UI.lua              -- 纯展示层
  Diagnostics.lua     -- /ak 命令、探针
  Flavor_Retail.lua   -- 只有正式服才跑的代码（TOC 里照样列，内部 if 拦截）
  Flavor_Forever.lua  -- 无限专属内容（露营、传承等）
```

要点：**插件不能在运行时加载任意文件**（除 LoadOnDemand 插件），所以"按版本分文件"必须把文件都列进 TOC，再在文件里用 `Platform.flavor` 做守卫。

## 5. 差异集中到 Compat 层

```lua
local Compat = {}

function Compat.PlayerName()
    if Platform.flavor == "forever" and type(GetUnitName) == "function" then
        local n = GetUnitName("player")
        if n and not Platform.IsSecret(n) then return n end
    end
    if type(UnitName) == "function" then
        local n = UnitName("player")
        if n and not Platform.IsSecret(n) then return n end
    end
    return UNKNOWN or "Unknown"
end

function Compat.SafeNumber(v, fallback)
    if Platform.IsSecret(v) then return fallback end
    return tonumber(v) or fallback
end

return Compat
```

业务代码只调 `Compat.*`，不直接调有差异的 API。这样新版本出问题时，改动面永远只有 Compat 一个文件。

## 6. 从方案 A 迁移到方案 B（差异变大时）

1. 把 `AzerothKit.toc` 复制成 `AzerothKit_Mainline.toc`（`## Interface: 120105`）与 `AzerothKit_Camelot.toc`（`## Interface: 16001`）。
2. 删掉裸 `AzerothKit.toc`（**不要同时存在裸 TOC 和 flavor TOC**，容易加载到不该加载的那份）。
3. 在两个 TOC 里分别列文件：公共文件照旧，flavor 专属文件只出现在对应清单里。
4. 进游戏用 `/dump select(4, GetBuildInfo())` 确认加载的是哪份（打印 `## Version` 后缀做标记）。
5. 如果发现某些 build 不认 `_Camelot` 后缀，退回方案 A（单 TOC 多 Interface 永远可用）。

## 7. 测试矩阵（每次改代码跑一遍）

| 场景 | 正式服 | 无限 |
| --- | --- | --- |
| 登录无报错 | ✅ | ✅ |
| `/ak probe` 输出正确版本 | ✅ | ✅ |
| 战斗中打开窗口不报错 | ✅ | ✅ |
| 战斗中显示血条（用 `SetValue` 透传） | ✅ | ✅ |
| 战斗结束后重新计算 | — | — |
| `/reload` 后 SavedVariables 正常 | ✅ | ✅ |
| 切换语言 zhCN/enUS 无乱码 | ✅ | ✅ |

## 8. 命名与分发

- 插件文件夹名 = TOC 文件名 = 全局变量前缀，三处要一致，玩家才不会装出两个副本。
- SavedVariables 变量名带插件前缀（`AzerothKitDB`），避免和别人的表撞名。
- 一份 zip 同时发布到两个客户端是可行的（方案 A 的前提下），但要在说明里写清各自的最低 Interface。
