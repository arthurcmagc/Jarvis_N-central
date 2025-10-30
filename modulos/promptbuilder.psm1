# promptbuilder.psm1
# -----------------------------------------------------------------------------------
# Gera um prompt técnico e compacto a partir de uma amostra de logs + sintoma do usuário.
# - Compatível com PowerShell 5.1 e 7+
# - Usa apenas verbos aprovados (PSUseApprovedVerbs)
# - Mantém compatibilidade: alias Build-IntelligentPrompt -> New-IntelligentPrompt
# -----------------------------------------------------------------------------------

#region Helpers (não exportados)

function ConvertTo-FlatJson {
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline = $true)]
        $InputObject,
        [int]$Depth = 4
    )
    process {
        try {
            return ($InputObject | ConvertTo-Json -Depth $Depth -Compress)
        } catch {
            # Fallback minimalista
            return ($InputObject | Out-String)
        }
    }
}

function Get-LogFingerprint {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [psobject]$LogEvent
    )

    $id  = ""
    $src = ""
    $msg = ""

    try {
        if ($LogEvent.PSObject.Properties.Match('Id').Count -gt 0)         { $id  = [string]$LogEvent.Id }
        elseif ($LogEvent.PSObject.Properties.Match('EventID').Count -gt 0) { $id  = [string]$LogEvent.EventID }

        if     ($LogEvent.PSObject.Properties.Match('Source').Count -gt 0)       { $src = [string]$LogEvent.Source }
        elseif ($LogEvent.PSObject.Properties.Match('ProviderName').Count -gt 0) { $src = [string]$LogEvent.ProviderName }

        if     ($LogEvent.PSObject.Properties.Match('Message').Count -gt 0)    { $msg = [string]$LogEvent.Message }
        elseif ($LogEvent.PSObject.Properties.Match('Descricao').Count -gt 0)  { $msg = [string]$LogEvent.Descricao }
    } catch {}

    $prefix = ""
    try {
        $len  = if ($msg) { $msg.Length } else { 0 }
        $take = [Math]::Min(64, [Math]::Max(0, $len))
        if ($take -gt 0) { $prefix = $msg.Substring(0, $take) }
    } catch {}

    return ("{0}|{1}|{2}" -f $id, $src, $prefix)
}

function Select-LogSample {
    <#
      Deduplica e limita a amostra de logs.
      - AllLogs: coleção heterogênea de objetos (EventLogRecord, PSObject, etc.)
      - MaxItems: limite de itens após deduplicação
      Retorno: lista de objetos limpos { Id, Source, Time, Message }
    #>
    [CmdletBinding()]
    param(
        [array]$AllLogs,
        [int]$MaxItems = 30
    )

    if (-not $AllLogs -or $AllLogs.Count -eq 0) { return @() }

    $seen = New-Object System.Collections.Generic.HashSet[string]
    $out  = New-Object System.Collections.Generic.List[object]

    foreach ($e in $AllLogs) {
        try {
           $finger = Get-LogFingerprint -LogEvent $e
            if ($seen.Add($finger)) {
                $id = ""
                $src = ""
                $time = $null
                $msg = ""

                if     ($e.PSObject.Properties.Match('Id').Count -gt 0)         { $id = [string]$e.Id }
                elseif ($e.PSObject.Properties.Match('EventID').Count -gt 0)     { $id = [string]$e.EventID }

                if     ($e.PSObject.Properties.Match('Source').Count -gt 0)      { $src = [string]$e.Source }
                elseif ($e.PSObject.Properties.Match('ProviderName').Count -gt 0){ $src = [string]$e.ProviderName }

                if     ($e.PSObject.Properties.Match('TimeCreated').Count -gt 0) { $time = $e.TimeCreated }

                if     ($e.PSObject.Properties.Match('Message').Count -gt 0)     { $msg = [string]$e.Message }
                elseif ($e.PSObject.Properties.Match('Descricao').Count -gt 0)   { $msg = [string]$e.Descricao }

                $out.Add([pscustomobject]@{
                    Id      = $id
                    Source  = $src
                    Time    = $time
                    Message = $msg
                })

                if ($out.Count -ge $MaxItems) { break }
            }
        } catch {
            # ignora item problemático e segue
            continue
        }
    }

    return $out
}

#endregion Helpers

#region Núcleo (exportado)

function New-IntelligentPrompt {
    <#
      Gera o texto do prompt para IA com base em:
      - Amostra de logs (opcional, deduplicada)
      - Sintoma relatado pelo usuário (obrigatório)
      - Orçamento de “tamanho” simples para o corpo (TargetTokenBudget)

      Mantém compatibilidade com chamadas antigas via alias Build-IntelligentPrompt.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)]
        [object[]]$AllLogs,

        [Parameter(Mandatory=$true)]
        [string]$UserSymptom,

        [int]$TargetTokenBudget = 2200
    )

    # 1) Seleção e sanitização de logs
    $sample = @()
    try {
        if ($AllLogs) {
            $sample = Select-LogSample -AllLogs $AllLogs -MaxItems 30
        }
    } catch { $sample = @() }

    $lines = @()
    if ($sample -and $sample.Count -gt 0) {
        foreach ($item in $sample) {
            try {
                # Formata cada item como JSON compacto, cortando caso muito grande
                $json = $item | ConvertTo-Json -Depth 4 -Compress
                if ($json.Length -gt 800) { $json = ($json.Substring(0, 800) + '…') }
                $lines += $json
            } catch {
                # Fallback por segurança
                $lines += (($item | ConvertTo-FlatJson -Depth 3) -as [string])
            }
        }
    } else {
        $lines = @("Sem eventos/entradas relevantes — utilizando resumo técnico mínimo do status coletado.")
    }

    # 2) “Achatamento” para caber (heurística simples)
    $acc = @()
    $accLen = 0
    foreach ($l in $lines) {
        if ([string]::IsNullOrWhiteSpace($l)) { continue }
        $chunk = $l.Trim()
        $accLen += $chunk.Length
        if ($accLen -gt 3000) { break } # margem pro resto
        $acc += $chunk
    }
    $logsJoined = "- " + ($acc -join "`r`n- ")

    # 3) Montagem do prompt
    $prompt = @"
**Contexto**
Você é um analista sênior de Windows e precisa gerar um relatório técnico a partir de um resumo de logs e de um sintoma.

**Sintoma reportado pelo usuário**
$UserSymptom

**Amostra de logs (resumida)**
$logsJoined

**Objetivo do relatório (responda em PT-BR técnico)**
1) Resumo do estado do equipamento (CPU/RAM/Disco/Rede) com base no que os logs sugerem.
2) Serviços críticos com falha/instabilidade e possíveis dependências.
3) Eventos relevantes (IDs, origem, quantidade/recorrência se aplicável).
4) Hipóteses principais do diagnóstico, com probabilidade (Alta/Média/Baixa).
5) Ações recomendadas imediatas e de médio prazo (comandos, ferramentas, rotinas).
6) Se necessário, incluir um plano de verificação (passo-a-passo) para o analista.

**Regras**
- Seja conciso, objetivo e priorize clareza.
- Deduzir a partir dos logs; evite suposições não fundamentadas.
- Agrupe eventos repetidos; cite apenas uma amostra de mensagens longas.
- Use marcadores e subtítulos para facilitar leitura.
"@

    return $prompt
}

# Alias para compatibilidade com versões antigas
Set-Alias -Name Build-IntelligentPrompt -Value New-IntelligentPrompt -Force

Export-ModuleMember -Function New-IntelligentPrompt -Alias Build-IntelligentPrompt

#endregion Núcleo
