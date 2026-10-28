# ============================================================
# LOCALIZACAO DE ITEMS E REVISOES NO TEAMCENTER
# ============================================================
#
# Este arquivo localiza Items e revisoes existentes utilizados
# principalmente pelo fluxo DatasetOnly.
#
# Estrategias de consulta:
#   1. Load_Item para recuperar diretamente uma revisao;
#   2. getItem utilizando os valores de empresa configurados;
#   3. Saved Query Item_Name_or_ID quando as consultas anteriores
#      nao localizarem o destino;
#   4. selecao manual quando mais de um Item possuir o mesmo codigo.
#
# Antes de aceitar o destino, o fluxo valida:
#   1. o codigo do Item;
#   2. o tipo tecnico do objeto retornado;
#   3. o item_revision_id;
#   4. a correspondencia entre a revisao do PDF e a revisao
#      encontrada no Teamcenter.
#
# As funcoes deste arquivo nao criam Items, revisoes ou Datasets.
# ============================================================
function Test-DcaTeamcenterItemExists {

  # Verifica se o codigo informado possui uma revisao acessivel
  # pelo metodo Load_Item.
  #
  # Load_Item nao depende do filtro de empresa utilizado por getItem.
  # O resultado e armazenado em cache para impedir consultas repetidas
  # do mesmo codigo durante a execucao atual.
  param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$ItemCode
  )

  if ($null -eq $script:TeamcenterFunctions) {

    throw (
      "As funcoes do Teamcenter nao foram carregadas. " +
      "Execute Connect-Teamcenter primeiro."
    )
  }

  $itemCodeClean =
  $ItemCode.Trim().ToUpperInvariant()

  if (
    [string]::IsNullOrWhiteSpace(
      $itemCodeClean
    )
  ) {

    return [PSCustomObject]@{
      Status = "Erro"
      Exists = $false
      ItemCode = ""
      Item = $null
      Revision = $null
      ErrorMessage = "O codigo do Item ficou vazio."
    }
  }

  if (
    $null -ne $script:TeamcenterItemLookupCache -and
    $script:TeamcenterItemLookupCache.ContainsKey(
      $itemCodeClean
    )
  ) {

    return $script:TeamcenterItemLookupCache[
    $itemCodeClean
    ]
  }

  $loadItemMethod =
  Get-TeamcenterMethod `
    -MethodName "Load_Item" `
    -ParameterCount 1

  $result =
  $null

  try {

    if ($Details) {

      Write-Host (
        "  Consultando Item '$itemCodeClean'..."
      ) -ForegroundColor DarkGray
    }

    $revision =
    $loadItemMethod.Invoke(
      $null,
      @(
        [string]$itemCodeClean
      )
    )

    if ($null -ne $revision) {

      $revisionBaseObject =
      $revision.PSObject.BaseObject

      if ($null -ne $revisionBaseObject) {

        $revision =
        $revisionBaseObject
      }
    }

    if ($null -eq $revision) {

      $result =
      [PSCustomObject]@{
        Status = "Nao"
        Exists = $false
        ItemCode = $itemCodeClean
        Item = $null
        Revision = $null
        ErrorMessage = $null
      }
    }
    else {

      $revisionTypeName =
      $revision.GetType().FullName

      # O Teamcenter pode retornar revisoes especializadas, como:
      # Design_Revision, DocumentRevision e ItemRevision.
      $isRevisionObject =
      $revisionTypeName -match
      '(?i)(ItemRevision|Revision)$'

      if (-not $isRevisionObject) {

        $result =
        [PSCustomObject]@{
          Status = "Erro"
          Exists = $false
          ItemCode = $itemCodeClean
          Item = $null
          Revision = $revision
          ErrorMessage = (
            "Load_Item retornou um objeto que nao e revisao: " +
            "'$revisionTypeName'."
          )
        }
      }
      else {

        $result =
        [PSCustomObject]@{
          Status = "Sim"
          Exists = $true
          ItemCode = $itemCodeClean
          Item = $null
          Revision = $revision
          ErrorMessage = $null
        }
      }
    }
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

    $errorMessage =
    ([string]$realException.Message).Trim()

    if (
      $errorMessage -match
      "(?i)not found|nao encontrado|não encontrado|" +
      "does not exist|cannot find|unable to find"
    ) {

      $result =
      [PSCustomObject]@{
        Status = "Nao"
        Exists = $false
        ItemCode = $itemCodeClean
        Item = $null
        Revision = $null
        ErrorMessage = $null
      }
    }
    else {

      $result =
      [PSCustomObject]@{
        Status = "Erro"
        Exists = $false
        ItemCode = $itemCodeClean
        Item = $null
        Revision = $null
        ErrorMessage = $errorMessage
      }
    }
  }

  if (
    $null -ne $script:TeamcenterItemLookupCache -and
    $null -ne $result
  ) {

    $script:TeamcenterItemLookupCache[
    $itemCodeClean
    ] =
    $result
  }

  return $result
}
function Find-DcaTeamcenterItemBySavedQuery {

  # Executa a Saved Query Item_Name_or_ID para localizar todos
  # os Items que possuem o codigo informado.
  #
  # A consulta retorna UIDs. Cada UID e carregado pelo
  # DataManagementService e validado pela propriedade item_id.
  #
  # A funcao pode retornar mais de um Item porque ambientes
  # diferentes ou empresas diferentes podem possuir o mesmo codigo.
  param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$ItemCode
  )

  $itemCodeClean =
  $ItemCode.Trim().ToUpperInvariant()

  $connection =
  Get-TeamcenterConnection

  $queryAssembly =
  @(
    $script:TeamcenterQueryAssemblies |
      Where-Object {
      [System.IO.Path]::GetFileName(
        [string]$_.Location
      ) -ieq "TcSoaQueryStrong.dll"
    }
  ) |
    Select-Object -First 1

  if ($null -eq $queryAssembly) {

    throw (
      "TcSoaQueryStrong.dll nao esta carregada."
    )
  }

  $savedQueryServiceType =
  $queryAssembly.GetType(
    "Teamcenter.Services.Strong.Query.SavedQueryService",
    $false,
    $false
  )

  if ($null -eq $savedQueryServiceType) {

    throw (
      "O tipo SavedQueryService nao foi encontrado."
    )
  }

  $getServiceMethod =
  $savedQueryServiceType.GetMethods() |
    Where-Object {
    $_.Name -eq "getService" -and
    $_.GetParameters().Count -eq 1
  } |
    Select-Object -First 1

  if ($null -eq $getServiceMethod) {

    throw (
      "SavedQueryService.getService nao foi encontrado."
    )
  }

  $savedQueryService =
  $getServiceMethod.Invoke(
    $null,
    @($connection)
  )

  if ($null -eq $savedQueryService) {

    throw (
      "SavedQueryService retornou NULL."
    )
  }

  $getSavedQueriesMethod =
  $savedQueryServiceType.GetMethods() |
    Where-Object {
    $_.Name -eq "GetSavedQueries" -and
    $_.GetParameters().Count -eq 0
  } |
    Select-Object -First 1

  if ($null -eq $getSavedQueriesMethod) {

    throw (
      "SavedQueryService.GetSavedQueries nao foi encontrado."
    )
  }

  $savedQueriesResponse =
  $getSavedQueriesMethod.Invoke(
    $savedQueryService,
    @()
  )

  if (
    $null -eq $savedQueriesResponse -or
    $null -eq $savedQueriesResponse.Queries
  ) {

    throw (
      "GetSavedQueries nao retornou a lista de consultas."
    )
  }

  $savedQueryObject =
  $savedQueriesResponse.Queries |
    Where-Object {
    $_.Name -eq "Item_Name_or_ID"
  } |
    Select-Object -First 1

  if ($null -eq $savedQueryObject) {

    throw (
      "A saved query 'Item_Name_or_ID' nao foi encontrada."
    )
  }

  if ($null -eq $savedQueryObject.Query) {

    throw (
      "A saved query 'Item_Name_or_ID' foi encontrada, " +
      "mas o objeto Query esta vazio."
    )
  }

  $executeSavedQueriesMethod =
  $savedQueryServiceType.GetMethods() |
    Where-Object {

    if (
      $_.Name -ne "ExecuteSavedQueries" -or
      $_.GetParameters().Count -ne 1
    ) {
      return $false
    }

    $parameterType =
    $_.GetParameters()[0].ParameterType

    $parameterType.IsArray -and
    $parameterType.GetElementType().FullName -eq
    "Teamcenter.Services.Strong.Query._2008_06.SavedQuery.QueryInput"
  } |
    Select-Object -First 1

  if ($null -eq $executeSavedQueriesMethod) {

    throw (
      "ExecuteSavedQueries da versao 2008_06 " +
      "nao foi encontrado."
    )
  }

  $queryInputArrayType =
  $executeSavedQueriesMethod.GetParameters()[0].ParameterType

  $queryInputType =
  $queryInputArrayType.GetElementType()

  $queryInput =
  [System.Activator]::CreateInstance(
    $queryInputType
  )

  if ($null -eq $queryInput) {

    throw (
      "Nao foi possivel criar QueryInput."
    )
  }

  $queryInput.Query =
  $savedQueryObject.Query

  $queryInput.Entries =
  [string[]]@(
    "Item ID"
  )

  $querySearchValue =
  $itemCodeClean

  $queryInput.Values =
  [string[]]@(
    $querySearchValue
  )

  $queryInput.MaxNumToReturn =
  [int]50

  $queryInput.LimitList =
  $null

  $queryInput.ClientId =
  [string]"DcaExistingItemLookup"

  $queryInput.RequestId =
  [string](
    "DcaExistingItemLookup_" +
    [System.Guid]::NewGuid().ToString("N")
  )

  $queryInputArray =
  [System.Array]::CreateInstance(
    $queryInputType,
    1
  )

  $queryInputArray.SetValue(
    $queryInput,
    0
  )

  $executeArguments =
  New-Object "System.Object[]" 1

  $executeArguments[0] =
  $queryInputArray

  if ($Details) {

    Write-Host (
      "  Executando saved query Item_Name_or_ID:"
    ) -ForegroundColor Cyan

    Write-Host (
      "    Campo: Item ID"
    ) -ForegroundColor DarkGray

    Write-Host (
      "    Valor: '$querySearchValue'"
    ) -ForegroundColor DarkGray
  }

  $queryResponse =
  $null

  try {

    # As primeiras execucoes da Saved Query podem retornar
    # resultados incompletos. A ultima resposta sera utilizada.
    for (
      $queryAttempt = 1
      $queryAttempt -le 4
      $queryAttempt++
    ) {

      $queryResponse =
      $executeSavedQueriesMethod.Invoke(
        $savedQueryService,
        $executeArguments
      )

      $attemptUidCount =
      0

      if (
        $null -ne $queryResponse -and
        $null -ne $queryResponse.ArrayOfResults
      ) {

        $attemptUidCount =
        @(
          $queryResponse.ArrayOfResults |
            ForEach-Object {
            $_.ObjectUIDS
          } |
            Where-Object {
            -not [string]::IsNullOrWhiteSpace(
              [string]$_
            )
          } |
            Sort-Object -Unique
        ).Count
      }

      if ($Details) {

        Write-Host (
          "  Tentativa $queryAttempt da saved query: " +
          "$attemptUidCount UID(s)."
        ) -ForegroundColor DarkGray
      }

      if ($attemptUidCount -gt 0) {
        break
      }
    }
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
      "Falha ao executar Item_Name_or_ID para " +
      "'$itemCodeClean': " +
      $realException.Message
    )
  }

  if (
    $null -eq $queryResponse -or
    $null -eq $queryResponse.ArrayOfResults
  ) {

    return $null
  }

  $objectUids =
  @(
    foreach (
      $queryResult in
      @($queryResponse.ArrayOfResults)
    ) {

      if ($null -eq $queryResult) {
        continue
      }

      foreach (
        $objectUid in
        @($queryResult.ObjectUIDS)
      ) {

        $uidText =
        ([string]$objectUid).Trim()

        if (
          -not [string]::IsNullOrWhiteSpace(
            $uidText
          )
        ) {

          $uidText
        }
      }
    }
  ) |
    Sort-Object -Unique

  if ($Details) {

    Write-Host (
      "  UIDs retornados pela saved query: " +
      $objectUids.Count
    ) -ForegroundColor DarkGray
  }

  if ($objectUids.Count -eq 0) {

    return $null
  }

  $dataManagementService =
  Get-TeamcenterDataManagementService

  $matchingItems =
  [System.Collections.Generic.List[object]]::new()

  foreach ($objectUid in $objectUids) {

    $loadObjectsMethod =
    $dataManagementService.GetType().GetMethods() |
      Where-Object {
      $_.Name -match "^(?i)LoadObjects$" -and
      $_.GetParameters().Count -eq 1
    } |
      Select-Object -First 1

    if ($null -eq $loadObjectsMethod) {

      throw (
        "DataManagementService.LoadObjects nao foi encontrado."
      )
    }

    $uidArray =
    [string[]]@(
      [string]$objectUid
    )

    $loadArguments =
    New-Object "System.Object[]" 1

    $loadArguments[0] =
    $uidArray

    $serviceData =
    $loadObjectsMethod.Invoke(
      $dataManagementService,
      $loadArguments
    )

    if ($null -eq $serviceData) {
      continue
    }

    $plainObjectMethod =
    $serviceData.GetType().GetMethods() |
      Where-Object {
      $_.Name -match "^(?i)GetPlainObject$" -and
      $_.GetParameters().Count -eq 1
    } |
      Select-Object -First 1

    if ($null -eq $plainObjectMethod) {

      throw (
        "ServiceData.GetPlainObject nao foi encontrado."
      )
    }

    $plainObject =
    $plainObjectMethod.Invoke(
      $serviceData,
      @([int]0)
    )

    if ($null -eq $plainObject) {
      continue
    }

    $plainObjectBase =
    $plainObject.PSObject.BaseObject

    if ($null -ne $plainObjectBase) {

      $plainObject =
      $plainObjectBase
    }

    try {

      $getPropertiesMethod =
      $dataManagementService.GetType().GetMethods() |
        Where-Object {
        $_.Name -match "^(?i)GetProperties$" -and
        $_.GetParameters().Count -eq 2
      } |
        Select-Object -First 1

      if ($null -ne $getPropertiesMethod) {

        $modelObjectArrayType =
        $getPropertiesMethod.GetParameters()[0].ParameterType

        $modelObjectType =
        $modelObjectArrayType.GetElementType()

        $objectArray =
        [System.Array]::CreateInstance(
          $modelObjectType,
          1
        )

        $objectArray.SetValue(
          $plainObject,
          0
        )

        $propertyNames =
        [string[]]@(
          "item_id",
          "object_name"
        )

        $propertyArguments =
        New-Object "System.Object[]" 2

        $propertyArguments[0] =
        $objectArray

        $propertyArguments[1] =
        $propertyNames

        $null =
        $getPropertiesMethod.Invoke(
          $dataManagementService,
          $propertyArguments
        )
      }
    }
    catch {

      if ($Details) {

        Write-Warn (
          "Nao foi possivel carregar as propriedades " +
          "do objeto '$objectUid': " +
          $_.Exception.Message
        )
      }
    }

    $foundItemCode =
    Get-TeamcenterModelPropertyText `
      -ModelObject $plainObject `
      -PropertyName "item_id"

    $foundItemName =
    Get-TeamcenterModelPropertyText `
      -ModelObject $plainObject `
      -PropertyName "object_name"

    $itemTypeName =
    $plainObject.GetType().Name

    if ($Details) {

      Write-Host (
        "  Objeto retornado pela saved query:"
      ) -ForegroundColor DarkGray

      Write-Host (
        "    UID:  $objectUid"
      ) -ForegroundColor DarkGray

      Write-Host (
        "    Tipo: $($plainObject.GetType().FullName)"
      ) -ForegroundColor DarkGray

      Write-Host (
        "    Nome: '$foundItemName'"
      ) -ForegroundColor DarkGray
    }

    if ($foundItemCode -ieq $itemCodeClean) {

      $matchingItems.Add(
        [PSCustomObject]@{
          ItemCode = $foundItemCode
          ItemName = $foundItemName
          ItemType = $itemTypeName
          ObjectUid = [string]$objectUid
          Item = $plainObject
        }
      )

      continue
    }

    if ($Details) {

      Write-Warn (
        "O objeto retornado foi descartado porque o item_id " +
        "'$foundItemCode' e diferente do codigo esperado " +
        "'$itemCodeClean'."
      )
    }
  }

  if ($matchingItems.Count -eq 0) {

    return @()
  }

  return $matchingItems.ToArray()
}
function Find-DcaTeamcenterItemRevision {

  # Localiza o Item e a revisao esperada utilizando ate tres
  # estrategias de consulta:
  #
  #   1. Load_Item;
  #   2. getItem com os valores de empresa conhecidos;
  #   3. Saved Query Item_Name_or_ID.
  #
  # A revisao somente e aceita quando item_revision_id corresponde
  # exatamente a revisao informada pelo PDF.

  param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$ItemCode,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$ExpectedRevision
  )

  if ($null -eq $script:TeamcenterFunctions) {

    throw (
      "As funcoes do Teamcenter nao foram carregadas. " +
      "Execute Connect-Teamcenter primeiro."
    )
  }

  $itemCodeClean =
  $ItemCode.Trim().ToUpperInvariant()

  $expectedRevisionClean =
  $ExpectedRevision.Trim().ToUpperInvariant()

  $item =
  $null

  $revision =
  $null

  # ============================================================
  # 1. TENTAR A CONSULTA DIRETA COM LOAD_ITEM
  # ============================================================
  $loadItemMethod =
  Get-TeamcenterMethod `
    -MethodName "Load_Item" `
    -ParameterCount 1

  try {

    $revision =
    $loadItemMethod.Invoke(
      $null,
      @(
        [string]$itemCodeClean
      )
    )
  }
  catch {

    if ($Details) {

      $loadException =
      $_.Exception

      while (
        $null -ne $loadException.InnerException
      ) {

        $loadException =
        $loadException.InnerException
      }

      Write-Warn (
        "Load_Item falhou para '$itemCodeClean': " +
        $loadException.Message
      )
    }
  }

  if ($null -ne $revision) {

    $revisionBaseObject =
    $revision.PSObject.BaseObject

    if ($null -ne $revisionBaseObject) {

      $revision =
      $revisionBaseObject
    }
  }

  # ============================================================
  # 2. TENTAR GETITEM COM OS VALORES DE EMPRESA
  # ============================================================
  #
  # Cada valor de empresa e testado separadamente. Um valor vazio
  # tambem e incluido para ambientes que nao exigem esse filtro.
  if ($null -eq $revision) {

    $getItemMethod =
    Get-TeamcenterMethod `
      -MethodName "getItem" `
      -ParameterCount 2

    $getRevisionMethod =
    Get-TeamcenterMethod `
      -MethodName "getItemRevisionfromItem" `
      -ParameterCount 1

    $companyCandidates =
    @(
      ([string]$env:DCA_TC_DATASET_COMPANY).Trim(),
      ([string]$env:DCA_TC_TEST_PROCESS_CLIENT_VALUE).Trim(),
      ([string]$env:DCA_TC_TEST_ORIGINAL_CLIENT_VALUE).Trim(),
      ([string]$env:DCA_TC_PROCESS_PROCESS_CLIENT_VALUE).Trim(),
      ""
    ) |
      Select-Object -Unique

    foreach ($companyCandidate in $companyCandidates) {

      $companyDisplay =
      $companyCandidate

      if (
        [string]::IsNullOrWhiteSpace(
          $companyDisplay
        )
      ) {

        $companyDisplay =
        "(vazio)"
      }

      if ($Details) {

        Write-Host (
          "  Tentando getItem para '$itemCodeClean', " +
          "empresa '$companyDisplay'..."
        ) -ForegroundColor DarkGray
      }

      try {

        $item =
        $getItemMethod.Invoke(
          $null,
          @(
            [string]$itemCodeClean,
            [string]$companyCandidate
          )
        )

        if ($null -eq $item) {

          if ($Details) {

            Write-Host (
              "  Nenhum Item retornado com empresa " +
              "'$companyDisplay'."
            ) -ForegroundColor DarkGray
          }

          continue
        }

        $itemBaseObject =
        $item.PSObject.BaseObject

        if ($null -ne $itemBaseObject) {

          $item =
          $itemBaseObject
        }

        Write-Success (
          "Item localizado com empresa '$companyDisplay'."
        )

        $revision =
        $getRevisionMethod.Invoke(
          $null,
          @($item)
        )

        if ($null -eq $revision) {

          if ($Details) {

            Write-Warn (
              "O Item foi localizado com empresa " +
              "'$companyDisplay', mas nenhuma revisao foi retornada."
            )
          }

          $item =
          $null

          continue
        }

        $revisionBaseObject =
        $revision.PSObject.BaseObject

        if ($null -ne $revisionBaseObject) {

          $revision =
          $revisionBaseObject
        }

        if ($Details) {

          Write-Host (
            "  Revisao localizada com empresa " +
            "'$companyDisplay'."
          ) -ForegroundColor Green
        }

        break
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

        if ($Details) {

          Write-Warn (
            "getItem falhou com empresa " +
            "'$companyDisplay': " +
            $realException.Message
          )
        }

        $item =
        $null

        $revision =
        $null
      }
    }
  }

  # ============================================================
  # 3. TENTAR A SAVED QUERY ITEM_NAME_OR_ID
  # ============================================================
  #
  # A Saved Query pode localizar varios Items com o mesmo codigo.
  # Cada candidato tem sua revisao carregada e comparada com a
  # revisao esperada antes da selecao.

  if ($null -eq $revision) {

    try {

      $savedQueryCandidates =
      @(
        Find-DcaTeamcenterItemBySavedQuery `
          -ItemCode $itemCodeClean
      )

      if ($savedQueryCandidates.Count -gt 0) {

        $getRevisionMethod =
        Get-TeamcenterMethod `
          -MethodName "getItemRevisionfromItem" `
          -ParameterCount 1

        $destinationCandidates =
        [System.Collections.Generic.List[object]]::new()

        foreach ($savedQueryCandidate in $savedQueryCandidates) {

          $candidateItem =
          $savedQueryCandidate.Item

          if ($null -eq $candidateItem) {
            continue
          }

          try {

            $candidateRevision =
            $getRevisionMethod.Invoke(
              $null,
              @($candidateItem)
            )

            if ($null -eq $candidateRevision) {

              if ($Details) {

                Write-Warn (
                  "Nenhuma revisao foi retornada para o Item " +
                  "'$($savedQueryCandidate.ItemCode)' com UID " +
                  "'$($savedQueryCandidate.ObjectUid)'."
                )
              }

              continue
            }

            $candidateRevisionBaseObject =
            $candidateRevision.PSObject.BaseObject

            if ($null -ne $candidateRevisionBaseObject) {

              $candidateRevision =
              $candidateRevisionBaseObject
            }

            # Carrega explicitamente o ID da revisao antes da leitura.
            $dataManagementService =
            Get-TeamcenterDataManagementService

            $getPropertiesMethod =
            $dataManagementService.GetType().GetMethods() |
              Where-Object {
              $_.Name -match "^(?i)GetProperties$" -and
              $_.GetParameters().Count -eq 2
            } |
              Select-Object -First 1

            if ($null -eq $getPropertiesMethod) {

              throw (
                "DataManagementService.GetProperties nao foi encontrado."
              )
            }

            $revisionObjectArrayType =
            $getPropertiesMethod.GetParameters()[0].ParameterType

            if (-not $revisionObjectArrayType.IsArray) {

              throw (
                "O primeiro parametro de GetProperties nao e um array."
              )
            }

            $revisionObjectType =
            $revisionObjectArrayType.GetElementType()

            $revisionObjectArray =
            [System.Array]::CreateInstance(
              $revisionObjectType,
              1
            )

            $revisionObjectArray.SetValue(
              $candidateRevision,
              0
            )

            $revisionPropertyNames =
            [string[]]@(
              "item_revision_id",
              "object_name"
            )

            $getRevisionPropertiesArguments =
            New-Object "System.Object[]" 2

            $getRevisionPropertiesArguments[0] =
            $revisionObjectArray

            $getRevisionPropertiesArguments[1] =
            $revisionPropertyNames

            $revisionPropertyResponse =
            $getPropertiesMethod.Invoke(
              $dataManagementService,
              $getRevisionPropertiesArguments
            )

            if ($null -ne $revisionPropertyResponse) {

              $revisionPropertyErrors =
              @(
                Get-TeamcenterServiceErrors `
                  -ServiceData $revisionPropertyResponse
              )

              if ($revisionPropertyErrors.Count -gt 0) {

                throw (
                  "O Teamcenter nao carregou as propriedades da revisao: " +
                  ($revisionPropertyErrors -join " | ")
                )
              }
            }

            $candidateRevisionId =
            Get-TeamcenterModelPropertyText `
              -ModelObject $candidateRevision `
              -PropertyName "item_revision_id"

            $candidateRevisionId =
            ([string]$candidateRevisionId).Trim().ToUpperInvariant()

            $destinationCandidates.Add(
              [PSCustomObject]@{
                ItemCode = [string]$savedQueryCandidate.ItemCode
                ItemName = [string]$savedQueryCandidate.ItemName
                ItemType = [string]$savedQueryCandidate.ItemType
                ObjectUid = [string]$savedQueryCandidate.ObjectUid
                RevisionId = $candidateRevisionId
                Item = $candidateItem
                Revision = $candidateRevision
              }
            )
          }
          catch {

            $candidateException =
            $_.Exception

            while (
              $null -ne $candidateException.InnerException
            ) {

              $candidateException =
              $candidateException.InnerException
            }

            if ($Details) {

              Write-Warn (
                "Nao foi possivel recuperar a revisao do candidato " +
                "'$($savedQueryCandidate.ObjectUid)': " +
                $candidateException.Message
              )
            }
          }
        }

        if ($destinationCandidates.Count -gt 0) {

          $matchingRevisionCandidates =
          @(
            $destinationCandidates |
              Where-Object {
              $_.RevisionId -ieq $expectedRevisionClean
            }
          )

          $selectedDestination =
          $null

          # Se existe somente um Item e a revisao confere,
          # nao e necessario perguntar.
          if (
            $destinationCandidates.Count -eq 1 -and
            $matchingRevisionCandidates.Count -eq 1
          ) {

            $selectedDestination =
            $matchingRevisionCandidates[0]

            Write-Success (
              "Destino localizado pela saved query: " +
              "$($selectedDestination.ItemCode)/" +
              "$($selectedDestination.RevisionId) | " +
              "$($selectedDestination.ItemName)"
            )
          }
          else {

            Write-AnimatedLine ""

            Write-Host (
              "  Foram encontrados varios destinos com o codigo " +
              "'$itemCodeClean':"
            ) -ForegroundColor Cyan

            Write-Host ""

            for (
              $candidateIndex = 0
              $candidateIndex -lt $destinationCandidates.Count
              $candidateIndex++
            ) {

              $destinationCandidate =
              $destinationCandidates[$candidateIndex]

              $candidateNumber =
              $candidateIndex + 1

              $candidateName =
              [string]$destinationCandidate.ItemName

              if (
                [string]::IsNullOrWhiteSpace(
                  $candidateName
                )
              ) {

                $candidateName =
                "nome nao informado"
              }

              $candidateRevisionText =
              [string]$destinationCandidate.RevisionId

              if (
                [string]::IsNullOrWhiteSpace(
                  $candidateRevisionText
                )
              ) {

                $candidateRevisionText =
                "nao identificada"
              }

              $candidateColor =
              [System.ConsoleColor]::Gray

              $candidateSuffix =
              ""

              if (
                $candidateRevisionText -ieq
                $expectedRevisionClean
              ) {

                $candidateColor =
                [System.ConsoleColor]::Green

                $candidateSuffix =
                "  <- revisao do PDF"
              }

              Write-Host (
                "  [{0}] {1} | {2} | revisao {3} | {4}{5}" -f
                $candidateNumber,
                $destinationCandidate.ItemCode,
                $candidateName,
                $candidateRevisionText,
                $destinationCandidate.ItemType,
                $candidateSuffix
              ) -ForegroundColor $candidateColor

              if ($Details) {

                Write-Host (
                  "      UID: " +
                  $destinationCandidate.ObjectUid
                ) -ForegroundColor DarkGray
              }
            }

            Write-Host ""

            $suggestedCandidateNumber =
            $null

            if ($matchingRevisionCandidates.Count -eq 1) {

              for (
                $candidateIndex = 0
                $candidateIndex -lt $destinationCandidates.Count
                $candidateIndex++
              ) {

                if (
                  $destinationCandidates[$candidateIndex].ObjectUid -eq
                  $matchingRevisionCandidates[0].ObjectUid
                ) {

                  $suggestedCandidateNumber =
                  $candidateIndex + 1

                  break
                }
              }
            }

            while ($null -eq $selectedDestination) {

              $selectionPrompt =
              if ($null -ne $suggestedCandidateNumber) {

                "Digite o numero do destino ou pressione Enter " +
                "para usar [$suggestedCandidateNumber]"
              }
              else {

                "Digite o numero do destino"
              }

              $selectedDestinationText =
              Read-Host $selectionPrompt

              if (
                [string]::IsNullOrWhiteSpace(
                  $selectedDestinationText
                ) -and
                $null -ne $suggestedCandidateNumber
              ) {

                $selectedDestination =
                $destinationCandidates[
                $suggestedCandidateNumber - 1
                ]

                break
              }

              $selectedDestinationNumber =
              0

              $validDestinationNumber =
              [System.Int32]::TryParse(
                $selectedDestinationText,
                [ref]$selectedDestinationNumber
              )

              if (
                -not $validDestinationNumber -or
                $selectedDestinationNumber -lt 1 -or
                $selectedDestinationNumber -gt
                $destinationCandidates.Count
              ) {

                Write-Warn (
                  "Destino invalido. Digite um numero entre 1 e " +
                  "$($destinationCandidates.Count)."
                )

                continue
              }

              $selectedDestination =
              $destinationCandidates[
              $selectedDestinationNumber - 1
              ]
            }
          }

          if ($null -ne $selectedDestination) {

            if (
              $selectedDestination.RevisionId -ine
              $expectedRevisionClean
            ) {

              throw (
                "O destino selecionado possui revisao " +
                "'$($selectedDestination.RevisionId)', mas o PDF " +
                "informa a revisao '$expectedRevisionClean'. " +
                "A importacao foi bloqueada."
              )
            }

            $item =
            $selectedDestination.Item

            $revision =
            $selectedDestination.Revision

            Write-Success (
              "Destino selecionado: " +
              "$($selectedDestination.ItemCode)/" +
              "$($selectedDestination.RevisionId) | " +
              "$($selectedDestination.ItemName)"
            )
          }
        }
      }
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

      if ($Details) {

        Write-Warn (
          "Falha ao obter informacoes do destino pela saved query: " +
          $realException.Message
        )
      }

      return [PSCustomObject]@{
        Status = "Erro"
        ItemExists = $false
        RevisionExists = $false
        ItemCode = $itemCodeClean
        ExpectedRevision = $expectedRevisionClean
        FoundRevision = ""
        Item = $null
        Revision = $null
        ErrorMessage = (
          "Falha ao selecionar o destino pela saved query: " +
          $realException.Message
        )
      }
    }
  }

  # ============================================================
  # 4. VALIDAR O RESULTADO FINAL DA CONSULTA
  # ============================================================
  if ($null -eq $revision) {

    return [PSCustomObject]@{
      Status = "Nao"
      ItemExists = ($null -ne $item)
      RevisionExists = $false
      ItemCode = $itemCodeClean
      ExpectedRevision = $expectedRevisionClean
      FoundRevision = ""
      Item = $item
      Revision = $null
      ErrorMessage = (
        "Load_Item, getItem e a saved query Item_Name_or_ID " +
        "nao localizaram uma revisao compativel para " +
        "'$itemCodeClean/$expectedRevisionClean' no ambiente " +
        "'$script:TeamcenterEnvironment'."
      )
    }
  }

  $revisionBaseObject =
  $revision.PSObject.BaseObject

  if ($null -ne $revisionBaseObject) {

    $revision =
    $revisionBaseObject
  }

  $revisionTypeName =
  $revision.GetType().FullName

  $isRevisionObject =
  $revisionTypeName -match
  '(?i)(ItemRevision|Revision)$'

  if (-not $isRevisionObject) {

    return [PSCustomObject]@{
      Status = "Erro"
      ItemExists = $true
      RevisionExists = $false
      ItemCode = $itemCodeClean
      ExpectedRevision = $expectedRevisionClean
      FoundRevision = ""
      Item = $item
      Revision = $revision
      ErrorMessage = (
        "O destino selecionado nao retornou uma revisao valida. " +
        "Tipo recebido: '$revisionTypeName'."
      )
    }
  }

  # ============================================================
  # 5. CARREGAR AS PROPRIEDADES DA REVISAO
  # ============================================================
  #
  # Load_Item e getItemRevisionfromItem podem retornar o objeto
  # de revisao sem carregar item_revision_id no modelo cliente.
  # A propriedade deve ser solicitada explicitamente antes da
  # leitura e da comparacao com a revisao esperada.
  try {

    $dataManagementService =
    Get-TeamcenterDataManagementService

    $getPropertiesMethod =
    $dataManagementService.GetType().GetMethods() |
      Where-Object {
        $_.Name -match "^(?i)GetProperties$" -and
        $_.GetParameters().Count -eq 2
      } |
      Select-Object -First 1

    if ($null -eq $getPropertiesMethod) {

      throw (
        "DataManagementService.GetProperties nao foi encontrado."
      )
    }

    $revisionArrayType =
    $getPropertiesMethod.GetParameters()[0].ParameterType

    if (-not $revisionArrayType.IsArray) {

      throw (
        "O primeiro parametro de GetProperties nao e um array."
      )
    }

    $revisionObjectType =
    $revisionArrayType.GetElementType()

    if ($null -eq $revisionObjectType) {

      throw (
        "O tipo de objeto aceito por GetProperties nao foi " +
        "identificado."
      )
    }

    $revisionArray =
    [System.Array]::CreateInstance(
      $revisionObjectType,
      1
    )

    $revisionArray.SetValue(
      $revision,
      0
    )

    $revisionPropertyNames =
    [string[]]@(
      "item_revision_id",
      "object_name",
      "object_string"
    )

    $propertyArguments =
    New-Object "System.Object[]" 2

    $propertyArguments[0] =
    $revisionArray

    $propertyArguments[1] =
    $revisionPropertyNames

    $propertyResponse =
    $getPropertiesMethod.Invoke(
      $dataManagementService,
      $propertyArguments
    )

    if ($null -ne $propertyResponse) {

      $propertyErrors =
      @(
        Get-TeamcenterServiceErrors `
          -ServiceData $propertyResponse
      )

      if ($propertyErrors.Count -gt 0) {

        throw (
          "O Teamcenter nao carregou as propriedades da revisao: " +
          ($propertyErrors -join " | ")
        )
      }
    }

    if ($Details) {

      Write-Host (
        "  Propriedades da revisao carregadas para validacao."
      ) -ForegroundColor DarkGray
    }
  }
  catch {

    $propertyException =
    $_.Exception

    while (
      $null -ne $propertyException.InnerException
    ) {

      $propertyException =
      $propertyException.InnerException
    }

    return [PSCustomObject]@{
      Status = "Erro"
      ItemExists = $true
      RevisionExists = $false
      ItemCode = $itemCodeClean
      ExpectedRevision = $expectedRevisionClean
      FoundRevision = ""
      Item = $item
      Revision = $revision
      ErrorMessage = (
        "Nao foi possivel carregar item_revision_id da revisao: " +
        $propertyException.Message
      )
    }
  }

  $foundRevision =
  Get-TeamcenterModelPropertyText `
    -ModelObject $revision `
    -PropertyName "item_revision_id"

  $foundRevision =
  ([string]$foundRevision).Trim().ToUpperInvariant()

  if (
    [string]::IsNullOrWhiteSpace(
      $foundRevision
    )
  ) {

    return [PSCustomObject]@{
      Status = "Erro"
      ItemExists = $true
      RevisionExists = $false
      ItemCode = $itemCodeClean
      ExpectedRevision = $expectedRevisionClean
      FoundRevision = ""
      Item = $item
      Revision = $revision
      ErrorMessage = (
        "A revisao foi encontrada, mas nao foi possivel " +
        "ler item_revision_id."
      )
    }
  }

  if ($foundRevision -ine $expectedRevisionClean) {

    return [PSCustomObject]@{
      Status = "Revisao diferente"
      ItemExists = $true
      RevisionExists = $false
      ItemCode = $itemCodeClean
      ExpectedRevision = $expectedRevisionClean
      FoundRevision = $foundRevision
      Item = $item
      Revision = $revision
      ErrorMessage = (
        "O destino selecionado possui revisao " +
        "'$foundRevision', mas o PDF informa " +
        "'$expectedRevisionClean'."
      )
    }
  }

  return [PSCustomObject]@{
    Status = "Sim"
    ItemExists = $true
    RevisionExists = $true
    ItemCode = $itemCodeClean
    ExpectedRevision = $expectedRevisionClean
    FoundRevision = $foundRevision
    Item = $item
    Revision = $revision
    ErrorMessage = $null
  }
}
