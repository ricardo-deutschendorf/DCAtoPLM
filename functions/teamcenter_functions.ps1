$script:ImporterAssembly = $null
$script:TeamcenterSession = $null
$script:TeamcenterFunctions = $null

function Confirm-TeamcenterImporter {

  $importerExecutablePath = "C:\PATH\TO\Importar GD.exe"

  if (-not (Test-Path -LiteralPath $importerExecutablePath -PathType Leaf)) {
    throw "Import GD not found at '$importerExecutablePath'."
  }

  return $importerExecutablePath
}

# Configure locally or use DCA_TC_URL, DCA_TC_USER, and DCA_TC_PASSWORD.
function Get-TeamcenterSettings {

  $teamcenterServerUrl = "<TEAMCENTER_SERVER_URL>"
  $teamcenterUser = "<TEAMCENTER_USER>"
  $teamcenterPassword = "<TEAMCENTER_PASSWORD>"

  if (-not [string]::IsNullOrWhiteSpace($env:DCA_TC_URL)) {
    $teamcenterServerUrl = $env:DCA_TC_URL
  }

  if (-not [string]::IsNullOrWhiteSpace($env:DCA_TC_USER)) {
    $teamcenterUser = $env:DCA_TC_USER
  }

  if (-not [string]::IsNullOrWhiteSpace($env:DCA_TC_PASSWORD)) {
    $teamcenterPassword = $env:DCA_TC_PASSWORD
  }

  if ($teamcenterServerUrl -like "<*>") {
    throw (
      "The URL in Teamcenter is still a placeholder. Edit " +
      "Get-TeamcenterSettings or set DCA_TC_URL."
    )
  }

  if ($teamcenterUser -like "<*>") {
    throw (
      "The user in Teamcenter is still a placeholder. Edit " +
      "Get-TeamcenterSettings or set DCA_TC_USER."
    )
  }

  if ($teamcenterPassword -like "<*>") {

    $securePassword = Read-Host "Password in Teamcenter for '$teamcenterUser'" -AsSecureString
    $credential = New-Object System.Net.NetworkCredential("", $securePassword)
    $teamcenterPassword = $credential.Password
  }

  return [PSCustomObject]@{
    Url = $teamcenterServerUrl
    User = $teamcenterUser
    Password = $teamcenterPassword
  }
}

function Get-TeamcenterConfigurationWarnings {

  $warnings = [System.Collections.Generic.List[string]]::new()

  if (
    [string]::IsNullOrWhiteSpace($env:DCA_TC_URL) -or
    $env:DCA_TC_URL -like "<*>"
  ) {
    $warnings.Add(
      "DCA_TC_URL must be configured with the Teamcenter server URL."
    )
  }

  if (
    [string]::IsNullOrWhiteSpace($env:DCA_TC_USER) -or
    $env:DCA_TC_USER -like "<*>"
  ) {
    $warnings.Add(
      "DCA_TC_USER must be configured with the Teamcenter user."
    )
  }

  if (
    [string]::IsNullOrWhiteSpace($env:DCA_TC_PASSWORD) -or
    $env:DCA_TC_PASSWORD -like "<*>"
  ) {
    $warnings.Add(
      "DCA_TC_PASSWORD must be configured, or entered when requested."
    )
  }

  if (
    -not (Test-Path -LiteralPath "C:\PATH\TO\Importar GD.exe" -PathType Leaf)
  ) {
    $warnings.Add(
      "The Import GD.exe path must be configured in Confirm-TeamcenterImporter."
    )
  }

  return $warnings.ToArray()
}

function Connect-Teamcenter {

  $importerExecutablePath = Confirm-TeamcenterImporter
  $settings = Get-TeamcenterSettings

  $script:ImporterAssembly =
  [System.Reflection.Assembly]::LoadFrom($importerExecutablePath)

  if ($null -eq $script:ImporterAssembly) {
    throw "Could not load the Import GD."
  }

  $sessionType =
  $script:ImporterAssembly.GetType("Teamcenter.ClientX.Session")

  if ($null -eq $sessionType) {
    throw "Type Teamcenter.ClientX.Session not found."
  }

  $script:TeamcenterSession =
  [System.Activator]::CreateInstance($sessionType, @($settings.Url))

  if ($null -eq $script:TeamcenterSession) {
    throw "The Teamcenter session returned NULL."
  }

  $authenticatedUser =
  $script:TeamcenterSession.login(
    $settings.User,
    $settings.Password,
    "",
    "",
    "SoaAppX"
  )

  if ($null -eq $authenticatedUser) {
    throw "The Teamcenter login returned NULL."
  }

  $script:TeamcenterFunctions =
  $script:ImporterAssembly.GetType("ImportarGD.Controller.Functions")

  if ($null -eq $script:TeamcenterFunctions) {
    throw "ImportarGD.Controller.Functions not found."
  }

  return $script:TeamcenterSession
}

function Get-TeamcenterMethod {

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
      "The functions in Teamcenter not were loaded. " +
      "Run Connect-Teamcenter first."
    )
  }

  $method =
  $script:TeamcenterFunctions.GetMethods() |
    Where-Object {
    $_.Name -eq $MethodName -and
    $_.GetParameters().Count -eq $ParameterCount
  } |
    Select-Object -First 1

  if ($null -eq $method) {
    throw (
      "Method '$MethodName' with $ParameterCount parameter(s) " +
      "was not found in Import GD."
    )
  }

  return $method
}

function Get-TeamcenterConnection {

  if ($null -eq $script:ImporterAssembly) {
    throw (
      "The Import GD assembly was not loaded. " +
      "Run Connect-Teamcenter first."
    )
  }

  $sessionType =
  $script:ImporterAssembly.GetType("Teamcenter.ClientX.Session")

  if ($null -eq $sessionType) {
    throw "Type Teamcenter.ClientX.Session not found."
  }

  $getConnectionMethod = $sessionType.GetMethod("getConnection")

  if ($null -eq $getConnectionMethod) {
    throw "Method Session.getConnection not found."
  }

  $connection = $getConnectionMethod.Invoke($null, @())

  if ($null -eq $connection) {
    throw "The Teamcenter SOA connection returned NULL."
  }

  return $connection
}

function Get-TeamcenterDataManagementService {

  $connection = Get-TeamcenterConnection

  $serviceType =
  [System.AppDomain]::CurrentDomain.GetAssemblies() |
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
    throw "Type DataManagementService not found."
  }

  $getServiceMethod =
  $serviceType.GetMethods() |
    Where-Object {
    $_.Name -eq "getService" -and
    $_.GetParameters().Count -eq 1
  } |
    Select-Object -First 1

  if ($null -eq $getServiceMethod) {
    throw "Method DataManagementService.getService not found."
  }

  $service = $getServiceMethod.Invoke($null, @($connection))

  if ($null -eq $service) {
    throw "DataManagementService returned NULL."
  }

  return $service
}

function Get-TeamcenterRevision {

  param(
    [Parameter(Mandatory = $true)]
    $Item
  )

  if ($null -eq $Item) {
    throw "The Teamcenter item was not provided."
  }

  $getRevisionMethod =
  Get-TeamcenterMethod -MethodName "getItemRevisionfromItem" -ParameterCount 1

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
    [string]$FilePath
  )

  if ($null -eq $Revision) {
    throw "The item revision '$ItemCode' was not provided."
  }

  if (-not (Test-Path -LiteralPath $FilePath -PathType Leaf)) {
    throw "PDF not found at '$FilePath'."
  }

  if ([System.IO.Path]::GetExtension($FilePath) -ine ".pdf") {
    throw "The specified file does not have a PDF extension."
  }

  $revisionBaseObject = $Revision.PSObject.BaseObject

  if ($null -ne $revisionBaseObject) {
    $Revision = $revisionBaseObject
  }

  $revisionTypeName = $Revision.GetType().FullName

  if ($revisionTypeName -notmatch "ItemRevision") {
    throw (
      "The received revision is not a valid ItemRevision. " +
      "Type received: '$revisionTypeName'."
    )
  }

  $importMethod =
  Get-TeamcenterMethod -MethodName "ImportarPDF" -ParameterCount 5

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
        "Failed to import the PDF to '$ItemCode': " +
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

  param(
    $ServiceData
  )

  $errorMessages = [System.Collections.Generic.List[string]]::new()

  if ($null -eq $ServiceData) {
    return $errorMessages.ToArray()
  }

  $serviceDataType = $ServiceData.GetType()

  $sizeMethod =
  $serviceDataType.GetMethods() |
    Where-Object { $_.Name -match '(?i)sizeofpartialerrors' } |
    Select-Object -First 1

  $getErrorMethod =
  $serviceDataType.GetMethods() |
    Where-Object { $_.Name -match '(?i)getpartialerror$' } |
    Select-Object -First 1

  if ($null -eq $sizeMethod -or $null -eq $getErrorMethod) {
    # This version API does not expose the expected methods.
    # The original CreateObjects exception, if any, is already propagated.
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

# Splits a value such as "BA4" into client revision "B" and format "A4".
function Get-DcaClientRevisionInfo {

  param(
    [string]$ClientRevision
  )

  $value = ([string]$ClientRevision).Trim().ToUpper()
  $revision = $value
  $paper = $null

  if ($value -match '^(?<Revision>[A-Z0-9]{1,2})(?<Paper>A[0-4])$') {
    $revision = $Matches["Revision"]
    $paper = $Matches["Paper"]
  }

  return [PSCustomObject]@{
    Original = $value
    Revision = $revision
    Paper = $paper
  }
}

# Maps each document type to Teamcenter objects and properties.
function Get-DcaTypeConfiguration {

  param(
    [Parameter(Mandatory = $true)]
    [string]$DocumentType,

    [string]$ClientRevision
  )

  if ($DocumentType -eq "Original") {

    $info = Get-DcaClientRevisionInfo -ClientRevision $ClientRevision

    if ([string]::IsNullOrWhiteSpace($info.Revision)) {
      throw "ClientRevision ficou empty for '$DocumentType'."
    }

    if ($info.Revision.Length -gt 2) {
      throw (
        "Client Revision '$($info.Revision)' has " +
        "$($info.Revision.Length) characters. " +
        "Teamcenter allows a maximum of 2 characters."
      )
    }

    return [PSCustomObject]@{
      ItemType = "ITEM_TYPE_ORIGINAL_DRAWING"
      RevisionType = "REVISION_TYPE_ORIGINAL_DRAWING"
      ClientProperty = "CLIENT_PROPERTY"
      ClientValue = "CLIENT_NAME"
      TeamcenterRevisionId = $info.Revision
      RevisionProperties = @{ "CLIENT_REVISION_PROPERTY" = $info.Revision }
      Paper = $info.Paper
    }
  }

  if ($DocumentType -eq "Processo") {

    $processValue = ([string]$ClientRevision).Trim().ToUpper()

    if ($processValue -notmatch '^(?<Client>[A-Z0-9-]{1,2})(?<Internall>\d)$') {
      throw (
        "The revision '$processValue' does not follow the DCA Process pattern " +
        "(1 or 2 client revision characters plus 1 internal digit, " +
        "e.g.: BA4, AA4, --4)."
      )
    }

    return [PSCustomObject]@{
      ItemType = "ITEM_TYPE_PROCESS"
      RevisionType = "REVISION_TYPE_PROCESS"
      ClientProperty = "CLIENT_PROPERTY"
      ClientValue = "CLIENT_NAME"
      TeamcenterRevisionId = $processValue
      RevisionProperties = @{
        "CLIENT_REVISION_PROPERTY" = $Matches["Client"]
        "INTERNAL_REVISION_PROPERTY" = $Matches["Internal"]
      }
      Paper = $null
    }
  }

  if ($DocumentType -eq "NormaExterna") {

    return [PSCustomObject]@{
      ItemType = "ITEM_TYPE_EXTERNAL_STANDARD"
      RevisionType = "REVISION_TYPE_EXTERNAL_STANDARD"
      ClientProperty = "CLIENT_PROPERTY"
      ClientValue = "CLIENT_NAME"
      TeamcenterRevisionId = "DEFAULT_REVISION"
      RevisionProperties = @{}
      Paper = $null
    }
  }

  throw "Document type not supported: '$DocumentType'."
}

function New-DcaCreateInputObject {

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
    throw "Could not create the CreateInput for '$BoName'."
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

  param(
    $CreateResponse,
    $ServiceData
  )

  $createdObjects = [System.Collections.Generic.List[object]]::new()
  $publicInstance =
  [System.Reflection.BindingFlags]::Public -bor
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

  $duplicatePattern =
  '(?i)already exists|already exists|duplicate|not unique|is not unique'

  $sourceCodeClean = $SourceCode.Trim().ToUpper()
  $itemNameClean = $ItemName.Trim()

  if ([string]::IsNullOrWhiteSpace($sourceCodeClean)) {
    throw "SourceCode ficou empty."
  }

  if ([string]::IsNullOrWhiteSpace($itemNameClean)) {
    throw "ItemName ficou empty."
  }

  $typeConfiguration =
  Get-DcaTypeConfiguration `
    -DocumentType $DocumentType `
    -ClientRevision $ClientRevision

  $itemType = $typeConfiguration.ItemType
  $revisionType = $typeConfiguration.RevisionType
  $clientProperty = $typeConfiguration.ClientProperty
  $clientValue = $typeConfiguration.ClientValue
  $teamcenterRevisionId = $typeConfiguration.TeamcenterRevisionId
  $revisionExtraProperties = $typeConfiguration.RevisionProperties

  if ([string]::IsNullOrWhiteSpace($teamcenterRevisionId)) {
    throw "Revision ID is empty for '$DocumentType'."
  }

  $dataManagementService = Get-TeamcenterDataManagementService

  $createObjectsMethod =
  $dataManagementService.GetType().GetMethods() |
    Where-Object {
    $_.Name -eq "CreateObjects" -and
    $_.GetParameters().Count -eq 1
  } |
    Select-Object -First 1

  if ($null -eq $createObjectsMethod) {
    throw "Method CreateObjects not found."
  }

  $createInArrayType = $createObjectsMethod.GetParameters()[0].ParameterType

  if (-not $createInArrayType.IsArray) {
    throw "The CreateObjects parameter is not an array."
  }

  $createInType = $createInArrayType.GetElementType()

  if ($null -eq $createInType) {
    throw "Type CreateIn not identified."
  }

  $createInputField =
  $createInType.GetField(
    "Data",
    [System.Reflection.BindingFlags]::Public -bor
    [System.Reflection.BindingFlags]::Instance -bor
    [System.Reflection.BindingFlags]::IgnoreCase
  )

  if ($null -eq $createInputField) {
    throw "Data field not found in CreateIn."
  }

  $createInputType = $createInputField.FieldType

  if ($null -eq $createInputType) {
    throw "CreateInput type not identified."
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

    $revisionInput =
    New-DcaCreateInputObject `
      -InputType $createInputType `
      -BoName $revisionType `
      -Properties $revisionProperties

    $itemProperties = @{
      "item_id" = $candidateCode
      "object_name" = $itemNameClean
      "object_desc" = $itemNameClean
    }

    if (-not [string]::IsNullOrWhiteSpace($clientProperty)) {
      $itemProperties[$clientProperty] = $clientValue
    }

    $itemInput =
    New-DcaCreateInputObject `
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
      throw "Could not create createIn."
    }

    $createIn.ClientId = [string]"CreateDcaItem"
    $createIn.Data = $itemInput

    $createInArray = [System.Array]::CreateInstance($createInType, 1)
    $createInArray.SetValue($createIn, 0)

    $createInSent = $createInArray.GetValue(0)
    $revisionSent = $createInSent.Data.CompoundCreateInput["revision"].GetValue(0)

    if ($null -eq $revisionSent) {
      throw "revisionSent was NULL."
    }

    foreach ($extraKey in $revisionExtraProperties.Keys) {

      if ([string]::IsNullOrWhiteSpace([string]$revisionSent.StringProps[$extraKey])) {
        throw "A property '$extraKey' is empty in the revision."
      }
    }

    if ($revisionSent.StringProps.ContainsKey("sequence_id")) {
      throw "sequence_id must not be sent."
    }

    if (
      $DocumentType -eq "NormaExterna" -and
      $revisionSent.StringProps.ContainsKey("CLIENT_REVISION_PROPERTY")
    ) {
      throw "CLIENT_REVISION_PROPERTY must not be sent for '$DocumentType'."
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
        throw "The item '$candidateCode' already exists in Teamcenter."
      }

      throw "Failure while running CreateObjects for '$candidateCode': $errorMessage"
    }

    if ($null -eq $createResponse) {
      throw "CreateObjects returned NULL."
    }

    $serviceData = $createResponse.ServiceData
    $serviceErrors = @(Get-TeamcenterServiceErrors -ServiceData $serviceData)

    if ($serviceErrors.Count -gt 0) {

      $joinedErrors = $serviceErrors -join " | "

      if ($joinedErrors -match $duplicatePattern) {
        throw "The item '$candidateCode' already exists in Teamcenter."
      }

      throw "Teamcenter rejected the creation: $joinedErrors"
    }

    $createdObjects =
    @(Get-DcaCreatedObjects -CreateResponse $createResponse -ServiceData $serviceData)

    $createdItem =
    $createdObjects |
      Where-Object {
      $_.GetType().Name -eq "Item" -or
      $_.GetType().FullName -match '\.Item$'
    } |
      Select-Object -First 1

    $createdRevision =
    $createdObjects |
      Where-Object {
      $_.GetType().Name -eq "ItemRevision" -or
      $_.GetType().FullName -match 'ItemRevision'
    } |
      Select-Object -First 1

    if ($null -eq $createdItem) {
      throw (
        "CreateObjects did not return the created item. " +
        "Objetos returneds: $($createdObjects.Count)."
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
