function Invoke-TestGameLaunch {
    param(
        [Parameter(Mandatory)]
        $Report,
        [Parameter(Mandatory)]
        $Config
    )

    if (-not $Config.LaunchSmokeTest) {
        Add-Phase0TestResult -Report $Report -Name 'launch.smoke' -Status 'Skip' `
            -Message 'LaunchSmokeTest=false. Set true in config to auto-start DerailValley.exe'
        return
    }

    $paths = Resolve-DvPaths -Config $Config
    if (-not (Test-Path -LiteralPath $paths.GameExe)) {
        Add-Phase0TestResult -Report $Report -Name 'launch.smoke' -Status 'Fail' -Message 'Game exe missing'
        return
    }

    # Remove stale log for clean signal
    if (Test-Path -LiteralPath $paths.LogFile) {
        Remove-Item -LiteralPath $paths.LogFile -Force -ErrorAction SilentlyContinue
    }

    $args = @()
    if ($Config.LaunchArgs) { $args += @($Config.LaunchArgs) }

    $wd = $paths.DvInstallDir
    $timeout = [int]$Config.SmokeTestTimeoutSeconds
    if ($timeout -lt 30) { $timeout = 30 }

    Add-Phase0TestResult -Report $Report -Name 'launch.start' -Status 'Pass' `
        -Message "Starting $($paths.GameExe) $($args -join ' ') (timeout ${timeout}s)"

    $proc = Start-Process -FilePath $paths.GameExe -ArgumentList $args -WorkingDirectory $wd -PassThru

    $deadline = (Get-Date).AddSeconds($timeout)
    $logResult = $null

    while ((Get-Date) -lt $deadline) {
        if ($proc.HasExited) {
            break
        }
        if (Test-Path -LiteralPath $paths.LogFile) {
            $logResult = Test-LogPatterns -LogPath $paths.LogFile `
                -SuccessPatterns $Config.LogSuccessPatterns `
                -FailurePatterns $Config.LogFailurePatterns
            if ($logResult.ok) { break }
            if ($logResult.failures.Count -gt 0) { break }
        }
        Start-Sleep -Seconds 3
    }

    if ($proc.HasExited) {
        Add-Phase0TestResult -Report $Report -Name 'launch.exit' -Status 'Fail' `
            -Message "Game exited early with code $($proc.ExitCode)" -Details @{ exitCode = $proc.ExitCode }
    }
    else {
        Add-Phase0TestResult -Report $Report -Name 'launch.running' -Status 'Pass' `
            -Message "Process still running after $timeout s (PID $($proc.Id))"
    }

    if ($logResult) {
        Add-Phase0TestResult -Report $Report -Name 'launch.mod_log' -Status $(if ($logResult.ok) { 'Pass' } else { 'Fail' }) `
            -Message $logResult.message -Details $logResult
    }
    else {
        Add-Phase0TestResult -Report $Report -Name 'launch.mod_log' -Status 'Fail' `
            -Message "No $($Config.LogFileName) or patterns not matched within ${timeout}s"
    }

    if ($Config.SmokeTestKillOnComplete -and -not $proc.HasExited) {
        Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
        Add-Phase0TestResult -Report $Report -Name 'launch.cleanup' -Status 'Pass' -Message 'Stopped game process after smoke test'
    }
}
