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

  # ============================================================
  # 1. PREPARAR A PESQUISA NO INDICE DO VAULT
  # ============================================================
  #
  # Converte os curingas utilizados pelo script para o formato
  # aceito pela API do PDM e cria o objeto responsavel pela busca.
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
  # entrada do script aceita os curingas "*" e "?".
  #
  # Quando nenhum curinga estiver presente, o termo sera tratado
  # como uma pesquisa parcial.
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

# Cria o objeto de pesquisa utilizado para consultar o indice
# mantido pelo Vault.
$search =
$Vault.CreateSearch()

if ($null -eq $search) {

  throw (
    "A API do PDM nao retornou um objeto de pesquisa."
  )
}

# Define o nome pesquisado e desabilita a inclusao de versoes
# historicas nos resultados.
$search.FileName =
$likePattern

$search.FindHistoricStates =
$false

# ============================================================
# 2. LIMITAR A PESQUISA A UMA PASTA
# ============================================================
#
# Quando uma pasta inicial for informada, a consulta sera
# limitada a essa parte do Vault.
#
# Sem esse filtro, a API pesquisa a partir da raiz do Vault.
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

# ============================================================
# 3. COLETAR OS RESULTADOS DA PESQUISA
# ============================================================
#
# Percorre os resultados retornados pela API e mantem somente
# arquivos com extensao PDF.
$entries =
[System.Collections.Generic.List[object]]::new()

# A API retorna o primeiro resultado separadamente. Os demais
# resultados sao obtidos durante a repeticao abaixo.
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

    # Padroniza o resultado da API no mesmo formato utilizado
    # pelos arquivos encontrados diretamente no disco.
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

# Retorna um array vazio quando nenhum PDF for encontrado.
# Isso permite que o chamador diferencie uma pesquisa sem
# resultados de uma falha na API.
return $entries.ToArray()
}

function Get-DcaDiskPdfEntries {

  # ============================================================
  # 1. VALIDAR A PASTA DE PESQUISA LOCAL
  # ============================================================
  #
  # Confirma se a pasta existe antes de percorrer os arquivos
  # presentes no cache ou no sistema de arquivos.
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

  # ============================================================
  # 2. COLETAR OS PDFs DISPONIVEIS NO DISCO
  # ============================================================
  #
  # Pesquisa recursivamente os arquivos PDF existentes na pasta
  # atual e em todas as suas subpastas.
  $entries =
  [System.Collections.Generic.List[object]]::new()

  # Erros de acesso individuais sao ignorados para permitir que
  # a pesquisa continue nas demais pastas disponiveis.
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

    # Mantem a mesma estrutura utilizada pelos resultados da API.
    # FromVault indica que o arquivo ja foi localizado no disco.
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

  # ============================================================
  # 1. VERIFICAR SE O PDF JA ESTA DISPONIVEL
  # ============================================================
  #
  # Retorna imediatamente o caminho recebido quando o arquivo
  # ja estiver presente no cache ou no sistema de arquivos.
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

  # O download somente pode ser solicitado quando a entrada veio
  # do Vault e existe uma conexao ativa com o PDM.
  $vault = $script:DcaVault

  if (-not $Entry.FromVault -or $null -eq $vault) {
    throw "PDF nao encontrado no disco: '$($Entry.FullName)'."
  }

  # ============================================================
  # 2. SOLICITAR UMA COPIA LOCAL AO VAULT
  # ============================================================
  #
  # Localiza o objeto do arquivo e sua pasta no Vault antes de
  # solicitar que a versao correspondente seja copiada ao cache.
  Write-Info "Baixando o PDF do vault..."

  $parentFolder = $null

  # A API preenche parentFolder por referencia ao localizar o
  # arquivo correspondente ao caminho completo.
  $pdmFile = $vault.GetFileFromPath($Entry.FullName, [ref]$parentFolder)

  if ($null -eq $pdmFile) {
    throw "Nao foi possivel obter o arquivo no vault."
  }

  if ($null -eq $parentFolder) {
    throw "Nao foi possivel obter a pasta do arquivo no vault."
  }

  # A versao zero permite que a API determine a versao adequada.
  # O identificador da pasta informa em qual cache local a copia
  # deve ser disponibilizada.
  $fileVersion = 0
  $folderId = $parentFolder.ID

  $pdmFile.GetFileCopy(0, [ref]$fileVersion, [ref]$folderId, 0, "")

  # ============================================================
  # 3. VALIDAR O ARQUIVO DISPONIBILIZADO
  # ============================================================
  #
  # Depois da solicitacao da copia, consulta o caminho do cache
  # e confirma que o PDF realmente foi criado no disco.
  $localCachePath = $pdmFile.GetLocalPath($parentFolder.ID)

  if (-not (Test-Path -LiteralPath $localCachePath -PathType Leaf)) {
    throw "O arquivo nao foi encontrado no cache local do PDM: '$localCachePath'."
  }

  return $localCachePath
}
