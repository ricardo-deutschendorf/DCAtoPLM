# ============================================================
# NORMALIZACAO DOS DADOS DO DOCUMENTO
# ============================================================
#
# Este arquivo aplica ao documento os dados encontrados no cartao
# do SOLIDWORKS PDM.
#
# Responsabilidades:
#   1. selecionar as variaveis de revisao conforme o tipo;
#   2. normalizar a descricao do Desenho Original;
#   3. substituir a descricao extraida do nome pelo cartao;
#   4. substituir a revisao extraida do nome pelo cartao;
#   5. registrar a origem da revisao e da descricao;
#   6. apresentar diagnosticos quando o modo Details estiver ativo.
#
# Os valores do cartao possuem prioridade sobre os valores
# interpretados somente pelo nome fisico do PDF.
# ============================================================
function Get-DcaCardRevisionVariableNames {

  param(
    [string]$DocumentType
  )

  # ============================================================
  # 1. SELECIONAR A CONFIGURACAO DE REVISAO
  # ============================================================
  #
  # Cada tipo de documento utiliza uma variavel diferente do
  # arquivo .env para informar os campos de revisao do cartao.
  $configuredValue =
  ""

  if ($DocumentType -eq "Original") {

    $configuredValue =
    [string]$env:DCA_PDM_VAR_ORIGINAL_REVISION
  }
  elseif ($DocumentType -eq "Processo") {

    $configuredValue =
    [string]$env:DCA_PDM_VAR_PROCESS_REVISION
  }
  elseif ($DocumentType -eq "NormaExterna") {

    $configuredValue =
    [string]$env:DCA_PDM_VAR_STANDARD_REVISION
  }
  elseif ($DocumentType -eq "DatasetOnly") {

    $configuredValue =
    [string]$env:DCA_PDM_VAR_DATASET_REVISION
  }

  # ============================================================
  # 2. PREPARAR OS NOMES DAS VARIAVEIS
  # ============================================================
  #
  # A configuracao pode possuir mais de uma variavel separada por
  # barra vertical ou ponto e virgula. Nomes vazios sao ignorados.
  $variableNames =
  [System.Collections.Generic.List[string]]::new()

  foreach ($part in ($configuredValue -split '[|;]')) {

    $currentName =
    ([string]$part).Trim()

    if (-not [string]::IsNullOrWhiteSpace($currentName)) {
      $variableNames.Add($currentName)
    }
  }

  # Retorna um array vazio quando nenhuma variavel estiver
  # configurada para o tipo de documento recebido.
  return $variableNames.ToArray()
}

function Convert-DcaOriginalDescription {

  param(
    [string]$Description
  )

  # ============================================================
  # 1. PREPARAR A DESCRICAO
  # ============================================================
  #
  # Remove os espacos das extremidades antes de normalizar o
  # texto que sera utilizado como nome no Teamcenter.
  $descriptionClean =
  ([string]$Description).Trim()

  if (
    [string]::IsNullOrWhiteSpace(
      $descriptionClean
    )
  ) {

    return $null
  }

  # ============================================================
  # 2. NORMALIZAR O CONTEUDO DA DESCRICAO
  # ============================================================
  #
  # As virgulas utilizadas como separadores no cartao sao
  # convertidas em espacos antes da remocao dos espacos duplicados.
  $descriptionClean =
  $descriptionClean.Replace(
    ",",
    " "
  )

  # Remove espacos duplicados.
  $descriptionClean =
  (
    $descriptionClean -replace
    '\s+',
    ' '
  ).Trim()

  if (
    [string]::IsNullOrWhiteSpace(
      $descriptionClean
    )
  ) {

    return $null
  }

  # ============================================================
  # 3. APLICAR O PADRAO DE NOME DO TEAMCENTER
  # ============================================================
  #
  # A primeira letra permanece maiuscula e os demais caracteres
  # sao convertidos para minusculo.
  if ($descriptionClean.Length -eq 1) {

    return $descriptionClean.ToUpperInvariant()
  }

  return (
    $descriptionClean.Substring(
      0,
      1
    ).ToUpperInvariant() +
    $descriptionClean.Substring(
      1
    ).ToLowerInvariant()
  )
}

function Update-DcaMatchDescriptionFromCard {
  param(
    [Parameter(Mandatory = $true)]
    $Match
  )

  # ============================================================
  # 1. TRATAR DOCUMENTOS SOMENTE DATASET
  # ============================================================
  #
  # DatasetOnly nao depende de uma descricao do cartao. Quando
  # nenhum titulo estiver disponivel, o codigo sera utilizado
  # como nome do documento.
  if ($Match.DocumentType -eq "DatasetOnly") {

    if (
      [string]::IsNullOrWhiteSpace(
        [string]$Match.DocumentTitle
      )
    ) {

      $Match.DocumentTitle =
      [string]$Match.SourceCode
    }

    return
  }

  # ============================================================
  # 2. SELECIONAR A VARIAVEL DE DESCRICAO
  # ============================================================
  #
  # Cada tipo de documento consulta uma variavel especifica do
  # arquivo .env para identificar o campo de descricao do cartao.
  $descriptionVariableName =
  $null

  if ($Match.DocumentType -eq "Processo") {

    $descriptionVariableName =
    [string]$env:DCA_PDM_VAR_PROCESS_DESCRIPTION
  }
  elseif ($Match.DocumentType -eq "Original") {

    $descriptionVariableName =
    [string]$env:DCA_PDM_VAR_ORIGINAL_DESCRIPTION
  }
  elseif ($Match.DocumentType -eq "NormaExterna") {

    $descriptionVariableName =
    [string]$env:DCA_PDM_VAR_STANDARD_DESCRIPTION
  }

  $descriptionVariableName =
  ([string]$descriptionVariableName).Trim()

  if (
    [string]::IsNullOrWhiteSpace(
      $descriptionVariableName
    )
  ) {

    # Registra que a descricao nao foi consultada porque nenhuma
    # variavel foi configurada para o tipo atual.
    Add-Member `
      -InputObject $Match `
      -NotePropertyName "DescriptionSource" `
      -NotePropertyValue "nao configurada" `
      -Force

    return
  }

  # ============================================================
  # 3. CONSULTAR A DESCRICAO NO CARTAO
  # ============================================================
  #
  # Le o valor da variavel configurada diretamente no cartao de
  # dados associado ao PDF.
  $cardDescription =
  Get-DcaPdmVariableValue `
    -Entry $Match.File `
    -VariableNames @(
    $descriptionVariableName
  )

  $cardDescription =
  ([string]$cardDescription).Trim()

  # Desenhos Originais utilizam uma normalizacao adicional para
  # adequar a descricao ao padrao de nome do Teamcenter.
  if ($Match.DocumentType -eq "Original") {

    $cardDescription =
    Convert-DcaOriginalDescription `
      -Description $cardDescription
  }
  if (
    [string]::IsNullOrWhiteSpace(
      $cardDescription
    )
  ) {

    # Mantem o titulo obtido anteriormente e registra que a
    # variavel do cartao foi encontrada sem um valor utilizavel.
    Add-Member `
      -InputObject $Match `
      -NotePropertyName "DescriptionSource" `
      -NotePropertyValue "cartao vazio" `
      -Force

    if ($Details) {

      Write-Warn (
        "A descricao do cartao esta vazia em " +
        "'$($Match.File.Name)'. " +
        "Variavel: '$descriptionVariableName'."
      )
    }

    return
  }

  # ============================================================
  # 4. APLICAR A DESCRICAO DO CARTAO
  # ============================================================
  #
  # Uma descricao valida encontrada no cartao substitui o titulo
  # interpretado anteriormente pelo nome fisico do PDF.
  $Match.DocumentTitle =
  $cardDescription

  # Preserva o valor original do cartao e registra sua origem para
  # permitir diagnosticos nas etapas seguintes.
  Add-Member `
    -InputObject $Match `
    -NotePropertyName "CardDescription" `
    -NotePropertyValue $cardDescription `
    -Force

  Add-Member `
    -InputObject $Match `
    -NotePropertyName "DescriptionSource" `
    -NotePropertyValue "cartao de dados" `
    -Force

  # O valor encontrado e apresentado somente quando o modo de
  # diagnostico estiver ativo.
  if ($Details) {

    Write-Host (
      "  Descricao do cartao: " +
      "'$cardDescription'"
    ) -ForegroundColor Cyan
  }
}

function Update-DcaMatchRevisionFromCard {
  param(
    [Parameter(Mandatory = $true)]
    $Match
  )

  # ============================================================
  # 1. VERIFICAR O MODO DE DESCOBERTA DO CARTAO
  # ============================================================
  #
  # Quando habilitada no arquivo .env, esta opcao apresenta todas
  # as variaveis encontradas no cartao para auxiliar diagnosticos
  # e ajustes de configuracao.
  $discoverCardVariables =
  ([string]$env:DCA_PDM_DISCOVER_CARD_VARIABLES).Trim()

  if (
    $discoverCardVariables -match
    '^(?i:true|1|sim|yes)$'
  ) {

    Show-DcaPdmCardVariables `
      -Entry $Match.File
  }

  # ============================================================
  # 2. PRESERVAR A REVISAO DO NOME DO ARQUIVO
  # ============================================================
  #
  # A revisao interpretada pelo nome e preservada separadamente
  # para permitir identificar posteriormente sua origem.
  $fileRevision =
  ([string]$Match.ClientRevision).Trim().ToUpper()

  # A origem inicial permanece como nome do arquivo. Esse valor
  # sera alterado somente quando o cartao fornecer uma revisao.
  $revisionSource =
  "nome do arquivo"

  # ============================================================
  # 3. OBTER AS VARIAVEIS DE REVISAO CONFIGURADAS
  # ============================================================
  #
  # Seleciona os campos do cartao associados ao tipo atual do
  # documento.
  $variableNames =
  @(
    Get-DcaCardRevisionVariableNames `
      -DocumentType ([string]$Match.DocumentType)
  )

  # No modo Details, apresenta os nomes dos campos que serao
  # consultados no cartao do documento atual.
  if ($Details) {

    $configuredVariablesDisplay =
    if ($variableNames.Count -gt 0) {
      $variableNames -join ", "
    }
    else {
      "<nenhuma>"
    }

    Write-Host (
      "  Variaveis de revisao configuradas: " +
      $configuredVariablesDisplay
    ) -ForegroundColor DarkGray
  }

  # ============================================================
  # 4. CONSULTAR A REVISAO NO CARTAO
  # ============================================================
  #
  # Testa as variaveis configuradas e utiliza o primeiro valor
  # valido encontrado no cartao de dados.
  if ($variableNames.Count -gt 0) {

    $cardRevision =
    Get-DcaPdmVariableValue `
      -Entry $Match.File `
      -VariableNames $variableNames

    # Os diagnosticos mostram o arquivo consultado, as variaveis
    # testadas e o valor retornado pelo cartao.
    if ($Details) {

      Write-Host (
        "  Cartao de dados: " +
        $Match.File.Name
      ) -ForegroundColor Cyan

      Write-Host (
        "    Variavel(is) testada(s): " +
        ($variableNames -join ", ")
      ) -ForegroundColor DarkGray

      if (
        [string]::IsNullOrWhiteSpace(
          [string]$cardRevision
        )
      ) {

        Write-Host (
          "    Revisao do cartao: nao encontrada ou vazia"
        ) -ForegroundColor Yellow
      }
      else {

        Write-Host (
          "    Revisao do cartao: [$cardRevision]"
        ) -ForegroundColor Green
      }
    }

    if (
      -not [string]::IsNullOrWhiteSpace(
        $cardRevision
      )
    ) {

      $cardRevision =
      ([string]$cardRevision).Trim().ToUpperInvariant()

      # Uma revisao valida do cartao substitui a revisao extraida
      # anteriormente do nome fisico do PDF.
      $Match.ClientRevision =
      $cardRevision

      $revisionSource =
      "cartao de dados"
    }
  }

  # ============================================================
  # 5. INFORMAR UMA CONFIGURACAO AUSENTE
  # ============================================================
  #
  # Quando nenhuma variavel estiver configurada, o modo Details
  # informa qual propriedade deve ser adicionada ao arquivo .env.
  if (
    $variableNames.Count -eq 0 -and
    $Details
  ) {

    # Identifica o nome da variavel de ambiente correspondente ao
    # tipo do documento para facilitar a correcao da configuracao.
    $configurationName =
    switch ($Match.DocumentType) {

      "Original" {
        "DCA_PDM_VAR_ORIGINAL_REVISION"
      }

      "Processo" {
        "DCA_PDM_VAR_PROCESS_REVISION"
      }

      "NormaExterna" {
        "DCA_PDM_VAR_STANDARD_REVISION"
      }

      "DatasetOnly" {
        "DCA_PDM_VAR_DATASET_REVISION"
      }

      default {
        "a variavel de revisao correspondente"
      }
    }

    Write-Warn (
      "Nenhuma variavel de revisao do cartao foi configurada " +
      "para o tipo '$($Match.DocumentType)'."
    )

    Write-Host (
      "  Configure $configurationName no arquivo .env."
    ) -ForegroundColor DarkGray
  }

  # ============================================================
  # 6. REGISTRAR A ORIGEM DA REVISAO
  # ============================================================
  #
  # FileRevision preserva a revisao extraida do nome do arquivo.
  # RevisionSource informa se a revisao final veio do nome ou do
  # cartao de dados.
  Add-Member `
    -InputObject $Match `
    -NotePropertyName "FileRevision" `
    -NotePropertyValue $fileRevision `
    -Force

  Add-Member `
    -InputObject $Match `
    -NotePropertyName "RevisionSource" `
    -NotePropertyValue $revisionSource `
    -Force
}
