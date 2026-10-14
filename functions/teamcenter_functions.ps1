$script:ImporterAssembly = $null
$script:TeamcenterSession = $null
$script:TeamcenterFunctions = $null
$script:TeamcenterEnvironment = $null
$script:TeamcenterHost = $null
# Helpers for loading the .NET importer and executing Teamcenter operations.

function Confirm-TeamcenterImporter {

  # Confirm the executable used by the integration.
  $importerExecutablePath = $env:DCA_IMPORTER_PATH

  if ([string]::IsNullOrWhiteSpace($importerExecutablePath)) {
    throw "DCA_IMPORTER_PATH must be configured."
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

  # Load the assembly, create a session, and authenticate with Teamcenter.
  $importerExecutablePath = Confirm-TeamcenterImporter
  $settings = Get-TeamcenterSettings
  $script:TeamcenterEnvironment = $settings.Environment

  $script:TeamcenterHost = $settings.Host

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

  return $script:TeamcenterSession
}

function Get-TeamcenterMethod {

  # Find an importer static method by name and parameter count.
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

  # Get the SOA connection maintained by the Teamcenter session.
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

function Get-TeamcenterDataManagementService {

  # Locate and instantiate the SOA data-management service.
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

function Get-TeamcenterRevision {

  # Get the revision associated with the supplied item.
  param(
    [Parameter(Mandatory = $true)]
    $Item
  )

  if ($null -eq $Item) {
    throw "O item do Teamcenter nao foi fornecido."
  }

  $getRevisionMethod = Get-TeamcenterMethod -MethodName "getItemRevisionfromItem" -ParameterCount 1

  $revision = $getRevisionMethod.Invoke($null, @($Item))

  return $revision
}

function Import-TeamcenterPdf {

  param(
    [Parameter(Mandatory = $true)]
    $Revision,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$ItemCode,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$DatasetRevision,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$FilePath
  )

  if ($null -eq $Revision) {
    throw "A revisao do item '$ItemCode' nao foi fornecida."
  }

  if (-not (
      Test-Path `
        -LiteralPath $FilePath `
        -PathType Leaf
    )) {

    throw "PDF nao encontrado em '$FilePath'."
  }

  if (
    [System.IO.Path]::GetExtension(
      $FilePath
    ) -ine ".pdf"
  ) {

    throw "O arquivo informado nao possui extensao PDF."
  }

  $revisionBaseObject =
  $Revision.PSObject.BaseObject

  if ($null -ne $revisionBaseObject) {
    $Revision = $revisionBaseObject
  }

  $revisionTypeName =
  $Revision.GetType().FullName

  if ($revisionTypeName -notmatch "ItemRevision") {

    throw (
      "A revisao recebida nao e um ItemRevision valido. " +
      "Tipo recebido: '$revisionTypeName'."
    )
  }

  $datasetId =
  $ItemCode.Trim()

  $datasetRevisionClean =
  $DatasetRevision.Trim().ToUpperInvariant()

  if (
    [string]::IsNullOrWhiteSpace(
      $datasetId
    )
  ) {

    throw "DatasetId ficou vazio para '$ItemCode'."
  }

  if (
    [string]::IsNullOrWhiteSpace(
      $datasetRevisionClean
    )
  ) {

    throw "DatasetRev ficou vazio para '$ItemCode'."
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

  try {

    return $importMethod.Invoke(
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
}

function Get-TeamcenterServiceErrors {

  # Convert service partial errors into text messages.
  param(
    $ServiceData
  )

  $errorMessages = [System.Collections.Generic.List[string]]::new()

  if ($null -eq $ServiceData) {
    return $errorMessages.ToArray()
  }

  $serviceDataType = $ServiceData.GetType()

  $sizeMethod = $serviceDataType.GetMethods() |
    Where-Object { $_.Name -match '(?i)sizeofpartialerrors' } |
    Select-Object -First 1

  $getErrorMethod = $serviceDataType.GetMethods() |
    Where-Object { $_.Name -match '(?i)getpartialerror$' } |
    Select-Object -First 1

  if ($null -eq $sizeMethod -or $null -eq $getErrorMethod) {
    return $errorMessages.ToArray()
  }

  $errorCount = $sizeMethod.Invoke($ServiceData, @())

  for ($errorIndex = 0; $errorIndex -lt $errorCount; $errorIndex++) {

    $partialError = $getErrorMethod.Invoke($ServiceData, @($errorIndex))

    if ($null -eq $partialError) {
      continue
    }

    $errorStackProperty = $partialError.GetType().GetProperty("ErrorValues")

    if ($null -ne $errorStackProperty) {

      $errorValues = $errorStackProperty.GetValue($partialError)

      foreach ($errorValue in $errorValues) {

        $messageProperty = $errorValue.GetType().GetProperty("Message")

        if ($null -ne $messageProperty) {
          $errorMessages.Add([string]$messageProperty.GetValue($errorValue))
        }
      }
    }
    else {
      $errorMessages.Add($partialError.ToString())
    }
  }

  return $errorMessages.ToArray()
}

function Get-DcaClientRevisionInfo {

  # Normalize the client revision and separate its internal suffix, when present.
  param(
    [string]$ClientRevision
  )

  $value = ([string]$ClientRevision).Trim().ToUpper()
  $revision = $value

  if ($value -match '^(?<Revision>[A-Z0-9]{1,10})A[0-4]$') {
    $revision = $Matches["Revision"]
  }

  return [PSCustomObject]@{
    Original = $value
    Revision = $revision
  }
}

function Get-DcaTypeConfiguration {

  param(
    [Parameter(Mandatory = $true)]
    [ValidateSet(
      "Original",
      "Processo",
      "NormaExterna"
    )]
    [string]$DocumentType,

    [string]$ClientRevision,

    [ValidateSet(
      "Teste",
      "Processo"
    )]
    [string]$TeamcenterEnvironment
  )
  if (
    [string]::IsNullOrWhiteSpace(
      $TeamcenterEnvironment
    )
  ) {

    if (
      -not [string]::IsNullOrWhiteSpace(
        $script:TeamcenterEnvironment
      )
    ) {

      $TeamcenterEnvironment = $script:TeamcenterEnvironment
    }
    else {

      $teamcenterSettings = Get-TeamcenterSettings

      $TeamcenterEnvironment = [string]$teamcenterSettings.Environment
    }
  }

  if (
    $TeamcenterEnvironment -notin @(
      "Teste",
      "Processo"
    )
  ) {

    throw (
      "O ambiente do Teamcenter nao foi identificado. " +
      "Ambiente recebido: '$TeamcenterEnvironment'."
    )
  }
  $processTypes = @{

    Original = @{
      ItemType = $env:DCA_TC_PROCESS_ORIGINAL_ITEM_TYPE
      RevisionType = $env:DCA_TC_PROCESS_ORIGINAL_REVISION_TYPE
      ClientProperty = $env:DCA_TC_PROCESS_ORIGINAL_CLIENT_PROPERTY
      ClientValue = $env:DCA_TC_PROCESS_ORIGINAL_CLIENT_VALUE
    }

    Processo = @{
      ItemType = $env:DCA_TC_PROCESS_PROCESS_ITEM_TYPE
      RevisionType = $env:DCA_TC_PROCESS_PROCESS_REVISION_TYPE
      ClientProperty = $env:DCA_TC_PROCESS_PROCESS_CLIENT_PROPERTY
      ClientValue = $env:DCA_TC_PROCESS_PROCESS_CLIENT_VALUE
    }

    NormaExterna = @{
      ItemType = $env:DCA_TC_PROCESS_STANDARD_ITEM_TYPE
      RevisionType = $env:DCA_TC_PROCESS_STANDARD_REVISION_TYPE
      ClientProperty = $env:DCA_TC_PROCESS_STANDARD_CLIENT_PROPERTY
      ClientValue = $env:DCA_TC_PROCESS_STANDARD_CLIENT_VALUE
    }
  }

  $testTypes = @{

    Original = @{
      ItemType = $env:DCA_TC_TEST_ORIGINAL_ITEM_TYPE
      RevisionType = $env:DCA_TC_TEST_ORIGINAL_REVISION_TYPE
      ClientProperty = $env:DCA_TC_TEST_ORIGINAL_CLIENT_PROPERTY
      ClientValue = $env:DCA_TC_TEST_ORIGINAL_CLIENT_VALUE
    }

    Processo = @{
      ItemType = $env:DCA_TC_TEST_PROCESS_ITEM_TYPE
      RevisionType = $env:DCA_TC_TEST_PROCESS_REVISION_TYPE
      ClientProperty = $env:DCA_TC_TEST_PROCESS_CLIENT_PROPERTY
      ClientValue = $env:DCA_TC_TEST_PROCESS_CLIENT_VALUE
    }

    NormaExterna = @{
      ItemType = $env:DCA_TC_TEST_STANDARD_ITEM_TYPE
      RevisionType = $env:DCA_TC_TEST_STANDARD_REVISION_TYPE
      ClientProperty = $env:DCA_TC_TEST_STANDARD_CLIENT_PROPERTY
      ClientValue = $env:DCA_TC_TEST_STANDARD_CLIENT_VALUE
    }
  }
  if ($TeamcenterEnvironment -eq "Processo") {

    $selectedTypes = $processTypes
  }
  elseif ($TeamcenterEnvironment -eq "Teste") {

    $selectedTypes = $testTypes
  }
  else {

    throw (
      "Ambiente Teamcenter nao suportado: " +
      "'$TeamcenterEnvironment'."
    )
  }

  if (-not $selectedTypes.ContainsKey($DocumentType)) {

    throw (
      "Tipo de documento '$DocumentType' nao configurado " +
      "para o ambiente '$TeamcenterEnvironment'."
    )
  }

  $selectedDocumentTypes = $selectedTypes[$DocumentType]

  $itemType = [string]$selectedDocumentTypes.ItemType

  $revisionType = [string]$selectedDocumentTypes.RevisionType

  $clientProperty = [string]$selectedDocumentTypes.ClientProperty

  $clientValue = [string]$selectedDocumentTypes.ClientValue

  # Prevent creation when the configured type names are missing.
  if (
    [string]::IsNullOrWhiteSpace($itemType) -or
    $itemType -like "<*>"
  ) {

    throw (
      "ItemType de '$DocumentType' ainda nao foi " +
      "configurado para o ambiente " +
      "'$TeamcenterEnvironment'."
    )
  }

  if (
    [string]::IsNullOrWhiteSpace($revisionType) -or
    $revisionType -like "<*>"
  ) {

    throw (
      "RevisionType de '$DocumentType' ainda nao foi " +
      "configurado para o ambiente " +
      "'$TeamcenterEnvironment'."
    )
  }

  if ($DocumentType -eq "Original") {

    $info = Get-DcaClientRevisionInfo `
      -ClientRevision $ClientRevision

    if (
      [string]::IsNullOrWhiteSpace(
        $info.Revision
      )
    ) {

      throw (
        "ClientRevision ficou vazia para " +
        "'$DocumentType'."
      )
    }

    if ($info.Revision.Length -gt 5) {

      throw (
        "Revisao Cliente '$($info.Revision)' possui " +
        "$($info.Revision.Length) caracteres. " +
        "O limite configurado e 5."
      )
    }

    return [PSCustomObject]@{
      Environment = $TeamcenterEnvironment
      ItemType = $itemType
      RevisionType = $revisionType
      ClientProperty = $clientProperty
      ClientValue = $clientValue
      TeamcenterRevisionId = $info.Revision

      RevisionProperties = @{
        "gd5revcliente" = $info.Revision
      }
    }
  }

  if ($DocumentType -eq "Processo") {

    $processValueRaw =
    ([string]$ClientRevision).Trim().ToUpperInvariant()

    $clientRevisionValue =
    $null

    $internalRevisionValue =
    $null

    $processValue =
    $null

    # Formato do cartao:
    # AH-3, EB-2, FC-5.
    $processRevisionWithSeparatorRegex =
    [System.Text.RegularExpressions.Regex]::new(
      '^([A-Z0-9]{2})-([0-9])$'
    )

    # Formato antigo:
    # AH3, EB2, FC5 ou --4.
    $processRevisionWithoutSeparatorRegex =
    [System.Text.RegularExpressions.Regex]::new(
      '^([A-Z0-9-]{1,2})([0-9])$'
    )

    $processRevisionWithSeparatorMatch =
    $processRevisionWithSeparatorRegex.Match(
      $processValueRaw
    )

    $processRevisionWithoutSeparatorMatch =
    $processRevisionWithoutSeparatorRegex.Match(
      $processValueRaw
    )

    if ($processRevisionWithSeparatorMatch.Success) {

      $clientRevisionValue =
      $processRevisionWithSeparatorMatch.Groups[1].Value

      $internalRevisionValue =
      $processRevisionWithSeparatorMatch.Groups[2].Value
    }
    elseif ($processRevisionWithoutSeparatorMatch.Success) {

      $clientRevisionValue =
      $processRevisionWithoutSeparatorMatch.Groups[1].Value

      $internalRevisionValue =
      $processRevisionWithoutSeparatorMatch.Groups[2].Value
    }
    else {

      throw (
        "A revisao '$processValueRaw' nao segue o padrao " +
        "de DCA Processo. Formatos aceitos: AH-3, AH3, " +
        "BA-4, BA4 ou --4."
      )
    }

    $clientRevisionValue =
    ([string]$clientRevisionValue).Trim().ToUpperInvariant()

    $internalRevisionValue =
    ([string]$internalRevisionValue).Trim()

    if (
      $clientRevisionValue -notmatch
      '^[A-Z0-9-]{1,2}$'
    ) {

      throw (
        "A revisao cliente '$clientRevisionValue' e invalida."
      )
    }

    if (
      $internalRevisionValue -notmatch
      '^[0-9]$'
    ) {

      throw (
        "A revisao interna '$internalRevisionValue' e invalida. " +
        "Era esperado exatamente um digito."
      )
    }

    $processValue =
    $clientRevisionValue + $internalRevisionValue
    if ($Details) {

      Write-Host (
        "  Revisao recebida do cartao: " +
        "[$processValueRaw]"
      ) -ForegroundColor DarkGray

      Write-Host (
        "  Revisao cliente: " +
        "[$clientRevisionValue]"
      ) -ForegroundColor DarkGray

      Write-Host (
        "  Revisao interna: " +
        "[$internalRevisionValue]"
      ) -ForegroundColor DarkGray

      Write-Host (
        "  Revision ID do Teamcenter: " +
        "[$processValue]"
      ) -ForegroundColor Cyan
    }
    return [PSCustomObject]@{
      Environment = $TeamcenterEnvironment
      ItemType = $itemType
      RevisionType = $revisionType
      ClientProperty = $clientProperty
      ClientValue = $clientValue
      TeamcenterRevisionId = $processValue

      RevisionProperties = @{
        "gd5revcliente" = $clientRevisionValue
        "gd5revinterna" = $internalRevisionValue
      }
    }
  }
  if ($DocumentType -eq "NormaExterna") {

    $standardRevision =
    ([string]$ClientRevision).Trim().ToUpperInvariant()

    if (
      [string]::IsNullOrWhiteSpace(
        $standardRevision
      )
    ) {

      throw (
        "A revisao da Norma Externa ficou vazia."
      )
    }

    if (
      $standardRevision -notmatch
      '^[A-Z0-9.-]{1,10}$'
    ) {

      throw (
        "A revisao da Norma Externa possui formato invalido: " +
        "'$standardRevision'."
      )
    }

    return [PSCustomObject]@{
      Environment = $TeamcenterEnvironment
      ItemType = $itemType
      RevisionType = $revisionType
      ClientProperty = $clientProperty
      ClientValue = $clientValue
      TeamcenterRevisionId = $standardRevision
      RevisionProperties = @{}
    }
  }
  throw (
    "Tipo de documento nao suportado: " +
    "'$DocumentType'."
  )
}
function Start-TeamcenterWorkflow {

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

  if ($revisionTypeName -notmatch "ItemRevision") {

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
function Get-DcaIntegerPropertyNames {

  # Propriedades que o Teamcenter espera como INTEIRO (IntProps).
  # Padrao: gd5revinterna. Para desligar, use DCA_TC_INTEGER_PROPERTIES=none
  $configuredValue =
  ([string]$env:DCA_TC_INTEGER_PROPERTIES).Trim()

  if ([string]::IsNullOrWhiteSpace($configuredValue)) {
    return @("gd5revinterna")
  }

  if ($configuredValue -ieq "none") {
    return @()
  }

  $names =
  [System.Collections.Generic.List[string]]::new()

  foreach ($part in ($configuredValue -split '[|;,]')) {

    $name =
    ([string]$part).Trim()

    if (-not [string]::IsNullOrWhiteSpace($name)) {
      $names.Add($name)
    }
  }

  return $names.ToArray()
}

function Get-DcaCreateInputPropertyText {

  param(
    $InputObject,

    [string]$PropertyName
  )

  if (
    $null -ne $InputObject.StringProps -and
    $InputObject.StringProps.ContainsKey($PropertyName)
  ) {
    return ([string]$InputObject.StringProps[$PropertyName]).Trim()
  }

  if (
    $null -ne $InputObject.IntProps -and
    $InputObject.IntProps.ContainsKey($PropertyName)
  ) {
    return ([string]$InputObject.IntProps[$PropertyName]).Trim()
  }

  return ""
}

function New-DcaCreateInputObject {

  # Create and populate an input object compatible with the SOA API.
  param(
    [Parameter(Mandatory = $true)]
    [type]$InputType,

    [Parameter(Mandatory = $true)]
    [string]$BoName,

    [Parameter(Mandatory = $true)]
    [hashtable]$Properties,

    [string[]]$IntegerPropertyNames = @()
  )

  $inputObject = [System.Activator]::CreateInstance($InputType)

  if ($null -eq $inputObject) {
    throw "Nao foi possivel criar o CreateInput de '$BoName'."
  }

  $inputObject.BoName = $BoName

  $stringProps = New-Object System.Collections.Hashtable
  $intProps = New-Object System.Collections.Hashtable

  foreach ($key in $Properties.Keys) {

    $isInteger = $false

    foreach ($integerName in $IntegerPropertyNames) {

      if ($key -ieq $integerName) {
        $isInteger = $true
        break
      }
    }

    if ($isInteger) {

      $parsedInteger = 0

      if (-not [int]::TryParse(
          ([string]$Properties[$key]).Trim(),
          [ref]$parsedInteger
        )) {

        throw (
          "A propriedade inteira '$key' recebeu um valor " +
          "invalido: '$($Properties[$key])'."
        )
      }

      $intProps[$key] = [int]$parsedInteger
    }
    else {

      $stringProps[$key] = [string]$Properties[$key]
    }
  }

  $inputObject.StringProps = $stringProps

  if ($intProps.Count -gt 0) {

    Set-DcaObjectMemberValue `
      -InputObject $inputObject `
      -MemberName "IntProps" `
      -Value $intProps
  }

  if ($null -eq $inputObject.StringProps) {

    throw (
      "StringProps ficou NULL no CreateInput de '$BoName'."
    )
  }

  Write-Output `
    -NoEnumerate `
    -InputObject $inputObject
}
function Get-DcaCreatedObjects {

  # Collect created objects from both the response and service data.
  param(
    $CreateResponse,
    $ServiceData
  )

  $createdObjects = [System.Collections.Generic.List[object]]::new()
  $publicInstance = [System.Reflection.BindingFlags]::Public -bor
  [System.Reflection.BindingFlags]::Instance

  if ($null -ne $CreateResponse.Output) {

    foreach ($outputEntry in $CreateResponse.Output) {

      if ($null -eq $outputEntry) {
        continue
      }

      foreach ($field in $outputEntry.GetType().GetFields($publicInstance)) {

        $fieldValue = $field.GetValue($outputEntry)

        if ($null -eq $fieldValue) {
          continue
        }

        if (
          $fieldValue -is [System.Collections.IEnumerable] -and
          $fieldValue -isnot [string]
        ) {

          foreach ($returnedObject in $fieldValue) {

            if (
              $null -ne $returnedObject -and
              -not $createdObjects.Contains($returnedObject)
            ) {
              $createdObjects.Add($returnedObject)
            }
          }
        }
        elseif ($fieldValue.GetType().FullName -like "Teamcenter.Soa.Client.Model.*") {

          if (-not $createdObjects.Contains($fieldValue)) {
            $createdObjects.Add($fieldValue)
          }
        }
      }
    }
  }

  if ($null -ne $ServiceData) {

    $createdCount = $ServiceData.SizeOfCreatedObjects()

    for ($objectIndex = 0; $objectIndex -lt $createdCount; $objectIndex++) {

      $createdObject = $ServiceData.GetCreatedObject($objectIndex)

      if (
        $null -ne $createdObject -and
        -not $createdObjects.Contains($createdObject)
      ) {
        $createdObjects.Add($createdObject)
      }
    }
  }

  if ($Details) {

    Write-Host (
      "  Quantidade de objetos criados: $($createdObjects.Count)"
    ) -ForegroundColor DarkGray
  }

  return $createdObjects.ToArray()
}
function Set-DcaObjectMemberValue {

  param(
    [Parameter(Mandatory = $true)]
    $InputObject,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$MemberName,

    [Parameter(Mandatory = $true)]
    $Value
  )

  $objectType =
  $InputObject.GetType()

  $bindingFlags =
  [System.Reflection.BindingFlags]::Public -bor
  [System.Reflection.BindingFlags]::Instance -bor
  [System.Reflection.BindingFlags]::IgnoreCase

  $memberProperty =
  $objectType.GetProperty(
    $MemberName,
    $bindingFlags
  )

  if ($null -ne $memberProperty) {

    if (-not $memberProperty.CanWrite) {

      throw (
        "A propriedade '$MemberName' existe em " +
        "'$($objectType.FullName)', mas nao permite escrita."
      )
    }

    $memberProperty.SetValue(
      $InputObject,
      $Value,
      $null
    )

    return
  }

  $memberField =
  $objectType.GetField(
    $MemberName,
    $bindingFlags
  )

  if ($null -ne $memberField) {

    $memberField.SetValue(
      $InputObject,
      $Value
    )

    return
  }

  $availableMembers =
  @(
    $objectType.GetMembers($bindingFlags) |
      Where-Object {
      $_.MemberType -eq
      [System.Reflection.MemberTypes]::Field -or
      $_.MemberType -eq
      [System.Reflection.MemberTypes]::Property
    } |
      ForEach-Object {
      $_.Name
    } |
      Sort-Object -Unique
  )

  throw (
    "O membro '$MemberName' nao foi encontrado no tipo " +
    "'$($objectType.FullName)'. Membros disponiveis: " +
    ($availableMembers -join ", ")
  )
}
function New-DcaTeamcenterItem {

  # Build and submit the item and revision creation request.
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

  $typeConfiguration = Get-DcaTypeConfiguration `
    -DocumentType $DocumentType `
    -ClientRevision $ClientRevision `
    -TeamcenterEnvironment $script:TeamcenterEnvironment
  Write-Host ""
  if ($Details) {

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

  Write-Host ""
  $itemType = $typeConfiguration.ItemType
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
  [System.Activator]::CreateInstance(
    $createInputType
  )

  if ($null -eq $itemInput) {

    throw (
      "Nao foi possivel criar o CreateInput do Item " +
      "'$itemType'."
    )
  }

  $itemInput.BoName =
  [string]$itemType

  $itemStringProperties =
  New-Object System.Collections.Hashtable

  foreach ($itemPropertyName in $itemProperties.Keys) {

    $itemStringProperties[$itemPropertyName] =
    [string]$itemProperties[$itemPropertyName]
  }

  $itemInput.StringProps =
  $itemStringProperties

  $revisionInputArray = [System.Array]::CreateInstance($createInputType, 1)
  $revisionInputArray.SetValue($revisionInput, 0)

  $compoundInput = New-Object System.Collections.Hashtable
  $compoundInput["revision"] = $revisionInputArray

  if ($null -eq $itemInput) {

    throw (
      "itemInput ficou NULL antes de preencher " +
      "CompoundCreateInput."
    )
  }

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

  $createInSent = $createInArray.GetValue(0)
  $revisionSent = $revisionInput

  if ($null -eq $revisionSent) {
    throw "revisionSent ficou NULL."
  }
  # Valida as propriedades obrigatorias da revisao de Processo
  # no objeto que sera enviado ao Teamcenter.
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

  if ($revisionSent.StringProps.ContainsKey("sequence_id")) {
    throw "sequence_id nao deve ser enviado."
  }

  $invokeArguments = New-Object "System.Object[]" 1
  $invokeArguments[0] = $createInArray

  $createResponse = $null

  try {
    $createResponse = $createObjectsMethod.Invoke($dataManagementService, $invokeArguments)
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

  $createdObjects = @(Get-DcaCreatedObjects -CreateResponse $createResponse -ServiceData $serviceData)

  $createdItem = $createdObjects |
    Where-Object {
    $_.GetType().Name -eq "Item" -or
    $_.GetType().FullName -match '\.Item$'
  } |
    Select-Object -First 1

  $createdRevision = $createdObjects |
    Where-Object {
    $_.GetType().Name -eq "ItemRevision" -or
    $_.GetType().FullName -match 'ItemRevision'
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
