# menu.ps1
#
# Script principal para o Assistente de Diagnóstico - Jarvis

# Força o uso do console do PowerShell para exibição colorida e correta.
$Host.UI.RawUI.WindowTitle = "Assistente de Diagnóstico - Jarvis"
$Host.UI.RawUI.BufferSize = New-Object System.Management.Automation.Host.Size(120, 9999)
$Host.UI.RawUI.WindowSize = New-Object System.Management.Automation.Host.Size(120, 40)

# Define os caminhos dos scripts e módulos
$currentScriptPath = Split-Path -Parent -Path $MyInvocation.MyCommand.Definition
$diagnosticScriptPath = Join-Path -Path $currentScriptPath -ChildPath "diagnostic-v2.ps1"
$logPath = Join-Path -Path $currentScriptPath -ChildPath "output\status-maquina.json"
$interpretationModulePath = Join-Path -Path $currentScriptPath -ChildPath "modulos\interpretation.psm1"
$maintenanceModulePath = Join-Path -Path $currentScriptPath -ChildPath "modulos\maintenance.psm1"

# Importa os módulos necessários
try {
    Import-Module -Name $interpretationModulePath -Force
    Import-Module -Name $maintenanceModulePath -Force
}
catch {
    Write-Error "Falha ao carregar os módulos de diagnóstico: $_" -ForegroundColor Red
    exit
}

# Inicia as correções automáticas
Function Start-Fixes {
    # Chama a função de correção do módulo de manutenção.
    try {
        Invoke-Corrections
    }
    catch {
        Write-Error "Falha na execução das correções: $_" -ForegroundColor Red
    }
}

function Show-JarvisFinalSuggestion {
    param(
        [Parameter(Mandatory=$true)]
        [string]$JsonPath
    )
    try {
        if (-not (Test-Path $JsonPath)) {
            Write-Host "`n[ERRO] Arquivo de diagnóstico não encontrado para a sugestão." -ForegroundColor Red
            return
        }
        $data = Get-Content $JsonPath -Raw | ConvertFrom-Json
        $windowWidth = $Host.UI.RawUI.WindowSize.Width
        $line = "=" * $windowWidth
        Write-Host "`n$line" -ForegroundColor Cyan
        
        $manufacturer = $data.Fabricante.Manufacturer
        if ($manufacturer) {
            # Escreve a tag [JARVIS] em azul e o restante da mensagem em branco.
            Write-Host "[JARVIS] " -NoNewline -ForegroundColor Blue
            $suggestion = Get-ManufacturerSoftwareSuggestion -Manufacturer $manufacturer
            Write-TypingFormattedText -Text $suggestion -Delay 10 -ForegroundColor "White" -LineWidth ($windowWidth - 4) -Indent "          "
        } else {
            Write-Host "[JARVIS] Sugestão de Software do Fabricante:" -ForegroundColor Blue
            Write-Host "Não foi possível identificar o fabricante da máquina para recomendações de software." -ForegroundColor Yellow
        }
        Write-Host "`n$line" -ForegroundColor Cyan
    }
    catch {
        Write-Host "`n[ERRO] Falha ao exibir a sugestão do Jarvis: $($_.Exception.Message)" -ForegroundColor Red
    }
}

# Menu principal
while ($true) {
    # Adiciona o tratamento para a interrupção por Ctrl+C
    trap [System.Management.Automation.Host.HostException] {
        Write-Host "`nOperação cancelada pelo usuário (Ctrl+C). Retornando ao menu principal..." -ForegroundColor Yellow
        Start-Sleep -Seconds 2
        continue # Retorna ao início do loop 'while'
    }

    Clear-Host
    Write-Host "=================================================" -ForegroundColor Cyan
    Write-Host "      Assistente de Diagnóstico " -NoNewline -ForegroundColor White
    Write-Host "Jarvis" -ForegroundColor Blue
    Write-Host "      Data: $(Get-Date -Format 'dd/MM/yyyy HH:mm')" -ForegroundColor DarkGray
    Write-Host "=================================================" -ForegroundColor Cyan
    Write-Host "`n"
    Write-Host "[1] Executar Diagnóstico Completo" -ForegroundColor White
    Write-Host "[2] Visualizar Relatórios" -ForegroundColor White
    Write-Host "[3] Executar Correções Automáticas" -ForegroundColor White
    Write-Host "[4] Sair" -ForegroundColor White
    Write-Host "`n=================================================" -ForegroundColor Cyan

    $opcao = Read-Host "`nEscolha uma opção (1-4)"

    switch ($opcao) {
        "1" {
            Clear-Host
            # AJUSTE: Remove a indentação para alinhar o cabeçalho à esquerda
            # AJUSTE: Formato da data para ser mais legível
            $currentDate = Get-Date -Format 'dd/MM/yyyy HH:mm'
            Write-Host "ANÁLISE DO DIAGNÓSTICO" -ForegroundColor Cyan
            Write-Host "Análise do sistema '$(hostname)' em $currentDate" -ForegroundColor White
            Write-Host "`n"
            
            # Chama o script de orquestração 'diagnostic-v2.ps1'
            try {
                & $diagnosticScriptPath
                # Exibe a sugestão do Jarvis aqui, como um resumo rápido.
                Show-JarvisFinalSuggestion -JsonPath $logPath
            }
            catch {
                Write-Error "Falha na execução do diagnóstico: $_" -ForegroundColor Red
            }
            Read-Host "`nPressione ENTER para voltar ao menu"
        }
        "2" {
            # Submenu de visualização de relatórios
            $inSubmenuRelatorios = $true
            while ($inSubmenuRelatorios) {
                Clear-Host
                Write-Host "=================================================" -ForegroundColor Cyan
                Write-Host "      Visualizar Relatórios" -ForegroundColor Cyan
                Write-Host "=================================================" -ForegroundColor Cyan
                Write-Host "`n"
                Write-Host "[1] Ver Relatório Formatado" -ForegroundColor White
                Write-Host "[2] Ver JSON Completo" -ForegroundColor White
                Write-Host "[3] Voltar" -ForegroundColor White
                Write-Host "`n=================================================" -ForegroundColor Cyan
                $submenuOpcao = Read-Host "`nEscolha uma opção (1-3)"
                
                switch ($submenuOpcao) {
                    "1" {
                        try {
                            # Exibe o relatório detalhado apenas aqui.
                            Start-DiagnosticAnalysis -JsonPath $logPath
                        }
                        catch {
                            Write-Error "Falha ao analisar o relatório: $_" -ForegroundColor Red
                        }
                        Read-Host "`nPressione ENTER para continuar"
                    }
                    "2" {
                        try {
                            $jsonContent = Get-Content $logPath -Raw
                            Clear-Host
                            Write-Host $jsonContent -ForegroundColor Gray
                        }
                        catch {
                            Write-Error "Falha ao ler o arquivo JSON: $_" -ForegroundColor Red
                        }
                        Read-Host "`nPressione ENTER para continuar"
                    }
                    "3" {
                        $inSubmenuRelatorios = $false
                    }
                    default {
                        Write-Host "Opção inválida. Tente novamente." -ForegroundColor Red
                        Start-Sleep -Seconds 2
                    }
                }
            }
        }
        "3" {
            # Novo submenu de correções
            $inSubmenuCorrecoes = $true
            while ($inSubmenuCorrecoes) {
                Clear-Host
                Write-Host "=================================================" -ForegroundColor Cyan
                Write-Host "      Executar Correções Automáticas" -ForegroundColor Cyan
                Write-Host "=================================================" -ForegroundColor Cyan
                Write-Host "`n"
                Write-Host "[1] Executar SFC (System File Checker)" -ForegroundColor White
                Write-Host "[2] Executar DISM (Deployment Image Servicing and Management)" -ForegroundColor White
                # AJUSTE: Descrição da opção corrigida com capitalização
                Write-Host "[3] Executar Correções de Rede Imediatas" -NoNewline -ForegroundColor White
                Write-Host " (Sequência de Comandos para Limpeza de Serviços de Rede)" -ForegroundColor DarkGray
                Write-Host "[4] Voltar" -ForegroundColor White
                Write-Host "`n=================================================" -ForegroundColor Cyan
                $correcoesOpcao = Read-Host "`nEscolha uma opção (1-4)"

                switch ($correcoesOpcao) {
                    "1" {
                        Invoke-SFC
                        Read-Host "`nPressione ENTER para continuar"
                    }
                    "2" {
                        Invoke-DISM
                        Read-Host "`nPressione ENTER para continuar"
                    }
                    "3" {
                        Invoke-NetworkCorrections
                        Read-Host "`nPressione ENTER para continuar"
                    }
                    "4" {
                        $inSubmenuCorrecoes = $false
                    }
                    default {
                        Write-Host "Opção inválida. Tente novamente." -ForegroundColor Red
                        Start-Sleep -Seconds 2
                    }
                }
            }
        }
        "4" {
            # AJUSTE: Corrigido o encerramento para não quebrar a linha
            Write-Host "`n"
            Write-Host "[JARVIS]" -ForegroundColor Blue
            # Adiciona um valor alto para a largura da linha, forçando o texto a não quebrar.
            Write-TypingFormattedText -Text "Encerrando operações..." -Delay 10 -ForegroundColor White -LineWidth 120
            Start-Sleep -Seconds 1
            Write-TypingFormattedText -Text "Procedimentos finalizados. Permanecerei em standby até a próxima missão." -Delay 10 -ForegroundColor White -LineWidth 120
            Start-Sleep -Seconds 1
            exit
        }
        default {
            Write-Host "Opção inválida. Tente novamente." -ForegroundColor Red
            Start-Sleep -Seconds 2
        }
    }
}