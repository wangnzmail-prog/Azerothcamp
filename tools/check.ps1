<#
.SYNOPSIS
  Validate addon TOC Interface numbers against the installed clients, and
  syntax-check every .lua under addon\ (requires tools\node_modules\luaparse).

.NOTES
  ASCII-only on purpose: Windows PowerShell 5.1 reads BOM-less .ps1 files as
  ANSI, which mangles non-ASCII literals.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File tools\check.ps1
#>
[CmdletBinding()]
param(
    [string]$WowRoot = 'E:\Program Files\Blizzard Games\World of Warcraft',
    # products this addon actually targets; others are listed but not judged
    [string[]]$Products = @('wow', 'wowf')
)

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot

# ---------- 1. clients ----------
$buildInfo = Join-Path $WowRoot '.build.info'
if (-not (Test-Path -LiteralPath $buildInfo)) {
    throw "Missing .build.info: $buildInfo"
}

$lines = Get-Content -LiteralPath $buildInfo
# header cells look like "Version!STRING:0" -> keep the name part only
$header = @($lines[0].Split('|') | ForEach-Object { ($_ -split '!', 2)[0] })
$vi = [array]::IndexOf($header, 'Version')
$pi = [array]::IndexOf($header, 'Product')
if ($vi -lt 0 -or $pi -lt 0) { throw 'Unrecognized .build.info format' }

$installed = @()
foreach ($line in ($lines | Select-Object -Skip 1)) {
    if ([string]::IsNullOrWhiteSpace($line)) { continue }
    $f = $line.Split('|')
    $ver = $f[$vi]
    $prod = $f[$pi]
    if (-not $ver) { continue }
    $parts = $ver.Split('.')
    $iface = ([int]$parts[0] * 10000) + ([int]$parts[1] * 100) + $(if ($parts.Count -ge 3) { [int]$parts[2] } else { 0 })
    $installed += [pscustomobject]@{ Product = $prod; Version = $ver; Interface = $iface }
}

# ---------- 2. TOC ----------
$addonRoot = Join-Path $repo 'addon'
$tocs = Get-ChildItem -Path $addonRoot -Filter *.toc -Recurse -ErrorAction SilentlyContinue
if (-not $tocs) { throw "No .toc found under $addonRoot" }

$declared = @{}
foreach ($toc in $tocs) {
    $line = Select-String -LiteralPath $toc.FullName -Pattern '^##\s*Interface\s*:' | Select-Object -First 1
    if (-not $line) { continue }
    $value = ($line.Line -split ':', 2)[1]
    $ids = @($value.Split(',') | ForEach-Object { $_.Trim() } |
        Where-Object { $_ -match '^\d+$' } | ForEach-Object { [int]$_ })
    $declared[$toc.FullName] = $ids
}

# ---------- 3. compare ----------
$rows = @()
foreach ($toc in $tocs) {
    $ids = $declared[$toc.FullName]
    if (-not $ids) {
        $rows += [pscustomobject]@{
            TOC = $toc.Name; Client = ''; Version = ''; Expected = ''
            Declared = '(none)'; Status = 'NO-INTERFACE'
        }
        continue
    }
    foreach ($c in $installed) {
        $inScope = $Products -contains $c.Product
        if (-not $inScope) {
            $rows += [pscustomobject]@{
                TOC      = $toc.Name
                Client   = $c.Product
                Version  = $c.Version
                Expected = $c.Interface
                Declared = ($ids -join ',')
                Status   = 'SKIP'
            }
            continue
        }
        $hit = $ids -contains $c.Interface
        $rows += [pscustomobject]@{
            TOC      = $toc.Name
            Client   = $c.Product
            Version  = $c.Version
            Expected = $c.Interface
            Declared = ($ids -join ',')
            Status   = $(if ($hit) { 'OK' } else { 'MISMATCH' })
        }
    }
}

Write-Host ''
Write-Host '=== installed clients ===' -ForegroundColor Cyan
$installed | Format-Table -AutoSize | Out-String | Write-Host

Write-Host '=== TOC vs client ===' -ForegroundColor Cyan
$rows | Format-Table -AutoSize | Out-String | Write-Host

$mismatch = @($rows | Where-Object { $_.Status -eq 'MISMATCH' -or $_.Status -eq 'NO-INTERFACE' })

# ---------- 4. Lua syntax ----------
Write-Host '=== Lua syntax ===' -ForegroundColor Cyan
$node = Get-Command node -ErrorAction SilentlyContinue
$luaparse = Join-Path $PSScriptRoot 'node_modules\luaparse'
$luaFiles = Get-ChildItem -Path $addonRoot -Filter *.lua -Recurse -ErrorAction SilentlyContinue
$syntaxBad = 0

if (-not $node) {
    Write-Host 'node not found, skipped.' -ForegroundColor Yellow
}
elseif (-not (Test-Path -LiteralPath $luaparse)) {
    Write-Host 'luaparse not installed, skipped. Run: cd tools; npm install luaparse' -ForegroundColor Yellow
}
else {
    $checker = "const l=require(process.argv[2]);const fs=require('fs');l.parse(fs.readFileSync(process.argv[1],'utf8'))"
    foreach ($f in $luaFiles) {
        $out = & node -e $checker $f.FullName $luaparse 2>&1
        if ($LASTEXITCODE -ne 0) {
            $syntaxBad++
            Write-Host ("FAIL " + $f.Name) -ForegroundColor Red
            Write-Host ($out -join "`n") -ForegroundColor DarkRed
        }
        else {
            Write-Host ("OK   " + $f.Name) -ForegroundColor Green
        }
    }
}

Write-Host ''
if ($mismatch.Count -gt 0) {
    Write-Host ("Interface mismatch on {0} row(s): bump the TOC after a client patch." -f $mismatch.Count) -ForegroundColor Yellow
}
if ($syntaxBad -gt 0) {
    Write-Host ("Lua syntax errors: {0}" -f $syntaxBad) -ForegroundColor Red
}

if ($syntaxBad -gt 0) { exit 1 }
exit 0


