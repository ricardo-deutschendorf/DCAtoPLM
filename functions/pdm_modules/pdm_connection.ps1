# ============================================================
# CONEXAO COM O SOLIDWORKS PDM
# ============================================================
#
# Este arquivo gerencia a conexao com o Vault.
#
# Responsabilidades:
#   1. validar a biblioteca Interop.EdmLib.dll;
#   2. carregar os objetos COM do PDM;
#   3. utilizar credenciais configuradas quando disponiveis;
#   4. utilizar LoginAuto como alternativa;
#   5. reutilizar a conexao durante a mesma execucao;
#   6. permitir o uso do sistema de arquivos em caso de falha.
#
# Nenhuma pesquisa de PDF e executada diretamente neste arquivo.
# ============================================================
function Get-DcaVault {

  # ============================================================
  # 1. VERIFICAR SE A CONEXAO COM O VAULT E NECESSARIA
  # ============================================================
  #
  # A API nao sera utilizada quando o parametro -NoVaultApi
  # estiver ativo. Nesse caso, o chamador continuara utilizando
  # somente os arquivos disponiveis no sistema de arquivos.
  if ($NoVaultApi) {
    return $null
  }

  # Reutiliza a conexao autenticada anteriormente para evitar
  # novos logins durante a mesma execucao do script.
  if ($null -ne $script:DcaVault) {
    return $script:DcaVault
  }

  # Quando uma tentativa anterior tiver falhado, nao repete o
  # carregamento da biblioteca e o login durante esta execucao.
  # O retorno NULL permite que a pesquisa continue pelo disco.
  if ($script:DcaVaultTried) {
    return $null
  }

  # Registra a tentativa antes de iniciar a conexao. Assim, mesmo
  # uma excecao durante o carregamento ou login impede repeticoes.
  $script:DcaVaultTried = $true

  # O ponteiro sera utilizado somente no login com credenciais.
  # O valor inicial permite verificar com seguranca se a memoria
  # nao gerenciada precisa ser liberada no bloco finally.
  $passwordPointer = [System.IntPtr]::Zero

  try {

    # ============================================================
    # 2. VALIDAR E CARREGAR A BIBLIOTECA DO PDM
    # ============================================================
    #
    # A biblioteca Interop.EdmLib.dll deve existir antes da
    # criacao dos objetos COM utilizados para acessar o Vault.
    if (
      [string]::IsNullOrWhiteSpace(
        [string]$PdmLibraryPath
      ) -or
      $PdmLibraryPath -like "<*>" -or
      -not (
        Test-Path `
          -LiteralPath $PdmLibraryPath `
          -PathType Leaf
      )
    ) {

      throw (
        "Interop.EdmLib.dll nao encontrada em " +
        "'$PdmLibraryPath'. Verifique DCA_PDM_LIB no arquivo .env."
      )
    }

    # A biblioteca EdmLib disponibiliza os objetos COM utilizados
    # para login, pesquisa e leitura dos cartoes do PDM.
    Add-Type -Path $PdmLibraryPath

    # Cria o objeto principal da API utilizado para autenticar e
    # acessar os arquivos e pastas do Vault.
    $vault = New-Object EdmLib.EdmVault5Class

    # Carrega os tipos da biblioteca EdmLib no processo atual.
    # Esses tipos disponibilizam os objetos COM utilizados para
    # login, pesquisa e leitura dos cartoes do PDM.
    $hasCredentialFile =
    -not [string]::IsNullOrWhiteSpace(
      [string]$VaultCredentialPath
    ) -and
    $VaultCredentialPath -notlike "<*>" -and
    (
      Test-Path `
        -LiteralPath $VaultCredentialPath `
        -PathType Leaf
    )

    # ============================================================
    # 4. AUTENTICAR COM CREDENCIAIS CONFIGURADAS
    # ============================================================
    #
    # O arquivo pode armazenar diretamente um PSCredential ou uma
    # estrutura com Usuario e SenhaCriptografada.
    if ($hasCredentialFile) {

      # Import-Clixml recupera a estrutura protegida anteriormente
      # no contexto do usuario e da maquina correspondentes.
      $credential = Import-Clixml -LiteralPath $VaultCredentialPath

      if ($null -eq $credential) {
        throw "O arquivo de credencial do vault nao pode ser lido."
      }

      # ==========================================================
      # A. INTERPRETAR O FORMATO DA CREDENCIAL
      # ==========================================================
      #
      # Inicializa os valores antes de identificar qual estrutura
      # foi armazenada no arquivo.
      $credentialUser = $null
      $securePassword = $null

      # PSCredential fornece diretamente o nome do usuario e a
      # senha protegida como SecureString.
      if ($credential -is [System.Management.Automation.PSCredential]) {
        $credentialUser = $credential.UserName
        $securePassword = $credential.Password
      }

      # O formato alternativo utiliza as propriedades Usuario e
      # SenhaCriptografada e converte a senha para SecureString.
      elseif (
        $credential.PSObject.Properties["Usuario"] -and
        $credential.PSObject.Properties["SenhaCriptografada"]
      ) {
        $credentialUser = [string]$credential.Usuario
        $securePassword = $credential.SenhaCriptografada | ConvertTo-SecureString
      }
      else {
        throw (
          "O arquivo de credencial do vault deve ser um PSCredential " +
          "ou conter as propriedades Usuario e SenhaCriptografada."
        )
      }

      # ==========================================================
      # B. VALIDAR O USUARIO E A SENHA
      # ==========================================================
      #
      # O login nao sera iniciado quando algum dos valores
      # obrigatorios nao tiver sido recuperado do arquivo.
      if (
        [string]::IsNullOrWhiteSpace(
          [string]$credentialUser
        )
      ) {

        throw (
          "O usuario do Vault nao foi encontrado no arquivo " +
          "de credenciais."
        )
      }

      if ($null -eq $securePassword) {

        throw (
          "A senha do Vault nao foi encontrada no arquivo " +
          "de credenciais."
        )
      }

      # ==========================================================
      # C. REALIZAR O LOGIN COM CREDENCIAIS
      # ==========================================================
      #
      # O metodo Login da API exige a senha em texto. Por isso, a
      # SecureString e convertida temporariamente para uma area de
      # memoria nao gerenciada, removida posteriormente no finally.
      $passwordPointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePassword)

      # Recupera o texto somente durante a chamada de autenticacao.
      # A variavel sera removida ao final da tentativa de conexao.
      $plainTextPassword = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($passwordPointer)

      # Autentica no Vault configurado utilizando o usuario e a
      # senha recuperados do arquivo de credenciais.
      $vault.Login($credentialUser, $plainTextPassword, $VaultName)
    }
    else {

      # ==========================================================
      # D. UTILIZAR A AUTENTICACAO AUTOMATICA
      # ==========================================================
      #
      # Quando nenhuma credencial valida estiver disponivel, tenta
      # reutilizar a sessao do PDM associada ao usuario do Windows.
      # Apresenta o aviso somente quando um caminho real tiver sido
      # configurado, mas o arquivo correspondente nao for encontrado.
      if (
        -not [string]::IsNullOrWhiteSpace($VaultCredentialPath) -and
        $VaultCredentialPath -notlike "<*>" -and
        -not (Test-Path -LiteralPath $VaultCredentialPath -PathType Leaf)
      ) {
        Write-Warn (
          "Arquivo de credencial do vault nao encontrado em " +
          "'$VaultCredentialPath'. Tentando LoginAuto."
        )
      }

      # Solicita a conexao utilizando a autenticacao ja estabelecida
      # para o usuario atual no cliente do SOLIDWORKS PDM.
      $vault.LoginAuto($VaultName, 0)
    }

    # ============================================================
    # 5. VALIDAR E ARMAZENAR A CONEXAO
    # ============================================================
    #
    # Confirma que a API considera a sessao autenticada antes de
    # disponibilizar o objeto do Vault para as demais funcoes.
    if (-not $vault.IsLoggedIn) {
      throw "Nao foi possivel autenticar no vault '$VaultName'."
    }

    # Mantem a conexao no estado compartilhado do script para que
    # as proximas consultas reutilizem a mesma sessao.
    $script:DcaVault = $vault

    return $vault
  }

  # ============================================================
  # 6. PERMITIR A CONTINUIDADE SEM A API
  # ============================================================
  #
  # Uma falha de biblioteca ou autenticacao nao encerra o fluxo.
  # O retorno NULL informa ao chamador que a pesquisa deve usar
  # somente os arquivos disponiveis no sistema de arquivos.
  catch {

    Write-Warn (
      "Falha no login do vault '$VaultName': $($_.Exception.Message) " +
      "Usando apenas o sistema de arquivos. Verifique o nome do vault, " +
      "o login do PDM e DCA_VAULT_CREDENTIAL."
    )

    return $null
  }
  finally {

    # ============================================================
    # 7. LIMPAR OS DADOS TEMPORARIOS DA AUTENTICACAO
    # ============================================================
    # Remove da memoria nao gerenciada a representacao temporaria
    # da senha utilizada pelo metodo Login.
    if ($passwordPointer -ne [System.IntPtr]::Zero) {
      [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($passwordPointer)
    }

    # Remove tambem a variavel que armazenou temporariamente a
    # representacao textual da senha durante o login.
    Remove-Variable plainTextPassword -ErrorAction SilentlyContinue
  }
}
