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

  # ============================================================
  # 1. VALIDAR A CONEXAO E O CAMINHO DO ARQUIVO
  # ============================================================
  #
  # A consulta do estado exige uma conexao ativa com o Vault e
  # um caminho completo para localizar o arquivo no PDM.
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

  # ============================================================
  # 2. CONSULTAR O ESTADO ATUAL NO PDM
  # ============================================================
  #
  # GetFileFromPath localiza o objeto do arquivo e preenche sua
  # pasta por referencia. O estado atual e obtido desse objeto.
  $parentFolder =
  $null

  try {

    # Localiza o arquivo pelo caminho completo informado na
    # entrada recebida pela pesquisa.
    $pdmFile =
    $script:DcaVault.GetFileFromPath(
      [string]$Entry.FullName,
      [ref]$parentFolder
    )

    if ($null -eq $pdmFile) {
      return $null
    }

    # CurrentState representa o estado atual do arquivo dentro do
    # workflow configurado no SOLIDWORKS PDM.
    $currentState =
    $pdmFile.CurrentState

    if ($null -eq $currentState) {
      return $null
    }

    return (
      [string]$currentState.Name
    ).Trim()
  }

  # Uma falha na consulta do estado nao deve interromper a
  # pesquisa dos PDFs. O documento continuara sem estado.
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

  # ============================================================
  # 1. PREPARAR A VARIAVEL SOLICITADA
  # ============================================================
  #
  # Remove espacos das extremidades antes de consultar o campo
  # correspondente no cartao de dados.
  $variableNameClean =
  $VariableName.Trim()

  # ============================================================
  # 2. LOCALIZAR A INTERFACE DE LEITURA GETVAR2
  # ============================================================
  #
  # Procura a interface IEdmEnumeratorVariable10 nos assemblies
  # carregados. Essa interface disponibiliza o metodo GetVar2.
  #
  # A descoberta em tempo de execucao preserva a compatibilidade
  # com versoes diferentes da biblioteca EdmLib.
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

    # Localiza especificamente a sobrecarga de GetVar2 que recebe
    # quatro parametros.
    $getVar2Method =
    $enumeratorVariableType.GetMethods() |
      Where-Object {
      $_.Name -eq "GetVar2" -and
      $_.GetParameters().Count -eq 4
    } |
      Select-Object -First 1

    if ($null -ne $getVar2Method) {

      # ==========================================================
      # A. PREPARAR OS ARGUMENTOS DO GETVAR2
      # ==========================================================
      #
      # O array segue a ordem esperada pelo metodo:
      #   1. nome da variavel;
      #   2. configuracao;
      #   3. identificador da pasta;
      #   4. valor retornado por referencia.

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

      # ========================================================
      # B. LER O VALOR COM GETVAR2
      # ========================================================
      #
      # Invoke atualiza o quarto elemento do array de argumentos
      # com o valor encontrado no cartao.
      try {

        $variableFound =
        [bool]$getVar2Method.Invoke(
          $VariableReader,
          $getVar2Arguments
        )

        $variableValue =
        $getVar2Arguments[3]

        # Padroniza o resultado da leitura para que o chamador
        # conheca o valor, o metodo utilizado e uma eventual falha.
        return [PSCustomObject]@{
          Found = $variableFound
          Value = ([string]$variableValue).Trim()
          Method = "GetVar2"
          Error = $null
        }
      }
      catch {

        # Chamadas realizadas por reflexao podem encapsular o erro
        # real em uma ou mais InnerException. O laco recupera a
        # causa original da falha.
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

  # ============================================================
  # 3. UTILIZAR GETVAR COMO ALTERNATIVA
  # ============================================================
  #
  # Quando GetVar2 nao estiver disponivel, utiliza GetVar para
  # manter a compatibilidade com versoes anteriores da EdmLib.
  #
  # A leitura testa a configuracao vazia e a configuracao "@",
  # utilizadas pelos cartoes de documentos sem configuracao CAD.
  $fallbackConfigurations =
  @(
    "",
    "@"
  )

  # Cada configuracao e testada ate que a variavel seja encontrada
  # ou apresente um valor preenchido.
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

  # ============================================================
  # 4. INFORMAR QUE A VARIAVEL NAO FOI ENCONTRADA
  # ============================================================
  #
  # Mantem a mesma estrutura de retorno mesmo quando GetVar2 e
  # GetVar nao localizarem um valor utilizavel.
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

  # ============================================================
  # 1. VALIDAR A CONEXAO E O ARQUIVO
  # ============================================================
  #
  # A enumeracao das variaveis exige acesso a API do PDM e um
  # caminho valido para localizar o arquivo e seu cartao.
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

  # Localiza o arquivo e recupera sua pasta por referencia. O ID
  # da pasta sera utilizado durante a leitura das variaveis.
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

  # ============================================================
  # 2. ABRIR O CARTAO DE DADOS
  # ============================================================
  #
  # O enumerador fornece acesso aos valores das variaveis
  # associadas ao arquivo atual.
  $variableReader =
  $pdmFile.GetEnumeratorVariable("")

  if ($null -eq $variableReader) {

    throw (
      "Nao foi possivel abrir o cartao de dados de " +
      "'$($Entry.Name)'."
    )
  }

  # ============================================================
  # 3. LOCALIZAR O GERENCIADOR DE VARIAVEIS
  # ============================================================
  #
  # O objeto do Vault implementa o gerenciador utilizado para
  # enumerar todas as variaveis cadastradas no PDM.
  $variableManager =
  $vault

  # A interface e localizada por reflexao para evitar dependencia
  # direta de uma versao especifica da biblioteca EdmLib.
  $variableManagerType =
  [System.AppDomain]::CurrentDomain.GetAssemblies() |
    ForEach-Object {

    # Alguns assemblies podem impedir a enumeracao de seus tipos.
    # Nesse caso, retorna uma colecao vazia e continua a pesquisa.
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

  # ============================================================
  # 4. LOCALIZAR OS METODOS DE ENUMERACAO
  # ============================================================
  #
  # GetFirstVariablePosition inicia o cursor e GetNextVariable
  # retorna a variavel correspondente a posicao atual.
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

  # ============================================================
  # 5. ENUMERAR E LER AS VARIAVEIS DO CARTAO
  # ============================================================
  #
  # Cada variavel encontrada sera adicionada a lista depois da
  # leitura de seu valor no cartao do arquivo.
  $results =
  [System.Collections.Generic.List[object]]::new()

  try {

    # Solicita a posicao inicial utilizada pelo cursor da API.
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

    # Percorre as variaveis ate que a API informe o final da
    # colecao por meio de uma posicao nula.
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

        # Algumas versoes da API sinalizam o final da lista por
        # excecao. Essas mensagens sao tratadas como encerramento
        # normal da enumeracao.
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

      # ========================================================
      # A. LER O VALOR DA VARIAVEL ATUAL
      # ========================================================
      #
      # Utiliza a funcao de compatibilidade que prioriza GetVar2
      # e utiliza GetVar quando necessario.
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

        # Uma falha devolvida pela leitura e exibida somente no
        # modo Details para nao poluir a saida normal do lote.
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

      # ========================================================
      # B. VALIDAR O VALOR ENCONTRADO
      # ========================================================
      #
      # Por padrao, variaveis vazias nao sao adicionadas. O
      # parametro -IncludeEmpty permite inclui-las no diagnostico.
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

      # O identificador e opcional porque pode nao estar exposto
      # pela versao atual do objeto retornado pela API.
      $variableId =
      $null

      if (
        $pdmVariable.PSObject.Properties["ID"]
      ) {

        $variableId =
        $pdmVariable.ID
      }

      # Registra o nome, o ID, o valor e o metodo utilizado para
      # permitir a apresentacao detalhada posteriormente.
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

    # ============================================================
    # 6. FECHAR O ENUMERADOR DO CARTAO
    # ============================================================
    #
    # O fechamento ocorre mesmo quando uma falha interrompe a
    # enumeracao das variaveis.

    if ($null -ne $variableReader) {

      # Localiza CloseFile por reflexao porque sua assinatura pode
      # variar conforme a versao da biblioteca PDM.
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

          # Algumas versoes recebem um valor booleano e outras nao
          # exigem parametros para fechar o arquivo.
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

  # ============================================================
  # 7. RETORNAR AS VARIAVEIS ORDENADAS
  # ============================================================
  #
  # A ordenacao pelo nome facilita a leitura durante o diagnostico.
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

  # ============================================================
  # 1. APRESENTAR O ARQUIVO CONSULTADO
  # ============================================================
  Write-AnimatedLine ""

  Write-Host (
    "  Consultando as variaveis do cartao de:"
  ) -ForegroundColor Cyan

  Write-Host (
    "  $($Entry.Name)"
  ) -ForegroundColor White

  # ============================================================
  # 2. CONSULTAR TODAS AS VARIAVEIS DO CARTAO
  # ============================================================
  #
  # Inclui tambem os campos vazios para permitir a identificacao
  # da variavel correta durante o diagnostico.
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

  # ============================================================
  # 3. APRESENTAR AS VARIAVEIS ENCONTRADAS
  # ============================================================
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

    # O ID sera apresentado somente quando a API disponibilizar
    # essa propriedade para a variavel atual.
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

  # ============================================================
  # 4. ORIENTAR A CONFIGURACAO
  # ============================================================
  #
  # A mensagem auxilia na identificacao do nome exato que deve
  # ser informado nas variaveis correspondentes do arquivo .env.
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

  # ============================================================
  # 1. VALIDAR A CONEXAO E O CAMINHO DO ARQUIVO
  # ============================================================
  #
  # Sem acesso ao Vault ou sem um caminho completo, o cartao nao
  # pode ser consultado e a funcao retorna NULL.
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

    # Abre o enumerador utilizado para consultar os valores das
    # variaveis configuradas.
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

    # ============================================================
    # 3. TESTAR AS VARIAVEIS CONFIGURADAS
    # ============================================================
    #
    # As variaveis sao verificadas na ordem recebida. O primeiro
    # valor encontrado e preenchido encerra a consulta.
    foreach ($variableName in $VariableNames) {

      # Remove espacos adicionais e ignora nomes vazios.
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

      # Get-DcaPdmCardVariableValue seleciona automaticamente o
      # metodo de leitura compativel com a API carregada.
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

        # Quando o campo nao existir, continua para o proximo nome
        # configurado.
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

      # ========================================================
      # A. VALIDAR O VALOR RETORNADO
      # ========================================================
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

        # O primeiro valor preenchido possui prioridade e encerra
        # a pesquisa das demais variaveis configuradas.
        return $valueText
      }

      if ($Details) {

        Write-Host (
          "  Variavel encontrada, mas vazia: '$currentName'"
        ) -ForegroundColor DarkGray
      }
    }

    # Nenhuma das variaveis configuradas apresentou um valor
    # preenchido no cartao.
    return $null
  }
  catch {

    # A falha de leitura e apresentada somente no modo Details.
    # O retorno NULL permite que o fluxo mantenha os dados obtidos
    # anteriormente pelo nome do arquivo.
    if ($Details) {

      Write-Warn (
        "Falha ao ler o cartao de dados de " +
        "'$($Entry.Name)': $($_.Exception.Message)"
      )
    }

    return $null
  }
}
