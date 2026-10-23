# ============================================================
# LEITURA DOS DOCUMENTOS DE UMA PASTA
# ============================================================
#
# Este arquivo carrega os PDFs que estao diretamente dentro
# de uma pasta selecionada.
#
# A API do Vault e utilizada quando estiver disponivel.
# Caso contrario, os arquivos sao pesquisados no disco local.
#
# Para cada PDF, o fluxo:
#   1. interpreta o nome do arquivo;
#   2. identifica codigo, revisao e titulo;
#   3. consulta o estado do arquivo no PDM;
#   4. complementa revisao e descricao pelo cartao de dados;
#   5. prepara o objeto utilizado pelo lote de importacao.
#
# As subpastas nao sao processadas por este arquivo.
# ============================================================
function Get-DcaDocumentsFromFolderPath {

  # Carrega somente os PDFs diretamente dentro da pasta informada.
  # As subpastas sao tratadas separadamente pelo navegador.
  param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNull()]
    $FolderOption,

    $Vault
  )

  $pdfEntries =
  @()

  if ($null -ne $Vault) {

    $searchResults =
    @(
      Search-DcaVaultPdfEntries `
        -Vault $Vault `
        -SearchText "*" `
        -StartFolderPath $FolderOption.FullName
    )

    $pdfEntries =
    @(
      $searchResults |
        Where-Object {

        $pdfPath =
        [string]$_.FullName

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
        $FolderOption.FullName
      } |
        Sort-Object FullName
    )
  }
  else {

    $diskFiles =
    @(
      Get-ChildItem `
        -LiteralPath $FolderOption.FullName `
        -Filter "*.pdf" `
        -File `
        -Force `
        -ErrorAction SilentlyContinue
    )

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

  $documents =
  [System.Collections.Generic.List[object]]::new()

  foreach ($pdfEntry in $pdfEntries) {

    $parsedName =
    ConvertFrom-PdfFileName `
      -BaseName $pdfEntry.BaseName `
      -DocumentType $FolderOption.DocumentType

    $pdmState =
    Get-DcaPdmFileState `
      -Entry $pdfEntry

    $document =
    [PSCustomObject]@{
      File = $pdfEntry
      SourceCode = $parsedName.SourceCode
      ClientRevision = [string]$parsedName.ClientRevision
      DocumentTitle = $parsedName.DocumentTitle
      DocumentType = $FolderOption.DocumentType
      TypeDisplayName = $FolderOption.DisplayName
      CodeParsed = $parsedName.CodeParsed
      PdmState = $pdmState
      FolderImport = $true
      SourceFolder = $FolderOption.RelativePath
      CategoryFolder = $FolderOption.CategoryFolder
      TeamcenterItem = $null
      TeamcenterRevision = $null
    }

    Update-DcaMatchRevisionFromCard `
      -Match $document

    Update-DcaMatchDescriptionFromCard `
      -Match $document

    $documents.Add(
      $document
    )
  }

  return $documents.ToArray()
}