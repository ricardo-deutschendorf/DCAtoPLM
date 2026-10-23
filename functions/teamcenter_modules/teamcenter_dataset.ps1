# ============================================================
# REVISAO DE DESTINO E IMPORTACAO DE DATASET
# ============================================================
#
# Este arquivo recupera uma revisao existente e importa um PDF
# como Dataset associado a essa revisao.
#
# Responsabilidades:
#   1. recuperar a revisao associada a um Item;
#   2. remover wrappers criados pelo PowerShell;
#   3. validar o tipo tecnico da revisao;
#   4. validar o caminho e a extensao do PDF;
#   5. normalizar o nome e a revisao do Dataset;
#   6. localizar o metodo ImportarPDF;
#   7. executar a importacao e retornar a resposta textual.
#
# Este arquivo nao cria Items ou revisoes e nao inicia workflows.
# ============================================================


# ============================================================
# RECUPERACAO DA REVISAO DE UM ITEM
# ============================================================
function Get-TeamcenterRevision {

  # Localiza a revisao associada ao Item informado utilizando
  # o metodo getItemRevisionfromItem do Importar GD.
  param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNull()]
    $Item
  )


  # ============================================================
  # 1. VALIDAR O ITEM E A CONEXAO
  # ============================================================

  if ($null -eq $Item) {

    throw (
      "O Item do Teamcenter nao foi fornecido."
    )
  }

  if ($null -eq $script:TeamcenterFunctions) {

    throw (
      "As funcoes do Teamcenter nao foram carregadas. " +
      "Execute Connect-Teamcenter primeiro."
    )
  }


  # ============================================================
  # 2. NORMALIZAR O OBJETO DO ITEM
  # ============================================================
  #
  # Quando o PowerShell encapsula o objeto retornado pela API,
  # PSObject.BaseObject recupera o objeto tecnico original.

  $itemBaseObject =
  $Item.PSObject.BaseObject

  if ($null -ne $itemBaseObject) {

    $Item =
    $itemBaseObject
  }


  # ============================================================
  # 3. LOCALIZAR O METODO DE CONSULTA DA REVISAO
  # ============================================================

  $getRevisionMethod =
  Get-TeamcenterMethod `
    -MethodName "getItemRevisionfromItem" `
    -ParameterCount 1


  # ============================================================
  # 4. RECUPERAR A REVISAO
  # ============================================================

  try {

    $revision =
    $getRevisionMethod.Invoke(
      $null,
      @($Item)
    )
  }
  catch {

    # Percorre as excecoes internas para apresentar a causa
    # original informada pelo Importar GD ou pelo Teamcenter.
    $realException =
    $_.Exception

    while (
      $null -ne $realException.InnerException
    ) {

      $realException =
      $realException.InnerException
    }

    throw (
      "Nao foi possivel recuperar a revisao do Item: " +
      $realException.Message
    )
  }

  if ($null -eq $revision) {

    return $null
  }


  # ============================================================
  # 5. NORMALIZAR E RETORNAR A REVISAO
  # ============================================================

  $revisionBaseObject =
  $revision.PSObject.BaseObject

  if ($null -ne $revisionBaseObject) {

    $revision =
    $revisionBaseObject
  }

  return $revision
}


# ============================================================
# IMPORTACAO DO PDF COMO DATASET
# ============================================================
function Import-TeamcenterPdf {

  # Valida os dados recebidos e chama o metodo ImportarPDF do
  # Importar GD para associar o PDF a revisao do Teamcenter.
  param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNull()]
    $Revision,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$ItemCode,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$DatasetName,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$DatasetRevision,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$FilePath
  )


  # ============================================================
  # 1. VALIDAR A REVISAO E O ARQUIVO PDF
  # ============================================================

  if ($null -eq $Revision) {

    throw (
      "A revisao do Item '$ItemCode' nao foi fornecida."
    )
  }

  if (-not (
      Test-Path `
        -LiteralPath $FilePath `
        -PathType Leaf
    )) {

    throw (
      "PDF nao encontrado em '$FilePath'."
    )
  }

  if (
    [System.IO.Path]::GetExtension(
      $FilePath
    ) -ine ".pdf"
  ) {

    throw (
      "O arquivo informado nao possui extensao PDF."
    )
  }


  # ============================================================
  # 2. NORMALIZAR O OBJETO DE REVISAO
  # ============================================================
  #
  # Remove o wrapper criado pelo PowerShell quando o objeto
  # original retornado pela API estiver disponivel.

  $revisionBaseObject =
  $Revision.PSObject.BaseObject

  if ($null -ne $revisionBaseObject) {

    $Revision =
    $revisionBaseObject
  }


  # ============================================================
  # 3. VALIDAR O TIPO TECNICO DA REVISAO
  # ============================================================
  #
  # O Teamcenter pode retornar revisoes especializadas. Por isso,
  # a validacao aceita tipos que terminem com ItemRevision ou
  # Revision.

  $revisionTypeName =
  $Revision.GetType().FullName

  $isRevisionObject =
  $revisionTypeName -match
  '(?i)(ItemRevision|Revision)$'

  if (-not $isRevisionObject) {

    throw (
      "A revisao recebida nao e um objeto de revisao valido. " +
      "Tipo recebido: '$revisionTypeName'."
    )
  }


  # ============================================================
  # 4. NORMALIZAR OS DADOS DO DATASET
  # ============================================================

  $datasetId =
  $DatasetName.Trim()

  $datasetRevisionClean =
  $DatasetRevision.Trim().ToUpperInvariant()

  if (
    [string]::IsNullOrWhiteSpace(
      $datasetId
    )
  ) {

    throw (
      "O nome do Dataset ficou vazio para '$ItemCode'."
    )
  }

  if (
    [string]::IsNullOrWhiteSpace(
      $datasetRevisionClean
    )
  ) {

    throw (
      "A revisao do Dataset ficou vazia para '$ItemCode'."
    )
  }


  # ============================================================
  # 5. LOCALIZAR O METODO IMPORTARPDF
  # ============================================================
  #
  # O metodo esperado recebe cinco parametros:
  #   1. identificador do Dataset;
  #   2. revisao do Dataset;
  #   3. caminho local do PDF;
  #   4. objeto de revisao;
  #   5. indicador booleano exigido pelo importador.

  $importMethod =
  Get-TeamcenterMethod `
    -MethodName "ImportarPDF" `
    -ParameterCount 5


  # ============================================================
  # 6. PREPARAR OS ARGUMENTOS DA IMPORTACAO
  # ============================================================

  $invokeArguments =
  New-Object "System.Object[]" 5

  $invokeArguments[0] =
  [string]$datasetId

  $invokeArguments[1] =
  [string]$datasetRevisionClean

  $invokeArguments[2] =
  [string]$FilePath

  $invokeArguments[3] =
  $Revision

  $invokeArguments[4] =
  [bool]$true


  # ============================================================
  # 7. APRESENTAR O DIAGNOSTICO DA IMPORTACAO
  # ============================================================

  if ($Details) {

    Write-Host (
      "  Dados enviados ao ImportarPDF:"
    ) -ForegroundColor Cyan

    Write-Host (
      "    Dataset ID:       '$datasetId'"
    ) -ForegroundColor Gray

    Write-Host (
      "    Dataset Revision: '$datasetRevisionClean'"
    ) -ForegroundColor Gray

    Write-Host (
      "    Arquivo:          '$FilePath'"
    ) -ForegroundColor Gray

    Write-Host (
      "    Tipo da revisao:  '$revisionTypeName'"
    ) -ForegroundColor Gray
  }


  # ============================================================
  # 8. IMPORTAR O PDF
  # ============================================================
  #
  # A chamada abaixo pode criar efetivamente o Dataset e associar
  # o PDF a revisao recebida. Todas as validacoes locais ocorrem
  # antes deste ponto.

  try {

    $importResult =
    $importMethod.Invoke(
      $null,
      $invokeArguments
    )
  }
  catch {

    # Percorre as excecoes internas para apresentar a mensagem
    # original retornada pelo Importar GD ou pelo Teamcenter.
    $realException =
    $_.Exception

    while (
      $null -ne $realException.InnerException
    ) {

      $realException =
      $realException.InnerException
    }

    throw (
      "Falha ao importar o PDF para '$ItemCode': " +
      $realException.Message
    )
  }


  # ============================================================
  # 9. RETORNAR A RESPOSTA DO IMPORTADOR
  # ============================================================

  return $importResult
}