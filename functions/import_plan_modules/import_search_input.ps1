# ============================================================
# INTERPRETACAO DA ENTRADA DE PESQUISA
# ============================================================
# Interpreta os termos digitados antes da consulta dos documentos.
#   1. separa varios termos por virgula;
#   2. identifica pesquisa por codigo ou por pasta;
#   3. valida o nome completo da pasta (sem curingas nem "..").
#
# Modos reconhecidos:
#   \NomeCompleto   -> pesquisa a pasta e retorna seus documentos
#   \\NomeCompleto  -> pesquisa a pasta e abre a selecao dos itens
# ============================================================

function Get-DcaSearchCodeList {
    param([Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$InputText)

    $codes = [System.Collections.Generic.List[string]]::new()
    $knownFolders = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

    foreach ($part in ($InputText -split ",")) {
        $term = ([string]$part).Trim()
        if (-not $term) { continue }

        # Pastas (\ ou /) nao se repetem. Codigos repetidos sao mantidos:
        # cada repeticao gera uma nova pesquisa, que mostra o que foi escolhido antes.
        if ($term -match '^[\\/]' -and -not $knownFolders.Add($term)) { continue }

        $codes.Add($term)
    }

    if ($codes.Count -eq 0) { throw "Nenhum codigo valido foi informado." }

    return $codes.ToArray()
}

function Get-DcaFolderSearchMode {
    param([Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$SearchText)

    $text = $SearchText.Trim()

    # Tamanho do prefixo: 2 = selecao manual, 1 = importacao completa, 0 = codigo.
    $prefixLength =
        if     ($text -match '^(\\\\|//)') { 2 }
        elseif ($text -match '^[\\/]')     { 1 }
        else                               { 0 }

    return [PSCustomObject]@{
        IsFolderSearch  = $prefixLength -gt 0
        ListFolderItems = $prefixLength -eq 2
        SearchText      = $text.Substring($prefixLength).Trim()
    }
}

function Test-DcaFolderSearch {
    param([string]$SearchText)

    if ([string]::IsNullOrWhiteSpace($SearchText)) { return $false }

    return [bool]((Get-DcaFolderSearchMode -SearchText $SearchText).IsFolderSearch)
}

function Get-DcaFolderSearchPattern {
    param([Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$SearchText)

    $mode = Get-DcaFolderSearchMode -SearchText $SearchText
    if (-not $mode.IsFolderSearch) { throw "A pesquisa informada nao e uma pesquisa de pasta: '$SearchText'." }

    # Remove barras extras no inicio para o nome nao ser tratado como caminho absoluto.
    $folderName = (([string]$mode.SearchText).Trim() -replace '^[\\/]+', '').Trim()

    if (-not $folderName)                { throw "O nome completo da pasta ficou vazio." }
    if ($folderName -match '[*?]')       { throw "A pesquisa de pasta nao aceita curingas. Digite o nome completo da pasta." }
    if ($folderName.Contains(".."))      { throw "O nome da pasta nao pode conter '..': '$folderName'." }
    if ($folderName -match '[:"<>\|]')   { throw "O nome da pasta possui caracteres invalidos: '$folderName'." }

    # Formato unico: barras invertidas.
    return $folderName.Replace("/", "\")
}