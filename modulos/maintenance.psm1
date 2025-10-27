# maintenance.psm1
# Módulo de manutenção do Jarvis (com Reparo do Indexador de Pesquisa)

Set-StrictMode -Version Latest

# ---------------------------
# Infra de Log/UI
# ---------------------------
$OutputDir = Join-Path $PSScriptRoot "..\output"
if (-not (Test-Path $OutputDir)) { New-Item -Path $OutputDir -ItemType Directory | Out-Null }
$Global:JarvisLogPath = Join-Path $OutputDir "JarvisLog.txt"

function Write-LogEntry {
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
    param([string]$Text, [ConsoleColor]$Color = "White")
    try { Write-Host $Text -ForegroundColor $Color } catch { Write-Host $Text }
    Write-LogEntry -Level INFO -Message $Text
}

function Save-TerminalState {
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

# ---------------------------
# SFC / DISM / Rede / Limpezas / Memória (mantidos)
# ---------------------------
function Invoke-SFC {
    Write-Jarvis "Iniciando SFC..." Green
    try { sfc /scannow } catch { Write-Jarvis "Erro SFC: $($_.Exception.Message)" Red }
}

function Invoke-DISM {
    Write-Jarvis "Iniciando DISM /RestoreHealth..." Green
    try { Dism /Online /Cleanup-Image /RestoreHealth } catch { Write-Jarvis "Erro DISM: $($_.Exception.Message)" Red }
}

function Invoke-NetworkCorrections {
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

function Get-PathStats { param([string]$Path)
    if (-not (Test-Path $Path)) { return @{ Count=0; SizeBytes=0 } }
    try {
        $items = Get-ChildItem -Path $Path -Recurse -Force -File -ErrorAction SilentlyContinue
        $count = ($items | Measure-Object).Count
        $size  = if ($count -gt 0) { ($items | Measure-Object -Property Length -Sum).Sum } else { 0 }
        return @{ Count=$count; SizeBytes=$size }
    } catch { return @{ Count=0; SizeBytes=0 } }
}
function Remove-PathAndReport { param([string]$Path)
    $before = Get-PathStats -Path $Path
    try {
        if ($before.Count -gt 0) {
            Get-ChildItem -Path $Path -Recurse -Force -ErrorAction SilentlyContinue |
                ForEach-Object { try { Remove-Item -LiteralPath $_.FullName -Force -Recurse -ErrorAction SilentlyContinue -Confirm:$false } catch {} }
        } else {
            Remove-Item -Path $Path -Recurse -Force -ErrorAction SilentlyContinue -Confirm:$false
        }
    } catch {}
    $after = Get-PathStats -Path $Path
    return @{ FreedBytes=[math]::Max(0,$before.SizeBytes-$after.SizeBytes); RemovedCount=[math]::Max(0,$before.Count-$after.Count) }
}

function Invoke-QuickClean {
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
                ForEach-Object { try { $_.CloseMainWindow() | Out-Null; Start-Sleep 2; $_.Kill() } catch {} }
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
        Write-Jarvis "❌ Falha na limpeza: $($_.Exception.Message)" Red
        Write-LogEntry -Level ERROR -Message "Falha Limpeza Completa: $($_.Exception.Message)"
        return @{ ItemsRemoved=0; FreedMB=0 }
    } finally {
        $ErrorActionPreference = $oldEA
        Restore-TerminalState -State $state
    }
}

# Otimização de Memória
if (-not ([System.Management.Automation.PSTypeName]'MemApi').Type) {
    $memApi = @"
using System;
using System.Runtime.InteropServices;
public static class MemApi {
    [DllImport("psapi.dll")]
    public static extern bool EmptyWorkingSet(IntPtr hProcess);
}
"@
    Add-Type -TypeDefinition $memApi -ErrorAction SilentlyContinue
}
$Global:ProtectedProcesses = @(
    'wininit','lsass','csrss','services','winlogon','smss','System','Idle','Registry',
    'Memory Compression','explorer','dwm','sihost','fontdrvhost','SearchIndexer','SearchUI','SearchApp','SearchHost'
)
function Invoke-OptimizeMemory {
    Write-Jarvis "`n[MANUTENÇÃO] Otimização de Memória..." Cyan
    try {
        $beforeMB = [math]::Round((Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory/1024,2)
        Write-Jarvis "Memória antes: $beforeMB MB" DarkGray
        $procs = Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.Name -and $Global:ProtectedProcesses -notcontains $_.ProcessName -and $_.Id -ne $PID }
        $trimmed = 0
        foreach ($p in $procs) { try { if (-not $p.HasExited -and [MemApi]::EmptyWorkingSet($p.Handle)) { $trimmed++ } } catch {} }
        [System.GC]::Collect(); [System.GC]::WaitForPendingFinalizers(); [System.GC]::Collect()
        Start-Sleep -Milliseconds 400
        $afterMB = [math]::Round((Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory/1024,2)
        Write-Jarvis "Memória depois: $afterMB MB" DarkGray
        Write-Jarvis "[RESULTADO] Liberado: $([math]::Round($afterMB-$beforeMB,2)) MB | Processos ajustados: $trimmed" Green
        return @{ FreedMB=[math]::Round($afterMB-$beforeMB,2); ProcessesTrimmed=$trimmed }
    } catch {
        Write-Jarvis "Erro na otimização: $($_.Exception.Message)" Red
        return @{ FreedMB=0; ProcessesTrimmed=0 }
    }
}

# ---------------------------
# Reparo do Indexador (NOVO)
# ---------------------------
function Invoke-RepairSearchIndexer {
    <#
      - Habilita SearchEngine-Client-Package (Enable-WindowsOptionalFeature -> DISM fallback).
      - Define WSearch como Automático, zera dependências (sc.exe config depend= ""), reinicia.
      - (Opcional) Reconstrói catálogo.
    #>
    param([switch]$RebuildCatalogOnYesPrompt)

    Write-Jarvis "[PESQUISA] Reparo do Windows Search..." Cyan
    $notes = New-Object System.Collections.Generic.List[string]
    $success = $true

    # 1) Habilitar recurso
    try {
        Write-Jarvis "Habilitando recurso (Enable-WindowsOptionalFeature)..." DarkGray
        Enable-WindowsOptionalFeature -Online -FeatureName "SearchEngine-Client-Package" -All -NoRestart -ErrorAction Stop | Out-Null
        $notes.Add("Enable-WindowsOptionalFeature OK")
    } catch {
        $notes.Add("Enable-WindowsOptionalFeature falhou: $($_.Exception.Message)")
        Write-Jarvis "Fallback para DISM..." Yellow
        try {
            & dism.exe /online /enable-feature /featurename:SearchEngine-Client-Package /all
            if ($LASTEXITCODE -eq 0) { $notes.Add("DISM enable-feature OK") }
            else { $success=$false; $notes.Add("DISM exit $LASTEXITCODE") }
        } catch {
            $success=$false; $notes.Add("DISM exception: $($_.Exception.Message)")
        }
    }

    # 2) Serviço WSearch
    try {
        Write-Jarvis "Ajustando WSearch (Automatic)..." DarkGray
        Set-Service -Name WSearch -StartupType Automatic -ErrorAction SilentlyContinue
        Write-Jarvis "Limpando dependências do WSearch..." DarkGray
        & sc.exe config WSearch depend= "" | Out-Null
        Write-Jarvis "Iniciando/ Reiniciando WSearch..." DarkGray
        try { Restart-Service -Name WSearch -Force -ErrorAction Stop } catch { Start-Service -Name WSearch -ErrorAction SilentlyContinue }
        Start-Sleep -Seconds 2
        $svc = Get-Service -Name WSearch -ErrorAction SilentlyContinue
        if ($svc -and $svc.Status -eq 'Running') { Write-Jarvis "WSearch em execução." Green }
        else { $notes.Add("WSearch status: $($svc.Status)"); Write-Jarvis "WSearch não está 'Running' (Status: $($svc.Status))." Yellow }
    } catch {
        $success = $false; $notes.Add("Serviço WSearch erro: $($_.Exception.Message)")
        Write-Jarvis "Erro ao ajustar WSearch: $($_.Exception.Message)" Red
    }

    # 3) Reconstrução de catálogo (opcional)
    if ($RebuildCatalogOnYesPrompt) {
        $doRebuild = Read-Host "Deseja reconstruir o catálogo de indexação (pode demorar)? (S/N)"
        if ($doRebuild -in @('S','s')) {
            try {
                Write-Jarvis "Parando WSearch..." DarkGray
                Stop-Service -Name WSearch -Force -ErrorAction SilentlyContinue
                Start-Sleep -Seconds 2
                $catPath = "C:\ProgramData\Microsoft\Search\Data\Applications\Windows"
                if (Test-Path -LiteralPath $catPath) {
                    Write-Jarvis "Limpando catálogo: $catPath" DarkGray
                    Get-ChildItem -LiteralPath $catPath -Recurse -Force -ErrorAction SilentlyContinue |
                        Remove-Item -Force -Recurse -ErrorAction SilentlyContinue
                }
                Write-Jarvis "Iniciando WSearch..." DarkGray
                Start-Service -Name WSearch -ErrorAction SilentlyContinue
                Start-Sleep -Seconds 2
                $svc2 = Get-Service -Name WSearch -ErrorAction SilentlyContinue
                if ($svc2 -and $svc2.Status -eq 'Running') { Write-Jarvis "Reconstrução iniciada." Green }
                else { $notes.Add("Após rebuild, WSearch: $($svc2.Status)"); Write-Jarvis "WSearch não iniciou após rebuild (Status: $($svc2.Status))." Yellow }
            } catch {
                $success=$false; $notes.Add("Rebuild erro: $($_.Exception.Message)")
                Write-Jarvis "Erro durante reconstrução: $($_.Exception.Message)" Red
            }
        } else {
            Write-Jarvis "Reconstrução ignorada." DarkGray
        }
    }

    if ($success) { Write-LogEntry -Level INFO -Message "[PESQUISA] Reparo finalizado com sucesso." }
    else { Write-LogEntry -Level WARN -Message "[PESQUISA] Reparo finalizado com avisos/erros: $($notes -join ' | ')" }

    [pscustomobject]@{
        Success = $success
        Notes   = $notes
        Service = (Get-Service -Name WSearch -ErrorAction SilentlyContinue | Select-Object -Property Name, Status, StartType)
    }
}

Export-ModuleMember -Function `
    Invoke-SFC, Invoke-DISM, Invoke-NetworkCorrections, `
    Invoke-QuickClean, Invoke-FullClean, Invoke-OptimizeMemory, `
    Invoke-RepairSearchIndexer
