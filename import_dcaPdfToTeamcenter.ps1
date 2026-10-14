# Main script: locate a DCA PDF, collect the required data, and, unless running
# in Preview mode, create the item and import the file into Teamcenter.
param(
  [string]$SearchRoot = $env:DCA_ROOT,

  [string]$SourceCode,

  [string]$ItemName,

  # SolidWorks PDM vault name. Override with DCA_VAULT_NAME.
  [string]$VaultName = $env:DCA_VAULT_NAME,

  [string]$PdmLibraryPath = $env:DCA_PDM_LIB,

  [string]$VaultCredentialPath = $env:DCA_VAULT_CREDENTIAL,

  [ValidateRange(0, 2000)]
  [int]$OutputDelayMilliseconds = 100,

  # Enumerate local files without using the PDM API.
  [switch]$NoVaultApi,

  # Mostra os arquivos individualmente durante pesquisas por pasta.
  [switch]$Details,

  # Search only; do not connect to Teamcenter or create objects.
  [switch]$Preview
)

function Import-DcaEnvironmentFile {

  param(
    [Parameter(Mandatory = $true)]
    [string]$FilePath
  )

  if (-not (
      Test-Path `
        -LiteralPath $FilePath `
        -PathType Leaf
    )) {

    throw "Arquivo de configuracao nao encontrado: '$FilePath'."
  }

  foreach (
    $line in Get-Content `
      -LiteralPath $FilePath `
      -Encoding UTF8
  ) {

    $trimmedLine = $line.Trim()

    if (
      [string]::IsNullOrWhiteSpace($trimmedLine) -or
      $trimmedLine.StartsWith("#")
    ) {
      continue
    }

    $separatorIndex =
    $trimmedLine.IndexOf("=")

    if ($separatorIndex -le 0) {
      continue
    }

    $variableName =
    $trimmedLine.Substring(
      0,
      $separatorIndex
    ).Trim()

    $variableValue =
    $trimmedLine.Substring(
      $separatorIndex + 1
    ).Trim()

    if (
      [string]::IsNullOrWhiteSpace(
        $variableName
      )
    ) {
      continue
    }

    [System.Environment]::SetEnvironmentVariable(
      $variableName,
      $variableValue,
      [System.EnvironmentVariableTarget]::Process
    )
  }
}
$environmentFilePath =
Join-Path `
  -Path $PSScriptRoot `
  -ChildPath ".env"

Import-DcaEnvironmentFile `
  -FilePath $environmentFilePath
$ErrorActionPreference = "Stop"
$script:DcaVault = $null
$script:DcaVaultTried = $false

if (-not [string]::IsNullOrWhiteSpace($env:DCA_VAULT_NAME)) {
  $VaultName = $env:DCA_VAULT_NAME
}

if (-not [string]::IsNullOrWhiteSpace($env:DCA_PDM_LIB)) {
  $PdmLibraryPath = $env:DCA_PDM_LIB
}

if (-not [string]::IsNullOrWhiteSpace($env:DCA_ROOT)) {
  $SearchRoot = $env:DCA_ROOT
}

if (-not [string]::IsNullOrWhiteSpace($env:DCA_VAULT_CREDENTIAL)) {
  $VaultCredentialPath = $env:DCA_VAULT_CREDENTIAL
}
try {
  [Console]::InputEncoding = [System.Text.Encoding]::UTF8
  [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
}
catch {
}

$teamcenterFunctionsPath = Join-Path $PSScriptRoot "functions\teamcenter_functions.ps1"

if (-not (Test-Path -LiteralPath $teamcenterFunctionsPath -PathType Leaf)) {
  Write-Host "Algo deu errado: o arquivo do helper nao foi encontrado:" -ForegroundColor Red
  Write-Host $teamcenterFunctionsPath -ForegroundColor Red
  exit 1
}

. $teamcenterFunctionsPath
$outputFunctionsPath =
Join-Path `
  -Path $PSScriptRoot `
  -ChildPath "functions\output_functions.ps1"

$pdmFunctionsPath =
Join-Path `
  -Path $PSScriptRoot `
  -ChildPath "functions\pdm_functions.ps1"

$searchFunctionsPath =
Join-Path `
  -Path $PSScriptRoot `
  -ChildPath "functions\search_functions.ps1"

$importPlanFunctionsPath =
Join-Path `
  -Path $PSScriptRoot `
  -ChildPath "functions\import_plan_functions.ps1"

$additionalFunctionFiles =
@(
  $outputFunctionsPath,
  $pdmFunctionsPath,
  $searchFunctionsPath,
  $importPlanFunctionsPath
)

foreach (
  $functionFilePath in
  $additionalFunctionFiles
) {

  if (-not (
      Test-Path `
        -LiteralPath $functionFilePath `
        -PathType Leaf
    )) {

    Write-Host (
      "Algo deu errado: arquivo de funcoes nao encontrado:"
    ) -ForegroundColor Red

    Write-Host (
      $functionFilePath
    ) -ForegroundColor Red

    exit 1
  }

  . $functionFilePath
}
$requiredFunctions =
@(
  # Saida e interface.
  "Write-Section",
  "Write-AnimatedLine",
  "Write-SearchResultLine",
  "Write-Success",
  "Write-Failure",
  "Write-Warn",
  "Write-Info",

  # PDM e cartao de dados.
  "Get-DcaVault",
  "Search-DcaVaultPdfEntries",
  "Get-DcaDiskPdfEntries",
  "Confirm-DcaLocalPdf",
  "Get-DcaPdmVariableValue",
  "Update-DcaMatchRevisionFromCard",
  "Update-DcaMatchDescriptionFromCard",

  # Pesquisa e selecao.
  "Select-DcaDocumentsFromFolder",
  "Select-DcaPdfsByFolder",
  "Select-DcaPdfByCode",

  # Preparacao e plano.
  "Copy-PdfToTemporaryFolder",
  "Get-DcaSearchCodeList",
  "Get-DcaFolderSearchMode",
  "Get-DcaFolderSearchPattern",
  "Get-DcaConfiguredEnvironmentName",
  "Show-DcaImportPlan",

  # Teamcenter.
  "Connect-Teamcenter",
  "Get-TeamcenterMethod",
  "Get-TeamcenterRevision",
  "Get-TeamcenterDataManagementService",
  "Get-TeamcenterServiceErrors",
  "Import-TeamcenterPdf",
  "New-DcaTeamcenterItem",
  "Start-TeamcenterWorkflow"
)

foreach ($requiredFunction in $requiredFunctions) {

  $loadedFunction = Get-Command -Name $requiredFunction -CommandType Function -ErrorAction SilentlyContinue

  if ($null -eq $loadedFunction) {
    Write-Host (
      "Algo deu errado: a funcao '$requiredFunction' nao foi carregada de " +
      "'$teamcenterFunctionsPath'."
    ) -ForegroundColor Red
    exit 1
  }
}

function Invoke-DcaMain {

  Write-Section -Title "Informe o que deseja pesquisar" -NoLeadingBlank

  $rootPath = $SearchRoot

  if ([string]::IsNullOrWhiteSpace($rootPath)) {
    throw "DCA_ROOT or -SearchRoot must be configured."
  }

  $searchInput =
  [string]$SourceCode

  if (
    [string]::IsNullOrWhiteSpace(
      $searchInput
    )
  ) {
    $searchInput =
    Read-Host (
      "Digite codigos separados por virgula; " +
      "use \ para pesquisar pastas ou \\ para abrir os itens"
    )
  }

  if (
    [string]::IsNullOrWhiteSpace(
      $searchInput
    )
  ) {

    throw "Nenhum codigo de pesquisa foi informado."
  }

  $requestedCodes =
  @(
    Get-DcaSearchCodeList `
      -InputText $searchInput
  )

  Write-Host ""

  Write-Host (
    "  Codigo(s) informado(s): " +
    $requestedCodes.Count
  ) -ForegroundColor Gray

  $selectedDocuments =
  [System.Collections.Generic.List[object]]::new()

  $selectedDocumentPaths =
  [System.Collections.Generic.HashSet[string]]::new(
    [System.StringComparer]::OrdinalIgnoreCase
  )
  for (
    $searchIndex = 0
    $searchIndex -lt $requestedCodes.Count
    $searchIndex++
  ) {

    $currentSearchCode =
    [string]$requestedCodes[$searchIndex]

    Write-Host ""

    Write-Host (
      "Preparando pesquisa " +
      "[$($searchIndex + 1)/$($requestedCodes.Count)]: " +
      "$currentSearchCode"
    ) -ForegroundColor Cyan

    try {
      $folderSearchMode =
      Get-DcaFolderSearchMode `
        -SearchText $currentSearchCode

      if ($folderSearchMode.IsFolderSearch) {

        $selectedPdfs =
        @(
          Select-DcaPdfsByFolder `
            -FolderPath $rootPath `
            -FolderSearch $currentSearchCode `
            -ListFolderItems:$folderSearchMode.ListFolderItems
        )
      }
      else {

        $selectedPdfs =
        @(
          Select-DcaPdfByCode `
            -FolderPath $rootPath `
            -Code $currentSearchCode
        )
      }
      if ($selectedPdfs.Count -eq 0) {

        throw (
          "Nenhum PDF foi selecionado para a pesquisa " +
          "'$currentSearchCode'."
        )
      }

      foreach ($selectedPdf in $selectedPdfs) {

        if ($null -eq $selectedPdf) {
          continue
        }

        $selectedPath =
        [string]$selectedPdf.File.FullName

        if (
          [string]::IsNullOrWhiteSpace(
            $selectedPath
          )
        ) {

          Write-Warn (
            "O resultado selecionado nao possui caminho."
          )

          continue
        }

        if (-not $selectedDocumentPaths.Add($selectedPath)) {

          Write-Warn (
            "O PDF ja foi adicionado ao lote e sera ignorado: " +
            $selectedPath
          )

          continue
        }

        $selectedDocuments.Add(
          [PSCustomObject]@{
            SearchText = $currentSearchCode
            SelectedPdf = $selectedPdf
          }
        )
      }
    }
    catch {
      Write-Warn (
        "Falha na pesquisa '$currentSearchCode': " +
        $_.Exception.Message
      )
    }
  }

  if ($selectedDocuments.Count -eq 0) {
    throw "Nenhum documento foi selecionado para importacao."
  }

  $preparedDocuments =
  [System.Collections.Generic.List[object]]::new()

  for (
    $documentIndex = 0
    $documentIndex -lt $selectedDocuments.Count
    $documentIndex++
  ) {

    $selection =
    $selectedDocuments[$documentIndex]

    $selectedPdf =
    $selection.SelectedPdf

    $documentType =
    [string]$selectedPdf.DocumentType

    $itemCodeFromFile =
    [string]$selectedPdf.SourceCode

    $documentTitle =
    [string]$selectedPdf.DocumentTitle

    if (
      $documentType -eq "NormaExterna" -and
      -not $selectedPdf.CodeParsed
    ) {

      if ($selectedPdf.FolderImport) {

        Write-Warn (
          "Codigo nao reconhecido. Arquivo ignorado: " +
          "'$($selectedPdf.File.Name)'."
        )

        continue
      }

      Write-Warn (
        "Nao foi possivel extrair o codigo da norma de " +
        "'$($selectedPdf.File.BaseName)'."
      )

      $typedCode =
      Read-Host (
        "Digite o codigo da norma " +
        "(Enter usa o nome completo)"
      )

      if (
        -not [string]::IsNullOrWhiteSpace(
          $typedCode
        )
      ) {
        $itemCodeFromFile =
        $typedCode.Trim()
      }
    }

    $clientRevision =
    [string]$selectedPdf.ClientRevision

    Write-Host ""
    Write-Host (
      "Preparando documento " +
      "[$($documentIndex + 1)/$($selectedDocuments.Count)]: " +
      "$itemCodeFromFile"
    ) -ForegroundColor Cyan

    if (
      [string]::IsNullOrWhiteSpace(
        $clientRevision
      )
    ) {

      if ($documentType -eq "NormaExterna") {

        Write-Warn (
          "A revisao da Norma Externa nao foi encontrada " +
          "no cartao de dados."
        )

        $clientRevision =
        Read-Host (
          "Digite a revisao da Norma Externa para " +
          "'$itemCodeFromFile' ou Enter para ignorar"
        )

        if (
          [string]::IsNullOrWhiteSpace(
            $clientRevision
          )
        ) {

          Write-Warn (
            "Arquivo ignorado: '$($selectedPdf.File.Name)'."
          )

          continue
        }
      }
      else {

        Write-Warn (
          "Revisao nao encontrada no nome do PDF: " +
          "'$($selectedPdf.File.Name)'."
        )

        $revisionPrompt =
        if ($documentType -eq "Processo") {
          "Digite a revisao do Processo"
        }
        else {
          "Digite a revisao do Desenho Original"
        }

        $clientRevision =
        Read-Host (
          "$revisionPrompt para '$itemCodeFromFile' " +
          "ou Enter para ignorar"
        )

        if (
          [string]::IsNullOrWhiteSpace(
            $clientRevision
          )
        ) {

          Write-Warn (
            "Arquivo ignorado: '$($selectedPdf.File.Name)'."
          )

          continue
        }
      }
    }
    $clientRevision =
    $clientRevision.Trim().ToUpper()

    $itemNameText =
    [string]$ItemName

    if (
      -not [string]::IsNullOrWhiteSpace(
        $documentTitle
      )
    ) {

      $itemNameText =
      $documentTitle.Trim()
    }

    if (
      [string]::IsNullOrWhiteSpace(
        $itemNameText
      )
    ) {

      if ($selectedPdf.FolderImport) {

        # Quando o arquivo possui somente o codigo,
        # usa o proprio codigo como nome.
        $itemNameText =
        $itemCodeFromFile

        if ($Details) {

          Write-Warn (
            "Titulo nao encontrado para '$itemCodeFromFile'. " +
            "O codigo sera usado como nome."
          )
        }
      }
      else {

        $itemNameText =
        Read-Host (
          "Digite o nome do item '$itemCodeFromFile' " +
          "(obrigatorio)"
        )
      }
    }

    if (
      [string]::IsNullOrWhiteSpace(
        $itemNameText
      )
    ) {

      Write-Warn (
        "Nome nao informado para '$itemCodeFromFile'. " +
        "O documento sera ignorado."
      )

      continue
    }

    $preparedDocuments.Add(
      [PSCustomObject]@{
        SearchText = $selection.SearchText
        SelectedPdf = $selectedPdf
        ItemCode = $itemCodeFromFile
        ItemName = $itemNameText.Trim()
        CardDescription = [string]$selectedPdf.CardDescription
        DescriptionSource = [string]$selectedPdf.DescriptionSource
        ClientRevision = $clientRevision
        DocumentType = $documentType
        DisplayType = $selectedPdf.TypeDisplayName
        PdmState = [string]$selectedPdf.PdmState
      }
    )
  }

  if ($preparedDocuments.Count -eq 0) {
    throw "Nenhum documento ficou pronto para importacao."
  }
  Write-Section -Title "Resumo do lote"

  $totalPrepared =
  $preparedDocuments.Count

  $approvedPrepared =
  @(
    $preparedDocuments |
      Where-Object {
      $_.PdmState -ieq "Aprovado"
    }
  ).Count

  $obsoletePrepared =
  @(
    $preparedDocuments |
      Where-Object {
      $_.PdmState -ieq "Obsoleto"
    }
  ).Count

  $withoutWorkflowPrepared =
  $totalPrepared -
  $approvedPrepared -
  $obsoletePrepared

  Write-Host ""
  Write-Host (
    "  Documentos preparados: $totalPrepared"
  ) -ForegroundColor White

  Write-Host (
    "  Workflow de aprovacao: $approvedPrepared"
  ) -ForegroundColor Green

  Write-Host (
    "  Workflow de obsoleto:  $obsoletePrepared"
  ) -ForegroundColor Red

  Write-Host (
    "  Sem workflow:           $withoutWorkflowPrepared"
  ) -ForegroundColor Yellow

  if ($Details -or $totalPrepared -le 10) {

    Write-Host ""

    for (
      $index = 0
      $index -lt $preparedDocuments.Count
      $index++
    ) {

      $document =
      $preparedDocuments[$index]

      Write-Host (
        "  [{0}] {1} | {2} | {3}" -f
        ($index + 1),
        $document.ItemCode,
        $document.ClientRevision,
        $document.PdmState
      ) -ForegroundColor Gray
    }
  }
  else {

    Write-Host ""
    Write-Host (
      "  Lista individual ocultada para manter a tela limpa."
    ) -ForegroundColor DarkGray

    Write-Host (
      "  Execute com -Details para mostrar todos os documentos."
    ) -ForegroundColor DarkGray
  }
  if ($Preview) {

    Show-DcaImportPlan -Documents $preparedDocuments.ToArray()

    Write-AnimatedLine ""
    Write-Success "Preview apenas. Nada foi criado no Teamcenter."

    return 0
  }

  $null =
  Connect-Teamcenter

  # ====================================================
  # Confirmacao adicional para ambiente de processo
  # ====================================================

  if (
    $script:TeamcenterEnvironment -eq "Processo"
  ) {

    Write-AnimatedLine ""

    Write-Warn (
      "Voce esta conectado ao Teamcenter de PROCESSO."
    )

    $productionConfirmation =
    Read-Host (
      "Digite PROCESSO para confirmar a criacao " +
      "no servidor normal"
    )

    if (
      $productionConfirmation.Trim() -cne "PROCESSO"
    ) {

      Write-AnimatedLine ""

      Write-Warn (
        "Operacao cancelada. Nenhum item foi criado."
      )

      return 0
    }
  }

  # ====================================================
  # Confirmacao geral do lote
  # ====================================================

  Show-DcaImportPlan -Documents $preparedDocuments.ToArray()

  Write-Section `
    -Title "Criar itens e importar documentos"

  Write-AnimatedLine ""

  Write-Warn (
    "Esta etapa vai processar $($preparedDocuments.Count) " +
    "documento(s) no Teamcenter."
  )

  $confirmation =
  Read-Host (
    "Digite SIM para continuar ou pressione Enter para abortar"
  )

  if (
    $confirmation.Trim() -ine "SIM"
  ) {

    Write-AnimatedLine ""

    Write-Warn (
      "Abortado pelo usuario. Nenhum item foi criado."
    )

    return 0
  }

  # ====================================================
  # Executar o lote
  # ====================================================

  $batchResults =
  [System.Collections.Generic.List[object]]::new()

  for (
    $index = 0
    $index -lt $preparedDocuments.Count
    $index++
  ) {

    $document =
    $preparedDocuments[$index]

    $createdCode =
    $null

    $itemCreated =
    $false

    $pdfImported =
    $false

    $workflowStarted =
    $false

    Write-AnimatedLine ""

    Write-Info (
      "Importando [$($index + 1)/$($preparedDocuments.Count)]: " +
      $document.ItemCode
    )

    try {

      # ==================================================
      # 1. Criar Item e revisao
      # ==================================================

      $teamcenterDestination =
      New-DcaTeamcenterItem `
        -SourceCode $document.ItemCode `
        -ItemName $document.ItemName `
        -ClientRevision $document.ClientRevision `
        -DocumentType $document.DocumentType

      if ($null -eq $teamcenterDestination) {

        throw (
          "New-DcaTeamcenterItem nao retornou resultado " +
          "para '$($document.ItemCode)'."
        )
      }

      $createdCode =
      [string]$teamcenterDestination.Code

      if (
        [string]::IsNullOrWhiteSpace(
          $createdCode
        )
      ) {

        throw "O codigo criado nao foi retornado."
      }

      $itemCreated =
      $true

      Write-Success (
        "Item criado: $createdCode"
      )

      # ==================================================
      # 2. Obter o Item criado
      # ==================================================

      $teamcenterItem =
      $teamcenterDestination.Item

      if ($null -ne $teamcenterItem) {

        $teamcenterItem =
        $teamcenterItem.PSObject.BaseObject
      }

      if ($null -eq $teamcenterItem) {

        throw (
          "O Item criado nao foi retornado para " +
          "'$createdCode'."
        )
      }

      # ==================================================
      # 3. Obter a revisao criada
      # ==================================================

      $teamcenterRevision =
      $teamcenterDestination.Revision

      if ($null -ne $teamcenterRevision) {

        $teamcenterRevision =
        $teamcenterRevision.PSObject.BaseObject
      }

      if ($null -eq $teamcenterRevision) {

        Write-Info (
          "Localizando a revisao do item..."
        )

        $teamcenterRevision =
        Get-TeamcenterRevision `
          -Item $teamcenterItem

        if ($null -ne $teamcenterRevision) {

          $teamcenterRevision =
          $teamcenterRevision.PSObject.BaseObject
        }
      }

      if ($null -eq $teamcenterRevision) {

        throw (
          "A revisao do Teamcenter nao foi encontrada " +
          "para '$createdCode'."
        )
      }

      $revisionTypeName =
      $teamcenterRevision.GetType().FullName

      if (
        $revisionTypeName -notmatch "ItemRevision"
      ) {

        throw (
          "O objeto retornado nao e uma revisao valida. " +
          "Tipo recebido: '$revisionTypeName'."
        )
      }

      Write-Info (
        "Revisao do Teamcenter localizada."
      )

      if ($Details) {

        Write-Info (
          "Tipo tecnico: $revisionTypeName"
        )
      }
      # ==================================================
      # 4. Garantir que o PDF esteja no cache local
      # ==================================================

      $localPdfPath =
      Confirm-DcaLocalPdf `
        -Entry $document.SelectedPdf.File

      if (
        [string]::IsNullOrWhiteSpace(
          $localPdfPath
        )
      ) {

        throw (
          "Confirm-DcaLocalPdf nao retornou o caminho " +
          "do PDF para '$createdCode'."
        )
      }

      if (-not (
          Test-Path `
            -LiteralPath $localPdfPath `
            -PathType Leaf
        )) {

        throw (
          "O PDF local nao foi encontrado para '$createdCode': " +
          "'$localPdfPath'."
        )
      }

      # ==================================================
      # 5. Copiar o PDF para a pasta temporaria
      # ==================================================

      $temporaryPdfPath =
      Copy-PdfToTemporaryFolder `
        -SourcePdfPath $localPdfPath `
        -ItemCode $createdCode

      if (
        [string]::IsNullOrWhiteSpace(
          $temporaryPdfPath
        )
      ) {

        throw (
          "Copy-PdfToTemporaryFolder nao retornou " +
          "o caminho do PDF temporario."
        )
      }

      if (-not (
          Test-Path `
            -LiteralPath $temporaryPdfPath `
            -PathType Leaf
        )) {

        throw (
          "O PDF temporario nao existe para '$createdCode': " +
          "'$temporaryPdfPath'."
        )
      }

      $temporaryPdfFile =
      Get-Item `
        -LiteralPath $temporaryPdfPath `
        -ErrorAction Stop

      if ($temporaryPdfFile.Length -le 0) {

        throw (
          "O PDF temporario de '$createdCode' esta vazio."
        )
      }

      if ($Details) {

        Write-Info (
          "PDF temporario validado: " +
          "$($temporaryPdfFile.Length) bytes"
        )
      }

      if ($Details) {

        Write-Info (
          "Arquivo temporario: " +
          $temporaryPdfPath
        )
      }
      # ==================================================
      # 6. Importar o PDF na revisao
      # ==================================================

      Write-Info (
        "Importando o PDF no Teamcenter..."
      )

      $importResult =
      Import-TeamcenterPdf `
        -Revision $teamcenterRevision `
        -ItemCode $createdCode `
        -DatasetRevision $document.ClientRevision `
        -FilePath $temporaryPdfPath

      # O metodo pode ser void e retornar NULL.
      # A ausencia de excecao indica que a chamada terminou.
      $pdfImported =
      $true

      $pdmState =
      ([string]$document.PdmState).Trim()

      $workflowTemplate =
      $null

      $workflowLabel =
      $null

      if ($pdmState -ieq "Aprovado") {

        $workflowTemplate =
        [string]$env:DCA_TC_APPROVED_WORKFLOW

        $workflowLabel =
        "aprovacao"
      }
      elseif ($pdmState -ieq "Obsoleto") {

        $workflowTemplate =
        [string]$env:DCA_TC_OBSOLETE_WORKFLOW

        $workflowLabel =
        "obsolescencia"
      }

      if ($null -eq $workflowLabel) {

        if (
          [string]::IsNullOrWhiteSpace(
            $pdmState
          )
        ) {

          Write-Info (
            "Estado do PDM nao identificado. " +
            "Nenhum workflow sera iniciado."
          )
        }
        else {

          Write-Info (
            "Estado no PDM: '$pdmState'. " +
            "Nenhum workflow configurado para esse estado."
          )
        }
      }
      elseif (
        [string]::IsNullOrWhiteSpace(
          $workflowTemplate
        )
      ) {

        Write-Warn (
          "Workflow de $workflowLabel nao configurado no .env. " +
          "O Item e o PDF foram mantidos sem workflow."
        )
      }
      else {

        Write-Info (
          "Estado no PDM: '$pdmState'. " +
          "Iniciando workflow de $workflowLabel..."
        )

        Start-TeamcenterWorkflow `
          -WorkflowTemplate $workflowTemplate `
          -Revision $teamcenterRevision

        $workflowStarted =
        $true

        Write-Success (
          "Workflow de $workflowLabel solicitado."
        )
      }

      # ==================================================
      # 7. Registrar sucesso
      # ==================================================

      $batchResults.Add(
        [PSCustomObject]@{
          SearchText = $document.SearchText
          ItemCode = $document.ItemCode
          ItemName = $document.ItemName
          TeamcenterCode = $createdCode
          ItemCreated = $itemCreated
          PdfImported = $pdfImported
          PdmState = $pdmState
          WorkflowStarted = $workflowStarted
          Succeeded = $true
          ErrorMessage = $null
        }
      )
    }
    catch {
      if ($Details) {
        $errorRecord =
        $_

        $errorLine =
        $errorRecord.InvocationInfo.ScriptLineNumber

        $errorFile =
        [string]$errorRecord.InvocationInfo.ScriptName

        $errorCode =
        [string]$errorRecord.InvocationInfo.Line

        $errorStack =
        [string]$errorRecord.ScriptStackTrace

        Write-Host ""

        Write-Host (
          "  Diagnostico tecnico da falha:"
        ) -ForegroundColor Yellow

        Write-Host (
          "    Arquivo: $errorFile"
        ) -ForegroundColor DarkGray

        Write-Host (
          "    Linha:   $errorLine"
        ) -ForegroundColor DarkGray

        Write-Host (
          "    Comando: $($errorCode.Trim())"
        ) -ForegroundColor DarkGray

        Write-Host (
          "    Erro:    $($errorRecord.Exception.Message)"
        ) -ForegroundColor Red

        if (
          -not [string]::IsNullOrWhiteSpace(
            $errorStack
          )
        ) {

          Write-Host (
            "    Stack:"
          ) -ForegroundColor DarkGray

          Write-Host (
            $errorStack
          ) -ForegroundColor DarkGray
        }

        Write-Host ""
      }
      $batchResults.Add(
        [PSCustomObject]@{
          SearchText = $document.SearchText
          ItemCode = $document.ItemCode
          ItemName = $document.ItemName
          TeamcenterCode = $createdCode
          ItemCreated = $itemCreated
          PdfImported = $pdfImported
          Succeeded = $false
          ErrorMessage = $_.Exception.Message
        }
      )

      Write-Failure (
        "$($document.ItemCode): " +
        $_.Exception.Message
      )

      # Uma falha nao interrompe os outros documentos.
      continue
    }
  }

  # ====================================================
  # Resumo final
  # ====================================================

  Write-Section `
    -Title "Resumo da importacao"

  Write-AnimatedLine ""

  foreach ($result in $batchResults) {

    if (
      $result.ItemCreated -and
      $result.PdfImported
    ) {

      $successMessage =
      "$($result.ItemCode) -> " +
      "$($result.TeamcenterCode) - " +
      "Item e PDF importados"

      if ($result.WorkflowStarted) {

        $successMessage +=
        " - workflow solicitado"
      }

      Write-Success $successMessage
    }
    elseif (
      $result.ItemCreated -and
      -not $result.PdfImported
    ) {

      Write-Failure (
        "$($result.ItemCode) -> Item criado, " +
        "mas PDF nao importado: " +
        $result.ErrorMessage
      )
    }
    else {

      Write-Failure (
        "$($result.ItemCode) -> Item nao criado: " +
        $result.ErrorMessage
      )
    }
  }
  $successCount =
  @(
    $batchResults |
      Where-Object {
      $_.Succeeded
    }
  ).Count

  $failureCount =
  @(
    $batchResults |
      Where-Object {
      -not $_.Succeeded
    }
  ).Count

  Write-AnimatedLine ""

  Write-Host (
    "  Importados: $successCount"
  ) -ForegroundColor Green

  Write-Host (
    "  Falharam:   $failureCount"
  ) -ForegroundColor Yellow

  Write-Host (
    "  Total:      $($batchResults.Count)"
  ) -ForegroundColor Gray

  if ($failureCount -gt 0) {
    return 1
  }

  return 0
}

$exitCode = 1

try {
  $exitCode = @(Invoke-DcaMain) | Select-Object -Last 1
}
catch {

  Write-Failure $_.Exception.Message

  $exitCode = 1
}

exit ([int]$exitCode)
