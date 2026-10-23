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

if ($null -eq $OutputDelayMilliseconds) {

  $OutputDelayMilliseconds =
  0
}

if ($null -eq $script:SearchResultDelayMilliseconds) {

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

function Write-Success {

  # Exibe uma mensagem de operacao concluida com sucesso.
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

  # Exibe uma mensagem de falha com o prefixo padronizado.
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

  # Exibe um aviso que exige atencao do usuario, mas que nem
  # sempre representa uma falha definitiva do fluxo.
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

  # Exibe uma mensagem informativa sem indicar sucesso ou falha.
  param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$Message
  )

  Write-AnimatedLine `
    -Message "  $Message" `
    -Color Gray
}