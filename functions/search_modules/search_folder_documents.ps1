
# ============================================================
# LEITURA DOS DOCUMENTOS DE UMA PASTA
# ============================================================
#
# Carrega os documentos diretamente dentro de uma pasta.
#
# Fontes utilizadas:
#   1. Indice do Vault, quando a API do PDM estiver disponivel;
#   2. Sistema de arquivos, quando a API estiver indisponivel.
#
# Para cada documento, o fluxo:
#   1. Interpreta o nome fisico do arquivo;
#   2. Identifica codigo, revisao e titulo;
#   3. Consulta o estado atual no PDM;
#   4. Complementa a revisao pelo cartao de dados;
#   5. Complementa a descricao pelo cartao de dados;
#   6. Prepara o objeto utilizado pelo lote de importacao.
#
# Somente arquivos suportados diretamente dentro da pasta sao
# carregados: PDFs nas categorias comuns e desenhos SLDDRW em NDT.
# As subpastas sao tratadas pelo modulo de navegacao.
#
# Nenhum arquivo e alterado ou importado por esta funcao.
# ============================================================

function Get-DcaDocumentsFromFolderPath {

    # --------------------------------------------------------
    # PARAMETROS
    # --------------------------------------------------------

    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNull()]
        $FolderOption,

        $Vault,

        # Oculta diagnosticos individuais durante a leitura.
        [switch]$SuppressItemDetails
    )

    # --------------------------------------------------------
    # CONFIGURACOES INICIAIS
    # --------------------------------------------------------

    # Preserva o modo Details geral, mas permite ocultar
    # mensagens individuais de cada documento.
    $showItemDetails = (
        $Details -and
        -not $SuppressItemDetails
    )

    # Preserva a informacao de que o script foi iniciado com
    # -Details, mesmo quando os diagnosticos forem suprimidos.
    $showFolderTiming = [bool]$Details

    # Cronometra todo o processamento da pasta.
    $folderTotalTimer =
        [System.Diagnostics.Stopwatch]::StartNew()

    $folderFullName =
        ([string]$FolderOption.FullName).Trim()

    $documentType =
        ([string]$FolderOption.DocumentType).Trim()

    # Valida o caminho informado.
    if (
        [string]::IsNullOrWhiteSpace($folderFullName)
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

    # Valida o tipo de documento.
    if (
        [string]::IsNullOrWhiteSpace($documentType)
    ) {
        throw (
            "FolderOption nao possui um tipo de documento valido."
        )
    }

    # --------------------------------------------------------
    # 1. PREPARAR A COLECAO DE ARQUIVOS
    # --------------------------------------------------------
    #
    # Categorias comuns utilizam PDFs.
    # NDT utiliza desenhos SLDDRW, dos quais o fluxo principal
    # localiza o PDF correspondente.
    #
    # Mede somente a localizacao dos arquivos.

    $folderSearchTimer =
        [System.Diagnostics.Stopwatch]::StartNew()

    $documentEntries = @()

    $useDiskSearch = $null -eq $Vault

    $expectedExtension = if ($documentType -ieq "NDT") {
        ".slddrw"
    }
    else {
        ".pdf"
    }

    # --------------------------------------------------------
    # 2. PESQUISAR OS ARQUIVOS PELO VAULT
    # --------------------------------------------------------
    #
    # A pesquisa pode retornar arquivos localizados em subpastas.
    # Por isso, os resultados sao filtrados pelo diretorio completo.

    if ($null -ne $Vault) {

        try {

            $searchResults = @(
                Search-DcaVaultPdfEntries `
                    -Vault $Vault `
                    -SearchText "*" `
                    -StartFolderPath $folderFullName
            )

            $documentEntries = @(
                $searchResults |
                    Where-Object {

                        $documentPath =
                            ([string]$_.FullName).Trim()

                        if (
                            [string]::IsNullOrWhiteSpace(
                                $documentPath
                            )
                        ) {
                            return $false
                        }

                        if (
                            [System.IO.Path]::GetExtension(
                                $documentPath
                            ) -ine $expectedExtension
                        ) {
                            return $false
                        }

                        $documentDirectory =
                            [System.IO.Path]::GetDirectoryName(
                                $documentPath
                            )

                        $documentDirectory -ieq $folderFullName
                    } |
                    Sort-Object FullName
            )

            if ($documentEntries.Count -eq 0) {

                $useDiskSearch = $true

                if ($Details) {

                    Write-Info (
                        "O Vault nao retornou arquivos " +
                        "'*$expectedExtension' diretamente em " +
                        "'$folderFullName'. A pasta local sera consultada."
                    )
                }
            }
        }
        catch {

            $useDiskSearch = $true

            Write-Warn (
                "Nao foi possivel consultar os arquivos pelo Vault: " +
                $_.Exception.Message +
                " A pasta local sera consultada."
            )
        }
    }

    # --------------------------------------------------------
    # 3. PESQUISAR OS ARQUIVOS NO SISTEMA DE ARQUIVOS
    # --------------------------------------------------------
    #
    # Utilizado quando a API do Vault nao estiver disponivel.
    #
    # A pesquisa nao utiliza Recurse. Portanto, somente os
    # arquivos diretamente dentro da pasta atual sao retornados.

    if ($useDiskSearch) {

        $diskFiles = @(
            Get-ChildItem `
                -LiteralPath $folderFullName `
                -Filter "*$expectedExtension" `
                -File `
                -Force `
                -ErrorAction SilentlyContinue
        )

        # Converte os arquivos locais para a mesma estrutura
        # utilizada pelos resultados retornados pela API do Vault.

        $documentEntries = @(
            foreach ($diskFile in $diskFiles) {

                [PSCustomObject]@{
                    Name      = $diskFile.Name
                    BaseName  = $diskFile.BaseName.Trim()
                    FullName  = $diskFile.FullName
                    FromVault = $false
                }
            }
        )
    }

    $folderSearchTimer.Stop()

    # --------------------------------------------------------
    # 4. PREPARAR OS DOCUMENTOS ENCONTRADOS
    # --------------------------------------------------------
    #
    # Cada arquivo sera interpretado e transformado em um objeto
    # utilizado pelo fluxo principal.

    $pdmItemsTimer =
        [System.Diagnostics.Stopwatch]::StartNew()

    $documents =
        [System.Collections.Generic.List[object]]::new()

    # As funcoes chamadas abaixo consultam a variavel Details
    # do escopo chamador. Uma variavel local permite silenciar
    # apenas esta leitura.

    $Details = $showItemDetails

    foreach ($documentEntry in $documentEntries) {

        if ($null -eq $documentEntry) {
            continue
        }

        $documentBaseName =
            ([string]$documentEntry.BaseName).Trim()

        $documentFullName =
            ([string]$documentEntry.FullName).Trim()

        if (
            [string]::IsNullOrWhiteSpace($documentBaseName) -or
            [string]::IsNullOrWhiteSpace($documentFullName)
        ) {

            if ($Details) {

                Write-Warn (
                    "Uma entrada de arquivo foi ignorada porque nao possui " +
                    "nome base ou caminho completo."
                )
            }

            continue
        }

        # Interpreta o nome do arquivo conforme o tipo de documento.
        $parsedName =
            ConvertFrom-PdfFileName `
                -BaseName $documentBaseName `
                -DocumentType $documentType

        # Consulta o estado atual do arquivo no workflow do PDM.
        # Sem uma conexao com o Vault, o estado permanece vazio.
        $pdmState =
            Get-DcaPdmFileState `
                -Entry $documentEntry

        # Reune os dados do arquivo, da pasta e do PDM.
        $document = [PSCustomObject]@{
            File                = $documentEntry
            SourceCode          = $parsedName.SourceCode
            ClientRevision      = [string]$parsedName.ClientRevision
            DocumentTitle       = $parsedName.DocumentTitle
            DocumentType        = $documentType
            TypeDisplayName     = $FolderOption.DisplayName
            CodeParsed          = $parsedName.CodeParsed
            PdmState            = $pdmState
            FolderImport        = $true
            SourceFolder        = $FolderOption.RelativePath
            CategoryFolder      = $FolderOption.CategoryFolder
            TeamcenterItem      = $null
            TeamcenterRevision  = $null
        }

        # ----------------------------------------------------
        # 5. COMPLEMENTAR OS DADOS PELO CARTAO DO PDM
        # ----------------------------------------------------
        #
        # Os valores encontrados no cartao possuem prioridade
        # sobre os valores extraidos somente do nome fisico.

        # Atualiza a revisao quando encontrar um valor preenchido.
        Update-DcaMatchRevisionFromCard `
            -Match $document

        # Atualiza o titulo quando encontrar uma descricao preenchida.
        Update-DcaMatchDescriptionFromCard `
            -Match $document

        # Adiciona o documento depois de concluir sua preparacao.
        $documents.Add($document)
    }

    $pdmItemsTimer.Stop()

    $folderTotalTimer.Stop()

    # --------------------------------------------------------
    # 6. RETORNAR OS DOCUMENTOS PREPARADOS
    # --------------------------------------------------------

    if (
        $documents.Count -eq 0 -and
        $Details
    ) {

        Write-Info (
            "Nenhum arquivo '*$expectedExtension' foi encontrado " +
            "diretamente na pasta " +
            "'$folderFullName'."
        )
    }

    # --------------------------------------------------------
    # 7. REGISTRAR OS TEMPOS DE EXECUCAO
    # --------------------------------------------------------

    $script:DcaLastFolderTiming = [PSCustomObject]@{

        FolderPath = $folderFullName

        SearchSeconds = [Math]::Round(
            $folderSearchTimer.Elapsed.TotalSeconds,
            2
        )

        PdmReadSeconds = [Math]::Round(
            $pdmItemsTimer.Elapsed.TotalSeconds,
            2
        )

        TotalSeconds = [Math]::Round(
            $folderTotalTimer.Elapsed.TotalSeconds,
            2
        )

        DocumentCount = $documents.Count

        AverageMilliseconds = if ($documents.Count -gt 0) {

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

    # --------------------------------------------------------
    # 8. ACUMULAR OS TEMPOS DO PROCESSAMENTO
    # --------------------------------------------------------
    #
    # Permite apresentar um resumo final mesmo quando o usuario
    # navegar por mais de uma pasta.

    $script:DcaFolderSearchTotalSeconds +=
        [double]$script:DcaLastFolderTiming.SearchSeconds

    $script:DcaFolderPdmReadTotalSeconds +=
        [double]$script:DcaLastFolderTiming.PdmReadSeconds

    $script:DcaFolderTotalSeconds +=
        [double]$script:DcaLastFolderTiming.TotalSeconds

    $script:DcaFolderLoadCount++

    $script:DcaFolderDocumentCount +=
        [int]$script:DcaLastFolderTiming.DocumentCount

    # --------------------------------------------------------
    # 9. RETORNAR A COLECAO
    # --------------------------------------------------------

    return $documents.ToArray()
}
