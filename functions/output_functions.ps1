# ============================================================
# SAIDA E INTERFACE DO CONSOLE
# ============================================================
# Centraliza atrasos, cabecalhos e mensagens padronizadas.
# Nao pesquisa documentos nem acessa PDM ou Teamcenter.
# ============================================================

if ($null -eq (Get-Variable -Name "OutputDelayMilliseconds" -ErrorAction SilentlyContinue)) {
    $OutputDelayMilliseconds = 0
}

if ($null -eq (Get-Variable -Name "SearchResultDelayMilliseconds" -Scope Script -ErrorAction SilentlyContinue)) {
    $script:SearchResultDelayMilliseconds = 0
}

# Escreve uma linha com cor e atraso configuraveis.
function Write-AnimatedLine {
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Message,

        [System.ConsoleColor]$Color = [System.ConsoleColor]::Gray,

        [ValidateRange(0, 2000)]
        [int]$DelayMilliseconds = $OutputDelayMilliseconds
    )

    Write-Host -Object $Message -ForegroundColor $Color

    if ($DelayMilliseconds -gt 0) {
        Start-Sleep -Milliseconds $DelayMilliseconds
    }
}

# Exibe um cabecalho de secao com largura fixa.
function Write-Section {
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Title,

        [switch]$NoLeadingBlank
    )

    if (-not $NoLeadingBlank) {
        Write-AnimatedLine ""
    }

    $titleText = $Title.Trim()

    if ($titleText.Length -gt 66) {
        $titleText = $titleText.Substring(0, 63) + "..."
    }

    $border = "+" + ("-" * 68) + "+"

    Write-AnimatedLine -Message $border -Color Gray
    Write-AnimatedLine -Message ("| {0,-66} |" -f $titleText) -Color White
    Write-AnimatedLine -Message $border -Color Gray
}

# Exibe resultados com atraso independente.
function Write-SearchResultLine {
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Message,

        [System.ConsoleColor]$Color = [System.ConsoleColor]::Gray
    )

    $delay = [Math]::Max(
        0,
        [int]$script:SearchResultDelayMilliseconds
    )

    Write-AnimatedLine `
        -Message $Message `
        -Color $Color `
        -DelayMilliseconds $delay
}

# Aplica recuo, prefixo e cor padronizados.
function Write-DcaConsoleMessage {
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Message,

        [AllowEmptyString()]
        [string]$Prefix = "",

        [Parameter(Mandatory)]
        [System.ConsoleColor]$Color
    )

    Write-AnimatedLine `
        -Message ("  " + $Prefix + $Message) `
        -Color $Color
}

function Write-Success {
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Message
    )

    Write-DcaConsoleMessage `
        -Message $Message `
        -Color Green
}

function Write-Failure {
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Message
    )

    Write-DcaConsoleMessage `
        -Message $Message `
        -Prefix "Algo deu errado: " `
        -Color Red
}

function Write-Warn {
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Message
    )

    Write-DcaConsoleMessage `
        -Message $Message `
        -Prefix "Atencao: " `
        -Color Yellow
}

function Write-Info {
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Message
    )

    Write-DcaConsoleMessage `
        -Message $Message `
        -Color Gray
}