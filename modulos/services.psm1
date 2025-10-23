# services.psm1

function Get-CriticalServiceStatus {
    try {
        $criticalServices = @('TermService', 'MpsSvc', 'BITS')
        $serviceStatus = @()

        foreach ($serviceName in $criticalServices) {
            $service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
            if ($null -ne $service) {
                if ($service.Status -ne 'Running') {
                    $serviceStatus += [pscustomobject]@{
                        Name = $service.DisplayName
                        Status = $service.Status
                    }
                }
            }
        }
        return [pscustomobject]@{
            CriticalServicesNotRunning = $serviceStatus
        }
    }
    catch {
        return [pscustomobject]@{ Error = "Falha na verificação de serviços críticos: $($_.Exception.Message)" }
    }
}

Export-ModuleMember -Function Get-CriticalServiceStatus