# menu.ps1 — Assistente de Diagnóstico Jarvis (PS 5.1/7+)

# =========================
# Configuração do console
# =========================
try {
    $Host.UI.RawUI.WindowTitle = "Assistente de Diagnóstico - Jarvis"
    $Host.UI.RawUI.BufferSize  = New-Object System.Management.Automation.Host.Size(120, 9999)
    $Host.UI.RawUI.WindowSize  = New-Object System.Management.Automation.Host.Size(120, 40)
} catch { }

# =========================
# Caminhos principais
# =========================
$ScriptRoot            = Split-Path -Parent -Path $MyInvocation.MyCommand.Definition
$DiagnosticScriptPath  = Join-Path $ScriptRoot "diagnostic-v2.ps1"
$LogJsonPath           = Join-Path $ScriptRoot "output\status-maquina.json"
$InterpretationPath    = Join-Path $ScriptRoot "modulos\interpretation.psm1"
$MaintenancePath       = Join-Path $ScriptRoot "modulos\maintenance.psm1"
$PromptBuilderPath     = Join-Path $ScriptRoot "modulos\promptbuilder.psm1"

# =========================
# Pasta fixa (TXT persistente do prompt)
# =========================
$script:FixedOutputDir = 'C:\HealthCheck\Assistente Jarvis - Hype\Jarvis_N-central-main\output'

function Save-PromptToFixedPath {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$Text)
    try {
        if (-not (Test-Path -LiteralPath $script:FixedOutputDir)) {
            New-Item -ItemType Directory -Path $script:FixedOutputDir -Force | Out-Null
        }
        $ts   = Get-Date -Format 'yyyyMMdd_HHmmss'
        $dest = Join-Path $script:FixedOutputDir ("Prompt_Inteligente_{0}.txt" -f $ts)
        Set-Content -Path $dest -Value $Text -Encoding UTF8 -Force
        return $dest
    } catch {
        return $null
    }
}

# =========================
# Helpers de import (com correção de NBSP)
# =========================
function Convert-FileNbsp {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)
    try {
        if (-not (Test-Path -LiteralPath $Path)) { return }
        $raw   = Get-Content -Raw -Path $Path -Encoding Byte
        if (-not $raw) { return }
        $fixed = [byte[]]($raw | ForEach-Object { if ($_ -eq 0xA0) { 0x20 } else { $_ } })
        if ($raw.Length -ne $fixed.Length) { return }
        for ($i=0; $i -lt $raw.Length; $i++) {
            if ($raw[$i] -ne $fixed[$i]) { [IO.File]::WriteAllBytes($Path, $fixed); break }
        }
    } catch { }
}

function Import-ModuleSafe {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [switch]$RepairNbspFirst
    )
    try {
        if ($RepairNbspFirst) { Convert-FileNbsp -Path $Path }
        Import-Module -Name $Path -Force -ErrorAction Stop
        return $true
    } catch {
        Write-Host "Falha ao importar módulo: $Path" -ForegroundColor Red
        Write-Host "Detalhes: $($_.Exception.Message)" -ForegroundColor DarkYellow
        return $false
    }
}

# =========================
# Import de módulos
# =========================
$okInterp  = Import-ModuleSafe -Path $InterpretationPath -RepairNbspFirst
$okMaint   = Import-ModuleSafe -Path $MaintenancePath   -RepairNbspFirst
$okPrompt  = Import-ModuleSafe -Path $PromptBuilderPath -RepairNbspFirst

if (-not $okInterp) {
    Write-Host "ATENÇÃO: interpretation.psm1 não foi importado. Relatório formatado pode não abrir." -ForegroundColor Yellow
}
if (-not $okMaint) {
    Write-Host "ATENÇÃO: maintenance.psm1 não foi importado. Correções podem não funcionar." -ForegroundColor Yellow
}
if (-not $okPrompt) {
    Write-Host "ATENÇÃO: promptbuilder.psm1 não foi importado. O Prompt Inteligente pode não funcionar." -ForegroundColor Yellow
}

# =========================
# Estado do Prompt (memória da sessão)
# =========================
$script:LastPrompt     = $null
$script:LastPromptPath = $null

# =========================
# Helpers Sessão/Entrada
# =========================
function Test-InteractiveSession {
    try {
        return [Environment]::UserInteractive -and ($Host.UI.RawUI.KeyAvailable -or $Host.Name -notlike "*ServerRemoteHost*")
    } catch { return $false }
}

function Get-UserSymptom {
    [CmdletBinding()]
    param([string]$Title = "Jarvis - Sintoma do Usuário")
    if (Test-InteractiveSession) {
        try {
            Add-Type -AssemblyName Microsoft.VisualBasic -ErrorAction Stop
            $message = "Informe brevemente o sintoma (ex.: lentidão ao iniciar, falha na internet, travamentos...)."
            $val = [Microsoft.VisualBasic.Interaction]::InputBox($message, $Title, "")
            if ($null -ne $val -and $val.Trim().Length -gt 0) { return $val }
        } catch { }
    }
    Write-Host ""
    Write-Host "[IA] Digite o sintoma do usuário e pressione ENTER:" -ForegroundColor Cyan
    $v = Read-Host "Sintoma"
    if ([string]::IsNullOrWhiteSpace($v)) { return $null }
    return $v.Trim()
}

# =========================
# Clipboard resiliente
# =========================
function Set-ClipboardSafe {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$Text)

    try {
        Set-Clipboard -Value $Text -ErrorAction Stop
        return @{ Copied=$true; Method="Set-Clipboard"; Path=$null; Error=$null }
    } catch {
        $err1 = $_.Exception.Message
    }

    $tmp = [System.IO.Path]::GetTempFileName()
    try {
        Set-Content -Path $tmp -Value $Text -Encoding UTF8 -Force
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = "powershell.exe"
        $psi.Arguments = "-NoProfile -STA -Command `"Get-Content -Raw -Encoding UTF8 '$tmp' | Set-Clipboard`""
        $psi.CreateNoWindow = $true
        $psi.WindowStyle = 'Hidden'
        $p = [System.Diagnostics.Process]::Start($psi)
        $p.WaitForExit()
        if ($p.ExitCode -eq 0) {
            try { Remove-Item $tmp -Force -ErrorAction SilentlyContinue } catch {}
            return @{ Copied=$true; Method="STA helper"; Path=$null; Error=$null }
        }
    } catch {
        $err2 = $_.Exception.Message
    }

    try {
        cmd.exe /c "type `"$tmp`" | clip" | Out-Null
        try { Remove-Item $tmp -Force -ErrorAction SilentlyContinue } catch {}
        return @{ Copied=$true; Method="clip.exe"; Path=$null; Error=$null }
    } catch {
        $err3 = $_.Exception.Message
    }

    return @{ Copied=$false; Method="file"; Path=$tmp; Error=("Set-Clipboard: $err1; STA: $err2; clip.exe: $err3") }
}

# =========================
# Prompt Inteligente
# =========================
function Invoke-IntelligentPrompt {
    [CmdletBinding()]
    param([string]$JsonPath)

    Write-Host "Gerando Prompt Inteligente..." -ForegroundColor Cyan

    $isInteractive = Test-InteractiveSession
    if (-not (Test-Path $JsonPath)) {
        Write-Host "[ERRO] Arquivo JSON não encontrado em: $JsonPath" -ForegroundColor Red
        return
    }

    try {
        $UserSymptom = Get-UserSymptom -Title "Jarvis - Sintoma do Usuário"
        if ([string]::IsNullOrWhiteSpace($UserSymptom)) {
            Write-Host "❌ Operação cancelada. Nenhum sintoma informado." -ForegroundColor Yellow
            return
        }

        $data = Get-Content $JsonPath -Raw | ConvertFrom-Json

        # Amostra de logs — tenta campos comuns do JSON gerado
        $logs = @()
        if ($null -ne $data.EventosCriticos) {
            if     ($data.EventosCriticos.Events)            { $logs = @($data.EventosCriticos.Events) }
            elseif ($data.EventosCriticos.EventosRelevantes) { $logs = @($data.EventosCriticos.EventosRelevantes) }
            elseif ($data.EventosCriticos.EventosCriticos)   { $logs = @($data.EventosCriticos.EventosCriticos) }
        } elseif ($null -ne $data.Dados -and $null -ne $data.Dados.Eventos) {
            # Se o formato “novo” tiver uma área consolidada
            $logs = @($data.Dados.Eventos.RelevantesSugeridos)
        }

        if (-not (Get-Command Build-IntelligentPrompt -ErrorAction SilentlyContinue)) {
            Write-Host "❌ Função 'Build-IntelligentPrompt' não disponível (promptbuilder.psm1?)." -ForegroundColor Red
            return
        }

        $prompt = Build-IntelligentPrompt -AllLogs $logs -UserSymptom $UserSymptom -TargetTokenBudget 2200

        # Guarda na sessão
        $script:LastPrompt     = $prompt
        $script:LastPromptPath = $null

        # SEMPRE salva cópia persistente (System Shell / auditoria)
        $fixedPath = Save-PromptToFixedPath -Text $prompt
        if ($fixedPath) {
            $script:LastPromptPath = $fixedPath
            Write-Host "📄 Prompt salvo em:" -ForegroundColor Yellow
            Write-Host "  $fixedPath" -ForegroundColor Cyan
        } else {
            Write-Host "⚠️ Falha ao salvar cópia persistente em $($script:FixedOutputDir)" -ForegroundColor Yellow
        }

        # Tenta copiar clipboard (interativo)
        $copied = $false
        if ($isInteractive) {
            $copy = Set-ClipboardSafe -Text $prompt
            if ($copy.Copied) {
                $copied = $true
                Write-Host "✅ Prompt copiado para a área de transferência! ($($copy.Method))" -ForegroundColor Green
            } else {
                Write-Host "⚠️ Não foi possível copiar automaticamente para o clipboard." -ForegroundColor Yellow
            }
        } else {
            Write-Host "[Aviso] Sessão não interativa: clipboard e abertura automática do navegador podem falhar." -ForegroundColor DarkYellow
        }

        # Tenta abrir o ChatGPT (interativo)
        $url = "https://chat.openai.com/?model=gpt-5"
        $opened = $false
        if ($isInteractive) {
            try { Start-Process $url -ErrorAction Stop; $opened = $true }
            catch {
                if     (Get-Command "msedge.exe"  -ErrorAction SilentlyContinue) { Start-Process "msedge.exe"  $url; $opened = $true }
                elseif (Get-Command "chrome.exe"  -ErrorAction SilentlyContinue) { Start-Process "chrome.exe"  $url; $opened = $true }
                elseif (Get-Command "firefox.exe" -ErrorAction SilentlyContinue) { Start-Process "firefox.exe" $url; $opened = $true }
            }
        }

        if ($opened) {
            Write-Host "`nCole (CTRL+V) no ChatGPT e gere o relatório técnico." -ForegroundColor Cyan
        } else {
            Write-Host ""
            Write-Host "Abra o link no navegador e cole o conteúdo:" -ForegroundColor Yellow
            if ($copied) {
                Write-Host " - Do seu clipboard (CTRL+V)" -ForegroundColor DarkYellow
            } else {
                Write-Host " - Do arquivo salvo em: $script:LastPromptPath" -ForegroundColor DarkYellow
            }
            Write-Host "  $url" -ForegroundColor Cyan
            Write-Host ""
            Write-Host "Dica: Você também pode visualizar o texto do prompt em:" -ForegroundColor DarkGray
            Write-Host "  Menu [2] > Ver Prompt Inteligente (texto)" -ForegroundColor DarkGray
        }
    }
    catch {
        Write-Host "[ERRO] Falha ao gerar o prompt inteligente: $($_.Exception.Message)" -ForegroundColor Red
    }
}

# =========================
# Sugestão final (fabricante)
# =========================
function Show-JarvisFinalSuggestion {
    [CmdletBinding()]
    param([string]$JsonPath)
    if (-not (Test-Path $JsonPath)) { return }
    try {
        $data = Get-Content $JsonPath -Raw | ConvertFrom-Json
        $windowWidth = $Host.UI.RawUI.WindowSize.Width
        Write-Host "`n" + ("=" * $windowWidth) -ForegroundColor Cyan
        $manufacturer = $null
        if ($data.Fabricante -and $data.Fabricante.Manufacturer) { $manufacturer = $data.Fabricante.Manufacturer }
        elseif ($data.Dados -and $data.Dados.Fabricante -and $data.Dados.Fabricante.Manufacturer) { $manufacturer = $data.Dados.Fabricante.Manufacturer }

        Write-Host "[JARVIS] " -NoNewline -ForegroundColor Blue
        if ($manufacturer -and (Get-Command Get-ManufacturerSoftwareSuggestion -ErrorAction SilentlyContinue)) {
            $suggestion = Get-ManufacturerSoftwareSuggestion -Manufacturer $manufacturer
            if ($suggestion) {
                if (Get-Command Write-TypingFormattedText -ErrorAction SilentlyContinue) {
                    Write-TypingFormattedText -Text $suggestion -Delay 10 -ForegroundColor White -LineWidth ($windowWidth-4) -Indent "          "
                } else {
                    Write-Host $suggestion -ForegroundColor White
                }
            } else {
                Write-Host "Sugestão de Software do Fabricante: Não foi possível identificar o fabricante." -ForegroundColor Yellow
            }
        } else {
            Write-Host "Sugestão de Software do Fabricante: Não foi possível identificar o fabricante." -ForegroundColor Yellow
        }
        Write-Host ("=" * $windowWidth) -ForegroundColor Cyan
    }
    catch {
        Write-Host "[ERRO] Falha ao exibir a sugestão do Jarvis: $($_.Exception.Message)" -ForegroundColor Red
    }
}

# =========================
# Exibir Prompt em texto (submenu Relatórios)
# =========================
function Show-LastPromptText {
    if (-not $script:LastPrompt -and -not $script:LastPromptPath) {
        Write-Host "Nenhum Prompt Inteligente gerado nesta sessão. Use o menu [4] primeiro." -ForegroundColor Yellow
        return
    }

    Write-Host ""
    Write-Host "=== Prompt Inteligente (texto) ===" -ForegroundColor Cyan
    Write-Host ""

    if ($script:LastPrompt) {
        $script:LastPrompt | Out-Host -Paging
    }
    elseif (Test-Path $script:LastPromptPath) {
        Get-Content -Path $script:LastPromptPath -Raw | Out-Host -Paging
    } else {
        Write-Host "(O arquivo de prompt temporário/persistente não está mais disponível.)" -ForegroundColor Yellow
    }

    if ($script:LastPromptPath -and $script:LastPromptPath -like "$script:FixedOutputDir*") {
        Write-Host ""
        Write-Host "Cópia persistente do prompt salva em:" -ForegroundColor DarkGray
        Write-Host "  $script:LastPromptPath" -ForegroundColor DarkGray
    }

    Write-Host ""
    Write-Host "Para enviar ao ChatGPT:" -ForegroundColor Yellow
    Write-Host "  1) Abra o link abaixo;" -ForegroundColor DarkYellow
    Write-Host "  2) CTRL+A, CTRL+C no texto exibido aqui (ou no TXT salvo);" -ForegroundColor DarkYellow
    Write-Host "  3) CTRL+V no ChatGPT." -ForegroundColor DarkYellow
    Write-Host "  https://chat.openai.com/?model=gpt-5" -ForegroundColor Cyan
}

# =========================
# Menu de relatórios
# =========================
function Show-ReportsMenu {
    $inReports = $true
    while ($inReports) {
        Clear-Host
        Write-Host "=================================================" -ForegroundColor Cyan
        Write-Host "      Visualizar Relatórios" -ForegroundColor Cyan
        Write-Host "=================================================" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "[1] Ver Relatório Formatado" -ForegroundColor White
        Write-Host "[2] Ver JSON Completo" -ForegroundColor White
        Write-Host "[3] Ver Prompt Inteligente (texto)" -ForegroundColor White
        Write-Host "[4] Voltar" -ForegroundColor White
        Write-Host "`n=================================================" -ForegroundColor Cyan

        $submenu = Read-Host "`nEscolha uma opção (1-4)"
        switch ($submenu) {
            "1" {
                if (Get-Command Start-DiagnosticAnalysis -ErrorAction SilentlyContinue) {
                    Start-DiagnosticAnalysis -JsonPath $LogJsonPath
                } else {
                    Write-Host "Módulo de interpretação não disponível." -ForegroundColor Red
                }
                Read-Host "`nPressione ENTER para continuar"
            }
            "2" {
                Clear-Host
                if (Test-Path -LiteralPath $LogJsonPath) {
                    try { Get-Content -Raw -Path $LogJsonPath | Write-Host -ForegroundColor Gray }
                    catch { Write-Host "Falha ao ler JSON: $($_.Exception.Message)" -ForegroundColor Red }
                } else {
                    Write-Host "Arquivo não encontrado: $LogJsonPath" -ForegroundColor Yellow
                }
                Read-Host "`nPressione ENTER para continuar"
            }
            "3" { Clear-Host; Show-LastPromptText; Read-Host "`nPressione ENTER para continuar" }
            "4" { $inReports = $false }
            default { Write-Host "Opção inválida." -ForegroundColor Red; Start-Sleep 2 }
        }
    }
}

# =========================
# Menu de correções
# =========================
function Show-FixesMenu {
    $inFixes = $true
    while ($inFixes) {
        Clear-Host
        Write-Host "=================================================" -ForegroundColor Cyan
        Write-Host "      Executar Correções Automáticas" -ForegroundColor Cyan
        Write-Host "=================================================" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "[1] Executar SFC" -ForegroundColor White
        Write-Host "[2] Executar DISM" -ForegroundColor White
        Write-Host "[3] Correções de Rede" -ForegroundColor White
        Write-Host "[4] Limpeza Completa" -ForegroundColor White
        Write-Host "[5] Otimização Inteligente (RAM + Limpeza Rápida)" -ForegroundColor White
        Write-Host "[6] Limpeza Rápida (TEMP/Lixeira/WU Download)" -ForegroundColor White
        Write-Host "[7] Reparo do Indexador (WSearch)" -ForegroundColor White
        Write-Host "[8] Voltar" -ForegroundColor White
        Write-Host "`n=================================================" -ForegroundColor Cyan

        $fx = Read-Host "`nEscolha uma opção (1-8)"
        switch ($fx) {
            "1" { if (Get-Command Invoke-SFC               -ErrorAction SilentlyContinue) { Invoke-SFC } else { Write-Host "Invoke-SFC indisponível."               -ForegroundColor Yellow }; Read-Host "`nPressione ENTER para voltar" }
            "2" { if (Get-Command Invoke-DISM              -ErrorAction SilentlyContinue) { Invoke-DISM } else { Write-Host "Invoke-DISM indisponível."              -ForegroundColor Yellow }; Read-Host "`nPressione ENTER para voltar" }
            "3" { if (Get-Command Invoke-NetworkCorrections-ErrorAction SilentlyContinue) { Invoke-NetworkCorrections } else { Write-Host "Invoke-NetworkCorrections indisponível." -ForegroundColor Yellow }; Read-Host "`nPressione ENTER para voltar" }
            "4" { if (Get-Command Invoke-FullClean         -ErrorAction SilentlyContinue) { Invoke-FullClean } else { Write-Host "Invoke-FullClean indisponível."       -ForegroundColor Yellow }; Read-Host "`nPressione ENTER para voltar" }
            "5" {
                if (Get-Command Invoke-OptimizeMemory -ErrorAction SilentlyContinue) { Invoke-OptimizeMemory } else { Write-Host "Invoke-OptimizeMemory indisponível." -ForegroundColor Yellow }
                if (Get-Command Invoke-QuickClean     -ErrorAction SilentlyContinue) { Invoke-QuickClean     } else { Write-Host "Invoke-QuickClean indisponível."     -ForegroundColor Yellow }
                Read-Host "`nPressione ENTER para voltar"
            }
            "6" { if (Get-Command Invoke-QuickClean -ErrorAction SilentlyContinue) { Invoke-QuickClean } else { Write-Host "Invoke-QuickClean indisponível." -ForegroundColor Yellow }; Read-Host "`nPressione ENTER para voltar" }
            "7" {
                if (Get-Command Invoke-RepairSearchIndexer -ErrorAction SilentlyContinue) {
                    try { Invoke-RepairSearchIndexer -RebuildCatalogOnYesPrompt } catch { Write-Host "❌ Falha no reparo: $($_.Exception.Message)" -ForegroundColor Red }
                } else { Write-Host "Função Invoke-RepairSearchIndexer indisponível." -ForegroundColor Yellow }
                Read-Host "`nPressione ENTER para voltar"
            }
            "8" { $inFixes = $false }
            default { Write-Host "Opção inválida." -ForegroundColor Red; Start-Sleep 2 }
        }
    }
}

# =========================
# MENU PRINCIPAL
# =========================
while ($true) {
    Clear-Host
    Write-Host "=================================================" -ForegroundColor Cyan
    Write-Host "      Assistente de Diagnóstico Jarvis" -ForegroundColor White
    Write-Host ("      Data: {0}" -f (Get-Date -Format 'dd/MM/yyyy HH:mm')) -ForegroundColor DarkGray
    Write-Host "=================================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "[1] Executar Diagnóstico Completo" -ForegroundColor White
    Write-Host "[2] Visualizar Relatórios" -ForegroundColor White
    Write-Host "[3] Menu de Correções" -ForegroundColor White
    Write-Host "[4] Gerar Prompt Inteligente (IA)" -ForegroundColor White
    Write-Host "[5] Sair" -ForegroundColor White
    Write-Host "`n=================================================" -ForegroundColor Cyan

    $opcao = Read-Host "`nEscolha uma opção (1-5)"
    switch ($opcao) {
        "1" {
            Clear-Host
            Write-Host "ANÁLISE DO DIAGNÓSTICO" -ForegroundColor Cyan
            Write-Host ("Analisando sistema '{0}' em {1}" -f (hostname), (Get-Date -Format 'dd/MM/yyyy HH:mm')) -ForegroundColor White
            Write-Host ""
            try {
                & $DiagnosticScriptPath
                Show-JarvisFinalSuggestion -JsonPath $LogJsonPath
            } catch {
                Write-Host ("Falha no diagnóstico: {0}" -f $_) -ForegroundColor Red
            }
            Read-Host "`nPressione ENTER para voltar ao menu"
        }
        "2" { Show-ReportsMenu }
        "3" { Show-FixesMenu }
        "4" {
            Invoke-IntelligentPrompt -JsonPath $LogJsonPath
            Read-Host "`nPressione ENTER para voltar ao menu"
        }
        "5" {
            Write-Host ""
            Write-Host "[JARVIS]" -ForegroundColor Blue
            if (Get-Command Write-TypingFormattedText -ErrorAction SilentlyContinue) {
                Write-TypingFormattedText -Text "Encerrando operações..." -Delay 10 -ForegroundColor White -LineWidth 120
                Start-Sleep 1
                Write-TypingFormattedText -Text "Procedimentos finalizados. Permanecerei em standby até a próxima missão." -Delay 10 -ForegroundColor White -LineWidth 120
            } else {
                Write-Host "Encerrando operações..." -ForegroundColor White
                Start-Sleep 1
                Write-Host "Procedimentos finalizados. Permanecerei em standby até a próxima missão." -ForegroundColor White
            }
            Start-Sleep 1
            exit
        }
        default { Write-Host "Opção inválida." -ForegroundColor Red; Start-Sleep 2 }
    }
}
