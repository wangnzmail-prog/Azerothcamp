<#
.SYNOPSIS
  从 AzerothKit 的源码构建独立版 AzerothCamp（露营管理），并打出可分发 zip。

.NOTES
  单一源码：Camp.lua / Comms.lua / Data\CampItems.lua 只在 addon\AzerothKit 维护一份，
  这里把它们 + standalone\Shim.lua 组装成独立插件目录。
#>
[CmdletBinding()]
param(
    [string]$Version = '0.15.0'
)

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$src = Join-Path $repo 'addon\AzerothKit'
$shim = Join-Path $repo 'standalone\Shim.lua'
$outRoot = Join-Path $repo 'dist\standalone'
$addon = Join-Path $outRoot 'AzerothCamp'

if (Test-Path $outRoot) { Remove-Item $outRoot -Recurse -Force }
New-Item -ItemType Directory -Path (Join-Path $addon 'Data') -Force | Out-Null

Copy-Item $shim (Join-Path $addon 'Shim.lua') -Force
Copy-Item (Join-Path $src 'Modules\Camp.lua') (Join-Path $addon 'Camp.lua') -Force
Copy-Item (Join-Path $src 'Modules\Comms.lua') (Join-Path $addon 'Comms.lua') -Force
Copy-Item (Join-Path $src 'Data\CampItems.lua') (Join-Path $addon 'Data\CampItems.lua') -Force

$toc = @"
## Interface: 120105, 16001
## Title: AzerothCamp
## Title-zhCN: 露营管理
## Notes: Camping assistant for WoW Forever (campfire, tent, camp items, party sync)
## Notes-zhCN: 无限露营助手（营火/帐篷/营地制品/小队同步）
## Author: DSH
## Version: $Version-1
## SavedVariables: AzerothCampDB
## X-Website: https://github.com/

Shim.lua
Data\CampItems.lua
Camp.lua
Comms.lua
"@
$utf8 = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText((Join-Path $addon 'AzerothCamp.toc'), $toc, $utf8)

$zip = Join-Path $repo "dist\AzerothCamp-$Version.zip"
if (Test-Path $zip) { Remove-Item $zip -Force }
Compress-Archive -Path $addon -DestinationPath $zip -CompressionLevel Optimal

$files = Get-ChildItem $addon -Recurse -File
Write-Host ("built: {0}" -f $zip) -ForegroundColor Green
Write-Host ("  files: {0}  size: {1} KB" -f $files.Count, [math]::Round((Get-Item $zip).Length / 1KB, 1))
$files | ForEach-Object { Write-Host ("  " + $_.FullName.Replace("$addon\", '')) }
