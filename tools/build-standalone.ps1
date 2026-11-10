<#
.SYNOPSIS
  打包 AzerothCamp（独立露营插件）为可上传 zip。

.NOTES
  源码目录就是 addon\AzerothCamp，不再从套件拼装——套件已改为纯框架。
#>
[CmdletBinding()]
param(
    [string]$Version = '0.17.0'
)

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$addon = Join-Path $repo 'addon\AzerothCamp'

if (-not (Test-Path $addon)) { throw "addon dir not found: $addon" }

# 版本号写进 TOC
$tocPath = Join-Path $addon 'AzerothCamp.toc'
$toc = [System.IO.File]::ReadAllText($tocPath)
$toc = [regex]::Replace($toc, '## Version: [\d\.]+-\d+', "## Version: $Version-1")
[System.IO.File]::WriteAllText($tocPath, $toc, (New-Object System.Text.UTF8Encoding($false)))

$zip = Join-Path $repo "dist\AzerothCamp-$Version.zip"
if (Test-Path $zip) { Remove-Item $zip -Force }
Compress-Archive -Path $addon -DestinationPath $zip -CompressionLevel Optimal

$files = Get-ChildItem $addon -Recurse -File
Write-Host ("built: {0}" -f $zip) -ForegroundColor Green
Write-Host ("  files: {0}  size: {1} KB" -f $files.Count, [math]::Round((Get-Item $zip).Length / 1KB, 1))
$files | ForEach-Object { Write-Host ("  " + $_.FullName.Replace("$addon\", '')) }
