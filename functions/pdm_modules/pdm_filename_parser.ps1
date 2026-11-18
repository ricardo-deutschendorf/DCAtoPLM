# ============================================================
# INTERPRETACAO DOS NOMES DOS ARQUIVOS
# ============================================================
#   1. reconhece codigos de Normas Externas e separa o titulo;
#   2. extrai a revisao informada entre colchetes;
#   3. prepara codigo, revisao e descricao iniciais;
#   4. compara o codigo pesquisado com o nome do PDF.
# Os dados extraidos do nome podem ser substituidos depois pelos
# valores do cartao de dados do PDM.
# ============================================================

# Limpa o titulo: remove separadores no inicio e o ponto final. Retorna $null se vazio.
function Format-DcaNormaTitle {
    param([string]$Title, [char[]]$LeadingChars = @('-', ' '))

    if ([string]::IsNullOrWhiteSpace($Title)) { return $null }
    return $Title.Trim().TrimStart($LeadingChars).TrimEnd('.', ' ')
}

function New-DcaNormaResult {
    param($Code, $Title, [bool]$Parsed, $Prefix, $Pattern)

    return [PSCustomObject]@{ Code = $Code; Title = $Title; Parsed = $Parsed; Prefix = $Prefix; Pattern = $Pattern }
}

function Get-NormaCodeFromText {
    # Separa o codigo tecnico e o titulo de uma Norma Externa.
    # Regras especificas vem antes das genericas para que prefixos curtos
    # nao capturem codigos compostos.
    param([Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$Text)

    $normalizedText = ($Text.Trim() -replace '\s+', ' ')
    if (-not $normalizedText) { return New-DcaNormaResult $null $null $false $null $null }

    # --- Prefixos tecnicos conhecidos (os mais longos sao avaliados primeiro) ---
    $knownPrefixes = @(
        "COL-ASQR-PRO", "AMS-QQ-C", "AMS-QQ-N", "AMS-QQ-P", "AMS-QQ-S", "MIL-HDBK", "QPL-AMS", "AMS-STD",
        "AMS-QQ", "MIL-STD", "MIL-PRF", "MIL-DTL", "FED-STD", "ASTM-MNL", "SNT-TC", "AMS STD", "AMS A",
        "AMS M", "AMS S", "AMS-C", "AMS-H", "AMS-S", "ASTM-A", "ASTM-B", "ASTM-D", "ASTM-E", "ASTM-F",
        "ASTM-G", "ASME B", "ASME Y", "ANSI H", "AWS D", "SAE J", "SAE-J", "MIL-A", "MIL-C", "MIL-H",
        "MIL-I", "MIL-L", "MIL-R", "MIL-S", "TT-P", "NEDE E", "ADDHS", "ASQR", "EMBRAER", "UTCQR",
        "FLIGHTPARTS", "AMS", "ARP", "ASTM", "ANSI", "ASME", "AWS", "CID", "MFG", "NASM", "NAS", "QPL",
        "BAC", "CPS", "HSC", "HSM", "SVHS", "PMP", "MIL", "MS", "MEP", "ZERO", "SAE", "ISO", "DIN", "AS",
        "CG", "HS", "PN", "QC", "NB", "NE", "RR", "UC", "E", "F"
    ) | Sort-Object { $_.Length } -Descending

    # --- 1. Formatos especiais AMS (avaliados na ordem; o primeiro que casar encerra) ---
    $tail = '(?:\s+-?\s*(?<Title>.*))?$'
    $specialPatterns = @(
        @{ Name = "AMS A numero sufixo";     Prefix = "AMS A";       Regex = '^(?<Code>AMS\s+A\s+\d+[A-Z0-9./-]*(?:\s+[A-Z])?)' + $tail }
        @{ Name = "AMS STD com espaco";      Prefix = "AMS STD";     Regex = '^(?<Code>AMS\s+STD\s+\d+[A-Z0-9./-]*)' + $tail }
        @{ Name = "AMS M com espaco";        Prefix = "AMS M";       Regex = '^(?<Code>AMS\s+M\s*\d+[A-Z0-9./-]*)' + $tail }
        @{ Name = "AMS S com espaco";        Prefix = "AMS S";       Regex = '^(?<Code>AMS\s+S\s*\d+[A-Z0-9./-]*)' + $tail }
        @{ Name = "AMS numerico com espaco"; Prefix = "AMS";         Regex = '^(?<Code>AMS\s+\d+[A-Z]?(?:-\d+)?)' + $tail }
        @{ Name = "AMS numerico sem espaco"; Prefix = "AMS";         Regex = '^(?<Code>AMS\d+[A-Z]?(?:-\d+)?)' + $tail }
        @{ Name = "AMS composto com hifen";  Prefix = "AMS composto"; Regex = '^(?<Code>AMS(?:-[A-Z0-9]+)+)' + $tail }
    )

    foreach ($special in $specialPatterns) {
        if ($normalizedText -notmatch $special.Regex) { continue }

        return New-DcaNormaResult ([string]$Matches["Code"]).Trim() (Format-DcaNormaTitle $Matches["Title"]) `
            $true $special.Prefix $special.Name
    }

    # --- 2. Prefixos conhecidos (o identificador precisa ter ao menos um numero) ---
    foreach ($prefix in $knownPrefixes) {
        $prefixRegex = [regex]::Escape($prefix).Replace("\ ", "\s+")
        $pattern = "^(?<Code>$prefixRegex(?:\s*-\s*|\s*)[A-Z0-9./-]*\d[A-Z0-9./-]*(?:\s+[A-Z])?)$tail"

        if ($normalizedText -notmatch $pattern) { continue }

        $code = ([string]$Matches["Code"]).Trim()
        if (-not $code) { continue }

        return New-DcaNormaResult $code (Format-DcaNormaTitle $Matches["Title"] @('-', '_', ' ')) `
            $true $prefix "Prefixo conhecido: $prefix"
    }

    # --- 3. Codigo tecnico completo, sem espacos e com ao menos um numero ---
    if (
        $normalizedText -notmatch '\s' -and
        $normalizedText -match '\d' -and
        $normalizedText -match '^[A-Z0-9][A-Z0-9./_-]*$'
    ) {
        return New-DcaNormaResult $normalizedText $null $true "Codigo completo" "Codigo tecnico sem descricao"
    }

    # --- 4. Regra tecnica generica ---
    $genericPattern = '^(?<Code>[A-Z][A-Z0-9-]*(?:\s+[A-Z]+)?(?:[- ]?[A-Z]*)?[- ]?\d+[A-Z0-9./-]*)' + $tail
    if ($normalizedText -match $genericPattern) {
        return New-DcaNormaResult ([string]$Matches["Code"]).Trim() (Format-DcaNormaTitle $Matches["Title"]) `
            $true "Generico" "Codigo tecnico generico"
    }

    # --- 5. Nao identificado: preserva o texto como codigo provisorio ---
    return New-DcaNormaResult $normalizedText $null $false "NAO_IDENTIFICADO" $null
}

function ConvertFrom-PdfFileName {
    # Extrai codigo, revisao e titulo do nome fisico do PDF.
    param(
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$BaseName,
        [Parameter(Mandatory)]
        [ValidateSet("Original", "Processo", "NormaExterna", "DatasetOnly", "NDT")]
        [string]$DocumentType
    )

    if ($Details) {
        Write-Host ("  ConvertFrom-PdfFileName carregado de: {0}" -f $MyInvocation.MyCommand.ScriptBlock.File) -ForegroundColor DarkGray
        Write-Host ("  DocumentType recebido: '{0}'" -f $DocumentType) -ForegroundColor DarkGray
    }

    $name = $BaseName.Trim()
    if (-not $name) { throw "O nome base do PDF ficou vazio." }

    $sourceCodeText = $name
    $clientRevision = $null
    $ndtSheetType = $null

    # --- Valor entre colchetes no fim do nome ---
    if ($name -match '^(?<Code>[^\[\]]+?)\s*\[(?<BracketValue>[^\]]+)\]\s*$') {
        $possibleCode = $Matches["Code"].Trim()
        $possibleRevision = $Matches["BracketValue"].Trim().ToUpperInvariant()

        # MPI ou FPI identifica o tipo da Folha NDT.
        if ($DocumentType -eq "NDT" -and $possibleRevision -match '^(MPI|FPI)$') {
            $ndtSheetType = $possibleRevision
        }

        # Formato de revisao valido para cada tipo (NDT nao tem: a revisao vem do cartao).
        $revisionRegex = switch ($DocumentType) {
            { $_ -in "Processo", "DatasetOnly" } { '^[A-Z0-9-]{1,3}\d$' }   # A1, BA4, AA4, --4
            "Original"                           { '^[A-Z0-9]{1,2}$' }
            "NormaExterna"                       { '^[A-Z0-9.-]{1,10}$' }   # o cartao ainda tem prioridade
            default                              { $null }
        }

        if ($revisionRegex -and $possibleRevision -match $revisionRegex) {
            $sourceCodeText = $possibleCode
            $clientRevision = $possibleRevision
        }
        elseif ($ndtSheetType) {
            $sourceCodeText = $possibleCode
        }
    }

    # --- Norma Externa: separa codigo tecnico e descricao ---
    $codeParsed = $true
    $documentTitle = $null
    if ($DocumentType -eq "NormaExterna") {
        $normaInfo = Get-NormaCodeFromText -Text $sourceCodeText
        $sourceCodeText = $normaInfo.Code
        $documentTitle = $normaInfo.Title
        $codeParsed = $normaInfo.Parsed
    }

    return [PSCustomObject]@{
        SourceCode     = ([string]$sourceCodeText).Trim()
        ClientRevision = ([string]$clientRevision).Trim().ToUpperInvariant()
        DocumentTitle  = ([string]$documentTitle).Trim()
        CodeParsed     = $codeParsed
        NdtSheetType   = ([string]$ndtSheetType).Trim().ToUpperInvariant()
    }
}

function Test-DcaCodeMatch {
    # Compara o termo pesquisado com o nome do PDF e com o codigo extraido dele.
    param(
        [AllowEmptyString()][string]$BaseName,
        [AllowEmptyString()][string]$ParsedCode,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$Pattern,
        [Parameter(Mandatory)][bool]$UsesWildcard
    )

    $baseNameText = ([string]$BaseName).Trim()
    $parsedCodeText = ([string]$ParsedCode).Trim()
    $patternText = $Pattern.Trim()
    if (-not $patternText) { return $false }

    # Com curingas usa -like; sem curingas exige correspondencia completa (sem diferenciar maiusculas).
    if ($UsesWildcard) { return ($baseNameText -like $patternText -or $parsedCodeText -like $patternText) }
    return ($baseNameText -ieq $patternText -or $parsedCodeText -ieq $patternText)
}