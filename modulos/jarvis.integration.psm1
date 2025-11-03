# modulos\jarvis.integration.psm1
# Integração: lê jarvis.config.json (ou env), injeta MachineInfo no JSON e envia para /functions/v1/ingest

Set-StrictMode -Version Latest

function Get-JarvisConfig {
    [CmdletBinding()]
    param([string]$RootPath = (Split-Path -Parent -Path $PSCommandPath))

    $cfg = [ordered]@{
        IngestUrl = $env:JARVIS_INGEST_URL
        ApiToken  = $env:JARVIS_API_TOKEN
    }

    $cfgPath = Join-Path $RootPath 'jarvis.config.json'
    if (Test-Path -LiteralPath $cfgPath) {
        try {
            $fileCfg = Get-Content -Raw -Path $cfgPath | ConvertFrom-Json
            if ($fileCfg.IngestUrl) { $cfg.IngestUrl = $fileCfg.IngestUrl }
            if ($fileCfg.ApiToken)  { $cfg.ApiToken  = $fileCfg.ApiToken  }
        } catch {
            Write-Host "[JARVIS] Config inválida: $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }

    if (-not $cfg.IngestUrl -or -not $cfg.ApiToken) {
        throw "[JARVIS] Config ausente. Defina jarvis.config.json ou as variáveis JARVIS_INGEST_URL e JARVIS_API_TOKEN."
    }
    return [pscustomobject]$cfg
}

function Get-JarvisMachineInfo {
    [CmdletBinding()]
    param()
    try {
        $mi = Get-ComputerInfo |
              Select-Object CsName, WindowsVersion, OsArchitecture,
                            CsManufacturer, CsModel, CsProcessors, CsTotalPhysicalMemory

        [pscustomobject]@{
            CsName                = "$($mi.CsName)"
            WindowsVersion        = "$($mi.WindowsVersion)"
            OsArchitecture        = "$($mi.OsArchitecture)"
            CsManufacturer        = "$($mi.CsManufacturer)"
            CsModel               = "$($mi.CsModel)"
            CsProcessors          = ($mi.CsProcessors | ForEach-Object { "$_" }) -join ', '
            CsTotalPhysicalMemory = [math]::Round(([double]$mi.CsTotalPhysicalMemory/1GB), 2)
        }
    } catch { $null }
}

function Convert-JarvisReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$JsonText,
        [Parameter()][object]$MachineInfo
    )

    try { $obj = $JsonText | ConvertFrom-Json -ErrorAction Stop } catch {
        throw "[JARVIS] JSON inválido: $($_.Exception.Message)"
    }

    $isoNow = (Get-Date).ToString('o')

    if (-not $obj.PSObject.Properties.Match('Timestamp').Count) {
        $obj | Add-Member Timestamp $isoNow
    } else {
        try { $obj.Timestamp = (Get-Date $obj.Timestamp).ToString('o') } catch { $obj.Timestamp = $isoNow }
    }

    if (-not $obj.PSObject.Properties.Match('Hostname').Count -or -not $obj.Hostname) {
        $obj | Add-Member Hostname $env:COMPUTERNAME
    }

    if ($MachineInfo) {
        if (-not $obj.PSObject.Properties.Match('MachineInfo').Count) {
            $obj | Add-Member MachineInfo $MachineInfo
        } elseif (-not $obj.MachineInfo) {
            $obj.MachineInfo = $MachineInfo
        }
    }

    ($obj | ConvertTo-Json -Depth 8 -Compress)
}

function Send-JarvisReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ReportJsonPath,
        [Parameter()][string]$ProjectRoot = (Split-Path -Parent -Path $PSCommandPath),
        [string]$Scope = '',
        [string]$DeviceHint = ''
    )

    if (-not (Test-Path -LiteralPath $ReportJsonPath)) {
        throw "[JARVIS] Arquivo não encontrado: $ReportJsonPath"
    }

    $conf     = Get-JarvisConfig -RootPath $ProjectRoot
    $machine  = Get-JarvisMachineInfo
    $raw      = Get-Content -Raw -Path $ReportJsonPath
    $bodyJson = Convert-JarvisReport -JsonText $raw -MachineInfo $machine

    $headers = @{
        'Authorization' = "Bearer $($conf.ApiToken)"
        'Content-Type'  = 'application/json'
        'X-Jarvis-Scope'      = $Scope
        'X-Jarvis-DeviceHint' = $DeviceHint
    }

    try {
        $null = Invoke-RestMethod -Method Post -Uri $conf.IngestUrl -Headers $headers -Body $bodyJson -ErrorAction Stop
        Write-Host "[JARVIS] Relatório enviado. Host=$($env:COMPUTERNAME) Scope=$Scope Hint=$DeviceHint" -ForegroundColor Green
        $true
    } catch {
        Write-Host "[JARVIS] Falha no envio: $($_.Exception.Message)" -ForegroundColor Yellow
        $false
    }
}

Export-ModuleMember -Function Get-JarvisConfig,Get-JarvisMachineInfo,Convert-JarvisReport,Send-JarvisReport
