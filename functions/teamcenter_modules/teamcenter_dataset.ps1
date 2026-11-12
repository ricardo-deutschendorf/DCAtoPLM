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
    $Revision,

    [string[]]$RelationNames
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
    $_.Name -ieq "GetProperties" -and
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

  if ($null -ne $RelationNames -and $RelationNames.Count -gt 0) {

    $relationPropertyNames =
    [string[]]$RelationNames
  }

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
  [object[]]::new(2)

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

  if ($Details) {

    Write-AnimatedLine ""

    Write-Host (
      "  Diagnostico das relacoes da revisao:"
    ) -ForegroundColor Cyan

    Write-Host (
      "  Tipo da revisao: $revisionTypeName"
    ) -ForegroundColor DarkGray

    Write-Host ""
  }

  $foundObjects =
  [System.Collections.Generic.List[object]]::new()

  foreach ($relationPropertyName in $relationPropertyNames) {

    if ($Details) {

      Write-Host (
        "  Relacao: $relationPropertyName"
      ) -ForegroundColor White
    }

    try {

      $propertyObject =
      $getPropertyMethod.Invoke(
        $Revision,
        @(
          [string]$relationPropertyName
        )
      )

      if ($null -eq $propertyObject) {

        if ($Details) {

          Write-Host (
            "    Propriedade nao disponivel."
          ) -ForegroundColor DarkGray
        }

        continue
      }

      # O objeto Property pode disponibilizar a colecao por uma
      # propriedade publica ou por um metodo getter, dependendo da
      # versao das bibliotecas SOA carregadas.
      $arrayValueProperty =
      $propertyObject.GetType().GetProperties() |
        Where-Object {
        $_.Name -match
        "(?i)^(ModelObjectArrayValue|ObjectArrayValue)$"
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
          "(?i)^(get_|Get)(ModelObjectArrayValue|ObjectArrayValue)$" -and
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

        if ($Details) {

          Write-Host (
            "    Nenhum objeto relacionado."
          ) -ForegroundColor DarkGray
        }

        continue
      }

      if ($Details) {

        Write-Host (
          "    Objetos encontrados: $($relatedObjects.Count)"
        ) -ForegroundColor Green
      }

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
        [object[]]::new(2)

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

        if ($Details) {

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
        }

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

      if ($Details) {

        Write-Host (
          "    Nao foi possivel ler: " +
          $realException.Message
        ) -ForegroundColor DarkGray
      }
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
  # 4. COMPARAR A IDENTIFICACAO DO DATASET
  # ============================================================
  #
  # A versao atual identifica o Dataset pelo nome e pelo texto de
  # object_string. DatasetRevision permanece registrada no retorno,
  # mas ainda nao participa da comparacao.

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

  if ($Details) {

    Write-Host (
      "  Diagnostico inicial de Import-TeamcenterPdf:"
    ) -ForegroundColor Cyan

    Write-Host (
      "    ItemCode: '$ItemCode'"
    ) -ForegroundColor DarkGray

    Write-Host (
      "    DatasetName: '$DatasetName'"
    ) -ForegroundColor DarkGray

    Write-Host (
      "    DatasetRevision: '$DatasetRevision'"
    ) -ForegroundColor DarkGray

    Write-Host (
      "    FilePath: '$FilePath'"
    ) -ForegroundColor DarkGray

    Write-Host (
      "    Tipo de FilePath: " +
      $FilePath.GetType().FullName
    ) -ForegroundColor DarkGray

    Write-Host (
      "    Comprimento de FilePath: " +
      $FilePath.Length
    ) -ForegroundColor DarkGray
  }

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

  $pdfFile =
  Get-Item `
    -LiteralPath $FilePath `
    -ErrorAction Stop

  if ($pdfFile.Extension -ine ".pdf") {

    throw (
      "O arquivo informado nao possui extensao PDF: " +
      "'$FilePath'."
    )
  }

  if ($pdfFile.Length -le 0) {

    throw (
      "O PDF informado para '$ItemCode' esta vazio."
    )
  }

  $FilePath =
  $pdfFile.FullName

  $invalidPathCharacters =
  [System.IO.Path]::GetInvalidPathChars()

  if ($FilePath.IndexOfAny($invalidPathCharacters) -ge 0) {

    $pathCharacterCodes =
    @(
      $FilePath.ToCharArray() |
        ForEach-Object {
        [int][char]$_
      }
    ) -join ", "

    throw (
      "O caminho do PDF possui caracteres invalidos. " +
      "Caminho: '$FilePath'. " +
      "Codigos dos caracteres: $pathCharacterCodes"
    )
  }

  $pdfFile =
  Get-Item `
    -LiteralPath $FilePath `
    -ErrorAction Stop

  if ($pdfFile.Length -le 0) {

    throw (
      "O PDF informado para '$ItemCode' esta vazio."
    )
  }

  $FilePath =
  $pdfFile.FullName

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

  if ($Details) {

    Write-Host (
      "  Assinatura selecionada de ImportarPDF:"
    ) -ForegroundColor Cyan

    $importParameters =
    $importMethod.GetParameters()

    for (
      $parameterIndex = 0
      $parameterIndex -lt $importParameters.Count
      $parameterIndex++
    ) {

      $importParameter =
      $importParameters[$parameterIndex]

      Write-Host (
        "    [{0}] {1} {2}" -f
        $parameterIndex,
        $importParameter.ParameterType.FullName,
        $importParameter.Name
      ) -ForegroundColor DarkGray
    }

    Write-Host (
      "    Retorno: " +
      $importMethod.ReturnType.FullName
    ) -ForegroundColor DarkGray
  }

  # ============================================================
  # 6. PREPARAR OS ARGUMENTOS DA IMPORTACAO
  # ============================================================

  $invokeArguments =
  [object[]]::new(5)

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
  $importResultText =
  ([string]$importResult).Trim()

  if (
    [string]::IsNullOrWhiteSpace(
      $importResultText
    )
  ) {

    throw (
      "ImportarPDF nao retornou uma confirmacao para " +
      "'$ItemCode'."
    )
  }

  if (
    $importResultText -notmatch
    '^(?i:sim|true|1|yes)$'
  ) {

    throw (
      "ImportarPDF nao confirmou a importacao de '$ItemCode'. " +
      "Retorno recebido: '$importResultText'."
    )
  }

  # ============================================================
  # 9. RETORNAR A RESPOSTA DO IMPORTADOR
  # ============================================================

  return $importResultText
}
# ============================================================
# IMPORTACAO DO DESENHO SLDDRW DA FOLHA NDT
# ============================================================
# Importa o SLDDRW como Dataset (tipo, ferramenta e referencia
# vindos do .env) na revisao da folha NDT, usando ImportarOffice.
function Import-DcaNdtDrawing {
  param(
    [Parameter(Mandatory = $true)]
    $Revision,

    [Parameter(Mandatory = $true)]
    [string]$DatasetName,

    [Parameter(Mandatory = $true)]
    [string]$DatasetRevision,

    [Parameter(Mandatory = $true)]
    $DrawingEntry,

    [Parameter(Mandatory = $true)]
    [string]$TemporaryFolder
  )

  # 1. Configuracao obrigatoria do .env
  $datasetType = ([string]$env:DCA_TC_NDT_DRAWING_DATASET_TYPE).Trim()
  $toolUsed = ([string]$env:DCA_TC_NDT_DRAWING_TOOL).Trim()
  $reference = ([string]$env:DCA_TC_NDT_DRAWING_REFERENCE).Trim()

  foreach ($pair in @(
      @("DCA_TC_NDT_DRAWING_DATASET_TYPE", $datasetType),
      @("DCA_TC_NDT_DRAWING_TOOL", $toolUsed),
      @("DCA_TC_NDT_DRAWING_REFERENCE", $reference)
    )) {

    if ([string]::IsNullOrWhiteSpace([string]$pair[1])) {
      throw "$($pair[0]) nao esta configurado no .env."
    }
  }

  # 2. Garantir o SLDDRW localmente (download do Vault se preciso)
  $drawingSourcePath = ([string]$DrawingEntry.FullName).Trim()
  $drawingPath = $null

  if (Test-Path -LiteralPath $drawingSourcePath -PathType Leaf) {
    $drawingPath = $drawingSourcePath
  }
  else {

    Write-Info "Baixando o desenho NDT do Vault..."

    $vault = Get-DcaVault

    if ($null -eq $vault) {
      throw "Nao foi possivel obter a conexao com o Vault para baixar o desenho NDT."
    }

    $parentFolder = $null

    $pdmFile = $vault.GetFileFromPath(
      $drawingSourcePath,
      [ref]$parentFolder
    )

    if ($null -eq $pdmFile) {
      throw "O desenho NDT nao foi encontrado no Vault: '$drawingSourcePath'."
    }

    if ($null -eq $parentFolder) {
      throw "A pasta do desenho NDT nao foi encontrada no Vault."
    }

    $fileVersion = 0
    $folderId = $parentFolder.ID

    # Versao 0 baixa a versao mais recente do arquivo.
    $pdmFile.GetFileCopy(
      0,
      [ref]$fileVersion,
      [ref]$folderId,
      0,
      ""
    )

    $drawingPath = [string]$pdmFile.GetLocalPath($parentFolder.ID)

    if ($Details) {
      Write-Info "Desenho baixado na versao ${fileVersion}: $drawingPath"
    }
  }

  if (
    [string]::IsNullOrWhiteSpace($drawingPath) -or
    -not (Test-Path -LiteralPath $drawingPath -PathType Leaf)
  ) {
    throw "O desenho NDT nao ficou disponivel localmente: '$drawingSourcePath'."
  }

  # 3. Copia local com nome simples (sem espaco nem colchetes)
  $drawingExtension = [System.IO.Path]::GetExtension($drawingPath)
  $temporaryDrawingPath = Join-Path `
    -Path $TemporaryFolder `
    -ChildPath ($DatasetName + $drawingExtension)

  Copy-Item -LiteralPath $drawingPath -Destination $temporaryDrawingPath -Force

  $temporaryDrawingFile = Get-Item -LiteralPath $temporaryDrawingPath -ErrorAction Stop

  if ($temporaryDrawingFile.Length -le 0) {
    throw "A copia local do desenho NDT esta vazia: '$temporaryDrawingPath'."
  }

  # 4. Localizar ImportarGD.Controller.Functions.ImportarOffice
  $functionsType =
  [System.AppDomain]::CurrentDomain.GetAssemblies() |
    ForEach-Object {
    try { $_.GetTypes() } catch { @() }
  } |
    Where-Object { $_.FullName -eq "ImportarGD.Controller.Functions" } |
    Select-Object -First 1

  if ($null -eq $functionsType) {
    throw "O tipo ImportarGD.Controller.Functions nao foi encontrado."
  }

  $importMethod =
  $functionsType.GetMethods(
    [System.Reflection.BindingFlags]::Public -bor
    [System.Reflection.BindingFlags]::Static
  ) |
    Where-Object {
    $_.Name -eq "ImportarOffice" -and
    $_.GetParameters().Count -eq 7
  } |
    Select-Object -First 1

  if ($null -eq $importMethod) {
    throw "A sobrecarga ImportarOffice com 7 parametros nao foi encontrada."
  }

  $revisionObject = $Revision.PSObject.BaseObject
  if ($null -eq $revisionObject) { $revisionObject = $Revision }

  Write-Info "Importando o desenho NDT..."

  if ($Details) {
    Write-Host "  Dados enviados ao ImportarOffice:" -ForegroundColor Cyan
    Write-Host "    Dataset ID:       '$DatasetName'" -ForegroundColor DarkGray
    Write-Host "    Dataset Revision: '$DatasetRevision'" -ForegroundColor DarkGray
    Write-Host "    Arquivo:          '$temporaryDrawingPath'" -ForegroundColor DarkGray
    Write-Host "    Dataset Type:     '$datasetType'" -ForegroundColor DarkGray
    Write-Host "    ToolUsed:         '$toolUsed'" -ForegroundColor DarkGray
    Write-Host "    Reference:        '$reference'" -ForegroundColor DarkGray
  }

  # 5. Executar
  # Cada argumento e convertido explicitamente e atribuido por
  # posicao, para a reflexao nao receber wrappers PSObject.
  $invokeArguments = [object[]]::new(7)
  $invokeArguments[0] = [string]$DatasetName
  $invokeArguments[1] = [string]$DatasetRevision
  $invokeArguments[2] = [string]$temporaryDrawingFile.FullName
  $invokeArguments[3] = $revisionObject
  $invokeArguments[4] = [string]$datasetType
  $invokeArguments[5] = [string]$toolUsed
  $invokeArguments[6] = [string]$reference

  try {
    $importResult = $importMethod.Invoke(
      $null,
      $invokeArguments
    )
  }
  catch {
    $realException = $_.Exception
    while ($null -ne $realException.InnerException) {
      $realException = $realException.InnerException
    }
    throw "Falha no ImportarOffice para '$DatasetName': $($realException.Message)"
  }

  # O ImportarOffice pode exibir erro em janela e retornar normalmente.
  # Confirma que um Dataset diferente do PDF foi anexado a revisao.
  $relatedAfterImport = @(
    Show-DcaTeamcenterRevisionDatasets -Revision $revisionObject
  )

  $drawingDatasets = @(
    $relatedAfterImport |
      Where-Object {
      [string]$_.BusinessType -notmatch '(?i)^PDF$' -and
      [string]$_.TypeName -notmatch '(?i)\.PDF$'
    }
  )

  if ($drawingDatasets.Count -eq 0) {
    throw "O ImportarOffice nao anexou um Dataset de desenho para '$DatasetName'."
  }

  $importResultText = ([string]$importResult).Trim()

  if ($Details) {
    Write-Host "  Retorno do ImportarOffice: '$importResultText'"
  }

  # Sucesso real: "Sim" + espacos + "Dataset criado no Teamcenter".
  if ($importResultText -notmatch '(?i)^sim\b') {
    throw (
      "O ImportarOffice nao criou o Dataset de '$DatasetName'. " +
      "Retorno: '$importResultText'."
    )
  }

  return $importResultText
}

# ============================================================
# VINCULO DO DESENHO NDT A PASTA NDT DO DCA PROCESSO
# ============================================================

function Get-DcaModelObjectUid {
  param($ModelObject)

  if ($null -eq $ModelObject) { return "" }

  try { return ([string]$ModelObject.Uid).Trim() }
catch { return "" }
}

function Update-DcaModelObjectProperties {

  # Carrega propriedades de um objeto e devolve os erros do servico.
  param(
    [Parameter(Mandatory = $true)]
    $ModelObject,

    [Parameter(Mandatory = $true)]
    [string[]]$PropertyNames
  )

  $baseObject = $ModelObject.PSObject.BaseObject
  if ($null -ne $baseObject) { $ModelObject = $baseObject }

  $dataManagementService = Get-TeamcenterDataManagementService

  $getPropertiesMethod =
  $dataManagementService.GetType().GetMethods() |
    Where-Object {
    $_.Name -ieq "GetProperties" -and
    $_.GetParameters().Count -eq 2
  } |
    Select-Object -First 1

  if ($null -eq $getPropertiesMethod) {
    throw "DataManagementService.GetProperties nao foi encontrado."
  }

  $objectType =
  $getPropertiesMethod.GetParameters()[0].ParameterType.GetElementType()

  $objectArray = [System.Array]::CreateInstance($objectType, 1)
  $objectArray.SetValue($ModelObject, 0)

  $arguments = [object[]]::new(2)
  $arguments[0] = $objectArray
  $arguments[1] = [string[]]$PropertyNames

  $response = $getPropertiesMethod.Invoke($dataManagementService, $arguments)

  if ($null -eq $response) { return @() }

  return @(Get-TeamcenterServiceErrors -ServiceData $response)
}

function New-DcaTeamcenterRelation {

  # Cria uma relacao (GRM) entre dois objetos usando
  # DataManagementService.CreateRelations.
  param(
    [Parameter(Mandatory = $true)] $PrimaryObject,
    [Parameter(Mandatory = $true)] $SecondaryObject,
    [Parameter(Mandatory = $true)] [string]$RelationType
  )

  $primaryBase = $PrimaryObject.PSObject.BaseObject
  if ($null -ne $primaryBase) { $PrimaryObject = $primaryBase }

  $secondaryBase = $SecondaryObject.PSObject.BaseObject
  if ($null -ne $secondaryBase) { $SecondaryObject = $secondaryBase }

  $dataManagementService = Get-TeamcenterDataManagementService

  $createRelationsMethod =
  $dataManagementService.GetType().GetMethods() |
    Where-Object {

    if (
      $_.Name -ine "CreateRelations" -or
      $_.GetParameters().Count -ne 1
    ) {
      return $false
    }

    $parameterType = $_.GetParameters()[0].ParameterType

    $parameterType.IsArray -and
    $parameterType.GetElementType().Name -ieq "Relationship"
  } |
    Select-Object -First 1

  if ($null -eq $createRelationsMethod) {
    throw "DataManagementService.CreateRelations nao foi encontrado."
  }

  $relationshipType =
  $createRelationsMethod.GetParameters()[0].ParameterType.GetElementType()

  $relationship = [System.Activator]::CreateInstance($relationshipType)

  $memberValues = [ordered]@{
    PrimaryObject = $PrimaryObject
    SecondaryObject = $SecondaryObject
    RelationType = [string]$RelationType
    ClientId = [string]"DcaNdtPasta"
  }

  $memberFlags =
  [System.Reflection.BindingFlags]::Public -bor
  [System.Reflection.BindingFlags]::Instance -bor
  [System.Reflection.BindingFlags]::IgnoreCase

  $memberTypes =
  [System.Reflection.MemberTypes]::Property -bor
  [System.Reflection.MemberTypes]::Field

  foreach ($memberName in $memberValues.Keys) {

    $member =
    $relationshipType.GetMember($memberName, $memberTypes, $memberFlags) |
      Select-Object -First 1

    if ($null -eq $member) {
      throw (
        "O membro '$memberName' nao foi encontrado em " +
        "'$($relationshipType.FullName)'."
      )
    }

    if ($member -is [System.Reflection.PropertyInfo]) {
      $member.SetValue($relationship, $memberValues[$memberName], $null)
    }
    else {
      $member.SetValue($relationship, $memberValues[$memberName])
    }
  }

  $relationshipArray = [System.Array]::CreateInstance($relationshipType, 1)
  $relationshipArray.SetValue($relationship, 0)

  $arguments = [object[]]::new(1)
  $arguments[0] = $relationshipArray

  try {
    $response = $createRelationsMethod.Invoke(
      $dataManagementService,
      $arguments
    )
  }
  catch {
    $realException = $_.Exception
    while ($null -ne $realException.InnerException) {
      $realException = $realException.InnerException
    }
    throw "Falha ao criar a relacao '$RelationType': $($realException.Message)"
  }

  # A resposta pode ser o proprio ServiceData ou conter um.
  $serviceData = $response

  if ($null -ne $response) {

    $serviceDataProperty = $response.GetType().GetProperty("ServiceData")

    if ($null -ne $serviceDataProperty) {

      $nestedServiceData = $serviceDataProperty.GetValue($response, $null)

      if ($null -ne $nestedServiceData) { $serviceData = $nestedServiceData }
    }
  }

  if ($null -ne $serviceData) {

    $serviceErrors = @(Get-TeamcenterServiceErrors -ServiceData $serviceData)

    if ($serviceErrors.Count -gt 0) {
      throw (
        "O Teamcenter recusou a relacao '$RelationType': " +
        ($serviceErrors -join " | ")
      )
    }
  }
}

function Add-DcaNdtDrawingToProcessFolder {

  # Depois de importar o SLDDRW na Folha NDT, procura o DCA Processo de
  # mesmo codigo e relaciona o Dataset do desenho a Pasta NDT dele
  # (relacao GD5PastaNDT). Nao lanca excecao: problemas viram aviso.
  param(
    [Parameter(Mandatory = $true)]
    $NdtRevision,

    [Parameter(Mandatory = $true)]
    [string]$ProcessItemCode,

    [string]$RelationName = "GD5PastaNDT"
  )

  $processCode = ($ProcessItemCode.Trim() -replace '(?i)$', '')

  try {

    $ndtRevisionObject = $NdtRevision.PSObject.BaseObject
    if ($null -eq $ndtRevisionObject) { $ndtRevisionObject = $NdtRevision }

    # 1. Dataset do desenho na revisao da Folha NDT.
    $datasetType = ([string]$env:DCA_TC_NDT_DRAWING_DATASET_TYPE).Trim()

    $drawingDataset =
    @(
      Show-DcaTeamcenterRevisionDatasets -Revision $ndtRevisionObject |
        Where-Object { [string]$_.BusinessType -ieq $datasetType }
    ) |
      Select-Object -First 1

    if ($null -eq $drawingDataset) {
      throw (
        "O Dataset '$datasetType' nao foi encontrado na revisao " +
        "da Folha NDT."
      )
    }

    # 2. DCA Processo de mesmo codigo, escolhido pelo tipo do Item.
    if ($Details) {
      Write-Host (
        "  Procurando o DCA Processo '$processCode' para vincular " +
        "o desenho NDT..."
      ) -ForegroundColor Cyan
    }

    $processMatch =
    Find-DcaProcessRevisionByCode `
      -ItemCode $processCode

    if ($null -eq $processMatch -or $null -eq $processMatch.Revision) {

      Write-Warn (
        "Nenhum DCA Processo com o codigo '$processCode' foi " +
        "encontrado. O desenho NDT nao foi vinculado a uma Pasta NDT."
      )

      return [PSCustomObject]@{ Status = "ProcessoNaoEncontrado" }
    }

    $processRevision = $processMatch.Revision.PSObject.BaseObject
    if ($null -eq $processRevision) {
      $processRevision = $processMatch.Revision
    }

    # 3. Ler o ID da revisao do Processo para as mensagens.
    $null = @(
      Update-DcaModelObjectProperties `
        -ModelObject $processRevision `
        -PropertyNames @("item_revision_id")
    )

    $processRevisionId =
    ([string](
        Get-TeamcenterModelPropertyText `
          -ModelObject $processRevision `
          -PropertyName "item_revision_id"
      )).Trim()
    # 4. O desenho ja esta na pasta?
    $drawingUid = Get-DcaModelObjectUid $drawingDataset.Object

    $matchesDrawing = {
      param($RelatedEntry)

      $relatedUid = Get-DcaModelObjectUid $RelatedEntry.Object

      if ($drawingUid -and $relatedUid) {
        return ($relatedUid -eq $drawingUid)
      }

      return (
        [string]$RelatedEntry.ObjectString -ieq
        [string]$drawingDataset.ObjectString
      )
    }

    $existingObjects =
    @(
      Show-DcaTeamcenterRevisionDatasets `
        -Revision $processRevision `
        -RelationNames @($RelationName)
    )

    $alreadyLinked =
    @($existingObjects | Where-Object { & $matchesDrawing $_ })

    if ($alreadyLinked.Count -gt 0) {

      if ($Details) {
        Write-Host (
          "  O desenho NDT ja esta vinculado a Pasta NDT do Processo " +
          "'$processCode/$processRevisionId'."
        ) -ForegroundColor DarkGray
      }

      return [PSCustomObject]@{
        Status = "JaVinculado"
        Target = "$processCode/$processRevisionId"
      }
    }

    # 5. Criar a relacao Processo -> Dataset do desenho.
    New-DcaTeamcenterRelation `
      -PrimaryObject $processRevision `
      -SecondaryObject $drawingDataset.Object `
      -RelationType $RelationName

    # 6. Confirmar.
    $objectsAfter =
    @(
      Show-DcaTeamcenterRevisionDatasets `
        -Revision $processRevision `
        -RelationNames @($RelationName)
    )

    $linkedAfter =
    @($objectsAfter | Where-Object { & $matchesDrawing $_ })

    if ($linkedAfter.Count -gt 0) {

      if ($Details) {
        Write-Host (
          "  O desenho NDT foi vinculado a Pasta NDT do Processo " +
          "'$processCode/$processRevisionId'."
        ) -ForegroundColor DarkGray
      }

      return [PSCustomObject]@{
        Status = "Vinculado"
        Target = "$processCode/$processRevisionId"
      }
    }

    Write-Warn (
      "A relacao com a Pasta NDT foi solicitada, mas nao foi " +
      "possivel confirma-la. Confira no Teamcenter."
    )

    return [PSCustomObject]@{ Status = "NaoConfirmado" }
  }
  catch {

    $realException = $_.Exception
    while ($null -ne $realException.InnerException) {
      $realException = $realException.InnerException
    }

    Write-Warn (
      "O desenho NDT foi importado, mas nao foi vinculado a Pasta " +
      "NDT do Processo '$processCode': $($realException.Message)"
    )

    return [PSCustomObject]@{
      Status = "Erro"
      ErrorMessage = [string]$realException.Message
    }
  }
}
function Find-DcaProcessRevisionByCode {

  # Localiza o DCA Processo pelo codigo, sem perguntar ao usuario.
  # Usa a saved query e fica apenas com o Item cujo tipo e o
  # configurado em *_PROCESS_ITEM_TYPE no .env. Itens de outro tipo
  # com o mesmo codigo (por exemplo Design) sao ignorados.
  param(
    [Parameter(Mandatory = $true)]
    [string]$ItemCode
  )

  $envPrefix =
  if ($script:TeamcenterEnvironment -eq "Processo") {
    "DCA_TC_PROCESS_PROCESS"
  }
  else {
    "DCA_TC_TEST_PROCESS"
  }

  $configuredType =
  ([string][System.Environment]::GetEnvironmentVariable(
      "${envPrefix}_ITEM_TYPE"
    )).Trim()

  if ([string]::IsNullOrWhiteSpace($configuredType)) {
    $configuredType = "GD5_DCA_PROCESSO"
  }

  # object_type devolve o nome de exibicao ("DCA PROCESSO"), e o .env
  # tem o nome interno (GD5_DCA_PROCESSO). Os dois sao normalizados.
  $normalizeType = {
    param($TypeText)

    (
      ([string]$TypeText).Trim().ToUpperInvariant() `
        -replace '^GD5_', '' `
        -replace '_', ' '
    )
  }

  $expectedType = & $normalizeType $configuredType

  $candidates =
  @(
    Find-DcaTeamcenterItemBySavedQuery `
      -ItemCode $ItemCode.Trim().ToUpperInvariant()
  )

  foreach ($candidate in $candidates) {

    $candidateItem = $candidate.Item

    if ($null -eq $candidateItem) { continue }

    $null = @(
      Update-DcaModelObjectProperties `
        -ModelObject $candidateItem `
        -PropertyNames @("object_type")
    )

    $candidateType =
    & $normalizeType (
      Get-TeamcenterModelPropertyText `
        -ModelObject $candidateItem `
        -PropertyName "object_type"
    )

    if ($Details) {
      Write-Host (
        "  Candidato '$($candidate.ObjectUid)': tipo " +
        "'$candidateType' (esperado '$expectedType')."
      ) -ForegroundColor DarkGray
    }

    if ($candidateType -ne $expectedType) { continue }

    $candidateRevision =
    Get-TeamcenterRevision -Item $candidateItem

    if ($null -eq $candidateRevision) { continue }

    return [PSCustomObject]@{
      Item = $candidateItem
      Revision = $candidateRevision
      ItemType = $candidateType
    }
  }

  return $null
}

function Show-DcaNdtImportLocation {
  param(
    [Parameter(Mandatory = $true)]
    $Location
  )

  Write-Host ""
  Write-Host (
    "  Onde a folha NDT {0} foi importada:" -f $Location.SourceCode
  ) -ForegroundColor Green

  Write-Host ("  " + ("-" * 68)) -ForegroundColor DarkGray

  Write-Host (
    "    Ambiente:  Teamcenter de {0}" -f $Location.Environment
  ) -ForegroundColor White

  Write-Host (
    "    Item:      {0}   (tipo {1})" -f $Location.ItemCode, $Location.ItemType
  ) -ForegroundColor White

  Write-Host (
    "    Revisao:   {0}   (tipo {1})" -f $Location.RevisionId, $Location.RevisionType
  ) -ForegroundColor White

  Write-Host ""
  Write-Host "    Conteudo da revisao no Teamcenter:" -ForegroundColor Cyan

  foreach ($entry in @($Location.Contents)) {

    $kind =
    if ([string]$entry.BusinessType -match '(?i)^PDF$') { "PDF    " }
    else { "Desenho" }

    Write-Host (
      "      [{0}] {1}   tipo: {2}   relacao: {3}" -f
      $kind,
      $entry.ObjectName,
      $entry.BusinessType,
      $entry.Relation
    ) -ForegroundColor Gray
  }

  Write-Host ""
  Write-Host "    Origem dos arquivos (PDM):" -ForegroundColor Cyan
  Write-Host ("      PDF:     {0}" -f $Location.PdfSource) -ForegroundColor DarkGray
  Write-Host ("      Desenho: {0}" -f $Location.DrawingSource) -ForegroundColor DarkGray

  if (-not [string]::IsNullOrWhiteSpace([string]$Location.Workflow)) {

    Write-Host ""
    Write-Host (
      "    Workflow:  {0}" -f $Location.Workflow
    ) -ForegroundColor Cyan
  }
}