$script:ImporterAssembly = $null
$script:TeamcenterSession = $null
$script:TeamcenterFunctions = $null
$script:TeamcenterEnvironment = $null

$script:TeamcenterQueryAssemblies =
[System.Collections.Generic.List[object]]::new()
# Funcoes de integracao com o Teamcenter.
# Este arquivo concentra conexao, configuracao dos tipos DCA,
# construcao das entradas SOA, criacao dos objetos, importacao
# do PDF e inicializacao dos workflows.

# ============================================================
# CONEXAO E SESSAO DO TEAMCENTER
# ============================================================
function Confirm-TeamcenterImporter {

  # Valida o executavel que contem as bibliotecas utilizadas
  # pela integracao com o Teamcenter.
  $importerExecutablePath = $env:DCA_IMPORTER_PATH

  if ([string]::IsNullOrWhiteSpace($importerExecutablePath)) {
    throw ("DCA_IMPORTER_PATH deve ser configurado no arquivo .env.")
  }

  if (-not (Test-Path -LiteralPath $importerExecutablePath -PathType Leaf)) {
    throw "Importar GD nao encontrado em '$importerExecutablePath'."
  }

  return $importerExecutablePath
}

function Get-TeamcenterSettings {

  $teamcenterEnvironment =
  [string]$env:DCA_TC_ENV

  if (
    [string]::IsNullOrWhiteSpace(
      $teamcenterEnvironment
    )
  ) {

    throw (
      "DCA_TC_ENV nao foi configurado. " +
      "Use Teste ou Processo."
    )
  }

  $teamcenterEnvironment =
  $teamcenterEnvironment.Trim()

  $teamcenterServerUrl =
  $null

  $teamcenterUser =
  $null

  $teamcenterPassword =
  $null

  switch ($teamcenterEnvironment.ToLowerInvariant()) {

    "teste" {

      $teamcenterEnvironment =
      "Teste"

      $teamcenterServerUrl =
      [string]$env:DCA_TC_TEST_URL

      $teamcenterUser =
      [string]$env:DCA_TC_TEST_USER

      $teamcenterPassword =
      [string]$env:DCA_TC_TEST_PASSWORD
    }

    "processo" {

      $teamcenterEnvironment =
      "Processo"

      $teamcenterServerUrl =
      [string]$env:DCA_TC_PROCESS_URL

      $teamcenterUser =
      [string]$env:DCA_TC_PROCESS_USER

      $teamcenterPassword =
      [string]$env:DCA_TC_PROCESS_PASSWORD
    }

    default {

      throw (
        "Ambiente Teamcenter invalido: " +
        "'$teamcenterEnvironment'. " +
        "Use Teste ou Processo."
      )
    }
  }

  if (
    [string]::IsNullOrWhiteSpace(
      $teamcenterServerUrl
    )
  ) {

    throw (
      "A URL do Teamcenter nao foi configurada para " +
      "o ambiente '$teamcenterEnvironment'."
    )
  }

  if (
    [string]::IsNullOrWhiteSpace(
      $teamcenterUser
    )
  ) {

    throw (
      "O usuario do Teamcenter nao foi configurado para " +
      "o ambiente '$teamcenterEnvironment'."
    )
  }

  if (
    [string]::IsNullOrWhiteSpace(
      $teamcenterPassword
    )
  ) {

    $securePassword =
    Read-Host (
      "Senha do Teamcenter para '$teamcenterUser'"
    ) -AsSecureString

    $credential =
    New-Object `
      System.Net.NetworkCredential(
      "",
      $securePassword
    )

    $teamcenterPassword =
    $credential.Password
  }

  $parsedUri =
  $null

  $validUrl =
  [System.Uri]::TryCreate(
    $teamcenterServerUrl,
    [System.UriKind]::Absolute,
    [ref]$parsedUri
  )

  if (
    -not $validUrl -or
    $null -eq $parsedUri
  ) {

    throw (
      "URL invalida para o ambiente " +
      "'$teamcenterEnvironment': " +
      "'$teamcenterServerUrl'."
    )
  }

  $expectedHost =
  if ($teamcenterEnvironment -eq "Teste") {
    "perto30-novo.perto.com.br"
  }
  else {
    "perto37-novo.perto.com.br"
  }

  if (
    $parsedUri.Host -ine $expectedHost
  ) {

    throw (
      "A URL configurada nao corresponde ao ambiente. " +
      "Ambiente: '$teamcenterEnvironment'. " +
      "Servidor esperado: '$expectedHost'. " +
      "Servidor recebido: '$($parsedUri.Host)'."
    )
  }

  return [PSCustomObject]@{
    Url = $teamcenterServerUrl
    Host = $parsedUri.Host
    Environment = $teamcenterEnvironment
    User = $teamcenterUser
    Password = $teamcenterPassword
  }
}

function Connect-Teamcenter {

  # Reutiliza a sessao autenticada durante a mesma execucao.
  if (
    $null -ne $script:TeamcenterSession -and
    $null -ne $script:TeamcenterFunctions
  ) {

    return $script:TeamcenterSession
  }

  # Carrega o assembly do importador, cria a sessao e autentica
  # o usuario no ambiente configurado.
  $importerExecutablePath = Confirm-TeamcenterImporter
  $settings = Get-TeamcenterSettings
  $script:TeamcenterEnvironment = $settings.Environment

  Write-Host ""

  if ($settings.Environment -eq "Teste") {

    Write-Host (
      "  [AMBIENTE] Teamcenter de TESTES"
    ) -ForegroundColor Cyan
  }
  else {

    Write-Host (
      "  [AMBIENTE] Teamcenter de PROCESSO"
    ) -ForegroundColor Yellow
  }
  if ($Details) {

    Write-Host (
      "  Servidor: $($settings.Url)"
    ) -ForegroundColor Gray

    Write-Host (
      "  Usuario:  $($settings.User)"
    ) -ForegroundColor Gray
  }

  Write-Host ""

  $script:ImporterAssembly = [System.Reflection.Assembly]::LoadFrom($importerExecutablePath)

  if ($null -eq $script:ImporterAssembly) {
    throw "Nao foi possivel carregar o Importar GD."
  }

  $sessionType = $script:ImporterAssembly.GetType("Teamcenter.ClientX.Session")

  if ($null -eq $sessionType) {
    throw "Tipo Teamcenter.ClientX.Session nao encontrado."
  }

  $script:TeamcenterSession = [System.Activator]::CreateInstance($sessionType, @($settings.Url))

  if ($null -eq $script:TeamcenterSession) {
    throw "A sessao do Teamcenter retornou NULL."
  }

  $authenticatedUser = $script:TeamcenterSession.login(
    $settings.User,
    $settings.Password,
    "",
    "",
    "SoaAppX"
  )

  if ($null -eq $authenticatedUser) {
    throw "O login do Teamcenter retornou NULL."
  }

  $script:TeamcenterFunctions = $script:ImporterAssembly.GetType("ImportarGD.Controller.Functions")

  if ($null -eq $script:TeamcenterFunctions) {
    throw "ImportarGD.Controller.Functions nao encontrado."
  }

  Import-TeamcenterQueryAssemblies

  if ($Details) {

    Write-Host (
      "  Bibliotecas de consulta do Teamcenter carregadas."
    ) -ForegroundColor DarkGray
  }

  return $script:TeamcenterSession
}

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

function Get-TeamcenterMethod {
  # Localiza um metodo estatico do importador pelo nome e pela
  # quantidade de parametros esperada.
  param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$MethodName,

    [Parameter(Mandatory = $true)]
    [ValidateRange(0, 100)]
    [int]$ParameterCount
  )

  if ($null -eq $script:TeamcenterFunctions) {
    throw (
      "As funcoes do Teamcenter nao foram carregadas. " +
      "Execute Connect-Teamcenter primeiro."
    )
  }

  $method = $script:TeamcenterFunctions.GetMethods() |
    Where-Object {
    $_.Name -eq $MethodName -and
    $_.GetParameters().Count -eq $ParameterCount
  } |
    Select-Object -First 1

  if ($null -eq $method) {
    throw (
      "Metodo '$MethodName' com $ParameterCount parametro(s) " +
      "nao foi encontrado no Importar GD."
    )
  }

  return $method
}

function Get-TeamcenterConnection {

  # Recupera a conexao SOA mantida pela sessao autenticada.
  if ($null -eq $script:ImporterAssembly) {
    throw (
      "O assembly do Importar GD nao foi carregado. " +
      "Execute Connect-Teamcenter primeiro."
    )
  }

  $sessionType = $script:ImporterAssembly.GetType("Teamcenter.ClientX.Session")

  if ($null -eq $sessionType) {
    throw "Tipo Teamcenter.ClientX.Session nao encontrado."
  }

  $getConnectionMethod = $sessionType.GetMethod("getConnection")

  if ($null -eq $getConnectionMethod) {
    throw "Metodo Session.getConnection nao encontrado."
  }

  $connection = $getConnectionMethod.Invoke($null, @())

  if ($null -eq $connection) {
    throw "A conexao SOA do Teamcenter retornou NULL."
  }

  return $connection
}

function Import-TeamcenterQueryAssemblies {

  if ($Details) {

    Write-Host (
      "  Iniciando carregamento das bibliotecas de consulta..."
    ) -ForegroundColor Cyan
  }

  # Guarda diretamente os assemblies retornados pelo LoadFrom.
  $script:TeamcenterQueryAssemblies =
  [System.Collections.Generic.List[object]]::new()

  $importerExecutablePath =
  Confirm-TeamcenterImporter

  $importerFolder =
  [System.IO.Path]::GetDirectoryName(
    $importerExecutablePath
  )

  $queryAssemblyNames =
  @(
    "TcSoaQueryTypes.dll",
    "TcSoaQueryStrong.dll"
  )

  foreach ($queryAssemblyName in $queryAssemblyNames) {

    $queryAssemblyPath =
    Join-Path `
      -Path $importerFolder `
      -ChildPath $queryAssemblyName

    if (-not (
        Test-Path `
          -LiteralPath $queryAssemblyPath `
          -PathType Leaf
      )) {

      throw (
        "Biblioteca de consulta nao encontrada: " +
        "'$queryAssemblyPath'."
      )
    }

    try {

      $queryAssembly =
      [System.Reflection.Assembly]::LoadFrom(
        $queryAssemblyPath
      )

      if ($null -eq $queryAssembly) {

        throw (
          "Assembly.LoadFrom retornou NULL para " +
          "'$queryAssemblyName'."
        )
      }

      $script:TeamcenterQueryAssemblies.Add(
        $queryAssembly
      )

      if ($Details) {

        Write-Host (
          "  Biblioteca de consulta carregada: " +
          $queryAssemblyName
        ) -ForegroundColor Green

        Write-Host (
          "    Nome interno: " +
          $queryAssembly.GetName().Name
        ) -ForegroundColor DarkGray

        Write-Host (
          "    Local: " +
          $queryAssembly.Location
        ) -ForegroundColor DarkGray
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
        "Falha ao carregar '$queryAssemblyName': " +
        $realException.Message
      )
    }
  }

  if (
    $script:TeamcenterQueryAssemblies.Count -ne
    $queryAssemblyNames.Count
  ) {

    throw (
      "Nem todas as bibliotecas de consulta foram carregadas."
    )
  }
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

function Get-TeamcenterDataManagementService {

  # Localiza e instancia o servico SOA responsavel pela criacao
  # e pelo gerenciamento dos objetos do Teamcenter.
  $connection = Get-TeamcenterConnection

  $serviceType = [System.AppDomain]::CurrentDomain.GetAssemblies() |
    ForEach-Object {
    try {
      $_.GetType(
        "Teamcenter.Services.Strong.Core.DataManagementService",
        $false,
        $false
      )
    }
    catch {
      $null
    }
  } |
    Where-Object { $null -ne $_ } |
    Select-Object -First 1

  if ($null -eq $serviceType) {
    throw "Tipo DataManagementService nao encontrado."
  }

  $getServiceMethod = $serviceType.GetMethods() |
    Where-Object {
    $_.Name -eq "getService" -and
    $_.GetParameters().Count -eq 1
  } |
    Select-Object -First 1

  if ($null -eq $getServiceMethod) {
    throw "Metodo DataManagementService.getService nao encontrado."
  }

  $service = $getServiceMethod.Invoke($null, @($connection))

  if ($null -eq $service) {
    throw "DataManagementService retornou NULL."
  }

  return $service
}

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

function Test-DcaTeamcenterItemExists {

  # Verifica se o codigo possui uma revisao no Teamcenter.
  # Load_Item nao depende do filtro de empresa utilizado por getItem.
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

  # Tenta localizar diretamente a revisao com Load_Item.
  # Se Load_Item nao retornar resultado, tenta localizar o Item
  # com getItem e depois recupera sua revisao.
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

  # Quando Load_Item nao encontra o destino, tenta getItem
  # usando os valores de empresa configurados.
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

  # Terceira tentativa: pesquisa todos os Items com o mesmo codigo
  # e permite selecionar o destino correto.
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

# ============================================================
# OPERACOES SOBRE ITEM, REVISAO E PDF
# ============================================================
function Get-TeamcenterRevision {

  # Localiza a revisao associada ao Item informado.
  param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNull()]
    $Item
  )

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

  $itemBaseObject =
  $Item.PSObject.BaseObject

  if ($null -ne $itemBaseObject) {

    $Item =
    $itemBaseObject
  }

  $getRevisionMethod =
  Get-TeamcenterMethod `
    -MethodName "getItemRevisionfromItem" `
    -ParameterCount 1

  try {

    $revision =
    $getRevisionMethod.Invoke(
      $null,
      @($Item)
    )
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
      "Nao foi possivel recuperar a revisao do Item: " +
      $realException.Message
    )
  }

  if ($null -eq $revision) {

    return $null
  }

  $revisionBaseObject =
  $revision.PSObject.BaseObject

  if ($null -ne $revisionBaseObject) {

    $revision =
    $revisionBaseObject
  }

  return $revision
}

# ============================================================
# IMPORTACAO DO PDF
# ============================================================
function Import-TeamcenterPdf {

  # Valida o arquivo e chama o metodo do Importar GD que cria
  # o Dataset PDF associado a revisao do Teamcenter.
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

  $revisionBaseObject =
  $Revision.PSObject.BaseObject

  if ($null -ne $revisionBaseObject) {

    $Revision =
    $revisionBaseObject
  }

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

  $importMethod =
  Get-TeamcenterMethod `
    -MethodName "ImportarPDF" `
    -ParameterCount 5

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

  try {

    $importResult =
    $importMethod.Invoke(
      $null,
      $invokeArguments
    )
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
      "Falha ao importar o PDF para '$ItemCode': " +
      $realException.Message
    )
  }

  return $importResult
}

# ============================================================
# TRATAMENTO DAS RESPOSTAS SOA
# ============================================================
function Get-TeamcenterServiceErrors {

  # Converte os erros parciais do servico SOA em mensagens
  # legiveis para o log da importacao.
  param(
    $ServiceData
  )

  $errorMessages =
  [System.Collections.Generic.List[string]]::new()

  if ($null -eq $ServiceData) {

    return $errorMessages.ToArray()
  }

  $serviceDataType =
  $ServiceData.GetType()

  $sizeMethod =
  $serviceDataType.GetMethods() |
    Where-Object {
    $_.Name -match
    '^(?i)SizeOfPartialErrors$' -and
    $_.GetParameters().Count -eq 0
  } |
    Select-Object -First 1

  $getErrorMethod =
  $serviceDataType.GetMethods() |
    Where-Object {
    $_.Name -match
    '^(?i)GetPartialError$' -and
    $_.GetParameters().Count -eq 1
  } |
    Select-Object -First 1

  if (
    $null -eq $sizeMethod -or
    $null -eq $getErrorMethod
  ) {

    return $errorMessages.ToArray()
  }

  try {

    $errorCount =
    [int]$sizeMethod.Invoke(
      $ServiceData,
      @()
    )

    for (
      $errorIndex = 0
      $errorIndex -lt $errorCount
      $errorIndex++
    ) {

      $partialError =
      $getErrorMethod.Invoke(
        $ServiceData,
        @([int]$errorIndex)
      )

      if ($null -eq $partialError) {
        continue
      }

      $errorValuesProperty =
      $partialError.GetType().GetProperty(
        "ErrorValues"
      )

      if ($null -ne $errorValuesProperty) {

        $errorValues =
        @(
          $errorValuesProperty.GetValue(
            $partialError,
            $null
          )
        )

        foreach ($errorValue in $errorValues) {

          if ($null -eq $errorValue) {
            continue
          }

          $messageProperty =
          $errorValue.GetType().GetProperty(
            "Message"
          )

          if ($null -eq $messageProperty) {
            continue
          }

          $messageText =
          [string]$messageProperty.GetValue(
            $errorValue,
            $null
          )

          if (
            -not [string]::IsNullOrWhiteSpace(
              $messageText
            )
          ) {

            $errorMessages.Add(
              $messageText.Trim()
            )
          }
        }
      }
      else {

        $partialErrorText =
        ([string]$partialError).Trim()

        if (
          -not [string]::IsNullOrWhiteSpace(
            $partialErrorText
          )
        ) {

          $errorMessages.Add(
            $partialErrorText
          )
        }
      }
    }
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
        "Nao foi possivel interpretar os erros SOA: " +
        $realException.Message
      )
    }
  }

  return $errorMessages.ToArray()
}

function Start-TeamcenterWorkflow {

  # Cria a lista esperada pelo Importar GD e solicita o inicio
  # do workflow para a revisao criada.
  param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$WorkflowTemplate,

    [Parameter(Mandatory = $true)]
    $Revision
  )

  $workflowTemplateClean =
  $WorkflowTemplate.Trim()

  if (
    [string]::IsNullOrWhiteSpace(
      $workflowTemplateClean
    )
  ) {

    throw "O nome do workflow ficou vazio."
  }

  if ($null -eq $Revision) {

    throw (
      "A revisao nao foi fornecida para iniciar o workflow."
    )
  }

  if ($null -eq $script:TeamcenterFunctions) {

    throw (
      "As funcoes do Teamcenter nao foram carregadas. " +
      "Execute Connect-Teamcenter primeiro."
    )
  }

  $revisionBaseObject =
  $Revision.PSObject.BaseObject

  if ($null -ne $revisionBaseObject) {

    $Revision =
    $revisionBaseObject
  }

  $revisionTypeName =
  $Revision.GetType().FullName

  $isRevisionObject =
  $revisionTypeName -match
  '(?i)(ItemRevision|Revision)$'

  if (-not $isRevisionObject) {

    throw (
      "O objeto recebido nao e uma revisao valida. " +
      "Tipo recebido: '$revisionTypeName'."
    )
  }

  $workflowMethod =
  $script:TeamcenterFunctions.GetMethods() |
    Where-Object {
    $_.Name -eq "Start_Workflow" -and
    $_.GetParameters().Count -eq 2
  } |
    Select-Object -First 1

  if ($null -eq $workflowMethod) {

    throw (
      "Metodo Start_Workflow com 2 parametros " +
      "nao encontrado no Importar GD."
    )
  }

  $workflowParameters =
  $workflowMethod.GetParameters()

  $revisionListType =
  $workflowParameters[1].ParameterType

  if ($null -eq $revisionListType) {

    throw (
      "O tipo da lista de revisoes do workflow " +
      "nao foi identificado."
    )
  }

  $revisionList =
  [System.Activator]::CreateInstance(
    $revisionListType
  )

  if ($null -eq $revisionList) {

    throw (
      "Nao foi possivel criar a lista de revisoes " +
      "para o workflow."
    )
  }

  $addMethod =
  $revisionListType.GetMethods() |
    Where-Object {
    $_.Name -eq "Add" -and
    $_.GetParameters().Count -eq 1
  } |
    Select-Object -First 1

  if ($null -eq $addMethod) {

    throw (
      "Metodo Add nao encontrado na lista de revisoes."
    )
  }

  $null =
  $addMethod.Invoke(
    $revisionList,
    @($Revision)
  )

  $workflowArguments =
  New-Object "System.Object[]" 2

  $workflowArguments[0] =
  [string]$workflowTemplateClean

  $workflowArguments[1] =
  $revisionList

  try {

    $null =
    $workflowMethod.Invoke(
      $null,
      $workflowArguments
    )
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
      "Falha ao iniciar o workflow " +
      "'$workflowTemplateClean': " +
      $realException.Message
    )
  }
}

function New-DcaTeamcenterItem {

  # Monta a solicitacao CreateObjects, envia o Item e a revisao
  # ao Teamcenter e retorna os objetos efetivamente criados.
  param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$SourceCode,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$ItemName,

    [string]$ClientRevision,

    [Parameter(Mandatory = $true)]
    [ValidateSet("Original", "Processo", "NormaExterna")]
    [string]$DocumentType
  )

  $duplicatePattern = '(?i)already exists|ja existe|duplicate|not unique|is not unique'

  $sourceCodeClean = $SourceCode.Trim().ToUpper()
  $itemNameClean = $ItemName.Trim()

  if ([string]::IsNullOrWhiteSpace($sourceCodeClean)) {
    throw "SourceCode ficou vazio."
  }

  if ([string]::IsNullOrWhiteSpace($itemNameClean)) {
    throw "ItemName ficou vazio."
  }

  if (
    [string]::IsNullOrWhiteSpace(
      $script:TeamcenterEnvironment
    )
  ) {

    throw (
      "O ambiente do Teamcenter ainda nao foi identificado. " +
      "Execute Connect-Teamcenter antes da criacao."
    )
  }

  $typeConfiguration =
  Get-DcaTypeConfiguration `
    -DocumentType $DocumentType `
    -ClientRevision $ClientRevision `
    -TeamcenterEnvironment $script:TeamcenterEnvironment

  if ($Details) {

    Write-Host ""

    Write-Host (
      "  Ambiente Teamcenter: " +
      "$($typeConfiguration.Environment)"
    ) -ForegroundColor Gray

    Write-Host (
      "  Tipo do Item:        " +
      "$($typeConfiguration.ItemType)"
    ) -ForegroundColor Gray

    Write-Host (
      "  Tipo da Revisao:     " +
      "$($typeConfiguration.RevisionType)"
    ) -ForegroundColor Gray
  }

  $itemType =$typeConfiguration.ItemType
  $revisionType = $typeConfiguration.RevisionType
  $clientProperty = $typeConfiguration.ClientProperty
  $clientValue = $typeConfiguration.ClientValue
  $teamcenterRevisionId = $typeConfiguration.TeamcenterRevisionId
  $revisionExtraProperties = $typeConfiguration.RevisionProperties

  if ([string]::IsNullOrWhiteSpace($teamcenterRevisionId)) {
    throw "Revision ID ficou vazio para '$DocumentType'."
  }

  $dataManagementService = Get-TeamcenterDataManagementService

  $createObjectsMethod = $dataManagementService.GetType().GetMethods() |
    Where-Object {
    $_.Name -eq "CreateObjects" -and
    $_.GetParameters().Count -eq 1
  } |
    Select-Object -First 1

  if ($null -eq $createObjectsMethod) {
    throw "Metodo CreateObjects nao encontrado."
  }

  $createInArrayType = $createObjectsMethod.GetParameters()[0].ParameterType

  if (-not $createInArrayType.IsArray) {
    throw "O parametro de CreateObjects nao e um array."
  }

  $createInType = $createInArrayType.GetElementType()

  if ($null -eq $createInType) {
    throw "Tipo CreateIn nao identificado."
  }

  $createInputField = $createInType.GetField(
    "Data",
    [System.Reflection.BindingFlags]::Public -bor
    [System.Reflection.BindingFlags]::Instance -bor
    [System.Reflection.BindingFlags]::IgnoreCase
  )

  if ($null -eq $createInputField) {
    throw "Campo Data nao encontrado em CreateIn."
  }

  $createInputType = $createInputField.FieldType

  if ($null -eq $createInputType) {
    throw "Tipo do CreateInput nao identificado."
  }

  $candidateCode = $sourceCodeClean

  # Propriedades adicionais por tipo:
  # Original: gd5revcliente.
  # Processo: gd5revcliente e gd5revinterna.
  # Norma Externa: nenhuma propriedade adicional.
  $revisionProperties = @{
    "item_revision_id" = $teamcenterRevisionId
    "object_name" = $itemNameClean
    "object_desc" = $itemNameClean
  }

  foreach ($extraKey in $revisionExtraProperties.Keys) {
    $revisionProperties[$extraKey] =
    $revisionExtraProperties[$extraKey]
  }

  $integerPropertyNames =
  @(Get-DcaIntegerPropertyNames)

  $revisionInput =
  New-DcaCreateInputObject `
    -InputType $createInputType `
    -BoName $revisionType `
    -Properties $revisionProperties `
    -IntegerPropertyNames $integerPropertyNames

  if ($null -eq $revisionInput) {

    throw (
      "revisionInput ficou NULL para o tipo " +
      "'$revisionType'."
    )
  }
  if ($Details) {
    Write-Host (
      "  revisionInput criado: " +
      $revisionInput.GetType().FullName
    ) -ForegroundColor DarkGray

    Write-Host (
      "  BoName da revisao: " +
      [string]$revisionInput.BoName
    ) -ForegroundColor DarkGray

    Write-Host (
      "  Propriedades da revisao:"
    ) -ForegroundColor Cyan

    foreach (
      $revisionPropertyName in (
        $revisionInput.StringProps.Keys |
          Sort-Object
      )
    ) {

      Write-Host (
        "    {0} = '{1}'" -f
        $revisionPropertyName,
        $revisionInput.StringProps[$revisionPropertyName]
      ) -ForegroundColor Gray
    }
  }
  if (
    $Details -and
    $null -ne $revisionInput.IntProps
  ) {

    foreach (
      $integerPropertyName in (
        $revisionInput.IntProps.Keys |
          Sort-Object
      )
    ) {

      Write-Host (
        "    {0} = {1}  (inteiro)" -f
        $integerPropertyName,
        $revisionInput.IntProps[$integerPropertyName]
      ) -ForegroundColor Gray
    }
  }

  # O nome preparado pelo script e aplicado ao Item e a revisao
  # como nome e descricao.
  $itemProperties = @{
    "item_id"     = $candidateCode
    "object_name" = $itemNameClean
    "object_desc" = $itemNameClean
  }

  if (
    -not [string]::IsNullOrWhiteSpace(
      [string]$clientProperty
    ) -and
    -not [string]::IsNullOrWhiteSpace(
      [string]$clientValue
    )
  ) {

    $itemProperties[$clientProperty] =
    $clientValue
  }

  if ($Details) {

    Write-Host (
      "  Propriedades do Item:"
    ) -ForegroundColor Cyan

    foreach (
      $itemPropertyName in (
        $itemProperties.Keys |
          Sort-Object
      )
    ) {

      Write-Host (
        "    {0} = '{1}'" -f
        $itemPropertyName,
        $itemProperties[$itemPropertyName]
      ) -ForegroundColor Gray
    }
  }
  $itemInput =
  New-DcaCreateInputObject `
    -InputType $createInputType `
    -BoName $itemType `
    -Properties $itemProperties

  if ($null -eq $itemInput) {

    throw (
      "itemInput ficou NULL para o tipo " +
      "'$itemType'."
    )
  }
  $revisionInputArray = [System.Array]::CreateInstance($createInputType, 1)
  $revisionInputArray.SetValue($revisionInput, 0)

  $compoundInput = New-Object System.Collections.Hashtable
  $compoundInput["revision"] = $revisionInputArray

  if ($Details) {

    Write-Host (
      "  Tipo tecnico do CreateInput: " +
      $itemInput.GetType().FullName
    ) -ForegroundColor DarkGray
  }
  Set-DcaObjectMemberValue `
    -InputObject $itemInput `
    -MemberName "CompoundCreateInput" `
    -Value $compoundInput

  $createIn = [System.Activator]::CreateInstance($createInType)

  if ($null -eq $createIn) {
    throw "Nao foi possivel criar createIn."
  }

  $createIn.ClientId = [string]"CreateDcaItem"
  $createIn.Data = $itemInput

  $createInArray = [System.Array]::CreateInstance($createInType, 1)
  $createInArray.SetValue($createIn, 0)

  $revisionSent = $revisionInput

  if ($null -eq $revisionSent) {
    throw "revisionSent ficou NULL."
  }

  # Valida as propriedades depois da separacao entre StringProps
  # e IntProps, antes de chamar o CreateObjects.
  if ($DocumentType -eq "Processo") {

    $revisionClient =
    ([string]$revisionSent.StringProps["gd5revcliente"]).Trim()

    $revisionInternal =
    Get-DcaCreateInputPropertyText `
      -InputObject $revisionSent `
      -PropertyName "gd5revinterna"

    $finalRevisionId =
    ([string]$revisionSent.StringProps["item_revision_id"]).Trim()

    if (
      [string]::IsNullOrWhiteSpace(
        $revisionClient
      )
    ) {

      throw (
        "gd5revcliente ficou vazio no objeto de revisao " +
        "antes do CreateObjects."
      )
    }

    if (
      $revisionClient -notmatch
      '^[A-Z0-9-]{1,2}$'
    ) {

      throw (
        "gd5revcliente possui valor invalido: " +
        "'$revisionClient'."
      )
    }

    if (
      [string]::IsNullOrWhiteSpace(
        $revisionInternal
      )
    ) {

      throw (
        "gd5revinterna ficou vazio no objeto de revisao " +
        "antes do CreateObjects."
      )
    }

    if (
      $revisionInternal -notmatch
      '^[0-9]$'
    ) {

      throw (
        "gd5revinterna possui valor invalido: " +
        "'$revisionInternal'. Era esperado um digito."
      )
    }

    if (
      [string]::IsNullOrWhiteSpace(
        $finalRevisionId
      )
    ) {

      throw (
        "item_revision_id ficou vazio no objeto de revisao " +
        "antes do CreateObjects."
      )
    }
    if ($Details) {

      Write-Host (
        "  Dados da revisao que serao enviados:"
      ) -ForegroundColor Cyan

      Write-Host (
        "    item_revision_id = '$finalRevisionId'"
      ) -ForegroundColor Gray

      Write-Host (
        "    gd5revcliente    = '$revisionClient'"
      ) -ForegroundColor Gray

      Write-Host (
        "    gd5revinterna    = '$revisionInternal'"
      ) -ForegroundColor Gray
    }
  }
  foreach ($extraKey in $revisionExtraProperties.Keys) {
    $extraValueText =
    Get-DcaCreateInputPropertyText `
      -InputObject $revisionSent `
      -PropertyName $extraKey

    if ([string]::IsNullOrWhiteSpace($extraValueText)) {
      throw "A propriedade '$extraKey' ficou vazia na revisao."
    }
  }

  # A sequencia e controlada automaticamente pelo Teamcenter.
  # O importador nao deve enviar sequence_id.
  if ($revisionSent.StringProps.ContainsKey("sequence_id")) {
    throw "sequence_id nao deve ser enviado."
  }

  $invokeArguments = New-Object "System.Object[]" 1
  $invokeArguments[0] = $createInArray

  # A chamada abaixo pode efetivamente criar objetos no Teamcenter.
  # Todas as validacoes locais devem ocorrer antes deste ponto.
  $createResponse = $null

  try {
    $createResponse =
    $createObjectsMethod.Invoke(
      $dataManagementService,
      $invokeArguments
    )
  }
  catch {

    $realException = $_.Exception

    while ($null -ne $realException.InnerException) {
      $realException = $realException.InnerException
    }

    $errorMessage = $realException.Message

    if ($errorMessage -match $duplicatePattern) {
      throw "O item '$candidateCode' ja existe no Teamcenter."
    }

    throw "Falha ao executar CreateObjects para '$candidateCode': $errorMessage"
  }

  if ($null -eq $createResponse) {
    throw "CreateObjects retornou NULL."
  }

  $serviceData = $createResponse.ServiceData
  $serviceErrors = @(Get-TeamcenterServiceErrors -ServiceData $serviceData)

  if ($serviceErrors.Count -gt 0) {

    $joinedErrors = $serviceErrors -join " | "

    if ($joinedErrors -match $duplicatePattern) {
      throw "O item '$candidateCode' ja existe no Teamcenter."
    }

    throw "O Teamcenter rejeitou a criacao: $joinedErrors"
  }

  # A resposta pode conter Item, revisao e objetos auxiliares.
  # Somente o Item e a revisao sao retornados ao fluxo principal.
  $createdObjects =
  @(
    Get-DcaCreatedObjects `
      -CreateResponse $createResponse `
      -ServiceData $serviceData
  )

  $createdItem =
  $createdObjects |
    Where-Object {

    $null -ne $_ -and
    (
      $_.GetType().Name -eq "Item" -or
      $_.GetType().FullName -match '\.Item$'
    )
  } |
    Select-Object -First 1

  $createdRevision =
  $createdObjects |
    Where-Object {

    if ($null -eq $_) {
      return $false
    }

    $createdObjectTypeName =
    $_.GetType().FullName

    $createdObjectTypeName -match
    '(?i)(ItemRevision|Revision)$'
  } |
    Select-Object -First 1

  if ($null -eq $createdItem) {
    throw (
      "CreateObjects nao retornou o Item criado. " +
      "Objetos retornados: $($createdObjects.Count)."
    )
  }

  $itemBaseObject = $createdItem.PSObject.BaseObject

  if ($null -ne $itemBaseObject) {
    $createdItem = $itemBaseObject
  }

  if ($null -ne $createdRevision) {

    $revisionBaseObject = $createdRevision.PSObject.BaseObject

    if ($null -ne $revisionBaseObject) {
      $createdRevision = $revisionBaseObject
    }
  }

  return [PSCustomObject]@{
    Code = $candidateCode
    Item = $createdItem
    Revision = $createdRevision
  }
}
