# hardware.psm1
# ---------------------------------------------------------------------------------
# Saída EXATA do backup para Hardware:
# {
#   "CPU": "11th Gen Intel(R) Core(TM) i5-1135G7 @ 2.40GHz",
#   "RAM": { "TotalGB": 19.73, "UsedPercent": 76.04 },
#   "Disks": [
#     { "DeviceID":"C:", "FreeGB":69.46, "TotalGB":235.74, "FreePercent":29.47, "Tipo":"Disco Local Físico" },
#     { "DeviceID":"G:", "FreeGB":65.99, "TotalGB":235.74, "FreePercent":27.99, "Tipo":"Unidade Mapeada (Google Drive)" }
#   ]
# }
#
# E para Fabricante:
# {
#   "Manufacturer": "Dell Inc.",
#   "Model": "Vostro 3500"
# }
# ---------------------------------------------------------------------------------

function Get-DriveTipo {
    param([int]$DriveType, [string]$DeviceID)
    if ($DriveType -eq 3) { return "Disco Local Físico" }
    if ($DriveType -eq 4) {
        if ($DeviceID -like 'G:*' -or $DeviceID -eq 'G:') { return "Unidade Mapeada (Google Drive)" }
        return "Unidade de Rede"
    }
    if ($DriveType -eq 2) { return "Unidade Removível" }
    return "Volume"
}

function Get-HardwareStatus {
    [CmdletBinding()]
    param()

    # CPU
    $cpuName = "N/D"
    try {
        $cpu = Get-CimInstance -ClassName Win32_Processor -ErrorAction Stop | Select-Object -First 1 -Property Name
        if ($cpu -and $cpu.Name) { $cpuName = $cpu.Name }
    } catch {}

    # RAM (Total e % usada — como no backup)
    $ramTotalGB  = $null
    $ramUsedPct  = $null
    try {
        $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
        $cs = Get-CimInstance -ClassName Win32_ComputerSystem  -ErrorAction Stop
        $ramTotalGB = [math]::Round(($cs.TotalPhysicalMemory / 1GB), 2)
        $usedGB     = [math]::Round((($cs.TotalPhysicalMemory - $os.FreePhysicalMemory * 1KB) / 1GB), 2)
        if ($ramTotalGB -gt 0) {
            $ramUsedPct = [math]::Round((($usedGB / $ramTotalGB) * 100), 2)
        } else {
            $ramUsedPct = 0.0
        }
    } catch {}

    # Discos (DeviceID, FreeGB, TotalGB, FreePercent, Tipo)
    $disksOut = @()
    try {
        $ld = Get-CimInstance -ClassName Win32_LogicalDisk -ErrorAction Stop
        foreach ($d in $ld) {
            try {
                $dev   = $d.DeviceID
                $total = if ($d.Size) { [math]::Round(($d.Size/1GB),2) } else { 0.0 }
                $free  = if ($d.FreeSpace) { [math]::Round(($d.FreeSpace/1GB),2) } else { 0.0 }
                $freeP = if ($d.Size -gt 0) { [math]::Round((($d.FreeSpace / $d.Size) * 100),2) } else { 0.0 }
                $tipo  = Get-DriveTipo -DriveType $d.DriveType -DeviceID $dev

                $disksOut += [pscustomobject]@{
                    DeviceID    = $dev
                    FreeGB      = $free
                    TotalGB     = $total
                    FreePercent = $freeP
                    Tipo        = $tipo
                }
            } catch {}
        }
    } catch {}

    [pscustomobject]@{
        CPU = $cpuName
        RAM = [pscustomobject]@{
            TotalGB     = $ramTotalGB
            UsedPercent = $ramUsedPct
        }
        Disks = $disksOut
    }
}

function Get-ManufacturerInfo {
    [CmdletBinding()]
    param()
    # Coleta robusta com fallbacks para PS 5.1/7
    $manufacturer = $null
    $model        = $null

    try {
        $cs = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
        if ($cs) {
            $manufacturer = $cs.Manufacturer
            $model        = $cs.Model
        }
    } catch {}

    if (-not $manufacturer -or -not $model) {
        try {
            $prod = Get-CimInstance -ClassName Win32_ComputerSystemProduct -ErrorAction SilentlyContinue
            if ($prod) {
                if (-not $manufacturer -and $prod.Vendor) { $manufacturer = $prod.Vendor }
                if (-not $model -and $prod.Name) { $model = $prod.Name }
            }
        } catch {}
    }

    if (-not $manufacturer) { $manufacturer = "N/D" }
    if (-not $model)        { $model        = "N/D" }

    [pscustomobject]@{
        Manufacturer = $manufacturer
        Model        = $model
    }
}

Export-ModuleMember -Function Get-HardwareStatus, Get-ManufacturerInfo
