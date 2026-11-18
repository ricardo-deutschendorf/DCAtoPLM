# ============================================================
# NAVEGACAO ENTRE PASTAS E DOCUMENTOS
# ============================================================
# Navega pelas subpastas de uma categoria DCA e seleciona os
# documentos que entram no lote.
#   1. abre subpastas (P1) e volta para a pasta anterior (V);
#   2. seleciona documentos: D1 | D1,D3 | D1-D5 | T | T-D2,D5;
#   3. sai sem selecionar (S), retornando um array vazio.
# Os documentos da pasta atual vem de Get-DcaDocumentsFromFolderPath.
# Nenhum arquivo e alterado ou importado aqui.
# ============================================================

function Select-DcaDocumentsWithFolderNavigation {
    param([Parameter(Mandatory)][ValidateNotNull()]$RootFolderOption)

    # --- 1. Inicializar a navegacao ---
    $vault = Get-DcaVault   # reutilizado em toda a navegacao; sem API, le do disco
    $navigationStack = [System.Collections.Generic.Stack[object]]::new()   # pastas anteriores (opcao V)
    $currentFolder = $RootFolderOption

    $rowFormat = "  {0,-7} {1,-44} {2,-9} {3,-15} {4}"
    $fit = { param([string]$text, $max) if ($text.Length -gt $max) { $text.Substring(0, $max - 3) + "..." } else { $text } }   # preserva o alinhamento
    $stateColors = @{   # cores apenas visuais; a decisao sobre workflows fica no fluxo principal
        "Aprovado" = "Green"; "Verificado" = "Cyan"; "Obsoleto" = "Red"; "Corrigir" = "Magenta"
        "Em verificacao" = "DarkCyan"; "Em verificação" = "DarkCyan"
        "Em elaboracao"  = "DarkYellow"; "Em elaboração" = "DarkYellow"
        "Em revisao"     = "Blue"; "Em revisão" = "Blue"
    }

    while ($true) {
        # --- 2. Carregar subpastas e documentos da pasta atual ---
        $childFolders = @(Get-ChildItem -LiteralPath $currentFolder.FullName -Directory -Force -ErrorAction SilentlyContinue | Sort-Object Name)

        $script:DcaLastFolderTiming = $null
        $documents = @(Get-DcaDocumentsFromFolderPath -FolderOption $currentFolder -Vault $vault -SuppressItemDetails)

        # --- 3. Apresentar a pasta atual ---
        Write-AnimatedLine ""
        Write-Host ("  Pasta atual: \{0}" -f $currentFolder.RelativePath) -ForegroundColor Cyan
        Write-Host ("  Tipo: {0}" -f $currentFolder.DisplayName) -ForegroundColor Gray
        Write-Host ("  Subpastas: {0} | Documentos: {1}" -f $childFolders.Count, $documents.Count) -ForegroundColor Gray

        if ($Details -and $null -ne $script:DcaLastFolderTiming) {
            $t = $script:DcaLastFolderTiming
            Write-Host ""
            Write-Host "  Tempo da pesquisa da pasta:" -ForegroundColor Cyan
            Write-Host ("    Pesquisa dos PDFs:          {0,8:N2} s" -f $t.SearchSeconds) -ForegroundColor DarkGray
            Write-Host ("    Leitura dos dados do PDM:  {0,8:N2} s" -f $t.PdmReadSeconds) -ForegroundColor DarkGray
            Write-Host ("    Total da pasta:            {0,8:N2} s" -f $t.TotalSeconds) -ForegroundColor Gray
            Write-Host ("    Documentos preparados:     {0,8}" -f $t.DocumentCount) -ForegroundColor DarkGray
            if ($t.DocumentCount -gt 0) { Write-Host ("    Media por documento PDM:  {0,8:N0} ms" -f $t.AverageMilliseconds) -ForegroundColor DarkGray }
        }
        Write-Host ("  " + ("-" * 72)) -ForegroundColor DarkGray

        # --- 4. Tabela de itens: subpastas (P) antes dos documentos (D) ---
        if ($childFolders.Count -gt 0 -or $documents.Count -gt 0) {
            $showDocumentLines = $Details -and $documents.Count -le 20   # titulo e arquivo so em listas curtas
            if ($Details -and -not $showDocumentLines) {
                Write-Host "  Detalhes adicionais ocultados para acelerar a listagem de $($documents.Count) documentos." -ForegroundColor DarkGray
                Write-Host ""
            }

            Write-Host "  Itens encontrados:" -ForegroundColor Cyan
            Write-Host ("  " + ("-" * 104)) -ForegroundColor DarkGray
            Write-Host ($rowFormat -f "Item", "Codigo", "Tipo", "Revisao", "Estado") -ForegroundColor White
            Write-Host ($rowFormat -f ("-" * 5), ("-" * 42), ("-" * 7), ("-" * 13), ("-" * 20)) -ForegroundColor DarkGray

            for ($i = 0; $i -lt $childFolders.Count; $i++) {
                Write-Host ($rowFormat -f ("P" + ($i + 1)), (& $fit ([string]$childFolders[$i].Name) 44), "Pasta", "-", "-") -ForegroundColor Cyan
            }

            for ($i = 0; $i -lt $documents.Count; $i++) {
                $document = $documents[$i]

                $code = [string]$document.SourceCode
                if ([string]::IsNullOrWhiteSpace($code)) { $code = [string]$document.File.BaseName }   # codigo nao identificado: usa o nome do arquivo
                $revision = [string]$document.ClientRevision
                if ([string]::IsNullOrWhiteSpace($revision)) { $revision = "nao informada" }
                $state = [string]$document.PdmState
                if ([string]::IsNullOrWhiteSpace($state)) { $state = "nao informado" }
                $stateColor = if ($stateColors.ContainsKey($state)) { $stateColors[$state] } else { "Yellow" }

                Write-Host ("  {0,-7} {1,-44} {2,-9} {3,-15} " -f ("D" + ($i + 1)), (& $fit $code 44), "Item", (& $fit $revision 15)) -ForegroundColor Gray -NoNewline
                Write-Host $state -ForegroundColor $stateColor

                if ($showDocumentLines) {
                    $title = [string]$document.DocumentTitle
                    if ([string]::IsNullOrWhiteSpace($title)) { $title = "nao informado" }
                    Write-Host "          Nome:    $title" -ForegroundColor DarkGray
                    Write-Host "          Arquivo: $($document.File.Name)" -ForegroundColor DarkGray
                }
            }

            Write-Host ("  " + ("-" * 104)) -ForegroundColor DarkGray
            Write-Host ""
        }
        else { Write-Warn "A pasta atual nao possui subpastas nem documentos." }

        # --- 5. Opcoes disponiveis ---
        Write-Host "  Opcoes disponiveis:" -ForegroundColor Cyan
        if ($childFolders.Count -gt 0) { Write-Host "    P1              abrir a pasta P1" -ForegroundColor DarkGray }
        if ($documents.Count -gt 0) {
            Write-Host "    D1              selecionar o documento D1" -ForegroundColor DarkGray
            Write-Host "    D1,D3,D5        selecionar varios documentos" -ForegroundColor DarkGray
            Write-Host "    D1-D5           selecionar um intervalo" -ForegroundColor DarkGray
            Write-Host "    T               selecionar todos os documentos" -ForegroundColor DarkGray
            Write-Host "    T-D2,D5         selecionar todos, exceto D2 e D5" -ForegroundColor DarkGray
        }
        if ($navigationStack.Count -gt 0) { Write-Host "    V               voltar para a pasta anterior" -ForegroundColor DarkGray }
        Write-Host "    S               sair sem selecionar" -ForegroundColor DarkGray
        Write-Host ""

        # --- 6. Receber a opcao: sair, voltar, todos ---
        $selection = ([string](Read-Host "Digite a opcao")).Trim()
        if ($selection -eq "") { Write-Warn "Nenhuma opcao foi informada."; continue }

        if ($selection -ieq "S" -or $selection -ieq "SAIR") { return @() }

        if ($selection -ieq "V" -or $selection -ieq "VOLTAR") {
            if ($navigationStack.Count -eq 0) { Write-Warn "Nao existe uma pasta anterior."; continue }
            $currentFolder = $navigationStack.Pop()
            continue
        }

        if ($selection -ieq "T" -or $selection -ieq "TODOS") {
            if ($documents.Count -eq 0) { Write-Warn "A pasta atual nao possui documentos para selecionar."; continue }
            return @($documents)
        }

        # --- 7. Abrir uma subpasta (Pnumero) ---
        if ($selection -match '^(?i:P)(?<Number>\d+)$') {
            $n = [int]$Matches["Number"]
            if ($n -lt 1 -or $n -gt $childFolders.Count) { Write-Warn "Pasta invalida. Use um numero entre 1 e $($childFolders.Count)."; continue }

            $child = $childFolders[$n - 1]
            $childFullPath = [System.IO.Path]::GetFullPath($child.FullName).TrimEnd([char[]]@('\', '/'))

            # Caminho relativo calculado a partir da raiz da navegacao.
            $childRelativePath = $childFullPath.Substring($RootFolderOption.FullName.Length).TrimStart("\")
            $childRelativePath = if ([string]::IsNullOrWhiteSpace($childRelativePath)) { $child.Name }
                                 else { "$($RootFolderOption.RelativePath)\$childRelativePath" }

            $navigationStack.Push($currentFolder)   # usado pela opcao V

            # A nova pasta herda categoria e tipo definidos na raiz.
            $currentFolder = [PSCustomObject]@{
                Name           = $child.Name
                RelativePath   = $childRelativePath
                FullName       = $childFullPath
                CategoryFolder = $RootFolderOption.CategoryFolder
                DocumentType   = $RootFolderOption.DocumentType
                DisplayName    = $RootFolderOption.DisplayName
            }
            continue
        }

        # --- 8. Interpretar documentos: D1 | D1,D3 | D1-D5 | T-D2,D5 | T-D2-D5 ---
        # No modo T-, todos entram e os numeros depois do hifen saem.
        $excludeMode = $selection -match '^(?i:T|TODOS)\s*-\s*(.+)$'
        $documentSelection = if ($excludeMode) { ([string]$Matches[1]).Trim() } else { $selection }
        $documentSelection = $documentSelection -replace '(?i)D(?=\d)', ''   # D1-D5 -> 1-5

        $parsed = [System.Collections.Generic.List[int]]::new()   # sem repeticao, na ordem lida
        $valid = $true

        foreach ($part in ($documentSelection -split ",")) {
            $part = ([string]$part).Trim()

            if ($part -eq "") { Write-Warn "Selecao invalida: existem valores vazios na entrada."; $valid = $false; break }

            if ($part -match '^(?<Start>\d+)\s*-\s*(?<End>\d+)$') {   # intervalo
                $a = [int]$Matches["Start"]; $b = [int]$Matches["End"]
                if ($a -lt 1 -or $b -gt $documents.Count -or $a -gt $b) {
                    Write-Warn "Intervalo de documentos invalido: '$part'. Use valores entre D1 e D$($documents.Count)."
                    $valid = $false; break
                }
                $a..$b | ForEach-Object { if (-not $parsed.Contains($_)) { $parsed.Add($_) } }
                continue
            }

            $n = 0
            if (-not [int]::TryParse($part, [ref]$n) -or $n -lt 1 -or $n -gt $documents.Count) {
                Write-Warn "Documento invalido: '$part'. Use valores entre D1 e D$($documents.Count)."
                $valid = $false; break
            }
            if (-not $parsed.Contains($n)) { $parsed.Add($n) }
        }
        if (-not $valid) { continue }

        $selectedNumbers = if ($excludeMode) { @(1..$documents.Count | Where-Object { $parsed -notcontains $_ }) } else { @($parsed) }
        if ($selectedNumbers.Count -eq 0) { Write-Warn "Use Pnumero para abrir uma pasta ou Dnumero para selecionar documentos."; continue }

        # --- 9. Montar o retorno na mesma ordem apresentada ao usuario ---
        $selectedDocuments = [System.Collections.Generic.List[object]]::new()
        foreach ($n in ($selectedNumbers | Sort-Object)) {
            $selectedDocuments.Add($documents[$n - 1])
            Write-Success "PDF selecionado [D$n]: $($documents[$n - 1].File.Name)"
        }
        return $selectedDocuments.ToArray()
    }
}