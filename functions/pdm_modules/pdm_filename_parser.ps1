# ============================================================
# INTERPRETACAO DOS NOMES DOS ARQUIVOS
# ============================================================
#
# Este arquivo interpreta os nomes dos PDFs e extrai as
# informacoes utilizadas pelo lote.
#
# Responsabilidades:
#   1. reconhecer codigos de Normas Externas;
#   2. separar o codigo tecnico do titulo;
#   3. extrair revisoes informadas entre colchetes;
#   4. preparar codigo, revisao e descricao inicial;
#   5. comparar o codigo pesquisado com o nome do PDF.
#
# Os dados extraidos do nome podem ser substituidos posteriormente
# pelos valores encontrados no cartao de dados do PDM.
# ============================================================
function Get-NormaCodeFromText {

  # Separa o codigo tecnico e o titulo de uma Norma Externa.
  # Regras especificas sao avaliadas antes das regras genericas
  # para evitar que prefixos curtos capturem codigos compostos.
  param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$Text
  )

  $normalizedText = $Text.Trim() -replace '\s+', ' '

  if (
    [string]::IsNullOrWhiteSpace(
      $normalizedText
    )
  ) {

    return [PSCustomObject]@{
      Code = $null
      Title = $null
      Parsed = $false
      Prefix = $null
      Pattern = $null
    }
  }

  # Prefixos maiores sao avaliados primeiro para impedir que uma
  # regra generica capture apenas parte de um codigo especifico.
  $knownPrefixes = @(
    "COL-ASQR-PRO",
    "AMS-QQ-C",
    "AMS-QQ-N",
    "AMS-QQ-P",
    "AMS-QQ-S",
    "MIL-HDBK",
    "QPL-AMS",
    "AMS-STD",
    "AMS-QQ",
    "MIL-STD",
    "MIL-PRF",
    "MIL-DTL",
    "FED-STD",
    "ASTM-MNL",
    "SNT-TC",
    "AMS STD",
    "AMS A",
    "AMS M",
    "AMS S",
    "AMS-C",
    "AMS-H",
    "AMS-S",
    "ASTM-A",
    "ASTM-B",
    "ASTM-D",
    "ASTM-E",
    "ASTM-F",
    "ASTM-G",
    "ASME B",
    "ASME Y",
    "ANSI H",
    "AWS D",
    "SAE J",
    "SAE-J",
    "MIL-A",
    "MIL-C",
    "MIL-H",
    "MIL-I",
    "MIL-L",
    "MIL-R",
    "MIL-S",
    "TT-P",
    "NEDE E",
    "ADDHS",
    "ASQR",
    "EMBRAER",
    "UTCQR",
    "FLIGHTPARTS",
    "AMS",
    "ARP",
    "ASTM",
    "ANSI",
    "ASME",
    "AWS",
    "CID",
    "MFG",
    "NASM",
    "NAS",
    "QPL",
    "BAC",
    "CPS",
    "HSC",
    "HSM",
    "SVHS",
    "PMP",
    "MIL",
    "MS",
    "MEP",
    "ZERO",
    "SAE",
    "ISO",
    "DIN",
    "AS",
    "CG",
    "HS",
    "PN",
    "QC",
    "NB",
    "NE",
    "RR",
    "UC",
    "E",
    "F"
  )

  $knownPrefixes = @(
    $knownPrefixes |
      Sort-Object {
      $_.Length
    } -Descending
  )

  # Formatos especiais utilizados pelas normas AMS.

  $specialPatterns = @(
    [PSCustomObject]@{
      Name = "AMS A numero sufixo"

      Prefix = "AMS A"

      Regex = '^(?<Code>AMS\s+A\s+\d+[A-Z0-9./-]*(?:\s+[A-Z])?)(?:\s+-?\s*(?<Title>.*))?$'
    }

    [PSCustomObject]@{
      Name = "AMS STD com espaco"

      Prefix = "AMS STD"

      Regex = '^(?<Code>AMS\s+STD\s+\d+[A-Z0-9./-]*)(?:\s+-?\s*(?<Title>.*))?$'
    }

    [PSCustomObject]@{
      Name = "AMS M com espaco"

      Prefix = "AMS M"

      Regex = '^(?<Code>AMS\s+M\s*\d+[A-Z0-9./-]*)(?:\s+-?\s*(?<Title>.*))?$'
    }

    [PSCustomObject]@{
      Name = "AMS S com espaco"

      Prefix = "AMS S"

      Regex = '^(?<Code>AMS\s+S\s*\d+[A-Z0-9./-]*)(?:\s+-?\s*(?<Title>.*))?$'
    }

    [PSCustomObject]@{
      Name = "AMS numerico com espaco"

      Prefix = "AMS"

      Regex = '^(?<Code>AMS\s+\d+[A-Z]?(?:-\d+)?)(?:\s+-?\s*(?<Title>.*))?$'
    }

    [PSCustomObject]@{
      Name = "AMS numerico sem espaco"

      Prefix = "AMS"

      Regex = '^(?<Code>AMS\d+[A-Z]?(?:-\d+)?)(?:\s+-?\s*(?<Title>.*))?$'
    }

    [PSCustomObject]@{
      Name = "AMS composto com hifen"

      Prefix = "AMS composto"

      Regex = '^(?<Code>AMS(?:-[A-Z0-9]+)+)(?:\s+-?\s*(?<Title>.*))?$'
    }
  )

  foreach ($specialPattern in $specialPatterns) {

    if (
      $normalizedText -notmatch
      $specialPattern.Regex
    ) {
      continue
    }

    $code = [string]$Matches["Code"]

    $title = $null

    if ($Matches.ContainsKey("Title")) {

      $title = [string]$Matches["Title"]
    }

    if (
      -not [string]::IsNullOrWhiteSpace(
        $title
      )
    ) {

      $title = $title.Trim().TrimStart("-", " ").TrimEnd(".", " ")
    }
    else {

      $title = $null
    }

    return [PSCustomObject]@{
      Code = $code.Trim()

      Title = $title

      Parsed = $true

      Prefix = [string]$specialPattern.Prefix

      Pattern = [string]$specialPattern.Name
    }
  }

  # Regras baseadas nos prefixos tecnicos conhecidos.

  foreach ($prefix in $knownPrefixes) {

    # Prefixos compostos aceitam variacao na quantidade de espacos.
    $prefixRegex = [regex]::Escape($prefix)

    $prefixRegex = $prefixRegex.Replace(
      "\ ",
      "\s+"
    )

    # O identificador deve conter pelo menos um numero para nao
    # confundir uma descricao comum com um codigo tecnico.
    $pattern = (
      "^(?<Code>" +
      $prefixRegex +
      "(?:\s*-\s*|\s*)" +
      "[A-Z0-9./-]*\d[A-Z0-9./-]*" +
      "(?:\s+[A-Z])?" +
      ")" +
      "(?:\s+-?\s*(?<Title>.*))?$"
    )

    if ($normalizedText -notmatch $pattern) {
      continue
    }
    $code = [string]$Matches["Code"]

    if ([string]::IsNullOrWhiteSpace($code)) {
      continue
    }

    $code = $code.Trim()

    $title = $null

    if ($Matches.ContainsKey("Title")) {

      $title = [string]$Matches["Title"]
    }

    if (
      -not [string]::IsNullOrWhiteSpace(
        $title
      )
    ) {

      $title = $title.Trim()

      $title = $title.TrimStart(
        "-",
        "_",
        " "
      )

      $title = $title.TrimEnd(
        ".",
        " "
      )
    }
    else {

      $title = $null
    }

    return [PSCustomObject]@{
      Code = $code

      Title = $title

      Parsed = $true

      Prefix = $prefix

      Pattern = "Prefixo conhecido: $prefix"
    }
  }

  # Aceita diretamente codigos sem espacos que contenham pelo
  # menos um numero.
  if (
    $normalizedText -notmatch '\s' -and
    $normalizedText -match '\d' -and
    $normalizedText -match
    '^[A-Z0-9][A-Z0-9./_-]*$'
  ) {

    return [PSCustomObject]@{
      Code = $normalizedText

      Title = $null

      Parsed = $true

      Prefix = "Codigo completo"

      Pattern = "Codigo tecnico sem descricao"
    }
  }

  # Ultima tentativa para separar um codigo tecnico de sua
  # descricao quando nenhum prefixo conhecido foi identificado.
  $genericPattern = (
    "^(?<Code>" +
    "[A-Z][A-Z0-9-]*" +
    "(?:\s+[A-Z]+)?" +
    "(?:[- ]?[A-Z]*)?" +
    "[- ]?\d+[A-Z0-9./-]*" +
    ")" +
    "(?:\s+-?\s*(?<Title>.*))?$"
  )

  if ($normalizedText -match $genericPattern) {

    $genericCode = [string]$Matches["Code"]

    $genericTitle = $null

    if ($Matches.ContainsKey("Title")) {

      $genericTitle = [string]$Matches["Title"]
    }

    if (
      -not [string]::IsNullOrWhiteSpace(
        $genericTitle
      )
    ) {

      $genericTitle = $genericTitle.Trim().TrimStart("-", " ").TrimEnd(".", " ")
    }
    else {

      $genericTitle = $null
    }

    return [PSCustomObject]@{
      Code = $genericCode.Trim()

      Title = $genericTitle

      Parsed = $true

      Prefix = "Generico"

      Pattern = "Codigo tecnico generico"
    }
  }

  return [PSCustomObject]@{
    Code = $normalizedText

    Title = $null

    Parsed = $false

    Prefix = "NAO_IDENTIFICADO"

    Pattern = $null
  }
}

function ConvertFrom-PdfFileName {

  # Extrai codigo, revisao e titulo do nome fisico do PDF.
  # Os dados do cartao podem substituir posteriormente os
  # valores obtidos somente pelo nome do arquivo.
  param(
    [Parameter(Mandatory = $true)]
    [string]$BaseName,

    [Parameter(Mandatory = $true)]
    [ValidateSet(
      "Original",
      "Processo",
      "NormaExterna",
      "DatasetOnly"
    )]
    [string]$DocumentType
  )

  $name = $BaseName.Trim()
  $sourceCodeText = $name
  $clientRevision = $null

  if (
    $name -match
    '^(?<Code>[^\[\]]+?)\s*\[(?<BracketValue>[^\]]+)\]\s*$'
  ) {

    $possibleCode =
    $Matches["Code"].Trim()

    $possibleRevision =
    $Matches["BracketValue"].Trim().ToUpper()

    $validRevision =
    $false

    if (
      $DocumentType -eq "Processo" -or
      $DocumentType -eq "DatasetOnly"
    ) {

      # Processo: A1, BA4, AA4 ou --4.
      $validRevision =
      $possibleRevision -match
      '^[A-Z0-9-]{1,2}\d$'
    }
    elseif ($DocumentType -eq "Original") {

      # Original: uma ou duas letras/numeros.
      $validRevision =
      $possibleRevision -match
      '^[A-Z0-9]{1,2}$'
    }

    elseif ($DocumentType -eq "NormaExterna") {

      # Aceita uma revisao tecnica entre colchetes. Durante a
      # pesquisa, a revisao do cartao ainda possui prioridade.
      $validRevision =
      $possibleRevision -match
      '^[A-Z0-9.-]{1,10}$'
    }

    if ($validRevision) {

      $sourceCodeText =
      $possibleCode

      $clientRevision =
      $possibleRevision
    }
    else {

      # O texto entre colchetes nao e uma revisao.
      # Mantem o codigo anterior aos colchetes, mas deixa
      # a revisao vazia para o tratamento posterior.
      $sourceCodeText =
      $possibleCode

      $clientRevision =
      $null
    }
  }

  $codeParsed = $true

  $documentTitle = $null

  if ($DocumentType -eq "NormaExterna") {

    $normaInfo = Get-NormaCodeFromText `
      -Text $sourceCodeText

    $sourceCodeText = $normaInfo.Code

    $documentTitle = $normaInfo.Title

    $codeParsed = $normaInfo.Parsed
  }

  return [PSCustomObject]@{
    SourceCode = $sourceCodeText
    ClientRevision = $clientRevision
    DocumentTitle = $documentTitle
    CodeParsed = $codeParsed
  }
}
function Test-DcaCodeMatch {

  # Compara o termo pesquisado com o nome original do PDF e com
  # o codigo tecnico extraido desse nome.
  param(
    [string]$BaseName,
    [string]$ParsedCode,
    [string]$Pattern,
    [bool]$UsesWildcard
  )

  if ($UsesWildcard) {
    return (($BaseName -like $Pattern) -or ($ParsedCode -like $Pattern))
  }

  return (($BaseName -ieq $Pattern) -or ($ParsedCode -ieq $Pattern))
}
