# =================================================================
#       DIAGNÓSTICO CENTRAL - JARVIS LOCAL v2  (revisado)
# =================================================================

$ScriptDir   = Split-Path -Parent $MyInvocation.MyCommand.Path
$ModulesPath = Join-Path $ScriptDir "modulos"
$OutputPath  = Join-Path $ScriptDir "output"
$JsonFile    = Join-Path $OutputPath "status-maquina.json"
$LogPath     = Join-Path $ScriptDir "JarvisLog.txt"

$createdJobs = [System.Collections.Generic.List[object]]::new()

# ---- Verbos aprovados (PSScriptAnalyzer) ----
function Set-PropertyArray {
    param(
        [Parameter(Mandatory=$true)] $Object,
        [Parameter(Mandatory=$true)] [string] $Name
    )
    if (-not $Object) { return }
    if (-not $Object.PSObject.Properties.Match($Name)) {
        Add-Member -InputObject $Object -NotePropertyName $Name -NotePropertyValue @() -Force
    } elseif ($null -eq $Object.$Name) {
        $Object.$Name = @()
    }
}
function Initialize-EventosObject {
    param($Eventos)
    if (-not $Eventos) { return $Eventos }
    foreach ($n in @('BugCheck154','EventosRelevantes','EventosCriticos','Events')) {
        Set-PropertyArray -Object $Eventos -Name $n
    }
    return $Eventos
}

function Invoke-ModuleWithTimeout {
    param(
        [string]$Message,
        [string]$ModuleName,
        [string]$FunctionName,
        [int]$Timeout = 60
    )
    Write-Host "[INFO] ${Message} " -ForegroundColor White -NoNewline

    $scriptBlock = {
        param($modulesPath, $moduleName, $functionName, $logPath)
        Import-Module (Join-Path $modulesPath "log.psm1") -Force
        try {
            Import-Module (Join-Path $modulesPath $moduleName) -Force
            $data = & $functionName
            Write-LogEntry -LogPath $logPath -Level INFO -Message "Coleta de dados de ${moduleName} concluída."
            $data | ConvertTo-Json -Depth 6 | Out-String
        } catch {
            $errorMessage = "Falha na coleta de dados de ${moduleName}: $($_.Exception.Message)"
            Write-LogEntry -LogPath $logPath -Level ERROR -Message $errorMessage
            [pscustomobject]@{ Error = $errorMessage } | ConvertTo-Json -Depth 3 | Out-String
        }
    }
    $job = Start-Job -ScriptBlock $scriptBlock -ArgumentList $ModulesPath, $ModuleName, $FunctionName, $LogPath
    $script:createdJobs.Add($job)

    $spinner = '|/-\'
    $i = 0
    $start = Get-Date
    while ($job.State -eq 'Running') {
        if ((New-TimeSpan -Start $start).TotalSeconds -ge $Timeout) {
            Stop-Job -Job $job -Force | Out-Null
            Write-Host "`b `b" -NoNewline
            Write-Host "-> [FALHA]" -ForegroundColor Red
            return [pscustomobject]@{ Error = "Tempo limite excedido." }
        }
        Write-Host "`b$($spinner[$i])" -NoNewline
        $i = ($i + 1) % $spinner.Length
        Start-Sleep -Milliseconds 250
    }
    Write-Host "`b `b" -NoNewline
    Write-Host "  -> [SUCESSO]" -ForegroundColor Green

    $jsonResult = Receive-Job -Job $job
    if ($jsonResult) {
        try { return ($jsonResult | ConvertFrom-Json) }
        catch { return [pscustomobject]@{ Error = "Falha ao interpretar retorno de ${ModuleName}." } }
    }

    $errorMessage = "Falha na coleta de dados de ${ModuleName}: Job falhou ou não retornou dados."
    Write-LogEntry -LogPath $LogPath -Level ERROR -Message $errorMessage
    Write-Host "  -> [FALHA]" -ForegroundColor Red
    [pscustomobject]@{ Error = $errorMessage }
}

try {
    Import-Module (Join-Path $ModulesPath "interpretation.psm1") -Force
    Import-Module (Join-Path $ModulesPath "log.psm1")           -Force
    Import-Module (Join-Path $ModulesPath "automation.psm1")    -Force

    if (-not (Test-Path $OutputPath)) { New-Item -ItemType Directory -Path $OutputPath | Out-Null }

    Write-LogEntry -LogPath $LogPath -Level INFO -Message "Iniciando diagnóstico completo."
    Write-Host "[JARVIS] Iniciando diagnóstico completo. Aguarde, por favor..." -ForegroundColor Green

    # 🔒 Inicializa todas as chaves no hashtable
    $diagnostico = [ordered]@{
        Timestamp       = Get-Date -Format "yyyy-MM-ddTHH:mm:ss"
        Hostname        = $env:COMPUTERNAME
        Hardware        = $null
        Rede            = $null
        EventosCriticos = $null
        Servicos        = $null
        Fabricante      = $null
        Indexador       = $null
        Analise         = $null
    }

    # Coletas
    $diagnostico['Hardware']        = Invoke-ModuleWithTimeout -Message "Coletando informações de Hardware"                 -ModuleName "hardware.psm1"   -FunctionName "Get-HardwareStatus"          -Timeout 60
    $diagnostico['Rede']            = Invoke-ModuleWithTimeout -Message "Coletando informações de Rede"                     -ModuleName "networking.psm1" -FunctionName "Get-NetworkStatus"           -Timeout 30
    $diagnostico['EventosCriticos'] = Invoke-ModuleWithTimeout -Message "Verificando eventos críticos do sistema"           -ModuleName "events.psm1"     -FunctionName "Get-CriticalEvents"         -Timeout 90
    $diagnostico['Servicos']        = Invoke-ModuleWithTimeout -Message "Verificando status de serviços críticos"           -ModuleName "services.psm1"   -FunctionName "Get-CriticalServiceStatus"  -Timeout 30
    $diagnostico['Fabricante']      = Invoke-ModuleWithTimeout -Message "Identificando fabricante do hardware"              -ModuleName "hardware.psm1"   -FunctionName "Get-ManufacturerInfo"       -Timeout 10
    $diagnostico['Indexador']       = Invoke-ModuleWithTimeout -Message "Verificando Indexador de Pesquisa"                 -ModuleName "services.psm1"   -FunctionName "Get-SearchIndexerStatus"    -Timeout 15

    # Normaliza eventos para shape estável
    $diagnostico['EventosCriticos'] = Initialize-EventosObject -Eventos $diagnostico['EventosCriticos']

    # Análise de saúde
    $diagnostico['Analise'] = Invoke-HealthAnalysis -HardwareStatus $diagnostico['Hardware'] -Eventos $diagnostico['EventosCriticos'] -ServiceStatus $diagnostico['Servicos']

    # Salva JSON
    $diagnostico | ConvertTo-Json -Depth 6 | Set-Content -Path $JsonFile -Encoding UTF8

    Write-Host "`n[SUCESSO] Diagnóstico concluído. Resultado salvo em: ${JsonFile}" -ForegroundColor Green
    Write-LogEntry -LogPath $LogPath -Level INFO -Message "Diagnóstico completo concluído com sucesso. Resultado salvo em '${JsonFile}'."

} catch {
    $errorMessage = "Erro fatal no script de diagnóstico: $($_.Exception.Message)"
    Write-Host "`n[ERRO] ${errorMessage}" -ForegroundColor Red
    Write-LogEntry -LogPath $LogPath -Level ERROR -Message $errorMessage
    throw
} finally {
    $createdJobs | ForEach-Object { Remove-Job -Job $_ -Force | Out-Null }
}
