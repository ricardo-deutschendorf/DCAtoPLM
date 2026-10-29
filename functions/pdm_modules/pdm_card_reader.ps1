# ============================================================
# LEITURA DO ESTADO E DOS CARTOES DO PDM
# ============================================================
#
# Responsabilidades:
#   1. consultar o estado atual do arquivo;
#   2. ler uma variavel especifica diretamente do banco do PDM;
#   3. utilizar GetVar como alternativa de compatibilidade;
#   4. fechar o enumerador do cartao depois da leitura.
#
# A aplicacao dos valores ao documento ocorre nos demais
# modulos do projeto.
# ============================================================

function Get-DcaPdmFileState {

  # Retorna o estado atual do arquivo no workflow do PDM.
  param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNull()]
    $Entry
  )

  # ============================================================
  # 1. VALIDAR A CONEXAO E O CAMINHO
  # ============================================================

  if ($null -eq $script:DcaVault) {

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

  # ============================================================
  # 2. LOCALIZAR O ARQUIVO E CONSULTAR O ESTADO
  # ============================================================

  $parentFolder =
  $null

  try {

    $pdmFile =
    $script:DcaVault.GetFileFromPath(
      $filePath,
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
      "'$filePath': " +
      $_.Exception.Message
    )

    return $null
  }
}

function Get-DcaPdmCardVariableValue {

  # Le uma variavel especifica no cartao do arquivo.
  #
  # GetVarFromDb possui prioridade porque recupera diretamente
  # o valor persistido no banco do PDM.
  #
  # GetVar permanece como alternativa de compatibilidade.
  param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNull()]
    $VariableReader,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$VariableName
  )

  # ============================================================
  # 1. PREPARAR A VARIAVEL E AS CONFIGURACOES
  # ============================================================

  $variableNameClean =
  $VariableName.Trim()

  $configurations =
  [string[]]@(
    "",
    "@"
  )

  # ============================================================
  # 2. TENTAR GETVARFROMDB
  # ============================================================
  #
  # A interface e descoberta em tempo de execucao para manter
  # compatibilidade com diferentes versoes da EdmLib.

  $enumeratorVariable6Type =
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
    $_.Name -eq "IEdmEnumeratorVariable6"
  } |
    Select-Object -First 1

  if ($null -ne $enumeratorVariable6Type) {

    $getVarFromDbMethod =
    $enumeratorVariable6Type.GetMethods() |
      Where-Object {
      $_.Name -eq "GetVarFromDb" -and
      $_.GetParameters().Count -eq 3
    } |
      Select-Object -First 1

    if ($null -ne $getVarFromDbMethod) {

      foreach (
        $configurationName in
        $configurations
      ) {

        $arguments =
        New-Object "System.Object[]" 3

        $arguments[0] =
        [string]$variableNameClean

        $arguments[1] =
        [string]$configurationName

        $arguments[2] =
        $null

        try {

          $variableFound =
          [bool]$getVarFromDbMethod.Invoke(
            $VariableReader,
            $arguments
          )

          $variableValue =
          $arguments[2]

          $valueText =
          ([string]$variableValue).Trim()

          if (
            $variableFound -or
            -not [string]::IsNullOrWhiteSpace(
              $valueText
            )
          ) {

            return [PSCustomObject]@{
              Found = $true
              Value = $variableValue
              Method = "GetVarFromDb"
              Configuration = $configurationName
              Error = $null
            }
          }
        }
        catch {

          if ($Details) {

            $realException =
            $_.Exception

            while (
              $null -ne $realException.InnerException
            ) {

              $realException =
              $realException.InnerException
            }

            $configurationDisplay =
            [string]$configurationName

            if (
              [string]::IsNullOrWhiteSpace(
                $configurationDisplay
              )
            ) {

              $configurationDisplay =
              "<vazia>"
            }

            Write-Host (
              "  GetVarFromDb nao leu '$variableNameClean' na " +
              "configuracao '$configurationDisplay': " +
              $realException.Message
            ) -ForegroundColor DarkGray
          }
        }
      }
    }
  }

  # ============================================================
  # 3. UTILIZAR GETVAR COMO ALTERNATIVA
  # ============================================================

  foreach (
    $configurationName in
    $configurations
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
          Found = $true
          Value = $variableValue
          Method = "GetVar"
          Configuration = $configurationName
          Error = $null
        }
      }
    }
    catch {

      continue
    }
  }

  # ============================================================
  # 4. INFORMAR QUE A VARIAVEL NAO POSSUI VALOR
  # ============================================================

  return [PSCustomObject]@{
    Found = $false
    Value = $null
    Method = "nenhum"
    Configuration = $null
    Error = $null
  }
}

function Get-DcaPdmVariableValue {

  # Testa os nomes recebidos na ordem informada e retorna o
  # primeiro valor preenchido encontrado no cartao.
  param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNull()]
    $Entry,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string[]]$VariableNames
  )

  # ============================================================
  # 1. VALIDAR A CONEXAO E O CAMINHO
  # ============================================================

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

  # ============================================================
  # 2. LOCALIZAR O ARQUIVO E ABRIR O CARTAO
  # ============================================================

  $parentFolder =
  $null

  $variableReader =
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
    $pdmFile.GetEnumeratorVariable(
      ""
    )

    if ($null -eq $variableReader) {

      if ($Details) {

        Write-Warn (
          "Nao foi possivel abrir as variaveis do cartao de " +
          "'$($Entry.Name)'."
        )
      }

      return $null
    }

    # ==========================================================
    # 3. TESTAR AS VARIAVEIS CONFIGURADAS
    # ==========================================================

    foreach (
      $variableName in
      $VariableNames
    ) {

      $currentName =
      ([string]$variableName).Trim()

      if (
        [string]::IsNullOrWhiteSpace(
          $currentName
        )
      ) {

        continue
      }

      try {

        $readResult =
        Get-DcaPdmCardVariableValue `
          -VariableReader $variableReader `
          -VariableName $currentName

        if ($null -eq $readResult) {

          continue
        }

        $variableFound =
        [bool]$readResult.Found

        $variableValue =
        $readResult.Value

        # ======================================================
        # A. APRESENTAR O DIAGNOSTICO
        # ======================================================

        if ($Details) {

          $configurationDisplay =
          [string]$readResult.Configuration

          if (
            [string]::IsNullOrWhiteSpace(
              $configurationDisplay
            )
          ) {

            $configurationDisplay =
            "<vazia>"
          }

          $valueTypeName =
          if ($null -eq $variableValue) {

            "<null>"
          }
          else {

            $variableValue.GetType().FullName
          }

          Write-Host (
            "  Diagnostico da variavel '$currentName':"
          ) -ForegroundColor DarkGray

          Write-Host (
            "    Metodo:        $($readResult.Method)"
          ) -ForegroundColor DarkGray

          Write-Host (
            "    Configuracao:  $configurationDisplay"
          ) -ForegroundColor DarkGray

          Write-Host (
            "    Encontrada:    $variableFound"
          ) -ForegroundColor DarkGray

          Write-Host (
            "    Tipo do valor: $valueTypeName"
          ) -ForegroundColor DarkGray

          Write-Host (
            "    Valor bruto:   '$([string]$variableValue)'"
          ) -ForegroundColor DarkGray
        }

        # ======================================================
        # B. VALIDAR O VALOR
        # ======================================================

        $rawValueText =
        ([string]$variableValue).Trim()

        if (
          -not $variableFound -and
          [string]::IsNullOrWhiteSpace(
            $rawValueText
          )
        ) {

          if ($Details) {

            Write-Host (
              "  Variavel nao encontrada ou desmarcada no cartao: " +
              "'$currentName'"
            ) -ForegroundColor DarkGray
          }

          continue
        }

        # ======================================================
        # C. FORMATAR DATAS E TEXTOS
        # ======================================================

        $valueText =
        if ($variableValue -is [datetime]) {

          $variableValue.ToString(
            "dd/MM/yyyy",
            [System.Globalization.CultureInfo]::InvariantCulture
          )
        }
        else {

          $rawValueText
        }

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

        if ($Details) {

          Write-Host (
            "  Nao foi possivel ler a variavel '$currentName': " +
            $realException.Message
          ) -ForegroundColor DarkGray
        }
      }
    }

    return $null
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

    if ($Details) {

      Write-Warn (
        "Falha ao ler o cartao de dados de " +
        "'$($Entry.Name)': " +
        $realException.Message
      )
    }

    return $null
  }
  finally {

    # ==========================================================
    # 4. FECHAR O ENUMERADOR DO CARTAO
    # ==========================================================

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
              @(
                [bool]$false
              )
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

          # Uma falha ao fechar o enumerador nao deve interromper
          # o processamento do documento.
        }
      }
    }
  }
}
