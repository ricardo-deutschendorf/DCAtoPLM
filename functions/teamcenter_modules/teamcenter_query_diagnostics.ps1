# ============================================================
# DIAGNOSTICO DAS CONSULTAS DO TEAMCENTER
# ============================================================
# Exibe metodos, servicos e tipos usados nas consultas do Teamcenter.
# Auxilia na comparacao entre versoes das bibliotecas SOA.
# Nao pesquisa Items nem altera objetos no Teamcenter.
# ============================================================

# Retorna os tipos carregaveis de um assembly.
function Get-DcaAssemblyTypesSafe {
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        $Assembly
    )

    try {
        return @($Assembly.GetTypes())
    }
    catch [System.Reflection.ReflectionTypeLoadException] {
        if ($Details) {
            foreach ($error in @($_.Exception.LoaderExceptions | Where-Object { $null -ne $_ })) {
                Write-Warn "Falha parcial ao carregar tipo do assembly '$($Assembly.GetName().Name)': $($error.Message)"
            }
        }

        return @($_.Exception.Types | Where-Object { $null -ne $_ })
    }
    catch {
        if ($Details) {
            Write-Warn "Nao foi possivel ler os tipos do assembly '$($Assembly.GetName().Name)': $($_.Exception.Message)"
        }

        return @()
    }
}

# Formata a assinatura de um metodo ou construtor.
function Get-DcaMethodParameterText {
    param(
        [Parameter(Mandatory)]
        $Method
    )

    return @(
        $Method.GetParameters() | ForEach-Object {
            "{0} {1}" -f $_.ParameterType.FullName, $_.Name
        }
    ) -join ", "
}

# Lista os metodos de consulta disponiveis no Importar GD.
function Show-DcaTeamcenterLookupMethods {
    if ($null -eq $script:TeamcenterFunctions) { return }

    Write-Host ""
    Write-Host "  Metodos de consulta disponiveis:" -ForegroundColor Cyan

    foreach ($method in @(
        $script:TeamcenterFunctions.GetMethods() |
            Where-Object { $_.Name -match '(?i)item|revision|load|find|search' } |
            Sort-Object Name
    )) {
        $parameters = Get-DcaMethodParameterText -Method $method

        Write-Host (
            "    {0}({1}) -> {2}" -f
            $method.Name, $parameters, $method.ReturnType.FullName
        ) -ForegroundColor DarkGray
    }

    Write-Host ""
}

# Lista os tipos SavedQueryService e os respectivos metodos.
function Show-TeamcenterQueryServiceTypes {
    Write-Host ""
    Write-Host "  Tipos de servico de consulta carregados:" -ForegroundColor Cyan

    $serviceTypes = @(
        foreach ($assembly in @($script:TeamcenterQueryAssemblies)) {
            Get-DcaAssemblyTypesSafe -Assembly $assembly |
                Where-Object { $_.FullName -match '(?i)SavedQueryService$' }
        }
    ) | Sort-Object FullName -Unique

    if ($serviceTypes.Count -eq 0) {
        Write-Warn "Nenhum tipo SavedQueryService foi encontrado."
        return
    }

    foreach ($type in $serviceTypes) {
        Write-Host "    Tipo: $($type.FullName)" -ForegroundColor Gray

        foreach ($method in @(
            $type.GetMethods() |
                Where-Object { $_.Name -match '(?i)execute|query|search|getservice' } |
                Sort-Object Name
        )) {
            $parameters = Get-DcaMethodParameterText -Method $method

            Write-Host (
                "      {0}({1}) -> {2}" -f
                $method.Name, $parameters, $method.ReturnType.FullName
            ) -ForegroundColor DarkGray
        }
    }

    Write-Host ""
}

# Exibe construtores, campos e propriedades dos tipos de Saved Query.
function Show-TeamcenterSavedQueryTypeDetails {
    Write-Host ""
    Write-Host "  Estrutura dos tipos de Saved Query:" -ForegroundColor Cyan

    $assemblies = @($script:TeamcenterQueryAssemblies)

    if ($assemblies.Count -eq 0) {
        Write-Warn "As bibliotecas de consulta nao foram localizadas entre os assemblies carregados."
        return
    }

    if ($Details) {
        foreach ($assembly in $assemblies) {
            Write-Host "  Assembly de consulta encontrado: $($assembly.GetName().Name)" -ForegroundColor Green
            Write-Host "    Arquivo: $($assembly.Location)" -ForegroundColor DarkGray
        }
    }

    $typePattern = '(?i)QueryInput|SavedQueryInput|SavedQueriesResponse|' +
        'ExecuteSavedQueryResponse|SavedQueryObject|' +
        'BusinessObjectQueryClause|QueryResults|SavedQueryResults'

    $queryTypes = @(
        foreach ($assembly in $assemblies) {
            Write-Host "  Analisando biblioteca: $($assembly.GetName().Name)" -ForegroundColor DarkGray

            Get-DcaAssemblyTypesSafe -Assembly $assembly |
                Where-Object {
                    $null -ne $_ -and
                    -not [string]::IsNullOrWhiteSpace([string]$_.FullName) -and
                    $_.FullName -match $typePattern
                }
        }
    ) | Sort-Object FullName -Unique

    if ($queryTypes.Count -eq 0) {
        Write-Warn "Nenhum tipo de entrada ou resposta de Saved Query foi encontrado nas bibliotecas carregadas."
        return
    }

    $flags = [System.Reflection.BindingFlags]::Public -bor
        [System.Reflection.BindingFlags]::Instance

    foreach ($type in $queryTypes) {
        Write-Host ""
        Write-Host "  TIPO: $($type.FullName)" -ForegroundColor Green

        foreach ($constructor in $type.GetConstructors($flags)) {
            $parameters = Get-DcaMethodParameterText -Method $constructor
            Write-Host "    CONSTRUTOR: ($parameters)" -ForegroundColor DarkGray
        }

        foreach ($field in @($type.GetFields($flags) | Sort-Object Name)) {
            Write-Host (
                "    CAMPO: {0} = {1}" -f
                $field.Name, $field.FieldType.FullName
            ) -ForegroundColor Gray
        }

        foreach ($property in @($type.GetProperties($flags) | Sort-Object Name)) {
            Write-Host (
                "    PROPRIEDADE: {0} = {1} | escrita={2}" -f
                $property.Name, $property.PropertyType.FullName, $property.CanWrite
            ) -ForegroundColor Gray
        }
    }

    Write-Host ""
}