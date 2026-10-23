# ============================================================
# MONTAGEM E APRESENTACAO DO PLANO DE IMPORTACAO
# ============================================================
#
# Este arquivo prepara e apresenta o plano do lote antes da
# criacao de objetos no Teamcenter.
#
# Responsabilidades:
#   1. identificar o ambiente configurado;
#   2. validar a configuracao de cada documento;
#   3. determinar os tipos do Item e da revisao;
#   4. calcular os workflows aplicaveis;
#   5. apresentar a configuracao agrupada por tipo;
#   6. listar os documentos do lote;
#   7. destacar erros e workflows nao configurados.
#
# A apresentacao do plano nao cria Items, revisoes, Datasets
# nem workflows no Teamcenter.
# ============================================================
function Get-DcaConfiguredEnvironmentName {

  # Prioriza o ambiente confirmado durante a conexao. Antes da
  # conexao, utiliza o valor configurado no arquivo .env.
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

  # Consolida a configuracao dos documentos, tipos, revisoes,
  # estados e workflows antes da etapa que cria os objetos.
  param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNull()]
    [object[]]$Documents
  )

  if ($Documents.Count -eq 0) {

    throw (
      "Nenhum documento foi fornecido para montar o plano " +
      "de importacao."
    )
  }

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

  # ============================================================
  # MONTAGEM DO PLANO POR DOCUMENTO
  # ============================================================

  $planItems =
  [System.Collections.Generic.List[object]]::new()

  foreach ($document in $Documents) {

    if ($null -eq $document) {
      continue
    }

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

    if ($document.DocumentType -eq "DatasetOnly") {

      $configuration =
      [PSCustomObject]@{
        Environment = $environmentName
        ItemType = "Item existente"
        RevisionType = "Revisao existente"
        ClientProperty = ""
        ClientValue = ""
        TeamcenterRevisionId = [string]$document.ClientRevision
        RevisionProperties = @{}
      }
    }
    else {

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

  if ($planItems.Count -eq 0) {

    throw (
      "Nenhum documento valido ficou disponivel para montar " +
      "o plano de importacao."
    )
  }

  # ============================================================
  # CABECALHO DO PLANO
  # ============================================================

  Write-Section `
    -Title "Plano antes da importacao"

  Write-Host ""

  Write-Host (
    "  Nada foi criado ainda. Confira as informacoes abaixo."
  ) -ForegroundColor DarkGray

  Write-Host ""

  Write-Host (
    "  Ambiente:   {0}" -f $environmentName
  ) -ForegroundColor $environmentColor

  if ($Details) {

    Write-Host (
      "  Servidor:   {0}" -f
      $serverUrl
    ) -ForegroundColor Gray
  }

  Write-Host (
    "  Documentos: {0}" -f $planItems.Count
  ) -ForegroundColor White

  # ============================================================
  # CONFIGURACAO POR TIPO DE DOCUMENTO
  # ============================================================

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

  # ============================================================
  # RESUMO DOS WORKFLOWS
  # ============================================================

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

  # ============================================================
  # LISTA DOS DOCUMENTOS
  # ============================================================

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

  # ============================================================
  # AVISOS FINAIS
  # ============================================================

  if ($errorCount -gt 0) {

    Write-Host ""

    Write-Warn (
      "$errorCount documento(s) possuem erro de configuracao " +
      "e nao poderao ser criados."
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