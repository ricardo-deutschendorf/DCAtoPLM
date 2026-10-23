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

  $variableNames =
  [System.Collections.Generic.List[string]]::new()

  foreach ($part in ($configuredValue -split '[|;]')) {

    $currentName =
    ([string]$part).Trim()

    if (-not [string]::IsNullOrWhiteSpace($currentName)) {
      $variableNames.Add($currentName)
    }
  }

  return $variableNames.ToArray()
}
function Convert-DcaOriginalDescription {

  param(
    [string]$Description
  )

  $descriptionClean =
  ([string]$Description).Trim()

  if (
    [string]::IsNullOrWhiteSpace(
      $descriptionClean
    )
  ) {

    return $null
  }

  # Remove virgulas usadas como separador no cartao.
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

  # Padrao do nome no Teamcenter:
  # primeira letra maiuscula e restante minusculo.
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

    Add-Member `
      -InputObject $Match `
      -NotePropertyName "DescriptionSource" `
      -NotePropertyValue "nao configurada" `
      -Force

    return
  }

  $cardDescription =
  Get-DcaPdmVariableValue `
    -Entry $Match.File `
    -VariableNames @(
    $descriptionVariableName
  )

  $cardDescription =
  ([string]$cardDescription).Trim()
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

  $Match.DocumentTitle =
  $cardDescription

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

  $discoverCardVariables =
  ([string]$env:DCA_PDM_DISCOVER_CARD_VARIABLES).Trim()

  if (
    $discoverCardVariables -match
    '^(?i:true|1|sim|yes)$'
  ) {

    Show-DcaPdmCardVariables `
      -Entry $Match.File
  }
  $fileRevision =
  ([string]$Match.ClientRevision).Trim().ToUpper()

  $revisionSource =
  "nome do arquivo"

  $variableNames =
  @(
    Get-DcaCardRevisionVariableNames `
      -DocumentType ([string]$Match.DocumentType)
  )
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
  if ($variableNames.Count -gt 0) {

    $cardRevision =
    Get-DcaPdmVariableValue `
      -Entry $Match.File `
      -VariableNames $variableNames

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

      $Match.ClientRevision =
      $cardRevision

      $revisionSource =
      "cartao de dados"
    }
  }

  if (
    $variableNames.Count -eq 0 -and
    $Details
  ) {

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