# 01 · 三条产品线与插件生态现状

## 1. 《魔兽世界：无限》到底是什么

不是私服，不是怀旧服的赛季，而是暴雪在正式服、怀旧服之外开辟的**第三条长期并行产品线**：

- 2026-11-05 07:00（北京时间）全球同步上线，国服同刻开服；战网游戏版本列表里是独立一项。
- 门槛：账号有《魔兽世界》游戏时间即可进入，**不需要另买游戏本体**（礼包只提供额外内容）。
- 世界观：从 60 级经典艾泽拉斯出发，但**不打开黑暗之门**，走一条"如果当年没进外域"的平行时间线。
- 等级永久封顶 60，不追装等阶梯；首个团队副本 2026-12-10 开放。
- 新内容举例：新种族"天裔精灵"与泽风岛起始剧情、**露营系统**（营火可共建专业设施）、账号级**传承系统**。
- 首次进入可选"经典 / 强化"两种体验预设：强化预设默认开高清模型、任务关注点与现代界面。
- 国服由网易（雷火）运营，开服前因 128 元补给包 / 888 元年卡（帐篷休息经验 4 倍）有过付费争议。

英文社区把这条产品线叫 **WoW Forever**（客户端产品名 `wowf`），客户端内部代号 **Camelot**——这是插件开发里最关键的一个词。

## 2. 三个客户端并排看

| | 正式服 | 无限 | 经典旧世 / 时光服 |
| --- | --- | --- | --- |
| 战网条目 | World of Warcraft | World of Warcraft: Forever | Classic 系列 |
| 目录 | `_retail_` | `_forever_` | `_classic_era_` / `_classic_titan_` |
| 产品名（`.build.info`） | `wow` | `wowf` | `wow_classic` / `wow_classic_titan` |
| 本机版本 | 12.1.5.70783 | 1.60.1.70790 | 3.80.2.70522 |
| Interface | 120105 | 16001 | 11509（Era）/ 38002（时光） |
| `WOW_PROJECT_ID` | 1 | 18 | 2（Era）/ 各资料片不同 |
| Lua 全局环境 | Mainline 12.x | Mainline 家族（12.x 同代） | Classic |
| 战斗数值 | 战斗中机密 | 战斗/受限场景机密 | 明文 |

`WOW_PROJECT_CAMELOT = 18` 来自 Blizzard 自己的常量文件（`Gethe/wow-ui-source` 的 `forever` 分支）：

```lua
WOW_PROJECT_CAMELOT = 18;
WOW_PROJECT_ID = WOW_PROJECT_CAMELOT;
```

早期测试 build（69913）曾把无限报成 `1`（和正式服一样），70338 之后稳定为 18。所以**版本判定要"命名常量 + 能力探测"双保险**，不能只看数字。

## 3. 本机实况

安装根目录 `E:\Program Files\Blizzard Games\World of Warcraft`：

```
.build.info          四个产品条目：wow 12.1.5 / wow_classic_titan 3.80.2 / wowf 1.60.1
_retail_             正式服，已装 DBM 12.1.19 / Details 20261104 / NDui / SexyMap
_forever_            无限，已装 DBM / Details / NDui
_classic_titan_      时光服，装同上
_cn_beta_            国服测试客户端（本次未展开）
字体更改/             本地字体替换工具目录
```

已装插件本身就是最好的"兼容性样本"：

- `DBM-Core.toc` 用**单文件多 Interface**写法，一行列了 9 个版本号：
  `## Interface: 11509, 16001, 20506, 30405, 38002, 40402, 50504, 120105, 120107`
- `Details` 用**按 flavor 分 TOC**写法：`Details.toc`(120105)、`Details_Camelot.toc`(16001)、`Details_Classic.toc`(11509)……
- 两者都证明"一套代码同时服务正式服与无限"在生产上是可行的、且已在跑。

## 4. 插件生态现状（社区）

- **DBM / Details / NDui / Questie** 已发布支持无限的版本（Questie 发布说明里把 "Forever client support" 列为新特性）。
- **WeakAuras 已停止开发**（社区报道，发生在 Midnight 之前），经典 WA 字符串不要指望能直接迁移。
- **伤害统计类插件被官方取代**：12.x 内置伤害统计，通过 `C_DamageMeter` 暴露"会话级"数据；第三方统计只能消费这条管道。
- 社区已出现针对无限的专门资料站与工具（如 `wowforeverguides.com` 的 addon 指南、`forever-lint` 这类针对无限客户端 API 的 linter）。

## 5. 合规边界（做插件前必须知道）

- 暴雪允许 UI/信息展示类插件；**禁止**自动化操作、脚本代打、读取未公开的服务器数据、绕过客户端保护。
- 12.x 的一系列限制（机密值、禁止 CLEU、限制光环访问）本质就是"把'替你决策'挡在门外"，顺着这个方向做的插件才活得久。
- 无限对多开、脚本、破坏经济的行为有官方巡查；插件若被判定为自动化工具，风险由使用者承担。

参考资料：

- [17173：无限 11 月 5 日上线](https://news.17173.com/content/11042026/174623011.shtml)
- [17173：全球上线，等级永久 60](https://news.17173.com/content/11052026/083049483.shtml)
- [Warcraft Wiki: World of Warcraft: Forever](https://warcraft.wiki.gg/wiki/World_of_Warcraft:_Forever)
- [Gethe/wow-ui-source `forever` 分支](https://github.com/Gethe/wow-ui-source/tree/forever)
