# ============================================================
# PESQUISA E SELECAO POR PASTA
# ============================================================
#
# Este arquivo localiza pastas dentro da area de Documentacao,
# identifica a categoria DCA e prepara os PDFs encontrados.
#
# Categorias reconhecidas:
#   1. Desenhos Originais;
#   2. Ficha de Processo;
#   3. Normas Externas;
#   4. XXRE Dimensional.
#
# O fluxo:
#   1. valida a raiz informada;
#   2. interpreta o modo de pesquisa;
#   3. localiza a raiz Documentacao;
#   4. identifica as pastas correspondentes;
#   5. consulta os PDFs pelo Vault ou pelo disco;
#   6. prepara os documentos encontrados;
#   7. apresenta as pastas para selecao;
#   8. retorna os documentos escolhidos.
#
# Nenhum Item, revisao ou Dataset e criado por esta funcao.
# ============================================================

function Select-DcaPdfsByFolder {

  # Localiza pastas pelo nome completo dentro da area de
  # Documentacao e identifica o tipo DCA pela categoria.
  #
  # Quando ListFolderItems estiver ativo, a pasta escolhida sera
  # aberta para navegacao e selecao individual dos documentos.
  param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$FolderPath,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$FolderSearch,

    [switch]$ListFolderItems
  )

  # ============================================================
  # 1. VALIDAR A RAIZ DE PESQUISA
  # ============================================================
  if (-not (
      Test-Path `
        -LiteralPath $FolderPath `
        -PathType Container
    )) {

    throw "Vault DCA nao encontrado em '$FolderPath'."
  }

  # ============================================================
  # 2. INTERPRETAR O MODO E O NOME DA PASTA
  # ============================================================
  #
  # Get-DcaFolderSearchMode identifica se a pesquisa apenas
  # retorna os documentos ou abre a navegacao interna da pasta.
  #
  # Get-DcaFolderSearchPattern remove o prefixo da pesquisa e
  # valida o nome completo informado.
  $folderSearchMode =
  Get-DcaFolderSearchMode `
    -SearchText $FolderSearch

  $folderSearchText =
  ([string]$folderSearchMode.SearchText).Trim()

  $folderPattern =
  Get-DcaFolderSearchPattern `
    -SearchText $FolderSearch

  # ============================================================
  # 3. LOCALIZAR A RAIZ DOCUMENTACAO
  # ============================================================
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

  # Normaliza o caminho completo e remove a barra final para
  # permitir comparacoes consistentes com as subpastas.
  $documentationRootPath =
  [System.IO.Path]::GetFullPath(
    $documentationFolder.FullName
  ).TrimEnd("\")

  # ============================================================
  # 4. DEFINIR AS CATEGORIAS DCA PERMITIDAS
  # ============================================================
  #
  # O primeiro nivel abaixo de Documentacao determina o tipo
  # utilizado posteriormente na criacao do Item e da revisao.
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

    [PSCustomObject]@{
      FolderName = "FP - XXRE Dimensional"
      DocumentType = "DatasetOnly"
      DisplayName = "XXRE Dimensional - somente Dataset"
    }
  )

  # ============================================================
  # 5. LOCALIZAR AS PASTAS CORRESPONDENTES
  # ============================================================
  #
  # A busca e recursiva, mas cada pasta encontrada permanece
  # como uma opcao independente.
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

    # Ignora caminhos que, depois da normalizacao, nao estejam
    # realmente abaixo da raiz Documentacao.
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

    # A correspondencia exige o nome exato da pasta ou o caminho
    # relativo completo informado pelo usuario.
    $folderMatches =
    $availableFolder.Name -ieq $folderPattern -or
    $relativePath -ieq $folderPattern

    if (-not $folderMatches) {
      continue
    }

    # Identifica a categoria pelo primeiro nivel abaixo da pasta
    # Documentacao. Pastas fora das categorias conhecidas nao
    # podem ser transformadas em documentos DCA.
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
      "Nenhuma pasta DCA foi encontrada com o nome " +
      "'$folderSearchText' dentro de Documentacao."
    )
  }

  # ============================================================
  # 6. RESOLVER PASTAS COM O MESMO NOME
  # ============================================================
  #
  # Quando a navegacao de documentos localizar mais de uma pasta
  # com o mesmo nome, o usuario escolhe uma delas antes da leitura
  # dos PDFs e dos cartoes do PDM.
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

      # Mantem somente a pasta escolhida para impedir consultas
      # desnecessarias aos PDFs e cartoes das demais pastas.
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
  # 7. OBTER A CONEXAO COM O VAULT
  # ============================================================
  #
  # A conexao e reutilizada durante a preparacao das pastas.
  # Quando a API estiver indisponivel, os PDFs serao pesquisados
  # diretamente no sistema de arquivos.
  $vault =
  Get-DcaVault

  if ($null -eq $vault) {

    Write-Warn (
      "API do PDM indisponivel. " +
      "A pesquisa sera feita nos arquivos locais."
    )
  }

  # ============================================================
  # 8. PREPARAR OS DOCUMENTOS DE CADA PASTA
  # ============================================================
  $folderOptions =
  [System.Collections.Generic.List[object]]::new()

  foreach ($matchingFolder in $matchingFolders) {

    # A lista sera preenchida pelo Vault ou pelo sistema de
    # arquivos, conforme a disponibilidade da API.
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

      # A pesquisa do PDM pode retornar arquivos das subpastas.
      # Mantemos somente os PDFs diretamente dentro da pasta
      # que esta sendo preparada.
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

      # Sem uma conexao com o Vault, utiliza somente os PDFs
      # existentes diretamente no sistema de arquivos.
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

    # ============================================================
    # 9. TRANSFORMAR OS PDFS EM DOCUMENTOS DCA
    # ============================================================
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

    # Depois da interpretacao do nome, complementa cada documento
    # com a revisao e a descricao encontradas no cartao do PDM.
    #
    # Os valores do cartao possuem prioridade sobre os valores
    # extraidos somente do nome fisico do PDF.
    foreach ($folderDocument in $folderDocuments) {

      Update-DcaMatchRevisionFromCard `
        -Match $folderDocument

      Update-DcaMatchDescriptionFromCard `
        -Match $folderDocument
    }

    # Pastas sem PDFs diretamente dentro delas nao sao adicionadas
    # como opcoes de selecao.
    if ($folderDocuments.Count -eq 0) {
      continue
    }

    # ============================================================
    # 10. CALCULAR O RESUMO DA PASTA
    # ============================================================
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

  # ============================================================
  # 11. VALIDAR E ORDENAR AS OPCOES DE PASTA
  # ============================================================
  if ($folderOptions.Count -eq 0) {

    throw (
      "As pastas encontradas para '\$folderPattern' " +
      "nao possuem PDFs diretamente dentro delas."
    )
  }

  # Ordena as pastas pelo caminho relativo para manter uma
  # apresentacao previsivel entre execucoes.
  $folderOptions =
  @(
    $folderOptions |
      Sort-Object RelativePath
  )

  # A numeracao e aplicada somente depois da ordenacao.
  for (
    $index = 0
    $index -lt $folderOptions.Count
    $index++
  ) {

    $folderOptions[$index].Number =
    $index + 1
  }

  # ============================================================
  # 12. SELECIONAR AUTOMATICAMENTE UMA PASTA UNICA
  # ============================================================
  #
  # Quando somente uma pasta for encontrada, nao e necessario
  # solicitar que o usuario selecione a mesma pasta novamente.
  if ($folderOptions.Count -eq 1) {

    $selectedFolder =
    $folderOptions[0]

    # No modo de importacao completa, retorna todos os documentos
    # preparados diretamente dentro da pasta.
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

    # No modo de navegacao, abre a pasta para permitir a selecao
    # individual dos documentos e das subpastas.
    if ($ListFolderItems) {

      $selectedDocuments =
      Select-DcaDocumentsWithFolderNavigation `
        -RootFolderOption $selectedFolder

      return @($selectedDocuments)
    }

    return $selectedFolder.Documents
  }

  # ============================================================
  # 13. APRESENTAR AS PASTAS PARA SELECAO
  # ============================================================
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
  # ============================================================
  # 14. RECEBER E VALIDAR A SELECAO DAS PASTAS
  # ============================================================

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

    # Armazena os numeros validos na ordem em que forem lidos.
    $selectedNumbers =
    [System.Collections.Generic.List[int]]::new()

    # Impede que uma pasta seja adicionada mais de uma vez quando
    # numeros e intervalos estiverem sobrepostos.
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

        # Verifica primeiro se a parte atual representa um
        # intervalo numerico, por exemplo 1-3.
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

    # A navegacao interna pode abrir somente uma pasta por vez.
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

    # ============================================================
    # 15. ABRIR A PASTA ESCOLHIDA PARA SELECAO DOS DOCUMENTOS
    # ============================================================
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

      # NULL indica que o usuario solicitou o retorno para a lista
      # de pastas. Nesse caso, o ciclo de selecao e reapresentado.
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
    # 16. REUNIR OS DOCUMENTOS DAS PASTAS SELECIONADAS
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

        # O caminho completo e utilizado como identificador unico
        # do PDF durante a montagem do lote.
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

    # ============================================================
    # 17. RETORNAR OS DOCUMENTOS REUNIDOS
    # ============================================================
    return $selectedDocuments.ToArray()
  }
}
