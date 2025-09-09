# =========================================
# Módulo de Rede: Coleta informações de conectividade e adaptadores.
# =========================================

function Get-NetworkStatus {
    try {
        $adapters = Get-NetAdapter -Physical | Where-Object {$_.Status -eq "Up"} | ForEach-Object {
            [pscustomobject]@{
                Name = $_.Name
                Status = $_.Status
                MacAddress = $_.MacAddress
                LinkSpeedMbps = $_.LinkSpeed / 1MB
            }
        }

        $pingGoogle = Test-Connection -ComputerName "8.8.8.8" -Count 2 -Quiet

        return [pscustomobject]@{
            Adapters = $adapters
            InternetConnected = $pingGoogle
        }
    } catch {
        return [pscustomobject]@{ Error = "Falha na coleta de dados de rede: $($_.Exception.Message)" }
    }
}

Export-ModuleMember -Function Get-NetworkStatus
