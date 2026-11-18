# ============================================================
# SELECAO DOS DOCUMENTOS DE UMA PASTA
# ============================================================
# Apresenta os documentos ja preparados para uma pasta e permite
# selecionar os PDFs do lote.
#   1. ordena os documentos e apresenta codigo, nome, revisao e estado;
#   2. aceita: 1 | 1,3,5 | 1-5 | T | *  (e V para voltar, se AllowBack);
#   3. valida numeros e intervalos, sem repetir selecoes;
#   4. retorna os documentos selecionados.
# Com AllowBack, V devolve $null para a lista de pastas.
# Nenhum arquivo e alterado ou importado aqui.
# ============================================================

function Select-DcaDocumentsFromFolder {
    param(
        [Parameter(Mandatory)][ValidateNotNull()]$FolderOption,
        [switch]$AllowBack
    )

    # --- 1. Ordenar e validar os documentos ---
    if (-not $FolderOption.PSObject.Properties["Documents"]) { throw "A opcao de pasta nao possui a colecao Documents." }

    # Ordem previsivel entre execucoes: codigo e depois nome fisico do PDF.
    $documents = @($FolderOption.Documents | Sort-Object { [string]$_.SourceCode }, { [string]$_.File.Name })

    if (@($documents | Where-Object { $null -eq $_ -or $null -eq $_.File }).Count -gt 0) {
        throw "Foi encontrado um documento sem arquivo fisico na pasta '$($FolderOption.RelativePath)'."
    }

    # Pasta sem PDFs nao abre a tela de selecao.
    if ($documents.Count -eq 0) {
        Write-Warn "A pasta '$($FolderOption.RelativePath)' nao possui PDFs."
        if ($AllowBack) { return $null }
        return @()
    }

    # A cor so destaca o estado; a decisao sobre workflow fica no fluxo principal.
    $stateColors = @{
        "Aprovado" = "Green"; "Obsoleto" = "Red"; "Verificado" = "Cyan"; "Corrigir" = "Magenta"
        "Em verificacao" = "DarkCyan"; "Em verificação" = "DarkCyan"
        "Em elaboracao"  = "DarkYellow"; "Em elaboração" = "DarkYellow"
        "Em revisao"     = "Blue"; "Em revisão" = "Blue"
    }

    # --- 2. Apresentar e validar a selecao (repete ate selecionar ou voltar) ---
    while ($true) {
        Write-AnimatedLine ""
        Write-Host "  Pasta selecionada: \$($FolderOption.RelativePath)" -ForegroundColor Cyan
        Write-Host "  Tipo: $($FolderOption.DisplayName)" -ForegroundColor Gray
        Write-Host "  Documentos encontrados: $($documents.Count)" -ForegroundColor Gray
        Write-Host ("  " + ("-" * 72)) -ForegroundColor DarkGray

        for ($i = 0; $i -lt $documents.Count; $i++) {
            $document = $documents[$i]

            # Texto alternativo evita linhas vazias na listagem.
            $code = [string]$document.SourceCode
            if ([string]::IsNullOrWhiteSpace($code)) { $code = [string]$document.File.BaseName }
            $title = [string]$document.DocumentTitle
            if ([string]::IsNullOrWhiteSpace($title)) { $title = "sem titulo" }
            $revision = [string]$document.ClientRevision
            if ([string]::IsNullOrWhiteSpace($revision)) { $revision = "nao informada" }
            $state = [string]$document.PdmState
            if ([string]::IsNullOrWhiteSpace($state)) { $state = "nao informado" }
            $stateColor = if ($stateColors.ContainsKey($state)) { $stateColors[$state] } else { "Yellow" }

            Write-Host ("  [{0}] {1}" -f ($i + 1), $code) -ForegroundColor White
            Write-Host "       Nome:    $title" -ForegroundColor Gray
            Write-Host "       Revisao: $revision" -ForegroundColor Gray
            if ($Details) {
                $revisionSource = [string]$document.RevisionSource
                if ([string]::IsNullOrWhiteSpace($revisionSource)) { $revisionSource = "nome do arquivo" }
                Write-Host "       Fonte:   $revisionSource" -ForegroundColor DarkGray
            }
            Write-Host "       Estado:  $state" -ForegroundColor $stateColor
            if ($Details) {
                Write-Host "       PDF:     $($document.File.Name)" -ForegroundColor DarkGray
                Write-Host "       Local:   $($document.File.FullName)" -ForegroundColor DarkGray
            }
            Write-Host ""
        }

        Write-Host "  Selecione os documentos que deseja importar." -ForegroundColor Cyan
        Write-Host "  Exemplos: 1 | 1,3,5 | 1-5 | T | *" -ForegroundColor DarkGray
        if ($AllowBack) { Write-Host "  Digite V para voltar para a lista de pastas" -ForegroundColor DarkGray }

        # --- 3. Receber e interpretar a entrada ---
        $text = ([string](Read-Host "Digite os numeros dos documentos")).Trim()
        if ($text -eq "") { Write-Warn "Nenhum documento foi selecionado."; continue }

        if ($AllowBack -and ($text -ieq "V" -or $text -ieq "VOLTAR")) { return $null }   # chamador reapresenta as pastas

        # Numeros validos, na ordem lida e sem repeticao (ex.: 1,2,1-5).
        $selected = [System.Collections.Generic.List[int]]::new()
        $valid = $true

        if ($text -ieq "T" -or $text -ieq "TODOS" -or $text -eq "*") { 1..$documents.Count | ForEach-Object { $selected.Add($_) } }
        else {
            foreach ($part in ($text -split ",")) {
                $part = ([string]$part).Trim()

                if ($part -eq "") { Write-Warn "Selecao invalida: existem valores vazios na entrada."; $valid = $false; break }

                if ($part -match '^(?<Start>\d+)\s*-\s*(?<End>\d+)$') {   # intervalo, ex.: 1-5
                    $a = [int]$Matches["Start"]; $b = [int]$Matches["End"]
                    if ($a -lt 1 -or $b -gt $documents.Count -or $a -gt $b) {
                        Write-Warn "Intervalo invalido: '$part'. Use valores entre 1 e $($documents.Count)."
                        $valid = $false; break
                    }
                    $a..$b | ForEach-Object { if (-not $selected.Contains($_)) { $selected.Add($_) } }
                    continue
                }

                $n = 0
                if (-not [int]::TryParse($part, [ref]$n) -or $n -lt 1 -or $n -gt $documents.Count) {
                    Write-Warn "Selecao invalida: '$part'. Digite numeros entre 1 e $($documents.Count)."
                    $valid = $false; break
                }
                if (-not $selected.Contains($n)) { $selected.Add($n) }
            }
        }
        if (-not $valid) { continue }
        if ($selected.Count -eq 0) { Write-Warn "Nenhum documento valido foi selecionado."; continue }

        # --- 4. Montar o retorno na mesma ordem apresentada ao usuario ---
        $selectedDocuments = [System.Collections.Generic.List[object]]::new()

        Write-AnimatedLine ""
        foreach ($n in ($selected | Sort-Object)) {
            $selectedDocuments.Add($documents[$n - 1])
            Write-Success "PDF selecionado [$n]: $($documents[$n - 1].File.Name)"
        }
        Write-AnimatedLine ""
        Write-Host "  Documentos selecionados: $($selectedDocuments.Count)" -ForegroundColor Cyan

        return $selectedDocuments.ToArray()
    }
}