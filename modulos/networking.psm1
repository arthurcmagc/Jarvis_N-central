# networking.psm1
# Coleta de status de rede + latência

function Test-NetLatency {
    [CmdletBinding()]
    param(
        [string[]]$Targets = @('1.1.1.1','8.8.8.8'),
        [int]$Count = 4,
        [int]$TimeoutMs = 900
    )
    $out = foreach ($t in $Targets) {
        $rtts = @()
        for ($i=0; $i -lt $Count; $i++) {
            try {
                $tc = Test-Connection -ComputerName $t -Count 1 -ErrorAction Stop -TimeoutSeconds ([math]::Ceiling($TimeoutMs/1000))
                if ($tc) {
                    $ms = if ($tc.Latency) { [double]$tc.Latency } else { [double]$tc.ResponseTime }
                    if ($ms -gt 0) { $rtts += $ms }
                }
            } catch {}
            Start-Sleep -Milliseconds 120
        }
        if ($rtts.Count -gt 0) {
            [pscustomobject]@{
                Target  = $t
                Count   = $rtts.Count
                AvgMs   = [math]::Round(($rtts | Measure-Object -Average | Select-Object -ExpandProperty Average),1)
                MedMs   = [math]::Round(($rtts | Sort-Object | Select-Object -Index ([int][math]::Floor($rtts.Count/2))),1)
                MinMs   = [math]::Round(($rtts | Measure-Object -Minimum | Select-Object -ExpandProperty Minimum),1)
                MaxMs   = [math]::Round(($rtts | Measure-Object -Maximum | Select-Object -ExpandProperty Maximum),1)
                LossPct = [math]::Round((($Count - $rtts.Count) / $Count) * 100,0)
            }
        } else {
            [pscustomobject]@{ Target=$t; Count=0; AvgMs=$null; MedMs=$null; MinMs=$null; MaxMs=$null; LossPct=100 }
        }
    }
    return $out
}

function Get-DnsString {
    param($ipConfig)
    try {
        # NetTCPIP: $ipConfig.DnsServer.Address (array de IPs)
        if ($ipConfig -and $ipConfig.DnsServer -and $ipConfig.DnsServer.Address) {
            return ($ipConfig.DnsServer.Address | Where-Object { $_ } | ForEach-Object { "$_" }) -join ', '
        }
    } catch {}
    return "N/A"
}

function Get-NetworkSnapshot {
    [CmdletBinding()]
    param()
    $result = [ordered]@{
        InterfaceName = $null; Status = $null; MAC = $null
        IPv4 = $null; IPv6 = $null; Gateway = $null
        DNSServers = $null; LinkSpeed = $null; DHCPEnabled = $null
    }
    try {
        if (Get-Command Get-NetAdapter -ErrorAction Ignore) {
            $nic = Get-NetAdapter -Physical | Where-Object Status -ne 'Disabled' | Sort-Object -Property Status -Descending | Select-Object -First 1
            if ($nic) {
                $ip  = Get-NetIPConfiguration -InterfaceIndex $nic.ifIndex -ErrorAction SilentlyContinue
                $dns = Get-DnsString -ipConfig $ip
                $result.InterfaceName = $nic.Name
                $result.Status        = $nic.Status
                $result.MAC           = $nic.MacAddress
                $result.IPv4          = ($ip.IPv4Address.IPAddress | Select-Object -First 1)
                $result.IPv6          = ($ip.IPv6Address.IPAddress | Select-Object -First 1)
                $result.Gateway       = ($ip.IPv4DefaultGateway.NextHop | Select-Object -First 1)
                $result.DNSServers    = $dns
                $result.LinkSpeed     = $nic.LinkSpeed
                $result.DHCPEnabled   = $ip.IPv4Address -and $ip.NetProfile
            }
        } else {
            $cfg  = Get-WmiObject Win32_NetworkAdapterConfiguration -Filter "IPEnabled=TRUE" -ErrorAction SilentlyContinue | Select-Object -First 1
            $nic2 = if ($cfg) { Get-WmiObject Win32_NetworkAdapter -ErrorAction SilentlyContinue | Where-Object {$_.Index -eq $cfg.Index} }
            if ($cfg) {
                $result.InterfaceName = $nic2.NetConnectionID
                $result.Status        = if ($nic2.NetEnabled) {'Up'} else {'Down'}
                $result.MAC           = $cfg.MACAddress
                $result.IPv4          = ($cfg.IPAddress | Where-Object {$_ -match '\.'} | Select-Object -First 1)
                $result.IPv6          = ($cfg.IPAddress | Where-Object {$_ -match ':'} | Select-Object -First 1)
                $result.Gateway       = ($cfg.DefaultIPGateway | Select-Object -First 1)
                $result.DNSServers    = ($cfg.DNSServerSearchOrder -join ', ')
                $result.LinkSpeed     = $nic2.Speed
                $result.DHCPEnabled   = $cfg.DHCPEnabled
            }
        }
    } catch {}
    [pscustomobject]$result
}

function Get-NetworkStatus {
    [CmdletBinding()]
    param()
    try {
        $snap    = Get-NetworkSnapshot
        $latency = Test-NetLatency
        # internet = se há pelo menos 1 alvo com perda < 100%
        $hasNet  = $false
        foreach ($l in $latency) {
            if ($l -and $l.LossPct -lt 100) { $hasNet = $true; break }
        }
        [pscustomobject]@{
            Snapshot             = $snap
            HasInternetConnection= $hasNet
            Latency              = $latency
        }
    } catch {
        [pscustomobject]@{ Error = $_.Exception.Message }
    }
}

Export-ModuleMember -Function Test-NetLatency, Get-NetworkSnapshot, Get-NetworkStatus
