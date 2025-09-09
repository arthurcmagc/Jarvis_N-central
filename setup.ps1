# =================================================================
#             SETUP - JARVIS LOCAL v2
# =================================================================
# OBJETIVO: Prepara o ambiente para a execução do Jarvis.
#           Ajusta a política de execução apenas para o processo
#           atual, garantindo segurança e funcionalidade.
# =================================================================

Clear-Host
Write-Host "==================================================" -ForegroundColor Cyan
Write-Host "    Configurando ambiente para o Jarvis Local" -ForegroundColor White
Write-Host "==================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Este script irá ajustar a política de execução de scripts do PowerShell" -ForegroundColor Yellow
Write-Host "apenas para esta sessão, permitindo que o Jarvis funcione corretamente." -ForegroundColor Yellow
Write-Host "Nenhuma alteração permanente será feita no seu sistema." -ForegroundColor Yellow
Write-Host ""

try {
    # Define a política de execução como 'RemoteSigned' apenas para o processo atual.
    # Isso permite que scripts locais (como o Jarvis) rodem sem problemas.
    Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope Process -Force -ErrorAction Stop
    Write-Host "[SUCESSO] Política de execução ajustada com sucesso para esta sessão." -ForegroundColor Green
    Write-Host ""
    Write-Host "Você já pode executar o 'menu.ps1'." -ForegroundColor White
}
catch {
    Write-Host "[ERRO] Não foi possível ajustar a política de execução." -ForegroundColor Red
    Write-Host "Por favor, execute o PowerShell como Administrador e tente novamente." -ForegroundColor Red
    Write-Host "Detalhes do erro: $($_.Exception.Message)" -ForegroundColor Gray
}

Write-Host ""
Read-Host "Pressione ENTER para encerrar..."