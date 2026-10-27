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
#
# Os caminhos abaixo sao relativos a pasta raiz do projeto,
# representada por $PSScriptRoot.
#
# Os modulos sao carregados por responsabilidade e em uma ordem
# previsivel:
#   1. interface do console;
#   2. integracao com o PDM;
#   3. preparacao e apresentacao do plano;
#   4. pesquisa e selecao dos documentos;
#   5. integracao com o Teamcenter.
#
# Cada caminho e relativo a pasta raiz representada por
# $PSScriptRoot.

$functionFiles =
@(
  # Saida e interface.
  "functions\output_functions.ps1",

  # Logs da execucao e relatorio CSV do lote.
  "functions\reporting_functions.ps1",

  # PDM: conexao, arquivos, nomes e cartoes de dados.
  "functions\pdm_modules\pdm_connection.ps1",
  "functions\pdm_modules\pdm_files.ps1",
  "functions\pdm_modules\pdm_filename_parser.ps1",
  "functions\pdm_modules\pdm_card_reader.ps1",
  "functions\pdm_modules\pdm_document_metadata.ps1",

  # Preparacao do PDF, entrada da pesquisa e plano.
  "functions\import_plan_modules\import_pdf_preparation.ps1",
  "functions\import_plan_modules\import_search_input.ps1",
  "functions\import_plan_modules\import_plan_display.ps1",

  # Pesquisa e selecao dos documentos.
  "functions\search_modules\search_folder_documents.ps1",
  "functions\search_modules\search_folder_navigation.ps1",
  "functions\search_modules\search_folder_selection.ps1",
  "functions\search_modules\search_folder_lookup.ps1",
  "functions\search_modules\search_code_lookup.ps1",

  # Teamcenter: estado, conexao, consultas, criacao e workflow.
  "functions\teamcenter_modules\teamcenter_state.ps1",
  "functions\teamcenter_modules\teamcenter_connections.ps1",
  "functions\teamcenter_modules\teamcenter_query_diagnostics.ps1",
  "functions\teamcenter_modules\teamcenter_query_properties.ps1",
  "functions\teamcenter_modules\teamcenter_item_lookup.ps1",
  "functions\teamcenter_modules\teamcenter_dataset.ps1",
  "functions\teamcenter_modules\teamcenter_creation_helpers.ps1",
  "functions\teamcenter_modules\teamcenter_creation.ps1",
  "functions\teamcenter_modules\teamcenter_workflow.ps1"
)

# Valida cada arquivo antes do dot source. Se um modulo estiver
# ausente, o fluxo e interrompido antes de qualquer pesquisa,
# conexao ou alteracao externa.
foreach ($functionRelativePath in $functionFiles) {

  $functionFilePath =
  Join-Path `
    -Path $PSScriptRoot `
    -ChildPath $functionRelativePath

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

# Verifica se todas as funcoes exigidas pelo fluxo estao disponiveis.
# Essa validacao confirma tanto a existencia dos arquivos quanto a
# presenca das funcoes esperadas dentro de cada modulo.
#
# A execucao e interrompida antes da pesquisa caso alguma funcao
# obrigatoria nao tenha sido carregada.
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

  # Logs e relatorios.
  "Initialize-DcaExecutionArtifacts",
  "Stop-DcaExecutionLog",
  "Export-DcaBatchReport",

  # PDM e cartao de dados.
  "Get-DcaVault",
  "Get-NormaCodeFromText",
  "ConvertFrom-PdfFileName",
  "Test-DcaCodeMatch",
  "Get-DcaPdmFileState",
  "Get-DcaPdmCardVariableValue",
  "Get-DcaPdmCardVariables",
  "Show-DcaPdmCardVariables",
  "Get-DcaCardRevisionVariableNames",
  "Convert-DcaOriginalDescription",
  "Search-DcaVaultPdfEntries",
  "Get-DcaDiskPdfEntries",
  "Confirm-DcaLocalPdf",
  "Get-DcaPdmVariableValue",
  "Update-DcaMatchRevisionFromCard",
  "Update-DcaMatchDescriptionFromCard",

  # Pesquisa e selecao.
  "Get-DcaDocumentsFromFolderPath",
  "Select-DcaDocumentsWithFolderNavigation",
  "Select-DcaDocumentsFromFolder",
  "Select-DcaPdfsByFolder",
  "Select-DcaPdfByCode",

  # Preparacao e plano.
  "Copy-PdfToTemporaryFolder",
  "Get-DcaSearchCodeList",
  "Get-DcaFolderSearchMode",
  "Test-DcaFolderSearch",
  "Get-DcaFolderSearchPattern",
  "Get-DcaConfiguredEnvironmentName",
  "Show-DcaImportPlan",

  # Teamcenter: conexao, consultas, configuracao dos tipos,
  # construcao das entradas SOA, criacao, Dataset e workflow.
  "Confirm-TeamcenterImporter",
  "Get-TeamcenterSettings",
  "Connect-Teamcenter",
  "Get-TeamcenterMethod",
  "Get-TeamcenterConnection",
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
  "Get-DcaClientRevisionInfo",
  "Get-DcaTypeConfiguration",
  "Get-DcaIntegerPropertyNames",
  "Get-DcaCreateInputPropertyText",
  "New-DcaCreateInputObject",
  "Get-DcaCreatedObjects",
  "Set-DcaObjectMemberValue",
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

  # Coordena o fluxo completo da execucao.
  #
  # As operacoes especificas permanecem nos modulos da pasta
  # functions. Esta funcao controla apenas a sequencia geral:
  # pesquisa, preparacao, confirmacao, importacao e resumo.

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

    # A revisao encontrada no cartao de dados ou no nome do arquivo
    # tem prioridade. A entrada manual ocorre somente quando nenhuma
    # revisao tiver sido identificada automaticamente.
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

    # A descricao obtida do cartao de dados tem prioridade sobre o
    # parametro -ItemName. Quando nenhuma descricao estiver disponivel,
    # o fluxo solicita um nome ou utiliza o codigo em importacoes por pasta.
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

  # Somente documentos do tipo DatasetOnly precisam localizar
  # antecipadamente um Item e uma revisao existentes. Os demais
  # documentos criam um novo Item durante a execucao do lote.
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

  # Impede que o lote avance para a confirmacao quando algum
  # documento DatasetOnly nao possui Item e revisao de destino
  # devidamente localizados no Teamcenter.
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
  # 6. VALIDACAO FINAL E CONFIRMACAO DO USUARIO
  # ============================================================

  # O plano e apresentado novamente depois da conexao para que o
  # usuario confira o ambiente real, os documentos e as operacoes
  # antes da unica confirmacao que permite alterar o Teamcenter.
  if (
    $script:TeamcenterEnvironment -eq "Processo"
  ) {

    Write-AnimatedLine ""

    Write-Warn (
      "ATENCAO: o processamento sera realizado no " +
      "Teamcenter de PROCESSO."
    )
  }

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
  # 7. EXECUCAO DO LOTE
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

    # Registra o inicio do processamento individual para calcular
    # a duracao apresentada no relatorio CSV.
    $documentStartedAt =
    Get-Date

    # Estado individual do documento atual.
    #
    # Os indicadores abaixo permitem diferenciar:
    #   - falha durante a criacao do Item;
    #   - Item criado com falha na importacao do PDF;
    #   - PDF importado com falha no workflow;
    #   - processamento totalmente concluido.
    #
    # Os valores sao registrados em $batchResults mesmo quando uma
    # das etapas do documento atual falha.
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
    # A. Localizar ou criar o destino no Teamcenter
    # ==================================================

    # DatasetOnly reutiliza um Item existente. Os demais tipos
    # criam um novo Item e uma nova revisao.
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
      # B. Validar a revisao de destino
      # ==================================================

      # A importacao do PDF e o workflow exigem um objeto de revisao
      # valido, incluindo tipos especializados derivados de ItemRevision.
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
      # C. Garantir que o PDF esteja no cache local
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
      # D. Preparar uma copia local validada para o importador
      # ==================================================

      # O Importar GD recebe uma copia local independente do cache
      # do Vault. O arquivo e validado antes da chamada ao importador.
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
      # E. Importar o PDF na revisao
      # ==================================================

      # Define o identificador do Dataset enviado ao ImportarPDF.
      # DatasetOnly utiliza o codigo do Item existente. Os demais
      # documentos utilizam o codigo criado no Teamcenter.
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
      # F. Iniciar o workflow quando aplicavel
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

        # Nenhuma acao adicional e necessaria para DatasetOnly.
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
      # G. Registrar o resultado para o resumo final
      # ==================================================
      $documentFinishedAt =
      Get-Date

      $documentDuration =
      $documentFinishedAt -
      $documentStartedAt

      $batchResults.Add(
        [PSCustomObject]@{
          ItemCode = $document.ItemCode
          ItemName = $document.ItemName
          TeamcenterCode = $createdCode
          ClientRevision = $document.ClientRevision
          DocumentType = $document.DocumentType
          PdmState = $document.PdmState
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
          DocumentStartedAt = $documentStartedAt.ToString(
            "yyyy-MM-dd HH:mm:ss"
          )
          DocumentFinishedAt = $documentFinishedAt.ToString(
            "yyyy-MM-dd HH:mm:ss"
          )
          DurationSeconds = [Math]::Round(
            $documentDuration.TotalSeconds,
            2
          )
          SourceFile = [string]$document.SelectedPdf.File.FullName
          ErrorMessage = $null
        }
      )
    }
    # Uma falha neste documento e registrada no lote, mas nao
    # interrompe o processamento dos documentos seguintes.
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
      $documentFinishedAt =
      Get-Date

      $documentDuration =
      $documentFinishedAt -
      $documentStartedAt

      $batchResults.Add(
        [PSCustomObject]@{
          ItemCode = $document.ItemCode
          ItemName = $document.ItemName
          TeamcenterCode = $createdCode
          ClientRevision = $document.ClientRevision
          DocumentType = $document.DocumentType
          PdmState = $document.PdmState
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
          DocumentStartedAt = $documentStartedAt.ToString(
            "yyyy-MM-dd HH:mm:ss"
          )
          DocumentFinishedAt = $documentFinishedAt.ToString(
            "yyyy-MM-dd HH:mm:ss"
          )
          DurationSeconds = [Math]::Round(
            $documentDuration.TotalSeconds,
            2
          )
          SourceFile = [string]$document.SelectedPdf.File.FullName
          ErrorMessage = $_.Exception.Message
        }
      )

      Write-Failure (
        "$($document.ItemCode): " +
        $_.Exception.Message
      )

      # O resultado de falha ja foi registrado em $batchResults.
      continue
    }
  }

  # ============================================================
  # 8. RESUMO FINAL
  # ============================================================

  Write-Section `
    -Title "Resumo da importacao"

  Write-AnimatedLine ""

  # Apresenta um resultado individual para cada documento,
  # diferenciando criacao, importacao do PDF e workflow.
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

  # ============================================================
  # 9. EXPORTAR O RELATORIO CSV
  # ============================================================

  try {

    $null =
    Export-DcaBatchReport `
      -Results $batchResults.ToArray() `
      -Environment ([string]$script:TeamcenterEnvironment) `
      -ExecutionStartedAt $script:DcaExecutionStartedAt
  }
  catch {

    Write-Warn (
      "Nao foi possivel criar o relatorio CSV: " +
      $_.Exception.Message
    )
  }

  if ($failureCount -gt 0) {
    return 1
  }

  return 0
}

# ============================================================
# 9. PONTO DE ENTRADA E CODIGO DE SAIDA
# ============================================================
#
# Codigo 0:
#   Todos os documentos foram processados com sucesso ou a
#   operacao foi cancelada antes de efetuar alteracoes.
#
# Codigo 1:
#   O fluxo principal falhou ou pelo menos um documento do
#   lote nao foi processado com sucesso.

# Prepara o log e o caminho do relatorio antes de iniciar o fluxo
# principal. Uma falha ao criar o log nao impede a importacao.

try {

  Initialize-DcaExecutionArtifacts `
    -ProjectRoot $PSScriptRoot
}
catch {

  Write-Warn (
    "Nao foi possivel preparar os arquivos da execucao: " +
    $_.Exception.Message
  )
}

# O valor inicial indica falha por seguranca. O retorno de
# Invoke-DcaMain substitui esse valor quando o fluxo termina.
$exitCode = 1

try {

  $exitCode =
  @(
    Invoke-DcaMain
  ) |
    Select-Object -Last 1
}
catch {

  Write-Failure $_.Exception.Message

  $exitCode =
  1
}
finally {

  Stop-DcaExecutionLog
}

exit ([int]$exitCode)
