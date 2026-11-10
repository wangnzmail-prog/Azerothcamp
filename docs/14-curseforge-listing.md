# 14 · CurseForge 上架清单与文案

## 一、上架前必须填的三处

| 位置 | 内容 | 何时填 |
| --- | --- | --- |
| `AzerothCamp.toc` | `## X-Curse-Project-ID: <id>` | 建项目后，从项目页 URL 里取数字 |
| CurseForge 项目设置 | 游戏版本**只勾 1.60.1**（WoW Forever）——正式服无露营系统 | 建项目时 |
| 项目设置 | 分类：**Addons → Utility**（或 Camping，若分类可用） | 建项目时 |

TOC 里已留注释占位：`# X-Curse-Project-ID: fill-after-create`。

## 二、英文描述（主语言）

**Summary (short, <200 chars):**

> Camping assistant for WoW Forever: campfire kits, tents, all profession camp items by itemID, the shared 1-hour cooldown, camp capacity, and party sync.

**Description:**

```
AzerothCamp — camping, without the guesswork.

WHAT IT DOES
• Campfire kits: shows how many Basic / Journeyman / Expert kits you carry; falls back to Flint and Tinder, and crafts a kit when you have Simple Wood.
• Tents: the Expedition Tent toy (+20% rested XP) and the Leatherworking Camp Tent (+5%) are tracked separately, each with its own state.
• Camp items: all 12 professions' camp objects are recognised by itemID — not by name — so it works on every client language.
• Shared cooldown: reads the "Boosted Rest" debuff, the single 1-hour cooldown shared by every camp object, and shows it once instead of once per item.
• Camp capacity: remembers the campfire tier you placed (3 / 5 / 10 slots) and syncs the highest known value across your party.
• Party sync: broadcasts "what I can place, how long my cooldown is" over an addon channel, so your group stops placing duplicates.
• Quality of life: draggable, collapsible (grows downward), hides in combat, version label for support.

COMMANDS
/ac camp      scan bags, auras and recipes
/ac group     broadcast and print party camping state
/ac errors    show the last recorded Lua errors

NOTES
• Built for WoW Forever 1.60.1 only — Retail has no camping system.
• Localised in English, 简体中文 and 繁體中文, following your game language.
• If AzerothKit is installed, this addon stays inactive and the suite provides the same panel.
• Party sync only sees players who also run AzerothCamp — the game does not expose other players' bags or cooldowns.
```

## 三、简体中文描述

**摘要：**

> 《魔兽世界：无限》露营助手：营火工具包、帐篷、12 专业营地制品（按 itemID 识别）、共享 1 小时冷却、营火容量与小队同步。

**正文：**

```
AzerothCamp —— 露营不用再猜。

功能
• 营火工具包：显示基础/熟练/专家工具包数量；没有时显示燧石和火绒，有普通木柴可直接制造。
• 帐篷：资深冒险者的探险帐篷（+20% 休息经验）与制皮营地帐篷（+5%）分行显示，各自判定。
• 营地制品：12 个专业的营地制品全部按 itemID 识别，不依赖名字，任何语言的客户端都能用。
• 共享冷却：读取「强化休息」debuff，这是所有营地制品共享的唯一 1 小时冷却，只显示一次。
• 营火容量：记录你放的营火等级（3/5/10 格），小队内取已知最大值。
• 小队同步：广播「我能放什么、冷却剩多久」，避免队友重复放置。
• 使用体验：可拖动、可折叠（只向下生长）、战斗中自动隐藏、底部显示版本号。

命令
/ac camp      扫描背包、光环与配方
/ac group     广播并打印小队露营状态
/ac errors    查看最近的 Lua 报错

说明
• 仅支持《魔兽世界：无限》1.60.1——正式服没有露营系统。
• 简体中文 / 繁體中文 / English，跟随游戏语言。
• 若已安装 AzerothKit，本插件自动让位，功能由套件提供。
• 小队同步只对同样安装本插件的玩家生效——游戏不向插件暴露他人背包与冷却。
```

## 四、繁體中文描述

**摘要：**

> 《魔獸世界：無限》露營助手：營火工具包、帳篷、12 專業營地製品（依 itemID 辨識）、共用 1 小時冷卻、營火容量與小隊同步。

**正文：**

```
AzerothCamp —— 露營不用再猜。

功能
• 營火工具包：顯示基礎／熟練／專家工具包數量；沒有時顯示燧石和火絨，有普通木柴可直接製作。
• 帳篷：資深冒險者的探險帳篷（+20% 休息經驗）與製皮營地帳篷（+5%）分行顯示，各自判定。
• 營地製品：12 個專業的營地製品全部依 itemID 辨識，不依賴名稱，任何語言的客戶端都能用。
• 共用冷卻：讀取「強化休息」debuff，這是所有營地製品共用的唯一 1 小時冷卻，只顯示一次。
• 營火容量：記錄你放的營火等級（3/5/10 格），小隊內取已知最大值。
• 小隊同步：廣播「我能放什麼、冷卻剩多久」，避免隊友重複放置。
• 使用體驗：可拖曳、可摺疊（只向下展開）、戰鬥中自動隱藏、底部顯示版本號。

指令
/ac camp      掃描背包、光環與配方
/ac group     廣播並列印小隊露營狀態
/ac errors    查看最近的 Lua 錯誤

說明
• 僅支援《魔獸世界：無限》1.60.1——正式服沒有露營系統。
• 繁體中文／简体中文／English，跟隨遊戲語言。
• 若已安裝 AzerothKit，本插件自動讓位，功能由套件提供。
• 小隊同步只對同樣安裝本插件的玩家生效——遊戲不向插件揭露他人背包與冷卻。
```

## 五、截图清单（3 张就够）

| # | 内容 | 要点 |
| --- | --- | --- |
| 1 | **折叠态**：标题栏 + `E G R -` 四个按钮 + 底部版本号 | 展示"不占屏" |
| 2 | **展开态**：营火工具包、两行帐篷、营地制品、营火行（带容量）、光环行 | 展示主要功能 |
| 3 | **小队露营区**：队友的 `名字 / 可放类型 / 冷却` | 展示同步（可用两人截图） |

截图要求：默认 UI 比例、无多余插件、窗口背景干净，PNG。

## 六、上传流程

```powershell
# 1) 出包（当前版本号）
powershell -ExecutionPolicy Bypass -File tools\build-standalone.ps1 -Version 0.16.1

# 2) 检查包结构
#    应为 AzerothCamp\*.lua + AzerothCamp.toc + LICENSE + README.md

# 3) 上传 dist\AzerothCamp-0.16.1.zip
#    上传后在项目页把 Release 标记为支持 1.60.1 与 12.1.5
```

## 七、审核常见退回原因（自查）

- [ ] zip 根目录直接是 `.toc`（**错**）而不是 `AzerothCamp/`（**对**）
- [ ] `## Interface` 与所选游戏版本不匹配
- [ ] 描述为空或只有一句"a camping addon"
- [ ] 缺少 LICENSE
- [ ] 混淆/压缩过的 Lua
- [ ] 使用他人美术资源（我们只用游戏内置贴图路径）
