# events.psm1
# Coleta eventos críticos/erros dos últimos 7 dias + bugcheck 154 (seguro) e garante shape estável.

function Convert-TruncateString {
    param(
        [Parameter(Mandatory=$true)][string]$Text,
        [int]$Max = 300
    )
    if ([string]::IsNullOrWhiteSpace($Text)) { return "" }
    if ($Text.Length -le $Max) { return $Text }
    return ($Text.Substring(0, $Max) + " ...")
}

function Get-CriticalEvents {
    try {
        $since = (Get-Date).AddDays(-7)

        # Coleta básica (Critical + Error) de System e Application
        $filter = @{
            StartTime = $since
            Level     = 1,2
            LogName   = 'System','Application'
        }

        $raw = @()
        try {
            $raw = Get-WinEvent -FilterHashtable $filter -ErrorAction SilentlyContinue
        } catch {}

        # Converte para objetos simples
        $eventsConverted = @()
        foreach ($e in $raw) {
            $eventsConverted += [pscustomobject]@{
                Id           = $e.Id
                ProviderName = $e.ProviderName
                TimeCreated  = $e.TimeCreated
                Message      = Convert-TruncateString -Text ($e.Message)
            }
        }

        # Relevantes por ID
        $relevantIDs = @(41,55,7031,7024,7043,7000,7001,1001,10010,10016)
        $eventosRelevantes = @()
        if ($eventsConverted) {
            $eventosRelevantes = $eventsConverted | Where-Object { $relevantIDs -contains $_.Id }
        }

        # Demais críticos/erros
        $eventosCriticos = @()
        if ($eventsConverted) {
            $eventosCriticos = $eventsConverted | Where-Object { $relevantIDs -notcontains $_.Id }
        }

        # Bugcheck 154: Event 1001 com "154" na mensagem
        $bug154 = @()
        try {
            $bugFilter = @{ StartTime = $since; Id = 1001; LogName = 'System' }
            $bugRaw = Get-WinEvent -FilterHashtable $bugFilter -ErrorAction SilentlyContinue
            if ($bugRaw) {
                foreach ($e in $bugRaw) {
                    if ($e.Message -and $e.Message -match '\b154\b') {
                        $bug154 += [pscustomobject]@{
                            Id           = 1001
                            ProviderName = $e.ProviderName
                            TimeCreated  = $e.TimeCreated
                            Message      = Convert-TruncateString -Text ($e.Message)
                        }
                    }
                }
            }
        } catch {}

        $result = [pscustomobject]@{
            TotalEventos      = ($eventsConverted | Measure-Object).Count
            EventosRelevantes = $eventosRelevantes
            EventosCriticos   = $eventosCriticos
            Events            = $eventsConverted
            BugCheck154       = $bug154
        }

        # Shape estável
        if (-not $result.PSObject.Properties.Match('BugCheck154'))       { $result | Add-Member -NotePropertyName 'BugCheck154'       -NotePropertyValue @() }
        if (-not $result.PSObject.Properties.Match('EventosRelevantes')) { $result | Add-Member -NotePropertyName 'EventosRelevantes' -NotePropertyValue @() }
        if (-not $result.PSObject.Properties.Match('EventosCriticos'))   { $result | Add-Member -NotePropertyName 'EventosCriticos'   -NotePropertyValue @() }
        if (-not $result.PSObject.Properties.Match('Events'))            { $result | Add-Member -NotePropertyName 'Events'            -NotePropertyValue @() }

        return $result
    } catch {
        return [pscustomobject]@{ Error = "Falha na coleta de eventos: $($_.Exception.Message)" }
    }
}

Export-ModuleMember -Function Get-CriticalEvents
