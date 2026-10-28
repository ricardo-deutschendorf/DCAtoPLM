# ============================================================
# REVISAO DE DESTINO E IMPORTACAO DE DATASET
# ============================================================
#
# Este arquivo recupera uma revisao existente e importa um PDF
# como Dataset associado a essa revisao.
#
# Responsabilidades:
#   1. recuperar a revisao associada a um Item;
#   2. remover wrappers criados pelo PowerShell;
#   3. validar o tipo tecnico da revisao;
#   4. validar o caminho e a extensao do PDF;
#   5. normalizar o nome e a revisao do Dataset;
#   6. localizar o metodo ImportarPDF;
#   7. executar a importacao e retornar a resposta textual.
#
# Este arquivo nao cria Items ou revisoes e nao inicia workflows.
# ============================================================

# ============================================================
# RECUPERACAO DA REVISAO DE UM ITEM
# ============================================================
function Get-TeamcenterRevision {

  # Localiza a revisao associada ao Item informado utilizando
  # o metodo getItemRevisionfromItem do Importar GD.
  param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNull()]
    $Item
  )

  # ============================================================
  # 1. VALIDAR O ITEM E A CONEXAO
  # ============================================================

  if ($null -eq $Item) {

    throw (
      "O Item do Teamcenter nao foi fornecido."
    )
  }

  if ($null -eq $script:TeamcenterFunctions) {

    throw (
      "As funcoes do Teamcenter nao foram carregadas. " +
      "Execute Connect-Teamcenter primeiro."
    )
  }

  # ============================================================
  # 2. NORMALIZAR O OBJETO DO ITEM
  # ============================================================
  #
  # Quando o PowerShell encapsula o objeto retornado pela API,
  # PSObject.BaseObject recupera o objeto tecnico original.

  $itemBaseObject =
  $Item.PSObject.BaseObject

  if ($null -ne $itemBaseObject) {

    $Item =
    $itemBaseObject
  }

  # ============================================================
  # 3. LOCALIZAR O METODO DE CONSULTA DA REVISAO
  # ============================================================

  $getRevisionMethod =
  Get-TeamcenterMethod `
    -MethodName "getItemRevisionfromItem" `
    -ParameterCount 1

  # ============================================================
  # 4. RECUPERAR A REVISAO
  # ============================================================

  try {

    $revision =
    $getRevisionMethod.Invoke(
      $null,
      @($Item)
    )
  }
  catch {

    # Percorre as excecoes internas para apresentar a causa
    # original informada pelo Importar GD ou pelo Teamcenter.
    $realException =
    $_.Exception

    while (
      $null -ne $realException.InnerException
    ) {

      $realException =
      $realException.InnerException
    }

    throw (
      "Nao foi possivel recuperar a revisao do Item: " +
      $realException.Message
    )
  }

  if ($null -eq $revision) {

    return $null
  }

  # ============================================================
  # 5. NORMALIZAR E RETORNAR A REVISAO
  # ============================================================

  $revisionBaseObject =
  $revision.PSObject.BaseObject

  if ($null -ne $revisionBaseObject) {

    $revision =
    $revisionBaseObject
  }

  return $revision
}

# ============================================================
# DIAGNOSTICO DAS RELACOES DA REVISAO
# ============================================================
function Show-DcaTeamcenterRevisionDatasets {

  # Consulta as propriedades de relacao mais comuns de uma revisao
  # e apresenta os objetos secundarios encontrados.
  #
  # Esta funcao apenas le informacoes. Nenhum Dataset e criado,
  # alterado ou removido durante o diagnostico.
  param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNull()]
    $Revision
  )

  # ============================================================
  # 1. NORMALIZAR E VALIDAR A REVISAO
  # ============================================================

  $revisionBaseObject =
  $Revision.PSObject.BaseObject

  if ($null -ne $revisionBaseObject) {

    $Revision =
    $revisionBaseObject
  }

  if ($null -eq $Revision) {

    throw (
      "A revisao nao foi fornecida para o diagnostico " +
      "dos Datasets."
    )
  }

  $revisionTypeName =
  $Revision.GetType().FullName

  if (
    $revisionTypeName -notmatch
    '(?i)(ItemRevision|Revision)$'
  ) {

    throw (
      "O objeto recebido nao e uma revisao valida. " +
      "Tipo recebido: '$revisionTypeName'."
    )
  }

  # ============================================================
  # 2. OBTER O DATAMANAGEMENTSERVICE
  # ============================================================

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

  # ============================================================
  # 3. DEFINIR AS RELACOES QUE SERAO TESTADAS
  # ============================================================
  #
  # A relacao utilizada pelo Importar GD pode variar conforme o
  # modelo do Teamcenter. Por isso, esta etapa testa as relacoes
  # mais comuns sem assumir antecipadamente qual delas e usada.
  $relationPropertyNames =
  [string[]]@(
    "IMAN_specification",
    "IMAN_reference",
    "IMAN_Rendering",
    "IMAN_manifestation",
    "IMAN_requirement"
  )

  # ============================================================
  # 4. CARREGAR AS PROPRIEDADES DA REVISAO
  # ============================================================

  $revisionArrayType =
  $getPropertiesMethod.GetParameters()[0].ParameterType

  if (-not $revisionArrayType.IsArray) {

    throw (
      "O primeiro parametro de GetProperties nao e um array."
    )
  }

  $modelObjectType =
  $revisionArrayType.GetElementType()

  if ($null -eq $modelObjectType) {

    throw (
      "O tipo dos objetos de GetProperties nao foi identificado."
    )
  }

  $revisionArray =
  [System.Array]::CreateInstance(
    $modelObjectType,
    1
  )

  $revisionArray.SetValue(
    $Revision,
    0
  )

  $getPropertiesArguments =
  New-Object "System.Object[]" 2

  $getPropertiesArguments[0] =
  $revisionArray

  $getPropertiesArguments[1] =
  $relationPropertyNames

  $propertyResponse =
  $getPropertiesMethod.Invoke(
    $dataManagementService,
    $getPropertiesArguments
  )

  if ($null -ne $propertyResponse) {

    $propertyErrors =
    @(
      Get-TeamcenterServiceErrors `
        -ServiceData $propertyResponse
    )

    if ($propertyErrors.Count -gt 0) {

      Write-Warn (
        "Algumas propriedades nao puderam ser carregadas: " +
        ($propertyErrors -join " | ")
      )
    }
  }

  # ============================================================
  # 5. LOCALIZAR O METODO GETPROPERTY
  # ============================================================
  #
  # A versao atual do modelo cliente nao disponibiliza o metodo
  # GetPropertyObject. As propriedades carregadas pelo servico
  # sao recuperadas pelo metodo GetProperty.
  $getPropertyMethod =
  $Revision.GetType().GetMethods() |
    Where-Object {
    $_.Name -eq "GetProperty" -and
    $_.GetParameters().Count -eq 1 -and
    $_.GetParameters()[0].ParameterType -eq [string]
  } |
    Select-Object -First 1

  if ($null -eq $getPropertyMethod) {

    throw (
      "O metodo GetProperty(string) nao foi encontrado no objeto " +
      "de revisao '$revisionTypeName'."
    )
  }

  # ============================================================
  # 6. LER OS OBJETOS DE CADA RELACAO
  # ============================================================

  Write-AnimatedLine ""

  Write-Host (
    "  Diagnostico das relacoes da revisao:"
  ) -ForegroundColor Cyan

  Write-Host (
    "  Tipo da revisao: $revisionTypeName"
  ) -ForegroundColor DarkGray

  Write-Host ""

  $foundObjects =
  [System.Collections.Generic.List[object]]::new()

  foreach ($relationPropertyName in $relationPropertyNames) {

    Write-Host (
      "  Relacao: $relationPropertyName"
    ) -ForegroundColor White

    try {

      $propertyObject =
      $getPropertyMethod.Invoke(
        $Revision,
        @(
          [string]$relationPropertyName
        )
      )

      if ($null -eq $propertyObject) {

        Write-Host (
          "    Propriedade nao disponivel."
        ) -ForegroundColor DarkGray

        continue
      }

      # O objeto Property pode disponibilizar a colecao por uma
      # propriedade publica ou por um metodo getter, dependendo da
      # versao das bibliotecas SOA carregadas.
      $arrayValueProperty =
      $propertyObject.GetType().GetProperties() |
        Where-Object {
        $_.Name -match
        "^(?i)(ModelObjectArrayValue|ObjectArrayValue)$"
      } |
        Select-Object -First 1

      $relatedObjects =
      @()

      if ($null -ne $arrayValueProperty) {

        $relatedObjects =
        @(
          $arrayValueProperty.GetValue(
            $propertyObject,
            $null
          )
        )
      }
      else {

        $arrayValueMethod =
        $propertyObject.GetType().GetMethods() |
          Where-Object {
          $_.Name -match
          "^(?i)(get_|Get)(ModelObjectArrayValue|ObjectArrayValue)$" -and
          $_.GetParameters().Count -eq 0
        } |
          Select-Object -First 1

        if ($null -ne $arrayValueMethod) {

          $relatedObjects =
          @(
            $arrayValueMethod.Invoke(
              $propertyObject,
              @()
            )
          )
        }
        elseif ($Details) {

          Write-Host (
            "    O tipo da propriedade nao disponibiliza um " +
            "array de objetos relacionados."
          ) -ForegroundColor DarkGray

          Write-Host (
            "    Tipo da propriedade: " +
            $propertyObject.GetType().FullName
          ) -ForegroundColor DarkGray
        }
      }

      $relatedObjects =
      @(
        $relatedObjects |
          Where-Object {
          $null -ne $_
        }
      )

      if ($relatedObjects.Count -eq 0) {

        Write-Host (
          "    Nenhum objeto relacionado."
        ) -ForegroundColor DarkGray

        continue
      }

      Write-Host (
        "    Objetos encontrados: $($relatedObjects.Count)"
      ) -ForegroundColor Green

      # Carrega as propriedades utilizadas para identificar os
      # objetos relacionados e comparar os Datasets encontrados.
      try {

        $relatedObjectArray =
        [System.Array]::CreateInstance(
          $modelObjectType,
          $relatedObjects.Count
        )

        for (
          $relatedIndex = 0
          $relatedIndex -lt $relatedObjects.Count
          $relatedIndex++
        ) {

          $relatedObject =
          $relatedObjects[$relatedIndex]

          $relatedBaseObject =
          $relatedObject.PSObject.BaseObject

          if ($null -ne $relatedBaseObject) {

            $relatedObject =
            $relatedBaseObject
          }

          $relatedObjectArray.SetValue(
            $relatedObject,
            $relatedIndex
          )

          $relatedObjects[$relatedIndex] =
          $relatedObject
        }

        $relatedPropertyNames =
        [string[]]@(
          "object_name",
          "object_string",
          "object_type"
        )

        $relatedPropertyArguments =
        New-Object "System.Object[]" 2

        $relatedPropertyArguments[0] =
        $relatedObjectArray

        $relatedPropertyArguments[1] =
        $relatedPropertyNames

        $relatedPropertyResponse =
        $getPropertiesMethod.Invoke(
          $dataManagementService,
          $relatedPropertyArguments
        )

        if ($null -ne $relatedPropertyResponse) {

          $relatedPropertyErrors =
          @(
            Get-TeamcenterServiceErrors `
              -ServiceData $relatedPropertyResponse
          )

          if (
            $relatedPropertyErrors.Count -gt 0 -and
            $Details
          ) {

            Write-Warn (
              "Algumas propriedades dos objetos relacionados " +
              "nao foram carregadas: " +
              ($relatedPropertyErrors -join " | ")
            )
          }
        }
      }
      catch {

        if ($Details) {

          $relatedPropertyException =
          $_.Exception

          while (
            $null -ne $relatedPropertyException.InnerException
          ) {

            $relatedPropertyException =
            $relatedPropertyException.InnerException
          }

          Write-Warn (
            "Nao foi possivel carregar todas as propriedades " +
            "dos objetos relacionados: " +
            $relatedPropertyException.Message
          )
        }
      }

      foreach ($relatedObject in $relatedObjects) {

        $relatedBaseObject =
        $relatedObject.PSObject.BaseObject

        if ($null -ne $relatedBaseObject) {

          $relatedObject =
          $relatedBaseObject
        }

        $relatedTypeName =
        $relatedObject.GetType().FullName

        $relatedName =
        Get-TeamcenterModelPropertyText `
          -ModelObject $relatedObject `
          -PropertyName "object_name"

        $relatedId =
        Get-TeamcenterModelPropertyText `
          -ModelObject $relatedObject `
          -PropertyName "object_string"

        $relatedBusinessType =
        Get-TeamcenterModelPropertyText `
          -ModelObject $relatedObject `
          -PropertyName "object_type"

        Write-Host (
          "    Tipo tecnico: $relatedTypeName"
        ) -ForegroundColor Gray

        if (
          -not [string]::IsNullOrWhiteSpace(
            [string]$relatedBusinessType
          )
        ) {

          Write-Host (
            "    Tipo Teamcenter: '$relatedBusinessType'"
          ) -ForegroundColor Gray
        }

        Write-Host (
          "    Nome: '$relatedName'"
        ) -ForegroundColor Gray

        if (
          -not [string]::IsNullOrWhiteSpace(
            [string]$relatedId
          )
        ) {

          Write-Host (
            "    Identificacao: '$relatedId'"
          ) -ForegroundColor DarkGray
        }

        Write-Host ""

        $foundObjects.Add(
          [PSCustomObject]@{
            Relation = $relationPropertyName
            TypeName = $relatedTypeName
            BusinessType = [string]$relatedBusinessType
            ObjectName = [string]$relatedName
            ObjectString = [string]$relatedId
            Object = $relatedObject
          }
        )
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

      Write-Host (
        "    Nao foi possivel ler: " +
        $realException.Message
      ) -ForegroundColor DarkGray
    }
  }

  # ============================================================
  # 7. RETORNAR OS OBJETOS ENCONTRADOS
  # ============================================================

  return $foundObjects.ToArray()
}
# ============================================================
# VERIFICACAO DE DATASET EXISTENTE
# ============================================================
function Test-DcaTeamcenterDatasetExists {

  # Verifica se a revisao ja possui um Dataset com o nome
  # esperado antes de chamar o metodo ImportarPDF.
  #
  # A funcao apenas consulta os objetos relacionados. Nenhum
  # objeto do Teamcenter e criado ou alterado nesta etapa.
  param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNull()]
    $Revision,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$DatasetName,

    [string]$DatasetRevision
  )

  # ============================================================
  # 1. NORMALIZAR OS VALORES ESPERADOS
  # ============================================================

  $datasetNameClean =
  $DatasetName.Trim()

  $datasetRevisionClean =
  ([string]$DatasetRevision).Trim().ToUpperInvariant()

  if (
    [string]::IsNullOrWhiteSpace(
      $datasetNameClean
    )
  ) {

    throw (
      "O nome esperado do Dataset ficou vazio."
    )
  }

  # ============================================================
  # 2. CONSULTAR OS OBJETOS RELACIONADOS
  # ============================================================

  $relatedObjects =
  @(
    Show-DcaTeamcenterRevisionDatasets `
      -Revision $Revision
  )

  # ============================================================
  # 3. FILTRAR SOMENTE OBJETOS DE DATASET
  # ============================================================

  $datasetCandidates =
  @(
    $relatedObjects |
      Where-Object {

      $technicalType =
      [string]$_.TypeName

      $businessType =
      [string]$_.BusinessType

      (
        $technicalType -match
        '(?i)(Dataset|PDF)' -or
        $businessType -match
        '(?i)(Dataset|PDF)'
      )
    }
  )

  if ($Details) {

    Write-Host (
      "  Datasets encontrados na revisao: " +
      $datasetCandidates.Count
    ) -ForegroundColor DarkGray
  }

  # ============================================================
  # 4. COMPARAR O NOME DO DATASET
  # ============================================================

  foreach ($datasetCandidate in $datasetCandidates) {

    $foundDatasetName =
    ([string]$datasetCandidate.ObjectName).Trim()

    $foundObjectString =
    ([string]$datasetCandidate.ObjectString).Trim()

    if ($Details) {

      Write-Host (
        "  Comparando Dataset:"
      ) -ForegroundColor DarkGray

      Write-Host (
        "    Esperado: '$datasetNameClean'"
      ) -ForegroundColor DarkGray

      Write-Host (
        "    Encontrado: '$foundDatasetName'"
      ) -ForegroundColor DarkGray

      Write-Host (
        "    Relacao: '$($datasetCandidate.Relation)'"
      ) -ForegroundColor DarkGray
    }

    $datasetNameMatches =
    (
      $foundDatasetName -ieq $datasetNameClean -or
      $foundObjectString -ieq $datasetNameClean -or
      $foundObjectString -like "$datasetNameClean/*" -or
      $foundObjectString -like "$datasetNameClean *"
    )

    if (-not $datasetNameMatches) {
      continue
    }

    # ==========================================================
    # A. RETORNAR O DATASET ENCONTRADO
    # ==========================================================

    return [PSCustomObject]@{
      Exists = $true
      DatasetName = $foundDatasetName
      DatasetRevision = $datasetRevisionClean
      Relation = [string]$datasetCandidate.Relation
      TypeName = [string]$datasetCandidate.TypeName
      ObjectString = $foundObjectString
      Dataset = $datasetCandidate.Object
      ErrorMessage = $null
    }
  }

  # ============================================================
  # 5. INFORMAR QUE O DATASET NAO EXISTE
  # ============================================================

  return [PSCustomObject]@{
    Exists = $false
    DatasetName = $datasetNameClean
    DatasetRevision = $datasetRevisionClean
    Relation = $null
    TypeName = $null
    ObjectString = $null
    Dataset = $null
    ErrorMessage = $null
  }
}

# ============================================================
# IMPORTACAO DO PDF COMO DATASET
# ============================================================
function Import-TeamcenterPdf {

  # Valida os dados recebidos e chama o metodo ImportarPDF do
  # Importar GD para associar o PDF a revisao do Teamcenter.
  param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNull()]
    $Revision,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$ItemCode,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$DatasetName,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$DatasetRevision,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$FilePath
  )

  # ============================================================
  # 1. VALIDAR A REVISAO E O ARQUIVO PDF
  # ============================================================

  if ($null -eq $Revision) {

    throw (
      "A revisao do Item '$ItemCode' nao foi fornecida."
    )
  }

  if (-not (
      Test-Path `
        -LiteralPath $FilePath `
        -PathType Leaf
    )) {

    throw (
      "PDF nao encontrado em '$FilePath'."
    )
  }

  if (
    [System.IO.Path]::GetExtension(
      $FilePath
    ) -ine ".pdf"
  ) {

    throw (
      "O arquivo informado nao possui extensao PDF."
    )
  }

  # ============================================================
  # 2. NORMALIZAR O OBJETO DE REVISAO
  # ============================================================
  #
  # Remove o wrapper criado pelo PowerShell quando o objeto
  # original retornado pela API estiver disponivel.

  $revisionBaseObject =
  $Revision.PSObject.BaseObject

  if ($null -ne $revisionBaseObject) {

    $Revision =
    $revisionBaseObject
  }

  # ============================================================
  # 3. VALIDAR O TIPO TECNICO DA REVISAO
  # ============================================================
  #
  # O Teamcenter pode retornar revisoes especializadas. Por isso,
  # a validacao aceita tipos que terminem com ItemRevision ou
  # Revision.

  $revisionTypeName =
  $Revision.GetType().FullName

  $isRevisionObject =
  $revisionTypeName -match
  '(?i)(ItemRevision|Revision)$'

  if (-not $isRevisionObject) {

    throw (
      "A revisao recebida nao e um objeto de revisao valido. " +
      "Tipo recebido: '$revisionTypeName'."
    )
  }

  # ============================================================
  # 4. NORMALIZAR OS DADOS DO DATASET
  # ============================================================

  $datasetId =
  $DatasetName.Trim()

  $datasetRevisionClean =
  $DatasetRevision.Trim().ToUpperInvariant()

  if (
    [string]::IsNullOrWhiteSpace(
      $datasetId
    )
  ) {

    throw (
      "O nome do Dataset ficou vazio para '$ItemCode'."
    )
  }

  if (
    [string]::IsNullOrWhiteSpace(
      $datasetRevisionClean
    )
  ) {

    throw (
      "A revisao do Dataset ficou vazia para '$ItemCode'."
    )
  }

  # ============================================================
  # 5. LOCALIZAR O METODO IMPORTARPDF
  # ============================================================
  #
  # O metodo esperado recebe cinco parametros:
  #   1. identificador do Dataset;
  #   2. revisao do Dataset;
  #   3. caminho local do PDF;
  #   4. objeto de revisao;
  #   5. indicador booleano exigido pelo importador.

  $importMethod =
  Get-TeamcenterMethod `
    -MethodName "ImportarPDF" `
    -ParameterCount 5

  # ============================================================
  # 6. PREPARAR OS ARGUMENTOS DA IMPORTACAO
  # ============================================================

  $invokeArguments =
  New-Object "System.Object[]" 5

  $invokeArguments[0] =
  [string]$datasetId

  $invokeArguments[1] =
  [string]$datasetRevisionClean

  $invokeArguments[2] =
  [string]$FilePath

  $invokeArguments[3] =
  $Revision

  $invokeArguments[4] =
  [bool]$true

  # ============================================================
  # 7. APRESENTAR O DIAGNOSTICO DA IMPORTACAO
  # ============================================================

  if ($Details) {

    Write-Host (
      "  Dados enviados ao ImportarPDF:"
    ) -ForegroundColor Cyan

    Write-Host (
      "    Dataset ID:       '$datasetId'"
    ) -ForegroundColor Gray

    Write-Host (
      "    Dataset Revision: '$datasetRevisionClean'"
    ) -ForegroundColor Gray

    Write-Host (
      "    Arquivo:          '$FilePath'"
    ) -ForegroundColor Gray

    Write-Host (
      "    Tipo da revisao:  '$revisionTypeName'"
    ) -ForegroundColor Gray
  }

  # ============================================================
  # 8. IMPORTAR O PDF
  # ============================================================
  #
  # A chamada abaixo pode criar efetivamente o Dataset e associar
  # o PDF a revisao recebida. Todas as validacoes locais ocorrem
  # antes deste ponto.

  try {

    $importResult =
    $importMethod.Invoke(
      $null,
      $invokeArguments
    )
  }
  catch {

    # Percorre as excecoes internas para apresentar a mensagem
    # original retornada pelo Importar GD ou pelo Teamcenter.
    $realException =
    $_.Exception

    while (
      $null -ne $realException.InnerException
    ) {

      $realException =
      $realException.InnerException
    }

    throw (
      "Falha ao importar o PDF para '$ItemCode': " +
      $realException.Message
    )
  }

  # ============================================================
  # 9. RETORNAR A RESPOSTA DO IMPORTADOR
  # ============================================================

  return $importResult
}
