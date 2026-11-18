# ============================================================
# CONEXAO, SESSAO E SERVICOS DO TEAMCENTER
# ============================================================
# Recursos compartilhados para acessar os servicos SOA do Teamcenter.
#   1. valida o executavel Importar GD;
#   2. le e valida a configuracao do ambiente;
#   3. autentica e reutiliza a sessao do Teamcenter;
#   4. localiza metodos do Importar GD e recupera a conexao SOA;
#   5. carrega os assemblies das Saved Queries e fornece o
#      DataManagementService;
#   6. converte erros parciais SOA em mensagens legiveis.
# Nenhuma funcao daqui cria Items, revisoes ou Datasets; elas apenas
# preparam e fornecem os recursos usados pelos demais modulos.
# ============================================================

# Valida o executavel Importar GD configurado no .env. Se nao existir
# no destino local, copia todos os arquivos da origem de rede.
function Confirm-TeamcenterImporter {

    # --- 1. Ler as configuracoes do Importar GD ---
    $exePath    = ([string]$env:DCA_IMPORTER_PATH).Trim()
    $sourcePath = ([string]$env:DCA_IMPORTER_SOURCE).Trim()
    $destPath   = ([string]$env:DCA_IMPORTER_DESTINATION).Trim()

    if ($Details) {
        Write-Host "  DCA_IMPORTER_SOURCE: '$sourcePath'" -ForegroundColor DarkGray
        Write-Host "  DCA_IMPORTER_DESTINATION: '$destPath'" -ForegroundColor DarkGray
        Write-Host "  DCA_IMPORTER_PATH: '$exePath'" -ForegroundColor DarkGray
    }

    if ([string]::IsNullOrWhiteSpace($exePath)) { throw "DCA_IMPORTER_PATH deve ser configurado no arquivo .env." }

    # --- 2. Retornar se o executavel ja existir ---
    if (Test-Path -LiteralPath $exePath -PathType Leaf) {
        if ($Details) { Write-Host "  Importar GD disponivel: $exePath" -ForegroundColor DarkGray }
        return $exePath
    }

    # --- 3. Validar as configuracoes da copia automatica ---
    Write-Warn "Importar GD nao encontrado em '$exePath'. Iniciando copia automatica."

    if ([string]::IsNullOrWhiteSpace($sourcePath)) { throw "O Importar GD nao existe no destino e DCA_IMPORTER_SOURCE nao foi configurado no .env." }
    if ([string]::IsNullOrWhiteSpace($destPath))   { throw "O Importar GD nao existe no destino e DCA_IMPORTER_DESTINATION nao foi configurado no .env." }

    # --- 4. Validar a origem de rede ---
    if (-not (Test-Path -LiteralPath $sourcePath -PathType Container)) {
        throw "A origem do Importar GD nao foi encontrada ou nao esta acessivel: '$sourcePath'. Verifique a conexao com a rede."
    }

    $sourceExe = Join-Path -Path $sourcePath -ChildPath "Importar GD.exe"
    if (-not (Test-Path -LiteralPath $sourceExe -PathType Leaf)) {
        throw "A origem do Importar GD foi encontrada, mas nao contem o executavel esperado: '$sourceExe'."
    }

    # --- 5. Validar a coerencia do destino ---
    $exeFolder = [System.IO.Path]::GetDirectoryName($exePath)
    if ([string]::IsNullOrWhiteSpace($exeFolder)) { throw "Nao foi possivel identificar a pasta de destino a partir de DCA_IMPORTER_PATH: '$exePath'." }

    $separators = [char[]]@('\', '/')
    $normalizedExeFolder = [System.IO.Path]::GetFullPath($exeFolder).TrimEnd($separators)
    $normalizedDest      = [System.IO.Path]::GetFullPath($destPath).TrimEnd($separators)

    if ($normalizedExeFolder -ine $normalizedDest) {
        throw "DCA_IMPORTER_PATH e DCA_IMPORTER_DESTINATION apontam para pastas diferentes. Caminho do executavel: '$exeFolder'. Destino configurado: '$destPath'."
    }

    # --- 6. Preparar o destino local (remove copia incompleta e recria a pasta) ---
    try {
        $normalizedSource = [System.IO.Path]::GetFullPath($sourcePath).TrimEnd($separators)

        if ($normalizedSource -ieq $normalizedDest -or
            $normalizedSource.StartsWith($normalizedDest + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase)) {
            throw "O destino do Importar GD nao pode ser igual ou conter a pasta de origem. Origem: '$normalizedSource'. Destino: '$normalizedDest'."
        }

        if (Test-Path -LiteralPath $destPath) {
            Write-Host "  Removendo copia local incompleta do Importar GD..." -ForegroundColor DarkGray
            Remove-Item -LiteralPath $destPath -Recurse -Force -ErrorAction Stop
        }

        New-Item -ItemType Directory -Path $destPath -Force -ErrorAction Stop | Out-Null
    }
    catch {
        $root = $_.Exception; while ($null -ne $root.InnerException) { $root = $root.InnerException }
        throw "Nao foi possivel preparar o destino local do Importar GD em '$destPath': $($root.Message)"
    }

    # --- 7. Copiar o Importar GD ---
    Write-Host "  Copiando Importar GD da rede..." -ForegroundColor Cyan
    if ($Details) {
        Write-Host "  Origem:  $sourcePath" -ForegroundColor DarkGray
        Write-Host "  Destino: $destPath" -ForegroundColor DarkGray
    }

    try {
        Get-ChildItem -LiteralPath $sourcePath -Force -ErrorAction Stop |
            Copy-Item -Destination $destPath -Recurse -Force -ErrorAction Stop
    }
    catch {
        $root = $_.Exception; while ($null -ne $root.InnerException) { $root = $root.InnerException }
        throw "Falha ao copiar o Importar GD de '$sourcePath' para '$destPath': $($root.Message)"
    }

    # --- 8. Desbloquear os arquivos copiados e confirmar a copia ---
    Get-ChildItem -LiteralPath $destPath -File -Recurse -ErrorAction SilentlyContinue | Unblock-File -ErrorAction SilentlyContinue

    if (-not (Test-Path -LiteralPath $exePath -PathType Leaf)) {
        throw "A copia do Importar GD foi concluida, mas o executavel nao foi encontrado no destino esperado: '$exePath'."
    }

    Write-Success "Importar GD copiado com sucesso: $exePath"
    return $exePath
}

# Le a configuracao do ambiente (Teste ou Processo) e retorna URL, servidor,
# usuario e senha. Valida DCA_TC_ENV, pede a senha quando vazia, valida a URL
# e confirma que o servidor corresponde ao ambiente.
function Get-TeamcenterSettings {

    # --- 1. Ler o ambiente e escolher as variaveis (URL, usuario e senha independentes) ---
    $environment = ([string]$env:DCA_TC_ENV).Trim()
    if ($environment -eq "") { throw "DCA_TC_ENV nao foi configurado. Use Teste ou Processo." }

    switch ($environment.ToLowerInvariant()) {
        "teste" {
            $environment = "Teste"
            $url = [string]$env:DCA_TC_TEST_URL; $user = [string]$env:DCA_TC_TEST_USER; $password = [string]$env:DCA_TC_TEST_PASSWORD
        }
        "processo" {
            $environment = "Processo"
            $url = [string]$env:DCA_TC_PROCESS_URL; $user = [string]$env:DCA_TC_PROCESS_USER; $password = [string]$env:DCA_TC_PROCESS_PASSWORD
        }
        default { throw "Ambiente Teamcenter invalido: '$environment'. Use Teste ou Processo." }
    }

    # --- 2. Validar URL e usuario ---
    if ([string]::IsNullOrWhiteSpace($url))  { throw "A URL do Teamcenter nao foi configurada para o ambiente '$environment'." }
    if ([string]::IsNullOrWhiteSpace($user)) { throw "O usuario do Teamcenter nao foi configurado para o ambiente '$environment'." }

    # Espacos acidentais saem da URL e do usuario; a senha nao e normalizada porque espacos podem fazer parte dela.
    $url  = $url.Trim()
    $user = $user.Trim()

    # --- 3. Obter a senha (sem senha no .env, pede uma SecureString no console) ---
    if ([string]::IsNullOrWhiteSpace($password)) {
        $securePassword = Read-Host "Senha do Teamcenter para '$user'" -AsSecureString
        $password = [System.Net.NetworkCredential]::new("", $securePassword).Password
        if ([string]::IsNullOrWhiteSpace([string]$password)) { throw "Nenhuma senha foi informada para o usuario '$user'." }
    }

    # --- 4. Validar o formato da URL ---
    $parsedUri = $null
    if (-not [System.Uri]::TryCreate($url, [System.UriKind]::Absolute, [ref]$parsedUri) -or $null -eq $parsedUri) {
        throw "URL invalida para o ambiente '$environment': '$url'."
    }
    if ($parsedUri.Scheme -ine "http" -and $parsedUri.Scheme -ine "https") {
        throw "A URL do Teamcenter deve utilizar HTTP ou HTTPS. Protocolo recebido: '$($parsedUri.Scheme)'."
    }

    # --- 5. Confirmar o servidor (evita conectar em Processo estando em Teste, ou o inverso) ---
    $expectedHost = if ($environment -eq "Teste") { "perto30-novo.perto.com.br" } else { "perto37-novo.perto.com.br" }

    if ($parsedUri.Host -ine $expectedHost) {
        throw "A URL configurada nao corresponde ao ambiente. Ambiente: '$environment'. Servidor esperado: '$expectedHost'. Servidor recebido: '$($parsedUri.Host)'."
    }

    return [PSCustomObject]@{
        Url         = $url
        Host        = $parsedUri.Host
        Environment = $environment
        User        = $user
        Password    = $password
    }
}

# Carrega o assembly do importador, cria a sessao e autentica o usuario.
# A sessao e reutilizada durante a execucao enquanto estiver valida.
function Connect-Teamcenter {
    if ($null -ne $script:TeamcenterSession -and $null -ne $script:TeamcenterFunctions) { return $script:TeamcenterSession }

    # --- 1. Validar o importador e obter as configuracoes ---
    $importerExecutablePath = Confirm-TeamcenterImporter
    $settings = Get-TeamcenterSettings
    $script:TeamcenterEnvironment = $settings.Environment

    # --- 2. Apresentar o ambiente selecionado ---
    Write-Host ""
    if ($settings.Environment -eq "Teste") { Write-Host "  [AMBIENTE] Teamcenter de TESTES" -ForegroundColor Cyan }
    else { Write-Host "  [AMBIENTE] Teamcenter de PROCESSO" -ForegroundColor Yellow }

    if ($Details) {
        Write-Host "  Servidor: $($settings.Url)" -ForegroundColor Gray
        Write-Host "  Usuario:  $($settings.User)" -ForegroundColor Gray
    }
    Write-Host ""

    # --- 3. Carregar o assembly do Importar GD ---
    try { $script:ImporterAssembly = [System.Reflection.Assembly]::LoadFrom($importerExecutablePath) }
    catch {
        $root = $_.Exception; while ($null -ne $root.InnerException) { $root = $root.InnerException }
        throw "Nao foi possivel carregar o Importar GD em '$importerExecutablePath': $($root.Message)"
    }
    if ($null -eq $script:ImporterAssembly) { throw "O carregamento do Importar GD retornou NULL para '$importerExecutablePath'." }

    # --- 4. Criar a sessao (o tipo ausente indica assembly incompativel com DCA_IMPORTER_PATH) ---
    $sessionType = $script:ImporterAssembly.GetType("Teamcenter.ClientX.Session")
    if ($null -eq $sessionType) { throw "O tipo Teamcenter.ClientX.Session nao foi encontrado no assembly do Importar GD." }

    $script:TeamcenterSession = [System.Activator]::CreateInstance($sessionType, @($settings.Url))
    if ($null -eq $script:TeamcenterSession) { throw "A sessao do Teamcenter retornou NULL." }

    # --- 5. Autenticar (a senha nunca aparece em mensagens ou diagnosticos) ---
    if ([string]::IsNullOrWhiteSpace([string]$settings.Password)) { throw "A senha do Teamcenter ficou vazia antes da autenticacao." }

    try { $authenticatedUser = $script:TeamcenterSession.login($settings.User, $settings.Password, "", "", "SoaAppX") }
    catch {
        # A mensagem real pode estar em excecoes internas do assembly.
        $root = $_.Exception; while ($null -ne $root.InnerException) { $root = $root.InnerException }
        throw "Falha ao autenticar o usuario '$($settings.User)' no Teamcenter de $($settings.Environment). Servidor: '$($settings.Host)'. Detalhe retornado pelo Teamcenter: $($root.Message)"
    }
    if ($null -eq $authenticatedUser) { throw "O login do Teamcenter foi executado, mas retornou NULL." }
    if ($Details) { Write-Host "  Usuario autenticado no Teamcenter." -ForegroundColor Green }

    # --- 6. Carregar as funcoes auxiliares e as bibliotecas de Saved Query ---
    $script:TeamcenterFunctions = $script:ImporterAssembly.GetType("ImportarGD.Controller.Functions")
    if ($null -eq $script:TeamcenterFunctions) { throw "ImportarGD.Controller.Functions nao encontrado." }

    Import-TeamcenterQueryAssemblies
    if ($Details) { Write-Host "  Bibliotecas de consulta do Teamcenter carregadas." -ForegroundColor DarkGray }

    return $script:TeamcenterSession
}

# Diagnostico: lista os metodos do Importar GD relacionados a arquivos.
function Show-TeamcenterImporterFileMethods {
    if ($null -eq $script:TeamcenterFunctions) { throw "As funcoes do Importar GD nao foram carregadas. Execute Connect-Teamcenter primeiro." }

    Write-Host ""
    Write-Host "  Metodos do Importar GD relacionados a arquivos:" -ForegroundColor Cyan
    Write-Host ("  " + ("-" * 68)) -ForegroundColor DarkGray

    $candidateMethods = @(
        $script:TeamcenterFunctions.GetMethods() |
            Where-Object { $_.Name -match '(?i)(import|dataset|solid|sld|arquivo|file|document)' } |
            Sort-Object Name, { $_.GetParameters().Count }
    )

    if ($candidateMethods.Count -eq 0) { Write-Warn "Nenhum metodo relacionado a arquivos foi encontrado no Importar GD."; return }

    foreach ($method in $candidateMethods) {
        Write-Host "  Metodo: $($method.Name)" -ForegroundColor White
        Write-Host "    Estatico: $($method.IsStatic)" -ForegroundColor DarkGray
        Write-Host "    Retorno: $($method.ReturnType.FullName)" -ForegroundColor DarkGray

        $parameters = $method.GetParameters()
        if ($parameters.Count -eq 0) { Write-Host "    Parametros: nenhum" -ForegroundColor DarkGray }
        else {
            for ($i = 0; $i -lt $parameters.Count; $i++) {
                Write-Host ("    [{0}] {1} {2}" -f $i, $parameters[$i].ParameterType.FullName, $parameters[$i].Name) -ForegroundColor Gray
            }
        }
        Write-Host ""
    }
}

# Localiza um metodo de ImportarGD.Controller.Functions pelo nome e pela
# quantidade de parametros (diferencia sobrecargas de mesmo nome).
function Get-TeamcenterMethod {
    param(
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$MethodName,
        [Parameter(Mandatory)][ValidateRange(0, 100)][int]$ParameterCount
    )

    if ($null -eq $script:TeamcenterFunctions) { throw "As funcoes do Teamcenter nao foram carregadas. Execute Connect-Teamcenter primeiro." }

    $method = $script:TeamcenterFunctions.GetMethods() |
        Where-Object { $_.Name -eq $MethodName -and $_.GetParameters().Count -eq $ParameterCount } |
        Select-Object -First 1

    if ($null -eq $method) { throw "Metodo '$MethodName' com $ParameterCount parametro(s) nao foi encontrado no Importar GD." }

    return $method
}

# Recupera a conexao SOA mantida pela sessao autenticada.
function Get-TeamcenterConnection {
    if ($null -eq $script:ImporterAssembly) { throw "O assembly do Importar GD nao foi carregado. Execute Connect-Teamcenter primeiro." }

    $sessionType = $script:ImporterAssembly.GetType("Teamcenter.ClientX.Session")
    if ($null -eq $sessionType) { throw "Tipo Teamcenter.ClientX.Session nao encontrado." }

    # getConnection e estatico e fornece a conexao SOA da sessao.
    $getConnectionMethod = $sessionType.GetMethod("getConnection")
    if ($null -eq $getConnectionMethod) { throw "Metodo Session.getConnection nao encontrado." }

    $connection = $getConnectionMethod.Invoke($null, @())
    if ($null -eq $connection) { throw "A conexao SOA do Teamcenter retornou NULL." }

    return $connection
}

# Carrega TcSoaQueryTypes.dll e TcSoaQueryStrong.dll (pasta do Importar GD)
# em $script:TeamcenterQueryAssemblies.
function Import-TeamcenterQueryAssemblies {
    if ($Details) { Write-Host "  Iniciando carregamento das bibliotecas de consulta..." -ForegroundColor Cyan }

    # Reinicia a lista para nao acumular assemblies de uma carga anterior.
    $script:TeamcenterQueryAssemblies = [System.Collections.Generic.List[object]]::new()

    $importerFolder = [System.IO.Path]::GetDirectoryName((Confirm-TeamcenterImporter))
    $queryAssemblyNames = @("TcSoaQueryTypes.dll", "TcSoaQueryStrong.dll")

    foreach ($name in $queryAssemblyNames) {
        $path = Join-Path -Path $importerFolder -ChildPath $name
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Biblioteca de consulta nao encontrada: '$path'." }

        try {
            $assembly = [System.Reflection.Assembly]::LoadFrom($path)
            if ($null -eq $assembly) { throw "Assembly.LoadFrom retornou NULL para '$name'." }

            $script:TeamcenterQueryAssemblies.Add($assembly)

            if ($Details) {
                Write-Host "  Biblioteca de consulta carregada: $name" -ForegroundColor Green
                Write-Host "    Nome interno: $($assembly.GetName().Name)" -ForegroundColor DarkGray
                Write-Host "    Local: $($assembly.Location)" -ForegroundColor DarkGray
            }
        }
        catch {
            $root = $_.Exception; while ($null -ne $root.InnerException) { $root = $root.InnerException }
            throw "Falha ao carregar '$name': $($root.Message)"
        }
    }

    if ($script:TeamcenterQueryAssemblies.Count -ne $queryAssemblyNames.Count) { throw "Nem todas as bibliotecas de consulta foram carregadas." }
}

function Get-TeamcenterDataManagementService {
    $connection = Get-TeamcenterConnection

    # O tipo e procurado em todos os assemblies do AppDomain, sem depender de um assembly fixo.
    $serviceType = [System.AppDomain]::CurrentDomain.GetAssemblies() |
        ForEach-Object {
            try { $_.GetType("Teamcenter.Services.Strong.Core.DataManagementService", $false, $false) }
            catch { $null }
        } |
        Where-Object { $null -ne $_ } | Select-Object -First 1
    if ($null -eq $serviceType) { throw "Tipo DataManagementService nao encontrado." }

    $getServiceMethod = $serviceType.GetMethods() |
        Where-Object { $_.Name -eq "getService" -and $_.GetParameters().Count -eq 1 } | Select-Object -First 1
    if ($null -eq $getServiceMethod) { throw "Metodo DataManagementService.getService nao encontrado." }

    $service = $getServiceMethod.Invoke($null, @($connection))
    if ($null -eq $service) { throw "DataManagementService retornou NULL." }

    return $service
}

# Converte os erros parciais do ServiceData em mensagens de texto para log e
# excecoes. Se o objeto nao tiver os metodos esperados, retorna lista vazia
# (compatibilidade entre versoes das bibliotecas SOA).
function Get-TeamcenterServiceErrors {
    param([Parameter(Mandatory)][AllowNull()]$ServiceData)

    $errorMessages = [System.Collections.Generic.List[string]]::new()
    if ($null -eq $ServiceData) { return $errorMessages.ToArray() }

    $methods = $ServiceData.GetType().GetMethods()
    $sizeMethod = $methods | Where-Object { $_.Name -ieq "SizeOfPartialErrors" -and $_.GetParameters().Count -eq 0 } | Select-Object -First 1
    $getErrorMethod = $methods | Where-Object { $_.Name -ieq "GetPartialError" -and $_.GetParameters().Count -eq 1 } | Select-Object -First 1
    if ($null -eq $sizeMethod -or $null -eq $getErrorMethod) { return $errorMessages.ToArray() }

    try {
        $errorCount = [int]$sizeMethod.Invoke($ServiceData, @())

        for ($i = 0; $i -lt $errorCount; $i++) {
            $partialError = $getErrorMethod.Invoke($ServiceData, @([int]$i))
            if ($null -eq $partialError) { continue }

            $errorValuesProperty = $partialError.GetType().GetProperty("ErrorValues")

            if ($null -ne $errorValuesProperty) {
                foreach ($errorValue in @($errorValuesProperty.GetValue($partialError, $null))) {
                    if ($null -eq $errorValue) { continue }

                    $messageProperty = $errorValue.GetType().GetProperty("Message")
                    if ($null -eq $messageProperty) { continue }

                    $messageText = [string]$messageProperty.GetValue($errorValue, $null)
                    if (-not [string]::IsNullOrWhiteSpace($messageText)) { $errorMessages.Add($messageText.Trim()) }
                }
            }
            else {
                $partialErrorText = ([string]$partialError).Trim()
                if ($partialErrorText -ne "") { $errorMessages.Add($partialErrorText) }
            }
        }
    }
    catch {
        if ($Details) {
            $root = $_.Exception; while ($null -ne $root.InnerException) { $root = $root.InnerException }
            Write-Warn "Nao foi possivel interpretar os erros SOA: $($root.Message)"
        }
    }

    return @($errorMessages | Select-Object -Unique)
}