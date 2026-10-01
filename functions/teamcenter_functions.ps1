$script:ImporterAssembly = $null
$script:TeamcenterSession = $null
$script:TeamcenterFunctions = $null

function Write-TeamcenterDetail {

  param(
    [Parameter(Mandatory = $true)]
    [string]$Message
  )

  if (-not $script:ShowDetails) {
    return
  }

  Write-Host "  -> $Message" -ForegroundColor Gray
}

function Confirm-TeamcenterImporter {

  $importerExecutablePath = "C:\Temp\ImportarGD\Importar GD.exe"

  if (-not (Test-Path -LiteralPath $importerExecutablePath -PathType Leaf)) {
    throw "Importar GD nao encontrado em '$importerExecutablePath'."
  }

  return $importerExecutablePath
}

# Configure localmente ou use DCA_TC_URL, DCA_TC_USER e DCA_TC_PASSWORD.
# Uma senha placeholder sera solicitada no console.
function Get-TeamcenterSettings {

  $teamcenterServerUrl = "<TEAMCENTER_URL>"
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
      "A URL do Teamcenter ainda e um placeholder. Edite " +
      "Get-TeamcenterSettings ou defina DCA_TC_URL."
    )
  }

  if ($teamcenterUser -like "<*>") {
    throw (
      "O usuario do Teamcenter ainda e um placeholder. Edite " +
      "Get-TeamcenterSettings ou defina DCA_TC_USER."
    )
  }

  if ($teamcenterPassword -like "<*>") {

    $securePassword = Read-Host "Senha do Teamcenter para '$teamcenterUser'" -AsSecureString
    $credential = New-Object System.Net.NetworkCredential("", $securePassword)
    $teamcenterPassword = $credential.Password
  }

  return [PSCustomObject]@{
    Url = $teamcenterServerUrl
    User = $teamcenterUser
    Password = $teamcenterPassword
  }
}

function Connect-Teamcenter {

  $importerExecutablePath = Confirm-TeamcenterImporter
  $settings = Get-TeamcenterSettings

  $script:ImporterAssembly =
  [System.Reflection.Assembly]::LoadFrom($importerExecutablePath)

  if ($null -eq $script:ImporterAssembly) {
    throw "Nao foi possivel carregar o Importar GD."
  }

  $sessionType =
  $script:ImporterAssembly.GetType("Teamcenter.ClientX.Session")

  if ($null -eq $sessionType) {
    throw "Tipo Teamcenter.ClientX.Session nao encontrado."
  }

  $script:TeamcenterSession =
  [System.Activator]::CreateInstance($sessionType, @($settings.Url))

  if ($null -eq $script:TeamcenterSession) {
    throw "A sessao do Teamcenter retornou NULL."
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
    throw "O login do Teamcenter retornou NULL."
  }

  $script:TeamcenterFunctions =
  $script:ImporterAssembly.GetType("ImportarGD.Controller.Functions")

  if ($null -eq $script:TeamcenterFunctions) {
    throw "ImportarGD.Controller.Functions nao encontrado."
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
      "As funcoes do Teamcenter nao foram carregadas. " +
      "Execute Connect-Teamcenter primeiro."
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
      "Metodo '$MethodName' com $ParameterCount parametro(s) " +
      "nao foi encontrado no Importar GD."
    )
  }

  return $method
}

function Get-TeamcenterConnection {

  if ($null -eq $script:ImporterAssembly) {
    throw (
      "O assembly do Importar GD nao foi carregado. " +
      "Execute Connect-Teamcenter primeiro."
    )
  }

  $sessionType =
  $script:ImporterAssembly.GetType("Teamcenter.ClientX.Session")

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
    throw "Tipo DataManagementService nao encontrado."
  }

  $getServiceMethod =
  $serviceType.GetMethods() |
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

  param(
    [Parameter(Mandatory = $true)]
    $Item
  )

  if ($null -eq $Item) {
    throw "O item do Teamcenter nao foi fornecido."
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

  Write-TeamcenterDetail "Tipo recebido por ImportarPDF: [$revisionTypeName]"

  if ($revisionTypeName -notmatch "ItemRevision") {
    throw (
      "A revisao recebida nao e um ItemRevision valido. " +
      "Tipo recebido: '$revisionTypeName'."
    )
  }

  $importMethod =
  Get-TeamcenterMethod -MethodName "ImportarPDF" -ParameterCount 5

  Write-TeamcenterDetail "Executando ImportarPDF."
  Write-TeamcenterDetail "Item: $ItemCode"
  Write-TeamcenterDetail "Arquivo: $FilePath"

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
    # A API desta versao nao expoe os metodos esperados.
    # A excecao original do CreateObjects (se houver) ja e propagada.
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

# Separa um valor como "BA4" em revisao cliente "B" e formato "A4".
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

# Mapeia cada tipo de documento para objetos e propriedades do Teamcenter.
function Get-DcaTypeConfiguration {

  param(
    [Parameter(Mandatory = $true)]
    [string]$DocumentType,

    [string]$ClientRevision
  )

  if ($DocumentType -eq "Original") {

    $info = Get-DcaClientRevisionInfo -ClientRevision $ClientRevision

    if ([string]::IsNullOrWhiteSpace($info.Revision)) {
      throw "ClientRevision ficou vazia para '$DocumentType'."
    }

    if ($info.Revision.Length -gt 2) {
      throw (
        "Revisao Cliente '$($info.Revision)' possui " +
        "$($info.Revision.Length) caracteres. " +
        "O Teamcenter permite no maximo 2."
      )
    }

    return [PSCustomObject]@{
      ItemType = "GD5_DCA_DESENHO"
      RevisionType = "GD5_DCA_DESENHORevision"
      ClientProperty = "gd5client"
      ClientValue = "Collins"
      TeamcenterRevisionId = $info.Revision
      RevisionProperties = @{ "gd5revcliente" = $info.Revision }
      Paper = $info.Paper
    }
  }

  if ($DocumentType -eq "Processo") {

    $processValue = ([string]$ClientRevision).Trim().ToUpper()

    if ($processValue -notmatch '^(?<Client>[A-Z0-9-]{1,2})(?<Internal>\d)$') {
      throw (
        "A revisao '$processValue' nao segue o padrao de DCA Processo " +
        "(1 ou 2 caracteres de revisao cliente + 1 digito interno, " +
        "ex.: BA4, AA4, --4)."
      )
    }

    return [PSCustomObject]@{
      ItemType = "GD5_DCA_PROCESSO"
      RevisionType = "GD5_DCA_PROCESSORevision"
      ClientProperty = "gd5client"
      ClientValue = "Collins"
      TeamcenterRevisionId = $processValue
      RevisionProperties = @{
        "gd5revcliente" = $Matches["Client"]
        "gd5revinterna" = $Matches["Internal"]
      }
      Paper = $null
    }
  }

  if ($DocumentType -eq "NormaExterna") {

    return [PSCustomObject]@{
      ItemType = "GD5_DCA_NORMA"
      RevisionType = "GD5_DCA_NORMARevision"
      ClientProperty = "gd5client"
      ClientValue = "Collins"
      TeamcenterRevisionId = "000"
      RevisionProperties = @{}
      Paper = $null
    }
  }

  throw "Tipo de documento nao suportado: '$DocumentType'."
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
  '(?i)already exists|ja existe|duplicate|not unique|is not unique'

  $sourceCodeClean = $SourceCode.Trim().ToUpper()
  $itemNameClean = $ItemName.Trim()

  if ([string]::IsNullOrWhiteSpace($sourceCodeClean)) {
    throw "SourceCode ficou vazio."
  }

  if ([string]::IsNullOrWhiteSpace($itemNameClean)) {
    throw "ItemName ficou vazio."
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
    throw "Revision ID ficou vazio para '$DocumentType'."
  }

  Write-TeamcenterDetail "Tipo selecionado pela pasta: [$DocumentType]"
  Write-TeamcenterDetail "Item BoName: [$itemType]"
  Write-TeamcenterDetail "Revision BoName: [$revisionType]"
  Write-TeamcenterDetail "Valor original do PDF: [$ClientRevision]"
  Write-TeamcenterDetail "Revision ID: [$teamcenterRevisionId]"

  foreach ($extraKey in $revisionExtraProperties.Keys) {
    Write-TeamcenterDetail "Propriedade da revisao: [$extraKey = $($revisionExtraProperties[$extraKey])]"
  }

  if ($revisionExtraProperties.Count -eq 0) {
    Write-TeamcenterDetail "Revisao Cliente: [nao utilizada por este tipo]"
  }

  if (-not [string]::IsNullOrWhiteSpace($typeConfiguration.Paper)) {
    Write-TeamcenterDetail "Formato identificado: [$($typeConfiguration.Paper)]"
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

  $createInputField =
  $createInType.GetField(
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
  Write-TeamcenterDetail "Criando item DCA: $candidateCode"

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

    Write-TeamcenterDetail "Item BoName: [$($createInSent.Data.BoName)]"
    Write-TeamcenterDetail "Item ID: [$($createInSent.Data.StringProps['item_id'])]"
    Write-TeamcenterDetail "Item Name: [$($createInSent.Data.StringProps['object_name'])]"
    Write-TeamcenterDetail "Revision BoName: [$($revisionSent.BoName)]"
    Write-TeamcenterDetail "Revision ID: [$($revisionSent.StringProps['item_revision_id'])]"

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

    Write-TeamcenterDetail "Tipo do Item retornado: [$($createdItem.GetType().FullName)]"

    if ($null -ne $createdRevision) {
      Write-TeamcenterDetail "Tipo da revisao retornada: [$($createdRevision.GetType().FullName)]"
    }
    else {
      Write-Host (
        "  [WARNING] A revisao nao veio no retorno. " +
        "Ela sera consultada pelo Item."
      ) -ForegroundColor Yellow
    }

    Write-Host "  [OK] Item criado: $candidateCode" -ForegroundColor Green

    return [PSCustomObject]@{
      Code = $candidateCode
      Item = $createdItem
      Revision = $createdRevision
    }
}
