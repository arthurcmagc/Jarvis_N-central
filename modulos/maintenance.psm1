# maintenance.psm1
# Módulo com funções de manutenção e correção do sistema.
# Versão: Integrada — preserva funções antigas + novas funções reais e instrumentadas.

# ---------------------------
# Variáveis / Paths / Log
# ---------------------------
$OutputDir = Join-Path $PSScriptRoot "..\output"
if (-not (Test-Path $OutputDir)) { New-Item -Path $OutputDir -ItemType Directory | Out-Null }
$Global:JarvisLogPath = Join-Path $OutputDir "JarvisLog.txt"

function Write-LogEntry {
    param(
        [string]$LogPath = $Global:JarvisLogPath,
        [string]$Level = "INFO",
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
# FUNÇÕES ANTIGAS (ORIGINAIS)
# ===========================

function Invoke-Corrections {
    Write-Jarvis "Iniciando rotina de correções completas..." Yellow
    Invoke-SFC
    Write-Jarvis "--------------------" DarkGray
    Invoke-DISM
    Write-Jarvis "--------------------" DarkGray
    Invoke-NetworkCorrections
    Write-Jarvis "Rotina de correções completa." Green
}

function Invoke-SFC {
    Write-Jarvis "Iniciando SFC (System File Checker)..." Green
    try {
        Write-LogEntry -Message "Executando: sfc /scannow"
        sfc /scannow
        Write-Jarvis "SFC concluído. Verifique o resultado acima." Yellow
    } catch {
        Write-Jarvis "Erro ao executar SFC: $($_.Exception.Message)" Red
        Write-LogEntry -Level ERROR -Message "SFC error: $($_.Exception.Message)"
    }
}

function Invoke-DISM {
    Write-Jarvis "Iniciando DISM (Deployment Image Servicing and Management)..." Green
    Write-Jarvis "Isso pode demorar alguns minutos. Por favor, aguarde." DarkGray
    try {
        Write-LogEntry -Message "Executando: Dism /Online /Cleanup-Image /RestoreHealth"
        Dism /Online /Cleanup-Image /RestoreHealth
        Write-Jarvis "DISM concluído. Verifique o resultado acima." Yellow
    } catch {
        Write-Jarvis "Erro ao executar DISM: $($_.Exception.Message)" Red
        Write-LogEntry -Level ERROR -Message "DISM error: $($_.Exception.Message)"
    }
}

function Invoke-NetworkCorrections {
    Write-Jarvis "Iniciando correções de rede imediatas..." Green
    try {
        Write-Jarvis "-> Limpando cache DNS..." DarkGray
        ipconfig /flushdns | Out-Null
        netsh int ip reset | Out-Null
        netsh winsock reset | Out-Null
        netsh winhttp reset proxy | Out-Null
        Write-Jarvis "Correções de rede concluídas. Recomenda-se reiniciar o computador." Yellow
    } catch {
        Write-Jarvis "Erro nas correções de rede: $($_.Exception.Message)" Red
        Write-LogEntry -Level ERROR -Message "NetworkCorrections error: $($_.Exception.Message)"
    }
}

# ===========================
# NOVAS FUNÇÕES REAIS
# ===========================

$ProtectedProcesses = @(
    "explorer","winlogon","csrss","services","lsass","svchost","System",
    "taskhostw","dwm","ctfmon","searchui","StartMenuExperienceHost",
    "msedge","chrome","firefox","winword","excel","outlook","powerpnt","teams","powershell"
)

function Get-PathStats {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return @{ Count = 0; SizeBytes = 0 } }
    try {
        $items = Get-ChildItem -Path $Path -Recurse -Force -File -ErrorAction SilentlyContinue
        $count = ($items | Measure-Object).Count
        $size = 0
        if ($count -gt 0) {
            $size = ($items | Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum
        }
        return @{ Count = $count; SizeBytes = $size }
    } catch { return @{ Count = 0; SizeBytes = 0 } }
}

function Remove-PathAndReport {
    param([string]$Path)
    $before = Get-PathStats -Path $Path
    Try {
        if ($before.Count -gt 0) {
            $items = Get-ChildItem -Path $Path -Recurse -Force -ErrorAction SilentlyContinue
            foreach ($i in $items) {
                try { Remove-Item -LiteralPath $i.FullName -Force -Recurse -ErrorAction SilentlyContinue -Confirm:$false } catch {}
            }
        } else {
            try { Remove-Item -Path $Path -Recurse -Force -ErrorAction SilentlyContinue -Confirm:$false } catch {}
        }
    } catch { }
    $after = Get-PathStats -Path $Path
    $freedBytes = [math]::Max(0, $before.SizeBytes - $after.SizeBytes)
    $removedCount = [math]::Max(0, $before.Count - $after.Count)
    return @{ FreedBytes = $freedBytes; RemovedCount = $removedCount }
}

# -----------------
# Limpeza Completa (com opção agressiva)
# -----------------
function Invoke-FullClean {
    Write-Jarvis "`n[MANUTENÇÃO] Iniciando Limpeza Completa..." Cyan
    Write-Jarvis "A limpeza completa pode remover caches, logs e arquivos temporários do sistema e aplicativos." DarkYellow
    $confirm = Read-Host "`nTem certeza que deseja continuar? (S/N)"
    if ($confirm -notin @('S','s')) {
        Write-Jarvis "Operação cancelada pelo usuário." Yellow
        return
    }

    $totalFreed = 0
    $totalRemoved = 0

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

    foreach ($p in $paths) {
        $res = Remove-PathAndReport -Path $p
        $totalFreed += $res.FreedBytes
        $totalRemoved += $res.RemovedCount
        Write-Jarvis "  -> Path: $p | Removidos: $($res.RemovedCount) | Liberado: $([math]::Round($res.FreedBytes/1MB,2)) MB" DarkGray
    }

    try {
        $logs = wevtutil el
        foreach ($l in $logs) { try { wevtutil cl $l 2>$null } catch {} }
        Write-Jarvis "  -> Logs do Windows limpos (wevtutil)." DarkGray
    } catch {}

    try {
        Clear-RecycleBin -Force -ErrorAction SilentlyContinue
        Write-Jarvis "  -> Lixeira esvaziada." DarkGray
    } catch {}

    # -------- LIMPEZA AGRESSIVA (opcional) --------
    Write-Jarvis "`nDeseja executar a limpeza agressiva (Dell SARemediation e Remediation Packages)?`nATENÇÃO: Isso pode remover utilitários de recuperação Dell." Red
    $confirm2 = Read-Host "Executar limpeza agressiva? (S/N)"
    if ($confirm2 -in @('S','s')) {
        Write-Jarvis "`n[AGRESSIVA] Iniciando remoção de componentes Remediation..." Yellow

        $extraPaths = @(
            @{Path = "C:\ProgramData\Dell\SARemediation\SystemRepair\*"; Description = "Dell System Repair Snapshots"},
            @{Path = "C:\ProgramData\Dell\SARemediation\Snapshots\*"; Description = "Dell SARemediation Snapshots"}
        )

        foreach ($ep in $extraPaths) {
            $res = Remove-PathAndReport -Path $ep.Path
            Write-Jarvis "  -> $($ep.Description): Removidos $($res.RemovedCount) | Liberado $([math]::Round($res.FreedBytes/1MB,2)) MB" DarkGray
            $totalFreed += $res.FreedBytes
            $totalRemoved += $res.RemovedCount
        }

        try {
            $remediations = Get-WmiObject -Class Win32_Product | Where-Object { $_.Name -like "*Remediation*" }
            foreach ($r in $remediations) {
                Write-Jarvis "  -> Desinstalando pacote: $($r.Name)" DarkGray
                $r.Uninstall() | Out-Null
            }
            Write-Jarvis "[AGRESSIVA] Remoção de pacotes Remediation concluída." Green
        } catch {
            Write-Jarvis "[AGRESSIVA] Falha ao remover componentes Remediation: $($_.Exception.Message)" Red
        }
    } else {
        Write-Jarvis "[INFO] Limpeza agressiva ignorada pelo usuário." DarkGray
    }

    $totalFreedMB = [math]::Round($totalFreed / 1MB, 2)
    Write-Jarvis "`n[RESULTADO] Limpeza completa concluída. Itens removidos: $totalRemoved | Espaço liberado: $totalFreedMB MB" Green
    return @{ ItemsRemoved = $totalRemoved; FreedMB = $totalFreedMB }
}

# -----------------
# Otimização de Memória
# -----------------
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

function Invoke-OptimizeMemory {
    Write-Jarvis "`n[MANUTENÇÃO] Iniciando Otimização de Memória (nativa)..." Cyan
    try {
        $beforeKB = (Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory
        $beforeMB = [math]::Round($beforeKB / 1024,2)
        Write-Jarvis "Memória disponível antes: $beforeMB MB" DarkGray

        $procs = Get-Process | Where-Object {
            $_.Name -and ($ProtectedProcesses -notcontains $_.ProcessName) -and $_.Id -ne $PID
        }

        $trimmed = 0
        foreach ($p in $procs) {
            try { [MemApi]::EmptyWorkingSet($p.Handle) | Out-Null; $trimmed++ } catch {}
        }

        [System.GC]::Collect(); Start-Sleep -Milliseconds 400
        $afterKB = (Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory
        $afterMB = [math]::Round($afterKB / 1024,2)
        $freedMB = [math]::Round($afterMB - $beforeMB,2)

        Write-Jarvis "`n[RESULTADO] Memória liberada: $freedMB MB | Processos ajustados: $trimmed" Green
        return @{ FreedMB = $freedMB; ProcessesTrimmed = $trimmed }
    } catch {
        Write-Jarvis "Erro: $($_.Exception.Message)" Red
    }
}

Export-ModuleMember -Function `
    Invoke-Corrections, Invoke-SFC, Invoke-DISM, Invoke-NetworkCorrections, `
    Invoke-FullClean, Invoke-OptimizeMemory
