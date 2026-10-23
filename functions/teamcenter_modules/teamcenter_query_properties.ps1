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