# ============================================================
# DIAGNOSTICO DAS CONSULTAS DO TEAMCENTER
# ============================================================
#
# Este arquivo apresenta informacoes tecnicas sobre os metodos,
# servicos e tipos utilizados pelas consultas do Teamcenter.
#
# Responsabilidades:
#   1. listar os metodos de consulta do Importar GD;
#   2. localizar tipos SavedQueryService carregados;
#   3. listar os metodos disponiveis nos servicos de consulta;
#   4. apresentar construtores, campos e propriedades dos tipos
#      utilizados pelas Saved Queries;
#   5. auxiliar o diagnostico de diferencas entre versoes das
#      bibliotecas SOA.
#
# As funcoes deste arquivo nao pesquisam Items e nao alteram
# objetos no Teamcenter.
# ============================================================
function Show-DcaTeamcenterLookupMethods {

  if ($null -eq $script:TeamcenterFunctions) {
    return
  }

  Write-Host ""

  Write-Host (
    "  Metodos de consulta disponiveis:"
  ) -ForegroundColor Cyan

  $lookupMethods =
  @(
    $script:TeamcenterFunctions.GetMethods() |
      Where-Object {
      $_.Name -match
      "(?i)item|revision|load|find|search"
    } |
      Sort-Object Name
  )

  foreach ($lookupMethod in $lookupMethods) {

    $parameterText =
    @(
      $lookupMethod.GetParameters() |
        ForEach-Object {

        "{0} {1}" -f
        $_.ParameterType.FullName,
        $_.Name
      }
    ) -join ", "

    Write-Host (
      "    {0}({1}) -> {2}" -f
      $lookupMethod.Name,
      $parameterText,
      $lookupMethod.ReturnType.FullName
    ) -ForegroundColor DarkGray
  }

  Write-Host ""
}
function Show-TeamcenterQueryServiceTypes {

  Write-Host ""

  Write-Host (
    "  Tipos de servico de consulta carregados:"
  ) -ForegroundColor Cyan

  $queryAssemblies =
  @(
    $script:TeamcenterQueryAssemblies
  )

  $queryServiceTypes =
  [System.Collections.Generic.List[type]]::new()

  foreach ($queryAssembly in $queryAssemblies) {

    try {

      $assemblyTypes =
      @(
        $queryAssembly.GetTypes()
      )
    }
    catch [System.Reflection.ReflectionTypeLoadException] {

      $assemblyTypes =
      @(
        $_.Exception.Types |
          Where-Object {
          $null -ne $_
        }
      )
    }

    foreach ($assemblyType in $assemblyTypes) {

      if (
        $null -ne $assemblyType -and
        $assemblyType.FullName -match
        "(?i)SavedQueryService$"
      ) {

        $queryServiceTypes.Add(
          $assemblyType
        )
      }
    }
  }

  $queryServiceTypes =
  @(
    $queryServiceTypes |
      Sort-Object FullName -Unique
  )

  if ($queryServiceTypes.Count -eq 0) {

    Write-Warn (
      "Nenhum tipo SavedQueryService foi encontrado."
    )

    return
  }

  foreach ($queryServiceType in $queryServiceTypes) {

    Write-Host (
      "    Tipo: {0}" -f
      $queryServiceType.FullName
    ) -ForegroundColor Gray

    foreach (
      $queryMethod in (
        $queryServiceType.GetMethods() |
          Where-Object {
          $_.Name -match
          "(?i)execute|query|search|getservice"
        } |
          Sort-Object Name
      )
    ) {

      $parameterText =
      @(
        $queryMethod.GetParameters() |
          ForEach-Object {

          "{0} {1}" -f
          $_.ParameterType.FullName,
          $_.Name
        }
      ) -join ", "

      Write-Host (
        "      {0}({1}) -> {2}" -f
        $queryMethod.Name,
        $parameterText,
        $queryMethod.ReturnType.FullName
      ) -ForegroundColor DarkGray
    }
  }

  Write-Host ""
}
function Show-TeamcenterSavedQueryTypeDetails {

  Write-Host ""

  Write-Host (
    "  Estrutura dos tipos de Saved Query:"
  ) -ForegroundColor Cyan

  $queryAssemblies =
  @(
    $script:TeamcenterQueryAssemblies
  )

  if ($Details) {

    foreach ($queryAssembly in $queryAssemblies) {

      Write-Host (
        "  Assembly de consulta encontrado: " +
        "$($queryAssembly.GetName().Name)"
      ) -ForegroundColor Green

      Write-Host (
        "    Arquivo: " +
        $queryAssembly.Location
      ) -ForegroundColor DarkGray
    }
  }

  if ($queryAssemblies.Count -eq 0) {

    Write-Warn (
      "As bibliotecas de consulta nao foram localizadas " +
      "entre os assemblies carregados."
    )

    return
  }

  $queryTypes =
  [System.Collections.Generic.List[type]]::new()

  foreach ($queryAssembly in $queryAssemblies) {

    Write-Host (
      "  Analisando biblioteca: " +
      $queryAssembly.GetName().Name
    ) -ForegroundColor DarkGray

    try {

      $assemblyTypes =
      @(
        $queryAssembly.GetTypes()
      )
    }
    catch [System.Reflection.ReflectionTypeLoadException] {

      $assemblyTypes =
      @(
        $_.Exception.Types |
          Where-Object {
          $null -ne $_
        }
      )

      if ($Details) {

        foreach (
          $loaderException in
          $_.Exception.LoaderExceptions
        ) {

          if ($null -eq $loaderException) {
            continue
          }

          Write-Warn (
            "Falha parcial ao carregar tipo: " +
            $loaderException.Message
          )
        }
      }
    }

    foreach ($assemblyType in $assemblyTypes) {

      if (
        $assemblyType.FullName -match
        "(?i)QueryInput|" +
        "SavedQueryInput|" +
        "SavedQueriesResponse|" +
        "ExecuteSavedQueryResponse|" +
        "SavedQueryObject|" +
        "BusinessObjectQueryClause|" +
        "QueryResults|" +
        "SavedQueryResults"
      ) {

        $queryTypes.Add(
          $assemblyType
        )
      }
    }
  }

  $queryTypes =
  @(
    $queryTypes |
      Sort-Object FullName -Unique
  )

  if ($queryTypes.Count -eq 0) {

    Write-Warn (
      "Nenhum tipo de entrada ou resposta de Saved Query " +
      "foi encontrado nas bibliotecas carregadas."
    )

    return
  }

  $bindingFlags =
  [System.Reflection.BindingFlags]::Public -bor
  [System.Reflection.BindingFlags]::Instance

  foreach ($queryType in $queryTypes) {

    Write-Host ""

    Write-Host (
      "  TIPO: $($queryType.FullName)"
    ) -ForegroundColor Green

    foreach (
      $constructor in
      $queryType.GetConstructors(
        $bindingFlags
      )
    ) {

      $parameterText =
      @(
        $constructor.GetParameters() |
          ForEach-Object {

          "{0} {1}" -f
          $_.ParameterType.FullName,
          $_.Name
        }
      ) -join ", "

      Write-Host (
        "    CONSTRUTOR: ({0})" -f
        $parameterText
      ) -ForegroundColor DarkGray
    }

    foreach (
      $field in (
        $queryType.GetFields(
          $bindingFlags
        ) |
          Sort-Object Name
      )
    ) {

      Write-Host (
        "    CAMPO: {0} = {1}" -f
        $field.Name,
        $field.FieldType.FullName
      ) -ForegroundColor Gray
    }

    foreach (
      $property in (
        $queryType.GetProperties(
          $bindingFlags
        ) |
          Sort-Object Name
      )
    ) {

      Write-Host (
        "    PROPRIEDADE: {0} = {1} | escrita={2}" -f
        $property.Name,
        $property.PropertyType.FullName,
        $property.CanWrite
      ) -ForegroundColor Gray
    }
  }

  Write-Host ""
}