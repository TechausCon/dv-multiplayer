#Requires -Version 5.1
<#
.SYNOPSIS
    Build DV Multiplayer mod (Windows).

.EXAMPLE
    .\scripts\Build-Mod.ps1
    .\scripts\Build-Mod.ps1 -Configuration Release
    .\scripts\Build-Mod.ps1 -DvInstallDir "D:\Steam\steamapps\common\Derail Valley"
#>
[CmdletBinding()]
param(
    [ValidateSet('Debug', 'Release')]
    [string]$Configuration = 'Debug',
    [string]$DvInstallDir = '',
    [string]$UnityInstallDir = '',
    [switch]$SkipUnityAssetsCheck
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$targetsFile = Join-Path $repoRoot 'Directory.Build.targets'
$exampleFile = Join-Path $repoRoot 'Directory.Build.targets.EXAMPLE'
$buildDir = Join-Path $repoRoot 'build'

function Find-DerailValleyDir {
    $candidates = @(
        $DvInstallDir,
        'C:\Spiele\DerailValley\Derail Valley',
        'C:\Program Files (x86)\Steam\steamapps\common\Derail Valley',
        'C:\Program Files\Steam\steamapps\common\Derail Valley',
        'D:\Steam\steamapps\common\Derail Valley',
        'E:\Steam\steamapps\common\Derail Valley'
    ) | Where-Object { $_ -and ($_ -as [string]).Trim() -ne '' }

    foreach ($path in $candidates) {
        $exe = Join-Path $path 'DerailValley.exe'
        if (Test-Path -LiteralPath $exe) { return $path }
    }
    return $null
}

function Find-Unity2019Dir {
    $candidates = @(
        $UnityInstallDir,
        'C:\Program Files\Unity\Hub\Editor\2019.4.40f1\Editor',
        'C:\Program Files\Unity\Editor\2019.4.40f1\Editor'
    ) | Where-Object { $_ -and ($_ -as [string]).Trim() -ne '' }

    foreach ($path in $candidates) {
        $engine = Join-Path $path 'Unity.exe'
        if (Test-Path -LiteralPath $engine) { return $path }
    }
    return $null
}

function Ensure-DirectoryBuildTargets {
    param([string]$DvDir, [string]$UnityDir)

    if (Test-Path -LiteralPath $targetsFile) {
        Write-Host "Using existing Directory.Build.targets"
        return
    }

    if (-not (Test-Path -LiteralPath $exampleFile)) {
        throw "Missing Directory.Build.targets.EXAMPLE"
    }

    $xml = Get-Content -LiteralPath $exampleFile -Raw
    $xml = $xml -replace '<DvInstallDir>[^<]+</DvInstallDir>', "<DvInstallDir>$DvDir</DvInstallDir>"
    $xml = $xml -replace '<UnityInstallDir>[^<]+</UnityInstallDir>', "<UnityInstallDir>$UnityDir</UnityInstallDir>"
    $xml = $xml -replace '<Cert-Thumb>[^<]+</Cert-Thumb>', '<Cert-Thumb></Cert-Thumb>'
    Set-Content -LiteralPath $targetsFile -Value $xml -Encoding UTF8
    Write-Host "Created Directory.Build.targets"
}

function Test-BuildAssets {
    $required = @(
        'multiplayer.assetbundle',
        'MultiplayerEditor.dll',
        'UnityChan.dll'
    )
    $missing = @()
    foreach ($name in $required) {
        if (-not (Test-Path -LiteralPath (Join-Path $buildDir $name))) {
            $missing += $name
        }
    }
    if ($missing.Count -eq 0) { return $true }

    Write-Warning "build/ is missing: $($missing -join ', ')"
    Write-Warning "Build Unity assets (Multiplayer > Build Asset Bundle and Scripts) or copy from a release zip into build/"
    return $false
}

# --- main ---
if ($PSVersionTable.PSEdition -eq 'Core' -and $PSVersionTable.Platform -eq 'Unix') {
    Write-Error "Run this script on Windows where Derail Valley is installed."
}

$dvDir = Find-DerailValleyDir
if (-not $dvDir) {
    throw "Derail Valley not found. Pass -DvInstallDir or install the game via Steam."
}

$unityDir = Find-Unity2019Dir
if (-not $unityDir) {
    throw "Unity 2019.4.40f1 not found. Pass -UnityInstallDir or install via Unity Hub."
}

Write-Host "DV:     $dvDir"
Write-Host "Unity:  $unityDir"
Write-Host "Config: $Configuration"

if (-not (Test-Path -LiteralPath $buildDir)) {
    New-Item -ItemType Directory -Path $buildDir | Out-Null
}

Ensure-DirectoryBuildTargets -DvDir $dvDir -UnityDir $unityDir

if (-not $SkipUnityAssetsCheck) {
    if (-not (Test-BuildAssets)) {
        throw "Cannot compile Multiplayer without build/ assets. Use -SkipUnityAssetsCheck to try anyway."
    }
}

$dotnet = Get-Command dotnet -ErrorAction SilentlyContinue
if (-not $dotnet) {
    throw "dotnet SDK not found. Install .NET SDK 6+ from https://dotnet.microsoft.com/download"
}

Push-Location $repoRoot
try {
    Write-Host "`n=== Building MultiplayerAPI ===" -ForegroundColor Cyan
    & dotnet build (Join-Path $repoRoot 'MultiplayerAPI\MultiplayerAPI.csproj') -c $Configuration
    if ($LASTEXITCODE -ne 0) { throw "MultiplayerAPI build failed" }

    Write-Host "`n=== Building Multiplayer ===" -ForegroundColor Cyan
    & dotnet build (Join-Path $repoRoot 'Multiplayer\Multiplayer.csproj') -c $Configuration
    if ($LASTEXITCODE -ne 0) { throw "Multiplayer build failed" }

    $outDll = Join-Path $repoRoot "Multiplayer\bin\$Configuration\net48\Multiplayer.dll"
    $modDir = Join-Path $dvDir 'Mods\Multiplayer'

    Write-Host "`n=== Done ===" -ForegroundColor Green
    Write-Host "Output DLL: $outDll"
    Write-Host "Copied to:  $modDir (via post-build.ps1)"
    Write-Host "build/:    $buildDir"
}
finally {
    Pop-Location
}
