# promptbuilder.psm1
# -----------------------------------------------------------------------------------
# Gera um prompt técnico e compacto a partir de logs + sintoma + MachineInfo (opcional)
# - Verbos aprovados
# - Compatível PS 5.1/7+
# - Alias Build-IntelligentPrompt -> New-IntelligentPrompt
# -----------------------------------------------------------------------------------

function ConvertTo-FlatJson {
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline = $true)]
        $InputObject,
        [int]$Depth = 4
    )
    process {
        try { return ($InputObject | ConvertTo-Json -Depth $Depth -Compress) }
        catch { return ($InputObject | Out-String) }
    }
}

function Get-LogFingerprint {
    [CmdletBinding()]
    param([Parameter(Mandatory)][psobject]$LogEvent)

    $id  = ""; $src = ""; $msg = ""; $prefix = ""
    try {
        if ($LogEvent.PSObject.Properties.Match('Id').Count -gt 0)         { $id  = [string]$LogEvent.Id }
        elseif ($LogEvent.PSObject.Properties.Match('EventID').Count -gt 0) { $id  = [string]$LogEvent.EventID }
        if ($LogEvent.PSObject.Properties.Match('Source').Count -gt 0)       { $src = [string]$LogEvent.Source }
        elseif ($LogEvent.PSObject.Properties.Match('ProviderName').Count -gt 0) { $src = [string]$LogEvent.ProviderName }
        if ($LogEvent.PSObject.Properties.Match('Message').Count -gt 0)     { $msg = [string]$LogEvent.Message }
        elseif ($LogEvent.PSObject.Properties.Match('Descricao').Count -gt 0) { $msg = [string]$LogEvent.Descricao }
        $take = [Math]::Min(64, [Math]::Max(0, $msg.Length))
        if ($take -gt 0) { $prefix = $msg.Substring(0, $take) }
    } catch {}
    return ("{0}|{1}|{2}" -f $id,$src,$prefix)
}

function Select-LogSample {
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
                $id=""; $src=""; $time=$null; $msg=""
                if ($e.PSObject.Properties.Match('Id').Count -gt 0)         { $id = [string]$e.Id }
                elseif ($e.PSObject.Properties.Match('EventID').Count -gt 0){ $id = [string]$e.EventID }
                if ($e.PSObject.Properties.Match('Source').Count -gt 0)      { $src = [string]$e.Source }
                elseif ($e.PSObject.Properties.Match('ProviderName').Count -gt 0){ $src = [string]$e.ProviderName }
                if ($e.PSObject.Properties.Match('TimeCreated').Count -gt 0) { $time = $e.TimeCreated }
                if ($e.PSObject.Properties.Match('Message').Count -gt 0)     { $msg = [string]$e.Message }
                elseif ($e.PSObject.Properties.Match('Descricao').Count -gt 0){ $msg = [string]$e.Descricao }

                $out.Add([pscustomobject]@{
                    Id      = $id
                    Source  = $src
                    Time    = $time
                    Message = $msg
                })
                if ($out.Count -ge $MaxItems) { break }
            }
        } catch { continue }
    }
    return $out
}

function New-IntelligentPrompt {
    [CmdletBinding()]
    param(
        [Parameter()][object[]]$AllLogs,
        [Parameter(Mandatory)][string]$UserSymptom,
        [Parameter()][psobject]$MachineInfo,
        [int]$TargetTokenBudget = 2200
    )

    # 1) Amostra de logs
    $sample = @()
    try { if ($AllLogs) { $sample = Select-LogSample -AllLogs $AllLogs -MaxItems 30 } } catch {}
    $lines = @()
    if ($sample -and $sample.Count -gt 0) {
        foreach ($item in $sample) {
            try {
                $json = $item | ConvertTo-Json -Depth 4 -Compress
                if ($json.Length -gt 800) { $json = ($json.Substring(0,800)+'…') }
                $lines += $json
            } catch { $lines += (($item | ConvertTo-FlatJson -Depth 3) -as [string]) }
        }
    } else {
        $lines = @('Sem eventos/entradas relevantes — utilizando resumo técnico mínimo do status coletado.')
    }

    # 2) Enxuga
    $acc = @(); $accLen = 0
    foreach ($l in $lines) {
        if ([string]::IsNullOrWhiteSpace($l)) { continue }
        $chunk = $l.Trim()
        $accLen += $chunk.Length
        if ($accLen -gt 3000) { break }
        $acc += $chunk
    }
    $logsJoined = "- " + ($acc -join "`r`n- ")

    # 3) MachineInfo (linha única)
    $miLine = ""
    if ($MachineInfo) {
        $miLine = ("Hostname={0}; Windows={1}; Arch={2}; Fabricante={3}; Modelo={4}; Proc={5}; RAM={6}" -f `
            $MachineInfo.CsName, $MachineInfo.WindowsVersion, $MachineInfo.OsArchitecture, `
            $MachineInfo.CsManufacturer, $MachineInfo.CsModel, $MachineInfo.CsProcessors, $MachineInfo.CsTotalPhysicalMemory)
    } else {
        $miLine = "Informações do equipamento não disponíveis (MachineInfo ausente)."
    }

$prompt = @"
**Contexto**
Você é um analista sênior de Windows e precisa gerar um relatório técnico a partir de um resumo de logs e de um sintoma.

**Dados do equipamento**
$miLine

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

Set-Alias -Name Build-IntelligentPrompt -Value New-IntelligentPrompt -Force
Export-ModuleMember -Function New-IntelligentPrompt -Alias Build-IntelligentPrompt
