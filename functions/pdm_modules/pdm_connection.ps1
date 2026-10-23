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

  # Retorna uma conexao reutilizavel com o Vault.
  # Quando a API estiver desativada ou o login falhar, retorna NULL
  # para permitir que a pesquisa continue pelo sistema de arquivos.
  if ($NoVaultApi) {
    return $null
  }

  if ($null -ne $script:DcaVault) {
    return $script:DcaVault
  }

  # Evita repetir uma tentativa de login que ja falhou durante
  # a mesma execucao do script.
  if ($script:DcaVaultTried) {
    return $null
  }

  $script:DcaVaultTried = $true
  $passwordPointer = [System.IntPtr]::Zero

  try {

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

    $vault = New-Object EdmLib.EdmVault5Class

    # O arquivo de credenciais e opcional. Sem ele, o script utiliza
    # a sessao do usuario autenticado no Windows por meio de LoginAuto.
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

    if ($hasCredentialFile) {

      $credential = Import-Clixml -LiteralPath $VaultCredentialPath

      if ($null -eq $credential) {
        throw "O arquivo de credencial do vault nao pode ser lido."
      }

      $credentialUser = $null
      $securePassword = $null

      if ($credential -is [System.Management.Automation.PSCredential]) {
        $credentialUser = $credential.UserName
        $securePassword = $credential.Password
      }
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

      $passwordPointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePassword)

      $plainTextPassword = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($passwordPointer)

      $vault.Login($credentialUser, $plainTextPassword, $VaultName)
    }
    else {

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

      $vault.LoginAuto($VaultName, 0)
    }

    if (-not $vault.IsLoggedIn) {
      throw "Nao foi possivel autenticar no vault '$VaultName'."
    }

    $script:DcaVault = $vault

    return $vault
  }
  catch {

    Write-Warn (
      "Falha no login do vault '$VaultName': $($_.Exception.Message) " +
      "Usando apenas o sistema de arquivos. Verifique o nome do vault, " +
      "o login do PDM e DCA_VAULT_CREDENTIAL."
    )

    return $null
  }
  finally {

    # Remove da memoria nao gerenciada a representacao temporaria
    # da senha utilizada pelo metodo Login.
    if ($passwordPointer -ne [System.IntPtr]::Zero) {
      [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($passwordPointer)
    }

    Remove-Variable plainTextPassword -ErrorAction SilentlyContinue
  }
}