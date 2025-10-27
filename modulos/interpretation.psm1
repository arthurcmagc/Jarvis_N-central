# interpretation.psm1
# Versão limpa, corrigida e resiliente

function Get-Safe {
    param($obj, [string]$prop, $default = 'N/A')
    try {
        $v = $null
        if ($null -ne $obj) { $v = $obj.$prop }
        if ($null -eq $v -or [string]::IsNullOrWhiteSpace([string]$v)) { return $default }
        return $v
    } catch { return $default }
}

function Get-ExplicacaoPorID {
    param([Parameter(Mandatory=$true)][string]$id)
    switch ("$id") {
        "41"      { return "[ID 41] - Desligamento inesperado. Pode indicar queda de energia ou travamento. Sugestão: Verificar no-break e logs de desligamento." }
        "55"      { return "[ID 55] - Corrupção no sistema de arquivos. Sugestão: Executar 'chkdsk' no volume afetado." }
        "1001"    { return "[ID 1001] - Aplicativo apresentou erro. Sugestão: Reinstalar/verificar atualizações ou log do app." }
        "7031"    { return "[ID 7031] - Serviço finalizado inesperadamente. Verificar dependências e iniciar manualmente." }
        "7024"    { return "[ID 7024] - Serviço terminou com erro. Analisar log, dependências e permissões." }
        "7043"    { return "[ID 7043] - Serviço não desligou corretamente. Aumentar timeout ou checar travamentos." }
        "10010"   { return "[ID 10010] - DCOM não respondeu. Frequentemente inofensivo; ajustar permissões se causar impacto." }
        "10016"   { return "[ID 10016] - Permissões DCOM. Geralmente inofensivo." }
        "7000"    { return "[ID 7000] - Serviço não iniciou. Iniciar manualmente e checar dependências." }
        "7001"    { return "[ID 7001] - Serviço dependente falhou. Iniciar dependências/ajustar ordem." }
        "SERVICO_CRITICO_STOPPED" { return "[SERVIÇO CRÍTICO] - Serviço essencial parado. Iniciar/ajustar inicialização." }
        Default   { return "[ID $id] - Evento de erro geral. Verificar o Visualizador de Eventos para detalhes." }
    }
}

function Get-ExplicacaoPorBugCheck {
    param([Parameter(Mandatory=$true)][string]$bugCheckId)
    switch ("$bugCheckId") {
        "154" { return "[BUGCHECK 154] - Erro crítico (KERNEL_DATA_INPAGE_ERROR). Possível problema em disco/armazenamento ou RAM. Rodar chkdsk/SMART/memtest." }
        Default { return "[BUGCHECK $bugCheckId] - Código de parada do Windows. Pesquisar para causa/ação." }
    }
}

function Write-FormattedColoredString {
    param(
        [Parameter(Mandatory=$true)][string]$Text,
        [Parameter(Mandatory=$true)][int]$LineWidth,
        [Parameter(Mandatory=$false)][string]$Indent = "",
        [Parameter(Mandatory=$false)][string]$ForegroundColor = "White"
    )
    $lines = @()
    $words = $Text -split ' '
    $currentLine = ""
    $effectiveLineWidth = [math]::Max(20, ($LineWidth - $Indent.Length))

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

function Format-LatencyDisplay {
    param(
        [Parameter(Mandatory=$true)][string]$Target,
        [Parameter(Mandatory=$true)]$LatencyObj
    )
    $avg = $LatencyObj.AverageMs
    $med = $LatencyObj.MedianMs
    $loss = $LatencyObj.Loss
    $method = $LatencyObj.Method
    $methodTag = if ($method -and $method -ne 'ICMP') { " ($method)" } else { "" }
    if ([string]::IsNullOrWhiteSpace("$avg")) { $avg = 'N/D' }
    if ([string]::IsNullOrWhiteSpace("$med")) { $med = 'N/D' }
    if ([string]::IsNullOrWhiteSpace("$loss")) { $loss = 'N/D' }
    return " - {0}  avg {1} ms | med {2} ms | perda {3}{4}" -f $Target, $avg, $med, $loss, $methodTag
}

function Get-ManufacturerSoftwareSuggestion {
    param([Parameter(Mandatory=$true)][string]$Manufacturer)
    $normalizedManufacturer = $Manufacturer.ToLower()
    switch -wildcard ($normalizedManufacturer) {
        "*dell*"   { return "Essa máquina é da marca Dell. Utilize o Dell SupportAssist para análise e correções. No menu [3], SFC/DISM ajudam na base do SO." }
        "*lenovo*" { return "Essa máquina é da marca Lenovo. Utilize o Lenovo Vantage para drivers/atualizações. No menu [3], SFC/DISM para verificação." }
        "*hp*"     { return "Essa máquina é da marca HP. Utilize o HP Support Assistant para diagnóstico e drivers. No menu [3], SFC/DISM auxiliam." }
        "*samsung*"{ return "Essa máquina é da marca Samsung. Utilize o Samsung Update para drivers. No menu [3], SFC/DISM para verificação." }
        Default    { return "Fabricante: $Manufacturer. Verifique drivers no site oficial e use SFC/DISM no menu [3] para verificação profunda." }
    }
}

function Get-IntelligentSummary {
    param([Parameter(Mandatory=$true)] $AnalysisData, [Parameter(Mandatory=$true)] $RawData)
    $summaryText = "Resumo inteligente gerado: análise simples de saúde do sistema."
    $recs = @()
    if ($AnalysisData -and $AnalysisData.SaudePontuacao) {
        $score = [int]$AnalysisData.SaudePontuacao
        if ($score -ge 80) {
            $summaryText = "Sistema com saúde geral boa (pontuação $score/100)."
            $recs += "Manter rotinas de monitoramento."
            $recs += "Revisar logs semanalmente."
        } elseif ($score -ge 50) {
            $summaryText = "Sistema com sinais moderados de alerta (pontuação $score/100)."
            $recs += "Fechar apps não essenciais e verificar disco/RAM."
            $recs += "Agendar análise detalhada de eventos relevantes."
        } else {
            $summaryText = "Sistema em estado frágil (pontuação $score/100). Ação imediata recomendada."
            $recs += "Realizar backup e investigar eventos críticos."
            $recs += "Executar chkdsk/diagnóstico de estabilidade."
        }
    } else {
        $recs += "Executar análise completa de hardware e logs."
        $recs += "Garantir que a coleta de eventos/serviços esteja habilitada."
    }
    [pscustomobject]@{
        Summary         = $summaryText
        Recommendations = $recs
    }
}

function Invoke-HealthAnalysis {
    param(
        [Parameter(Mandatory=$true)] $HardwareStatus,
        [Parameter(Mandatory=$true)] $Eventos,
        [Parameter(Mandatory=$false)] $ServiceStatus
    )
    $score  = 100
    $issues = New-Object System.Collections.Generic.List[string]
    $eventWeights = @{
        "41" = 10; "55" = 10; "7031" = 5; "1001" = 3; "10010" = 2; "7024" = 5; "7043" = 5; "7000" = 5; "7001" = 5;
    }

    # RAM
    if ($HardwareStatus -and $HardwareStatus.PSObject.Properties.Match('RAM')) {
        $ram = $HardwareStatus.RAM
        if ($ram -and $null -ne $ram.UsedPercent) {
            $ramUsed = [int]$ram.UsedPercent
            if ($ramUsed -ge 95)      { $score -= 15; $issues.Add("[CRÍTICO] Uso de RAM: $ramUsed%.") }
            elseif ($ramUsed -ge 90)  { $score -= 10; $issues.Add("[ALTO] Uso de RAM: $ramUsed%.") }
            elseif ($ramUsed -ge 80)  { $score -= 3;  $issues.Add("[ALERTA] Uso de RAM: $ramUsed%.") }
        }
    }

    # Discos
    if ($HardwareStatus -and $HardwareStatus.PSObject.Properties.Match('Disks')) {
        foreach ($disk in $HardwareStatus.Disks) {
            if ($disk -and $null -ne $disk.FreePercent) {
                if ([double]$disk.FreePercent -lt 15) {
                    $score -= 10
                    $issues.Add("[ALERTA] Pouco espaço em disco em $($disk.DeviceID): $($disk.FreePercent)% livre.")
                }
            }
        }
    }

    # Eventos
    if ($Eventos) {
        $eventosRelevantes = @()
        if ($Eventos.PSObject.Properties.Match('EventosRelevantes').Count -gt 0 -and $Eventos.EventosRelevantes) {
            $eventosRelevantes = $Eventos.EventosRelevantes
        }
        if ($eventosRelevantes.Count -gt 0) {
            $eventosAgrupados = $eventosRelevantes | Group-Object -Property Id
            foreach ($grupo in $eventosAgrupados) {
                $id = "$($grupo.Name)"
                $contagem = [int]$grupo.Count
                $peso = 1 * [math]::Log($contagem + 1)
                if ($eventWeights.ContainsKey($id)) { $peso = $eventWeights[$id] * [math]::Log($contagem + 1) }
                $score -= $peso
                if ($peso -ge 5) { $issues.Add("[CRÍTICO] Evento relevante (ID: $id) detectado $contagem vezes.") }
                else             { $issues.Add("[ALERTA] Evento relevante (ID: $id) detectado $contagem vezes.") }
            }
        }

        if ($Eventos.PSObject.Properties.Match('BugCheck154').Count -gt 0) {
            $bc = $Eventos.BugCheck154
            if ($bc -and ($bc | Measure-Object).Count -gt 0) {
                $score -= 20
                $issues.Add("[CRÍTICO] Bugcheck 154 detectado. Indica falha grave de disco/RAM.")
            }
        }
    }

    # Serviços
    if ($ServiceStatus -and $ServiceStatus.PSObject.Properties.Match('CriticalServicesNotRunning')) {
        if ($ServiceStatus.CriticalServicesNotRunning.Count -gt 0) {
            $score -= 15
            $issues.Add("[CRÍTICO] Um ou mais serviços essenciais não estão em execução.")
        }
    }

    if ($score -lt 0) { $score = 0 }

    [pscustomobject]@{
        SaudePontuacao         = [int][math]::Round($score)
        ProblemasIdentificados = $issues
    }
}

function Write-TypingFormattedText {
    param(
        [Parameter(Mandatory=$true)][string]$Text,
        [Parameter(Mandatory=$false)][int]$Delay = 25,
        [Parameter(Mandatory=$false)][string]$ForegroundColor = "White",
        [Parameter(Mandatory=$false)][int]$LineWidth,
        [Parameter(Mandatory=$false)][string]$Indent = ""
    )
    $lines = @()
    $words = $Text -split ' '
    $currentLine = ""
    $effectiveLineWidth = [math]::Max(20, ($LineWidth - $Indent.Length))
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
        foreach ($char in $line.ToCharArray()) {
            Write-Host -NoNewline $char -ForegroundColor $ForegroundColor
            Start-Sleep -Milliseconds $Delay
        }
        Write-Host ""
    }
}

function Start-DiagnosticAnalysis {
    param([Parameter(Mandatory=$true)][string]$JsonPath)

    if (-not (Test-Path $JsonPath)) {
        throw "Arquivo de diagnóstico '$JsonPath' não encontrado. Execute a opção apropriada do fluxo primeiro."
    }

    $data = Get-Content $JsonPath -Raw | ConvertFrom-Json

    Clear-Host
    $windowWidth = $Host.UI.RawUI.WindowSize.Width
    $reportWidth = $windowWidth - 4

    $intelligentSummary = Get-IntelligentSummary -AnalysisData $data.Analise -RawData $data
    Write-Host "[DIAGNÓSTICO INTELIGENTE]" -ForegroundColor Cyan
    Write-FormattedColoredString -Text $intelligentSummary.Summary -LineWidth $reportWidth -Indent "" -ForegroundColor White
    if ($intelligentSummary.Recommendations) {
        $intelligentSummary.Recommendations | ForEach-Object {
            Write-FormattedColoredString -Text "- $_" -LineWidth $reportWidth -Indent "  " -ForegroundColor Yellow
        }
    }

    Write-Host "`n--- DADOS TÉCNICOS ---" -ForegroundColor DarkGray
    $healthScore = 0
    if ($null -ne $data.Analise -and $null -ne $data.Analise.SaudePontuacao) {
        $healthScore = [int]$data.Analise.SaudePontuacao
    }
    $scoreColor = if ($healthScore -ge 80) { "Green" } elseif ($healthScore -ge 75) { "Yellow" } else { "Red" }
    Write-Host "Pontuação de Saúde do Sistema: $healthScore/100" -ForegroundColor $scoreColor

    # [HARDWARE] (igual versão anterior) ...
    Write-Host "`n[HARDWARE]" -ForegroundColor White
    if ($data.Hardware -and -not $data.Hardware.Error) {
        if ($data.Hardware.RAM -and $null -ne $data.Hardware.RAM.UsedPercent) {
            $ramUsed  = [int]$data.Hardware.RAM.UsedPercent
            $ramTotal = [int]$data.Hardware.RAM.TotalGB
            $ramText  = "Uso de RAM: $ramUsed% (Total: $ramTotal GB)"
            if     ($ramUsed -ge 95) { Write-FormattedColoredString -Text "$ramText - CRÍTICO! Desempenho severamente afetado." -LineWidth $reportWidth -ForegroundColor Red }
            elseif ($ramUsed -ge 80) { Write-FormattedColoredString -Text "$ramText - ALERTA: Uso alto, porém possível."      -LineWidth $reportWidth -ForegroundColor Yellow }
            else                     { Write-FormattedColoredString -Text "$ramText - Normal."                                -LineWidth $reportWidth -ForegroundColor Green }
        }
        if ($data.Hardware.Disks) {
            foreach ($disk in $data.Hardware.Disks) {
                if ($disk -and $null -ne $disk.FreePercent -and $null -ne $disk.TotalGB) {
                    $diskColor = if ($disk.FreePercent -lt 15) { "Red" } elseif ($disk.FreePercent -lt 30) { "Yellow" } else { "Green" }
                    Write-FormattedColoredString -Text "Disco $($disk.DeviceID): $($disk.FreeGB) GB livres ($($disk.FreePercent)%) - Tipo: $($disk.Tipo)" -LineWidth $reportWidth -ForegroundColor $diskColor
                } else {
                    Write-FormattedColoredString -Text "Disco $($disk.DeviceID): Dados de espaço livre não disponíveis." -LineWidth $reportWidth -ForegroundColor Yellow
                }
            }
        }
    } else {
        Write-Host "Falha na coleta de Hardware: $($data.Hardware.Error)" -ForegroundColor Red
    }

    # --- REDE ---
    Write-Host "`n"
    Write-Host "[REDE]" -ForegroundColor White

    if ($data.Rede -and -not $data.Rede.Error) {
        if ($null -ne $data.Rede.HasInternetConnection) {
            $networkColor = if ($data.Rede.HasInternetConnection) { "Green" } else { "Red" }
            $networkStatusText = if ($data.Rede.HasInternetConnection) { 'Conectado' } else { 'Desconectado' }
            Write-FormattedColoredString -Text "Status da Internet: $networkStatusText" -LineWidth $reportWidth -Indent "" -ForegroundColor $networkColor
        } else {
            Write-FormattedColoredString -Text "Status da Internet: Indisponível" -LineWidth $reportWidth -Indent "" -ForegroundColor Yellow
        }

        if ($data.Rede.Interface) {
            Write-FormattedColoredString -Text ("Interface: {0}" -f $data.Rede.Interface) -LineWidth $reportWidth -Indent "" -ForegroundColor Gray
        }

        $ipv4 = if ($data.Rede.IPv4) { $data.Rede.IPv4 } else { "N/D" }
        $gw   = if ($data.Rede.Gateway) { $data.Rede.Gateway } else { "N/A" }
        Write-FormattedColoredString -Text ("IPv4: {0}  |  Gateway: {1}" -f $ipv4, $gw) -LineWidth $reportWidth -Indent "" -ForegroundColor Gray

        if ($data.Rede.DNS) {
            $dnsList = @()
            foreach ($d in $data.Rede.DNS) { $dnsList += "$d" }
            if ($dnsList.Count -gt 0) {
                Write-FormattedColoredString -Text ("DNS:  {0}" -f ($dnsList -join ", ")) -LineWidth $reportWidth -Indent "" -ForegroundColor Gray
            }
        }

        if ($data.Rede.Latency -and $data.Rede.Latency.Keys.Count -gt 0) {
            Write-Host "`nLatência (média/mediana, perda):" -ForegroundColor Gray
            foreach ($k in $data.Rede.Latency.Keys) {
                $l = $data.Rede.Latency.$k
                if ($null -eq $l) {
                    Write-FormattedColoredString -Text (" - {0}  N/D" -f $k) -LineWidth $reportWidth -Indent "" -ForegroundColor Gray
                    continue
                }
                $line = Format-LatencyDisplay -Target $k -LatencyObj $l
                Write-FormattedColoredString -Text $line -LineWidth $reportWidth -Indent "" -ForegroundColor Gray
            }
        } else {
            Write-FormattedColoredString -Text "Latência: N/D" -LineWidth $reportWidth -Indent "" -ForegroundColor Gray
        }
    }
    else {
        Write-Host ("Falha na coleta de Rede: {0}" -f ($data.Rede?.Error ?? "N/D")) -ForegroundColor Red
    }

    # [ESTABILIDADE DO SISTEMA] (igual versão anterior com checks safe)
    Write-Host "`n[ESTABILIDADE DO SISTEMA]" -ForegroundColor White
    if ($data.EventosCriticos -and -not $data.EventosCriticos.Error) {
        $eventCount = $data.EventosCriticos.TotalEventos
        $eventRelevantesCount = 0
        if ($data.EventosCriticos.PSObject.Properties.Match('EventosRelevantes').Count -gt 0 -and $data.EventosCriticos.EventosRelevantes) {
            $eventRelevantesCount = $data.EventosCriticos.EventosRelevantes.Count
        }
        $eventCriticosCount = 0
        if ($data.EventosCriticos.PSObject.Properties.Match('EventosCriticos').Count -gt 0 -and $data.EventosCriticos.EventosCriticos) {
            $eventCriticosCount = $data.EventosCriticos.EventosCriticos.Count
        }
        Write-Host "Total de eventos críticos nos últimos 7 dias: $eventCount" -ForegroundColor DarkGray
        Write-Host "  -> Eventos relevantes (falhas): $eventRelevantesCount" -ForegroundColor Red
        Write-Host "  -> Eventos gerais (erros): $eventCriticosCount" -ForegroundColor Yellow

        if ($data.EventosCriticos.PSObject.Properties.Match('BugCheck154').Count -gt 0) {
            $bc = $data.EventosCriticos.BugCheck154
            if ($bc -and ($bc | Measure-Object).Count -gt 0) {
                Write-Host "`nSugestões para Bugcheck 154:" -ForegroundColor Cyan
                $explicacao = Get-ExplicacaoPorBugCheck -bugCheckId "154"
                Write-FormattedColoredString -Text "  - $explicacao" -LineWidth $reportWidth -Indent "    " -ForegroundColor Yellow
            }
        }

        if ($eventRelevantesCount -gt 0) {
            Write-Host "`nSugestões para Eventos Relevantes:" -ForegroundColor Cyan
            $eventosAgrupados = $data.EventosCriticos.EventosRelevantes | Group-Object -Property Id
            foreach ($grupo in $eventosAgrupados) {
                $explicacao = Get-ExplicacaoPorID -id $grupo.Name
                Write-FormattedColoredString -Text "  - $explicacao" -LineWidth $reportWidth -Indent "    " -ForegroundColor Yellow
            }
        }
    } else {
        Write-Host "Falha na coleta de Eventos: $($data.EventosCriticos.Error)" -ForegroundColor Red
    }

    # [SERVIÇOS CRÍTICOS] (igual)
    Write-Host "`n[SERVIÇOS CRÍTICOS]" -ForegroundColor White
    if ($data.Servicos -and -not $data.Servicos.Error) {
        if ($data.Servicos.CriticalServicesNotRunning.Count -gt 0) {
            Write-Host "Serviços essenciais que não estão em execução:" -ForegroundColor Red
            $data.Servicos.CriticalServicesNotRunning | ForEach-Object {
                $explicacao = Get-ExplicacaoPorID -id "SERVICO_CRITICO_STOPPED"
                Write-FormattedColoredString -Text ("  - {0}: {1}" -f $_.Name, $explicacao) -LineWidth $reportWidth -ForegroundColor Yellow
            }
        } else {
            Write-Host "Todos os serviços críticos estão em execução." -ForegroundColor Green
        }
    } else {
        Write-Host "Falha na coleta de serviços: $($data.Servicos.Error)" -ForegroundColor Red
    }

    # [INDEXADOR DE PESQUISA]
    Write-Host "`n[INDEXADOR DE PESQUISA]" -ForegroundColor White
    if ($data.Indexador -and -not $data.Indexador.Error) {
        Write-Host ("Status do serviço WSearch: {0}" -f ($data.Indexador.WSearchStatus ?? 'N/D')) -ForegroundColor Gray
        Write-Host ("Recurso SearchEngine-Client-Package habilitado: {0}" -f ($data.Indexador.FeatureEnabled ?? 'N/D')) -ForegroundColor Gray
    } else {
        Write-Host ("Falha na coleta do Indexador: {0}" -f ($data.Indexador?.Error ?? "N/D")) -ForegroundColor Yellow
    }

    Write-Host "`n========================================================================================================================================================================" -ForegroundColor Cyan
}

Export-ModuleMember -Function `
    Start-DiagnosticAnalysis, Invoke-HealthAnalysis, Get-ExplicacaoPorID, `
    Get-IntelligentSummary, Write-FormattedColoredString, `
    Get-ExplicacaoPorBugCheck, Get-ManufacturerSoftwareSuggestion, `
    Write-TypingFormattedText, Format-LatencyDisplay
