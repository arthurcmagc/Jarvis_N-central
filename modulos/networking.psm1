# networking.psm1
# Coleta de status de rede com fallback de latência (ICMP -> HTTP) e DNS formatado.

function Get-PrimaryInterfaceInfo {
    try {
        $adapters = Get-NetAdapter -Physical -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq 'Up' }
        if (-not $adapters) { $adapters = Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq 'Up' } }
        $primary = $adapters | Sort-Object -Property ifIndex | Select-Object -First 1
        if (-not $primary) { return $null }

        $ipcfg = Get-NetIPConfiguration -InterfaceIndex $primary.ifIndex -ErrorAction SilentlyContinue
        if (-not $ipcfg) { return $null }

        $ipv4   = $ipcfg.IPv4Address.IPAddress | Select-Object -First 1
        $gw     = $ipcfg.IPv4DefaultGateway.NextHop | Select-Object -First 1

        # DNS (apenas strings)
        $dnsSrv = (Get-DnsClientServerAddress -InterfaceIndex $primary.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue).ServerAddresses
        $dnsArr = @()
        if ($dnsSrv) { $dnsArr = $dnsSrv | ForEach-Object { "$_" } }

        [pscustomobject]@{
            Name           = $primary.Name
            InterfaceAlias = $ipcfg.InterfaceAlias
            IPv4           = $ipv4
            Gateway        = $gw
            DNS            = $dnsArr
        }
    } catch {
        return $null
    }
}

function Test-TargetLatencyICMP {
    param(
        [Parameter(Mandatory=$true)][string]$Target,
        [int]$Count = 4
    )
    try {
        $pings = Test-Connection -ComputerName $Target -Count $Count -ErrorAction SilentlyContinue
        if (-not $pings) { return $null }
        $rtts = $pings | Where-Object { $_.ResponseTime -ge 0 } | ForEach-Object { [double]$_.ResponseTime }
        if (-not $rtts -or $rtts.Count -eq 0) { return $null }
        $avg = [math]::Round(($rtts | Measure-Object -Average).Average, 1)
        $sorted = $rtts | Sort-Object
        $med = [math]::Round($sorted[[Math]::Floor(($sorted.Count-1)/2)], 1)
        $loss = [math]::Round(100 * (1 - ($rtts.Count / $Count)),0)
        return @{ AverageMs = $avg; MedianMs = $med; Loss = ("{0}%" -f $loss); Method = "ICMP" }
    } catch { return $null }
}

function Test-TargetLatencyHTTP {
    param([Parameter(Mandatory=$true)][string]$TargetUrl)
    try {
        $elapsed = (Measure-Command {
            try {
                try {
                    Invoke-WebRequest -Uri $TargetUrl -Method Head -TimeoutSec 5 -UseBasicParsing -ErrorAction Stop | Out-Null
                } catch {
                    Invoke-WebRequest -Uri $TargetUrl -Method Get  -TimeoutSec 5 -UseBasicParsing -ErrorAction Stop | Out-Null
                }
            } catch {}
        }).TotalMilliseconds
        $ms = [math]::Round([double]$elapsed, 1)
        return @{ AverageMs = $ms; MedianMs = $ms; Loss = "N/D (HTTP)"; Method = "HTTP" }
    } catch { return $null }
}

function Get-InternetReachability {
    $targetsIcmp = @('1.1.1.1','8.8.8.8')
    foreach ($t in $targetsIcmp) {
        try {
            $ok = Test-Connection -ComputerName $t -Count 1 -Quiet -ErrorAction SilentlyContinue
            if ($ok) { return $true }
        } catch {}
    }
    foreach ($u in @('http://1.1.1.1','http://dns.google')) {
        try {
            $elapsed = (Measure-Command { Invoke-WebRequest -Uri $u -Method Head -TimeoutSec 5 -UseBasicParsing -ErrorAction Stop | Out-Null }).TotalMilliseconds
            if ($elapsed -gt 0) { return $true }
        } catch {}
    }
    return $false
}

function Get-LatencyWithFallback {
    param([string[]]$Targets = @('1.1.1.1','8.8.8.8'))

    $result = @{}
    foreach ($t in $Targets) {
        $icmp = Test-TargetLatencyICMP -Target $t -Count 4
        if ($icmp) {
            $result[$t] = $icmp
            continue
        }
        $url = if ($t -eq '8.8.8.8') { 'http://dns.google' } else { "http://$t" }
        $http = Test-TargetLatencyHTTP -TargetUrl $url
        if ($http) { $result[$t] = $http }
        else { $result[$t] = @{ AverageMs = 'N/D'; MedianMs = 'N/D'; Loss = '100%'; Method = 'N/A' } }
    }
    return $result
}

function Get-NetworkStatus {
    try {
        $iface = Get-PrimaryInterfaceInfo
        $hasInternet = Get-InternetReachability
        $lat = Get-LatencyWithFallback -Targets @('1.1.1.1','8.8.8.8')

        $interfaceLabel = if ($iface) {
            $na = Get-NetAdapter -Name $iface.Name -ErrorAction SilentlyContinue
            $st = if ($na -and $na.Status) { $na.Status } else { "Unknown" }
            "$($iface.InterfaceAlias) ($st)"
        } else {
            "Indefinida"
        }

        [pscustomobject]@{
            HasInternetConnection = $hasInternet
            Interface             = $interfaceLabel
            IPv4                  = $iface?.IPv4
            Gateway               = $iface?.Gateway
            DNS                   = $iface?.DNS
            Latency               = $lat
        }
    } catch {
        [pscustomobject]@{ Error = "Falha na coleta de rede: $($_.Exception.Message)" }
    }
}

Export-ModuleMember -Function Get-NetworkStatus
