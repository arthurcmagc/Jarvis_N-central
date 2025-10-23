# interpretation.psm1
# Versão limpa e corrigida do módulo de análise.

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
    param(
        [Parameter(Mandatory=$true)]
        [string]$id
    )

    switch ("$id") {
        "41"      { return "[ID 41] - Desligamento inesperado. Pode indicar queda de energia ou travamento. Sugestão: Verificar no-break e logs de desligamento." }
        "55"      { return "[ID 55] - Corrupção no sistema de arquivos. Sugestão: Executar 'chkdsk' no volume afetado para verificar e reparar o disco." }
        "1001"    { return "[ID 1001] - Aplicativo apresentou erro. Sugestão: Reinstalar o aplicativo, verificar atualizações ou analisar o log específico do software." }
        "7031"    { return "[ID 7031] - Serviço foi finalizado de forma inesperada. Sugestão: Verificar dependências do serviço e tentar iniciá-lo manualmente." }
        "7024"    { return "[ID 7024] - Serviço terminou com erro. Sugestão: Analisar o log do serviço para mais detalhes, verificar dependências e permissões." }
        "7043"    { return "[ID 7043] - Serviço não foi desligado corretamente. Sugestão: Aumentar o tempo de espera para o desligamento de serviços ou verificar problemas de travamento." }
        "10010"   { return "[ID 10010] - DCOM não respondeu. Sugestão: Este erro é comum e geralmente não crítico. Ajustar permissões DCOM se causar problemas específicos." }
        "10016"   { return "[ID 10016] - Permissões DCOM incorretas. Sugestão: Este é um erro comum e frequentemente inofensivo." }
        "7000"    { return "[ID 7000] - Serviço não foi iniciado. Sugestão: Tentar iniciar o serviço manualmente e verificar as dependências." }
        "7001"    { return "[ID 7001] - Serviço dependente falhou ao iniciar. Sugestão: Iniciar o serviço dependente primeiro, ou verificar a ordem de inicialização." }
        "SERVICO_CRITICO_STOPPED" { return "[SERVIÇO CRÍTICO] - Um serviço essencial não está em execução. Sugestão: Iniciar o serviço manualmente ou verificar as configurações de inicialização." }
        Default   { return "[ID $id] - Evento de erro geral. Sugestão: Verificar o Log de Eventos do Windows para mais detalhes." }
    }
}

function Get-ExplicacaoPorBugCheck {
    param(
        [Parameter(Mandatory=$true)]
        [string]$bugCheckId
    )
    switch ("$bugCheckId") {
        "154" { return "[BUGCHECK 154] - Erro de sistema de arquivos crítico (KERNEL_DATA_INPAGE_ERROR). Causa: Geralmente indica um problema com o disco rígido, dados corrompidos ou falha de RAM. Sugestão: Executar chkdsk para verificar a integridade do disco e uma verificação SMART para a saúde do HD." }
        Default { return "[BUGCHECK $bugCheckId] - Código de parada do Windows. Sugestão: Pesquisar o código para identificar a causa e solução." }
    }
}

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

function Get-ManufacturerSoftwareSuggestion {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Manufacturer
    )
    $normalizedManufacturer = $Manufacturer.ToLower()
    switch -wildcard ($normalizedManufacturer) {
        "*dell*" {
            return "Essa máquina é da marca Dell. Utilize o software Dell Support Assist para uma análise completa e correções automáticas. Além disso, você pode executar em meu menu [3] as correções SFC e DISM para uma verificação profunda."
        }
        "*lenovo*" {
            return "Essa máquina é da marca Lenovo. Utilize o software Lenovo Vantage para gerenciar drivers, atualizações e otimizações. Além disso, você pode executar em meu menu [3] as correções SFC e DISM para uma verificação profunda."
        }
        "*hp*" {
            return "Essa máquina é da marca HP. Utilize o software HP Support Assistant para diagnóstico e atualizações de drivers. Além disso, você pode executar em meu menu [3] as correções SFC e DISM para uma verificação profunda."
        }
        "*samsung*" {
            return "Essa máquina é da marca Samsung. Utilize o software Samsung Update para gerenciar os drivers e programas pré-instalados. Além disso, você pode executar em meu menu [3] as correções SFC e DISM para uma verificação profunda."
        }
        Default {
            return "O fabricante da máquina é $Manufacturer. Para garantir que os drivers estejam atualizados, acesse o site oficial da fabricante e verifique a seção de suporte ou drivers. Além disso, você pode executar em meu menu [3] as correções SFC e DISM para uma verificação profunda."
        }
    }
}

function Get-IntelligentSummary {
    param(
        [Parameter(Mandatory=$true)]
        $AnalysisData,
        [Parameter(Mandatory=$true)]
        $RawData
    )

    $summaryText = "Resumo inteligente gerado: análise simples de saúde do sistema."
    $recs = @()
    if ($AnalysisData -and $AnalysisData.SaudePontuacao) {
        $score = $AnalysisData.SaudePontuacao
        if ($score -ge 80) {
            $summaryText = "Sistema com saúde geral boa (pontuação $score/100)."
            $recs += "Manter rotinas de monitoramento."
            $recs += "Revisar logs semanalmente."
        } elseif ($score -ge 50) {
            $summaryText = "Sistema com sinais moderados de alerta (pontuação $score/100)."
            $recs += "Feche aplicações não essenciais e verifique disco/RAM."
            $recs += "Agende uma análise detalhada dos eventos relevantes."
        } else {
            $summaryText = "Sistema em estado frágil (pontuação $score/100). Ação imediata recomendada."
            $recs += "Agendar backup e investigação de eventos críticos."
            $recs += "Considerar reinício controlado e checar integridade de disco."
        }
    } else {
        $recs += "Executar análise completa de hardware e logs."
        $recs += "Configurar coleta de dados se não existir."
    }

    return [pscustomobject]@{
        Summary = $summaryText
        Recommendations = $recs
    }
}

function Invoke-HealthAnalysis {
    param(
        [Parameter(Mandatory=$true)]
        $HardwareStatus,
        [Parameter(Mandatory=$true)]
        $Eventos,
        [Parameter(Mandatory=$false)]
        $ServiceStatus
    )

    $score = 100
    $issues = New-Object System.Collections.Generic.List[string]

    $eventWeights = @{
        "41" = 10;
        "55" = 10;
        "7031" = 5;
        "1001" = 3;
        "10010" = 2;
        "7024" = 5;
        "7043" = 5;
        "7000" = 5;
        "7001" = 5;
    }

    # RAM
    if ($null -ne $HardwareStatus -and $null -ne $HardwareStatus.PSObject.Properties.Match('RAM')) {
        $ram = $HardwareStatus.RAM
        if ($ram -and $null -ne $ram.UsedPercent) {
            $ramUsed = [int]$ram.UsedPercent
            if ($ramUsed -ge 95) {
                $score -= 15
                $issues.Add("[CRÍTICO] Uso de RAM: $ramUsed% (sistema pode estar lento).")
            } elseif ($ramUsed -ge 90) {
                $score -= 10
                $issues.Add("[ALTO] Uso de RAM: $ramUsed% (desempenho pode estar comprometido).")
            } elseif ($ramUsed -ge 80) {
                $score -= 3
                $issues.Add("[ALERTA] Uso de RAM: $ramUsed% (uso alto, mas normal).")
            }
        }
    }

    # Discos
    if ($null -ne $HardwareStatus -and $null -ne $HardwareStatus.PSObject.Properties.Match('Disks')) {
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
    if ($null -ne $Eventos -and $null -ne $Eventos.PSObject.Properties.Match('EventosRelevantes')) {
        $eventosRelevantes = $Eventos.EventosRelevantes
        if ($eventosRelevantes -and $eventosRelevantes.Count -gt 0) {
            $eventosAgrupados = $eventosRelevantes | Group-Object -Property Id
            foreach ($grupo in $eventosAgrupados) {
                $id = "$($grupo.Name)"
                $contagem = [int]$grupo.Count

                $peso = 0
                if ($eventWeights.ContainsKey($id)) {
                    $peso = $eventWeights[$id] * [math]::Log($contagem + 1)
                } else {
                    # peso mínimo para eventos não mapeados
                    $peso = 1 * [math]::Log($contagem + 1)
                }

                $score -= $peso
                if ($peso -ge 5) {
                    $issues.Add("[CRÍTICO] Evento relevante (ID: $id) detectado $contagem vezes.")
                } else {
                    $issues.Add("[ALERTA] Evento relevante (ID: $id) detectado $contagem vezes.")
                }
            }
        }
    }
    
    # Bugcheck 154
    if ($null -ne $Eventos -and $null -ne $Eventos.PSObject.Properties.Match('BugCheck154') -and $Eventos.BugCheck154.Count -gt 0) {
        $score -= 20
        $issues.Add("[CRÍTICO] Bugcheck 154 detectado. Indica falha grave de disco/RAM.")
    }

    # Serviços
    if ($null -ne $ServiceStatus -and $null -ne $ServiceStatus.PSObject.Properties.Match('CriticalServicesNotRunning')) {
        if ($ServiceStatus.CriticalServicesNotRunning.Count -gt 0) {
            $score -= 15
            $issues.Add("[CRÍTICO] Um ou mais serviços essenciais não estão em execução.")
        }
    }

    if ($score -lt 0) { $score = 0 }

    return [pscustomobject]@{
        SaudePontuacao = [int][math]::Round($score)
        ProblemasIdentificados = $issues
    }
}

# Combina animação com formatação de texto
function Write-TypingFormattedText {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Text,
        [Parameter(Mandatory=$false)]
        [int]$Delay = 25,
        [Parameter(Mandatory=$false)]
        [string]$ForegroundColor = "White",
        [Parameter(Mandatory=$false)]
        [int]$LineWidth,
        [Parameter(Mandatory=$false)]
        [string]$Indent = ""
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
        foreach ($char in $line.ToCharArray()) {
            Write-Host -NoNewline $char -ForegroundColor $ForegroundColor
            Start-Sleep -Milliseconds $Delay
        }
        Write-Host ""
    }
}

function Start-DiagnosticAnalysis {
    param(
        [Parameter(Mandatory=$true)]
        [string]$JsonPath
    )

    if (-not (Test-Path $JsonPath)) {
        throw "Arquivo de diagnóstico '$JsonPath' não encontrado. Execute a opção apropriada do fluxo primeiro."
    }

    $data = Get-Content $JsonPath -Raw | ConvertFrom-Json

    Clear-Host
    $windowWidth = $Host.UI.RawUI.WindowSize.Width
    $reportWidth = $windowWidth - 4

    # --- DIAGNÓSTICO INTELIGENTE ---
    $intelligentSummary = Get-IntelligentSummary -AnalysisData $data.Analise -RawData $data
    
    Write-Host "[DIAGNÓSTICO INTELIGENTE]" -ForegroundColor Cyan
    $summaryText = $intelligentSummary.Summary
    Write-FormattedColoredString -Text $summaryText -LineWidth $reportWidth -Indent "" -ForegroundColor White
    
    if ($intelligentSummary.Recommendations) {
        $intelligentSummary.Recommendations | ForEach-Object {
            $recommendation = "- $_"
            Write-FormattedColoredString -Text $recommendation -LineWidth $reportWidth -Indent "  " -ForegroundColor Yellow
        }
    }
    
    Write-Host "`n--- DADOS TÉCNICOS ---" -ForegroundColor DarkGray
    
    $healthScore = 0
    if ($null -ne $data.Analise -and $null -ne $data.Analise.SaudePontuacao) {
        $healthScore = [int]$data.Analise.SaudePontuacao
    }
    
    $scoreColor = if ($healthScore -ge 80) { "Green" } elseif ($healthScore -ge 75) { "Yellow" } else { "Red" }
    Write-Host "Pontuação de Saúde do Sistema: $healthScore/100" -ForegroundColor $scoreColor
    
    # --- HARDWARE ---
    Write-Host "`n"
    Write-Host "[HARDWARE]" -ForegroundColor White
    if ($null -ne $data.Hardware -and $null -ne $data.Hardware.Error) {
        Write-Host "Falha na coleta de Hardware: $($data.Hardware.Error)" -ForegroundColor Red
    } else {
        if ($null -ne $data.Hardware -and $null -ne $data.Hardware.RAM -and $null -ne $data.Hardware.RAM.UsedPercent) {
            $ramUsed = [int]$data.Hardware.RAM.UsedPercent
            $ramTotal = [int]$data.Hardware.RAM.TotalGB
    
            $ramStatusText = "Uso de RAM: $ramUsed% (Total: $ramTotal GB)"
            if ($ramUsed -ge 95) {
                Write-FormattedColoredString -Text "$ramStatusText - CRÍTICO! Desempenho severamente afetado." -LineWidth $reportWidth -Indent "" -ForegroundColor Red
            } elseif ($ramUsed -ge 80) {
                Write-FormattedColoredString -Text "$ramStatusText - ALERTA: Uso alto, mas normal para sistemas exigentes." -LineWidth $reportWidth -Indent "" -ForegroundColor Yellow
            } else {
                Write-FormattedColoredString -Text "$ramStatusText - Normal." -LineWidth $reportWidth -Indent "" -ForegroundColor Green
            }
        }
    
        if ($null -ne $data.Hardware -and $null -ne $data.Hardware.Disks) {
            foreach ($disk in $data.Hardware.Disks) {
                if ($disk -and $null -ne $disk.FreePercent -and $null -ne $disk.TotalGB) {
                    $diskColor = if ($disk.FreePercent -lt 15) { "Red" } elseif ($disk.FreePercent -lt 30) { "Yellow" } else { "Green" }
                    Write-FormattedColoredString -Text "Disco $($disk.DeviceID): $($disk.FreeGB) GB livres ($($disk.FreePercent)%) - Tipo: $($disk.Tipo)" -LineWidth $reportWidth -Indent "" -ForegroundColor $diskColor
                } else {
                    Write-FormattedColoredString -Text "Disco $($disk.DeviceID): Dados de espaço livre não disponíveis." -LineWidth $reportWidth -Indent "" -ForegroundColor Yellow
                }
            }
        }
    }
    
    # --- REDE ---
    Write-Host "`n"
    Write-Host "[REDE]" -ForegroundColor White
    if ($null -ne $data.Rede -and $null -ne $data.Rede.Error) {
        Write-Host "Falha na coleta de Rede: $($data.Rede.Error)" -ForegroundColor Red
    } else {
        # Status de Internet (se fornecido pelo módulo)
        if ($null -ne $data.Rede -and $null -ne $data.Rede.HasInternetConnection) {
            $networkColor = if ($data.Rede.HasInternetConnection) { "Green" } else { "Red" }
            $networkStatusText = if ($data.Rede.HasInternetConnection) { 'Conectado' } else { 'Desconectado' }
            Write-FormattedColoredString -Text "Status da Internet: $networkStatusText" -LineWidth $reportWidth -Indent "" -ForegroundColor $networkColor
        } else {
            Write-FormattedColoredString -Text "Status da Internet: Indisponível" -LineWidth $reportWidth -Indent "" -ForegroundColor Yellow
        }

        # Snapshot da interface (quando disponível)
        if ($data.Rede -and $data.Rede.Snapshot) {
            $snap = $data.Rede.Snapshot
            $iface = Get-Safe $snap 'InterfaceName'
            $ipv4  = Get-Safe $snap 'IPv4'
            $gw    = Get-Safe $snap 'Gateway'
            $dns   = Get-Safe $snap 'DNSServers'
            $status = Get-Safe $snap 'Status'

            Write-Host "Interface: $iface ($status)" -ForegroundColor DarkGray
            Write-Host "IPv4: $ipv4  |  Gateway: $gw" -ForegroundColor DarkGray
            Write-Host "DNS:  $dns" -ForegroundColor DarkGray
        }

        # Latência (quando disponível)
        if ($data.Rede -and $data.Rede.Latency) {
            Write-Host ""
            Write-Host "Latência (média/mediana, perda):" -ForegroundColor White
            foreach ($l in $data.Rede.Latency) {
                $avg = if ($l.AvgMs) { "$($l.AvgMs) ms" } else { "N/D" }
                $med = if ($l.MedMs) { "$($l.MedMs) ms" } else { "N/D" }
                $loss = if ($null -ne $l.LossPct) { "$($l.LossPct)%" } else { "N/D" }
                Write-Host (" - {0,-8} avg {1,6} | med {2,6} | perda {3,4}" -f $l.Target,$avg,$med,$loss) -ForegroundColor Gray
            }
        }
    }
    
    # --- ESTABILIDADE DO SISTEMA ---
    Write-Host "`n"
    Write-Host "[ESTABILIDADE DO SISTEMA]" -ForegroundColor White
    if ($null -ne $data.EventosCriticos -and $null -ne $data.EventosCriticos.Error) {
        Write-Host "Falha na coleta de Eventos: $($data.EventosCriticos.Error)" -ForegroundColor Red
    } else {
        if ($data.EventosCriticos) {
            $eventCount = $data.EventosCriticos.TotalEventos
            $eventRelevantesCount = 0
            if ($data.EventosCriticos.EventosRelevantes) { $eventRelevantesCount = $data.EventosCriticos.EventosRelevantes.Count }
            $eventCriticosCount = 0
            if ($data.EventosCriticos.EventosCriticos) { $eventCriticosCount = $data.EventosCriticos.EventosCriticos.Count }
    
            Write-Host "Total de eventos críticos nos últimos 7 dias: $eventCount" -ForegroundColor DarkGray
            Write-Host "  -> Eventos relevantes (falhas): $eventRelevantesCount" -ForegroundColor Red
            Write-Host "  -> Eventos gerais (erros): $eventCriticosCount" -ForegroundColor Yellow
    
            if ($null -ne $data.EventosCriticos.BugCheck154 -and $data.EventosCriticos.BugCheck154.Count -gt 0) {
                Write-Host "`nSugestões para Bugcheck 154:" -ForegroundColor Cyan
                $explicacao = Get-ExplicacaoPorBugCheck -bugCheckId "154"
                Write-FormattedColoredString -Text "  - $explicacao" -LineWidth $reportWidth -Indent "    " -ForegroundColor "Yellow"
            }
    
            if ($eventRelevantesCount -gt 0) {
                Write-Host "`nSugestões para Eventos Relevantes:" -ForegroundColor Cyan
                $eventosAgrupados = $data.EventosCriticos.EventosRelevantes | Group-Object -Property Id
                foreach ($grupo in $eventosAgrupados) {
                    $explicacao = Get-ExplicacaoPorID -id $grupo.Name
                    Write-FormattedColoredString -Text "  - $explicacao" -LineWidth $reportWidth -Indent "    " -ForegroundColor "Yellow"
                }
            }
        } else {
            Write-Host "Não há dados de eventos críticos." -ForegroundColor Green
        }
    }
    
    # --- SERVIÇOS CRÍTICOS ---
    Write-Host "`n"
    Write-Host "[SERVIÇOS CRÍTICOS]" -ForegroundColor White
    if ($null -ne $data.Servicos -and $null -ne $data.Servicos.Error) {
        Write-Host "Falha na coleta de serviços: $($data.Servicos.Error)" -ForegroundColor Red
    } elseif ($data.Servicos.CriticalServicesNotRunning.Count -gt 0) {
        Write-Host "Serviços essenciais que não estão em execução:" -ForegroundColor Red
        $data.Servicos.CriticalServicesNotRunning | ForEach-Object {
            $explicacao = Get-ExplicacaoPorID -id "SERVICO_CRITICO_STOPPED"
            $text = "- $($_.Name): $explicacao"
            Write-FormattedColoredString -Text "  $text" -LineWidth $reportWidth -Indent "    " -ForegroundColor "Yellow"
        }
    } else {
        Write-Host "Todos os serviços críticos estão em execução." -ForegroundColor Green
    }
    
    Write-Host "`n========================================================================================================================================================================" -ForegroundColor Cyan
}

Export-ModuleMember -Function Start-DiagnosticAnalysis, Invoke-HealthAnalysis, Get-ExplicacaoPorID, Get-IntelligentSummary, Write-FormattedColoredString, Get-ExplicacaoPorBugCheck, Get-ManufacturerSoftwareSuggestion, Write-TypingFormattedText
