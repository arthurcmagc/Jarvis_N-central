# promptbuilder.psm1
# Constrói prompt compacto e técnico a partir de uma amostra de logs + sintoma do usuário.

function ConvertTo-FlatJson {
    param(
        [Parameter(ValueFromPipeline=$true)]
        $InputObject,
        [int]$Depth = 4
    )
    process {
        try { return ($InputObject | ConvertTo-Json -Depth $Depth -Compress) }
        catch { return ($InputObject | Out-String) }
    }
}

function Select-LogSample {
    param(
        [array]$AllLogs,
        [int]$MaxItems = 30
    )
    if (-not $AllLogs) { return @() }

    # Deduplica por (Id + Source + Message reduzida)
    $seen = [System.Collections.Generic.HashSet[string]]::new()
    $out  = New-Object System.Collections.Generic.List[object]

    foreach ($e in $AllLogs) {
        try {
            $id = ""
            if ($e.PSObject.Properties.Match('Id').Count -gt 0) { $id = [string]$e.Id }
            elseif ($e.PSObject.Properties.Match('EventID').Count -gt 0) { $id = [string]$e.EventID }

            $src = ""
            if ($e.PSObject.Properties.Match('Source').Count -gt 0) { $src = [string]$e.Source }
            elseif ($e.PSObject.Properties.Match('ProviderName').Count -gt 0) { $src = [string]$e.ProviderName }

            $msg = ""
            if ($e.PSObject.Properties.Match('Message').Count -gt 0) { $msg = [string]$e.Message }
            elseif ($e.PSObject.Properties.Match('Descricao').Count -gt 0) { $msg = [string]$e.Descricao }

            $finger = ("{0}|{1}|{2}" -f $id,$src,($msg.Substring(0,[Math]::Min(64,[Math]::Max(0,$msg.Length)))))
            if ($seen.Add($finger)) {
                $out.Add([pscustomobject]@{
                    Id=$id; Source=$src; Time=$e.TimeCreated; Message=$msg
                })
                if ($out.Count -ge $MaxItems) { break }
            }
        } catch { continue }
    }

    return $out
}

function Build-IntelligentPrompt {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)] [array]$AllLogs,
        [Parameter(Mandatory=$true)]  [string]$UserSymptom,
        [int]$TargetTokenBudget = 2200
    )

    # Fallbacks
    if ([string]::IsNullOrWhiteSpace($UserSymptom)) { $UserSymptom = "Não informado" }
    if (-not $AllLogs) { $AllLogs = @() }

    # Amostra enxuta
    $sample = Select-LogSample -AllLogs $AllLogs -MaxItems 30
    $logsJson = if ($sample.Count -gt 0) { $sample | ConvertTo-FlatJson -Depth 4 } else { "[]" }

    # Prompt técnico
    $prompt = @"
🧠 **Contexto**
Você é um analista sênior de Windows e precisa gerar um relatório técnico a partir de um resumo de logs e de um sintoma do usuário.

🗣️ **Sintoma reportado pelo usuário**
$UserSymptom

📁 **Amostra de logs (resumida)**
$logsJson

🎯 **Objetivo do relatório (responda em PT-BR técnico)**
1) Resumo do estado do equipamento (CPU/RAM/Disco/Rede) com base no que os logs sugerem.
2) Serviços críticos com falha/instabilidade e possíveis dependências.
3) Eventos relevantes (IDs, origem, quantidade/recorrência se aplicável).
4) Hipóteses principais do diagnóstico, com probabilidade (Alta/Média/Baixa).
5) Ações recomendadas imediatas e de médio prazo (comandos, ferramentas, rotinas).
6) Se necessário, incluir um plano de verificação (passo-a-passo) para o analista.

⚠️ **Regras de saída**
- Seja conciso, objetivo e priorize clareza.
- Deduzir a partir dos logs; evite suposições não fundamentadas.
- Agrupe eventos repetidos; cite apenas uma amostra de mensagens longas.
- Use marcadores e subtítulos para facilitar leitura.
"@

    return $prompt
}

Export-ModuleMember -Function Build-IntelligentPrompt
