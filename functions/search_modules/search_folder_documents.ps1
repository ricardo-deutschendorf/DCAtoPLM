# ============================================================
# LEITURA DOS DOCUMENTOS DE UMA PASTA
# ============================================================
#
# Este arquivo carrega os PDFs existentes diretamente dentro
# de uma pasta selecionada.
#
# Fontes utilizadas:
#   1. indice do Vault, quando a API do PDM estiver disponivel;
#   2. sistema de arquivos, quando a API estiver indisponivel.
#
# Para cada PDF, o fluxo:
#   1. interpreta o nome fisico do arquivo;
#   2. identifica codigo, revisao e titulo;
#   3. consulta o estado atual no PDM;
#   4. complementa a revisao pelo cartao de dados;
#   5. complementa a descricao pelo cartao de dados;
#   6. prepara o objeto utilizado pelo lote de importacao.
#
# Somente os PDFs diretamente dentro da pasta sao carregados.
# As subpastas sao tratadas pelo modulo de navegacao.
#
# Nenhum arquivo e alterado ou importado por esta funcao.
# ============================================================
function Get-DcaDocumentsFromFolderPath {

  # Carrega os PDFs diretamente dentro da pasta informada e
  # transforma cada resultado em um documento preparado.
  #
  # FolderOption informa:
  #   1. caminho completo da pasta;
  #   2. caminho relativo;
  #   3. categoria DCA;
  #   4. tipo do documento;
  #   5. nome utilizado na apresentacao.
  #
  # Vault pode permanecer NULL. Nesse caso, a leitura utiliza
  # somente os arquivos disponíveis no sistema de arquivos.
  param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNull()]
    $FolderOption,

    $Vault,

    # Oculta diagnosticos individuais de estado e cartao durante
    # a leitura de pastas com muitos documentos.
    [switch]$SuppressItemDetails
  )

  # Preserva o modo Details geral, mas permite ocultar as mensagens
  # emitidas para cada PDF durante a leitura de uma pasta.
  $showItemDetails =
  (
    $Details -and
    -not $SuppressItemDetails
  )

  # Preserva a informacao de que o script foi iniciado com
  # -Details. Esse valor continua verdadeiro mesmo quando os
  # diagnosticos individuais dos documentos forem suprimidos.
  $showFolderTiming =
  [bool]$Details

  # Mede todo o processamento da pasta, incluindo pesquisa dos
  # PDFs, leitura dos dados no PDM e montagem dos documentos.
  $folderTotalTimer =
  [System.Diagnostics.Stopwatch]::StartNew()

  $folderFullName =
  ([string]$FolderOption.FullName).Trim()

  $documentType =
  ([string]$FolderOption.DocumentType).Trim()

  if (
    [string]::IsNullOrWhiteSpace(
      $folderFullName
    )
  ) {

    throw (
      "FolderOption nao possui um caminho completo valido."
    )
  }

  if (-not (
      Test-Path `
        -LiteralPath $folderFullName `
        -PathType Container
    )) {

    throw (
      "A pasta informada nao foi encontrada: " +
      "'$folderFullName'."
    )
  }

  if (
    [string]::IsNullOrWhiteSpace(
      $documentType
    )
  ) {

    throw (
      "FolderOption nao possui um tipo de documento valido."
    )
  }

  # ============================================================
  # 1. PREPARAR A COLECAO DE PDFS
  # ============================================================
  #
  # A mesma colecao recebe os resultados do Vault ou do sistema
  # de arquivos, mantendo o restante do processamento unificado.
  #
  # Mede somente a localização dos PDFs pelo índice do Vault ou
  # pelo sistema de arquivos.
  $folderSearchTimer =
  [System.Diagnostics.Stopwatch]::StartNew()

  $pdfEntries =
  @()

  $useDiskSearch =
  $null -eq $Vault
  # ============================================================
  # 2. PESQUISAR OS PDFS PELO VAULT
  # ============================================================
  #
  # A pesquisa pode retornar arquivos localizados em subpastas.
  # Por isso, os resultados sao filtrados pelo diretorio completo.
  if ($null -ne $Vault) {

    try {

      $searchResults =
      @(
        Search-DcaVaultPdfEntries `
          -Vault $Vault `
          -SearchText "*" `
          -StartFolderPath $folderFullName
      )

      $pdfEntries =
      @(
        $searchResults |
          Where-Object {

          $pdfPath =
          ([string]$_.FullName).Trim()

          if (
            [string]::IsNullOrWhiteSpace(
              $pdfPath
            )
          ) {

            return $false
          }

          $pdfDirectory =
          [System.IO.Path]::GetDirectoryName(
            $pdfPath
          )

          $pdfDirectory -ieq
          $folderFullName
        } |
          Sort-Object FullName
      )

      if ($pdfEntries.Count -eq 0) {

        $useDiskSearch =
        $true

        if ($Details) {

          Write-Info (
            "O Vault nao retornou PDFs diretamente em " +
            "'$folderFullName'. A pasta local sera consultada."
          )
        }
      }
    }
    catch {

      $useDiskSearch =
      $true

      Write-Warn (
        "Nao foi possivel consultar os PDFs pelo Vault: " +
        $_.Exception.Message +
        " A pasta local sera consultada."
      )
    }
  }
  # ============================================================
  # 3. PESQUISAR OS PDFS NO SISTEMA DE ARQUIVOS
  # ============================================================
  #
  # Esta alternativa e utilizada quando a API do Vault nao
  # estiver disponivel.
  #
  # A pesquisa nao utiliza Recurse, portanto somente os PDFs
  # diretamente dentro da pasta atual sao retornados.
  if ($useDiskSearch) {

    $diskFiles =
    @(
      Get-ChildItem `
        -LiteralPath $folderFullName `
        -Filter "*.pdf" `
        -File `
        -Force `
        -ErrorAction SilentlyContinue
    )

    # Converte os arquivos locais para a mesma estrutura utilizada
    # pelos resultados retornados pela API do Vault.
    $pdfEntries =
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

  $folderSearchTimer.Stop()

  # ============================================================
  # 4. PREPARAR OS DOCUMENTOS ENCONTRADOS
  # ============================================================
  #
  # Cada PDF sera interpretado e transformado em um objeto que
  # podera ser utilizado diretamente pelo fluxo principal.

  # Mede a interpretação dos nomes, leitura do estado e leitura
  # dos campos de revisão e descrição no cartão do PDM.
  $pdmItemsTimer =
  [System.Diagnostics.Stopwatch]::StartNew()

  $documents =
  [System.Collections.Generic.List[object]]::new()

  # As funcoes chamadas abaixo consultam a variavel Details do
  # escopo chamador. Uma variavel local permite silenciar apenas
  # esta leitura, sem alterar o modo Details do script principal.
  $Details =
  $showItemDetails

  foreach ($pdfEntry in $pdfEntries) {

    if ($null -eq $pdfEntry) {
      continue
    }

    $pdfBaseName =
    ([string]$pdfEntry.BaseName).Trim()

    $pdfFullName =
    ([string]$pdfEntry.FullName).Trim()

    if (
      [string]::IsNullOrWhiteSpace(
        $pdfBaseName
      ) -or
      [string]::IsNullOrWhiteSpace(
        $pdfFullName
      )
    ) {

      if ($Details) {

        Write-Warn (
          "Uma entrada de PDF foi ignorada porque nao possui " +
          "nome base ou caminho completo."
        )
      }

      continue
    }
    # Interpreta o nome do arquivo conforme o tipo de documento.
    #
    # O retorno pode conter:
    #   1. codigo de origem;
    #   2. revisao identificada;
    #   3. titulo do documento;
    #   4. indicador de codigo reconhecido.
    $parsedName =
    ConvertFrom-PdfFileName `
      -BaseName $pdfBaseName `
      -DocumentType $documentType

    # Consulta o estado atual do arquivo no workflow do PDM.
    # Sem uma conexao com o Vault, o estado permanece vazio.
    $pdmState =
    Get-DcaPdmFileState `
      -Entry $pdfEntry

    # Reune os dados do arquivo, da pasta e do PDM em uma unica
    # estrutura utilizada durante a preparacao do lote.
    $document =
    [PSCustomObject]@{
      File = $pdfEntry
      SourceCode = $parsedName.SourceCode
      ClientRevision = [string]$parsedName.ClientRevision
      DocumentTitle = $parsedName.DocumentTitle
      DocumentType = $documentType
      TypeDisplayName = $FolderOption.DisplayName
      CodeParsed = $parsedName.CodeParsed
      PdmState = $pdmState
      FolderImport = $true
      SourceFolder = $FolderOption.RelativePath
      CategoryFolder = $FolderOption.CategoryFolder
      TeamcenterItem = $null
      TeamcenterRevision = $null
    }

    # ============================================================
    # 5. COMPLEMENTAR OS DADOS PELO CARTAO DO PDM
    # ============================================================
    #
    # Os valores encontrados no cartao possuem prioridade sobre
    # os valores extraidos somente do nome fisico do PDF.
    # Substitui a revisao inicial quando uma revisao preenchida
    # for encontrada na variavel configurada do cartao.
    Update-DcaMatchRevisionFromCard `
      -Match $document

    # Substitui o titulo inicial quando uma descricao preenchida
    # for encontrada na variavel configurada do cartao.
    Update-DcaMatchDescriptionFromCard `
      -Match $document

    # Adiciona o documento somente depois de concluir a leitura
    # do nome, do estado e das variaveis do cartao.
    $documents.Add(
      $document
    )
  }

  $pdmItemsTimer.Stop()

  $folderTotalTimer.Stop()

  # ============================================================
  # 6. RETORNAR OS DOCUMENTOS PREPARADOS
  # ============================================================
  #
  # ToArray devolve uma colecao simples para a navegacao e para
  # o fluxo principal.
  if (
    $documents.Count -eq 0 -and
    $Details
  ) {

    Write-Info (
      "Nenhum PDF foi encontrado diretamente na pasta " +
      "'$folderFullName'."
    )
  }

  $script:DcaLastFolderTiming =
  [PSCustomObject]@{
    FolderPath =
    $folderFullName

    SearchSeconds =
    [Math]::Round(
      $folderSearchTimer.Elapsed.TotalSeconds,
      2
    )


    
    PdmReadSeconds =
    [Math]::Round(
      $pdmItemsTimer.Elapsed.TotalSeconds,
      2
    )

    TotalSeconds =
    [Math]::Round(
      $folderTotalTimer.Elapsed.TotalSeconds,
      2
    )

    
    DocumentCount =
    $documents.Count

    AverageMilliseconds =
    if ($documents.Count -gt 0) {

      [Math]::Round(
        (
          $pdmItemsTimer.Elapsed.TotalMilliseconds /
          $documents.Count
        ),
        0
      )
    }
    else {

      0
    }
  }

  # Acumula os tempos de todas as pastas abertas durante a
  # execucao. Isso permite apresentar um resumo final mesmo
  # quando o usuario navegar por mais de uma pasta.
  $script:DcaFolderSearchTotalSeconds +=
  [double]$script:DcaLastFolderTiming.SearchSeconds

  $script:DcaFolderPdmReadTotalSeconds +=
  [double]$script:DcaLastFolderTiming.PdmReadSeconds

  $script:DcaFolderTotalSeconds +=
  [double]$script:DcaLastFolderTiming.TotalSeconds

  $script:DcaFolderLoadCount++

  $script:DcaFolderDocumentCount +=
  [int]$script:DcaLastFolderTiming.DocumentCount

  return $documents.ToArray()
}
