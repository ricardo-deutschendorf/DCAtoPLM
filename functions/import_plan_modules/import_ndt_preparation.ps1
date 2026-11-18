# ============================================================
# PREPARACAO DOS ARQUIVOS DA FOLHA NDT
# ============================================================
# Associa o desenho SLDDRW selecionado ao PDF correspondente
# antes da conexao com o Teamcenter (nada e alterado la).
#   1. identifica MPI ou FPI;
#   2. preserva a entrada original do desenho;
#   3. localiza o PDF e o coloca em SelectedDocument.File;
#   4. retorna desenho, PDF e tipo de folha.
# ============================================================

function Resolve-DcaNdtSelectedFiles {
    param(
        [Parameter(Mandatory)][ValidateNotNull()] $SelectedDocument,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$ItemCode,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$ClientRevision
    )

    if (([string]$SelectedDocument.DocumentType).Trim() -ine "NDT") {
        return [PSCustomObject]@{
            SelectedDocument = $SelectedDocument
            DrawingEntry     = $null
            PdfEntry         = $null
            SheetType        = $null
        }
    }

    # --- Desenho de origem ---
    $fileProp = $SelectedDocument.PSObject.Properties["File"]
    if (-not $fileProp -or $null -eq $fileProp.Value) { throw "O resultado NDT nao possui o desenho de origem." }
    $drawingEntry = $fileProp.Value

    $drawingPath = ([string]$drawingEntry.FullName).Trim()
    if ([string]::IsNullOrWhiteSpace($drawingPath)) { throw "O desenho NDT nao possui um caminho completo." }
    if ([System.IO.Path]::GetExtension($drawingPath) -ine ".slddrw") { throw "O arquivo de origem do NDT nao e SLDDRW: '$drawingPath'." }

    # --- Tipo de folha: propriedade NdtSheetType ou [MPI]/[FPI] no nome ---
    $sheetType = ""
    if ($SelectedDocument.PSObject.Properties["NdtSheetType"]) {
        $sheetType = ([string]$SelectedDocument.NdtSheetType).Trim().ToUpperInvariant()
    }
    if (-not $sheetType -and ([string]$drawingEntry.BaseName) -match '(?i)\[(?<NdtType>MPI|FPI)\]') {
        $sheetType = $Matches["NdtType"].ToUpperInvariant()
    }
    if ($sheetType -notin "MPI", "FPI") { throw "Nao foi possivel identificar MPI ou FPI no desenho NDT '$($drawingEntry.Name)'." }

    # --- PDF correspondente ---
    $pdfEntry = Find-DcaNdtPdfEntry `
        -DrawingEntry $drawingEntry -ItemCode $ItemCode `
        -NdtSheetType $sheetType -ClientRevision $ClientRevision
    if ($null -eq $pdfEntry) { throw "A pesquisa do PDF correspondente retornou NULL para '$ItemCode [$sheetType]'." }

    # File passa a ser o PDF importado pelo fluxo comum; o desenho fica em NdtDrawingFile.
    $SelectedDocument.File = $pdfEntry
    $extras = [ordered]@{ NdtDrawingFile = $drawingEntry; NdtPdfFile = $pdfEntry; NdtSheetType = $sheetType }
    foreach ($name in $extras.Keys) {
        Add-Member -InputObject $SelectedDocument -NotePropertyName $name -NotePropertyValue $extras[$name] -Force
    }

    if ($Details) {
        Write-Host "  Arquivos associados ao DCA NDT:" -ForegroundColor Cyan
        @(
            "    Desenho: '$($drawingEntry.FullName)'"
            "    PDF:     '$($pdfEntry.FullName)'"
            "    Folha:   '$sheetType'"
            "    Revisao: '$ClientRevision'"
        ) | ForEach-Object { Write-Host $_ -ForegroundColor DarkGray }
    }

    return [PSCustomObject]@{
        SelectedDocument = $SelectedDocument
        DrawingEntry     = $drawingEntry
        PdfEntry         = $pdfEntry
        SheetType        = $sheetType
    }
}