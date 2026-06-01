function Invoke-TestNetwork {
    param(
        [Parameter(Mandatory)]
        $Report,
        [Parameter(Mandatory)]
        $Config
    )

    $port = [int]$Config.GamePort

    # Firewall rule hint (does not create rules automatically)
    $ruleName = "DV-Multiplayer-UDP-$port"
    $existing = Get-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue
    if ($existing) {
        $fwMsg = "Firewall rule exists: $ruleName"
        $fwStatus = 'Pass'
    }
    else {
        $fwMsg = "No rule '$ruleName'. Open UDP/TCP port $port manually for internet joins."
        $fwStatus = 'Warn'
    }
    Add-Phase0TestResult -Report $Report -Name 'firewall.rule' -Status $fwStatus -Message $fwMsg

    # If game is running, check UDP listener
    $udp = Test-UdpPortListening -Port $port
    if ($udp.listening) {
        Add-Phase0TestResult -Report $Report -Name 'udp.listening' -Status 'Pass' `
            -Message "UDP $port is listening" -Details $udp.endpoints
    }
    else {
        Add-Phase0TestResult -Report $Report -Name 'udp.listening' -Status 'Skip' `
            -Message "UDP $port not listening (start game and host first, or use -SessionMonitor)"
    }

    # Remote join probe (from client machine or when RemoteServerHost set)
    $remoteHost = $Config.RemoteServerHost
    if ($remoteHost) {
        $remotePort = [int]$Config.RemoteServerPort
        $resolved = [System.Net.Dns]::GetHostAddresses($remoteHost) | Where-Object { $_.AddressFamily -eq 'InterNetwork' } | Select-Object -First 1
        if (-not $resolved) {
            Add-Phase0TestResult -Report $Report -Name 'remote.dns' -Status 'Fail' -Message "Could not resolve IPv4 for $remoteHost"
            return
        }
        Add-Phase0TestResult -Report $Report -Name 'remote.dns' -Status 'Pass' -Message "$remoteHost -> $($resolved.IPAddressToString)"

        # TCP reachability (game may be UDP-only; still useful for SSH/RDP diagnostics)
        $tcp = Test-NetConnection -ComputerName $remoteHost -Port $remotePort -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
        Add-Phase0TestResult -Report $Report -Name 'remote.tcp_probe' -Status 'Warn' `
            -Message "TCP probe to ${remoteHost}:${remotePort}: $($tcp.TcpTestSucceeded) (multiplayer uses UDP; use in-game join to confirm)"

        # UDP send smoke (does not validate LiteNetLib protocol)
        try {
            $udpClient = New-Object System.Net.Sockets.UdpClient
            $udpClient.Client.ReceiveTimeout = 3000
            $bytes = [System.Text.Encoding]::ASCII.GetBytes('phase0-probe')
            $null = $udpClient.Send($bytes, $bytes.Length, $remoteHost, $remotePort)
            $remote = New-Object System.Net.IPEndPoint ([System.Net.IPAddress]::Any, 0)
            $reply = $udpClient.Receive([ref]$remote)
            Add-Phase0TestResult -Report $Report -Name 'remote.udp_reply' -Status 'Warn' `
                -Message "Unexpected UDP reply ($($reply.Length) bytes). Game does not implement phase0 probe."
        }
        catch [System.Net.Sockets.SocketException] {
            Add-Phase0TestResult -Report $Report -Name 'remote.udp_reply' -Status 'Pass' `
                -Message "No UDP reply (expected). Confirm join in-game; check firewall/NAT if join fails."
        }
        finally {
            if ($udpClient) { $udpClient.Close() }
        }
    }
    else {
        Add-Phase0TestResult -Report $Report -Name 'remote.join' -Status 'Skip' `
            -Message 'Set RemoteServerHost in config for automated remote reachability hints'
    }

    # Public IP (for Hetzner docs)
    try {
        $ip = (Invoke-WebRequest -Uri 'https://api.ipify.org' -UseBasicParsing -TimeoutSec 10).Content.Trim()
        Add-Phase0TestResult -Report $Report -Name 'network.public_ip' -Status 'Pass' -Message "Public IPv4: $ip"
        $Report.notes += "Share with clients: ${ip}:$port (UDP)"
    }
    catch {
        Add-Phase0TestResult -Report $Report -Name 'network.public_ip' -Status 'Warn' -Message $_.Exception.Message
    }
}
