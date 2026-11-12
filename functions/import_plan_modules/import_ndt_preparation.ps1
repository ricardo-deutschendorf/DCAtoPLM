# ============================================================
# PREPARACAO DOS ARQUIVOS DA FOLHA NDT
# ============================================================
#
# Este arquivo associa o desenho SLDDRW selecionado ao PDF
# correspondente antes da conexao com o Teamcenter.
#
# Responsabilidades:
#   1. identificar MPI ou FPI;
#   2. preservar a entrada original do desenho;
#   3. localizar o PDF correspondente;
#   4. trocar SelectedPdf.File pelo PDF usado no Dataset;
#   5. retornar os dois arquivos de forma organizada.
#
# Nenhuma alteracao e realizada no Teamcenter.
# ============================================================

function Resolve-DcaNdtSelectedFiles {

  param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNull()]
    $SelectedDocument,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$ItemCode,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$ClientRevision
  )

  $documentType =
  ([string]$SelectedDocument.DocumentType).Trim()

  if ($documentType -ine "NDT") {

    return [PSCustomObject]@{
      SelectedDocument = $SelectedDocument
      DrawingEntry = $null
      PdfEntry = $null
      SheetType = $null
    }
  }

  if (
    -not $SelectedDocument.PSObject.Properties["File"] -or
    $null -eq $SelectedDocument.File
  ) {

    throw (
      "O resultado NDT nao possui o desenho de origem."
    )
  }

  $drawingEntry =
  $SelectedDocument.File

  $drawingPath =
  ([string]$drawingEntry.FullName).Trim()

  if (
    [string]::IsNullOrWhiteSpace(
      $drawingPath
    )
  ) {

    throw (
      "O desenho NDT nao possui um caminho completo."
    )
  }

  if (
    [System.IO.Path]::GetExtension(
      $drawingPath
    ) -ine ".slddrw"
  ) {

    throw (
      "O arquivo de origem do NDT nao e SLDDRW: " +
      "'$drawingPath'."
    )
  }

  $sheetType =
  ""

  if (
    $SelectedDocument.PSObject.Properties["NdtSheetType"]
  ) {

    $sheetType =
    ([string]$SelectedDocument.NdtSheetType).Trim().ToUpperInvariant()
  }

  if (
    [string]::IsNullOrWhiteSpace(
      $sheetType
    )
  ) {

    $drawingBaseName =
    ([string]$drawingEntry.BaseName).Trim()

    if (
      $drawingBaseName -match
      '(?i)\[(?<NdtType>MPI|FPI)\]'
    ) {

      $sheetType =
      ([string]$Matches["NdtType"]).Trim().ToUpperInvariant()
    }
  }

  if (
    $sheetType -notin @(
      "MPI",
      "FPI"
    )
  ) {

    throw (
      "Nao foi possivel identificar MPI ou FPI no desenho " +
      "NDT '$($drawingEntry.Name)'."
    )
  }

  $pdfEntry =
  Find-DcaNdtPdfEntry `
    -DrawingEntry $drawingEntry `
    -ItemCode $ItemCode `
    -NdtSheetType $sheetType `
    -ClientRevision $ClientRevision

  if ($null -eq $pdfEntry) {

    throw (
      "A pesquisa do PDF correspondente retornou NULL para " +
      "'$ItemCode [$sheetType]'."
    )
  }

  # O campo File continua representando o arquivo que sera
  # importado pelo fluxo comum de PDF.
  $SelectedDocument.File =
  $pdfEntry

  Add-Member `
    -InputObject $SelectedDocument `
    -NotePropertyName "NdtDrawingFile" `
    -NotePropertyValue $drawingEntry `
    -Force

  Add-Member `
    -InputObject $SelectedDocument `
    -NotePropertyName "NdtPdfFile" `
    -NotePropertyValue $pdfEntry `
    -Force

  Add-Member `
    -InputObject $SelectedDocument `
    -NotePropertyName "NdtSheetType" `
    -NotePropertyValue $sheetType `
    -Force

  if ($Details) {

    Write-Host (
      "  Arquivos associados ao DCA NDT:"
    ) -ForegroundColor Cyan

    Write-Host (
      "    Desenho: '$($drawingEntry.FullName)'"
    ) -ForegroundColor DarkGray

    Write-Host (
      "    PDF:     '$($pdfEntry.FullName)'"
    ) -ForegroundColor DarkGray

    Write-Host (
      "    Folha:   '$sheetType'"
    ) -ForegroundColor DarkGray

    Write-Host (
      "    Revisao: '$ClientRevision'"
    ) -ForegroundColor DarkGray
  }

  return [PSCustomObject]@{
    SelectedDocument = $SelectedDocument
    DrawingEntry = $drawingEntry
    PdfEntry = $pdfEntry
    SheetType = $sheetType
  }
}