param(
  [string]$SearchRoot = "C:\VAULT_ROOT",

  [string]$SourceCode,

  [string]$ItemName,

  [string]$VaultName = "VAULT_NAME",

  [string]$PdmLibraryPath = "C:\PATH\TO\Interop.EdmLib.dll",

  # Export-Clixml credential file. Can be overridden with DCA_VAULT_CREDENTIAL.
  [string]$VaultCredentialPath = "<VAULT_CREDENTIAL_CLIXML_PATH>",

  # Enumerates local files without using the PDM API.
  [switch]$NoVaultApi,

  # Search only; does not connect to Teamcenter or create objects.
  [switch]$Preview
)

$ErrorActionPreference = "Stop"
$script:DcaVault = $null
$script:DcaVaultTried = $false

if (-not [string]::IsNullOrWhiteSpace($env:DCA_VAULT_NAME)) {
  $VaultName = $env:DCA_VAULT_NAME
}

if (-not [string]::IsNullOrWhiteSpace($env:DCA_PDM_LIB)) {
  $PdmLibraryPath = $env:DCA_PDM_LIB
}

if (-not [string]::IsNullOrWhiteSpace($env:DCA_VAULT_CREDENTIAL)) {
  $VaultCredentialPath = $env:DCA_VAULT_CREDENTIAL
}

try {
  [Console]::InputEncoding = [System.Text.Encoding]::UTF8
  [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
}
catch {
}

$teamcenterFunctionsPath =
Join-Path $PSScriptRoot "functions\teamcenter_functions.ps1"

if (-not (Test-Path -LiteralPath $teamcenterFunctionsPath -PathType Leaf)) {
  Write-Host "[ERROR] Helper file not found:" -ForegroundColor Red
  Write-Host $teamcenterFunctionsPath -ForegroundColor Red
  exit 1
}

. $teamcenterFunctionsPath

$requiredFunctions = @(
  "Connect-Teamcenter",
  "Get-TeamcenterMethod",
  "Get-TeamcenterRevision",
  "Get-TeamcenterDataManagementService",
  "Get-TeamcenterServiceErrors",
  "Import-TeamcenterPdf",
  "New-DcaTeamcenterItem"
)

foreach ($requiredFunction in $requiredFunctions) {

  $loadedFunction =
  Get-Command -Name $requiredFunction -CommandType Function -ErrorAction SilentlyContinue

  if ($null -eq $loadedFunction) {
    Write-Host (
      "[ERROR] Function '$requiredFunction' was not loaded from " +
      "'$teamcenterFunctionsPath'."
    ) -ForegroundColor Red
    exit 1
  }
}

function Write-Section {

  param(
    [Parameter(Mandatory = $true)]
    [string]$Title,

    [switch]$NoLeadingBlank
  )

  if (-not $NoLeadingBlank) {
    Write-AnimatedLine ""
  }
  Write-AnimatedLine ("+" + ("-" * 68) + "+") -Color Gray
  Write-AnimatedLine ("| {0,-66} |" -f $Title) -Color White
  Write-AnimatedLine ("+" + ("-" * 68) + "+") -Color Gray
}

function Write-AnimatedLine {

  param(
    [Parameter(Mandatory = $true)]
    [AllowEmptyString()]
    [string]$Message,

    [System.ConsoleColor]$Color = [System.ConsoleColor]::Gray,

    [ValidateRange(0, 500)]
    [int]$DelayMilliseconds = 30
  )

  Write-Host $Message -ForegroundColor $Color

  if ($DelayMilliseconds -gt 0) {
    Start-Sleep -Milliseconds $DelayMilliseconds
  }
}

function Write-Success {

  param(
    [Parameter(Mandatory = $true)]
    [string]$Message
  )

  Write-AnimatedLine "  [OK] $Message" -Color Green
}

function Write-Failure {

  param(
    [Parameter(Mandatory = $true)]
    [string]$Message
  )

  Write-AnimatedLine "  [ERROR] $Message" -Color Red
}

function Write-Warn {

  param(
    [Parameter(Mandatory = $true)]
    [string]$Message
  )

  Write-AnimatedLine "  [WARNING] $Message" -Color Yellow
}

function Write-Info {

  param(
    [Parameter(Mandatory = $true)]
    [string]$Message
  )

  Write-AnimatedLine "  $Message" -Color Gray
}

function Show-DcaConfigurationWarnings {

  $warnings = [System.Collections.Generic.List[string]]::new()

  if ($SearchRoot -eq "C:\VAULT_ROOT") {
    $warnings.Add(
      "SearchRoot is still set to 'C:\VAULT_ROOT'. Configure the local vault path."
    )
  }

  if ($VaultName -eq "VAULT_NAME") {
    $warnings.Add(
      "VaultName is still set to 'VAULT_NAME'. Configure the PDM vault name."
    )
  }

  if ($PdmLibraryPath -eq "C:\PATH\TO\Interop.EdmLib.dll") {
    $warnings.Add(
      "PdmLibraryPath is still a placeholder. Configure the Interop.EdmLib.dll path."
    )
  }

  if ($VaultCredentialPath -eq "<VAULT_CREDENTIAL_CLIXML_PATH>") {
    $warnings.Add(
      "VaultCredentialPath is still a placeholder. Configure a credential file or use automatic PDM login."
    )
  }

  foreach ($teamcenterWarning in @(Get-TeamcenterConfigurationWarnings)) {
    $warnings.Add([string]$teamcenterWarning)
  }

  if ($warnings.Count -gt 0) {
    Write-AnimatedLine ""
    Write-Section -Title "CONFIGURATION WARNINGS"

    foreach ($warning in $warnings) {
      Write-Warn $warning
    }

    Write-AnimatedLine ""
  }
}

# The PDM API may return files from the server that are not in the local cache.
function Get-DcaVault {

  if ($NoVaultApi) {
    return $null
  }

  if ($null -ne $script:DcaVault) {
    return $script:DcaVault
  }

  if ($script:DcaVaultTried) {
    return $null
  }

  $script:DcaVaultTried = $true

  $passwordPointer = [System.IntPtr]::Zero

  try {

    if (
      [string]::IsNullOrWhiteSpace($PdmLibraryPath) -or
      $PdmLibraryPath -like "<*>" -or
      -not (Test-Path -LiteralPath $PdmLibraryPath -PathType Leaf)
    ) {
      throw (
        "Interop.EdmLib.dll not found at '$PdmLibraryPath'. " +
        "Specify -PdmLibraryPath with the value used by PDMtoPLM."
      )
    }

    Add-Type -Path $PdmLibraryPath

    $vault = New-Object EdmLib.EdmVault5Class

    $hasCredentialFile =
    -not [string]::IsNullOrWhiteSpace($VaultCredentialPath) -and
    $VaultCredentialPath -notlike "<*>" -and
    (Test-Path -LiteralPath $VaultCredentialPath -PathType Leaf)

    if ($hasCredentialFile) {

      $credential = Import-Clixml -LiteralPath $VaultCredentialPath

      if ($null -eq $credential) {
        throw "The vault credential file could not be read."
      }

      $securePassword = $credential.SenhaCriptografada | ConvertTo-SecureString

      $passwordPointer =
      [Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePassword)

      $plainTextPassword =
      [Runtime.InteropServices.Marshal]::PtrToStringBSTR($passwordPointer)

      $vault.Login($credential.Usuario, $plainTextPassword, $VaultName)
    }
    else {

      $vault.LoginAuto($VaultName, 0)
    }

    if (-not $vault.IsLoggedIn) {
      throw "Could not authenticate to the vault '$VaultName'."
    }

    $script:DcaVault = $vault

    return $vault
  }
  catch {

    Write-Warn (
      "The PDM API is unavailable: $($_.Exception.Message) " +
      "Using only the file system."
    )

    return $null
  }
  finally {

    if ($passwordPointer -ne [System.IntPtr]::Zero) {
      [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($passwordPointer)
    }

    Remove-Variable plainTextPassword -ErrorAction SilentlyContinue
  }
}

# Searches the vault by name and returns PDFs for later filtering.
function Search-DcaVaultPdfEntries {

  param(
    [Parameter(Mandatory = $true)]
    $Vault,

    [Parameter(Mandatory = $true)]
    [string]$SearchText
  )

  $likePattern = $SearchText.Replace("*", "%").Replace("?", "_")

  if ($likePattern -notmatch "[%_]") {
    $likePattern = "%$likePattern%"
  }

  $search = $Vault.CreateSearch()
  $search.FileName = $likePattern
  $search.FindHistoricStates = $false

  $entries = [System.Collections.Generic.List[object]]::new()
  $currentResult = $search.GetFirstResult()

  while ($null -ne $currentResult) {

    $resultName = [string]$currentResult.Name

    if ($resultName -match '(?i)\.pdf$') {

      $entries.Add(
        [PSCustomObject]@{
          Name = $resultName
          BaseName = [System.IO.Path]::GetFileNameWithoutExtension($resultName).Trim()
          FullName = [string]$currentResult.Path
          FromVault = $true
        }
      )
    }

    $currentResult = $search.GetNextResult()
  }

  return $entries.ToArray()
}

function Get-DcaDiskPdfEntries {

  param(
    [Parameter(Mandatory = $true)]
    [string]$FolderPath
  )

  $entries = [System.Collections.Generic.List[object]]::new()

  $allObjects =
  @(Get-ChildItem -LiteralPath $FolderPath -Recurse -Force -ErrorAction SilentlyContinue)

  foreach ($fileSystemObject in $allObjects) {

    if ($fileSystemObject.PSIsContainer) {
      continue
    }

    if ($fileSystemObject.Name -notmatch '(?i)\.pdf$') {
      continue
    }

    $entries.Add(
      [PSCustomObject]@{
        Name = $fileSystemObject.Name
        BaseName = [System.IO.Path]::GetFileNameWithoutExtension($fileSystemObject.Name).Trim()
        FullName = $fileSystemObject.FullName
        FromVault = $false
      }
    )
  }

  return $entries.ToArray()
}

# Ensures that the selected PDF is available in the local PDM cache.
function Confirm-DcaLocalPdf {

  param(
    [Parameter(Mandatory = $true)]
    $Entry
  )

  if (Test-Path -LiteralPath $Entry.FullName -PathType Leaf) {
    return $Entry.FullName
  }

  $vault = $script:DcaVault

  if (-not $Entry.FromVault -or $null -eq $vault) {
    throw "PDF not found on disk: '$($Entry.FullName)'."
  }

  Write-Info "Downloading the PDF from the vault..."

  $parentFolder = $null

  $pdmFile = $vault.GetFileFromPath($Entry.FullName, [ref]$parentFolder)

  if ($null -eq $pdmFile) {
    throw "Could not retrieve the file from the vault."
  }

  if ($null -eq $parentFolder) {
    throw "Could not retrieve the file folder from the vault."
  }

  $fileVersion = 0
  $folderId = $parentFolder.ID

  $pdmFile.GetFileCopy(0, [ref]$fileVersion, [ref]$folderId, 0, "")

  $localCachePath = $pdmFile.GetLocalPath($parentFolder.ID)

  if (-not (Test-Path -LiteralPath $localCachePath -PathType Leaf)) {
    throw "The file was not found in the local PDM cache: '$localCachePath'."
  }

  return $localCachePath
}

# Extracts a standard code from the descriptive PDF name.
function Get-NormaCodeFromText {

  param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$Text
  )

  $trimmedText =
  $Text.Trim()

  $code =
  $null

  $title =
  $null

  $patterns =
  @(
    # AMS A 21180 A
    '^(?<Code>AMS\s+[A-Z]\s+\d+[A-Z0-9-]*(?:\s+[A-Z])?)(?:\s+-?\s*(?<Title>.*))?$',

    # AMS STD 1595
    '^(?<Code>AMS\s+STD\s+\d+[A-Z0-9-]*)(?:\s+-?\s*(?<Title>.*))?$',

    # AMS M 3171 and AMS S5000
    '^(?<Code>AMS\s+[A-Z]\s*\d+[A-Z0-9-]*)(?:\s+-?\s*(?<Title>.*))?$',

    # AMS-QQ-N-290, AMS-STD-2175, AMS-C-26074
    '^(?<Code>AMS(?:-[A-Z0-9]+)+)(?:\s+-?\s*(?<Title>.*))?$',

    # AMS 2759-3, AMS 2440C, AMS 2248
    '^(?<Code>AMS\s+\d+[A-Z]?(?:-\d+)?)(?:\s+-?\s*(?<Title>.*))?$',

    # AMS2470, AMS2773, AMS5659
    '^(?<Code>AMS\d+[A-Z]?(?:-\d+)?)(?:\s+-?\s*(?<Title>.*))?$'
  )

  foreach ($pattern in $patterns) {

    if ($trimmedText -notmatch $pattern) {
      continue
    }

    $code =
    $Matches["Code"].Trim()

    if ($Matches.ContainsKey("Title")) {

      $title =
      [string]$Matches["Title"]

      if (-not [string]::IsNullOrWhiteSpace($title)) {

        $title =
        $title.Trim(
          " ",
          "-",
          ",",
          "."
        )
      }
    }

    return [PSCustomObject]@{
      Code = $code
      Title = $title
      Parsed = $true
    }
  }

  return [PSCustomObject]@{
    Code = $trimmedText
    Title = $null
    Parsed = $false
  }
}
function ConvertFrom-PdfFileName {

  param(
    [Parameter(Mandatory = $true)]
    [string]$BaseName,

    [Parameter(Mandatory = $true)]
    [string]$DocumentType
  )

  $name = $BaseName.Trim()
  $sourceCodeText = $name
  $clientRevision = $null

  if ($name -match '^(?<Code>[^\[\]]+?)\s*\[(?<Revision>[^\]]+)\]\s*$') {
    $sourceCodeText = $Matches["Code"].Trim()
    $clientRevision = $Matches["Revision"].Trim().ToUpper()
  }

  $codeParsed = $true

  $documentTitle =
  $null

  if ($DocumentType -eq "NormaExterna") {

    $normaInfo =
    Get-NormaCodeFromText `
      -Text $sourceCodeText

    $sourceCodeText =
    $normaInfo.Code

    $documentTitle =
    $normaInfo.Title

    $codeParsed =
    $normaInfo.Parsed
  }

  return [PSCustomObject]@{
    SourceCode = $sourceCodeText
    ClientRevision = $clientRevision
    DocumentTitle = $documentTitle
    CodeParsed = $codeParsed
  }
}

function Test-DcaCodeMatch {

  param(
    [string]$BaseName,
    [string]$ParsedCode,
    [string]$Pattern,
    [bool]$UsesWildcard
  )

  if ($UsesWildcard) {
    return (($BaseName -like $Pattern) -or ($ParsedCode -like $Pattern))
  }

  return (($BaseName -ieq $Pattern) -or ($ParsedCode -ieq $Pattern))
}

function Select-DcaPdfByCode {

  param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$FolderPath,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$Code
  )

  if (-not (Test-Path -LiteralPath $FolderPath -PathType Container)) {
    throw "Vault root not found at '$FolderPath'."
  }

  $searchPattern = $Code.Trim()

  if ([string]::IsNullOrWhiteSpace($searchPattern)) {
    throw "The search code is empty."
  }

  $usesWildcard =
  $searchPattern.IndexOf("*") -ge 0 -or
  $searchPattern.IndexOf("?") -ge 0

  Write-AnimatedLine ""

  if ($usesWildcard) {
    Write-Info "Searching by pattern: [$searchPattern]"
  }
  else {
    Write-Info "Searching by exact code: [$searchPattern]"
  }

  $rootFolders =
  @(Get-ChildItem -LiteralPath $FolderPath -Directory -Force -ErrorAction Stop)

  $documentationFolder =
  $rootFolders |
    Where-Object { $_.Name -like "DOCUMENTATION*" } |
    Select-Object -First 1

  if ($null -eq $documentationFolder) {

    $visibleFolderNames = @($rootFolders | ForEach-Object { $_.Name })

    throw (
      "The documentation folder was not found at '$FolderPath'. " +
      "Folders visiveis: " + ($visibleFolderNames -join ", ")
    )
  }

  Write-Info "Documentation folder found."

  $categoryDefinitions = @(
    [PSCustomObject]@{
      FolderName = "ORIGINAL_DRAWINGS"
      DocumentType = "Original"
      DisplayName = "Original Drawing"
    },
    [PSCustomObject]@{
      FolderName = "PROCESS_DOCUMENTS"
      DocumentType = "Processo"
      DisplayName = "Process Document"
    },
    [PSCustomObject]@{
      FolderName = "EXTERNAL_STANDARDS"
      DocumentType = "NormaExterna"
      DisplayName = "Externall Standard"
    }
  )

  $documentationSubfolders =
  @(Get-ChildItem -LiteralPath $documentationFolder.FullName -Directory -Force -ErrorAction Stop)

  $searchFolders = [System.Collections.Generic.List[object]]::new()

  foreach ($categoryDefinition in $categoryDefinitions) {

    $categoryFolder =
    $documentationSubfolders |
      Where-Object { $_.Name.Trim() -ieq $categoryDefinition.FolderName } |
      Select-Object -First 1

    if ($null -eq $categoryFolder) {
      Write-Warn "Folder not found: $($categoryDefinition.FolderName)"
      continue
    }

    $searchFolders.Add(
      [PSCustomObject]@{
        DirectoryPath = $categoryFolder.FullName
        DocumentType = $categoryDefinition.DocumentType
        DisplayName = $categoryDefinition.DisplayName
      }
    )
  }

  if ($searchFolders.Count -eq 0) {

    $visibleSubfolderNames = @($documentationSubfolders | ForEach-Object { $_.Name })

    throw (
      "No supported folder was found in " +
      "'$($documentationFolder.FullName)'. Folders visiveis: " +
      ($visibleSubfolderNames -join ", ")
    )
  }

  $matchingFiles = [System.Collections.Generic.List[object]]::new()

  # A single server search (PDM API); results are then split by category.
  $apiEntries = $null
  $vault = Get-DcaVault

  if ($null -ne $vault) {

    Write-Info "Querying the vault..."

    try {
      $apiEntries = @(Search-DcaVaultPdfEntries -Vault $vault -SearchText $searchPattern)
    }
    catch {

      Write-Warn (
        "The PDM API search failed: $($_.Exception.Message) " +
        "Using the file system."
      )

      $apiEntries = $null
    }
  }

  $separator = [string][System.IO.Path]::DirectorySeparatorChar

  foreach ($searchFolder in $searchFolders) {

    if ($null -ne $apiEntries) {

      $categoryPrefix = $searchFolder.DirectoryPath.TrimEnd($separator) + $separator

      $pdfEntries =
      @(
        $apiEntries |
          Where-Object {
          $_.FullName.StartsWith($categoryPrefix, [System.StringComparison]::OrdinalIgnoreCase)
        } |
          Sort-Object FullName
      )

    }
    else {

      Write-Info ("Querying {0}..." -f $searchFolder.DisplayName)

      $pdfEntries =
      @(
        Get-DcaDiskPdfEntries -FolderPath $searchFolder.DirectoryPath |
          Sort-Object FullName
      )
    }

    if ($pdfEntries.Count -eq 0 -and $null -eq $apiEntries) {
      Write-Warn (
        "No PDF was found on disk and the PDM API was not used. " +
        "The content may exist only on the PDM server."
      )
    }

    foreach ($pdfEntry in $pdfEntries) {

      $parsedName =
      ConvertFrom-PdfFileName `
        -BaseName $pdfEntry.BaseName `
        -DocumentType $searchFolder.DocumentType

      $isMatch =
      Test-DcaCodeMatch `
        -BaseName $pdfEntry.BaseName `
        -ParsedCode $parsedName.SourceCode `
        -Pattern $searchPattern `
        -UsesWildcard $usesWildcard

      if (-not $isMatch) {
        continue
      }

      $matchingFiles.Add(
        [PSCustomObject]@{
          File = $pdfEntry
          SourceCode = $parsedName.SourceCode
          ClientRevision = $parsedName.ClientRevision
          DocumentTitle = $parsedName.DocumentTitle
          DocumentType = $searchFolder.DocumentType
          TypeDisplayName = $searchFolder.DisplayName
          CodeParsed = $parsedName.CodeParsed
        }
      )
    }
  }

  [int]$matchCount = $matchingFiles.Count

  if ($matchCount -eq 0) {
    throw "No PDF was found for the search '$searchPattern'."
  }

  Write-AnimatedLine ""
  Write-AnimatedLine ("  SEARCH RESULTS  ({0} found)" -f $matchCount) -Color White
  Write-AnimatedLine ("  Search: {0}" -f $searchPattern) -Color Gray
  Write-AnimatedLine ("  " + ("-" * 72)) -Color DarkGray

  for ($index = 0; $index -lt $matchCount; $index++) {

    $number = $index + 1
    $currentMatch = $matchingFiles[$index]
    $revisionDisplay = [string]$currentMatch.ClientRevision

    if ([string]::IsNullOrWhiteSpace($revisionDisplay)) {
      $revisionDisplay = "not provided"
    }

    $nameDisplay = [string]$currentMatch.DocumentTitle

    if ([string]::IsNullOrWhiteSpace($nameDisplay)) {
      $nameDisplay = "not provided"
    }

    Write-AnimatedLine ("  [{0}] {1}" -f $number, $currentMatch.File.Name) -Color White
    Write-AnimatedLine ("       Type:     {0}" -f $currentMatch.TypeDisplayName) -Color White
    Write-AnimatedLine ("       Code:   {0}" -f $currentMatch.SourceCode) -Color Gray
    Write-AnimatedLine ("       Name:     {0}" -f $nameDisplay) -Color Gray
    Write-AnimatedLine ("       Revision:  {0}" -f $revisionDisplay) -Color Gray
    Write-AnimatedLine ("       Location:    {0}" -f $currentMatch.File.FullName) -Color DarkGray
    Write-AnimatedLine ""
  }

  if ($matchCount -eq 1) {
    Write-Success "The only matching PDF was selected automatically."
    return $matchingFiles[0]
  }

  while ($true) {

    $selectionText = Read-Host "Enter the desired PDF number (1 to $matchCount)"
    $selectedNumber = 0

    $validNumber =
    [System.Int32]::TryParse($selectionText, [ref]$selectedNumber)

    if (-not $validNumber -or $selectedNumber -lt 1 -or $selectedNumber -gt $matchCount) {
      Write-Warn "Invalid option. Enter a number between 1 and $matchCount."
      continue
    }

    $selectedFile = $matchingFiles[$selectedNumber - 1]

    Write-AnimatedLine ""
    Write-Success "Selected PDF: $($selectedFile.File.FullName)"

    return $selectedFile
  }
}

function Copy-PdfToTemporaryFolder {

  param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$SourcePdfPath,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$ItemCode
  )

  if (-not (Test-Path -LiteralPath $SourcePdfPath -PathType Leaf)) {
    throw "Source PDF not found: $SourcePdfPath"
  }

  $sourceFile = Get-Item -LiteralPath $SourcePdfPath -ErrorAction Stop

  if ($sourceFile.Extension -ine ".pdf") {
    throw "The source file does not have a PDF extension."
  }

  if ($sourceFile.Length -le 0) {
    throw "The source PDF is empty."
  }

  $temporaryFolder = Join-Path $env:TEMP "DCAtoPLM"

  if (-not (Test-Path -LiteralPath $temporaryFolder -PathType Container)) {
    $null = New-Item -Path $temporaryFolder -ItemType Directory -Force -ErrorAction Stop
  }

  $safeItemCode = $ItemCode -replace '[\\/:*?"<>|]', '_'
  $temporaryPdfPath = Join-Path -Path $temporaryFolder -ChildPath "$safeItemCode.pdf"

  if (Test-Path -LiteralPath $temporaryPdfPath -PathType Leaf) {
    Remove-Item -LiteralPath $temporaryPdfPath -Force -ErrorAction Stop
  }

  Write-Info "Preparing the PDF for import..."

  Copy-Item -LiteralPath $SourcePdfPath -Destination $temporaryPdfPath -Force -ErrorAction Stop

  if (-not (Test-Path -LiteralPath $temporaryPdfPath -PathType Leaf)) {
    throw "The PDF was not created in the temporary folder."
  }

  $temporaryFile = Get-Item -LiteralPath $temporaryPdfPath -ErrorAction Stop

  if ($temporaryFile.Length -ne $sourceFile.Length) {
    throw (
      "The temporary copy size differs from the original. " +
      "Original: $($sourceFile.Length) bytes. " +
      "Copia: $($temporaryFile.Length) bytes."
    )
  }

  $stream = $null

  try {

    $stream =
    [System.IO.File]::Open(
      $temporaryPdfPath,
      [System.IO.FileMode]::Open,
      [System.IO.FileAccess]::Read,
      [System.IO.FileShare]::Read
    )

    if ($stream.Length -le 0) {
      throw "The temporary PDF copy is empty."
    }
  }
  finally {
    if ($null -ne $stream) {
      $stream.Dispose()
    }
  }

  Write-Success "PDF copied and validated in the temporary folder."
  return $temporaryFile.FullName
}

function Invoke-DcaMain {

  Show-DcaConfigurationWarnings

  Write-Section -Title "STAGE 1/3 - ENTER SEARCH" -NoLeadingBlank

  $searchPattern = $SourceCode

  if ([string]::IsNullOrWhiteSpace($searchPattern)) {
    $searchPattern = Read-Host "Enter the item code to search; use * for partial search"
  }

  if ([string]::IsNullOrWhiteSpace($searchPattern)) {
    throw "Item code not provided."
  }

  $rootPath = $SearchRoot

  if ([string]::IsNullOrWhiteSpace($rootPath)) {
    $rootPath = "C:\VAULT_ROOT"
  }

  Write-Section -Title "STAGE 2/3 - SELECT DOCUMENT"

  $selectedPdf = Select-DcaPdfByCode -FolderPath $rootPath -Code $searchPattern

  if ($null -eq $selectedPdf) {
    throw "No PDF was selected for the search '$searchPattern'."
  }

  $documentType =
  [string]$selectedPdf.DocumentType

  $itemCodeFromFile =
  [string]$selectedPdf.SourceCode

  $documentTitle =
  [string]$selectedPdf.DocumentTitle

  $itemNameText = $ItemName

  if (
    $documentType -eq "NormaExterna" -and
    -not [string]::IsNullOrWhiteSpace(
      $documentTitle
    )
  ) {

    $itemNameText =
    $documentTitle.Trim()
  }

  if ([string]::IsNullOrWhiteSpace($itemNameText)) {
    $itemNameText = Read-Host "Enter the item name (required)"
  }
  else {
    $displayItemName = $itemNameText

    if ($displayItemName.Length -gt 30) {
      $displayItemName = $displayItemName.Substring(0, 30) + "..."
    }

    $typedItemName =
    Read-Host "Change the item name? (Enter keeps '$displayItemName')"

    if (-not [string]::IsNullOrWhiteSpace($typedItemName)) {
      $itemNameText = $typedItemName
    }
  }

  if ([string]::IsNullOrWhiteSpace($itemNameText)) {
    throw "Item name not provided."
  }

  $itemNameText = $itemNameText.Trim()

  # If the External Standard code cannot be interpreted,
  # the user can provide the code manually.
  if (
    $documentType -eq "NormaExterna" -and
    -not $selectedPdf.CodeParsed
  ) {

    Write-Warn (
      "Could not extract the standard code from: " +
      "'$($selectedPdf.File.BaseName)'."
    )

    $typedCode =
    Read-Host (
      "Enter the standard code " +
      "(Press Enter to use the complete name)"
    )

    if (
      -not [string]::IsNullOrWhiteSpace(
        $typedCode
      )
    ) {

      $itemCodeFromFile =
      $typedCode.Trim()
    }
  }

  $clientRevision = [string]$selectedPdf.ClientRevision

  if ([string]::IsNullOrWhiteSpace($clientRevision)) {

    if ($documentType -eq "NormaExterna") {

      $clientRevision = "000"
      Write-Info "Initial External Standard revision: [000]"
    }
    else {

      $clientRevision = Read-Host "Enter the Client Revision (Original: B or BA4; Process: BA4)"

      if ([string]::IsNullOrWhiteSpace($clientRevision)) {
        throw "Client Revision not provided."
      }
    }
  }

  $clientRevision = $clientRevision.Trim().ToUpper()

  Write-AnimatedLine ""
  Write-Info "Creation summary:"
  Write-AnimatedLine "  Type:    $($selectedPdf.TypeDisplayName) [$documentType]" -Color Gray
  Write-AnimatedLine "  Code:  $itemCodeFromFile" -Color Gray
  Write-AnimatedLine "  Revision: $clientRevision" -Color Gray
  Write-AnimatedLine "  Name:    $itemNameText" -Color Gray
  Write-AnimatedLine "  File: $($selectedPdf.File.FullName)" -Color Gray

  if ($Preview) {

    Write-AnimatedLine ""
    Write-Success "Preview only. Nothing was created in Teamcenter."

    return 0
  }

  $null = Connect-Teamcenter

  Write-Section -Title "STAGE 3/3 - CREATE ITEM AND IMPORT DOCUMENT"

  Write-AnimatedLine ""
  Write-Warn "This stage will create actual items in Teamcenter."

  $confirmation = Read-Host "Enter YES to continue or press Enter to abort"

  if ($confirmation -notmatch "^(?i:yes)$") {

    Write-AnimatedLine ""
    Write-Warn "Aborted by the user. No item was created."

    return 0
  }

  $createdCode = $null

  try {

    $teamcenterDestination =
    New-DcaTeamcenterItem `
      -SourceCode $itemCodeFromFile `
      -ItemName $itemNameText `
      -ClientRevision $clientRevision `
      -DocumentType $documentType

    if ($null -eq $teamcenterDestination) {
      throw "New-DcaTeamcenterItem did not return result for '$itemCodeFromFile'."
    }

    $createdCode = [string]$teamcenterDestination.Code

    if ([string]::IsNullOrWhiteSpace($createdCode)) {
      throw "The created code was not returned."
    }

    Write-Success "Created item: $createdCode"

    $teamcenterItem = $teamcenterDestination.Item

    if ($null -ne $teamcenterItem) {
      $teamcenterItem = $teamcenterItem.PSObject.BaseObject
    }

    if ($null -eq $teamcenterItem) {
      throw "The created item was not returned for '$createdCode'."
    }

    $teamcenterRevision = $teamcenterDestination.Revision

    if ($null -ne $teamcenterRevision) {
      $teamcenterRevision = $teamcenterRevision.PSObject.BaseObject
    }

    if ($null -eq $teamcenterRevision) {

      Write-Info "Locating the item revision..."

      $teamcenterRevision = Get-TeamcenterRevision -Item $teamcenterItem

      if ($null -ne $teamcenterRevision) {
        $teamcenterRevision = $teamcenterRevision.PSObject.BaseObject
      }
    }

    if ($null -eq $teamcenterRevision) {
      throw "The Teamcenter revision was not found for '$createdCode'."
    }

    $revisionTypeName = $teamcenterRevision.GetType().FullName

    if ($revisionTypeName -notmatch "ItemRevision") {
      throw (
        "The returned object is not a valid revision. " +
        "Type received: '$revisionTypeName'."
      )
    }

    $localPdfPath = Confirm-DcaLocalPdf -Entry $selectedPdf.File

    $temporaryPdfPath =
    Copy-PdfToTemporaryFolder `
      -SourcePdfPath $localPdfPath `
      -ItemCode $createdCode

    if ([string]::IsNullOrWhiteSpace($temporaryPdfPath)) {
      throw "Copy-PdfToTemporaryFolder did not return the temporary PDF path."
    }

    Write-Info "Importing the PDF into Teamcenter..."

    $null =
    Import-TeamcenterPdf `
      -Revision $teamcenterRevision `
      -ItemCode $createdCode `
      -FilePath $temporaryPdfPath

    Write-Success "PDF imported: $createdCode"

  }
  catch {

    Write-Failure $_.Exception.Message

    Write-Section -Title "RESULT"
    Write-Failure "$itemCodeFromFile -> FAILED (item in Teamcenter: $createdCode)"

    return 1
  }

  Write-Section -Title "RESULT"
  Write-Success "$itemCodeFromFile -> $createdCode - $itemNameText"
  Write-Success "Item imported to Teamcenter."

  return 0
}

$exitCode = 1

try {
  $exitCode = @(Invoke-DcaMain) | Select-Object -Last 1
}
catch {

  Write-Failure $_.Exception.Message

  $exitCode = 1
}

exit ([int]$exitCode)
