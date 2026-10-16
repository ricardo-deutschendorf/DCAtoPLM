# Funcoes responsaveis pela apresentacao das mensagens no console.
# Centralizar a saida neste arquivo mantem cores, recuos e atrasos
# consistentes em todas as etapas do script.

# ============================================================
# SECOES E LINHAS DO CONSOLE
# ============================================================

# Quando o arquivo for carregado sem o script principal, utiliza
# atraso zero para evitar dependencia de uma variavel inexistente.
if ($null -eq $OutputDelayMilliseconds) {

  $OutputDelayMilliseconds =
  0
}

if ($null -eq $script:SearchResultDelayMilliseconds) {

  $script:SearchResultDelayMilliseconds =
  0
}
function Write-Section {

  # Exibe um cabecalho destacado para separar as principais
  # etapas da pesquisa, validacao e importacao.
  param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$Title,
    [switch]$NoLeadingBlank
  )

  if (-not $NoLeadingBlank) {

    Write-AnimatedLine ""
  }

  $sectionBorder =
  "+" + ("-" * 68) + "+"

  $sectionTitle =
  "| {0,-66} |" -f $Title

  Write-AnimatedLine `
    -Message $sectionBorder `
    -Color Gray

  Write-AnimatedLine `
    -Message $sectionTitle `
    -Color White

  Write-AnimatedLine `
    -Message $sectionBorder `
    -Color Gray
}

function Write-AnimatedLine {

  # Escreve uma linha no console e aplica o atraso configurado.
  # O atraso pode ser desativado usando o valor zero.
  param(
    [Parameter(Mandatory = $true)]
    [AllowEmptyString()]
    [string]$Message,
    [System.ConsoleColor]$Color = [System.ConsoleColor]::Gray,
    [ValidateRange(0, 2000)]
    [int]$DelayMilliseconds = $OutputDelayMilliseconds
  )

  Write-Host `
    -Object $Message `
    -ForegroundColor $Color

  if ($DelayMilliseconds -gt 0) {
    Start-Sleep `
      -Milliseconds $DelayMilliseconds
  }
}

# ============================================================
# RESULTADOS DE PESQUISA
# ============================================================
function Write-SearchResultLine {

  # Usa um atraso menor durante a listagem dos resultados para
  # evitar que pesquisas grandes deixem a interface muito lenta.
  param(
    [Parameter(Mandatory = $true)]
    [AllowEmptyString()]
    [string]$Message,
    [System.ConsoleColor]$Color = [System.ConsoleColor]::Gray
  )

  $searchDelay =
  [int]$script:SearchResultDelayMilliseconds

  if ($searchDelay -lt 0) {

    $searchDelay =
    0
  }

  Write-AnimatedLine `
    -Message $Message `
    -Color $Color `
    -DelayMilliseconds $searchDelay
}

# ============================================================
# MENSAGENS PADRONIZADAS
# ============================================================
function Write-Success {

  # As funcoes abaixo aplicam recuo, cor e prefixo padronizados
  # sem repetir essas regras no restante do projeto.
  param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$Message
  )

  Write-AnimatedLine `
    -Message "  $Message" `
    -Color Green
}

function Write-Failure {

  param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$Message
  )

  Write-AnimatedLine `
    -Message "  Algo deu errado: $Message" `
    -Color Red
}

function Write-Warn {

  param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$Message
  )

  Write-AnimatedLine `
    -Message "  Atencao: $Message" `
    -Color Yellow
}

function Write-Info {

  param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$Message
  )

  Write-AnimatedLine `
    -Message "  $Message" `
    -Color Gray
}
