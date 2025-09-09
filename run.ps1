# Define o diretório base
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $ScriptDir

# Importa módulos se necessário (opcional se o menu já faz isso)
# Exemplo: Import-Module "$ScriptDir\modulos\log.psm1" -Force

# Executa o menu principal
.\menu.ps1
