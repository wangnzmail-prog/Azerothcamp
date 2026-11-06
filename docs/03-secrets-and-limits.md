# 03 · 机密值体系：12.x 的能力边界（正式服与无限同源）

这是决定"什么插件能做、什么做不了"的一篇。2026-03-02 上线的 12.0（Midnight）是暴雪对插件能力最大的一次收紧，无限客户端继承同一套机制。

## 1. 两条硬规则

**规则一：战斗日志没了。**
12.0 起，注册 `COMBAT_LOG_EVENT` / `COMBAT_LOG_EVENT_UNFILTERED` **直接抛 Lua 错误**（Warcraft Wiki 12.0.0 API changes 原文：*"COMBAT_LOG_EVENT and COMBAT_LOG_EVENT_UNFILTERED will error when trying to register them"*）。

替代品是官方伤害统计接口 `C_DamageMeter`（`GetAvailableCombatSessions` / `GetCombatSessionFromID` / `GetCombatSessionFromType` / `GetSessionDurationSeconds` 等），提供**会话级**聚合数据，而不是逐条事件流。

**规则二：战斗数值变成"机密值"（secret value）。**
`UnitHealth`、`UnitPower`、冷却、光环、施法信息等在受限场景下返回 secret。它仍然有真实类型（`type()` 返回 `number`），但你**不能对它做大部分 Lua 操作**。

## 2. 机密值能做什么、不能做什么

| 操作 | 允许？ | 说明 |
| --- | --- | --- |
| 存进变量/表字段 | ✅ | |
| 作为参数传给函数 | ✅ | 但目标 C 函数必须显式声明接受 secret |
| 字符串拼接、`string.format` | ✅ | 仅限 string/number 类型的 secret |
| `type()` | ✅ | 返回真实类型 |
| `issecretvalue(v)` | ✅ | 判定是否机密 |
| 算术（`+ - * /`） | ❌ | 立即 Lua 错误 |
| 比较（`< > ==`） | ❌ | 立即 Lua 错误 |
| 布尔判断（`if v then`） | ❌（boolean 类型） | 例外：非 boolean 的 secret 恒为真 |
| 长度 `#` | ❌ | |
| 作为表键 | ❌ | 还会把整张表标记为"含机密键" |
| 索引/赋值 `v.x` | ❌ | |
| 当作函数调用 | ❌ | |
| 直接 `print` 出来 | ⚠️ | 无限客户端上打印 secret 会抛错，先 `issecretvalue` 再决定 |

表还有两个额外概念：`issecrettable()` / `canaccesstable()`，以及"禁止访问的表"（一索引就报错）。

## 3. 判断"现在是不是受限"的官方 API

### `C_Secrets`（谓词，返回普通布尔，可在战斗中安全调用）

| 函数 | 用途 |
| --- | --- |
| `C_Secrets.HasSecretRestrictions()` | 系统总开关，正式服世界里基线就是 true，别当"是否战斗中"用 |
| `C_Secrets.ShouldAurasBeSecret()` | **实时**：光环数据是否在被隐藏（战斗开始翻 true） |
| `C_Secrets.ShouldCooldownsBeSecret()` | **实时**：冷却是否被隐藏 |
| `C_Secrets.ShouldUnitHealthMaxBeSecret(unit)` | 最大生命值是否机密（实测恒 false） |
| `C_Secrets.ShouldUnitPowerBeSecret(unit[, type])` | 按资源类型粒度判断 |
| `C_Secrets.ShouldUnitIdentityBeSecret(unit)` | 单位身份是否机密（副本战斗中为 true） |
| `C_Secrets.ShouldUnitAuraIndexBeSecret(unit, index, filter)` | 逐条光环判断 |
| `C_Secrets.ShouldSpellCooldownBeSecret(spellID)` | 逐法术冷却判断 |

### `C_RestrictedActions`

`C_RestrictedActions.IsAddOnRestrictionActive(type)`，`type` 取值：`0` 战斗、`1` 首领战、`2` 挑战模式、`3` PvP 对局、`4` 地图、`5` 聊天。

## 4. 显示管线：允许"透传"，不允许"读懂"

暴雪的态度很清楚：**样式可以自定义，判断不可以**。因此提供了一批"接受 secret 的 UI 接口"，让插件把值原样喂给控件：

| 接口 | 用途 |
| --- | --- |
| `StatusBar:SetValue(secretNumber)` | 血条/进度条直接显示 |
| `Cooldown:SetCooldownFromDurationObject(dur)` | 用 `C_Spell.GetSpellCooldownDuration()` 返回的不透明对象画转圈 |
| `Cooldown:SetCooldownFromExpirationTime(start, duration)` | 接受 secret 的冷却绘制 |
| `SetAlphaFromBoolean(secretBool, a, b)` | 机密布尔 → 透明度（做发光/高亮） |
| `C_StringUtil.TruncateWhenZero(v)` | 可能为 secret 的数字转文本 |
| `C_CurveUtil.*` / `ColorCurve` | 机密值 → 颜色/曲线 |

反面教材：`StatusBar:GetValue()`、`texture:GetTexCoord()` 在血量机密时同样返回 secret，**想"读回来再算百分比"这条路是堵死的**。

## 5. 版本演进（重要时间线）

| 版本 | 变化 |
| --- | --- |
| 12.0.0（2026-03-02） | 机密值体系上线；CLEU 禁止注册；`C_DamageMeter`、`C_Secrets`、`C_RestrictedActions` 命名空间；战斗日志类插件模式终结 |
| 12.0.5 / 12.0.7 | 逐法术白名单逐步放开（`C_Secrets.GetSpellAuraSecrecy` 可按法术区分）；`SecretOnRestrictedMaps` 等新谓词 |
| 12.1.0（2026-08-11） | **光环进一步收紧**：`C_UnitAuras.GetAuraDataByIndex` / `GetUnitAuras` 在受限上下文直接抛错（`RequiresUnitAuraAccess`，FailureMode = Error）；新增 `AuraContainer` / `AuraButton` 体系 |
| 12.1.5（当前正式服） | 新增 `SecretWhenLuaTableHasSecretKeys`、`RequiresTimedSignalMapAccess`；血条/文本的 secret 方面继续细化 |

## 6. 无限（Forever）的情况

社区实测与客户端文件都指向同一结论：**无限 = Mainline 家族的 UI/API，只是世界内容是 60 级**。

- `WOW_PROJECT_CAMELOT = 18`，`WOW_PROJECT_ID = 18`（1.60.1 起）。
- 有 `issecretvalue` 等整套机密值 API；`UnitHealth("player")` 在战斗中返回 secret（社区在 69913 上实测 `pcall(function() return h + 1 end)` 返回 false）。
- 战斗日志：社区报告"不可用"；DBM/Details 的无限分支都按"无 CLEU"处理（Details 的 `Details_Camelot.toc` 加载的是 `core\parser_nocleu.xml`）。
- 12.1.0 的 `AuraContainer` / `AuraButton` 在无限上同样可用（暴雪明示后续 UI 改动会同时落到 Standard 与 Forever）。
- 官方常量文件位于 `Gethe/wow-ui-source` 的 `forever` 分支，可直接对照。

> 注意：这是**快速演进的客户端**。1.60.1 是首发版本，后续每个小补丁都可能改变具体函数的受限状态。所有结论都要以"当前 build 的实测"为准。

## 7. 由此推出的设计原则

1. **只做展示，不做决策**。能显示的数据就显示，不要试图反推战斗逻辑。
2. **能力探测优先于版本判断**。不要写 `if toc >= 120000 then` 去猜，直接 `type(C_DamageMeter) == "table"`。
3. **失败要降级，不要崩**。每个读取机密值的点都准备 fallback（显示 `--`、隐藏模块、退回静态文本）。
4. **不要用 `pcall` 当"处理好了"**。受保护动作被拒可能是静默且粘滞的；`pcall` 只适合包裹"探测型调用"。
5. **永不做的事**：注册 CLEU、解析战斗日志、基于血量阈值自动施法、读内存、模拟输入。

参考资料：

- [Warcraft Wiki: It's Secret（机密值规则全文）](https://warcraft.wiki.gg/wiki/Secret_Values)
- [Warcraft Wiki: Patch 12.0.0 API changes](https://warcraft.wiki.gg/wiki/Patch_12.0.0/API_changes)
- [WoW Forever Addon Patterns（社区实测与迁移建议）](https://wowforeverguides.com/addons/patterns)
- [JustAC 12.0 兼容性分析（逐 API 的 secret 实测矩阵）](https://github.com/wealdly/justac/blob/main/Documentation/12.0_COMPATIBILITY.md)
