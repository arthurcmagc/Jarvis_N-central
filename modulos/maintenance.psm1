# maintenance.psm1
# Módulo com funções de manutenção e correção do sistema.

# Função de correção combinada, pode ser chamada por automação
function Invoke-Corrections {
    Write-Host "Iniciando rotina de correções completas..." -ForegroundColor Yellow
    Invoke-SFC
    Write-Host "--------------------" -ForegroundColor DarkGray
    Invoke-DISM
    Write-Host "--------------------" -ForegroundColor DarkGray
    Invoke-NetworkCorrections
    Write-Host "Rotina de correções completa." -ForegroundColor Green
}

# Função para executar o System File Checker
function Invoke-SFC {
    Write-Host "Iniciando SFC (System File Checker)..." -ForegroundColor Green
    try {
        sfc /scannow
        Write-Host "SFC concluído. Verifique o resultado acima." -ForegroundColor Yellow
    }
    catch {
        Write-Error "Erro ao executar SFC: $_" -ForegroundColor Red
    }
}

# Função para executar o DISM
function Invoke-DISM {
    Write-Host "Iniciando DISM (Deployment Image Servicing and Management)..." -ForegroundColor Green
    Write-Host "Isso pode demorar alguns minutos. Por favor, aguarde." -ForegroundColor DarkGray
    try {
        Dism /Online /Cleanup-Image /RestoreHealth
        Write-Host "DISM concluído. Verifique o resultado acima." -ForegroundColor Yellow
    }
    catch {
        Write-Error "Erro ao executar DISM: $_" -ForegroundColor Red
    }
}

# NOVA FUNÇÃO: Executa um conjunto de correções de rede comuns
function Invoke-NetworkCorrections {
    Write-Host "Iniciando correções de rede imediatas..." -ForegroundColor Green
    Write-Host "-> Limpando cache DNS..." -ForegroundColor DarkGray
    ipconfig /flushdns
    Write-Host "-> Resetando a pilha de IP..." -ForegroundColor DarkGray
    netsh int ip reset
    Write-Host "-> Resetando o catálogo Winsock..." -ForegroundColor DarkGray
    netsh winsock reset
    Write-Host "-> Resetando o proxy WinHTTP..." -ForegroundColor DarkGray
    netsh winhttp reset proxy
    Write-Host "Correções de rede concluídas. Recomenda-se reiniciar o computador para aplicar todas as mudanças." -ForegroundColor Yellow
}

Export-ModuleMember -Function Invoke-Corrections, Invoke-SFC, Invoke-DISM, Invoke-NetworkCorrections