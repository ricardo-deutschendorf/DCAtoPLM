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

# ============================================================
# PESQUISA DE PDFS PELO INDICE DO VAULT
# ============================================================
function Search-DcaVaultPdfEntries {

  # Pesquisa PDFs no indice do Vault.
  #
  # Quando StartFolderPath estiver preenchido, a pesquisa sera
  # iniciada nessa pasta. Dependendo da versao da EdmLib, a API
  # pode incluir resultados localizados em subpastas.
  param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNull()]
    $Vault,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$SearchText,

    [string]$StartFolderPath
  )

  # ============================================================
  # 1. NORMALIZAR O TEXTO DA PESQUISA
  # ============================================================

  $searchTextClean =
  $SearchText.Trim()

  if (
    [string]::IsNullOrWhiteSpace(
      $searchTextClean
    )
  ) {

    throw (
      "O texto da pesquisa no Vault ficou vazio."
    )
  }

  # A API do PDM utiliza os curingas SQL:
  #
  #   % = zero ou mais caracteres;
  #   _ = exatamente um caractere.
  #
  # O fluxo do DCAtoPLM utiliza:
  #
  #   * = zero ou mais caracteres;
  #   ? = exatamente um caractere.
  $likePattern =
  $searchTextClean.Replace(
    "*",
    "%"
  ).Replace(
  "?",
  "_"
)

# Quando nenhum curinga for informado, realiza uma pesquisa
# parcial pelo texto recebido.
if ($likePattern -notmatch "[%_]") {

  $likePattern =
  "%$likePattern%"
}

# ============================================================
# 2. CRIAR O OBJETO DE PESQUISA
# ============================================================

$search =
$Vault.CreateSearch()

if ($null -eq $search) {

  throw (
    "A API do PDM nao retornou um objeto de pesquisa."
  )
}

$search.FileName =
$likePattern

# Impede que versoes historicas dos arquivos sejam retornadas.
$search.FindHistoricStates =
$false

# ============================================================
# 3. LIMITAR A PESQUISA A UMA PASTA
# ============================================================

$startFolderPathClean =
([string]$StartFolderPath).Trim()

if (
  -not [string]::IsNullOrWhiteSpace(
    $startFolderPathClean
  )
) {

  $startFolder =
  $Vault.GetFolderFromPath(
    $startFolderPathClean
  )

  if ($null -eq $startFolder) {

    throw (
      "A pasta nao foi encontrada pela API do PDM: " +
      "'$startFolderPathClean'."
    )
  }

  $search.StartFolderID =
  [int]$startFolder.ID
}

# ============================================================
# 4. COLETAR OS RESULTADOS
# ============================================================

$entries =
[System.Collections.Generic.List[object]]::new()

$currentResult =
$search.GetFirstResult()

while ($null -ne $currentResult) {

  $resultName =
  ([string]$currentResult.Name).Trim()

  $resultFullName =
  ([string]$currentResult.Path).Trim()

  $isPdf =
  (
    -not [string]::IsNullOrWhiteSpace(
      $resultName
    ) -and
    $resultName.EndsWith(
      ".pdf",
      [System.StringComparison]::OrdinalIgnoreCase
    )
  )

  if (
    $isPdf -and
    -not [string]::IsNullOrWhiteSpace(
      $resultFullName
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
        FullName = $resultFullName
        FromVault = $true
      }
    )
  }
  elseif (
    $isPdf -and
    $Details
  ) {

    Write-Host (
      "  Resultado do Vault ignorado por nao possuir caminho: " +
      "'$resultName'."
    ) -ForegroundColor DarkGray
  }

  $currentResult =
  $search.GetNextResult()
}

# ============================================================
# 5. RETORNAR OS PDFS ENCONTRADOS
# ============================================================

return $entries.ToArray()
}

# ============================================================
# PESQUISA DE PDFS NO SISTEMA DE ARQUIVOS
# ============================================================
function Get-DcaDiskPdfEntries {

  # Pesquisa recursivamente os PDFs existentes no sistema de
  # arquivos.
  #
  # Esta funcao e utilizada quando a API do PDM estiver
  # indisponivel ou quando o chamador escolher o modo local.
  param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$FolderPath
  )

  # ============================================================
  # 1. NORMALIZAR E VALIDAR A PASTA
  # ============================================================

  $folderPathClean =
  $FolderPath.Trim()

  if (
    [string]::IsNullOrWhiteSpace(
      $folderPathClean
    )
  ) {

    throw (
      "O caminho da pesquisa local ficou vazio."
    )
  }

  if (-not (
      Test-Path `
        -LiteralPath $folderPathClean `
        -PathType Container
    )) {

    throw (
      "A pasta de pesquisa local nao foi encontrada: " +
      "'$folderPathClean'."
    )
  }

  # ============================================================
  # 2. COLETAR OS PDFS DISPONIVEIS NO DISCO
  # ============================================================

  $entries =
  [System.Collections.Generic.List[object]]::new()

  # A pesquisa e recursiva porque esta funcao tambem e utilizada
  # pela pesquisa geral por codigo.
  #
  # A leitura somente da pasta atual e realizada pelo modulo
  # especifico de navegacao por pastas.
  $pdfFiles =
  @(
    Get-ChildItem `
      -LiteralPath $folderPathClean `
      -Filter "*.pdf" `
      -File `
      -Recurse `
      -Force `
      -ErrorAction SilentlyContinue |
      Sort-Object FullName
  )

  foreach ($pdfFile in $pdfFiles) {

    if ($null -eq $pdfFile) {
      continue
    }

    $pdfFullName =
    ([string]$pdfFile.FullName).Trim()

    if (
      [string]::IsNullOrWhiteSpace(
        $pdfFullName
      )
    ) {

      continue
    }

    $baseName =
    [System.IO.Path]::GetFileNameWithoutExtension(
      $pdfFile.Name
    )

    # Mantem a mesma estrutura utilizada pelos resultados da API.
    $entries.Add(
      [PSCustomObject]@{
        Name = [string]$pdfFile.Name
        BaseName = ([string]$baseName).Trim()
        FullName = $pdfFullName
        FromVault = $false
      }
    )
  }

  # ============================================================
  # 3. RETORNAR OS PDFS ENCONTRADOS
  # ============================================================

  return $entries.ToArray()
}

# ============================================================
# DISPONIBILIZACAO LOCAL DO PDF
# ============================================================
function Confirm-DcaLocalPdf {

  # Garante que o PDF esteja disponivel localmente.
  #
  # Quando o arquivo ja existir no cache ou no disco, retorna seu
  # caminho imediatamente.
  #
  # Quando o resultado veio do Vault e ainda nao estiver
  # disponivel localmente, solicita uma copia ao PDM.
  param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNull()]
    $Entry
  )

  # ============================================================
  # 1. VALIDAR A ENTRADA
  # ============================================================

  $entryPath =
  ([string]$Entry.FullName).Trim()

  if (
    [string]::IsNullOrWhiteSpace(
      $entryPath
    )
  ) {

    throw (
      "A entrada do PDF nao possui um caminho completo."
    )
  }

  if (
    [System.IO.Path]::GetExtension(
      $entryPath
    ) -ine ".pdf"
  ) {

    throw (
      "O arquivo informado nao possui extensao PDF: " +
      "'$entryPath'."
    )
  }

  # ============================================================
  # 2. RETORNAR O ARQUIVO JA DISPONIVEL
  # ============================================================

  if (
    Test-Path `
      -LiteralPath $entryPath `
      -PathType Leaf
  ) {

    $localFile =
    Get-Item `
      -LiteralPath $entryPath `
      -ErrorAction Stop

    if ($localFile.Length -le 0) {

      throw (
        "O PDF encontrado no disco esta vazio: " +
        "'$entryPath'."
      )
    }

    return $localFile.FullName
  }

  # ============================================================
  # 3. VALIDAR A ORIGEM DO ARQUIVO
  # ============================================================

  $vault =
  $script:DcaVault

  $entryFromVault =
  $false

  if ($Entry.PSObject.Properties["FromVault"]) {

    $entryFromVault =
    [bool]$Entry.FromVault
  }

  if (
    -not $entryFromVault -or
    $null -eq $vault
  ) {

    throw (
      "PDF nao encontrado no disco: '$entryPath'."
    )
  }

  # ============================================================
  # 4. LOCALIZAR O ARQUIVO NO VAULT
  # ============================================================

  Write-Info (
    "Baixando o PDF do vault..."
  )

  [object]$parentFolder =
  $null

  $pdmFile =
  $vault.GetFileFromPath(
    $entryPath,
    [ref]$parentFolder
  )

  if ($null -eq $pdmFile) {

    throw (
      "Nao foi possivel obter o arquivo no vault: " +
      "'$entryPath'."
    )
  }

  if ($null -eq $parentFolder) {

    throw (
      "Nao foi possivel obter a pasta do arquivo no vault: " +
      "'$entryPath'."
    )
  }

  # ============================================================
  # 5. SOLICITAR UMA COPIA LOCAL
  # ============================================================

  [int]$fileVersion =
  0

  [int]$folderId =
  [int]$parentFolder.ID

  try {

    if ($Details) {

      Write-Host (
        "  Preparando download pelo PDM:"
      ) -ForegroundColor Cyan

      Write-Host (
        "    Arquivo:     '$entryPath'"
      ) -ForegroundColor DarkGray

      Write-Host (
        "    Pasta ID:    '$folderId'"
      ) -ForegroundColor DarkGray

      Write-Host (
        "    Versao:      '$fileVersion'"
      ) -ForegroundColor DarkGray

      Write-Host (
        "    Tipo arquivo: " +
        $pdmFile.GetType().FullName
      ) -ForegroundColor DarkGray

      Write-Host (
        "    Tipo pasta:   " +
        $parentFolder.GetType().FullName
      ) -ForegroundColor DarkGray
    }

    $null =
    $pdmFile.GetFileCopy(
      0,
      [ref]$fileVersion,
      [ref]$folderId,
      0,
      ""
    )
  }
  catch {

    $realException =
    $_.Exception

    while (
      $null -ne $realException.InnerException
    ) {

      $realException =
      $realException.InnerException
    }

    throw (
      "Nao foi possivel disponibilizar o PDF no cache local. " +
      "Arquivo: '$entryPath'. " +
      "FileVersion: '$fileVersion'. " +
      "FolderID: '$folderId'. " +
      "Detalhe: " +
      $realException.Message
    )
  }

  # ============================================================
  # 6. VALIDAR O ARQUIVO DISPONIBILIZADO
  # ============================================================

  $localCachePath =
  [string]$pdmFile.GetLocalPath(
    $parentFolder.ID
  )

  $localCachePath =
  $localCachePath.Trim()

  if (
    [string]::IsNullOrWhiteSpace(
      $localCachePath
    )
  ) {

    throw (
      "O Vault nao retornou o caminho do cache local para " +
      "'$entryPath'."
    )
  }

  if (-not (
      Test-Path `
        -LiteralPath $localCachePath `
        -PathType Leaf
    )) {

    throw (
      "O arquivo nao foi encontrado no cache local do PDM: " +
      "'$localCachePath'."
    )
  }

  if (
    [System.IO.Path]::GetExtension(
      $localCachePath
    ) -ine ".pdf"
  ) {

    throw (
      "O arquivo retornado pelo cache do PDM nao e um PDF: " +
      "'$localCachePath'."
    )
  }

  $localCacheFile =
  Get-Item `
    -LiteralPath $localCachePath `
    -ErrorAction Stop

  if ($localCacheFile.Length -le 0) {

    throw (
      "O PDF disponibilizado no cache do PDM esta vazio: " +
      "'$localCachePath'."
    )
  }

  # ============================================================
  # 7. RETORNAR O CAMINHO LOCAL VALIDADO
  # ============================================================

  return $localCacheFile.FullName
}
