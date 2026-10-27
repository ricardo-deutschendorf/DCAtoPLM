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
    if ($result.Operation -eq "DatasetOnly") {
      "Importar Dataset em revisao existente"
    }
    else {
      "Criar Item e importar Dataset"
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
