# automation.psm1
# Módulo de Automação: Envia dados para um webhook.

function Send-ToWebhook {
    param(
        [Parameter(Mandatory=$true)]
        [string]$WebhookUrl,

        [Parameter(Mandatory=$true)]
        [string]$JsonData
    )

    try {
        # Define o caminho do log de forma confiável
        $logPath = Join-Path $PSScriptRoot "..\JarvisLog.txt"

        # Faz o envio dos dados JSON para o webhook usando o método POST
        $response = Invoke-RestMethod -Uri $WebhookUrl -Method Post -ContentType "application/json" -Body $JsonData
        
        Write-LogEntry -LogPath $logPath -Level INFO -Message "Dados enviados com sucesso para o webhook."
        Write-Host "[SUCESSO] Dados enviados para o webhook!" -ForegroundColor Green

        return $response

    } catch {
        $errorMessage = "Falha ao enviar dados para o webhook: $($_.Exception.Message)"
        Write-LogEntry -LogPath $logPath -Level ERROR -Message $errorMessage
        Write-Host "[ERRO] ${errorMessage}" -ForegroundColor Red
        return $null
    }
}

Export-ModuleMember -Function Send-ToWebhook