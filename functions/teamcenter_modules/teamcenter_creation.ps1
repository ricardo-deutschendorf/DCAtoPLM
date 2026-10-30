# ============================================================
# CRIACAO DE ITEM E REVISAO NO TEAMCENTER
# ============================================================
#
# Este arquivo prepara e executa a criacao de um Item e de sua
# revisao por meio de DataManagementService.CreateObjects.
#
# Antes da criacao, o fluxo:
#   1. valida codigo, nome, ambiente e revisao;
#   2. obtem a configuracao tecnica do tipo DCA;
#   3. localiza os tipos CreateIn e CreateInput;
#   4. prepara as propriedades do Item e da revisao;
#   5. monta o CompoundCreateInput;
#   6. valida as propriedades especificas do documento.
#
# Depois da chamada, o fluxo:
#   1. interpreta os erros retornados pelo servico SOA;
#   2. recupera o Item e a revisao criados;
#   3. remove wrappers criados pelo PowerShell;
#   4. grava aprovador e data na revisao de Processo;
#   5. devolve os objetos ao fluxo principal.
#
# Esta funcao pode criar objetos efetivamente no Teamcenter.
# As validacoes da criacao devem ocorrer antes de CreateObjects.
# As propriedades de aprovacao sao aplicadas depois, quando o
# objeto da revisao criada estiver disponivel.
# ============================================================
function New-DcaTeamcenterItem {

  # Monta a solicitacao CreateObjects, envia o Item e a revisao
  # ao Teamcenter e retorna os objetos efetivamente criados.
  #
  # A configuracao dos tipos e das propriedades varia conforme:
  #   - tipo do documento;
  #   - ambiente conectado;
  #   - revisao informada pelo cliente.
  param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$SourceCode,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$ItemName,

    [string]$ClientRevision,

    [Parameter(Mandatory = $false)]
    [AllowEmptyString()]
    [string]$Approver,

    [Parameter(Mandatory = $false)]
    [AllowEmptyString()]
    [string]$ApprovalDate,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$DocumentType
  )

  # ============================================================
  # 1. VALIDAR E NORMALIZAR OS DADOS DE ENTRADA
  # ============================================================
  #
  # O padrao abaixo identifica mensagens de duplicidade retornadas
  # tanto por excecoes quanto pelos erros parciais do servico SOA.
  $duplicatePattern = '(?i)already exists|ja existe|duplicate|not unique|is not unique'

  $sourceCodeClean =
  $SourceCode.Trim().ToUpperInvariant()

  $itemNameClean =
  $ItemName.Trim()

  $approverClean =
  ([string]$Approver).Trim()

  if ([string]::IsNullOrWhiteSpace($sourceCodeClean)) {
    throw "SourceCode ficou vazio."
  }

  if ([string]::IsNullOrWhiteSpace($itemNameClean)) {
    throw "ItemName ficou vazio."
  }

  if (
    [string]::IsNullOrWhiteSpace(
      $script:TeamcenterEnvironment
    )
  ) {

    throw (
      "O ambiente do Teamcenter ainda nao foi identificado. " +
      "Execute Connect-Teamcenter antes da criacao."
    )
  }

  # ============================================================
  # 2. OBTER A CONFIGURACAO TECNICA DO TIPO DCA
  # ============================================================
  #
  # A configuracao define:
  #   - tipo tecnico do Item;
  #   - tipo tecnico da revisao;
  #   - propriedade e valor do cliente;
  #   - item_revision_id;
  #   - propriedades adicionais da revisao.
  $typeConfiguration =
  Get-DcaTypeConfiguration `
    -DocumentType $DocumentType `
    -ClientRevision $ClientRevision `
    -TeamcenterEnvironment $script:TeamcenterEnvironment

  if ($Details) {

    Write-Host ""

    Write-Host (
      "  Ambiente Teamcenter: " +
      "$($typeConfiguration.Environment)"
    ) -ForegroundColor Gray

    Write-Host (
      "  Tipo do Item:        " +
      "$($typeConfiguration.ItemType)"
    ) -ForegroundColor Gray

    Write-Host (
      "  Tipo da Revisao:     " +
      "$($typeConfiguration.RevisionType)"
    ) -ForegroundColor Gray
  }

  # Transfere os valores da configuracao para variaveis locais
  # utilizadas durante a montagem dos objetos CreateInput.
  $itemType = $typeConfiguration.ItemType
  $revisionType = $typeConfiguration.RevisionType
  $clientProperty = $typeConfiguration.ClientProperty
  $clientValue = $typeConfiguration.ClientValue
  $teamcenterRevisionId = $typeConfiguration.TeamcenterRevisionId
  $revisionExtraProperties = $typeConfiguration.RevisionProperties

  if ([string]::IsNullOrWhiteSpace($teamcenterRevisionId)) {
    throw "Revision ID ficou vazio para '$DocumentType'."
  }

  # ============================================================
  # 3. LOCALIZAR CREATEOBJECTS E OS TIPOS DE ENTRADA
  # ============================================================
  #
  # Os tipos CreateIn e CreateInput sao obtidos por reflexao a
  # partir da assinatura real de DataManagementService.CreateObjects.
  #
  # Isso evita depender diretamente de um namespace ou de uma
  # versao especifica das bibliotecas SOA.
  $dataManagementService = Get-TeamcenterDataManagementService

  $createObjectsMethod = $dataManagementService.GetType().GetMethods() |
    Where-Object {
    $_.Name -eq "CreateObjects" -and
    $_.GetParameters().Count -eq 1
  } |
    Select-Object -First 1

  if ($null -eq $createObjectsMethod) {
    throw "Metodo CreateObjects nao encontrado."
  }

  $createInArrayType = $createObjectsMethod.GetParameters()[0].ParameterType

  if (-not $createInArrayType.IsArray) {
    throw "O parametro de CreateObjects nao e um array."
  }

  $createInType = $createInArrayType.GetElementType()

  if ($null -eq $createInType) {
    throw "Tipo CreateIn nao identificado."
  }

  $createInputField = $createInType.GetField(
    "Data",
    [System.Reflection.BindingFlags]::Public -bor
    [System.Reflection.BindingFlags]::Instance -bor
    [System.Reflection.BindingFlags]::IgnoreCase
  )

  if ($null -eq $createInputField) {
    throw "Campo Data nao encontrado em CreateIn."
  }

  $createInputType = $createInputField.FieldType

  if ($null -eq $createInputType) {
    throw "Tipo do CreateInput nao identificado."
  }

  # ============================================================
  # 4. PREPARAR AS PROPRIEDADES DA REVISAO
  # ============================================================
  $candidateCode = $sourceCodeClean

  # Todas as revisoes recebem item_revision_id, object_name e
  # object_desc.
  #
  # Propriedades adicionais por tipo:
  #   Original:
  #     gd5revcliente.
  #
  #   Processo:
  #     gd5revcliente e gd5revinterna.
  #
  #   Norma Externa:
  #     nenhuma propriedade adicional.
  $revisionProperties = @{
    "item_revision_id" = $teamcenterRevisionId
    "object_name" = $itemNameClean
    "object_desc" = $itemNameClean
  }

  # Adiciona as propriedades especificas configuradas para o tipo
  # de documento, como as revisoes cliente e interna de Processo.
  foreach ($extraKey in $revisionExtraProperties.Keys) {

    $revisionProperties[$extraKey] =
    $revisionExtraProperties[$extraKey]
  }

  # ============================================================
  # MAPEAR APROVADOR E DATA DO PDM PARA O TEAMCENTER
  # ============================================================
  # Os valores sao validados e preparados antes da criacao.
  # Depois do CreateObjects, eles sao gravados diretamente nas
  # propriedades da revisao criada por SetProperties.
  #
  # Nenhum desses dados e concatenado em comentarios ou object_desc.
  if ($DocumentType -eq "Processo") {

    # ==========================================================
    # A. APROVADOR DO PDM
    # ==========================================================

    # O valor limpo permanece em $approverClean e sera aplicado
    # na revisao criada por SetProperties.
    if ($Details) {

      if (
        [string]::IsNullOrWhiteSpace(
          $approverClean
        )
      ) {

        Write-Host (
          "  Aprovador do PDM: <vazio>"
        ) -ForegroundColor DarkGray
      }
      else {

        Write-Host (
          "  Aprovador do PDM preparado:"
        ) -ForegroundColor Cyan

        Write-Host (
          "    gd5AprovadorPDM = '$approverClean'"
        ) -ForegroundColor Gray
      }
    }

    # ==========================================================
    # B. DATA DE APROVACAO DO PDM
    # ==========================================================

    $approvalDateClean =
    ([string]$ApprovalDate).Trim()

    if (
      -not [string]::IsNullOrWhiteSpace(
        $approvalDateClean
      )
    ) {

      $parsedApprovalDate =
      [datetime]::MinValue

      $approvalDateWasParsed =
      [datetime]::TryParseExact(
        $approvalDateClean,
        "dd/MM/yyyy",
        [System.Globalization.CultureInfo]::InvariantCulture,
        [System.Globalization.DateTimeStyles]::None,
        [ref]$parsedApprovalDate
      )

      if (-not $approvalDateWasParsed) {

        throw (
          "A data de aprovacao '$approvalDateClean' nao possui " +
          "o formato esperado dd/MM/yyyy."
        )
      }

      # SetProperties recebe a data como texto. O valor deve ser
      # produzido pelo conversor oficial da biblioteca SOA para
      # respeitar o formato de data esperado pelo Teamcenter.
      $teamcenterPropertyType =
      [System.AppDomain]::CurrentDomain.GetAssemblies() |
        ForEach-Object {

        try {

          $_.GetTypes()
        }
        catch {

          @()
        }
      } |
        Where-Object {
        $_.FullName -eq
        "Teamcenter.Soa.Client.Model.Property"
      } |
        Select-Object -First 1

      if ($null -eq $teamcenterPropertyType) {

        throw (
          "O tipo Teamcenter.Soa.Client.Model.Property nao foi " +
          "encontrado para converter a data de aprovacao."
        )
      }

      $toDateStringMethods =
      @(
        $teamcenterPropertyType.GetMethods(
          [System.Reflection.BindingFlags]::Public -bor
          [System.Reflection.BindingFlags]::Static
        ) |
          Where-Object {
          $_.Name -ieq "ToDateString" -and
          $_.GetParameters().Count -eq 1
        }
      )

      if ($toDateStringMethods.Count -eq 0) {

        throw (
          "O metodo Property.ToDateString nao foi encontrado " +
          "nas bibliotecas SOA carregadas."
        )
      }

      $toDateStringMethod =
      $toDateStringMethods |
        Where-Object {

        $parameterType =
        $_.GetParameters()[0].ParameterType

        $parameterType -eq [datetime]
      } |
        Select-Object -First 1

      if ($null -eq $toDateStringMethod) {

        $toDateStringMethod =
        $toDateStringMethods |
          Select-Object -First 1
      }

      $dateParameterType =
      $toDateStringMethod.GetParameters()[0].ParameterType

      if ($Details) {

        Write-Host (
          "  Conversor de data localizado:"
        ) -ForegroundColor Cyan

        Write-Host (
          "    Tipo:   $($teamcenterPropertyType.FullName)"
        ) -ForegroundColor DarkGray

        Write-Host (
          "    Metodo: $($toDateStringMethod.Name)"
        ) -ForegroundColor DarkGray

        Write-Host (
          "    Entrada: $($dateParameterType.FullName)"
        ) -ForegroundColor DarkGray
      }

      $dateArgument =
      if ($dateParameterType -eq [datetime]) {

        $parsedApprovalDate
      }
      elseif (
        $dateParameterType -eq [datetimeoffset]
      ) {

        $localOffset =
        [System.TimeZoneInfo]::Local.GetUtcOffset(
          $parsedApprovalDate
        )

        [System.DateTimeOffset]::new(
          $parsedApprovalDate,
          $localOffset
        )
      }
      else {

        throw (
          "Property.ToDateString possui um parametro nao " +
          "suportado: '$($dateParameterType.FullName)'."
        )
      }

      try {

        $approvalDateTeamcenter =
        [string]$toDateStringMethod.Invoke(
          $null,
          @(
            $dateArgument
          )
        )
      }
      catch {

        $realException =
        $_.Exception

        while (
          $null -ne $realException.InnerException
        ) {

          $realException =
          $realException.InnerException
        }

        throw (
          "Nao foi possivel converter a data " +
          "'$approvalDateClean' com Property.ToDateString: " +
          $realException.Message
        )
      }

      $approvalDateTeamcenter =
      $approvalDateTeamcenter.Trim()

      if ($Details) {

        Write-Host (
          "  Texto produzido por Property.ToDateString:"
        ) -ForegroundColor Cyan

        Write-Host (
          "    '$approvalDateTeamcenter'"
        ) -ForegroundColor Yellow
      }

      if (
        [string]::IsNullOrWhiteSpace(
          $approvalDateTeamcenter
        )
      ) {

        throw (
          "Property.ToDateString retornou uma data vazia para " +
          "'$approvalDateClean'."
        )
      }

      if ($Details) {

        Write-Host (
          "  Data de aprovacao do PDM para o Teamcenter:"
        ) -ForegroundColor Cyan

        Write-Host (
          "    gd5AprovadorPDMData = " +
          "'$approvalDateTeamcenter'"
        ) -ForegroundColor Gray
      }
    }
  }

  # As propriedades configuradas como inteiras sao enviadas em
  # IntProps. Todas as demais permanecem em StringProps.
  $integerPropertyNames =
  @(Get-DcaIntegerPropertyNames)

  # Cria o CreateInput correspondente a revisao.
  $revisionInput =
  New-DcaCreateInputObject `
    -InputType $createInputType `
    -BoName $revisionType `
    -Properties $revisionProperties `
    -IntegerPropertyNames $integerPropertyNames

  if ($null -eq $revisionInput) {

    throw (
      "revisionInput ficou NULL para o tipo " +
      "'$revisionType'."
    )
  }

  # Exibe a estrutura final da revisao antes da montagem do
  # CompoundCreateInput.
  if ($Details) {
    Write-Host (
      "  revisionInput criado: " +
      $revisionInput.GetType().FullName
    ) -ForegroundColor DarkGray

    Write-Host (
      "  BoName da revisao: " +
      [string]$revisionInput.BoName
    ) -ForegroundColor DarkGray

    Write-Host (
      "  Propriedades da revisao:"
    ) -ForegroundColor Cyan

    foreach (
      $revisionPropertyName in (
        $revisionInput.StringProps.Keys |
          Sort-Object
      )
    ) {

      Write-Host (
        "    {0} = '{1}'" -f
        $revisionPropertyName,
        $revisionInput.StringProps[$revisionPropertyName]
      ) -ForegroundColor Gray
    }
  }
  if (
    $Details -and
    $null -ne $revisionInput.IntProps
  ) {

    foreach (
      $integerPropertyName in (
        $revisionInput.IntProps.Keys |
          Sort-Object
      )
    ) {

      Write-Host (
        "    {0} = {1}  (inteiro)" -f
        $integerPropertyName,
        $revisionInput.IntProps[$integerPropertyName]
      ) -ForegroundColor Gray
    }
  }

  # ============================================================
  # 5. PREPARAR AS PROPRIEDADES DO ITEM
  # ============================================================
  #
  # O nome preparado pelo fluxo e aplicado ao Item e a revisao
  # como object_name e object_desc.
  $itemProperties = @{
    "item_id"     = $candidateCode
    "object_name" = $itemNameClean
    "object_desc" = $itemNameClean
  }

  # A propriedade de cliente somente e enviada quando tanto o nome
  # da propriedade quanto o valor estiverem configurados.
  if (
    -not [string]::IsNullOrWhiteSpace(
      [string]$clientProperty
    ) -and
    -not [string]::IsNullOrWhiteSpace(
      [string]$clientValue
    )
  ) {

    $itemProperties[$clientProperty] =
    $clientValue
  }

  if ($Details) {

    Write-Host (
      "  Propriedades do Item:"
    ) -ForegroundColor Cyan

    foreach (
      $itemPropertyName in (
        $itemProperties.Keys |
          Sort-Object
      )
    ) {

      Write-Host (
        "    {0} = '{1}'" -f
        $itemPropertyName,
        $itemProperties[$itemPropertyName]
      ) -ForegroundColor Gray
    }
  }

  # Cria o CreateInput correspondente ao Item.
  $itemInput =
  New-DcaCreateInputObject `
    -InputType $createInputType `
    -BoName $itemType `
    -Properties $itemProperties

  if ($null -eq $itemInput) {

    throw (
      "itemInput ficou NULL para o tipo " +
      "'$itemType'."
    )
  }

  # ============================================================
  # 6. MONTAR O COMPOUNDCREATEINPUT
  # ============================================================
  #
  # A revisao e adicionada como entrada composta do Item.
  # Dessa forma, Item e revisao sao enviados na mesma chamada
  # ao DataManagementService.CreateObjects.
  $revisionInputArray = [System.Array]::CreateInstance($createInputType, 1)
  $revisionInputArray.SetValue($revisionInput, 0)

  $compoundInput = New-Object System.Collections.Hashtable
  $compoundInput["revision"] = $revisionInputArray

  if ($Details) {

    Write-Host (
      "  Tipo tecnico do CreateInput: " +
      $itemInput.GetType().FullName
    ) -ForegroundColor DarkGray
  }
  Set-DcaObjectMemberValue `
    -InputObject $itemInput `
    -MemberName "CompoundCreateInput" `
    -Value $compoundInput

  # ============================================================
  # 7. MONTAR A ENTRADA FINAL DE CREATEOBJECTS
  # ============================================================
  #
  # CreateIn recebe o CreateInput do Item, que ja possui a revisao
  # associada em CompoundCreateInput.
  $createIn = [System.Activator]::CreateInstance($createInType)

  if ($null -eq $createIn) {
    throw "Nao foi possivel criar createIn."
  }

  $createIn.ClientId = [string]"CreateDcaItem"
  $createIn.Data = $itemInput

  $createInArray = [System.Array]::CreateInstance($createInType, 1)
  $createInArray.SetValue($createIn, 0)

  $revisionSent = $revisionInput

  if ($null -eq $revisionSent) {
    throw "revisionSent ficou NULL."
  }

  # ============================================================
  # 8. VALIDAR AS PROPRIEDADES ANTES DA CRIACAO
  # ============================================================
  #
  # As propriedades sao verificadas depois da separacao entre
  # StringProps e IntProps, mas antes da chamada CreateObjects.
  if ($DocumentType -eq "Processo") {

    # O tipo Processo exige:
    #   - gd5revcliente com um ou dois caracteres;
    #   - gd5revinterna com exatamente um digito;
    #   - item_revision_id preenchido.
    $revisionClient =
    ([string]$revisionSent.StringProps["gd5revcliente"]).Trim()

    $revisionInternal =
    Get-DcaCreateInputPropertyText `
      -InputObject $revisionSent `
      -PropertyName "gd5revinterna"

    $finalRevisionId =
    ([string]$revisionSent.StringProps["item_revision_id"]).Trim()

    if (
      [string]::IsNullOrWhiteSpace(
        $revisionClient
      )
    ) {

      throw (
        "gd5revcliente ficou vazio no objeto de revisao " +
        "antes do CreateObjects."
      )
    }

    if (
      $revisionClient -notmatch
      '^[A-Z0-9-]{1,2}$'
    ) {

      throw (
        "gd5revcliente possui valor invalido: " +
        "'$revisionClient'."
      )
    }

    if (
      [string]::IsNullOrWhiteSpace(
        $revisionInternal
      )
    ) {

      throw (
        "gd5revinterna ficou vazio no objeto de revisao " +
        "antes do CreateObjects."
      )
    }

    if (
      $revisionInternal -notmatch
      '^[0-9]$'
    ) {

      throw (
        "gd5revinterna possui valor invalido: " +
        "'$revisionInternal'. Era esperado um digito."
      )
    }

    if (
      [string]::IsNullOrWhiteSpace(
        $finalRevisionId
      )
    ) {

      throw (
        "item_revision_id ficou vazio no objeto de revisao " +
        "antes do CreateObjects."
      )
    }

    if ($Details) {

      Write-Host (
        "  Dados da revisao que serao enviados:"
      ) -ForegroundColor Cyan

      Write-Host (
        "    item_revision_id = '$finalRevisionId'"
      ) -ForegroundColor Gray

      Write-Host (
        "    gd5revcliente    = '$revisionClient'"
      ) -ForegroundColor Gray

      Write-Host (
        "    gd5revinterna    = '$revisionInternal'"
      ) -ForegroundColor Gray
    }
  }

  # Confirma que todas as propriedades adicionais definidas pela
  # configuracao do tipo permaneceram preenchidas no CreateInput.
  foreach ($extraKey in $revisionExtraProperties.Keys) {
    $extraValueText =
    Get-DcaCreateInputPropertyText `
      -InputObject $revisionSent `
      -PropertyName $extraKey

    if ([string]::IsNullOrWhiteSpace($extraValueText)) {
      throw "A propriedade '$extraKey' ficou vazia na revisao."
    }
  }

  # O sequence_id e controlado automaticamente pelo Teamcenter.
  # O envio manual dessa propriedade pode causar rejeicao da
  # criacao ou gerar uma sequencia incorreta.
  if ($revisionSent.StringProps.ContainsKey("sequence_id")) {
    throw "sequence_id nao deve ser enviado."
  }

  # ============================================================
  # 9. PREPARAR A CHAMADA CREATEOBJECTS
  # ============================================================
  $invokeArguments = New-Object "System.Object[]" 1
  $invokeArguments[0] = $createInArray

  # ============================================================
  # 10. EXECUTAR A CRIACAO NO TEAMCENTER
  # ============================================================
  #
  # A chamada abaixo pode efetivamente criar objetos no Teamcenter.
  # Todas as validacoes locais devem estar concluidas neste ponto.
  $createResponse = $null

  try {
    $createResponse =
    $createObjectsMethod.Invoke(
      $dataManagementService,
      $invokeArguments
    )
  }
  catch {

    # Percorre as excecoes internas para recuperar a mensagem
    # original retornada pelo servico SOA.
    $realException = $_.Exception

    while ($null -ne $realException.InnerException) {
      $realException = $realException.InnerException
    }

    $errorMessage = $realException.Message

    # Mensagens de duplicidade recebem uma mensagem simplificada
    # para indicar claramente que o codigo ja existe.
    if ($errorMessage -match $duplicatePattern) {
      throw "O item '$candidateCode' ja existe no Teamcenter."
    }

    throw "Falha ao executar CreateObjects para '$candidateCode': $errorMessage"
  }

  # ============================================================
  # 11. VALIDAR A RESPOSTA DO SERVICO SOA
  # ============================================================
  if ($null -eq $createResponse) {
    throw "CreateObjects retornou NULL."
  }

  # Os erros parciais podem existir mesmo quando CreateObjects
  # retorna um objeto de resposta valido.
  $serviceData = $createResponse.ServiceData
  $serviceErrors = @(Get-TeamcenterServiceErrors -ServiceData $serviceData)

  if ($serviceErrors.Count -gt 0) {

    $joinedErrors = $serviceErrors -join " | "

    if ($joinedErrors -match $duplicatePattern) {
      throw "O item '$candidateCode' ja existe no Teamcenter."
    }

    throw "O Teamcenter rejeitou a criacao: $joinedErrors"
  }

  # ============================================================
  # 12. RECUPERAR O ITEM E A REVISAO CRIADOS
  # ============================================================
  #
  # A resposta pode conter Item, revisao e objetos auxiliares.
  # Somente o Item e a revisao sao devolvidos ao fluxo principal.
  $createdObjects =
  @(
    Get-DcaCreatedObjects `
      -CreateResponse $createResponse `
      -ServiceData $serviceData
  )

  # Localiza o primeiro objeto retornado cujo tipo tecnico seja Item.
  $createdItem =
  $createdObjects |
    Where-Object {

    $null -ne $_ -and
    (
      $_.GetType().Name -eq "Item" -or
      $_.GetType().FullName -match '\.Item$'
    )
  } |
    Select-Object -First 1

  # Localiza a primeira revisao, incluindo tipos especializados
  # derivados de ItemRevision.
  $createdRevision =
  $createdObjects |
    Where-Object {

    if ($null -eq $_) {
      return $false
    }

    $createdObjectTypeName =
    $_.GetType().FullName

    $createdObjectTypeName -match
    '(?i)(ItemRevision|Revision)$'
  } |
    Select-Object -First 1

  if ($null -eq $createdItem) {
    throw (
      "CreateObjects nao retornou o Item criado. " +
      "Objetos retornados: $($createdObjects.Count)."
    )
  }

  # ============================================================
  # 13. NORMALIZAR OS OBJETOS CRIADOS
  # ============================================================
  #
  # Remove os wrappers criados pelo PowerShell antes de retornar
  # os objetos para o fluxo principal.
  $itemBaseObject = $createdItem.PSObject.BaseObject

  if ($null -ne $itemBaseObject) {
    $createdItem = $itemBaseObject
  }

  if ($null -ne $createdRevision) {

    $revisionBaseObject = $createdRevision.PSObject.BaseObject

    if ($null -ne $revisionBaseObject) {
      $createdRevision = $revisionBaseObject
    }
  }

  # ============================================================
  # 14. GRAVAR APROVADOR E DATA NA REVISAO CRIADA
  # ============================================================
  #
  # Utiliza a sobrecarga moderna:
  #
  #   SetProperties(
  #     DataManagement.PropInfo[],
  #     string[]
  #   )
  #
  # As propriedades sao aplicadas diretamente ao objeto da
  # revisao retornado pelo CreateObjects.
  if (
    $DocumentType -eq "Processo" -and
    $null -ne $createdRevision
  ) {

    # ==========================================================
    # A. LOCALIZAR OS TIPOS NECESSARIOS
    # ==========================================================

    $propInfoType =
    [System.AppDomain]::CurrentDomain.GetAssemblies() |
      ForEach-Object {

      try {

        $_.GetTypes()
      }
      catch {

        @()
      }
    } |
      Where-Object {
      $_.FullName -eq
      "Teamcenter.Services.Strong.Core._2010_09." +
      "DataManagement.PropInfo"
    } |
      Select-Object -First 1

    if ($null -eq $propInfoType) {

      throw (
        "O tipo DataManagement.PropInfo nao foi encontrado."
      )
    }

    $nameValueStructType =
    [System.AppDomain]::CurrentDomain.GetAssemblies() |
      ForEach-Object {

      try {

        $_.GetTypes()
      }
      catch {

        @()
      }
    } |
      Where-Object {
      $_.FullName -eq
      "Teamcenter.Services.Strong.Core._2010_09." +
      "DataManagement.NameValueStruct1"
    } |
      Select-Object -First 1

    if ($null -eq $nameValueStructType) {

      throw (
        "O tipo DataManagement.NameValueStruct1 " +
        "nao foi encontrado."
      )
    }

    # ==========================================================
    # B. PREPARAR A LISTA DE PROPRIEDADES
    # ==========================================================

    $nameValueEntries =
    [System.Collections.Generic.List[object]]::new()

    if (
      -not [string]::IsNullOrWhiteSpace(
        $approverClean
      )
    ) {

      $approverNameValue =
      [System.Activator]::CreateInstance(
        $nameValueStructType
      )

      $approverNameValue.Name =
      [string]"gd5AprovadorPDM"

      $approverNameValue.Values =
      [string[]]@(
        $approverClean
      )

      $nameValueEntries.Add(
        $approverNameValue.PSObject.BaseObject
      )
    }

    if (
      -not [string]::IsNullOrWhiteSpace(
        [string]$approvalDateTeamcenter
      )
    ) {

      $approvalDateNameValue =
      [System.Activator]::CreateInstance(
        $nameValueStructType
      )

      $approvalDateNameValue.Name =
      [string]"gd5AprovadorPDMData"

      $approvalDateNameValue.Values =
      [string[]]@(
        $approvalDateTeamcenter
      )

      $nameValueEntries.Add(
        $approvalDateNameValue.PSObject.BaseObject
      )
    }

    # Somente chama SetProperties quando existir pelo menos uma
    # propriedade de aprovacao preenchida.
    if ($nameValueEntries.Count -gt 0) {

      # ========================================================
      # C. CRIAR O ARRAY TIPADO DE NAMEVALUESTRUCT1
      # ========================================================

      $nameValueArray =
      [System.Array]::CreateInstance(
        $nameValueStructType,
        $nameValueEntries.Count
      )

      for (
        $nameValueIndex = 0
        $nameValueIndex -lt $nameValueEntries.Count
        $nameValueIndex++
      ) {

        $nameValueArray.SetValue(
          $nameValueEntries[$nameValueIndex],
          $nameValueIndex
        )
      }

      # ========================================================
      # D. MONTAR O PROPINFO DA REVISAO
      # ========================================================

      $propertyInfo =
      [System.Activator]::CreateInstance(
        $propInfoType
      )

      $propertyInfo.Object =
      $createdRevision

      $propertyInfo.VecNameVal =
      $nameValueArray

      # Timestamp vazio informa que nao sera utilizado controle
      # otimista de alteracao nesta chamada.
      $propertyInfo.Timestamp =
      [datetime]::MinValue

      $propInfoArray =
      [System.Array]::CreateInstance(
        $propInfoType,
        1
      )

      $propInfoArray.SetValue(
        $propertyInfo.PSObject.BaseObject,
        0
      )

      # ========================================================
      # E. LOCALIZAR A SOBRECARGA MODERNA DE SETPROPERTIES
      # ========================================================

      $setPropertiesMethod =
      $dataManagementService.GetType().GetMethods() |
        Where-Object {

        if (
          $_.Name -ne "SetProperties" -or
          $_.GetParameters().Count -ne 2
        ) {

          return $false
        }

        $methodParameters =
        $_.GetParameters()

        (
          $methodParameters[0].ParameterType.FullName -eq
          "Teamcenter.Services.Strong.Core._2010_09." +
          "DataManagement.PropInfo[]" -and
          $methodParameters[1].ParameterType -eq
          [string[]]
        )
      } |
        Select-Object -First 1

      if ($null -eq $setPropertiesMethod) {

        throw (
          "A sobrecarga SetProperties(" +
          "PropInfo[], string[]) nao foi encontrada."
        )
      }

      # ========================================================
      # F. MOSTRAR OS VALORES PREPARADOS
      # ========================================================

      if ($Details) {

        Write-Host ""

        Write-Host (
          "  Dados que serao aplicados na revisao:"
        ) -ForegroundColor Cyan

        Write-Host (
          "    Revisao: $candidateCode/$teamcenterRevisionId"
        ) -ForegroundColor Gray

        foreach (
          $nameValueEntry in
          $nameValueEntries
        ) {

          Write-Host (
            "    $($nameValueEntry.Name) = " +
            "'$(@($nameValueEntry.Values) -join ", ")'"
          ) -ForegroundColor White
        }
      }
      if ($Details) {

        Write-Host (
          "  Estrutura de SetProperties:"
        ) -ForegroundColor Cyan

        Write-Host (
          "    PropInfo: " +
          $propertyInfo.GetType().FullName
        ) -ForegroundColor DarkGray

        Write-Host (
          "    Objeto alvo: " +
          $createdRevision.GetType().FullName
        ) -ForegroundColor DarkGray

        Write-Host (
          "    Quantidade de propriedades: " +
          $nameValueArray.Length
        ) -ForegroundColor DarkGray

        Write-Host (
          "    Sobrecarga: SetProperties(" +
          "PropInfo[], string[])"
        ) -ForegroundColor DarkGray
      }

      # ========================================================
      # G. EXECUTAR SETPROPERTIES
      # ========================================================

      $setPropertiesArguments =
      [object[]]::new(2)

      $setPropertiesArguments[0] =
      $propInfoArray

      # Nenhuma opcao adicional e necessaria.
      $setPropertiesArguments[1] =
      [string[]]@()

      try {

        $setPropertiesResponse =
        $setPropertiesMethod.Invoke(
          $dataManagementService,
          $setPropertiesArguments
        )
      }
      catch {

        $realException =
        $_.Exception

        while (
          $null -ne $realException.InnerException
        ) {

          $realException =
          $realException.InnerException
        }

        throw (
          "Falha ao gravar os dados de aprovacao na revisao " +
          "'$candidateCode/$teamcenterRevisionId': " +
          $realException.Message
        )
      }

      if ($null -eq $setPropertiesResponse) {

        throw (
          "SetProperties retornou NULL ao atualizar a revisao " +
          "'$candidateCode/$teamcenterRevisionId'."
        )
      }

      $setPropertiesServiceData =
      $setPropertiesResponse.Data

      if ($null -eq $setPropertiesServiceData) {

        throw (
          "SetProperties nao retornou ServiceData ao atualizar " +
          "'$candidateCode/$teamcenterRevisionId'."
        )
      }

      $setPropertiesErrors =
      @(
        Get-TeamcenterServiceErrors `
          -ServiceData $setPropertiesServiceData
      )

      if ($setPropertiesErrors.Count -gt 0) {

        throw (
          "O Teamcenter rejeitou os dados de aprovacao: " +
          ($setPropertiesErrors -join " | ")
        )
      }

      Write-Success (
        "Aprovador e data gravados na revisao " +
        "$candidateCode/$teamcenterRevisionId."
      )
    }
  }
  # ============================================================
  # 15. RETORNAR O DESTINO CRIADO
  # ============================================================

  return [PSCustomObject]@{
    Code = $candidateCode
    Item = $createdItem
    Revision = $createdRevision
  }
}
