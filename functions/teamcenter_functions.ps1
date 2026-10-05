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

  $teamcenterServerUrl = $env:DCA_TC_URL

  if ([string]::IsNullOrWhiteSpace($teamcenterServerUrl)) {
    throw "DCA_TC_URL must be configured."
  }

  $teamcenterServerUrl = $teamcenterServerUrl.Trim()

  # Validate the URL before identifying the environment.
  $parsedUri = $null

  $isValidUrl = [System.Uri]::TryCreate(
    $teamcenterServerUrl,
    [System.UriKind]::Absolute,
    [ref]$parsedUri
  )

  if (
    -not $isValidUrl -or
    $null -eq $parsedUri
  ) {

    throw (
      "A URL do Teamcenter e invalida: " +
      "'$teamcenterServerUrl'."
    )
  }

  $teamcenterHost = $parsedUri.Host.ToLowerInvariant()

  $teamcenterEnvironment = $null

  $teamcenterUser = $null

  $teamcenterPassword = $null

  $teamcenterEnvironment = $env:DCA_TC_ENV

  if ($teamcenterEnvironment -notin @("Teste", "Processo")) {
    throw "DCA_TC_ENV must be Teste or Processo."
  }

  # Generic variables override the credentials configured for the environment.
  if (
    -not [string]::IsNullOrWhiteSpace(
      $env:DCA_TC_USER
    )
  ) {

    $teamcenterUser = $env:DCA_TC_USER
  }

  if (
    -not [string]::IsNullOrWhiteSpace(
      $env:DCA_TC_PASSWORD
    )
  ) {

    $teamcenterPassword = $env:DCA_TC_PASSWORD
  }

  if ([string]::IsNullOrWhiteSpace($teamcenterUser)) {

    throw (
      "Usuario nao configurado para o ambiente " +
      "'$teamcenterEnvironment'."
    )
  }

  if ([string]::IsNullOrWhiteSpace($teamcenterPassword)) {

    $securePassword = Read-Host (
      "Senha do Teamcenter para " +
      "'$teamcenterUser'"
    ) -AsSecureString

    $credential = New-Object System.Net.NetworkCredential(
      "",
      $securePassword
    )

    $teamcenterPassword = $credential.Password
  }

  return [PSCustomObject]@{
    Url = $teamcenterServerUrl
    Host = $teamcenterHost
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

  Write-Host (
    "  Servidor: $($settings.Url)"
  ) -ForegroundColor Gray

  Write-Host (
    "  Usuario:  $($settings.User)"
  ) -ForegroundColor Gray

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

  # Invoke the importer method that attaches the PDF to the Teamcenter revision.
  param(
    [Parameter(Mandatory = $true)]
    $Revision,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$ItemCode,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$FilePath
  )

  if ($null -eq $Revision) {
    throw "A revisao do item '$ItemCode' nao foi fornecida."
  }

  if (-not (Test-Path -LiteralPath $FilePath -PathType Leaf)) {
    throw "PDF nao encontrado em '$FilePath'."
  }

  if ([System.IO.Path]::GetExtension($FilePath) -ine ".pdf") {
    throw "O arquivo informado nao possui extensao PDF."
  }

  $revisionBaseObject = $Revision.PSObject.BaseObject

  if ($null -ne $revisionBaseObject) {
    $Revision = $revisionBaseObject
  }

  $revisionTypeName = $Revision.GetType().FullName

  if ($revisionTypeName -notmatch "ItemRevision") {
    throw (
      "A revisao recebida nao e um ItemRevision valido. " +
      "Tipo recebido: '$revisionTypeName'."
    )
  }

  $importMethod = Get-TeamcenterMethod -MethodName "ImportarPDF" -ParameterCount 5

  $invokeArguments = New-Object "System.Object[]" 5
  $invokeArguments[0] = [string]$ItemCode
  $invokeArguments[1] = [string]""
  $invokeArguments[2] = [string]$FilePath
  $invokeArguments[3] = $Revision
  $invokeArguments[4] = [bool]$true

  $originalConsoleOut = [Console]::Out
  $importResult = $null

  try {

    [Console]::SetOut([System.IO.TextWriter]::Null)

    try {
      $importResult = $importMethod.Invoke($null, $invokeArguments)
    }
    catch {

      $realException = $_.Exception

      while ($null -ne $realException.InnerException) {
        $realException = $realException.InnerException
      }

      throw (
        "Falha ao importar o PDF para '$ItemCode': " +
        $realException.Message
      )
    }
  }
  finally {
    [Console]::SetOut($originalConsoleOut)
  }

  return $importResult
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

  if ($value -match '^(?<Revision>[A-Z0-9]{1,2})A[0-4]$') {
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
      ClientProperty = $env:DCA_TC_PROCESS_CLIENT_PROPERTY
      ClientValue = $env:DCA_TC_PROCESS_CLIENT_VALUE
    }

    Processo = @{
      ItemType = $env:DCA_TC_PROCESS_PROCESS_ITEM_TYPE
      RevisionType = $env:DCA_TC_PROCESS_PROCESS_REVISION_TYPE
      ClientProperty = $env:DCA_TC_PROCESS_CLIENT_PROPERTY
      ClientValue = $env:DCA_TC_PROCESS_CLIENT_VALUE
    }

    NormaExterna = @{
      ItemType = $env:DCA_TC_PROCESS_STANDARD_ITEM_TYPE
      RevisionType = $env:DCA_TC_PROCESS_STANDARD_REVISION_TYPE
      ClientProperty = $env:DCA_TC_PROCESS_CLIENT_PROPERTY
      ClientValue = $env:DCA_TC_PROCESS_CLIENT_VALUE
    }
  }

  $testTypes = @{

    Original = @{
      ItemType = $env:DCA_TC_TEST_ORIGINAL_ITEM_TYPE
      RevisionType = $env:DCA_TC_TEST_ORIGINAL_REVISION_TYPE
      ClientProperty = $null
      ClientValue = $null
    }

    Processo = @{
      ItemType = $env:DCA_TC_TEST_PROCESS_ITEM_TYPE
      RevisionType = $env:DCA_TC_TEST_PROCESS_REVISION_TYPE
      ClientProperty = $env:DCA_TC_TEST_CLIENT_PROPERTY
      ClientValue = $env:DCA_TC_TEST_CLIENT_VALUE
    }

    NormaExterna = @{
      ItemType = $env:DCA_TC_TEST_STANDARD_ITEM_TYPE
      RevisionType = $env:DCA_TC_TEST_STANDARD_REVISION_TYPE
      ClientProperty = $null
      ClientValue = $null
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

    if ($info.Revision.Length -gt 2) {

      throw (
        "Revisao Cliente '$($info.Revision)' possui " +
        "$($info.Revision.Length) caracteres. " +
        "O limite configurado e 2."
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

    $processValue = ([string]$ClientRevision).Trim().ToUpper()

    if (
      $processValue -notmatch
      '^(?<Client>[A-Z0-9-]{1,2})(?<Internal>\d)$'
    ) {

      throw (
        "A revisao '$processValue' nao segue o padrao " +
        "de DCA Processo: 1 ou 2 caracteres de revisao " +
        "cliente e 1 digito interno. Exemplos: BA4, " +
        "AA4 ou --4."
      )
    }

    $clientRevisionValue = $Matches["Client"]

    $internalRevisionValue = $Matches["Internal"]

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

    return [PSCustomObject]@{
      Environment = $TeamcenterEnvironment
      ItemType = $itemType
      RevisionType = $revisionType
      ClientProperty = $clientProperty
      ClientValue = $clientValue
      TeamcenterRevisionId = "000"
      RevisionProperties = @{}
    }
  }

  throw (
    "Tipo de documento nao suportado: " +
    "'$DocumentType'."
  )
}

function New-DcaCreateInputObject {

  # Create and populate an input object compatible with the SOA API.
  param(
    [Parameter(Mandatory = $true)]
    [type]$InputType,

    [Parameter(Mandatory = $true)]
    [string]$BoName,

    [Parameter(Mandatory = $true)]
    [hashtable]$Properties
  )

  $inputObject = [System.Activator]::CreateInstance($InputType)

  if ($null -eq $inputObject) {
    throw "Nao foi possivel criar o CreateInput de '$BoName'."
  }

  $inputObject.BoName = $BoName

  $stringProps = New-Object System.Collections.Hashtable

  foreach ($key in $Properties.Keys) {
    $stringProps[$key] = [string]$Properties[$key]
  }

  $inputObject.StringProps = $stringProps

  return $inputObject
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

  return $createdObjects.ToArray()
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
    $revisionProperties[$extraKey] = $revisionExtraProperties[$extraKey]
  }

  $revisionInput = New-DcaCreateInputObject `
    -InputType $createInputType `
    -BoName $revisionType `
    -Properties $revisionProperties

  $itemProperties = @{
    "item_id" = $candidateCode
    "object_name" = $itemNameClean
    "object_desc" = $itemNameClean
  }

  if (-not [string]::IsNullOrWhiteSpace([string]$clientProperty) -and
    -not [string]::IsNullOrWhiteSpace([string]$clientValue)
  ) {

    $itemProperties[$clientProperty] = $clientValue
  }

  $itemInput = New-DcaCreateInputObject `
    -InputType $createInputType `
    -BoName $itemType `
    -Properties $itemProperties

  $revisionInputArray = [System.Array]::CreateInstance($createInputType, 1)
  $revisionInputArray.SetValue($revisionInput, 0)

  $compoundInput = New-Object System.Collections.Hashtable
  $compoundInput["revision"] = $revisionInputArray
  $itemInput.CompoundCreateInput = $compoundInput

  $createIn = [System.Activator]::CreateInstance($createInType)

  if ($null -eq $createIn) {
    throw "Nao foi possivel criar createIn."
  }

  $createIn.ClientId = [string]"CreateDcaItem"
  $createIn.Data = $itemInput

  $createInArray = [System.Array]::CreateInstance($createInType, 1)
  $createInArray.SetValue($createIn, 0)

  $createInSent = $createInArray.GetValue(0)
  $revisionSent = $createInSent.Data.CompoundCreateInput["revision"].GetValue(0)

  if ($null -eq $revisionSent) {
    throw "revisionSent ficou NULL."
  }

  foreach ($extraKey in $revisionExtraProperties.Keys) {

    if ([string]::IsNullOrWhiteSpace([string]$revisionSent.StringProps[$extraKey])) {
      throw "A propriedade '$extraKey' ficou vazia na revisao."
    }
  }

  if ($revisionSent.StringProps.ContainsKey("sequence_id")) {
    throw "sequence_id nao deve ser enviado."
  }

  if (
    $DocumentType -eq "NormaExterna" -and
    $revisionSent.StringProps.ContainsKey("gd5revcliente")
  ) {
    throw "gd5revcliente nao deve ser enviado para '$DocumentType'."
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
