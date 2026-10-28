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
#   4. devolve os objetos ao fluxo principal.
#
# Esta funcao pode criar objetos efetivamente no Teamcenter.
# Todas as validacoes locais devem ocorrer antes de CreateObjects.
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

    [Parameter(Mandatory = $true)]
    [ValidateSet("Original", "Processo", "NormaExterna")]
    [string]$DocumentType
  )

  # ============================================================
  # 1. VALIDAR E NORMALIZAR OS DADOS DE ENTRADA
  # ============================================================
  #
  # O padrao abaixo identifica mensagens de duplicidade retornadas
  # tanto por excecoes quanto pelos erros parciais do servico SOA.
  $duplicatePattern = '(?i)already exists|ja existe|duplicate|not unique|is not unique'

  $sourceCodeClean = $SourceCode.Trim().ToUpper()
  $itemNameClean = $ItemName.Trim()

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

  foreach ($extraKey in $revisionExtraProperties.Keys) {
    $revisionProperties[$extraKey] =
    $revisionExtraProperties[$extraKey]
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
  # 14. RETORNAR O DESTINO CRIADO
  # ============================================================
  return [PSCustomObject]@{
    Code = $candidateCode
    Item = $createdItem
    Revision = $createdRevision
  }
}
