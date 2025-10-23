Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# --- Criar a janela principal ---
$form = New-Object System.Windows.Forms.Form
$form.Text = "Assistente de Diagnóstico - Jarvis"
$form.Size = New-Object System.Drawing.Size(820,700)
$form.StartPosition = "CenterScreen"
$form.BackColor = [System.Drawing.Color]::FromArgb(30,30,30)

# --- TextBox para logs ---
$txtLogs = New-Object System.Windows.Forms.TextBox
$txtLogs.Multiline = $true
$txtLogs.ScrollBars = "Vertical"
$txtLogs.ReadOnly = $true
$txtLogs.BackColor = [System.Drawing.Color]::FromArgb(10,10,10)
$txtLogs.ForeColor = [System.Drawing.Color]::FromArgb(124,252,0) # lime-ish
$txtLogs.Font = New-Object System.Drawing.Font("Consolas",10)
$txtLogs.Size = New-Object System.Drawing.Size(780,400)
$txtLogs.Location = New-Object System.Drawing.Point(10,10)
$form.Controls.Add($txtLogs)

# --- Função auxiliar para escrever no log ---
function Write-Log([string]$message){
    $txtLogs.AppendText("$(Get-Date -Format 'HH:mm:ss') > $message`r`n")
}

# --- Função para pop-up IA / Sintoma do usuário com placeholder + cancel ---
function Show-IAPopup {
    $popup = New-Object System.Windows.Forms.Form
    $popup.Size = New-Object System.Drawing.Size(480,220)
    $popup.StartPosition = "CenterParent"
    $popup.Text = "Sintoma do Usuário - Jarvis"
    $popup.FormBorderStyle = 'FixedDialog'
    $popup.BackColor = [System.Drawing.Color]::FromArgb(40,40,40)
    $popup.MinimizeBox = $false
    $popup.MaximizeBox = $false
    $popup.Topmost = $true

    $lbl = New-Object System.Windows.Forms.Label
    $lbl.Text = "Informe brevemente o sintoma (ex: lentidão ao iniciar, travamentos, sem internet):"
    $lbl.ForeColor = [System.Drawing.Color]::White
    $lbl.Size = New-Object System.Drawing.Size(440,40)
    $lbl.Location = New-Object System.Drawing.Point(15,10)
    $popup.Controls.Add($lbl)

    $txtInput = New-Object System.Windows.Forms.TextBox
    $txtInput.Size = New-Object System.Drawing.Size(440,30)
    $txtInput.Location = New-Object System.Drawing.Point(15,60)
    $txtInput.ForeColor = [System.Drawing.Color]::Gray
    $placeholder = "Ex: Lentidão ao iniciar, falha na internet, travamentos..."
    $txtInput.Text = $placeholder

    # placeholder behavior
    $txtInput.Add_GotFocus({
        if ($txtInput.Text -eq $placeholder) {
            $txtInput.Text = ""
            $txtInput.ForeColor = [System.Drawing.Color]::White
        }
    })
    $txtInput.Add_LostFocus({
        if ([string]::IsNullOrWhiteSpace($txtInput.Text)) {
            $txtInput.Text = $placeholder
            $txtInput.ForeColor = [System.Drawing.Color]::Gray
        }
    })
    $popup.Controls.Add($txtInput)

    # OK
    $btnOk = New-Object System.Windows.Forms.Button
    $btnOk.Text = "OK"
    $btnOk.Size = New-Object System.Drawing.Size(100,32)
    $btnOk.Location = New-Object System.Drawing.Point(355,120)
    $btnOk.BackColor = [System.Drawing.Color]::FromArgb(50,50,50)
    $btnOk.ForeColor = [System.Drawing.Color]::White
    $btnOk.Add_Click({
        $val = $txtInput.Text
        if ($val -eq $placeholder) { $val = "" } # don't return placeholder
        $popup.Tag = $val
        $popup.Close()
    })
    $popup.Controls.Add($btnOk)

    # Cancel
    $btnCancel = New-Object System.Windows.Forms.Button
    $btnCancel.Text = "Cancelar"
    $btnCancel.Size = New-Object System.Drawing.Size(100,32)
    $btnCancel.Location = New-Object System.Drawing.Point(240,120)
    $btnCancel.BackColor = [System.Drawing.Color]::FromArgb(90,20,20)
    $btnCancel.ForeColor = [System.Drawing.Color]::White
    $btnCancel.Add_Click({
        $popup.Tag = $null
        $popup.Close()
    })
    $popup.Controls.Add($btnCancel)

    # Small hint label
    $hint = New-Object System.Windows.Forms.Label
    $hint.Text = "Dica: deixe breve — o texto será incluído no prompt copiado para o ChatGPT."
    $hint.ForeColor = [System.Drawing.Color]::FromArgb(200,200,200)
    $hint.Size = New-Object System.Drawing.Size(440,20)
    $hint.Location = New-Object System.Drawing.Point(15,165)
    $popup.Controls.Add($hint)

    $popup.ShowDialog() | Out-Null
    return $popup.Tag
}

# --- Layout vars (forçados como inteiros pra evitar problemas de soma) ---
[int]$btnX = 10
[int]$btnY = 430
[int]$btnWidth = 180
[int]$btnHeight = 40
[int]$btnMargin = 10

# --- Botões principais (mantendo mesmas opções do menu antigo) ---

# Diagnóstico Completo
$btnDiag = New-Object System.Windows.Forms.Button
$btnDiag.Text = "Executar Diagnóstico"
$btnDiag.Size = New-Object System.Drawing.Size($btnWidth,$btnHeight)
$btnDiag.Location = New-Object System.Drawing.Point($btnX,$btnY)
$btnDiag.BackColor = [System.Drawing.Color]::FromArgb(50,50,50)
$btnDiag.ForeColor = [System.Drawing.Color]::White
$btnDiag.Add_Click({
    Write-Log "Iniciando diagnóstico completo..."
    # CHAMAR SEU SCRIPT DE DIAGNÓSTICO (descomente e ajuste caminho caso queira)
    # try { & "$PSScriptRoot\diagnostic-v2.ps1" -ErrorAction Stop; Write-Log "Diagnóstico finalizado!" } catch { Write-Log "Erro ao executar diagnóstico: $($_.Exception.Message)" }
    Write-Log "Diagnóstico (simulado) finalizado!"
})
$form.Controls.Add($btnDiag)

# Segundo grupo: SFC / DISM / Rede
[int]$y2 = $btnY + $btnHeight + $btnMargin
$btnSFC = New-Object System.Windows.Forms.Button
$btnSFC.Text = "SFC"
$btnSFC.Size = New-Object System.Drawing.Size(80,$btnHeight)
$btnSFC.Location = New-Object System.Drawing.Point($btnX,$y2)
$btnSFC.BackColor = [System.Drawing.Color]::FromArgb(50,50,50)
$btnSFC.ForeColor = [System.Drawing.Color]::White
$btnSFC.Add_Click({
    Write-Log "Executando SFC..."
    # & "$PSScriptRoot\modulos\maintenance.psm1"; Invoke-SFC
})
$form.Controls.Add($btnSFC)

$btnDISM = New-Object System.Windows.Forms.Button
$btnDISM.Text = "DISM"
$btnDISM.Size = New-Object System.Drawing.Size(80,$btnHeight)
$btnDISM.Location = New-Object System.Drawing.Point($btnX + 90,$y2)
$btnDISM.BackColor = [System.Drawing.Color]::FromArgb(50,50,50)
$btnDISM.ForeColor = [System.Drawing.Color]::White
$btnDISM.Add_Click({
    Write-Log "Executando DISM..."
})
$form.Controls.Add($btnDISM)

$btnRede = New-Object System.Windows.Forms.Button
$btnRede.Text = "Correções de Rede"
$btnRede.Size = New-Object System.Drawing.Size(140,$btnHeight)
$btnRede.Location = New-Object System.Drawing.Point($btnX + 180,$y2)
$btnRede.BackColor = [System.Drawing.Color]::FromArgb(50,50,50)
$btnRede.ForeColor = [System.Drawing.Color]::White
$btnRede.Add_Click({
    Write-Log "Executando correções de rede..."
})
$form.Controls.Add($btnRede)

# Limpeza Rápida e Completa
[int]$y3 = $y2 + $btnHeight + $btnMargin
$btnQuickClean = New-Object System.Windows.Forms.Button
$btnQuickClean.Text = "Limpeza Rápida"
$btnQuickClean.Size = New-Object System.Drawing.Size(140,$btnHeight)
$btnQuickClean.Location = New-Object System.Drawing.Point($btnX,$y3)
$btnQuickClean.BackColor = [System.Drawing.Color]::FromArgb(50,50,50)
$btnQuickClean.ForeColor = [System.Drawing.Color]::White
$btnQuickClean.Add_Click({ Write-Log "Executando Limpeza Rápida..." })
$form.Controls.Add($btnQuickClean)

$btnFullClean = New-Object System.Windows.Forms.Button
$btnFullClean.Text = "Limpeza Completa"
$btnFullClean.Size = New-Object System.Drawing.Size(140,$btnHeight)
$btnFullClean.Location = New-Object System.Drawing.Point($btnX + 150,$y3)
$btnFullClean.BackColor = [System.Drawing.Color]::FromArgb(50,50,50)
$btnFullClean.ForeColor = [System.Drawing.Color]::White
$btnFullClean.Add_Click({ Write-Log "Executando Limpeza Completa..." })
$form.Controls.Add($btnFullClean)

# Otimização de Memória
[int]$y4 = $y3 + $btnHeight + $btnMargin
$btnOptimize = New-Object System.Windows.Forms.Button
$btnOptimize.Text = "Otimizar Memória"
$btnOptimize.Size = New-Object System.Drawing.Size($btnWidth,$btnHeight)
$btnOptimize.Location = New-Object System.Drawing.Point($btnX,$y4)
$btnOptimize.BackColor = [System.Drawing.Color]::FromArgb(50,50,50)
$btnOptimize.ForeColor = [System.Drawing.Color]::White
$btnOptimize.Add_Click({ Write-Log "Otimização de memória iniciada..." })
$form.Controls.Add($btnOptimize)

# Relatórios Inteligentes
[int]$y5 = $y4 + $btnHeight + $btnMargin
$btnReport = New-Object System.Windows.Forms.Button
$btnReport.Text = "Visualizar Relatórios"
$btnReport.Size = New-Object System.Drawing.Size($btnWidth,$btnHeight)
$btnReport.Location = New-Object System.Drawing.Point($btnX,$y5)
$btnReport.BackColor = [System.Drawing.Color]::FromArgb(50,50,50)
$btnReport.ForeColor = [System.Drawing.Color]::White
$btnReport.Add_Click({ Write-Log "Abrindo relatórios inteligentes..." ; Start-DiagnosticAnalysis -JsonPath (Join-Path $PSScriptRoot 'output\status-maquina.json') })
$form.Controls.Add($btnReport)

# IA (Prompt inteligente)
[int]$y6 = $y5 + $btnHeight + $btnMargin
$btnAI = New-Object System.Windows.Forms.Button
$btnAI.Text = "🧠 Gerar Prompt Inteligente"
$btnAI.Size = New-Object System.Drawing.Size(220,$btnHeight)
$btnAI.Location = New-Object System.Drawing.Point($btnX,$y6)
$btnAI.BackColor = [System.Drawing.Color]::FromArgb(45,45,80)
$btnAI.ForeColor = [System.Drawing.Color]::White
$btnAI.Add_Click({
    Write-Log "Abrindo popup para sintoma do usuário..."
    $sintoma = Show-IAPopup
    if ($sintoma -ne $null) {
        if ($sintoma.Trim().Length -gt 0) {
            Write-Log "Sintoma informado: $sintoma"
        } else {
            Write-Log "Nenhum sintoma textual informado (campo vazio)."
        }

        # Gera prompt resumido e copia para clipboard (invoca sua função: Invoke-IntelligentPrompt)
        # Se você tiver Invoke-IntelligentPrompt definido em outro arquivo, chame aqui com o caminho e parâmetros.
        try {
            # Exemplo simples: montar prompt e copiar
            $jsonPath = Join-Path $PSScriptRoot 'output\status-maquina.json'
            if (Test-Path $jsonPath) {
                $raw = Get-Content $jsonPath -Raw
            } else {
                $raw = "{}"
            }
            $prompt = @"
🧠 Contexto:
Você é um assistente especialista em administração de sistemas Windows e análise de logs.
Sintoma relatado: $sintoma

Logs (resumo):
$raw

Gere relatório técnico seguindo as regras padrões.
"@
            Set-Clipboard -Value $prompt
            Write-Log "Prompt copiado para clipboard. Abra o ChatGPT e cole (CTRL+V)."
            # abrir chatgpt opcional (somente se o analista desejar)
            $open = [System.Windows.Forms.MessageBox]::Show("Deseja abrir o ChatGPT no navegador agora?","Abrir ChatGPT",[System.Windows.Forms.MessageBoxButtons]::YesNo,[System.Windows.Forms.MessageBoxIcon]::Question)
            if ($open -eq [System.Windows.Forms.DialogResult]::Yes) {
                $url = "https://chat.openai.com/"
                try { Start-Process $url } catch { Write-Log "Não foi possível abrir o navegador automaticamente. URL: $url" }
            }
        } catch {
            Write-Log "Erro ao gerar prompt: $($_.Exception.Message)"
        }
    } else {
        Write-Log "Ação cancelada pelo usuário."
    }
})
$form.Controls.Add($btnAI)

# Sair
[int]$y7 = $y6 + $btnHeight + $btnMargin
$btnExit = New-Object System.Windows.Forms.Button
$btnExit.Text = "Sair"
$btnExit.Size = New-Object System.Drawing.Size($btnWidth,$btnHeight)
$btnExit.Location = New-Object System.Drawing.Point($btnX,$y7)
$btnExit.BackColor = [System.Drawing.Color]::FromArgb(150,0,0)
$btnExit.ForeColor = [System.Drawing.Color]::White
$btnExit.Add_Click({ $form.Close() })
$form.Controls.Add($btnExit)

# --- Mostrar janela ---
$form.Topmost = $true
$form.Add_Shown({ $form.Activate() })
[void]$form.ShowDialog()
