function Invoke-TestLobbyApi {
    param(
        [Parameter(Mandatory)]
        $Report,
        [Parameter(Mandatory)]
        $Config
    )

    $base = ($Config.LobbyServerUrl -as [string]).TrimEnd('/')
    if ([string]::IsNullOrWhiteSpace($base)) {
        Add-Phase0TestResult -Report $Report -Name 'lobby.config' -Status 'Skip' -Message 'LobbyServerUrl not set'
        return
    }

    $url = "$base/list_game_servers"
    try {
        $response = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 15
        $ok = ($response.StatusCode -eq 200)
        $body = $response.Content
        $count = $null
        try {
            $json = $body | ConvertFrom-Json
            if ($json -is [Array]) { $count = $json.Count }
            elseif ($json.servers) { $count = @($json.servers).Count }
        }
        catch { }

        Add-Phase0TestResult -Report $Report -Name 'lobby.list' -Status $(if ($ok) { 'Pass' } else { 'Fail' }) `
            -Message "GET $url -> HTTP $($response.StatusCode)$(if ($null -ne $count) { ", ~$count servers" } else { '' })"
    }
    catch {
        Add-Phase0TestResult -Report $Report -Name 'lobby.list' -Status 'Fail' -Message "Lobby unreachable: $($_.Exception.Message)"
    }
}
