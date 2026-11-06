# 05 · 本机工具链与日常工作流

## 1. 本机现状（2026-11-06 实测）

| 工具 | 状态 | 说明 |
| --- | --- | --- |
| git | ✅ `C:\Program Files\Git\cmd\git.exe`（2.56.0） | 版本管理 |
| node | ✅ `C:\Program Files\nodejs\node.exe` | 跑 `luaparse` 做语法检查 |
| python | ⚠️ 只有 WindowsApps 占位符 | 未验证是否可用；`forever-lint` 需要真 Python |
| lua / luac | ❌ | 本机没有独立 Lua 解释器 |
| pnpm / npm | npm 随 node；pnpm 未装 | npm 够用 |
| VS Code | ❌ 未装 | 需要的话再装，并配 Lua 语言服务 |

游戏内没有"本地服务器"概念：**所有测试都在客户端里跑**，改文件 → `/reload` 就是完整的迭代循环。

## 2. 部署：目录联接（junction）

`tools/deploy.ps1` 把 `D:\ai\wow\addon\AzerothKit` 以目录联接方式挂到两个客户端的 `Interface\AddOns\` 下：

```powershell
# 部署（两个客户端都挂）
powershell -ExecutionPolicy Bypass -File D:\ai\wow\tools\deploy.ps1

# 只挂正式服
powershell -ExecutionPolicy Bypass -File D:\ai\wow\tools\deploy.ps1 -Only retail

# 卸载（只删联接，不动源码）
powershell -ExecutionPolicy Bypass -File D:\ai\wow\tools\deploy.ps1 -Remove
```

用联接而不是复制的好处：改源码即生效，游戏内 `/reload` 就行；坏处：删源码目录前必须先 `-Remove`，否则会在 AddOns 里留下断链。

> 游戏正在运行时也可以挂载，但插件列表在登录时扫描，需 `/reload` 或重登才看得到。

## 3. 校验：TOC 版本号 vs 客户端版本

`tools/check.ps1` 读取安装根目录的 `.build.info`，把版本号换算成 Interface，与插件 TOC 里声明的值比对：

```
12.1.5  → 120105      1.60.1 → 16001      3.80.2 → 38002
（主版本*10000 + 次版本*100 + 补丁号）
```

输出每个客户端"期望 Interface / TOC 声明 / 是否匹配"。客户端每次小版本更新后先跑它，能第一时间发现"插件被标记过期"的原因。

## 4. 语法检查：luaparse

没有 Lua 解释器也能查语法——用 node 的 `luaparse`：

```powershell
cd D:\ai\wow\tools
npm install luaparse --no-audit --no-fund
node -e "const l=require('luaparse');const fs=require('fs');l.parse(fs.readFileSync(process.argv[1],'utf8'))" ..\addon\AzerothKit\Core.lua
```

`check.ps1` 会自动对 `addon/` 下所有 `.lua` 跑一遍（装了 `luaparse` 的前提下）。它只查语法，不查 API 是否存在——API 只能进游戏验。

## 5. 编辑—测试循环

```
改 Lua / TOC  →  游戏内 /reload  →  看报错  →  改
```

必备开关：

```
/console scriptErrors 1      -- 让 Lua 错误弹出来
/console taintLog 2          -- 需要查污染时开
/reload                      -- 应用改动
/ak probe                    -- 本插件的自检
```

装 **BugSack + BugGrabber** 能保留历史报错，比默认红字框好用。报错会写到 `Logs\` 下。

## 6. 进游戏前的静态检查清单

- [ ] 文件夹名 = TOC 名 = `ADDON` 变量名
- [ ] TOC 的 `## Interface` 覆盖当前两个客户端的版本（或分成两份 TOC）
- [ ] TOC 里列出的每个文件都真实存在，且顺序正确（依赖先加载）
- [ ] `SavedVariables` 名字和代码里的全局表名一致
- [ ] 文件编码 UTF-8 **无 BOM**，换行 LF/CRLF 均可
- [ ] 没有注册 `COMBAT_LOG_EVENT*`
- [ ] 没有对可能为 secret 的值做算术/比较/布尔判断
- [ ] 没有在 `OnUpdate` 里做重活
- [ ] 中文文本有 `Title-zhCN` / `Notes-zhCN`，代码里走 locale 表

## 7. 打包与发布

| 环节 | 工具 | 说明 |
| --- | --- | --- |
| 版本号注入 | [BigWigs Packager](https://github.com/BigWigsMods/packager) | 从 git tag 生成 `## Version`，产出 zip |
| CI | GitHub Actions + packager | 打 tag 自动发 CurseForge / Wago |
| 分发 | CurseForge / Wago Addons / 手动 zip | 无限用户目前主要靠 CurseForge 与手动安装 |
| TOC 版本替换 | packager 的 `@toc@` 或 `.pkgmeta` | 避免每次补丁手改 Interface |

最小自动化建议：git 管理 + 一个 `release` GitHub Action，跑 packager，产出两个客户端通用的 zip。

## 8. 值得收藏的资料源

| 用途 | 地址 |
| --- | --- |
| API 总览与补丁变更 | <https://warcraft.wiki.gg/wiki/World_of_Warcraft_API> |
| 机密值规范 | <https://warcraft.wiki.gg/wiki/Secret_Values> |
| 暴雪界面源码（含 `forever` 分支） | <https://github.com/Gethe/wow-ui-source> |
| 无限插件开发社区指南 | <https://wowforeverguides.com/addons/developers> |
| 无限 API 速查 | <https://wowforeverguides.com/addons/api-cheatsheet> |
| 无限插件坑位清单 | <https://wowforeverguides.com/addons/pitfalls> |
| DB2 数据浏览 | <https://wago.tools> |
| 针对无限的 linter | <https://pypi.org/project/forever-lint/> |

## 9. 常见坑（按踩坑概率排序）

1. **TOC 版本号过期** → 插件在列表里灰掉，玩家以为坏了。每次补丁先跑 `check.ps1`。
2. **注册 CLEU** → 12.x 直接报错，整个插件加载失败。
3. **打印 secret 值** → 无限客户端上 `print(secret)` 抛错，日志里全是红字。
4. **拿 `UnitName` 当字符串比较** → 战斗中非队友单位返回 secret，`==` 直接炸。
5. **文件夹名和 TOC 名不一致** → 游戏读不到 TOC，插件不出现。
6. **SavedVariables 没做 schema 迁移** → 老用户升级后配置错乱。
7. **UTF-8 BOM** → 部分版本会把 BOM 当内容，出现奇怪的 `ï»¿`。
8. **在 `ADDON_LOADED` 里就访问其他插件** → 加载顺序不保证，改用 `PLAYER_LOGIN` 或 `## OptionalDeps`。
9. **用 PowerShell 写 Lua/TOC 带 BOM** → Windows PowerShell 5.1 的 `Set-Content -Encoding UTF8` 会写 BOM，还会把中文按 ANSI 读成乱码；后果是整份 TOC 失效、Lua 首字节报错。必须用 UTF-8 无 BOM 写（`check.ps1` 已自动检测 BOM 并判失败）。
