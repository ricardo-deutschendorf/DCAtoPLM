# ============================================================
# PESQUISA E DISPONIBILIZACAO DOS PDFS
# ============================================================
#
# Este arquivo localiza e disponibiliza os PDFs utilizados pelo
# lote de importacao.
#
# Responsabilidades:
#   1. pesquisar PDFs pelo indice do Vault;
#   2. pesquisar PDFs no sistema de arquivos;
#   3. limitar pesquisas a uma pasta quando solicitado;
#   4. solicitar uma copia local para arquivos do Vault;
#   5. validar o caminho local antes da importacao.
#
# A pesquisa pelo Vault possui prioridade. A pesquisa em disco
# permanece disponivel como alternativa.
# ============================================================
function Search-DcaVaultPdfEntries {

  # Pesquisa PDFs no indice do Vault. Quando uma pasta inicial
  # for informada, limita a consulta a essa parte do Vault.
  param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNull()]
    $Vault,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$SearchText,

    [string]$StartFolderPath
  )

  # A API do PDM utiliza os curingas SQL "%" e "_", enquanto a
  # interface do script aceita os curingas "*" e "?".
  $likePattern =
  $SearchText.Replace(
    "*",
    "%"
  ).Replace(
  "?",
  "_"
)

if ($likePattern -notmatch "[%_]") {

  $likePattern =
  "%$likePattern%"
}

$search =
$Vault.CreateSearch()

if ($null -eq $search) {

  throw (
    "A API do PDM nao retornou um objeto de pesquisa."
  )
}

$search.FileName =
$likePattern

$search.FindHistoricStates =
$false

# Limita a consulta a pasta informada. Sem esse filtro, a API
# pesquisa os arquivos a partir da raiz do Vault.
if (
  -not [string]::IsNullOrWhiteSpace(
    $StartFolderPath
  )
) {

  $startFolder =
  $Vault.GetFolderFromPath(
    $StartFolderPath
  )

  if ($null -eq $startFolder) {

    throw (
      "A pasta nao foi encontrada pela API do PDM: " +
      "'$StartFolderPath'."
    )
  }

  $search.StartFolderID =
  [int]$startFolder.ID
}

$entries =
[System.Collections.Generic.List[object]]::new()

$currentResult =
$search.GetFirstResult()

while ($null -ne $currentResult) {

  $resultName =
  [string]$currentResult.Name

  if (
    -not [string]::IsNullOrWhiteSpace(
      $resultName
    ) -and
    $resultName.EndsWith(
      ".pdf",
      [System.StringComparison]::OrdinalIgnoreCase
    )
  ) {

    $baseName =
    [System.IO.Path]::GetFileNameWithoutExtension(
      $resultName
    )

    $entries.Add(
      [PSCustomObject]@{
        Name = $resultName
        BaseName = ([string]$baseName).Trim()
        FullName = [string]$currentResult.Path
        FromVault = $true
      }
    )
  }

  $currentResult =
  $search.GetNextResult()
}

return $entries.ToArray()
}
function Get-DcaDiskPdfEntries {

  # Alternativa utilizada quando a API do PDM esta indisponivel.
  # Retorna somente os PDFs existentes no cache ou no disco local.
  param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$FolderPath
  )

  if (-not (
      Test-Path `
        -LiteralPath $FolderPath `
        -PathType Container
    )) {

    throw (
      "A pasta de pesquisa local nao foi encontrada: " +
      "'$FolderPath'."
    )
  }

  $entries =
  [System.Collections.Generic.List[object]]::new()

  $pdfFiles =
  @(
    Get-ChildItem `
      -LiteralPath $FolderPath `
      -Filter "*.pdf" `
      -File `
      -Recurse `
      -Force `
      -ErrorAction SilentlyContinue
  )

  foreach ($pdfFile in $pdfFiles) {

    $baseName =
    [System.IO.Path]::GetFileNameWithoutExtension(
      $pdfFile.Name
    )

    $entries.Add(
      [PSCustomObject]@{
        Name = $pdfFile.Name
        BaseName = ([string]$baseName).Trim()
        FullName = $pdfFile.FullName
        FromVault = $false
      }
    )
  }

  return $entries.ToArray()
}
function Confirm-DcaLocalPdf {

  # Garante que o PDF esteja disponivel localmente. Quando o
  # resultado veio do Vault e ainda nao esta no cache, solicita
  # uma copia local antes da importacao no Teamcenter.
  param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNull()]
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
