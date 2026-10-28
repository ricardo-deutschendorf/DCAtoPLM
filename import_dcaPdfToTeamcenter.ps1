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
  [switch]$Preview,

  # Quando o Item ja existir, tenta localizar a revisao esperada
  # e importar o PDF sem criar novamente o Item.
  [switch]$RecoverExisting,

  # Reprocessa as falhas registradas em um relatorio CSV anterior.
  # O arquivo original permanece inalterado e uma nova execucao
  # gera um novo log e um novo relatorio.
  [string]$RetryReport
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
  "Import-DcaRetryReport",

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
  "Show-DcaTeamcenterRevisionProperties",
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
  "Show-DcaTeamcenterRevisionDatasets",
  "Test-DcaTeamcenterDatasetExists",
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
  # VALIDAR OS MODOS DE EXECUCAO
  # ============================================================

  if (
    -not [string]::IsNullOrWhiteSpace(
      $RetryReport
    ) -and
    -not [string]::IsNullOrWhiteSpace(
      $SourceCode
    )
  ) {

    throw (
      "Use -SourceCode ou -RetryReport. Os dois parametros nao " +
      "podem ser utilizados na mesma execucao."
    )
  }

  if (
    $Preview -and
    -not [string]::IsNullOrWhiteSpace(
      $RetryReport
    )
  ) {

    throw (
      "-RetryReport nao pode ser utilizado com -Preview."
    )
  }

  $retryMode =
  -not [string]::IsNullOrWhiteSpace(
    $RetryReport
  )

  # ============================================================
  # REPETIR A PESQUISA ATE ENCONTRAR DOCUMENTOS
  # ============================================================
  #
  # Quando uma pesquisa interativa nao retornar documentos, o
  # usuario pode informar outro termo sem reiniciar a aplicacao.
  $searchCompleted =
  $false

  while (-not $searchCompleted) {

    # ============================================================
    # 1. RECEBER E VALIDAR A PESQUISA
    # ============================================================
    if (-not $retryMode) {

      Write-Section `
        -Title "Informe o que deseja pesquisar" `
        -NoLeadingBlank
    }
    else {

      Write-Section `
        -Title "Reprocessar falhas do relatorio" `
        -NoLeadingBlank
    }

    if (-not $retryMode) {
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
    }
    # ============================================================
    # 2. PESQUISAR E SELECIONAR OS PDFs
    # ============================================================
    $selectedDocuments =
    [System.Collections.Generic.List[object]]::new()

    # Quando -RetryReport for utilizado, os documentos sao
    # reconstruidos diretamente das falhas registradas no CSV.
    if ($retryMode) {

      $retryRows =
      @(
        Import-DcaRetryReport `
          -FilePath $RetryReport
      )

      foreach ($retryRow in $retryRows) {

        $sourceFilePath =
        [string]$retryRow.SourceFile

        $sourceFileName =
        [System.IO.Path]::GetFileName(
          $sourceFilePath
        )

        $sourceBaseName =
        [System.IO.Path]::GetFileNameWithoutExtension(
          $sourceFilePath
        )

        $retryFile =
        [PSCustomObject]@{
          Name = $sourceFileName
          BaseName = $sourceBaseName
          FullName = $sourceFilePath
          FromVault = $true
        }

        $retrySelectedPdf =
        [PSCustomObject]@{
          File = $retryFile
          SourceCode = [string]$retryRow.ItemCode
          ClientRevision = [string]$retryRow.ClientRevision
          DocumentTitle = [string]$retryRow.ItemName
          DocumentType = [string]$retryRow.DocumentType
          TypeDisplayName = [string]$retryRow.DocumentType
          CodeParsed = $true
          PdmState = [string]$retryRow.PdmState
          FolderImport = $true
          TeamcenterItem = $null
          TeamcenterRevision = $null
          RetryMode = [string]$retryRow.RetryMode
          PreviousError = [string]$retryRow.PreviousError
        }

        $selectedDocuments.Add(
          [PSCustomObject]@{
            SelectedPdf = $retrySelectedPdf
          }
        )
      }
    }

    if (-not $retryMode) {
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
    }
    # ==========================================================
    # VALIDAR O RESULTADO DA PESQUISA ATUAL
    # ==========================================================

    if ($selectedDocuments.Count -gt 0) {

      # Pelo menos um documento foi encontrado e selecionado.
      # Encerra o laco e continua a preparacao do lote.
      $searchCompleted =
      $true

      break
    }

    # O modo de reprocessamento nao possui uma pesquisa
    # interativa para repetir. Nesse caso, mantem a falha.
    if ($retryMode) {

      throw (
        "Nenhum documento valido foi carregado do relatorio " +
        "informado para nova tentativa."
      )
    }

    Write-AnimatedLine ""

    Write-Warn (
      "Nenhum documento foi encontrado ou selecionado para " +
      "a pesquisa informada."
    )

    Write-Host ""

    $newSearchInput =
    Read-Host (
      "Digite outra pesquisa ou pressione Enter para sair"
    )

    if (
      [string]::IsNullOrWhiteSpace(
        $newSearchInput
      )
    ) {

      Write-AnimatedLine ""

      Write-Warn (
        "Pesquisa encerrada pelo usuario. " +
        "Nenhuma alteracao foi realizada."
      )

      return 0
    }

    # Atualiza SourceCode para que a proxima repeticao utilize
    # diretamente o novo texto informado.
    $SourceCode =
    $newSearchInput.Trim()

    Write-AnimatedLine ""

    Write-Info (
      "Reiniciando a pesquisa..."
    )
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
        RequestedMode =
        if (
          $selectedPdf.PSObject.Properties["RetryMode"]
        ) {
          [string]$selectedPdf.RetryMode
        }
        elseif ($documentType -eq "DatasetOnly") {
          "DatasetOnly"
        }
        else {
          "CreateItem"
        }

        PreviousError =
        if (
          $selectedPdf.PSObject.Properties["PreviousError"]
        ) {
          [string]$selectedPdf.PreviousError
        }
        else {
          $null
        }
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

    # ==========================================================
    # A. DETERMINAR A REVISAO ESPERADA NO TEAMCENTER
    # ==========================================================
    #
    # ClientRevision representa a revisao documental do PDF.
    # Alguns tipos utilizam outro item_revision_id no Teamcenter.
    #
    # Para Norma Externa, por exemplo:
    #   - revisao documental do Dataset: 07-1998;
    #   - item_revision_id no Teamcenter: 001.
    $expectedTeamcenterRevision =
    [string]$document.ClientRevision

    if ($document.DocumentType -ne "DatasetOnly") {

      $lookupTypeConfiguration =
      Get-DcaTypeConfiguration `
        -DocumentType $document.DocumentType `
        -ClientRevision $document.ClientRevision `
        -TeamcenterEnvironment $script:TeamcenterEnvironment

      if (
        $null -ne $lookupTypeConfiguration -and
        -not [string]::IsNullOrWhiteSpace(
          [string]$lookupTypeConfiguration.TeamcenterRevisionId
        )
      ) {

        $expectedTeamcenterRevision =
        [string]$lookupTypeConfiguration.TeamcenterRevisionId
      }
    }

    $expectedTeamcenterRevision =
    $expectedTeamcenterRevision.Trim().ToUpperInvariant()

    if (
      [string]::IsNullOrWhiteSpace(
        $expectedTeamcenterRevision
      )
    ) {

      throw (
        "A revisao esperada no Teamcenter ficou vazia para " +
        "'$($document.ItemCode)'."
      )
    }

    Add-Member `
      -InputObject $document `
      -NotePropertyName "ExpectedTeamcenterRevision" `
      -NotePropertyValue $expectedTeamcenterRevision `
      -Force

    Write-Info (
      "Consultando no Teamcenter: " +
      "$($document.ItemCode), revisao " +
      "$expectedTeamcenterRevision"
    )

    if ($Details) {

      Write-Info (
        "Revisao documental do PDF: " +
        "'$($document.ClientRevision)'"
      )

      Write-Info (
        "Revisao esperada no Teamcenter: " +
        "'$expectedTeamcenterRevision'"
      )
    }

    $lookupResult =
    Find-DcaTeamcenterItemRevision `
      -ItemCode $document.ItemCode `
      -ExpectedRevision $expectedTeamcenterRevision

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

      # Item e revisao existem. DatasetOnly mantem seu fluxo
      # especifico; os demais tipos passam para recuperacao.
      if ($document.DocumentType -eq "DatasetOnly") {

        $document.RequestedMode =
        "DatasetOnly"
      }
      else {

        $document.RequestedMode =
        "RecoverExisting"
      }

      Write-Success (
        "Item e revisao existentes encontrados: " +
        "$($document.ItemCode)/" +
        "$($document.ExpectedTeamcenterRevision)"
      )
    }
    elseif (
      $document.DocumentType -ne "DatasetOnly" -and
      -not $lookupResult.ItemExists
    ) {

      # Nenhum Item foi encontrado. O fluxo pode criar o Item e
      # sua primeira revisao normalmente.
      $document.RequestedMode =
      "CreateItem"

      Write-Info (
        "Item existente nao localizado. O documento sera " +
        "processado com criacao normal."
      )
    }
    elseif ($lookupResult.ItemExists) {

      # O Item existe, mas a revisao esperada nao foi validada.
      # Mantem o modo de recuperacao para que a validacao anterior
      # a confirmacao bloqueie a operacao.
      $document.RequestedMode =
      "RecoverExisting"

      Write-Warn (
        "O Item '$($document.ItemCode)' existe, mas a revisao " +
        "'$($document.ExpectedTeamcenterRevision)' nao foi validada."
      )

      if (
        -not [string]::IsNullOrWhiteSpace(
          [string]$lookupResult.FoundRevision
        )
      ) {

        Write-Warn (
          "Revisao encontrada no Teamcenter: " +
          "'$($lookupResult.FoundRevision)'."
        )
      }
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
  $unavailableExistingDestinations =
  @(
    $preparedDocuments |
      Where-Object {
      $_.RequestedMode -in @(
        "DatasetOnly",
        "RecoverExisting"
      ) -and
      (
        $_.TeamcenterStatus -ne "Sim" -or
        $null -eq $_.TeamcenterRevision
      )
    }
  )

  if ($unavailableExistingDestinations.Count -gt 0) {

    Write-AnimatedLine ""

    foreach (
      $unavailableDocument in
      $unavailableExistingDestinations
    ) {

      Write-Failure (
        "Destino existente indisponivel: " +
        "$($unavailableDocument.ItemCode)/" +
        "$($unavailableDocument.ExpectedTeamcenterRevision)"
      )
    }

    throw (
      "A importacao foi interrompida antes da confirmacao porque " +
      "$($unavailableExistingDestinations.Count) destino(s) " +
      "existentes nao foram validados no Teamcenter."
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
      $_.RequestedMode -eq "DatasetOnly"
    }
  ).Count

  $recoverExistingCount =
  @(
    $preparedDocuments |
      Where-Object {
      $_.RequestedMode -eq "RecoverExisting"
    }
  ).Count

  $createItemCount =
  @(
    $preparedDocuments |
      Where-Object {
      $_.RequestedMode -eq "CreateItem"
    }
  ).Count

  Write-Section `
    -Title "Processar documentos no Teamcenter"

  Write-AnimatedLine ""

  Write-Warn (
    "Esta etapa vai processar $($preparedDocuments.Count) " +
    "documento(s) no Teamcenter: $createItemCount com criacao " +
    "de Item, $recoverExistingCount com recuperacao e " +
    "$datasetOnlyCount somente como Dataset."
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

    # Indica se o Dataset ja estava relacionado a revisao antes
    # desta execucao.
    $datasetAlreadyExists =
    $false

    # Indica se o PDF foi importado especificamente nesta
    # execucao, diferenciando importacao de Dataset ja existente.
    $pdfImportedThisRun =
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

      if (
        $document.RequestedMode -eq "DatasetOnly" -or
        $document.RequestedMode -eq "RecoverExisting"
      ) {

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
            "O destino '$createdCode/" +
            "$($document.ExpectedTeamcenterRevision)' " +
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

        if ($document.RequestedMode -eq "RecoverExisting") {

          Write-Warn (
            "Recuperando o PDF no Item existente: " +
            "$createdCode/" +
            "$($document.ExpectedTeamcenterRevision)"
          )
        }

        Write-Success (
          "Destino existente localizado: " +
          "$createdCode/" +
          "$($document.ExpectedTeamcenterRevision)"
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

        $null =
        Show-DcaTeamcenterRevisionProperties `
          -Revision $teamcenterRevision

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

      # ==================================================
      # E.1. Verificar se o Dataset ja existe
      # ==================================================
      #
      # A verificacao e obrigatoria para destinos existentes.
      # Em Items criados nesta execucao, a revisao acabou de ser
      # criada e ainda nao deve possuir o Dataset.
      $shouldCheckExistingDataset =
      (
        $document.RequestedMode -eq "DatasetOnly" -or
        $document.RequestedMode -eq "RecoverExisting"
      )

      $datasetLookup =
      $null

      if ($shouldCheckExistingDataset) {

        Write-Info (
          "Verificando se o Dataset ja existe na revisao..."
        )

        $datasetLookup =
        Test-DcaTeamcenterDatasetExists `
          -Revision $teamcenterRevision `
          -DatasetName $datasetName `
          -DatasetRevision $document.ClientRevision

        if ($null -eq $datasetLookup) {

          throw (
            "A verificacao do Dataset retornou NULL para " +
            "'$datasetName'."
          )
        }
      }

      # ==================================================
      # E.2. Importar somente quando o Dataset estiver ausente
      # ==================================================

      if (
        $null -ne $datasetLookup -and
        $datasetLookup.Exists
      ) {

        $datasetAlreadyExists =
        $true

        $pdfImported =
        $true

        $pdfImportedThisRun =
        $false

        Write-Warn (
          "O Dataset '$datasetName' ja existe na revisao " +
          "'$($document.ClientRevision)'. " +
          "A importacao nao sera repetida."
        )

        if ($Details) {

          Write-Info (
            "Relacao do Dataset existente: " +
            $datasetLookup.Relation
          )

          Write-Info (
            "Tipo tecnico do Dataset existente: " +
            $datasetLookup.TypeName
          )
        }
      }
      else {

        Write-Info (
          "Dataset nao encontrado. Importando o PDF no Teamcenter..."
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

        # A ausencia de excecao indica que a chamada ao importador
        # foi concluida. A verificacao posterior do relacionamento
        # ainda pode ser implementada em uma etapa futura.
        $pdfImported =
        $true

        $pdfImportedThisRun =
        $true

        $datasetAlreadyExists =
        $false
      }

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

      # Quando o Dataset ja existia antes da execucao, o workflow
      # nao e repetido automaticamente. Isso evita iniciar dois
      # processos para o mesmo documento.
      if (
        $datasetAlreadyExists -and
        $document.RequestedMode -eq "RecoverExisting"
      ) {

        Write-Info (
          "O Dataset ja existia. Nenhum workflow sera repetido."
        )
      }

      $workflowTemplate =
      $null

      $workflowLabel =
      $null

      if (
        $document.DocumentType -ne "DatasetOnly" -and
        -not $datasetAlreadyExists -and
        $pdmState -ieq "Aprovado"
      ) {

        $workflowTemplate =
        [string]$env:DCA_TC_APPROVED_WORKFLOW

        $workflowLabel =
        "aprovacao"
      }
      elseif (
        $document.DocumentType -ne "DatasetOnly" -and
        -not $datasetAlreadyExists -and
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
          Operation = [string]$document.RequestedMode
          ItemCreated = $itemCreated
          PdfImported = $pdfImported
          PdfImportedThisRun = $pdfImportedThisRun
          DatasetAlreadyExists = $datasetAlreadyExists
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
          RequestedMode = [string]$document.RequestedMode
          Operation = [string]$document.RequestedMode
          ItemCreated = $itemCreated
          PdfImported = $pdfImported
          PdfImportedThisRun = $pdfImportedThisRun
          DatasetAlreadyExists = $datasetAlreadyExists
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

    if ($result.DatasetAlreadyExists) {

      Write-Success (
        "$($result.ItemCode) -> Dataset ja existente; " +
        "nenhuma nova importacao foi realizada"
      )

      continue
    }

    if (
      $result.Operation -eq "RecoverExisting" -and
      $result.PdfImported
    ) {

      $recoveryMessage =
      "$($result.ItemCode) -> " +
      "$($result.TeamcenterCode) - " +
      "PDF recuperado no Item existente"

      if ($result.WorkflowStarted) {

        $recoveryMessage +=
        " - workflow solicitado"
      }

      Write-Success $recoveryMessage

      continue
    }

    if (
      $result.Operation -eq "RecoverExisting" -and
      -not $result.PdfImported
    ) {

      Write-Failure (
        "$($result.ItemCode) -> Recuperacao do PDF falhou: " +
        $result.ErrorMessage
      )

      continue
    }

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
