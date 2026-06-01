#Requires -Version 5.1
<#
.SYNOPSIS
    Build DV Multiplayer mod (Windows).

.EXAMPLE
    .\scripts\Build-Mod.ps1
    .\scripts\Build-Mod.ps1 -Configuration Release
    .\scripts\Build-Mod.ps1 -DvInstallDir "D:\Steam\steamapps\common\Derail Valley"
    .\scripts\Build-Mod.ps1 -FetchBuildAssets
#>
[CmdletBinding()]
param(
    [ValidateSet('Debug', 'Release')]
    [string]$Configuration = 'Debug',
    [string]$DvInstallDir = '',
    [string]$UnityInstallDir = '',
    [switch]$SkipUnityAssetsCheck,
    [switch]$FetchBuildAssets,
    [switch]$NoAutoFetchBuildAssets
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

function Get-RequiredBuildAssetNames {
    return @('multiplayer.assetbundle', 'MultiplayerEditor.dll', 'UnityChan.dll')
}

function Get-ReleaseDownloadUrl {
    $releasesJson = Join-Path $repoRoot 'releases.json'
    if (Test-Path -LiteralPath $releasesJson) {
        $data = Get-Content -LiteralPath $releasesJson -Raw | ConvertFrom-Json
        $entry = @($data.Releases | Where-Object { $_.Id -eq 'Multiplayer' } | Select-Object -First 1)[0]
        if ($entry -and $entry.DownloadUrl) {
            return $entry.DownloadUrl
        }
    }
    return 'https://github.com/AMacro/dv-multiplayer/releases/download/v0.1.14.0-Beta/Multiplayer.0.1.14.0.zip'
}

function Install-BuildAssetsFromRelease {
    $url = Get-ReleaseDownloadUrl
    $zipPath = Join-Path $env:TEMP 'dv-multiplayer-release.zip'
    $extractPath = Join-Path $env:TEMP 'dv-multiplayer-release-extract'

    Write-Host "Downloading release assets..." -ForegroundColor Cyan
    Write-Host "  $url"
    Invoke-WebRequest -Uri $url -OutFile $zipPath -UseBasicParsing

    if (Test-Path -LiteralPath $extractPath) {
        Remove-Item -LiteralPath $extractPath -Recurse -Force
    }
    Expand-Archive -LiteralPath $zipPath -DestinationPath $extractPath -Force

    if (-not (Test-Path -LiteralPath $buildDir)) {
        New-Item -ItemType Directory -Path $buildDir | Out-Null
    }

    foreach ($name in (Get-RequiredBuildAssetNames)) {
        $found = Get-ChildItem -Path $extractPath -Filter $name -Recurse -File -ErrorAction SilentlyContinue |
            Select-Object -First 1
        if (-not $found) {
            throw "Release zip does not contain $name"
        }
        Copy-Item -LiteralPath $found.FullName -Destination (Join-Path $buildDir $name) -Force
        Write-Host "  build\$name" -ForegroundColor Green
    }

    Remove-Item -LiteralPath $zipPath -Force -ErrorAction SilentlyContinue
}

function Test-BuildAssets {
    $missing = @()
    foreach ($name in (Get-RequiredBuildAssetNames)) {
        if (-not (Test-Path -LiteralPath (Join-Path $buildDir $name))) {
            $missing += $name
        }
    }
    if ($missing.Count -eq 0) { return $true }

    Write-Warning "build/ is missing: $($missing -join ', ')"
    return $false
}

function Ensure-BuildAssets {
    if (Test-BuildAssets) { return }

    if ($FetchBuildAssets -or (-not $NoAutoFetchBuildAssets -and -not $SkipUnityAssetsCheck)) {
        Install-BuildAssetsFromRelease
        if (Test-BuildAssets) { return }
    }

    Write-Warning "Build Unity assets (Multiplayer > Build Asset Bundle and Scripts) or run: .\scripts\Build-Mod.ps1 -FetchBuildAssets"
    throw "Cannot compile Multiplayer without build/ assets. Use -SkipUnityAssetsCheck only if you know what you are doing."
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
    Ensure-BuildAssets
}
elseif ($FetchBuildAssets) {
    Install-BuildAssetsFromRelease
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
