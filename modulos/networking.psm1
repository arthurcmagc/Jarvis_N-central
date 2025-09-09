# Módulo de Rede: Coleta informações sobre o status da conexão.

function Get-NetworkStatus {
    try {
        # Usamos Test-Connection para uma verificação de conectividade mais universal
        $isOnline = Test-Connection -ComputerName "8.8.8.8" -Count 1 -Quiet -ErrorAction SilentlyContinue

        # --- Aprimoramento para capturar o IP e MAC do adaptador principal ---
        # Filtra apenas por adaptadores conectados (NetConnectionStatus = 2) e com IP habilitado
        $networkAdapter = Get-CimInstance Win32_NetworkAdapter | Where-Object { $_.NetConnectionStatus -eq 2 }
        
        $ipAddress = "N/A"
        $macAddress = "N/A"
        
        if ($networkAdapter) {
            # Pega a configuração do adaptador principal
            $networkConfig = Get-CimInstance Win32_NetworkAdapterConfiguration -Filter "Index = $($networkAdapter.InterfaceIndex) and IPEnabled = 'True'"

            if ($networkConfig) {
                # Pega apenas o endereço IPv4, se disponível
                $ipAddress = $networkConfig.IPAddress | Where-Object { $_ -match '\.' }
                if (-not $ipAddress) {
                    $ipAddress = "N/A"
                }
            }
            # Captura o endereço MAC do adaptador principal
            $macAddress = $networkAdapter.MACAddress
        }
        # -------------------------------------------------------------------
        
        return [pscustomobject]@{
            HasInternetConnection = $isOnline
            IPAddress = $ipAddress
            MACAddress = $macAddress
        }

    } catch {
        return [pscustomobject]@{ Error = "Falha na coleta de dados de Rede: $($_.Exception.Message)" }
    }
}

Export-ModuleMember -Function Get-NetworkStatus