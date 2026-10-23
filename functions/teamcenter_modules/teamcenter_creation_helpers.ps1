# ============================================================
# FUNCOES AUXILIARES PARA CRIACAO NO TEAMCENTER
# ============================================================
#
# Este arquivo prepara os tipos, propriedades e objetos utilizados
# durante a criacao de Items e revisoes no Teamcenter.
#
# Responsabilidades:
#   1. normalizar as revisoes dos documentos;
#   2. selecionar os tipos tecnicos conforme o ambiente;
#   3. preparar as propriedades especificas de cada tipo DCA;
#   4. separar propriedades entre StringProps e IntProps;
#   5. criar e preencher objetos CreateInput;
#   6. definir membros por reflexao;
#   7. interpretar os objetos retornados por CreateObjects.
#
# As funcoes deste arquivo apenas preparam e interpretam objetos.
# A chamada efetiva de CreateObjects permanece no arquivo
# teamcenter_creation.ps1.
# ============================================================

# ============================================================
# NORMALIZACAO DAS REVISOES DO CLIENTE
# ============================================================
function Get-DcaClientRevisionInfo {

  # Normaliza a revisao do Desenho Original e remove o sufixo
  # interno quando o cartao apresentar esse formato.
  param(
    [string]$ClientRevision
  )

  # Normaliza o valor recebido antes de procurar o sufixo interno
  # utilizado em algumas revisoes do Desenho Original.
  $value = ([string]$ClientRevision).Trim().ToUpper()
  $revision = $value

  # Quando a revisao termina com A0, A1, A2, A3 ou A4, remove
  # esse sufixo e mantem somente a revisao do cliente.
  if ($value -match '^(?<Revision>[A-Z0-9]{1,10})A[0-4]$') {
    $revision = $Matches["Revision"]
  }

  return [PSCustomObject]@{
    Original = $value
    Revision = $revision
  }
}

# ============================================================
# CONFIGURACAO DOS TIPOS DCA
# ============================================================
function Get-DcaTypeConfiguration {

  # Retorna a configuracao tecnica utilizada para criar o Item
  # e a revisao no Teamcenter.
  #
  # A configuracao depende de:
  #   - ambiente ativo;
  #   - tipo do documento;
  #   - revisao recebida do PDF ou do cartao.
  #
  # O retorno informa:
  #   - tipo do Item;
  #   - tipo da revisao;
  #   - propriedade e valor do cliente;
  #   - item_revision_id;
  #   - propriedades adicionais da revisao.
  param(
    [Parameter(Mandatory = $true)]
    [ValidateSet(
      "Original",
      "Processo",
      "NormaExterna"
    )]
    [string]$DocumentType,

    [string]$ClientRevision,

    [ValidateSet(
      "Teste",
      "Processo"
    )]
    [string]$TeamcenterEnvironment
  )

  # ============================================================
  # 1. DETERMINAR O AMBIENTE DO TEAMCENTER
  # ============================================================
  #
  # O parametro informado possui prioridade. Quando estiver vazio,
  # utiliza o ambiente da sessao conectada ou a configuracao do .env.
  if (
    [string]::IsNullOrWhiteSpace(
      $TeamcenterEnvironment
    )
  ) {

    if (
      -not [string]::IsNullOrWhiteSpace(
        $script:TeamcenterEnvironment
      )
    ) {

      $TeamcenterEnvironment = $script:TeamcenterEnvironment
    }
    else {

      $teamcenterSettings = Get-TeamcenterSettings

      $TeamcenterEnvironment = [string]$teamcenterSettings.Environment
    }
  }

  if (
    $TeamcenterEnvironment -notin @(
      "Teste",
      "Processo"
    )
  ) {

    throw (
      "O ambiente do Teamcenter nao foi identificado. " +
      "Ambiente recebido: '$TeamcenterEnvironment'."
    )
  }

  # ============================================================
  # 2. DEFINIR OS TIPOS DO AMBIENTE DE PROCESSO
  # ============================================================
  $processTypes = @{

    Original = @{
      ItemType = $env:DCA_TC_PROCESS_ORIGINAL_ITEM_TYPE
      RevisionType = $env:DCA_TC_PROCESS_ORIGINAL_REVISION_TYPE
      ClientProperty = $env:DCA_TC_PROCESS_ORIGINAL_CLIENT_PROPERTY
      ClientValue = $env:DCA_TC_PROCESS_ORIGINAL_CLIENT_VALUE
    }

    Processo = @{
      ItemType = $env:DCA_TC_PROCESS_PROCESS_ITEM_TYPE
      RevisionType = $env:DCA_TC_PROCESS_PROCESS_REVISION_TYPE
      ClientProperty = $env:DCA_TC_PROCESS_PROCESS_CLIENT_PROPERTY
      ClientValue = $env:DCA_TC_PROCESS_PROCESS_CLIENT_VALUE
    }

    NormaExterna = @{
      ItemType = $env:DCA_TC_PROCESS_STANDARD_ITEM_TYPE
      RevisionType = $env:DCA_TC_PROCESS_STANDARD_REVISION_TYPE
      ClientProperty = $env:DCA_TC_PROCESS_STANDARD_CLIENT_PROPERTY
      ClientValue = $env:DCA_TC_PROCESS_STANDARD_CLIENT_VALUE
    }
  }

  # ============================================================
  # 3. DEFINIR OS TIPOS DO AMBIENTE DE TESTE
  # ============================================================
  $testTypes = @{

    Original = @{
      ItemType = $env:DCA_TC_TEST_ORIGINAL_ITEM_TYPE
      RevisionType = $env:DCA_TC_TEST_ORIGINAL_REVISION_TYPE
      ClientProperty = $env:DCA_TC_TEST_ORIGINAL_CLIENT_PROPERTY
      ClientValue = $env:DCA_TC_TEST_ORIGINAL_CLIENT_VALUE
    }

    Processo = @{
      ItemType = $env:DCA_TC_TEST_PROCESS_ITEM_TYPE
      RevisionType = $env:DCA_TC_TEST_PROCESS_REVISION_TYPE
      ClientProperty = $env:DCA_TC_TEST_PROCESS_CLIENT_PROPERTY
      ClientValue = $env:DCA_TC_TEST_PROCESS_CLIENT_VALUE
    }

    NormaExterna = @{
      ItemType = $env:DCA_TC_TEST_STANDARD_ITEM_TYPE
      RevisionType = $env:DCA_TC_TEST_STANDARD_REVISION_TYPE
      ClientProperty = $env:DCA_TC_TEST_STANDARD_CLIENT_PROPERTY
      ClientValue = $env:DCA_TC_TEST_STANDARD_CLIENT_VALUE
    }
  }

  # ============================================================
  # 4. SELECIONAR A CONFIGURACAO DO AMBIENTE ATIVO
  # ============================================================
  $selectedTypes =
  if ($TeamcenterEnvironment -eq "Processo") {
    $processTypes
  }
  else {
    $testTypes
  }

  if (-not $selectedTypes.ContainsKey($DocumentType)) {

    throw (
      "Tipo de documento '$DocumentType' nao configurado " +
      "para o ambiente '$TeamcenterEnvironment'."
    )
  }

  # ============================================================
  # 5. OBTER A CONFIGURACAO DO TIPO DE DOCUMENTO
  # ============================================================
  $selectedDocumentTypes = $selectedTypes[$DocumentType]

  # Converte os valores da configuracao para texto antes das
  # validacoes e da montagem do objeto de retorno.
  $itemType = [string]$selectedDocumentTypes.ItemType

  $revisionType = [string]$selectedDocumentTypes.RevisionType

  $clientProperty = [string]$selectedDocumentTypes.ClientProperty

  $clientValue = [string]$selectedDocumentTypes.ClientValue

  # ============================================================
  # 6. VALIDAR OS NOMES TECNICOS
  # ============================================================
  #
  # A criacao e bloqueada quando os nomes tecnicos do Item ou da
  # revisao estiverem vazios ou ainda contiverem marcadores.
  if (
    [string]::IsNullOrWhiteSpace($itemType) -or
    $itemType -like "<*>"
  ) {

    throw (
      "ItemType de '$DocumentType' ainda nao foi " +
      "configurado para o ambiente " +
      "'$TeamcenterEnvironment'."
    )
  }

  if (
    [string]::IsNullOrWhiteSpace($revisionType) -or
    $revisionType -like "<*>"
  ) {

    throw (
      "RevisionType de '$DocumentType' ainda nao foi " +
      "configurado para o ambiente " +
      "'$TeamcenterEnvironment'."
    )
  }

  # ============================================================
  # 7. CONFIGURAR O DESENHO ORIGINAL
  # ============================================================
  #
  # A revisao normalizada e utilizada como item_revision_id e
  # como valor da propriedade gd5revcliente.
  if ($DocumentType -eq "Original") {

    $info = Get-DcaClientRevisionInfo `
      -ClientRevision $ClientRevision

    if (
      [string]::IsNullOrWhiteSpace(
        $info.Revision
      )
    ) {

      throw (
        "ClientRevision ficou vazia para " +
        "'$DocumentType'."
      )
    }

    if ($info.Revision.Length -gt 5) {

      throw (
        "Revisao Cliente '$($info.Revision)' possui " +
        "$($info.Revision.Length) caracteres. " +
        "O limite configurado e 5."
      )
    }

    return [PSCustomObject]@{
      Environment = $TeamcenterEnvironment
      ItemType = $itemType
      RevisionType = $revisionType
      ClientProperty = $clientProperty
      ClientValue = $clientValue
      TeamcenterRevisionId = $info.Revision

      RevisionProperties = @{
        "gd5revcliente" = $info.Revision
      }
    }
  }

  # ============================================================
  # 8. CONFIGURAR A FICHA DE PROCESSO
  # ============================================================
  #
  # A revisao de Processo e separada em:
  #   - revisao do cliente;
  #   - revisao interna numerica.
  #
  # O item_revision_id e formado pela concatenacao dos dois
  # valores normalizados.
  if ($DocumentType -eq "Processo") {

    $processValueRaw =
    ([string]$ClientRevision).Trim().ToUpperInvariant()

    $clientRevisionValue =
    $null

    $internalRevisionValue =
    $null

    $processValue =
    $null

    # O cartao pode retornar a revisao de Processo com ou sem
    # separador. Exemplos aceitos: AH-3, AH3, BA-4 e BA4.
    # Primeiro tenta o formato com separador, por exemplo AH-3.
    $processRevisionWithSeparatorMatch =
    [System.Text.RegularExpressions.Regex]::Match(
      $processValueRaw,
      '^([A-Z0-9]{2})-([0-9])$'
    )

    # Depois tenta o formato sem separador, por exemplo AH3.
    $processRevisionWithoutSeparatorMatch =
    [System.Text.RegularExpressions.Regex]::Match(
      $processValueRaw,
      '^([A-Z0-9-]{1,2})([0-9])$'
    )

    if ($processRevisionWithSeparatorMatch.Success) {

      $clientRevisionValue =
      $processRevisionWithSeparatorMatch.Groups[1].Value

      $internalRevisionValue =
      $processRevisionWithSeparatorMatch.Groups[2].Value
    }
    elseif ($processRevisionWithoutSeparatorMatch.Success) {

      $clientRevisionValue =
      $processRevisionWithoutSeparatorMatch.Groups[1].Value

      $internalRevisionValue =
      $processRevisionWithoutSeparatorMatch.Groups[2].Value
    }
    else {

      throw (
        "A revisao '$processValueRaw' nao segue o padrao " +
        "de DCA Processo. Formatos aceitos: AH-3, AH3, " +
        "BA-4, BA4 ou --4."
      )
    }

    $clientRevisionValue =
    ([string]$clientRevisionValue).Trim().ToUpperInvariant()

    $internalRevisionValue =
    ([string]$internalRevisionValue).Trim()

    if (
      $clientRevisionValue -notmatch
      '^[A-Z0-9-]{1,2}$'
    ) {

      throw (
        "A revisao cliente '$clientRevisionValue' e invalida."
      )
    }

    if (
      $internalRevisionValue -notmatch
      '^[0-9]$'
    ) {

      throw (
        "A revisao interna '$internalRevisionValue' e invalida. " +
        "Era esperado exatamente um digito."
      )
    }

    # O item_revision_id enviado ao Teamcenter e formado pela
    # concatenacao da revisao do cliente com a revisao interna.
    $processValue =
    $clientRevisionValue + $internalRevisionValue
    if ($Details) {

      Write-Host (
        "  Revisao recebida do cartao: " +
        "[$processValueRaw]"
      ) -ForegroundColor DarkGray

      Write-Host (
        "  Revisao cliente: " +
        "[$clientRevisionValue]"
      ) -ForegroundColor DarkGray

      Write-Host (
        "  Revisao interna: " +
        "[$internalRevisionValue]"
      ) -ForegroundColor DarkGray

      Write-Host (
        "  Revision ID do Teamcenter: " +
        "[$processValue]"
      ) -ForegroundColor Cyan
    }
    return [PSCustomObject]@{
      Environment = $TeamcenterEnvironment
      ItemType = $itemType
      RevisionType = $revisionType
      ClientProperty = $clientProperty
      ClientValue = $clientValue
      TeamcenterRevisionId = $processValue

      RevisionProperties = @{
        "gd5revcliente" = $clientRevisionValue
        "gd5revinterna" = $internalRevisionValue
      }
    }
  }

  # ============================================================
  # 9. CONFIGURAR A NORMA EXTERNA
  # ============================================================
  #
  # A revisao documental permanece separada do item_revision_id.
  # O tipo de revisao da Norma Externa exige um identificador
  # numerico com exatamente tres digitos.
  if ($DocumentType -eq "NormaExterna") {

    # A revisao documental e obtida do PDF ou do cartao de dados.
    # Exemplo: REV-U.
    #
    # Essa revisao sera utilizada pelo Dataset, mas nao diretamente
    # como item_revision_id da revisao criada.
    $standardRevision =
    ([string]$ClientRevision).Trim().ToUpperInvariant()

    if (
      [string]::IsNullOrWhiteSpace(
        $standardRevision
      )
    ) {

      throw (
        "A revisao da Norma Externa ficou vazia."
      )
    }

    if (
      $standardRevision -notmatch
      '^[A-Z0-9.-]{1,20}$'
    ) {

      throw (
        "A revisao da Norma Externa possui formato invalido: " +
        "'$standardRevision'."
      )
    }

    # O tipo GD5_DCA_NORMARevision exige que item_revision_id
    # siga o padrao numerico NNN. A revisao documental, como
    # REV-U, nao pode ser usada diretamente nesse campo.
    $teamcenterRevisionId =
    ([string]$env:DCA_TC_STANDARD_INITIAL_REVISION).Trim()

    if (
      [string]::IsNullOrWhiteSpace(
        $teamcenterRevisionId
      )
    ) {

      # Utiliza 001 como valor padrao quando a configuracao nao
      # estiver preenchida no arquivo .env.
      $teamcenterRevisionId =
      "001"
    }

    if (
      $teamcenterRevisionId -notmatch
      '^[0-9]{3}$'
    ) {

      throw (
        "DCA_TC_STANDARD_INITIAL_REVISION possui valor invalido: " +
        "'$teamcenterRevisionId'. Era esperado exatamente " +
        "tres numeros, por exemplo 001."
      )
    }

    if ($Details) {

      Write-Host (
        "  Revisao documental da Norma Externa: " +
        "[$standardRevision]"
      ) -ForegroundColor DarkGray

      Write-Host (
        "  Revision ID usado no Teamcenter: " +
        "[$teamcenterRevisionId]"
      ) -ForegroundColor Cyan
    }

    return [PSCustomObject]@{
      Environment = $TeamcenterEnvironment
      ItemType = $itemType
      RevisionType = $revisionType
      ClientProperty = $clientProperty
      ClientValue = $clientValue
      TeamcenterRevisionId = $teamcenterRevisionId
      DocumentRevision = $standardRevision
      RevisionProperties = @{}
    }
  }
  throw (
    "Tipo de documento nao suportado: " +
    "'$DocumentType'."
  )
}

# ============================================================
# CONFIGURACAO DAS PROPRIEDADES INTEIRAS
# ============================================================
function Get-DcaIntegerPropertyNames {

  # Retorna os nomes das propriedades que devem ser enviadas
  # em IntProps.
  #
  # Quando a configuracao estiver vazia, gd5revinterna e usada
  # como valor padrao.
  #
  # O valor "none" desativa o envio de propriedades inteiras.
  #
  # Le a lista configurada no .env e remove espacos externos.
  $configuredValue =
  ([string]$env:DCA_TC_INTEGER_PROPERTIES).Trim()

  if ([string]::IsNullOrWhiteSpace($configuredValue)) {
    return @("gd5revinterna")
  }

  if ($configuredValue -ieq "none") {
    return @()
  }

  $names =
  [System.Collections.Generic.List[string]]::new()

  # Aceita nomes separados por barra vertical, ponto e virgula
  # ou virgula.
  foreach ($part in ($configuredValue -split '[|;,]')) {

    $name =
    ([string]$part).Trim()

    if (-not [string]::IsNullOrWhiteSpace($name)) {
      $names.Add($name)
    }
  }

  return $names.ToArray()
}

# ============================================================
# LEITURA DAS PROPRIEDADES DO CREATEINPUT
# ============================================================
function Get-DcaCreateInputPropertyText {

  # Recupera uma propriedade do CreateInput independentemente
  # de ela estar armazenada em StringProps ou IntProps.
  #
  # O valor sempre e convertido para texto para simplificar as
  # validacoes executadas antes de CreateObjects.
  param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNull()]
    $InputObject,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$PropertyName
  )

  if (
    $null -ne $InputObject.StringProps -and
    $InputObject.StringProps.ContainsKey($PropertyName)
  ) {
    return ([string]$InputObject.StringProps[$PropertyName]).Trim()
  }

  if (
    $null -ne $InputObject.IntProps -and
    $InputObject.IntProps.ContainsKey($PropertyName)
  ) {
    return ([string]$InputObject.IntProps[$PropertyName]).Trim()
  }

  return ""
}
# ============================================================
# CONSTRUCAO DOS OBJETOS CREATEINPUT
# ============================================================
function New-DcaCreateInputObject {

  # Cria e preenche um objeto CreateInput compativel com a API SOA.
  #
  # As propriedades configuradas como inteiras sao armazenadas
  # em IntProps. Todas as demais sao armazenadas em StringProps.
  param(
    [Parameter(Mandatory = $true)]
    [type]$InputType,

    [Parameter(Mandatory = $true)]
    [string]$BoName,

    [Parameter(Mandatory = $true)]
    [hashtable]$Properties,

    [string[]]$IntegerPropertyNames = @()
  )

  # ============================================================
  # 1. CRIAR A INSTANCIA DO CREATEINPUT
  # ============================================================
  $inputObject = [System.Activator]::CreateInstance($InputType)

  if ($null -eq $inputObject) {
    throw "Nao foi possivel criar o CreateInput de '$BoName'."
  }

  $inputObject.BoName = $BoName

  # ============================================================
  # 2. PREPARAR AS COLECOES DE PROPRIEDADES
  # ============================================================
  $stringProps = New-Object System.Collections.Hashtable
  $intProps = New-Object System.Collections.Hashtable

  # ============================================================
  # 3. SEPARAR STRINGPROPS E INTPROPS
  # ============================================================
  foreach ($key in $Properties.Keys) {

    $isInteger = $false

    foreach ($integerName in $IntegerPropertyNames) {

      if ($key -ieq $integerName) {
        $isInteger = $true
        break
      }
    }

    if ($isInteger) {

      $parsedInteger = 0

      if (-not [int]::TryParse(
          ([string]$Properties[$key]).Trim(),
          [ref]$parsedInteger
        )) {

        throw (
          "A propriedade inteira '$key' recebeu um valor " +
          "invalido: '$($Properties[$key])'."
        )
      }

      $intProps[$key] = [int]$parsedInteger
    }
    else {

      $stringProps[$key] = [string]$Properties[$key]
    }
  }

  # ============================================================
  # 4. APLICAR AS PROPRIEDADES AO CREATEINPUT
  # ============================================================
  $inputObject.StringProps = $stringProps

  if ($intProps.Count -gt 0) {

    Set-DcaObjectMemberValue `
      -InputObject $inputObject `
      -MemberName "IntProps" `
      -Value $intProps
  }

  if ($null -eq $inputObject.StringProps) {

    throw (
      "StringProps ficou NULL no CreateInput de '$BoName'."
    )
  }

  # ============================================================
  # 5. RETORNAR O CREATEINPUT SEM ENUMERACAO
  # ============================================================
  #
  # NoEnumerate impede que o PowerShell tente decompor o objeto
  # retornado como uma colecao.
  Write-Output `
    -NoEnumerate `
    -InputObject $inputObject
}

# ============================================================
# INTERPRETACAO DA RESPOSTA DE CREATEOBJECTS
# ============================================================
function Get-DcaCreatedObjects {

  # Reune os objetos criados que podem aparecer tanto na resposta
  # direta de CreateObjects quanto no ServiceData.
  #
  # As duas origens sao combinadas e objetos repetidos nao sao
  # adicionados novamente.
  param(
    $CreateResponse,
    $ServiceData
  )

  # ============================================================
  # 1. PREPARAR A COLECAO DE RESULTADOS
  # ============================================================
  $createdObjects = [System.Collections.Generic.List[object]]::new()
  $publicInstance = [System.Reflection.BindingFlags]::Public -bor
  [System.Reflection.BindingFlags]::Instance

  # ============================================================
  # 2. LER OS OBJETOS DA RESPOSTA DIRETA
  # ============================================================
  if ($null -ne $CreateResponse.Output) {

    foreach ($outputEntry in $CreateResponse.Output) {

      if ($null -eq $outputEntry) {
        continue
      }

      foreach ($field in $outputEntry.GetType().GetFields($publicInstance)) {

        $fieldValue = $field.GetValue($outputEntry)

        if ($null -eq $fieldValue) {
          continue
        }

        if (
          $fieldValue -is [System.Collections.IEnumerable] -and
          $fieldValue -isnot [string]
        ) {

          foreach ($returnedObject in $fieldValue) {

            if (
              $null -ne $returnedObject -and
              -not $createdObjects.Contains($returnedObject)
            ) {
              $createdObjects.Add($returnedObject)
            }
          }
        }
        elseif ($fieldValue.GetType().FullName -like "Teamcenter.Soa.Client.Model.*") {

          if (-not $createdObjects.Contains($fieldValue)) {
            $createdObjects.Add($fieldValue)
          }
        }
      }
    }
  }

  # ============================================================
  # 3. LER OS OBJETOS CRIADOS DO SERVICEDATA
  # ============================================================
  if ($null -ne $ServiceData) {

    $createdCount = $ServiceData.SizeOfCreatedObjects()

    for ($objectIndex = 0; $objectIndex -lt $createdCount; $objectIndex++) {

      $createdObject = $ServiceData.GetCreatedObject($objectIndex)

      if (
        $null -ne $createdObject -and
        -not $createdObjects.Contains($createdObject)
      ) {
        $createdObjects.Add($createdObject)
      }
    }
  }

  # ============================================================
  # 4. APRESENTAR O DIAGNOSTICO
  # ============================================================
  if ($Details) {

    Write-Host (
      "  Quantidade de objetos criados: $($createdObjects.Count)"
    ) -ForegroundColor DarkGray
  }

  # ============================================================
  # 5. RETORNAR OS OBJETOS SEM REPETICOES
  # ============================================================
  return $createdObjects.ToArray()
}

# ============================================================
# DEFINICAO DE MEMBROS POR REFLEXAO
# ============================================================
function Set-DcaObjectMemberValue {

  # Define um campo ou uma propriedade publica por reflexao.
  #
  # Algumas versoes da API SOA expoem o mesmo membro como campo,
  # enquanto outras versoes o expoem como propriedade.
  param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNull()]
    $InputObject,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$MemberName,

    [Parameter(Mandatory = $true)]
    [ValidateNotNull()]
    $Value
  )

  # ============================================================
  # 1. IDENTIFICAR O TIPO E OS MEMBROS PUBLICOS
  # ============================================================
  $objectType =
  $InputObject.GetType()

  $bindingFlags =
  [System.Reflection.BindingFlags]::Public -bor
  [System.Reflection.BindingFlags]::Instance -bor
  [System.Reflection.BindingFlags]::IgnoreCase

  # ============================================================
  # 2. TENTAR DEFINIR O MEMBRO COMO PROPRIEDADE
  # ============================================================
  $memberProperty =
  $objectType.GetProperty(
    $MemberName,
    $bindingFlags
  )

  if ($null -ne $memberProperty) {

    if (-not $memberProperty.CanWrite) {

      throw (
        "A propriedade '$MemberName' existe em " +
        "'$($objectType.FullName)', mas nao permite escrita."
      )
    }

    $memberProperty.SetValue(
      $InputObject,
      $Value,
      $null
    )

    return
  }

  # ============================================================
  # 3. TENTAR DEFINIR O MEMBRO COMO CAMPO
  # ============================================================
  $memberField =
  $objectType.GetField(
    $MemberName,
    $bindingFlags
  )

  if ($null -ne $memberField) {

    $memberField.SetValue(
      $InputObject,
      $Value
    )

    return
  }

  # ============================================================
  # 4. LISTAR OS MEMBROS DISPONIVEIS
  # ============================================================
  #
  # Quando o membro solicitado nao existe, a mensagem informa
  # todos os campos e propriedades localizados no tipo.
  $availableMembers =
  @(
    $objectType.GetMembers($bindingFlags) |
      Where-Object {
      $_.MemberType -eq
      [System.Reflection.MemberTypes]::Field -or
      $_.MemberType -eq
      [System.Reflection.MemberTypes]::Property
    } |
      ForEach-Object {
      $_.Name
    } |
      Sort-Object -Unique
  )

  throw (
    "O membro '$MemberName' nao foi encontrado no tipo " +
    "'$($objectType.FullName)'. Membros disponiveis: " +
    ($availableMembers -join ", ")
  )
}
