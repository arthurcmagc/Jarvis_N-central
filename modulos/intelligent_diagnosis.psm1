# intelligent_diagnosis.psm1
# Motor de pontuação (SelfHealing-style) – compatível PS 5.1/7+

function Get-UptimeDays {
    try {
        $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
        if ($null -ne $os -and $null -ne $os.LastBootUpTime) {
            $boot = $os.LastBootUpTime
            $ts = New-TimeSpan -Start $boot -End (Get-Date)
            return [int][math]::Floor($ts.TotalDays)
        }
    } catch {}
    return $null
}

function Get-MinDiskFreePercent {
    param($HardwareStatus)
    try {
        if ($null -eq $HardwareStatus -or $null -eq $HardwareStatus.Disks) { return $null }
        $min = $null
        foreach ($d in $HardwareStatus.Disks) {
            $pct = $null
            if ($null -ne $d.FreePercent) {
                $pct = [double]$d.FreePercent
            } elseif ($null -ne $d.TotalGB -and $null -ne $d.FreeGB -and [double]$d.TotalGB -gt 0) {
                $pct = ([double]$d.FreeGB / [double]$d.TotalGB) * 100.0
            }
            if ($null -ne $pct) {
                if ($null -eq $min -or $pct -lt $min) { $min = [math]::Round($pct,2) }
            }
        }
        return $min
    } catch { return $null }
}

function Measure-ServicesStopped {
    param($ServiceStatus)
    try {
        if ($null -eq $ServiceStatus) { return 0 }
        $down = $ServiceStatus.CriticalServicesNotRunning
        if ($null -eq $down) { return 0 }
        return @($down).Count
    } catch { return 0 }
}

function Get-EventCounts {
    param($Eventos)
    $counts = @{}
    try {
        if ($null -eq $Eventos) { return $counts }
        $lists = @()
        if ($Eventos.EventosRelevantes) { $lists += @($Eventos.EventosRelevantes) }
        if ($Eventos.EventosCriticos)   { $lists += @($Eventos.EventosCriticos) }
        foreach ($e in $lists) {
            $eid = $e.Id
            if ($null -ne $eid) {
                if (-not $counts.ContainsKey($eid)) { $counts[$eid] = 0 }
                $counts[$eid] = $counts[$eid] + 1
            }
        }
    } catch {}
    return $counts
}

function Measure-EventScore {
    param([hashtable]$Counts)
    $weights = @{
        41   = 10  # Kernel-Power
        55   = 10  # NTFS corruption
        153  = 10  # Disk error
        6008 = 8   # Unexpected shutdown
        7031 = 5
        7024 = 5
        7000 = 5
        7001 = 5
        1001 = 3   # BSOD
        10010= 2   # COM/DCOM
        10016= 1   # COM/DCOM perms
    }
    $score = 0.0
    foreach ($k in $Counts.Keys) {
        $n = [double]$Counts[$k]
        $w = 0.0
        if ($weights.ContainsKey($k)) { $w = [double]$weights[$k] }
        if ($w -gt 0 -and $n -gt 0) {
            $score += $w * [math]::Log($n + 1.0)
        }
    }
    return [math]::Round($score,2)
}

function Measure-CorruptionScore {
    param([hashtable]$Counts, [int]$ServicesDown)
    $score = 0

    $c55   = 0;   if ($Counts.ContainsKey(55))   { $c55   = [int]$Counts[55] }
    $c1001 = 0;   if ($Counts.ContainsKey(1001)) { $c1001 = [int]$Counts[1001] }
    $c153  = 0;   if ($Counts.ContainsKey(153))  { $c153  = [int]$Counts[153] }
    $c41   = 0;   if ($Counts.ContainsKey(41))   { $c41   = [int]$Counts[41]  }

    # ID55_NTFS: +20 por evento
    if ($c55  -gt 0) { $score += (20 * $c55) }
    # ID1001_BSOD: +15 por evento
    if ($c1001-gt 0) { $score += (15 * $c1001) }
    # ID153_DiskError: +15 por evento
    if ($c153 -gt 0) { $score += (15 * $c153) }
    # Múltiplas falhas de serviço
    if ($ServicesDown -ge 2) { $score += 20 }

    # Serviços parados + eventos críticos
    $totalEvents = 0
    foreach ($k in $Counts.Keys) { $totalEvents += [int]$Counts[$k] }
    if ($ServicesDown -gt 0 -and $totalEvents -gt 0) { $score += 25 }

    # ID41
    if ($c41 -gt 0) { $score += (10 * $c41) }

    return $score
}

function Convert-ScoreToClass {
    param([int]$Score)
    if     ($Score -ge 85) { return "EXCELENTE" }
    elseif ($Score -ge 70) { return "BOM" }
    elseif ($Score -ge 50) { return "ATENÇÃO" }
    elseif ($Score -ge 30) { return "RUIM" }
    else                   { return "CRÍTICO" }
}

function Invoke-HealthAnalysis {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]$HardwareStatus,
        [Parameter(Mandatory=$true)]$Eventos,
        [Parameter(Mandatory=$true)]$ServiceStatus,
        [Parameter(Mandatory=$false)]$NetworkStatus
    )

    $scoreBase = 100
    $pen   = @{}
    $bonus = @{}
    $issues = New-Object System.Collections.Generic.List[string]

    # RAM
    $ramPct = $null
    try {
        if ($null -ne $HardwareStatus -and $HardwareStatus.RAM -and $null -ne $HardwareStatus.RAM.UsedPercent) {
            $ramPct = [double]$HardwareStatus.RAM.UsedPercent
        }
    } catch {}
    $ramPenalty = 0
    if ($null -ne $ramPct) {
        if     ($ramPct -ge 95) { $ramPenalty = 25 }
        elseif ($ramPct -ge 90) { $ramPenalty = 20 }
        elseif ($ramPct -ge 85) { $ramPenalty = 15 }
        elseif ($ramPct -ge 80) { $ramPenalty = 12 }
        elseif ($ramPct -ge 75) { $ramPenalty = 10 }
        elseif ($ramPct -ge 70) { $ramPenalty = 7  }
        if ($ramPenalty -gt 0) { $issues.Add("[ALERTA] Uso de RAM elevado: $ramPct%"); $pen.RAM = -$ramPenalty }
    }

    # Disco (pior % livre)
    $minFreePct = Get-MinDiskFreePercent -HardwareStatus $HardwareStatus
    $diskPenalty = 0
    if ($null -ne $minFreePct) {
        if     ($minFreePct -lt 5)  { $diskPenalty = 25 }
        elseif ($minFreePct -lt 10) { $diskPenalty = 20 }
        elseif ($minFreePct -lt 15) { $diskPenalty = 15 }
        elseif ($minFreePct -lt 20) { $diskPenalty = 12 }
        elseif ($minFreePct -lt 25) { $diskPenalty = 10 }
        elseif ($minFreePct -lt 30) { $diskPenalty = 7  }
        if ($diskPenalty -gt 0) { $issues.Add("[ALERTA] Espaço em disco baixo: ${minFreePct}% livre no pior volume"); $pen.Disk = -$diskPenalty }
    }

    # Uptime
    $uptimeDays = Get-UptimeDays
    $uptimePenalty = 0
    if ($null -ne $uptimeDays) {
        if     ($uptimeDays -gt 90) { $uptimePenalty = 15 }
        elseif ($uptimeDays -gt 60) { $uptimePenalty = 12 }
        elseif ($uptimeDays -gt 30) { $uptimePenalty = 10 }
        if ($uptimePenalty -gt 0) { $issues.Add("[ATENÇÃO] Uptime alto: $uptimeDays dias"); $pen.Uptime = -$uptimePenalty }
    }

    # Serviços
    $svcDown = Measure-ServicesStopped -ServiceStatus $ServiceStatus
    $svcPenalty = 0
    if     ($svcDown -ge 3) { $svcPenalty = 15 }
    elseif ($svcDown -eq 2) { $svcPenalty = 12 }
    elseif ($svcDown -eq 1) { $svcPenalty = 10 }
    if ($svcPenalty -gt 0) { $issues.Add("[CRÍTICO] Serviços essenciais parados: $svcDown"); $pen.Services = -$svcPenalty }

    # Eventos
    $counts     = Get-EventCounts -Eventos $Eventos
    $eventScore = Measure-EventScore -Counts $counts
    $evPenalty  = 0
    if     ($eventScore -ge 50) { $evPenalty = 10 }
    elseif ($eventScore -ge 30) { $evPenalty = 7  }
    elseif ($eventScore -ge 15) { $evPenalty = 5  }
    elseif ($eventScore -ge 5)  { $evPenalty = 3  }
    if ($evPenalty -gt 0) { $issues.Add(("[ALERTA] EventScore elevado: {0}" -f $eventScore)); $pen.Events = -$evPenalty }

    # Corrupção
    $corrScore   = Measure-CorruptionScore -Counts $counts -ServicesDown $svcDown
    $corrPenalty = 0
    if     ($corrScore -ge 80) { $corrPenalty = 10 }
    elseif ($corrScore -ge 60) { $corrPenalty = 7  }
    elseif ($corrScore -ge 40) { $corrPenalty = 5  }
    elseif ($corrScore -ge 20) { $corrPenalty = 3  }
    if ($corrPenalty -gt 0) { $issues.Add(("[CRÍTICO] Sinais de corrupção/instabilidade: CorruptionScore={0}" -f $corrScore)); $pen.Corruption = -$corrPenalty }

    # Bônus simples (placeholder)
    $bonusCount  = 0
    try {
        if ($null -ne $NetworkStatus -and $NetworkStatus.Status -eq 'Conectado' -and ($NetworkStatus.LatenciaMs -is [int])) {
            if ($NetworkStatus.LatenciaMs -le 25) { $bonusCount += 1 }
        }
    } catch {}
    $bonusPoints = 0
    if     ($bonusCount -ge 5) { $bonusPoints = 3 }
    elseif ($bonusCount -ge 3) { $bonusPoints = 2 }
    if ($bonusPoints -gt 0) { $bonus.BonusCount = $bonusCount; $bonus.Points = +$bonusPoints }

    # Score final
    $totalPenalty = 0
    foreach ($k in $pen.Keys) { $totalPenalty += (-1 * [int]$pen[$k]) }
    $final = $scoreBase - $totalPenalty + $bonusPoints
    if ($final -lt 0)   { $final = 0 }
    if ($final -gt 100) { $final = 100 }
    $final = [int][math]::Round($final,0)

    $class = Convert-ScoreToClass -Score $final

    [pscustomobject]@{
        SaudePontuacao         = $final
        Classificacao          = $class
        EventScore             = $eventScore
        CorruptionScore        = $corrScore
        ProblemasIdentificados = $issues
        Detalhes = [pscustomobject]@{
            Penalizacoes   = $pen
            Bonus          = $bonus
            UptimeDias     = $uptimeDays
            MinDiskFreePct = $minFreePct
            RamUsedPct     = $ramPct
            ServicesDown   = $svcDown
        }
    }
}

Export-ModuleMember -Function Invoke-HealthAnalysis
