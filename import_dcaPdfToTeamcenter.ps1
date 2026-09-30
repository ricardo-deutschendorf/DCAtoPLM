# === DCA PDF to Teamcenter import workflow ===
# Place this file in the project root, next to import_toTeamcenter.ps1.

param(
  # Batch mode: search a vault folder for one or more codes
  [string]$SearchRoot = "C:\DCA",

  # Codes separated by comma, semicolon or space (e.g. "1003649,1003650")
  [string]$Codes,

  # Text file with one code per line
  [string]$CodesFile,
  [string]$ItemName,
  # Single-item mode: process exactly one already-known PDF path
  [string]$SourceCode,
  [switch]$Preview
)

try {
  [Console]::InputEncoding = [System.Text.Encoding]::UTF8
  [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
}
catch {
  # Ignora se a saida nao for um console interativo (ex: rodando via agendador).
}

$isSingleItemMode =
-not [string]::IsNullOrWhiteSpace($SourceCode) -or
(
  [string]::IsNullOrWhiteSpace($Codes) -and
  [string]::IsNullOrWhiteSpace($CodesFile)
)

if ($isSingleItemMode) {

  Write-Host ""
  Write-Host "============================================" -ForegroundColor White
  Write-Host " Criacao de item com PDF no Teamcenter" -ForegroundColor White
  Write-Host "============================================" -ForegroundColor White
  Write-Host ""

  if ([string]::IsNullOrWhiteSpace($SourceCode)) {

    $SourceCode =
    Read-Host "Digite o codigo para pesquisar"
  }

  if ([string]::IsNullOrWhiteSpace($SourceCode)) {

    throw "Codigo do item nao informado."
  }

  $SourceCode =
  $SourceCode.Trim().ToUpper()

  if ([string]::IsNullOrWhiteSpace($ItemName)) {

    $ItemName =
    Read-Host "Digite o nome do item"
  }

  if ([string]::IsNullOrWhiteSpace($ItemName)) {

    throw "Nome do item nao informado."
  }

  $ItemName =
  $ItemName.Trim()

  if ([string]::IsNullOrWhiteSpace($SearchRoot)) {

    $SearchRoot =
    "C:\DCA"
  }
}
elseif ([string]::IsNullOrWhiteSpace($SearchRoot)) {

  throw "Informe -SearchRoot para a pesquisa em lote."
}

$ErrorActionPreference = "Stop"

$itemType =
"GD5_DCA_DESENHO"

$teamcenterFunctionsPath =
Join-Path $PSScriptRoot  "functions\teamcenter_functions.ps1"

if (-not (
    Test-Path -LiteralPath $teamcenterFunctionsPath -PathType Leaf
  )) {

  Write-Host  "[ERROR] Teamcenter functions file not found:"  -ForegroundColor Red

  Write-Host $teamcenterFunctionsPath -ForegroundColor Red

  exit 1
}

. $teamcenterFunctionsPath
$requiredFunctions = @(
  "Connect-Teamcenter",
  "Get-TeamcenterMethod",
  "Get-TeamcenterRevision",
  "Import-TeamcenterPdf",
  "New-DcaTeamcenterItem"
)

foreach ($requiredFunction in $requiredFunctions) {

  $loadedFunction = Get-Command `
    -Name $requiredFunction `
    -CommandType Function `
    -ErrorAction SilentlyContinue

  if ($null -eq $loadedFunction) {

    throw (
      "A funcao '$requiredFunction' nao foi carregada de " +
      "'$teamcenterFunctionsPath'. Verifique o arquivo helper."
    )
  }
}
# Section: Print a console section heading
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

# Section: Print a success message
function Write-Success {

  param(
    [Parameter(Mandatory = $true)]
    [string]$Message
  )

  Write-Host  "  [OK] $Message"  -ForegroundColor Green
}

# Section: Print a failure message
function Write-Failure {

  param(
    [Parameter(Mandatory = $true)]
    [string]$Message
  )

  Write-Host  "  [ERROR] $Message"  -ForegroundColor Red
}

# Section: Print an informational message
function Write-Info {

  param(
    [Parameter(Mandatory = $true)]
    [string]$Message
  )

  Write-Host  "  -> $Message"  -ForegroundColor Gray
}

# Section: Read the list of codes to search
function Get-CodeList {

  param(
    [string]$CodesText,

    [string]$CodesFilePath
  )

  $rawCodes =
  [System.Collections.Generic.List[string]]::new()

  if (-not [string]::IsNullOrWhiteSpace($CodesText)) {

    foreach ($item in ($CodesText -split '[,;\s]+')) {

      $rawCodes.Add($item)
    }
  }

  if (-not [string]::IsNullOrWhiteSpace($CodesFilePath)) {

    if (-not (
        Test-Path -LiteralPath $CodesFilePath -PathType Leaf
      )) {

      throw  "Codes file not found at '$CodesFilePath'."
    }

    foreach ($line in (Get-Content -LiteralPath $CodesFilePath -Encoding UTF8)) {

      foreach ($item in ($line -split '[,;\s]+')) {

        $rawCodes.Add($item)
      }
    }
  }

  $codeList =
  @(
    $rawCodes |
      Where-Object {
      -not [string]::IsNullOrWhiteSpace($_)
    } |
      ForEach-Object {
      $_.Trim()
    } |
      Sort-Object -Unique
  )

  if ($codeList.Count -eq 0) {

    throw  "No codes were provided. Use -Codes or -CodesFile."
  }

  Write-Host "  -> Codes: $($codeList -join ', ')" -ForegroundColor Gray

  return $codeList
}

# Section: Index every PDF under the vault folder (real .pdf only, other file types are ignored)
function Get-AllPdfFiles {

  param(
    [Parameter(Mandatory = $true)]
    [string]$FolderPath
  )

  if (-not (
      Test-Path -LiteralPath $FolderPath -PathType Container
    )) {

    throw  "Search folder not found at '$FolderPath'."
  }

  # The extension check is needed because -Filter "*.pdf" can also match
  # longer extensions that start with .pdf on Windows.
  $pdfFiles =
  @(
    Get-ChildItem -LiteralPath $FolderPath -Filter "*.pdf"  -File -Recurse |
      Where-Object {
      $_.Extension -ieq ".pdf"
    }
  )

  return $pdfFiles
}

# Section: Match indexed PDFs to a requested code
# "1003649" matches 1003649 and 1003649-1, 1003649-11, ...
# "1003649-1" matches only 1003649-1
function Find-PdfFilesByCode {

  param(
    [Parameter(Mandatory = $true)]
    [string]$Code,

    [Parameter(Mandatory = $true)]
    [AllowEmptyCollection()]
    [object[]]$ParsedFiles
  )

  $escapedCode =
  [regex]::Escape($Code)

  return @(
    $ParsedFiles |
      Where-Object {
      $_.SourceCode -match "^$escapedCode(-\d+)?$"
    }
  )
}
function ConvertFrom-PdfFileName {

  param(
    [Parameter(Mandatory = $true)]
    [System.IO.FileInfo]$PdfFile
  )

  $baseName =
  $PdfFile.BaseName.Trim()

  $sourceCode =
  $baseName

  $clientRevision =
  $null

  if (
    $baseName -match
    '^(?<Code>[^\[\]]+?)\s*\[(?<Revision>[^\]]+)\]\s*$'
  ) {

    $sourceCode =
    $Matches["Code"].Trim()

    $clientRevision =
    $Matches["Revision"].Trim().ToUpper()
  }

  return [PSCustomObject]@{
    File = $PdfFile
    SourceCode = $sourceCode
    ClientRevision = $clientRevision
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

  if (-not (
      Test-Path `
        -LiteralPath $FolderPath `
        -PathType Container
    )) {

    throw "Pasta do Vault DCA nao encontrada: $FolderPath"
  }

  $codeClean =
  $Code.Trim().ToUpper()

  Write-Host ""
  Write-Info "Pesquisando o codigo '$codeClean' no Vault DCA..."
  Write-Info "Pasta raiz: $FolderPath"

  $matchingFiles =
  [System.Collections.Generic.List[object]]::new()

  $pdfFiles =
  @(
    Get-ChildItem `
      -LiteralPath $FolderPath `
      -Filter "*.pdf" `
      -File `
      -Recurse `
      -ErrorAction Stop |
      Where-Object {
      $_.Extension -ieq ".pdf"
    } |
      Sort-Object FullName
  )

  Write-Info (
    "Total de PDFs examinados: " +
    $pdfFiles.Count
  )

  foreach ($pdfFile in $pdfFiles) {

    $parsedFile =
    ConvertFrom-PdfFileName `
      -PdfFile $pdfFile

    if ($null -eq $parsedFile) {
      continue
    }

    $parsedCode =
    [string]$parsedFile.SourceCode

    if (
      [System.String]::IsNullOrWhiteSpace(
        $parsedCode
      )
    ) {

      continue
    }

    if (
      $parsedCode.Trim().ToUpper() -eq
      $codeClean
    ) {

      $matchingFiles.Add(
        $parsedFile
      )
    }
  }

  $matchCount =
  $matchingFiles.Count

  Write-Info (
    "Total de PDFs encontrados para o codigo: " +
    $matchCount
  )

  if ($matchCount -eq 0) {

    throw (
      "Nenhum PDF foi encontrado para o codigo " +
      "'$codeClean' dentro de '$FolderPath'."
    )
  }

  Write-Host ""
  Write-Host (
    "PDFs encontrados para o codigo '$codeClean':"
  ) -ForegroundColor Cyan

  Write-Host ""

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
      [System.String]::IsNullOrWhiteSpace(
        $revisionDisplay
      )
    ) {

      $revisionDisplay =
      "nao informada no nome do PDF"
    }

    Write-Host (
      "  [$number] $($currentMatch.File.FullName)"
    ) -ForegroundColor White

    Write-Host (
      "      Revisao encontrada: " +
      "[$revisionDisplay]"
    ) -ForegroundColor DarkGray

    Write-Host ""
  }

  if ($matchCount -eq 1) {

    Write-Success (
      "O unico PDF encontrado foi selecionado automaticamente."
    )

    return $matchingFiles[0]
  }

  while ($true) {

    $selectionText =
    Read-Host (
      "Digite o numero do PDF desejado " +
      "(1 ate $matchCount)"
    )

    $selectedNumber =
    0

    $isValidNumber =
    [System.Int32]::TryParse(
      $selectionText,
      [ref]$selectedNumber
    )

    if (-not $isValidNumber) {

      Write-Host (
        "Opcao invalida. Digite somente o numero."
      ) -ForegroundColor Yellow

      continue
    }

    if (
      $selectedNumber -lt 1 -or
      $selectedNumber -gt $matchCount
    ) {

      Write-Host (
        "Opcao invalida. Digite um numero entre 1 e " +
        "$matchCount."
      ) -ForegroundColor Yellow

      continue
    }

    $selectedFile =
    $matchingFiles[$selectedNumber - 1]

    Write-Host ""

    Write-Success (
      "PDF selecionado: " +
      $selectedFile.File.FullName
    )

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

  if (-not (
      Test-Path `
        -LiteralPath $SourcePdfPath `
        -PathType Leaf
    )) {

    throw "PDF de origem nao encontrado: $SourcePdfPath"
  }

  $sourceFile =
  Get-Item `
    -LiteralPath $SourcePdfPath `
    -ErrorAction Stop

  if ($sourceFile.Extension -ine ".pdf") {
    throw "O arquivo de origem nao possui extensao PDF."
  }

  if ($sourceFile.Length -le 0) {
    throw "O PDF de origem esta vazio."
  }

  $temporaryFolder =
  "C:\Temp\DCAtoPLM"

  if (-not (
      Test-Path `
        -LiteralPath $temporaryFolder `
        -PathType Container
    )) {

    $null =
    New-Item `
      -Path $temporaryFolder `
      -ItemType Directory `
      -Force `
      -ErrorAction Stop
  }

  $safeItemCode =
  $ItemCode -replace '[\\/:*?"<>|]', '_'

  $temporaryPdfPath =
  Join-Path `
    -Path $temporaryFolder `
    -ChildPath "$safeItemCode.pdf"

  if (
    Test-Path `
      -LiteralPath $temporaryPdfPath `
      -PathType Leaf
  ) {

    Remove-Item `
      -LiteralPath $temporaryPdfPath `
      -Force `
      -ErrorAction Stop
  }

  Write-Info "Copiando PDF para pasta temporaria..."
  Write-Info "Origem: $SourcePdfPath"
  Write-Info "Destino: $temporaryPdfPath"

  Copy-Item `
    -LiteralPath $SourcePdfPath `
    -Destination $temporaryPdfPath `
    -Force `
    -ErrorAction Stop

  if (-not (
      Test-Path `
        -LiteralPath $temporaryPdfPath `
        -PathType Leaf
    )) {

    throw "O PDF nao foi criado na pasta temporaria."
  }

  $temporaryFile =
  Get-Item `
    -LiteralPath $temporaryPdfPath `
    -ErrorAction Stop

  if ($temporaryFile.Length -ne $sourceFile.Length) {

    throw (
      "O tamanho da copia temporaria e diferente do original. " +
      "Original: $($sourceFile.Length) bytes. " +
      "Copia: $($temporaryFile.Length) bytes."
    )
  }

  $stream =
  $null

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
if (
  $null -eq (
    Get-Command `
      -Name "Copy-PdfToTemporaryFolder" `
      -CommandType Function `
      -ErrorAction SilentlyContinue
  )
) {

  throw "A funcao Copy-PdfToTemporaryFolder nao foi carregada."
}
try {

  $parsedFiles =
  [System.Collections.Generic.List[object]]::new()

  $missingCodes =
  [System.Collections.Generic.List[string]]::new()

  if ($isSingleItemMode) {

    Write-Section -Title "PDF SEARCH"

    $selectedPdf =
    Select-DcaPdfByCode `
      -FolderPath $SearchRoot `
      -Code $SourceCode

    if ($null -eq $selectedPdf) {

      throw (
        "Nenhum PDF foi selecionado para o codigo " +
        "'$SourceCode'."
      )
    }

    $selectedPdf.SourceCode =
    $SourceCode.Trim().ToUpper()

    # Se a revisao nao estiver no nome do PDF, solicita ao usuario.
    if (
      [System.String]::IsNullOrWhiteSpace(
        [string]$selectedPdf.ClientRevision
      )
    ) {

      Write-Host ""

      Write-Host (
        "O PDF selecionado nao possui revisao no nome."
      ) -ForegroundColor Yellow

      Write-Host (
        "Arquivo: $($selectedPdf.File.FullName)"
      ) -ForegroundColor Gray

      Write-Host ""

      $typedClientRevision =
      Read-Host "Digite a Revisao Cliente, por exemplo B"

      if (
        [System.String]::IsNullOrWhiteSpace(
          $typedClientRevision
        )
      ) {

        throw "Revisao Cliente nao informada."
      }

      $typedClientRevision =
      $typedClientRevision.Trim().ToUpper()

      if ($typedClientRevision.Length -gt 2) {

        throw (
          "A Revisao Cliente '$typedClientRevision' possui " +
          "$($typedClientRevision.Length) caracteres. " +
          "O Teamcenter permite no maximo 2."
        )
      }

      $selectedPdf.ClientRevision =
      $typedClientRevision
    }

    $parsedFiles.Add(
      $selectedPdf
    )

    Write-Host ""
    Write-Section -Title "SELECTED PDF"

    Write-Info "Codigo: $($selectedPdf.SourceCode)"
    Write-Info "Nome do item: $ItemName"
    Write-Info "PDF: $($selectedPdf.File.FullName)"
    Write-Info "Revisao Cliente: $($selectedPdf.ClientRevision)"
  }
  else {

    Write-Section -Title "PDF SEARCH"

    $requestedCodes =
    @(
      Get-CodeList -CodesText $Codes -CodesFilePath $CodesFile
    )

    Write-Info -Message "Codes requested: $($requestedCodes -join ', ')"

    Write-Info -Message "Search folder: $SearchRoot"

    $allPdfFiles =
    @(
      Get-AllPdfFiles -FolderPath $SearchRoot
    )

    Write-Info -Message "$($allPdfFiles.Count) PDF file(s) indexed."

    $allParsedFiles =
    @(
      $allPdfFiles |
        ForEach-Object {
        ConvertFrom-PdfFileName -PdfFile $_
      }
    )

    $addedPaths =
    [System.Collections.Generic.HashSet[string]]::new(
      [System.StringComparer]::OrdinalIgnoreCase
    )

    Write-Host ""

    foreach ($requestedCode in $requestedCodes) {

      $matchedFiles =
      @(
        Find-PdfFilesByCode -Code $requestedCode -ParsedFiles $allParsedFiles
      )

      if ($matchedFiles.Count -eq 0) {

        $missingCodes.Add(
          $requestedCode
        )

        Write-Host  "  [NOT FOUND] $requestedCode"  -ForegroundColor Yellow

        continue
      }

      foreach ($matchedFile in $matchedFiles) {

        if ($addedPaths.Add($matchedFile.File.FullName)) {

          $parsedFiles.Add(
            $matchedFile
          )

          Write-Info -Message "$requestedCode  =>  $($matchedFile.File.FullName)  |  bracket: $($matchedFile.ClientRevision)"
        }
      }
    }

    if ($parsedFiles.Count -eq 0) {

      throw  "No PDF was found for the requested code(s)."
    }

    $duplicateNames =
    @(
      $parsedFiles |
        Group-Object { $_.File.Name } |
        Where-Object {
        $_.Count -gt 1
      }
    )

    foreach ($duplicateName in $duplicateNames) {

      Write-Host  "  [WARNING] Mesmo nome de PDF em mais de uma pasta: $($duplicateName.Name)"  -ForegroundColor Yellow
    }
  }

  Write-Host ""

  Write-Success -Message "$($parsedFiles.Count) PDF file(s) ready to import."

  if ($Preview) {

    Write-Host ""
    Write-Success -Message "Preview only. Nothing was created in Teamcenter."

    exit 0
  }

  Write-Section -Title "TEAMCENTER CONNECTION"

  $null = Connect-Teamcenter

  Write-Success -Message "Teamcenter connection established."

  Write-Section -Title "TEAMCENTER IMPORT"

  Write-Host ""
  Write-Host "ATENCAO: as proximas linhas vao CRIAR itens reais no Teamcenter." -ForegroundColor Yellow
  $confirmation = Read-Host "Digite 'sim' para continuar, ou qualquer outra coisa para abortar"

  if ($confirmation -ne "sim") {

    Write-Host ""
    Write-Host "Abortado pelo usuario. Nenhum item foi criado." -ForegroundColor Yellow
    exit 0
  }

  $importResults =
  [System.Collections.Generic.List[object]]::new()

  foreach ($parsedFile in $parsedFiles) {

    $createdCode =
    $null

    try {

      Write-Host ""

      Write-Info "Processing: $($parsedFile.File.Name)"

      $sourceCode =
      [string]$parsedFile.SourceCode

      $clientRevision =
      [string]$parsedFile.ClientRevision

      $itemNameForCreation =
      [string]$ItemName

      if ([System.String]::IsNullOrWhiteSpace($sourceCode)) {
        throw "Codigo do item ficou vazio."
      }

      if ([System.String]::IsNullOrWhiteSpace($clientRevision)) {

        throw (
          "Revisao Cliente nao encontrada no nome do PDF. " +
          "Arquivo: '$($parsedFile.File.Name)'. " +
          "Propriedades disponiveis: " +
          (($parsedFile.PSObject.Properties.Name) -join ", ")
        )
      }

      if ([System.String]::IsNullOrWhiteSpace($itemNameForCreation)) {
        throw "Nome do item ficou vazio."
      }

      Write-Info "Codigo do item: $sourceCode"
      Write-Info "Revisao Cliente: $clientRevision"
      Write-Info "Nome do item: $itemNameForCreation"

      $teamcenterDestination =
      New-DcaTeamcenterItem `
        -SourceCode $sourceCode `
        -ItemName $itemNameForCreation `
        -ClientRevision $clientRevision `
        -MaximumAttempts 20

      if ($null -eq $teamcenterDestination) {

        throw (
          "New-DcaTeamcenterItem nao retornou resultado " +
          "para '$sourceCode'."
        )
      }

      if ($null -eq $teamcenterDestination.Item) {

        throw (
          "New-DcaTeamcenterItem nao retornou o Item " +
          "para '$sourceCode'."
        )
      }

      $createdCode =
      [string]$teamcenterDestination.Code

      if ([System.String]::IsNullOrWhiteSpace($createdCode)) {
        throw "O codigo criado nao foi retornado."
      }

      Write-Success "Item criado: $createdCode"
      # ----------------------------------------------------
      # Obter o Item real retornado pelo Teamcenter
      # ----------------------------------------------------

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

      Write-Info (
        "Tipo do Item retornado: " +
        $teamcenterItem.GetType().FullName
      )

      # ----------------------------------------------------
      # Obter a revisao real do Teamcenter
      # ----------------------------------------------------

      $teamcenterRevision =
      $teamcenterDestination.Revision

      if ($null -ne $teamcenterRevision) {

        $teamcenterRevision =
        $teamcenterRevision.PSObject.BaseObject
      }

      if ($null -eq $teamcenterRevision) {

        Write-Info (
          "Revisao nao retornada diretamente. " +
          "Consultando pelo Item..."
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

      Write-Info (
        "Tipo da revisao para importar o PDF: " +
        $revisionTypeName
      )

      if ($revisionTypeName -notmatch "ItemRevision") {

        throw (
          "O objeto retornado nao e uma revisao valida. " +
          "Tipo recebido: '$revisionTypeName'."
        )
      }

      # ----------------------------------------------------
      # Copiar o PDF para a pasta temporaria
      # ----------------------------------------------------

      $temporaryPdfPath =
      Copy-PdfToTemporaryFolder `
        -SourcePdfPath $parsedFile.File.FullName `
        -ItemCode $createdCode

      if (
        [System.String]::IsNullOrWhiteSpace(
          $temporaryPdfPath
        )
      ) {

        throw (
          "Copy-PdfToTemporaryFolder nao retornou " +
          "o caminho do PDF temporario."
        )
      }

      # ----------------------------------------------------
      # Importar o PDF
      # ----------------------------------------------------

      Write-Info "Importando PDF no Teamcenter..."

      $importResult =
      Import-TeamcenterPdf `
        -Revision $teamcenterRevision `
        -ItemCode $createdCode `
        -FilePath $temporaryPdfPath

      Write-Success "PDF importado: $createdCode"

      if ($null -eq $importResult) {

        Write-Info (
          "ImportarPDF retornou NULL, mas nao gerou excecao."
        )
      }
      else {

        Write-Info "Resultado da importacao: $importResult"
      }

      # ----------------------------------------------------
      # Registrar sucesso
      # ----------------------------------------------------

      $importResults.Add(
        [PSCustomObject]@{
          SourceFile = $parsedFile.File.FullName
          SourceCode = $sourceCode
          TeamcenterCode = $createdCode
          Succeeded = $true
          ErrorMessage = $null
        }
      )
    }

    catch {

      $importResults.Add(
        [pscustomobject]@{
          Succeeded = $false
          SourceCode = $sourceCode
          TeamcenterCode = $createdCode
          ErrorMessage = $_.Exception.Message
        }
      )

      Write-Failure -Message $_.Exception.Message
    }
  }

  Write-Section -Title "IMPORT RESULT"

  foreach ($result in $importResults) {

    if ($result.Succeeded) {

      Write-Success -Message "$($result.SourceCode) -> $($result.TeamcenterCode)"
    }
    else {

      Write-Failure -Message "$($result.SourceCode) -> FAILED (item: $($result.TeamcenterCode))"
    }
  }

  $failedCount =
  @(
    $importResults |
      Where-Object {
      -not $_.Succeeded
    }
  ).Count

  Write-Host ""

  Write-Info -Message "Imported: $($importResults.Count - $failedCount) | Failed: $failedCount"

  if ($missingCodes.Count -gt 0) {

    Write-Host  "  [WARNING] Codigos sem PDF encontrado: $($missingCodes -join ', ')"  -ForegroundColor Yellow
  }

  if ($failedCount -gt 0) {

    exit 1
  }

  exit 0

}
catch {

  $realException =
  $_.Exception

  while ($null -ne $realException.InnerException) {

    $realException =
    $realException.InnerException
  }

  Write-Host ""
  Write-Failure -Message $realException.Message

  Write-Host ""
  Write-Host "[FULL ERROR]" -ForegroundColor DarkGray
  Write-Host $_.Exception.ToString() -ForegroundColor DarkGray
  Write-Host ""

  exit 1
}
