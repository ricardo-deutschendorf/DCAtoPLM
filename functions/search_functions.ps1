function Select-DcaDocumentsFromFolder {

  param(
    [Parameter(Mandatory = $true)]
    $FolderOption,

    [switch]$AllowBack
  )

  $documents =
  @(
    $FolderOption.Documents |
      Sort-Object {
      [string]$_.SourceCode
    }, {
      [string]$_.File.Name
    }
  )

  if ($documents.Count -eq 0) {
    Write-Warn (
      "A pasta '$($FolderOption.RelativePath)' nao possui PDFs."
    )

    return $null
  }

  while ($true) {

    Write-AnimatedLine ""

    Write-Host (
      "  Pasta selecionada: \$($FolderOption.RelativePath)"
    ) -ForegroundColor Cyan

    Write-Host (
      "  Tipo: $($FolderOption.DisplayName)"
    ) -ForegroundColor Gray

    Write-Host (
      "  Documentos encontrados: $($documents.Count)"
    ) -ForegroundColor Gray

    Write-Host (
      "  " + ("-" * 72)
    ) -ForegroundColor DarkGray

    for (
      $index = 0
      $index -lt $documents.Count
      $index++
    ) {

      $document =
      $documents[$index]

      $number =
      $index + 1

      $sourceCode =
      [string]$document.SourceCode

      if (
        [string]::IsNullOrWhiteSpace(
          $sourceCode
        )
      ) {
        $sourceCode =
        [string]$document.File.BaseName
      }

      $documentTitle =
      [string]$document.DocumentTitle

      if (
        [string]::IsNullOrWhiteSpace(
          $documentTitle
        )
      ) {
        $documentTitle =
        "sem titulo"
      }

      $revisionDisplay =
      [string]$document.ClientRevision

      if (
        [string]::IsNullOrWhiteSpace(
          $revisionDisplay
        )
      ) {
        $revisionDisplay =
        "nao informada"
      }

      $stateDisplay =
      [string]$document.PdmState

      if (
        [string]::IsNullOrWhiteSpace(
          $stateDisplay
        )
      ) {
        $stateDisplay =
        "nao informado"
      }

      $stateColor =
      [System.ConsoleColor]::Yellow

      if ($stateDisplay -ieq "Aprovado") {
        $stateColor =
        [System.ConsoleColor]::Green
      }
      elseif ($stateDisplay -ieq "Obsoleto") {
        $stateColor =
        [System.ConsoleColor]::Red
      }
      elseif ($stateDisplay -ieq "Verificado") {
        $stateColor =
        [System.ConsoleColor]::Cyan
      }

      Write-Host (
        "  [{0}] {1}" -f
        $number,
        $sourceCode
      ) -ForegroundColor White

      Write-Host (
        "       Nome:    {0}" -f
        $documentTitle
      ) -ForegroundColor Gray

      Write-Host (
        "       Revisao: {0}" -f
        $revisionDisplay
      ) -ForegroundColor Gray

      $revisionSourceDisplay =
      [string]$currentMatch.RevisionSource

      if (
        [string]::IsNullOrWhiteSpace(
          $revisionSourceDisplay
        )
      ) {
        $revisionSourceDisplay =
        "nome do arquivo"
      }

      Write-SearchResultLine (
        "       Fonte:   {0}" -f
        $revisionSourceDisplay
      ) -Color DarkGray

      Write-Host (
        "       Estado:  {0}" -f
        $stateDisplay
      ) -ForegroundColor $stateColor

      if ($Details) {

        Write-Host (
          "       PDF:     {0}" -f
          $document.File.Name
        ) -ForegroundColor DarkGray

        Write-Host (
          "       Local:   {0}" -f
          $document.File.FullName
        ) -ForegroundColor DarkGray
      }

      Write-Host ""
    }

    Write-Host (
      "  Selecione os documentos que deseja importar."
    ) -ForegroundColor Cyan

    Write-Host (
      "  Exemplos: 1 | 1,3,5 | 1-5 | T | *"
    ) -ForegroundColor DarkGray

    if ($AllowBack) {
      Write-Host (
        "  Digite V para voltar para a lista de pastas"
      ) -ForegroundColor DarkGray
    }

    $selectionText =
    Read-Host (
      "Digite os numeros dos documentos"
    )

    if (
      [string]::IsNullOrWhiteSpace(
        $selectionText
      )
    ) {
      Write-Warn "Nenhum documento foi selecionado."
      continue
    }

    $selectionText =
    $selectionText.Trim()

    if (
      $AllowBack -and
      (
        $selectionText -ieq "V" -or
        $selectionText -ieq "VOLTAR"
      )
    ) {
      return $null
    }

    $selectedNumbers =
    [System.Collections.Generic.List[int]]::new()

    $knownNumbers =
    [System.Collections.Generic.HashSet[int]]::new()

    $selectionIsValid =
    $true

    if (
      $selectionText -ieq "T" -or
      $selectionText -ieq "TODOS" -or
      $selectionText -eq "*"
    ) {

      for (
        $number = 1
        $number -le $documents.Count
        $number++
      ) {

        if ($knownNumbers.Add($number)) {
          $selectedNumbers.Add($number)
        }
      }
    }
    else {

      foreach (
        $selectionPart in (
          $selectionText -split ","
        )
      ) {

        $currentPart =
        ([string]$selectionPart).Trim()

        if (
          [string]::IsNullOrWhiteSpace(
            $currentPart
          )
        ) {
          continue
        }

        if (
          $currentPart -match
          '^(?<Start>\d+)\s*-\s*(?<End>\d+)$'
        ) {

          $rangeStart =
          [int]$Matches["Start"]

          $rangeEnd =
          [int]$Matches["End"]

          if (
            $rangeStart -lt 1 -or
            $rangeEnd -gt $documents.Count -or
            $rangeStart -gt $rangeEnd
          ) {

            Write-Warn (
              "Intervalo invalido: '$currentPart'. " +
              "Use valores entre 1 e $($documents.Count)."
            )

            $selectionIsValid =
            $false

            break
          }

          for (
            $rangeNumber = $rangeStart
            $rangeNumber -le $rangeEnd
            $rangeNumber++
          ) {

            if ($knownNumbers.Add($rangeNumber)) {
              $selectedNumbers.Add($rangeNumber)
            }
          }

          continue
        }

        $selectedNumber =
        0

        $validNumber =
        [System.Int32]::TryParse(
          $currentPart,
          [ref]$selectedNumber
        )

        if (
          -not $validNumber -or
          $selectedNumber -lt 1 -or
          $selectedNumber -gt $documents.Count
        ) {

          Write-Warn (
            "Selecao invalida: '$currentPart'. " +
            "Digite numeros entre 1 e $($documents.Count)."
          )

          $selectionIsValid =
          $false

          break
        }

        if ($knownNumbers.Add($selectedNumber)) {
          $selectedNumbers.Add($selectedNumber)
        }
      }
    }

    if (-not $selectionIsValid) {
      continue
    }

    if ($selectedNumbers.Count -eq 0) {
      Write-Warn "Nenhum documento valido foi selecionado."
      continue
    }

    $selectedDocuments =
    [System.Collections.Generic.List[object]]::new()

    Write-AnimatedLine ""

    foreach (
      $selectedNumber in (
        $selectedNumbers |
          Sort-Object
      )
    ) {

      $selectedDocument =
      $documents[$selectedNumber - 1]

      $selectedDocuments.Add(
        $selectedDocument
      )

      Write-Success (
        "PDF selecionado [$selectedNumber]: " +
        $selectedDocument.File.Name
      )
    }

    Write-AnimatedLine ""

    Write-Host (
      "  Documentos selecionados: " +
      $selectedDocuments.Count
    ) -ForegroundColor Cyan

    return $selectedDocuments.ToArray()
  }
}
function Select-DcaPdfsByFolder {
  param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$FolderPath,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$FolderSearch,

    [switch]$ListFolderItems
  )
  if (-not (
      Test-Path `
        -LiteralPath $FolderPath `
        -PathType Container
    )) {

    throw "Vault DCA nao encontrado em '$FolderPath'."
  }

  $folderPattern =
  Get-DcaFolderSearchPattern `
    -SearchText $FolderSearch
  $usesWildcard =
  $folderPattern.Contains("*") -or
  $folderPattern.Contains("?")

  # ====================================================
  # Localizar a raiz Documentacao
  # ====================================================

  $documentationFolder =
  Get-ChildItem `
    -LiteralPath $FolderPath `
    -Directory `
    -Force `
    -ErrorAction Stop |
    Where-Object {
    $_.Name -like "Documenta*"
  } |
    Select-Object -First 1

  if ($null -eq $documentationFolder) {

    throw (
      "A pasta de documentacao nao foi encontrada em " +
      "'$FolderPath'."
    )
  }

  $documentationRootPath =
  [System.IO.Path]::GetFullPath(
    $documentationFolder.FullName
  ).TrimEnd("\")

  # ====================================================
  # Categorias conhecidas
  # ====================================================

  $categoryDefinitions =
  @(
    [PSCustomObject]@{
      FolderName = "Desenhos Originais"
      DocumentType = "Original"
      DisplayName = "DCA Desenho Original"
    }

    [PSCustomObject]@{
      FolderName = "FP - Ficha de Processo (PDF)"
      DocumentType = "Processo"
      DisplayName = "DCA Processo"
    }

    [PSCustomObject]@{
      FolderName = "Normas Externas"
      DocumentType = "NormaExterna"
      DisplayName = "DCA Norma Externa"
    }
  )

  # ====================================================
  # Procurar pastas em toda Documentacao
  # ====================================================

  $availableFolders =
  @(
    Get-ChildItem `
      -LiteralPath $documentationRootPath `
      -Directory `
      -Recurse `
      -Force `
      -ErrorAction SilentlyContinue
  )

  $matchingFolders =
  [System.Collections.Generic.List[object]]::new()

  foreach ($availableFolder in $availableFolders) {

    $folderFullPath =
    [System.IO.Path]::GetFullPath(
      $availableFolder.FullName
    ).TrimEnd("\")

    if (-not $folderFullPath.StartsWith(
        $documentationRootPath + "\",
        [System.StringComparison]::OrdinalIgnoreCase
      )) {

      continue
    }

    $relativePath =
    $folderFullPath.Substring(
      $documentationRootPath.Length
    ).TrimStart("\")

    $folderMatches =
    $relativePath -like $folderPattern -or
    $availableFolder.Name -like $folderPattern

    if (-not $folderMatches) {
      continue
    }

    # Identifica o tipo de documento pelo primeiro nível
    # abaixo da pasta Documentacao.
    $matchedCategory =
    $null

    foreach ($categoryDefinition in $categoryDefinitions) {

      $categoryPrefix =
      $categoryDefinition.FolderName + "\"

      if (
        $relativePath -ieq $categoryDefinition.FolderName -or
        $relativePath.StartsWith(
          $categoryPrefix,
          [System.StringComparison]::OrdinalIgnoreCase
        )
      ) {

        $matchedCategory =
        $categoryDefinition

        break
      }
    }

    if ($null -eq $matchedCategory) {

      if ($Details) {

        Write-Warn (
          "Pasta encontrada, mas sem tipo DCA configurado: " +
          "'$relativePath'."
        )
      }

      continue
    }

    $matchingFolders.Add(
      [PSCustomObject]@{
        Name = $availableFolder.Name
        RelativePath = $relativePath
        FullName = $folderFullPath
        CategoryFolder = $matchedCategory.FolderName
        DocumentType = $matchedCategory.DocumentType
        DisplayName = $matchedCategory.DisplayName
      }
    )
  }

  if ($matchingFolders.Count -eq 0) {

    throw (
      "Nenhuma pasta DCA foi encontrada para o padrao " +
      "'\$folderPattern' dentro de Documentacao."
    )
  }

  Write-AnimatedLine ""

  Write-Info (
    "Modo pasta em toda Documentacao: \$folderPattern"
  )

  # ====================================================
  # Consultar todos os PDFs uma unica vez
  # ====================================================

  $vault =
  Get-DcaVault

  $allAvailablePdfs =
  @()

  if ($null -ne $vault) {

    Write-Info "Consultando os PDFs no Vault..."

    $allAvailablePdfs =
    @(
      Search-DcaVaultPdfEntries `
        -Vault $vault `
        -SearchText "*"
    )
  }
  else {

    Write-Warn (
      "API do PDM indisponivel. " +
      "A pesquisa sera feita nos arquivos locais."
    )
  }

  # ====================================================
  # Criar uma opcao para cada pasta encontrada
  # ====================================================

  $folderOptions =
  [System.Collections.Generic.List[object]]::new()

  foreach ($matchingFolder in $matchingFolders) {

    $folderPdfEntries =
    @()

    if ($null -ne $vault) {

      # Apenas PDFs diretamente dentro da pasta.
      # Subpastas aparecem separadamente.
      $folderPdfEntries =
      @(
        $allAvailablePdfs |
          Where-Object {

          $pdfFullName =
          [string]$_.FullName

          if (
            [string]::IsNullOrWhiteSpace(
              $pdfFullName
            )
          ) {
            return $false
          }

          $pdfDirectory =
          [System.IO.Path]::GetDirectoryName(
            $pdfFullName
          )

          return (
            $pdfDirectory -ieq
            $matchingFolder.FullName
          )
        } |
          Sort-Object FullName
      )
    }
    else {

      $diskFiles =
      @(
        Get-ChildItem `
          -LiteralPath $matchingFolder.FullName `
          -Filter "*.pdf" `
          -File `
          -Force `
          -ErrorAction SilentlyContinue
      )

      $folderPdfEntries =
      @(
        foreach ($diskFile in $diskFiles) {

          [PSCustomObject]@{
            Name = $diskFile.Name
            BaseName = $diskFile.BaseName.Trim()
            FullName = $diskFile.FullName
            FromVault = $false
          }
        }
      )
    }

    $folderDocuments =
    [System.Collections.Generic.List[object]]::new()

    foreach ($pdfEntry in $folderPdfEntries) {

      $parsedName =
      ConvertFrom-PdfFileName `
        -BaseName $pdfEntry.BaseName `
        -DocumentType $matchingFolder.DocumentType

      $clientRevision =
      [string]$parsedName.ClientRevision

      $pdmState =
      Get-DcaPdmFileState `
        -Entry $pdfEntry

      $folderDocuments.Add(
        [PSCustomObject]@{
          File = $pdfEntry
          SourceCode = $parsedName.SourceCode
          ClientRevision = $clientRevision
          DocumentTitle = $parsedName.DocumentTitle
          DocumentType = $matchingFolder.DocumentType
          TypeDisplayName = $matchingFolder.DisplayName
          CodeParsed = $parsedName.CodeParsed
          PdmState = $pdmState
          FolderImport = $true
          FolderPattern = $folderPattern
          SourceFolder = $matchingFolder.RelativePath
          CategoryFolder = $matchingFolder.CategoryFolder
        }
      )
    }
    foreach ($folderDocument in $folderDocuments) {

      Update-DcaMatchRevisionFromCard `
        -Match $folderDocument

      Update-DcaMatchDescriptionFromCard `
        -Match $folderDocument
    }
    # Pastas sem PDFs diretamente dentro delas não são
    # apresentadas como opções.
    if ($folderDocuments.Count -eq 0) {
      continue
    }

    $approvedCount =
    @(
      $folderDocuments |
        Where-Object {
        $_.PdmState -ieq "Aprovado"
      }
    ).Count

    $obsoleteCount =
    @(
      $folderDocuments |
        Where-Object {
        $_.PdmState -ieq "Obsoleto"
      }
    ).Count

    $otherCount =
    $folderDocuments.Count -
    $approvedCount -
    $obsoleteCount

    $folderOptions.Add(
      [PSCustomObject]@{
        Number = 0
        Name = $matchingFolder.Name
        RelativePath = $matchingFolder.RelativePath
        FullName = $matchingFolder.FullName
        CategoryFolder = $matchingFolder.CategoryFolder
        DocumentType = $matchingFolder.DocumentType
        DisplayName = $matchingFolder.DisplayName
        Documents = $folderDocuments.ToArray()
        Total = $folderDocuments.Count
        ApprovedCount = $approvedCount
        ObsoleteCount = $obsoleteCount
        OtherCount = $otherCount
      }
    )
  }

  if ($folderOptions.Count -eq 0) {

    throw (
      "As pastas encontradas para '\$folderPattern' " +
      "nao possuem PDFs diretamente dentro delas."
    )
  }

  $folderOptions =
  @(
    $folderOptions |
      Sort-Object RelativePath
  )

  for (
    $index = 0
    $index -lt $folderOptions.Count
    $index++
  ) {

    $folderOptions[$index].Number =
    $index + 1
  }

  # ====================================================
  # Pasta exata e unica: seleciona automaticamente
  # ====================================================
  if (
    -not $usesWildcard -and
    $folderOptions.Count -eq 1
  ) {

    $selectedFolder =
    $folderOptions[0]

    Write-AnimatedLine ""

    Write-Success (
      "Pasta selecionada: " +
      "\$($selectedFolder.RelativePath)"
    )

    Write-Host (
      "  Tipo:       $($selectedFolder.DisplayName)"
    ) -ForegroundColor Cyan

    Write-Host (
      "  PDFs:       $($selectedFolder.Total)"
    ) -ForegroundColor White

    Write-Host (
      "  Aprovados:  $($selectedFolder.ApprovedCount)"
    ) -ForegroundColor Green

    Write-Host (
      "  Obsoletos:  $($selectedFolder.ObsoleteCount)"
    ) -ForegroundColor Red

    Write-Host (
      "  Outros:     $($selectedFolder.OtherCount)"
    ) -ForegroundColor Yellow

    if ($ListFolderItems) {

      $selectedDocuments =
      Select-DcaDocumentsFromFolder `
        -FolderOption $selectedFolder

      return @($selectedDocuments)
    }

    return $selectedFolder.Documents
  }
  # ====================================================
  # Mostrar resumo das pastas para selecao
  # ====================================================

  Write-AnimatedLine ""

  Write-Host "  Pastas encontradas:" -ForegroundColor Cyan
  Write-Host ("  " + ("-" * 68)) -ForegroundColor DarkGray

  foreach ($folderOption in $folderOptions) {

    Write-Host (
      "  [{0}] {1}" -f
      $folderOption.Number,
      $folderOption.RelativePath
    ) -ForegroundColor White

    Write-Host (
      "      Tipo:       {0}" -f
      $folderOption.DisplayName
    ) -ForegroundColor Cyan

    Write-Host (
      "      PDFs:       {0}" -f
      $folderOption.Total
    ) -ForegroundColor Gray

    Write-Host (
      "      Aprovados:  {0}" -f
      $folderOption.ApprovedCount
    ) -ForegroundColor Green

    Write-Host (
      "      Obsoletos:  {0}" -f
      $folderOption.ObsoleteCount
    ) -ForegroundColor Red

    Write-Host (
      "      Outros:     {0}" -f
      $folderOption.OtherCount
    ) -ForegroundColor Yellow

    Write-Host ""
  }
  if ($ListFolderItems) {

    Write-Host (
      "  Selecione a pasta que deseja abrir."
    ) -ForegroundColor Cyan

    Write-Host (
      "  Depois da selecao, os documentos da pasta serao listados."
    ) -ForegroundColor DarkGray
  }
  else {

    Write-Host (
      "  Selecione uma ou mais pastas."
    ) -ForegroundColor Cyan

    Write-Host (
      "  Exemplos: 1 | 1,2 | 1-3 | T"
    ) -ForegroundColor DarkGray
  }
  # ====================================================
  # Ler a selecao das pastas
  # ====================================================

  while ($true) {
    if ($ListFolderItems) {

      $selectionText =
      Read-Host (
        "Digite o numero da pasta que deseja abrir"
      )
    }
    else {

      $selectionText =
      Read-Host (
        "Digite o numero da pasta, varios numeros ou T para todas"
      )
    }
    if (
      [string]::IsNullOrWhiteSpace(
        $selectionText
      )
    ) {

      Write-Warn "Nenhuma pasta foi selecionada."

      continue
    }

    $selectionText =
    $selectionText.Trim()

    $selectedNumbers =
    [System.Collections.Generic.List[int]]::new()

    $knownNumbers =
    [System.Collections.Generic.HashSet[int]]::new()

    $selectionIsValid =
    $true

    if (
      $selectionText -ieq "T" -or
      $selectionText -ieq "TODAS"
    ) {

      for (
        $number = 1
        $number -le $folderOptions.Count
        $number++
      ) {

        if ($knownNumbers.Add($number)) {
          $selectedNumbers.Add($number)
        }
      }
    }
    else {

      foreach ($selectionPart in ($selectionText -split ",")) {

        $currentPart =
        ([string]$selectionPart).Trim()

        if (
          [string]::IsNullOrWhiteSpace(
            $currentPart
          )
        ) {
          continue
        }

        # Intervalo, por exemplo 1-3.
        if (
          $currentPart -match
          '^(?<Start>\d+)\s*-\s*(?<End>\d+)$'
        ) {

          $rangeStart =
          [int]$Matches["Start"]

          $rangeEnd =
          [int]$Matches["End"]

          if (
            $rangeStart -lt 1 -or
            $rangeEnd -gt $folderOptions.Count -or
            $rangeStart -gt $rangeEnd
          ) {

            Write-Warn (
              "Intervalo invalido: '$currentPart'."
            )

            $selectionIsValid =
            $false

            break
          }

          for (
            $rangeNumber = $rangeStart
            $rangeNumber -le $rangeEnd
            $rangeNumber++
          ) {

            if ($knownNumbers.Add($rangeNumber)) {
              $selectedNumbers.Add($rangeNumber)
            }
          }

          continue
        }

        $selectedNumber =
        0

        $validNumber =
        [System.Int32]::TryParse(
          $currentPart,
          [ref]$selectedNumber
        )

        if (
          -not $validNumber -or
          $selectedNumber -lt 1 -or
          $selectedNumber -gt $folderOptions.Count
        ) {

          Write-Warn (
            "Selecao invalida: '$currentPart'. " +
            "Use numeros entre 1 e " +
            "$($folderOptions.Count)."
          )

          $selectionIsValid =
          $false

          break
        }

        if ($knownNumbers.Add($selectedNumber)) {
          $selectedNumbers.Add($selectedNumber)
        }
      }
    }

    if (-not $selectionIsValid) {
      continue
    }

    if ($selectedNumbers.Count -eq 0) {

      Write-Warn "Nenhuma pasta valida foi selecionada."

      continue
    }
    if (
      $ListFolderItems -and
      $selectedNumbers.Count -ne 1
    ) {

      Write-Warn (
        "No modo de visualizacao de itens, " +
        "selecione somente uma pasta por vez."
      )

      continue
    }

    if ($ListFolderItems) {

      $selectedFolderNumber =
      $selectedNumbers[0]

      $selectedFolder =
      $folderOptions[$selectedFolderNumber - 1]

      Write-AnimatedLine ""

      Write-Success (
        "Pasta selecionada [$selectedFolderNumber]: " +
        "\$($selectedFolder.RelativePath)"
      )

      $selectedDocuments =
      Select-DcaDocumentsFromFolder `
        -FolderOption $selectedFolder `
        -AllowBack

      if ($null -eq $selectedDocuments) {
        continue
      }

      if (@($selectedDocuments).Count -eq 0) {
        Write-Warn "Nenhum documento foi selecionado."
        continue
      }

      return @($selectedDocuments)
    }
    # ==================================================
    # Juntar os documentos das pastas selecionadas
    # ==================================================

    $selectedDocuments =
    [System.Collections.Generic.List[object]]::new()

    $knownDocumentPaths =
    [System.Collections.Generic.HashSet[string]]::new(
      [System.StringComparer]::OrdinalIgnoreCase
    )

    Write-AnimatedLine ""

    foreach (
      $selectedNumber in (
        $selectedNumbers |
          Sort-Object
      )
    ) {

      $selectedFolder =
      $folderOptions[$selectedNumber - 1]

      Write-Success (
        "Pasta selecionada [$selectedNumber]: " +
        "\$($selectedFolder.RelativePath)"
      )

      foreach ($document in $selectedFolder.Documents) {

        $documentPath =
        [string]$document.File.FullName

        if (
          [string]::IsNullOrWhiteSpace(
            $documentPath
          )
        ) {
          continue
        }

        if ($knownDocumentPaths.Add($documentPath)) {
          $selectedDocuments.Add($document)
        }
      }
    }

    Write-AnimatedLine ""

    Write-Host (
      "  Pastas selecionadas:    $($selectedNumbers.Count)"
    ) -ForegroundColor Cyan

    Write-Host (
      "  Documentos adicionados: $($selectedDocuments.Count)"
    ) -ForegroundColor Cyan

    return $selectedDocuments.ToArray()
  }
}
function Select-DcaPdfByCode {

  param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$FolderPath,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$Code
  )

  if (-not (Test-Path -LiteralPath $FolderPath -PathType Container)) {
    throw "Vault DCA nao encontrado em '$FolderPath'."
  }

  $searchText =
  $Code.Trim()

  if (
    [string]::IsNullOrWhiteSpace(
      $searchText
    )
  ) {
    throw "O codigo de pesquisa ficou vazio."
  }

  # A pesquisa por codigo e sempre parcial.
  # Se o usuario nao informar wildcard, o script adiciona.
  if (
    $searchText.Contains("*") -or
    $searchText.Contains("?")
  ) {
    $searchPattern =
    $searchText
  }
  else {
    $searchPattern =
    "*$searchText*"
  }

  Write-AnimatedLine ""

  Write-Info (
    "Pesquisando todas as correspondencias de: " +
    "[$searchText]"
  )
  $rootFolders = @(Get-ChildItem -LiteralPath $FolderPath -Directory -Force -ErrorAction Stop)

  $documentationFolder = $rootFolders |
    Where-Object { $_.Name -like "Documenta*" } |
    Select-Object -First 1

  if ($null -eq $documentationFolder) {

    $visibleFolderNames = @($rootFolders | ForEach-Object { $_.Name })

    throw (
      "A pasta de documentacao nao foi encontrada em '$FolderPath'. " +
      "Pastas visiveis: " + ($visibleFolderNames -join ", ")
    )
  }

  Write-Info "Pasta de documentacao localizada."

  $categoryDefinitions = @(
    [PSCustomObject]@{
      FolderName = "Desenhos Originais"
      DocumentType = "Original"
      DisplayName = "DCA Desenho Original"
    },
    [PSCustomObject]@{
      FolderName = "FP - Ficha de Processo (PDF)"
      DocumentType = "Processo"
      DisplayName = "DCA Processo"
    },
    [PSCustomObject]@{
      FolderName = "Normas Externas"
      DocumentType = "NormaExterna"
      DisplayName = "DCA Norma Externa"
    }
  )

  $documentationSubfolders = @(Get-ChildItem -LiteralPath $documentationFolder.FullName -Directory -Force -ErrorAction Stop)

  $searchFolders = [System.Collections.Generic.List[object]]::new()

  foreach ($categoryDefinition in $categoryDefinitions) {

    $categoryFolder = $documentationSubfolders |
      Where-Object { $_.Name.Trim() -ieq $categoryDefinition.FolderName } |
      Select-Object -First 1

    if ($null -eq $categoryFolder) {
      Write-Warn "Pasta nao encontrada: $($categoryDefinition.FolderName)"
      continue
    }

    $searchFolders.Add(
      [PSCustomObject]@{
        DirectoryPath = $categoryFolder.FullName
        DocumentType = $categoryDefinition.DocumentType
        DisplayName = $categoryDefinition.DisplayName
      }
    )
  }

  if ($searchFolders.Count -eq 0) {

    $visibleSubfolderNames = @($documentationSubfolders | ForEach-Object { $_.Name })

    throw (
      "Nenhuma pasta permitida foi encontrada em " +
      "'$($documentationFolder.FullName)'. Pastas visiveis: " +
      ($visibleSubfolderNames -join ", ")
    )
  }

  $matchingFiles = [System.Collections.Generic.List[object]]::new()

  $knownMatchingPaths =
  [System.Collections.Generic.HashSet[string]]::new(
    [System.StringComparer]::OrdinalIgnoreCase
  )

  $apiEntries = $null
  $vault = Get-DcaVault

  if ($null -ne $vault) {

    Write-Info "Consultando o vault..."

    try {
      $apiEntries =
      @(
        Search-DcaVaultPdfEntries `
          -Vault $vault `
          -SearchText $searchPattern
      )

      Write-Info (
        "Resultados retornados pelo Vault: " +
        $apiEntries.Count
      )
    }
    catch {

      Write-Warn (
        "A busca pela API do PDM falhou: $($_.Exception.Message) " +
        "Usando o sistema de arquivos."
      )

      $apiEntries = $null
    }
  }

  $separator = [string][System.IO.Path]::DirectorySeparatorChar

  foreach ($searchFolder in $searchFolders) {

    if ($null -ne $apiEntries) {

      $categoryPrefix = $searchFolder.DirectoryPath.TrimEnd($separator) + $separator

      $pdfEntries = @(
        $apiEntries |
          Where-Object {
          $_.FullName.StartsWith($categoryPrefix, [System.StringComparison]::OrdinalIgnoreCase)
        } |
          Sort-Object FullName
      )

    }
    else {

      Write-Info ("Consultando {0}..." -f $searchFolder.DisplayName)

      $pdfEntries = @(
        Get-DcaDiskPdfEntries -FolderPath $searchFolder.DirectoryPath |
          Sort-Object FullName
      )
    }

    if ($pdfEntries.Count -eq 0 -and $null -eq $apiEntries) {
      Write-Warn (
        "Nenhum PDF em disco e a API do PDM nao foi usada. " +
        "O conteudo pode existir so no servidor do PDM."
      )
    }

    foreach ($pdfEntry in $pdfEntries) {

      $parsedName = ConvertFrom-PdfFileName `
        -BaseName $pdfEntry.BaseName `
        -DocumentType $searchFolder.DocumentType

      $isMatch = Test-DcaCodeMatch `
        -BaseName $pdfEntry.BaseName `
        -ParsedCode $parsedName.SourceCode `
        -Pattern $searchPattern `
        -UsesWildcard $true

      if (-not $isMatch) {
        continue
      }

      $pdfFullName =
      [string]$pdfEntry.FullName

      if (
        [string]::IsNullOrWhiteSpace(
          $pdfFullName
        )
      ) {
        continue
      }

      if (-not $knownMatchingPaths.Add($pdfFullName)) {
        continue
      }
      $clientRevision =
      [string]$parsedName.ClientRevision

      $pdmState =
      Get-DcaPdmFileState `
        -Entry $pdfEntry

      $matchingFiles.Add(
        [PSCustomObject]@{
          File = $pdfEntry
          SourceCode = $parsedName.SourceCode
          ClientRevision = $clientRevision
          DocumentTitle = $parsedName.DocumentTitle
          DocumentType = $searchFolder.DocumentType
          TypeDisplayName = $searchFolder.DisplayName
          CodeParsed = $parsedName.CodeParsed
          PdmState = $pdmState
        }
      )
    }
  }
  foreach ($matchingFile in $matchingFiles) {

    Update-DcaMatchRevisionFromCard `
      -Match $matchingFile

    Update-DcaMatchDescriptionFromCard `
      -Match $matchingFile
  }
  [int]$matchCount = $matchingFiles.Count

  if ($matchCount -eq 0) {
    throw "Nenhum PDF foi encontrado para a pesquisa '$searchPattern'."
  }

  $script:SearchResultDelayMilliseconds = 30

  if ($matchCount -gt 3) {
    $script:SearchResultDelayMilliseconds = 20
  }

  Write-SearchResultLine ""
  Write-SearchResultLine ("  Resultados da busca ({0} encontrado(s))" -f $matchCount) -Color White
  Write-SearchResultLine ("  Pesquisa: {0}" -f $searchPattern) -Color Gray
  Write-SearchResultLine ("  " + ("-" * 72)) -Color DarkGray

  for (
    $index = 0
    $index -lt $matchCount
    $index++
  ) {

    $number =
    $index + 1

    $currentMatch =
    $matchingFiles[$index]

    $revisionDisplay =
    [string]$currentMatch.ClientRevision

    if (
      [string]::IsNullOrWhiteSpace(
        $revisionDisplay
      )
    ) {

      $revisionDisplay =
      "nao informada"
    }

    $nameDisplay =
    [string]$currentMatch.DocumentTitle

    if (
      [string]::IsNullOrWhiteSpace(
        $nameDisplay
      )
    ) {

      $nameDisplay =
      "nao informado"
    }

    $stateDisplay =
    [string]$currentMatch.PdmState

    if (
      [string]::IsNullOrWhiteSpace(
        $stateDisplay
      )
    ) {

      $stateDisplay =
      "nao informado"
    }

    $stateColor =
    [System.ConsoleColor]::Yellow

    if ($stateDisplay -ieq "Aprovado") {

      $stateColor =
      [System.ConsoleColor]::Green
    }
    elseif ($stateDisplay -ieq "Obsoleto") {

      $stateColor =
      [System.ConsoleColor]::Red
    }
    elseif ($stateDisplay -ieq "Verificado") {

      $stateColor =
      [System.ConsoleColor]::Cyan
    }

    Write-SearchResultLine (
      "  [{0}] {1}" -f
      $number,
      $currentMatch.SourceCode
    ) -Color White

    Write-SearchResultLine (
      "       Nome:    {0}" -f
      $nameDisplay
    ) -Color Gray

    Write-SearchResultLine (
      "       Tipo:    {0}" -f
      $currentMatch.TypeDisplayName
    ) -Color Gray

    Write-SearchResultLine (
      "       Revisao: {0}" -f
      $revisionDisplay
    ) -Color Gray

    Write-SearchResultLine (
      "       Estado:  {0}" -f
      $stateDisplay
    ) -Color $stateColor

    if ($Details) {

      Write-SearchResultLine (
        "       PDF:     {0}" -f
        $currentMatch.File.Name
      ) -Color DarkGray

      Write-SearchResultLine (
        "       Local:   {0}" -f
        $currentMatch.File.FullName
      ) -Color DarkGray
    }

    Write-SearchResultLine ""
  }

  # Este bloco precisa ficar FORA do for acima.
  if ($matchCount -eq 1) {

    Write-Success (
      "O unico PDF encontrado foi selecionado automaticamente."
    )

    return $matchingFiles[0]
  }

  # Esta pergunta tambem precisa ficar FORA do for.
  while ($true) {

    $selectionText =
    Read-Host (
      "Digite numeros separados por virgula, " +
      "um intervalo ou T para todos"
    )

    if (
      [string]::IsNullOrWhiteSpace(
        $selectionText
      )
    ) {

      Write-Warn (
        "Nenhum numero foi informado."
      )

      continue
    }

    $selectionText =
    $selectionText.Trim()

    $selectedNumbers =
    [System.Collections.Generic.List[int]]::new()

    $knownNumbers =
    [System.Collections.Generic.HashSet[int]]::new()

    $selectionIsValid =
    $true

    if (
      $selectionText -ieq "T" -or
      $selectionText -ieq "TODOS"
    ) {

      for (
        $number = 1
        $number -le $matchCount
        $number++
      ) {

        if ($knownNumbers.Add($number)) {

          $selectedNumbers.Add($number)
        }
      }
    }
    else {

      foreach (
        $selectionPart in (
          $selectionText -split ","
        )
      ) {

        $currentPart =
        ([string]$selectionPart).Trim()

        if (
          [string]::IsNullOrWhiteSpace(
            $currentPart
          )
        ) {
          continue
        }

        # Permite intervalo, por exemplo: 1-5.
        if (
          $currentPart -match
          '^(?<Start>\d+)\s*-\s*(?<End>\d+)$'
        ) {

          $rangeStart =
          [int]$Matches["Start"]

          $rangeEnd =
          [int]$Matches["End"]

          if (
            $rangeStart -lt 1 -or
            $rangeEnd -gt $matchCount -or
            $rangeStart -gt $rangeEnd
          ) {

            Write-Warn (
              "Intervalo invalido: '$currentPart'. " +
              "Use valores entre 1 e $matchCount."
            )

            $selectionIsValid =
            $false

            break
          }

          for (
            $rangeNumber = $rangeStart
            $rangeNumber -le $rangeEnd
            $rangeNumber++
          ) {

            if ($knownNumbers.Add($rangeNumber)) {

              $selectedNumbers.Add($rangeNumber)
            }
          }

          continue
        }

        $selectedNumber =
        0

        $validNumber =
        [System.Int32]::TryParse(
          $currentPart,
          [ref]$selectedNumber
        )

        if (
          -not $validNumber -or
          $selectedNumber -lt 1 -or
          $selectedNumber -gt $matchCount
        ) {

          Write-Warn (
            "Selecao invalida: '$currentPart'. " +
            "Digite numeros entre 1 e $matchCount."
          )

          $selectionIsValid =
          $false

          break
        }

        if ($knownNumbers.Add($selectedNumber)) {

          $selectedNumbers.Add($selectedNumber)
        }
      }
    }

    if (-not $selectionIsValid) {
      continue
    }

    if ($selectedNumbers.Count -eq 0) {

      Write-Warn (
        "Nenhum resultado valido foi selecionado."
      )

      continue
    }

    $selectedFiles =
    [System.Collections.Generic.List[object]]::new()

    Write-AnimatedLine ""

    foreach (
      $selectedNumber in (
        $selectedNumbers |
          Sort-Object
      )
    ) {

      $selectedFile =
      $matchingFiles[$selectedNumber - 1]

      $selectedFiles.Add($selectedFile)

      Write-Success (
        "PDF selecionado [$selectedNumber]: " +
        $selectedFile.File.Name
      )

      if ($Details) {

        Write-Info (
          "Local: " +
          $selectedFile.File.FullName
        )
      }
    }

    return $selectedFiles.ToArray()
  }
}
