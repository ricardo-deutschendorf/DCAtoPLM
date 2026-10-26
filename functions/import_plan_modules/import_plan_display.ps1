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

  # ============================================================
  # 1. UTILIZAR O AMBIENTE CONFIRMADO PELA CONEXAO
  # ============================================================
  #
  # Quando a conexao com o Teamcenter ja tiver sido realizada,
  # utiliza o ambiente identificado durante essa conexao.
  if (
    -not [string]::IsNullOrWhiteSpace(
      $script:TeamcenterEnvironment
    )
  ) {
    return [string]$script:TeamcenterEnvironment
  }

  # ============================================================
  # 2. LER O AMBIENTE CONFIGURADO
  # ============================================================
  #
  # Antes da conexao, utiliza o valor informado no arquivo .env.
  # Somente os ambientes Teste e Processo sao reconhecidos.
  $configuredValue =
  ([string]$env:DCA_TC_ENV).Trim()

  if ($configuredValue -ieq "Teste") {
    return "Teste"
  }

  if ($configuredValue -ieq "Processo") {
    return "Processo"
  }

  # Impede a montagem do plano quando o ambiente estiver vazio
  # ou possuir um valor diferente dos ambientes permitidos.
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

  # ============================================================
  # 1. VALIDAR OS DOCUMENTOS RECEBIDOS
  # ============================================================
  #
  # O plano precisa receber pelo menos um documento para calcular
  # as configuracoes e apresentar as operacoes previstas.
  if ($Documents.Count -eq 0) {

    throw (
      "Nenhum documento foi fornecido para montar o plano " +
      "de importacao."
    )
  }

  # ============================================================
  # 2. PREPARAR A CONFIGURACAO DO AMBIENTE
  # ============================================================
  #
  # Identifica o ambiente utilizado no plano e seleciona a URL
  # correspondente para apresentacao no modo Details.
  $environmentName =
  Get-DcaConfiguredEnvironmentName

  # Teste e utilizado como configuracao inicial. Quando o ambiente
  # for Processo, a URL e a cor serao substituidas abaixo.
  $serverUrl =
  [string]$env:DCA_TC_TEST_URL

  $environmentColor =
  [System.ConsoleColor]::Cyan

  # O ambiente de Processo utiliza uma URL propria e recebe uma
  # cor de destaque para chamar a atencao antes da importacao.
  if ($environmentName -eq "Processo") {

    $serverUrl =
    [string]$env:DCA_TC_PROCESS_URL

    $environmentColor =
    [System.ConsoleColor]::Yellow
  }

  # ============================================================
  # 3. LER OS WORKFLOWS CONFIGURADOS
  # ============================================================
  #
  # Os templates sao utilizados somente para montar e apresentar
  # o plano. Nenhum workflow e iniciado nesta funcao.
  $approvedTemplate =
  [string]$env:DCA_TC_APPROVED_WORKFLOW

  $obsoleteTemplate =
  [string]$env:DCA_TC_OBSOLETE_WORKFLOW

  # ============================================================
  # 4. MONTAR O PLANO DE CADA DOCUMENTO
  # ============================================================
  #
  # Consolida tipo, estado, revisao, configuracao do Teamcenter e
  # workflow previsto para cada documento recebido.
  # A lista mantem somente as informacoes necessarias para a
  # apresentacao e validacao do plano de importacao.
  $planItems =
  [System.Collections.Generic.List[object]]::new()

  foreach ($document in $Documents) {

    # Entradas nulas sao ignoradas para que nao interrompam a
    # montagem dos demais documentos do lote.
    if ($null -eq $document) {
      continue
    }

    # ==========================================================
    # A. DETERMINAR O WORKFLOW PREVISTO
    # ==========================================================
    #
    # O estado atual do PDM define se o documento recebera um
    # workflow de aprovacao, obsolescencia ou nenhum workflow.
    $pdmState =
    ([string]$document.PdmState).Trim()

    # Os valores permanecem nulos quando o estado nao possuir um
    # workflow associado.
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

    # ==========================================================
    # B. OBTER A CONFIGURACAO DO TIPO DE DOCUMENTO
    # ==========================================================
    #
    # A configuracao informa os tipos do Item e da revisao, as
    # propriedades adicionais e a revisao usada no Teamcenter.
    $configuration =
    $null

    $configurationError =
    $null

    # DatasetOnly reutiliza um Item e uma revisao existentes.
    # Por isso, nao precisa consultar uma configuracao de criacao.
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

        # Os demais tipos precisam de uma configuracao valida para
        # criar o Item e sua revisao no ambiente selecionado.
        $configuration =
        Get-DcaTypeConfiguration `
          -DocumentType $document.DocumentType `
          -ClientRevision $document.ClientRevision `
          -TeamcenterEnvironment $environmentName
      }
      catch {

        # A falha e registrada no plano sem interromper a analise
        # dos demais documentos do lote.
        $configurationError =
        $_.Exception.Message
      }
    }

    # ==========================================================
    # C. PREPARAR OS DADOS DA REVISAO
    # ==========================================================
    #
    # O identificador permanece como "?" quando a configuracao do
    # documento nao puder ser determinada.
    $teamcenterRevisionId =
    "?"

    $revisionText =
    ""

    if ($null -ne $configuration) {

      $teamcenterRevisionId =
      [string]$configuration.TeamcenterRevisionId

      # As propriedades adicionais da revisao sao convertidas em
      # um texto unico para apresentacao no modo Details.
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

    # ==========================================================
    # D. REGISTRAR O DOCUMENTO NO PLANO
    # ==========================================================
    #
    # Consolida os dados originais do documento com a configuracao
    # calculada e o workflow previsto.
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

  # Depois da remocao das entradas nulas, pelo menos um documento
  # deve permanecer disponivel para apresentacao.
  if ($planItems.Count -eq 0) {

    throw (
      "Nenhum documento valido ficou disponivel para montar " +
      "o plano de importacao."
    )
  }

  # ============================================================
  # 5. APRESENTAR O CABECALHO DO PLANO
  # ============================================================
  #
  # Informa o ambiente e a quantidade de documentos antes de
  # apresentar os detalhes calculados para o lote.
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

  # A URL do servidor e exibida somente no modo Details para
  # confirmar tecnicamente o destino selecionado.
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
  # 6. APRESENTAR A CONFIGURACAO POR TIPO
  # ============================================================
  #
  # Agrupa os documentos para evitar repetir a mesma configuracao
  # de Item, revisao e cliente em cada linha do plano.

  Write-Host ""
  Write-Host "  Configuracao por tipo:" -ForegroundColor Cyan

  # Cada grupo representa um tipo interno de documento presente
  # no lote atual.
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

    # Seleciona o primeiro documento com configuracao valida para
    # representar os dados comuns do grupo.
    $sampleItem =
    $typeGroup.Group |
      Where-Object {
      $null -ne $_.Configuration
    } |
      Select-Object -First 1

    # Quando nenhum documento do grupo possuir configuracao
    # valida, os erros individuais serao apresentados mais abaixo.
    if ($null -eq $sampleItem) {

      Write-Host (
        "      Configuracao invalida. Veja os erros abaixo."
      ) -ForegroundColor Red

      continue
    }

    $typeConfiguration =
    $sampleItem.Configuration

    # O texto permanece como "nenhum" quando o tipo nao exige uma
    # propriedade adicional para identificar o cliente.
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
  # 7. CALCULAR E APRESENTAR OS WORKFLOWS
  # ============================================================
  #
  # Conta os documentos de aprovacao, obsolescencia e aqueles que
  # permanecerao sem workflow.
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

  # Todo documento que nao estiver associado aos dois workflows
  # conhecidos sera contabilizado como sem workflow.
  $withoutWorkflowCount =
  $planItems.Count -
  $approvedCount -
  $obsoleteCount

  # Os nomes configurados sao preparados para apresentacao. Um
  # valor vazio recebe o texto NAO CONFIGURADO.
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
  # 8. APRESENTAR OS DOCUMENTOS DO LOTE
  # ============================================================
  #
  # Exibe a revisao prevista, o estado do PDM, o workflow e os
  # erros encontrados durante a montagem da configuracao.

  Write-Host ""
  Write-Host "  Documentos:" -ForegroundColor Cyan

  # Os contadores permitem apresentar avisos consolidados depois
  # da lista individual dos documentos.
  $errorCount =
  0

  $missingWorkflowCount =
  0

  for (
    $index = 0
    $index -lt $planItems.Count
    $index++
  ) {

    # ==========================================================
    # A. PREPARAR A LINHA DO DOCUMENTO
    # ==========================================================
    $planItem =
    $planItems[$index]

    # A linha utiliza inicialmente o estado sem workflow e a cor
    # neutra. Esses valores sao alterados conforme a configuracao.
    $workflowText =
    "sem workflow"

    $lineColor =
    [System.ConsoleColor]::Gray

    # ==========================================================
    # B. DEFINIR O TEXTO E A COR DO WORKFLOW
    # ==========================================================
    #
    # Workflows configurados recebem a cor correspondente. Quando
    # o template estiver ausente, a linha recebe um aviso amarelo.
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

    # Um erro de configuracao possui prioridade visual sobre o
    # estado do workflow e deixa a linha em vermelho.
    if ($null -ne $planItem.ConfigurationError) {

      $lineColor =
      [System.ConsoleColor]::Red

      $errorCount++
    }

    # ==========================================================
    # C. NORMALIZAR O ESTADO DO PDM
    # ==========================================================
    #
    # Quando o estado nao tiver sido identificado, utiliza um
    # texto explicito em vez de apresentar uma coluna vazia.
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

    # ==========================================================
    # D. EXIBIR O RESULTADO DO DOCUMENTO
    # ==========================================================
    Write-Host (
      "  [{0}] {1} | rev {2} | {3} | {4}" -f
      ($index + 1),
      $planItem.ItemCode,
      $planItem.TeamcenterRevisionId,
      $stateText,
      $workflowText
    ) -ForegroundColor $lineColor

    # O motivo completo da configuracao invalida e apresentado
    # imediatamente abaixo do documento correspondente.
    if ($null -ne $planItem.ConfigurationError) {

      Write-Host (
        "       ERRO: {0}" -f
        $planItem.ConfigurationError
      ) -ForegroundColor Red
    }

    # No modo Details, apresenta nome, propriedades da revisao,
    # template do workflow e caminho completo do arquivo.
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
  # 9. APRESENTAR OS AVISOS FINAIS
  # ============================================================
  #
  # Consolida os erros de configuracao e os workflows ausentes
  # encontrados durante a montagem do plano.
  # Erros de configuracao impedem a criacao dos documentos
  # correspondentes no Teamcenter.
  if ($errorCount -gt 0) {

    Write-Host ""

    Write-Warn (
      "$errorCount documento(s) possuem erro de configuracao " +
      "e nao poderao ser criados."
    )
  }

  # A ausencia do template nao impede a criacao do Item e a
  # importacao do PDF, mas deixa o documento sem workflow.
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
