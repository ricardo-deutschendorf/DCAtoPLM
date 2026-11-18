# ============================================================
# LOGS E RELATORIOS DA EXECUCAO
# ============================================================
# Cria logs e relatorios CSV da execucao e carrega falhas para
# nova tentativa. Nenhuma senha deve ser registrada.
# ============================================================

# Converte valores textuais comuns em booleano.
function ConvertTo-DcaReportBoolean {
    param($Value)

    return ([string]$Value).Trim() -match '^(?i:true|1|sim|yes)$'
}

# Retorna uma coluna opcional do relatorio ou texto vazio.
function Get-DcaReportOptionalText {
    param(
        [Parameter(Mandatory)]$Row,
        [Parameter(Mandatory)][string[]]$AvailableColumns,
        [Parameter(Mandatory)][string]$Column
    )

    if ($AvailableColumns -notcontains $Column) { return "" }
    return ([string]$Row.$Column).Trim()
}

# Prepara os caminhos e inicia o log da execucao.
function Initialize-DcaExecutionArtifacts {
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$ProjectRoot
    )

    $script:DcaExecutionStartedAt = Get-Date
    $script:DcaExecutionId = $script:DcaExecutionStartedAt.ToString("yyyyMMdd_HHmmss_fff")

    $temporaryFolder = ([string]$env:DCA_TEMP_FOLDER).Trim()
    if ([string]::IsNullOrWhiteSpace($temporaryFolder)) {
        throw "DCA_TEMP_FOLDER deve ser configurado no arquivo .env antes da preparacao dos logs e relatorios."
    }

    $logFolder = Join-Path $temporaryFolder "logs"
    $reportFolder = Join-Path $temporaryFolder "reports"

    foreach ($folder in @($logFolder, $reportFolder)) {
        if (-not (Test-Path -LiteralPath $folder -PathType Container)) {
            $null = New-Item -Path $folder -ItemType Directory -Force -ErrorAction Stop
        }
    }

    $script:DcaLogFilePath = Join-Path $logFolder "DCAtoPLM_$($script:DcaExecutionId).log"
    $script:DcaReportFilePath = Join-Path $reportFolder "DCAtoPLM_$($script:DcaExecutionId).csv"
    $script:DcaTranscriptStarted = $false

    try {
        Start-Transcript -LiteralPath $script:DcaLogFilePath -Force -ErrorAction Stop | Out-Null
        $script:DcaTranscriptStarted = $true
        Write-Info "Log da execucao: $script:DcaLogFilePath"
    }
    catch {
        Write-Warn "Nao foi possivel iniciar o arquivo de log: $($_.Exception.Message)"
    }
}

# Encerra o log somente quando o transcript foi iniciado.
function Stop-DcaExecutionLog {
    if ($script:DcaTranscriptStarted -ne $true) { return }

    try {
        Write-Info "Encerrando o log da execucao."
        Stop-Transcript -ErrorAction Stop | Out-Null
    }
    catch {
        Write-Warn "Nao foi possivel encerrar corretamente o log: $($_.Exception.Message)"
    }
    finally {
        $script:DcaTranscriptStarted = $false
    }
}

# Exporta os resultados individuais do lote em CSV.
function Export-DcaBatchReport {
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object[]]$Results,

        [string]$Environment,
        [datetime]$ExecutionStartedAt
    )

    if ($ExecutionStartedAt -eq [datetime]::MinValue) {
        $ExecutionStartedAt = if ($script:DcaExecutionStartedAt -is [datetime]) {
            $script:DcaExecutionStartedAt
        }
        else {
            Get-Date
        }
    }

    if ($Results.Count -eq 0) {
        Write-Warn "O relatorio CSV nao foi criado porque o lote nao possui resultados."
        return $null
    }

    if ([string]::IsNullOrWhiteSpace([string]$script:DcaReportFilePath)) {
        throw "O caminho do relatorio CSV nao foi preparado."
    }

    $finishedAt = Get-Date
    $startedText = $ExecutionStartedAt.ToString("yyyy-MM-dd HH:mm:ss")
    $finishedText = $finishedAt.ToString("yyyy-MM-dd HH:mm:ss")

    $reportRows = foreach ($result in $Results) {
        $operationText = switch ([string]$result.Operation) {
            "DatasetOnly" {
                "Importar Dataset em revisao existente"
            }
            "RecoverExisting" {
                if ([string]$result.DocumentType -eq "NDT") {
                    "Recuperar Item NDT e completar PDF ou SLDDRW"
                }
                else {
                    "Recuperar Item existente e importar Dataset"
                }
            }
            "CreateItem" {
                if ([string]$result.DocumentType -eq "NDT") {
                    "Criar Item NDT e importar PDF e SLDDRW"
                }
                else {
                    "Criar Item e importar Dataset"
                }
            }
            default {
                "Operacao nao identificada"
            }
        }

        [PSCustomObject][ordered]@{
            ExecutionId          = [string]$script:DcaExecutionId
            ExecutionStartedAt   = $startedText
            ExecutionFinishedAt  = $finishedText
            Environment          = [string]$Environment
            ItemCode             = [string]$result.ItemCode
            ItemName             = [string]$result.ItemName
            TeamcenterCode       = [string]$result.TeamcenterCode
            ClientRevision       = [string]$result.ClientRevision
            DocumentType         = [string]$result.DocumentType
            PdmState             = [string]$result.PdmState
            Approver             = [string]$result.Approver
            ApprovalDate         = [string]$result.ApprovalDate
            Operation            = [string]$result.Operation
            OperationDescription = $operationText
            ItemCreated          = [bool]$result.ItemCreated
            PdfImported          = [bool]$result.PdfImported
            NdtDrawingImported   = [bool]$result.NdtDrawingImported
            PdfImportedThisRun   = [bool]$result.PdfImportedThisRun
            DatasetAlreadyExists = [bool]$result.DatasetAlreadyExists
            WorkflowStarted      = [bool]$result.WorkflowStarted
            Succeeded            = [bool]$result.Succeeded
            Status               = if ($result.Succeeded) { "Sucesso" } else { "Falha" }
            DocumentStartedAt    = [string]$result.DocumentStartedAt
            DocumentFinishedAt   = [string]$result.DocumentFinishedAt
            DurationSeconds      = $result.DurationSeconds
            DestinationSeconds   = $result.DestinationSeconds
            PdfPreparationSeconds = $result.PdfPreparationSeconds
            DatasetLookupSeconds = $result.DatasetLookupSeconds
            PdfImportSeconds     = $result.PdfImportSeconds
            WorkflowSeconds      = $result.WorkflowSeconds
            SourceFile           = [string]$result.SourceFile
            NdtPdfFile           = [string]$result.NdtPdfFile
            NdtDrawingFile       = [string]$result.NdtDrawingFile
            ErrorMessage         = [string]$result.ErrorMessage
        }
    }

    $reportRows | Export-Csv `
        -LiteralPath $script:DcaReportFilePath `
        -NoTypeInformation `
        -Encoding UTF8 `
        -Delimiter ";" `
        -Force

    if (-not (Test-Path -LiteralPath $script:DcaReportFilePath -PathType Leaf)) {
        throw "O relatorio CSV nao foi criado no caminho esperado."
    }

    $reportFile = Get-Item `
        -LiteralPath $script:DcaReportFilePath `
        -ErrorAction Stop

    if ($reportFile.Length -le 0) {
        throw "O relatorio CSV foi criado, mas ficou vazio."
    }

    Write-Success "Relatorio CSV criado: $script:DcaReportFilePath"
    return $script:DcaReportFilePath
}

# Carrega falhas de um relatorio CSV para nova tentativa.
function Import-DcaRetryReport {
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$FilePath
    )

    if (-not (Test-Path -LiteralPath $FilePath -PathType Leaf)) {
        throw "O relatorio informado para nova tentativa nao foi encontrado: '$FilePath'."
    }

    if ([System.IO.Path]::GetExtension($FilePath) -ine ".csv") {
        throw "O arquivo informado em -RetryReport deve possuir extensao CSV."
    }

    $rows = @(
        Import-Csv `
            -LiteralPath $FilePath `
            -Delimiter ";" `
            -Encoding UTF8 `
            -ErrorAction Stop
    )

    if ($rows.Count -eq 0) {
        throw "O relatorio informado nao possui resultados."
    }

    $requiredColumns = @(
        "ItemCode"
        "ItemName"
        "ClientRevision"
        "DocumentType"
        "PdmState"
        "Operation"
        "ItemCreated"
        "PdfImported"
        "WorkflowStarted"
        "Succeeded"
        "SourceFile"
        "ErrorMessage"
    )

    $columns = @($rows[0].PSObject.Properties.Name)
    $missingColumns = @($requiredColumns | Where-Object { $_ -notin $columns })

    if ($missingColumns.Count -gt 0) {
        throw "O relatorio nao possui todas as colunas obrigatorias: $($missingColumns -join ', ')"
    }

    $retryRows = [System.Collections.Generic.List[object]]::new()

    foreach ($row in $rows) {
        if (ConvertTo-DcaReportBoolean $row.Succeeded) { continue }

        $pdfImported = ConvertTo-DcaReportBoolean $row.PdfImported
        $itemCreated = ConvertTo-DcaReportBoolean $row.ItemCreated
        $drawingImported = if ($columns -contains "NdtDrawingImported") {
            ConvertTo-DcaReportBoolean $row.NdtDrawingImported
        }
        else {
            $false
        }

        $documentType = ([string]$row.DocumentType).Trim()
        $needsDrawing = $documentType -eq "NDT" -and -not $drawingImported

        if ($pdfImported -and -not $needsDrawing) {
            Write-Warn "O documento '$($row.ItemCode)' nao sera reprocessado porque todos os arquivos esperados ja foram importados."
            continue
        }

        if ($needsDrawing) {
            Write-Info "O NDT '$($row.ItemCode)' sera reprocessado porque o desenho SLDDRW ainda nao foi confirmado."
        }

        $itemCode = ([string]$row.ItemCode).Trim()
        $clientRevision = ([string]$row.ClientRevision).Trim()
        $sourceFile = ([string]$row.SourceFile).Trim()

        if ($documentType -eq "NDT" -and
            $columns -contains "NdtDrawingFile" -and
            -not [string]::IsNullOrWhiteSpace([string]$row.NdtDrawingFile)) {
            $sourceFile = ([string]$row.NdtDrawingFile).Trim()
        }

        if (@($itemCode, $clientRevision, $documentType, $sourceFile) |
            Where-Object {[string]::IsNullOrWhiteSpace([string]$_) }) {
            Write-Warn "Uma linha do relatorio foi ignorada porque nao possui codigo, revisao, tipo ou caminho do arquivo."
            continue
        }

        if (-not (Test-Path -LiteralPath $sourceFile -PathType Leaf)) {
            Write-Warn "O documento '$itemCode' foi ignorado porque o arquivo de origem nao foi encontrado: '$sourceFile'."
            continue
        }

        $retryMode = if ($documentType -eq "DatasetOnly") {
            "DatasetOnly"
        }
        elseif ($itemCreated) {
            "RecoverExisting"
        }
        else {
            "CreateItem"
        }

        $retryRows.Add([PSCustomObject]@{
            ItemCode           = $itemCode
            ItemName           = ([string]$row.ItemName).Trim()
            ClientRevision     = $clientRevision.ToUpperInvariant()
            DocumentType       = $documentType
            PdmState           = ([string]$row.PdmState).Trim()
            SourceFile         = $sourceFile
            NdtDrawingImported = $drawingImported
            RetryMode          = $retryMode
            Approver           = Get-DcaReportOptionalText $row $columns "Approver"
            ApprovalDate       = Get-DcaReportOptionalText $row $columns "ApprovalDate"
            PreviousError      = [string]$row.ErrorMessage
        })
    }

    if ($retryRows.Count -eq 0) {
        throw "O relatorio nao possui falhas que possam ser reprocessadas com seguranca."
    }

    Write-Info "Falhas carregadas para nova tentativa: $($retryRows.Count)"
    return $retryRows.ToArray()
}