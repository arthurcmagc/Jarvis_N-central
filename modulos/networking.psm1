# networking.psm1
# Compatível com PS 5.1 e 7+. Sem uso de ?. ou ??.

function Get-ActiveAdapterInfo {
    [CmdletBinding()]
    param()

    # 1) Tenta Get-NetIPConfiguration / Get-NetAdapter (Win10+)
    try {
        $ipcfg = Get-NetIPConfiguration -Detailed -ErrorAction Stop |
                 Where-Object { $_.IPv4Address -and $_.NetAdapter.Status -eq 'Up' } |
                 Select-Object -First 1
        if ($null -ne $ipcfg) {
            $iface  = if ($ipcfg.NetAdapter.InterfaceDescription) { $ipcfg.NetAdapter.InterfaceDescription } else { $ipcfg.InterfaceAlias }
            $ipv4   = if ($ipcfg.IPv4Address.IPAddress) { $ipcfg.IPv4Address.IPAddress } else { $null }
            $gw     = $null
            if ($ipcfg.IPv4DefaultGateway -and $ipcfg.IPv4DefaultGateway.NextHop) { $gw = $ipcfg.IPv4DefaultGateway.NextHop }

            $dnsArr = @()
            if ($ipcfg.DnsServer -and $ipcfg.DnsServer.ServerAddresses) { $dnsArr = $ipcfg.DnsServer.ServerAddresses }
            elseif ($ipcfg.DnsServer) { $dnsArr = @($ipcfg.DnsServer) }
            $dns = if ($dnsArr -and $dnsArr.Count -gt 0) { ($dnsArr -join ', ') } else { $null }

            return [pscustomobject]@{
                Interface = $iface
                IPv4      = $ipv4
                Gateway   = $gw
                DNS       = $dns
            }
        }
    } catch {}

    # 2) Fallback WMI (PS 5.1/legacy)
    try {
        $nics = Get-CimInstance -ClassName Win32_NetworkAdapterConfiguration -Filter "IPEnabled=TRUE" -ErrorAction Stop
        foreach ($n in $nics) {
            # Pega o primeiro com IPv4
            $ipv4 = $null
            if ($n.IPAddress) {
                foreach ($ip in $n.IPAddress) {
                    if ($ip -match '^\d{1,3}(\.\d{1,3}){3}$') { $ipv4 = $ip; break }
                }
            }
            if ($null -ne $ipv4) {
                $dns = $null
                if ($n.DNSServerSearchOrder) { $dns = ($n.DNSServerSearchOrder -join ', ') }

                $iface = $n.Description
                $gw    = $null
                if ($n.DefaultIPGateway -and $n.DefaultIPGateway.Length -gt 0) { $gw = $n.DefaultIPGateway[0] }

                return [pscustomobject]@{
                    Interface = $iface
                    IPv4      = $ipv4
                    Gateway   = $gw
                    DNS       = $dns
                }
            }
        }
    } catch {}

    return $null
}

function Test-LatencyMs {
    [CmdletBinding()]
    param(
        [string]$Target = "8.8.8.8",
        [int]$Count = 3,
        [int]$TimeoutMs = 1500
    )
    try {
        # PS 7+: objetos têm propriedade .Latency
        $tc = Test-Connection -TargetName $Target -Count $Count -TimeoutMilliseconds $TimeoutMs -ErrorAction Stop
        $lat = $null
        try {
            $lat = ($tc | Select-Object -ExpandProperty Latency -ErrorAction Stop | Measure-Object -Average).Average
        } catch {
            # PS 5.1: usa ResponseTime
            $lat = ($tc | Select-Object -ExpandProperty ResponseTime -ErrorAction Stop | Measure-Object -Average).Average
        }
        if ($null -ne $lat) { return [int][math]::Round($lat,0) }
    } catch {}
    return $null
}

function Get-NetworkStatus {
    [CmdletBinding()]
    param()

    try {
        $info = Get-ActiveAdapterInfo
        if ($null -eq $info) {
            return [pscustomobject]@{ Error = "Nenhuma interface ativa com IPv4 foi encontrada." }
        }

        $lat = Test-LatencyMs
        $status = if ($null -ne $lat -or $info.IPv4) { "Conectado" } else { "Desconectado" }

        # Normaliza DNS para string
        $dnsOut = $info.DNS
        if ($null -eq $dnsOut -and $info.DNS -is [array]) { $dnsOut = ($info.DNS -join ', ') }

        return [pscustomobject]@{
            Interface  = $info.Interface
            IPv4       = if ($info.IPv4) { $info.IPv4 } else { $null }
            Gateway    = if ($info.Gateway) { $info.Gateway } else { $null }
            DNS        = $dnsOut
            Status     = $status
            LatenciaMs = $lat
        }
    } catch {
        return [pscustomobject]@{ Error = "Falha na coleta de rede: $($_.Exception.Message)" }
    }
}

Export-ModuleMember -Function Get-NetworkStatus
