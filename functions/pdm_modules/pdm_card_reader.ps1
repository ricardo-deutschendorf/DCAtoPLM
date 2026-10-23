# ============================================================
# LEITURA DO ESTADO E DOS CARTOES DO PDM
# ============================================================
#
# Este arquivo realiza a leitura das informacoes armazenadas
# no SOLIDWORKS PDM.
#
# Responsabilidades:
#   1. consultar o estado atual do arquivo;
#   2. ler uma variavel especifica do cartao;
#   3. enumerar as variaveis disponiveis;
#   4. exibir as variaveis no modo de diagnostico;
#   5. utilizar GetVar2 ou GetVar conforme a API disponivel;
#   6. fechar os enumeradores do PDM depois da leitura.
#
# As funcoes deste arquivo apenas leem dados. A aplicacao dos
# valores ao documento ocorre em pdm_document_metadata.ps1.
# ============================================================
function Get-DcaPdmFileState {

  # Retorna o estado atual do arquivo no workflow do PDM.
  # Sem uma conexao com o Vault, o estado nao pode ser consultado.
  param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNull()]
    $Entry
  )

  if ($null -eq $script:DcaVault) {
    return $null
  }

  if (
    [string]::IsNullOrWhiteSpace(
      [string]$Entry.FullName
    )
  ) {
    return $null
  }

  $parentFolder =
  $null

  try {

    $pdmFile =
    $script:DcaVault.GetFileFromPath(
      [string]$Entry.FullName,
      [ref]$parentFolder
    )

    if ($null -eq $pdmFile) {
      return $null
    }

    $currentState =
    $pdmFile.CurrentState

    if ($null -eq $currentState) {
      return $null
    }

    return (
      [string]$currentState.Name
    ).Trim()
  }
  catch {

    Write-Warn (
      "Nao foi possivel consultar o estado no PDM para " +
      "'$($Entry.FullName)': " +
      $_.Exception.Message
    )

    return $null
  }
}
function Get-DcaPdmCardVariableValue {

  # Le uma variavel especifica do cartao. Prioriza GetVar2 e
  # utiliza GetVar como compatibilidade com versoes anteriores
  # da biblioteca EdmLib.
  param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNull()]
    $VariableReader,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$VariableName,

    [Parameter(Mandatory = $true)]
    [int]$FolderId
  )

  $variableNameClean =
  $VariableName.Trim()

  $enumeratorVariableType =
  [System.AppDomain]::CurrentDomain.GetAssemblies() |
    ForEach-Object {

    try {

      $_.GetTypes()
    }
    catch {

      @()
    }
  } |
    Where-Object {
    $_.IsInterface -and
    $_.Name -eq "IEdmEnumeratorVariable10"
  } |
    Select-Object -First 1

  if ($null -ne $enumeratorVariableType) {

    $getVar2Method =
    $enumeratorVariableType.GetMethods() |
      Where-Object {
      $_.Name -eq "GetVar2" -and
      $_.GetParameters().Count -eq 4
    } |
      Select-Object -First 1

    if ($null -ne $getVar2Method) {

      $getVar2Arguments =
      New-Object "System.Object[]" 4

      $getVar2Arguments[0] =
      [string]$variableNameClean

      # PDFs nao possuem configuracoes como os arquivos CAD.
      # A configuracao enviada ao GetVar2 permanece vazia.
      $getVar2Arguments[1] =
      [string]""

      $getVar2Arguments[2] =
      [int]$FolderId

      $getVar2Arguments[3] =
      $null

      try {

        $variableFound =
        [bool]$getVar2Method.Invoke(
          $VariableReader,
          $getVar2Arguments
        )

        $variableValue =
        $getVar2Arguments[3]

        return [PSCustomObject]@{
          Found = $variableFound
          Value = ([string]$variableValue).Trim()
          Method = "GetVar2"
          Error = $null
        }
      }
      catch {

        $realException =
        $_.Exception

        while (
          $null -ne $realException.InnerException
        ) {

          $realException =
          $realException.InnerException
        }

        return [PSCustomObject]@{
          Found = $false
          Value = ""
          Method = "GetVar2"
          Error = $realException.Message
        }
      }
    }
  }

  # Compatibilidade com versoes antigas da API.
  $fallbackConfigurations =
  @(
    "",
    "@"
  )

  foreach (
    $configurationName in
    $fallbackConfigurations
  ) {

    $variableValue =
    $null

    try {

      $variableFound =
      $VariableReader.GetVar(
        $variableNameClean,
        $configurationName,
        [ref]$variableValue
      )

      $valueText =
      ([string]$variableValue).Trim()

      if (
        $variableFound -or
        -not [string]::IsNullOrWhiteSpace(
          $valueText
        )
      ) {

        return [PSCustomObject]@{
          Found = [bool]$variableFound
          Value = $valueText
          Method = "GetVar('$configurationName')"
          Error = $null
        }
      }
    }
    catch {

      continue
    }
  }

  return [PSCustomObject]@{
    Found = $false
    Value = ""
    Method = "nenhum"
    Error = $null
  }
}
function Get-DcaPdmCardVariables {

  # Enumera as variaveis cadastradas no PDM e tenta ler cada
  # valor no cartao do arquivo. Esta funcao e utilizada
  # principalmente pelo modo de diagnostico.
  param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNull()]
    $Entry,

    [switch]$IncludeEmpty
  )

  $vault =
  Get-DcaVault

  if ($null -eq $vault) {

    throw (
      "A API do PDM nao esta disponivel para consultar " +
      "as variaveis do cartao."
    )
  }

  $filePath =
  [string]$Entry.FullName

  if (
    [string]::IsNullOrWhiteSpace(
      $filePath
    )
  ) {

    throw "O caminho do arquivo ficou vazio."
  }

  $parentFolder =
  $null

  $pdmFile =
  $vault.GetFileFromPath(
    $filePath,
    [ref]$parentFolder
  )

  if ($null -eq $pdmFile) {

    throw (
      "O arquivo nao foi encontrado pela API do PDM: " +
      "'$($Entry.Name)'."
    )
  }

  if ($null -eq $parentFolder) {

    throw (
      "A pasta do arquivo nao foi encontrada pela API do PDM."
    )
  }

  $variableReader =
  $pdmFile.GetEnumeratorVariable("")

  if ($null -eq $variableReader) {

    throw (
      "Nao foi possivel abrir o cartao de dados de " +
      "'$($Entry.Name)'."
    )
  }

  $variableManager =
  $vault

  $variableManagerType =
  [System.AppDomain]::CurrentDomain.GetAssemblies() |
    ForEach-Object {

    try {

      $_.GetTypes()
    }
    catch {

      @()
    }
  } |
    Where-Object {
    $_.IsInterface -and
    $_.Name -eq "IEdmVariableMgr5"
  } |
    Select-Object -First 1

  if ($null -eq $variableManagerType) {

    throw (
      "A interface IEdmVariableMgr5 nao foi encontrada " +
      "nos assemblies carregados."
    )
  }

  $getFirstVariablePositionMethod =
  $variableManagerType.GetMethods() |
    Where-Object {
    $_.Name -eq "GetFirstVariablePosition" -and
    $_.GetParameters().Count -eq 0
  } |
    Select-Object -First 1

  $getNextVariableMethod =
  $variableManagerType.GetMethods() |
    Where-Object {
    $_.Name -eq "GetNextVariable" -and
    $_.GetParameters().Count -eq 1
  } |
    Select-Object -First 1

  if (
    $null -eq $getFirstVariablePositionMethod -or
    $null -eq $getNextVariableMethod
  ) {

    throw (
      "Os metodos de enumeracao das variaveis " +
      "nao foram encontrados em IEdmVariableMgr5."
    )
  }

  $results =
  [System.Collections.Generic.List[object]]::new()

  try {

    $position =
    $getFirstVariablePositionMethod.Invoke(
      $variableManager,
      @()
    )

    if ($null -eq $position) {

      throw (
        "A API do PDM nao retornou a posicao inicial " +
        "das variaveis."
      )
    }

    while (
      $null -ne $position -and
      -not $position.IsNull
    ) {

      $pdmVariable =
      $null

      try {

        $pdmVariable =
        $getNextVariableMethod.Invoke(
          $variableManager,
          @($position)
        )
      }
      catch {

        $cursorError =
        [string]$_.Exception.Message

        if (
          $cursorError -match
          "cursor.*final|elemento.*lista|end.*list"
        ) {
          break
        }

        throw
      }

      if ($null -eq $pdmVariable) {
        continue
      }

      $variableName =
      ([string]$pdmVariable.Name).Trim()

      if (
        [string]::IsNullOrWhiteSpace(
          $variableName
        )
      ) {
        continue
      }

      $variableValue =
      $null

      $variableFound =
      $false
      try {

        $readResult =
        Get-DcaPdmCardVariableValue `
          -VariableReader $variableReader `
          -VariableName $variableName `
          -FolderId ([int]$parentFolder.ID)

        $variableFound =
        [bool]$readResult.Found

        $variableValue =
        [string]$readResult.Value

        if (
          $Details -and
          -not [string]::IsNullOrWhiteSpace(
            [string]$readResult.Error
          )
        ) {

          Write-Host (
            "  Erro ao ler '$variableName' com " +
            "$($readResult.Method): " +
            $readResult.Error
          ) -ForegroundColor DarkGray
        }
      }
      catch {

        if ($Details) {

          Write-Host (
            "  Erro inesperado ao ler '$variableName': " +
            $_.Exception.Message
          ) -ForegroundColor DarkGray
        }

        continue
      }

      $valueText =
      ([string]$variableValue).Trim()

      if (
        -not $IncludeEmpty -and
        [string]::IsNullOrWhiteSpace(
          $valueText
        )
      ) {
        continue
      }

      $variableId =
      $null

      if (
        $pdmVariable.PSObject.Properties["ID"]
      ) {

        $variableId =
        $pdmVariable.ID
      }

      $results.Add(
        [PSCustomObject]@{
          Name = $variableName
          ID = $variableId
          Value = $valueText
          Found = [bool]$variableFound
          Method = [string]$readResult.Method
        }
      )
    }
  }
  finally {
    if ($null -ne $variableReader) {

      $closeFileMethod =
      $variableReader.GetType().GetMethods() |
        Where-Object {
        $_.Name -eq "CloseFile"
      } |
        Select-Object -First 1

      if ($null -ne $closeFileMethod) {

        try {

          $closeParameters =
          $closeFileMethod.GetParameters()

          if ($closeParameters.Count -eq 1) {

            $null =
            $closeFileMethod.Invoke(
              $variableReader,
              @([bool]$false)
            )
          }
          elseif ($closeParameters.Count -eq 0) {

            $null =
            $closeFileMethod.Invoke(
              $variableReader,
              @()
            )
          }
        }
        catch {

          # A falha ao fechar o enumerador nao deve
          # interromper a descoberta das variaveis.
        }
      }
    }
  }

  return @(
    $results |
      Sort-Object Name
  )
}
function Show-DcaPdmCardVariables {

  param(
    [Parameter(Mandatory = $true)]
    $Entry
  )

  Write-AnimatedLine ""

  Write-Host (
    "  Consultando as variaveis do cartao de:"
  ) -ForegroundColor Cyan

  Write-Host (
    "  $($Entry.Name)"
  ) -ForegroundColor White

  $cardVariables =
  @(
    Get-DcaPdmCardVariables `
      -Entry $Entry `
      -IncludeEmpty
  )

  if ($cardVariables.Count -eq 0) {

    Write-Warn (
      "Nenhuma variavel foi encontrada no cartao."
    )

    return
  }

  Write-Host ""

  Write-Host (
    "  Variaveis encontradas no cartao:"
  ) -ForegroundColor Cyan

  Write-Host (
    "  " + ("-" * 68)
  ) -ForegroundColor DarkGray

  for (
    $index = 0
    $index -lt $cardVariables.Count
    $index++
  ) {

    $variable =
    $cardVariables[$index]

    $number =
    $index + 1

    $idDisplay =
    ""

    if ($null -ne $variable.ID) {

      $idDisplay =
      " | ID: $($variable.ID)"
    }

    Write-Host (
      "  [{0}] {1}{2}" -f
      $number,
      $variable.Name,
      $idDisplay
    ) -ForegroundColor White

    $valueDisplay =
    [string]$variable.Value

    $valueColor =
    [System.ConsoleColor]::Green

    if (
      [string]::IsNullOrWhiteSpace(
        $valueDisplay
      )
    ) {

      $valueDisplay =
      "<vazio>"

      $valueColor =
      [System.ConsoleColor]::DarkGray
    }

    Write-Host (
      "       Valor: {0}" -f
      $valueDisplay
    ) -ForegroundColor $valueColor

    Write-Host (
      "       Leitura: {0}" -f
      $variable.Method
    ) -ForegroundColor DarkGray
  }

  Write-Host ""

  Write-Host (
    "  Procure acima o campo que representa a revisao."
  ) -ForegroundColor Yellow

  Write-Host (
    "  Copie exatamente o nome exibido antes de 'Valor'."
  ) -ForegroundColor DarkGray
}
function Get-DcaPdmVariableValue {
  param(
    [Parameter(Mandatory = $true)]
    $Entry,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string[]]$VariableNames
  )

  $vault =
  Get-DcaVault

  if ($null -eq $vault) {
    return $null
  }

  $filePath =
  [string]$Entry.FullName

  if (
    [string]::IsNullOrWhiteSpace(
      $filePath
    )
  ) {
    return $null
  }

  $parentFolder =
  $null

  try {

    $pdmFile =
    $vault.GetFileFromPath(
      $filePath,
      [ref]$parentFolder
    )

    if ($null -eq $pdmFile) {

      if ($Details) {

        Write-Warn (
          "Arquivo nao encontrado pela API do PDM: " +
          "'$($Entry.Name)'."
        )
      }

      return $null
    }

    $variableReader =
    $pdmFile.GetEnumeratorVariable("")

    if ($null -eq $variableReader) {

      if ($Details) {

        Write-Warn (
          "Nao foi possivel abrir as variaveis do cartao de " +
          "'$($Entry.Name)'."
        )
      }

      return $null
    }

    foreach ($variableName in $VariableNames) {

      $currentName =
      ([string]$variableName).Trim()

      if (
        [string]::IsNullOrWhiteSpace(
          $currentName
        )
      ) {
        continue
      }

      $variableValue =
      $null

      try {
        $readResult =
        Get-DcaPdmCardVariableValue `
          -VariableReader $variableReader `
          -VariableName $currentName `
          -FolderId ([int]$parentFolder.ID)

        $variableFound =
        [bool]$readResult.Found

        $variableValue =
        [string]$readResult.Value
        if (-not $variableFound) {

          if ($Details) {

            Write-Host (
              "  Variavel nao encontrada no cartao: " +
              "'$currentName'"
            ) -ForegroundColor DarkGray
          }

          continue
        }
      }
      catch {

        if ($Details) {

          Write-Host (
            "  Variavel nao encontrada: '$currentName'"
          ) -ForegroundColor DarkGray
        }

        continue
      }

      $valueText =
      ([string]$variableValue).Trim()

      if (
        -not [string]::IsNullOrWhiteSpace(
          $valueText
        )
      ) {

        if ($Details) {

          Write-Host (
            "  Cartao de dados: '$currentName' = '$valueText'"
          ) -ForegroundColor Cyan
        }

        return $valueText
      }

      if ($Details) {

        Write-Host (
          "  Variavel encontrada, mas vazia: '$currentName'"
        ) -ForegroundColor DarkGray
      }
    }

    return $null
  }
  catch {

    if ($Details) {

      Write-Warn (
        "Falha ao ler o cartao de dados de " +
        "'$($Entry.Name)': $($_.Exception.Message)"
      )
    }

    return $null
  }
}