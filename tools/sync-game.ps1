<#
.SYNOPSIS
  确保游戏插件目录里的 AzerothKit / AzerothCamp 都是指向源码的目录联接。

.NOTES
  两个插件都以 junction 方式挂载，源码一改游戏内即生效（TOC 变更需重启客户端）。
  若某个目录变成了"真实拷贝"（例如手工复制过），本脚本会把它移到 _backup 并重建联接。
#>
[CmdletBinding()]
param(
    [string]$WowRoot = 'E:\Program Files\Blizzard Games\World of Warcraft',
    [switch]$Remove
)

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$pairs = [ordered]@{
    'AzerothKit'  = Join-Path $repo 'addon\AzerothKit'
    'AzerothCamp' = Join-Path $repo 'addon\AzerothCamp'
}
$backup = Join-Path $repo '_backup'
$addons = Join-Path $WowRoot '_forever_\Interface\AddOns'

if (-not (Test-Path $addons)) { throw "AddOns not found: $addons" }
if (-not (Test-Path $backup)) { New-Item -ItemType Directory -Path $backup -Force | Out-Null }

foreach ($name in $pairs.Keys) {
    $src = $pairs[$name]
    $dst = Join-Path $addons $name
    if (-not (Test-Path $src)) { Write-Warning "[$name] source missing: $src"; continue }

    if ($Remove) {
        if (Test-Path $dst) {
            $i = Get-Item $dst -Force
            if ($i.Attributes -band [IO.FileAttributes]::ReparsePoint) { cmd /c rmdir "$dst" | Out-Null; Write-Host "[$name] unlinked" }
            else { Write-Warning "[$name] real dir, left untouched: $dst" }
        }
        continue
    }

    if (Test-Path $dst) {
        $i = Get-Item $dst -Force
        $isLink = [bool]($i.Attributes -band [IO.FileAttributes]::ReparsePoint)
        if ($isLink) {
            $target = @($i.Target)[0]
            if ($target -eq $src) { Write-Host "[$name] OK (junction)"; continue }
            cmd /c rmdir "$dst" | Out-Null
        }
        else {
            $bak = Join-Path $backup ("{0}.bak-{1}" -f $name, (Get-Date -Format 'yyyyMMdd-HHmmss'))
            Move-Item $dst $bak -Force
            Write-Warning "[$name] was a real copy -> moved to $bak"
        }
    }

    New-Item -ItemType Junction -Path $dst -Target $src | Out-Null
    Write-Host "[$name] linked -> $src"
}

Write-Host ''
Write-Host 'current state:' -ForegroundColor Cyan
Get-ChildItem $addons -Directory | Where-Object { $_.Name -like 'Azeroth*' } | ForEach-Object {
    $i = Get-Item $_.FullName -Force
    $kind = if ($i.Attributes -band [IO.FileAttributes]::ReparsePoint) { '-> ' + (@($i.Target)[0]) } else { '(real dir)' }
    Write-Host ("  {0}  {1}" -f $_.Name, $kind)
}
