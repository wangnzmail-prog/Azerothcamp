# 08 · 自研套件蓝图：NDui 级 UI + 内置统计

## 0. 先定约束（会决定整条路线）

**NDui 是"保留所有权利"（All Rights Reserved）。** `License.txt` 原文：

> The contents of this addon ... are copyrighted to its authors with all rights reserved.
> 1. You may make modifications to this addon for **private use only**, you may not publicize any portion ...
> 3. Do not embed the contents of this addon within another addon without permission ...

所以：

- ✅ 可以**读它、学它的结构**（模块划分、主题层、事件总线）
- ✅ 可以自己私下改着玩
- ❌ 不能 fork 后发布、不能把它的代码/材质搬进我们的插件
- ❌ 不能"NDui + 我们的模块"打包成一个发布物

结论：**必须 clean-room 重写**。好消息是 NDui 的架构本身不复杂，真正吃人力的是 Skins（13,997 行，占 38%）和地图数据（3,440 行），这两块我们可以按需裁剪。

## 1. 目标与范围

既然 NDui 的每个功能你都在用，目标就不是"几个轻量模块"，而是：

> **一套能完整替代 NDui 的自有套件（Core + 10 类模块），外加一个原生的统计面板。**

但要接受两个现实：

1. 我们不需要 1:1 复刻 6.6 万行。**NDui 的 38% 是皮肤、5% 是地图数据**，自研可按需砍到 **9,000–12,000 行**达到"日常够用"。
2. 配置无法从 NDui 迁移（不同的库、不同的 schema），切换是"重新配一遍"的过程，所以路线必须是**并存 → 逐模块切换 → 最后卸载**。

## 2. 分层架构（已被 AzerothKit 0.2.0 实现）

```
AzerothKit.toc
├─ Platform.lua    版本/能力探测（唯一的版本分支点）
├─ Theme.lua       主题令牌 + 控件工厂  ← 统一外观的唯一来源
├─ Core.lua        数据库 / 事件总线 / 模块注册器
├─ UI.lua          主面板（版本、模块开关、能力矩阵）
├─ Diagnostics.lua /ak 命令
└─ Modules\        各功能模块，一个文件一个模块
```

对应 NDui 的映射（只学结构，不抄代码）：

| NDui | 我们的对应物 | 说明 |
| --- | --- | --- |
| `Init.lua` 的 `B:RegisterEvent` | `Core:On(event, fn)` | 集中注册 + `xpcall` 隔离，一个模块崩不拖垮全套 |
| `B:RegisterModule` | `Core:RegisterModule(name, def)` | 多了 `flavors` 与 `defaultEnabled` |
| `Core/Functions.lua` 的 `CreateBD/CreateFS/Reskin*` | `Theme.lua` 的 `ApplyBackdrop/CreatePanel/CreateText/CreateButton/CreateCheckbox` | 统一外观的关键 |
| `Core/GUI.lua`（1,848 行自研配置界面） | 先用手写面板，后续换 `Settings` API | 省 1,800 行 |
| `Core/Mover.lua` | 每个面板自带拖动 + 位置存 DB | 先够用 |
| `Modules\Skins\*` | 可选插件 `AzerothKit_Skins` | 皮肤永远可选，别拖累主包 |

Theme 层的价值在于：**统计面板、背包、信息条、单位框架全部 `T:CreatePanel` 出来，视觉天然一致**——这正是你希望 Details 与 NDui 一致的那种效果，但我们是"同源"，不是"事后 skin"。

## 3. 模块清单：预算、工期、顺序

按"一个人、熟悉 Lua 与 WoW API"估算（人日）：

| 阶段 | 模块 | 预算行数 | 工期 | 风险 | 说明 |
| --- | --- | --- | --- | --- | --- |
| M0 ✅ | Core + Theme + 主面板 + Infobar 示例 | ~900（已完成） | — | — | 框架已跑通 |
| M1 | Tooltip（装等/物品/单位） | 500 | 3–5 | 低 | `TooltipDataProcessor` |
| M1 | Infobar 正式版（金币/耐久/坐标/延迟/帧数/背包格） | 400 | 3–5 | 低 | 纯读取 |
| M1 | Bags（分类/搜索/整理/银行） | 800 | 8–10 | 中 | 容器 API 多 |
| M2 | **Meter（统计面板）** | 1,200 | 10–15 | 中高 | 见第 4 节 |
| M2 | Minimap（按钮收纳/追踪/时钟） | 600 | 5–7 | 中 | |
| M2 | Chat（频道/过滤/复制/超链接） | 700 | 6–8 | 中 | |
| M3 | UnitFrames（基于 oUF 写布局） | 1,500 | 15–20 | 高 | 光环/连击点/载具 |
| M3 | Nameplates（只做外观） | 700 | 8–10 | 高 | 12.x 施法条状态是 secret |
| M4 | ActionBar（先皮肤，后行为） | 600 / 2,000 | 10 / 30 | 很高 | 安全模板、翻页、载具 |
| M4 | Auras（`AuraContainer` 体系） | 500 | 6–8 | 高 | 12.1 新 API |
| M5 | Misc（修理/售卖/邮件/装等/团队工具） | 600 | 5–7 | 中 | |
| 按需 | Skins（每个窗口 0.5–1 天） | 视需求 | — | 低技术高风险人力 | 只 skin 自己常用的 |

合计约 **8,000–9,500 行 / 85–120 人日**（不含大规模皮肤）。这是"日常够用"，不是"NDui 1:1"。

## 4. 统计面板（替代 Details 的核心）

### 4.1 数据从哪来

```lua
-- 会话列表（按类型：0=伤害, 1=治疗 …，具体枚举见 Enum.DamageMeterType）
local sessions = C_DamageMeter.GetAvailableCombatSessions()
local session  = C_DamageMeter.GetCombatSessionFromID(sessionID, index)
-- session = { combatSources = {...}, totalAmount=, maxAmount=, durationSeconds= }
-- 单个来源明细：
C_DamageMeter.GetCombatSessionSourceFromType(type, index, guid, x)
C_DamageMeter.GetSessionDurationSeconds(type)
```

### 4.2 关键设计：战斗中"降级"，不是"破解"

Details 的做法是 `Apocalypse.IsServerInCombat()`：一旦发现 `combatSources[1].name` 是 secret，就停止更新。我们照做，并且更明确地显示状态：

| 场景 | 表现 |
| --- | --- |
| 战斗中 | 标题显示"战斗中（数据受限）"，行数据冻结在上一场，数值显示 `--` |
| 战斗结束（`PLAYER_REGEN_ENABLED`） | 拉取新会话，排序、算占比、算 DPS，刷新 |
| 切换副本/重置 | 监听 `ENCOUNTER_END` / `ZONE_CHANGED_NEW_AREA`，重建列表 |
| 无数据 | 显示"本场无记录" |

### 4.3 面板结构（复用 Theme）

```
┌─ AzerothKit 统计 ────────────────┐
│ 会话: 首领战 #12   时长 3:41      │
│ ─────────────────────────────── │
│ #  玩家            总量      占比 │
│ 1  Xxx            1.2M     32.1% │
│ 2  Yyy            1.0M     27.4% │
│ …                                │
└──────────────────────────────────┘
```

行数固定（首版 8 行，不做滚动），够用且省掉 ScrollBox 的复杂度。配色、边框、字体全部来自 `Theme`，与其它模块一致。

### 4.4 明确不做

- CLEU 解析（已禁）
- 战斗中的实时排行（数据不可读）
- 窗口设计器、时间轴回放、WCL 上传、报告导出（Details 的 5 万行主要花在这）

## 5. 里程碑与验收

| 里程碑 | 内容 | 验收标准（游戏内可验证） |
| --- | --- | --- |
| **M0** ✅ | Core/Theme/主面板/Infobar | `/ak` 打开面板；勾选 Infobar 即时显示/隐藏；`/reload` 后状态保持 |
| M1 | Tooltip + Infobar + Bags | 关闭 NDui 对应模块后，日常操作无缺失 |
| M2 | Meter + Minimap + Chat | 打完一场首领战，面板能列出正确排行 |
| M3 | UFs + Nameplates | 关掉 NDui 后，团队框体/姓名板可用 |
| M4 | ActionBar + Auras | 关掉 NDui 后，能正常打副本 |
| M5 | Misc + Skins | 卸载 NDui，连续玩一周不怀念 |

每个里程碑结束都跑一次 [tools/check.ps1](tools/check.ps1) + 两个客户端的 `/reload` 冒烟测试。

## 6. 与 NDui 并存的迁移策略

1. **并存期**：NDui 与我们同时装，NDui 里逐个关模块（NDui 支持模块级开关），我们的模块逐个补上。
2. **冲突期**：同名功能的框架会重叠（比如两个顶部信息条）。用 `/ak toggle Infobar` 临时关掉我们的，避免视觉打架。
3. **切换期**：确认某模块稳定后，关掉 NDui 对应模块；不要一次全关。
4. **卸载期**：NDui 全部模块关闭并观察一周后，再物理删除。
5. **配置**：无法导入，建议把 NDui 的关键设置（框体尺寸、字体、颜色）截图存档，迁移时照着重配。

## 7. 风险清单

| 风险 | 影响 | 应对 |
| --- | --- | --- |
| 暴雪再收紧 API（12.2/13.0） | 某些模块直接失效 | 所有判断走 `Platform.HasAPI`，功能可关 |
| 无限客户端版本号/接口变动 | 插件被标记过期 | 每次补丁跑 `check.ps1`，多 Interface 声明 |
| 安全模板（动作条）踩污染 | 战斗中报错 | 动作条先只做皮肤，行为交给 Blizzard |
| 工作量低估 | 半途而废 | 按 M1→M5 交付，每个里程碑都能独立上线 |
| 皮肤需求膨胀 | 吃掉 40% 工时 | 皮肤独立插件，按需加载，绝不进主包 |

## 8. 现在就能做的三件事

1. 进游戏 `/reload`，`/ak` 打开面板，确认 Infobar 模块能勾选/取消、位置可拖、`/reload` 后保持——**先验证内核**。
2. 选 M1 的第一个模块（建议 Tooltip，3–5 天），我按 `Modules\Tooltip.lua` 的形态写出来。
3. 给 `Theme` 定一套你自己的视觉（颜色、字体、边框材质），越早定，后面 10 个模块越省事。
