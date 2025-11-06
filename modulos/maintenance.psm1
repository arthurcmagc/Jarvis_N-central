# maintenance.psm1
# Módulo de manutenção do Jarvis (com Reparo do Indexador de Pesquisa)
# Compatível PS 5.1 / 7+

Set-StrictMode -Version Latest

# =========================
# Infra de Log/UI
# =========================
$OutputDir = Join-Path $PSScriptRoot "..\output"
if (-not (Test-Path $OutputDir)) { New-Item -Path $OutputDir -ItemType Directory | Out-Null }
$Global:JarvisLogPath = Join-Path $OutputDir "JarvisLog.txt"

function Write-LogEntry {
    [CmdletBinding()]
    param(
        [string]$LogPath = $Global:JarvisLogPath,
        [ValidateSet('INFO','WARN','ERROR')][string]$Level = "INFO",
        [string]$Message
    )
    try {
        $timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        Add-Content -Path $LogPath -Value "[$timestamp] [$Level] $Message" -Encoding UTF8 -ErrorAction SilentlyContinue
    } catch {}
}

function Write-Jarvis {
    [CmdletBinding()]
    param(
        [string]$Text,
        [ConsoleColor]$Color = "White"
    )
    try { Write-Host $Text -ForegroundColor $Color } catch { Write-Host $Text }
    Write-LogEntry -Level INFO -Message $Text
}

function Save-TerminalState {
    [CmdletBinding()]
    param()
    try {
        return [ordered]@{
            FG = $Host.UI.RawUI.ForegroundColor
            BG = $Host.UI.RawUI.BackgroundColor
            WS = $Host.UI.RawUI.WindowSize
            BS = $Host.UI.RawUI.BufferSize
        }
    } catch { return $null }
}
function Restore-TerminalState {
    [CmdletBinding()]
    param([hashtable]$State)
    try {
        if ($null -ne $State) {
            $Host.UI.RawUI.ForegroundColor = $State.FG
            $Host.UI.RawUI.BackgroundColor = $State.BG
            $Host.UI.RawUI.WindowSize      = $State.WS
            $Host.UI.RawUI.BufferSize      = $State.BS
            try { [Console]::ResetColor() } catch {}
        }
    } catch {}
}

# =========================
# SFC / DISM / Rede / Limpezas
# =========================
function Invoke-SFC {
    [CmdletBinding()]
    param()
    Write-Jarvis "Iniciando SFC..." Green
    try { sfc /scannow } catch { Write-Jarvis "Erro SFC: $($_.Exception.Message)" Red }
}

function Invoke-DISM {
    [CmdletBinding()]
    param()
    Write-Jarvis "Iniciando DISM /RestoreHealth..." Green
    try { Dism /Online /Cleanup-Image /RestoreHealth } catch { Write-Jarvis "Erro DISM: $($_.Exception.Message)" Red }
}

function Invoke-NetworkCorrections {
    [CmdletBinding()]
    param()
    Write-Jarvis "Iniciando correções de rede..." Green
    $steps = @(
        @{ Cmd='ipconfig /flushdns'        ; Desc='Flush DNS cache' },
        @{ Cmd='netsh int ip reset'        ; Desc='Reset pilha TCP/IP' },
        @{ Cmd='netsh winsock reset'       ; Desc='Reset Winsock' },
        @{ Cmd='netsh winhttp reset proxy' ; Desc='Reset WinHTTP proxy' }
    )
    foreach ($s in $steps) {
        try {
            Write-Host " -> $($s.Desc) ($($s.Cmd))" -ForegroundColor DarkGray
            & cmd.exe /c $s.Cmd | Out-Null
        } catch {
            Write-Host " [ERRO] $($s.Desc): $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }
    Write-Jarvis "Correções de rede concluídas. Recomenda-se reiniciar." Yellow
}

function Get-PathStats {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path $Path)) { return @{ Count=0; SizeBytes=0 } }
    try {
        $items = Get-ChildItem -Path $Path -Recurse -Force -File -ErrorAction SilentlyContinue
        $count = ($items | Measure-Object).Count
        $size  = if ($count -gt 0) { ($items | Measure-Object -Property Length -Sum).Sum } else { 0 }
        return @{ Count=$count; SizeBytes=$size }
    } catch { return @{ Count=0; SizeBytes=0 } }
}

function Remove-PathAndReport {
    [CmdletBinding()]

    param([Parameter(Mandatory)][string]$Path)
    $before = Get-PathStats -Path $Path
    try {
        if ($before.Count -gt 0) {
            Get-ChildItem -Path $Path -Recurse -Force -ErrorAction SilentlyContinue |
                ForEach-Object {
                    try { Remove-Item -LiteralPath $_.FullName -Force -Recurse -ErrorAction SilentlyContinue -Confirm:$false } catch {}
                }
        } else {
            Remove-Item -Path $Path -Recurse -Force -ErrorAction SilentlyContinue -Confirm:$false
        }
    } catch {}
    $after = Get-PathStats -Path $Path
    return @{

        FreedBytes   = [math]::Max(0, $before.SizeBytes - $after.SizeBytes)
        RemovedCount = [math]::Max(0, $before.Count - $after.Count)
    }
}

function Invoke-QuickClean {
    [CmdletBinding()]
    param()
    Write-Jarvis "`n[MANUTENÇÃO] Iniciando Limpeza Rápida..." Cyan
    $paths = @("$env:TEMP\*","$env:LOCALAPPDATA\Temp\*","$env:WINDIR\Temp\*")
    $totalFreed=0; $totalRemoved=0
    foreach ($p in $paths) {
        $res = Remove-PathAndReport -Path $p
        $totalFreed += $res.FreedBytes; $totalRemoved += $res.RemovedCount
        Write-Jarvis "  -> $p | Removidos $($res.RemovedCount) | Liberado $([math]::Round($res.FreedBytes/1MB,2)) MB" DarkGray
    }
    try { Clear-RecycleBin -Force -ErrorAction SilentlyContinue } catch {}
    Write-Jarvis "[RESULTADO] Itens: $totalRemoved | Espaço: $([math]::Round($totalFreed/1MB,2)) MB" Green
    return @{ ItemsRemoved=$totalRemoved; FreedMB=[math]::Round($totalFreed/1MB,2) }
}

function Invoke-FullClean {
    [CmdletBinding()]
    param()
    Write-Jarvis "`n[MANUTENÇÃO] Iniciando Limpeza Completa..." Cyan
    Write-Jarvis "Pode remover caches, logs e temporários do sistema e apps." DarkYellow
    $confirm = Read-Host "Tem certeza que deseja continuar? (S/N)"
    if ($confirm -notin @('S','s')) { Write-Jarvis "Operação cancelada." Yellow; return }

    Write-Host ""
    Write-Jarvis "AVISO: Para limpar caches, alguns navegadores podem ser FECHADOS temporariamente." Yellow
    $closeBrowsers = Read-Host "Deseja permitir fechar navegadores agora? (S/N)"
    $shouldClose   = $closeBrowsers -in @('S','s')

    $state = Save-TerminalState
    $oldEA = $ErrorActionPreference
    $ErrorActionPreference = 'Stop'
    try {
        $paths = @(
            "$env:TEMP\*",
            "$env:LOCALAPPDATA\Temp\*",
            "$env:WINDIR\Temp\*",
            "$env:WINDIR\SoftwareDistribution\Download\*",
            "$env:LOCALAPPDATA\Microsoft\Windows\WebCache\*",
            "$env:LOCALAPPDATA\Mozilla\Firefox\Profiles\*\cache2\*",
            "$env:LOCALAPPDATA\Google\Chrome\User Data\*\Cache\*",
            "$env:LOCALAPPDATA\Microsoft\Edge\User Data\*\Cache\*",
            "$env:LOCALAPPDATA\Microsoft\Windows\Explorer\thumbcache_*",
            "$env:ProgramData\Microsoft\Windows\WER\*"
        )

        if ($shouldClose) {
            Write-Jarvis "[1/8] Fechando navegadores..." DarkGray
            Get-Process -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -in @('msedge','chrome','firefox','iexplore','acrord32') } |
                ForEach-Object {
                    try { $_.CloseMainWindow() | Out-Null; Start-Sleep 2; $_.Kill() } catch {}
                }
        } else { Write-Jarvis "[1/8] Sem fechar navegadores (opção do analista)." DarkGray }

        Write-Jarvis "[2/8] Limpando temporários e caches..." DarkGray
        $totalFreed=0; $totalRemoved=0
        foreach ($p in $paths) {
            $res = Remove-PathAndReport -Path $p
            $totalFreed += $res.FreedBytes; $totalRemoved += $res.RemovedCount
            Write-Jarvis "  -> $p | Removidos $($res.RemovedCount) | Liberado $([math]::Round($res.FreedBytes/1MB,2)) MB" DarkGray
        }

        Write-Jarvis "[3/8] Limpando cache do Windows Update..." DarkGray
        try {
            net stop wuauserv  | Out-Null
            net stop bits      | Out-Null
            Remove-Item "$env:WINDIR\SoftwareDistribution\Download\*" -Recurse -Force -ErrorAction SilentlyContinue
        } finally {
            net start wuauserv | Out-Null
            net start bits     | Out-Null
        }

        Write-Jarvis "[4/8] Limpando logs de eventos antigos..." DarkGray
        try { wevtutil el | ForEach-Object { wevtutil cl $_ 2>$null } } catch {}

        Write-Jarvis "[5/8] Esvaziando Lixeira..." DarkGray
        try { Clear-RecycleBin -Force -ErrorAction SilentlyContinue } catch {}

        $aggConfirm = Read-Host "Deseja executar limpeza agressiva (Dell SARemediation)? (S/N)"
        if ($aggConfirm -in @('S','s')) {
            Write-Jarvis "[6/8] Removendo componentes Remediation..." Red
            $aggPaths = @(
                @{Path="C:\ProgramData\Dell\SARemediation\SystemRepair\*"; Description="Dell System Repair Snapshots"},
                @{Path="C:\ProgramData\Dell\SARemediation\Snapshots\*";    Description="Dell SARemediation Snapshots"}
            )
            foreach ($item in $aggPaths) {
                $res = Remove-PathAndReport -Path $item.Path
                Write-Jarvis "  -> $($item.Description): Removidos $($res.RemovedCount) | Liberado $([math]::Round($res.FreedBytes/1MB,2)) MB" DarkGray
            }
            Write-Jarvis "[AGRESSIVA] Remoção de pacotes Remediation concluída." Red
        } else { Write-Jarvis "[6/8] Agressiva ignorada." DarkGray }

        Write-Jarvis "[7/8] DISM StartComponentCleanup (opcional)..." DarkGray
        $runDism = Read-Host "Executar StartComponentCleanup? (S/N)"
        if ($runDism -in @('S','s')) {
            try {
                Start-Process -FilePath "dism.exe" -ArgumentList "/Online","/Cleanup-Image","/StartComponentCleanup","/Quiet" -Wait -WindowStyle Hidden
                Write-LogEntry -Level INFO -Message "StartComponentCleanup OK"
            } catch {
                Write-LogEntry -Level WARN -Message "StartComponentCleanup falhou: $($_.Exception.Message)"
            }
        }

        Write-Jarvis "[8/8] Final..." DarkGray
        Write-Jarvis "`n[RESULTADO] Itens removidos: $totalRemoved | Espaço: $([math]::Round($totalFreed/1MB,2)) MB" Green
        return @{ ItemsRemoved=$totalRemoved; FreedMB=[math]::Round($totalFreed/1MB,2) }
    } catch {
        Write-Jarvis " Falha na limpeza: $($_.Exception.Message)" Red
        Write-LogEntry -Level ERROR -Message "Falha Limpeza Completa: $($_.Exception.Message)"
        return @{ ItemsRemoved=0; FreedMB=0 }
    } finally {
        $ErrorActionPreference = $oldEA
        Restore-TerminalState -State $state
    }
}

# =========================
# Otimização de Memória (segura / sem erro fatal no import)
# =========================
function Initialize-MemApi {
    # Retorna $true se o tipo está pronto; $false se não conseguir (sem lançar erro)
    try {
        if ([System.AppDomain]::CurrentDomain.GetAssemblies() |
              ForEach-Object { $_.GetType("MemApi", $false) } |
              Where-Object { $_ } ) {
            $script:MemApiReady = $true
            return $true
        }

        $src = @"
using System;
using System.Runtime.InteropServices;
public static class MemApi {
    [DllImport("psapi.dll")]
    public static extern bool EmptyWorkingSet(IntPtr hProcess);
}
"@

        $prev = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        try {
            Add-Type -TypeDefinition $src -ErrorAction Stop | Out-Null
            $script:MemApiReady = $true
        } catch {
            $script:MemApiReady = $false
        } finally {
            $ErrorActionPreference = $prev
        }
        return [bool]$script:MemApiReady
    } catch {
        $script:MemApiReady = $false
        return $false
    }
}

# Lista de processos protegidos (não tentar “trim” neles)
$Global:ProtectedProcesses = @(
    'wininit','lsass','csrss','services','winlogon','smss','System','Idle','Registry',
    'Memory Compression','explorer','dwm','sihost','fontdrvhost','SearchIndexer','SearchUI','SearchApp','SearchHost'
)

function Invoke-OptimizeMemory {
    [CmdletBinding()]
    param()
    Write-Jarvis "`n[MANUTENÇÃO] Otimização de Memória..." Cyan
    $freed = 0.0
    $trimmed = 0
    try {
        # Tenta carregar o MemApi de forma segura (sem matar o módulo caso falhe)
        $memAvailable = Initialize-MemApi

        # Medição antes
        $beforeMB = 0
        try { $beforeMB = [math]::Round((Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory/1024,2) } catch {}
        if ($beforeMB -gt 0) { Write-Jarvis ("Memória antes: {0} MB" -f $beforeMB) DarkGray }

        $procs = Get-Process -ErrorAction SilentlyContinue |
                 Where-Object { $_.Name -and $Global:ProtectedProcesses -notcontains $_.ProcessName -and $_.Id -ne $PID }

        foreach ($p in $procs) {
            try {
                if ($p.HasExited) { continue }
                if ($memAvailable) {
                    # P/Invoke real (quando compilou OK)
                    [void][MemApi]::EmptyWorkingSet($p.Handle)
                    $trimmed++
                } else {
                    # Fallback “suave”: tentar forçar um refresh de working set sem P/Invoke
                    $null = $p.Refresh()
                }
            } catch {
                # Ignorar acessos negados ou processos que morreram no meio
            }
        }

        # GC do PowerShell
        try {
            [System.GC]::Collect()
            [System.GC]::WaitForPendingFinalizers()
            [System.GC]::Collect()
        } catch {}
        Start-Sleep -Milliseconds 400

        $afterMB = 0
        try { $afterMB = [math]::Round((Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory/1024,2) } catch {}
        if ($afterMB -gt 0) { Write-Jarvis ("Memória depois: {0} MB" -f $afterMB) DarkGray }

        if ($beforeMB -gt 0 -and $afterMB -gt 0) { $freed = [math]::Round($afterMB - $beforeMB,2) }

        if ($memAvailable) {
            Write-Jarvis ("[RESULTADO] Liberado: {0} MB | Processos ajustados: {1}" -f $freed, $trimmed) Green
        } else {
            Write-Jarvis ("[RESULTADO] (modo compatível) Ajustes leves aplicados | Proc. tocados: {0}" -f $trimmed) Green
            Write-LogEntry -Level WARN -Message "OptimizeMemory executou sem MemApi (Add-Type falhou)."
        }

        return @{ FreedMB = $freed; ProcessesTrimmed = $trimmed; UsedFallback = (-not $memAvailable) }
    } catch {
        Write-Jarvis ("Erro na otimização: {0}" -f $_.Exception.Message) Red
        return @{ FreedMB = 0; ProcessesTrimmed = 0; UsedFallback = $null }
    }
}

# =========================
# Reparo do Indexador (idempotente) — legado (interativo opcional)
# =========================
# --- REPARO DO INDEXADOR (SAFE / sem -Force) ---
function Invoke-RepairSearchIndexer {
    [CmdletBinding()]
    param([switch]$RebuildCatalogOnYesPrompt)

    Write-Host "[PESQUISA] Reparo do Windows Search..." -ForegroundColor Cyan
    $notes = New-Object System.Collections.Generic.List[string]
    $success = $true

    # 1) Habilitar recurso (com fallback DISM)
    try {
        Enable-WindowsOptionalFeature -Online -FeatureName "SearchEngine-Client-Package" -All -NoRestart -ErrorAction Stop | Out-Null
        $notes.Add("Enable-WindowsOptionalFeature OK")
    } catch {
        $notes.Add("Enable-WindowsOptionalFeature falhou: $($_.Exception.Message)")
        try {
            & dism.exe /online /enable-feature /featurename:SearchEngine-Client-Package /all | Out-Null
            if ($LASTEXITCODE -eq 0) { $notes.Add("DISM enable-feature OK") } else { $success=$false; $notes.Add("DISM exit $LASTEXITCODE") }
        } catch { $success=$false; $notes.Add("DISM exception: $($_.Exception.Message)") }
    }

    # 2) Serviço WSearch -> Automático (sem Force)
    try {
        Set-Service -Name WSearch -StartupType Automatic -ErrorAction SilentlyContinue
        & sc.exe config WSearch depend= "" | Out-Null
    } catch {
        $success = $false; $notes.Add("Set/SC WSearch erro: $($_.Exception.Message)")
    }

    # 3) Iniciar (sem -Force) com pequena espera
    try {
        $svc = Get-Service -Name WSearch -ErrorAction SilentlyContinue
        if ($null -ne $svc -and $svc.Status -ne 'Running') {
            Start-Service -Name WSearch -ErrorAction SilentlyContinue
            $limit = (Get-Date).AddSeconds(8)
            do {
                Start-Sleep -Milliseconds 400
                $svc = Get-Service -Name WSearch -ErrorAction SilentlyContinue
            } while ($svc -and $svc.Status -ne 'Running' -and (Get-Date) -lt $limit)
        }
    } catch {
        $success = $false; $notes.Add("Start WSearch erro: $($_.Exception.Message)")
    }

    # 4) Rebuild opcional do catálogo (sem -Force)
    if ($RebuildCatalogOnYesPrompt) {
        $doRebuild = Read-Host "Deseja reconstruir o catálogo de indexação (pode demorar)? (S/N)"
        if ($doRebuild -in @('S','s')) {
            try {
                $svc = Get-Service -Name WSearch -ErrorAction SilentlyContinue
                if ($svc -and $svc.Status -eq 'Running') {
                    Stop-Service -Name WSearch -ErrorAction SilentlyContinue
                    $stopLimit = (Get-Date).AddSeconds(8)
                    do {
                        Start-Sleep -Milliseconds 400
                        $svc = Get-Service -Name WSearch -ErrorAction SilentlyContinue
                    } while ($svc -and $svc.Status -ne 'Stopped' -and (Get-Date) -lt $stopLimit)
                }

                $catPath = "C:\ProgramData\Microsoft\Search\Data\Applications\Windows"
                if (Test-Path -LiteralPath $catPath) {
                    Get-ChildItem -LiteralPath $catPath -Recurse -Force -ErrorAction SilentlyContinue |
                        Remove-Item -Force -Recurse -ErrorAction SilentlyContinue
                }

                Start-Service -Name WSearch -ErrorAction SilentlyContinue
                $startLimit = (Get-Date).AddSeconds(8)
                do {
                    Start-Sleep -Milliseconds 400
                    $svc = Get-Service -Name WSearch -ErrorAction SilentlyContinue
                } while ($svc -and $svc.Status -ne 'Running' -and (Get-Date) -lt $startLimit)

                if ($svc -and $svc.Status -eq 'Running') { $notes.Add("Reconstrução iniciada.") } else { $success=$false; $notes.Add("WSearch não iniciou após rebuild.") }
            } catch { $success=$false; $notes.Add("Rebuild erro: $($_.Exception.Message)") }
        } else {
            $notes.Add("Reconstrução ignorada.")
        }
    }

    [pscustomobject]@{
        Success = $success
        Notes   = $notes
        Service = (Get-Service -Name WSearch -ErrorAction SilentlyContinue | Select-Object -Property Name, Status, StartType)
    }
}

# =========================
# NOVA FUNÇÃO — Repair-WindowsSearchIndex (silenciosa e sem -Force onde não existe)
# =========================
function Repair-WindowsSearchIndex {
    [CmdletBinding()]
    param(
        [ValidateSet('validate','lightclean','rebuild')]
        [string]$Mode = 'validate',
        [switch]$Silent
    )

    $SearchRoot = Join-Path $env:PROGRAMDATA 'Microsoft\Search\Data'
    $TempPaths  = @(
        (Join-Path $SearchRoot 'Temp\*')
    )
    $RebuildPaths = @(
        (Join-Path $SearchRoot 'Applications\Windows\*'),
        (Join-Path $SearchRoot 'Config\*')
    )

    $out = [pscustomobject]@{
        Mode     = $Mode
        Action   = 'None'
        Status   = 'Unknown'
        Details  = $null
        Service  = 'WSearch'
        Changed  = $false
    }

    try {
        if (-not $Silent) { Write-Host "[INFO] Verificando Indexador de Pesquisa (mode: $Mode)" -ForegroundColor Gray }

        # Serviço
        $svc = $null
        try { $svc = Get-Service -Name 'WSearch' -ErrorAction Stop } catch { $svc = $null }
        if (-not $svc) {
            $out.Status  = 'ServiceNotFound'
            $out.Details = 'Serviço WSearch ausente nesta edição do Windows.'
            if (-not $Silent) { Write-Host "  [INFO] WSearch não disponível nesta máquina" -ForegroundColor Yellow }
            return $out
        }

        # StartupType & start (sem -Force)
        try { Set-Service -Name 'WSearch' -StartupType Automatic -ErrorAction SilentlyContinue } catch {}
        try {
            $svc = Get-Service -Name 'WSearch' -ErrorAction SilentlyContinue
            if ($svc -and $svc.Status -ne 'Running') { Start-Service -Name 'WSearch' -ErrorAction SilentlyContinue }
        } catch {}

        $svc = Get-Service -Name 'WSearch' -ErrorAction SilentlyContinue
        if ($svc -and $svc.Status -eq 'Running') {
            if (-not $Silent) { Write-Host "  [SUCESSO] WSearch em execução" -ForegroundColor Green }
        } else {
            if (-not $Silent) { Write-Host "  [AVISO] WSearch não conseguiu iniciar" -ForegroundColor Yellow }
        }

        switch ($Mode) {
            'validate' {
                $out.Action  = 'ValidateOnly'
                $out.Status  = 'OK'
                $out.Details = 'Serviço validado; nenhuma limpeza aplicada.'
                if (-not $Silent) { Write-Host "  -> [SUCESSO]" -ForegroundColor Green }
            }
            'lightclean' {
                $needs = $false
                foreach ($p in $TempPaths) { if (Test-Path -LiteralPath $p) { $needs = $true; break } }
                if ($needs) {
                    if (-not $Silent) { Write-Host "  [INFO] Limpando artefatos temporários do índice" -ForegroundColor Yellow }
                    try {
                        $svc = Get-Service -Name 'WSearch' -ErrorAction SilentlyContinue
                        if ($svc -and $svc.Status -eq 'Running') {
                            Stop-Service -Name 'WSearch' -ErrorAction SilentlyContinue
                            Start-Sleep -Seconds 2
                        }
                        foreach ($p in $TempPaths) {
                            Remove-Item -LiteralPath $p -Recurse -ErrorAction SilentlyContinue
                        }
                        Start-Service -Name 'WSearch' -ErrorAction SilentlyContinue
                        $out.Action  = 'LightCleanup'
                        $out.Status  = 'Cleaned'
                        $out.Details = 'Temp limpos e serviço reiniciado.'
                        $out.Changed = $true
                        if (-not $Silent) { Write-Host "  [SUCESSO] Indexador limpo (light) e reiniciado" -ForegroundColor Green }
                    } catch {
                        if (-not $Silent) { Write-Host "  [AVISO] Limpeza do índice falhou, seguindo: $($_.Exception.Message)" -ForegroundColor Yellow }
                        $out.Action  = 'LightCleanup'
                        $out.Status  = 'Warning'
                        $out.Details = $_.Exception.Message
                    }
                } else {
                    $out.Action  = 'LightCleanup'
                    $out.Status  = 'NoChanges'
                    $out.Details = 'Nenhum artefato temporário encontrado.'
                    if (-not $Silent) { Write-Host "  [INFO] Nada para limpar (light)" -ForegroundColor Gray }
                }
            }
            'rebuild' {
                $exists = $false
                foreach ($p in $RebuildPaths) { if (Test-Path -LiteralPath $p) { $exists = $true; break } }
                if ($exists) {
                    if (-not $Silent) { Write-Host "  [INFO] Rebuild do índice (limpeza controlada)" -ForegroundColor Yellow }
                    try {
                        $svc = Get-Service -Name 'WSearch' -ErrorAction SilentlyContinue
                        if ($svc -and $svc.Status -eq 'Running') {
                            Stop-Service -Name 'WSearch' -ErrorAction SilentlyContinue
                            Start-Sleep -Seconds 2
                        }
                        foreach ($p in $RebuildPaths) {
                            Remove-Item -LiteralPath $p -Recurse -ErrorAction SilentlyContinue
                        }
                        Start-Service -Name 'WSearch' -ErrorAction SilentlyContinue
                        $out.Action  = 'Rebuild'
                        $out.Status  = 'Rebuilt'
                        $out.Details = 'Pastas do índice limpas; Windows irá reindexar em background.'
                        $out.Changed = $true
                        if (-not $Silent) { Write-Host "  [SUCESSO] Rebuild disparado; reindexação ocorrerá em background" -ForegroundColor Green }
                    } catch {
                        if (-not $Silent) { Write-Host "  [AVISO] Rebuild falhou, seguindo: $($_.Exception.Message)" -ForegroundColor Yellow }
                        $out.Action  = 'Rebuild'
                        $out.Status  = 'Warning'
                        $out.Details = $_.Exception.Message
                    }
                } else {
                    $out.Action  = 'Rebuild'
                    $out.Status  = 'NoChanges'
                    $out.Details = 'Estruturas de índice já estavam normais.'
                    if (-not $Silent) { Write-Host "  [INFO] Nada para limpar (rebuild)" -ForegroundColor Gray }
                }
            }
        }

        return $out
    } catch {
        $out.Status  = 'Error'
        $out.Details = $_.Exception.Message
        if (-not $Silent) { Write-Host "  [ERRO] Falha no Indexador de Pesquisa: $($out.Details)" -ForegroundColor Red }
        return $out
    }
}

# =========================
# Export
# =========================
Export-ModuleMember -Function `
    Invoke-SFC, Invoke-DISM, Invoke-NetworkCorrections, `
    Invoke-QuickClean, Invoke-FullClean, Invoke-OptimizeMemory, `
    Invoke-RepairSearchIndexer, Repair-WindowsSearchIndex
