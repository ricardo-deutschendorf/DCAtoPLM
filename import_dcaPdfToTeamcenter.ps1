# ============================================================
# DCAtoPLM - Importacao de PDFs do PDM para o Teamcenter
# ============================================================
#
# Responsabilidades deste script:
#   1. Carregar e validar a configuracao local.
#   2. Pesquisar e selecionar PDFs no Vault DCA.
#   3. Ler codigo, revisao, descricao e estado do cartao.
#   4. Preparar e exibir o plano de importacao.
#   5. Localizar ou criar o destino no Teamcenter.
#   6. Importar o PDF como Dataset.
#   7. Iniciar o workflow quando aplicavel.
#   8. Apresentar o resumo final do lote.
#
# Os detalhes de PDM, pesquisa, saida e Teamcenter permanecem
# separados nos arquivos da pasta functions.
# ============================================================

# ============================================================
# PARAMETROS DE EXECUCAO
# ============================================================
param(
  [string]$SearchRoot = $env:DCA_ROOT,

  [string]$SourceCode,

  [string]$ItemName,

  # Nome da view local do Vault. O valor do .env tem prioridade.
  [string]$VaultName = $env:DCA_VAULT_NAME,

  [string]$PdmLibraryPath = $env:DCA_PDM_LIB,

  [string]$VaultCredentialPath = $env:DCA_VAULT_CREDENTIAL,

  [ValidateRange(0, 2000)]
  [int]$OutputDelayMilliseconds = 10,

  # Ignora a API do PDM e pesquisa somente nos arquivos locais.
  [switch]$NoVaultApi,

  # Exibe caminhos, propriedades tecnicas e diagnosticos adicionais.
  [switch]$Details,

  # Valida o lote sem criar objetos no Teamcenter.
  [switch]$Preview
)

# ============================================================
# CONFIGURACAO E ESTADO DA EXECUCAO
# ============================================================
#
# O arquivo .env e carregado no escopo do processo atual.
# As variaveis ficam disponiveis para o script principal e
# para todos os arquivos carregados por dot source.
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

# O .env deve permanecer fora do repositorio porque pode conter
# caminhos internos, usuarios, servidores e credenciais.
$environmentFilePath =
Join-Path `
  -Path $PSScriptRoot `
  -ChildPath ".env"

Import-DcaEnvironmentFile `
  -FilePath $environmentFilePath

$ErrorActionPreference =
"Stop"

# Estado compartilhado pela execucao atual.
#
# DcaVault:
#   Mantem a conexao autenticada com o Vault.
#
# DcaVaultTried:
#   Impede tentativas repetidas de conexao quando o Vault nao
#   estiver disponivel.
#
# TeamcenterItemLookupCache:
#   Evita consultar repetidamente o mesmo codigo no Teamcenter.
$script:DcaVault = $null
$script:DcaVaultTried = $false

# Armazena o resultado das consultas de existencia no Teamcenter.
# Evita consultar o mesmo Item mais de uma vez durante a execucao.
$script:TeamcenterItemLookupCache =
[System.Collections.Generic.Dictionary[string, object]]::new(
  [System.StringComparer]::OrdinalIgnoreCase
)

# Os valores do .env possuem prioridade sobre os parametros
# definidos na assinatura do script.
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

# Mantem a entrada e a saida do console em UTF-8.
# A falha desta configuracao nao deve interromper a importacao.
try {
  [Console]::InputEncoding = [System.Text.Encoding]::UTF8
  [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
}
catch {
}

# ============================================================
# CARREGAMENTO DOS ARQUIVOS DE FUNCOES
# ============================================================
$functionFiles =
@(
  "output_functions.ps1",
  "pdm_functions.ps1",
  "search_functions.ps1",
  "import_plan_functions.ps1",
  "teamcenter_functions.ps1"
)

foreach ($functionFileName in $functionFiles) {

  $functionFilePath =
  Join-Path `
    -Path $PSScriptRoot `
    -ChildPath (
    Join-Path `
      -Path "functions" `
      -ChildPath $functionFileName
  )

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

# Valida antecipadamente as funcoes obrigatorias para evitar
# falhas somente no meio da importacao.
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
  "Select-DcaDocumentsWithFolderNavigation",
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
  "Show-DcaTeamcenterLookupMethods",
  "Import-TeamcenterQueryAssemblies",
  "Show-TeamcenterQueryServiceTypes",
  "Show-TeamcenterSavedQueryTypeDetails",
  "Get-TeamcenterRevision",
  "Get-TeamcenterModelPropertyText",
  "Test-DcaTeamcenterItemExists",
  "Find-DcaTeamcenterItemBySavedQuery",
  "Find-DcaTeamcenterItemRevision",
  "Get-TeamcenterDataManagementService",
  "Get-TeamcenterServiceErrors",
  "Import-TeamcenterPdf",
  "New-DcaTeamcenterItem",
  "Start-TeamcenterWorkflow"
)

$missingFunctions =
[System.Collections.Generic.List[string]]::new()

foreach ($requiredFunction in $requiredFunctions) {

  $loadedFunction =
  Get-Command `
    -Name $requiredFunction `
    -CommandType Function `
    -ErrorAction SilentlyContinue

  if ($null -eq $loadedFunction) {

    $missingFunctions.Add(
      $requiredFunction
    )
  }
}

if ($missingFunctions.Count -gt 0) {

  Write-Host (
    "Algo deu errado: uma ou mais funcoes obrigatorias " +
    "nao foram carregadas."
  ) -ForegroundColor Red

  foreach ($missingFunction in $missingFunctions) {

    Write-Host (
      "  - $missingFunction"
    ) -ForegroundColor Red
  }

  exit 1
}

# ============================================================
# FLUXO PRINCIPAL
# ============================================================
function Invoke-DcaMain {

  # ============================================================
  # 1. RECEBER E VALIDAR A PESQUISA
  # ============================================================
  Write-Section -Title "Informe o que deseja pesquisar" -NoLeadingBlank

  $rootPath =
  [string]$SearchRoot

  if (
    [string]::IsNullOrWhiteSpace(
      $rootPath
    )
  ) {

    throw (
      "DCA_ROOT ou o parametro -SearchRoot deve ser configurado."
    )
  }

  if (-not (
      Test-Path `
        -LiteralPath $rootPath `
        -PathType Container
    )) {

    throw (
      "A raiz de pesquisa nao foi encontrada: " +
      "'$rootPath'."
    )
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
      "use \NomeCompleto para importar uma pasta ou " +
      "\\NomeCompleto para escolher os itens"
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

  # ============================================================
  # 2. PESQUISAR E SELECIONAR OS PDFs
  # ============================================================
  $selectedDocuments =
  [System.Collections.Generic.List[object]]::new()

  # Impede que o mesmo PDF seja adicionado mais de uma vez quando
  # diferentes pesquisas retornarem o mesmo caminho.
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

  # ============================================================
  # 3. NORMALIZAR OS DOCUMENTOS SELECIONADOS
  # ============================================================
  #
  # Consolida codigo, nome, revisao, tipo e estado antes da
  # conexao com o Teamcenter.
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
      }
      elseif ($documentType -eq "DatasetOnly") {

        Write-Warn (
          "A revisao do documento dimensional nao foi encontrada " +
          "no cartao de dados."
        )

        $clientRevision =
        Read-Host (
          "Digite a revisao existente no Teamcenter para " +
          "'$itemCodeFromFile' ou Enter para ignorar"
        )
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
      }

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

    $clientRevision =
    $clientRevision.Trim().ToUpperInvariant()

    # A descricao do cartao tem prioridade sobre o nome informado
    # manualmente e sera usada como nome e descricao no Teamcenter.
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

        # Em importacoes por pasta nao ha interacao individual.
        # Se o cartao nao possuir descricao, o codigo evita que todo
        # o lote seja interrompido por falta de nome.
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
        SelectedPdf = $selectedPdf
        ItemCode = $itemCodeFromFile
        ItemName = $itemNameText.Trim()
        ClientRevision = $clientRevision
        DocumentType = $documentType
        DisplayType = $selectedPdf.TypeDisplayName
        PdmState = [string]$selectedPdf.PdmState
        TeamcenterItem = $selectedPdf.TeamcenterItem
        TeamcenterRevision = $selectedPdf.TeamcenterRevision
      }
    )
  }

  if ($preparedDocuments.Count -eq 0) {
    throw "Nenhum documento ficou pronto para importacao."
  }

  # ============================================================
  # 4. APRESENTAR O RESUMO DO LOTE
  # ============================================================
  Write-Section -Title "Resumo do lote"

  $totalPrepared =
  $preparedDocuments.Count

  $datasetOnlyPrepared =
  @(
    $preparedDocuments |
      Where-Object {
      $_.DocumentType -eq "DatasetOnly"
    }
  ).Count

  $approvedPrepared =
  @(
    $preparedDocuments |
      Where-Object {
      $_.DocumentType -ne "DatasetOnly" -and
      $_.PdmState -ieq "Aprovado"
    }
  ).Count

  $obsoletePrepared =
  @(
    $preparedDocuments |
      Where-Object {
      $_.DocumentType -ne "DatasetOnly" -and
      $_.PdmState -ieq "Obsoleto"
    }
  ).Count

  $withoutWorkflowPrepared =
  $totalPrepared -
  $approvedPrepared -
  $obsoletePrepared -
  $datasetOnlyPrepared

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

  Write-Host (
    "  Somente Dataset:        $datasetOnlyPrepared"
  ) -ForegroundColor Cyan

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

  # ============================================================
  # 5. CONECTAR E VALIDAR OS DESTINOS EXISTENTES
  # ============================================================
  $null =
  Connect-Teamcenter

  # Consulta somente os documentos que adicionam Dataset em uma
  # revisao existente. Isso evita consultar centenas de Items antes
  # que o usuario selecione os documentos desejados.
  foreach ($document in $preparedDocuments) {

    if ($document.DocumentType -ne "DatasetOnly") {
      continue
    }

    Write-Info (
      "Consultando no Teamcenter: " +
      "$($document.ItemCode), revisao $($document.ClientRevision)"
    )

    $lookupResult =
    Find-DcaTeamcenterItemRevision `
      -ItemCode $document.ItemCode `
      -ExpectedRevision $document.ClientRevision

    Write-Info (
      "Resultado da consulta: " +
      "status='$($lookupResult.Status)', " +
      "revisao esperada='$($lookupResult.ExpectedRevision)', " +
      "revisao encontrada='$($lookupResult.FoundRevision)'."
    )

    if (
      -not [string]::IsNullOrWhiteSpace(
        [string]$lookupResult.ErrorMessage
      )
    ) {

      Write-Warn (
        "Detalhe da consulta: " +
        $lookupResult.ErrorMessage
      )
    }

    Add-Member `
      -InputObject $document `
      -NotePropertyName "TeamcenterStatus" `
      -NotePropertyValue ([string]$lookupResult.Status) `
      -Force

    $document.TeamcenterItem =
    $lookupResult.Item

    $document.TeamcenterRevision =
    $lookupResult.Revision

    if ($lookupResult.Status -eq "Sim") {

      Write-Success (
        "Item e revisao encontrados: " +
        "$($document.ItemCode)/$($document.ClientRevision)"
      )
    }
    else {

      Write-Warn (
        "Destino nao localizado para '$($document.ItemCode)': " +
        $lookupResult.ErrorMessage
      )
    }
  }

  # Interrompe o fluxo antes da confirmacao quando algum documento
  # que depende de uma revisao existente nao possui destino valido.
  $unavailableDatasetDestinations =
  @(
    $preparedDocuments |
      Where-Object {
      $_.DocumentType -eq "DatasetOnly" -and
      (
        $_.TeamcenterStatus -ne "Sim" -or
        $null -eq $_.TeamcenterRevision
      )
    }
  )

  if ($unavailableDatasetDestinations.Count -gt 0) {

    Write-AnimatedLine ""

    foreach (
      $unavailableDocument in
      $unavailableDatasetDestinations
    ) {

      Write-Failure (
        "Destino indisponivel: " +
        "$($unavailableDocument.ItemCode)/" +
        "$($unavailableDocument.ClientRevision)"
      )
    }

    throw (
      "A importacao foi interrompida antes da confirmacao porque " +
      "$($unavailableDatasetDestinations.Count) destino(s) de " +
      "Dataset nao foram validados no Teamcenter."
    )
  }

  # ============================================================
  # PROTECAO PARA O AMBIENTE DE PROCESSO
  # ============================================================
  # Exige uma confirmacao exclusiva antes da confirmacao geral
  # para reduzir o risco de criacao acidental no ambiente oficial.

  if (
    $script:TeamcenterEnvironment -eq "Processo"
  ) {

    Write-AnimatedLine ""

    Write-Warn (
      "Voce esta conectado ao Teamcenter de PROCESSO."
    )

    $productionConfirmation =
    Read-Host (
      "Digite PROCESSO para confirmar o processamento " +
      "no servidor normal"
    )

    if (
      $productionConfirmation.Trim() -cne "PROCESSO"
    ) {

      Write-AnimatedLine ""

      Write-Warn (
        "Operacao cancelada. Nenhuma alteracao foi realizada."
      )

      return 0
    }
  }

  # ============================================================
  # VALIDACAO FINAL ANTES DA CRIACAO
  # ============================================================
  # O plano e exibido novamente depois da conexao para garantir
  # que o usuario veja o ambiente e os documentos que serao criados.

  Show-DcaImportPlan -Documents $preparedDocuments.ToArray()

  $datasetOnlyCount =
  @(
    $preparedDocuments |
      Where-Object {
      $_.DocumentType -eq "DatasetOnly"
    }
  ).Count

  $createItemCount =
  $preparedDocuments.Count -
  $datasetOnlyCount

  Write-Section `
    -Title "Processar documentos no Teamcenter"

  Write-AnimatedLine ""

  Write-Warn (
    "Esta etapa vai processar $($preparedDocuments.Count) " +
    "documento(s) no Teamcenter: $createItemCount com criacao " +
    "de Item e $datasetOnlyCount somente como Dataset."
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
      "Abortado pelo usuario. Nenhuma alteracao foi realizada."
    )

    return 0
  }

  # ============================================================
  # EXECUCAO DO LOTE
  # ============================================================
  # Cada documento possui tratamento de erro independente.
  # Uma falha individual nao interrompe os documentos seguintes.

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

    # ==================================================
    # 1. Localizar ou criar o destino no Teamcenter
    # ==================================================
    try {

      $teamcenterItem =
      $null

      $teamcenterRevision =
      $null

      if ($document.DocumentType -eq "DatasetOnly") {

        # O Item e a revisao ja existem. O script utiliza os objetos
        # encontrados anteriormente e importa somente o Dataset.
        $createdCode =
        [string]$document.ItemCode

        $teamcenterItem =
        $document.TeamcenterItem

        $teamcenterRevision =
        $document.TeamcenterRevision

        if (
          $document.TeamcenterStatus -ne "Sim" -or
          $null -eq $teamcenterRevision
        ) {

          $statusText =
          [string]$document.TeamcenterStatus

          if (
            [string]::IsNullOrWhiteSpace(
              $statusText
            )
          ) {

            $statusText =
            "nao informado"
          }

          throw (
            "O destino '$createdCode/$($document.ClientRevision)' " +
            "nao esta disponivel para receber o Dataset. " +
            "Status da consulta: '$statusText'."
          )
        }
        if ($null -ne $teamcenterItem) {

          $itemBaseObject =
          $teamcenterItem.PSObject.BaseObject

          if ($null -ne $itemBaseObject) {

            $teamcenterItem =
            $itemBaseObject
          }
        }

        $revisionBaseObject =
        $teamcenterRevision.PSObject.BaseObject

        if ($null -ne $revisionBaseObject) {

          $teamcenterRevision =
          $revisionBaseObject
        }

        if ($null -eq $teamcenterRevision) {

          throw (
            "A revisao existente ficou NULL para '$createdCode'."
          )
        }

        # Neste fluxo nenhum Item novo foi criado.
        $itemCreated =
        $false

        Write-Success (
          "Destino existente localizado: " +
          "$createdCode/$($document.ClientRevision)"
        )
      }
      else {

        # Para os demais tipos, cria o Item e a revisao normalmente.
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

        $itemCreated =
        $true

        Write-Success (
          "Item criado: $createdCode"
        )
      }

      # ==================================================
      # 2. Validar a revisao de destino
      # ==================================================

      $revisionTypeName =
      $teamcenterRevision.GetType().FullName

      $isRevisionObject =
      $revisionTypeName -match
      '(?i)(ItemRevision|Revision)$'

      if (-not $isRevisionObject) {

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
      # 3. Garantir que o PDF esteja no cache local
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
      # 4. Preparar uma copia local validada para o importador
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

        Write-Info (
          "Arquivo temporario: " +
          $temporaryPdfPath
        )
      }
      # ==================================================
      # 5. Importar o PDF na revisao
      # ==================================================

      # Para documentos dimensionais, o Dataset usa o codigo do Item
      # existente. Para os demais documentos, usa o codigo efetivamente
      # criado no Teamcenter.
      $datasetName =
      if ($document.DocumentType -eq "DatasetOnly") {

        [string]$document.ItemCode
      }
      else {

        [string]$createdCode
      }

      $datasetName =
      $datasetName.Trim()

      if (
        [string]::IsNullOrWhiteSpace(
          $datasetName
        )
      ) {

        throw (
          "Nao foi possivel definir o nome do Dataset para " +
          "'$($document.ItemCode)'."
        )
      }
      Write-Info (
        "Importando o PDF no Teamcenter..."
      )

      Write-Info (
        "Nome do Dataset: '$datasetName'"
      )

      Write-Info (
        "Revisao do Dataset: '$($document.ClientRevision)'"
      )

      $pdfImportResult =
      Import-TeamcenterPdf `
        -Revision $teamcenterRevision `
        -ItemCode $createdCode `
        -DatasetName $datasetName `
        -DatasetRevision $document.ClientRevision `
        -FilePath $temporaryPdfPath

      if ($Details) {

        Write-Info (
          "Retorno do ImportarPDF: " +
          "'$([string]$pdfImportResult)'"
        )
      }

      # ImportarPDF retorna uma mensagem textual. A ausencia de
      # excecao indica que a chamada ao importador foi concluida.
      $pdfImported =
      $true

      # ==================================================
      # 6. Iniciar o workflow quando aplicavel
      # ==================================================
      $pdmState =
      ([string]$document.PdmState).Trim()

      if ($document.DocumentType -eq "DatasetOnly") {

        Write-Info (
          "Documento dimensional: somente o Dataset sera importado. " +
          "Nenhum workflow sera iniciado."
        )

        $workflowStarted =
        $false
      }

      $workflowTemplate =
      $null

      $workflowLabel =
      $null

      if (
        $document.DocumentType -ne "DatasetOnly" -and
        $pdmState -ieq "Aprovado"
      ) {

        $workflowTemplate =
        [string]$env:DCA_TC_APPROVED_WORKFLOW

        $workflowLabel =
        "aprovacao"
      }
      elseif (
        $document.DocumentType -ne "DatasetOnly" -and
        $pdmState -ieq "Obsoleto"
      ) {

        $workflowTemplate =
        [string]$env:DCA_TC_OBSOLETE_WORKFLOW

        $workflowLabel =
        "obsolescencia"
      }

      if ($document.DocumentType -eq "DatasetOnly") {

        # O documento dimensional apenas recebe o Dataset.
        # Nenhum workflow e iniciado nesse fluxo.
      }
      elseif ($null -eq $workflowLabel) {

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
      # 7. Registrar o resultado para o resumo final
      # ==================================================
      $batchResults.Add(
        [PSCustomObject]@{
          ItemCode = $document.ItemCode
          ItemName = $document.ItemName
          TeamcenterCode = $createdCode
          Operation = if (
            $document.DocumentType -eq "DatasetOnly"
          ) {
            "DatasetOnly"
          }
          else {
            "CreateItem"
          }
          ItemCreated = $itemCreated
          PdfImported = $pdfImported
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
          ItemCode = $document.ItemCode
          ItemName = $document.ItemName
          TeamcenterCode = $createdCode
          Operation = if (
            $document.DocumentType -eq "DatasetOnly"
          ) {
            "DatasetOnly"
          }
          else {
            "CreateItem"
          }
          ItemCreated = $itemCreated
          PdfImported = $pdfImported
          WorkflowStarted = $workflowStarted
          Succeeded = $false
          ErrorMessage = $_.Exception.Message
        }
      )

      Write-Failure (
        "$($document.ItemCode): " +
        $_.Exception.Message
      )

      # O lote continua mesmo que um documento falhe. O erro sera
      # consolidado no resumo final.
      continue
    }
  }

  # ============================================================
  # RESUMO FINAL E CODIGO DE SAIDA
  # ============================================================

  Write-Section `
    -Title "Resumo da importacao"

  Write-AnimatedLine ""

  foreach ($result in $batchResults) {

    if (
      $result.Operation -eq "DatasetOnly" -and
      $result.PdfImported
    ) {

      Write-Success (
        "$($result.ItemCode) -> " +
        "$($result.TeamcenterCode)"
      )

      continue
    }

    if (
      $result.Operation -eq "DatasetOnly" -and
      -not $result.PdfImported
    ) {

      Write-Failure (
        "$($result.ItemCode) -> Dataset nao importado: " +
        $result.ErrorMessage
      )

      continue
    }

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

# ============================================================
# PONTO DE ENTRADA E CODIGO DE SAIDA
# ============================================================
#
# Codigo 0:
#   Todos os documentos foram processados com sucesso ou a
#   operacao foi cancelada antes de efetuar alteracoes.
#
# Codigo 1:
#   O fluxo principal falhou ou pelo menos um documento do
#   lote nao foi processado com sucesso.
$exitCode = 1

try {
  $exitCode = @(Invoke-DcaMain) | Select-Object -Last 1
}
catch {

  Write-Failure $_.Exception.Message

  $exitCode = 1
}

exit ([int]$exitCode)
