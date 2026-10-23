# ============================================================
# INICIALIZACAO DE WORKFLOWS DO TEAMCENTER
# ============================================================
#
# Este arquivo inicia um workflow para uma revisao existente
# no Teamcenter.
#
# Responsabilidades:
#   1. validar o nome do template de workflow;
#   2. validar o objeto de revisao recebido;
#   3. localizar o metodo Start_Workflow no Importar GD;
#   4. criar a lista de revisoes exigida pelo metodo;
#   5. adicionar a revisao na lista;
#   6. solicitar o inicio do workflow configurado.
#
# Este arquivo nao determina qual workflow deve ser iniciado.
# A escolha entre aprovacao e obsolescencia ocorre no fluxo
# principal, conforme o estado do documento no PDM.
# ============================================================


function Start-TeamcenterWorkflow {

  # Cria a lista exigida pelo Importar GD e solicita o inicio
  # do workflow para a revisao recebida.
  param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$WorkflowTemplate,

    [Parameter(Mandatory = $true)]
    $Revision
  )


  # ============================================================
  # 1. VALIDAR O TEMPLATE E A REVISAO
  # ============================================================

  $workflowTemplateClean =
  $WorkflowTemplate.Trim()

  if (
    [string]::IsNullOrWhiteSpace(
      $workflowTemplateClean
    )
  ) {

    throw "O nome do workflow ficou vazio."
  }

  if ($null -eq $Revision) {

    throw (
      "A revisao nao foi fornecida para iniciar o workflow."
    )
  }

  if ($null -eq $script:TeamcenterFunctions) {

    throw (
      "As funcoes do Teamcenter nao foram carregadas. " +
      "Execute Connect-Teamcenter primeiro."
    )
  }


  # ============================================================
  # 2. NORMALIZAR E VALIDAR O OBJETO DE REVISAO
  # ============================================================
  #
  # Remove o wrapper criado pelo PowerShell quando o objeto
  # original da API estiver disponivel.

  $revisionBaseObject =
  $Revision.PSObject.BaseObject

  if ($null -ne $revisionBaseObject) {

    $Revision =
    $revisionBaseObject
  }

  $revisionTypeName =
  $Revision.GetType().FullName

  # O Teamcenter pode retornar tipos especializados derivados
  # de ItemRevision. Por isso, a validacao aceita nomes que
  # terminem com ItemRevision ou Revision.
  $isRevisionObject =
  $revisionTypeName -match
  '(?i)(ItemRevision|Revision)$'

  if (-not $isRevisionObject) {

    throw (
      "O objeto recebido nao e uma revisao valida. " +
      "Tipo recebido: '$revisionTypeName'."
    )
  }


  # ============================================================
  # 3. LOCALIZAR O METODO DE INICIALIZACAO DO WORKFLOW
  # ============================================================
  #
  # O metodo esperado e estatico e recebe dois parametros:
  #   1. nome do template;
  #   2. lista de revisoes.

  $workflowMethod =
  $script:TeamcenterFunctions.GetMethods() |
    Where-Object {
      $_.Name -eq "Start_Workflow" -and
      $_.GetParameters().Count -eq 2
    } |
    Select-Object -First 1

  if ($null -eq $workflowMethod) {

    throw (
      "Metodo Start_Workflow com 2 parametros " +
      "nao encontrado no Importar GD."
    )
  }


  # ============================================================
  # 4. CRIAR A LISTA DE REVISOES
  # ============================================================
  #
  # O tipo exato da lista e obtido diretamente do segundo
  # parametro do metodo Start_Workflow. Isso evita depender
  # de um nome fixo de classe ou de uma versao especifica
  # das bibliotecas do Teamcenter.

  $workflowParameters =
  $workflowMethod.GetParameters()

  $revisionListType =
  $workflowParameters[1].ParameterType

  if ($null -eq $revisionListType) {

    throw (
      "O tipo da lista de revisoes do workflow " +
      "nao foi identificado."
    )
  }

  $revisionList =
  [System.Activator]::CreateInstance(
    $revisionListType
  )

  if ($null -eq $revisionList) {

    throw (
      "Nao foi possivel criar a lista de revisoes " +
      "para o workflow."
    )
  }


  # ============================================================
  # 5. ADICIONAR A REVISAO NA LISTA
  # ============================================================

  $addMethod =
  $revisionListType.GetMethods() |
    Where-Object {
      $_.Name -eq "Add" -and
      $_.GetParameters().Count -eq 1
    } |
    Select-Object -First 1

  if ($null -eq $addMethod) {

    throw (
      "Metodo Add nao encontrado na lista de revisoes."
    )
  }

  $null =
  $addMethod.Invoke(
    $revisionList,
    @($Revision)
  )


  # ============================================================
  # 6. PREPARAR OS ARGUMENTOS DO WORKFLOW
  # ============================================================

  $workflowArguments =
  New-Object "System.Object[]" 2

  $workflowArguments[0] =
  [string]$workflowTemplateClean

  $workflowArguments[1] =
  $revisionList


  # ============================================================
  # 7. SOLICITAR O INICIO DO WORKFLOW
  # ============================================================
  #
  # A chamada abaixo pode iniciar efetivamente um workflow no
  # Teamcenter. Todas as validacoes locais ocorrem antes dela.

  try {

    $null =
    $workflowMethod.Invoke(
      $null,
      $workflowArguments
    )
  }
  catch {

    # Percorre as excecoes internas para apresentar a causa
    # original retornada pelo Importar GD ou pelo Teamcenter.
    $realException =
    $_.Exception

    while (
      $null -ne $realException.InnerException
    ) {

      $realException =
      $realException.InnerException
    }

    throw (
      "Falha ao iniciar o workflow " +
      "'$workflowTemplateClean': " +
      $realException.Message
    )
  }
}
