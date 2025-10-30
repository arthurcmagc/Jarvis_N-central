# modulos\compat.psm1
# ======================================================================
# Camada de compatibilidade para PowerShell 5.1 (funciona também no 7+)
# - Get-ValueOrDefault  : emula o operador ?? (null-coalescing)
# - Convert-NormalizedString : remove NBSP de cópias/colas
# - Format-WrappedText  : word-wrap simples com largura/indentação
# - Write-TypingFormattedText : animação com Delay/LineWidth/Indent
#   (mantém a experiência original do Jarvis)
# ======================================================================

# ----------------------------
# Helper: Get-ValueOrDefault
# ----------------------------
if (-not (Get-Command -Name Get-ValueOrDefault -ErrorAction SilentlyContinue)) {
    function Get-ValueOrDefault {
        [CmdletBinding()]
        param(
            [Parameter(ValueFromPipeline = $true)]
            $Value,
            [Parameter()] [object] $Default = 'N/D'
        )
        process {
            if ($null -eq $Value) { return $Default }
            if ($Value -is [string]) {
                $s = [string]$Value
                if ([string]::IsNullOrWhiteSpace($s)) { return $Default }
            }
            return $Value
        }
    }
}

# ------------------------------------------------------------
# Helper: Convert-NormalizedString (remove NBSP U+00A0)
# ------------------------------------------------------------
if (-not (Get-Command -Name Convert-NormalizedString -ErrorAction SilentlyContinue)) {
    function Convert-NormalizedString {
        [CmdletBinding()]
        param([string] $Text)
        if ($null -eq $Text) { return $null }
        return ($Text -replace [char]0xA0, ' ')
    }
}

# ------------------------------------------------------------
# Helper: Format-WrappedText (word-wrap com largura/indent)
# ------------------------------------------------------------
if (-not (Get-Command -Name Format-WrappedText -ErrorAction SilentlyContinue)) {
    function Format-WrappedText {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory)][string] $Text,
            [int] $LineWidth = 0,
            [string] $Indent = ''
        )
        # Sem wrap: retorna linhas originais (respeitando quebras)
        $clean = Convert-NormalizedString $Text
        if ($LineWidth -le 0) { return ($clean -split "(\r?\n)") }

        $eff = [math]::Max(1, $LineWidth - $Indent.Length)
        $out = @()
        foreach ($rawLine in ($clean -split "(\r?\n)")) {
            if ($rawLine -match "^\r?\n$") { $out += ''; continue }
            $line = $rawLine
            while ($line.Length -gt $eff) {
                $slice = $line.Substring(0, $eff)
                $break = $slice.LastIndexOf(' ')
                if ($break -lt 0) { $break = $eff }
                $out += $line.Substring(0, $break)
                $line  = $line.Substring($break).TrimStart()
            }
            $out += $line
        }
        return ,$out
    }
}

# ------------------------------------------------------------
# Write-TypingFormattedText (com Delay/LineWidth/Indent)
# - Compatível com PS 5.1 e 7+
# - Mantém parâmetros que o menu.ps1 já usa
# ------------------------------------------------------------
if (-not (Get-Command -Name Write-TypingFormattedText -ErrorAction SilentlyContinue)) {
    function Write-TypingFormattedText {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory)][string] $Text,
            [int]    $Delay = 8,                 # ms por caractere
            [string] $ForegroundColor = 'White',
            [int]    $LineWidth = 0,             # 0 = sem wrap
            [string] $Indent = ''                # espaços iniciais por linha
        )

        $lines = Format-WrappedText -Text $Text -LineWidth $LineWidth -Indent $Indent

        foreach ($ln in $lines) {
            if ($Indent -and $Indent.Length -gt 0) {
                Write-Host $Indent -NoNewline -ForegroundColor $ForegroundColor
            }
            foreach ($ch in $ln.ToCharArray()) {
                Write-Host $ch -NoNewline -ForegroundColor $ForegroundColor
                if ($Delay -gt 0) { Start-Sleep -Milliseconds $Delay }
            }
            Write-Host ''  # newline
        }
    }
}

# ----------------------------
# Exportação
# ----------------------------
$toExport = @()
foreach ($fn in 'Get-ValueOrDefault','Convert-NormalizedString','Format-WrappedText','Write-TypingFormattedText') {
    if (Get-Command -Name $fn -ErrorAction SilentlyContinue) { $toExport += $fn }
}
if ($toExport.Count -gt 0) {
    Export-ModuleMember -Function $toExport -ErrorAction SilentlyContinue
}
