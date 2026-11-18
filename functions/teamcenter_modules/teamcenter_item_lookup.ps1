# ============================================================
# LOCALIZACAO DE ITEMS E REVISOES NO TEAMCENTER
# ============================================================
# Localiza Items e revisoes existentes para o fluxo DatasetOnly:
#   1. Load_Item;
#   2. getItem com os valores de empresa configurados;
#   3. Saved Query Item_Name_or_ID;
#   4. selecao manual quando houver mais de um destino.
# Nao cria Items, revisoes ou Datasets.
# ============================================================

# Remove o wrapper PSObject quando presente.
function Get-DcaTeamcenterBaseObject {
  param($Object)

  if ($null -eq $Object) { return $null }
  if ($null -ne $Object.PSObject.BaseObject) { return $Object.PSObject.BaseObject }
  return $Object
}

# Retorna a excecao interna real.
function Get-DcaTeamcenterRootException {
  param([Parameter(Mandatory)]$Exception)

  while ($null -ne $Exception.InnerException) { $Exception = $Exception.InnerException }
  return $Exception
}

# Localiza um metodo publico pela quantidade de parametros.
function Get-DcaTeamcenterObjectMethod {
  param(
    [Parameter(Mandatory)]$Object,
    [Parameter(Mandatory)][string]$Name,
    [Parameter(Mandatory)][int]$ParameterCount
  )

  return $Object.GetType().GetMethods() |
    Where-Object { $_.Name -ieq $Name -and $_.GetParameters().Count -eq $ParameterCount } |
    Select-Object -First 1
}

# Carrega propriedades de um objeto do modelo Teamcenter.
function Update-DcaTeamcenterObjectProperties {
  param(
    [Parameter(Mandatory)]$ModelObject,
    [Parameter(Mandatory)][string[]]$PropertyNames
  )

  $ModelObject = Get-DcaTeamcenterBaseObject $ModelObject
  $service = Get-TeamcenterDataManagementService
  $method = Get-DcaTeamcenterObjectMethod -Object $service -Name "GetProperties" -ParameterCount 2
  if ($null -eq $method) { throw "DataManagementService.GetProperties nao foi encontrado." }

  $arrayType = $method.GetParameters()[0].ParameterType
  if (-not $arrayType.IsArray) { throw "O primeiro parametro de GetProperties nao e um array." }

  $objectType = $arrayType.GetElementType()
  if ($null -eq $objectType) { throw "O tipo de objeto aceito por GetProperties nao foi identificado." }

  $objects = [System.Array]::CreateInstance($objectType, 1)
  $objects.SetValue($ModelObject, 0)

  $response = $method.Invoke($service, [object[]]@($objects, [string[]]$PropertyNames))
  if ($null -eq $response) { return }

  $errors = @(Get-TeamcenterServiceErrors -ServiceData $response)
  if ($errors.Count -gt 0) {
    throw "O Teamcenter nao carregou as propriedades solicitadas: $($errors -join ' | ')"
  }
}

# Cria o retorno padrao da verificacao por Load_Item.
function New-DcaTeamcenterItemExistsResult {
  param(
    [Parameter(Mandatory)][string]$Status,
    [Parameter(Mandatory)][bool]$Exists,
    [Parameter(Mandatory)][string]$ItemCode,
    $Item,
    $Revision,
    [AllowNull()][string]$ErrorMessage
  )

  [PSCustomObject]@{
    Status = $Status
    Exists = $Exists
    ItemCode = $ItemCode
    Item = $Item
    Revision = $Revision
    ErrorMessage = $ErrorMessage
  }
}

# Cria o retorno padrao da localizacao de Item e revisao.
function New-DcaTeamcenterRevisionResult {
  param(
    [Parameter(Mandatory)][string]$Status,
    [Parameter(Mandatory)][bool]$ItemExists,
    [Parameter(Mandatory)][bool]$RevisionExists,
    [Parameter(Mandatory)][string]$ItemCode,
    [Parameter(Mandatory)][string]$ExpectedRevision,
    [string]$FoundRevision = "",
    $Item,
    $Revision,
    [AllowNull()][string]$ErrorMessage
  )

  [PSCustomObject]@{
    Status = $Status
    ItemExists = $ItemExists
    RevisionExists = $RevisionExists
    ItemCode = $ItemCode
    ExpectedRevision = $ExpectedRevision
    FoundRevision = $FoundRevision
    Item = $Item
    Revision = $Revision
    ErrorMessage = $ErrorMessage
  }
}

# Verifica se Load_Item retorna uma revisao valida para o codigo.
function Test-DcaTeamcenterItemExists {
  param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$ItemCode
  )

  if ($null -eq $script:TeamcenterFunctions) {
    throw "As funcoes do Teamcenter nao foram carregadas. Execute Connect-Teamcenter primeiro."
  }

  $itemCodeClean = $ItemCode.Trim().ToUpperInvariant()
  if ([string]::IsNullOrWhiteSpace($itemCodeClean)) {
    return New-DcaTeamcenterItemExistsResult -Status "Erro" -Exists $false `
      -ItemCode "" -ErrorMessage "O codigo do Item ficou vazio."
  }

  $cacheKey = "{0}|{1}" -f ([string]$script:TeamcenterEnvironment).Trim(), $itemCodeClean
  if ($null -ne $script:TeamcenterItemLookupCache -and
    $script:TeamcenterItemLookupCache.ContainsKey($cacheKey)) {
    return $script:TeamcenterItemLookupCache[$cacheKey]
  }

  $method = Get-TeamcenterMethod -MethodName "Load_Item" -ParameterCount 1

  try {
    if ($Details) {
      Write-Host "  Consultando Item '$itemCodeClean'..." -ForegroundColor DarkGray
    }

    $revision = Get-DcaTeamcenterBaseObject ($method.Invoke($null, @([string]$itemCodeClean)))

    if ($null -eq $revision) {
      $result = New-DcaTeamcenterItemExistsResult -Status "Nao" -Exists $false `
        -ItemCode $itemCodeClean
    }
    else {
      $typeName = $revision.GetType().FullName

      if ($typeName -notmatch '(?i)(ItemRevision|Revision)$') {
        $result = New-DcaTeamcenterItemExistsResult -Status "Erro" -Exists $false `
          -ItemCode $itemCodeClean -Revision $revision `
          -ErrorMessage "Load_Item retornou um objeto que nao e revisao: '$typeName'."
      }
      else {
        $result = New-DcaTeamcenterItemExistsResult -Status "Sim" -Exists $true `
          -ItemCode $itemCodeClean -Revision $revision
      }
    }
  }
  catch {
    $rootException = Get-DcaTeamcenterRootException $_.Exception
    $message = ([string]$rootException.Message).Trim()

    if ($message -match '(?i)not found|nao encontrado|não encontrado|does not exist|cannot find|unable to find') {
      $result = New-DcaTeamcenterItemExistsResult -Status "Nao" -Exists $false `
        -ItemCode $itemCodeClean
    }
    else {
      $result = New-DcaTeamcenterItemExistsResult -Status "Erro" -Exists $false `
        -ItemCode $itemCodeClean -ErrorMessage $message
    }
  }

  if ($null -ne $script:TeamcenterItemLookupCache) {
    $script:TeamcenterItemLookupCache[$cacheKey] = $result
  }

  return $result
}

# Executa Item_Name_or_ID e retorna todos os Items cujo item_id confere.
function Find-DcaTeamcenterItemBySavedQuery {
  param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$ItemCode
  )

  $itemCodeClean = $ItemCode.Trim().ToUpperInvariant()
  $connection = Get-TeamcenterConnection

  $queryAssembly = $script:TeamcenterQueryAssemblies |
    Where-Object { [System.IO.Path]::GetFileName([string]$_.Location) -ieq "TcSoaQueryStrong.dll" } |
    Select-Object -First 1
  if ($null -eq $queryAssembly) { throw "TcSoaQueryStrong.dll nao esta carregada." }

  $serviceType = $queryAssembly.GetType(
    "Teamcenter.Services.Strong.Query.SavedQueryService", $false, $false
  )
  if ($null -eq $serviceType) { throw "O tipo SavedQueryService nao foi encontrado." }

  $getService = $serviceType.GetMethods() |
    Where-Object { $_.Name -eq "getService" -and $_.GetParameters().Count -eq 1 } |
    Select-Object -First 1
  if ($null -eq $getService) { throw "SavedQueryService.getService nao foi encontrado." }

  $service = $getService.Invoke($null, @($connection))
  if ($null -eq $service) { throw "SavedQueryService retornou NULL." }

  $getQueries = $serviceType.GetMethods() |
    Where-Object { $_.Name -eq "GetSavedQueries" -and $_.GetParameters().Count -eq 0 } |
    Select-Object -First 1
  if ($null -eq $getQueries) { throw "SavedQueryService.GetSavedQueries nao foi encontrado." }

  $queries = $getQueries.Invoke($service, @())
  if ($null -eq $queries -or $null -eq $queries.Queries) {
    throw "GetSavedQueries nao retornou a lista de consultas."
  }

  $savedQuery = $queries.Queries |
    Where-Object { $_.Name -eq "Item_Name_or_ID" } |
    Select-Object -First 1

  if ($null -eq $savedQuery) {
    throw "A saved query 'Item_Name_or_ID' nao foi encontrada."
  }
  if ($null -eq $savedQuery.Query) {
    throw "A saved query 'Item_Name_or_ID' foi encontrada, mas o objeto Query esta vazio."
  }

  $execute = $serviceType.GetMethods() | Where-Object {
    if ($_.Name -ne "ExecuteSavedQueries" -or $_.GetParameters().Count -ne 1) {
      return $false
    }

    $type = $_.GetParameters()[0].ParameterType
    $type.IsArray -and $type.GetElementType().FullName -eq
    "Teamcenter.Services.Strong.Query._2008_06.SavedQuery.QueryInput"
  } | Select-Object -First 1

  if ($null -eq $execute) {
    throw "ExecuteSavedQueries da versao 2008_06 nao foi encontrado."
  }

  $inputType = $execute.GetParameters()[0].ParameterType.GetElementType()
  if ($null -eq $inputType) {
    throw "O tipo QueryInput aceito por ExecuteSavedQueries nao foi identificado."
  }

  $input = [System.Activator]::CreateInstance($inputType)
  if ($null -eq $input) { throw "Nao foi possivel criar QueryInput." }

  $input.Query = $savedQuery.Query
  $input.Entries = [string[]]@("Item ID")
  $input.Values = [string[]]@($itemCodeClean)
  $input.MaxNumToReturn = 50
  $input.LimitList = $null
  $input.ClientId = "DcaExistingItemLookup"
  $input.RequestId = "DcaExistingItemLookup_$([guid]::NewGuid().ToString('N'))"

  $inputArray = [System.Array]::CreateInstance($inputType, 1)
  $inputArray.SetValue($input, 0)

  if ($Details) {
    Write-Host "  Executando saved query Item_Name_or_ID:" -ForegroundColor Cyan
    Write-Host "    Campo: Item ID" -ForegroundColor DarkGray
    Write-Host "    Valor: '$itemCodeClean'" -ForegroundColor DarkGray
  }

  try {
    $response = $execute.Invoke($service, [object[]]@(,$inputArray))
  }
  catch {
    $rootError = Get-DcaTeamcenterRootException $_.Exception
    throw "Falha ao executar Item_Name_or_ID para '$itemCodeClean': $($rootError.Message)"
  }

  $objectUids = @(
    if ($null -ne $response -and $null -ne $response.ArrayOfResults) {
      $response.ArrayOfResults.ObjectUIDS |
        ForEach-Object { ([string]$_).Trim() } |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
        Sort-Object -Unique
    }
  )

  if ($Details) {
    Write-Host "  UIDs retornados pela saved query: $($objectUids.Count)" -ForegroundColor DarkGray
  }
  if ($objectUids.Count -eq 0) { return @() }

  $dataService = Get-TeamcenterDataManagementService
  $getProperties = Get-DcaTeamcenterObjectMethod -Object $dataService -Name "GetProperties" -ParameterCount 2
  $loadObjects = Get-DcaTeamcenterObjectMethod -Object $dataService -Name "LoadObjects" -ParameterCount 1

  if ($null -eq $getProperties) {
    throw "DataManagementService.GetProperties nao foi encontrado."
  }
  if ($null -eq $loadObjects) {
    throw "DataManagementService.LoadObjects nao foi encontrado."
  }

  $modelArrayType = $getProperties.GetParameters()[0].ParameterType
  if (-not $modelArrayType.IsArray) {
    throw "O primeiro parametro de GetProperties nao e um array."
  }

  $modelType = $modelArrayType.GetElementType()
  if ($null -eq $modelType) {
    throw "O tipo de objeto de GetProperties nao foi identificado."
  }

  $matches = [System.Collections.Generic.List[object]]::new()
  $plainObjectMethod = $null

  foreach ($objectUid in $objectUids) {
    $serviceData = $loadObjects.Invoke(
      $dataService,
      [object[]]@(,[string[]]@([string]$objectUid))
    )
    if ($null -eq $serviceData) { continue }

    if ($null -eq $plainObjectMethod) {
      $plainObjectMethod = Get-DcaTeamcenterObjectMethod `
        -Object $serviceData -Name "GetPlainObject" -ParameterCount 1

      if ($null -eq $plainObjectMethod) {
        throw "ServiceData.GetPlainObject nao foi encontrado."
      }
    }

    $item = Get-DcaTeamcenterBaseObject (
      $plainObjectMethod.Invoke($serviceData, @([int]0))
    )
    if ($null -eq $item) { continue }

    try {
      $objects = [System.Array]::CreateInstance($modelType, 1)
      $objects.SetValue($item, 0)
      $null = $getProperties.Invoke(
        $dataService,
        [object[]]@($objects, [string[]]@("item_id", "object_name"))
      )
    }
    catch {
      if ($Details) {
        $rootException = Get-DcaTeamcenterRootException $_.Exception
        Write-Warn "Nao foi possivel carregar as propriedades do objeto '$objectUid': $($rootException.Message)"
      }
    }

    $foundCode = Get-TeamcenterModelPropertyText -ModelObject $item -PropertyName "item_id"
    $foundName = Get-TeamcenterModelPropertyText -ModelObject $item -PropertyName "object_name"

    if ($Details) {
      Write-Host "  Objeto retornado pela saved query:" -ForegroundColor DarkGray
      Write-Host "    UID:  $objectUid" -ForegroundColor DarkGray
      Write-Host "    Tipo: $($item.GetType().FullName)" -ForegroundColor DarkGray
      Write-Host "    Nome: '$foundName'" -ForegroundColor DarkGray
    }

    if ($foundCode -ieq $itemCodeClean) {
      $matches.Add([PSCustomObject]@{
          ItemCode = [string]$foundCode
          ItemName = [string]$foundName
          ItemType = $item.GetType().Name
          ObjectUid = [string]$objectUid
          Item = $item
        })
    }
    elseif ($Details) {
      Write-Warn "O objeto foi descartado porque o item_id '$foundCode' difere de '$itemCodeClean'."
    }
  }

  return $matches.ToArray()
}

# Converte os Items da Saved Query em destinos com revisao identificada.
function Get-DcaTeamcenterRevisionCandidates {
  param(
    [Parameter(Mandatory)]
    [object[]]$Candidates,

    [Parameter(Mandatory)]
    $GetRevisionMethod
  )

  $results = [System.Collections.Generic.List[object]]::new()

  foreach ($candidate in $Candidates) {
    if ($null -eq $candidate.Item) {
      continue
    }

    try {
      $revision = Get-DcaTeamcenterBaseObject (
        $GetRevisionMethod.Invoke(
          $null,
          @($candidate.Item)
        )
      )

      if ($null -eq $revision) {
        if ($Details) {
          Write-Warn (
            "Nenhuma revisao foi retornada para " +
            "'$($candidate.ItemCode)' com UID " +
            "'$($candidate.ObjectUid)'."
          )
        }

        continue
      }

      Update-DcaTeamcenterObjectProperties `
        -ModelObject $revision `
        -PropertyNames @(
        "item_revision_id",
        "object_name"
      )

      $revisionId = Get-TeamcenterModelPropertyText `
        -ModelObject $revision `
        -PropertyName "item_revision_id"

      $results.Add(
        [PSCustomObject]@{
          ItemCode = [string]$candidate.ItemCode
          ItemName = [string]$candidate.ItemName
          ItemType = [string]$candidate.ItemType
          ObjectUid = [string]$candidate.ObjectUid
          RevisionId = ([string]$revisionId).Trim().ToUpperInvariant()
          Item = $candidate.Item
          Revision = $revision
        }
      )
    }
    catch {
      if ($Details) {
        $rootException = Get-DcaTeamcenterRootException $_.Exception

        Write-Warn (
          "Nao foi possivel recuperar a revisao do candidato " +
          "'$($candidate.ObjectUid)': $($rootException.Message)"
        )
      }
    }
  }

  return $results.ToArray()
}

# Exibe os destinos encontrados e solicita a selecao quando necessario.
function Select-DcaTeamcenterRevisionCandidate {
  param(
    [Parameter(Mandatory)]
    [object[]]$Candidates,

    [Parameter(Mandatory)]
    [string]$ItemCode,

    [Parameter(Mandatory)]
    [string]$ExpectedRevision
  )

  $matching = @(
    $Candidates |
      Where-Object {
      $_.RevisionId -ieq $ExpectedRevision
    }
  )

  if ($Candidates.Count -eq 1 -and $matching.Count -eq 1) {
    $selected = $matching[0]

    Write-Success (
      "Destino localizado pela saved query: " +
      "$($selected.ItemCode)/$($selected.RevisionId) | " +
      "$($selected.ItemName)"
    )

    return $selected
  }

  Write-AnimatedLine ""
  Write-Host (
    "  Foram encontrados varios destinos com o codigo " +
    "'$ItemCode':"
  ) -ForegroundColor Cyan
  Write-Host ""

  for ($index = 0; $index -lt $Candidates.Count; $index++) {
    $candidate = $Candidates[$index]

    $name = ([string]$candidate.ItemName).Trim()
    if ([string]::IsNullOrWhiteSpace($name)) {
      $name = "nome nao informado"
    }

    $revision = ([string]$candidate.RevisionId).Trim()
    if ([string]::IsNullOrWhiteSpace($revision)) {
      $revision = "nao identificada"
    }

    $isExpected = $revision -ieq $ExpectedRevision
    $color = if ($isExpected) {
      [System.ConsoleColor]::Green
    }
    else {
      [System.ConsoleColor]::Gray
    }

    $suffix = if ($isExpected) {
      "  <- revisao esperada"
    }
    else {
      ""
    }

    Write-Host (
      "  [{0}] {1} | {2} | revisao {3} | {4}{5}" -f
      ($index + 1),
      $candidate.ItemCode,
      $name,
      $revision,
      $candidate.ItemType,
      $suffix
    ) -ForegroundColor $color

    if ($Details) {
      Write-Host (
        "      UID: $($candidate.ObjectUid)"
      ) -ForegroundColor DarkGray
    }
  }

  Write-Host ""

  $suggestedNumber = $null

  if ($matching.Count -eq 1) {
    for ($index = 0; $index -lt $Candidates.Count; $index++) {
      if ($Candidates[$index].ObjectUid -eq $matching[0].ObjectUid) {
        $suggestedNumber = $index + 1
        break
      }
    }
  }

  while ($true) {
    $prompt = if ($null -ne $suggestedNumber) {
      "Digite o numero do destino ou pressione Enter para usar [$suggestedNumber]"
    }
    else {
      "Digite o numero do destino"
    }

    $text = Read-Host $prompt

    if (
      [string]::IsNullOrWhiteSpace($text) -and
      $null -ne $suggestedNumber
    ) {
      return $Candidates[$suggestedNumber - 1]
    }

    $number = 0
    $validNumber = [System.Int32]::TryParse(
      $text,
      [ref]$number
    )

    if (
      -not $validNumber -or
      $number -lt 1 -or
      $number -gt $Candidates.Count
    ) {
      Write-Warn (
        "Destino invalido. Digite um numero entre 1 e " +
        "$($Candidates.Count)."
      )

      continue
    }

    return $Candidates[$number - 1]
  }
}

# Localiza o Item e valida se a revisao corresponde ao documento.
function Find-DcaTeamcenterItemRevision {
  param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$ItemCode,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$ExpectedRevision
  )

  if ($null -eq $script:TeamcenterFunctions) {
    throw "As funcoes do Teamcenter nao foram carregadas. Execute Connect-Teamcenter primeiro."
  }

  $itemCodeClean = $ItemCode.Trim().ToUpperInvariant()
  $expectedClean = $ExpectedRevision.Trim().ToUpperInvariant()
  $item = $null
  $revision = $null

  # 1. Load_Item
  $loadItem = Get-TeamcenterMethod -MethodName "Load_Item" -ParameterCount 1

  try {
    $revision = Get-DcaTeamcenterBaseObject (
      $loadItem.Invoke($null, @([string]$itemCodeClean))
    )
  }
  catch {
    if ($Details) {
      $rootError = Get-DcaTeamcenterRootException $_.Exception
      Write-Warn "Load_Item falhou para '$itemCodeClean': $($rootError.Message)"
    }
  }

  # 2. getItem com os valores de empresa.
  if ($null -eq $revision) {
    $getItem = Get-TeamcenterMethod -MethodName "getItem" -ParameterCount 2
    $getRevision = Get-TeamcenterMethod -MethodName "getItemRevisionfromItem" -ParameterCount 1

    $companies = @(
      ([string]$env:DCA_TC_DATASET_COMPANY).Trim()
      ([string]$env:DCA_TC_TEST_PROCESS_CLIENT_VALUE).Trim()
      ([string]$env:DCA_TC_TEST_ORIGINAL_CLIENT_VALUE).Trim()
      ([string]$env:DCA_TC_PROCESS_PROCESS_CLIENT_VALUE).Trim()
      ""
    ) | Select-Object -Unique

    foreach ($company in $companies) {
      $display = if ([string]::IsNullOrWhiteSpace($company)) { "(vazio)" } else { $company }

      if ($Details) {
        Write-Host "  Tentando getItem para '$itemCodeClean', empresa '$display'..." -ForegroundColor DarkGray
      }

      try {
        $item = Get-DcaTeamcenterBaseObject (
          $getItem.Invoke($null, @([string]$itemCodeClean, [string]$company))
        )

        if ($null -eq $item) {
          if ($Details) {
            Write-Host "  Nenhum Item retornado com empresa '$display'." -ForegroundColor DarkGray
          }
          continue
        }

        if ($Details) {
          Write-Host "  Item localizado com empresa '$display'." -ForegroundColor Green
        }

        $revision = Get-DcaTeamcenterBaseObject (
          $getRevision.Invoke($null, @($item))
        )

        if ($null -eq $revision) {
          if ($Details) {
            Write-Warn "O Item foi localizado com empresa '$display', mas nenhuma revisao foi retornada."
          }

          $item = $null
          continue
        }

        if ($Details) {
          Write-Host "  Revisao localizada com empresa '$display'." -ForegroundColor Green
        }

        break
      }
      catch {
        if ($Details) {
          $rootError = Get-DcaTeamcenterRootException $_.Exception
          Write-Warn "getItem falhou com empresa '$display': $($rootError.Message)"
        }

        $item = $null
        $revision = $null
      }
    }
  }

  # 3. Saved Query.
  if ($null -eq $revision) {
    try {
      $queryCandidates = @(Find-DcaTeamcenterItemBySavedQuery -ItemCode $itemCodeClean)

      if ($queryCandidates.Count -gt 0) {
        $getRevision = Get-TeamcenterMethod `
          -MethodName "getItemRevisionfromItem" `
          -ParameterCount 1

        $destinations = @(
          Get-DcaTeamcenterRevisionCandidates `
            -Candidates $queryCandidates `
            -GetRevisionMethod $getRevision
        )

        if ($destinations.Count -gt 0) {
          $selected = Select-DcaTeamcenterRevisionCandidate `
            -Candidates $destinations `
            -ItemCode $itemCodeClean `
            -ExpectedRevision $expectedClean

          if ($selected.RevisionId -ine $expectedClean) {
            throw "O destino selecionado possui revisao '$($selected.RevisionId)', mas o documento informa '$expectedClean'. A importacao foi bloqueada."
          }

          $item = $selected.Item
          $revision = $selected.Revision

          Write-Success "Destino selecionado: $($selected.ItemCode)/$($selected.RevisionId) | $($selected.ItemName)"
        }
      }
    }
    catch {
      $rootError = Get-DcaTeamcenterRootException $_.Exception

      if ($Details) {
        Write-Warn "Falha ao obter informacoes do destino pela saved query: $($rootError.Message)"
      }

      return New-DcaTeamcenterRevisionResult `
        -Status "Erro" `
        -ItemExists $false `
        -RevisionExists $false `
        -ItemCode $itemCodeClean `
        -ExpectedRevision $expectedClean `
        -ErrorMessage "Nenhuma revisao foi localizada pelas consultas diretas e a Saved Query falhou: $($rootError.Message)"
    }
  }

  # 4. Validar o objeto encontrado.
  if ($null -eq $revision) {
    return New-DcaTeamcenterRevisionResult `
      -Status "Nao" `
      -ItemExists ($null -ne $item) `
      -RevisionExists $false `
      -ItemCode $itemCodeClean `
      -ExpectedRevision $expectedClean `
      -Item $item `
      -ErrorMessage "Load_Item, getItem e a saved query Item_Name_or_ID nao localizaram uma revisao compativel para '$itemCodeClean/$expectedClean' no ambiente '$script:TeamcenterEnvironment'."
  }

  $revision = Get-DcaTeamcenterBaseObject $revision
  $revisionType = $revision.GetType().FullName

  if ($revisionType -notmatch '(?i)(ItemRevision|Revision)$') {
    return New-DcaTeamcenterRevisionResult `
      -Status "Erro" `
      -ItemExists $true `
      -RevisionExists $false `
      -ItemCode $itemCodeClean `
      -ExpectedRevision $expectedClean `
      -Item $item `
      -Revision $revision `
      -ErrorMessage "O destino selecionado nao retornou uma revisao valida. Tipo recebido: '$revisionType'."
  }

  # 5. Carregar e conferir item_revision_id.
  try {
    Update-DcaTeamcenterObjectProperties `
      -ModelObject $revision `
      -PropertyNames @("item_revision_id", "object_name", "object_string")

    if ($Details) {
      Write-Host "  Propriedades da revisao carregadas para validacao." -ForegroundColor DarkGray
    }
  }
  catch {
    $rootError = Get-DcaTeamcenterRootException $_.Exception

    return New-DcaTeamcenterRevisionResult `
      -Status "Erro" `
      -ItemExists $true `
      -RevisionExists $false `
      -ItemCode $itemCodeClean `
      -ExpectedRevision $expectedClean `
      -Item $item `
      -Revision $revision `
      -ErrorMessage "Nao foi possivel carregar item_revision_id da revisao: $($rootError.Message)"
  }

  $foundRevision = Get-TeamcenterModelPropertyText `
    -ModelObject $revision `
    -PropertyName "item_revision_id"

  $foundRevision = ([string]$foundRevision).Trim().ToUpperInvariant()

  if ([string]::IsNullOrWhiteSpace($foundRevision)) {
    return New-DcaTeamcenterRevisionResult `
      -Status "Erro" `
      -ItemExists $true `
      -RevisionExists $false `
      -ItemCode $itemCodeClean `
      -ExpectedRevision $expectedClean `
      -Item $item `
      -Revision $revision `
      -ErrorMessage "A revisao foi encontrada, mas nao foi possivel ler item_revision_id."
  }

  if ($foundRevision -ine $expectedClean) {
    return New-DcaTeamcenterRevisionResult `
      -Status "Revisao diferente" `
      -ItemExists $true `
      -RevisionExists $false `
      -ItemCode $itemCodeClean `
      -ExpectedRevision $expectedClean `
      -FoundRevision $foundRevision `
      -Item $item `
      -Revision $revision `
      -ErrorMessage "O destino selecionado possui revisao '$foundRevision', mas o documento informa '$expectedClean'."
  }

  return New-DcaTeamcenterRevisionResult `
    -Status "Sim" `
    -ItemExists $true `
    -RevisionExists $true `
    -ItemCode $itemCodeClean `
    -ExpectedRevision $expectedClean `
    -FoundRevision $foundRevision `
    -Item $item `
    -Revision $revision
}
