# ============================================================
# INICIALIZACAO DE WORKFLOWS DO TEAMCENTER
# ============================================================
# Valida a revisao, cria a lista exigida pelo Importar GD e inicia
# o workflow configurado. A escolha do template ocorre no fluxo principal.
# ============================================================

function Start-TeamcenterWorkflow {
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$WorkflowTemplate,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        $Revision
    )

    $template = $WorkflowTemplate.Trim()
    if ([string]::IsNullOrWhiteSpace($template)) {
        throw "O nome do workflow ficou vazio."
    }

    if ($null -eq $Revision) {
        throw "A revisao nao foi fornecida para iniciar o workflow."
    }

    if ($null -eq $script:TeamcenterFunctions) {
        throw "As funcoes do Teamcenter nao foram carregadas. Execute Connect-Teamcenter primeiro."
    }

    if ($null -ne $Revision.PSObject.BaseObject) {
        $Revision = $Revision.PSObject.BaseObject
    }

    $revisionType = $Revision.GetType()
    if ($revisionType.FullName -notmatch '(?i)(ItemRevision|Revision)$') {
        throw "O objeto recebido nao e uma revisao valida. Tipo recebido: '$($revisionType.FullName)'."
    }

    $workflowMethod = Get-TeamcenterMethod -MethodName "Start_Workflow" -ParameterCount 2
    $listType = $workflowMethod.GetParameters()[1].ParameterType

    if ($null -eq $listType) {
        throw "O tipo da lista de revisoes do workflow nao foi identificado."
    }

    try {
        $revisionList = [System.Activator]::CreateInstance($listType)
    }
    catch {
        throw "Nao foi possivel criar a lista de revisoes para o workflow: $($_.Exception.Message)"
    }

    if ($null -eq $revisionList) {
        throw "Nao foi possivel criar a lista de revisoes para o workflow."
    }

    $addMethod = $listType.GetMethods() |
        Where-Object {
            if ($_.Name -ne "Add" -or $_.GetParameters().Count -ne 1) {
                return $false
            }

            $parameterType = $_.GetParameters()[0].ParameterType
            if ($parameterType -eq [object]) {
                return $true
            }

            return $parameterType.IsAssignableFrom($revisionType)
        } |
        Select-Object -First 1

    if ($null -eq $addMethod) {
        throw "Metodo Add compativel com o tipo de revisao '$($revisionType.FullName)' nao foi encontrado na lista '$($listType.FullName)'."
    }

    try {
        $null = $addMethod.Invoke($revisionList, @($Revision))
        $null = $workflowMethod.Invoke($null, [object[]]@($template, $revisionList))
    }
    catch {
        $rootException = $_.Exception
        while ($null -ne $rootException.InnerException) {
            $rootException = $rootException.InnerException
        }

        throw "Falha ao iniciar o workflow '$template': $($rootException.Message)"
    }
}