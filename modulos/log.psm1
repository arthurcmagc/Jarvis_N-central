# Módulo de Log: Centraliza a escrita de logs de execução.

function Write-LogEntry {
    param (
        [Parameter(Mandatory=$true)]
        [string]$LogPath,

        [Parameter(Mandatory=$true)]
        [string]$Message,
        
        [ValidateSet("INFO", "WARNING", "ERROR")]
        [string]$Level = "INFO"
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logLine = "[$timestamp] [$Level] - $Message"
    
    try {
        Add-Content -Path $LogPath -Value $logLine -ErrorAction Stop
    } catch {
        Write-Warning "Não foi possível escrever no arquivo de log '$LogPath': $($_.Exception.Message)"
    }
}

Export-ModuleMember -Function Write-LogEntry