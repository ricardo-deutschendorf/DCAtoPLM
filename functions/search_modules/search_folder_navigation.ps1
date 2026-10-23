# ============================================================
# NAVEGACAO ENTRE PASTAS E DOCUMENTOS
# ============================================================
#
# Este arquivo permite navegar pelas subpastas de uma categoria
# DCA e selecionar os documentos que serao adicionados ao lote.
#
# A navegacao permite:
#   1. abrir uma subpasta;
#   2. voltar para a pasta anterior;
#   3. selecionar um documento;
#   4. selecionar varios documentos;
#   5. selecionar todos os documentos da pasta atual;
#   6. sair sem selecionar.
#
# A pilha de navegacao mantem o historico das pastas visitadas.
# Os documentos da pasta atual sao carregados pela funcao
# Get-DcaDocumentsFromFolderPath.
#
# Nenhum arquivo e alterado ou importado por esta funcao.
# ============================================================

function Select-DcaDocumentsWithFolderNavigation {

  # Navega pelas pastas abaixo da raiz informada e apresenta
  # os PDFs existentes diretamente na pasta atual.
  #
  # A funcao retorna:
  #   - um array com os documentos selecionados;
  #   - um array vazio quando o usuario solicitar a saida.
  param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNull()]
    $RootFolderOption
  )

  # ============================================================
  # 1. INICIALIZAR A NAVEGACAO
  # ============================================================
  #
  # A conexao com o Vault e reutilizada durante toda a navegacao.
  # Quando a API estiver indisponivel, os documentos serao
  # pesquisados diretamente no sistema de arquivos.
  $vault =
  Get-DcaVault

  # A pilha armazena as pastas anteriores. Cada vez que uma
  # subpasta e aberta, a pasta atual e adicionada na pilha.
  $navigationStack =
  [System.Collections.Generic.Stack[object]]::new()

  # A navegacao inicia na pasta recebida pelo parametro.
  $currentFolder =
  $RootFolderOption

  # ============================================================
  # 2. EXECUTAR O CICLO DE NAVEGACAO
  # ============================================================
  #
  # O ciclo continua ate que o usuario selecione documentos
  # ou solicite a saida.
  while ($true) {

    # ============================================================
    # 3. CARREGAR AS SUBPASTAS DA PASTA ATUAL
    # ============================================================
    #
    # Somente as subpastas diretamente abaixo da pasta atual
    # sao exibidas nesta etapa.
    $childFolders =
    @(
      Get-ChildItem `
        -LiteralPath $currentFolder.FullName `
        -Directory `
        -Force `
        -ErrorAction SilentlyContinue |
        Sort-Object Name
    )

    # ============================================================
    # 4. CARREGAR OS DOCUMENTOS DA PASTA ATUAL
    # ============================================================
    #
    # Get-DcaDocumentsFromFolderPath retorna somente os PDFs
    # diretamente dentro da pasta atual. As subpastas permanecem
    # disponíveis para navegacao separadamente.
    $documents =
    @(
      Get-DcaDocumentsFromFolderPath `
        -FolderOption $currentFolder `
        -Vault $vault
    )

    # ============================================================
    # 5. APRESENTAR A PASTA ATUAL
    # ============================================================
    Write-AnimatedLine ""

    Write-Host (
      "  Pasta atual: \{0}" -f
      $currentFolder.RelativePath
    ) -ForegroundColor Cyan

    Write-Host (
      "  Tipo: {0}" -f
      $currentFolder.DisplayName
    ) -ForegroundColor Gray

    Write-Host (
      "  Subpastas: {0} | Documentos: {1}" -f
      $childFolders.Count,
      $documents.Count
    ) -ForegroundColor Gray

    Write-Host (
      "  " + ("-" * 72)
    ) -ForegroundColor DarkGray

    # A tabela e apresentada somente quando a pasta atual possui
    # pelo menos uma subpasta ou um documento.
    if (
      $childFolders.Count -gt 0 -or
      $documents.Count -gt 0
    ) {

      Write-Host (
        "  Itens encontrados:"
      ) -ForegroundColor Cyan

      Write-Host (
        "  " + ("-" * 104)
      ) -ForegroundColor DarkGray

      Write-Host (
        "  {0,-7} {1,-44} {2,-9} {3,-15} {4}" -f
        "Item",
        "Codigo",
        "Tipo",
        "Revisao",
        "Estado"
      ) -ForegroundColor White

      Write-Host (
        "  {0,-7} {1,-44} {2,-9} {3,-15} {4}" -f
        ("-" * 5),
        ("-" * 42),
        ("-" * 7),
        ("-" * 13),
        ("-" * 20)
      ) -ForegroundColor DarkGray

      # ============================================================
      # 6. APRESENTAR AS SUBPASTAS
      # ============================================================
      #
      # As pastas sao identificadas pelo prefixo P e aparecem
      # antes dos documentos.
      for (
        $folderIndex = 0
        $folderIndex -lt $childFolders.Count
        $folderIndex++
      ) {

        $folderNumber =
        "P" + ($folderIndex + 1)

        $folderName =
        [string]$childFolders[$folderIndex].Name

        $folderNameDisplay =
        $folderName

        # Limita o nome para preservar o alinhamento da tabela.
        if ($folderNameDisplay.Length -gt 44) {

          $folderNameDisplay =
          $folderNameDisplay.Substring(
            0,
            41
          ) + "..."
        }

        Write-Host (
          "  {0,-7} {1,-44} {2,-9} {3,-15} {4}" -f
          $folderNumber,
          $folderNameDisplay,
          "Pasta",
          "-",
          "-"
        ) -ForegroundColor Cyan
      }

      # ============================================================
      # 7. APRESENTAR OS DOCUMENTOS
      # ============================================================
      #
      # Os documentos sao identificados pelo prefixo D e aparecem
      # depois das subpastas.
      for (
        $documentIndex = 0
        $documentIndex -lt $documents.Count
        $documentIndex++
      ) {

        $document =
        $documents[$documentIndex]

        $documentNumber =
        "D" + ($documentIndex + 1)

        # Usa o nome base do arquivo quando o codigo nao tiver
        # sido identificado durante a preparacao do documento.
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

        $sourceCodeDisplay =
        $sourceCode

        # Limita o codigo para preservar o alinhamento da tabela.
        if ($sourceCodeDisplay.Length -gt 44) {

          $sourceCodeDisplay =
          $sourceCodeDisplay.Substring(
            0,
            41
          ) + "..."
        }

        # Apresenta um texto alternativo quando a revisao nao
        # estiver disponivel no nome ou no cartao do PDM.
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

        # Limita a revisao para preservar o alinhamento da tabela.
        if ($revisionDisplay.Length -gt 15) {

          $revisionDisplay =
          $revisionDisplay.Substring(
            0,
            12
          ) + "..."
        }

        # Apresenta um texto alternativo quando o estado do PDM
        # nao puder ser consultado.
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

        # ============================================================
        # 8. DEFINIR A COR DO ESTADO
        # ============================================================
        #
        # As cores sao apenas visuais. A decisao sobre workflows
        # ocorre posteriormente no fluxo principal.

        $stateColor =
        [System.ConsoleColor]::Yellow

        if ($stateDisplay -ieq "Aprovado") {

          $stateColor =
          [System.ConsoleColor]::Green
        }
        elseif ($stateDisplay -ieq "Verificado") {

          $stateColor =
          [System.ConsoleColor]::Cyan
        }
        elseif ($stateDisplay -ieq "Obsoleto") {

          $stateColor =
          [System.ConsoleColor]::Red
        }
        elseif ($stateDisplay -ieq "Corrigir") {

          $stateColor =
          [System.ConsoleColor]::Magenta
        }
        elseif (
          $stateDisplay -ieq "Em verificacao" -or
          $stateDisplay -ieq "Em verificação"
        ) {

          $stateColor =
          [System.ConsoleColor]::DarkCyan
        }
        elseif (
          $stateDisplay -ieq "Em elaboracao" -or
          $stateDisplay -ieq "Em elaboração"
        ) {

          $stateColor =
          [System.ConsoleColor]::DarkYellow
        }
        elseif (
          $stateDisplay -ieq "Em revisao" -or
          $stateDisplay -ieq "Em revisão"
        ) {

          $stateColor =
          [System.ConsoleColor]::Blue
        }

        Write-Host (
          "  {0,-7} {1,-44} {2,-9} {3,-15} " -f
          $documentNumber,
          $sourceCodeDisplay,
          "Item",
          $revisionDisplay
        ) -ForegroundColor Gray -NoNewline

        Write-Host (
          $stateDisplay
        ) -ForegroundColor $stateColor

        # No modo Details, apresenta o titulo e o nome fisico
        # do PDF alem das informacoes resumidas da tabela.
        if ($Details) {

          $documentTitle =
          [string]$document.DocumentTitle

          if (
            [string]::IsNullOrWhiteSpace(
              $documentTitle
            )
          ) {

            $documentTitle =
            "nao informado"
          }

          Write-Host (
            "          Nome:    {0}" -f
            $documentTitle
          ) -ForegroundColor DarkGray

          Write-Host (
            "          Arquivo: {0}" -f
            $document.File.Name
          ) -ForegroundColor DarkGray
        }
      }

      Write-Host (
        "  " + ("-" * 104)
      ) -ForegroundColor DarkGray

      Write-Host ""
    }

    # Informa quando a pasta atual nao possui itens navegaveis.
    if (
      $childFolders.Count -eq 0 -and
      $documents.Count -eq 0
    ) {

      Write-Warn (
        "A pasta atual nao possui subpastas nem documentos."
      )
    }

    # ============================================================
    # 9. APRESENTAR AS OPCOES DISPONIVEIS
    # ============================================================
    Write-Host (
      "  Opcoes disponiveis:"
    ) -ForegroundColor Cyan

    if ($childFolders.Count -gt 0) {

      Write-Host (
        "    P1              abrir a pasta P1"
      ) -ForegroundColor DarkGray
    }

    if ($documents.Count -gt 0) {

      Write-Host (
        "    D1              selecionar o documento D1"
      ) -ForegroundColor DarkGray

      Write-Host (
        "    D1,D3,D5        selecionar varios documentos"
      ) -ForegroundColor DarkGray

      Write-Host (
        "    D1-D5           selecionar um intervalo"
      ) -ForegroundColor DarkGray

      Write-Host (
        "    T               selecionar todos os documentos"
      ) -ForegroundColor DarkGray
    }

    if ($navigationStack.Count -gt 0) {

      Write-Host (
        "    V               voltar para a pasta anterior"
      ) -ForegroundColor DarkGray
    }

    Write-Host (
      "    S               sair sem selecionar"
    ) -ForegroundColor DarkGray

    Write-Host ""

    # ============================================================
    # 10. RECEBER E NORMALIZAR A OPCAO
    # ============================================================
    $selection =
    Read-Host (
      "Digite a opcao"
    )

    if (
      [string]::IsNullOrWhiteSpace(
        $selection
      )
    ) {

      Write-Warn "Nenhuma opcao foi informada."
      continue
    }

    $selection =
    $selection.Trim()

    # S ou SAIR encerra a navegacao e retorna um array vazio.
    if (
      $selection -ieq "S" -or
      $selection -ieq "SAIR"
    ) {
      return @()
    }

    # V ou VOLTAR recupera a pasta anterior armazenada na pilha.
    if (
      $selection -ieq "V" -or
      $selection -ieq "VOLTAR"
    ) {

      if ($navigationStack.Count -eq 0) {

        Write-Warn "Nao existe uma pasta anterior."
        continue
      }

      $currentFolder =
      $navigationStack.Pop()

      continue
    }

    # T ou TODOS retorna todos os documentos da pasta atual.
    if (
      $selection -ieq "T" -or
      $selection -ieq "TODOS"
    ) {

      if ($documents.Count -eq 0) {

        Write-Warn (
          "A pasta atual nao possui documentos para selecionar."
        )

        continue
      }

      return $documents
    }

    # ============================================================
    # 11. ABRIR UMA SUBPASTA
    # ============================================================
    #
    # Uma entrada iniciada por P representa uma subpasta.
    # Exemplo:
    #   P1
    if (
      $selection -match
      '^(?i:P)(?<Number>\d+)$'
    ) {

      # O grupo nomeado Number contem o indice informado depois
      # do prefixo P.
      $selectedFolderNumber =
      [int]$Matches["Number"]

      if (
        $selectedFolderNumber -lt 1 -or
        $selectedFolderNumber -gt $childFolders.Count
      ) {

        Write-Warn (
          "Pasta invalida. Use um numero entre 1 e " +
          "$($childFolders.Count)."
        )

        continue
      }

      $selectedChildFolder =
      $childFolders[$selectedFolderNumber - 1]

      $childFullPath =
      [System.IO.Path]::GetFullPath(
        $selectedChildFolder.FullName
      ).TrimEnd("\")

      # Calcula o caminho relativo da subpasta em relacao a pasta
      # raiz utilizada para iniciar a navegacao.
      $childRelativePath =
      $childFullPath.Substring(
        $RootFolderOption.FullName.Length
      ).TrimStart("\")

      if (
        [string]::IsNullOrWhiteSpace(
          $childRelativePath
        )
      ) {
        $childRelativePath =
        $selectedChildFolder.Name
      }
      else {
        $childRelativePath =
        $RootFolderOption.RelativePath +
        "\" +
        $childRelativePath
      }

      # Armazena a pasta atual antes de abrir a subpasta. Esse
      # valor sera utilizado pela opcao VOLTAR.
      $navigationStack.Push(
        $currentFolder
      )

      # Prepara a nova pasta atual preservando a categoria e o
      # tipo de documento definidos na raiz.
      $currentFolder =
      [PSCustomObject]@{
        Name = $selectedChildFolder.Name
        RelativePath = $childRelativePath
        FullName = $childFullPath
        CategoryFolder = $RootFolderOption.CategoryFolder
        DocumentType = $RootFolderOption.DocumentType
        DisplayName = $RootFolderOption.DisplayName
      }

      continue
    }

    # ============================================================
    # 12. INTERPRETAR A SELECAO DOS DOCUMENTOS
    # ============================================================
    #
    # Depois que as opcoes de navegacao forem descartadas, a
    # entrada restante e interpretada como selecao de documentos.
    $documentSelection =
    $selection -replace '(?i)(^|,)\s*D', '$1'

    # Armazena os numeros validos na ordem em que forem encontrados.
    $selectedNumbers =
    [System.Collections.Generic.List[int]]::new()

    # Impede que o mesmo documento seja adicionado mais de uma vez
    # quando numeros e intervalos estiverem sobrepostos.
    $knownNumbers =
    [System.Collections.Generic.HashSet[int]]::new()

    $selectionIsValid =
    $true

    foreach (
      $selectionPart in (
        $documentSelection -split ","
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

      # Verifica primeiro se a parte atual representa um intervalo,
      # por exemplo D1-D5 ou 1-5.
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
            "Intervalo de documentos invalido: '$currentPart'."
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

      # Quando a parte atual nao e um intervalo, tenta interpretar
      # o valor como um numero individual.
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
          "Documento invalido: '$currentPart'."
        )

        $selectionIsValid =
        $false

        break
      }

      if ($knownNumbers.Add($selectedNumber)) {
        $selectedNumbers.Add($selectedNumber)
      }
    }

    if (-not $selectionIsValid) {
      continue
    }

    if ($selectedNumbers.Count -eq 0) {

      Write-Warn (
        "Use Pnumero para abrir uma pasta ou Dnumero para " +
        "selecionar documentos."
      )

      continue
    }

    # ============================================================
    # 13. MONTAR O RETORNO DA SELECAO
    # ============================================================
    $selectedDocuments =
    [System.Collections.Generic.List[object]]::new()

    # Ordena os numeros antes de montar o resultado para manter
    # a mesma ordem visual apresentada ao usuario.
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
        "PDF selecionado [D$selectedNumber]: " +
        $selectedDocument.File.Name
      )
    }

    # ============================================================
    # 14. RETORNAR OS DOCUMENTOS SELECIONADOS
    # ============================================================
    return $selectedDocuments.ToArray()
  }
}
