# 魔兽世界插件开发准备包（正式服 + 无限）

本目录是「为《魔兽世界》正式服与《魔兽世界：无限》开发插件」的前期准备成果：一份现状调研、一套双版本插件骨架、一套本机部署与校验脚本。

> 结论先行：**《魔兽世界：无限》不是私服**，是暴雪 2026 年推出的第三条官方产品线（海外名 *WoW Forever*，客户端内部代号 **Camelot**）。它用「Mainline 家族的 UI/引擎」跑「60 级封顶的旧世界」，因此插件 API 上它既不像经典旧世、也不完全等于正式服——这一条决定了整套开发策略。

## 目录

| 路径 | 内容 |
| --- | --- |
| `README.md` | 现状速查表 + 三步上手 |
| `docs/01-versions-and-ecosystem.md` | 三个客户端、版本号、Interface、本机实况、插件生态 |
| `docs/02-addon-model.md` | 插件运行模型：TOC / Lua / 事件 / SavedVariables / 污染与安全 |
| `docs/03-secrets-and-limits.md` | 12.x「机密值」体系与无战斗日志时代的能力边界（含无限） |
| `docs/04-dual-flavor-architecture.md` | 一套代码同时跑正式服与无限的架构与写法 |
| `docs/05-toolchain-and-workflow.md` | 本机工具链、部署脚本、调试命令、打包发布 |
| `docs/06-roadmap-and-checklist.md` | 分阶段路线图、验证清单、待确认问题 |
| `docs/07-ndui-details-anatomy.md` | NDui/Details 结构解剖、替代可行性矩阵、自研路线 |
| `docs/08-suite-blueprint.md` | 自研套件蓝图：分层、模块预算与工期、统计面板设计、迁移策略 |
| `docs/09-agent-bridge.md` | Agent 接入：Schema / Profile / Export 三件套、文件通道、整合层设计 |
| `addon/AzerothKit/` | 可直接加载的双版本示例插件（0.1.0） |
| `tools/deploy.ps1` | 把示例插件以目录联接方式挂进两个客户端 |
| `tools/check.ps1` | 校验 TOC Interface 与本机客户端版本是否匹配 |

## 现状速查（本机实测，2026-11-06）

| 项 | 正式服 | 无限 | 时光服（对照） |
| --- | --- | --- | --- |
| 客户端目录 | `_retail_` | `_forever_` | `_classic_titan_` |
| 产品代号 | `wow` | `wowf` | `wow_classic_titan` |
| 客户端版本 | 12.1.5.70783 | 1.60.1.70790 | 3.80.2.70522 |
| TOC `## Interface` | **120105** | **16001** | 38002 |
| `WOW_PROJECT_ID` | 1 | **18**（`WOW_PROJECT_CAMELOT`） | 2 |
| UI 家族 | Mainline | Mainline（同一套框架） | Classic |
| 战斗日志（CLEU） | 注册即报错 | 社区报告不可用（待自测） | 可用 |

安装根目录：`E:\Program Files\Blizzard Games\World of Warcraft`
（另有 `_cn_beta_` 国服测试客户端，本次未展开。）

## 三步上手

```powershell
# 1) 把示例插件挂进正式服与无限两个客户端（目录联接，不复制文件）
powershell -ExecutionPolicy Bypass -File D:\ai\wow\tools\deploy.ps1

# 2) 校验 TOC 版本号与本机客户端是否匹配
powershell -ExecutionPolicy Bypass -File D:\ai\wow\tools\check.ps1
```

3) 进游戏：插件列表里启用 **AzerothKit**，输入 `/ak probe` 看能力矩阵；`/ak ui` 开关测试窗口。

改动 `addon/AzerothKit/` 下的文件后，游戏内 `/reload` 即可生效（联接目录，无需重新部署）。

## 已完成验证（2026-11-06）

| 项 | 结果 |
| --- | --- |
| `tools/check.ps1` | ✅ 正式服 120105 / 无限 16001 均匹配；6 个 Lua 文件 luaparse 语法检查全通过 |
| `tools/deploy.ps1` | ✅ `_retail_` 与 `_forever_` 的 `Interface\AddOns\AzerothKit` 均为目录联接 |
| 0.2.0 模块化内核 | ✅ Theme（主题控件）+ Core（事件总线/模块注册器/DB）+ UI（模块开关）+ Infobar 示例模块，语法校验通过 |
| 0.3.0 Agent 写入口 | ✅ `Profile.lua` + `tools/ak-config.ps1`：JSON 生成配置（版本自增）、`/ak export` 导出状态，链路已跑通 |
| 0.4.0 第三方整合 | ✅ `Integrations/` 框架 + Details 适配器（检测/版本/窗口数/皮肤、窗口缩放）；`check.ps1` 增加 BOM 检测 |
| 游戏内加载 | ⏳ 待验证：`/reload` 后在插件列表看到 AzerothKit，`/ak` 打开面板、勾选模块 |
| 时光服 | 未挂载（骨架只声明了 120105 与 16001）；需要时给 TOC 补一个 `38002` 再 `deploy.ps1 -Only titan` |


## 两条最重要的开发结论

1. **不要注册 `COMBAT_LOG_EVENT_UNFILTERED`**。12.0（2026-03-02 上线）起注册它直接抛 Lua 错误；伤害/治疗数据改由官方 `C_DamageMeter` 会话接口提供，且只允许"展示"，不允许基于它做决策逻辑。
2. **战斗中的数值是"机密值"（secret value）**。可以读取、可以传给 UI 控件、可以拼接字符串，但**不能比较、不能算术、不能当布尔判断、不能当表键**，违反即报错。无限客户端同源，同样受限。所有涉及血量、资源、冷却、光环、施法的功能，都要按"能力探测 + 降级显示"来设计。

详见 `docs/03-secrets-and-limits.md`。
