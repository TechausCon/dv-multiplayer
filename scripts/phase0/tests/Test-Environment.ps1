function Invoke-TestEnvironment {
    param(
        [Parameter(Mandatory)]
        $Report,
        [Parameter(Mandatory)]
        $Config
    )

    if ($PSVersionTable.PSEdition -ne 'Desktop' -and $PSVersionTable.Platform -eq 'Unix') {
        Add-Phase0TestResult -Report $Report -Name 'os.windows' -Status 'Skip' -Message 'Environment tests target Windows (run on Hetzner or home PC)'
        return
    }

    $os = [System.Environment]::OSVersion
    if ($os.Platform -ne 'Win32NT') {
        Add-Phase0TestResult -Report $Report -Name 'os.windows' -Status 'Fail' -Message "Not Windows: $($os.VersionString)"
        return
    }
    Add-Phase0TestResult -Report $Report -Name 'os.windows' -Status 'Pass' -Message $os.VersionString

    $paths = Resolve-DvPaths -Config $Config

    $checks = @(
        @{ name = 'game.exe'; path = $paths.GameExe; label = 'DerailValley.exe' },
        @{ name = 'mod.dir'; path = $paths.ModDir; label = 'Mod folder' },
        @{ name = 'mod.info'; path = $paths.InfoJson; label = 'info.json' },
        @{ name = 'mod.assetbundle'; path = $paths.AssetBundle; label = 'multiplayer.assetbundle' }
    )

    foreach ($c in $checks) {
        $r = Test-PathExists -Path $c.path -Label $c.label
        Add-Phase0TestResult -Report $Report -Name $c.name -Status $(if ($r.ok) { 'Pass' } else { 'Fail' }) -Message $r.message
    }

    if (Test-Path -LiteralPath $paths.InfoJson) {
        try {
            $info = Get-Content -LiteralPath $paths.InfoJson -Raw | ConvertFrom-Json
            $verOk = ($info.Version -eq $Config.ExpectedModVersion)
            Add-Phase0TestResult -Report $Report -Name 'mod.version' -Status $(if ($verOk) { 'Pass' } else { 'Warn' }) `
                -Message "Installed $($info.Version), expected $($Config.ExpectedModVersion)" `
                -Details $info
            $ummOk = ($info.ManagerVersion -eq $Config.ExpectedUmmVersion)
            Add-Phase0TestResult -Report $Report -Name 'umm.version' -Status $(if ($ummOk) { 'Pass' } else { 'Warn' }) `
                -Message "UMM $($info.ManagerVersion), expected $($Config.ExpectedUmmVersion)"
        }
        catch {
            Add-Phase0TestResult -Report $Report -Name 'mod.info.parse' -Status 'Fail' -Message $_.Exception.Message
        }
    }

    if ($Config.SteamExe) {
        $r = Test-PathExists -Path $Config.SteamExe -Label 'Steam'
        Add-Phase0TestResult -Report $Report -Name 'steam.exe' -Status $(if ($r.ok) { 'Pass' } else { 'Warn' }) -Message $r.message
    }

    # Optional: detect display / GPU (Hetzner often has none)
    try {
        $video = Get-CimInstance Win32_VideoController -ErrorAction Stop | Select-Object Name, AdapterRAM
        $hasGpu = @($video | Where-Object { $_.Name -notmatch 'Microsoft Basic|Remote' }).Count -gt 0
        Add-Phase0TestResult -Report $Report -Name 'hardware.gpu' -Status $(if ($hasGpu) { 'Pass' } else { 'Warn' }) `
            -Message $(if ($hasGpu) { 'GPU detected' } else { 'No dedicated GPU. Batchmode may fail on VPS.' }) `
            -Details $video
    }
    catch {
        Add-Phase0TestResult -Report $Report -Name 'hardware.gpu' -Status 'Skip' -Message 'Could not query GPU'
    }

    $ramGb = [math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB, 1)
    $ramStatus = if ($ramGb -ge 16) { 'Pass' } elseif ($ramGb -ge 8) { 'Warn' } else { 'Fail' }
    Add-Phase0TestResult -Report $Report -Name 'hardware.ram' -Status $ramStatus -Message "${ramGb} GB RAM (recommend >= 16 GB for dedicated host)"
}
