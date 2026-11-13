
# ============================================================
# LOCALIZACAO DO PDF CORRESPONDENTE A UMA FOLHA NDT
# ============================================================

function Find-DcaNdtPdfEntry {

  # Localiza o PDF correspondente ao desenho SLDDRW de uma
  # Folha NDT.
  #
  # Estrutura esperada:
  #
  #   Hamilton
  #   |-- Folhas NDT
  #   |   `-- 1002370-1 [MPI].SLDDRW
  #   |
  #   `-- Folhas NDT PDF
  #       `-- 1002370-1 [MPI] [--2].PDF
  #
  # A correspondencia utiliza:
  #   1. codigo do documento;
  #   2. tipo da folha, MPI ou FPI;
  #   3. revisao do documento.

  param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNull()]
    $DrawingEntry,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$ItemCode,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$NdtSheetType,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$ClientRevision
  )

  # ============================================================
  # 1. NORMALIZAR OS VALORES
  # ============================================================

  $drawingPath = ([string]$DrawingEntry.FullName).Trim()
  $itemCodeClean = $ItemCode.Trim().ToUpperInvariant()
  $ndtSheetTypeClean = $NdtSheetType.Trim().ToUpperInvariant()
  $clientRevisionClean = $ClientRevision.Trim().ToUpperInvariant()

  if ([string]::IsNullOrWhiteSpace($drawingPath)) {

    throw "O desenho NDT nao possui um caminho completo."
  }

  if (
    [System.IO.Path]::GetExtension($drawingPath) -ine ".slddrw"
  ) {

    throw (
      "O arquivo selecionado como Folha NDT nao e um desenho " +
      "SLDDRW: '$drawingPath'."
    )
  }

  if ($ndtSheetTypeClean -notin @("MPI", "FPI")) {

    throw (
      "O tipo da Folha NDT e invalido: " +
      "'$ndtSheetTypeClean'. Era esperado MPI ou FPI."
    )
  }

  # ============================================================
  # 2. LOCALIZAR A PASTA FOLHAS NDT PDF
  # ============================================================

  $drawingFolder = [System.IO.Path]::GetDirectoryName(
    $drawingPath
  )

  if ([string]::IsNullOrWhiteSpace($drawingFolder)) {

    throw (
      "Nao foi possivel identificar a pasta do desenho NDT: " +
      "'$drawingPath'."
    )
  }

  $drawingFolderName = [System.IO.Path]::GetFileName(
    $drawingFolder.TrimEnd(
      [char[]]@(
        '\',
        '/'
      )
    )
  )

  if ($drawingFolderName -ine "Folhas NDT") {

    throw (
      "O desenho NDT nao esta diretamente dentro da pasta " +
      "'Folhas NDT'. Caminho: '$drawingPath'."
    )
  }

  $ndtParentFolder = [System.IO.Path]::GetDirectoryName(
    $drawingFolder
  )

  if ([string]::IsNullOrWhiteSpace($ndtParentFolder)) {

    throw (
      "Nao foi possivel identificar a pasta superior de " +
      "'$drawingFolder'."
    )
  }

  $ndtPdfFolder = Join-Path `
    -Path $ndtParentFolder `
    -ChildPath "Folhas NDT PDF"

  $ndtPdfFolderAvailableLocally = Test-Path `
    -LiteralPath $ndtPdfFolder `
    -PathType Container

  if (
    -not $ndtPdfFolderAvailableLocally -and
    $Details
  ) {

    Write-Warn (
      "A pasta Folhas NDT PDF nao esta disponivel no cache local. " +
      "A pesquisa sera realizada pelo indice do Vault. " +
      "Caminho esperado: '$ndtPdfFolder'."
    )
  }

  # ============================================================
  # 3. MONTAR O NOME EXATO ESPERADO
  # ============================================================

  $expectedPdfBaseName = "{0} [{1}] [{2}]" -f `
    $itemCodeClean,
    $ndtSheetTypeClean,
    $clientRevisionClean

  $expectedPdfName = $expectedPdfBaseName + ".PDF"

  if ($Details) {

    Write-Host "  Associando o PDF da Folha NDT:" -ForegroundColor Cyan

    Write-Host (
      "    Desenho:  '$drawingPath'"
    ) -ForegroundColor DarkGray

    Write-Host (
      "    Pasta:    '$ndtPdfFolder'"
    ) -ForegroundColor DarkGray

    Write-Host (
      "    Esperado: '$expectedPdfName'"
    ) -ForegroundColor DarkGray
  }

  # ============================================================
  # 4. PESQUISAR PRIMEIRO PELO VAULT
  # ============================================================

  $vault = Get-DcaVault
  $pdfCandidates = @()

  if ($null -ne $vault) {

    try {

      $vaultEntries = @(
        Search-DcaVaultPdfEntries `
          -Vault $vault `
          -SearchText (
            "*{0}*" -f $itemCodeClean
          )
      )

      $pdfCandidates = @(
        $vaultEntries |
          Where-Object {

            $candidateBaseName = ([string]$_.BaseName).Trim()
            $candidateFullName = ([string]$_.FullName).Trim()

            if ([string]::IsNullOrWhiteSpace($candidateFullName)) {
              return $false
            }

            if ($candidateBaseName -ine $expectedPdfBaseName) {
              return $false
            }

            $candidateFolderPath = [System.IO.Path]::GetDirectoryName(
              $candidateFullName
            )

            if ([string]::IsNullOrWhiteSpace($candidateFolderPath)) {
              return $false
            }

            $candidateFolderName = [System.IO.Path]::GetFileName(
              $candidateFolderPath.TrimEnd(
                [char[]]@(
                  '\',
                  '/'
                )
              )
            )

            return (
              $candidateFolderName -ieq "Folhas NDT PDF"
            )
          }
      )
    }
    catch {

      if ($Details) {

        Write-Warn (
          "A pesquisa do PDF NDT pelo Vault falhou: " +
          $_.Exception.Message +
          " A pesquisa sera repetida no disco."
        )
      }

      $pdfCandidates = @()
    }
  }

  # ============================================================
  # 5. UTILIZAR O DISCO COMO ALTERNATIVA
  # ============================================================

  if (
    $pdfCandidates.Count -eq 0 -and
    $ndtPdfFolderAvailableLocally
  ) {

    $diskFiles = @(
      Get-ChildItem `
        -LiteralPath $ndtPdfFolder `
        -Filter "*.pdf" `
        -File `
        -Force `
        -ErrorAction SilentlyContinue |
        Where-Object {
          $_.BaseName -ieq $expectedPdfBaseName
        }
    )

    $pdfCandidates = @(
      foreach ($diskFile in $diskFiles) {

        [PSCustomObject]@{
          Name = [string]$diskFile.Name
          BaseName = [string]$diskFile.BaseName
          FullName = [string]$diskFile.FullName
          Extension = [string]$diskFile.Extension
          DocumentType = "NDT"
          TypeDisplayName = "DCA NDT"
          IsNdtPdf = $true
          FromVault = $false
        }
      }
    )
  }

  # ============================================================
  # 6. VALIDAR A QUANTIDADE DE RESULTADOS
  # ============================================================

  if ($pdfCandidates.Count -eq 0) {

    throw (
      "PDF correspondente da Folha NDT nao encontrado. " +
      "Desenho: '$drawingPath'. " +
      "PDF esperado: '$expectedPdfName'. " +
      "Pasta pesquisada: '$ndtPdfFolder'."
    )
  }

  if ($pdfCandidates.Count -gt 1) {

    $candidatePaths = @(
      $pdfCandidates |
        ForEach-Object {
          [string]$_.FullName
        }
    )

    throw (
      "Foram encontrados varios PDFs para a Folha NDT " +
      "'$itemCodeClean [$ndtSheetTypeClean] " +
      "[$clientRevisionClean]': " +
      ($candidatePaths -join " | ")
    )
  }

  $selectedPdfEntry = $pdfCandidates[0]

  if ($Details) {

    Write-Success (
      "PDF correspondente da Folha NDT localizado: " +
      $selectedPdfEntry.FullName
    )
  }

  return $selectedPdfEntry
}
