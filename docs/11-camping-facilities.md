# 11 · 露营设施清单（38–39 件）与数据来源

用途：把面板从"三个固定物品"升级为"按设施表扫描背包"，并为小队去重提供设施 key。
名称/效果来自社区资料汇总；**itemID 与 buff spellID 需游戏内采集**（见 docs/10 的方法）。

## 数据来源

- WoW Forever Camping: All 38 Campsite Objects — https://wow-forever.online/camping/
- Wowhead: What Camping Buffs Can You Get — https://www.wowhead.com/tw/news/what-camping-buffs-can-you-get-in-wow-forever-383027
- NGA: 39 种设施谱系全景实测 — https://ngabbs.com/read.php?tid=47604866
- Mobalytics Camping Guide — https://mobalytics.gg/wow-forever/guides/camping-guide

## 规则

- 每个专业 3 阶（技能 20 / 140 / 300）；一阶只给 buff，二阶叠加功能（铁砧/修理/温室/矿点/鱼架）。
- **帐篷只有 2 件**：资深冒险者的探险帐篷（玩具，+20% 经验累积）、营地帐篷（制皮，+5%），并且额外给**随机一种 buff**。
- 其它设施：**一种固定 buff**，无经验加成。
- 所有营地制品共享同一个 1 小时冷却，表现为 debuff `强化休息 1229451`。
- 营地容量：基础营火 3 / 熟练营火 5 / 专家营火 10 个设施。

## 设施 → buff 对照（一阶）

| 专业 | 设施 | 主要效果 |
| --- | --- | --- |
| 炼金 | 法力之泉 Mana Well | 法力回复 |
| 锻造 | 磨刀轮 Sharpening Wheel | 力量 |
| 锻造(二阶) | 铁砧 Anvil | 保留力量 + 提供铁砧 |
| 采矿 | 磁石 Lodestone | 近战攻强 |
| 采矿(二阶) | 岩石花园 Rock Garden | 保留攻强 + 矿点 |
| 草药 | 香烛 Incense Candle | 智力 |
| 草药(二阶) | 温室 Greenhouse | 保留智力 + 种草药 |
| 制皮 | 露营椅 Camp Chair | 2% 暴击 |
| 制皮 | 营地帐篷 Camp Tent | **+5% 经验累积 + 随机 buff** |
| 裁缝 | 阵营旗帜 Faction Banner | 精神 |
| 附魔 | 魔法鲁特琴 Enchanted Lute | 护甲/属性/抗性 |
| 工程 | 试剂机器人 Reagent Bot | 试剂商 |
| 工程(二阶) | 修理机器人 Repair Bot | 保留商人 + 修理 |
| 急救 | 急救包 First Aid Kit | 耐力 |
| 钓鱼 | 鱼缸 Fish Bowl | 8% 属性 |
| 钓鱼(二阶) | 鱼架 Fishing Rack | 保留属性 + 稀有鱼 |
| 烹饪 | 饼干盛宴 Cookie's Feast | 耐力食物（需 140 烹饪） |
| 烹饪 | 基础/熟练/专家营火工具包 | 决定可放设施数量（3/5/10） |

## 待补（游戏内采）

- 每件设施的 itemID（背包扫描即可）
- 每条 buff 的 spellID 与显示名（`/ak camp` 的 aura dump 能拿到）
- 三阶设施（Master Forge / Iron Oven 等）的完整名单