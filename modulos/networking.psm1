# networking.psm1
# Coleta de rede com latência/mediana/perda e objetos simples (sem CIM cru)

function Measure-Latency {
    param(
        [Parameter(Mandatory=$true)][string]$HostName,
        [int]$Count = 6,
        [int]$TimeoutMs = 500
    )

    $total = $Count
    $successTimes = @()

    # 1) Test-Connection (PS nativo)
    try {
        $replies = Test-Connection -TargetName $HostName -Count $Count -TimeoutMilliseconds $TimeoutMs -ErrorAction Stop
        foreach ($r in $replies) {
            if ($r.Status -eq 'Success' -and $r.ResponseTime -ge 0) {
                $successTimes += [double]$r.ResponseTime
            }
        }
    } catch {
        # 2) Fallback: ping.exe (parse "tempo=" pt-BR / "time=" en-US)
        try {
            $raw = & cmd.exe /c "ping -n $Count -w $TimeoutMs $HostName"
            if ($raw) {
                foreach ($line in $raw) {
                    if ($line -match 'tempo[=<]\s*(\d+)\s*ms' -or $line -match 'time[=<]\s*(\d+)\s*ms') {
                        $successTimes += [double]$Matches[1]
                    }
                }
            }
        } catch {}
    }

    $succ = $successTimes.Count
    $lossPct = if ($total -gt 0) { [math]::Round(((($total - $succ) / $total) * 100), 0) } else { 100 }

    if ($succ -gt 0) {
        $avg = [math]::Round(($successTimes | Measure-Object -Average).Average, 1)
        $sorted = $successTimes | Sort-Object
        $mid = [int][math]::Floor($sorted.Count/2)
        if (($sorted.Count % 2) -eq 0) {
            $med = [math]::Round((($sorted[$mid-1] + $sorted[$mid]) / 2), 1)
        } else {
            $med = [math]::Round($sorted[$mid], 1)
        }
        return [pscustomobject]@{
            Host    = $HostName
            AvgMs   = $avg
            MedMs   = $med
            LossPct = $lossPct
        }
    } else {
        return [pscustomobject]@{
            Host    = $HostName
            AvgMs   = $null
            MedMs   = $null
            LossPct = 100
        }
    }
}

function Get-SimpleDnsServers {
    try {
        $dns = Get-DnsClientServerAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue
        if ($dns) {
            $all = @()
            foreach ($d in $dns) {
                if ($d.ServerAddresses -and $d.ServerAddresses.Count -gt 0) {
                    $all += $d.ServerAddresses
                }
            }
            $all = $all | Where-Object { $_ -and $_.Trim().Length -gt 0 } | Select-Object -Unique
            return $all
        }
    } catch {}
    return @()
}

function Get-ActiveInterfaceInfo {
    try {
        $up = Get-NetAdapter -Physical | Where-Object { $_.Status -eq 'Up' } | Sort-Object -Property ifIndex | Select-Object -First 1
        if (-not $up) {
            $up = Get-NetAdapter | Where-Object { $_.Status -eq 'Up' } | Sort-Object -Property ifIndex | Select-Object -First 1
        }
        if ($up) {
            $ipcfg = Get-NetIPConfiguration -InterfaceIndex $up.ifIndex -ErrorAction SilentlyContinue
            $ipv4 = $null
            if ($ipcfg -and $ipcfg.IPv4Address) { $ipv4 = ($ipcfg.IPv4Address | Select-Object -First 1).IPv4Address }
            $gw = $null
            if ($ipcfg -and $ipcfg.IPv4DefaultGateway) { $gw = $ipcfg.IPv4DefaultGateway.NextHop }
            return [pscustomobject]@{
                Name    = $up.Name
                Status  = $up.Status
                IPv4    = $ipv4
                Gateway = $gw
            }
        }
    } catch {}
    return $null
}

function Test-InternetQuick {
    $ok = $false
    try {
        $null = Resolve-DnsName -Name one.one.one.one -ErrorAction Stop
        $ok = $true
    } catch {}
    if (-not $ok) {
        try {
            $ping = Measure-Latency -HostName '1.1.1.1' -Count 2 -TimeoutMs 400
            if ($ping -and $ping.LossPct -lt 100) { $ok = $true }
        } catch {}
    }
    return $ok
}

function Get-NetworkStatus {
    try {
        $iface   = Get-ActiveInterfaceInfo
        $dnsList = Get-SimpleDnsServers

        $targets = @('1.1.1.1','8.8.8.8')
        $lat     = @()
        foreach ($t in $targets) {
            $lat += Measure-Latency -HostName $t -Count 6 -TimeoutMs 500
        }

        $hasNet = Test-InternetQuick

        return [pscustomobject]@{
            HasInternetConnection = [bool]$hasNet
            Interfaces = if ($iface) { @($iface) } else { @() }
            DNS        = $dnsList
            Latency    = $lat
        }
    } catch {
        return [pscustomobject]@{ Error = $_.Exception.Message }
    }
}

Export-ModuleMember -Function Get-NetworkStatus
