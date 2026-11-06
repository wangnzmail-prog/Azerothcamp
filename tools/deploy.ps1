<#
.SYNOPSIS
  Link addon\AzerothKit into the clients' Interface\AddOns as a directory
  junction (no file copies), or remove those links.

.NOTES
  ASCII-only on purpose: Windows PowerShell 5.1 reads BOM-less .ps1 files as
  ANSI, which mangles non-ASCII literals.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File tools\deploy.ps1
  powershell -ExecutionPolicy Bypass -File tools\deploy.ps1 -Only forever
  powershell -ExecutionPolicy Bypass -File tools\deploy.ps1 -Remove
#>
[CmdletBinding()]
param(
    [string]$WowRoot = 'E:\Program Files\Blizzard Games\World of Warcraft',
    [ValidateSet('all', 'retail', 'forever', 'titan')]
    [string]$Only = 'all',
    [switch]$Remove
)

$ErrorActionPreference = 'Stop'

$repo = Split-Path -Parent $PSScriptRoot
$source = Join-Path $repo 'addon\AzerothKit'
$addonName = 'AzerothKit'

if (-not $Remove -and -not (Test-Path -LiteralPath $source)) {
    throw "Addon source not found: $source"
}

$flavors = [ordered]@{
    retail  = '_retail_'
    forever = '_forever_'
    titan   = '_classic_titan_'
}

if ($Only -ne 'all') {
    $flavors = [ordered]@{ $Only = $flavors[$Only] }
}

foreach ($proc in @('Wow', 'WowClassic')) {
    if (Get-Process -Name $proc -ErrorAction SilentlyContinue) {
        Write-Warning "$proc.exe is running: /reload or relog after deploying."
    }
}

$fail = 0

foreach ($flavor in $flavors.Keys) {
    $clientDir = Join-Path $WowRoot $flavors[$flavor]
    if (-not (Test-Path -LiteralPath $clientDir)) {
        Write-Warning "[$flavor] client dir missing, skipped: $clientDir"
        continue
    }

    $addonsDir = Join-Path $clientDir 'Interface\AddOns'
    if (-not (Test-Path -LiteralPath $addonsDir)) {
        Write-Warning "[$flavor] Interface\AddOns missing, skipped: $addonsDir"
        continue
    }

    $link = Join-Path $addonsDir $addonName

    if ($Remove) {
        if (-not (Test-Path -LiteralPath $link)) {
            Write-Host "[$flavor] not linked, skipped"
            continue
        }
        $item = Get-Item -LiteralPath $link -Force
        if (-not ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
            Write-Warning "[$flavor] $link is a real directory, left untouched"
            $fail++
            continue
        }
        cmd /c rmdir "$link" | Out-Null
        if (Test-Path -LiteralPath $link) {
            Write-Warning "[$flavor] failed to unlink: $link"
            $fail++
        }
        else {
            Write-Host "[$flavor] unlinked $link"
        }
        continue
    }

    if (Test-Path -LiteralPath $link) {
        $item = Get-Item -LiteralPath $link -Force
        if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
            $targets = @($item.Target)
            if ($targets -contains $source) {
                Write-Host "[$flavor] already linked, skipped"
                continue
            }
            Write-Warning "[$flavor] link points elsewhere: $($targets -join ', '); run -Remove first"
            $fail++
            continue
        }
        Write-Warning "[$flavor] $link is a real directory, not overwritten"
        $fail++
        continue
    }

    New-Item -ItemType Junction -Path $link -Target $source | Out-Null
    Write-Host "[$flavor] linked $link -> $source"
}

if ($fail -gt 0) { exit 1 }
exit 0
