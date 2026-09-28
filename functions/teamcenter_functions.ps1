# === Teamcenter integration helper functions ===

# Section: Establish the Teamcenter connection
# ============================================================
# TEAMCENTER IMPORTER AVAILABILITY
# Verifica se o Importar GD ja esta instalado localmente.
# Caso nao esteja, executa o instalador existente.
# ============================================================

function Confirm-TeamcenterImporter {

  $importerExecutablePath =
  "C:\Temp\ImportarGD\Importar GD.exe"

  if (-not (
      Test-Path `
        -LiteralPath $importerExecutablePath `
        -PathType Leaf
    )) {

    throw (
      "Importar GD nao encontrado em '$importerExecutablePath'. " +
      "Execute primeiro o instalador do PDMtoPLM."
    )
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
  "http://perto30-novo.perto.com.br:8080/tc"

  if (-not (
      Test-Path -LiteralPath $importerExecutablePath -PathType Leaf
    )) {

    throw  "Teamcenter importer executable not found at '$importerExecutablePath'."
  }

  $script:ImporterAssembly =
  [System.Reflection.Assembly]::LoadFrom(
    $importerExecutablePath
  )

  if ($null -eq $script:ImporterAssembly) {

    throw  "Teamcenter importer assembly could not be loaded."
  }

  $sessionType =
  $script:ImporterAssembly.GetType(
    "Teamcenter.ClientX.Session"
  )

  if ($null -eq $sessionType) {

    throw  "Teamcenter.ClientX.Session type was not found."
  }

  $script:TeamcenterSession =
  [System.Activator]::CreateInstance(
    $sessionType,
    @(
      $teamcenterServerUrl
    )
  )

  if ($null -eq $script:TeamcenterSession) {

    throw  "Teamcenter session returned NULL."
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

    throw  "Teamcenter login returned NULL."
  }

  $script:TeamcenterFunctions =
  $script:ImporterAssembly.GetType(
    "ImportarGD.Controller.Functions"
  )

  if ($null -eq $script:TeamcenterFunctions) {

    throw  "ImportarGD.Controller.Functions type was not found."
  }

  return $script:TeamcenterSession
}
function Show-PdfImporterMethods {

  $pdfMethods =
  @(
    $script:TeamcenterFunctions.GetMethods() |
      Where-Object {
      $_.Name -like "*PDF*"
    }
  )

  if ($pdfMethods.Count -eq 0) {

    Write-Host `
      "  [WARNING] Nenhum metodo contendo PDF foi encontrado." `
      -ForegroundColor Yellow

    return
  }

  foreach ($method in $pdfMethods) {

    $parameters =
    @(
      $method.GetParameters() |
        ForEach-Object {
        "$($_.ParameterType.FullName) $($_.Name)"
      }
    )

    Write-Host ""
    Write-Host "  Metodo: $($method.Name)" -ForegroundColor Cyan
    Write-Host "  Retorno: $($method.ReturnType.FullName)" -ForegroundColor Gray
    Write-Host "  Parametros: $($parameters -join ', ')" -ForegroundColor Gray
  }
}
# Section: Resolve a Teamcenter API method
function Get-TeamcenterMethod {

  param(
    [Parameter(Mandatory = $true)]
    [string]$MethodName,

    [Parameter(Mandatory = $true)]
    [int]$ParameterCount
  )

  if ($null -eq $script:TeamcenterFunctions) {

    throw  "Teamcenter functions are not loaded. Run Connect-Teamcenter first."
  }

  $method =
  $script:TeamcenterFunctions.GetMethods() |
    Where-Object {
    $_.Name -eq $MethodName -and
    $_.GetParameters().Count -eq $ParameterCount
  } |
    Select-Object -First 1

  if ($null -eq $method) {

    throw  "Teamcenter method '$MethodName' with $ParameterCount parameter(s) was not found."
  }

  return $method
}

# Section: Retrieve a Teamcenter revision
function Get-TeamcenterRevision {

  param(
    [Parameter(Mandatory = $true)]
    $Item
  )

  if ($null -eq $Item) {

    throw  "Teamcenter item was not provided."
  }

  $getRevisionMethod =
  Get-TeamcenterMethod -MethodName "getItemRevisionfromItem"  -ParameterCount 1

  $revision =
  $getRevisionMethod.Invoke(
    $null,
    @(
      $Item
    )
  )

  return $revision
}

# Section: Retrieve a Teamcenter item
function Get-TeamcenterItem {

  param(
    [Parameter(Mandatory = $true)]
    [string]$ItemCode,

    [string]$CompanyCode = "02"
  )

  $getItemMethod =
  Get-TeamcenterMethod -MethodName "getItem"  -ParameterCount 2

  $item =
  $getItemMethod.Invoke(
    $null,
    @(
      $ItemCode,
      $CompanyCode
    )
  )

  return $item
}

# Section: Create the next Teamcenter item
function New-NextTeamcenterItem {

  param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$SourceCode,

    [string]$CompanyCode = "02",

    [string]$ItemType = "GD5DesignPerto",

    [ValidateRange(1, 10000)]
    [int]$MaximumAttempts = 100
  )

  if ($SourceCode -match '^(.*)-(\d+)$') {

    $baseCode =
    $Matches[1]
  }
  else {

    $baseCode =
    $SourceCode
  }

  $getItemMethod =
  Get-TeamcenterMethod `
    -MethodName "getItem" `
    -ParameterCount 2

  $createItemMethod =
  Get-TeamcenterMethod `
    -MethodName "criarItem" `
    -ParameterCount 3

  for (
    $attempt = 0
    $attempt -le $MaximumAttempts
    $attempt++
  ) {

    if ($attempt -eq 0) {

      $candidateCode =
      $baseCode
    }
    else {

      $candidateCode =
      "$baseCode-$attempt"
    }

    Write-Host "Checking: $candidateCode"

    $existingItem =
    $getItemMethod.Invoke(
      $null,
      @(
        $candidateCode,
        $CompanyCode
      )
    )

    if ($null -ne $existingItem) {

      Write-Host `
        "[WARNING] Item already exists: $candidateCode" `
        -ForegroundColor Yellow

      continue
    }

    Write-Host `
      "[INFO] Creating item: $candidateCode" `
      -ForegroundColor Gray

    $createdItem =
    $createItemMethod.Invoke(
      $null,
      @(
        $candidateCode,
        $ItemType,
        $CompanyCode
      )
    )

    if ($null -eq $createdItem) {

      throw (
        "O metodo criarItem retornou NULL. " +
        "Codigo: '$candidateCode'. " +
        "Tipo: '$ItemType'. " +
        "Empresa: '$CompanyCode'."
      )
    }

    Write-Host `
      "[OK] Item created: $candidateCode" `
      -ForegroundColor Green

    return [PSCustomObject]@{
      Code = $candidateCode
      Item = $createdItem
    }
  }

  throw (
    "Nao foi possivel criar um item depois de " +
    "$MaximumAttempts tentativas."
  )
}
# Section: Import a dataset into Teamcenter
function Import-TeamcenterDataset {

  param(
    [Parameter(Mandatory = $true)]
    $Revision,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$ItemCode,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$FilePath,

    [Parameter(Mandatory = $true)]
    [ValidateSet(
      "ImportarPrt",
      "ImportarJT",
      "ImportarDWG"
    )]
    [string]$ImporterMethod
  )

  if ($null -eq $Revision) {

    throw  "Teamcenter revision was not provided for '$ItemCode'."
  }

  if (-not (
      Test-Path -LiteralPath $FilePath -PathType Leaf
    )) {

    throw  "Import file not found at '$FilePath'."
  }

  $importMethod =
  Get-TeamcenterMethod -MethodName $ImporterMethod -ParameterCount 5

  $importResult =
  $importMethod.Invoke(
    $null,
    @(
      $ItemCode,
      "",
      $FilePath,
      $Revision,
      $true
    )
  )

  return $importResult
}
# Section: Import a PDF file
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

  if (-not (
      Test-Path `
        -LiteralPath $FilePath `
        -PathType Leaf
    )) {

    throw "PDF nao encontrado em '$FilePath'."
  }

  if ([System.IO.Path]::GetExtension($FilePath) -ine ".pdf") {
    throw "O arquivo informado nao possui extensao PDF."
  }

  $importMethod =
  Get-TeamcenterMethod `
    -MethodName "ImportarPDF" `
    -ParameterCount 5

  return $importMethod.Invoke(
    $null,
    @(
      $ItemCode,
      "",
      $FilePath,
      $Revision,
      $true
    )
  )
}
# Section: Import a PRT file
function Import-TeamcenterPrt {

  param(
    [Parameter(Mandatory = $true)]
    $Revision,

    [Parameter(Mandatory = $true)]
    [string]$ItemCode,

    [Parameter(Mandatory = $true)]
    [string]$FilePath
  )

  return Import-TeamcenterDataset -Revision $Revision -ItemCode $ItemCode -FilePath $FilePath -ImporterMethod "ImportarPrt"
}

# Section: Import a JT file
function Import-TeamcenterJt {

  param(
    [Parameter(Mandatory = $true)]
    $Revision,

    [Parameter(Mandatory = $true)]
    [string]$ItemCode,

    [Parameter(Mandatory = $true)]
    [string]$FilePath
  )

  return Import-TeamcenterDataset -Revision $Revision -ItemCode $ItemCode -FilePath $FilePath -ImporterMethod "ImportarJT"
}

# Section: Import a DWG file
function Import-TeamcenterDwg {

  param(
    [Parameter(Mandatory = $true)]
    $Revision,

    [Parameter(Mandatory = $true)]
    [string]$ItemCode,

    [Parameter(Mandatory = $true)]
    [string]$FilePath
  )

  return Import-TeamcenterDataset -Revision $Revision -ItemCode $ItemCode -FilePath $FilePath -ImporterMethod "ImportarDWG"
}
