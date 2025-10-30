# events.psm1
# -----------------------------------------------------------------------------
# Get-CriticalEvents
#   - Compatível PS 5.1/7+
#   - Shape idêntico ao "backup":
#     {
#       "TotalEventos":  <int>,
#       "EventosRelevantes": [ {TimeCreated, Id, LevelDisplayName, Message}, ... ],
#       "EventosCriticos":   [ {TimeCreated, Id, LevelDisplayName, Message}, ... ]
#     }
# -----------------------------------------------------------------------------

function Get-SafeWinEvents {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][datetime]$StartTime,
        [Parameter(Mandatory=$true)][int[]]$Levels,          # 1=Critical, 2=Error
        [Parameter(Mandatory=$true)][string[]]$Logs,
        [int]$MaxToFetch = 2000
    )
    try {
        $filter = @{
            LogName   = $Logs
            Level     = $Levels
            StartTime = $StartTime
        }
        $ev = Get-WinEvent -FilterHashtable $filter -ErrorAction Stop |
              Select-Object -First $MaxToFetch -Property Id, LevelDisplayName, TimeCreated, Message
        return @($ev)
    } catch {
        return @()
    }
}

function Convert-ToSimpleEvent {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]$InputEvent
    )
    [pscustomobject]@{
        TimeCreated      = $InputEvent.TimeCreated
        Id               = $InputEvent.Id
        LevelDisplayName = $InputEvent.LevelDisplayName
        Message          = $InputEvent.Message
    }
}

function Get-CriticalEvents {
    [CmdletBinding()]
    param(
        [int]$Days = 7,
        [int]$MaxEventosLista = 30,       # limite para EventosCriticos
        [int]$MaxRelevantesLista = 30     # limite para EventosRelevantes
    )

    $since = (Get-Date).AddDays(-[math]::Abs($Days))
    $logs  = @('System','Application')
    $lvls  = @(1,2)   # Critical (1) e Error (2)

    $events = Get-SafeWinEvents -StartTime $since -Levels $lvls -Logs $logs -MaxToFetch 5000
    $totalEventos = @($events).Count

    # Ordena do mais novo para o mais antigo
    $ordered = $events | Sort-Object -Property TimeCreated -Descending

    # IDs “relevantes” para destacar
    $relevantIds = @(
        10010, # DCOM timeout/permissões
        10016, # DCOM permissions
        7009,  # Timeout de serviço
        7023,  # Serviço terminou com erro
        10005, # DCOM failed to start service
        11,    # erros diversos (conforme origem)
        20,    # Windows Update/Setup
        21,    # Windows Update/Setup
        1801   # Secure Boot/keys
    )

    # Monta listas com limites
    $eventosRelevantes = @()
    foreach ($e in $ordered) {
        if ($eventosRelevantes.Count -ge $MaxRelevantesLista) { break }
        foreach ($rid in $relevantIds) {
            if ($e.Id -eq $rid) { $eventosRelevantes += (Convert-ToSimpleEvent -InputEvent $e); break }
        }
    }

    $eventosCriticos = @()
    foreach ($e in $ordered) {
        if ($eventosCriticos.Count -ge $MaxEventosLista) { break }
        $eventosCriticos += (Convert-ToSimpleEvent -InputEvent $e)
    }

    [pscustomobject]@{
        TotalEventos      = $totalEventos
        EventosRelevantes = $eventosRelevantes
        EventosCriticos   = $eventosCriticos
    }
}

Export-ModuleMember -Function Get-CriticalEvents
