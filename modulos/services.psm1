# services.psm1
# Serviços críticos + status e reparo do Windows Search (Indexador), com pré-checagem idempotente.
# Compatível PS 5.1/7+. Sem ?. ou ??.

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
        Retorna (shape compatível com o backup):
        {
          "Services": [ { Name, DisplayName, Status }... ],    # Status string ("Running", ...)
          "CriticalServicesNotRunning": [ { Name, Status }... ] # Name = DisplayName; Status = código numérico (1=Stopped, 4=Running, ...)
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
            'TermService',         # Serviços de Área de Trabalho Remota
            'WSearch'              # Windows Search (útil p/ menu)
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
                    # Para CriticalServicesNotRunning, o backup usa Name = DisplayName e Status = numérico
                    $notRunning += [pscustomobject]@{
                        Name   = $svc.DisplayName
                        Status = $code
                    }
                }
            } else {
                # Serviço ausente: reporta como parado (compatível com ideia do backup)
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
# Windows Search (Indexador) - Status
# -------------------------------------------------
function Get-SearchIndexerStatus {
    <#
        Retorna:
        - WSearchStatus  : Running/Stopped/Paused/NotFound
        - StartType      : Automatic/Manual/Disabled/Unknown
        - FeatureEnabled : $true/$false/$null (quando não for possível checar)
        - IsAdmin        : $true/$false
    #>
    [CmdletBinding()]
    param()

    try {
        $svc = Get-Service -Name 'WSearch' -ErrorAction SilentlyContinue
        $svcStatus = if ($null -ne $svc) { "$($svc.Status)" } else { "NotFound" }
        $startType = "Unknown"

        if ($null -ne $svc) {
            try {
                $wmiSvc = Get-WmiObject -Class Win32_Service -Filter "Name='WSearch'" -ErrorAction SilentlyContinue
                if ($null -ne $wmiSvc) {
                    switch ($wmiSvc.StartMode) {
                        "Auto"     { $startType = "Automatic" }
                        "Manual"   { $startType = "Manual" }
                        "Disabled" { $startType = "Disabled" }
                        default    { $startType = $wmiSvc.StartMode }
                    }
                }
            } catch { $startType = "Unknown" }
        }

        $featureEnabled = $null
        try {
            $feat = Get-WindowsOptionalFeature -Online -FeatureName "SearchEngine-Client-Package" -ErrorAction SilentlyContinue
            if ($null -ne $feat) { $featureEnabled = ($feat.State -eq 'Enabled') }
        } catch {
            $featureEnabled = $null
        }

        [pscustomobject]@{
            WSearchStatus  = $svcStatus
            StartType      = $startType
            FeatureEnabled = $featureEnabled
            IsAdmin        = (Test-IsAdmin)
        }
    } catch {
        [pscustomobject]@{ Error = "Falha ao verificar Indexador: $($_.Exception.Message)" }
    }
}

# -------------------------------------------------
# Windows Search (Indexador) - Reparo idempotente
# -------------------------------------------------
function Repair-SearchIndexer {
    <#
        Lógica:
        - Se recurso habilitado e serviço Running => Skipped = $true (nenhuma ação aplicada).
        - Caso contrário aplica:
          1) Enable-WindowsOptionalFeature (se necessário)
          2) Set-Service WSearch -StartupType Automatic
          3) sc.exe config WSearch depend= /   (limpa dependências)
          4) Start-Service WSearch
        Retorna objeto com:
          Skipped, Success, Status, Report (log de etapas)
    #>
    [CmdletBinding()]
    param()

    $report  = New-Object System.Collections.Generic.List[string]
    $isAdmin = Test-IsAdmin
    if (-not $isAdmin) {
        $report.Add("Aviso: Execução sem privilégios administrativos. Algumas etapas podem falhar.")
    }

    try {
        $initial = Get-SearchIndexerStatus
        if ($initial.WSearchStatus -eq 'Running' -and $initial.FeatureEnabled -eq $true) {
            $report.Add("Indexador já está saudável: serviço em execução e recurso habilitado. Nenhuma ação necessária.")
            return [pscustomobject]@{
                Skipped = $true
                Success = $true
                Status  = $initial
                Report  = $report
            }
        }

        # 1) Habilitar o recurso, se necessário
        if ($initial.FeatureEnabled -ne $true) {
            $report.Add("Habilitando recurso SearchEngine-Client-Package (se necessário)...")
            try {
                Enable-WindowsOptionalFeature -Online -FeatureName "SearchEngine-Client-Package" -All -NoRestart -ErrorAction Stop | Out-Null
                $report.Add("Recurso habilitado (ou já estava habilitado).")
            } catch {
                $report.Add("Falha ao habilitar recurso: $($_.Exception.Message)")
            }
        } else {
            $report.Add("Recurso SearchEngine-Client-Package já habilitado.")
        }

        # 2) Deixar WSearch como Automático
        $report.Add("Ajustando inicialização do serviço WSearch para Automático...")
        try {
            Set-Service -Name WSearch -StartupType Automatic -ErrorAction SilentlyContinue
            $report.Add("StartupType ajustado para Automático.")
        } catch {
            $report.Add("Falha ao ajustar StartupType: $($_.Exception.Message)")
        }

        # 3) Limpar dependências
        $report.Add("Removendo dependências problemáticas (se houver)...")
        try {
            sc.exe config WSearch depend= / | Out-Null
            $report.Add("Dependências limpas.")
        } catch {
            $report.Add("Falha ao limpar dependências: $($_.Exception.Message)")
        }

        # 4) Iniciar serviço
        $report.Add("Iniciando serviço WSearch...")
        try {
            Start-Service WSearch -ErrorAction Stop
            $report.Add("WSearch iniciado com sucesso.")
        } catch {
            $report.Add("Falha ao iniciar WSearch: $($_.Exception.Message)")
        }

        # Validação final
        $final = Get-SearchIndexerStatus
        $ok    = ($final.WSearchStatus -eq 'Running' -and $final.FeatureEnabled -eq $true)
        if ($ok) {
            $report.Add("Validação final OK: serviço em execução e recurso habilitado.")
        } else {
            $report.Add("Validação final com pendências: verifique manualmente o status exibido em 'Status'.")
        }

        [pscustomobject]@{
            Skipped = $false
            Success = $ok
            Status  = $final
            Report  = $report
        }
    } catch {
        $report.Add("Erro inesperado: $($_.Exception.Message)")
        [pscustomobject]@{
            Skipped = $false
            Success = $false
            Status  = $null
            Report  = $report
        }
    }
}

# -------------------------------------------------
# Export
# -------------------------------------------------
Export-ModuleMember -Function Get-CriticalServiceStatus, Get-SearchIndexerStatus, Repair-SearchIndexer
