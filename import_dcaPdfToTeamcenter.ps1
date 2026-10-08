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

  # Mostra os arquivos individualmente durante pesquisas por pasta.
  [switch]$Details,

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

if (-not [string]::IsNullOrWhiteSpace($env:DCA_ROOT)) {
  $SearchRoot = $env:DCA_ROOT
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
  "New-DcaTeamcenterItem",
  "Start-TeamcenterWorkflow"
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

  if (
    $name -match
    '^(?<Code>[^\[\]]+?)\s*\[(?<BracketValue>[^\]]+)\]\s*$'
  ) {

    $possibleCode =
    $Matches["Code"].Trim()

    $possibleRevision =
    $Matches["BracketValue"].Trim().ToUpper()

    $validRevision =
    $false

    if ($DocumentType -eq "Processo") {

      # Processo: A1, BA4, AA4 ou --4.
      $validRevision =
      $possibleRevision -match
      '^[A-Z0-9-]{1,2}\d$'
    }
    elseif ($DocumentType -eq "Original") {

      # Original: uma ou duas letras/numeros.
      $validRevision =
      $possibleRevision -match
      '^[A-Z0-9]{1,2}$'
    }
    elseif ($DocumentType -eq "NormaExterna") {

      # Norma Externa usa 000 automaticamente.
      $validRevision =
      $possibleRevision -eq "000"
    }

    if ($validRevision) {

      $sourceCodeText =
      $possibleCode

      $clientRevision =
      $possibleRevision
    }
    else {

      # O texto entre colchetes nao e uma revisao.
      # Mantem o codigo anterior aos colchetes, mas deixa
      # a revisao vazia para o tratamento posterior.
      $sourceCodeText =
      $possibleCode

      $clientRevision =
      $null
    }
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
function Get-DcaPdmFileState {

  param(
    [Parameter(Mandatory = $true)]
    $Entry
  )

  if ($null -eq $script:DcaVault) {
    return $null
  }

  if (
    [string]::IsNullOrWhiteSpace(
      [string]$Entry.FullName
    )
  ) {
    return $null
  }

  $parentFolder =
  $null

  try {

    $pdmFile =
    $script:DcaVault.GetFileFromPath(
      [string]$Entry.FullName,
      [ref]$parentFolder
    )

    if ($null -eq $pdmFile) {
      return $null
    }

    $currentState =
    $pdmFile.CurrentState

    if ($null -eq $currentState) {
      return $null
    }

    return (
      [string]$currentState.Name
    ).Trim()
  }
  catch {

    Write-Warn (
      "Nao foi possivel consultar o estado no PDM para " +
      "'$($Entry.FullName)': " +
      $_.Exception.Message
    )

    return $null
  }
}
function Select-DcaPdfsByFolder {

  param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$FolderPath,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$FolderSearch
  )

  if (-not (
      Test-Path `
        -LiteralPath $FolderPath `
        -PathType Container
    )) {

    throw "Vault DCA nao encontrado em '$FolderPath'."
  }

  $folderPattern =
  Get-DcaFolderSearchPattern `
    -SearchText $FolderSearch
  $usesWildcard =
  $folderPattern.Contains("*") -or
  $folderPattern.Contains("?")

  # ====================================================
  # Localizar a raiz Documentacao
  # ====================================================

  $documentationFolder =
  Get-ChildItem `
    -LiteralPath $FolderPath `
    -Directory `
    -Force `
    -ErrorAction Stop |
    Where-Object {
    $_.Name -like "Documenta*"
  } |
    Select-Object -First 1

  if ($null -eq $documentationFolder) {

    throw (
      "A pasta de documentacao nao foi encontrada em " +
      "'$FolderPath'."
    )
  }

  $documentationRootPath =
  [System.IO.Path]::GetFullPath(
    $documentationFolder.FullName
  ).TrimEnd("\")

  # ====================================================
  # Categorias conhecidas
  # ====================================================

  $categoryDefinitions =
  @(
    [PSCustomObject]@{
      FolderName = "Desenhos Originais"
      DocumentType = "Original"
      DisplayName = "DCA Desenho Original"
    }

    [PSCustomObject]@{
      FolderName = "FP - Ficha de Processo (PDF)"
      DocumentType = "Processo"
      DisplayName = "DCA Processo"
    }

    [PSCustomObject]@{
      FolderName = "Normas Externas"
      DocumentType = "NormaExterna"
      DisplayName = "DCA Norma Externa"
    }
  )

  # ====================================================
  # Procurar pastas em toda Documentacao
  # ====================================================

  $availableFolders =
  @(
    Get-ChildItem `
      -LiteralPath $documentationRootPath `
      -Directory `
      -Recurse `
      -Force `
      -ErrorAction SilentlyContinue
  )

  $matchingFolders =
  [System.Collections.Generic.List[object]]::new()

  foreach ($availableFolder in $availableFolders) {

    $folderFullPath =
    [System.IO.Path]::GetFullPath(
      $availableFolder.FullName
    ).TrimEnd("\")

    if (-not $folderFullPath.StartsWith(
        $documentationRootPath + "\",
        [System.StringComparison]::OrdinalIgnoreCase
      )) {

      continue
    }

    $relativePath =
    $folderFullPath.Substring(
      $documentationRootPath.Length
    ).TrimStart("\")

    $folderMatches =
    $relativePath -like $folderPattern -or
    $availableFolder.Name -like $folderPattern

    if (-not $folderMatches) {
      continue
    }

    # Identifica o tipo de documento pelo primeiro nível
    # abaixo da pasta Documentacao.
    $matchedCategory =
    $null

    foreach ($categoryDefinition in $categoryDefinitions) {

      $categoryPrefix =
      $categoryDefinition.FolderName + "\"

      if (
        $relativePath -ieq $categoryDefinition.FolderName -or
        $relativePath.StartsWith(
          $categoryPrefix,
          [System.StringComparison]::OrdinalIgnoreCase
        )
      ) {

        $matchedCategory =
        $categoryDefinition

        break
      }
    }

    if ($null -eq $matchedCategory) {

      if ($Details) {

        Write-Warn (
          "Pasta encontrada, mas sem tipo DCA configurado: " +
          "'$relativePath'."
        )
      }

      continue
    }

    $matchingFolders.Add(
      [PSCustomObject]@{
        Name = $availableFolder.Name
        RelativePath = $relativePath
        FullName = $folderFullPath
        CategoryFolder = $matchedCategory.FolderName
        DocumentType = $matchedCategory.DocumentType
        DisplayName = $matchedCategory.DisplayName
      }
    )
  }

  if ($matchingFolders.Count -eq 0) {

    throw (
      "Nenhuma pasta DCA foi encontrada para o padrao " +
      "'\$folderPattern' dentro de Documentacao."
    )
  }

  Write-AnimatedLine ""

  Write-Info (
    "Modo pasta em toda Documentacao: \$folderPattern"
  )

  # ====================================================
  # Consultar todos os PDFs uma unica vez
  # ====================================================

  $vault =
  Get-DcaVault

  $allAvailablePdfs =
  @()

  if ($null -ne $vault) {

    Write-Info "Consultando os PDFs no Vault..."

    $allAvailablePdfs =
    @(
      Search-DcaVaultPdfEntries `
        -Vault $vault `
        -SearchText "*"
    )
  }
  else {

    Write-Warn (
      "API do PDM indisponivel. " +
      "A pesquisa sera feita nos arquivos locais."
    )
  }

  # ====================================================
  # Criar uma opcao para cada pasta encontrada
  # ====================================================

  $folderOptions =
  [System.Collections.Generic.List[object]]::new()

  foreach ($matchingFolder in $matchingFolders) {

    $folderPdfEntries =
    @()

    if ($null -ne $vault) {

      # Apenas PDFs diretamente dentro da pasta.
      # Subpastas aparecem separadamente.
      $folderPdfEntries =
      @(
        $allAvailablePdfs |
          Where-Object {

          $pdfFullName =
          [string]$_.FullName

          if (
            [string]::IsNullOrWhiteSpace(
              $pdfFullName
            )
          ) {
            return $false
          }

          $pdfDirectory =
          [System.IO.Path]::GetDirectoryName(
            $pdfFullName
          )

          return (
            $pdfDirectory -ieq
            $matchingFolder.FullName
          )
        } |
          Sort-Object FullName
      )
    }
    else {

      $diskFiles =
      @(
        Get-ChildItem `
          -LiteralPath $matchingFolder.FullName `
          -Filter "*.pdf" `
          -File `
          -Force `
          -ErrorAction SilentlyContinue
      )

      $folderPdfEntries =
      @(
        foreach ($diskFile in $diskFiles) {

          [PSCustomObject]@{
            Name = $diskFile.Name
            BaseName = $diskFile.BaseName.Trim()
            FullName = $diskFile.FullName
            FromVault = $false
          }
        }
      )
    }

    $folderDocuments =
    [System.Collections.Generic.List[object]]::new()

    foreach ($pdfEntry in $folderPdfEntries) {

      $parsedName =
      ConvertFrom-PdfFileName `
        -BaseName $pdfEntry.BaseName `
        -DocumentType $matchingFolder.DocumentType

      $clientRevision =
      [string]$parsedName.ClientRevision

      if (
        $matchingFolder.DocumentType -eq "NormaExterna" -and
        [string]::IsNullOrWhiteSpace(
          $clientRevision
        )
      ) {

        $clientRevision =
        "000"
      }

      $pdmState =
      Get-DcaPdmFileState `
        -Entry $pdfEntry

      $folderDocuments.Add(
        [PSCustomObject]@{
          File = $pdfEntry
          SourceCode = $parsedName.SourceCode
          ClientRevision = $clientRevision
          DocumentTitle = $parsedName.DocumentTitle
          DocumentType = $matchingFolder.DocumentType
          TypeDisplayName = $matchingFolder.DisplayName
          CodeParsed = $parsedName.CodeParsed
          PdmState = $pdmState
          FolderImport = $true
          FolderPattern = $folderPattern
          SourceFolder = $matchingFolder.RelativePath
          CategoryFolder = $matchingFolder.CategoryFolder
        }
      )
    }

    # Pastas sem PDFs diretamente dentro delas não são
    # apresentadas como opções.
    if ($folderDocuments.Count -eq 0) {
      continue
    }

    $approvedCount =
    @(
      $folderDocuments |
        Where-Object {
        $_.PdmState -ieq "Aprovado"
      }
    ).Count

    $obsoleteCount =
    @(
      $folderDocuments |
        Where-Object {
        $_.PdmState -ieq "Obsoleto"
      }
    ).Count

    $otherCount =
    $folderDocuments.Count -
    $approvedCount -
    $obsoleteCount

    $folderOptions.Add(
      [PSCustomObject]@{
        Number = 0
        Name = $matchingFolder.Name
        RelativePath = $matchingFolder.RelativePath
        FullName = $matchingFolder.FullName
        CategoryFolder = $matchingFolder.CategoryFolder
        DocumentType = $matchingFolder.DocumentType
        DisplayName = $matchingFolder.DisplayName
        Documents = $folderDocuments.ToArray()
        Total = $folderDocuments.Count
        ApprovedCount = $approvedCount
        ObsoleteCount = $obsoleteCount
        OtherCount = $otherCount
      }
    )
  }

  if ($folderOptions.Count -eq 0) {

    throw (
      "As pastas encontradas para '\$folderPattern' " +
      "nao possuem PDFs diretamente dentro delas."
    )
  }

  $folderOptions =
  @(
    $folderOptions |
      Sort-Object RelativePath
  )

  for (
    $index = 0
    $index -lt $folderOptions.Count
    $index++
  ) {

    $folderOptions[$index].Number =
    $index + 1
  }

  # ====================================================
  # Pasta exata e unica: seleciona automaticamente
  # ====================================================

  if (
    -not $usesWildcard -and
    $folderOptions.Count -eq 1
  ) {

    $selectedFolder =
    $folderOptions[0]

    Write-AnimatedLine ""

    Write-Success (
      "Pasta selecionada: " +
      "\$($selectedFolder.RelativePath)"
    )

    Write-Host (
      "  Tipo:       $($selectedFolder.DisplayName)"
    ) -ForegroundColor Cyan

    Write-Host (
      "  PDFs:       $($selectedFolder.Total)"
    ) -ForegroundColor White

    Write-Host (
      "  Aprovados:  $($selectedFolder.ApprovedCount)"
    ) -ForegroundColor Green

    Write-Host (
      "  Obsoletos:  $($selectedFolder.ObsoleteCount)"
    ) -ForegroundColor Red

    Write-Host (
      "  Outros:     $($selectedFolder.OtherCount)"
    ) -ForegroundColor Yellow

    return $selectedFolder.Documents
  }

  # ====================================================
  # Mostrar resumo das pastas para selecao
  # ====================================================

  Write-AnimatedLine ""

  Write-Host "  Pastas encontradas:" -ForegroundColor Cyan
  Write-Host ("  " + ("-" * 68)) -ForegroundColor DarkGray

  foreach ($folderOption in $folderOptions) {

    Write-Host (
      "  [{0}] {1}" -f
      $folderOption.Number,
      $folderOption.RelativePath
    ) -ForegroundColor White

    Write-Host (
      "      Tipo:       {0}" -f
      $folderOption.DisplayName
    ) -ForegroundColor Cyan

    Write-Host (
      "      PDFs:       {0}" -f
      $folderOption.Total
    ) -ForegroundColor Gray

    Write-Host (
      "      Aprovados:  {0}" -f
      $folderOption.ApprovedCount
    ) -ForegroundColor Green

    Write-Host (
      "      Obsoletos:  {0}" -f
      $folderOption.ObsoleteCount
    ) -ForegroundColor Red

    Write-Host (
      "      Outros:     {0}" -f
      $folderOption.OtherCount
    ) -ForegroundColor Yellow

    Write-Host ""
  }

  Write-Host (
    "  Selecione uma ou mais pastas."
  ) -ForegroundColor Cyan

  Write-Host (
    "  Exemplos: 1 | 1,2 | 1-3 | T"
  ) -ForegroundColor DarkGray

  # ====================================================
  # Ler a selecao das pastas
  # ====================================================

  while ($true) {

    $selectionText =
    Read-Host (
      "Digite o numero da pasta, varios numeros ou T para todas"
    )

    if (
      [string]::IsNullOrWhiteSpace(
        $selectionText
      )
    ) {

      Write-Warn "Nenhuma pasta foi selecionada."

      continue
    }

    $selectionText =
    $selectionText.Trim()

    $selectedNumbers =
    [System.Collections.Generic.List[int]]::new()

    $knownNumbers =
    [System.Collections.Generic.HashSet[int]]::new()

    $selectionIsValid =
    $true

    if (
      $selectionText -ieq "T" -or
      $selectionText -ieq "TODAS"
    ) {

      for (
        $number = 1
        $number -le $folderOptions.Count
        $number++
      ) {

        if ($knownNumbers.Add($number)) {
          $selectedNumbers.Add($number)
        }
      }
    }
    else {

      foreach ($selectionPart in ($selectionText -split ",")) {

        $currentPart =
        ([string]$selectionPart).Trim()

        if (
          [string]::IsNullOrWhiteSpace(
            $currentPart
          )
        ) {
          continue
        }

        # Intervalo, por exemplo 1-3.
        if (
          $currentPart -match
          '^(?<Start>\d+)\s*-\s*(?<End>\d+)$'
        ) {

          $rangeStart =
          [int]$Matches["Start"]

          $rangeEnd =
          [int]$Matches["End"]

          if (
            $rangeStart -lt 1 -or
            $rangeEnd -gt $folderOptions.Count -or
            $rangeStart -gt $rangeEnd
          ) {

            Write-Warn (
              "Intervalo invalido: '$currentPart'."
            )

            $selectionIsValid =
            $false

            break
          }

          for (
            $rangeNumber = $rangeStart
            $rangeNumber -le $rangeEnd
            $rangeNumber++
          ) {

            if ($knownNumbers.Add($rangeNumber)) {
              $selectedNumbers.Add($rangeNumber)
            }
          }

          continue
        }

        $selectedNumber =
        0

        $validNumber =
        [System.Int32]::TryParse(
          $currentPart,
          [ref]$selectedNumber
        )

        if (
          -not $validNumber -or
          $selectedNumber -lt 1 -or
          $selectedNumber -gt $folderOptions.Count
        ) {

          Write-Warn (
            "Selecao invalida: '$currentPart'. " +
            "Use numeros entre 1 e " +
            "$($folderOptions.Count)."
          )

          $selectionIsValid =
          $false

          break
        }

        if ($knownNumbers.Add($selectedNumber)) {
          $selectedNumbers.Add($selectedNumber)
        }
      }
    }

    if (-not $selectionIsValid) {
      continue
    }

    if ($selectedNumbers.Count -eq 0) {

      Write-Warn "Nenhuma pasta valida foi selecionada."

      continue
    }

    # ==================================================
    # Juntar os documentos das pastas selecionadas
    # ==================================================

    $selectedDocuments =
    [System.Collections.Generic.List[object]]::new()

    $knownDocumentPaths =
    [System.Collections.Generic.HashSet[string]]::new(
      [System.StringComparer]::OrdinalIgnoreCase
    )

    Write-AnimatedLine ""

    foreach (
      $selectedNumber in (
        $selectedNumbers |
          Sort-Object
      )
    ) {

      $selectedFolder =
      $folderOptions[$selectedNumber - 1]

      Write-Success (
        "Pasta selecionada [$selectedNumber]: " +
        "\$($selectedFolder.RelativePath)"
      )

      foreach ($document in $selectedFolder.Documents) {

        $documentPath =
        [string]$document.File.FullName

        if (
          [string]::IsNullOrWhiteSpace(
            $documentPath
          )
        ) {
          continue
        }

        if ($knownDocumentPaths.Add($documentPath)) {
          $selectedDocuments.Add($document)
        }
      }
    }

    Write-AnimatedLine ""

    Write-Host (
      "  Pastas selecionadas:    $($selectedNumbers.Count)"
    ) -ForegroundColor Cyan

    Write-Host (
      "  Documentos adicionados: $($selectedDocuments.Count)"
    ) -ForegroundColor Cyan

    return $selectedDocuments.ToArray()
  }
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

  $searchText =
  $Code.Trim()

  if (
    [string]::IsNullOrWhiteSpace(
      $searchText
    )
  ) {
    throw "O codigo de pesquisa ficou vazio."
  }

  # A pesquisa por codigo e sempre parcial.
  # Se o usuario nao informar wildcard, o script adiciona.
  if (
    $searchText.Contains("*") -or
    $searchText.Contains("?")
  ) {
    $searchPattern =
    $searchText
  }
  else {
    $searchPattern =
    "*$searchText*"
  }

  Write-AnimatedLine ""

  Write-Info (
    "Pesquisando todas as correspondencias de: " +
    "[$searchText]"
  )
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

  $knownMatchingPaths =
  [System.Collections.Generic.HashSet[string]]::new(
    [System.StringComparer]::OrdinalIgnoreCase
  )

  $apiEntries = $null
  $vault = Get-DcaVault

  if ($null -ne $vault) {

    Write-Info "Consultando o vault..."

    try {
      $apiEntries =
      @(
        Search-DcaVaultPdfEntries `
          -Vault $vault `
          -SearchText $searchPattern
      )

      Write-Info (
        "Resultados retornados pelo Vault: " +
        $apiEntries.Count
      )
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
        -UsesWildcard $true

      if (-not $isMatch) {
        continue
      }

      $pdfFullName =
      [string]$pdfEntry.FullName

      if (
        [string]::IsNullOrWhiteSpace(
          $pdfFullName
        )
      ) {
        continue
      }

      if (-not $knownMatchingPaths.Add($pdfFullName)) {
        continue
      }

      $clientRevision = $parsedName.ClientRevision

      if (
        $searchFolder.DocumentType -eq "NormaExterna" -and
        [string]::IsNullOrWhiteSpace($clientRevision)
      ) {
        $clientRevision = "000"
      }

      $pdmState =
      Get-DcaPdmFileState `
        -Entry $pdfEntry

      $matchingFiles.Add(
        [PSCustomObject]@{
          File = $pdfEntry
          SourceCode = $parsedName.SourceCode
          ClientRevision = $clientRevision
          DocumentTitle = $parsedName.DocumentTitle
          DocumentType = $searchFolder.DocumentType
          TypeDisplayName = $searchFolder.DisplayName
          CodeParsed = $parsedName.CodeParsed
          PdmState = $pdmState
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

  for (
    $index = 0
    $index -lt $matchCount
    $index++
  ) {

    $number =
    $index + 1

    $currentMatch =
    $matchingFiles[$index]

    $revisionDisplay =
    [string]$currentMatch.ClientRevision

    if (
      [string]::IsNullOrWhiteSpace(
        $revisionDisplay
      )
    ) {

      $revisionDisplay =
      "nao informada"
    }

    $nameDisplay =
    [string]$currentMatch.DocumentTitle

    if (
      [string]::IsNullOrWhiteSpace(
        $nameDisplay
      )
    ) {

      $nameDisplay =
      "nao informado"
    }

    $stateDisplay =
    [string]$currentMatch.PdmState

    if (
      [string]::IsNullOrWhiteSpace(
        $stateDisplay
      )
    ) {

      $stateDisplay =
      "nao informado"
    }

    $stateColor =
    [System.ConsoleColor]::Yellow

    if ($stateDisplay -ieq "Aprovado") {

      $stateColor =
      [System.ConsoleColor]::Green
    }
    elseif ($stateDisplay -ieq "Obsoleto") {

      $stateColor =
      [System.ConsoleColor]::Red
    }
    elseif ($stateDisplay -ieq "Verificado") {

      $stateColor =
      [System.ConsoleColor]::Cyan
    }

    Write-SearchResultLine (
      "  [{0}] {1}" -f
      $number,
      $currentMatch.SourceCode
    ) -Color White

    Write-SearchResultLine (
      "       Nome:    {0}" -f
      $nameDisplay
    ) -Color Gray

    Write-SearchResultLine (
      "       Tipo:    {0}" -f
      $currentMatch.TypeDisplayName
    ) -Color Gray

    Write-SearchResultLine (
      "       Revisao: {0}" -f
      $revisionDisplay
    ) -Color Gray

    Write-SearchResultLine (
      "       Estado:  {0}" -f
      $stateDisplay
    ) -Color $stateColor

    if ($Details) {

      Write-SearchResultLine (
        "       PDF:     {0}" -f
        $currentMatch.File.Name
      ) -Color DarkGray

      Write-SearchResultLine (
        "       Local:   {0}" -f
        $currentMatch.File.FullName
      ) -Color DarkGray
    }

    Write-SearchResultLine ""
  }

  # Este bloco precisa ficar FORA do for acima.
  if ($matchCount -eq 1) {

    Write-Success (
      "O unico PDF encontrado foi selecionado automaticamente."
    )

    return $matchingFiles[0]
  }

  # Esta pergunta tambem precisa ficar FORA do for.
  while ($true) {

    $selectionText =
    Read-Host (
      "Digite numeros separados por virgula, " +
      "um intervalo ou T para todos"
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

    $selectionText =
    $selectionText.Trim()

    $selectedNumbers =
    [System.Collections.Generic.List[int]]::new()

    $knownNumbers =
    [System.Collections.Generic.HashSet[int]]::new()

    $selectionIsValid =
    $true

    if (
      $selectionText -ieq "T" -or
      $selectionText -ieq "TODOS"
    ) {

      for (
        $number = 1
        $number -le $matchCount
        $number++
      ) {

        if ($knownNumbers.Add($number)) {

          $selectedNumbers.Add($number)
        }
      }
    }
    else {

      foreach (
        $selectionPart in (
          $selectionText -split ","
        )
      ) {

        $currentPart =
        ([string]$selectionPart).Trim()

        if (
          [string]::IsNullOrWhiteSpace(
            $currentPart
          )
        ) {
          continue
        }

        # Permite intervalo, por exemplo: 1-5.
        if (
          $currentPart -match
          '^(?<Start>\d+)\s*-\s*(?<End>\d+)$'
        ) {

          $rangeStart =
          [int]$Matches["Start"]

          $rangeEnd =
          [int]$Matches["End"]

          if (
            $rangeStart -lt 1 -or
            $rangeEnd -gt $matchCount -or
            $rangeStart -gt $rangeEnd
          ) {

            Write-Warn (
              "Intervalo invalido: '$currentPart'. " +
              "Use valores entre 1 e $matchCount."
            )

            $selectionIsValid =
            $false

            break
          }

          for (
            $rangeNumber = $rangeStart
            $rangeNumber -le $rangeEnd
            $rangeNumber++
          ) {

            if ($knownNumbers.Add($rangeNumber)) {

              $selectedNumbers.Add($rangeNumber)
            }
          }

          continue
        }

        $selectedNumber =
        0

        $validNumber =
        [System.Int32]::TryParse(
          $currentPart,
          [ref]$selectedNumber
        )

        if (
          -not $validNumber -or
          $selectedNumber -lt 1 -or
          $selectedNumber -gt $matchCount
        ) {

          Write-Warn (
            "Selecao invalida: '$currentPart'. " +
            "Digite numeros entre 1 e $matchCount."
          )

          $selectionIsValid =
          $false

          break
        }

        if ($knownNumbers.Add($selectedNumber)) {

          $selectedNumbers.Add($selectedNumber)
        }
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

    foreach (
      $selectedNumber in (
        $selectedNumbers |
          Sort-Object
      )
    ) {

      $selectedFile =
      $matchingFiles[$selectedNumber - 1]

      $selectedFiles.Add($selectedFile)

      Write-Success (
        "PDF selecionado [$selectedNumber]: " +
        $selectedFile.File.Name
      )

      if ($Details) {

        Write-Info (
          "Local: " +
          $selectedFile.File.FullName
        )
      }
    }

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
function Test-DcaFolderSearch {

  param(
    [string]$SearchText
  )

  if (
    [string]::IsNullOrWhiteSpace(
      $SearchText
    )
  ) {
    return $false
  }

  return (
    $SearchText.Trim().StartsWith("\") -or
    $SearchText.Trim().StartsWith("/")
  )
}
function Get-DcaFolderSearchPattern {

  param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$SearchText
  )

  $folderPattern =
  $SearchText.Trim().TrimStart("\", "/").Trim()

  if (
    [string]::IsNullOrWhiteSpace(
      $folderPattern
    )
  ) {
    throw "O nome ou padrao da pasta ficou vazio."
  }

  if ($folderPattern.Contains("..")) {
    throw (
      "O padrao de pasta nao pode conter '..': " +
      "'$folderPattern'."
    )
  }

  # Permite * e ?, mas bloqueia caracteres inadequados.
  if ($folderPattern -match '[:"<>\|]') {
    throw (
      "O padrao de pasta possui caracteres invalidos: " +
      "'$folderPattern'."
    )
  }

  return $folderPattern.Replace("/", "\")
}
function Invoke-DcaMain {

  Write-Section -Title "Informe o que deseja pesquisar" -NoLeadingBlank

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
      "Digite codigos separados por virgula; " +
      "use \ para pesquisar pastas"
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
      $isFolderSearch =
      Test-DcaFolderSearch `
        -SearchText $currentSearchCode

      if ($isFolderSearch) {

        $selectedPdfs =
        @(
          Select-DcaPdfsByFolder `
            -FolderPath $rootPath `
            -FolderSearch $currentSearchCode
        )
      }
      else {

        $selectedPdfs =
        @(
          Select-DcaPdfByCode `
            -FolderPath $rootPath `
            -Code $currentSearchCode
        )
      }

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

      if ($selectedPdf.FolderImport) {

        Write-Warn (
          "Codigo nao reconhecido. Arquivo ignorado: " +
          "'$($selectedPdf.File.Name)'."
        )

        continue
      }

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

        Write-Warn (
          "Revisao nao encontrada no nome do PDF: " +
          "'$($selectedPdf.File.Name)'."
        )

        $revisionPrompt =
        if ($documentType -eq "Processo") {
          "Digite a revisao do Processo"
        }
        else {
          "Digite a revisao do Desenho Original"
        }

        $clientRevision =
        Read-Host (
          "$revisionPrompt para '$itemCodeFromFile' " +
          "ou Enter para ignorar"
        )

        if (
          [string]::IsNullOrWhiteSpace(
            $clientRevision
          )
        ) {

          Write-Warn (
            "Arquivo ignorado: '$($selectedPdf.File.Name)'."
          )

          continue
        }
      }
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

      if ($selectedPdf.FolderImport) {

        # Quando o arquivo possui somente o codigo,
        # usa o proprio codigo como nome.
        $itemNameText =
        $itemCodeFromFile

        if ($Details) {

          Write-Warn (
            "Titulo nao encontrado para '$itemCodeFromFile'. " +
            "O codigo sera usado como nome."
          )
        }
      }
      else {

        $itemNameText =
        Read-Host (
          "Digite o nome do item '$itemCodeFromFile' " +
          "(obrigatorio)"
        )
      }
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
        PdmState = [string]$selectedPdf.PdmState
      }
    )
  }

  if ($preparedDocuments.Count -eq 0) {
    throw "Nenhum documento ficou pronto para importacao."
  }
  Write-Section -Title "Resumo do lote"

  $totalPrepared =
  $preparedDocuments.Count

  $approvedPrepared =
  @(
    $preparedDocuments |
      Where-Object {
      $_.PdmState -ieq "Aprovado"
    }
  ).Count

  $obsoletePrepared =
  @(
    $preparedDocuments |
      Where-Object {
      $_.PdmState -ieq "Obsoleto"
    }
  ).Count

  $withoutWorkflowPrepared =
  $totalPrepared -
  $approvedPrepared -
  $obsoletePrepared

  Write-Host ""
  Write-Host (
    "  Documentos preparados: $totalPrepared"
  ) -ForegroundColor White

  Write-Host (
    "  Workflow de aprovacao: $approvedPrepared"
  ) -ForegroundColor Green

  Write-Host (
    "  Workflow de obsoleto:  $obsoletePrepared"
  ) -ForegroundColor Red

  Write-Host (
    "  Sem workflow:           $withoutWorkflowPrepared"
  ) -ForegroundColor Yellow

  if ($Details -or $totalPrepared -le 10) {

    Write-Host ""

    for (
      $index = 0
      $index -lt $preparedDocuments.Count
      $index++
    ) {

      $document =
      $preparedDocuments[$index]

      Write-Host (
        "  [{0}] {1} | {2} | {3}" -f
        ($index + 1),
        $document.ItemCode,
        $document.ClientRevision,
        $document.PdmState
      ) -ForegroundColor Gray
    }
  }
  else {

    Write-Host ""
    Write-Host (
      "  Lista individual ocultada para manter a tela limpa."
    ) -ForegroundColor DarkGray

    Write-Host (
      "  Execute com -Details para mostrar todos os documentos."
    ) -ForegroundColor DarkGray
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
    "Esta etapa vai processar $($preparedDocuments.Count) " +
    "documento(s) no Teamcenter."
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

    $workflowStarted =
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
        "Revisao do Teamcenter localizada."
      )

      if ($Details) {

        Write-Info (
          "Tipo tecnico: $revisionTypeName"
        )
      }
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
        "PDF temporario validado: " +
        "$($temporaryPdfFile.Length) bytes"
      )

      if ($Details) {

        Write-Info (
          "Arquivo temporario: " +
          $temporaryPdfPath
        )
      }
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
        -DatasetRevision $document.ClientRevision `
        -FilePath $temporaryPdfPath

      # O metodo pode ser void e retornar NULL.
      # A ausencia de excecao indica que a chamada terminou.
      $pdfImported =
      $true

      $pdmState =
([string]$document.PdmState).Trim()

$workflowTemplate =
$null

$workflowLabel =
$null

if ($pdmState -ieq "Aprovado") {

  $workflowTemplate =
  [string]$env:DCA_TC_APPROVED_WORKFLOW

  $workflowLabel =
  "aprovacao"
}
elseif ($pdmState -ieq "Obsoleto") {

  $workflowTemplate =
  [string]$env:DCA_TC_OBSOLETE_WORKFLOW

  $workflowLabel =
  "obsolescencia"
}

if ($null -eq $workflowLabel) {

  if (
    [string]::IsNullOrWhiteSpace(
      $pdmState
    )
  ) {

    Write-Info (
      "Estado do PDM nao identificado. " +
      "Nenhum workflow sera iniciado."
    )
  }
  else {

    Write-Info (
      "Estado no PDM: '$pdmState'. " +
      "Nenhum workflow configurado para esse estado."
    )
  }
}
elseif (
  [string]::IsNullOrWhiteSpace(
    $workflowTemplate
  )
) {

  Write-Warn (
    "Workflow de $workflowLabel nao configurado no .env. " +
    "O Item e o PDF foram mantidos sem workflow."
  )
}
else {

  Write-Info (
    "Estado no PDM: '$pdmState'. " +
    "Iniciando workflow de $workflowLabel..."
  )

  Start-TeamcenterWorkflow `
    -WorkflowTemplate $workflowTemplate `
    -Revision $teamcenterRevision

  $workflowStarted =
  $true

  Write-Success (
    "Workflow de $workflowLabel solicitado."
  )
}

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
          PdmState = $pdmState
          WorkflowStarted = $workflowStarted
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

      $successMessage =
      "$($result.ItemCode) -> " +
      "$($result.TeamcenterCode) - " +
      "Item e PDF importados"

      if ($result.WorkflowStarted) {

        $successMessage +=
        " - workflow solicitado"
      }

      Write-Success $successMessage
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
