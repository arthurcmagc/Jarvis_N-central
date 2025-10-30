# menudiag.ps1
# Diagnóstico de importação de módulos do Jarvis (PS 5.1/7+)

[CmdletBinding()]
param(
    # Opcional: paths explícitos dos módulos a testar
    [string[]]$Modules
)

# =========================
# Contexto / Cabeçalho
# =========================
$ErrorActionPreference = 'Continue'
Write-Host "================ JARVIS - DIAGNÓSTICO DE MÓDULOS ================" -ForegroundColor Cyan
Write-Host ("Host      : {0}" -f $Host.Name) -ForegroundColor DarkGray
Write-Host ("PSVersion : {0}" -f $PSVersionTable.PSVersion) -ForegroundColor DarkGray
Write-Host ("CLR       : {0}" -f $PSVersionTable.CLRVersion) -ForegroundColor DarkGray
Write-Host ("Path      : {0}" -f (Get-Location)) -ForegroundColor DarkGray
Write-Host "==================================================================" -ForegroundColor Cyan

# =========================
# Descobrir caminhos padrão
# =========================
$ScriptRoot = Split-Path -Parent -Path $MyInvocation.MyCommand.Definition
$DefaultModules = @(
    Join-Path $ScriptRoot "modulos\interpretation.psm1"),
    (Join-Path $ScriptRoot "modulos\maintenance.psm1"),
    (Join-Path $ScriptRoot "modulos\promptbuilder.psm1"),
    (Join-Path $ScriptRoot "modulos\services.psm1")

if (-not $Modules -or $Modules.Count -eq 0) {
    $Modules = $DefaultModules
}

# =========================
# Utils
# =========================
function Convert-FileNbsp {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)
    try {
        if (-not (Test-Path -LiteralPath $Path)) { return $false }
        $bytes = Get-Content -Raw -Path $Path -Encoding Byte -ErrorAction Stop
        if (-not $bytes) { return $false }
        $changed = $false
        for ($i=0; $i -lt $bytes.Length; $i++) {
            if ($bytes[$i] -eq 0xA0) { $bytes[$i] = 0x20; $changed = $true }
        }
        if ($changed) { [System.IO.File]::WriteAllBytes($Path, $bytes) }
        return $changed
    } catch {
        Write-Host ("[NBSP] Falha ao processar {0}: {1}" -f $Path, $_.Exception.Message) -ForegroundColor Yellow
        return $false
    }
}

function Import-ModuleVerbose {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [switch]$TryRepairNbsp
    )

    Write-Host "`n== Testando módulo ==" -ForegroundColor Cyan
    Write-Host $Path -ForegroundColor DarkCyan

    if (-not (Test-Path -LiteralPath $Path)) {
        Write-Host "Arquivo não encontrado." -ForegroundColor Red
        return
    }

    $fi = Get-Item -LiteralPath $Path
    Write-Host ("Tamanho: {0} bytes | Editado: {1}" -f $fi.Length, $fi.LastWriteTime) -ForegroundColor DarkGray

    try { Unblock-File -LiteralPath $Path -ErrorAction SilentlyContinue } catch {}

    if ($TryRepairNbsp) {
        $fix = Convert-FileNbsp -Path $Path
        if ($fix) { Write-Host "NBSP reparado (0xA0->0x20)." -ForegroundColor Yellow }
    }

    try {
        $module = Import-Module -Name $Path -Force -ErrorAction Stop -PassThru
        Write-Host ("OK: {0} importado." -f $module.Name) -ForegroundColor Green

        $cmds = ($module.ExportedCommands.Keys | Sort-Object)
        if ($cmds.Count -gt 0) {
            Write-Host ("Exportados ({0}): {1}" -f $cmds.Count, ($cmds -join ", ")) -ForegroundColor DarkGreen
        } else {
            Write-Host "Nenhum comando exportado." -ForegroundColor Yellow
        }
    } catch {
        Write-Host "FALHA AO IMPORTAR" -ForegroundColor Red
        Write-Host ("Mensagem: {0}" -f $_.Exception.Message) -ForegroundColor Yellow

        if ($_.Exception.InnerException) {
            Write-Host ("Inner: {0}" -f $_.Exception.InnerException.Message) -ForegroundColor DarkYellow
        }
        if ($_.FullyQualifiedErrorId) {
            Write-Host ("FQID: {0}" -f $_.FullyQualifiedErrorId) -ForegroundColor DarkGray
        }
        if ($_.CategoryInfo) {
            Write-Host ("Categoria: {0}" -f $_.CategoryInfo) -ForegroundColor DarkGray
        }
        if ($_.InvocationInfo) {
            $ii = $_.InvocationInfo
            if ($ii.ScriptLineNumber -gt 0) {
                Write-Host ("Script: {0}" -f $ii.ScriptName) -ForegroundColor DarkGray
                Write-Host ("Linha : {0}, Coluna: {1}" -f $ii.ScriptLineNumber, $ii.OffsetInLine) -ForegroundColor DarkGray
                if ($ii.Line) { Write-Host ("Código: {0}" -f $ii.Line.Trim()) -ForegroundColor DarkGray }
            }
        }
        if ($_.ScriptStackTrace) {
            Write-Host "Stack:" -ForegroundColor DarkGray
            Write-Host $_.ScriptStackTrace -ForegroundColor DarkGray
        }

        # Tenta de novo após NBSP (se ainda não tentou)
        if (-not $TryRepairNbsp) {
            Write-Host "Tentando reparar NBSP e reimportar..." -ForegroundColor Yellow
            Import-ModuleVerbose -Path $Path -TryRepairNbsp
        }
    }
}

# =========================
# Execução
# =========================
foreach ($m in $Modules) {
    Import-ModuleVerbose -Path $m
}

Write-Host "`n==================================================================" -ForegroundColor Cyan
Write-Host "Fim do diagnóstico." -ForegroundColor Cyan
