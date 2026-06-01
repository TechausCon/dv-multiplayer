#Requires -Version 5.1
<#
.SYNOPSIS
    Phase 0 feasibility tests for DV Multiplayer dedicated server (Windows).

.DESCRIPTION
    Automates environment, network, lobby API, optional game launch smoke, and session monitoring.
    In-game Career host + Steam join still require manual steps (see README.md).

.PARAMETER ConfigPath
    Path to phase0.config.json (default: ./phase0.config.json)

.PARAMETER HostProfile
    Label for report: HomePC, Hetzner, Client, etc.

.PARAMETER SessionMonitor
    Monitor running DerailValley.exe (host must already be running).

.PARAMETER ClientOnly
    Only environment skip + network remote probes (run on second PC).

.PARAMETER LaunchSmoke
    Override config LaunchSmokeTest to start game automatically.

.EXAMPLE
    .\Invoke-Phase0Tests.ps1 -HostProfile HomePC

.EXAMPLE
    # After hosting Career on server machine:
    .\Invoke-Phase0Tests.ps1 -HostProfile HomePC -SessionMonitor

.EXAMPLE
    # From laptop joining Hetzner server:
    .\Invoke-Phase0Tests.ps1 -HostProfile Client -ClientOnly
#>
[CmdletBinding()]
param(
    [string]$ConfigPath = (Join-Path $PSScriptRoot 'phase0.config.json'),
    [string]$HostProfile = 'Windows',
    [switch]$SessionMonitor,
    [switch]$ClientOnly,
    [switch]$LaunchSmoke
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$lib = Join-Path $PSScriptRoot 'lib\Phase0.Common.ps1'
. $lib

$tests = @(
    'Test-Environment.ps1',
    'Test-Network.ps1',
    'Test-LobbyApi.ps1',
    'Test-GameLaunch.ps1',
    'Test-SessionMonitor.ps1'
)

foreach ($t in $tests) {
    . (Join-Path $PSScriptRoot "tests\$t")
}

$config = Get-Phase0Config -ConfigPath $ConfigPath

if ($SessionMonitor) {
    if (-not $config.SessionMonitor) {
        $config | Add-Member -NotePropertyName SessionMonitor -NotePropertyValue (@{}) -Force
    }
    $config.SessionMonitor.Enabled = $true
}

if ($LaunchSmoke) {
    $config.LaunchSmokeTest = $true
}

$reportDir = Join-Path $PSScriptRoot 'reports'
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$reportPath = Join-Path $reportDir "phase0-$HostProfile-$stamp.json"

$report = New-Phase0Report -HostProfile $HostProfile

Write-Host "=== DV Multiplayer Phase 0 ===" -ForegroundColor Cyan
Write-Host "Profile: $HostProfile"
Write-Host "Config:  $ConfigPath"
Write-Host ""

if ($ClientOnly) {
    Invoke-TestNetwork -Report $report -Config $config
}
else {
    Invoke-TestEnvironment -Report $report -Config $config
    Invoke-TestLobbyApi -Report $report -Config $config
    Invoke-TestNetwork -Report $report -Config $config
    Invoke-TestGameLaunch -Report $report -Config $config
    Invoke-TestSessionMonitor -Report $report -Config $config
}

$report = Write-Phase0Report -Report $report -ReportPath $reportPath

Write-Host ""
Write-Host "=== Summary ===" -ForegroundColor Cyan
Write-Host "Pass:    $($report.summary.passed)"
Write-Host "Fail:    $($report.summary.failed)"
Write-Host "Warn:    $($report.summary.warnings)"
Write-Host "Skip:    $($report.summary.skipped)"
Write-Host "Go/NoGo: $($report.goNoGo)" -ForegroundColor $(switch ($report.goNoGo) {
        'Go' { 'Green' }
        'ConditionalGo' { 'Yellow' }
        default { 'Red' }
    })
Write-Host "Report:  $reportPath"

if ($report.notes.Count) {
    Write-Host ""
    Write-Host "Notes:" -ForegroundColor Cyan
    foreach ($n in $report.notes) { Write-Host "  - $n" }
}

if ($report.summary.failed -gt 0) { exit 1 }
exit 0
