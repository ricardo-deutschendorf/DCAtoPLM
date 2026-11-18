# ============================================================
# LEITURA DOS DOCUMENTOS DE UMA PASTA
# ============================================================
# Carrega os documentos diretamente dentro de uma pasta (sem subpastas;
# elas ficam com o modulo de navegacao).
#   1. busca pelo indice do Vault ou, sem API, pelo sistema de arquivos;
#   2. interpreta o nome (codigo, revisao, titulo) e consulta o estado no PDM;
#   3. complementa revisao e descricao pelo cartao de dados;
#   4. prepara o objeto usado pelo lote e acumula os tempos.
# Arquivos aceitos: PDFs nas categorias comuns e SLDDRW em NDT.
# Nenhum arquivo e alterado ou importado aqui.
# ============================================================

function Get-DcaDocumentsFromFolderPath {
    param(
        [Parameter(Mandatory)][ValidateNotNull()]$FolderOption,
        $Vault,
        # Oculta diagnosticos individuais durante a leitura.
        [switch]$SuppressItemDetails
    )

    # Preserva o Details geral, mas permite silenciar cada documento.
    $showItemDetails = $Details -and -not $SuppressItemDetails

    $folderTotalTimer = [System.Diagnostics.Stopwatch]::StartNew()

    $folderFullName = ([string]$FolderOption.FullName).Trim()
    $documentType   = ([string]$FolderOption.DocumentType).Trim()

    if (-not $folderFullName) { throw "FolderOption nao possui um caminho completo valido." }
    if (-not (Test-Path -LiteralPath $folderFullName -PathType Container)) {
        throw "A pasta informada nao foi encontrada: '$folderFullName'."
    }
    if (-not $documentType) { throw "FolderOption nao possui um tipo de documento valido." }

    # --- 1. Localizar os arquivos (NDT usa SLDDRW; as demais categorias, PDF) ---
    $searchTimer = [System.Diagnostics.Stopwatch]::StartNew()

    $expectedExtension = if ($documentType -ieq "NDT") { ".slddrw" } else { ".pdf" }
    $documentEntries = @()
    $useDiskSearch = $null -eq $Vault

    # O Vault pode devolver arquivos de subpastas: filtra pelo diretorio exato.
    if ($null -ne $Vault) {
        try {
            $documentEntries = @(
                Search-DcaVaultPdfEntries -Vault $Vault -SearchText "*" -StartFolderPath $folderFullName |
                    Where-Object {
                        $path = ([string]$_.FullName).Trim()
                        $path -and
                        [System.IO.Path]::GetExtension($path) -ieq $expectedExtension -and
                        [System.IO.Path]::GetDirectoryName($path) -ieq $folderFullName
                    } |
                    Sort-Object FullName
            )

            if ($documentEntries.Count -eq 0) {
                $useDiskSearch = $true
                if ($Details) {
                    Write-Info (
                        "O Vault nao retornou arquivos '*$expectedExtension' diretamente em " +
                        "'$folderFullName'. A pasta local sera consultada."
                    )
                }
            }
        }
        catch {
            $useDiskSearch = $true
            Write-Warn "Nao foi possivel consultar os arquivos pelo Vault: $($_.Exception.Message) A pasta local sera consultada."
        }
    }

    # Disco: sem Recurse, so os arquivos diretamente na pasta, na mesma estrutura da API.
    if ($useDiskSearch) {
        $documentEntries = @(
            Get-ChildItem -LiteralPath $folderFullName -Filter "*$expectedExtension" -File -Force `
                -ErrorAction SilentlyContinue |
                ForEach-Object {
                    [PSCustomObject]@{
                        Name      = $_.Name
                        BaseName  = $_.BaseName.Trim()
                        FullName  = $_.FullName
                        FromVault = $false
                    }
                }
        )
    }

    $searchTimer.Stop()

    # --- 2. Preparar os documentos ---
    $pdmTimer = [System.Diagnostics.Stopwatch]::StartNew()
    $documents = [System.Collections.Generic.List[object]]::new()

    # As funcoes chamadas abaixo leem $Details do escopo chamador;
    # esta copia local silencia so esta leitura.
    $Details = $showItemDetails

    foreach ($entry in $documentEntries) {
        if ($null -eq $entry) { continue }

        $baseName = ([string]$entry.BaseName).Trim()
        $fullName = ([string]$entry.FullName).Trim()

        if (-not $baseName -or -not $fullName) {
            if ($Details) { Write-Warn "Uma entrada de arquivo foi ignorada porque nao possui nome base ou caminho completo." }
            continue
        }

        $parsedName = ConvertFrom-PdfFileName -BaseName $baseName -DocumentType $documentType

        $document = [PSCustomObject]@{
            File               = $entry
            SourceCode         = $parsedName.SourceCode
            ClientRevision     = [string]$parsedName.ClientRevision
            DocumentTitle      = $parsedName.DocumentTitle
            DocumentType       = $documentType
            TypeDisplayName    = $FolderOption.DisplayName
            CodeParsed         = $parsedName.CodeParsed
            PdmState           = Get-DcaPdmFileState -Entry $entry   # sem Vault, fica vazio
            FolderImport       = $true
            SourceFolder       = $FolderOption.RelativePath
            CategoryFolder     = $FolderOption.CategoryFolder
            TeamcenterItem     = $null
            TeamcenterRevision = $null
        }

        # Valores do cartao tem prioridade sobre os extraidos do nome.
        Update-DcaMatchRevisionFromCard -Match $document
        Update-DcaMatchDescriptionFromCard -Match $document

        $documents.Add($document)
    }

    $pdmTimer.Stop()
    $folderTotalTimer.Stop()

    if ($documents.Count -eq 0 -and $Details) {
        Write-Info "Nenhum arquivo '*$expectedExtension' foi encontrado diretamente na pasta '$folderFullName'."
    }

    # --- 3. Registrar e acumular os tempos (resumo final com varias pastas) ---
    $script:DcaLastFolderTiming = [PSCustomObject]@{
        FolderPath          = $folderFullName
        SearchSeconds       = [Math]::Round($searchTimer.Elapsed.TotalSeconds, 2)
        PdmReadSeconds      = [Math]::Round($pdmTimer.Elapsed.TotalSeconds, 2)
        TotalSeconds        = [Math]::Round($folderTotalTimer.Elapsed.TotalSeconds, 2)
        DocumentCount       = $documents.Count
        AverageMilliseconds = if ($documents.Count -gt 0) {
            [Math]::Round($pdmTimer.Elapsed.TotalMilliseconds / $documents.Count, 0)
        } else { 0 }
    }

    $script:DcaFolderSearchTotalSeconds  += [double]$script:DcaLastFolderTiming.SearchSeconds
    $script:DcaFolderPdmReadTotalSeconds += [double]$script:DcaLastFolderTiming.PdmReadSeconds
    $script:DcaFolderTotalSeconds        += [double]$script:DcaLastFolderTiming.TotalSeconds
    $script:DcaFolderLoadCount++
    $script:DcaFolderDocumentCount       += [int]$script:DcaLastFolderTiming.DocumentCount

    return $documents.ToArray()
}