# 06 · 路线图、验证清单与待确认问题

## 1. 分阶段路线

### 阶段 0 · 环境（本次已完成 80%）

- [x] 摸清三个客户端、版本号、Interface、本机路径
- [x] 写出双版本示例插件 `addon/AzerothKit`
- [x] 目录联接部署脚本 + TOC 校验脚本
- [ ] VS Code + Lua Language Server（可选，需另装）
- [ ] `git init` 并把本目录纳入版本管理
- [ ] 注册 CurseForge / Wago 项目（要发布时再做）

### 阶段 1 · 只读信息类（低风险，建议从这里开始）

两个客户端都能做，不碰战斗数值，练手同时能出成品：

| 方向 | 用到的 API | 备注 |
| --- | --- | --- |
| 背包/银行/供应商增强 | `C_Container.*`、`C_MerchantFrame.*` | 纯读取 + 排序显示 |
| 鼠标提示增强 | `C_TooltipInfo.*`、`TooltipDataProcessor` | 12.x 推荐 `TooltipDataProcessor.AddTooltipPostCall` |
| 地图标点/路线 | `C_Map.SetUserWaypoint`、`C_Map.GetMapInfo` | 别用超远追踪那个受保护调用 |
| 任务日志整理 | `C_QuestLog.*`、`C_TaskQuest.*` | 无限的新大陆任务会需要 |
| 专业/配方清单 | `C_TradeSkillUI.*` | |
| 聊天增强 | `C_ChatInfo.*`、`ChatFrame_AddMessageEventFilter` | 注意 12.x 的聊天限制 |

### 阶段 2 · 显示层美化（中风险）

| 方向 | 说明 |
| --- | --- |
| 姓名板皮肤 | 只改外观，不读施法条状态（那可能是 secret 布尔） |
| 单位框架皮肤 | 想显示血量就 `StatusBar:SetValue(UnitHealth(u))` 透传，别自己算百分比 |
| 小地图/任务追踪外观 | |
| 冷却图标外观 | 用 `Cooldown:SetCooldownFromDurationObject` |

### 阶段 3 · 战斗相关（高风险，只消费官方管道）

| 方向 | 可行性 | 说明 |
| --- | --- | --- |
| 伤害/治疗统计展示 | ⚠️ 有限 | 只能读 `C_DamageMeter` 的会话聚合，且官方内置统计已覆盖大部分需求 |
| 首领技能计时 | ⚠️ 有限 | 参考 DBM 的做法：官方 encounter 事件 + 预置时间轴，不做 CLEU 解析 |
| 冷却查看器皮肤 | ✅ | `C_CooldownViewer.*` + 只读元数据 |
| 触发/优先级提示 | ❌ | 这正是暴雪要挡的"替你决策" |
| 自动打断/自动循环 | ❌ 违规 | |

### 无限专属的机会（差异化）

- **露营系统**：营地设施、共享建造状态的界面增强。
- **传承系统**（账号级成长）：账号维度的进度面板、跨角色汇总。
- **新大陆内容**：泽风岛、海加尔山、Riverglades 等新地图的任务/采集路线。
- **经典/强化双预设**：为"经典外观党"做像素级还原的 UI 套件。

这些是正式服没有的需求，竞争也少。

## 2. 明确不做的清单

- 解析战斗日志（CLEU 已禁）
- 基于战斗数值的自动决策（输出循环、自动打断、自动保命）
- 内存读取、注入、模拟输入、多开同步
- 绕过暴雪的保护帧/安全模板

## 3. 游戏内验证命令（复制即用）

```lua
-- 版本与产品线
/run local v,b,d,t=GetBuildInfo(); print(v,b,t,WOW_PROJECT_ID, WOW_PROJECT_CAMELOT)

-- 机密值体系是否存在
/run print("secrets:", type(issecretvalue), type(canaccessvalue), type(C_Secrets))

-- 生命值是不是 secret（战斗中再跑一次对比）
/run local h=UnitHealth("player"); print(type(h), issecretvalue and issecretvalue(h))

-- 机密值不能做算术（预期 pcall 返回 false）
/run local h=UnitHealth("player"); print(pcall(function() return h+1 end))

-- 冷却显示管线
/run print(type(C_Spell.GetSpellCooldownDuration), type(C_ActionBar.GetActionCooldownDuration))

-- 官方伤害统计接口
/run print(type(C_DamageMeter), C_DamageMeter and type(C_DamageMeter.GetAvailableCombatSessions))

-- 光环是否被隐藏（战斗中应为 true）
/run print(C_Secrets and C_Secrets.ShouldAurasBeSecret and C_Secrets.ShouldAurasBeSecret())

-- 插件抽屉是否可用
/run print(type(AddonCompartmentFrame))

-- 设置面板 API
/run print(type(Settings), Settings and type(Settings.RegisterAddOnCategory))

-- 当前 UI 家族线索
/run print(GetLocale(), select(4, GetBuildInfo()), LE_EXPANSION_LEVEL_CURRENT)
```

把结果记到 `docs/03` 的表格里，就是你自己客户端的"能力基线"。

## 4. 待确认问题（进游戏逐个回答）

| # | 问题 | 验证方式 |
| --- | --- | --- |
| Q1 | 无限 1.60.1 是否真的禁止 CLEU？ | 用 `/run` 试注册，**会报错就别再试**；或读 DBM/Details 的无限分支 |
| Q2 | 无限上 `UnitHealth("player")` 在战斗中是否 secret？ | 上面第 3/4 条命令，战斗内外各跑一次 |
| Q3 | 无限上 `GetUnitName` 与 `UnitName` 的差别？ | 两者都跑，比较返回值与 secret 状态 |
| Q4 | 无限的 `C_DamageMeter` 是否完整可用？ | `type(C_DamageMeter.GetAvailableCombatSessions)` |
| Q5 | 无限的 AddonCompartment 是否显示条目？ | 装好 AzerothKit 后看小地图旁的抽屉 |
| Q6 | 12.1.5 下光环读取的实际报错形态？ | 战斗中 `C_UnitAuras.GetAuraDataByIndex` 包 pcall |
| Q7 | 中文客户端下 Interface 与英文是否一致？ | `select(4, GetBuildInfo())`（国服同版本号） |
| Q8 | 无限下次小版本会不会改 Interface？ | 关注 `.build.info` 与 `check.ps1` 输出 |

## 5. 每周/每补丁例行

1. 跑 `tools/check.ps1`，确认 TOC Interface 跟上了客户端。
2. 进两个客户端各 `/reload` 一次，看 `Logs\` 有没有新报错。
3. 看 [Warcraft Wiki API changes](https://warcraft.wiki.gg/wiki/API_change_summaries) 有没有新补丁条目。
4. 对比 `Gethe/wow-ui-source` 的 `forever` 分支与 `12.x` 分支的差异（尤其是 `Blizzard_APIDocumentation`）。
5. 更新 `docs/03` 的版本时间线。

## 6. 交付物清单

| 文件 | 用途 |
| --- | --- |
| `addon/AzerothKit/` | 可运行示例，`/ak` 命令 + 自检面板 |
| `tools/deploy.ps1` | 一键挂载/卸载到两个客户端 |
| `tools/check.ps1` | TOC 版本校验 + Lua 语法检查 |
| `docs/01`–`docs/06` | 调研与规范 |

下一步最划算的动作：**把阶段 1 的"背包/银行增强"做成第一个真插件**——它两个客户端通用、不碰机密值、能在一天内跑通完整发布链路（打包、上架、收反馈）。
