# ============================================================
# CONEXAO, SESSAO E SERVICOS DO TEAMCENTER
# ============================================================
#
# Este arquivo concentra os recursos compartilhados necessários
# para acessar os servicos SOA do Teamcenter.
#
# Responsabilidades:
#   1. validar o executavel Importar GD;
#   2. ler e validar a configuracao do ambiente;
#   3. autenticar e reutilizar a sessao do Teamcenter;
#   4. localizar metodos expostos pelo Importar GD;
#   5. recuperar a conexao SOA da sessao;
#   6. carregar os assemblies utilizados pelas Saved Queries;
#   7. fornecer o DataManagementService;
#   8. converter erros parciais SOA em mensagens legiveis.
#
# Nenhuma funcao deste arquivo cria Items, revisoes ou Datasets
# diretamente. As funcoes apenas preparam e fornecem os recursos
# compartilhados utilizados pelos demais modulos.
# ============================================================

# ============================================================
# VALIDACAO DO IMPORTADOR
# ============================================================
function Confirm-TeamcenterImporter {

  # Valida o executavel Importar GD configurado no .env.
  #
  # Se o executavel nao existir no destino local, copia
  # automaticamente todos os arquivos da origem de rede.

  # ============================================================
  # 1. LER AS CONFIGURACOES DO IMPORTAR GD
  # ============================================================

  $importerExecutablePath =
  ([string]$env:DCA_IMPORTER_PATH).Trim()

  $importerSourcePath =
  ([string]$env:DCA_IMPORTER_SOURCE).Trim()

  $importerDestinationPath =
  ([string]$env:DCA_IMPORTER_DESTINATION).Trim()

  if ($Details) {

    Write-Host (
      "  DCA_IMPORTER_SOURCE: '{0}'" -f
      $importerSourcePath
    ) -ForegroundColor DarkGray

    Write-Host (
      "  DCA_IMPORTER_DESTINATION: '{0}'" -f
      $importerDestinationPath
    ) -ForegroundColor DarkGray

    Write-Host (
      "  DCA_IMPORTER_PATH: '{0}'" -f
      $importerExecutablePath
    ) -ForegroundColor DarkGray
  }

  if (
    [string]::IsNullOrWhiteSpace(
      $importerExecutablePath
    )
  ) {

    throw (
      "DCA_IMPORTER_PATH deve ser configurado no arquivo .env."
    )
  }

  # ============================================================
  # 2. RETORNAR SE O EXECUTAVEL JA EXISTIR
  # ============================================================

  if (
    Test-Path `
      -LiteralPath $importerExecutablePath `
      -PathType Leaf
  ) {

    if ($Details) {

      Write-Host (
        "  Importar GD disponivel: " +
        $importerExecutablePath
      ) -ForegroundColor DarkGray
    }

    return $importerExecutablePath
  }

  # ============================================================
  # 3. VALIDAR AS CONFIGURACOES DA COPIA AUTOMATICA
  # ============================================================

  Write-Warn (
    (
      "Importar GD nao encontrado em '{0}'. " +
      "Iniciando copia automatica."
    ) -f $importerExecutablePath
  )

  if (
    [string]::IsNullOrWhiteSpace(
      $importerSourcePath
    )
  ) {

    throw (
      "O Importar GD nao existe no destino e " +
      "DCA_IMPORTER_SOURCE nao foi configurado no .env."
    )
  }

  if (
    [string]::IsNullOrWhiteSpace(
      $importerDestinationPath
    )
  ) {

    throw (
      "O Importar GD nao existe no destino e " +
      "DCA_IMPORTER_DESTINATION nao foi configurado no .env."
    )
  }

  # ============================================================
  # 4. VALIDAR A ORIGEM DE REDE
  # ============================================================

  if (-not (
      Test-Path `
        -LiteralPath $importerSourcePath `
        -PathType Container
    )) {

    throw (
      "A origem do Importar GD nao foi encontrada ou nao esta " +
      "acessivel: '{0}'. Verifique a conexao com a rede." -f
      $importerSourcePath
    )
  }

  $sourceExecutablePath =
  Join-Path `
    -Path $importerSourcePath `
    -ChildPath "Importar GD.exe"

  if (-not (
      Test-Path `
        -LiteralPath $sourceExecutablePath `
        -PathType Leaf
    )) {

    throw (
      "A origem do Importar GD foi encontrada, mas nao contem " +
      "o executavel esperado: '{0}'." -f
      $sourceExecutablePath
    )
  }

  # ============================================================
  # 5. VALIDAR A COERENCIA DO DESTINO
  # ============================================================

  $configuredExecutableFolder =
  [System.IO.Path]::GetDirectoryName(
    $importerExecutablePath
  )

  if (
    [string]::IsNullOrWhiteSpace(
      $configuredExecutableFolder
    )
  ) {

    throw (
      "Nao foi possivel identificar a pasta de destino a partir " +
      "de DCA_IMPORTER_PATH: '$importerExecutablePath'."
    )
  }

  $normalizedConfiguredFolder =
  [System.IO.Path]::GetFullPath(
    $configuredExecutableFolder
  ).TrimEnd(
  [char[]]@(
    '\',
    '/'
  )
)

$normalizedDestinationFolder =
[System.IO.Path]::GetFullPath(
  $importerDestinationPath
).TrimEnd(
[char[]]@(
  '\',
  '/'
)
)

if (
  $normalizedConfiguredFolder -ine
  $normalizedDestinationFolder
) {

  throw (
    "DCA_IMPORTER_PATH e DCA_IMPORTER_DESTINATION apontam " +
    "para pastas diferentes. Caminho do executavel: '{0}'. " +
    "Destino configurado: '{1}'." -f
    $configuredExecutableFolder,
    $importerDestinationPath
  )
}

# ============================================================
# 6. PREPARAR O DESTINO LOCAL
# ============================================================

try {

  if (
    Test-Path `
      -LiteralPath $importerDestinationPath
  ) {

    Write-Host (
      "  Removendo copia local incompleta do Importar GD..."
    ) -ForegroundColor DarkGray

    Remove-Item `
      -LiteralPath $importerDestinationPath `
      -Recurse `
      -Force `
      -ErrorAction Stop
  }

  New-Item `
    -ItemType Directory `
    -Path $importerDestinationPath `
    -Force `
    -ErrorAction Stop |
    Out-Null
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

  throw (
    "Nao foi possivel preparar o destino local do " +
    "Importar GD em '{0}': {1}" -f
    $importerDestinationPath,
    $realException.Message
  )
}

# ============================================================
# 7. COPIAR O IMPORTAR GD
# ============================================================

Write-Host (
  "  Copiando Importar GD da rede..."
) -ForegroundColor Cyan

if ($Details) {

  Write-Host (
    "  Origem:  $importerSourcePath"
  ) -ForegroundColor DarkGray

  Write-Host (
    "  Destino: $importerDestinationPath"
  ) -ForegroundColor DarkGray
}

try {

  Get-ChildItem `
    -LiteralPath $importerSourcePath `
    -Force `
    -ErrorAction Stop |
    Copy-Item `
    -Destination $importerDestinationPath `
    -Recurse `
    -Force `
    -ErrorAction Stop
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

  throw (
    "Falha ao copiar o Importar GD de '{0}' para '{1}': {2}" -f
    $importerSourcePath,
    $importerDestinationPath,
    $realException.Message
  )
}

# ============================================================
# 8. DESBLOQUEAR OS ARQUIVOS COPIADOS
# ============================================================

Get-ChildItem `
  -LiteralPath $importerDestinationPath `
  -File `
  -Recurse `
  -ErrorAction SilentlyContinue |
  Unblock-File `
  -ErrorAction SilentlyContinue

# ============================================================
# 9. CONFIRMAR A COPIA
# ============================================================

if (-not (
    Test-Path `
      -LiteralPath $importerExecutablePath `
      -PathType Leaf
  )) {

  throw (
    "A copia do Importar GD foi concluida, mas o executavel " +
    "nao foi encontrado no destino esperado: '{0}'." -f
    $importerExecutablePath
  )
}

Write-Success (
  "Importar GD copiado com sucesso: {0}" -f
  $importerExecutablePath
)

return $importerExecutablePath
}

# ============================================================
# CONFIGURACAO DO AMBIENTE E DAS CREDENCIAIS
# ============================================================
function Get-TeamcenterSettings {

  # Le a configuracao do ambiente selecionado e retorna a URL,
  # o servidor, o usuario e a senha utilizados na autenticacao.
  #
  # A funcao tambem:
  #   1. valida o valor de DCA_TC_ENV;
  #   2. escolhe as variaveis de Teste ou Processo;
  #   3. solicita a senha quando ela estiver vazia;
  #   4. valida o formato da URL;
  #   5. confirma que o servidor corresponde ao ambiente.

  # ============================================================
  # 1. LER E VALIDAR O AMBIENTE CONFIGURADO
  # ============================================================
  $teamcenterEnvironment =
  [string]$env:DCA_TC_ENV

  if (
    [string]::IsNullOrWhiteSpace(
      $teamcenterEnvironment
    )
  ) {

    throw (
      "DCA_TC_ENV nao foi configurado. " +
      "Use Teste ou Processo."
    )
  }

  $teamcenterEnvironment =
  $teamcenterEnvironment.Trim()

  $teamcenterServerUrl =
  $null

  $teamcenterUser =
  $null

  $teamcenterPassword =
  $null

  # ============================================================
  # 2. SELECIONAR A CONFIGURACAO DO AMBIENTE
  # ============================================================
  #
  # Cada ambiente possui URL, usuario e senha independentes.
  switch ($teamcenterEnvironment.ToLowerInvariant()) {

    "teste" {

      $teamcenterEnvironment =
      "Teste"

      $teamcenterServerUrl =
      [string]$env:DCA_TC_TEST_URL

      $teamcenterUser =
      [string]$env:DCA_TC_TEST_USER

      $teamcenterPassword =
      [string]$env:DCA_TC_TEST_PASSWORD
    }

    "processo" {

      $teamcenterEnvironment =
      "Processo"

      $teamcenterServerUrl =
      [string]$env:DCA_TC_PROCESS_URL

      $teamcenterUser =
      [string]$env:DCA_TC_PROCESS_USER

      $teamcenterPassword =
      [string]$env:DCA_TC_PROCESS_PASSWORD
    }

    default {

      throw (
        "Ambiente Teamcenter invalido: " +
        "'$teamcenterEnvironment'. " +
        "Use Teste ou Processo."
      )
    }
  }

  # ============================================================
  # 3. VALIDAR URL E USUARIO
  # ============================================================
  if (
    [string]::IsNullOrWhiteSpace(
      $teamcenterServerUrl
    )
  ) {

    throw (
      "A URL do Teamcenter nao foi configurada para " +
      "o ambiente '$teamcenterEnvironment'."
    )
  }

  if (
    [string]::IsNullOrWhiteSpace(
      $teamcenterUser
    )
  ) {

    throw (
      "O usuario do Teamcenter nao foi configurado para " +
      "o ambiente '$teamcenterEnvironment'."
    )
  }
  # Remove espacos acidentais da URL e do usuario. A senha nao
  # deve ser normalizada porque espacos podem fazer parte dela.
  $teamcenterServerUrl =
  $teamcenterServerUrl.Trim()

  $teamcenterUser =
  $teamcenterUser.Trim()
  # ============================================================
  # 4. OBTER A SENHA DO USUARIO
  # ============================================================
  #
  # Quando a senha nao estiver preenchida no .env, solicita uma
  # SecureString no console e converte o valor somente para a
  # autenticacao realizada durante a execucao atual.
  if (
    [string]::IsNullOrWhiteSpace(
      $teamcenterPassword
    )
  ) {

    $securePassword =
    Read-Host (
      "Senha do Teamcenter para '$teamcenterUser'"
    ) -AsSecureString

    $credential =
    [System.Net.NetworkCredential]::new(
      "",
      $securePassword
    )

    $teamcenterPassword =
    $credential.Password

    if (
      [string]::IsNullOrWhiteSpace(
        [string]$teamcenterPassword
      )
    ) {

      throw (
        "Nenhuma senha foi informada para o usuario " +
        "'$teamcenterUser'."
      )
    }
  }

  # ============================================================
  # 5. VALIDAR O FORMATO DA URL
  # ============================================================
  $parsedUri =
  $null

  $validUrl =
  [System.Uri]::TryCreate(
    $teamcenterServerUrl,
    [System.UriKind]::Absolute,
    [ref]$parsedUri
  )

  if (
    -not $validUrl -or
    $null -eq $parsedUri
  ) {

    throw (
      "URL invalida para o ambiente " +
      "'$teamcenterEnvironment': " +
      "'$teamcenterServerUrl'."
    )
  }

  if (
    $parsedUri.Scheme -ine "http" -and
    $parsedUri.Scheme -ine "https"
  ) {

    throw (
      "A URL do Teamcenter deve utilizar HTTP ou HTTPS. " +
      "Protocolo recebido: '$($parsedUri.Scheme)'."
    )
  }

  # ============================================================
  # 6. CONFIRMAR O SERVIDOR DO AMBIENTE
  # ============================================================
  #
  # Essa verificacao impede uma conexao acidental ao servidor
  # de Processo quando o ambiente selecionado for Teste, ou o
  # caminho inverso.
  $expectedHost =
  if ($teamcenterEnvironment -eq "Teste") {
    "perto30-novo.perto.com.br"
  }
  else {
    "perto37-novo.perto.com.br"
  }

  if (
    $parsedUri.Host -ine $expectedHost
  ) {

    throw (
      "A URL configurada nao corresponde ao ambiente. " +
      "Ambiente: '$teamcenterEnvironment'. " +
      "Servidor esperado: '$expectedHost'. " +
      "Servidor recebido: '$($parsedUri.Host)'."
    )
  }

  # ============================================================
  # 7. RETORNAR A CONFIGURACAO VALIDADA
  # ============================================================
  return [PSCustomObject]@{
    Url = $teamcenterServerUrl
    Host = $parsedUri.Host
    Environment = $teamcenterEnvironment
    User = $teamcenterUser
    Password = $teamcenterPassword
  }
}

# ============================================================
# CONEXAO E AUTENTICACAO
# ============================================================
function Connect-Teamcenter {

  # Reutiliza a sessao autenticada durante a mesma execucao.
  #
  # A sessao somente e criada novamente quando ainda nao existe
  # uma sessao valida ou quando o tipo de funcoes nao foi carregado.
  if (
    $null -ne $script:TeamcenterSession -and
    $null -ne $script:TeamcenterFunctions
  ) {

    return $script:TeamcenterSession
  }

  # Carrega o assembly do importador, cria a sessao e autentica
  # o usuario no ambiente configurado.

  # ============================================================
  # 1. VALIDAR O IMPORTADOR E OBTER AS CONFIGURACOES
  # ============================================================
  $importerExecutablePath = Confirm-TeamcenterImporter
  $settings = Get-TeamcenterSettings
  $script:TeamcenterEnvironment = $settings.Environment

  # ============================================================
  # 2. APRESENTAR O AMBIENTE SELECIONADO
  # ============================================================
  Write-Host ""

  if ($settings.Environment -eq "Teste") {

    Write-Host (
      "  [AMBIENTE] Teamcenter de TESTES"
    ) -ForegroundColor Cyan
  }
  else {

    Write-Host (
      "  [AMBIENTE] Teamcenter de PROCESSO"
    ) -ForegroundColor Yellow
  }
  if ($Details) {

    Write-Host (
      "  Servidor: $($settings.Url)"
    ) -ForegroundColor Gray

    Write-Host (
      "  Usuario:  $($settings.User)"
    ) -ForegroundColor Gray
  }

  Write-Host ""

  # ============================================================
  # 3. CARREGAR O ASSEMBLY DO IMPORTAR GD
  # ============================================================
  try {

    $script:ImporterAssembly =
    [System.Reflection.Assembly]::LoadFrom(
      $importerExecutablePath
    )
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

    throw (
      "Nao foi possivel carregar o Importar GD em " +
      "'$importerExecutablePath': " +
      $realException.Message
    )
  }

  if ($null -eq $script:ImporterAssembly) {

    throw (
      "O carregamento do Importar GD retornou NULL para " +
      "'$importerExecutablePath'."
    )
  }

  # ============================================================
  # 4. CRIAR A SESSAO DO TEAMCENTER
  # ============================================================
  #
  # Localiza no assembly do Importar GD o tipo responsavel pela
  # sessao utilizada para autenticar e acessar os servicos SOA.
  $sessionType =
  $script:ImporterAssembly.GetType(
    "Teamcenter.ClientX.Session"
  )

  # O tipo precisa ser localizado antes da chamada ao Activator.
  # Uma falha nesta etapa normalmente indica incompatibilidade
  # com o assembly configurado em DCA_IMPORTER_PATH.
  if ($null -eq $sessionType) {

    throw (
      "O tipo Teamcenter.ClientX.Session nao foi encontrado " +
      "no assembly do Importar GD."
    )
  }

  $script:TeamcenterSession =
  [System.Activator]::CreateInstance(
    $sessionType,
    @($settings.Url)
  )

  if ($null -eq $script:TeamcenterSession) {

    throw (
      "A sessao do Teamcenter retornou NULL."
    )
  }
  # ============================================================
  # 5. AUTENTICAR O USUARIO
  # ============================================================
  #
  # A senha e mantida somente durante a execucao atual. O
  # conteudo nao deve ser apresentado em mensagens ou diagnosticos.
  if (
    [string]::IsNullOrWhiteSpace(
      [string]$settings.Password
    )
  ) {

    throw (
      "A senha do Teamcenter ficou vazia antes da autenticacao."
    )
  }

  try {

    $authenticatedUser =
    $script:TeamcenterSession.login(
      $settings.User,
      $settings.Password,
      "",
      "",
      "SoaAppX"
    )
  }
  catch {

    # As chamadas realizadas pelo assembly podem encapsular a
    # mensagem real em uma ou mais excecoes internas.
    $realException =
    $_.Exception

    while (
      $null -ne $realException.InnerException
    ) {

      $realException =
      $realException.InnerException
    }

    throw (
      "Falha ao autenticar o usuario '$($settings.User)' no " +
      "Teamcenter de $($settings.Environment). " +
      "Servidor: '$($settings.Host)'. " +
      "Detalhe retornado pelo Teamcenter: " +
      $realException.Message
    )
  }

  if ($null -eq $authenticatedUser) {

    throw (
      "O login do Teamcenter foi executado, mas retornou NULL."
    )
  }

  if ($Details) {

    Write-Host (
      "  Usuario autenticado no Teamcenter."
    ) -ForegroundColor Green
  }
  # ============================================================
  # 6. CARREGAR AS FUNCOES AUXILIARES DO IMPORTADOR
  # ============================================================
  $script:TeamcenterFunctions =
  $script:ImporterAssembly.GetType(
    "ImportarGD.Controller.Functions"
  )

  if ($null -eq $script:TeamcenterFunctions) {
    throw "ImportarGD.Controller.Functions nao encontrado."
  }

  # ============================================================
  # 7. CARREGAR AS BIBLIOTECAS DE SAVED QUERY
  # ============================================================
  Import-TeamcenterQueryAssemblies

  if ($Details) {

    Write-Host (
      "  Bibliotecas de consulta do Teamcenter carregadas."
    ) -ForegroundColor DarkGray
  }

  # ============================================================
  # 8. RETORNAR A SESSAO AUTENTICADA
  # ============================================================
  return $script:TeamcenterSession
}

# ============================================================
# DIAGNOSTICO DOS METODOS DE IMPORTACAO DO IMPORTAR GD
# ============================================================
function Show-TeamcenterImporterFileMethods {

  if ($null -eq $script:TeamcenterFunctions) {

    throw (
      "As funcoes do Importar GD nao foram carregadas. " +
      "Execute Connect-Teamcenter primeiro."
    )
  }

  Write-Host ""
  Write-Host (
    "  Metodos do Importar GD relacionados a arquivos:"
  ) -ForegroundColor Cyan

  Write-Host (
    "  " + ("-" * 68)
  ) -ForegroundColor DarkGray

  $candidateMethods =
  @(
    $script:TeamcenterFunctions.GetMethods() |
      Where-Object {
        $_.Name -match
        '(?i)(import|dataset|solid|sld|arquivo|file|document)'
      } |
      Sort-Object Name, {
        $_.GetParameters().Count
      }
  )

  if ($candidateMethods.Count -eq 0) {

    Write-Warn (
      "Nenhum metodo relacionado a arquivos foi encontrado " +
      "no Importar GD."
    )

    return
  }

  foreach ($candidateMethod in $candidateMethods) {

    Write-Host (
      "  Metodo: {0}" -f
      $candidateMethod.Name
    ) -ForegroundColor White

    Write-Host (
      "    Estatico: {0}" -f
      $candidateMethod.IsStatic
    ) -ForegroundColor DarkGray

    Write-Host (
      "    Retorno: {0}" -f
      $candidateMethod.ReturnType.FullName
    ) -ForegroundColor DarkGray

    $methodParameters =
    $candidateMethod.GetParameters()

    if ($methodParameters.Count -eq 0) {

      Write-Host (
        "    Parametros: nenhum"
      ) -ForegroundColor DarkGray
    }
    else {

      for (
        $parameterIndex = 0
        $parameterIndex -lt $methodParameters.Count
        $parameterIndex++
      ) {

        $methodParameter =
        $methodParameters[$parameterIndex]

        Write-Host (
          "    [{0}] {1} {2}" -f
          $parameterIndex,
          $methodParameter.ParameterType.FullName,
          $methodParameter.Name
        ) -ForegroundColor Gray
      }
    }

    Write-Host ""
  }
}

# ============================================================
# LOCALIZACAO DOS METODOS DO IMPORTADOR
# ============================================================
function Get-TeamcenterMethod {
  # Localiza um metodo do tipo ImportarGD.Controller.Functions
  # utilizando o nome e a quantidade esperada de parametros.
  #
  # A quantidade de parametros ajuda a diferenciar sobrecargas
  # que possuam o mesmo nome.
  param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$MethodName,

    [Parameter(Mandatory = $true)]
    [ValidateRange(0, 100)]
    [int]$ParameterCount
  )

  if ($null -eq $script:TeamcenterFunctions) {
    throw (
      "As funcoes do Teamcenter nao foram carregadas. " +
      "Execute Connect-Teamcenter primeiro."
    )
  }

  # Pesquisa somente os metodos que correspondem ao nome e a
  # quantidade de parametros solicitados.
  $method = $script:TeamcenterFunctions.GetMethods() |
    Where-Object {
    $_.Name -eq $MethodName -and
    $_.GetParameters().Count -eq $ParameterCount
  } |
    Select-Object -First 1

  if ($null -eq $method) {
    throw (
      "Metodo '$MethodName' com $ParameterCount parametro(s) " +
      "nao foi encontrado no Importar GD."
    )
  }

  return $method
}

# ============================================================
# RECUPERACAO DA CONEXAO SOA
# ============================================================
function Get-TeamcenterConnection {

  # Recupera a conexao SOA mantida pela sessao autenticada.
  if ($null -eq $script:ImporterAssembly) {
    throw (
      "O assembly do Importar GD nao foi carregado. " +
      "Execute Connect-Teamcenter primeiro."
    )
  }

  # Localiza novamente o tipo Session no assembly carregado.
  $sessionType =
  $script:ImporterAssembly.GetType(
    "Teamcenter.ClientX.Session"
  )
  if ($null -eq $sessionType) {
    throw "Tipo Teamcenter.ClientX.Session nao encontrado."
  }

  # getConnection e um metodo estatico que fornece a conexao SOA
  # mantida pela sessao autenticada.
  $getConnectionMethod =
  $sessionType.GetMethod(
    "getConnection"
  )

  if ($null -eq $getConnectionMethod) {
    throw "Metodo Session.getConnection nao encontrado."
  }

  $connection =
  $getConnectionMethod.Invoke(
    $null,
    @()
  )

  if ($null -eq $connection) {
    throw "A conexao SOA do Teamcenter retornou NULL."
  }

  return $connection
}

# ============================================================
# CARREGAMENTO DOS ASSEMBLIES DE SAVED QUERY
# ============================================================
function Import-TeamcenterQueryAssemblies {

  # Carrega os assemblies utilizados pelas Saved Queries.
  #
  # Os arquivos sao procurados na mesma pasta do Importar GD:
  #   - TcSoaQueryTypes.dll;
  #   - TcSoaQueryStrong.dll.
  #
  # Os objetos Assembly retornados por LoadFrom sao armazenados
  # em $script:TeamcenterQueryAssemblies.

  if ($Details) {

    Write-Host (
      "  Iniciando carregamento das bibliotecas de consulta..."
    ) -ForegroundColor Cyan
  }

  # Reinicializa a lista para impedir que assemblies de uma carga
  # anterior permaneçam armazenados na execucao atual.
  $script:TeamcenterQueryAssemblies =
  [System.Collections.Generic.List[object]]::new()

  # ============================================================
  # 1. LOCALIZAR A PASTA DO IMPORTADOR
  # ============================================================
  $importerExecutablePath =
  Confirm-TeamcenterImporter

  $importerFolder =
  [System.IO.Path]::GetDirectoryName(
    $importerExecutablePath
  )

  # ============================================================
  # 2. DEFINIR AS BIBLIOTECAS OBRIGATORIAS
  # ============================================================
  $queryAssemblyNames =
  @(
    "TcSoaQueryTypes.dll",
    "TcSoaQueryStrong.dll"
  )

  # ============================================================
  # 3. VALIDAR E CARREGAR CADA ASSEMBLY
  # ============================================================
  foreach ($queryAssemblyName in $queryAssemblyNames) {

    $queryAssemblyPath =
    Join-Path `
      -Path $importerFolder `
      -ChildPath $queryAssemblyName

    if (-not (
        Test-Path `
          -LiteralPath $queryAssemblyPath `
          -PathType Leaf
      )) {

      throw (
        "Biblioteca de consulta nao encontrada: " +
        "'$queryAssemblyPath'."
      )
    }

    try {

      $queryAssembly =
      [System.Reflection.Assembly]::LoadFrom(
        $queryAssemblyPath
      )

      if ($null -eq $queryAssembly) {

        throw (
          "Assembly.LoadFrom retornou NULL para " +
          "'$queryAssemblyName'."
        )
      }

      $script:TeamcenterQueryAssemblies.Add(
        $queryAssembly
      )

      if ($Details) {

        Write-Host (
          "  Biblioteca de consulta carregada: " +
          $queryAssemblyName
        ) -ForegroundColor Green

        Write-Host (
          "    Nome interno: " +
          $queryAssembly.GetName().Name
        ) -ForegroundColor DarkGray

        Write-Host (
          "    Local: " +
          $queryAssembly.Location
        ) -ForegroundColor DarkGray
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

      throw (
        "Falha ao carregar '$queryAssemblyName': " +
        $realException.Message
      )
    }
  }

  # ============================================================
  # 4. CONFIRMAR O CARREGAMENTO COMPLETO
  # ============================================================
  if (
    $script:TeamcenterQueryAssemblies.Count -ne
    $queryAssemblyNames.Count
  ) {

    throw (
      "Nem todas as bibliotecas de consulta foram carregadas."
    )
  }
}

function Get-TeamcenterDataManagementService {

  # ============================================================
  # 1. RECUPERAR A CONEXAO SOA
  # ============================================================

  $connection =
  Get-TeamcenterConnection

  # ============================================================
  # 2. LOCALIZAR O TIPO DATAMANAGEMENTSERVICE
  # ============================================================
  #
  # O tipo e pesquisado entre todos os assemblies carregados no
  # AppDomain para evitar dependencia direta de um assembly fixo.
  $serviceType = [System.AppDomain]::CurrentDomain.GetAssemblies() |
    ForEach-Object {
    try {
      $_.GetType(
        "Teamcenter.Services.Strong.Core.DataManagementService",
        $false,
        $false
      )
    }
    catch {
      $null
    }
  } |
    Where-Object { $null -ne $_ } |
    Select-Object -First 1

  if ($null -eq $serviceType) {
    throw "Tipo DataManagementService nao encontrado."
  }

  # ============================================================
  # 3. LOCALIZAR O METODO GETSERVICE
  # ============================================================
  $getServiceMethod = $serviceType.GetMethods() |
    Where-Object {
    $_.Name -eq "getService" -and
    $_.GetParameters().Count -eq 1
  } |
    Select-Object -First 1

  if ($null -eq $getServiceMethod) {
    throw "Metodo DataManagementService.getService nao encontrado."
  }

  # ============================================================
  # 4. INSTANCIAR O SERVICO
  # ============================================================
  $service = $getServiceMethod.Invoke($null, @($connection))

  if ($null -eq $service) {
    throw "DataManagementService retornou NULL."
  }

  return $service
}

# ============================================================
# INTERPRETACAO DOS ERROS PARCIAIS SOA
# ============================================================
function Get-TeamcenterServiceErrors {

  # Converte os erros parciais do ServiceData em mensagens de
  # texto que podem ser utilizadas pelo log e pelas excecoes.
  #
  # Quando o objeto nao disponibiliza os metodos esperados, uma
  # lista vazia e retornada para manter compatibilidade entre
  # diferentes versoes das bibliotecas SOA.
  param(
    [Parameter(Mandatory = $true)]
    [AllowNull()]
    $ServiceData
  )

  # ============================================================
  # 1. PREPARAR A COLECAO DE MENSAGENS
  # ============================================================
  $errorMessages =
  [System.Collections.Generic.List[string]]::new()

  if ($null -eq $ServiceData) {

    return $errorMessages.ToArray()
  }

  # ============================================================
  # 2. LOCALIZAR OS METODOS DE ERRO
  # ============================================================
  $serviceDataType =
  $ServiceData.GetType()

  $sizeMethod =
  $serviceDataType.GetMethods() |
    Where-Object {
    $_.Name -ieq "SizeOfPartialErrors" -and
    $_.GetParameters().Count -eq 0
  } |
    Select-Object -First 1

  $getErrorMethod =
  $serviceDataType.GetMethods() |
    Where-Object {
    $_.Name -ieq "GetPartialError" -and
    $_.GetParameters().Count -eq 1
  } |
    Select-Object -First 1

  if (
    $null -eq $sizeMethod -or
    $null -eq $getErrorMethod
  ) {

    return $errorMessages.ToArray()
  }

  # ============================================================
  # 3. LER OS ERROS PARCIAIS
  # ============================================================
  try {

    $errorCount =
    [int]$sizeMethod.Invoke(
      $ServiceData,
      @()
    )

    for (
      $errorIndex = 0
      $errorIndex -lt $errorCount
      $errorIndex++
    ) {

      $partialError =
      $getErrorMethod.Invoke(
        $ServiceData,
        @([int]$errorIndex)
      )

      if ($null -eq $partialError) {
        continue
      }

      $errorValuesProperty =
      $partialError.GetType().GetProperty(
        "ErrorValues"
      )

      if ($null -ne $errorValuesProperty) {

        $errorValues =
        @(
          $errorValuesProperty.GetValue(
            $partialError,
            $null
          )
        )

        foreach ($errorValue in $errorValues) {

          if ($null -eq $errorValue) {
            continue
          }

          $messageProperty =
          $errorValue.GetType().GetProperty(
            "Message"
          )

          if ($null -eq $messageProperty) {
            continue
          }

          $messageText =
          [string]$messageProperty.GetValue(
            $errorValue,
            $null
          )

          if (
            -not [string]::IsNullOrWhiteSpace(
              $messageText
            )
          ) {

            $errorMessages.Add(
              $messageText.Trim()
            )
          }
        }
      }
      else {

        $partialErrorText =
        ([string]$partialError).Trim()

        if (
          -not [string]::IsNullOrWhiteSpace(
            $partialErrorText
          )
        ) {

          $errorMessages.Add(
            $partialErrorText
          )
        }
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

      Write-Warn (
        "Nao foi possivel interpretar os erros SOA: " +
        $realException.Message
      )
    }
  }

  # ============================================================
  # 4. RETORNAR AS MENSAGENS ENCONTRADAS
  # ============================================================
  return @(
    $errorMessages |
      Select-Object -Unique
  )
}
