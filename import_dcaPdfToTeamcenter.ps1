# Main script: locate a DCA PDF, collect the required data, and, unless running
# in Preview mode, create the item and import the file into Teamcenter.
param(
  [string]$SearchRoot = $env:DCA_ROOT,

  [string]$SourceCode,

  [string]$ItemName,

  # SolidWorks PDM vault name. Override with DCA_VAULT_NAME.
  [string]$VaultName = $env:DCA_VAULT_NAME,

  [string]$PdmLibraryPath = $env:DCA_PDM_LIB,

  [string]$VaultCredentialPath = $env:DCA_VAULT_CREDENTIAL,

  [ValidateRange(0, 2000)]
  [int]$OutputDelayMilliseconds = 100,

  # Enumerate local files without using the PDM API.
  [switch]$NoVaultApi,

  # Search only; do not connect to Teamcenter or create objects.
  [switch]$Preview
)

function Import-DcaEnvironmentFile {

  param(
    [Parameter(Mandatory = $true)]
    [string]$FilePath
  )

  if (-not (
      Test-Path `
        -LiteralPath $FilePath `
        -PathType Leaf
    )) {

    throw "Arquivo de configuracao nao encontrado: '$FilePath'."
  }

  foreach (
    $line in Get-Content `
      -LiteralPath $FilePath `
      -Encoding UTF8
  ) {

    $trimmedLine =
    $line.Trim()

    if (
      [string]::IsNullOrWhiteSpace($trimmedLine) -or
      $trimmedLine.StartsWith("#")
    ) {
      continue
    }

    $separatorIndex =
    $trimmedLine.IndexOf("=")

    if ($separatorIndex -le 0) {
      continue
    }

    $variableName =
    $trimmedLine.Substring(
      0,
      $separatorIndex
    ).Trim()

    $variableValue =
    $trimmedLine.Substring(
      $separatorIndex + 1
    ).Trim()

    if (
      [string]::IsNullOrWhiteSpace(
        $variableName
      )
    ) {
      continue
    }

    [System.Environment]::SetEnvironmentVariable(
      $variableName,
      $variableValue,
      [System.EnvironmentVariableTarget]::Process
    )
  }
}
$environmentFilePath =
Join-Path `
  -Path $PSScriptRoot `
  -ChildPath ".env"

Import-DcaEnvironmentFile `
  -FilePath $environmentFilePath
$ErrorActionPreference = "Stop"
$script:DcaVault = $null
$script:DcaVaultTried = $false

if (-not [string]::IsNullOrWhiteSpace($env:DCA_VAULT_NAME)) {
  $VaultName = $env:DCA_VAULT_NAME
}

if (-not [string]::IsNullOrWhiteSpace($env:DCA_PDM_LIB)) {
  $PdmLibraryPath = $env:DCA_PDM_LIB
}

try {
  [Console]::InputEncoding = [System.Text.Encoding]::UTF8
  [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
}
catch {
}

$teamcenterFunctionsPath = Join-Path $PSScriptRoot "functions\teamcenter_functions.ps1"

if (-not (Test-Path -LiteralPath $teamcenterFunctionsPath -PathType Leaf)) {
  Write-Host "Algo deu errado: o arquivo do helper nao foi encontrado:" -ForegroundColor Red
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

  $loadedFunction = Get-Command -Name $requiredFunction -CommandType Function -ErrorAction SilentlyContinue

  if ($null -eq $loadedFunction) {
    Write-Host (
      "Algo deu errado: a funcao '$requiredFunction' nao foi carregada de " +
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
    [ValidateRange(0, 2000)]
    [int]$DelayMilliseconds = $OutputDelayMilliseconds
  )

  Write-Host $Message -ForegroundColor $Color

  if ($DelayMilliseconds -gt 0) {
    Start-Sleep -Milliseconds $DelayMilliseconds
  }
}

function Write-SearchResultLine {

  param(
    [Parameter(Mandatory = $true)]
    [AllowEmptyString()]
    [string]$Message,
    [System.ConsoleColor]$Color = [System.ConsoleColor]::Gray
  )

  Write-AnimatedLine `
    -Message $Message `
    -Color $Color `
    -DelayMilliseconds $script:SearchResultDelayMilliseconds
}

function Write-Success {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Message
  )

  Write-AnimatedLine "  $Message" -Color Green
}

function Write-Failure {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Message
  )

  Write-AnimatedLine "  Algo deu errado: $Message" -Color Red
}

function Write-Warn {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Message
  )

  Write-AnimatedLine "  Atencao: $Message" -Color Yellow
}

function Write-Info {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Message
  )

  Write-AnimatedLine "  $Message" -Color Gray
}

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
        "Interop.EdmLib.dll nao encontrada em '$PdmLibraryPath'. " +
        "Informe -PdmLibraryPath (mesmo valor de `$pdmLibraryPath do PDMtoPLM)."
      )
    }

    Add-Type -Path $PdmLibraryPath

    $vault = New-Object EdmLib.EdmVault5Class

    $hasCredentialFile = -not [string]::IsNullOrWhiteSpace($VaultCredentialPath) -and
    $VaultCredentialPath -notlike "<*>" -and
    (Test-Path -LiteralPath $VaultCredentialPath -PathType Leaf)

    if ($hasCredentialFile) {

      $credential = Import-Clixml -LiteralPath $VaultCredentialPath

      if ($null -eq $credential) {
        throw "O arquivo de credencial do vault nao pode ser lido."
      }

      $credentialUser = $null
      $securePassword = $null

      if ($credential -is [System.Management.Automation.PSCredential]) {
        $credentialUser = $credential.UserName
        $securePassword = $credential.Password
      }
      elseif (
        $credential.PSObject.Properties["Usuario"] -and
        $credential.PSObject.Properties["SenhaCriptografada"]
      ) {
        $credentialUser = [string]$credential.Usuario
        $securePassword = $credential.SenhaCriptografada | ConvertTo-SecureString
      }
      else {
        throw (
          "O arquivo de credencial do vault deve ser um PSCredential " +
          "ou conter as propriedades Usuario e SenhaCriptografada."
        )
      }

      if ([string]::IsNullOrWhiteSpace($credentialUser)) {
        throw "O usuario do vault nao foi encontrado no arquivo de credencial."
      }

      $passwordPointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePassword)

      $plainTextPassword = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($passwordPointer)

      $vault.Login($credentialUser, $plainTextPassword, $VaultName)
    }
    else {

      if (
        -not [string]::IsNullOrWhiteSpace($VaultCredentialPath) -and
        $VaultCredentialPath -notlike "<*>" -and
        -not (Test-Path -LiteralPath $VaultCredentialPath -PathType Leaf)
      ) {
        Write-Warn (
          "Arquivo de credencial do vault nao encontrado em " +
          "'$VaultCredentialPath'. Tentando LoginAuto."
        )
      }

      $vault.LoginAuto($VaultName, 0)
    }

    if (-not $vault.IsLoggedIn) {
      throw "Nao foi possivel autenticar no vault '$VaultName'."
    }

    $script:DcaVault = $vault

    return $vault
  }
  catch {

    Write-Warn (
      "Falha no login do vault '$VaultName': $($_.Exception.Message) " +
      "Usando apenas o sistema de arquivos. Verifique o nome do vault, " +
      "o login do PDM e DCA_VAULT_CREDENTIAL."
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

    if (
      -not [string]::IsNullOrWhiteSpace(
        $resultName
      ) -and
      $resultName.EndsWith(
        ".pdf",
        [System.StringComparison]::OrdinalIgnoreCase
      )
    ) {

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

  $pdfFiles = @(Get-ChildItem `
    -LiteralPath $FolderPath `
    -Filter "*.pdf" `
    -File `
    -Recurse `
    -Force `
    -ErrorAction SilentlyContinue)

  foreach ($pdfFile in $pdfFiles) {

    $entries.Add(
      [PSCustomObject]@{
        Name = $pdfFile.Name
        BaseName = [System.IO.Path]::GetFileNameWithoutExtension($pdfFile.Name).Trim()
        FullName = $pdfFile.FullName
        FromVault = $false
      }
    )
  }

  return $entries.ToArray()
}

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
    throw "PDF nao encontrado no disco: '$($Entry.FullName)'."
  }

  Write-Info "Baixando o PDF do vault..."

  $parentFolder = $null

  $pdmFile = $vault.GetFileFromPath($Entry.FullName, [ref]$parentFolder)

  if ($null -eq $pdmFile) {
    throw "Nao foi possivel obter o arquivo no vault."
  }

  if ($null -eq $parentFolder) {
    throw "Nao foi possivel obter a pasta do arquivo no vault."
  }

  $fileVersion = 0
  $folderId = $parentFolder.ID

  $pdmFile.GetFileCopy(0, [ref]$fileVersion, [ref]$folderId, 0, "")

  $localCachePath = $pdmFile.GetLocalPath($parentFolder.ID)

  if (-not (Test-Path -LiteralPath $localCachePath -PathType Leaf)) {
    throw "O arquivo nao foi encontrado no cache local do PDM: '$localCachePath'."
  }

  return $localCachePath
}

function Get-NormaCodeFromText {

  param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$Text
  )

  $normalizedText = $Text.Trim() -replace '\s+', ' '

  if (
    [string]::IsNullOrWhiteSpace(
      $normalizedText
    )
  ) {

    return [PSCustomObject]@{
      Code = $null
      Title = $null
      Parsed = $false
      Prefix = $null
      Pattern = $null
    }
  }

  # Test longer prefixes first so generic prefixes do not capture specific codes.
  $knownPrefixes = @(
    "COL-ASQR-PRO",
    "AMS-QQ-C",
    "AMS-QQ-N",
    "AMS-QQ-P",
    "AMS-QQ-S",
    "MIL-HDBK",
    "QPL-AMS",
    "AMS-STD",
    "AMS-QQ",
    "MIL-STD",
    "MIL-PRF",
    "MIL-DTL",
    "FED-STD",
    "ASTM-MNL",
    "SNT-TC",
    "AMS STD",
    "AMS A",
    "AMS M",
    "AMS S",
    "AMS-C",
    "AMS-H",
    "AMS-S",
    "ASTM-A",
    "ASTM-B",
    "ASTM-D",
    "ASTM-E",
    "ASTM-F",
    "ASTM-G",
    "ASME B",
    "ASME Y",
    "ANSI H",
    "AWS D",
    "SAE J",
    "SAE-J",
    "MIL-A",
    "MIL-C",
    "MIL-H",
    "MIL-I",
    "MIL-L",
    "MIL-R",
    "MIL-S",
    "TT-P",
    "NEDE E",
    "ADDHS",
    "ASQR",
    "EMBRAER",
    "UTCQR",
    "FLIGHTPARTS",
    "AMS",
    "ARP",
    "ASTM",
    "ANSI",
    "ASME",
    "AWS",
    "CID",
    "MFG",
    "NASM",
    "NAS",
    "QPL",
    "BAC",
    "CPS",
    "HSC",
    "HSM",
    "SVHS",
    "PMP",
    "MIL",
    "MS",
    "MEP",
    "ZERO",
    "SAE",
    "ISO",
    "DIN",
    "AS",
    "CG",
    "HS",
    "PN",
    "QC",
    "NB",
    "NE",
    "RR",
    "UC",
    "E",
    "F"
  )

  $knownPrefixes = @(
    $knownPrefixes |
      Sort-Object {
      $_.Length
    } -Descending
  )

  # Special AMS patterns.

  $specialPatterns = @(
    [PSCustomObject]@{
      Name = "AMS A numero sufixo"

      Prefix = "AMS A"

      Regex = '^(?<Code>AMS\s+A\s+\d+[A-Z0-9./-]*(?:\s+[A-Z])?)(?:\s+-?\s*(?<Title>.*))?$'
    }

    [PSCustomObject]@{
      Name = "AMS STD com espaco"

      Prefix = "AMS STD"

      Regex = '^(?<Code>AMS\s+STD\s+\d+[A-Z0-9./-]*)(?:\s+-?\s*(?<Title>.*))?$'
    }

    [PSCustomObject]@{
      Name = "AMS M com espaco"

      Prefix = "AMS M"

      Regex = '^(?<Code>AMS\s+M\s*\d+[A-Z0-9./-]*)(?:\s+-?\s*(?<Title>.*))?$'
    }

    [PSCustomObject]@{
      Name = "AMS S com espaco"

      Prefix = "AMS S"

      Regex = '^(?<Code>AMS\s+S\s*\d+[A-Z0-9./-]*)(?:\s+-?\s*(?<Title>.*))?$'
    }

    [PSCustomObject]@{
      Name = "AMS numerico com espaco"

      Prefix = "AMS"

      Regex = '^(?<Code>AMS\s+\d+[A-Z]?(?:-\d+)?)(?:\s+-?\s*(?<Title>.*))?$'
    }

    [PSCustomObject]@{
      Name = "AMS numerico sem espaco"

      Prefix = "AMS"

      Regex = '^(?<Code>AMS\d+[A-Z]?(?:-\d+)?)(?:\s+-?\s*(?<Title>.*))?$'
    }

    [PSCustomObject]@{
      Name = "AMS composto com hifen"

      Prefix = "AMS composto"

      Regex = '^(?<Code>AMS(?:-[A-Z0-9]+)+)(?:\s+-?\s*(?<Title>.*))?$'
    }
  )

  foreach ($specialPattern in $specialPatterns) {

    if (
      $normalizedText -notmatch
      $specialPattern.Regex
    ) {
      continue
    }

    $code = [string]$Matches["Code"]

    $title = $null

    if ($Matches.ContainsKey("Title")) {

      $title = [string]$Matches["Title"]
    }

    if (
      -not [string]::IsNullOrWhiteSpace(
        $title
      )
    ) {

      $title = $title.Trim().TrimStart("-", " ").TrimEnd(".", " ")
    }
    else {

      $title = $null
    }

    return [PSCustomObject]@{
      Code = $code.Trim()

      Title = $title

      Parsed = $true

      Prefix = [string]$specialPattern.Prefix

      Pattern = [string]$specialPattern.Name
    }
  }

  # Known-prefix rules.

  foreach ($prefix in $knownPrefixes) {

    # Allow variable whitespace in compound prefixes.
    $prefixRegex = [regex]::Escape($prefix)

    $prefixRegex = $prefixRegex.Replace(
      "\ ",
      "\s+"
    )

    # The identifier must contain at least one number.
    $pattern = (
      "^(?<Code>" +
      $prefixRegex +
      "(?:\s*-\s*|\s*)" +
      "[A-Z0-9./-]*\d[A-Z0-9./-]*" +
      "(?:\s+[A-Z])?" +
      ")" +
      "(?:\s+-?\s*(?<Title>.*))?$"
    )

    if ($normalizedText -notmatch $pattern) {
      continue
    }
    $code = [string]$Matches["Code"]

    if ([string]::IsNullOrWhiteSpace($code)) {
      continue
    }

    $code = $code.Trim()

    $title = $null

    if ($Matches.ContainsKey("Title")) {

      $title = [string]$Matches["Title"]
    }

    if (
      -not [string]::IsNullOrWhiteSpace(
        $title
      )
    ) {

      $title = $title.Trim()

      $title = $title.TrimStart(
        "-",
        "_",
        " "
      )

      $title = $title.TrimEnd(
        ".",
        " "
      )
    }
    else {

      $title = $null
    }

    return [PSCustomObject]@{
      Code = $code

      Title = $title

      Parsed = $true

      Prefix = $prefix

      Pattern = "Prefixo conhecido: $prefix"
    }
  }

  # Accept a complete technical code when it has no spaces and contains a number.
  if (
    $normalizedText -notmatch '\s' -and
    $normalizedText -match '\d' -and
    $normalizedText -match
    '^[A-Z0-9][A-Z0-9./_-]*$'
  ) {

    return [PSCustomObject]@{
      Code = $normalizedText

      Title = $null

      Parsed = $true

      Prefix = "Codigo completo"

      Pattern = "Codigo tecnico sem descricao"
    }
  }

  # Generic fallback for separating a technical code from its description.
  $genericPattern = (
    "^(?<Code>" +
    "[A-Z][A-Z0-9-]*" +
    "(?:\s+[A-Z]+)?" +
    "(?:[- ]?[A-Z]*)?" +
    "[- ]?\d+[A-Z0-9./-]*" +
    ")" +
    "(?:\s+-?\s*(?<Title>.*))?$"
  )

  if ($normalizedText -match $genericPattern) {

    $genericCode = [string]$Matches["Code"]

    $genericTitle = $null

    if ($Matches.ContainsKey("Title")) {

      $genericTitle = [string]$Matches["Title"]
    }

    if (
      -not [string]::IsNullOrWhiteSpace(
        $genericTitle
      )
    ) {

      $genericTitle = $genericTitle.Trim().TrimStart("-", " ").TrimEnd(".", " ")
    }
    else {

      $genericTitle = $null
    }

    return [PSCustomObject]@{
      Code = $genericCode.Trim()

      Title = $genericTitle

      Parsed = $true

      Prefix = "Generico"

      Pattern = "Codigo tecnico generico"
    }
  }

  return [PSCustomObject]@{
    Code = $normalizedText

    Title = $null

    Parsed = $false

    Prefix = "NAO_IDENTIFICADO"

    Pattern = $null
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

  $documentTitle = $null

  if ($DocumentType -eq "NormaExterna") {

    $normaInfo = Get-NormaCodeFromText `
      -Text $sourceCodeText

    $sourceCodeText = $normaInfo.Code

    $documentTitle = $normaInfo.Title

    $codeParsed = $normaInfo.Parsed
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
    throw "Vault DCA nao encontrado em '$FolderPath'."
  }

  $searchPattern = $Code.Trim()

  if ([string]::IsNullOrWhiteSpace($searchPattern)) {
    throw "O codigo de pesquisa ficou vazio."
  }

  $usesWildcard = $searchPattern.IndexOf("*") -ge 0 -or
  $searchPattern.IndexOf("?") -ge 0

  Write-AnimatedLine ""

  if ($usesWildcard) {
    Write-Info "Pesquisando pelo padrao: [$searchPattern]"
  }
  else {
    Write-Info "Pesquisando pelo codigo exato: [$searchPattern]"
  }

  $rootFolders = @(Get-ChildItem -LiteralPath $FolderPath -Directory -Force -ErrorAction Stop)

  $documentationFolder = $rootFolders |
    Where-Object { $_.Name -like "Documenta*" } |
    Select-Object -First 1

  if ($null -eq $documentationFolder) {

    $visibleFolderNames = @($rootFolders | ForEach-Object { $_.Name })

    throw (
      "A pasta de documentacao nao foi encontrada em '$FolderPath'. " +
      "Pastas visiveis: " + ($visibleFolderNames -join ", ")
    )
  }

  Write-Info "Pasta de documentacao localizada."

  $categoryDefinitions = @(
    [PSCustomObject]@{
      FolderName = "Desenhos Originais"
      DocumentType = "Original"
      DisplayName = "DCA Desenho Original"
    },
    [PSCustomObject]@{
      FolderName = "FP - Ficha de Processo (PDF)"
      DocumentType = "Processo"
      DisplayName = "DCA Processo"
    },
    [PSCustomObject]@{
      FolderName = "Normas Externas"
      DocumentType = "NormaExterna"
      DisplayName = "DCA Norma Externa"
    }
  )

  $documentationSubfolders = @(Get-ChildItem -LiteralPath $documentationFolder.FullName -Directory -Force -ErrorAction Stop)

  $searchFolders = [System.Collections.Generic.List[object]]::new()

  foreach ($categoryDefinition in $categoryDefinitions) {

    $categoryFolder = $documentationSubfolders |
      Where-Object { $_.Name.Trim() -ieq $categoryDefinition.FolderName } |
      Select-Object -First 1

    if ($null -eq $categoryFolder) {
      Write-Warn "Pasta nao encontrada: $($categoryDefinition.FolderName)"
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
      "Nenhuma pasta permitida foi encontrada em " +
      "'$($documentationFolder.FullName)'. Pastas visiveis: " +
      ($visibleSubfolderNames -join ", ")
    )
  }

  $matchingFiles = [System.Collections.Generic.List[object]]::new()

  $apiEntries = $null
  $vault = Get-DcaVault

  if ($null -ne $vault) {

    Write-Info "Consultando o vault..."

    try {
      $apiEntries = @(Search-DcaVaultPdfEntries -Vault $vault -SearchText $searchPattern)
    }
    catch {

      Write-Warn (
        "A busca pela API do PDM falhou: $($_.Exception.Message) " +
        "Usando o sistema de arquivos."
      )

      $apiEntries = $null
    }
  }

  $separator = [string][System.IO.Path]::DirectorySeparatorChar

  foreach ($searchFolder in $searchFolders) {

    if ($null -ne $apiEntries) {

      $categoryPrefix = $searchFolder.DirectoryPath.TrimEnd($separator) + $separator

      $pdfEntries = @(
        $apiEntries |
          Where-Object {
          $_.FullName.StartsWith($categoryPrefix, [System.StringComparison]::OrdinalIgnoreCase)
        } |
          Sort-Object FullName
      )

    }
    else {

      Write-Info ("Consultando {0}..." -f $searchFolder.DisplayName)

      $pdfEntries = @(
        Get-DcaDiskPdfEntries -FolderPath $searchFolder.DirectoryPath |
          Sort-Object FullName
      )
    }

    if ($pdfEntries.Count -eq 0 -and $null -eq $apiEntries) {
      Write-Warn (
        "Nenhum PDF em disco e a API do PDM nao foi usada. " +
        "O conteudo pode existir so no servidor do PDM."
      )
    }

    foreach ($pdfEntry in $pdfEntries) {

      $parsedName = ConvertFrom-PdfFileName `
        -BaseName $pdfEntry.BaseName `
        -DocumentType $searchFolder.DocumentType

      $isMatch = Test-DcaCodeMatch `
        -BaseName $pdfEntry.BaseName `
        -ParsedCode $parsedName.SourceCode `
        -Pattern $searchPattern `
        -UsesWildcard $usesWildcard

      if (-not $isMatch) {
        continue
      }

      $clientRevision = $parsedName.ClientRevision

      if (
        $searchFolder.DocumentType -eq "NormaExterna" -and
        [string]::IsNullOrWhiteSpace($clientRevision)
      ) {
        $clientRevision = "000"
      }

      $matchingFiles.Add(
        [PSCustomObject]@{
          File = $pdfEntry
          SourceCode = $parsedName.SourceCode
          ClientRevision = $clientRevision
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
    throw "Nenhum PDF foi encontrado para a pesquisa '$searchPattern'."
  }

  $script:SearchResultDelayMilliseconds = 30

  if ($matchCount -gt 3) {
    $script:SearchResultDelayMilliseconds = 20
  }

  Write-SearchResultLine ""
  Write-SearchResultLine ("  Resultados da busca ({0} encontrado(s))" -f $matchCount) -Color White
  Write-SearchResultLine ("  Pesquisa: {0}" -f $searchPattern) -Color Gray
  Write-SearchResultLine ("  " + ("-" * 72)) -Color DarkGray

  for ($index = 0; $index -lt $matchCount; $index++) {

    $number = $index + 1
    $currentMatch = $matchingFiles[$index]
    $revisionDisplay = [string]$currentMatch.ClientRevision

    if ([string]::IsNullOrWhiteSpace($revisionDisplay)) {
      $revisionDisplay = "nao informada"
    }

    $nameDisplay = [string]$currentMatch.DocumentTitle

    if ([string]::IsNullOrWhiteSpace($nameDisplay)) {
      $nameDisplay = "não informado"
    }

    Write-SearchResultLine ("  [{0}] {1}" -f $number, $currentMatch.File.Name) -Color White
    Write-SearchResultLine ("       Tipo:     {0}" -f $currentMatch.TypeDisplayName) -Color White
    Write-SearchResultLine ("       Codigo:   {0}" -f $currentMatch.SourceCode) -Color Gray
    Write-SearchResultLine ("       Nome:     {0}" -f $nameDisplay) -Color Gray
    Write-SearchResultLine ("       Revisao:  {0}" -f $revisionDisplay) -Color Gray
    Write-SearchResultLine ("       Local:    {0}" -f $currentMatch.File.FullName) -Color DarkGray
    Write-SearchResultLine ""
  }

  if ($matchCount -eq 1) {

    Write-Success "O unico PDF encontrado foi selecionado automaticamente."

    return $matchingFiles[0]
  }

  while ($true) {

    $selectionText =
    Read-Host (
      "Digite um ou mais numeros separados por virgula " +
      "(exemplo: 1,2)"
    )

    if (
      [string]::IsNullOrWhiteSpace(
        $selectionText
      )
    ) {

      Write-Warn (
        "Nenhum numero foi informado."
      )

      continue
    }

    $selectedNumbers =
    [System.Collections.Generic.List[int]]::new()

    $knownNumbers =
    [System.Collections.Generic.HashSet[int]]::new()

    $selectionIsValid =
    $true

    foreach ($selectionPart in ($selectionText -split ",")) {

      $trimmedSelection =
      ([string]$selectionPart).Trim()

      $selectedNumber =
      0

      $validNumber =
      [System.Int32]::TryParse(
        $trimmedSelection,
        [ref]$selectedNumber
      )

      if (
        -not $validNumber -or
        $selectedNumber -lt 1 -or
        $selectedNumber -gt $matchCount
      ) {

        Write-Warn (
          "Selecao invalida: '$trimmedSelection'. " +
          "Digite numeros entre 1 e $matchCount."
        )

        $selectionIsValid =
        $false

        break
      }

      # Evita selecionar o mesmo resultado duas vezes.
      if ($knownNumbers.Add($selectedNumber)) {

        $selectedNumbers.Add($selectedNumber)
      }
    }

    if (-not $selectionIsValid) {
      continue
    }

    if ($selectedNumbers.Count -eq 0) {

      Write-Warn (
        "Nenhum resultado valido foi selecionado."
      )

      continue
    }

    $selectedFiles =
    [System.Collections.Generic.List[object]]::new()

    Write-AnimatedLine ""

    foreach ($selectedNumber in $selectedNumbers) {

      $selectedFile =
      $matchingFiles[$selectedNumber - 1]

      $selectedFiles.Add($selectedFile)

      Write-Success (
        "PDF selecionado [$selectedNumber]: " +
        $selectedFile.File.FullName
      )
    }

    # A virgula impede que o PowerShell desmonte a colecao.
    return $selectedFiles.ToArray()
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
    throw "PDF de origem nao encontrado: $SourcePdfPath"
  }

  $sourceFile = Get-Item -LiteralPath $SourcePdfPath -ErrorAction Stop

  if ($sourceFile.Extension -ine ".pdf") {
    throw "O arquivo de origem nao possui extensao PDF."
  }

  if ($sourceFile.Length -le 0) {
    throw "O PDF de origem esta vazio."
  }

  $temporaryFolder = $env:DCA_TEMP_FOLDER

  if ([string]::IsNullOrWhiteSpace($temporaryFolder)) {
    throw "DCA_TEMP_FOLDER must be configured."
  }

  if (-not (Test-Path -LiteralPath $temporaryFolder -PathType Container)) {
    $null = New-Item -Path $temporaryFolder -ItemType Directory -Force -ErrorAction Stop
  }

  $safeItemCode = $ItemCode -replace '[\\/:*?"<>|]', '_'
  $temporaryPdfPath = Join-Path -Path $temporaryFolder -ChildPath "$safeItemCode.pdf"

  if (Test-Path -LiteralPath $temporaryPdfPath -PathType Leaf) {
    Remove-Item -LiteralPath $temporaryPdfPath -Force -ErrorAction Stop
  }

  Write-Info "Preparando o PDF para importacao..."

  Copy-Item -LiteralPath $SourcePdfPath -Destination $temporaryPdfPath -Force -ErrorAction Stop

  if (-not (Test-Path -LiteralPath $temporaryPdfPath -PathType Leaf)) {
    throw "O PDF nao foi criado na pasta temporaria."
  }

  $temporaryFile = Get-Item -LiteralPath $temporaryPdfPath -ErrorAction Stop

  if ($temporaryFile.Length -ne $sourceFile.Length) {
    throw (
      "O tamanho da copia temporaria e diferente do original. " +
      "Original: $($sourceFile.Length) bytes. " +
      "Copia: $($temporaryFile.Length) bytes."
    )
  }

  $stream = $null

  try {

    $stream = [System.IO.File]::Open(
      $temporaryPdfPath,
      [System.IO.FileMode]::Open,
      [System.IO.FileAccess]::Read,
      [System.IO.FileShare]::Read
    )

    if ($stream.Length -le 0) {
      throw "A copia temporaria do PDF esta vazia."
    }
  }
  finally {
    if ($null -ne $stream) {
      $stream.Dispose()
    }
  }

  Write-Success "PDF copiado e validado na pasta temporaria."
  return $temporaryFile.FullName
}
function Get-DcaSearchCodeList {

  param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$InputText
  )

  $codes =
  [System.Collections.Generic.List[string]]::new()

  $knownCodes =
  [System.Collections.Generic.HashSet[string]]::new(
    [System.StringComparer]::OrdinalIgnoreCase
  )

  foreach ($part in ($InputText -split ",")) {

    $currentCode =
    ([string]$part).Trim()

    if (
      [string]::IsNullOrWhiteSpace(
        $currentCode
      )
    ) {
      continue
    }

    # Add retorna false quando o mesmo padrao ja existe.
    if ($knownCodes.Add($currentCode)) {

      $codes.Add($currentCode)
    }
  }

  if ($codes.Count -eq 0) {

    throw "Nenhum codigo valido foi informado."
  }

  return $codes.ToArray()
}
function Invoke-DcaMain {

  Write-Section -Title "Informe o que deseja pesquisar" -NoLeadingBlank

  $searchPattern = $SourceCode

  $rootPath = $SearchRoot

  if ([string]::IsNullOrWhiteSpace($rootPath)) {
    throw "DCA_ROOT or -SearchRoot must be configured."
  }

  $searchInput =
  [string]$SourceCode

  if (
    [string]::IsNullOrWhiteSpace(
      $searchInput
    )
  ) {

    $searchInput =
    Read-Host (
      "Digite um ou mais codigos separados por virgula; " +
      "use * para busca parcial"
    )
  }

  if (
    [string]::IsNullOrWhiteSpace(
      $searchInput
    )
  ) {

    throw "Nenhum codigo de pesquisa foi informado."
  }

  $requestedCodes =
  @(
    Get-DcaSearchCodeList `
      -InputText $searchInput
  )

  Write-Host ""

  Write-Host (
    "  Codigo(s) informado(s): " +
    $requestedCodes.Count
  ) -ForegroundColor Gray

  $selectedDocuments =
  [System.Collections.Generic.List[object]]::new()

  $selectedDocumentPaths =
  [System.Collections.Generic.HashSet[string]]::new(
    [System.StringComparer]::OrdinalIgnoreCase
  )

  $searchFailures =
  [System.Collections.Generic.List[object]]::new()
  for (
    $searchIndex = 0
    $searchIndex -lt $requestedCodes.Count
    $searchIndex++
  ) {

    $currentSearchCode =
    [string]$requestedCodes[$searchIndex]

    Write-Host ""

    Write-Host (
      "Preparando pesquisa " +
      "[$($searchIndex + 1)/$($requestedCodes.Count)]: " +
      "$currentSearchCode"
    ) -ForegroundColor Cyan

    try {
      $selectedPdfs =
      @(
        Select-DcaPdfByCode `
          -FolderPath $rootPath `
          -Code $currentSearchCode
      )

      if ($selectedPdfs.Count -eq 0) {

        throw (
          "Nenhum PDF foi selecionado para a pesquisa " +
          "'$currentSearchCode'."
        )
      }

      foreach ($selectedPdf in $selectedPdfs) {

        if ($null -eq $selectedPdf) {
          continue
        }

        $selectedPath =
        [string]$selectedPdf.File.FullName

        if (
          [string]::IsNullOrWhiteSpace(
            $selectedPath
          )
        ) {

          Write-Warn (
            "O resultado selecionado nao possui caminho."
          )

          continue
        }

        if (-not $selectedDocumentPaths.Add($selectedPath)) {

          Write-Warn (
            "O PDF ja foi adicionado ao lote e sera ignorado: " +
            $selectedPath
          )

          continue
        }

        $selectedDocuments.Add(
          [PSCustomObject]@{
            SearchText = $currentSearchCode
            SelectedPdf = $selectedPdf
          }
        )
      }
    }
    catch {

      $searchFailures.Add(
        [PSCustomObject]@{
          SearchText = $currentSearchCode
          ErrorMessage = $_.Exception.Message
        }
      )

      Write-Warn (
        "Falha na pesquisa '$currentSearchCode': " +
        $_.Exception.Message
      )
    }
  }

  if ($selectedDocuments.Count -eq 0) {
    throw "Nenhum documento foi selecionado para importacao."
  }

  $preparedDocuments =
  [System.Collections.Generic.List[object]]::new()

  for (
    $documentIndex = 0
    $documentIndex -lt $selectedDocuments.Count
    $documentIndex++
  ) {

    $selection =
    $selectedDocuments[$documentIndex]

    $selectedPdf =
    $selection.SelectedPdf

    $documentType =
    [string]$selectedPdf.DocumentType

    $itemCodeFromFile =
    [string]$selectedPdf.SourceCode

    $documentTitle =
    [string]$selectedPdf.DocumentTitle

    if (
      $documentType -eq "NormaExterna" -and
      -not $selectedPdf.CodeParsed
    ) {

      Write-Warn (
        "Nao foi possivel extrair o codigo da norma de " +
        "'$($selectedPdf.File.BaseName)'."
      )

      $typedCode =
      Read-Host (
        "Digite o codigo da norma " +
        "(Enter usa o nome completo)"
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

    $clientRevision =
    [string]$selectedPdf.ClientRevision

    Write-Host ""
    Write-Host (
      "Preparando documento " +
      "[$($documentIndex + 1)/$($selectedDocuments.Count)]: " +
      "$itemCodeFromFile"
    ) -ForegroundColor Cyan

    if (
      [string]::IsNullOrWhiteSpace(
        $clientRevision
      )
    ) {

      if ($documentType -eq "NormaExterna") {

        $clientRevision =
        "000"

        Write-Host (
          "  Revisao inicial da Norma Externa: [000]"
        ) -ForegroundColor Gray
      }
      else {

        $clientRevision =
        Read-Host (
          "Digite a Revisao Cliente para '$itemCodeFromFile' " +
          "(Original: B ou BA4; Processo: BA4)"
        )
      }
    }

    if (
      [string]::IsNullOrWhiteSpace(
        $clientRevision
      )
    ) {

      Write-Warn (
        "Revisao nao informada para '$itemCodeFromFile'. " +
        "O documento sera ignorado."
      )

      continue
    }

    $clientRevision =
    $clientRevision.Trim().ToUpper()

    $itemNameText =
    [string]$ItemName

    if (
      $documentType -eq "NormaExterna" -and
      -not [string]::IsNullOrWhiteSpace(
        $documentTitle
      )
    ) {

      $itemNameText =
      $documentTitle.Trim()
    }

    if (
      [string]::IsNullOrWhiteSpace(
        $itemNameText
      )
    ) {

      $itemNameText =
      Read-Host (
        "Digite o nome do item '$itemCodeFromFile' " +
        "(obrigatorio)"
      )
    }

    if (
      [string]::IsNullOrWhiteSpace(
        $itemNameText
      )
    ) {

      Write-Warn (
        "Nome nao informado para '$itemCodeFromFile'. " +
        "O documento sera ignorado."
      )

      continue
    }

    $preparedDocuments.Add(
      [PSCustomObject]@{
        SearchText = $selection.SearchText
        SelectedPdf = $selectedPdf
        ItemCode = $itemCodeFromFile
        ItemName = $itemNameText.Trim()
        ClientRevision = $clientRevision
        DocumentType = $documentType
        DisplayType = $selectedPdf.TypeDisplayName
      }
    )
  }

  if ($preparedDocuments.Count -eq 0) {
    throw "Nenhum documento ficou pronto para importacao."
  }
  Write-Section -Title "Resumo do lote"

  Write-Host ""

  for (
    $index = 0
    $index -lt $preparedDocuments.Count
    $index++
  ) {

    $document =
    $preparedDocuments[$index]

    Write-Host (
      "  [$($index + 1)] $($document.ItemCode)"
    ) -ForegroundColor White

    Write-Host (
      "       Tipo:    " +
      "$($document.DisplayType) [$($document.DocumentType)]"
    ) -ForegroundColor Gray

    Write-Host (
      "       Revisao: " +
      $document.ClientRevision
    ) -ForegroundColor Gray

    Write-Host (
      "       Nome:    " +
      $document.ItemName
    ) -ForegroundColor Gray

    Write-Host (
      "       Arquivo: " +
      $document.SelectedPdf.File.FullName
    ) -ForegroundColor DarkGray

    Write-Host ""
  }
  if ($Preview) {

    Write-AnimatedLine ""
    Write-Success "Preview apenas. Nada foi criado no Teamcenter."

    return 0
  }

  $null =
  Connect-Teamcenter

  # ====================================================
  # Confirmacao adicional para ambiente de processo
  # ====================================================

  if (
    $script:TeamcenterEnvironment -eq "Processo"
  ) {

    Write-AnimatedLine ""

    Write-Warn (
      "Voce esta conectado ao Teamcenter de PROCESSO."
    )

    $productionConfirmation =
    Read-Host (
      "Digite PROCESSO para confirmar a criacao " +
      "no servidor normal"
    )

    if (
      $productionConfirmation.Trim() -cne "PROCESSO"
    ) {

      Write-AnimatedLine ""

      Write-Warn (
        "Operacao cancelada. Nenhum item foi criado."
      )

      return 0
    }
  }

  # ====================================================
  # Confirmacao geral do lote
  # ====================================================

  Write-Section `
    -Title "Criar itens e importar documentos"

  Write-AnimatedLine ""

  Write-Warn (
    "Esta etapa vai criar $($preparedDocuments.Count) " +
    "item(ns) real(is) no Teamcenter."
  )

  $confirmation =
  Read-Host (
    "Digite SIM para continuar ou pressione Enter para abortar"
  )

  if (
    $confirmation.Trim() -ine "SIM"
  ) {

    Write-AnimatedLine ""

    Write-Warn (
      "Abortado pelo usuario. Nenhum item foi criado."
    )

    return 0
  }

  # ====================================================
  # Executar o lote
  # ====================================================

  $batchResults =
  [System.Collections.Generic.List[object]]::new()

  for (
    $index = 0
    $index -lt $preparedDocuments.Count
    $index++
  ) {

    $document =
    $preparedDocuments[$index]

    $createdCode =
    $null

    $itemCreated =
    $false

    $pdfImported =
    $false

    Write-AnimatedLine ""

    Write-Info (
      "Importando [$($index + 1)/$($preparedDocuments.Count)]: " +
      $document.ItemCode
    )

    try {

      # ==================================================
      # 1. Criar Item e revisao
      # ==================================================

      $teamcenterDestination =
      New-DcaTeamcenterItem `
        -SourceCode $document.ItemCode `
        -ItemName $document.ItemName `
        -ClientRevision $document.ClientRevision `
        -DocumentType $document.DocumentType

      if ($null -eq $teamcenterDestination) {

        throw (
          "New-DcaTeamcenterItem nao retornou resultado " +
          "para '$($document.ItemCode)'."
        )
      }

      $createdCode =
      [string]$teamcenterDestination.Code

      if (
        [string]::IsNullOrWhiteSpace(
          $createdCode
        )
      ) {

        throw "O codigo criado nao foi retornado."
      }

      $itemCreated =
      $true

      Write-Success (
        "Item criado: $createdCode"
      )

      # ==================================================
      # 2. Obter o Item criado
      # ==================================================

      $teamcenterItem =
      $teamcenterDestination.Item

      if ($null -ne $teamcenterItem) {

        $teamcenterItem =
        $teamcenterItem.PSObject.BaseObject
      }

      if ($null -eq $teamcenterItem) {

        throw (
          "O Item criado nao foi retornado para " +
          "'$createdCode'."
        )
      }

      # ==================================================
      # 3. Obter a revisao criada
      # ==================================================

      $teamcenterRevision =
      $teamcenterDestination.Revision

      if ($null -ne $teamcenterRevision) {

        $teamcenterRevision =
        $teamcenterRevision.PSObject.BaseObject
      }

      if ($null -eq $teamcenterRevision) {

        Write-Info (
          "Localizando a revisao do item..."
        )

        $teamcenterRevision =
        Get-TeamcenterRevision `
          -Item $teamcenterItem

        if ($null -ne $teamcenterRevision) {

          $teamcenterRevision =
          $teamcenterRevision.PSObject.BaseObject
        }
      }

      if ($null -eq $teamcenterRevision) {

        throw (
          "A revisao do Teamcenter nao foi encontrada " +
          "para '$createdCode'."
        )
      }

      $revisionTypeName =
      $teamcenterRevision.GetType().FullName

      if (
        $revisionTypeName -notmatch "ItemRevision"
      ) {

        throw (
          "O objeto retornado nao e uma revisao valida. " +
          "Tipo recebido: '$revisionTypeName'."
        )
      }

      Write-Info (
        "Revisao localizada: $revisionTypeName"
      )

      # ==================================================
      # 4. Garantir que o PDF esteja no cache local
      # ==================================================

      $localPdfPath =
      Confirm-DcaLocalPdf `
        -Entry $document.SelectedPdf.File

      if (
        [string]::IsNullOrWhiteSpace(
          $localPdfPath
        )
      ) {

        throw (
          "Confirm-DcaLocalPdf nao retornou o caminho " +
          "do PDF para '$createdCode'."
        )
      }

      if (-not (
          Test-Path `
            -LiteralPath $localPdfPath `
            -PathType Leaf
        )) {

        throw (
          "O PDF local nao foi encontrado para '$createdCode': " +
          "'$localPdfPath'."
        )
      }

      # ==================================================
      # 5. Copiar o PDF para a pasta temporaria
      # ==================================================

      $temporaryPdfPath =
      Copy-PdfToTemporaryFolder `
        -SourcePdfPath $localPdfPath `
        -ItemCode $createdCode

      if (
        [string]::IsNullOrWhiteSpace(
          $temporaryPdfPath
        )
      ) {

        throw (
          "Copy-PdfToTemporaryFolder nao retornou " +
          "o caminho do PDF temporario."
        )
      }

      if (-not (
          Test-Path `
            -LiteralPath $temporaryPdfPath `
            -PathType Leaf
        )) {

        throw (
          "O PDF temporario nao existe para '$createdCode': " +
          "'$temporaryPdfPath'."
        )
      }

      $temporaryPdfFile =
      Get-Item `
        -LiteralPath $temporaryPdfPath `
        -ErrorAction Stop

      if ($temporaryPdfFile.Length -le 0) {

        throw (
          "O PDF temporario de '$createdCode' esta vazio."
        )
      }

      Write-Info (
        "PDF pronto para importacao: $temporaryPdfPath"
      )

      Write-Info (
        "Tamanho do PDF: " +
        "$($temporaryPdfFile.Length) bytes"
      )

      # ==================================================
      # 6. Importar o PDF na revisao
      # ==================================================

      Write-Info (
        "Importando o PDF no Teamcenter..."
      )

      $importResult =
      Import-TeamcenterPdf `
        -Revision $teamcenterRevision `
        -ItemCode $createdCode `
        -FilePath $temporaryPdfPath

      # O metodo pode ser void e retornar NULL.
      # A ausencia de excecao indica que a chamada terminou.
      $pdfImported =
      $true

      Write-Success (
        "PDF importado: $createdCode"
      )

      # ==================================================
      # 7. Registrar sucesso
      # ==================================================

      $batchResults.Add(
        [PSCustomObject]@{
          SearchText = $document.SearchText
          ItemCode = $document.ItemCode
          ItemName = $document.ItemName
          TeamcenterCode = $createdCode
          ItemCreated = $itemCreated
          PdfImported = $pdfImported
          Succeeded = $true
          ErrorMessage = $null
        }
      )
    }
    catch {

      $batchResults.Add(
        [PSCustomObject]@{
          SearchText = $document.SearchText
          ItemCode = $document.ItemCode
          ItemName = $document.ItemName
          TeamcenterCode = $createdCode
          ItemCreated = $itemCreated
          PdfImported = $pdfImported
          Succeeded = $false
          ErrorMessage = $_.Exception.Message
        }
      )

      Write-Failure (
        "$($document.ItemCode): " +
        $_.Exception.Message
      )

      # Uma falha nao interrompe os outros documentos.
      continue
    }
  }

  # ====================================================
  # Resumo final
  # ====================================================

  Write-Section `
    -Title "Resumo da importacao"

  Write-AnimatedLine ""

  foreach ($result in $batchResults) {

    if (
      $result.ItemCreated -and
      $result.PdfImported
    ) {

      Write-Success (
        "$($result.ItemCode) -> " +
        "$($result.TeamcenterCode) - " +
        "Item e PDF importados"
      )
    }
    elseif (
      $result.ItemCreated -and
      -not $result.PdfImported
    ) {

      Write-Failure (
        "$($result.ItemCode) -> Item criado, " +
        "mas PDF nao importado: " +
        $result.ErrorMessage
      )
    }
    else {

      Write-Failure (
        "$($result.ItemCode) -> Item nao criado: " +
        $result.ErrorMessage
      )
    }
  }

  $successCount =
  @(
    $batchResults |
      Where-Object {
      $_.Succeeded
    }
  ).Count

  $failureCount =
  @(
    $batchResults |
      Where-Object {
      -not $_.Succeeded
    }
  ).Count

  Write-AnimatedLine ""

  Write-Host (
    "  Importados: $successCount"
  ) -ForegroundColor Green

  Write-Host (
    "  Falharam:   $failureCount"
  ) -ForegroundColor Yellow

  Write-Host (
    "  Total:      $($batchResults.Count)"
  ) -ForegroundColor Gray

  if ($failureCount -gt 0) {
    return 1
  }

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
