# ============================================================
# PREPARACAO DO PDF PARA IMPORTACAO
# ============================================================
#
# Este arquivo prepara uma copia local e validada do PDF antes
# da chamada ao importador do Teamcenter.
#
# Responsabilidades:
#   1. validar o caminho e a extensao do arquivo de origem;
#   2. rejeitar arquivos vazios;
#   3. criar a pasta temporaria quando necessario;
#   4. normalizar o codigo usado no nome do arquivo;
#   5. remover copias temporarias anteriores;
#   6. copiar e validar o tamanho do PDF;
#   7. confirmar que o arquivo pode ser aberto para leitura.
#
# Nenhuma alteracao e realizada no arquivo PDF original.
# ============================================================
function Copy-PdfToTemporaryFolder {

  # Cria uma copia controlada do PDF para o importador.
  # A copia e validada por extensao, tamanho e leitura antes
  # de ser enviada ao Teamcenter.
  param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$SourcePdfPath,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$ItemCode
  )

  if (-not (
      Test-Path `
        -LiteralPath $SourcePdfPath `
        -PathType Leaf
    )) {

    throw (
      "PDF de origem nao encontrado: " +
      "'$SourcePdfPath'."
    )
  }

  $sourceFile =
  Get-Item `
    -LiteralPath $SourcePdfPath `
    -ErrorAction Stop

  if ($sourceFile.Extension -ine ".pdf") {
    throw "O arquivo de origem nao possui extensao PDF."
  }

  if ($sourceFile.Length -le 0) {
    throw "O PDF de origem esta vazio."
  }

  $temporaryFolder = $env:DCA_TEMP_FOLDER

  if ([string]::IsNullOrWhiteSpace($temporaryFolder)) {
    throw (
      "DCA_TEMP_FOLDER deve ser configurado no arquivo .env."
    )
  }

  if (-not (
      Test-Path `
        -LiteralPath $temporaryFolder `
        -PathType Container
    )) {

    $null =
    New-Item `
      -Path $temporaryFolder `
      -ItemType Directory `
      -Force `
      -ErrorAction Stop
  }

  # Remove caracteres que nao podem fazer parte de um nome de
  # arquivo no Windows.
  $safeItemCode =
  $ItemCode.Trim() -replace '[\\/:*?"<>|]', '_'

  if (
    [string]::IsNullOrWhiteSpace(
      $safeItemCode
    )
  ) {

    throw (
      "O codigo do Item ficou vazio depois da normalizacao " +
      "do nome do arquivo."
    )
  }

  $temporaryPdfPath =
  Join-Path `
    -Path $temporaryFolder `
    -ChildPath "$safeItemCode.pdf"

  # Remove uma copia anterior para impedir que o importador utilize
  # um PDF desatualizado.
  if (
    Test-Path `
      -LiteralPath $temporaryPdfPath `
      -PathType Leaf
  ) {

    Remove-Item `
      -LiteralPath $temporaryPdfPath `
      -Force `
      -ErrorAction Stop
  }

  Write-Info "Preparando o PDF para importacao..."

  Copy-Item `
    -LiteralPath $SourcePdfPath `
    -Destination $temporaryPdfPath `
    -Force `
    -ErrorAction Stop

  if (-not (Test-Path -LiteralPath $temporaryPdfPath -PathType Leaf)) {
    throw "O PDF nao foi criado na pasta temporaria."
  }

  $temporaryFile = Get-Item -LiteralPath $temporaryPdfPath -ErrorAction Stop

  # A comparacao de tamanho detecta copias incompletas antes que
  # o arquivo seja entregue ao importador.
  if ($temporaryFile.Length -ne $sourceFile.Length) {
    throw (
      "O tamanho da copia temporaria e diferente do original. " +
      "Original: $($sourceFile.Length) bytes. " +
      "Copia: $($temporaryFile.Length) bytes."
    )
  }

  # A abertura em modo de leitura confirma que o arquivo pode ser
  # acessado pelo processo antes da chamada ao Importar GD.
  $stream = $null

  try {

    $stream = [System.IO.File]::Open(
      $temporaryPdfPath,
      [System.IO.FileMode]::Open,
      [System.IO.FileAccess]::Read,
      [System.IO.FileShare]::Read
    )

    if ($stream.Length -le 0) {
      throw "A copia temporaria do PDF esta vazia."
    }
  }
  finally {
    if ($null -ne $stream) {
      $stream.Dispose()
    }
  }

  Write-Success "PDF copiado e validado na pasta temporaria."
  return $temporaryFile.FullName
}
