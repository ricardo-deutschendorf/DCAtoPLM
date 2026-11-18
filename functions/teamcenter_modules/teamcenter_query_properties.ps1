# ============================================================
# LEITURA E DIAGNOSTICO DE PROPRIEDADES DO TEAMCENTER
# ============================================================
# Le propriedades textuais dos objetos SOA e lista as propriedades
# disponiveis em revisoes. Nao cria nem altera objetos no Teamcenter.
# ============================================================

# Remove o wrapper criado pelo PowerShell, quando presente.
function Get-DcaModelBaseObject {
    param($Object)

    if ($null -eq $Object) { return $null }
    if ($null -ne $Object.PSObject.BaseObject) { return $Object.PSObject.BaseObject }
    return $Object
}

# Retorna a excecao interna real.
function Get-DcaRootException {
    param([Parameter(Mandatory)]$Exception)

    while ($null -ne $Exception.InnerException) {
        $Exception = $Exception.InnerException
    }

    return $Exception
}

# Converte um valor simples ou enumeravel em texto.
function ConvertTo-DcaPropertyText {
    param(
        $Value,
        [string]$Separator = ", "
    )

    if ($null -eq $Value) { return "" }

    if ($Value -is [System.Collections.IEnumerable] -and $Value -isnot [string]) {
        return @(
            $Value |
                ForEach-Object { ([string]$_).Trim() } |
                Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
        ) -join $Separator
    }

    return ([string]$Value).Trim()
}

# Le uma propriedade textual de um objeto retornado pela API SOA.
function Get-TeamcenterModelPropertyText {
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        $ModelObject,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$PropertyName
    )

    $ModelObject = Get-DcaModelBaseObject $ModelObject
    $objectType = $ModelObject.GetType()

    $getPropertyMethod = $objectType.GetMethods() |
        Where-Object {
            $_.Name -match '^(?i:GetProperty|getPropertyObject)$' -and
            $_.GetParameters().Count -eq 1
        } |
        Sort-Object { if ($_.Name -ieq "GetProperty") { 0 } else { 1 } } |
        Select-Object -First 1

    if ($null -eq $getPropertyMethod) {
        if ($Details) {
            Write-Warn "Nenhum metodo GetProperty ou getPropertyObject foi encontrado no tipo '$($objectType.FullName)'."
        }

        return ""
    }

    try {
        $propertyObject = $getPropertyMethod.Invoke(
            $ModelObject,
            @([string]$PropertyName)
        )
        if ($null -eq $propertyObject) { return "" }

        $propertyType = $propertyObject.GetType()

        foreach ($name in @("StringValue", "DisplayableValue", "StringArrayValue")) {
            $property = $propertyType.GetProperty($name)
            if ($null -eq $property) { continue }

            try {
                $text = ConvertTo-DcaPropertyText (
                    $property.GetValue($propertyObject, $null)
                )
            }
            catch {
                continue
            }

            if (-not [string]::IsNullOrWhiteSpace($text)) { return $text }
        }
    }
    catch {
        if ($Details) {
            $error = Get-DcaRootException $_.Exception
            Write-Warn "Nao foi possivel ler a propriedade '$PropertyName' do tipo '$($objectType.FullName)': $($error.Message)"
        }
    }

    return ""
}

# Lista os nomes tecnicos e valores exibidos das propriedades da revisao.
function Show-DcaTeamcenterRevisionProperties {
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        $Revision,

        [string]$SearchText
    )

    $Revision = Get-DcaModelBaseObject $Revision
    if ($null -eq $Revision) {
        throw "A revisao nao foi fornecida para o diagnostico das propriedades."
    }

    $revisionTypeName = $Revision.GetType().FullName
    if ($revisionTypeName -notmatch '(?i)(ItemRevision|Revision)$') {
        throw "O objeto recebido nao e uma revisao valida. Tipo recebido: '$revisionTypeName'."
    }

    if (-not $Revision.PSObject.Properties["PropertyNames"]) {
        throw "O objeto de revisao '$revisionTypeName' nao disponibiliza a colecao PropertyNames."
    }

    $propertyNames = @(
        $Revision.PropertyNames |
            ForEach-Object { ([string]$_).Trim() } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
            Sort-Object -Unique
    )
    if ($propertyNames.Count -eq 0) {
        throw "A revisao nao retornou nomes de propriedades."
    }

    # Carrega todas as propriedades no modelo cliente.
    $service = Get-TeamcenterDataManagementService
    $getPropertiesMethod = $service.GetType().GetMethods() |
        Where-Object {
            $_.Name -ieq "GetProperties" -and
            $_.GetParameters().Count -eq 2
        } |
        Select-Object -First 1

    if ($null -eq $getPropertiesMethod) {
        throw "DataManagementService.GetProperties nao foi encontrado."
    }

    $arrayType = $getPropertiesMethod.GetParameters()[0].ParameterType
    if (-not $arrayType.IsArray) {
        throw "O primeiro parametro de GetProperties nao e um array."
    }

    $objectType = $arrayType.GetElementType()
    if ($null -eq $objectType) {
        throw "O tipo dos objetos de GetProperties nao foi identificado."
    }

    $revisionArray = [System.Array]::CreateInstance($objectType, 1)
    $revisionArray.SetValue($Revision, 0)

    try {
        $response = $getPropertiesMethod.Invoke(
            $service,
            [object[]]@($revisionArray, [string[]]$propertyNames)
        )

        if ($null -ne $response) {
            $errors = @(Get-TeamcenterServiceErrors -ServiceData $response)

            if ($errors.Count -gt 0 -and $Details) {
                Write-Warn "Algumas propriedades nao puderam ser carregadas: $($errors -join ' | ')"
            }
        }
    }
    catch {
        $error = Get-DcaRootException $_.Exception
        throw "Nao foi possivel carregar as propriedades da revisao: $($error.Message)"
    }

      # Localiza as formas de leitura disponibilizadas pela API.
    $methods = $Revision.GetType().GetMethods() |
        Where-Object {
            $_.Name -match '^GetPropertyDisplayableValues?$' -and
            $_.GetParameters().Count -eq 1 -and
            $_.GetParameters()[0].ParameterType -eq [string]
        }

    $getDisplayValueMethod = $methods |
        Where-Object { $_.Name -eq "GetPropertyDisplayableValue" } |
        Select-Object -First 1

    $getDisplayValuesMethod = $methods |
        Where-Object { $_.Name -eq "GetPropertyDisplayableValues" } |
        Select-Object -First 1

    if ($null -eq $getDisplayValueMethod -and
        $null -eq $getDisplayValuesMethod) {
        throw "Os metodos de leitura das propriedades nao foram encontrados no objeto de revisao."
    }

    $searchTextClean = ([string]$SearchText).Trim()
    $results = [System.Collections.Generic.List[object]]::new()

    foreach ($propertyName in $propertyNames) {
        $value = ""

        try {
            if ($null -ne $getDisplayValuesMethod) {
                $displayValues = $getDisplayValuesMethod.Invoke(
                    $Revision,
                    @([string]$propertyName)
                )

                $value = ConvertTo-DcaPropertyText `
                    -Value $displayValues `
                    -Separator " | "
            }

            if ([string]::IsNullOrWhiteSpace($value) -and
                $null -ne $getDisplayValueMethod) {
                $displayValue = $getDisplayValueMethod.Invoke(
                    $Revision,
                    @([string]$propertyName)
                )

                $value = ConvertTo-DcaPropertyText -Value $displayValue
            }
        }
        catch {
            if (-not $Details) { continue }
            $value = "<nao foi possivel ler>"
        }

        if (
            -not [string]::IsNullOrWhiteSpace($searchTextClean) -and
            $propertyName.IndexOf(
                $searchTextClean,
                [System.StringComparison]::OrdinalIgnoreCase
            ) -lt 0 -and
            $value.IndexOf(
                $searchTextClean,
                [System.StringComparison]::OrdinalIgnoreCase
            ) -lt 0
        ) {
            continue
        }

        $results.Add([PSCustomObject]@{
            PropertyName = $propertyName
            Value        = $value
        })
    }

    Write-AnimatedLine ""
    Write-Host "  Propriedades da revisao do Teamcenter:" -ForegroundColor Cyan
    Write-Host "  Tipo tecnico: $revisionTypeName" -ForegroundColor DarkGray

    if (-not [string]::IsNullOrWhiteSpace($searchTextClean)) {
        Write-Host "  Filtro: '$searchTextClean'" -ForegroundColor DarkGray
    }

    Write-Host ""

    if ($results.Count -eq 0) {
        if ([string]::IsNullOrWhiteSpace($searchTextClean)) {
            Write-Warn "Nenhuma propriedade com valor legivel foi encontrada na revisao."
        }
        else {
            Write-Warn "Nenhuma propriedade corresponde ao filtro '$searchTextClean'."
        }

        return @()
    }

    foreach ($result in $results) {
        $valueText = ([string]$result.Value).Trim()

        if ([string]::IsNullOrWhiteSpace($valueText)) {
            $valueText = "<vazio>"
        }

        Write-Host (
            "    {0} = '{1}'" -f
            $result.PropertyName,
            $valueText
        ) -ForegroundColor Gray
    }

    Write-Host ""
    return $results.ToArray()
}