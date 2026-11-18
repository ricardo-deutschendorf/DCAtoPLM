# ============================================================
# PESQUISA E SELECAO POR CODIGO
# ============================================================
# Pesquisa PDFs (e SLDDRW de Folhas NDT) pelo codigo informado nas
# categorias DCA permitidas. A API do Vault tem prioridade (acha
# arquivos fora do cache local); sem ela, usa o sistema de arquivos.
# Para cada resultado: interpreta o nome, identifica codigo e revisao,
# consulta o estado no PDM, complementa revisao/descricao pelo cartao
# e apresenta os resultados para selecao.
# ============================================================

# Verdadeiro quando algum segmento do caminho e igual a $Segment.
function Test-DcaPathSegment {
  param([string]$Path, [string]$Segment)

  if ([string]::IsNullOrWhiteSpace($Path)) { return $false }
  return @($Path -split '[\\/]' | Where-Object { $_.Trim() -ieq $Segment }).Count -gt 0
}

# Converte a selecao digitada (1,3-5 | T | T-2,5) em numeros ordenados.
# Retorna $null (apos avisar) quando a selecao e invalida.
function ConvertFrom-DcaSelectionText {
  param([string]$Text, [int]$Count)

  $selected = [System.Collections.Generic.SortedSet[int]]::new()
  $excludeMode = $false
  $valuesText = $Text

  if ($Text -match '(?i)^(T|TODOS)\s*-\s*(.+)$') {
    # T-2,5: comeca com todos e remove os informados.
    $excludeMode = $true
    $valuesText = $Matches[2].Trim()
    $selected.UnionWith([int[]](1..$Count))
  }
  elseif ($Text -ieq "T" -or $Text -ieq "TODOS") {
    $selected.UnionWith([int[]](1..$Count))
    return , $selected
  }

  $parsed = [System.Collections.Generic.SortedSet[int]]::new()

  foreach ($part in ($valuesText -split ",")) {
    $part = $part.Trim()
    if (-not $part) { continue }

    # Intervalo 1-5 (em T-2-4, significa todos, exceto 2, 3 e 4).
    if ($part -match '^(?<Start>\d+)\s*-\s*(?<End>\d+)$') {
      $start = [int]$Matches["Start"]
      $end = [int]$Matches["End"]

      if ($start -lt 1 -or $end -gt $Count -or $start -gt $end) {
        Write-Warn "Intervalo invalido: '$part'. Use valores entre 1 e $Count."
        return $null
      }
      foreach ($n in $start..$end) { $null = $parsed.Add($n) }
      continue
    }

    $number = 0
    if (-not [int]::TryParse($part, [ref]$number) -or $number -lt 1 -or $number -gt $Count) {
      Write-Warn "Selecao invalida: '$part'. Digite numeros entre 1 e $Count."
      return $null
    }
    $null = $parsed.Add($number)
  }

  if ($excludeMode) { $selected.ExceptWith($parsed) } else { $selected.UnionWith($parsed) }
  return , $selected
}

function Select-DcaPdfByCode {
  param(
    [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$FolderPath,
    [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$Code,
    [System.Collections.Generic.HashSet[string]]$PreviouslySelectedPaths
  )

  # --- 1. Raiz e codigo de pesquisa ---
  if (-not (Test-Path -LiteralPath $FolderPath -PathType Container)) {
    throw "Vault DCA nao encontrado em '$FolderPath'."
  }

  $searchText = $Code.Trim()
  if (-not $searchText) { throw "O codigo de pesquisa ficou vazio." }

  # Pesquisa parcial: sem curinga, envolve o termo por asteriscos.
  $searchPattern = if ($searchText -match '[*?]') { $searchText } else { "*$searchText*" }

  Write-AnimatedLine ""
  Write-Info "Pesquisando todas as correspondencias de: [$searchText]"

  # --- 2. Pasta de documentacao ---
  $rootFolders = @(Get-ChildItem -LiteralPath $FolderPath -Directory -Force -ErrorAction Stop)
  $documentationFolder = $rootFolders | Where-Object { $_.Name -like "Documenta*" } | Select-Object -First 1

  if ($null -eq $documentationFolder) {
    throw (
      "A pasta de documentacao nao foi encontrada em '$FolderPath'. " +
      "Pastas visiveis: " + (($rootFolders | ForEach-Object { $_.Name }) -join ", ")
    )
  }
  Write-Info "Pasta de documentacao localizada."

  # --- 3. Categorias permitidas ---
  $categoryDefinitions = @(
    @{ FolderName = "Desenhos Originais";            DocumentType = "Original";     DisplayName = "DCA Desenho Original" }
    @{ FolderName = "FP - Ficha de Processo (PDF)";  DocumentType = "Processo";     DisplayName = "DCA Processo" }
    @{ FolderName = "FP - Ficha de Processo";        DocumentType = "NDT";          DisplayName = "GD5_DCA_NDT"
       RequiredPathSegment = "Folhas NDT"; AllowedExtension = ".slddrw" }
    @{ FolderName = "Normas Externas";               DocumentType = "NormaExterna"; DisplayName = "DCA Norma Externa" }
    @{ FolderName = "FP - XXRE Dimensional";         DocumentType = "DatasetOnly";  DisplayName = "XXRE Dimensional - somente Dataset" }
  )

  $documentationSubfolders = @(Get-ChildItem -LiteralPath $documentationFolder.FullName -Directory -Force -ErrorAction Stop)

  $searchFolders = foreach ($category in $categoryDefinitions) {
    $categoryFolder = $documentationSubfolders |
      Where-Object { $_.Name.Trim() -ieq $category.FolderName } |
      Select-Object -First 1

    if ($null -eq $categoryFolder) {
      if ($Details) { Write-Warn "Pasta nao encontrada: $($category.FolderName)" }
      continue
    }

    [PSCustomObject]@{
      DirectoryPath       = $categoryFolder.FullName
      DocumentType        = $category.DocumentType
      DisplayName         = $category.DisplayName
      RequiredPathSegment = ([string]$category.RequiredPathSegment).Trim()
      AllowedExtension    = ([string]$category.AllowedExtension).Trim()
    }
  }
  $searchFolders = @($searchFolders)

  if ($searchFolders.Count -eq 0) {
    throw (
      "Nenhuma pasta permitida foi encontrada em '$($documentationFolder.FullName)'. " +
      "Pastas visiveis: " + (($documentationSubfolders | ForEach-Object { $_.Name }) -join ", ")
    )
  }

  # --- 4. API do PDM primeiro (se falhar ou vier vazia, usa o disco) ---
  $matchingFiles = [System.Collections.Generic.List[object]]::new()
  $knownPaths = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

  $apiEntries = $null
  $vault = Get-DcaVault

  if ($null -ne $vault) {
    Write-Info "Consultando o vault..."
    try {
      $apiEntries = @(Search-DcaVaultPdfEntries -Vault $vault -SearchText $searchPattern)
      Write-Info "Resultados retornados pelo Vault: $($apiEntries.Count)"

      if ($apiEntries.Count -eq 0) {
        Write-Warn "A API do PDM nao retornou resultados. A pesquisa sera repetida nos arquivos locais."
        $apiEntries = $null
      }
    }
    catch {
      Write-Warn "A busca pela API do PDM falhou: $($_.Exception.Message) Usando o sistema de arquivos."
      $apiEntries = $null
    }
  }

  $separator = [string][System.IO.Path]::DirectorySeparatorChar

  # --- 5. Pesquisar em cada categoria ---
  foreach ($searchFolder in $searchFolders) {

    if ($null -ne $apiEntries) {
      $categoryPrefix = $searchFolder.DirectoryPath.TrimEnd($separator) + $separator
      $segment = $searchFolder.RequiredPathSegment
      $extension = $searchFolder.AllowedExtension

      $pdfEntries = @(
        $apiEntries |
          Where-Object {
            $fullName = [string]$_.FullName
            $fullName -and
            $fullName.StartsWith($categoryPrefix, [System.StringComparison]::OrdinalIgnoreCase) -and
            (-not $segment -or (Test-DcaPathSegment $fullName $segment)) -and
            (-not $extension -or [System.IO.Path]::GetExtension($fullName) -ieq $extension)
          } |
          Sort-Object FullName
      )
    }
    else {
      Write-Info ("Consultando {0}..." -f $searchFolder.DisplayName)

      if ($searchFolder.DocumentType -ieq "NDT") {
        # NDT: desenhos SLDDRW dentro de pastas "Folhas NDT".
        $pdfEntries = @(
          Get-ChildItem -LiteralPath $searchFolder.DirectoryPath -Filter "*.slddrw" -File -Recurse -Force `
            -ErrorAction SilentlyContinue |
            Where-Object { Test-DcaPathSegment $_.FullName "Folhas NDT" } |
            Sort-Object FullName |
            ForEach-Object {
              [PSCustomObject]@{
                Name            = [string]$_.Name
                BaseName        = [System.IO.Path]::GetFileNameWithoutExtension($_.Name)
                FullName        = [string]$_.FullName
                Extension       = ".slddrw"
                DocumentType    = "NDT"
                TypeDisplayName = "GD5_DCA_NDT"
                IsNdt           = $true
                FromVault       = $false
              }
            }
        )
      }
      else {
        $pdfEntries = @(Get-DcaDiskPdfEntries -FolderPath $searchFolder.DirectoryPath | Sort-Object FullName)
      }
    }

    if ($pdfEntries.Count -eq 0 -and $null -eq $apiEntries) {
      Write-Warn "Nenhum documento em disco e a API do PDM nao foi usada. O conteudo pode existir so no servidor do PDM."
    }

    foreach ($pdfEntry in $pdfEntries) {
      $entryFullName = [string]$pdfEntry.FullName
      $entryDocumentType = [string]$searchFolder.DocumentType
      $entryDisplayName = [string]$searchFolder.DisplayName

      # Folha NDT identificada pelo caminho, em qualquer categoria.
      if (Test-DcaPathSegment $entryFullName "Folhas NDT") {
        $entryDocumentType = "NDT"
        $entryDisplayName = "GD5_DCA_NDT"
        if ($Details) { Write-Host "  Folha NDT identificada pelo caminho: $entryFullName" -ForegroundColor DarkGray }
      }

      $parsedName = ConvertFrom-PdfFileName -BaseName $pdfEntry.BaseName -DocumentType $entryDocumentType

      $isMatch = Test-DcaCodeMatch `
        -BaseName $pdfEntry.BaseName -ParsedCode $parsedName.SourceCode `
        -Pattern $searchPattern -UsesWildcard $true
      if (-not $isMatch) { continue }

      # Um resultado por caminho completo.
      if (-not $entryFullName -or -not $knownPaths.Add($entryFullName)) { continue }

      $matchingFiles.Add([PSCustomObject]@{
          File               = $pdfEntry
          FileExtension      = [System.IO.Path]::GetExtension($entryFullName)
          SourceCode         = $parsedName.SourceCode
          ClientRevision     = [string]$parsedName.ClientRevision
          DocumentTitle      = $parsedName.DocumentTitle
          DocumentType       = $entryDocumentType
          TypeDisplayName    = $entryDisplayName
          CodeParsed         = $parsedName.CodeParsed
          NdtSheetType       = [string]$parsedName.NdtSheetType
          FolderImport       = $false
          PdmState           = Get-DcaPdmFileState -Entry $pdfEntry
          TeamcenterItem     = $null
          TeamcenterRevision = $null
        })
    }
  }

  # Revisao e descricao do cartao substituem as do nome do arquivo.
  foreach ($matchingFile in $matchingFiles) {
    Update-DcaMatchRevisionFromCard -Match $matchingFile
    Update-DcaMatchDescriptionFromCard -Match $matchingFile
  }

  [int]$matchCount = $matchingFiles.Count
  if ($matchCount -eq 0) { throw "Nenhum documento foi encontrado para a pesquisa '$searchPattern'." }

  # Numeros (a partir de 1) dos resultados ja escolhidos em pesquisas anteriores.
  $previousNumbers = [System.Collections.Generic.HashSet[int]]::new()
  if ($null -ne $PreviouslySelectedPaths) {
    for ($i = 0; $i -lt $matchCount; $i++) {
      $previousPath = ([string]$matchingFiles[$i].File.FullName).Trim()
      if ($previousPath -and $PreviouslySelectedPaths.Contains($previousPath)) { $null = $previousNumbers.Add($i + 1) }
    }
  }

  # --- 6. Exibir os resultados ---
  $script:SearchResultDelayMilliseconds = if ($matchCount -gt 3) { 20 } else { 30 }

  Write-SearchResultLine ""
  Write-SearchResultLine ("  Resultados da busca ({0} encontrado(s))" -f $matchCount) -Color White
  Write-SearchResultLine ("  Pesquisa: {0}" -f $searchPattern) -Color Gray
  Write-SearchResultLine ("  " + ("-" * 72)) -Color DarkGray

  for ($index = 0; $index -lt $matchCount; $index++) {
    $number = $index + 1
    $match = $matchingFiles[$index]
    $chosenBefore = $previousNumbers.Contains($number)

    $revisionDisplay = if ([string]::IsNullOrWhiteSpace([string]$match.ClientRevision)) { "nao informada" } else { [string]$match.ClientRevision }
    $nameDisplay     = if ([string]::IsNullOrWhiteSpace([string]$match.DocumentTitle))  { "nao informado" } else { [string]$match.DocumentTitle }
    $stateDisplay    = if ([string]::IsNullOrWhiteSpace([string]$match.PdmState))       { "nao informado" } else { [string]$match.PdmState }

    $stateColor = switch ($stateDisplay) {
      "Aprovado"   { "Green" }
      "Obsoleto"   { "Red" }
      "Verificado" { "Cyan" }
      default      { "Yellow" }
    }

    # O que ja foi escolhido antes aparece todo em cinza.
    $headerColor = "White"
    $textColor = "Gray"
    if ($chosenBefore) { $headerColor = $textColor = $stateColor = "DarkGray" }

    $headerText = "  [{0}] {1}" -f $number, $match.SourceCode
    if ($chosenBefore) { $headerText += "  (escolhido anteriormente)" }

    Write-SearchResultLine $headerText -Color $headerColor
    Write-SearchResultLine ("       Nome:    {0}" -f $nameDisplay) -Color $textColor
    Write-SearchResultLine ("       Tipo:    {0}" -f $match.TypeDisplayName) -Color $textColor
    Write-SearchResultLine ("       Revisao: {0}" -f $revisionDisplay) -Color $textColor
    Write-SearchResultLine ("       Estado:  {0}" -f $stateDisplay) -Color $stateColor

    if ($Details) {
      Write-SearchResultLine ("       Arquivo: {0}" -f $match.File.Name) -Color DarkGray
      if ($match.DocumentType -ieq "NDT" -and -not [string]::IsNullOrWhiteSpace([string]$match.NdtSheetType)) {
        Write-SearchResultLine ("       Folha:   {0}" -f $match.NdtSheetType) -Color DarkGray
      }
      Write-SearchResultLine ("       Local:   {0}" -f $match.File.FullName) -Color DarkGray
    }

    Write-SearchResultLine ""
  }

  # --- 7. Selecao ---
  # Um unico resultado dispensa a selecao manual.
  if ($matchCount -eq 1) {
    if (-not $previousNumbers.Contains(1)) {
      Write-Success "O unico documento encontrado foi selecionado automaticamente."
    }
    return $matchingFiles[0]
  }

  # Tudo ja escolhido antes: o fluxo principal ignora cada um com um aviso.
  if ($previousNumbers.Count -eq $matchCount) {
    Write-Warn "Todos os documentos desta pesquisa ja foram escolhidos anteriormente."
    return $matchingFiles.ToArray()
  }

  # Repete a pergunta ate haver uma selecao valida.
  while ($true) {
    $selectionText = ([string](Read-Host (
          "Digite numeros, intervalos, T para todos ou T-2,5 para excluir resultados"
        ))).Trim()

    if (-not $selectionText) {
      Write-Warn "Nenhum numero foi informado."
      continue
    }

    $selectedNumbers = ConvertFrom-DcaSelectionText -Text $selectionText -Count $matchCount
    if ($null -eq $selectedNumbers) { continue }

    # T e T-x pulam o que ja foi escolhido; numeros em cinza digitados tambem sao ignorados.
    $alreadyChosen = @($selectedNumbers | Where-Object { $previousNumbers.Contains($_) })
    if ($alreadyChosen.Count -gt 0) {
      Write-Warn (
        "Ja escolhido(s) anteriormente e ignorado(s): " +
        (($alreadyChosen | ForEach-Object { "[$_]" }) -join ", ")
      )
      $selectedNumbers.ExceptWith([int[]]$alreadyChosen)
    }

    if ($selectedNumbers.Count -eq 0) {
      Write-Warn "Nenhum resultado valido foi selecionado."
      continue
    }

    Write-AnimatedLine ""

    $selectedFiles = foreach ($selectedNumber in $selectedNumbers) {
      $selectedFile = $matchingFiles[$selectedNumber - 1]
      Write-Success "Documento selecionado [$selectedNumber]: $($selectedFile.File.Name)"
      if ($Details) { Write-Info "Local: $($selectedFile.File.FullName)" }
      $selectedFile
    }

    return @($selectedFiles)
  }
}