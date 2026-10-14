function Copy-PdfToTemporaryFolder {

  param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$SourcePdfPath,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$ItemCode
  )

  if (-not (Test-Path -LiteralPath $SourcePdfPath -PathType Leaf)) {
    throw "PDF de origem nao encontrado: $SourcePdfPath"
  }

  $sourceFile = Get-Item -LiteralPath $SourcePdfPath -ErrorAction Stop

  if ($sourceFile.Extension -ine ".pdf") {
    throw "O arquivo de origem nao possui extensao PDF."
  }

  if ($sourceFile.Length -le 0) {
    throw "O PDF de origem esta vazio."
  }

  $temporaryFolder = $env:DCA_TEMP_FOLDER

  if ([string]::IsNullOrWhiteSpace($temporaryFolder)) {
    throw "DCA_TEMP_FOLDER must be configured."
  }

  if (-not (Test-Path -LiteralPath $temporaryFolder -PathType Container)) {
    $null = New-Item -Path $temporaryFolder -ItemType Directory -Force -ErrorAction Stop
  }

  $safeItemCode = $ItemCode -replace '[\\/:*?"<>|]', '_'
  $temporaryPdfPath = Join-Path -Path $temporaryFolder -ChildPath "$safeItemCode.pdf"

  if (Test-Path -LiteralPath $temporaryPdfPath -PathType Leaf) {
    Remove-Item -LiteralPath $temporaryPdfPath -Force -ErrorAction Stop
  }

  Write-Info "Preparando o PDF para importacao..."

  Copy-Item -LiteralPath $SourcePdfPath -Destination $temporaryPdfPath -Force -ErrorAction Stop

  if (-not (Test-Path -LiteralPath $temporaryPdfPath -PathType Leaf)) {
    throw "O PDF nao foi criado na pasta temporaria."
  }

  $temporaryFile = Get-Item -LiteralPath $temporaryPdfPath -ErrorAction Stop

  if ($temporaryFile.Length -ne $sourceFile.Length) {
    throw (
      "O tamanho da copia temporaria e diferente do original. " +
      "Original: $($sourceFile.Length) bytes. " +
      "Copia: $($temporaryFile.Length) bytes."
    )
  }

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
function Get-DcaSearchCodeList {

  param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$InputText
  )

  $codes =
  [System.Collections.Generic.List[string]]::new()

  $knownCodes =
  [System.Collections.Generic.HashSet[string]]::new(
    [System.StringComparer]::OrdinalIgnoreCase
  )

  foreach ($part in ($InputText -split ",")) {

    $currentCode =
    ([string]$part).Trim()

    if (
      [string]::IsNullOrWhiteSpace(
        $currentCode
      )
    ) {
      continue
    }

    # Add retorna false quando o mesmo padrao ja existe.
    if ($knownCodes.Add($currentCode)) {

      $codes.Add($currentCode)
    }
  }

  if ($codes.Count -eq 0) {

    throw "Nenhum codigo valido foi informado."
  }

  return $codes.ToArray()
}
function Get-DcaFolderSearchMode {

  param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$SearchText
  )

  $normalizedSearch =
  $SearchText.Trim()

  if (
    $normalizedSearch.StartsWith("\\") -or
    $normalizedSearch.StartsWith("//")
  ) {

    return [PSCustomObject]@{
      IsFolderSearch = $true
      ListFolderItems = $true
      SearchText = $normalizedSearch.Substring(2).Trim()
    }
  }

  if (
    $normalizedSearch.StartsWith("\") -or
    $normalizedSearch.StartsWith("/")
  ) {

    return [PSCustomObject]@{
      IsFolderSearch = $true
      ListFolderItems = $false
      SearchText = $normalizedSearch.Substring(1).Trim()
    }
  }

  return [PSCustomObject]@{
    IsFolderSearch = $false
    ListFolderItems = $false
    SearchText = $normalizedSearch
  }
}
function Test-DcaFolderSearch {

  param(
    [string]$SearchText
  )

  if (
    [string]::IsNullOrWhiteSpace(
      $SearchText
    )
  ) {
    return $false
  }

  $folderSearchMode =
  Get-DcaFolderSearchMode `
    -SearchText $SearchText

  return [bool]$folderSearchMode.IsFolderSearch
}
function Get-DcaFolderSearchPattern {

  param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$SearchText
  )

  $folderSearchMode =
  Get-DcaFolderSearchMode `
    -SearchText $SearchText

  if (-not $folderSearchMode.IsFolderSearch) {
    throw (
      "A pesquisa informada nao e uma pesquisa de pasta: " +
      "'$SearchText'."
    )
  }

  $folderPattern =
  ([string]$folderSearchMode.SearchText).Trim()

  if (
    [string]::IsNullOrWhiteSpace(
      $folderPattern
    )
  ) {
    throw "O nome ou padrao da pasta ficou vazio."
  }

  if ($folderPattern.Contains("..")) {
    throw (
      "O padrao de pasta nao pode conter '..': " +
      "'$folderPattern'."
    )
  }

  if ($folderPattern -match '[:"<>\|]') {
    throw (
      "O padrao de pasta possui caracteres invalidos: " +
      "'$folderPattern'."
    )
  }

  return $folderPattern.Replace("/", "\")
}
function Get-DcaConfiguredEnvironmentName {

  if (
    -not [string]::IsNullOrWhiteSpace(
      $script:TeamcenterEnvironment
    )
  ) {
    return [string]$script:TeamcenterEnvironment
  }

  $configuredValue =
  ([string]$env:DCA_TC_ENV).Trim()

  if ($configuredValue -ieq "Teste") {
    return "Teste"
  }

  if ($configuredValue -ieq "Processo") {
    return "Processo"
  }

  throw (
    "DCA_TC_ENV nao foi configurado. " +
    "Use Teste ou Processo."
  )
}

function Show-DcaImportPlan {

  param(
    [Parameter(Mandatory = $true)]
    [object[]]$Documents
  )

  $environmentName =
  Get-DcaConfiguredEnvironmentName

  $serverUrl =
  [string]$env:DCA_TC_TEST_URL

  $environmentColor =
  [System.ConsoleColor]::Cyan

  if ($environmentName -eq "Processo") {

    $serverUrl =
    [string]$env:DCA_TC_PROCESS_URL

    $environmentColor =
    [System.ConsoleColor]::Yellow
  }

  $approvedTemplate =
  [string]$env:DCA_TC_APPROVED_WORKFLOW

  $obsoleteTemplate =
  [string]$env:DCA_TC_OBSOLETE_WORKFLOW

  # ====================================================
  # Montar o plano de cada documento
  # ====================================================

  $planItems =
  [System.Collections.Generic.List[object]]::new()

  foreach ($document in $Documents) {

    $pdmState =
    ([string]$document.PdmState).Trim()

    $workflowLabel =
    $null

    $workflowTemplate =
    $null

    if ($pdmState -ieq "Aprovado") {

      $workflowLabel =
      "aprovacao"

      $workflowTemplate =
      $approvedTemplate
    }
    elseif ($pdmState -ieq "Obsoleto") {

      $workflowLabel =
      "obsolescencia"

      $workflowTemplate =
      $obsoleteTemplate
    }

    $configuration =
    $null

    $configurationError =
    $null

    try {

      $configuration =
      Get-DcaTypeConfiguration `
        -DocumentType $document.DocumentType `
        -ClientRevision $document.ClientRevision `
        -TeamcenterEnvironment $environmentName
    }
    catch {

      $configurationError =
      $_.Exception.Message
    }

    $teamcenterRevisionId =
    "?"

    $revisionText =
    ""

    if ($null -ne $configuration) {

      $teamcenterRevisionId =
      [string]$configuration.TeamcenterRevisionId

      $revisionParts =
      @()

      foreach (
        $propertyName in (
          $configuration.RevisionProperties.Keys |
            Sort-Object
        )
      ) {

        $revisionParts +=
        (
          "{0}={1}" -f
          $propertyName,
          $configuration.RevisionProperties[$propertyName]
        )
      }

      $revisionText =
      $revisionParts -join "; "
    }

    $planItems.Add(
      [PSCustomObject]@{
        ItemCode = ([string]$document.ItemCode).Trim().ToUpper()
        ItemName = [string]$document.ItemName
        DocumentType = [string]$document.DocumentType
        DisplayType = [string]$document.DisplayType
        PdmState = $pdmState
        Configuration = $configuration
        ConfigurationError = $configurationError
        TeamcenterRevisionId = $teamcenterRevisionId
        RevisionText = $revisionText
        WorkflowLabel = $workflowLabel
        WorkflowTemplate = $workflowTemplate
        FilePath = [string]$document.SelectedPdf.File.FullName
      }
    )
  }

  # ====================================================
  # Cabecalho
  # ====================================================

  Write-Section -Title "Log antes da importacao"

  Write-Host ""

  Write-Host (
    "  Nada foi criado ainda. Confira as informacoes abaixo."
  ) -ForegroundColor DarkGray

  Write-Host ""

  Write-Host (
    "  Ambiente:   {0}" -f $environmentName
  ) -ForegroundColor $environmentColor

  Write-Host (
    "  Servidor:   {0}" -f $serverUrl
  ) -ForegroundColor Gray

  Write-Host (
    "  Documentos: {0}" -f $planItems.Count
  ) -ForegroundColor White

  # ====================================================
  # Configuracao por tipo de documento
  # ====================================================

  Write-Host ""
  Write-Host "  Configuracao por tipo:" -ForegroundColor Cyan

  foreach (
    $typeGroup in @(
      $planItems |
        Group-Object -Property DocumentType
    )
  ) {

    $groupLabel =
    [string]$typeGroup.Group[0].DisplayType

    Write-Host (
      "    {0}  ({1} documento(s))" -f
      $groupLabel,
      $typeGroup.Count
    ) -ForegroundColor White

    $sampleItem =
    $typeGroup.Group |
      Where-Object {
      $null -ne $_.Configuration
    } |
      Select-Object -First 1

    if ($null -eq $sampleItem) {

      Write-Host (
        "      Configuracao invalida. Veja os erros abaixo."
      ) -ForegroundColor Red

      continue
    }

    $typeConfiguration =
    $sampleItem.Configuration

    $clientText =
    "nenhum"

    if (
      -not [string]::IsNullOrWhiteSpace(
        [string]$typeConfiguration.ClientProperty
      ) -and
      -not [string]::IsNullOrWhiteSpace(
        [string]$typeConfiguration.ClientValue
      )
    ) {

      $clientText =
      "{0} = {1}" -f
      $typeConfiguration.ClientProperty,
      $typeConfiguration.ClientValue
    }

    Write-Host (
      "      Tipo do Item:    {0}" -f
      $typeConfiguration.ItemType
    ) -ForegroundColor Gray

    Write-Host (
      "      Tipo da Revisao: {0}" -f
      $typeConfiguration.RevisionType
    ) -ForegroundColor Gray

    Write-Host (
      "      Cliente:         {0}" -f
      $clientText
    ) -ForegroundColor Gray
  }

  # ====================================================
  # Workflows
  # ====================================================

  $approvedCount =
  @(
    $planItems |
      Where-Object {
      $_.WorkflowLabel -eq "aprovacao"
    }
  ).Count

  $obsoleteCount =
  @(
    $planItems |
      Where-Object {
      $_.WorkflowLabel -eq "obsolescencia"
    }
  ).Count

  $withoutWorkflowCount =
  $planItems.Count -
  $approvedCount -
  $obsoleteCount

  $approvedText =
  $approvedTemplate

  if (
    [string]::IsNullOrWhiteSpace(
      $approvedText
    )
  ) {
    $approvedText =
    "NAO CONFIGURADO"
  }

  $obsoleteText =
  $obsoleteTemplate

  if (
    [string]::IsNullOrWhiteSpace(
      $obsoleteText
    )
  ) {
    $obsoleteText =
    "NAO CONFIGURADO"
  }

  Write-Host ""
  Write-Host "  Workflows:" -ForegroundColor Cyan

  Write-Host (
    "    Aprovacao:     {0,3}  ({1})" -f
    $approvedCount,
    $approvedText
  ) -ForegroundColor Green

  Write-Host (
    "    Obsolescencia: {0,3}  ({1})" -f
    $obsoleteCount,
    $obsoleteText
  ) -ForegroundColor Red

  Write-Host (
    "    Sem workflow:  {0,3}" -f
    $withoutWorkflowCount
  ) -ForegroundColor Yellow

  # ====================================================
  # Lista de documentos
  # ====================================================

  Write-Host ""
  Write-Host "  Documentos:" -ForegroundColor Cyan

  $errorCount =
  0

  $missingWorkflowCount =
  0

  for (
    $index = 0
    $index -lt $planItems.Count
    $index++
  ) {

    $planItem =
    $planItems[$index]

    $workflowText =
    "sem workflow"

    $lineColor =
    [System.ConsoleColor]::Gray

    if ($null -ne $planItem.WorkflowLabel) {

      if (
        [string]::IsNullOrWhiteSpace(
          $planItem.WorkflowTemplate
        )
      ) {

        $workflowText =
        "workflow de $($planItem.WorkflowLabel) NAO CONFIGURADO"

        $lineColor =
        [System.ConsoleColor]::Yellow

        $missingWorkflowCount++
      }
      elseif ($planItem.WorkflowLabel -eq "aprovacao") {

        $workflowText =
        "workflow de aprovacao"

        $lineColor =
        [System.ConsoleColor]::Green
      }
      else {

        $workflowText =
        "workflow de obsolescencia"

        $lineColor =
        [System.ConsoleColor]::Red
      }
    }

    if ($null -ne $planItem.ConfigurationError) {

      $lineColor =
      [System.ConsoleColor]::Red

      $errorCount++
    }

    $stateText =
    $planItem.PdmState

    if (
      [string]::IsNullOrWhiteSpace(
        $stateText
      )
    ) {
      $stateText =
      "sem estado"
    }

    Write-Host (
      "  [{0}] {1} | rev {2} | {3} | {4}" -f
      ($index + 1),
      $planItem.ItemCode,
      $planItem.TeamcenterRevisionId,
      $stateText,
      $workflowText
    ) -ForegroundColor $lineColor

    if ($null -ne $planItem.ConfigurationError) {

      Write-Host (
        "       ERRO: {0}" -f
        $planItem.ConfigurationError
      ) -ForegroundColor Red
    }

    if ($Details) {

      Write-Host (
        "       Nome:     {0}" -f
        $planItem.ItemName
      ) -ForegroundColor DarkGray

      if (
        -not [string]::IsNullOrWhiteSpace(
          $planItem.RevisionText
        )
      ) {

        Write-Host (
          "       Revisao:  {0}" -f
          $planItem.RevisionText
        ) -ForegroundColor DarkGray
      }

      if (
        -not [string]::IsNullOrWhiteSpace(
          $planItem.WorkflowTemplate
        )
      ) {

        Write-Host (
          "       Template: {0}" -f
          $planItem.WorkflowTemplate
        ) -ForegroundColor DarkGray
      }

      Write-Host (
        "       Arquivo:  {0}" -f
        $planItem.FilePath
      ) -ForegroundColor DarkGray
    }
  }

  # ====================================================
  # Avisos finais
  # ====================================================

  if ($errorCount -gt 0) {

    Write-Host ""

    Write-Warn (
      "$errorCount documento(s) com erro de configuracao " +
      "vao falhar na criacao."
    )
  }

  if ($missingWorkflowCount -gt 0) {

    Write-Host ""

    Write-Warn (
      "$missingWorkflowCount documento(s) com workflow nao " +
      "configurado no .env. O Item e o PDF serao criados " +
      "sem workflow."
    )
  }

  Write-Host ""
}