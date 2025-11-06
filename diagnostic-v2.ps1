# =================================================================
#  DIAGNÓSTICO CENTRAL - JARVIS v2 (PS 5.1/7+)
#  - Coletas com spinner/timeout
#  - Análise via Invoke-HealthAnalysis (intelligent_diagnosis.psm1)
#  - Gera output\status-maquina.json
#  - Envia o relatório ao painel (modulo jarvis.integration.psm1)
#  - Integração opcional com n8n (config.json)
# =================================================================

# --- CONFIGURAÇÃO INICIAL ---
$ScriptDir   = Split-Path -Parent $MyInvocation.MyCommand.Path
$ModulesPath = Join-Path $ScriptDir "modulos"
$OutputPath  = Join-Path $ScriptDir "output"
$JsonFile    = Join-Path $OutputPath "status-maquina.json"
$LogPath     = Join-Path $ScriptDir "JarvisLog.txt"

if (-not (Test-Path $OutputPath)) {
    New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
}

# --- IMPORTS EXPLÍCITOS ---
Import-Module (Join-Path $ModulesPath "log.psm1")                   -Force
Import-Module (Join-Path $ModulesPath "automation.psm1")            -Force
Import-Module (Join-Path $ModulesPath "hardware.psm1")              -Force
Import-Module (Join-Path $ModulesPath "networking.psm1")            -Force -ErrorAction SilentlyContinue
Import-Module (Join-Path $ModulesPath "events.psm1")                -Force
Import-Module (Join-Path $ModulesPath "services.psm1")              -Force
Import-Module (Join-Path $ModulesPath "intelligent_diagnosis.psm1") -Force

# --- CONTÊINER DE JOBS PARA LIMPEZA ---
$createdJobs = New-Object System.Collections.Generic.List[object]

# --- EXECUÇÃO COM TIMEOUT + SPINNER (1 linha/etapa) ---
function Invoke-ModuleWithTimeout {
    param(
        [Parameter(Mandatory=$true)][string]$Message,
        [Parameter(Mandatory=$true)][string]$ModuleName,
        [Parameter(Mandatory=$true)][string]$FunctionName,
        [int]$Timeout = 60
    )

    Write-Host "[INFO] $Message " -NoNewline -ForegroundColor White

    $scriptBlock = {
        param($modulesPath,$moduleName,$functionName,$logPath)
        Import-Module (Join-Path $modulesPath "log.psm1") -Force
        try {
            Import-Module (Join-Path $modulesPath $moduleName) -Force
            $data = & $functionName
            Write-LogEntry -LogPath $logPath -Level INFO -Message "Coleta de ${moduleName} concluída."
            $data | ConvertTo-Json -Depth 6 | Out-String
        } catch {
            $msg = "Falha na coleta de ${moduleName}: $($_.Exception.Message)"
            Write-LogEntry -LogPath $logPath -Level ERROR -Message $msg
            ([pscustomobject]@{ Error = $msg } | ConvertTo-Json -Depth 4 | Out-String)
        }
    }

    $job = Start-Job -ScriptBlock $scriptBlock -ArgumentList $ModulesPath,$ModuleName,$FunctionName,$LogPath
    [void]$createdJobs.Add($job)

    $spinner = '|/-\'
    $i = 0
    $start = Get-Date

    while ($job.State -eq 'Running') {
        if ((New-TimeSpan -Start $start).TotalSeconds -ge $Timeout) {
            Stop-Job -Job $job -Force | Out-Null
            Write-Host "`b " -NoNewline
            Write-Host " -> [FALHA]" -ForegroundColor Red
            return [pscustomobject]@{ Error = "Tempo limite excedido." }
        }
        Write-Host ("`b{0}" -f $spinner[$i]) -NoNewline
        $i = ($i + 1) % $spinner.Length
        Start-Sleep -Milliseconds 120
    }

    $jsonResult = Receive-Job -Job $job
    Write-Host "`b " -NoNewline
    if ($jsonResult) {
        Write-Host " -> [SUCESSO]" -ForegroundColor Green
        try   { return ($jsonResult | ConvertFrom-Json) }
        catch { return [pscustomobject]@{ Error = "Job retornou JSON inválido." } }
    } else {
        Write-Host " -> [FALHA]" -ForegroundColor Red
        return [pscustomobject]@{ Error = "Job falhou ou não retornou dados." }
    }
}

# --- EXECUÇÃO DO DIAGNÓSTICO ---
try {
    Write-LogEntry -LogPath $LogPath -Level INFO -Message "Iniciando diagnóstico completo."
    Write-Host "[JARVIS] Iniciando diagnóstico completo. Aguarde, por favor..." -ForegroundColor Green

    $diagnostico = [ordered]@{
        Timestamp = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss")
        Hostname  = $env:COMPUTERNAME
    }

    # Coletas principais
    $diagnostico.Hardware        = Invoke-ModuleWithTimeout -Message "Coletando informações de Hardware"         -ModuleName "hardware.psm1"   -FunctionName "Get-HardwareStatus"          -Timeout 60
    $diagnostico.Rede            = Invoke-ModuleWithTimeout -Message "Coletando informações de Rede"             -ModuleName "networking.psm1" -FunctionName "Get-NetworkStatus"           -Timeout 40
    $diagnostico.EventosCriticos = Invoke-ModuleWithTimeout -Message "Verificando eventos críticos do sistema"   -ModuleName "events.psm1"     -FunctionName "Get-CriticalEvents"          -Timeout 90
    $diagnostico.Servicos        = Invoke-ModuleWithTimeout -Message "Verificando status de serviços críticos"   -ModuleName "services.psm1"   -FunctionName "Get-CriticalServiceStatus"   -Timeout 40

    # (REMOVIDO) Indexador de Pesquisa
    # $diagnostico.Indexador       = Invoke-ModuleWithTimeout -Message "Verificando Indexador de Pesquisa"         -ModuleName "services.psm1"   -FunctionName "Get-SearchIndexerStatus"     -Timeout 20

    # Fabricante/Modelo
    $diagnostico.Fabricante      = Invoke-ModuleWithTimeout -Message "Identificando fabricante do hardware"      -ModuleName "hardware.psm1"   -FunctionName "Get-ManufacturerInfo"        -Timeout 12

    # Análise inteligente
    $diagnostico.Analise = Invoke-HealthAnalysis -HardwareStatus $diagnostico.Hardware `
                                                 -Eventos        $diagnostico.EventosCriticos `
                                                 -ServiceStatus  $diagnostico.Servicos `
                                                 -NetworkStatus  $diagnostico.Rede

    # Salva JSON
    $diagnostico | ConvertTo-Json -Depth 6 | Set-Content -Path $JsonFile -Encoding UTF8

    # Integração opcional com n8n
    try {
        $cfgPath = Join-Path $ScriptDir "config.json"
        if (Test-Path $cfgPath) {
            $config      = Get-Content $cfgPath -Raw | ConvertFrom-Json
            $healthScore = $diagnostico.Analise.SaudePontuacao
            $threshold   = $config.health_score_threshold

            if ($healthScore -lt $threshold) {
                Write-Host "`n[ALERTA] Pontuação de saúde ($healthScore) abaixo do limite. Enviando para Webhook..." -ForegroundColor Yellow
                $payload = $diagnostico | ConvertTo-Json -Depth 6
                Send-ToWebhook -WebhookUrl $config.webhook_url -JsonData $payload
            } else {
                Write-Host "`n[INFO] Pontuação de saúde ($healthScore) acima do limite. Nenhum webhook será enviado." -ForegroundColor Cyan
            }
        }
    } catch {
        Write-Host "[ERRO] Automação n8n: $($_.Exception.Message)" -ForegroundColor Red
        Write-LogEntry -LogPath $LogPath -Level ERROR -Message "Automação n8n: $($_.Exception.Message)"
    }

    Write-Host "`n[SUCESSO] Diagnóstico concluído. Resultado salvo em: $JsonFile" -ForegroundColor Green
    Write-LogEntry -LogPath $LogPath -Level INFO -Message "Diagnóstico completo OK. Resultado salvo em '$JsonFile'."
}
catch {
    $msg = "Erro fatal no diagnóstico: $($_.Exception.Message)"
    Write-Host "`n[ERRO] $msg" -ForegroundColor Red
    Write-LogEntry -LogPath $LogPath -Level ERROR -Message $msg
    throw
}
finally {
    foreach ($j in $createdJobs) { try { Remove-Job -Job $j -Force | Out-Null } catch {} }
}

# --- ENVIAR PARA O PAINEL JARVIS ---
try {
    Import-Module (Join-Path $ModulesPath 'jarvis.integration.psm1') -Force
    $reportPath = Join-Path $OutputPath 'status-maquina.json'
    if (Test-Path -LiteralPath $reportPath) {
        $ok = Send-JarvisReport -ReportJsonPath $reportPath -ProjectRoot $ScriptDir -Scope 'diagnostic' -DeviceHint 'jarvis-core'
        if (-not $ok) { Write-Host "[JARVIS] Envio retornou false." -ForegroundColor DarkYellow }
    } else {
        Write-Host "[JARVIS] status-maquina.json não encontrado para envio." -ForegroundColor DarkYellow
    }
} catch {
    Write-Host "[JARVIS] Falha ao integrar com o painel: $($_.Exception.Message)" -ForegroundColor DarkYellow
}
