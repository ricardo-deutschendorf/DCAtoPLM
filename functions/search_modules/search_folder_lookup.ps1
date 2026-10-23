# ============================================================
# PESQUISA E SELECAO POR PASTA
# ============================================================
#
# Este arquivo localiza pastas dentro da area de Documentacao
# e identifica o tipo de documento conforme a categoria DCA.
#
# Categorias reconhecidas:
#   1. Desenhos Originais;
#   2. Ficha de Processo;
#   3. Normas Externas;
#   4. XXRE Dimensional.
#
# O fluxo:
#   1. localiza a raiz Documentacao;
#   2. identifica as pastas correspondentes;
#   3. consulta os PDFs pelo Vault ou pelo disco;
#   4. prepara os documentos encontrados;
#   5. apresenta as pastas para selecao;
#   6. retorna os documentos escolhidos.
# ============================================================
function Select-DcaPdfsByFolder {

  # Localiza pastas dentro da raiz Documentacao, identifica o
  # tipo DCA pela categoria e prepara os PDFs encontrados.
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

  # Distingue curingas informados pelo usuario dos curingas
  # adicionados automaticamente pela pesquisa parcial.
  $folderSearchMode =
  Get-DcaFolderSearchMode `
    -SearchText $FolderSearch

  $folderSearchText =
  ([string]$folderSearchMode.SearchText).Trim()

  $folderPattern =
  Get-DcaFolderSearchPattern `
    -SearchText $FolderSearch

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

  # ============================================================
  # CATEGORIAS DCA PERMITIDAS
  # ============================================================
  #
  # O primeiro nivel abaixo de Documentacao define o tipo que sera
  # utilizado na criacao do Item e da revisao no Teamcenter.
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
    },
    [PSCustomObject]@{
      FolderName = "FP - XXRE Dimensional"
      DocumentType = "DatasetOnly"
      DisplayName = "XXRE Dimensional - somente Dataset"
    }
  )

  # ============================================================
  # PESQUISA DAS PASTAS
  # ============================================================
  #
  # A busca e recursiva, mas cada pasta encontrada e tratada como
  # uma opcao independente.
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

    # A pasta deve possuir exatamente o nome informado ou o caminho
    # relativo completo informado pelo usuario.
    $folderMatches =
    $availableFolder.Name -ieq $folderPattern -or
    $relativePath -ieq $folderPattern

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
      "Nenhuma pasta DCA foi encontrada contendo " +
      "'$folderSearchText' dentro de Documentacao."
    )
  }

  # Quando a pesquisa para abrir os documentos encontra mais de uma
  # pasta com o mesmo nome, permite escolher a pasta antes de consultar
  # os PDFs e os cartoes do PDM.
  if (
    $ListFolderItems -and
    $matchingFolders.Count -gt 1
  ) {

    Write-AnimatedLine ""

    Write-Host (
      "  Foram encontradas varias pastas com o nome " +
      "'$folderPattern':"
    ) -ForegroundColor Cyan

    Write-Host (
      "  " + ("-" * 68)
    ) -ForegroundColor DarkGray

    for (
      $folderIndex = 0
      $folderIndex -lt $matchingFolders.Count
      $folderIndex++
    ) {

      $folderOption =
      $matchingFolders[$folderIndex]

      Write-Host (
        "  [{0}] {1}" -f
        ($folderIndex + 1),
        $folderOption.RelativePath
      ) -ForegroundColor White

      Write-Host (
        "      Tipo: {0}" -f
        $folderOption.DisplayName
      ) -ForegroundColor Gray

      Write-Host ""
    }

    while ($true) {

      $selectedFolderText =
      Read-Host (
        "Digite o numero da pasta que deseja abrir"
      )

      $selectedFolderNumber =
      0

      $validFolderNumber =
      [System.Int32]::TryParse(
        $selectedFolderText,
        [ref]$selectedFolderNumber
      )

      if (
        -not $validFolderNumber -or
        $selectedFolderNumber -lt 1 -or
        $selectedFolderNumber -gt $matchingFolders.Count
      ) {

        Write-Warn (
          "Selecao invalida. Digite um numero entre 1 e " +
          "$($matchingFolders.Count)."
        )

        continue
      }

      $selectedMatchingFolder =
      $matchingFolders[$selectedFolderNumber - 1]

      Write-AnimatedLine ""

      Write-Success (
        "Pasta escolhida [$selectedFolderNumber]: " +
        $selectedMatchingFolder.RelativePath
      )

      # Mantem somente a pasta selecionada. A consulta dos PDFs e dos
      # cartoes ocorrera apenas para essa pasta.
      $matchingFolders =
      @(
        $selectedMatchingFolder
      )

      break
    }
  }

  Write-AnimatedLine ""

  Write-Info (
    "Localizando a pasta com o nome exato: " +
    "'$folderPattern'"
  )

  # ============================================================
  # CONEXAO COM O VAULT
  # ============================================================

  # A conexao e reutilizada, mas os PDFs serao consultados somente
  # nas pastas correspondentes ao termo pesquisado.
  $vault =
  Get-DcaVault

  if ($null -eq $vault) {

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

      if ($Details) {

        Write-Info (
          "Consultando PDFs da pasta: " +
          $matchingFolder.RelativePath
        )
      }

      $folderSearchResults =
      @(
        Search-DcaVaultPdfEntries `
          -Vault $vault `
          -SearchText "*" `
          -StartFolderPath $matchingFolder.FullName
      )

      # O PDM pode retornar resultados das subpastas. Mantemos
      # somente os PDFs diretamente dentro da pasta atual.
      $folderPdfEntries =
      @(
        $folderSearchResults |
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

          $pdfDirectory -ieq
          $matchingFolder.FullName
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
          TeamcenterItem = $null
          TeamcenterRevision = $null
        }
      )
    }

    # Depois de montar os resultados basicos, complementa cada
    # documento com revisao e descricao lidas do cartao do PDM.
    foreach ($folderDocument in $folderDocuments) {

      Update-DcaMatchRevisionFromCard `
        -Match $folderDocument

      Update-DcaMatchDescriptionFromCard `
        -Match $folderDocument
    }

    # Pastas sem PDFs diretamente dentro delas nao sao exibidas.
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

  # ============================================================
  # SELECAO AUTOMATICA DE PASTA EXATA
  # ============================================================
  #
  # Quando a pesquisa nao usa curinga e retorna apenas uma pasta,
  # nao e necessario pedir que o usuario selecione a mesma pasta.
  if ($folderOptions.Count -eq 1) {

    $selectedFolder =
    $folderOptions[0]

    if (-not $ListFolderItems) {

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
    }

    if ($ListFolderItems) {

      $selectedDocuments =
      Select-DcaDocumentsWithFolderNavigation `
        -RootFolderOption $selectedFolder

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

    # ============================================================
    # UNIAO DOS DOCUMENTOS DAS PASTAS SELECIONADAS
    # ============================================================
    #
    # O HashSet de caminhos impede que o mesmo PDF seja adicionado
    # mais de uma vez ao lote.
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
