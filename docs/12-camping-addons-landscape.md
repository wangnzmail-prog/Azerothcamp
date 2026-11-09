# 12 · 永恒服露营插件生态调研（交给生产 Agent 的参考）

用途：AzerothKit 露营模块动手前，先看清 CurseForge 上已经有什么、做到什么程度、还缺什么。
配套阅读：`docs/10-forever-camping-ids.md`（实测 ID）、`docs/11-camping-facilities.md`（38–39 件设施表）。

## 0. 采样方式与可信度

- 采样时间：**2026-11-10**，目标站点 `https://www.curseforge.com/wow`。
- `curseforge.com` 对非浏览器客户端返回 **HTTP 403（Cloudflare "Just a moment..."）**，所以元数据改从两个 CurseForge 镜像取：
  - `https://api.cfwidget.com/wow/addons/<slug>` —— 项目 id、下载量、**逐文件版本号与上传时间**（可用来确认真的是给 1.60.1 做的）；
  - `https://addon-radar.com/forever/categories/camping` —— CurseForge 分类镜像，`category=11739` 即 Camping。
- 下文数字均为上述来源的**精确值或列表页四舍五入值**，已在表内标注；插件功能描述来自作者自述，未逐个实测。
- 结论的置信度：**“存在哪些插件、各自动作什么”高**；**“各插件实现细节”中**（只有 Happy Camper / Camping Kit / Camping Companion 拿到了完整正文）。

## 1. 生态总览

| 指标 | 数值 |
| --- | --- |
| Camping 分类插件数 | **102**（CurseForge 分类 id 11739） |
| 文件版本 | 抽样的头部插件**全部只发 `1.60.1`**，无一支持零售/经典旧世 |
| 头部集中度 | 仅 1 个过 1 万下载（Happy Camper ≈16.8K）；>5K 的共 4 个；其余大量两位数下载 |
| 质量 | 长尾里混有大量一日产物，甚至有作者自述 “ai-slop addon” |
| 语言 | 头部基本英文；**只有 Happy Camper 明确列出简体中文** |

一句话：**分类很挤，但成熟度很低**。这是好事——需求已被验证，但没人做出“能长期用”的那一个。

## 2. 头部产品解剖（按下载量）

### Happy Camper（Torridon，16,827 下载，最新 1.1.1 / 2026-11-09）
覆盖面最广的一个，几乎把“露营”做成了一个社交系统：

- 地图/小地图显示**其他装了本插件的人**烤过的营火，带剩余燃烧时间、已放物件、按你等级算出的 buff、是否同一位面；
- 聊天里贴出的营火（含其他工具发的）也会以灰显形式进来，直到有人实地烤过；
- **按 buff 筛选营地**（自选 buff，或 近战/法系/均衡 一键方案）；被职业 buff 覆盖的物件会标出来（不叠加）；
- Camp 页：自身阵营 buff、每件物件给什么、持续多久、营地还缺什么；到期前提醒、物件冷却好了也提醒；
- **Camp Builder**：发“我要这些 buff + 集合点”的请求，附近能补的人收到提示并报名；
- **Group 页**：小队/团队营地规划——谁带哪件、哪些 buff 已被职业 buff 覆盖，一键 近战/法系/均衡 方案；队长指派“谁放什么”，被指派者看到 “Your job” + 放置按钮；开打前检查谁还没吃到营地 buff（只提示自己）；
- 快捷栏：营火包、营地物件、睡袋、食物、药水、武器 buff，全部带计时和键位；
- 手册（Handbook）：每件营地的产出、怎么做、**配方在哪掉**；
- 营地 BGM、徽章、隐藏歌曲、设置备份码；
- 多语言：英/德/法/西/葡/**简中**/韩/波。
- **许可证：保留所有权利，允许游玩使用，禁止复制、修改、再分发**。

> 对 AzerothKit 的意义：它的 **Group 页 + Handbook** 就是 `docs/11` 设施表和“小队去重”的成品形态，直接当需求清单读。但**代码和素材一行都不能抄**。

### Camping Kit（Shuklock，7,207 下载，最新 v1.8 / 2026-11-06）
把“烤火前的准备”做成一个帐篷图标：

- 点开帐篷，周围扇形展开：4 个自选槽（食物/饮料/武器 buff）、下方一行（钓鱼 + 急救营地物件、营火包、两个专业的物件）、底部睡袋；
- 每件下面一个小按钮**直接打开对应专业窗口**（营火下是烹饪）；自动识别你的专业，每槽默认用你带的最高级别版本，右键可换；
- Camp Benefits 与 Well Fed 计时，缺了就灰掉 + 边框发光；悬停 Camp Benefits 看具体条目；
- 武器 buff：磨刀石/平衡石/油/毒分别适配哪些武器、剩余时间、空着时发光；
- 地图/小地图看本区域别人放下的营地；
- **战斗中整套隐藏**（露营不能战斗中做，这个处理值得学）；
- 键位、小地图按钮、`/ck` 设置。

> 意义：交互密度和“专业窗口直达”这两点，比 AzerothKit 现在的面板更省点击。

### CozyFire（Synse，≈10.0K）
自动在地图标记营火 + 给营地物件加 tooltip（buff 数值和所属专业）。功能最窄，但**“tooltip 里给准确数值”是被验证过的刚需**。

### Wayfarer's Rest（ArcAnvil，≈5.2K）
营地窗口：专业贡献、配方材料、玩家 buff、可带路点的定位报告、可移动窗口 + 自定义美术 + 会话诊断。

### Camping Companion（Monan2k，63 下载，2026-10-17，1.0.1）
**功能设计上离 AzerothKit 最近的一个**，虽然几乎没人用：

- kit bar 一键放营火/营地物件，按钮下标注收益（法力回复/耐力/智力/属性%/暴击…）；
- 背包里有 → 可直接放；能造 → 金色 `+` 并跳到对应配方；缺料 → 红色 `!` 并列出缺什么；
- 营地面板：每条 buff 六种状态（已有 / 在营地但没吃到 / 被职业 buff 覆盖 / 我能放 / 队友能放 / 缺），buff 数值**从游戏里读**；
- **共享 1 小时冷却**显示在每个物件上，配紧凑计时（这是唯一一个明确建模共享 CD 的）；
- Rest 按钮：坐/跪/睡/躺一键，营地面板随之打开；1 分钟休息计时 + 提前移动警告；
- 队内请求 buff（右键物件 → 请求 / 一键请求全部缺失），需要对方也装；
- 缺料购物清单可复制给拍卖行；
- **明确限制：仅英文客户端（按 buff 名字匹配）**。

> 意义：它把“缺什么、谁能补、冷却还剩多久”讲清楚了，但死在英文名匹配上。**AzerothKit 用 spellID 判定，正好补它的死穴。**

## 3. 长尾里值得单独看的

| 插件 | 下载 | 一句话 |
| --- | --- | --- |
| [Camp Planner](https://www.curseforge.com/wow/addons/camp-planner) | 15 | 追每件营地物件，**每张蓝图由哪个 Boss 掉**，小队能补哪些 buff |
| [Camp Leader](https://www.curseforge.com/wow/addons/camp-leader) | 22 | 比较各设施收益，算“我贡献哪件最划算” |
| [Ark Camp](https://www.curseforge.com/wow/addons/ark-camp) | 35 | 营地规划 + 补给 + 队友贡献，主打“别浪费营地位” |
| [CampHelper Forever](https://www.curseforge.com/wow/addons/camphelper-forever) | 30 | 试剂数、已开配方、从背包放；面板可拖、横竖排 |
| [CampFireSit](https://www.curseforge.com/wow/addons/campfiresit) | 43 | 营火旁弹“坐下”按钮 + 60 秒倒计时 |
| [CampsideHelper](https://www.curseforge.com/wow/addons/campsidehelper) | 31 | 零配置，直接在世界 tooltip 里给精确 buff |
| [Fireside Camp](https://www.curseforge.com/wow/addons/fireside-camp) | 50 | 能造/缺什么一屏看完 + 靠近营火小地图提醒 |
| [Buff Guard Forever](https://www.curseforge.com/wow/addons/buff-guard-forever) | 208 | Well Fed / 营火 / 睡袋 三条 buff 追踪（升级经验向） |
| [Cozy sleeping bag timer](https://www.curseforge.com/wow/addons/cozy-sleeping-bag-timer) | 163 | 只做睡袋计时 |
| [ForeverCamp](https://www.curseforge.com/wow/addons/forevercamp) | 42 | 靠近营火时列出背包里的营地物件 + 全角色休息经验 |
| [Leveling: Campfire Easy](https://www.curseforge.com/wow/addons/leveling-campfire-easy) | 23 | 告诉你这堆营地摆了什么、坐下能吃到什么 |
| [Campfire Assistant - Forever](https://www.curseforge.com/wow/addons/campfire-assistant-forever) | 1.8K | 追营火 buff，一键把坐标发综合频道 |
| [Improved Forever: Camp](https://www.curseforge.com/wow/addons/improved-forever-camp) | 1.5K | 烤火变过场动画：隐藏 HUD、黑边、镜头环绕、字幕 |
| [Campfire Tales Forever](https://www.curseforge.com/wow/addons/campfire-tales-forever) | 1.2K | 篝火 RP 故事、狩猎回忆、荒野传说 |
| [Hearthsong: Campfire Band](https://www.curseforge.com/wow/addons/hearthsong-campfire-band) | 73 | 最多五人各挑乐器合奏（另有 5 个音色包） |

另有几个“大而全”的套件顺带做了营地页，可作信息架构参考：
[ForeverArtisan](https://www.curseforge.com/wow/addons/foreverartisan)（29.9K，12 专业 + Camping，含 Camp 窗口）、
[4Ever Leveling](https://www.curseforge.com/wow/addons/foreverleveling)（7.2K，含 Campfire Buffs）、
[ForeverGuide](https://www.curseforge.com/wow/addons/foreverguide)（14.9K，含 campsite）、
[ForeverLedger](https://www.curseforge.com/wow/addons/foreverledger)（2.1K，含 Camp）。

## 4. 功能矩阵（看得见的覆盖情况）

`✅` 做了 / `⚠️` 部分或近似 / `—` 没做

| 能力 | Happy Camper | Camping Kit | CozyFire | Camping Companion | Camp Planner | Wayfarer's Rest |
| --- | --- | --- | --- | --- | --- | --- |
| 地图共享/标记营火 | ✅ 玩家间共享 + 灰显他人来源 | ✅ 只看别人放的 | ✅ 自动标记 | — | — | ⚠️ 路点 |
| 按 buff 筛选营地 | ✅ | — | — | — | — | — |
| 营地面板 / 缺 buff 高亮 | ✅ | ⚠️ 只自身 | — | ✅ 六态 | ⚠️ | ⚠️ |
| 一键放置物件 | ✅ | ✅ | — | ✅ | — | ⚠️ |
| **共享 1 小时冷却建模** | — | — | — | ✅（唯一） | — | — |
| 小队“谁放什么” | ✅ 指派 + Your job | — | — | ⚠️ 只请求 | ⚠️ 看谁能补 | — |
| 设施手册 / 蓝图来源 | ✅ Handbook | — | — | — | ✅ Boss 掉落 | — |
| Camp Benefits / Well Fed 计时 | ✅ | ✅ | — | ✅ | — | — |
| 精确 buff 数值 | ✅ 按等级 | ⚠️ | ✅ tooltip | ✅ 读游戏 | — | — |
| 多语言（含简中） | ✅ | — | — | — | — | — |
| 允许再分发/改代码 | ❌ 保留所有权利 | 未标 | 未标 | 未标 | 未标 | 未标 |

## 5. 四个空白（AzerothKit 的机会）

1. **中文客户端 / 中文数据**。除 Happy Camper 外全是英文名匹配；Camping Companion 明写只支持英文客户端。AzerothKit 已有 spellID 判定（`1229739` / `1283391` / `1229451` / `1229741`），这是**唯一不依赖语言**的路子。
2. **共享冷却的正确建模**。只有 Camping Companion 读 `强化休息` 这个 debuff；其余仍是逐物品冷却或干脆没有。`docs/10` §3.5 的结论可以直接做成产品卖点。
3. **“设施表 × ID × 三阶”的可执行数据层**。所有人都停留在“buff 名字 + 描述”，没有一张能扫背包、判容量、算去重的表。`docs/11` 那张 38–39 件的表补上 itemID 就是壁垒。
4. **容量 3/5/10 与去重**。Camp Planner / Ark Camp 摸到了边，但没人把“营火等级 → 槽位数 → 已占/可选最优组合”做成一句话结论。

## 6. 给生产 Agent 的具体建议

按优先级：

1. **判定层先按 spellID，名字只做兜底**（现状正确，别退化）。任何“buff 名 == 'Camp Benefits'”的写法在中文客户端必挂。
2. **面板状态行只显示一次共享冷却**（`强化休息` 剩余时间），各行物件不再各报一个 CD；读不到再退回 `max(GetItemCooldown)`。
3. **交互对齐 Camping Kit**：物件按钮下方挂“打开对应专业窗口”的小按钮；进战斗整块面板隐藏。
4. **对齐 Camping Companion 的缺失态**：能造 → `+` 跳配方；缺料 → `!` + 缺什么 + 可复制购物清单。这是它唯一做对且有价值的部分。
5. **不要复制 Happy Camper 的代码/美术/音频**（明确保留所有权利）。可参考的是**信息架构**：Camp 页（我有什么/缺什么）、Group 页（谁放什么）、Handbook（怎么来）。文案自己写。
6. **共享营火若要联机**：Happy Camper 走隐藏频道广播且默认可见性可关。我们若做，必须默认关闭 + 明确开关 + 不外发战斗数据（12.x 机密值规则同理，见 `docs/03`）。
7. **多语言从第一天就按 key 走**，别把中文写死在 Lua 里——生态里已经证明“只做英文”会直接把中文用户让出来。

## 7. 可复用的调研动作（下次不用重新摸）

```powershell
# 取任意插件的精确元数据（版本 / 下载 / 逐文件时间）
Invoke-RestMethod https://api.cfwidget.com/wow/addons/happy-camper | ConvertTo-Json -Depth 4

# 分类全量（5 页）
# https://addon-radar.com/forever/categories/camping?page=N
```

**下一步最省力的补数据方式**：下载 `CampingKit-v1.8-forever.zip`（665 KB）和 Happy Camper 1.1.1（10.9 MB，主要是音频），反查它们 Lua 里的设施 ID 表、buff 表、蓝图掉落表，直接回填 `docs/11` 的“待补”三项（设施 itemID / buff spellID / 三阶名单）。这比在游戏里逐件采集快一个数量级。

## 8. 参考链接

- CurseForge Camping 分类（需浏览器）：`https://www.curseforge.com/wow/addons?category=camping`
- 分类镜像：https://addon-radar.com/forever/categories/camping
- Happy Camper：https://www.curseforge.com/wow/addons/happy-camper
- Camping Kit：https://www.curseforge.com/wow/addons/camping-kit
- CozyFire：https://www.curseforge.com/wow/addons/cozyfire
- Camping Companion：https://www.curseforge.com/wow/addons/camping-companion
- Wayfarer's Rest：https://www.curseforge.com/wow/addons/wayfarers-rest
- Camp Planner：https://www.curseforge.com/wow/addons/camp-planner
