# intelligent_diagnosis.psm1
# Funções de diagnóstico simplificado (opção 1 do menu)

function Write-FormattedColoredString {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Text,
        [Parameter(Mandatory=$true)]
        [int]$LineWidth,
        [Parameter(Mandatory=$false)]
        [string]$Indent = "",
        [Parameter(Mandatory=$false)]
        [string]$ForegroundColor = "White"
    )

    $lines = @()
    $words = $Text -split ' '
    $currentLine = ""
    $effectiveLineWidth = $LineWidth - $Indent.Length

    foreach ($word in $words) {
        if (($currentLine.Trim().Length + $word.Length + 1) -le $effectiveLineWidth) {
            $currentLine += " $word"
        } else {
            $lines += $currentLine.Trim()
            $currentLine = "$Indent$word"
        }
    }
    $lines += $currentLine.Trim()

    foreach ($line in $lines) {
        Write-Host $line -ForegroundColor $ForegroundColor
    }
}

function Start-DiagnosticAnalysis {
    param(
        [Parameter(Mandatory=$true)]
        [string]$JsonPath
    )

    if (-not (Test-Path $JsonPath)) {
        throw "Arquivo de diagnóstico '$JsonPath' não encontrado."
    }

    $data = Get-Content $JsonPath -Raw | ConvertFrom-Json
    Clear-Host
    $windowWidth = $Host.UI.RawUI.WindowSize.Width
    $reportWidth = $windowWidth - 4

    Write-Host "================== DIAGNÓSTICO BÁSICO ==================" -ForegroundColor Cyan
    Write-Host "Sistema: $($data.Hostname) | Data: $($data.Timestamp)" -ForegroundColor White
    Write-Host "=========================================================" -ForegroundColor Cyan
    Write-Host "`n"

    # --- MEMÓRIA RAM ---
    Write-Host "[MEMÓRIA RAM]" -ForegroundColor White
    if ($null -ne $data.Hardware -and $null -ne $data.Hardware.RAM) {
        $ramUsed = [int]$data.Hardware.RAM.UsedPercent
        $ramTotal = [int]$data.Hardware.RAM.TotalGB
        $ramStatusText = "Uso de RAM: $ramUsed% (Total: $ramTotal GB)"
        $ramColor = if ($ramUsed -ge 95) { "Red" } elseif ($ramUsed -ge 80) { "Yellow" } else { "Green" }
        Write-FormattedColoredString -Text $ramStatusText -LineWidth $reportWidth -ForegroundColor $ramColor
    } else {
        Write-Host "Dados de RAM não disponíveis." -ForegroundColor Yellow
    }
    Write-Host "`n"

    # --- DISCOS ---
    Write-Host "[DISCOS]" -ForegroundColor White
    if ($null -ne $data.Hardware -and $null -ne $data.Hardware.Disks) {
        foreach ($disk in $data.Hardware.Disks) {
            if ($disk -and $null -ne $disk.FreePercent -and $null -ne $disk.TotalGB) {
                $diskColor = if ($disk.FreePercent -lt 15) { "Red" } elseif ($disk.FreePercent -lt 30) { "Yellow" } else { "Green" }
                Write-FormattedColoredString -Text "Disco $($disk.DeviceID): $($disk.FreeGB) GB livres ($($disk.FreePercent)%) - Tipo: $($disk.Tipo)" -LineWidth $reportWidth -ForegroundColor $diskColor
            } else {
                Write-Host "Disco $($disk.DeviceID): Dados indisponíveis." -ForegroundColor Yellow
            }
        }
    } else {
        Write-Host "Informações de discos não disponíveis." -ForegroundColor Yellow
    }
    Write-Host "`n"

    # --- REDE ---
    Write-Host "[REDE]" -ForegroundColor White
    if ($null -ne $data.Rede) {
        if ($data.Rede.HasInternetConnection -eq $true) {
            Write-Host "Status da Internet: Conectado" -ForegroundColor Green
        } elseif ($data.Rede.HasInternetConnection -eq $false) {
            Write-Host "Status da Internet: Desconectado" -ForegroundColor Red
        } else {
            Write-Host "Status da Internet: Indisponível" -ForegroundColor Yellow
        }
    } else {
        Write-Host "Dados de rede não disponíveis." -ForegroundColor Yellow
    }
    Write-Host "`n"

    # --- ESTABILIDADE BÁSICA ---
    Write-Host "[ESTABILIDADE DO SISTEMA]" -ForegroundColor White
    if ($null -ne $data.EventosCriticos) {
        $totalEventos = $data.EventosCriticos.TotalEventos
        $relevantes = if ($data.EventosCriticos.EventosRelevantes) { $data.EventosCriticos.EventosRelevantes.Count } else { 0 }
        $criticos = if ($data.EventosCriticos.EventosCriticos) { $data.EventosCriticos.EventosCriticos.Count } else { 0 }
        Write-Host "Total de eventos críticos nos últimos 7 dias: $totalEventos" -ForegroundColor DarkGray
        Write-Host "  -> Eventos relevantes: $relevantes" -ForegroundColor Red
        Write-Host "  -> Eventos gerais: $criticos" -ForegroundColor Yellow
    } else {
        Write-Host "Dados de eventos não disponíveis." -ForegroundColor Yellow
    }
    Write-Host "`n"

    # --- SERVIÇOS CRÍTICOS ---
    Write-Host "[SERVIÇOS CRÍTICOS]" -ForegroundColor White
    if ($null -ne $data.Servicos -and $data.Servicos.CriticalServicesNotRunning.Count -gt 0) {
        Write-Host "Serviços essenciais que não estão em execução:" -ForegroundColor Red
        foreach ($svc in $data.Servicos.CriticalServicesNotRunning) {
            Write-Host "  - $($svc.Name): $($svc.Status)" -ForegroundColor Yellow
        }
    } else {
        Write-Host "Todos os serviços críticos estão em execução." -ForegroundColor Green
    }

    Write-Host "`n=========================================================" -ForegroundColor Cyan
}

Export-ModuleMember -Function Start-DiagnosticAnalysis, Write-FormattedColoredString
