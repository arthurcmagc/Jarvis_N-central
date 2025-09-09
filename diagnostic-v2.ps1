# =================================================================
#       DIAGNÓSTICO CENTRAL - JARVIS LOCAL v2
# =================================================================

# --- CONFIGURAÇÃO INICIAL ---
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ModulesPath = Join-Path $ScriptDir "modulos"
$OutputPath = Join-Path $ScriptDir "output"
$JsonFile = Join-Path $OutputPath "status-maquina.json"
$LogPath = Join-Path $ScriptDir "JarvisLog.txt"

# --- LISTA PARA CONTROLAR OS JOBS CRIADOS ---
$createdJobs = [System.Collections.Generic.List[object]]::new()

# --- FUNÇÃO CENTRAL DE EXECUÇÃO COM TIMEOUT E LOGS ---
function Invoke-ModuleWithTimeout {
    param(
        [string]$Message,
        [string]$ModuleName,
        [string]$FunctionName,
        [int]$Timeout = 60
    )
    
    # Exibe a mensagem de INFO sem a animação de "..."
    Write-Host "[INFO] ${Message} " -ForegroundColor White -NoNewline
    
    # Cria o bloco de script que será executado como um job
    $scriptBlock = {
        param($modulesPath, $moduleName, $functionName, $logPath)
        
        # O módulo de log precisa ser importado aqui para ser usado dentro do job
        Import-Module (Join-Path $modulesPath "log.psm1") -Force
        
        try {
            Import-Module (Join-Path $modulesPath $moduleName) -Force
            $data = & $functionName
            # Escreve no log que a coleta foi bem-sucedida dentro do job
            Write-LogEntry -LogPath $logPath -Level INFO -Message "Coleta de dados de ${moduleName} concluída."
            $data | ConvertTo-Json -Depth 5 | Out-String
        } catch {
            $errorMessage = "Falha na coleta de dados de ${moduleName}: $($_.Exception.Message)"
            # Escreve o erro no log e retorna um objeto de erro
            Write-LogEntry -LogPath $logPath -Level ERROR -Message $errorMessage
            $errorObj = [pscustomobject]@{ Error = $errorMessage }
            $errorObj | ConvertTo-Json -Depth 5 | Out-String
        }
    }
    
    $job = Start-Job -ScriptBlock $scriptBlock -ArgumentList $ModulesPath, $ModuleName, $FunctionName, $LogPath
    $script:createdJobs.Add($job)

    # Lógica do spinner corrigida para não interferir no texto
    $spinner = '|/-\'
    $i = 0
    $start = Get-Date

    # Loop para exibir o spinner enquanto o job está rodando
    while ($job.State -eq 'Running') {
        if ((New-TimeSpan -Start $start).TotalSeconds -ge $Timeout) {
            Stop-Job -Job $job -Force | Out-Null
            Write-Host "`b `b" -NoNewline
            Write-Host "-> [FALHA]" -ForegroundColor Red
            return [pscustomobject]@{ Error = "Tempo limite excedido." }
        }
        # Apenas um backspace para ir para o caractere anterior
        Write-Host "`b$($spinner[$i])" -NoNewline
        $i = ($i + 1) % $spinner.Length
        Start-Sleep -Milliseconds 250
    }
    
    # NOVO: Limpa o último caractere do spinner com um backspace e um espaço
    Write-Host "`b `b" -NoNewline
    Write-Host "  -> [SUCESSO]" -ForegroundColor Green

    $jsonResult = Receive-Job -Job $job
    if ($jsonResult) {
        $result = $jsonResult | ConvertFrom-Json
        return $result
    }

    # Se o job falhou ou não retornou dados, retorna um erro
    $errorMessage = "Falha na coleta de dados de ${ModuleName}: Job falhou ou não retornou dados."
    Write-LogEntry -LogPath $LogPath -Level ERROR -Message $errorMessage
    Write-Host "  -> [FALHA]" -ForegroundColor Red
    return [pscustomobject]@{ Error = $errorMessage }
}

# --- EXECUÇÃO DO DIAGNÓSTICO ---
try {
    # Garante que os módulos essenciais estejam importados para o script principal
    Import-Module (Join-Path $ModulesPath "interpretation.psm1") -Force
    Import-Module (Join-Path $ModulesPath "log.psm1") -Force
    Import-Module (Join-Path $ModulesPath "automation.psm1") -Force

    if (-not (Test-Path $OutputPath)) {
        New-Item -ItemType Directory -Path $OutputPath | Out-Null
    }
    
    # Início do log de execução
    Write-LogEntry -LogPath $LogPath -Level INFO -Message "Iniciando diagnóstico completo."

    $diagnostico = [ordered]@{
        Timestamp = Get-Date -Format "yyyy-MM-ddTHH:mm:ss"
        Hostname = $env:COMPUTERNAME
    }
    Write-Host "[JARVIS] Iniciando diagnóstico completo. Aguarde, por favor..." -ForegroundColor Green
    
    # Chama as funções com a nova lógica de exibição
    $diagnostico.Hardware = Invoke-ModuleWithTimeout -Message "Coletando informações de Hardware" -ModuleName "hardware.psm1" -FunctionName "Get-HardwareStatus" -Timeout 60
    $diagnostico.Rede = Invoke-ModuleWithTimeout -Message "Coletando informações de Rede" -ModuleName "networking.psm1" -FunctionName "Get-NetworkStatus" -Timeout 30
    $diagnostico.EventosCriticos = Invoke-ModuleWithTimeout -Message "Verificando eventos críticos do sistema" -ModuleName "events.psm1" -FunctionName "Get-CriticalEvents" -Timeout 90
    $diagnostico.Servicos = Invoke-ModuleWithTimeout -Message "Verificando status de serviços críticos" -ModuleName "services.psm1" -FunctionName "Get-CriticalServiceStatus" -Timeout 30
    $diagnostico.Fabricante = Invoke-ModuleWithTimeout -Message "Identificando fabricante do hardware" -ModuleName "hardware.psm1" -FunctionName "Get-ManufacturerInfo" -Timeout 10
    
    # Lógica de análise de saúde do sistema
    $diagnostico.Analise = Invoke-HealthAnalysis -HardwareStatus $diagnostico.Hardware -Eventos $diagnostico.EventosCriticos -ServiceStatus $diagnostico.Servicos

    $diagnostico | ConvertTo-Json -Depth 5 | Set-Content -Path $JsonFile -Encoding UTF8
    
    # --- LÓGICA DE INTEGRAÇÃO COM N8N ---
    try {
        # Carrega o arquivo de configuração
        $config = Get-Content (Join-Path $ScriptDir "config.json") -Raw | ConvertFrom-Json
        
        $healthScore = $diagnostico.Analise.SaudePontuacao
        $threshold = $config.health_score_threshold
        
        # Verifica a pontuação de saúde para decidir se envia o webhook
        if ($healthScore -lt $threshold) {
            Write-Host "`n[ALERTA] Pontuação de saúde (${healthScore}) abaixo do limite. Enviando dados para o webhook..." -ForegroundColor Yellow
            $diagnosticoJson = $diagnostico | ConvertTo-Json -Depth 5
            Send-ToWebhook -WebhookUrl $config.webhook_url -JsonData $diagnosticoJson
        } else {
            Write-Host "`n[INFO] Pontuação de saúde (${healthScore}) acima do limite. Nenhum webhook será enviado." -ForegroundColor Cyan
        }
    } catch {
        $errorMessage = "Erro na lógica de automação: $($_.Exception.Message)"
        Write-Host "`n[ERRO] ${errorMessage}" -ForegroundColor Red
        Write-LogEntry -LogPath $LogPath -Level ERROR -Message $errorMessage
    }

    Write-Host "`n[SUCESSO] Diagnóstico concluído. Resultado salvo em: ${JsonFile}" -ForegroundColor Green
    Write-LogEntry -LogPath $LogPath -Level INFO -Message "Diagnóstico completo concluído com sucesso. Resultado salvo em '${JsonFile}'."

} catch {
    $errorMessage = "Erro fatal no script de diagnóstico: $($_.Exception.Message)"
    Write-Host "`n[ERRO] ${errorMessage}" -ForegroundColor Red
    Write-LogEntry -LogPath $LogPath -Level ERROR -Message $errorMessage
    throw
} finally {
    # --- LIMPEZA SEGURA DE JOBS ---
    $createdJobs | ForEach-Object { Remove-Job -Job $_ -Force | Out-Null }
}