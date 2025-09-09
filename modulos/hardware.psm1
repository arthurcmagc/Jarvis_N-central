# Módulo de Hardware: Coleta informações sobre CPU, RAM e Discos.

function Get-HardwareStatus {
    try {
        $os = Get-CimInstance Win32_OperatingSystem

        # Cálculo de RAM usando a base correta para GB.
        $totalRAMBytes = $os.TotalVisibleMemorySize * 1KB
        $freeRAMBytes = $os.FreePhysicalMemory * 1KB
        $totalRAM = [math]::Round($totalRAMBytes / 1GB, 2)
        $usedPercent = [math]::Round((($totalRAMBytes - $freeRAMBytes) / $totalRAMBytes) * 100, 2)

        $disks = Get-CimInstance Win32_LogicalDisk | ForEach-Object {
            $diskInfo = [pscustomobject]@{
                DeviceID = $_.DeviceID
                FreeGB = [math]::Round($_.FreeSpace / 1GB, 2)
                TotalGB = [math]::Round($_.Size / 1GB, 2)
                FreePercent = [math]::Round(($_.FreeSpace / $_.Size) * 100, 2)
                Tipo = "Desconhecido"
            }

            # Lógica para identificação do tipo de disco
            switch ($_.DriveType) {
                2 { $diskInfo.Tipo = "Unidade Removível (Pendrive, etc.)" }
                3 { $diskInfo.Tipo = "Disco Local Físico" }
                4 { $diskInfo.Tipo = "Unidade de Rede" }
                5 { $diskInfo.Tipo = "Unidade de CD/DVD" }
                6 { $diskInfo.Tipo = "Unidade Mapeada" }
                Default {}
            }
            # Lógica para identificar discos virtuais como Google Drive
            if ($_.VolumeName -like "Google Drive*") {
                $diskInfo.Tipo = "Unidade Mapeada (Google Drive)"
            }

            $diskInfo
        }

        return [pscustomobject]@{
            CPU = (Get-CimInstance Win32_Processor | Select-Object -First 1).Name
            RAM = @{
                TotalGB = $totalRAM
                UsedPercent = $usedPercent
            }
            Disks = $disks
        }

    } catch {
        return [pscustomobject]@{ Error = "Falha na coleta de dados de Hardware: $($_.Exception.Message)" }
    }
}

function Get-ManufacturerInfo {
    try {
        $cs = Get-CimInstance -ClassName Win32_ComputerSystem
        return [pscustomobject]@{
            Manufacturer = $cs.Manufacturer
        }
    }
    catch {
        return [pscustomobject]@{ Error = "Falha na coleta de dados do fabricante: $($_.Exception.Message)" }
    }
}

Export-ModuleMember -Function Get-HardwareStatus, Get-ManufacturerInfo