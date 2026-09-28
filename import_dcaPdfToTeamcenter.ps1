# === Criar item no Teamcenter e importar um PDF ===

param(
  [Parameter(Mandatory = $true)]
  [ValidateNotNullOrEmpty()]
  [string]$SourceCode,

  [Parameter(Mandatory = $true)]
  [ValidateNotNullOrEmpty()]
  [string]$PdfPath
)

$ErrorActionPreference = "Stop"

$companyCode = "02"
$itemType = "GD5DesignPerto"

$createdCode = $null
$teamcenterFunctionsPath = $null
$resolvedPdfPath = $null
$projectRoot = $PSScriptRoot

$teamcenterFunctionsPath =
Join-Path `
  -Path $PSScriptRoot `
  -ChildPath "functions\teamcenter_functions.ps1"

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

function Write-Info {

  param(
    [Parameter(Mandatory = $true)]
    [string]$Message
  )

  Write-Host "  -> $Message" -ForegroundColor Gray
}
function Write-Failure {

  param(
    [Parameter(Mandatory = $true)]
    [string]$Message
  )

  Write-Host "  [ERROR] $Message" -ForegroundColor Red
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
      "O tamanho da copia temporaria e diferente do arquivo original. " +
      "Original: $($sourceFile.Length) bytes. " +
      "Copia: $($temporaryFile.Length) bytes."
    )
  }

  # Abre o arquivo apenas para confirmar que ele pode ser lido.
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
try {

  Write-Section "VALIDACAO"

  Write-Info "SourceCode recebido: [$SourceCode]"
  Write-Info "PdfPath recebido: [$PdfPath]"
  Write-Info "PSCommandPath: [$PSCommandPath]"
  Write-Info "PSScriptRoot: [$PSScriptRoot]"

  if ([System.String]::IsNullOrWhiteSpace($SourceCode)) {
    throw "O codigo do item chegou vazio ao PowerShell."
  }

  if ([System.String]::IsNullOrWhiteSpace($PdfPath)) {
    throw "O caminho do PDF chegou vazio ao PowerShell."
  }

  $currentScriptPath = $PSCommandPath

  if ([System.String]::IsNullOrWhiteSpace($currentScriptPath)) {
    $currentScriptPath = $MyInvocation.MyCommand.Path
  }

  if ([System.String]::IsNullOrWhiteSpace($currentScriptPath)) {
    throw "Nao foi possivel determinar o caminho do script atual."
  }

  $projectRoot =
  [System.IO.Path]::GetDirectoryName($currentScriptPath)

  if ([System.String]::IsNullOrWhiteSpace($projectRoot)) {
    throw "Nao foi possivel determinar a pasta do projeto."
  }

  $teamcenterFunctionsPath =
  [System.IO.Path]::Combine(
    $projectRoot,
    "functions",
    "teamcenter_functions.ps1"
  )

  Write-Info "Pasta do projeto: [$projectRoot]"
  Write-Info "Funcoes Teamcenter: [$teamcenterFunctionsPath]"

  if (-not (
      Test-Path `
        -LiteralPath $teamcenterFunctionsPath `
        -PathType Leaf
    )) {

    throw "Arquivo de funcoes nao encontrado: $teamcenterFunctionsPath"
  }

  Write-Success "Arquivo de funcoes encontrado."

  if (-not (
      Test-Path `
        -LiteralPath $PdfPath `
        -PathType Leaf
    )) {

    throw "O PDF informado nao foi encontrado: $PdfPath"
  }

  $resolvedPdfPath =
  (Resolve-Path `
    -LiteralPath $PdfPath `
    -ErrorAction Stop
  ).ProviderPath

  if ([System.String]::IsNullOrWhiteSpace($resolvedPdfPath)) {
    throw "O caminho resolvido do PDF ficou vazio."
  }

  Write-Success "PDF encontrado."
  Write-Info "PDF resolvido: [$resolvedPdfPath]"

  . $teamcenterFunctionsPath

  Write-Success "Funcoes do Teamcenter carregadas."

  Write-Section "CONFIRMACAO"

  Write-Host ""
  Write-Host "Este processo vai criar um item REAL no Teamcenter." `
    -ForegroundColor Yellow

  Write-Host "O PDF sera importado na revisao do item criado." `
    -ForegroundColor Yellow

  Write-Host ""

  $confirmation =
  Read-Host "Digite SIM para continuar"

  if ($confirmation -ine "SIM") {

    Write-Host ""
    Write-Host "Operacao cancelada. Nenhum item foi criado." `
      -ForegroundColor Yellow

    exit 0
  }

  Write-Section "TEAMCENTER CONNECTION"

  $null =
  Connect-Teamcenter

  Write-Success "Conexao estabelecida."

  Write-Section "ITEM CREATION"

  Write-Info "Codigo solicitado: $SourceCode"
  Write-Info "Tipo do item: $itemType"
  Write-Info "Empresa: $companyCode"

  $teamcenterDestination =
  New-NextTeamcenterItem `
    -SourceCode $SourceCode `
    -CompanyCode $companyCode `
    -ItemType $itemType

  if (
    $null -eq $teamcenterDestination -or
    $null -eq $teamcenterDestination.Item
  ) {
    throw "A criacao nao retornou um item valido."
  }

  $createdCode =
  $teamcenterDestination.Code

  Write-Success "Item criado: $createdCode"

  if (
    $null -eq $teamcenterDestination -or
    $null -eq $teamcenterDestination.Item
  ) {
    throw "A criacao do item DCA nao retornou um item valido."
  }

  $createdCode =
  $teamcenterDestination.Code

  Write-Success "Novo item DCA criado: $createdCode"

  Write-Section "ITEM REVISION"

  $teamcenterRevision =
  $teamcenterDestination.Revision

  if ($null -eq $teamcenterRevision) {

    $teamcenterRevision =
    Get-TeamcenterRevision `
      -Item $teamcenterDestination.Item
  }

  Write-Section "PDF PREPARATION"

  $temporaryPdfPath =
  Copy-PdfToTemporaryFolder `
    -SourcePdfPath $resolvedPdfPath `
    -ItemCode $createdCode

  Write-Section "PDF IMPORT"

  Write-Info "Importando a copia local."
  Write-Info "Arquivo: $temporaryPdfPath"

  $importResult =
  Import-TeamcenterPdf `
    -Revision $teamcenterRevision `
    -ItemCode $createdCode `
    -FilePath $temporaryPdfPath

  Write-Host ""

  if ($null -eq $importResult) {

    Write-Host `
      "  [WARNING] ImportarPDF retornou NULL." `
      -ForegroundColor Yellow
  }
  else {

    Write-Info "Tipo do retorno: $($importResult.GetType().FullName)"
    Write-Info "Retorno do ImportarPDF: $importResult"
  }

  Write-Section "RESULTADO"
  Write-Success "Novo item criado com PDF: $createdCode"
  Write-Info "PDF: $resolvedPdfPath"

  exit 0
}
catch {

  Write-Host ""
  Write-Failure $_.Exception.Message

  Write-Info "Linha do erro: $($_.InvocationInfo.ScriptLineNumber)"
  Write-Info "Comando: $($_.InvocationInfo.Line.Trim())"

  Write-Host ""
  Write-Host "[ERRO COMPLETO]" -ForegroundColor DarkGray
  Write-Host $_.Exception.ToString() -ForegroundColor DarkGray
  Write-Host ""

  if (-not [System.String]::IsNullOrWhiteSpace($createdCode)) {

    Write-Host (
      "  [ATENCAO] O item '$createdCode' pode ter sido criado, " +
      "mesmo que a importacao do PDF tenha falhado."
    ) -ForegroundColor Yellow
  }

  exit 1
}
