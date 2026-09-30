# === Teamcenter integration helper functions for DCAtoPLM ===

$script:ImporterAssembly = $null
$script:TeamcenterSession = $null
$script:TeamcenterFunctions = $null

function Confirm-TeamcenterImporter {

  $importerExecutablePath =
  "C:\Temp\ImportarGD\Importar GD.exe"

  if (-not (Test-Path -LiteralPath $importerExecutablePath -PathType Leaf)) {
    throw "Importar GD nao encontrado em '$importerExecutablePath'."
  }

  Write-Host `
    "  [OK] Importar GD encontrado." `
    -ForegroundColor Green

  Write-Host `
    "  -> $importerExecutablePath" `
    -ForegroundColor Gray

  return $importerExecutablePath
}

function Connect-Teamcenter {

  $importerExecutablePath =
  Confirm-TeamcenterImporter

  $teamcenterServerUrl =
  "http://perto37-novo.perto.com.br:8080/tc"

  Write-Host `
    "  -> Teamcenter server: $teamcenterServerUrl" `
    -ForegroundColor Gray

  $script:ImporterAssembly =
  [System.Reflection.Assembly]::LoadFrom(
    $importerExecutablePath
  )

  if ($null -eq $script:ImporterAssembly) {
    throw "Nao foi possivel carregar o Importar GD."
  }

  $sessionType =
  $script:ImporterAssembly.GetType(
    "Teamcenter.ClientX.Session"
  )

  if ($null -eq $sessionType) {
    throw "Tipo Teamcenter.ClientX.Session nao encontrado."
  }

  $script:TeamcenterSession =
  [System.Activator]::CreateInstance(
    $sessionType,
    @(
      $teamcenterServerUrl
    )
  )

  if ($null -eq $script:TeamcenterSession) {
    throw "A sessao do Teamcenter retornou NULL."
  }

  $authenticatedUser =
  $script:TeamcenterSession.login(
    "infodba",
    "infodba",
    "",
    "",
    "SoaAppX"
  )

  if ($null -eq $authenticatedUser) {
    throw "O login do Teamcenter retornou NULL."
  }

  $script:TeamcenterFunctions =
  $script:ImporterAssembly.GetType(
    "ImportarGD.Controller.Functions"
  )

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
  $script:ImporterAssembly.GetType(
    "Teamcenter.ClientX.Session"
  )

  if ($null -eq $sessionType) {
    throw "Tipo Teamcenter.ClientX.Session nao encontrado."
  }

  $getConnectionMethod =
  $sessionType.GetMethod(
    "getConnection"
  )

  if ($null -eq $getConnectionMethod) {
    throw "Metodo Session.getConnection nao encontrado."
  }

  $connection =
  $getConnectionMethod.Invoke(
    $null,
    @()
  )

  if ($null -eq $connection) {
    throw "A conexao SOA do Teamcenter retornou NULL."
  }

  return $connection
}

function Get-TeamcenterDataManagementService {

  $connection =
  Get-TeamcenterConnection

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
    Where-Object {
    $null -ne $_
  } |
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

  $service =
  $getServiceMethod.Invoke(
    $null,
    @(
      $connection
    )
  )

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
  Get-TeamcenterMethod `
    -MethodName "getItemRevisionfromItem" `
    -ParameterCount 1

  $revision =
  $getRevisionMethod.Invoke(
    $null,
    @(
      $Item
    )
  )

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

  if (
    [System.IO.Path]::GetExtension($FilePath) -ine ".pdf"
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

  Write-Host (
    "  -> Tipo recebido por ImportarPDF: " +
    "[$revisionTypeName]"
  ) -ForegroundColor Gray

  if ($revisionTypeName -notmatch "ItemRevision") {

    throw (
      "A revisao recebida nao e um ItemRevision valido. " +
      "Tipo recebido: '$revisionTypeName'."
    )
  }

  $importMethod = Get-TeamcenterMethod -MethodName "ImportarPDF" -ParameterCount 5

  Write-Host (
    "  -> Executando ImportarPDF."
  ) -ForegroundColor Gray

  Write-Host (
    "  -> Item: $ItemCode"
  ) -ForegroundColor Gray

  Write-Host (
    "  -> Arquivo: $FilePath"
  ) -ForegroundColor Gray

  $invokeArguments =
  New-Object "System.Object[]" 5

  $invokeArguments[0] =
  [string]$ItemCode

  $invokeArguments[1] =
  [string]""

  $invokeArguments[2] =
  [string]$FilePath

  $invokeArguments[3] =
  $Revision

  $invokeArguments[4] =
  [bool]$true

  try {

    $importResult = $importMethod.Invoke($null, $invokeArguments)
  }
  catch {

    $realException =
    $_.Exception

    while ($null -ne $realException.InnerException) {
      $realException = $realException.InnerException
    }

    throw (
      "Falha ao importar o PDF para '$ItemCode': " +
      $realException.Message
    )
  }

  return $importResult
}
function Get-TeamcenterServiceErrors {

  param(
    [Parameter(Mandatory = $true)]
    $ServiceData
  )

  $errorMessages =
  [System.Collections.Generic.List[string]]::new()

  if ($null -eq $ServiceData) {
    return $errorMessages
  }

  $serviceDataType =
  $ServiceData.GetType()

  $sizeMethod =
  $serviceDataType.GetMethods() |
    Where-Object {
    $_.Name -match '(?i)sizeofpartialerrors'
  } |
    Select-Object -First 1

  $getErrorMethod =
  $serviceDataType.GetMethods() |
    Where-Object {
    $_.Name -match '(?i)getpartialerror$'
  } |
    Select-Object -First 1

  if ($null -eq $sizeMethod -or $null -eq $getErrorMethod) {

    # A API dessa versao nao expoe os metodos esperados.
    # Retorna vazio em vez de travar; a excecao original do
    # CreateObjects (se houver) ja sera propagada por quem chamou.
    return $errorMessages
  }

  $errorCount =
  $sizeMethod.Invoke($ServiceData, @())

  for ($errorIndex = 0; $errorIndex -lt $errorCount; $errorIndex++) {

    $partialError =
    $getErrorMethod.Invoke($ServiceData, @($errorIndex))

    if ($null -eq $partialError) {
      continue
    }

    $errorStackProperty =
    $partialError.GetType().GetProperty("ErrorValues")

    if ($null -ne $errorStackProperty) {

      $errorValues =
      $errorStackProperty.GetValue($partialError)

      foreach ($errorValue in $errorValues) {

        $messageProperty =
        $errorValue.GetType().GetProperty("Message")

        if ($null -ne $messageProperty) {

          $errorMessages.Add(
            [string]$messageProperty.GetValue($errorValue)
          )
        }
      }
    }
    else {

      $errorMessages.Add(
        $partialError.ToString()
      )
    }
  }

  return $errorMessages
}

function New-DcaTeamcenterItem {

  param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$SourceCode,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$ItemName,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$ClientRevision,

    [ValidateRange(1, 100)]
    [int]$MaximumAttempts = 20
  )

  $itemNameClean =
  $ItemName.Trim()

  if ([System.String]::IsNullOrWhiteSpace($itemNameClean)) {
    throw "ItemName chegou vazio em New-DcaTeamcenterItem."
  }

  $itemType =
  "GD5_DCA_DESENHO"

  $revisionType =
  "GD5_DCA_DESENHORevision"

  $clientRevisionProperty =
  "gd5revcliente"

  $clientProperty =
  "gd5client"

  $clientValue =
  "Collins"

  $sourceCodeClean =
  $SourceCode.Trim().ToUpper()

  $itemNameClean =
  $ItemName.Trim()

  if ([System.String]::IsNullOrWhiteSpace($itemNameClean)) {

    throw "ItemName chegou vazio em New-DcaTeamcenterItem."
  }

  $clientRevisionFromFile =
  $ClientRevision.Trim().ToUpper()

  $clientRevisionClean =
  $clientRevisionFromFile

  $paperFormat =
  $null

  # BA4 = Revisao Cliente B + formato A4.
  # CA3 = Revisao Cliente C + formato A3.
  if (
    $clientRevisionFromFile -match
    '^(?<Revision>[A-Z0-9]{1,2})(?<Paper>A[0-4])$'
  ) {

    $clientRevisionClean =
    $Matches["Revision"]

    $paperFormat =
    $Matches["Paper"]
  }

  if (
    [System.String]::IsNullOrWhiteSpace(
      $sourceCodeClean
    )
  ) {

    throw "SourceCode ficou vazio."
  }

  if (
    [System.String]::IsNullOrWhiteSpace(
      $clientRevisionClean
    )
  ) {

    throw "Revisao Cliente ficou vazia."
  }

  if ($clientRevisionClean.Length -gt 2) {

    throw (
      "Revisao Cliente '$clientRevisionClean' possui " +
      "$($clientRevisionClean.Length) caracteres. " +
      "O Teamcenter permite no maximo 2."
    )
  }

  Write-Host (
    "  -> Valor original do PDF: " +
    "[$clientRevisionFromFile]"
  ) -ForegroundColor Gray

  Write-Host (
    "  -> Revisao Cliente tratada: " +
    "[$clientRevisionClean]"
  ) -ForegroundColor Gray

  if (
    -not [System.String]::IsNullOrWhiteSpace(
      $paperFormat
    )
  ) {

    Write-Host (
      "  -> Formato identificado: [$paperFormat]"
    ) -ForegroundColor Gray
  }

  $prefix =
  $sourceCodeClean

  $initialNumber =
  $null

  if ($sourceCodeClean -match '^(.*)-(\d+)$') {

    $prefix =
    $Matches[1]

    $initialNumber =
    [int]$Matches[2]
  }

  $dataManagementService =
  Get-TeamcenterDataManagementService

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

  $createInArrayType =
  $createObjectsMethod.GetParameters()[0].ParameterType

  if (-not $createInArrayType.IsArray) {
    throw "O parametro de CreateObjects nao e um array."
  }

  $createInType =
  $createInArrayType.GetElementType()

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

  $createInputType =
  $createInputField.FieldType

  for (
    $attempt = 0
    $attempt -lt $MaximumAttempts
    $attempt++
  ) {

    if ($attempt -eq 0) {

      $candidateCode =
      "$sourceCodeClean-teste"
    }
    else {

      $candidateCode =
      "$sourceCodeClean-TESTE-$attempt"
    }
    `

      Write-Host ""
    Write-Host "Creating DCA code: [$candidateCode]"

    Write-Host `
      "[INFO] Creating DCA item: $candidateCode" `
      -ForegroundColor Gray
    # ====================================================
    # Revision input
    # ====================================================

    $revisionInput =
    [System.Activator]::CreateInstance(
      $createInputType
    )

    if ($null -eq $revisionInput) {
      throw "Nao foi possivel criar revisionInput."
    }

    $revisionInput.BoName =
    $revisionType

    $revisionInput.StringProps =
    New-Object System.Collections.Hashtable

    if ($null -eq $revisionInput.StringProps) {
      throw "revisionInput.StringProps ficou NULL."
    }

    $revisionInput.StringProps["item_revision_id"] =
    [string]$clientRevisionClean

    $revisionInput.StringProps["object_name"] =
    [string]$itemNameClean

    $revisionInput.StringProps["object_desc"] =
    [string]$itemNameClean

    $revisionInput.StringProps[$clientRevisionProperty] =
    [string]$clientRevisionClean

    # ====================================================
    # Item input
    # ====================================================

    $itemInput =
    [System.Activator]::CreateInstance(
      $createInputType
    )

    if ($null -eq $itemInput) {
      throw "Nao foi possivel criar itemInput."
    }

    $itemInput.BoName =
    $itemType

    $itemInput.StringProps =
    New-Object System.Collections.Hashtable

    if ($null -eq $itemInput.StringProps) {
      throw "itemInput.StringProps ficou NULL."
    }

    $itemInput.StringProps["item_id"] =
    [string]$candidateCode

    $itemInput.StringProps["object_name"] =
    [string]$itemNameClean

    $itemInput.StringProps["object_desc"] =
    [string]$itemNameClean

    $itemInput.StringProps[$clientProperty] =
    [string]$clientValue
    # ====================================================
    # Connect revision to item
    # ====================================================

    $revisionInputArray =
    [System.Array]::CreateInstance(
      $createInputType,
      1
    )

    $revisionInputArray.SetValue(
      $revisionInput,
      0
    )

    if ($null -eq $revisionInputArray.GetValue(0)) {
      throw "revisionInputArray[0] ficou NULL."
    }

    $itemInput.CompoundCreateInput =
    New-Object System.Collections.Hashtable

    if ($null -eq $itemInput.CompoundCreateInput) {
      throw "itemInput.CompoundCreateInput ficou NULL."
    }

    $itemInput.CompoundCreateInput["revision"] =
    $revisionInputArray

    # ====================================================
    # Main CreateIn wrapper
    # ====================================================

    $createIn =
    [System.Activator]::CreateInstance(
      $createInType
    )

    if ($null -eq $createIn) {
      throw "Nao foi possivel criar createIn."
    }

    $createIn.ClientId =
    [string]"CreateDcaItem"

    $createIn.Data =
    $itemInput

    $createInArray =
    [System.Array]::CreateInstance(
      $createInType,
      1
    )

    $createInArray.SetValue(
      $createIn,
      0
    )

    $createInSent =
    $createInArray.GetValue(0)

    if ($null -eq $createInSent) {
      throw "createInArray[0] ficou NULL."
    }

    if ($null -eq $createInSent.Data) {
      throw "createInArray[0].Data ficou NULL."
    }

    if ($null -eq $createInSent.Data.StringProps) {
      throw "createInArray[0].Data.StringProps ficou NULL."
    }

    if (
      -not $createInSent.Data.StringProps.ContainsKey(
        "item_id"
      )
    ) {
      throw "StringProps do Item nao possui item_id."
    }

    if (
      $null -eq
      $createInSent.Data.CompoundCreateInput
    ) {
      throw "CompoundCreateInput do Item ficou NULL."
    }

    if (
      -not
      $createInSent.Data.CompoundCreateInput.ContainsKey(
        "revision"
      )
    ) {
      throw "CompoundCreateInput nao possui revision."
    }

    $revisionSentArray =
    $createInSent.Data.CompoundCreateInput["revision"]

    if (
      $null -eq $revisionSentArray -or
      $revisionSentArray.Length -eq 0
    ) {
      throw "revisionSentArray ficou vazio."
    }

    $revisionSent =
    $revisionSentArray.GetValue(0)

    if ($null -eq $revisionSent) {
      throw "revisionSent ficou NULL."
    }

    if ($null -eq $revisionSent.StringProps) {
      throw "revisionSent.StringProps ficou NULL."
    }

    if (
      -not $revisionSent.StringProps.ContainsKey(
        $clientRevisionProperty
      )
    ) {
      throw (
        "A revisao nao possui a propriedade " +
        "'$clientRevisionProperty'."
      )
    }

    Write-Host (
      "  -> CreateIn ClientId: " +
      "[$($createInSent.ClientId)]"
    ) -ForegroundColor Gray

    Write-Host (
      "  -> Item BoName: " +
      "[$($createInSent.Data.BoName)]"
    ) -ForegroundColor Gray

    Write-Host (
      "  -> Item ID: " +
      "[$($createInSent.Data.StringProps['item_id'])]"
    ) -ForegroundColor Gray

    Write-Host (
      "  -> Item Name: " +
      "[$($createInSent.Data.StringProps['object_name'])]"
    ) -ForegroundColor Gray

    Write-Host (
      "  -> Revision BoName: " +
      "[$($revisionSent.BoName)]"
    ) -ForegroundColor Gray

    Write-Host (
      "  -> Revision ID: " +
      "[$($revisionSent.StringProps['item_revision_id'])]"
    ) -ForegroundColor Gray

    Write-Host (
      "  -> Revisao Cliente property: " +
      "[$clientRevisionProperty]"
    ) -ForegroundColor Gray

    Write-Host (
      "  -> Revisao Cliente value: " +
      "[$($revisionSent.StringProps[$clientRevisionProperty])]"
    ) -ForegroundColor Gray

    Write-Host (
      "  -> CreateIn count: " +
      "[$($createInArray.Length)]"
    ) -ForegroundColor Gray

    $invokeArguments =
    New-Object "System.Object[]" 1

    $invokeArguments[0] =
    $createInArray

    try {

      $createResponse =
      $createObjectsMethod.Invoke(
        $dataManagementService,
        $invokeArguments
      )
    }
    catch {

      $realException =
      $_.Exception

      while ($null -ne $realException.InnerException) {

        $realException =
        $realException.InnerException
      }

      $errorMessage =
      $realException.Message

      if (
        $errorMessage -match
        '(?i)already exists|ja existe|jÃ¡ existe|duplicate'
      ) {

        Write-Host (
          "  [WARNING] O codigo '$candidateCode' ja existe."
        ) -ForegroundColor Yellow

        continue
      }

      throw (
        "Falha ao executar CreateObjects para " +
        "'$candidateCode': " +
        $errorMessage
      )
    }

    if ($null -eq $createResponse) {
      throw "CreateObjects retornou NULL."
    }

    # ====================================================
    # Process Teamcenter errors
    # ====================================================

    $serviceData =
    $createResponse.ServiceData

    if ($null -ne $serviceData) {

      $serviceErrors =
      Get-TeamcenterServiceErrors `
        -ServiceData $serviceData

      if ($serviceErrors.Count -gt 0) {

        $joinedErrors =
        $serviceErrors -join " | "

        throw (
          "O Teamcenter rejeitou a criacao: " +
          $joinedErrors
        )
      }
    }

    # ====================================================
    # Read returned objects
    # ====================================================

    $createdObjects =
    [System.Collections.Generic.List[object]]::new()

    if ($null -ne $createResponse.Output) {

      foreach ($outputEntry in $createResponse.Output) {

        if ($null -eq $outputEntry) {
          continue
        }

        $outputEntryType =
        $outputEntry.GetType()

        foreach (
          $field in $outputEntryType.GetFields(
            [System.Reflection.BindingFlags]::Public -bor
            [System.Reflection.BindingFlags]::Instance
          )
        ) {

          $fieldValue =
          $field.GetValue(
            $outputEntry
          )

          if ($null -eq $fieldValue) {
            continue
          }

          if (
            $fieldValue -is
            [System.Collections.IEnumerable] -and
            $fieldValue -isnot [string]
          ) {

            foreach ($returnedObject in $fieldValue) {

              if (
                $null -ne $returnedObject -and
                -not $createdObjects.Contains(
                  $returnedObject
                )
              ) {

                $createdObjects.Add(
                  $returnedObject
                )
              }
            }
          }
          elseif (
            $fieldValue.GetType().FullName -like
            "Teamcenter.Soa.Client.Model.*"
          ) {

            if (
              -not $createdObjects.Contains(
                $fieldValue
              )
            ) {

              $createdObjects.Add(
                $fieldValue
              )
            }
          }
        }
      }
    }

    if ($null -ne $serviceData) {

      for (
        $objectIndex = 0
        $objectIndex -lt
        $serviceData.SizeOfCreatedObjects()
        $objectIndex++
      ) {

        $createdObject =
        $serviceData.GetCreatedObject(
          $objectIndex
        )

        if (
          $null -ne $createdObject -and
          -not $createdObjects.Contains(
            $createdObject
          )
        ) {

          $createdObjects.Add(
            $createdObject
          )
        }
      }
    }

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

    # ====================================================
    # Remove wrappers PowerShell dos objetos retornados
    # ====================================================

    if ($null -ne $createdItem) {

      $itemBaseObject =
      $createdItem.PSObject.BaseObject

      if ($null -ne $itemBaseObject) {
        $createdItem = $itemBaseObject
      }
    }

    if ($null -ne $createdRevision) {

      $revisionBaseObject =
      $createdRevision.PSObject.BaseObject

      if ($null -ne $revisionBaseObject) {
        $createdRevision = $revisionBaseObject
      }
    }

    if ($null -eq $createdItem) {
      throw "O Item criado nao foi retornado pelo CreateObjects."
    }

    Write-Host (
      "  -> Tipo do Item retornado: [" +
      $createdItem.GetType().FullName +
      "]"
    ) -ForegroundColor Gray

    if ($null -ne $createdRevision) {

      Write-Host (
        "  -> Tipo da revisao retornada: [" +
        $createdRevision.GetType().FullName +
        "]"
      ) -ForegroundColor Gray
    }
    else {

      Write-Host (
        "  [WARNING] A revisao nao veio no retorno. " +
        "Ela sera consultada pelo Item."
      ) -ForegroundColor Yellow
    }

    Write-Host `
      "[OK] DCA item created: $candidateCode" `
      -ForegroundColor Green

    return [PSCustomObject]@{
      Code = $candidateCode
      Item = $createdItem
      Revision = $createdRevision
    }
  }

  throw (
    "Nao foi possivel criar o item depois de " +
    "$MaximumAttempts tentativa(s)."
  )
}
