# ============================================================
# NORMALIZACAO DOS DADOS DO DOCUMENTO
# ============================================================
# Aplica ao documento os dados do cartao do SOLIDWORKS PDM.
#   1. seleciona as variaveis de revisao e descricao por tipo;
#   2. normaliza a descricao do Desenho Original;
#   3. substitui descricao e revisao extraidas do nome pelas do cartao;
#   4. registra a origem de cada valor (DescriptionSource / RevisionSource).
# Os valores do cartao tem prioridade sobre os extraidos do nome do PDF.
# ============================================================

# Divide um valor do .env em nomes de variaveis (separador | ou ;), sem vazios nem repetidos.
function Split-DcaVariableNames {
    param([string]$ConfiguredValue)

    return @(
        ([string]$ConfiguredValue) -split '[|;]' |
            ForEach-Object { $_.Trim() } |
            Where-Object { $_ } |
            Select-Object -Unique
    )
}

function Get-DcaCardRevisionVariableNames {
    param(
        [Parameter(Mandatory)]
        [ValidateSet("Original", "Processo", "NormaExterna", "DatasetOnly", "NDT")]
        [string]$DocumentType
    )

    # Cada tipo usa uma variavel diferente do .env.
    $configuredValue = switch ($DocumentType) {
        "Original"     { $env:DCA_PDM_VAR_ORIGINAL_REVISION }
        { $_ -in "Processo", "NDT" } { $env:DCA_PDM_VAR_PROCESS_REVISION }
        "NormaExterna" { $env:DCA_PDM_VAR_STANDARD_REVISION }
        "DatasetOnly"  { $env:DCA_PDM_VAR_DATASET_REVISION }
    }

    return @(Split-DcaVariableNames -ConfiguredValue $configuredValue)
}

function Convert-DcaOriginalDescription {
    param([string]$Description)

    # Virgulas do cartao viram espacos; espacos duplicados sao removidos.
    $text = (([string]$Description).Replace(",", " ") -replace '\s+', ' ').Trim()
    if (-not $text) { return $null }

    # Padrao de nome do Teamcenter: primeira letra maiuscula, o resto minusculo.
    return $text.Substring(0, 1).ToUpperInvariant() + $text.Substring(1).ToLowerInvariant()
}

function Set-DcaMatchSource {
    param($Match, [string]$Name, $Value)

    Add-Member -InputObject $Match -NotePropertyName $Name -NotePropertyValue $Value -Force
}

function Update-DcaMatchDescriptionFromCard {
    param([Parameter(Mandatory)][ValidateNotNull()]$Match)

    # DatasetOnly nao depende do cartao: sem titulo, usa o codigo.
    if ($Match.DocumentType -eq "DatasetOnly") {
        if ([string]::IsNullOrWhiteSpace([string]$Match.DocumentTitle)) {
            $Match.DocumentTitle = [string]$Match.SourceCode
        }
        Set-DcaMatchSource $Match "DescriptionSource" "codigo do documento"
        return
    }

    # Variavel de descricao configurada no .env para o tipo.
    $descriptionVariable = switch ($Match.DocumentType) {
        { $_ -in "Processo", "NDT" } { $env:DCA_PDM_VAR_PROCESS_DESCRIPTION }
        "Original"                   { $env:DCA_PDM_VAR_ORIGINAL_DESCRIPTION }
        "NormaExterna"               { $env:DCA_PDM_VAR_STANDARD_DESCRIPTION }
    }
    $variableNames = @(Split-DcaVariableNames -ConfiguredValue $descriptionVariable)

    if ($variableNames.Count -eq 0) {
        Set-DcaMatchSource $Match "DescriptionSource" "nao configurada"
        return
    }

    $cardDescription = ([string](Get-DcaPdmVariableValue -Entry $Match.File -VariableNames $variableNames)).Trim()
    if ($Match.DocumentType -eq "Original") {
        $cardDescription = Convert-DcaOriginalDescription -Description $cardDescription
    }

    # Cartao sem valor utilizavel: mantem o titulo anterior.
    if ([string]::IsNullOrWhiteSpace($cardDescription)) {
        Set-DcaMatchSource $Match "DescriptionSource" "cartao vazio"
        if ($Details) {
            Write-Warn (
                "A descricao do cartao esta vazia em '$($Match.File.Name)'. " +
                "Variavel(is): '$($variableNames -join "', '")'."
            )
        }
        return
    }

    # Descricao valida do cartao substitui o titulo vindo do nome do PDF.
    $Match.DocumentTitle = $cardDescription
    Set-DcaMatchSource $Match "CardDescription" $cardDescription
    Set-DcaMatchSource $Match "DescriptionSource" "cartao de dados"

    if ($Details) { Write-Host "  Descricao do cartao: '$cardDescription'" -ForegroundColor Cyan }
}

function Update-DcaMatchRevisionFromCard {
    param([Parameter(Mandatory)][ValidateNotNull()]$Match)

    # Revisao do nome do arquivo, preservada para registrar a origem.
    $fileRevision   = ([string]$Match.ClientRevision).Trim().ToUpperInvariant()
    $revisionSource = "nome do arquivo"

    $variableNames = @(Get-DcaCardRevisionVariableNames -DocumentType ([string]$Match.DocumentType))

    if ($Details) {
        $display = if ($variableNames.Count -gt 0) { $variableNames -join ", " } else { "<nenhuma>" }
        Write-Host "  Variaveis de revisao configuradas: $display" -ForegroundColor DarkGray
    }

    if ($variableNames.Count -gt 0) {
        $cardRevision = Get-DcaPdmVariableValue -Entry $Match.File -VariableNames $variableNames

        if ($Details) {
            Write-Host "  Cartao de dados: $($Match.File.Name)" -ForegroundColor Cyan
            Write-Host "    Variavel(is) testada(s): $($variableNames -join ', ')" -ForegroundColor DarkGray
            if ([string]::IsNullOrWhiteSpace([string]$cardRevision)) {
                Write-Host "    Revisao do cartao: nao encontrada ou vazia" -ForegroundColor Yellow
            }
            else {
                Write-Host "    Revisao do cartao: [$cardRevision]" -ForegroundColor Green
            }
        }

        # Revisao valida do cartao substitui a extraida do nome do PDF.
        if (-not [string]::IsNullOrWhiteSpace([string]$cardRevision)) {
            $Match.ClientRevision = ([string]$cardRevision).Trim().ToUpperInvariant()
            $revisionSource = "cartao de dados"
        }
    }
    elseif ($Details) {
        # Sem variavel configurada: indica qual propriedade falta no .env.
        $configurationName = switch ($Match.DocumentType) {
            "Original"                   { "DCA_PDM_VAR_ORIGINAL_REVISION" }
            { $_ -in "Processo", "NDT" } { "DCA_PDM_VAR_PROCESS_REVISION" }
            "NormaExterna"               { "DCA_PDM_VAR_STANDARD_REVISION" }
            "DatasetOnly"                { "DCA_PDM_VAR_DATASET_REVISION" }
            default                      { "a variavel de revisao correspondente" }
        }
        Write-Warn "Nenhuma variavel de revisao do cartao foi configurada para o tipo '$($Match.DocumentType)'."
        Write-Host "  Configure $configurationName no arquivo .env." -ForegroundColor DarkGray
    }

    Set-DcaMatchSource $Match "FileRevision" $fileRevision
    Set-DcaMatchSource $Match "RevisionSource" $revisionSource
}