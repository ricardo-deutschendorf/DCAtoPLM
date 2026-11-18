# ============================================================
# LEITURA DO ESTADO E DOS CARTOES DO PDM
# ============================================================
#   1. consulta o estado atual do arquivo;
#   2. le uma variavel do cartao (GetVarFromDb; GetVar como alternativa);
#   3. fecha o enumerador do cartao depois da leitura.
# A aplicacao dos valores ao documento ocorre nos demais modulos.
# ============================================================

function Get-DcaPdmFileState {
    param([Parameter(Mandatory)][ValidateNotNull()]$Entry)

    if ($null -eq $script:DcaVault) { return $null }

    $filePath = [string]$Entry.FullName
    if ([string]::IsNullOrWhiteSpace($filePath)) { return $null }

    try {
        $parentFolder = $null
        $pdmFile = $script:DcaVault.GetFileFromPath($filePath, [ref]$parentFolder)
        if ($null -eq $pdmFile) { return $null }

        $currentState = $pdmFile.CurrentState
        if ($null -eq $currentState) { return $null }

        return ([string]$currentState.Name).Trim()
    }
    catch {
        if ($Details) {
            Write-Warn "Nao foi possivel consultar o estado no PDM para '$filePath': $($_.Exception.GetBaseException().Message)"
        }
        return $null
    }
}

function Get-DcaPdmCardVariableValue {
    # GetVarFromDb tem prioridade (valor persistido no banco do PDM);
    # GetVar fica como alternativa de compatibilidade.
    param(
        [Parameter(Mandatory)][ValidateNotNull()]$VariableReader,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$VariableName
    )

    $name = $VariableName.Trim()
    if (-not $name) { throw "O nome da variavel do cartao ficou vazio." }

    $configurations = [string[]]@("", "@")

    # --- 1. GetVarFromDb (interface descoberta em tempo de execucao, por causa das versoes da EdmLib) ---
    $interfaceType = [System.AppDomain]::CurrentDomain.GetAssemblies() |
        ForEach-Object { try { $_.GetTypes() } catch { @() } } |
        Where-Object { $_.IsInterface -and $_.Name -ieq "IEdmEnumeratorVariable6" } |
        Select-Object -First 1

    $getVarFromDb = $null
    if ($null -ne $interfaceType) {
        $getVarFromDb = $interfaceType.GetMethods() |
            Where-Object { $_.Name -ieq "GetVarFromDb" -and $_.GetParameters().Count -eq 3 } |
            Select-Object -First 1
    }

    if ($null -ne $getVarFromDb) {
        foreach ($configuration in $configurations) {
            $arguments = [object[]]@($name, $configuration, $null)
            try {
                $found = [bool]$getVarFromDb.Invoke($VariableReader, $arguments)
                $value = $arguments[2]

                if ($found -or ([string]$value).Trim()) {
                    return [PSCustomObject]@{
                        Found = $true; Value = $value; Method = "GetVarFromDb"
                        Configuration = $configuration; Error = $null
                    }
                }
            }
            catch {
                if ($Details) {
                    $display = if ($configuration) { $configuration } else { "<vazia>" }
                    Write-Host (
                        "  GetVarFromDb nao leu '$name' na configuracao '$display': " +
                        $_.Exception.GetBaseException().Message
                    ) -ForegroundColor DarkGray
                }
            }
        }
    }

    # --- 2. GetVar como alternativa ---
    foreach ($configuration in $configurations) {
        $value = $null
        try {
            $found = $VariableReader.GetVar($name, $configuration, [ref]$value)

            if ($found -or ([string]$value).Trim()) {
                return [PSCustomObject]@{
                    Found = $true; Value = $value; Method = "GetVar"
                    Configuration = $configuration; Error = $null
                }
            }
        }
        catch { continue }
    }

    # --- 3. Variavel sem valor ---
    return [PSCustomObject]@{
        Found = $false; Value = $null; Method = "nenhum"; Configuration = $null; Error = $null
    }
}

function Get-DcaPdmVariableValue {
    # Testa os nomes na ordem informada e retorna o primeiro valor preenchido do cartao.
    param(
        [Parameter(Mandatory)][ValidateNotNull()]$Entry,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string[]]$VariableNames
    )

    # --- 1. Conexao, caminho e nomes ---
    $vault = Get-DcaVault
    if ($null -eq $vault) { return $null }

    $filePath = ([string]$Entry.FullName).Trim()
    if (-not $filePath) { return $null }

    $names = @(
        $VariableNames |
            ForEach-Object { ([string]$_).Trim() } |
            Where-Object { $_ } |
            Select-Object -Unique
    )
    if ($names.Count -eq 0) { return $null }

    $parentFolder = $null
    $variableReader = $null

    try {
        # --- 2. Localizar o arquivo e abrir o cartao ---
        $pdmFile = $vault.GetFileFromPath($filePath, [ref]$parentFolder)
        if ($null -eq $pdmFile) {
            if ($Details) { Write-Warn "Arquivo nao encontrado pela API do PDM: '$($Entry.Name)'." }
            return $null
        }

        $variableReader = $pdmFile.GetEnumeratorVariable("")
        if ($null -eq $variableReader) {
            if ($Details) { Write-Warn "Nao foi possivel abrir as variaveis do cartao de '$($Entry.Name)'." }
            return $null
        }

        # --- 3. Testar cada variavel ---
        foreach ($currentName in $names) {
            try {
                $readResult = Get-DcaPdmCardVariableValue -VariableReader $variableReader -VariableName $currentName
                if ($null -eq $readResult) { continue }

                $found = [bool]$readResult.Found
                $value = $readResult.Value
                $rawText = ([string]$value).Trim()

                if ($Details) {
                    $configurationDisplay = if ($readResult.Configuration) { [string]$readResult.Configuration } else { "<vazia>" }
                    $valueTypeName = if ($null -eq $value) { "<null>" } else { $value.GetType().FullName }
                    @(
                        "  Diagnostico da variavel '$currentName':"
                        "    Metodo:        $($readResult.Method)"
                        "    Configuracao:  $configurationDisplay"
                        "    Encontrada:    $found"
                        "    Tipo do valor: $valueTypeName"
                        "    Valor bruto:   '$([string]$value)'"
                    ) | ForEach-Object { Write-Host $_ -ForegroundColor DarkGray }
                }

                if (-not $found -and -not $rawText) {
                    if ($Details) {
                        Write-Host "  Variavel nao encontrada ou desmarcada no cartao: '$currentName'" -ForegroundColor DarkGray
                    }
                    continue
                }

                # Datas saem em dd/MM/yyyy; os demais valores, como texto.
                $valueText = if ($value -is [datetime]) {
                    $value.ToString("dd/MM/yyyy", [System.Globalization.CultureInfo]::InvariantCulture)
                } else { $rawText }

                if ($valueText) {
                    if ($Details) { Write-Host "  Cartao de dados: '$currentName' = '$valueText'" -ForegroundColor Cyan }
                    return $valueText
                }
            }
            catch {
                if ($Details) {
                    Write-Host "  Nao foi possivel ler a variavel '$currentName': $($_.Exception.GetBaseException().Message)" -ForegroundColor DarkGray
                }
            }
        }

        return $null
    }
    catch {
        if ($Details) {
            Write-Warn "Falha ao ler o cartao de dados de '$($Entry.Name)': $($_.Exception.GetBaseException().Message)"
        }
        return $null
    }
    finally {
        # --- 4. Fechar o enumerador (falha aqui nao interrompe o documento) ---
        if ($null -ne $variableReader) {
            $closeFile = $variableReader.GetType().GetMethods() |
                Where-Object { $_.Name -ieq "CloseFile" -and ($_.GetParameters().Count -in 0, 1) } |
                Sort-Object { $_.GetParameters().Count } -Descending |
                Select-Object -First 1

            if ($null -ne $closeFile) {
                try {
                    $closeParameters = $closeFile.GetParameters()
                    if ($closeParameters.Count -eq 1 -and $closeParameters[0].ParameterType -eq [bool]) {
                        $null = $closeFile.Invoke($variableReader, @([bool]$false))
                    }
                    elseif ($closeParameters.Count -eq 0) {
                        $null = $closeFile.Invoke($variableReader, @())
                    }
                }
                catch {
                    if ($Details) {
                        Write-Host "  Nao foi possivel fechar o cartao de '$($Entry.Name)': $($_.Exception.GetBaseException().Message)" -ForegroundColor DarkGray
                    }
                }
            }
        }
    }
}