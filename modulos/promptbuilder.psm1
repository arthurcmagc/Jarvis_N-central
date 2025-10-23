# promptbuilder.psm1
# Construtor de prompt inteligente (robusto a nulos e com orçamento)

function Write-PromptLog {
    param([string]$Message)
    try { Write-Host "[PROMPT] $Message" -ForegroundColor DarkGray } catch {}
}

function New-SystemPrompt {
    param(
        [string]$Role = "Você é um assistente especialista em Windows, redes e análise de logs."
    )
@"
$Role
Siga boas práticas de diagnóstico e seja objetivo.
"@
}

function Build-IntelligentPrompt {
    [CmdletBinding()]
    param(
        [Alias('Logs')]
        [array]$AllLogs = @(),            # tolera $null
        [string]$UserSymptom = "",
        [int]$TargetTokenBudget = 2500,
        [int]$MaxItemsInitial   = 160
    )

    # garantia: sempre array
    $AllLogs = @($AllLogs) | Where-Object { $_ -ne $null }

    # heurística simples de orçamento: 1 item ~ 30 tokens (grosseiro)
    $approxTokensPerItem = 30
    $maxItems = [math]::Max(20, [math]::Floor($TargetTokenBudget / $approxTokensPerItem))

    # preferir erros/criticos e recentes (se tiver campos)
    $logsRanked =
        ($AllLogs | Where-Object { $_.Level -match 'Error|Critical' }) +
        ($AllLogs | Where-Object { $_.Level -notmatch 'Error|Critical' })

    # ordenar por Data/Time se houver
    $logsRanked = $logsRanked | Sort-Object {
        if ($_.TimeCreated) { try { [datetime]$_.TimeCreated } catch { Get-Date 0 } }
        elseif ($_.TimeGenerated) { try { [datetime]$_.TimeGenerated } catch { Get-Date 0 } }
        else { Get-Date 0 }
    } -Descending

    if (-not $logsRanked -or $logsRanked.Count -eq 0) {
        Write-PromptLog "Nenhum log fornecido; usarei placeholders mínimos."
        $logsRanked = @()
    }

    $sample = $logsRanked | Select-Object -First ([math]::Min($maxItems, $MaxItemsInitial))

    # compactar cada item para evitar JSON gigante (somente campos-chave)
    $compact = foreach ($e in $sample) {
        [ordered]@{
            Time   = ($e.TimeCreated, $e.TimeGenerated, $e.Time)[0]
            Id     = $e.Id
            Source = $e.ProviderName ?? $e.Source
            Level  = $e.LevelDisplayName ?? $e.Level
            Msg    = $e.Message
        }
    }

    $logsJson = ($compact | ConvertTo-Json -Depth 3)

    $sym = if ([string]::IsNullOrWhiteSpace($UserSymptom)) { "Não informado" } else { $UserSymptom }

@"
🧠 CONTEXTO (sistema/diagnóstico)
$(New-SystemPrompt)

🗣️ Sintoma relatado pelo usuário
$sym

📁 Amostra de eventos (recente/erro primeiro, compactados)
$logsJson

🎯 Objetivo
1) Resumo do estado provável e possíveis causas alinhadas ao sintoma.
2) Sinais em serviços, rede, armazenamento, updates, drivers.
3) Ações priorizadas: rápidas, seguras e com comandos (PowerShell/CMD).
4) Itens de monitoramento (o que acompanhar nas próximas 24–48h).

⚠️ Regras
- Seja conciso; agrupe eventos repetidos (cite contagem).
- Destaque [ALERTA] e [CRÍTICO] onde fizer sentido.
- Inclua comandos prontos quando houver correção sugerida.
"@
}

Export-ModuleMember -Function Write-PromptLog, New-SystemPrompt, Build-IntelligentPrompt
