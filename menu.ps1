# menu.ps1
# Assistente de Diagnóstico - Jarvis

# Configuração do console
$Host.UI.RawUI.WindowTitle = "Assistente de Diagnóstico - Jarvis"
$Host.UI.RawUI.BufferSize = New-Object System.Management.Automation.Host.Size(120, 9999)
$Host.UI.RawUI.WindowSize = New-Object System.Management.Automation.Host.Size(120, 40)

# Caminhos
$currentScriptPath = Split-Path -Parent -Path $MyInvocation.MyCommand.Definition
$diagnosticScriptPath = Join-Path -Path $currentScriptPath -ChildPath "diagnostic-v2.ps1"
$logPath = Join-Path -Path $currentScriptPath -ChildPath "output\status-maquina.json"
$interpretationModulePath = Join-Path -Path $currentScriptPath -ChildPath "modulos\interpretation.psm1"
$maintenanceModulePath = Join-Path -Path $currentScriptPath -ChildPath "modulos\maintenance.psm1"
$promptModulePath = Join-Path -Path $currentScriptPath -ChildPath "modulos\promptbuilder.psm1"


# Importa módulos
try {
    Import-Module -Name $interpretationModulePath -Force
    Import-Module -Name $maintenanceModulePath -Force
    Import-Module -Name $promptModulePath -Force
}
catch {
    Write-Error "Falha ao carregar os módulos: $_" -ForegroundColor Red
    exit
}

function Invoke-IntelligentPrompt {
    param([string]$JsonPath)

    Add-Type -AssemblyName Microsoft.VisualBasic
    Write-Host "🧠 Gerando Prompt Inteligente..." -ForegroundColor Cyan

    if (-not (Test-Path $JsonPath)) {
        Write-Host "[ERRO] Arquivo JSON não encontrado em: $JsonPath" -ForegroundColor Red
        return
    }

    try {
        $message = "Informe o sintoma indicado pelo usuário." + [Environment]::NewLine +
                    "Exemplo: Lentidão ao iniciar, falha na internet, travamentos..."
        $UserSymptom = [Microsoft.VisualBasic.Interaction]::InputBox(
            $message,
            "Jarvis - Sintoma do Usuário",
            ""
        )
        if ([string]::IsNullOrWhiteSpace($UserSymptom)) {
            Write-Host "`n❌ Operação cancelada pelo usuário. Nenhum prompt gerado." -ForegroundColor Yellow
            return
        }

        $data = Get-Content $JsonPath -Raw | ConvertFrom-Json

        # SEMPRE array (nunca null)
        $logs = @()
        if ($null -ne $data.EventosCriticos) {
            if ($data.EventosCriticos.Events) {
                $logs = @($data.EventosCriticos.Events)
            } elseif ($data.EventosCriticos.EventosRelevantes) {
                $logs = @($data.EventosCriticos.EventosRelevantes)
            } elseif ($data.EventosCriticos.EventosCriticos) {
                $logs = @($data.EventosCriticos.EventosCriticos)
            }
        }

        # compatibilidade: aceita -AllLogs (preferido) ou -Logs (alias)
        $prompt = Build-IntelligentPrompt -AllLogs $logs -UserSymptom $UserSymptom -TargetTokenBudget 2200

        Set-Clipboard -Value $prompt
        Write-Host "✅ Prompt copiado para a área de transferência!" -ForegroundColor Green

        $url = "https://chat.openai.com/?model=gpt-5"
        try { Start-Process $url -ErrorAction Stop }
        catch {
            if (Get-Command "msedge.exe"   -ErrorAction SilentlyContinue) { Start-Process "msedge.exe" $url }
            elseif (Get-Command "chrome.exe"  -ErrorAction SilentlyContinue) { Start-Process "chrome.exe" $url }
            elseif (Get-Command "firefox.exe" -ErrorAction SilentlyContinue) { Start-Process "firefox.exe" $url }
            else { Write-Host "⚠️ Abra manualmente: $url" -ForegroundColor Yellow }
        }

        Write-Host "`n🌐 ChatGPT aberto. Cole o prompt e gere o relatório técnico." -ForegroundColor Cyan
    }
    catch {
        Write-Host "[ERRO] Falha ao gerar o prompt inteligente: $($_.Exception.Message)" -ForegroundColor Red
    }
}

# Função para mostrar sugestão do Jarvis
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

# --- MENU PRINCIPAL ---
while ($true) {
    Clear-Host
    Write-Host "=================================================" -ForegroundColor Cyan
    Write-Host "      Assistente de Diagnóstico " -NoNewline -ForegroundColor White
    Write-Host "Jarvis" -ForegroundColor Blue
    Write-Host "      Data: $(Get-Date -Format 'dd/MM/yyyy HH:mm')" -ForegroundColor DarkGray
    Write-Host "=================================================" -ForegroundColor Cyan
    Write-Host "`n"
    Write-Host "[1] Executar Diagnóstico Completo" -ForegroundColor White
    Write-Host "[2] Visualizar Relatórios" -ForegroundColor White
    Write-Host "[3] Menu de Correções" -ForegroundColor White
    Write-Host "[4] 🧠 Gerar Prompt Inteligente (IA)" -ForegroundColor White
    Write-Host "[5] Sair" -ForegroundColor White
    Write-Host "`n=================================================" -ForegroundColor Cyan

    $opcao = Read-Host "`nEscolha uma opção (1-5)"

    switch ($opcao) {
        "1" {
            Clear-Host
            Write-Host "ANÁLISE DO DIAGNÓSTICO" -ForegroundColor Cyan
            Write-Host "Analisando sistema '$(hostname)' em $(Get-Date -Format 'dd/MM/yyyy HH:mm')" -ForegroundColor White
            Write-Host "`n"
            try { & $diagnosticScriptPath; Show-JarvisFinalSuggestion -JsonPath $logPath }
            catch { Write-Error "Falha no diagnóstico: $_" -ForegroundColor Red }
            Read-Host "`nPressione ENTER para voltar ao menu"
        }
        "2" {
            # submenu de relatórios
            $inSubmenuRelatorios = $true
            while ($inSubmenuRelatorios) {
                Clear-Host
                Write-Host "=================================================" -ForegroundColor Cyan
                Write-Host "      Visualizar Relatórios" -ForegroundColor Cyan
                Write-Host "=================================================" -ForegroundColor Cyan
                Write-Host "`n[1] Ver Relatório Formatado" -ForegroundColor White
                Write-Host "[2] Ver JSON Completo" -ForegroundColor White
                Write-Host "[3] Voltar" -ForegroundColor White
                Write-Host "`n=================================================" -ForegroundColor Cyan
                $submenuOpcao = Read-Host "`nEscolha uma opção (1-3)"
                switch ($submenuOpcao) {
                    "1" { Start-DiagnosticAnalysis -JsonPath $logPath; Read-Host "`nPressione ENTER para continuar" }
                    "2" { Clear-Host; Get-Content $logPath -Raw | Write-Host -ForegroundColor Gray; Read-Host "`nPressione ENTER para continuar" }
                    "3" { $inSubmenuRelatorios = $false }
                    default { Write-Host "Opção inválida." -ForegroundColor Red; Start-Sleep 2 }
                }
            }
        }
        "3" {
            # submenu de correções
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
