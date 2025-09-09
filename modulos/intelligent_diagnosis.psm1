# Módulo de Diagnóstico Inteligente
# Traduz os dados técnicos em uma conclusão clara e proativa.

function Get-IntelligentSummary {
    param (
        [Parameter(Mandatory=$true)]
        [psobject]$AnalysisData,
        [Parameter(Mandatory=$true)]
        [psobject]$RawData
    )

    $summary = ""
    $recommendation = @()
    $healthScore = $AnalysisData.SaudePontuacao

    # 1. Resumo da Saúde Geral
    if ($healthScore -gt 80) {
        $summary = "A máquina está em bom estado de saúde. A pontuação de $healthScore/100 indica que os problemas detectados são de baixa gravidade e não devem comprometer o desempenho de forma significativa."
    } elseif ($healthScore -gt 50) {
        $summary = "A máquina apresenta sinais de problemas de desempenho. A pontuação de $healthScore/100 sugere que há problemas recorrentes que podem causar lentidão e instabilidade."
    } else {
        $summary = "A máquina está em estado crítico de saúde. A pontuação de $healthScore/100 é um alerta para problemas graves que podem estar causando travamentos, falhas e comprometimento do desempenho."
    }

    # 2. Análise e Recomendação Baseada nos Problemas
    $ramUsage = $RawData.Hardware.RAM.UsedPercent
    $relevantEventsCount = $RawData.EventosCriticos.EventosRelevantes.Count
    $diskSpace = $RawData.Hardware.Disks[0].FreePercent

    if ($ramUsage -ge 90) {
        $recommendation += "A causa mais provável de lentidão é o **alto uso de RAM ($ramUsage%)**. O sistema está usando o disco para simular memória, o que impacta drasticamente a velocidade. **Ação recomendada:** Fechar programas pesados ou aumentar a memória RAM."
    } elseif ($relevantEventsCount -gt 10) {
        $recommendation += "A estabilidade do sistema está comprometida. A alta contagem de eventos relevantes ($relevantEventsCount) indica falhas de serviço e desligamentos inesperados. **Ação recomendada:** Analisar os logs para identificar a causa raiz das falhas."
    } elseif ($diskSpace -lt 15) {
        $recommendation += "O espaço em disco está criticamente baixo ($diskSpace% livre). Isso pode impedir atualizações e causar lentidão. **Ação recomendada:** Limpar arquivos temporários e liberar espaço no disco C:."
    }

    if ($recommendation.Count -eq 0) {
        $recommendation += "Nenhum problema grave foi encontrado. A máquina está operando dentro dos parâmetros normais."
    }
    
    return [pscustomobject]@{
        Summary = $summary
        Recommendations = $recommendation
    }
}

Export-ModuleMember -Function Get-IntelligentSummary