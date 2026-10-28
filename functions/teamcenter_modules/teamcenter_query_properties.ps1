# ============================================================
# LEITURA DAS PROPRIEDADES DOS OBJETOS DO TEAMCENTER
# ============================================================
#
# Este arquivo recupera valores textuais dos objetos retornados
# pela API SOA do Teamcenter.
#
# Responsabilidades:
#   1. remover wrappers criados pelo PowerShell;
#   2. localizar GetProperty ou getPropertyObject;
#   3. ler StringValue, DisplayableValue ou StringArrayValue;
#   4. transformar valores enumeraveis em texto;
#   5. retornar uma string vazia quando a propriedade nao puder
#      ser lida;
#   6. apresentar diagnosticos adicionais quando Details estiver
#      ativo.
#
# A funcao deste arquivo apenas le propriedades. Nenhum objeto
# e criado ou alterado no Teamcenter.
# ============================================================
function Get-TeamcenterModelPropertyText {

  # Recupera uma propriedade textual de um objeto retornado
  # pela API do Teamcenter.
  param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNull()]
    $ModelObject,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$PropertyName
  )

  $baseObject =
  $ModelObject.PSObject.BaseObject

  if ($null -ne $baseObject) {

    $ModelObject =
    $baseObject
  }

  $objectType =
  $ModelObject.GetType()

  # Algumas versoes da API expoem GetProperty e outras
  # expoem getPropertyObject.
  $getPropertyMethod =
  $objectType.GetMethods() |
    Where-Object {
    $_.Name -match
    "^(?i)(GetProperty|getPropertyObject)$" -and
    $_.GetParameters().Count -eq 1
  } |
    Sort-Object {
    if ($_.Name -ieq "GetProperty") {
      0
    }
    else {
      1
    }
  } |
    Select-Object -First 1

  if ($null -eq $getPropertyMethod) {

    if ($Details) {

      Write-Warn (
        "Nenhum metodo GetProperty ou getPropertyObject " +
        "foi encontrado no tipo '$($objectType.FullName)'."
      )
    }

    return ""
  }

  try {

    $propertyObject =
    $getPropertyMethod.Invoke(
      $ModelObject,
      @(
        [string]$PropertyName
      )
    )

    if ($null -eq $propertyObject) {

      return ""
    }

    $propertyType =
    $propertyObject.GetType()

    foreach (
      $candidatePropertyName in @(
        "StringValue",
        "DisplayableValue",
        "StringArrayValue"
      )
    ) {

      $candidateProperty =
      $propertyType.GetProperty(
        $candidatePropertyName
      )

      if ($null -eq $candidateProperty) {

        continue
      }

      $candidateValue =
      $candidateProperty.GetValue(
        $propertyObject,
        $null
      )

      if (
        $candidateValue -is
        [System.Collections.IEnumerable] -and
        $candidateValue -isnot [string]
      ) {

        $candidateValue =
        @($candidateValue) -join ", "
      }

      $candidateText =
      ([string]$candidateValue).Trim()

      if (
        -not [string]::IsNullOrWhiteSpace(
          $candidateText
        )
      ) {

        return $candidateText
      }
    }

    return ""
  }
  catch {

    if ($Details) {

      $realException =
      $_.Exception

      while (
        $null -ne $realException.InnerException
      ) {

        $realException =
        $realException.InnerException
      }

      Write-Warn (
        "Nao foi possivel ler a propriedade " +
        "'$PropertyName' do tipo " +
        "'$($objectType.FullName)': " +
        $realException.Message
      )
    }

    return ""
  }
}
# ============================================================
# DIAGNOSTICO DAS PROPRIEDADES DA REVISAO
# ============================================================
function Show-DcaTeamcenterRevisionProperties {

  # Lista os nomes tecnicos e os valores exibidos das propriedades
  # disponíveis no objeto de revisao.
  #
  # Esta funcao realiza somente consultas. Nenhuma propriedade
  # do Teamcenter e alterada.
  param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNull()]
    $Revision,

    # Quando informado, mostra somente propriedades cujo nome ou
    # valor contenha o texto pesquisado.
    [string]$SearchText
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
      "das propriedades."
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
  # 2. OBTER OS NOMES DAS PROPRIEDADES
  # ============================================================

  $propertyNames =
  @(
    $Revision.PropertyNames |
      ForEach-Object {
      ([string]$_).Trim()
    } |
      Where-Object {
      -not [string]::IsNullOrWhiteSpace(
        [string]$_
      )
    } |
      Sort-Object -Unique
  )

  if ($propertyNames.Count -eq 0) {

    throw (
      "A revisao nao retornou nomes de propriedades."
    )
  }

  # ============================================================
  # 3. CARREGAR AS PROPRIEDADES NO MODELO CLIENTE
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

  $propertyArguments =
  New-Object "System.Object[]" 2

  $propertyArguments[0] =
  $revisionArray

  $propertyArguments[1] =
  [string[]]$propertyNames

  try {

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

      if (
        $propertyErrors.Count -gt 0 -and
        $Details
      ) {

        Write-Warn (
          "Algumas propriedades nao puderam ser carregadas: " +
          ($propertyErrors -join " | ")
        )
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
      "Nao foi possivel carregar as propriedades da revisao: " +
      $realException.Message
    )
  }

  # ============================================================
  # 4. LOCALIZAR OS METODOS DE LEITURA
  # ============================================================

  $getDisplayValueMethod =
  $Revision.GetType().GetMethods() |
    Where-Object {
    $_.Name -eq "GetPropertyDisplayableValue" -and
    $_.GetParameters().Count -eq 1 -and
    $_.GetParameters()[0].ParameterType -eq [string]
  } |
    Select-Object -First 1

  $getDisplayValuesMethod =
  $Revision.GetType().GetMethods() |
    Where-Object {
    $_.Name -eq "GetPropertyDisplayableValues" -and
    $_.GetParameters().Count -eq 1 -and
    $_.GetParameters()[0].ParameterType -eq [string]
  } |
    Select-Object -First 1

  if (
    $null -eq $getDisplayValueMethod -and
    $null -eq $getDisplayValuesMethod
  ) {

    throw (
      "Os metodos de leitura das propriedades nao foram " +
      "encontrados no objeto de revisao."
    )
  }

  # ============================================================
  # 5. LER OS VALORES DAS PROPRIEDADES
  # ============================================================

  $propertyResults =
  [System.Collections.Generic.List[object]]::new()

  foreach ($propertyName in $propertyNames) {

    $propertyValue =
    ""

    try {

      if ($null -ne $getDisplayValuesMethod) {

        $displayValues =
        @(
          $getDisplayValuesMethod.Invoke(
            $Revision,
            @(
              [string]$propertyName
            )
          )
        )

        $propertyValue =
        @(
          $displayValues |
            ForEach-Object {
            ([string]$_).Trim()
          } |
            Where-Object {
            -not [string]::IsNullOrWhiteSpace(
              [string]$_
            )
          }
        ) -join " | "
      }

      if (
        [string]::IsNullOrWhiteSpace(
          $propertyValue
        ) -and
        $null -ne $getDisplayValueMethod
      ) {

        $propertyValue =
        [string]$getDisplayValueMethod.Invoke(
          $Revision,
          @(
            [string]$propertyName
          )
        )

        $propertyValue =
        $propertyValue.Trim()
      }
    }
    catch {

      if ($Details) {

        $propertyValue =
        "<nao foi possivel ler>"
      }
      else {

        continue
      }
    }

    $matchesSearch =
    $true

    if (
      -not [string]::IsNullOrWhiteSpace(
        $SearchText
      )
    ) {

      $matchesSearch =
      (
        $propertyName.IndexOf(
          $SearchText,
          [System.StringComparison]::OrdinalIgnoreCase
        ) -ge 0 -or
        $propertyValue.IndexOf(
          $SearchText,
          [System.StringComparison]::OrdinalIgnoreCase
        ) -ge 0
      )
    }

    if (-not $matchesSearch) {
      continue
    }

    $propertyResults.Add(
      [PSCustomObject]@{
        PropertyName = $propertyName
        Value = $propertyValue
      }
    )
  }

  # ============================================================
  # 6. APRESENTAR O RESULTADO
  # ============================================================

  Write-AnimatedLine ""

  Write-Host (
    "  Propriedades da revisao do Teamcenter:"
  ) -ForegroundColor Cyan

  Write-Host (
    "  Tipo tecnico: $revisionTypeName"
  ) -ForegroundColor DarkGray

  if (
    -not [string]::IsNullOrWhiteSpace(
      $SearchText
    )
  ) {

    Write-Host (
      "  Filtro: '$SearchText'"
    ) -ForegroundColor DarkGray
  }

  Write-Host ""

  if ($propertyResults.Count -eq 0) {

    Write-Warn (
      "Nenhuma propriedade corresponde ao filtro informado."
    )

    return @()
  }

  foreach ($propertyResult in $propertyResults) {

    $valueText =
    [string]$propertyResult.Value

    if (
      [string]::IsNullOrWhiteSpace(
        $valueText
      )
    ) {

      $valueText =
      "<vazio>"
    }

    Write-Host (
      "    {0} = '{1}'" -f
      $propertyResult.PropertyName,
      $valueText
    ) -ForegroundColor Gray
  }

  Write-Host ""

  return $propertyResults.ToArray()
}
