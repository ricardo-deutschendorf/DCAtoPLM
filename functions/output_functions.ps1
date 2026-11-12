# ============================================================
# SAIDA E INTERFACE DO CONSOLE
# ============================================================
#
# Este arquivo centraliza a apresentacao das mensagens exibidas
# pelo DCAtoPLM.
#
# Responsabilidades:
#   1. escrever linhas com atraso configuravel;
#   2. exibir cabecalhos de secao;
#   3. apresentar resultados de pesquisa com atraso independente;
#   4. padronizar mensagens de sucesso, falha, aviso e informacao.
#
# As funcoes deste arquivo nao pesquisam documentos, nao acessam
# o PDM e nao realizam alteracoes no Teamcenter.
# ============================================================

# ============================================================
# CONFIGURACAO DA SAIDA
# ============================================================
#
# Quando este arquivo for carregado fora do script principal,
# utiliza atraso zero para evitar dependencia de variaveis que
# ainda nao foram inicializadas.

if (
  $null -eq (
    Get-Variable `
      -Name "OutputDelayMilliseconds" `
      -ErrorAction SilentlyContinue
  )
) {

  $OutputDelayMilliseconds =
  0
}

if (
  $null -eq (
    Get-Variable `
      -Name "SearchResultDelayMilliseconds" `
      -Scope Script `
      -ErrorAction SilentlyContinue
  )
) {

  $script:SearchResultDelayMilliseconds =
  0
}

# ============================================================
# ESCRITA BASICA NO CONSOLE
# ============================================================
function Write-AnimatedLine {

  # Escreve uma linha no console utilizando a cor e o atraso
  # informados. O atraso pode ser desativado com o valor zero.
  param(
    [Parameter(Mandatory = $true)]
    [AllowEmptyString()]
    [string]$Message,

    [System.ConsoleColor]$Color =
    [System.ConsoleColor]::Gray,

    [ValidateRange(0, 2000)]
    [int]$DelayMilliseconds =
    $OutputDelayMilliseconds
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
# CABECALHOS DE SECAO
# ============================================================
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

  $sectionTitleText =
  $Title.Trim()

  if ($sectionTitleText.Length -gt 66) {

    $sectionTitleText =
    $sectionTitleText.Substring(
      0,
      63
    ) + "..."
  }

  $sectionTitle =
  "| {0,-66} |" -f $sectionTitleText

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

# ============================================================
# RESULTADOS DE PESQUISA
# ============================================================
function Write-SearchResultLine {

  # Exibe uma linha dos resultados de pesquisa utilizando um
  # atraso independente do restante das mensagens do console.
  #
  # Esse atraso pode ser reduzido durante pesquisas grandes para
  # impedir que a apresentacao dos resultados fique muito lenta.
  param(
    [Parameter(Mandatory = $true)]
    [AllowEmptyString()]
    [string]$Message,

    [System.ConsoleColor]$Color =
    [System.ConsoleColor]::Gray
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
#
# As funcoes abaixo aplicam recuo, cor e prefixo padronizados.
# Isso evita repetir as mesmas regras de apresentacao nos outros
# arquivos do projeto.

function Write-DcaConsoleMessage {

  param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$Message,

    [AllowEmptyString()]
    [string]$Prefix = "",

    [Parameter(Mandatory = $true)]
    [System.ConsoleColor]$Color
  )

  Write-AnimatedLine `
    -Message (
    "  " +
    $Prefix +
    $Message
  ) `
    -Color $Color
}

function Write-Success {

  param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$Message
  )

  Write-DcaConsoleMessage `
    -Message $Message `
    -Color Green
}

function Write-Failure {

  param(
    [Parameter(Mandatory = $true)]
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
    [Parameter(Mandatory = $true)]
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
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$Message
  )

  Write-DcaConsoleMessage `
    -Message $Message `
    -Color Gray
}