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

  # ============================================================
  # 1. VALIDAR O PDF DE ORIGEM
  # ============================================================
  #
  # Confirma que o caminho recebido aponta para um arquivo antes
  # de verificar sua extensao e seu tamanho.
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

  # Recupera as informacoes do arquivo utilizadas para validar
  # sua extensao e comparar posteriormente o tamanho da copia.
  $sourceFile =
  Get-Item `
    -LiteralPath $SourcePdfPath `
    -ErrorAction Stop

  # Somente arquivos com extensao PDF podem ser preparados para
  # envio ao importador do Teamcenter.
  if ($sourceFile.Extension -ine ".pdf") {
    throw "O arquivo de origem nao possui extensao PDF."
  }

  # Rejeita o arquivo antes da copia quando nenhum conteudo tiver
  # sido encontrado no PDF de origem.
  if ($sourceFile.Length -le 0) {
    throw "O PDF de origem esta vazio."
  }

  # ============================================================
  # 2. PREPARAR A PASTA TEMPORARIA
  # ============================================================
  #
  # O caminho da pasta temporaria deve ser informado no arquivo
  # .env por meio da variavel DCA_TEMP_FOLDER.
  $temporaryFolder = $env:DCA_TEMP_FOLDER

  if ([string]::IsNullOrWhiteSpace($temporaryFolder)) {
    throw (
      "DCA_TEMP_FOLDER deve ser configurado no arquivo .env."
    )
  }

  # Quando a pasta ainda nao existir, cria toda a estrutura
  # necessaria antes de preparar a copia do PDF.
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

  # ============================================================
  # 3. NORMALIZAR O NOME DO ARQUIVO TEMPORARIO
  # ============================================================
  #
  # Remove espacos das extremidades e substitui os caracteres que
  # nao podem fazer parte de um nome de arquivo no Windows.
  $safeItemCode =
  $ItemCode.Trim() -replace '[\\/:*?"<>|]', '_'

  # O codigo precisa manter algum caractere utilizavel depois da
  # substituicao dos caracteres invalidos.
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

  # ============================================================
  # 4. DEFINIR O CAMINHO DA COPIA
  # ============================================================
  #
  # O PDF temporario utiliza o codigo normalizado do Item como
  # nome e permanece dentro da pasta configurada para o lote.
  $temporaryPdfPath =
  Join-Path `
    -Path $temporaryFolder `
    -ChildPath "$safeItemCode.pdf"

  # ============================================================
  # 5. REMOVER UMA COPIA TEMPORARIA ANTERIOR
  # ============================================================
  #
  # Quando ja existir um arquivo com o mesmo codigo, remove a copia
  # anterior para impedir que o importador utilize um PDF antigo.
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

  # ============================================================
  # 6. COPIAR O PDF PARA A PASTA TEMPORARIA
  # ============================================================
  #
  # Cria uma copia independente do arquivo original para que o
  # importador trabalhe somente com o arquivo temporario.
  Write-Info "Preparando o PDF para importacao..."

  Copy-Item `
    -LiteralPath $SourcePdfPath `
    -Destination $temporaryPdfPath `
    -Force `
    -ErrorAction Stop

  # Confirma que a operacao de copia realmente criou o arquivo no
  # caminho esperado antes de continuar a validacao.
  if (-not (Test-Path -LiteralPath $temporaryPdfPath -PathType Leaf)) {
    throw "O PDF nao foi criado na pasta temporaria."
  }

  # Recupera as informacoes da copia para comparar seu tamanho com
  # o arquivo de origem.
  $temporaryFile = Get-Item -LiteralPath $temporaryPdfPath -ErrorAction Stop

  # ============================================================
  # 7. VALIDAR O TAMANHO DA COPIA
  # ============================================================
  #
  # A copia deve possuir exatamente o mesmo tamanho do arquivo de
  # origem. Uma diferenca indica que o arquivo pode estar incompleto.
  if ($temporaryFile.Length -ne $sourceFile.Length) {
    throw (
      "O tamanho da copia temporaria e diferente do original. " +
      "Original: $($sourceFile.Length) bytes. " +
      "Copia: $($temporaryFile.Length) bytes."
    )
  }

  # ============================================================
  # 8. CONFIRMAR O ACESSO DE LEITURA
  # ============================================================
  #
  # A abertura em modo de leitura confirma que o arquivo pode ser
  # acessado pelo processo antes da chamada ao Importar GD.
  # O valor inicial permite fechar o fluxo com seguranca no bloco
  # finally, mesmo quando a abertura do arquivo falhar.
  $stream = $null

  try {

    # Abre o arquivo somente para leitura e permite o acesso
    # simultaneo de outros processos tambem em modo de leitura.
    $stream = [System.IO.File]::Open(
      $temporaryPdfPath,
      [System.IO.FileMode]::Open,
      [System.IO.FileAccess]::Read,
      [System.IO.FileShare]::Read
    )

    # Confirma novamente o conteudo utilizando o fluxo realmente
    # aberto pelo processo.
    if ($stream.Length -le 0) {
      throw "A copia temporaria do PDF esta vazia."
    }
  }
  finally {

    # ============================================================
    # 9. FECHAR O FLUXO DE LEITURA
    # ============================================================
    #
    # O fluxo deve ser liberado mesmo quando uma falha ocorrer
    # durante a validacao do arquivo.
    if ($null -ne $stream) {

      # Libera o controle do arquivo para evitar que a copia
      # temporaria permaneca bloqueada pelo processo.
      $stream.Dispose()
    }
  }

  # ============================================================
  # 10. RETORNAR O PDF VALIDADO
  # ============================================================
  #
  # Depois de todas as verificacoes, retorna o caminho completo
  # da copia que sera enviada ao importador do Teamcenter.
  Write-Success "PDF copiado e validado na pasta temporaria."
  return $temporaryFile.FullName
}