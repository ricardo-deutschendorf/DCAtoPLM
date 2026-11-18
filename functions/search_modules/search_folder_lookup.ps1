# ============================================================
# PESQUISA E SELECAO POR PASTA
# Localiza pastas pelo nome completo dentro de Documentacao,
# identifica a categoria DCA e retorna os PDFs escolhidos.
# Com ListFolderItems, a pasta escolhida abre para navegacao e
# selecao individual. Nao cria Item, revisao nem Dataset.
# ============================================================
function Select-DcaPdfsByFolder {
  param(
    [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$FolderPath,
    [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$FolderSearch,
    [switch]$ListFolderItems
  )

  # 1. Validar raiz
  if (-not (Test-Path -LiteralPath $FolderPath -PathType Container)) {
    throw "Vault DCA nao encontrado em '$FolderPath'."
  }

  # 2. Interpretar modo e nome da pasta
  $folderSearchText = ([string](Get-DcaFolderSearchMode -SearchText $FolderSearch).SearchText).Trim()
  $folderPattern = Get-DcaFolderSearchPattern -SearchText $FolderSearch

  # 3. Localizar a raiz Documentacao
  $documentationFolder = Get-ChildItem -LiteralPath $FolderPath -Directory -Force -ErrorAction Stop |
    Where-Object { $_.Name -like "Documenta*" } | Select-Object -First 1
  if ($null -eq $documentationFolder) {
    throw "A pasta de documentacao nao foi encontrada em '$FolderPath'."
  }

  # 4. Categorias DCA (o primeiro nivel abaixo de Documentacao define o tipo)
  $categories = @(
    [PSCustomObject]@{ FolderName = "Desenhos Originais";           DocumentType = "Original";     DisplayName = "DCA Desenho Original" }
    [PSCustomObject]@{ FolderName = "FP - Ficha de Processo (PDF)"; DocumentType = "Processo";     DisplayName = "DCA Processo" }
    [PSCustomObject]@{ FolderName = "Normas Externas";              DocumentType = "NormaExterna"; DisplayName = "DCA Norma Externa" }
    [PSCustomObject]@{ FolderName = "FP - XXRE Dimensional";        DocumentType = "DatasetOnly";  DisplayName = "XXRE Dimensional - somente Dataset" }
    [PSCustomObject]@{ FolderName = "Folhas NDT";                   DocumentType = "NDT";          DisplayName = "GD5_DCA_NDT" }
  )
  $processFolder = "FP - Ficha de Processo (PDF)"

  # 5. Localizar pastas com nome ou caminho relativo exato (busca recursiva)
  $root = $documentationFolder.FullName
  $matchingFolders = @(
    foreach ($dir in Get-ChildItem -LiteralPath $root -Directory -Recurse -Force -ErrorAction SilentlyContinue) {
      $full = [System.IO.Path]::GetFullPath($dir.FullName).TrimEnd("\")
      if (-not $full.StartsWith("$root\", [System.StringComparison]::OrdinalIgnoreCase)) { continue }

      $rel = $full.Substring($root.Length).TrimStart("\")
      if ($dir.Name -ine $folderPattern -and $rel -ine $folderPattern) { continue }

      # Folhas NDT fica aninhada em FP - Ficha de Processo (PDF) e deve ser
      # verificada antes de Processo, pois o caminho tambem comeca por ele.
      $isProcess = $rel -ieq $processFolder -or $rel.StartsWith("$processFolder\", [System.StringComparison]::OrdinalIgnoreCase)
      $isNdt = $isProcess -and @($rel -split '[\\/]' | Where-Object { $_.Trim() -ieq "Folhas NDT" }).Count -gt 0

      $category = if ($isNdt) {
        $categories | Where-Object { $_.DocumentType -ieq "NDT" } | Select-Object -First 1
      }
      else {
        $categories | Where-Object {
          $_.DocumentType -ine "NDT" -and (
            $rel -ieq $_.FolderName -or
            $rel.StartsWith("$($_.FolderName)\", [System.StringComparison]::OrdinalIgnoreCase))
        } | Select-Object -First 1
      }

      # Pasta fora das categorias DCA: ignorada silenciosamente.
      if ($null -eq $category) { continue }

      [PSCustomObject]@{
        Name             = $dir.Name
        RelativePath     = $rel
        FullName         = $full
        CategoryFolder   = if ($isNdt) { $processFolder } else { $category.FolderName }
        DocumentCategory = $category.FolderName
        DocumentType     = $category.DocumentType
        DisplayName      = $category.DisplayName
      }
    }
  )

  if ($matchingFolders.Count -eq 0) {
    throw "Nenhuma pasta importavel foi encontrada com o nome '$folderSearchText' dentro das categorias DCA reconhecidas."
  }

  # 6. Pastas com o mesmo nome: escolher uma antes de ler os PDFs e cartoes do PDM
  if ($ListFolderItems -and $matchingFolders.Count -gt 1) {
    Write-AnimatedLine ""
    Write-Host "  Foram encontradas varias pastas com o nome '$folderPattern':" -ForegroundColor Cyan
    Write-Host ("  " + ("-" * 68)) -ForegroundColor DarkGray
    for ($i = 0; $i -lt $matchingFolders.Count; $i++) {
      Write-Host ("  [{0}] {1}" -f ($i + 1), $matchingFolders[$i].RelativePath) -ForegroundColor White
      Write-Host ("      Tipo: {0}" -f $matchingFolders[$i].DisplayName) -ForegroundColor Gray
      Write-Host ""
    }

    while ($true) {
      $n = 0
      if (-not [int]::TryParse((Read-Host "Digite o numero da pasta que deseja abrir"), [ref]$n) -or
          $n -lt 1 -or $n -gt $matchingFolders.Count) {
        Write-Warn "Selecao invalida. Digite um numero entre 1 e $($matchingFolders.Count)."
        continue
      }
      Write-AnimatedLine ""
      Write-Success "Pasta escolhida [$n]: $($matchingFolders[$n - 1].RelativePath)"
      $matchingFolders = @($matchingFolders[$n - 1])
      break
    }
  }

  Write-AnimatedLine ""
  Write-Info "Localizando a pasta com o nome exato: '$folderPattern'"

  # 7. Conexao com o Vault (sem API, os PDFs sao lidos do disco)
  $vault = Get-DcaVault
  if ($null -eq $vault) {
    Write-Warn "API do PDM indisponivel. A pesquisa sera feita nos arquivos locais."
  }

  # 8. Preparar documentos e resumo (aprovados/obsoletos/outros) de cada pasta
  $folderOptions = foreach ($folder in $matchingFolders) {
    $docs = @()
    if (-not $ListFolderItems) {
      $docs = @(Get-DcaDocumentsFromFolderPath -FolderOption $folder -Vault $vault -SuppressItemDetails)
      if ($docs.Count -eq 0) { continue }   # sem PDFs diretamente na pasta
    }
    $approved = @($docs | Where-Object { $_.PdmState -ieq "Aprovado" }).Count
    $obsolete = @($docs | Where-Object { $_.PdmState -ieq "Obsoleto" }).Count

    $folder | Add-Member -PassThru -NotePropertyMembers @{
      Number        = 0
      Documents     = $docs
      Total         = $docs.Count
      ApprovedCount = $approved
      ObsoleteCount = $obsolete
      OtherCount    = $docs.Count - $approved - $obsolete
    }
  }

  # 9. Validar, ordenar e numerar (a numeracao vem depois da ordenacao)
  $folderOptions = @($folderOptions | Sort-Object RelativePath)
  if ($folderOptions.Count -eq 0) {
    throw "As pastas encontradas para '$folderPattern' nao possuem PDFs diretamente dentro delas."
  }
  for ($i = 0; $i -lt $folderOptions.Count; $i++) { $folderOptions[$i].Number = $i + 1 }

  $writeSummary = {
    param($o, $pad, $pdfColor)
    Write-Host "${pad}Tipo:       $($o.DisplayName)" -ForegroundColor Cyan
    Write-Host "${pad}PDFs:       $($o.Total)" -ForegroundColor $pdfColor
    Write-Host "${pad}Aprovados:  $($o.ApprovedCount)" -ForegroundColor Green
    Write-Host "${pad}Obsoletos:  $($o.ObsoleteCount)" -ForegroundColor Red
    Write-Host "${pad}Outros:     $($o.OtherCount)" -ForegroundColor Yellow
  }

  # 10. Pasta unica: seleciona automaticamente
  if ($folderOptions.Count -eq 1) {
    $selectedFolder = $folderOptions[0]

    if ($ListFolderItems) {
      return @(Select-DcaDocumentsWithFolderNavigation -RootFolderOption $selectedFolder)
    }

    Write-AnimatedLine ""
    Write-Success "Pasta selecionada: \$($selectedFolder.RelativePath)"
    & $writeSummary $selectedFolder "  " White
    return $selectedFolder.Documents
  }

  # 11. Apresentar as pastas
  Write-AnimatedLine ""
  Write-Host "  Pastas encontradas:" -ForegroundColor Cyan
  Write-Host ("  " + ("-" * 68)) -ForegroundColor DarkGray
  foreach ($option in $folderOptions) {
    Write-Host ("  [{0}] {1}" -f $option.Number, $option.RelativePath) -ForegroundColor White
    & $writeSummary $option "      " Gray
    Write-Host ""
  }
  if ($ListFolderItems) {
    Write-Host "  Selecione a pasta que deseja abrir." -ForegroundColor Cyan
    Write-Host "  Depois da selecao, os documentos da pasta serao listados." -ForegroundColor DarkGray
  }
  else {
    Write-Host "  Selecione uma ou mais pastas." -ForegroundColor Cyan
    Write-Host "  Exemplos: 1 | 1,2 | 1-3 | T" -ForegroundColor DarkGray
  }

  # 12. Receber e validar a selecao (numeros, listas, intervalos ou T)
  $prompt = if ($ListFolderItems) { "Digite o numero da pasta que deseja abrir" }
            else { "Digite o numero da pasta, varios numeros ou T para todas" }

  while ($true) {
    $text = ([string](Read-Host $prompt)).Trim()
    if ($text -eq "") { Write-Warn "Nenhuma pasta foi selecionada."; continue }

    $isAll = $text -ieq "T" -or $text -ieq "TODAS"
    if ($isAll -and $ListFolderItems) {
      Write-Warn "No modo de visualizacao de itens, selecione apenas o numero de uma pasta."
      continue
    }

    $selected = [System.Collections.Generic.List[int]]::new()   # sem duplicados, na ordem lida
    $valid = $true

    if ($isAll) {
      1..$folderOptions.Count | ForEach-Object { $selected.Add($_) }
    }
    else {
      foreach ($part in ($text -split ",")) {
        $part = ([string]$part).Trim()

        if ($part -eq "") {
          Write-Warn "Selecao invalida. Existem partes vazias na entrada."
          $valid = $false; break
        }

        if ($part -match '^(?<Start>\d+)\s*-\s*(?<End>\d+)$') {
          $a = 0; $b = 0
          if (-not ([int]::TryParse($Matches["Start"], [ref]$a) -and [int]::TryParse($Matches["End"], [ref]$b)) -or
              $a -lt 1 -or $b -gt $folderOptions.Count -or $a -gt $b) {
            Write-Warn "Intervalo invalido: '$part'."
            $valid = $false; break
          }
          $a..$b | ForEach-Object { if (-not $selected.Contains($_)) { $selected.Add($_) } }
          continue
        }

        $n = 0
        if (-not [int]::TryParse($part, [ref]$n) -or $n -lt 1 -or $n -gt $folderOptions.Count) {
          Write-Warn "Selecao invalida: '$part'. Use numeros entre 1 e $($folderOptions.Count)."
          $valid = $false; break
        }
        if (-not $selected.Contains($n)) { $selected.Add($n) }
      }
    }

    if (-not $valid) { continue }

    # 13. Modo navegacao: abre uma unica pasta
    if ($ListFolderItems) {
      if ($selected.Count -ne 1) {
        Write-Warn "No modo de visualizacao de itens, selecione somente uma pasta por vez."
        continue
      }
      $n = $selected[0]
      $selectedFolder = $folderOptions[$n - 1]
      Write-AnimatedLine ""
      Write-Success "Pasta selecionada [$n]: \$($selectedFolder.RelativePath)"

      $docs = Select-DcaDocumentsFromFolder -FolderOption $selectedFolder -AllowBack
      if ($null -eq $docs) { continue }   # NULL = voltar para a lista de pastas
      if (@($docs).Count -eq 0) { Write-Warn "Nenhum documento foi selecionado."; continue }
      return @($docs)
    }

    # 14. Reunir os documentos (o caminho completo evita PDFs duplicados no lote)
    $documents = [System.Collections.Generic.List[object]]::new()
    $knownPaths = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

    Write-AnimatedLine ""
    foreach ($n in ($selected | Sort-Object)) {
      $folder = $folderOptions[$n - 1]
      Write-Success "Pasta selecionada [$n]: \$($folder.RelativePath)"

      foreach ($doc in $folder.Documents) {
        if ($null -eq $doc -or $null -eq $doc.File) {
          Write-Warn "Documento ignorado: arquivo fisico nao encontrado."
          continue
        }
        $path = [string]$doc.File.FullName
        if (-not [string]::IsNullOrWhiteSpace($path) -and $knownPaths.Add($path)) { $documents.Add($doc) }
      }
    }

    Write-AnimatedLine ""
    Write-Host "  Pastas selecionadas:    $($selected.Count)" -ForegroundColor Cyan
    Write-Host "  Documentos adicionados: $($documents.Count)" -ForegroundColor Cyan

    return $documents.ToArray()
  }
}