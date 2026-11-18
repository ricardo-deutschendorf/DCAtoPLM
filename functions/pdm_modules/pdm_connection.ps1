# ============================================================
# CONEXAO COM O SOLIDWORKS PDM
# ============================================================
#   1. valida e carrega a biblioteca Interop.EdmLib.dll;
#   2. autentica com credencial configurada ou LoginAuto;
#   3. reutiliza a conexao durante a execucao;
#   4. em caso de falha, devolve $null e o fluxo segue pelo disco.
# Nenhuma pesquisa de PDF e executada aqui.
# ============================================================

function Get-DcaVault {
    # Sem API (-NoVaultApi): o chamador usa somente o sistema de arquivos.
    if ($NoVaultApi) { return $null }

    # Reutiliza a sessao ja autenticada.
    if ($null -ne $script:DcaVault) { return $script:DcaVault }

    # Uma tentativa anterior falhou: nao repete biblioteca nem login.
    if ($script:DcaVaultTried) { return $null }
    $script:DcaVaultTried = $true

    $vaultNameClean      = ([string]$VaultName).Trim()
    $pdmLibraryPath      = ([string]$PdmLibraryPath).Trim()
    $credentialPath      = ([string]$VaultCredentialPath).Trim()

    if (-not $vaultNameClean) {
        Write-Warn "DCA_VAULT_NAME nao foi configurado. Usando somente o sistema de arquivos."
        return $null
    }

    # Valores no formato <...> sao placeholders do .env, nao caminhos reais.
    $credentialConfigured = $credentialPath -and $credentialPath -notlike "<*>"
    $hasCredentialFile    = $credentialConfigured -and (Test-Path -LiteralPath $credentialPath -PathType Leaf)

    $passwordPointer = [System.IntPtr]::Zero

    try {
        # --- 1. Biblioteca do PDM ---
        if (-not $pdmLibraryPath -or $pdmLibraryPath -like "<*>" -or -not (Test-Path -LiteralPath $pdmLibraryPath -PathType Leaf)) {
            throw "Interop.EdmLib.dll nao encontrada em '$pdmLibraryPath'. Verifique DCA_PDM_LIB no arquivo .env."
        }
        Add-Type -Path $pdmLibraryPath -ErrorAction Stop
        $vault = New-Object EdmLib.EdmVault5Class

        # --- 2. Autenticacao ---
        if ($hasCredentialFile) {
            # Aceita PSCredential ou um objeto com Usuario e SenhaCriptografada.
            $credential = Import-Clixml -LiteralPath $credentialPath -ErrorAction Stop
            if ($null -eq $credential) { throw "O arquivo de credencial do vault nao pode ser lido." }

            if ($credential -is [System.Management.Automation.PSCredential]) {
                $user = $credential.UserName
                $securePassword = $credential.Password
            }
            elseif ($credential.PSObject.Properties["Usuario"] -and $credential.PSObject.Properties["SenhaCriptografada"]) {
                $user = [string]$credential.Usuario
                $securePassword = $credential.SenhaCriptografada | ConvertTo-SecureString
            }
            else {
                throw (
                    "O arquivo de credencial do vault deve ser um PSCredential " +
                    "ou conter as propriedades Usuario e SenhaCriptografada."
                )
            }

            if ([string]::IsNullOrWhiteSpace([string]$user)) { throw "O usuario do Vault nao foi encontrado no arquivo de credenciais." }
            if ($null -eq $securePassword) { throw "A senha do Vault nao foi encontrada no arquivo de credenciais." }
            if ($securePassword -isnot [System.Security.SecureString]) {
                throw "A senha recuperada do arquivo de credenciais nao e uma SecureString valida."
            }

            # O Login exige texto puro: a senha existe so durante a chamada e e liberada no finally.
            $passwordPointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePassword)
            $plainTextPassword = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($passwordPointer)
            $vault.Login($user, $plainTextPassword, $vaultNameClean)
            $plainTextPassword = $null
        }
        else {
            # Avisa so quando um caminho real foi configurado e o arquivo nao existe.
            if ($credentialConfigured) {
                Write-Warn "Arquivo de credencial do vault nao encontrado em '$credentialPath'. Tentando LoginAuto."
            }
            $vault.LoginAuto($vaultNameClean, 0)
        }

        # --- 3. Validar e guardar a conexao ---
        if (-not $vault.IsLoggedIn) { throw "Nao foi possivel autenticar no vault '$vaultNameClean'." }

        $script:DcaVault = $vault
        return $vault
    }
    catch {
        # Falha de biblioteca ou login nao encerra o fluxo: a pesquisa continua pelo disco.
        Write-Warn (
            "Falha no login do vault '$vaultNameClean': $($_.Exception.GetBaseException().Message) " +
            "Usando apenas o sistema de arquivos. " +
            "Verifique o nome do vault, o login do PDM e DCA_VAULT_CREDENTIAL."
        )
        return $null
    }
    finally {
        # Apaga e libera a memoria nao gerenciada da senha.
        if ($passwordPointer -ne [System.IntPtr]::Zero) {
            [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($passwordPointer)
        }
        $plainTextPassword = $null
    }
}