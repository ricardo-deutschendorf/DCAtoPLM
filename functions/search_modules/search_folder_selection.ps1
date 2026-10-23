# ============================================================
# SELECAO DOS DOCUMENTOS DE UMA PASTA
# ============================================================
#
# Este arquivo apresenta os documentos previamente preparados
# para uma pasta e permite selecionar os PDFs do lote.
#
# Formas de selecao aceitas:
#   1. numero individual;
#   2. numeros separados por virgula;
#   3. intervalo numerico;
#   4. todos os documentos;
#   5. retorno para a lista de pastas, quando permitido.
#
# O fluxo:
#   1. ordena os documentos;
#   2. apresenta codigo, nome, revisao e estado;
#   3. recebe e interpreta a entrada do usuario;
#   4. valida numeros e intervalos;
#   5. remove selecoes repetidas;
#   6. retorna os documentos selecionados.
#
# Nenhum arquivo e alterado ou importado por esta funcao.
# ============================================================

function Select-DcaDocumentsFromFolder {

  # Exibe os documentos encontrados na pasta e permite selecionar
  # resultados individuais, listas, intervalos ou todos os PDFs.
  #
  # Quando AllowBack estiver ativo, o usuario tambem pode retornar
  # para a selecao de pastas sem escolher nenhum documento.
  param(
    [Parameter(Mandatory = $true)]
    $FolderOption,

    [switch]$AllowBack
  )

  # ============================================================
  # 1. ORDENAR E VALIDAR OS DOCUMENTOS
  # ============================================================
  #
  # A ordenacao mantem os resultados previsiveis entre execucoes:
  # primeiro pelo codigo e depois pelo nome fisico do PDF.
  $documents =
  @(
    $FolderOption.Documents |
      Sort-Object {
      [string]$_.SourceCode
    }, {
      [string]$_.File.Name
    }
  )

  # Uma pasta sem PDFs nao abre a tela de selecao.
  if ($documents.Count -eq 0) {
    Write-Warn (
      "A pasta '$($FolderOption.RelativePath)' nao possui PDFs."
    )

    return $null
  }

  # ============================================================
  # 2. APRESENTAR E VALIDAR A SELECAO
  # ============================================================
  #
  # O ciclo permanece ativo ate que o usuario:
  #   1. selecione documentos validos;
  #   2. solicite o retorno para a lista de pastas.
  while ($true) {

    # ============================================================
    # 3. APRESENTAR A PASTA ATUAL
    # ============================================================
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

    # ============================================================
    # 4. APRESENTAR OS DOCUMENTOS DISPONIVEIS
    # ============================================================
    for (
      $index = 0
      $index -lt $documents.Count
      $index++
    ) {

      $document =
      $documents[$index]

      $number =
      $index + 1

      # Prepara os valores apresentados no console.
      #
      # Quando uma informacao nao estiver preenchida, utiliza um
      # texto alternativo para evitar linhas vazias na listagem.
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

      # A cor serve somente para destacar visualmente o estado.
      # A decisao sobre workflow ocorre posteriormente no fluxo
      # principal e nao e alterada por essa apresentacao.
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

      if ($Details) {

        $revisionSourceDisplay =
        [string]$document.RevisionSource

        if (
          [string]::IsNullOrWhiteSpace(
            $revisionSourceDisplay
          )
        ) {

          $revisionSourceDisplay =
          "nome do arquivo"
        }

        Write-Host (
          "       Fonte:   {0}" -f
          $revisionSourceDisplay
        ) -ForegroundColor DarkGray
      }

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

    # ============================================================
    # 5. APRESENTAR AS OPCOES DE SELECAO
    # ============================================================
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

    # ============================================================
    # 6. RECEBER A ENTRADA DO USUARIO
    # ============================================================
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

    # Quando o retorno estiver permitido, V ou VOLTAR devolve
    # NULL para que a funcao chamadora reapresente as pastas.
    if (
      $AllowBack -and
      (
        $selectionText -ieq "V" -or
        $selectionText -ieq "VOLTAR"
      )
    ) {
      return $null
    }

    # ============================================================
    # 7. INTERPRETAR A SELECAO INFORMADA
    # ============================================================
    #
    # A selecao aceita:
    #   1. um numero;
    #   2. numeros separados por virgula;
    #   3. intervalos;
    #   4. T ou TODOS;
    #   5. o caractere curinga usado para selecionar todos.
    $selectedNumbers =
    [System.Collections.Generic.List[int]]::new()

    # O HashSet impede que o mesmo numero seja adicionado duas
    # vezes quando a entrada combinar selecoes sobrepostas.
    #
    # Exemplo:
    #   1,2,1-5
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

        # Verifica primeiro se a parte atual representa um
        # intervalo numerico, por exemplo 1-5.
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

        # Quando a entrada nao e um intervalo, tenta interpretar
        # a parte atual como um numero individual.
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

    # ============================================================
    # 8. MONTAR A LISTA DE DOCUMENTOS SELECIONADOS
    # ============================================================
    $selectedDocuments =
    [System.Collections.Generic.List[object]]::new()

    Write-AnimatedLine ""

    # Os numeros sao ordenados antes da montagem do retorno para
    # manter a mesma ordem visual apresentada ao usuario.
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

    # ============================================================
    # 9. RETORNAR OS DOCUMENTOS SELECIONADOS
    # ============================================================
    return $selectedDocuments.ToArray()
  }
}
