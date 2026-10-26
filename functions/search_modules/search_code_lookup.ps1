# ============================================================
# PESQUISA E SELECAO POR CODIGO
# ============================================================
#
# Este arquivo pesquisa PDFs pelo codigo informado nas categorias
# DCA permitidas.
#
# A API do Vault possui prioridade porque pode localizar arquivos
# que ainda nao estao presentes no cache local.
#
# Quando a API estiver indisponivel, a pesquisa utiliza os PDFs
# encontrados no sistema de arquivos.
#
# Para cada resultado, o fluxo:
#   1. interpreta o nome do arquivo;
#   2. identifica codigo e revisao;
#   3. consulta o estado no PDM;
#   4. complementa revisao e descricao pelo cartao;
#   5. apresenta os resultados para selecao.
# ============================================================
function Select-DcaPdfByCode {

  param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$FolderPath,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$Code
  )

  # ============================================================
  # 1. VALIDAR A RAIZ E O CODIGO DE PESQUISA
  # ============================================================
  #
  # Confirma se a raiz informada existe e prepara o padrao usado
  # para localizar correspondencias parciais do codigo.
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

  # A pesquisa por codigo e parcial. Quando nenhum curinga e
  # informado, o termo e envolvido automaticamente por asteriscos.
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

  # ============================================================
  # 2. LOCALIZAR A PASTA DE DOCUMENTACAO
  # ============================================================
  #
  # Localiza a pasta principal de documentacao antes de pesquisar
  # as categorias de documentos permitidas pelo fluxo.

  $rootFolders =
  @(
    Get-ChildItem `
      -LiteralPath $FolderPath `
      -Directory `
      -Force `
      -ErrorAction Stop
  )

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

  # ============================================================
  # 3. LOCALIZAR AS CATEGORIAS PERMITIDAS
  # ============================================================
  #
  # Cada configuracao relaciona o nome da pasta no Vault com o
  # tipo interno do documento e o nome apresentado ao usuario.
  #
  # Somente as categorias definidas abaixo participam da pesquisa
  # por codigo.
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
    },
    [PSCustomObject]@{
      FolderName = "FP - XXRE Dimensional"
      DocumentType = "DatasetOnly"
      DisplayName = "XXRE Dimensional - somente Dataset"
    }
  )

  $documentationSubfolders =
  @(
    Get-ChildItem `
      -LiteralPath $documentationFolder.FullName `
      -Directory `
      -Force `
      -ErrorAction Stop
  )

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

  # ============================================================
  # 4. PREPARAR A PESQUISA DOS ARQUIVOS
  # ============================================================
  #
  # Prepara a lista de resultados e o controle utilizado para
  # impedir que o mesmo caminho seja adicionado mais de uma vez.

  $matchingFiles = [System.Collections.Generic.List[object]]::new()

  # A mesma busca pode localizar o arquivo em diferentes etapas.
  # O HashSet garante um unico resultado por caminho completo.
  $knownMatchingPaths =
  [System.Collections.Generic.HashSet[string]]::new(
    [System.StringComparer]::OrdinalIgnoreCase
  )

  # A API do PDM e priorizada porque pode localizar arquivos que
  # ainda nao estao presentes no cache local.
  #
  # Quando a conexao com o Vault nao estiver disponivel ou a
  # pesquisa pela API falhar, o fluxo utiliza os arquivos
  # encontrados no sistema de arquivos.
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

  # ============================================================
  # 5. PESQUISAR OS PDFs EM CADA CATEGORIA
  # ============================================================
  #
  # Utiliza os resultados retornados pela API do PDM quando ela
  # estiver disponivel. Caso contrario, pesquisa diretamente os
  # arquivos locais de cada categoria.
  foreach ($searchFolder in $searchFolders) {

    if ($null -ne $apiEntries) {

      $categoryPrefix =
      $searchFolder.DirectoryPath.TrimEnd(
        $separator
      ) + $separator

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
          TeamcenterItem = $null
          TeamcenterRevision = $null
        }
      )
    }
  }

  # A revisao e a descricao do cartao substituem os valores
  # obtidos apenas pelo nome do arquivo quando estiverem preenchidas.
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

  # Um unico resultado dispensa a etapa de selecao manual.
  if ($matchCount -eq 1) {

    Write-Success (
      "O unico PDF encontrado foi selecionado automaticamente."
    )

    return $matchingFiles[0]
  }

  # Com mais de um resultado, mantem a pergunta em repeticao ate
  # que o usuario informe uma selecao valida.
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
