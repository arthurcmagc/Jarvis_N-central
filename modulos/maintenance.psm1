# maintenance.psm1
# Módulo de manutenção e correção do sistema — versão refinada e estável
# ======================================================================

# ---------------------------
# Variáveis / Paths / Log
# ---------------------------
$OutputDir = Join-Path $PSScriptRoot "..\output"
if (-not (Test-Path $OutputDir)) { New-Item -Path $OutputDir -ItemType Directory | Out-Null }
$Global:JarvisLogPath = Join-Path $OutputDir "JarvisLog.txt"

# ---------------------------
# Helpers de Terminal
# ---------------------------
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

# ---------------------------
# Helpers de Log/UI
# ---------------------------
function Write-LogEntry {
    param(
        [string]$LogPath = $Global:JarvisLogPath,
        [ValidateSet('INFO','WARN','ERROR')][string]$Level = "INFO",
        [string]$Message
    )
    $timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    $entry = "[$timestamp] [$Level] $Message"
    try { Add-Content -Path $LogPath -Value $entry -ErrorAction SilentlyContinue } catch {}
}

function Write-Jarvis {
    param([string]$Text, [ConsoleColor]$Color = "White")
    Write-Host $Text -ForegroundColor $Color
    Write-LogEntry -Level INFO -Message $Text
}

# ===========================
# FUNÇÕES DE MANUTENÇÃO
# ===========================

# -----------------
# SFC
# -----------------
function Invoke-SFC {
    Write-Jarvis "Iniciando SFC (System File Checker)..." Green
    try {
        Write-LogEntry -Level INFO -Message "Executando: sfc /scannow"
        sfc /scannow
        Write-Jarvis "SFC concluído. Verifique o resultado acima." Yellow
    } catch {
        Write-Jarvis "Erro ao executar SFC: $($_.Exception.Message)" Red
        Write-LogEntry -Level ERROR -Message "SFC error: $($_.Exception.Message)"
    }
}

# -----------------
# DISM (RestoreHealth)
# -----------------
function Invoke-DISM {
    Write-Jarvis "Iniciando DISM (Deployment Image Servicing and Management)..." Green
    Write-Jarvis "Isso pode demorar alguns minutos. Aguarde." DarkGray
    try {
        Write-LogEntry -Level INFO -Message "Executando: Dism /Online /Cleanup-Image /RestoreHealth"
        Dism /Online /Cleanup-Image /RestoreHealth
        Write-Jarvis "DISM concluído. Verifique o resultado acima." Yellow
    } catch {
        Write-Jarvis "Erro ao executar DISM: $($_.Exception.Message)" Red
        Write-LogEntry -Level ERROR -Message "DISM error: $($_.Exception.Message)"
    }
}

# -----------------
# Correções de Rede (com mini-relatório)
# -----------------
function Invoke-NetworkCorrections {
    Write-Jarvis "Iniciando correções de rede..." Green

    $steps = @(
        @{ Cmd = 'ipconfig /flushdns'        ; Desc = 'Flush DNS cache' },
        @{ Cmd = 'netsh int ip reset'        ; Desc = 'Reset pilha TCP/IP' },
        @{ Cmd = 'netsh winsock reset'       ; Desc = 'Reset Winsock' },
        @{ Cmd = 'netsh winhttp reset proxy' ; Desc = 'Reset WinHTTP proxy' }
    )

    $report = @()
    foreach ($s in $steps) {
        try {
            Write-Host " -> $($s.Desc)  ($($s.Cmd))" -ForegroundColor DarkGray
            & cmd.exe /c $s.Cmd | Out-Null
            $report += "[OK] $($s.Desc)"
        } catch {
            $report += "[ERRO] $($s.Desc): $($_.Exception.Message)"
        }
    }

    Write-Host ""
    Write-Jarvis "Resumo das correções:" Cyan
    $report | ForEach-Object { Write-Host "   $_" -ForegroundColor Gray }

    Write-Host ""
    Write-Jarvis "Correções de rede concluídas. Recomenda-se reiniciar o computador." Yellow
}

# -----------------
# Helpers de limpeza
# -----------------
function Get-PathStats {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return @{ Count = 0; SizeBytes = 0 } }
    try {
        $items = Get-ChildItem -Path $Path -Recurse -Force -File -ErrorAction SilentlyContinue
        $count = ($items | Measure-Object).Count
        $size  = if ($count -gt 0) { ($items | Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum } else { 0 }
        return @{ Count = $count; SizeBytes = $size }
    } catch { return @{ Count = 0; SizeBytes = 0 } }
}

function Remove-PathAndReport {
    param([string]$Path)
    $before = Get-PathStats -Path $Path
    try {
        if ($before.Count -gt 0) {
            $items = Get-ChildItem -Path $Path -Recurse -Force -ErrorAction SilentlyContinue
            foreach ($i in $items) {
                try { Remove-Item -LiteralPath $i.FullName -Force -Recurse -ErrorAction SilentlyContinue -Confirm:$false } catch {}
            }
        } else {
            Remove-Item -Path $Path -Recurse -Force -ErrorAction SilentlyContinue -Confirm:$false
        }
    } catch {}
    $after = Get-PathStats -Path $Path
    $freedBytes   = [math]::Max(0, $before.SizeBytes - $after.SizeBytes)
    $removedCount = [math]::Max(0, $before.Count - $after.Count)
    return @{ FreedBytes = $freedBytes; RemovedCount = $removedCount }
}

# -----------------
# Limpeza Rápida
# -----------------
function Invoke-QuickClean {
    Write-Jarvis "`n[MANUTENÇÃO] Iniciando Limpeza Rápida..." Cyan
    $paths = @(
        "$env:TEMP\*",
        "$env:LOCALAPPDATA\Temp\*",
        "$env:WINDIR\Temp\*"
    )
    $totalFreed = 0; $totalRemoved = 0

    foreach ($p in $paths) {
        $res = Remove-PathAndReport -Path $p
        $totalFreed  += $res.FreedBytes
        $totalRemoved += $res.RemovedCount
        Write-Jarvis "  -> Path: $p | Removidos: $($res.RemovedCount) | Liberado: $([math]::Round($res.FreedBytes/1MB,2)) MB" DarkGray
    }

    try { Clear-RecycleBin -Force -ErrorAction SilentlyContinue } catch {}

    Write-Jarvis "`n[RESULTADO] Limpeza rápida concluída. Itens removidos: $totalRemoved | Espaço liberado: $([math]::Round($totalFreed/1MB,2)) MB" Green
    return @{ ItemsRemoved = $totalRemoved; FreedMB = [math]::Round($totalFreed/1MB,2) }
}

# -----------------
# Limpeza Completa (blindada + progresso DISM)
# -----------------
function Invoke-FullClean {
    Write-Jarvis "`n[MANUTENÇÃO] Iniciando Limpeza Completa..." Cyan
    Write-Jarvis "Pode remover caches, logs e temporários do sistema e aplicativos." DarkYellow
    $confirm = Read-Host "Tem certeza que deseja continuar? (S/N)"
    if ($confirm -notin @('S','s')) { Write-Jarvis "Operação cancelada." Yellow; return }

    # AVISO sobre fechamento de navegadores (não mexe em extensões)
    Write-Host ""
    Write-Jarvis "AVISO: Para limpar caches, alguns navegadores podem ser FECHADOS temporariamente." Yellow
    $closeBrowsers = Read-Host "Deseja permitir fechar navegadores agora? (S/N)"
    $shouldClose   = $closeBrowsers -in @('S','s')

    # Proteções de terminal/erros
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
            Write-Jarvis "[1/8] Fechando navegadores para liberar cache..." DarkGray
            Get-Process -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -in @('msedge','chrome','firefox','iexplore','acrord32') } |
                ForEach-Object { try { $_.CloseMainWindow() | Out-Null; Start-Sleep 2; $_.Kill() } catch {} }
        } else {
            Write-Jarvis "[1/8] Pulando fechamento de navegadores por opção do analista." DarkGray
        }

        Write-Jarvis "[2/8] Limpando temporários e caches..." DarkGray
        $totalFreed = 0; $totalRemoved = 0
        foreach ($p in $paths) {
            $res = Remove-PathAndReport -Path $p
            $totalFreed  += $res.FreedBytes
            $totalRemoved += $res.RemovedCount
            Write-Jarvis "  -> Path: $p | Removidos: $($res.RemovedCount) | Liberado: $([math]::Round($res.FreedBytes/1MB,2)) MB" DarkGray
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

        # Limpeza Agressiva opcional (Dell SARemediation, etc.)
        $aggConfirm = Read-Host "Deseja executar a limpeza agressiva (Dell SARemediation)? (S/N)"
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
        } else {
            Write-Jarvis "[6/8] Etapa agressiva ignorada por opção do analista." DarkGray
        }

        Write-Jarvis "[7/8] Consolidando resultados parciais..." DarkGray
        Write-LogEntry -Level INFO -Message ("Limpeza parcial: Removidos={0} | Liberado={1} MB" -f $totalRemoved, [math]::Round($totalFreed/1MB,2))

        Write-Jarvis "[8/8] (Opcional) DISM StartComponentCleanup..." DarkGray
        $runDism = Read-Host "Executar StartComponentCleanup? (S/N)"
        if ($runDism -in @('S','s')) {
            try {
                # Barra de progresso enquanto o DISM executa
                $psi = New-Object System.Diagnostics.ProcessStartInfo
                $psi.FileName  = "dism.exe"
                $psi.Arguments = "/Online /Cleanup-Image /StartComponentCleanup /Quiet"
                $psi.UseShellExecute = $false
                $psi.RedirectStandardOutput = $true
                $psi.RedirectStandardError  = $true

                $proc = New-Object System.Diagnostics.Process
                $proc.StartInfo = $psi
                [void]$proc.Start()

                $pct = 0
                while (-not $proc.HasExited) {
                    Write-Progress -Activity "DISM StartComponentCleanup" -Status "Otimizando componentes..." -PercentComplete $pct
                    Start-Sleep -Milliseconds 300
                    $pct = ($pct + 3) % 100
                }
                Write-Progress -Activity "DISM StartComponentCleanup" -Completed
                Write-LogEntry -Level INFO -Message "DISM StartComponentCleanup finalizado. ExitCode=$($proc.ExitCode)"
            } catch {
                Write-LogEntry -Level WARN -Message "Falha no DISM StartComponentCleanup: $($_.Exception.Message)"
                Write-Jarvis "Falha no DISM StartComponentCleanup: $($_.Exception.Message)" Yellow
            }
        } else {
            Write-Jarvis "DISM StartComponentCleanup não executado (opção do analista)." DarkGray
        }

        Write-Jarvis "`n[RESULTADO] Limpeza completa concluída. Itens removidos: $totalRemoved | Espaço liberado: $([math]::Round($totalFreed/1MB,2)) MB" Green
        return @{ ItemsRemoved = $totalRemoved; FreedMB = [math]::Round($totalFreed/1MB,2) }
    }
    catch {
        Write-Jarvis "❌ Falha na limpeza: $($_.Exception.Message)" Red
        Write-LogEntry -Level ERROR -Message "Falha na Limpeza Completa: $($_.Exception.Message)"
        return @{ ItemsRemoved = 0; FreedMB = 0 }
    }
    finally {
        $ErrorActionPreference = $oldEA
        Restore-TerminalState -State $state
    }
}

# -----------------
# Otimização de Memória
# -----------------
# Tipo nativo para EmptyWorkingSet (só declara uma vez)
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

# Processos que não devemos tocar
$Global:ProtectedProcesses = @(
    'wininit','lsass','csrss','services','winlogon','smss','System','Idle','Registry',
    'Memory Compression','explorer','dwm','sihost','fontdrvhost','SearchIndexer'
)

function Invoke-OptimizeMemory {
    Write-Jarvis "`n[MANUTENÇÃO] Iniciando Otimização de Memória..." Cyan
    try {
        $beforeMB = [math]::Round((Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory/1024,2)
        Write-Jarvis "Memória disponível antes: $beforeMB MB" DarkGray

        $procs = Get-Process -ErrorAction SilentlyContinue | Where-Object {
            $_.Name -and $Global:ProtectedProcesses -notcontains $_.ProcessName -and $_.Id -ne $PID
        }

        $trimmed = 0
        foreach ($p in $procs) {
            try {
                if (-not $p.HasExited) {
                    if ([MemApi]::EmptyWorkingSet($p.Handle)) { $trimmed++ }
                }
            } catch {}
        }

        [System.GC]::Collect(); [System.GC]::WaitForPendingFinalizers(); [System.GC]::Collect()
        Start-Sleep -Milliseconds 400

        $afterMB = [math]::Round((Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory/1024,2)
        Write-Jarvis "Memória disponível depois: $afterMB MB" DarkGray
        Write-Jarvis "`n[RESULTADO] Memória liberada: $([math]::Round($afterMB-$beforeMB,2)) MB | Processos ajustados: $trimmed" Green

        return @{ FreedMB = [math]::Round($afterMB-$beforeMB,2); ProcessesTrimmed = $trimmed }
    } catch {
        Write-Jarvis "Erro na otimização: $($_.Exception.Message)" Red
        Write-LogEntry -Level ERROR -Message "OptimizeMemory error: $($_.Exception.Message)"
        return @{ FreedMB = 0; ProcessesTrimmed = 0 }
    }
}

# ---------------------------
# Exporta funções
# ---------------------------
Export-ModuleMember -Function `
    Invoke-SFC, Invoke-DISM, Invoke-NetworkCorrections, `
    Invoke-QuickClean, Invoke-FullClean, Invoke-OptimizeMemory
