# Shared helpers for Phase 0 dedicated-server feasibility tests.

function Get-Phase0Config {
    param(
        [Parameter(Mandatory)]
        [string]$ConfigPath
    )

    if (-not (Test-Path -LiteralPath $ConfigPath)) {
        throw "Config not found: $ConfigPath. Copy phase0.config.example.json to phase0.config.json"
    }

    return (Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json)
}

function New-Phase0Report {
    param([string]$HostProfile)

    return [ordered]@{
        schemaVersion = 1
        startedAt     = (Get-Date).ToUniversalTime().ToString('o')
        completedAt   = $null
        hostProfile   = $HostProfile
        machine       = [ordered]@{
            name   = $env:COMPUTERNAME
            os     = [System.Environment]::OSVersion.VersionString
            is64   = [Environment]::Is64BitOperatingSystem
        }
        summary       = [ordered]@{
            passed = 0
            failed = 0
            skipped = 0
            warnings = 0
        }
        tests         = @()
        goNoGo        = $null
        notes         = @()
    }
}

function Add-Phase0TestResult {
    param(
        [Parameter(Mandatory)]
        $Report,
        [Parameter(Mandatory)]
        [string]$Name,
        [ValidateSet('Pass', 'Fail', 'Skip', 'Warn')]
        [string]$Status,
        [string]$Message = '',
        [object]$Details = $null
    )

    $Report.tests += [ordered]@{
        name      = $Name
        status    = $Status
        message   = $Message
        timestamp = (Get-Date).ToUniversalTime().ToString('o')
        details   = $Details
    }

    switch ($Status) {
        'Pass' { $Report.summary.passed++ }
        'Fail' { $Report.summary.failed++ }
        'Skip' { $Report.summary.skipped++ }
        'Warn' { $Report.summary.warnings++ }
    }
}

function Write-Phase0Report {
    param(
        [Parameter(Mandatory)]
        $Report,
        [Parameter(Mandatory)]
        [string]$ReportPath
    )

    $Report.completedAt = (Get-Date).ToUniversalTime().ToString('o')

    $fail = $Report.summary.failed
    $warn = $Report.summary.warnings

    if ($fail -gt 0) {
        $Report.goNoGo = 'NoGo'
    }
    elseif ($warn -gt 0) {
        $Report.goNoGo = 'ConditionalGo'
    }
    else {
        $Report.goNoGo = 'Go'
    }

    $dir = Split-Path -Parent $ReportPath
    if ($dir -and -not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }

    $Report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $ReportPath -Encoding UTF8
    return $Report
}

function Resolve-DvPaths {
    param($Config)

    $dvDir = $Config.DvInstallDir
    $exe = Join-Path $dvDir 'DerailValley.exe'
    $mods = Join-Path $dvDir 'Mods'
    $modDir = Join-Path $mods $Config.ModFolderName
    $infoJson = Join-Path $modDir 'info.json'
    $assetBundle = Join-Path $modDir 'multiplayer.assetbundle'
    $logFile = Join-Path $dvDir $Config.LogFileName

    return [ordered]@{
        DvInstallDir = $dvDir
        GameExe      = $exe
        ModsDir      = $mods
        ModDir       = $modDir
        InfoJson     = $infoJson
        AssetBundle  = $assetBundle
        LogFile      = $logFile
    }
}

function Test-PathExists {
    param([string]$Path, [string]$Label)
    if (Test-Path -LiteralPath $Path) {
        return @{ ok = $true; message = "$Label found: $Path" }
    }
    return @{ ok = $false; message = "$Label missing: $Path" }
}

function Get-ProcessSamples {
    param(
        [string]$ProcessName = 'DerailValley',
        [int]$DurationSeconds = 60,
        [int]$IntervalSeconds = 5
    )

    $samples = @()
    $end = (Get-Date).AddSeconds($DurationSeconds)

    while ((Get-Date) -lt $end) {
        $proc = Get-Process -Name $ProcessName -ErrorAction SilentlyContinue
        if ($proc) {
            $samples += [ordered]@{
                time       = (Get-Date).ToUniversalTime().ToString('o')
                cpuSeconds = [math]::Round(($proc | Measure-Object CPU -Sum).Sum, 2)
                ramMb      = [math]::Round((($proc | Measure-Object WorkingSet64 -Sum).Sum / 1MB), 1)
                count      = @($proc).Count
            }
        }
        else {
            $samples += [ordered]@{
                time  = (Get-Date).ToUniversalTime().ToString('o')
                alive = $false
            }
        }
        Start-Sleep -Seconds $IntervalSeconds
    }

    return $samples
}

function Test-LogPatterns {
    param(
        [string]$LogPath,
        [string[]]$SuccessPatterns,
        [string[]]$FailurePatterns,
        [int]$TailLines = 500
    )

    if (-not (Test-Path -LiteralPath $LogPath)) {
        return @{
            ok = $false
            message = "Log file not found: $LogPath"
            successes = @()
            failures = @()
        }
    }

    $lines = Get-Content -LiteralPath $LogPath -Tail $TailLines -ErrorAction SilentlyContinue
    $text = $lines -join "`n"

    $successes = @()
    foreach ($p in $SuccessPatterns) {
        if ($text -match $p) { $successes += $p }
    }

    $failures = @()
    foreach ($p in $FailurePatterns) {
        if ($text -match $p) { $failures += $p }
    }

    return @{
        ok        = ($failures.Count -eq 0 -and $successes.Count -gt 0)
        message   = "Matched $($successes.Count) success / $($failures.Count) failure patterns"
        successes = $successes
        failures  = $failures
        tail      = $lines | Select-Object -Last 30
    }
}

function Test-UdpPortListening {
    param([int]$Port)

    $endpoints = Get-NetUDPEndpoint -LocalPort $Port -ErrorAction SilentlyContinue |
        Where-Object { $_.LocalAddress -notin @('0.0.0.0', '::') -or $true }

    # Any listener on the port counts (including 0.0.0.0)
    $all = Get-NetUDPEndpoint -LocalPort $Port -ErrorAction SilentlyContinue
    return @{
        listening = ($null -ne $all -and $all.Count -gt 0)
        endpoints = @($all | ForEach-Object { "$($_.LocalAddress):$($_.LocalPort)" })
    }
}
