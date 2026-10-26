# ============================================================
# INTERPRETACAO DA ENTRADA DE PESQUISA
# ============================================================
#
# Este arquivo interpreta os termos de pesquisa informados pelo
# usuario antes da consulta dos documentos.
#
# Responsabilidades:
#   1. separar varios termos informados por virgula;
#   2. remover termos repetidos;
#   3. identificar pesquisas por codigo;
#   4. identificar pesquisas por pasta;
#   5. diferenciar importacao completa de selecao dos documentos;
#   6. validar o nome completo da pasta;
#   7. bloquear curingas e caminhos relativos em pesquisas de pasta.
#
# Modos reconhecidos:
#   \NomeCompleto
#     Pesquisa a pasta e retorna seus documentos.
#
#   \\NomeCompleto
#     Pesquisa a pasta e abre a selecao dos documentos.
# ============================================================
function Get-DcaSearchCodeList {

  # Separa os termos informados por virgula e remove repeticoes
  # sem diferenciar letras maiusculas e minusculas.
  param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$InputText
  )

  # ============================================================
  # 1. PREPARAR A LISTA DE TERMOS
  # ============================================================
  #
  # A lista preserva os termos validos na ordem informada pelo
  # usuario. O HashSet permite identificar termos repetidos sem
  # diferenciar letras maiusculas e minusculas.
  $codes =
  [System.Collections.Generic.List[string]]::new()

  $knownCodes =
  [System.Collections.Generic.HashSet[string]]::new(
    [System.StringComparer]::OrdinalIgnoreCase
  )

  # ============================================================
  # 2. SEPARAR E NORMALIZAR OS TERMOS
  # ============================================================
  #
  # Cada valor separado por virgula e tratado como uma pesquisa
  # independente. Espacos nas extremidades e valores vazios sao
  # removidos antes da inclusao no lote.
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

    # O HashSet impede que o mesmo termo seja pesquisado mais de
    # uma vez no lote. A primeira ocorrencia permanece na lista.
    if ($knownCodes.Add($currentCode)) {

      $codes.Add($currentCode)
    }
  }

  # ============================================================
  # 3. VALIDAR E RETORNAR OS TERMOS
  # ============================================================
  #
  # Depois da remocao dos valores vazios e repetidos, pelo menos
  # um termo valido deve permanecer para iniciar a pesquisa.
  if ($codes.Count -eq 0) {

    throw "Nenhum codigo valido foi informado."
  }

  # Converte a lista interna em um array utilizado pelo fluxo
  # principal para processar cada pesquisa separadamente.
  return $codes.ToArray()
}

function Get-DcaFolderSearchMode {

  # Interpreta os prefixos usados na entrada:
  # uma barra pesquisa pastas;
  # duas barras pesquisam a pasta e abrem seus documentos.
  param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$SearchText
  )

  # ============================================================
  # 1. NORMALIZAR O TERMO DE PESQUISA
  # ============================================================
  #
  # Remove espacos das extremidades antes de verificar os
  # prefixos que identificam cada modo de pesquisa.
  $normalizedSearch =
  $SearchText.Trim()

  # ============================================================
  # 2. IDENTIFICAR A PESQUISA COM SELECAO
  # ============================================================
  #
  # Duas barras indicam que a pasta deve ser localizada e seus
  # documentos apresentados para selecao manual.
  #
  # Sao aceitas barras invertidas ou barras comuns para facilitar
  # a entrada no console.
  if (
    $normalizedSearch.StartsWith("\\") -or
    $normalizedSearch.StartsWith("//")
  ) {

    # Remove as duas barras iniciais e preserva apenas o nome que
    # sera validado posteriormente como nome completo da pasta.
    return [PSCustomObject]@{
      IsFolderSearch = $true
      ListFolderItems = $true
      SearchText = $normalizedSearch.Substring(2).Trim()
    }
  }

  # ============================================================
  # 3. IDENTIFICAR A IMPORTACAO COMPLETA DA PASTA
  # ============================================================
  #
  # Uma barra indica que a pasta deve ser localizada e todos os
  # documentos validos devem ser retornados sem selecao manual.
  if (
    $normalizedSearch.StartsWith("\") -or
    $normalizedSearch.StartsWith("/")
  ) {

    # Remove a barra inicial e preserva o nome que sera utilizado
    # para localizar exatamente a pasta solicitada.
    return [PSCustomObject]@{
      IsFolderSearch = $true
      ListFolderItems = $false
      SearchText = $normalizedSearch.Substring(1).Trim()
    }
  }

  # ============================================================
  # 4. MANTER A PESQUISA POR CODIGO
  # ============================================================
  #
  # Quando nenhum prefixo de pasta estiver presente, o texto sera
  # tratado normalmente como codigo ou parte do nome de um PDF.
  return [PSCustomObject]@{
    IsFolderSearch = $false
    ListFolderItems = $false
    SearchText = $normalizedSearch
  }
}

function Test-DcaFolderSearch {

  # Retorna apenas se o texto representa uma pesquisa por pasta.
  param(
    [string]$SearchText
  )

  # ============================================================
  # 1. VALIDAR O TEXTO RECEBIDO
  # ============================================================
  #
  # Um valor vazio nao representa uma pesquisa por pasta.
  if (
    [string]::IsNullOrWhiteSpace(
      $SearchText
    )
  ) {
    return $false
  }

  # ============================================================
  # 2. IDENTIFICAR O TIPO DE PESQUISA
  # ============================================================
  #
  # Reutiliza a interpretacao centralizada para evitar regras
  # diferentes entre a validacao e o fluxo principal.
  $folderSearchMode =
  Get-DcaFolderSearchMode `
    -SearchText $SearchText

  # Retorna somente a informacao necessaria para indicar se o
  # termo recebido representa uma pesquisa por pasta.
  return [bool]$folderSearchMode.IsFolderSearch
}

function Get-DcaFolderSearchPattern {

  # Remove o prefixo do modo de pesquisa e valida o nome completo
  # da pasta antes de iniciar a busca.
  param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$SearchText
  )

  # ============================================================
  # 1. INTERPRETAR O MODO DE PESQUISA
  # ============================================================
  #
  # Identifica o prefixo utilizado e recupera o texto restante
  # antes de validar o nome completo da pasta.
  $folderSearchMode =
  Get-DcaFolderSearchMode `
    -SearchText $SearchText

  # Esta funcao deve ser utilizada somente para termos que tenham
  # sido identificados anteriormente como pesquisa por pasta.
  if (-not $folderSearchMode.IsFolderSearch) {

    throw (
      "A pesquisa informada nao e uma pesquisa de pasta: " +
      "'$SearchText'."
    )
  }

  # ============================================================
  # 2. PREPARAR O NOME DA PASTA
  # ============================================================
  #
  # Recupera somente o texto posterior ao prefixo identificado e
  # remove espacos adicionais das extremidades.
  $folderName =
  ([string]$folderSearchMode.SearchText).Trim()

  # Remove barras adicionais que tenham permanecido no inicio da
  # entrada. Isso evita que o nome seja tratado como caminho
  # absoluto durante a pesquisa.
  $folderName =
  $folderName.TrimStart(
    [char]'\',
    [char]'/'
  ).Trim()

  # ============================================================
  # 3. VALIDAR O NOME COMPLETO DA PASTA
  # ============================================================
  #
  # Depois da remocao dos prefixos, o nome da pasta deve possuir
  # algum conteúdo utilizavel.
  if (
    [string]::IsNullOrWhiteSpace(
      $folderName
    )
  ) {

    throw "O nome completo da pasta ficou vazio."
  }

  # A pesquisa por pasta exige correspondencia exata. Curingas
  # poderiam localizar pastas diferentes da solicitada e por isso
  # nao sao permitidos nesse modo.
  if (
    $folderName.Contains("*") -or
    $folderName.Contains("?")
  ) {

    throw (
      "A pesquisa de pasta nao aceita curingas. " +
      "Digite o nome completo da pasta."
    )
  }

  # ============================================================
  # 4. BLOQUEAR CAMINHOS INSEGUROS OU INVALIDOS
  # ============================================================
  #
  # Impede navegacao relativa com "..", evitando que a pesquisa
  # tente sair da estrutura permitida de Documentacao.
  if ($folderName.Contains("..")) {

    throw (
      "O nome da pasta nao pode conter '..': " +
      "'$folderName'."
    )
  }

  # Bloqueia caracteres que nao podem fazer parte de um nome de
  # pasta valido no caminho utilizado pela pesquisa.
  if (
    $folderName -match
    '[:"<>\|]'
  ) {

    throw (
      "O nome da pasta possui caracteres invalidos: " +
      "'$folderName'."
    )
  }

    # ============================================================
  # 5. RETORNAR O NOME NORMALIZADO
  # ============================================================
  #
  # Converte barras comuns em barras invertidas para manter um
  # formato unico durante a localizacao da pasta.
  return $folderName.Replace(
    "/",
    "\"
  )
}
