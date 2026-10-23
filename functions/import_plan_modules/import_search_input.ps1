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

    # O HashSet impede que o mesmo termo seja pesquisado mais de
    # uma vez no mesmo lote.
    if ($knownCodes.Add($currentCode)) {

      $codes.Add($currentCode)
    }
  }

  if ($codes.Count -eq 0) {

    throw "Nenhum codigo valido foi informado."
  }

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

  $normalizedSearch =
  $SearchText.Trim()

  if (
    $normalizedSearch.StartsWith("\\") -or
    $normalizedSearch.StartsWith("//")
  ) {

    return [PSCustomObject]@{
      IsFolderSearch = $true
      ListFolderItems = $true
      SearchText = $normalizedSearch.Substring(2).Trim()
    }
  }

  if (
    $normalizedSearch.StartsWith("\") -or
    $normalizedSearch.StartsWith("/")
  ) {

    return [PSCustomObject]@{
      IsFolderSearch = $true
      ListFolderItems = $false
      SearchText = $normalizedSearch.Substring(1).Trim()
    }
  }

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

  if (
    [string]::IsNullOrWhiteSpace(
      $SearchText
    )
  ) {
    return $false
  }

  $folderSearchMode =
  Get-DcaFolderSearchMode `
    -SearchText $SearchText

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

  $folderSearchMode =
  Get-DcaFolderSearchMode `
    -SearchText $SearchText

  if (-not $folderSearchMode.IsFolderSearch) {

    throw (
      "A pesquisa informada nao e uma pesquisa de pasta: " +
      "'$SearchText'."
    )
  }

  $folderName =
  ([string]$folderSearchMode.SearchText).Trim()

  # Remove barras que tenham permanecido no inicio da entrada.
  $folderName =
  $folderName.TrimStart(
    [char]'\',
    [char]'/'
  ).Trim()

  if (
    [string]::IsNullOrWhiteSpace(
      $folderName
    )
  ) {

    throw "O nome completo da pasta ficou vazio."
  }

  # A pesquisa de pastas exige o nome completo e nao aceita
  # curingas ou correspondencias parciais.
  if (
    $folderName.Contains("*") -or
    $folderName.Contains("?")
  ) {

    throw (
      "A pesquisa de pasta nao aceita curingas. " +
      "Digite o nome completo da pasta."
    )
  }

  # Impede navegacao relativa para fora da raiz Documentacao.
  if ($folderName.Contains("..")) {

    throw (
      "O nome da pasta nao pode conter '..': " +
      "'$folderName'."
    )
  }

  if (
    $folderName -match
    '[:"<>\|]'
  ) {

    throw (
      "O nome da pasta possui caracteres invalidos: " +
      "'$folderName'."
    )
  }

  return $folderName.Replace(
    "/",
    "\"
  )
}