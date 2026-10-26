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

  # ============================================================
  # 1. NORMALIZAR O TEXTO RECEBIDO
  # ============================================================
  #
  # Remove espacos das extremidades e substitui sequencias de
  # espacos por um unico espaco antes de aplicar as regras de
  # reconhecimento do codigo.
  $normalizedText = $Text.Trim() -replace '\s+', ' '

  # Um texto vazio nao possui codigo ou titulo identificavel.
  # O retorno mantem a mesma estrutura utilizada pelos demais
  # resultados, mas indica que a interpretacao nao foi concluida.
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

  # ============================================================
  # 2. PREPARAR OS PREFIXOS TECNICOS CONHECIDOS
  # ============================================================
  #
  # A lista contem os prefixos reconhecidos para Normas Externas.
  # Prefixos maiores sao avaliados primeiro para impedir que uma
  # regra generica capture somente parte de um codigo composto.
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

  # Ordena os prefixos pelo tamanho em ordem decrescente. Assim,
  # por exemplo, MIL-STD e avaliado antes do prefixo MIL.
  $knownPrefixes = @(
    $knownPrefixes |
      Sort-Object {
      $_.Length
    } -Descending
  )

  # ============================================================
  # 3. AVALIAR OS FORMATOS ESPECIAIS AMS
  # ============================================================
  #
  # Algumas normas AMS utilizam estruturas que nao podem ser
  # interpretadas corretamente apenas pela lista de prefixos.
  #
  # Cada regra informa um nome para diagnostico, o prefixo
  # correspondente e a expressao regular utilizada na leitura.
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

  # As regras sao verificadas na ordem em que foram declaradas.
  # A primeira correspondencia valida encerra a interpretacao.
  foreach ($specialPattern in $specialPatterns) {

    if (
      $normalizedText -notmatch
      $specialPattern.Regex
    ) {
      continue
    }

    # Os grupos nomeados Code e Title foram preenchidos pela
    # expressao regular correspondente ao formato reconhecido.
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

      # Remove separadores residuais entre o codigo e o titulo,
      # alem do ponto final que pode existir no nome do arquivo.
      $title = $title.Trim().TrimStart("-", " ").TrimEnd(".", " ")
    }
    else {

      $title = $null
    }

    # Retorna imediatamente porque um formato especial conhecido
    # foi reconhecido com sucesso.
    return [PSCustomObject]@{
      Code = $code.Trim()

      Title = $title

      Parsed = $true

      Prefix = [string]$specialPattern.Prefix

      Pattern = [string]$specialPattern.Name
    }
  }

  # ============================================================
  # 4. AVALIAR OS PREFIXOS TECNICOS CONHECIDOS
  # ============================================================
  #
  # Quando nenhum formato especial for reconhecido, o texto sera
  # comparado com os prefixos tecnicos cadastrados anteriormente.
  foreach ($prefix in $knownPrefixes) {

    # Escapa os caracteres especiais do prefixo e permite variacao
    # na quantidade de espacos dos prefixos compostos.
    $prefixRegex = [regex]::Escape($prefix)

    $prefixRegex = $prefixRegex.Replace(
      "\ ",
      "\s+"
    )

    # A expressao combina o prefixo atual com o restante do codigo.
    # O identificador deve conter pelo menos um numero para evitar
    # que uma descricao comum seja aceita como codigo tecnico.
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

      # Remove os separadores que podem permanecer entre o codigo
      # tecnico e a descricao encontrada no nome do arquivo.
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

    # Retorna o codigo e o titulo obtidos pela regra associada ao
    # prefixo conhecido atual.
    return [PSCustomObject]@{
      Code = $code

      Title = $title

      Parsed = $true

      Prefix = $prefix

      Pattern = "Prefixo conhecido: $prefix"
    }
  }

  # ============================================================
  # 5. ACEITAR UM CODIGO TECNICO COMPLETO
  # ============================================================
  #
  # Quando o texto nao possuir espacos, mas contiver pelo menos
  # um numero e somente caracteres tecnicos permitidos, todo o
  # valor sera utilizado como codigo.
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

  # ============================================================
  # 6. APLICAR A REGRA TECNICA GENERICA
  # ============================================================
  #
  # Esta e a ultima tentativa de separar um codigo tecnico de sua
  # descricao quando nenhum formato especial ou prefixo conhecido
  # tiver sido identificado.
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

      # Remove separadores residuais entre o codigo generico e
      # sua descricao.
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

  # ============================================================
  # 7. RETORNAR UM CODIGO NAO IDENTIFICADO
  # ============================================================
  #
  # Quando nenhuma regra reconhecer o formato, preserva o texto
  # normalizado como codigo provisório. Parsed igual a false
  # permite que o fluxo solicite ou trate o codigo posteriormente.
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

  # ============================================================
  # 1. PREPARAR O NOME DO ARQUIVO
  # ============================================================
  #
  # Remove espacos das extremidades e utiliza inicialmente todo
  # o nome base como codigo de origem.
  $name = $BaseName.Trim()
  $sourceCodeText = $name
  $clientRevision = $null

  # ============================================================
  # 2. EXTRAIR O VALOR ENTRE COLCHETES
  # ============================================================
  #
  # Quando o nome terminar com um valor entre colchetes, separa
  # o codigo anterior aos colchetes e verifica se o valor possui
  # um formato de revisao valido para o tipo de documento.
  if (
    $name -match
    '^(?<Code>[^\[\]]+?)\s*\[(?<BracketValue>[^\]]+)\]\s*$'
  ) {

    $possibleCode =
    $Matches["Code"].Trim()

    $possibleRevision =
    $Matches["BracketValue"].Trim().ToUpper()

    # Cada tipo de documento possui uma regra propria para validar
    # o formato da revisao encontrada entre colchetes.
    $validRevision =
    $false

    if (
      $DocumentType -eq "Processo" -or
      $DocumentType -eq "DatasetOnly"
    ) {

      # Processo e DatasetOnly aceitam formatos como A1, BA4,
      # AA4 ou --4.
      $validRevision =
      $possibleRevision -match
      '^[A-Z0-9-]{1,2}\d$'
    }
    elseif ($DocumentType -eq "Original") {

      # Desenho Original aceita uma ou duas letras ou numeros.
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

    # Somente um valor reconhecido pela regra do tipo atual sera
    # armazenado como revisao do cliente.
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

  # ============================================================
  # 3. INTERPRETAR O CODIGO E O TITULO
  # ============================================================
  #
  # Os tipos comuns utilizam diretamente o codigo separado do
  # nome. Normas Externas passam por regras adicionais para
  # separar o codigo tecnico de sua descricao.
  $codeParsed = $true

  $documentTitle = $null

  # Norma Externa pode possuir codigo e descricao no mesmo nome.
  # Get-NormaCodeFromText realiza essa separacao e informa se o
  # formato do codigo foi reconhecido.
  if ($DocumentType -eq "NormaExterna") {

    $normaInfo = Get-NormaCodeFromText `
      -Text $sourceCodeText

    $sourceCodeText = $normaInfo.Code

    $documentTitle = $normaInfo.Title

    $codeParsed = $normaInfo.Parsed
  }

  # ============================================================
  # 4. RETORNAR OS DADOS INTERPRETADOS
  # ============================================================
  #
  # Retorna uma estrutura unica para todos os tipos de documento.
  # Esses valores ainda podem ser substituidos posteriormente
  # pelos dados obtidos no cartao do PDM.
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

  # ============================================================
  # 1. COMPARAR O CODIGO PESQUISADO
  # ============================================================
  #
  # A comparacao considera tanto o nome original do PDF quanto o
  # codigo tecnico obtido pela interpretacao do nome.
  #
  # Quando a pesquisa utilizar curingas, aplica -like. Nos demais
  # casos, exige correspondencia completa sem diferenciar letras
  # maiusculas e minusculas.
  if ($UsesWildcard) {
    return (($BaseName -like $Pattern) -or ($ParsedCode -like $Pattern))
  }

  return (($BaseName -ieq $Pattern) -or ($ParsedCode -ieq $Pattern))
}
