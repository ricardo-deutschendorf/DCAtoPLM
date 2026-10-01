param(
  [string]$SearchRoot = "C:\DCA",

  [string]$SourceCode,

  [string]$ItemName,

  # Nome do vault no SolidWorks PDM. Pode ser substituido por DCA_VAULT_NAME.
  [string]$VaultName = "DCA",

  # Caminho para Interop.EdmLib.dll. Pode ser substituido por DCA_PDM_LIB.
  [string]$PdmLibraryPath = "<PDM_INTEROP_EDMLIB_DLL_PATH>",

  # Arquivo de credencial Export-Clixml. Pode ser substituido por DCA_VAULT_CREDENTIAL.
  [string]$VaultCredentialPath = "<VAULT_CREDENTIAL_CLIXML_PATH>",

  # Enumera arquivos locais sem usar a API do PDM.
  [switch]$NoVaultApi,

  # Apenas pesquisa; nao conecta ao Teamcenter nem cria objetos.
  [switch]$Preview,

  # Exibe diagnosticos tecnicos.
  [switch]$Details
)

$ErrorActionPreference = "Stop"
$script:ShowDetails = [bool]$Details
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
  Write-Host "[ERROR] Arquivo do helper nao encontrado:" -ForegroundColor Red
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
      "[ERROR] A funcao '$requiredFunction' nao foi carregada de " +
      "'$teamcenterFunctionsPath'."
    ) -ForegroundColor Red
    exit 1
  }
}

function Write-Section {

  param(
    [Parameter(Mandatory = $true)]
    [string]$Title
  )

  Write-Host ""
  Write-Host ("=" * 60) -ForegroundColor White
  Write-Host " $Title" -ForegroundColor White
  Write-Host ("=" * 60) -ForegroundColor White
}

function Write-Success {

  param(
    [Parameter(Mandatory = $true)]
    [string]$Message
  )

  Write-Host "  [OK] $Message" -ForegroundColor Green
}

function Write-Failure {

  param(
    [Parameter(Mandatory = $true)]
    [string]$Message
  )

  Write-Host "  [ERROR] $Message" -ForegroundColor Red
}

function Write-Warn {

  param(
    [Parameter(Mandatory = $true)]
    [string]$Message
  )

  Write-Host "  [WARNING] $Message" -ForegroundColor Yellow
}

function Write-Info {

  param(
    [Parameter(Mandatory = $true)]
    [string]$Message
  )

  if (-not $script:ShowDetails) {
    return
  }

  Write-Host "  -> $Message" -ForegroundColor Gray
}

# A API do PDM pode retornar arquivos do servidor que nao estao no cache local.
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

    $hasCredentialFile =
    -not [string]::IsNullOrWhiteSpace($VaultCredentialPath) -and
    $VaultCredentialPath -notlike "<*>" -and
    (Test-Path -LiteralPath $VaultCredentialPath -PathType Leaf)

    if ($hasCredentialFile) {

      $credential = Import-Clixml -LiteralPath $VaultCredentialPath

      if ($null -eq $credential) {
        throw "O arquivo de credencial do vault nao pode ser lido."
      }

      $securePassword = $credential.SenhaCriptografada | ConvertTo-SecureString

      $passwordPointer =
      [Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePassword)

      $plainTextPassword =
      [Runtime.InteropServices.Marshal]::PtrToStringBSTR($passwordPointer)

      $vault.Login($credential.Usuario, $plainTextPassword, $VaultName)
    }
    else {

      Write-Info "Credencial do vault nao informada. Tentando login automatico."

      $vault.LoginAuto($VaultName, 0)
    }

    if (-not $vault.IsLoggedIn) {
      throw "Nao foi possivel autenticar no vault '$VaultName'."
    }

    $script:DcaVault = $vault

    Write-Info "API do PDM conectada ao vault '$VaultName'."

    return $vault
  }
  catch {

    Write-Warn (
      "API do PDM indisponivel: $($_.Exception.Message) " +
      "Usando apenas o sistema de arquivos."
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

# Pesquisa o vault pelo nome e retorna PDFs para filtragem posterior.
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

  Write-Info "Padrao enviado ao vault: [$likePattern]"

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

# Garante que o PDF selecionado esteja disponivel no cache local do PDM.
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

  Write-Info "PDF fora do cache local. Baixando do vault..."

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

# Extrai o codigo de uma norma a partir do nome descritivo do PDF.
function Get-NormaCodeFromText {

  param(
    [Parameter(Mandatory = $true)]
    [string]$Text
  )

  $trimmedText = $Text.Trim()

  if ($trimmedText -notmatch '\s') {

    return [PSCustomObject]@{
      Code = $trimmedText
      Title = $null
      Parsed = $true
    }
  }

  $normaPattern =
  '^(?<Code>[A-Za-z]{2,}[ -]?[A-Za-z]{0,3}\d[\w./-]*)(?:\s+(?<Title>\S.*))?$'

  if ($trimmedText -match $normaPattern) {

    return [PSCustomObject]@{
      Code = $Matches["Code"].Trim()
      Title = [string]$Matches["Title"]
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

  if ($DocumentType -eq "NormaExterna") {

    $normaInfo = Get-NormaCodeFromText -Text $sourceCodeText
    $sourceCodeText = $normaInfo.Code
    $codeParsed = $normaInfo.Parsed
  }

  return [PSCustomObject]@{
    SourceCode = $sourceCodeText
    ClientRevision = $clientRevision
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

  $usesWildcard =
  $searchPattern.IndexOf("*") -ge 0 -or
  $searchPattern.IndexOf("?") -ge 0

  Write-Host ""

  if ($usesWildcard) {
    Write-Host "  -> Pesquisando com o padrao: [$searchPattern]" -ForegroundColor Gray
  }
  else {
    Write-Host "  -> Pesquisando o codigo exato: [$searchPattern]" -ForegroundColor Gray
  }

  $rootFolders =
  @(Get-ChildItem -LiteralPath $FolderPath -Directory -Force -ErrorAction Stop)

  $documentationFolder =
  $rootFolders |
    Where-Object { $_.Name -like "Documenta*" } |
    Select-Object -First 1

  if ($null -eq $documentationFolder) {

    $visibleFolderNames = @($rootFolders | ForEach-Object { $_.Name })

    throw (
      "A pasta de documentacao nao foi encontrada em '$FolderPath'. " +
      "Pastas visiveis: " + ($visibleFolderNames -join ", ")
    )
  }

  Write-Host "  -> Pasta localizada: $($documentationFolder.FullName)" -ForegroundColor DarkGray

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

  $documentationSubfolders =
  @(Get-ChildItem -LiteralPath $documentationFolder.FullName -Directory -Force -ErrorAction Stop)

  $searchFolders = [System.Collections.Generic.List[object]]::new()

  foreach ($categoryDefinition in $categoryDefinitions) {

    $categoryFolder =
    $documentationSubfolders |
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

  # Uma unica busca no servidor (API do PDM); depois separa por categoria.
  $apiEntries = $null
  $vault = Get-DcaVault

  if ($null -ne $vault) {

    Write-Host "  -> Pesquisando no vault (pode demorar)..." -ForegroundColor DarkGray

    try {
      $apiEntries = @(Search-DcaVaultPdfEntries -Vault $vault -SearchText $searchPattern)

      if ($apiEntries.Count -gt 0) {
        Write-Info "Exemplo de caminho retornado: $($apiEntries[0].FullName)"
      }
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

    $sourceLabel = "disco"

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

      $sourceLabel = "API do PDM"
    }
    else {

      Write-Host "  -> Lendo $($searchFolder.DisplayName) em disco..." -ForegroundColor DarkGray

      $pdfEntries =
      @(
        Get-DcaDiskPdfEntries -FolderPath $searchFolder.DirectoryPath |
          Sort-Object FullName
      )
    }

    Write-Host (
      "  -> $($searchFolder.DisplayName): " +
      "$($pdfEntries.Count) PDF(s) candidato(s) [$sourceLabel]"
    ) -ForegroundColor DarkGray

    if ($pdfEntries.Count -eq 0 -and $null -eq $apiEntries) {
      Write-Warn (
        "Nenhum PDF em disco e a API do PDM nao foi usada. " +
        "O conteudo pode existir so no servidor do PDM."
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

  Write-Host ""
  Write-Host "PDFs encontrados para '$searchPattern':" -ForegroundColor Cyan
  Write-Host ""

  for ($index = 0; $index -lt $matchCount; $index++) {

    $number = $index + 1
    $currentMatch = $matchingFiles[$index]
    $revisionDisplay = [string]$currentMatch.ClientRevision

    if ([string]::IsNullOrWhiteSpace($revisionDisplay)) {
      $revisionDisplay = "nao informada"
    }

    Write-Host "  [$number] $($currentMatch.File.Name)" -ForegroundColor White
    Write-Host "      Caminho: $($currentMatch.File.FullName)" -ForegroundColor Gray
    Write-Host "      Codigo: [$($currentMatch.SourceCode)]" -ForegroundColor DarkGray
    Write-Host "      Revisao: [$revisionDisplay]" -ForegroundColor DarkGray
    Write-Host "      Tipo: [$($currentMatch.TypeDisplayName)]" -ForegroundColor DarkGray
    Write-Host ""
  }

  if ($matchCount -eq 1) {
    Write-Success "O unico PDF encontrado foi selecionado automaticamente."
    return $matchingFiles[0]
  }

  while ($true) {

    $selectionText = Read-Host "Digite o numero do PDF desejado (1 ate $matchCount)"
    $selectedNumber = 0

    $validNumber =
    [System.Int32]::TryParse($selectionText, [ref]$selectedNumber)

    if (-not $validNumber -or $selectedNumber -lt 1 -or $selectedNumber -gt $matchCount) {
      Write-Host "Opcao invalida. Digite um numero entre 1 e $matchCount." -ForegroundColor Yellow
      continue
    }

    $selectedFile = $matchingFiles[$selectedNumber - 1]

    Write-Host ""
    Write-Success "PDF selecionado: $($selectedFile.File.FullName)"

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
    throw "PDF de origem nao encontrado: $SourcePdfPath"
  }

  $sourceFile = Get-Item -LiteralPath $SourcePdfPath -ErrorAction Stop

  if ($sourceFile.Extension -ine ".pdf") {
    throw "O arquivo de origem nao possui extensao PDF."
  }

  if ($sourceFile.Length -le 0) {
    throw "O PDF de origem esta vazio."
  }

  $temporaryFolder = "C:\Temp\DCAtoPLM"

  if (-not (Test-Path -LiteralPath $temporaryFolder -PathType Container)) {
    $null = New-Item -Path $temporaryFolder -ItemType Directory -Force -ErrorAction Stop
  }

  $safeItemCode = $ItemCode -replace '[\\/:*?"<>|]', '_'
  $temporaryPdfPath = Join-Path -Path $temporaryFolder -ChildPath "$safeItemCode.pdf"

  if (Test-Path -LiteralPath $temporaryPdfPath -PathType Leaf) {
    Remove-Item -LiteralPath $temporaryPdfPath -Force -ErrorAction Stop
  }

  Write-Info "Copiando PDF para pasta temporaria..."
  Write-Info "Origem: $SourcePdfPath"
  Write-Info "Destino: $temporaryPdfPath"

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

    $stream =
    [System.IO.File]::Open(
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
  Write-Info "Tamanho: $($temporaryFile.Length) bytes"

  return $temporaryFile.FullName
}

function Invoke-DcaMain {

  Write-Section -Title "ETAPA 1/3 - INFORMACOES DO ITEM"

  $searchPattern = $SourceCode

  if ([string]::IsNullOrWhiteSpace($searchPattern)) {
    $searchPattern = Read-Host "Digite o codigo para pesquisar; use * para busca parcial"
  }

  if ([string]::IsNullOrWhiteSpace($searchPattern)) {
    throw "Codigo do item nao informado."
  }

  $itemNameText = $ItemName

  if ([string]::IsNullOrWhiteSpace($itemNameText)) {
    $itemNameText = Read-Host "Digite o nome do item"
  }

  if ([string]::IsNullOrWhiteSpace($itemNameText)) {
    throw "Nome do item nao informado."
  }

  $itemNameText = $itemNameText.Trim()

  $rootPath = $SearchRoot

  if ([string]::IsNullOrWhiteSpace($rootPath)) {
    $rootPath = "C:\DCA"
  }

  Write-Section -Title "ETAPA 2/3 - LOCALIZAR PDF"

  $selectedPdf = Select-DcaPdfByCode -FolderPath $rootPath -Code $searchPattern

  if ($null -eq $selectedPdf) {
    throw "Nenhum PDF foi selecionado para a pesquisa '$searchPattern'."
  }

  $documentType = [string]$selectedPdf.DocumentType
  $itemCodeFromFile = [string]$selectedPdf.SourceCode

  # Norma Externa: se o codigo nao pode ser extraido do nome, confirmar.
  if ($documentType -eq "NormaExterna" -and -not $selectedPdf.CodeParsed) {

    Write-Warn (
      "Nao foi possivel extrair o codigo da norma de: " +
      "'$($selectedPdf.File.BaseName)'."
    )

    $typedCode =
    Read-Host "Digite o codigo da norma (Enter usa o nome completo)"

    if (-not [string]::IsNullOrWhiteSpace($typedCode)) {
      $itemCodeFromFile = $typedCode.Trim()
    }
  }

  $clientRevision = [string]$selectedPdf.ClientRevision

  if ([string]::IsNullOrWhiteSpace($clientRevision)) {

    if ($documentType -eq "NormaExterna") {

      $clientRevision = "000"
      Write-Host "  -> Revisao inicial da Norma Externa: [000]" -ForegroundColor Gray
    }
    else {

      $clientRevision = Read-Host "Digite a Revisao Cliente (Original: B ou BA4; Processo: BA4)"

      if ([string]::IsNullOrWhiteSpace($clientRevision)) {
        throw "Revisao Cliente nao informada."
      }
    }
  }

  $clientRevision = $clientRevision.Trim().ToUpper()

  Write-Host ""
  Write-Host "Resumo do que sera criado:" -ForegroundColor Cyan
  Write-Host "  Tipo:    $($selectedPdf.TypeDisplayName) [$documentType]" -ForegroundColor Gray
  Write-Host "  Codigo:  $itemCodeFromFile" -ForegroundColor Gray
  Write-Host "  Revisao: $clientRevision" -ForegroundColor Gray
  Write-Host "  Nome:    $itemNameText" -ForegroundColor Gray
  Write-Host "  Arquivo: $($selectedPdf.File.FullName)" -ForegroundColor Gray

  if ($Preview) {

    Write-Host ""
    Write-Success "Preview apenas. Nada foi criado no Teamcenter."

    return 0
  }

  $null = Connect-Teamcenter

  Write-Section -Title "ETAPA 3/3 - CRIAR ITEM E IMPORTAR PDF"

  Write-Host ""
  Write-Host "ATENCAO: esta etapa vai criar itens reais no Teamcenter." -ForegroundColor Yellow

  $confirmation = Read-Host "Digite SIM para continuar ou pressione Enter para abortar"

  if ($confirmation -ne "sim") {

    Write-Host ""
    Write-Host "Abortado pelo usuario. Nenhum item foi criado." -ForegroundColor Yellow

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
      throw "New-DcaTeamcenterItem nao retornou resultado para '$itemCodeFromFile'."
    }

    $createdCode = [string]$teamcenterDestination.Code

    if ([string]::IsNullOrWhiteSpace($createdCode)) {
      throw "O codigo criado nao foi retornado."
    }

    $teamcenterItem = $teamcenterDestination.Item

    if ($null -ne $teamcenterItem) {
      $teamcenterItem = $teamcenterItem.PSObject.BaseObject
    }

    if ($null -eq $teamcenterItem) {
      throw "O Item criado nao foi retornado para '$createdCode'."
    }

    Write-Info "Tipo do Item retornado: $($teamcenterItem.GetType().FullName)"

    $teamcenterRevision = $teamcenterDestination.Revision

    if ($null -ne $teamcenterRevision) {
      $teamcenterRevision = $teamcenterRevision.PSObject.BaseObject
    }

    if ($null -eq $teamcenterRevision) {

      Write-Info "Revisao nao retornada diretamente. Consultando pelo Item..."

      $teamcenterRevision = Get-TeamcenterRevision -Item $teamcenterItem

      if ($null -ne $teamcenterRevision) {
        $teamcenterRevision = $teamcenterRevision.PSObject.BaseObject
      }
    }

    if ($null -eq $teamcenterRevision) {
      throw "A revisao do Teamcenter nao foi encontrada para '$createdCode'."
    }

    $revisionTypeName = $teamcenterRevision.GetType().FullName

    Write-Info "Tipo da revisao para importar o PDF: $revisionTypeName"

    if ($revisionTypeName -notmatch "ItemRevision") {
      throw (
        "O objeto retornado nao e uma revisao valida. " +
        "Tipo recebido: '$revisionTypeName'."
      )
    }

    $localPdfPath = Confirm-DcaLocalPdf -Entry $selectedPdf.File

    $temporaryPdfPath =
    Copy-PdfToTemporaryFolder `
      -SourcePdfPath $localPdfPath `
      -ItemCode $createdCode

    if ([string]::IsNullOrWhiteSpace($temporaryPdfPath)) {
      throw "Copy-PdfToTemporaryFolder nao retornou o caminho do PDF temporario."
    }

    Write-Info "Importando PDF no Teamcenter..."

    $importResult =
    Import-TeamcenterPdf `
      -Revision $teamcenterRevision `
      -ItemCode $createdCode `
      -FilePath $temporaryPdfPath

    Write-Success "PDF importado: $createdCode"

    if ($null -eq $importResult) {
      Write-Info "ImportarPDF retornou NULL, mas nao gerou excecao."
    }
    else {
      Write-Info "Resultado da importacao: $importResult"
    }
  }
  catch {

    Write-Failure $_.Exception.Message

    Write-Section -Title "RESULTADO"
    Write-Failure "$itemCodeFromFile -> FALHOU (item no Teamcenter: $createdCode)"

    return 1
  }

  Write-Section -Title "RESULTADO"
  Write-Success "$itemCodeFromFile -> $createdCode"

  return 0
}

$exitCode = 1

try {
  $exitCode = @(Invoke-DcaMain) | Select-Object -Last 1
}
catch {

  Write-Failure $_.Exception.Message

  if ($script:ShowDetails) {
    Write-Host $_.ScriptStackTrace -ForegroundColor DarkGray
  }

  $exitCode = 1
}

exit ([int]$exitCode)
