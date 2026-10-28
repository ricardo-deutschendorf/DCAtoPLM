# ============================================================
# LOGS E RELATORIOS DA EXECUCAO
# ============================================================
#
# Este arquivo registra a saida da execucao e exporta o resultado
# individual dos documentos processados.
#
# Responsabilidades:
#   1. criar as pastas de logs e relatorios;
#   2. gerar um identificador unico para a execucao;
#   3. iniciar a captura da saida do console;
#   4. encerrar o log com seguranca;
#   5. exportar os resultados do lote em formato CSV.
#
# As senhas nao devem ser escritas por nenhuma funcao deste
# arquivo.
# ============================================================

function Initialize-DcaExecutionArtifacts {

  param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$ProjectRoot
  )

  # ============================================================
  # 1. PREPARAR O IDENTIFICADOR DA EXECUCAO
  # ============================================================

  $script:DcaExecutionStartedAt =
  Get-Date

  $script:DcaExecutionId =
  $script:DcaExecutionStartedAt.ToString(
    "yyyyMMdd_HHmmss"
  )

  # ============================================================
  # 2. DEFINIR AS PASTAS DE SAIDA
  # ============================================================
  #
  # Os logs e relatorios permanecem dentro da pasta temporaria
  # configurada em DCA_TEMP_FOLDER.
  $temporaryFolder =
  ([string]$env:DCA_TEMP_FOLDER).Trim()

  if (
    [string]::IsNullOrWhiteSpace(
      $temporaryFolder
    )
  ) {

    throw (
      "DCA_TEMP_FOLDER deve ser configurado no arquivo .env " +
      "antes da preparacao dos logs e relatorios."
    )
  }

  # Cria uma pasta especifica para cada tipo de arquivo, evitando
  # misturar os PDFs temporarios com logs e relatorios do lote.
  $logFolder =
  Join-Path `
    -Path $temporaryFolder `
    -ChildPath "logs"

  $reportFolder =
  Join-Path `
    -Path $temporaryFolder `
    -ChildPath "reports"
  # ============================================================
  # 3. CRIAR AS PASTAS NECESSARIAS
  # ============================================================

  foreach (
    $outputFolder in @(
      $logFolder,
      $reportFolder
    )
  ) {

    if (-not (
        Test-Path `
          -LiteralPath $outputFolder `
          -PathType Container
      )) {

      $null =
      New-Item `
        -Path $outputFolder `
        -ItemType Directory `
        -Force `
        -ErrorAction Stop
    }
  }

  # ============================================================
  # 4. PREPARAR OS CAMINHOS DOS ARQUIVOS
  # ============================================================

  $script:DcaLogFilePath =
  Join-Path `
    -Path $logFolder `
    -ChildPath (
    "DCAtoPLM_{0}.log" -f
    $script:DcaExecutionId
  )

  $script:DcaReportFilePath =
  Join-Path `
    -Path $reportFolder `
    -ChildPath (
    "DCAtoPLM_{0}.csv" -f
    $script:DcaExecutionId
  )

  # ============================================================
  # 5. INICIAR A CAPTURA DA SAIDA
  # ============================================================

  try {

    Start-Transcript `
      -LiteralPath $script:DcaLogFilePath `
      -Force `
      -ErrorAction Stop |
      Out-Null

    $script:DcaTranscriptStarted =
    $true
  }
  catch {

    $script:DcaTranscriptStarted =
    $false

    Write-Warn (
      "Nao foi possivel iniciar o arquivo de log: " +
      $_.Exception.Message
    )
  }

  if ($script:DcaTranscriptStarted) {

    Write-Info (
      "Log da execucao: " +
      $script:DcaLogFilePath
    )
  }
}

function Stop-DcaExecutionLog {

  # ============================================================
  # 1. VERIFICAR SE O LOG FOI INICIADO
  # ============================================================

  if (-not $script:DcaTranscriptStarted) {
    return
  }

  # ============================================================
  # 2. ENCERRAR A CAPTURA DA SAIDA
  # ============================================================

  try {

    Write-Info (
      "Encerrando o log da execucao."
    )

    Stop-Transcript `
      -ErrorAction Stop |
      Out-Null
  }
  catch {

    Write-Warn (
      "Nao foi possivel encerrar corretamente o log: " +
      $_.Exception.Message
    )
  }
  finally {

    $script:DcaTranscriptStarted =
    $false
  }
}

function Export-DcaBatchReport {

  param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNull()]
    [object[]]$Results,

    [string]$Environment,

    [datetime]$ExecutionStartedAt
  )

  # ============================================================
  # 1. VALIDAR OS RESULTADOS RECEBIDOS
  # ============================================================

  if ($Results.Count -eq 0) {

    Write-Warn (
      "O relatorio CSV nao foi criado porque o lote nao possui " +
      "resultados."
    )

    return $null
  }

  if (
    [string]::IsNullOrWhiteSpace(
      [string]$script:DcaReportFilePath
    )
  ) {

    throw (
      "O caminho do relatorio CSV nao foi preparado."
    )
  }

  # ============================================================
  # 2. PREPARAR AS LINHAS DO RELATORIO
  # ============================================================

  $executionFinishedAt =
  Get-Date

  $reportRows =
  foreach ($result in $Results) {

    $resultStatus =
    if ($result.Succeeded) {
      "Sucesso"
    }
    else {
      "Falha"
    }

    $operationText =
    switch ([string]$result.Operation) {

      "DatasetOnly" {
        "Importar Dataset em revisao existente"
      }

      "RecoverExisting" {
        "Recuperar Item existente e importar Dataset"
      }

      default {
        "Criar Item e importar Dataset"
      }
    }

    [PSCustomObject][ordered]@{
      ExecutionId = [string]$script:DcaExecutionId
      ExecutionStartedAt = $ExecutionStartedAt.ToString(
        "yyyy-MM-dd HH:mm:ss"
      )
      ExecutionFinishedAt = $executionFinishedAt.ToString(
        "yyyy-MM-dd HH:mm:ss"
      )
      Environment = [string]$Environment
      ItemCode = [string]$result.ItemCode
      ItemName = [string]$result.ItemName
      TeamcenterCode = [string]$result.TeamcenterCode
      ClientRevision = [string]$result.ClientRevision
      DocumentType = [string]$result.DocumentType
      PdmState = [string]$result.PdmState
      Operation = $operationText
      ItemCreated = [bool]$result.ItemCreated
      PdfImported = [bool]$result.PdfImported
      PdfImportedThisRun = [bool]$result.PdfImportedThisRun
      DatasetAlreadyExists = [bool]$result.DatasetAlreadyExists
      WorkflowStarted = [bool]$result.WorkflowStarted
      Succeeded = [bool]$result.Succeeded
      Status = $resultStatus
      DocumentStartedAt = [string]$result.DocumentStartedAt
      DocumentFinishedAt = [string]$result.DocumentFinishedAt
      DurationSeconds = $result.DurationSeconds
      SourceFile = [string]$result.SourceFile
      ErrorMessage = [string]$result.ErrorMessage
    }
  }

  # ============================================================
  # 3. EXPORTAR O ARQUIVO CSV
  # ============================================================

  $reportRows |
    Export-Csv `
    -LiteralPath $script:DcaReportFilePath `
    -NoTypeInformation `
    -Encoding UTF8 `
    -Delimiter ";" `
    -Force

  if (-not (
      Test-Path `
        -LiteralPath $script:DcaReportFilePath `
        -PathType Leaf
    )) {

    throw (
      "O relatorio CSV nao foi criado no caminho esperado."
    )
  }

  $reportFile =
  Get-Item `
    -LiteralPath $script:DcaReportFilePath `
    -ErrorAction Stop

  if ($reportFile.Length -le 0) {

    throw (
      "O relatorio CSV foi criado, mas ficou vazio."
    )
  }

  Write-Success (
    "Relatorio CSV criado: " +
    $script:DcaReportFilePath
  )

  return $script:DcaReportFilePath
}
function Import-DcaRetryReport {

  param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$FilePath
  )

  # ============================================================
  # 1. VALIDAR O ARQUIVO DO RELATORIO
  # ============================================================

  if (-not (
      Test-Path `
        -LiteralPath $FilePath `
        -PathType Leaf
    )) {

    throw (
      "O relatorio informado para nova tentativa nao foi " +
      "encontrado: '$FilePath'."
    )
  }

  if (
    [System.IO.Path]::GetExtension(
      $FilePath
    ) -ine ".csv"
  ) {

    throw (
      "O arquivo informado em -RetryReport deve possuir " +
      "extensao CSV."
    )
  }

  # ============================================================
  # 2. CARREGAR AS LINHAS DO RELATORIO
  # ============================================================

  $reportRows =
  @(
    Import-Csv `
      -LiteralPath $FilePath `
      -Delimiter ";" `
      -Encoding UTF8 `
      -ErrorAction Stop
  )

  if ($reportRows.Count -eq 0) {

    throw (
      "O relatorio informado nao possui resultados."
    )
  }

  # ============================================================
  # 3. VALIDAR AS COLUNAS OBRIGATORIAS
  # ============================================================

  $requiredColumns =
  @(
    "ItemCode",
    "ItemName",
    "ClientRevision",
    "DocumentType",
    "PdmState",
    "Operation",
    "ItemCreated",
    "PdfImported",
    "WorkflowStarted",
    "Succeeded",
    "SourceFile",
    "ErrorMessage"
  )

  $availableColumns =
  @(
    $reportRows[0].PSObject.Properties.Name
  )

  $missingColumns =
  @(
    $requiredColumns |
      Where-Object {
      $_ -notin $availableColumns
    }
  )

  if ($missingColumns.Count -gt 0) {

    throw (
      "O relatorio nao possui todas as colunas obrigatorias: " +
      ($missingColumns -join ", ")
    )
  }

  # ============================================================
  # 4. SELECIONAR SOMENTE FALHAS REPROCESSAVEIS
  # ============================================================
  #
  # Documentos cujo PDF ja foi importado nao sao reprocessados.
  # Isso evita criar um Dataset duplicado apenas para repetir um
  # workflow que falhou.
  $retryRows =
  [System.Collections.Generic.List[object]]::new()

  foreach ($reportRow in $reportRows) {

    $succeeded =
    ([string]$reportRow.Succeeded).Trim() -match
    '^(?i:true|1|sim|yes)$'

    $pdfImported =
    ([string]$reportRow.PdfImported).Trim() -match
    '^(?i:true|1|sim|yes)$'

    $itemCreated =
    ([string]$reportRow.ItemCreated).Trim() -match
    '^(?i:true|1|sim|yes)$'

    if ($succeeded) {
      continue
    }

    if ($pdfImported) {

      Write-Warn (
        "O documento '$($reportRow.ItemCode)' nao sera " +
        "reprocessado porque o relatorio informa que o PDF " +
        "ja foi importado."
      )

      continue
    }

    $itemCode =
    ([string]$reportRow.ItemCode).Trim()

    $clientRevision =
    ([string]$reportRow.ClientRevision).Trim()

    $documentType =
    ([string]$reportRow.DocumentType).Trim()

    $sourceFile =
    ([string]$reportRow.SourceFile).Trim()

    if (
      [string]::IsNullOrWhiteSpace(
        $itemCode
      ) -or
      [string]::IsNullOrWhiteSpace(
        $clientRevision
      ) -or
      [string]::IsNullOrWhiteSpace(
        $documentType
      ) -or
      [string]::IsNullOrWhiteSpace(
        $sourceFile
      )
    ) {

      Write-Warn (
        "Uma linha do relatorio foi ignorada porque nao possui " +
        "codigo, revisao, tipo ou caminho do arquivo."
      )

      continue
    }

    $retryMode =
    if ($documentType -eq "DatasetOnly") {
      "DatasetOnly"
    }
    elseif ($itemCreated) {
      "RecoverExisting"
    }
    else {
      "CreateItem"
    }

    $retryRows.Add(
      [PSCustomObject]@{
        ItemCode = $itemCode
        ItemName = ([string]$reportRow.ItemName).Trim()
        ClientRevision = $clientRevision.ToUpperInvariant()
        DocumentType = $documentType
        PdmState = ([string]$reportRow.PdmState).Trim()
        SourceFile = $sourceFile
        RetryMode = $retryMode
        PreviousError = [string]$reportRow.ErrorMessage
      }
    )
  }

  if ($retryRows.Count -eq 0) {

    throw (
      "O relatorio nao possui falhas que possam ser " +
      "reprocessadas com seguranca."
    )
  }

  # ============================================================
  # 5. RETORNAR AS FALHAS SELECIONADAS
  # ============================================================

  Write-Info (
    "Falhas carregadas para nova tentativa: " +
    $retryRows.Count
  )

  return $retryRows.ToArray()
}
