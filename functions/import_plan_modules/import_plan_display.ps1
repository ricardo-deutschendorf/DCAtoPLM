# ============================================================
# MONTAGEM E APRESENTACAO DO PLANO DE IMPORTACAO
# ============================================================
# Monta e exibe o plano do lote antes de criar qualquer objeto
# no Teamcenter (nenhum Item, revisao, Dataset ou workflow e criado aqui).
#   1. identifica o ambiente (Teste/Processo);
#   2. valida a configuracao de cada documento;
#   3. calcula o workflow previsto pelo estado do PDM;
#   4. exibe configuracao por tipo, workflows e lista do lote.
# ============================================================

function Get-DcaConfiguredEnvironmentName {
    # Depois da conexao, vale o ambiente confirmado por ela.
    if (-not [string]::IsNullOrWhiteSpace($script:TeamcenterEnvironment)) {
        return [string]$script:TeamcenterEnvironment
    }

    # Antes da conexao, vale o .env (somente Teste ou Processo).
    $configuredValue = ([string]$env:DCA_TC_ENV).Trim()
    foreach ($name in "Teste", "Processo") {
        if ($configuredValue -ieq $name) { return $name }
    }

    throw "DCA_TC_ENV nao foi configurado. Use Teste ou Processo."
}

function Show-DcaImportPlan {
    param([Parameter(Mandatory)][ValidateNotNull()][object[]]$Documents)

    if ($Documents.Count -eq 0) { throw "Nenhum documento foi fornecido para montar o plano de importacao." }

    # --- Ambiente e workflows configurados ---
    $environmentName  = Get-DcaConfiguredEnvironmentName
    $isProcess        = $environmentName -eq "Processo"
    $serverUrl        = ([string]$(if ($isProcess) { $env:DCA_TC_PROCESS_URL } else { $env:DCA_TC_TEST_URL })).Trim()
    $environmentColor = if ($isProcess) { "Yellow" } else { "Cyan" }

    $approvedTemplate = ([string]$env:DCA_TC_APPROVED_WORKFLOW).Trim()
    $obsoleteTemplate = ([string]$env:DCA_TC_OBSOLETE_WORKFLOW).Trim()

    # --- Plano de cada documento (entradas nulas sao ignoradas) ---
    $planItems = @(
        foreach ($document in $Documents) {
            if ($null -eq $document) { continue }

            # Workflow previsto pelo estado do PDM.
            $pdmState = ([string]$document.PdmState).Trim()
            $workflowLabel = $workflowTemplate = $null
            if ($document.DocumentType -ne "DatasetOnly") {
                if ($pdmState -in "Aprovado", "Verificado") {
                    $workflowLabel = "aprovacao";     $workflowTemplate = $approvedTemplate
                }
                elseif ($pdmState -ieq "Obsoleto") {
                    $workflowLabel = "obsolescencia"; $workflowTemplate = $obsoleteTemplate
                }
            }

            # Validacao basica e configuracao do tipo.
            $documentType = ([string]$document.DocumentType).Trim()
            $configuration = $null
            $configurationError =
                if     (-not $documentType)                                     { "O tipo do documento ficou vazio." }
                elseif (-not ([string]$document.ItemCode).Trim())               { "O codigo do Item ficou vazio." }
                elseif (-not ([string]$document.ClientRevision).Trim())         { "A revisao do documento ficou vazia." }

            if ($configurationError) { }
            elseif ($documentType -eq "DatasetOnly") {
                # Reutiliza Item e revisao existentes: nao ha configuracao de criacao.
                $configuration = [PSCustomObject]@{
                    Environment          = $environmentName
                    ItemType             = "Item existente"
                    RevisionType         = "Revisao existente"
                    ClientProperty       = ""
                    ClientValue          = ""
                    TeamcenterRevisionId = [string]$document.ClientRevision
                    RevisionProperties   = @{}
                }
            }
            else {
                try {
                    $configuration = Get-DcaTypeConfiguration `
                        -DocumentType $document.DocumentType `
                        -ClientRevision $document.ClientRevision `
                        -TeamcenterEnvironment $environmentName
                }
                catch { $configurationError = $_.Exception.Message }
            }

            # Dados da revisao ("?" quando a configuracao nao pode ser determinada).
            $teamcenterRevisionId = "?"
            $revisionText = ""
            if ($null -ne $configuration) {
                $teamcenterRevisionId = [string]$configuration.TeamcenterRevisionId
                $revisionProperties = $configuration.RevisionProperties
                if ($null -ne $revisionProperties) {
                    $revisionText = (
                        $revisionProperties.Keys | Sort-Object |
                            ForEach-Object { "{0}={1}" -f $_, $revisionProperties[$_] }
                    ) -join "; "
                }
            }

            [PSCustomObject]@{
                ItemCode             = ([string]$document.ItemCode).Trim().ToUpper()
                ItemName             = [string]$document.ItemName
                DocumentType         = [string]$document.DocumentType
                DisplayType          = [string]$document.DisplayType
                PdmState             = $pdmState
                Configuration        = $configuration
                ConfigurationError   = $configurationError
                TeamcenterRevisionId = $teamcenterRevisionId
                RevisionText         = $revisionText
                WorkflowLabel        = $workflowLabel
                WorkflowTemplate     = $workflowTemplate
                FilePath             = [string]$document.SelectedPdf.File.FullName
            }
        }
    )

    if ($planItems.Count -eq 0) { throw "Nenhum documento valido ficou disponivel para montar o plano de importacao." }

    # --- Cabecalho ---
    Write-Section -Title "Plano antes da importacao"
    Write-Host ""
    Write-Host "  Nada foi criado ainda. Confira as informacoes abaixo." -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  Ambiente:   $environmentName" -ForegroundColor $environmentColor
    if ($Details) { Write-Host "  Servidor:   $serverUrl" -ForegroundColor Gray }
    Write-Host "  Documentos: $($planItems.Count)" -ForegroundColor White

    # --- Configuracao por tipo (um bloco por tipo de documento) ---
    Write-Host ""
    Write-Host "  Configuracao por tipo:" -ForegroundColor Cyan

    foreach ($typeGroup in @($planItems | Group-Object -Property DocumentType)) {
        Write-Host ("    {0}  ({1} documento(s))" -f $typeGroup.Group[0].DisplayType, $typeGroup.Count) -ForegroundColor White

        # O primeiro documento com configuracao valida representa o grupo.
        $sample = $typeGroup.Group | Where-Object { $null -ne $_.Configuration } | Select-Object -First 1
        if ($null -eq $sample) {
            Write-Host "      Configuracao invalida. Veja os erros abaixo." -ForegroundColor Red
            continue
        }

        $typeConfiguration = $sample.Configuration
        $clientText = "nenhum"
        if (
            -not [string]::IsNullOrWhiteSpace([string]$typeConfiguration.ClientProperty) -and
            -not [string]::IsNullOrWhiteSpace([string]$typeConfiguration.ClientValue)
        ) {
            $clientText = "$($typeConfiguration.ClientProperty) = $($typeConfiguration.ClientValue)"
        }

        @(
            "      Tipo do Item:    $($typeConfiguration.ItemType)"
            "      Tipo da Revisao: $($typeConfiguration.RevisionType)"
            "      Cliente:         $clientText"
        ) | ForEach-Object { Write-Host $_ -ForegroundColor Gray }
    }

    # --- Workflows ---
    $approvedCount        = @($planItems | Where-Object { $_.WorkflowLabel -eq "aprovacao" }).Count
    $obsoleteCount        = @($planItems | Where-Object { $_.WorkflowLabel -eq "obsolescencia" }).Count
    $withoutWorkflowCount = @($planItems | Where-Object { -not $_.WorkflowLabel }).Count

    $approvedText = if ($approvedTemplate) { $approvedTemplate } else { "NAO CONFIGURADO" }
    $obsoleteText = if ($obsoleteTemplate) { $obsoleteTemplate } else { "NAO CONFIGURADO" }

    Write-Host ""
    Write-Host "  Workflows:" -ForegroundColor Cyan
    Write-Host ("    Aprovacao:     {0,3}  ({1})" -f $approvedCount, $approvedText) -ForegroundColor Green
    Write-Host ("    Obsolescencia: {0,3}  ({1})" -f $obsoleteCount, $obsoleteText) -ForegroundColor Red
    Write-Host ("    Sem workflow:  {0,3}" -f $withoutWorkflowCount) -ForegroundColor Yellow

    # --- Documentos do lote ---
    Write-Host ""
    Write-Host "  Documentos:" -ForegroundColor Cyan

    $errorCount = 0
    $missingWorkflowCount = 0

    for ($index = 0; $index -lt $planItems.Count; $index++) {
        $planItem = $planItems[$index]

        # Texto e cor da linha: erro > workflow ausente > tipo de workflow.
        $workflowText = "sem workflow"
        $lineColor = "Gray"

        if ($planItem.DocumentType -eq "DatasetOnly") {
            $workflowText = "somente Dataset"
        }
        elseif ($planItem.WorkflowLabel) {
            if (-not $planItem.WorkflowTemplate) {
                $workflowText = "workflow de $($planItem.WorkflowLabel) NAO CONFIGURADO"
                $lineColor = "Yellow"
                $missingWorkflowCount++
            }
            elseif ($planItem.WorkflowLabel -eq "aprovacao") {
                $workflowText = "workflow de aprovacao"
                $lineColor = "Green"
            }
            else {
                $workflowText = "workflow de obsolescencia"
                $lineColor = "Red"
            }
        }

        if ($planItem.ConfigurationError) {
            $lineColor = "Red"
            $errorCount++
        }

        $stateText = if ($planItem.PdmState) { $planItem.PdmState } else { "sem estado" }

        Write-Host ("  [{0}] {1} | rev {2} | {3} | {4}" -f
            ($index + 1), $planItem.ItemCode, $planItem.TeamcenterRevisionId, $stateText, $workflowText
        ) -ForegroundColor $lineColor

        if ($planItem.ConfigurationError) {
            Write-Host "       ERRO: $($planItem.ConfigurationError)" -ForegroundColor Red
        }

        if ($Details) {
            Write-Host "       Nome:     $($planItem.ItemName)" -ForegroundColor DarkGray
            if ($planItem.RevisionText)     { Write-Host "       Revisao:  $($planItem.RevisionText)" -ForegroundColor DarkGray }
            if ($planItem.WorkflowTemplate) { Write-Host "       Template: $($planItem.WorkflowTemplate)" -ForegroundColor DarkGray }
            Write-Host "       Arquivo:  $($planItem.FilePath)" -ForegroundColor DarkGray
        }
    }

    # --- Avisos finais ---
    if ($errorCount -gt 0) {
        Write-Host ""
        Write-Warn "$errorCount documento(s) possuem erro de configuracao e nao poderao ser criados."
    }

    # Template ausente nao impede criar Item e importar PDF; so deixa sem workflow.
    if ($missingWorkflowCount -gt 0) {
        Write-Host ""
        Write-Warn (
            "$missingWorkflowCount documento(s) com workflow nao configurado no .env. " +
            "O Item e o PDF serao criados sem workflow."
        )
    }

    Write-Host ""
}