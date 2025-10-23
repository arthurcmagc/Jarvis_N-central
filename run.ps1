param(
    [string]$ZipUrl = "https://github.com/arthurcmagc/Jarvis_N-central/archive/refs/heads/main.zip"
)

$InstallFolder = "C:\HealthCheck\Assistente Jarvis - Hype"
$ExtractFolder = Join-Path $InstallFolder "Jarvis_N-central-main"

# Cria a pasta base se não existir
if (-not (Test-Path $InstallFolder)) {
    New-Item -Path $InstallFolder -ItemType Directory | Out-Null
}

$TempZip = Join-Path $InstallFolder "Jarvis_N-central.zip"

# Baixa o pacote
Write-Host "[INFO] Baixando pacote Jarvis... " -NoNewline
try {
    Invoke-WebRequest -Uri $ZipUrl -OutFile $TempZip -UseBasicParsing
    Write-Host "OK"
} catch {
    Write-Error "[ERRO] Falha ao baixar o pacote Jarvis: $_"
    exit 1
}

# Extrai o pacote
Write-Host "[INFO] Extraindo... " -NoNewline
try {
    if (Test-Path $ExtractFolder) { Remove-Item $ExtractFolder -Recurse -Force }

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [System.IO.Compression.ZipFile]::ExtractToDirectory($TempZip, $InstallFolder)

    Write-Host "OK"
} catch {
    Write-Error "[ERRO] Falha ao extrair o pacote: $_"
    exit 1
}

# Remove o zip depois da extração
Remove-Item $TempZip -Force -ErrorAction SilentlyContinue

# Mensagem final
Write-Host ""
Write-Host "[SUCESSO] Jarvis instalado com sucesso.`n" -ForegroundColor Green
Write-Host "Para usar o assistente, execute os comandos abaixo no PowerShell 5.1+:`n" -ForegroundColor White
Write-Host "1 - CD '$ExtractFolder'"
Write-Host "2 - Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass" -ForegroundColor Yellow
Write-Host "3 - .\menu.ps1"
Write-Host "`nObs: Sempre use o comando acima para liberar scripts 'desconhecidos' na sessão atual do PowerShell.`n" -ForegroundColor DarkGray
