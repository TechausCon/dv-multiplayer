function Invoke-TestSessionMonitor {
    param(
        [Parameter(Mandatory)]
        $Report,
        [Parameter(Mandatory)]
        $Config
    )

    $mon = $Config.SessionMonitor
    if (-not $mon -or -not $mon.Enabled) {
        Add-Phase0TestResult -Report $Report -Name 'session.monitor' -Status 'Skip' `
            -Message 'SessionMonitor.Enabled=false. Host Career in-game, then re-run with -SessionMonitor'
        return
    }

    $duration = [int]$mon.DurationSeconds
    $interval = [int]$mon.SampleIntervalSeconds
    if ($duration -lt 30) { $duration = 30 }
    if ($interval -lt 5) { $interval = 5 }

    $paths = Resolve-DvPaths -Config $Config
    $port = [int]$Config.GamePort

    $proc = Get-Process -Name 'DerailValley' -ErrorAction SilentlyContinue
    if (-not $proc) {
        Add-Phase0TestResult -Report $Report -Name 'session.process' -Status 'Fail' `
            -Message 'DerailValley.exe not running. Start game and host before -SessionMonitor.'
        return
    }

    Add-Phase0TestResult -Report $Report -Name 'session.process' -Status 'Pass' `
        -Message "Monitoring PID(s): $(@($proc.Id) -join ', ') for ${duration}s"

    $samples = Get-ProcessSamples -DurationSeconds $duration -IntervalSeconds $interval
    $aliveSamples = @($samples | Where-Object { $_.ramMb })
    $maxRam = ($aliveSamples | Measure-Object ramMb -Maximum).Maximum
    $avgRam = if ($aliveSamples.Count) { [math]::Round(($aliveSamples | Measure-Object ramMb -Average).Average, 1) } else { 0 }

    Add-Phase0TestResult -Report $Report -Name 'session.performance' -Status $(if ($maxRam -le 16384) { 'Pass' } elseif ($maxRam -le 24576) { 'Warn' } else { 'Fail' }) `
        -Message "RAM peak ${maxRam} MB, avg ${avgRam} MB" -Details @{ samples = $samples }

    $udpSeen = $false
    $logServerOk = $false
    $deadline = (Get-Date).AddSeconds($duration)

    while ((Get-Date) -lt $deadline) {
        if (-not $udpSeen) {
            $udp = Test-UdpPortListening -Port $port
            if ($udp.listening) { $udpSeen = $true }
        }
        if (Test-Path -LiteralPath $paths.LogFile) {
            $log = Test-LogPatterns -LogPath $paths.LogFile `
                -SuccessPatterns $Config.LogServerPatterns `
                -FailurePatterns $Config.LogFailurePatterns `
                -TailLines 200
            if ($log.successes.Count -gt 0) { $logServerOk = $true }
        }
        Start-Sleep -Seconds $interval
    }

    if ($mon.RequireUdpPortListening) {
        Add-Phase0TestResult -Report $Report -Name 'session.udp' -Status $(if ($udpSeen) { 'Pass' } else { 'Fail' }) `
            -Message $(if ($udpSeen) { "UDP $port was listening during session" } else { "UDP $port never listened. Is server hosted?" })
    }

    Add-Phase0TestResult -Report $Report -Name 'session.server_log' -Status $(if ($logServerOk) { 'Pass' } else { 'Warn' }) `
        -Message $(if ($logServerOk) { 'Server log patterns detected' } else { 'No server patterns in log. Host may not be started.' })

    $logResult = Test-LogPatterns -LogPath $paths.LogFile `
        -SuccessPatterns $Config.LogSuccessPatterns `
        -FailurePatterns $Config.LogFailurePatterns
    Add-Phase0TestResult -Report $Report -Name 'session.mod_log' -Status $(if ($logResult.failures.Count -eq 0) { 'Pass' } else { 'Fail' }) `
        -Message $logResult.message -Details $logResult
}
