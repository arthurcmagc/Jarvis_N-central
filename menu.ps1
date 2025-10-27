# menu.ps1
# Assistente de Diagnóstico - Jarvis

# =========================
# Configuração do console
# =========================
try {
    $Host.UI.RawUI.WindowTitle = "Assistente de Diagnóstico - Jarvis"
    $Host.UI.RawUI.BufferSize  = New-Object System.Management.Automation.Host.Size(120, 9999)
    $Host.UI.RawUI.WindowSize  = New-Object System.Management.Automation.Host.Size(120, 40)
} catch {}

# =========================
# Caminhos
# =========================
$currentScriptPath    = Split-Path -Parent -Path $MyInvocation.MyCommand.Definition
$diagnosticScriptPath = Join-Path -Path $currentScriptPath -ChildPath "diagnostic-v2.ps1"
$logPath              = Join-Path -Path $currentScriptPath -ChildPath "output\status-maquina.json"
$interpretationModulePath = Join-Path -Path $currentScriptPath -ChildPath "modulos\interpretation.psm1"
$maintenanceModulePath    = Join-Path -Path $currentScriptPath -ChildPath "modulos\maintenance.psm1"
$promptModulePath         = Join-Path -Path $currentScriptPath -ChildPath "modulos\promptbuilder.psm1"

# =========================
# Importa módulos
# =========================
try {
    Import-Module -Name $interpretationModulePath -Force
    Import-Module -Name $maintenanceModulePath   -Force
    Import-Module -Name $promptModulePath        -Force
}
catch {
    Write-Host "Falha ao carregar os módulos: $($_.Exception.Message)" -ForegroundColor Red
    exit
}

# =========================
# Saída fixa de fallback (TXT)
# =========================
$script:FixedOutputDir = 'C:\HealthCheck\Assistente Jarvis - Hype\Jarvis_N-central-main\output'

function Save-PromptToFixedPath {
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
# Estado do Prompt (para fallback/visualização)
# =========================
$script:LastPrompt      = $null
$script:LastPromptPath  = $null

# =========================
# Helpers Sessão/Entrada
# =========================
function Test-InteractiveSession {
    # True quando há desktop interativo (PowerShell local). False no System Shell/Command Prompt do N-central.
    try {
        return [Environment]::UserInteractive -and ($Host.UI.RawUI.KeyAvailable -or $Host.Name -notlike "*ServerRemoteHost*")
    } catch { return $false }
}

function Get-UserSymptom {
    param([string]$Title = "Jarvis - Sintoma do Usuário")

    # 1) Tenta popup se houver desktop interativo
    if (Test-InteractiveSession) {
        try {
            Add-Type -AssemblyName Microsoft.VisualBasic -ErrorAction Stop
            $message = "Informe brevemente o sintoma (ex.: lentidão ao iniciar, falha na internet, travamentos...)."
            $val = [Microsoft.VisualBasic.Interaction]::InputBox($message, $Title, "")
            if ($null -ne $val -and $val.Trim().Length -gt 0) { return $val }
        } catch {
            # cai pro modo terminal
        }
    }

    # 2) Fallback: solicita no terminal (compatível com System Shell/Command Prompt)
    Write-Host ""
    Write-Host "[IA] Digite o sintoma do usuário e pressione ENTER:" -ForegroundColor Cyan
    $v = Read-Host "Sintoma"
    if ([string]::IsNullOrWhiteSpace($v)) { return $null }
    return $v.Trim()
}

# =========================
# Clipboard resiliente (Approved Verb)
# =========================
function Set-ClipboardSafe {
    param([Parameter(Mandatory=$true)][string]$Text)

    # Tenta Set-Clipboard direto
    try {
        Set-Clipboard -Value $Text -ErrorAction Stop
        return @{ Copied=$true; Method="Set-Clipboard"; Path=$null; Error=$null }
    } catch {
        $err1 = $_.Exception.Message
    }

    # Tenta via sessão STA usando arquivo temporário
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

    # Tenta clip.exe com arquivo (mais compatível)
    try {
        cmd.exe /c "type `"$tmp`" | clip" | Out-Null
        try { Remove-Item $tmp -Force -ErrorAction SilentlyContinue } catch {}
        return @{ Copied=$true; Method="clip.exe"; Path=$null; Error=$null }
    } catch {
        $err3 = $_.Exception.Message
    }

    # Fallback final: mantém o arquivo temporário para o usuário copiar manualmente
    return @{ Copied=$false; Method="file"; Path=$tmp; Error=("Set-Clipboard: $err1; STA: $err2; clip.exe: $err3") }
}

# =========================
# Prompt Inteligente
# =========================
function Invoke-IntelligentPrompt {
    param([string]$JsonPath)

    Write-Host "Gerando Prompt Inteligente..." -ForegroundColor Cyan

    # Mensagem de cenário
    $isInteractive = Test-InteractiveSession
    if ($isInteractive) {
        Write-Host "[Cenário detectado] PowerShell com acesso à área de trabalho do usuário." -ForegroundColor Green
    } else {
        Write-Host "[Cenário detectado] Sessão sem desktop interativo (System Shell/Command Prompt)." -ForegroundColor Yellow
        Write-Host "  - Clipboard e abertura automática do navegador podem não funcionar aqui." -ForegroundColor DarkYellow
        Write-Host "  - O prompt SERÁ salvo em TXT no caminho persistente para você copiar manualmente." -ForegroundColor DarkYellow
        Write-Host "    Caminho: $script:FixedOutputDir" -ForegroundColor DarkYellow
        Write-Host ""
    }

    if (-not (Test-Path $JsonPath)) {
        Write-Host "[ERRO] Arquivo JSON não encontrado em: $JsonPath" -ForegroundColor Red
        Write-Host "Execute primeiro a opção [1] 'Executar Diagnóstico Completo'." -ForegroundColor Yellow
        return
    }

    try {
        $UserSymptom = Get-UserSymptom -Title "Jarvis - Sintoma do Usuário"
        if ([string]::IsNullOrWhiteSpace($UserSymptom)) {
            Write-Host "❌ Operação cancelada. Nenhum sintoma informado." -ForegroundColor Yellow
            return
        }

        $data = Get-Content $JsonPath -Raw | ConvertFrom-Json

        # Seleciona poucos logs (amostra). Nunca deixe $logs = $null.
        $logs = @()
        if ($null -ne $data.EventosCriticos) {
            if     ($data.EventosCriticos.Events)            { $logs = @($data.EventosCriticos.Events) }
            elseif ($data.EventosCriticos.EventosRelevantes) { $logs = @($data.EventosCriticos.EventosRelevantes) }
            elseif ($data.EventosCriticos.EventosCriticos)   { $logs = @($data.EventosCriticos.EventosCriticos) }
        }

        # --- Fallback quando não há eventos: criar "mini-resumo técnico" ---
        if (-not $logs -or $logs.Count -eq 0) {
            $mini = @()

            # Hardware
            try {
                if ($data.Hardware) {
                    if ($data.Hardware.RAM) {
                        $mini += ("RAM: {0}% de uso (Total {1} GB)" -f $data.Hardware.RAM.UsedPercent, $data.Hardware.RAM.TotalGB)
                    }
                    if ($data.Hardware.Disks) {
                        foreach ($d in $data.Hardware.Disks) {
                            if ($d.DeviceID -and ($null -ne $d.FreeGB) -and ($null -ne $d.FreePercent)) {

                                $tipo = if ($d.Tipo) { $d.Tipo } else { 'N/A' }
                                $mini += ("Disco {0}: {1} GB livres ({2}%), Tipo: {3}" -f $d.DeviceID, $d.FreeGB, $d.FreePercent, $tipo)
                            }
                        }
                    }
                }
            } catch {}

            # Rede
            try {
                if ($data.Rede) {
                    $net = 'N/A'
                    if ($data.Rede.HasInternetConnection -eq $true) { $net = 'Conectado' }
                    elseif ($data.Rede.HasInternetConnection -eq $false) { $net = 'Desconectado' }
                    $mini += ("Internet: {0}" -f $net)

                    if ($data.Rede.Interfaces -and $data.Rede.Interfaces.Count -gt 0) {
                        $i = $data.Rede.Interfaces[0]
                        $iName = if ($i.Name) { $i.Name } else { 'N/A' }
                        $iStatus = if ($i.Status) { $i.Status } else { 'N/A' }
                        $iIPv4 = if ($i.IPv4) { $i.IPv4 } else { 'N/A' }
                        $iGw = if ($i.Gateway) { $i.Gateway } else { 'N/A' }
                        $mini += ("IF: {0} ({1}) IPv4: {2} GW: {3}" -f $iName, $iStatus, $iIPv4, $iGw)
                    }

                    if ($data.Rede.DNS) {
                        $dnsFlat = @($data.Rede.DNS) | ForEach-Object { "$_" } | Where-Object { $_ -and $_.Trim().Length -gt 0 }
                        if ($dnsFlat.Count -gt 0) { $mini += ("DNS: {0}" -f ($dnsFlat -join ', ')) }
                    }

                    if ($data.Rede.Latency) {
                        foreach ($l in $data.Rede.Latency) {
                            $avg = if ($null -ne $l.AvgMs) { ("{0} ms" -f $l.AvgMs) } else { "N/D" }
                            $med = if ($null -ne $l.MedMs) { ("{0} ms" -f $l.MedMs) } else { "N/D" }
                            $loss = if ($null -ne $l.LossPct) { $l.LossPct } else { "N/D" }
                            $mini += ("Ping {0}: avg {1} | med {2} | perda {3}%" -f $l.Host, $avg, $med, $loss)
                        }
                    }
                }
            } catch {}

            # Eventos (contagem)
            try {
                if ($data.EventosCriticos) {
                    $tot = $data.EventosCriticos.TotalEventos
                    $r   = if ($data.EventosCriticos.EventosRelevantes) { $data.EventosCriticos.EventosRelevantes.Count } else { 0 }
                    $e   = if ($data.EventosCriticos.EventosCriticos)   { $data.EventosCriticos.EventosCriticos.Count } else { 0 }
                    $mini += ("Eventos: total {0} | relevantes {1} | erros {2}" -f $tot, $r, $e)
                }
            } catch {}

            # Serviços críticos
            try {
                if ($data.Servicos -and $data.Servicos.CriticalServicesNotRunning -and $data.Servicos.CriticalServicesNotRunning.Count -gt 0) {
                    $names = $data.Servicos.CriticalServicesNotRunning | ForEach-Object { $_.Name }
                    if ($names -and $names.Count -gt 0) {
                        $mini += ("Serviços parados: {0}" -f ($names -join ', '))
                    }
                }
            } catch {}

            if ($mini.Count -eq 0) { $mini += "Sem eventos e sem dados adicionais aproveitáveis no JSON." }
            $logs = $mini
        }

        # Usa o módulo promptbuilder
        $prompt = Build-IntelligentPrompt -AllLogs $logs -UserSymptom $UserSymptom -TargetTokenBudget 2200

        # Guarda para submenu de relatórios
        $script:LastPrompt = $prompt
        $script:LastPromptPath = $null

        # Cenário 1/2 (não interativo): SEMPRE salvar TXT persistente
        $fixedPath = $null
        if (-not $isInteractive) {
            $fixedPath = Save-PromptToFixedPath -Text $prompt
            if ($fixedPath) {
                $script:LastPromptPath = $fixedPath
                Write-Host "📄 Prompt salvo para cópia manual:" -ForegroundColor Yellow
                Write-Host "  $fixedPath" -ForegroundColor Cyan
            } else {
                Write-Host "Falha ao salvar no caminho persistente." -ForegroundColor Red
            }
        }

        # Tenta copiar para clipboard (com todos os fallbacks) — útil no cenário 3
        $copy = Set-ClipboardSafe -Text $prompt

        if ($copy.Copied -and $isInteractive) {
            Write-Host "✅ Prompt copiado para a área de transferência! ($($copy.Method))" -ForegroundColor Green
        } elseif ($isInteractive -and -not $copy.Copied) {
            Write-Host "⚠️ Não foi possível copiar automaticamente para o clipboard." -ForegroundColor Yellow

            if ($copy.Path) {
                $script:LastPromptPath = $copy.Path
                Write-Host "O prompt foi salvo temporariamente em:" -ForegroundColor Yellow
                Write-Host "  $($copy.Path)" -ForegroundColor Cyan
            }

            if (-not $fixedPath) {
                $fixedPath = Save-PromptToFixedPath -Text $prompt
                if ($fixedPath) {
                    $script:LastPromptPath = $fixedPath
                    Write-Host "Cópia persistente gravada em:" -ForegroundColor Yellow
                    Write-Host "  $fixedPath" -ForegroundColor Cyan
                }
            }
        }

        # Link do ChatGPT
        $url = "https://chat.openai.com/?model=gpt-5"
        $opened = $false

        if ($isInteractive) {
            try {
                Start-Process $url -ErrorAction Stop
                $opened = $true
            } catch {
                if     (Get-Command "msedge.exe"  -ErrorAction SilentlyContinue) { Start-Process "msedge.exe"  $url; $opened = $true }
                elseif (Get-Command "chrome.exe"  -ErrorAction SilentlyContinue) { Start-Process "chrome.exe"  $url; $opened = $true }
                elseif (Get-Command "firefox.exe" -ErrorAction SilentlyContinue) { Start-Process "firefox.exe" $url; $opened = $true }
            }
        }

        if (-not $opened) {
            Write-Host ""
            if ($isInteractive -and $copy.Copied) {
                Write-Host "Abra o link no navegador e cole o conteúdo do seu clipboard (CTRL+V):" -ForegroundColor Yellow
            } elseif (-not $isInteractive) {
                Write-Host "Abra o link no navegador e cole o conteúdo do arquivo TXT salvo no caminho indicado acima." -ForegroundColor Yellow
                Write-Host "Ex.: Abra o arquivo, CTRL+A / CTRL+C, e cole no ChatGPT." -ForegroundColor DarkYellow
            } else {
                Write-Host "Abra o link no navegador e cole o conteúdo do arquivo/prompt indicado acima." -ForegroundColor Yellow
            }
            Write-Host "  $url" -ForegroundColor Cyan
            Write-Host ""
            Write-Host "Dica: Você também pode visualizar o texto do prompt em:" -ForegroundColor DarkGray
            Write-Host "  Menu [2] > Ver Prompt Inteligente (texto)" -ForegroundColor DarkGray
        } else {
            Write-Host "`nCole (CTRL+V) no ChatGPT e gere o relatório técnico." -ForegroundColor Cyan
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
    param([string]$JsonPath)
    if (-not (Test-Path $JsonPath)) { return }
    try {
        $data = Get-Content $JsonPath -Raw | ConvertFrom-Json
        $windowWidth = $Host.UI.RawUI.WindowSize.Width
        Write-Host "`n" + ("=" * $windowWidth) -ForegroundColor Cyan
        $manufacturer = $data.Fabricante.Manufacturer
        if ($manufacturer) {
            Write-Host "[JARVIS] " -NoNewline -ForegroundColor Blue
            $suggestion = Get-ManufacturerSoftwareSuggestion -Manufacturer $manufacturer
            Write-TypingFormattedText -Text $suggestion -Delay 10 -ForegroundColor White -LineWidth ($windowWidth-4) -Indent "          "
        }
        else {
            Write-Host "[JARVIS] Sugestão de Software do Fabricante:" -ForegroundColor Blue
            Write-Host "Não foi possível identificar o fabricante." -ForegroundColor Yellow
        }
        Write-Host ("=" * $windowWidth) -ForegroundColor Cyan
    }
    catch { Write-Host "[ERRO] Falha ao exibir a sugestão do Jarvis: $($_.Exception.Message)" -ForegroundColor Red }
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
# MENU PRINCIPAL
# =========================
while ($true) {
    Clear-Host
    Write-Host "=================================================" -ForegroundColor Cyan
    Write-Host "      Assistente de Diagnóstico Jarvis" -ForegroundColor White
    Write-Host "      Data: $(Get-Date -Format 'dd/MM/yyyy HH:mm')" -ForegroundColor DarkGray
    Write-Host "=================================================" -ForegroundColor Cyan
    Write-Host "`n"
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
            Write-Host "Analisando sistema '$(hostname)' em $(Get-Date -Format 'dd/MM/yyyy HH:mm')" -ForegroundColor White
            Write-Host "`n"
            try {
                & $diagnosticScriptPath
                Show-JarvisFinalSuggestion -JsonPath $logPath
            }
            catch {
                Write-Host "Falha no diagnóstico: $($_.Exception.Message)" -ForegroundColor Red
            }
            Read-Host "`nPressione ENTER para voltar ao menu"
        }
        "2" {
            # Submenu de relatórios
            $inSubmenuRelatorios = $true
            while ($inSubmenuRelatorios) {
                Clear-Host
                Write-Host "=================================================" -ForegroundColor Cyan
                Write-Host "      Visualizar Relatórios" -ForegroundColor Cyan
                Write-Host "=================================================" -ForegroundColor Cyan
                Write-Host "`n[1] Ver Relatório Formatado" -ForegroundColor White
                Write-Host "[2] Ver JSON Completo" -ForegroundColor White
                Write-Host "[3] Ver Prompt Inteligente (texto)" -ForegroundColor White
                Write-Host "[4] Voltar" -ForegroundColor White
                Write-Host "`n=================================================" -ForegroundColor Cyan
                $submenuOpcao = Read-Host "`nEscolha uma opção (1-4)"
                switch ($submenuOpcao) {
                    "1" {
                        if (Test-Path $logPath) {
                            Start-DiagnosticAnalysis -JsonPath $logPath
                        } else {
                            Write-Host "Arquivo não encontrado: $logPath" -ForegroundColor Yellow
                        }
                        Read-Host "`nPressione ENTER para continuar"
                    }
                    "2" {
                        Clear-Host
                        if (Test-Path $logPath) {
                            Get-Content $logPath -Raw | Write-Host -ForegroundColor Gray
                        } else {
                            Write-Host "Arquivo não encontrado: $logPath" -ForegroundColor Yellow
                        }
                        Read-Host "`nPressione ENTER para continuar"
                    }
                    "3" {
                        Clear-Host
                        Show-LastPromptText
                        Read-Host "`nPressione ENTER para continuar"
                    }
                    "4" { $inSubmenuRelatorios = $false }
                    default { Write-Host "Opção inválida." -ForegroundColor Red; Start-Sleep 2 }
                }
            }
        }
        "3" {
            # Submenu de correções (unificação futura; por ora mantém as opções)
            $inSubmenuCorrecoes = $true
            while ($inSubmenuCorrecoes) {
                Clear-Host
                Write-Host "=================================================" -ForegroundColor Cyan
                Write-Host "      Executar Correções Automáticas" -ForegroundColor Cyan
                Write-Host "=================================================" -ForegroundColor Cyan
                Write-Host "`n[1] Executar SFC" -ForegroundColor White
                Write-Host "[2] Executar DISM" -ForegroundColor White
                Write-Host "[3] Correções de Rede" -ForegroundColor White
                Write-Host "[4] Limpeza Rápida" -ForegroundColor White
                Write-Host "[5] Limpeza Completa" -ForegroundColor White
                Write-Host "[6] Otimização Inteligente (RAM + Limpeza)" -ForegroundColor White
                Write-Host "[7] Voltar" -ForegroundColor White
                Write-Host "`n=================================================" -ForegroundColor Cyan
                $correcoesOpcao = Read-Host "`nEscolha uma opção (1-7)"
                switch ($correcoesOpcao) {
                    "1" { Invoke-SFC; Read-Host "`nPressione ENTER para voltar" }
                    "2" { Invoke-DISM; Read-Host "`nPressione ENTER para voltar" }
                    "3" { Invoke-NetworkCorrections; Read-Host "`nPressione ENTER para voltar" }
                    "4" { Invoke-QuickClean; Read-Host "`nPressione ENTER para voltar" }
                    "5" { Invoke-FullClean; Read-Host "`nPressione ENTER para voltar" }
                    "6" { Invoke-OptimizeMemory; Invoke-QuickClean; Read-Host "`nPressione ENTER para voltar" }
                    "7" { $inSubmenuCorrecoes = $false }
                    default { Write-Host "Opção inválida." -ForegroundColor Red; Start-Sleep 2 }
                }
            }
        }
        "4" {
            Invoke-IntelligentPrompt -JsonPath $logPath
            Read-Host "`nPressione ENTER para voltar ao menu"
        }
        "5" {
            Write-Host "`n[JARVIS]" -ForegroundColor Blue
            Write-TypingFormattedText -Text "Encerrando operações..." -Delay 10 -ForegroundColor White -LineWidth 120
            Start-Sleep 1
            Write-TypingFormattedText -Text "Procedimentos finalizados. Permanecerei em standby até a próxima missão." -Delay 10 -ForegroundColor White -LineWidth 120
            Start-Sleep 1
            exit
        }
        default { Write-Host "Opção inválida." -ForegroundColor Red; Start-Sleep 2 }
    }
}
