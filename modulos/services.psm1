# services.psm1
# Serviços críticos (sem funções de Indexador).
# Compatível PS 5.1/7+.

# -------------------------------------------------
# Utilitários
# -------------------------------------------------
function Test-IsAdmin {
    try {
        $id  = [System.Security.Principal.WindowsIdentity]::GetCurrent()
        $pr  = New-Object System.Security.Principal.WindowsPrincipal($id)
        return $pr.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch { return $false }
}

function Convert-ServiceStatusToCode {
    param([System.ServiceProcess.ServiceControllerStatus]$Status)
    switch ($Status) {
        'Stopped'         { return 1 }
        'StartPending'    { return 2 }
        'StopPending'     { return 3 }
        'Running'         { return 4 }
        'ContinuePending' { return 5 }
        'PausePending'    { return 6 }
        'Paused'          { return 7 }
        default           { return 0 }
    }
}

# -------------------------------------------------
# Status de serviços críticos
# -------------------------------------------------
function Get-CriticalServiceStatus {
    <#
        Retorno:
        {
          "Services": [ { Name, DisplayName, Status }... ],
          "CriticalServicesNotRunning": [ { Name, Status }... ]
        }
    #>
    [CmdletBinding()]
    param(
        [string[]]$CriticalNames = @(
            'wuauserv',            # Windows Update
            'bits',                # BITS
            'lanmanworkstation',   # Estação de Trabalho
            'Dnscache',            # Cliente DNS
            'Winmgmt',             # WMI
            'TermService'          # RDP
            # (Sem WSearch — removido por decisão)
        )
    )

    try {
        $servicesList = @()
        $notRunning   = @()

        foreach ($name in $CriticalNames) {
            $svc = Get-Service -Name $name -ErrorAction SilentlyContinue
            if ($null -ne $svc) {
                $servicesList += [pscustomobject]@{
                    Name        = $svc.Name
                    DisplayName = $svc.DisplayName
                    Status      = "$($svc.Status)"
                }

                $code = Convert-ServiceStatusToCode -Status $svc.Status
                if ($code -ne 4) {
                    $notRunning += [pscustomobject]@{
                        Name   = $svc.DisplayName
                        Status = $code
                    }
                }
            } else {
                $servicesList += [pscustomobject]@{
                    Name        = $name
                    DisplayName = $name
                    Status      = "NotFound"
                }
                $notRunning += [pscustomobject]@{
                    Name   = $name
                    Status = 1
                }
            }
        }

        [pscustomobject]@{
            Services                   = $servicesList
            CriticalServicesNotRunning = $notRunning
        }
    } catch {
        [pscustomobject]@{ Error = "Falha na coleta de serviços: $($_.Exception.Message)" }
    }
}

# -------------------------------------------------
# Export
# -------------------------------------------------
Export-ModuleMember -Function Get-CriticalServiceStatus
