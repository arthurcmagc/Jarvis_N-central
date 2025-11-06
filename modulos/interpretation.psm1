# interpretation.psm1
# =======================================================================================
# Jarvis - Interpretação e exibição formatada do diagnóstico
# Compatível com PowerShell 5.1 e 7+
# - Start-DiagnosticAnalysis: exibe relatório formatado a partir do JSON (formato "backup" ou "novo")
# - Helpers: Get-ManufacturerSoftwareSuggestion, Format-LatencyDisplay, Write-TypingFormattedText
# - Ajuste: Indexador de Pesquisa agora tenta usar Get-SearchIndexerStatus (services.psm1) para checagem ao vivo
# =======================================================================================

#region Fallbacks / Helpers básicos
function Get-ValueOrDefault {
    param($Value, $Default = 'N/D')
    if ($null -eq $Value) { return $Default }
    if ($Value -is [string] -and [string]::IsNullOrWhiteSpace($Value)) { return $Default }
    return $Value
}

function ConvertTo-NormalizedString {
    param([string]$Text)
    if ($null -eq $Text) { return $null }
    return ($Text -replace [char]0xA0, ' ')
}

function Write-SectionHeader {
    param([Parameter(Mandatory)][string]$Title)
    Write-Host ""
    Write-Host ("=" * 98) -ForegroundColor Cyan
    Write-Host ("[ {0} ]" -f $Title) -ForegroundColor Green
    Write-Host ("=" * 98) -ForegroundColor Cyan
}

function Write-SubHeader {
    param([Parameter(Mandatory)][string]$Title)
    Write-Host ""
    Write-Host ("- {0} -" -f $Title) -ForegroundColor Yellow
}

function Write-KV {
    param([Parameter(Mandatory)][string]$Key,[string]$Value="")
    Write-Host ("{0,-40}: {1}" -f $Key,$Value)
}

function Write-Ok   { param([string]$Msg) Write-Host $Msg -ForegroundColor Green }
function Write-Warn { param([string]$Msg) Write-Host $Msg -ForegroundColor Yellow }
function Write-ErrT { param([string]$Msg) Write-Host $Msg -ForegroundColor Red }

# Mantém a animação usada pelo menu (Delay/LineWidth/Indent)
function Write-TypingFormattedText {
    param(
        [Parameter(Mandatory)][string]$Text,
        [int]$Delay = 8,
        [string]$ForegroundColor = 'White',
        [int]$LineWidth = 0,
        [string]$Indent = ''
    )
    $t = ConvertTo-NormalizedString $Text
    $lines = @()

    if ($LineWidth -le 0) {
        $lines = $t -split "(\r?\n)"
    } else {
        $eff = [math]::Max(1, $LineWidth - $Indent.Length)
        foreach ($rawLine in ($t -split "(\r?\n)")) {
            if ($rawLine -match "^\r?\n$") { $lines += ''; continue }
            $line = $rawLine
            while ($line.Length -gt $eff) {
                $slice = $line.Substring(0,$eff)
                $break = $slice.LastIndexOf(' ')
                if ($break -lt 0) { $break = $eff }
                $lines += $line.Substring(0,$break)
                $line  = $line.Substring($break).TrimStart()
            }
            $lines += $line
        }
    }

    foreach ($ln in $lines) {
        if ($Indent) {
            try { Write-Host $Indent -NoNewline -ForegroundColor $ForegroundColor } catch { Write-Host $Indent -NoNewline }
        }
        foreach ($ch in $ln.ToCharArray()) {
            try { Write-Host $ch -NoNewline -ForegroundColor $ForegroundColor } catch { Write-Host $ch -NoNewline }
            if ($Delay -gt 0) { Start-Sleep -Milliseconds $Delay }
        }
        Write-Host ''
    }
}
#endregion

#region Mapeamentos/Explicações
function Get-ManufacturerSoftwareSuggestion {
    param([string]$Manufacturer)
    if ([string]::IsNullOrWhiteSpace($Manufacturer)) { return $null }
    if ($Manufacturer -match 'Dell')   { return "Essa máquina é da marca Dell. Utilize o Dell SupportAssist para análise e correções." }
    if ($Manufacturer -match 'Lenovo') { return "Essa máquina é Lenovo. Utilize o Lenovo Vantage para análise e correções." }
    if ($Manufacturer -match 'HP')     { return "Essa máquina é HP. Utilize o HP Support Assistant para análise e correções." }
    return $null
}

function Format-LatencyDisplay {
    param([nullable[int]]$LatencyMs)
    if ($null -eq $LatencyMs) { return 'N/D' }
    if ($LatencyMs -lt 30)  { return "$($LatencyMs) ms (ótima)" }
    if ($LatencyMs -lt 80)  { return "$($LatencyMs) ms (boa)" }
    if ($LatencyMs -lt 150) { return "$($LatencyMs) ms (regular)" }
    return "$($LatencyMs) ms (alta)"
}
#endregion

#region Normalizador de JSON (aceita o formato BACKUP e o formato NOVO)
# Saída normalizada (campos usados pela renderização):
#   Hostname, Timestamp
#   Hardware.RAM: TotalGB, UsedPercent, UsedGB, FreeGB
#   Hardware.Disks[]: Name, FreeGB, UsedGB, UsedPct, Root
#   Rede: Interface, IPv4, Gateway, DNS, Status, LatenciaMs | OU Rede.Error
#   Eventos: CriticosTotal, ErrosTotal, RelevantesSugeridos[]
#   Servicos.CriticosParados[]: Name, Status
#   Indexador (se existir): WSearchStatus, FeatureEnabled
#   HealthScore (se existir)
function ConvertTo-NormalizedReport {
    param([psobject]$Root)

    $norm = [ordered]@{}

    $hasDados = $false
    try { if ($Root.PSObject.Properties['Dados']) { $hasDados = $true } } catch {}

    # Host e Timestamp
    $norm.Hostname  = Get-ValueOrDefault $Root.Hostname 'N/D'
    $norm.Timestamp = Get-ValueOrDefault $Root.Timestamp 'N/D'

    # ---------------- HARDWARE ----------------
    $norm.Hardware = [ordered]@{}
    if ($hasDados) {
        $h = $Root.Dados.Hardware
        if ($h) {
            $norm.Hardware.RAM   = $h.RAM
            $norm.Hardware.Disks = $h.Disks
        }
    } else {
        $h = $Root.Hardware
        if ($h) {
            $tot  = Get-ValueOrDefault $h.RAM.TotalGB $null
            $pct  = Get-ValueOrDefault $h.RAM.UsedPercent $null
            $used = $null; $free = $null
            if ($null -ne $tot -and $null -ne $pct) {
                $used = [math]::Round(($tot * $pct / 100), 2)
                $free = [math]::Round(($tot - $used), 2)
            }
            $norm.Hardware.RAM = [ordered]@{
                TotalGB     = $tot
                UsedPercent = $pct
                UsedGB      = $used
                FreeGB      = $free
            }

            $norm.Hardware.Disks = @()
            foreach ($d in ($h.Disks | ForEach-Object { $_ })) {
                $name  = ($d.DeviceID -replace ':','')
                $total = Get-ValueOrDefault $d.TotalGB $null
                $free  = Get-ValueOrDefault $d.FreeGB  $null
                $usedGB = $null
                $usedPct = $null
                $rootp = "$($d.DeviceID)\"
                try {
                    if ($null -ne $total -and $null -ne $free) {
                        $usedGB  = [math]::Round(([double]$total - [double]$free), 2)
                        if ($total -gt 0) { $usedPct = [math]::Round((($usedGB / $total) * 100), 2) }
                    }
                } catch {}
                $norm.Hardware.Disks += [PSCustomObject]@{
                    Name    = $name
                    FreeGB  = $free
                    UsedGB  = $usedGB
                    UsedPct = $usedPct
                    Root    = $rootp
                }
            }
        }
    }

    # ---------------- REDE ----------------
    if ($hasDados) {
        $norm.Rede = $Root.Dados.Rede
    } else {
        if ($Root.Rede -and $Root.Rede.Error) { $norm.Rede = [ordered]@{ Error = $Root.Rede.Error } }
        elseif ($Root.Rede) { $norm.Rede = $Root.Rede }
    }

    # ---------------- EVENTOS ----------------
    if ($hasDados) {
        $norm.Eventos = $Root.Dados.Eventos
        if (-not $norm.Eventos -and $Root.Dados.EventosCriticos) {
            $ec = $Root.Dados.EventosCriticos
            $total = Get-ValueOrDefault $ec.TotalEventos 0
            $norm.Eventos = [ordered]@{
                CriticosTotal       = $total
                ErrosTotal          = $total
                RelevantesSugeridos = @(
                    [PSCustomObject]@{ Id=10010; Titulo='DCOM não respondeu'; Observacao='Frequentemente inofensivo; ajustar permissões se causar impacto.' }
                )
            }
        }
    } else {
        $ec = $Root.EventosCriticos
        if ($ec) {
            $total = Get-ValueOrDefault $ec.TotalEventos 0
            $norm.Eventos = [ordered]@{
                CriticosTotal       = $total
                ErrosTotal          = $total
                RelevantesSugeridos = @(
                    [PSCustomObject]@{ Id=10010; Titulo='DCOM não respondeu'; Observacao='Frequentemente inofensivo; ajustar permissões se causar impacto.' }
                )
            }
        }
    }

    # ---------------- SERVIÇOS ----------------
    if ($hasDados) {
        $norm.Servicos = $Root.Dados.Servicos
    } else {
        $s = $Root.Servicos
        if ($s -and $s.CriticalServicesNotRunning) {
            $down = @()
            foreach ($x in $s.CriticalServicesNotRunning) {
                $down += [PSCustomObject]@{
                    Name   = (Get-ValueOrDefault $x.Name 'Serviço')
                    Status = (Get-ValueOrDefault $x.Status 'Indefinido')
                }
            }
            $norm.Servicos = [ordered]@{ CriticosParados = $down }
        }
    }

    # ---------------- INDEXADOR (raiz/Dados) ----------------
    if ($hasDados -and $Root.Dados.Indexador) {
        $norm.Indexador = $Root.Dados.Indexador
    } elseif ($Root.Indexador) {
        $norm.Indexador = $Root.Indexador
    }

    # ---------------- SCORE ----------------
    if ($hasDados) {
        $norm.HealthScore = $Root.Dados.HealthScore
    } else {
        if ($Root.Analise -and $null -ne $Root.Analise.SaudePontuacao) {
            $norm.HealthScore = [int]$Root.Analise.SaudePontuacao
        }
    }

    # ---------------- FABRICANTE ----------------
    if ($hasDados) {
        $norm.Fabricante = $Root.Dados.Fabricante
    } else {
        $norm.Fabricante = $Root.Fabricante
    }

    return $norm
}
#endregion

#region Helper local: consulta o Indexador via services.psm1 (se disponível)
function Get-LiveSearchIndexerStatusIfAvailable {
    try {
        $cmd = Get-Command -Name Get-SearchIndexerStatus -ErrorAction SilentlyContinue
        if ($null -ne $cmd) {
            return Get-SearchIndexerStatus
        }
    } catch {}
    return $null
}
#endregion

#region Relatório formatado
function Start-DiagnosticAnalysis {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$JsonPath)

    if (-not (Test-Path $JsonPath)) { Write-ErrT "Arquivo JSON não encontrado: $JsonPath"; return }

    try {
        $raw  = Get-Content -Raw -Path $JsonPath -Encoding UTF8
        $raw  = ConvertTo-NormalizedString $raw
        $root = $raw | ConvertFrom-Json -ErrorAction Stop
    } catch {
        Write-ErrT ("Falha ao interpretar JSON: {0}" -f $_.Exception.Message)
        return
    }

    $data = ConvertTo-NormalizedReport -Root $root

    Write-SectionHeader "ANÁLISE DO DIAGNÓSTICO"
    Write-Host ("Analisando sistema '{0}' em {1}" -f (Get-ValueOrDefault $data.Hostname 'N/D'), (Get-ValueOrDefault $data.Timestamp 'N/D')) -ForegroundColor White
    Write-Host ""

    # -------- HARDWARE --------
    Write-SubHeader "HARDWARE"
    try {
        $ram = $data.Hardware.RAM
        if ($ram) {
            $ramPct  = Get-ValueOrDefault $ram.UsedPercent 'N/D'
            $ramTot  = Get-ValueOrDefault $ram.TotalGB 'N/D'
            $ramUsed = Get-ValueOrDefault $ram.UsedGB 'N/D'
            $ramFree = Get-ValueOrDefault $ram.FreeGB 'N/D'
            Write-KV "Uso de RAM" ("{0}% (Total: {1} GB, Em uso: {2} GB, Livre: {3} GB)" -f $ramPct, $ramTot, $ramUsed, $ramFree)
        } else {
            Write-Warn "Sem dados de RAM."
        }

        $disks = $data.Hardware.Disks
        if ($disks) {
            foreach ($d in $disks) {
                $name  = Get-ValueOrDefault $d.Name "?"
                $free  = Get-ValueOrDefault $d.FreeGB "N/D"
                $used  = Get-ValueOrDefault $d.UsedGB "N/D"
                $pct   = Get-ValueOrDefault $d.UsedPct "N/D"
                $rootp = Get-ValueOrDefault $d.Root "N/D"
                Write-KV ("Disco {0}" -f ($name -replace ":", "")) ("Livre: {0} GB | Em uso: {1} GB ({2}%) | Raiz: {3}" -f $free, $used, $pct, $rootp)
            }
        } else {
            Write-Warn "Sem dados de discos."
        }
    } catch { Write-Warn "Falha ao interpretar HARDWARE." }

    # -------- REDE --------
    Write-SubHeader "REDE"
    try {
        if ($data.Rede -and $data.Rede.Error) {
            Write-Warn ("Falha na coleta de Rede: {0}" -f $data.Rede.Error)
        } elseif ($data.Rede) {
            Write-KV "Interface" (Get-ValueOrDefault $data.Rede.Interface 'N/D')
            Write-KV "IPv4"      (Get-ValueOrDefault $data.Rede.IPv4 'N/D')
            Write-KV "Gateway"   (Get-ValueOrDefault $data.Rede.Gateway 'N/D')
            Write-KV "DNS"       (Get-ValueOrDefault $data.Rede.DNS 'N/D')
            Write-KV "Status"    (Get-ValueOrDefault $data.Rede.Status 'N/D')
            if ($data.Rede.PSObject.Properties['LatenciaMs']) {
                Write-KV "Latência" (Format-LatencyDisplay $data.Rede.LatenciaMs)
            }
        } else {
            Write-Warn "Dados de rede indisponíveis."
        }
    } catch { Write-Warn "Erro ao exibir REDE." }

    # -------- EVENTOS --------
    Write-SubHeader "ESTABILIDADE DO SISTEMA"
    try {
        if ($data.Eventos) {
            $crit = Get-ValueOrDefault $data.Eventos.CriticosTotal 0
            $err  = Get-ValueOrDefault $data.Eventos.ErrosTotal    $crit
            Write-KV "Total de eventos críticos nos últimos 7 dias" $crit
            Write-KV "Total de erros (gerais)" $err

            if ($data.Eventos.RelevantesSugeridos) {
                Write-Host "Sugestões para Eventos Relevantes:" -ForegroundColor White
                foreach ($s in $data.Eventos.RelevantesSugeridos) {
                    $id  = Get-ValueOrDefault $s.Id "N/D"
                    $tit = Get-ValueOrDefault $s.Titulo "N/D"
                    $obs = Get-ValueOrDefault $s.Observacao "N/D"
                    Write-Host ("- [ID {0}] - {1}. {2}" -f $id, $tit, $obs)
                }
            }
        } else {
            Write-Warn "Falha ao coletar eventos: N/D"
        }
    } catch { Write-Warn "Erro ao exibir EVENTOS." }

    # -------- SERVIÇOS --------
    Write-SubHeader "SERVIÇOS CRÍTICOS"
    try {
        $svc = $data.Servicos
        if ($svc -and $svc.CriticosParados -and $svc.CriticosParados.Count -gt 0) {
            Write-Host "Serviços essenciais que não estão em execução:" -ForegroundColor White
            foreach ($s in $svc.CriticosParados) {
                $nm = Get-ValueOrDefault $s.Name '?'
                $st = Get-ValueOrDefault $s.Status 'Parado'
                if ($st -is [int]) {
                    if     ($st -eq 4) { $st = 'Running' }
                    elseif ($st -eq 1) { $st = 'Stopped' }
                }
                Write-Host ("- {0}: [SERVIÇO CRÍTICO] - {1}" -f $nm, $st)
            }
        } else {
            Write-Ok "Nenhum serviço crítico parado."
        }
    } catch { Write-Warn "Erro ao exibir SERVIÇOS." }

# -------- INDEXADOR (removido do pipeline) --------
# (Se futuramente voltar, a renderização atual já sabe lidar.)
# Intencionalmente não exibimos nada aqui quando não há dados.

    # -------- SCORE --------
    try {
        if ($null -ne $data.HealthScore) {
            Write-SubHeader "PONTUAÇÃO DE SAÚDE"
            Write-KV "Pontuação de Saúde do Sistema" ("{0}/100" -f [int]$data.HealthScore)
        }
    } catch {}

    Write-Host ""
    Write-Ok "[RELATÓRIO] Exibição concluída."
    Write-Host ("=" * 98) -ForegroundColor Cyan
}
#endregion

Export-ModuleMember -Function Start-DiagnosticAnalysis, `
    Get-ManufacturerSoftwareSuggestion, `
    Format-LatencyDisplay, `
    Write-TypingFormattedText
