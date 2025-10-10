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

# Função de correção combinada, pode ser chamada por automação
function Invoke-Corrections {
    Write-Jarvis "Iniciando rotina de correções completas..." Yellow
    Invoke-SFC
    Write-Jarvis "--------------------" DarkGray
    Invoke-DISM
    Write-Jarvis "--------------------" DarkGray
    Invoke-NetworkCorrections
    Write-Jarvis "Rotina de correções completa." Green
}

# Função para executar o System File Checker
function Invoke-SFC {
    Write-Jarvis "Iniciando SFC (System File Checker)..." Green
    try {
        Write-LogEntry -Level INFO -Message "Executando: sfc /scannow"
        sfc /scannow
        Write-Jarvis "SFC concluído. Verifique o resultado acima." Yellow
    }
    catch {
        Write-Jarvis "Erro ao executar SFC: $($_.Exception.Message)" Red
        Write-LogEntry -Level ERROR -Message "SFC error: $($_.Exception.Message)"
    }
}

# Função para executar o DISM
function Invoke-DISM {
    Write-Jarvis "Iniciando DISM (Deployment Image Servicing and Management)..." Green
    Write-Jarvis "Isso pode demorar alguns minutos. Por favor, aguarde." DarkGray
    try {
        Write-LogEntry -Level INFO -Message "Executando: Dism /Online /Cleanup-Image /RestoreHealth"
        Dism /Online /Cleanup-Image /RestoreHealth
        Write-Jarvis "DISM concluído. Verifique o resultado acima." Yellow
    }
    catch {
        Write-Jarvis "Erro ao executar DISM: $($_.Exception.Message)" Red
        Write-LogEntry -Level ERROR -Message "DISM error: $($_.Exception.Message)"
    }
}

# NOVA FUNÇÃO: Executa um conjunto de correções de rede comuns
function Invoke-NetworkCorrections {
    Write-Jarvis "Iniciando correções de rede imediatas..." Green
    try {
        Write-Jarvis "-> Limpando cache DNS..." DarkGray
        ipconfig /flushdns | Out-Null
        Write-LogEntry -Level INFO -Message "ipconfig /flushdns"
        
        Write-Jarvis "-> Resetando a pilha de IP..." DarkGray
        netsh int ip reset | Out-Null
        Write-LogEntry -Level INFO -Message "netsh int ip reset"
        
        Write-Jarvis "-> Resetando o catálogo Winsock..." DarkGray
        netsh winsock reset | Out-Null
        Write-LogEntry -Level INFO -Message "netsh winsock reset"
        
        Write-Jarvis "-> Resetando o proxy WinHTTP..." DarkGray
        netsh winhttp reset proxy | Out-Null
        Write-LogEntry -Level INFO -Message "netsh winhttp reset proxy"
        
        Write-Jarvis "Correções de rede concluídas. Recomenda-se reiniciar o computador para aplicar todas as mudanças." Yellow
    }
    catch {
        Write-Jarvis "Erro nas correções de rede: $($_.Exception.Message)" Red
        Write-LogEntry -Level ERROR -Message "NetworkCorrections error: $($_.Exception.Message)"
    }
}

# ===========================
# NOVAS FUNÇÕES REAIS
# ===========================

# Lista de processos/serviços protegidos (não tocar)
$ProtectedProcesses = @(
    "explorer","winlogon","csrss","services","lsass","svchost","System",
    "taskhostw","dwm","ctfmon","searchui","StartMenuExperienceHost",
    "msedge","chrome","firefox","winword","excel","outlook","powerpnt","teams","powershell"
)

# Função helper: size/count of a path (returns [pscustomobject] @{Count=..;SizeBytes=..})
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

# Função para remover e retornar stats freed
function Remove-PathAndReport {
    param([string]$Path)
    $before = Get-PathStats -Path $Path
    Try {
        if ($before.Count -gt 0) {
            # Remove items individually so we can catch errors
            $items = Get-ChildItem -Path $Path -Recurse -Force -ErrorAction SilentlyContinue
            foreach ($i in $items) {
                try { Remove-Item -LiteralPath $i.FullName -Force -Recurse -ErrorAction SilentlyContinue -Confirm:$false } catch {}
            }
        } else {
            # If wildcard path may represent files, attempt Remove-Item anyway (will be fast)
            try { Remove-Item -Path $Path -Recurse -Force -ErrorAction SilentlyContinue -Confirm:$false } catch {}
        }
    } catch { }
    $after = Get-PathStats -Path $Path
    $freedBytes = [math]::Max(0, $before.SizeBytes - $after.SizeBytes)
    $removedCount = [math]::Max(0, $before.Count - $after.Count)
    return @{ FreedBytes = $freedBytes; RemovedCount = $removedCount }
}

# -----------------
# Limpeza Rápida
# -----------------
function Invoke-QuickClean {
    <#
    Descrição: Limpeza rápida de cache e temporários. 
    Relata o que foi removido (quantidade e tamanho).
    #>
    Write-Jarvis "`n[MANUTENÇÃO] Iniciando Limpeza Rápida..." Cyan
    Write-LogEntry -Level INFO -Message "Start QuickClean"

    $totalFreed = 0
    $totalRemoved = 0

    $paths = @(
        "$env:TEMP\*",
        "$env:LOCALAPPDATA\Temp\*",
        "$env:WINDIR\Temp\*"
    )

    foreach ($p in $paths) {
        $res = Remove-PathAndReport -Path $p
        $totalFreed += $res.FreedBytes
        $totalRemoved += $res.RemovedCount
        Write-Jarvis "  -> Path: $p  | Arquivos removidos: $($res.RemovedCount)  | Espaço liberado: $([math]::Round($res.FreedBytes/1MB,2)) MB" DarkGray
        Write-LogEntry -Level INFO -Message "QuickClean path $p removed $($res.RemovedCount) items freed $([math]::Round($res.FreedBytes/1MB,2)) MB"
    }

    # Lixeira: contar antes e limpar
    try {
        $shell = New-Object -ComObject Shell.Application
        $recycle = $shell.Namespace(0xA)
        if ($recycle) {
            $items = $recycle.Items()
            $count = ($items | Measure-Object).Count
            # Attempt Clear-RecycleBin first (works on modern systems)
            try {
                Clear-RecycleBin -Force -ErrorAction SilentlyContinue
            } catch {
                # fallback: remove recycle bin contents by path
                $recyclePath = "$env:SYSTEMDRIVE\$Recycle.Bin\*"
                $res = Remove-PathAndReport -Path $recyclePath
                $totalFreed += $res.FreedBytes
                $totalRemoved += $res.RemovedCount
            }
            Write-Jarvis "  -> Lixeira: $count itens removidos (estimado)." DarkGray
            Write-LogEntry -Level INFO -Message "QuickClean recycle items: $count"
        }
    } catch {
        Write-LogEntry -Level WARNING -Message "QuickClean: erro ao limpar lixeira: $($_.Exception.Message)"
    }

    $totalFreedMB = [math]::Round($totalFreed / 1MB, 2)
    Write-Jarvis "`n[RESULTADO] Limpeza rápida concluída. Total removido: $totalRemoved itens | Espaço liberado: $totalFreedMB MB" Green
    Write-LogEntry -Level INFO -Message "QuickClean finished: items $totalRemoved freed ${totalFreedMB}MB"
    return @{ ItemsRemoved = $totalRemoved; FreedMB = $totalFreedMB }
}

# -----------------
# Limpeza Completa
# -----------------
function Invoke-FullClean {
    <#
    Descrição: Limpeza completa com confirmação. Limpa caches, logs (wevtutil), SoftwareDistribution, Explorer cache, navegadores (padrão paths),
    e reporta counts/space.
    #>
    Write-Jarvis "`n[MANUTENÇÃO] Iniciando Limpeza Completa..." Cyan
    Write-Jarvis "A limpeza completa pode remover caches, logs e arquivos temporários do sistema e aplicativos. Esse processo pode levar alguns minutos e pode afetar temporariamente o usuário final." DarkYellow
    $confirm = Read-Host "`nTem certeza que deseja continuar? (S/N)"
    if ($confirm -notin @('S','s')) {
        Write-Jarvis "Operação de Limpeza Completa cancelada pelo usuário." Yellow
        Write-LogEntry -Level INFO -Message "FullClean cancelled by user"
        return
    }

    Write-LogEntry -Level INFO -Message "Start FullClean"
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
        Write-LogEntry -Level INFO -Message "FullClean path $p removed $($res.RemovedCount) items freed $([math]::Round($res.FreedBytes/1MB,2)) MB"
    }

    # Limpar logs via wevtutil (apaga as logs; pode demandar privilégios)
    try {
        $logs = wevtutil el
        foreach ($l in $logs) {
            try {
                wevtutil cl $l 2>$null
                Write-LogEntry -Level INFO -Message "Cleared event log: $l"
            } catch {}
        }
        Write-Jarvis "  -> Logs do Windows limpos (wevtutil)." DarkGray
    } catch {
        Write-LogEntry -Level WARNING -Message "FullClean: wevtutil failed: $($_.Exception.Message)"
    }

    # Lixeira via Clear-RecycleBin
    try {
        Clear-RecycleBin -Force -ErrorAction SilentlyContinue
        Write-Jarvis "  -> Lixeira esvaziada." DarkGray
        Write-LogEntry -Level INFO -Message "FullClean: recyclebin cleared"
    } catch {
        Write-LogEntry -Level WARNING -Message "FullClean: recycle clear error: $($_.Exception.Message)"
    }

    $totalFreedMB = [math]::Round($totalFreed / 1MB, 2)
    Write-Jarvis "`n[RESULTADO] Limpeza completa concluída. Total removido: $totalRemoved itens | Espaço liberado: $totalFreedMB MB" Green
    Write-LogEntry -Level INFO -Message "FullClean finished: items $totalRemoved freed ${totalFreedMB}MB"
    return @{ ItemsRemoved = $totalRemoved; FreedMB = $totalFreedMB }
}

# -----------------
# Otimização de Memória (nativo, tenta reduzir working set)
# -----------------
# Declara EmptyWorkingSet via psapi
$null = $null
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
    <#
    Descrição: Tenta liberar RAM via EmptyWorkingSet em processos "seguros".
    Relata memória livre antes/depois e quantos processos foram 'trimmed'.
    #>
    Write-Jarvis "`n[MANUTENÇÃO] Iniciando Otimização de Memória (nativa)..." Cyan
    Write-LogEntry -Level INFO -Message "Start OptimizeMemory"

    try {
        $beforeKB = (Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory
        $beforeMB = [math]::Round($beforeKB / 1024,2)
        Write-Jarvis "Memória disponível antes: $beforeMB MB" DarkGray

        $procs = Get-Process -ErrorAction SilentlyContinue | Where-Object {
            $_.Name -and ($ProtectedProcesses -notcontains $_.ProcessName) -and $_.Id -ne $PID
        } | Sort-Object -Property WS -Descending

        $trimmed = 0
        foreach ($p in $procs) {
            try {
                # Skip system-critical processes
                if ($p.HasExited) { continue }
                # Try to empty working set
                $ok = [MemApi]::EmptyWorkingSet($p.Handle)
                if ($ok) { $trimmed++ }
            } catch {
                # ignore processes we cannot touch
            }
        }

        # Force GC in current process as well
        [System.GC]::Collect()
        [System.GC]::WaitForPendingFinalizers()
        [System.GC]::Collect()

        Start-Sleep -Milliseconds 500
        $afterKB = (Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory
        $afterMB = [math]::Round($afterKB / 1024,2)
        $freedMB = [math]::Round($afterMB - $beforeMB,2)

        Write-Jarvis "Memória disponível depois: $afterMB MB" DarkGray
        Write-Jarvis "`n[RESULTADO] Memória liberada (estimada): $freedMB MB | Processos trimados: $trimmed" Green
        Write-LogEntry -Level INFO -Message "OptimizeMemory finished: freed ${freedMB}MB trimmed ${trimmed} procs"
        return @{ FreedMB = $freedMB; ProcessesTrimmed = $trimmed }
    } catch {
        Write-Jarvis "Erro durante otimização de memória: $($_.Exception.Message)" Red
        Write-LogEntry -Level ERROR -Message "OptimizeMemory error: $($_.Exception.Message)"
        return @{ FreedMB = 0; ProcessesTrimmed = 0 }
    }
}

# ---------------------------
# Exporta todas funções (antigas + novas)
# ---------------------------
Export-ModuleMember -Function `
    Invoke-Corrections, Invoke-SFC, Invoke-DISM, Invoke-NetworkCorrections, `
    Invoke-QuickClean, Invoke-FullClean, Invoke-OptimizeMemory
