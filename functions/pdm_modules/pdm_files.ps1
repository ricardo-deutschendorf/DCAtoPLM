# ============================================================
# PESQUISA E DISPONIBILIZACAO DOS PDFS
# ============================================================
#
# Este arquivo localiza e disponibiliza os PDFs utilizados pelo
# lote de importacao.
#
# Responsabilidades:
#   1. pesquisar PDFs pelo indice do Vault;
#   2. pesquisar PDFs no sistema de arquivos;
#   3. limitar pesquisas a uma pasta quando solicitado;
#   4. solicitar uma copia local para arquivos do Vault;
#   5. validar o caminho local antes da importacao.
#
# A pesquisa pelo Vault possui prioridade. A pesquisa em disco
# permanece disponivel como alternativa.
# ============================================================

# ============================================================
# PESQUISA DE PDFS PELO INDICE DO VAULT
# ============================================================
function Search-DcaVaultPdfEntries {

  # Pesquisa PDFs no indice do Vault e desenhos SLDDRW localizados
  # especificamente dentro de pastas chamadas Folhas NDT.
  #
  # Quando StartFolderPath estiver preenchido, a pesquisa sera
  # iniciada nessa pasta. Dependendo da versao da EdmLib, a API
  # pode incluir resultados localizados em subpastas.
  param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNull()]
    $Vault,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$SearchText,

    [string]$StartFolderPath
  )

  # ============================================================
  # 1. NORMALIZAR O TEXTO DA PESQUISA
  # ============================================================

  $searchTextClean =
  $SearchText.Trim()

  if (
    [string]::IsNullOrWhiteSpace(
      $searchTextClean
    )
  ) {

    throw (
      "O texto da pesquisa no Vault ficou vazio."
    )
  }

  # A API do PDM utiliza os curingas SQL:
  #
  #   % = zero ou mais caracteres;
  #   _ = exatamente um caractere.
  #
  # O fluxo do DCAtoPLM utiliza:
  #
  #   * = zero ou mais caracteres;
  #   ? = exatamente um caractere.
  $likePattern =
  $searchTextClean.Replace(
    "*",
    "%"
  ).Replace(
  "?",
  "_"
)

# Quando nenhum curinga for informado, realiza uma pesquisa
# parcial pelo texto recebido.
if ($likePattern -notmatch "[%_]") {

  $likePattern =
  "%$likePattern%"
}

# ============================================================
# 2. CRIAR O OBJETO DE PESQUISA
# ============================================================

$search =
$Vault.CreateSearch()

if ($null -eq $search) {

  throw (
    "A API do PDM nao retornou um objeto de pesquisa."
  )
}

$search.FileName =
$likePattern

# Impede que versoes historicas dos arquivos sejam retornadas.
$search.FindHistoricStates =
$false

# ============================================================
# 3. LIMITAR A PESQUISA A UMA PASTA
# ============================================================

$startFolderPathClean =
([string]$StartFolderPath).Trim()

if (
  -not [string]::IsNullOrWhiteSpace(
    $startFolderPathClean
  )
) {

  $startFolder =
  $Vault.GetFolderFromPath(
    $startFolderPathClean
  )

  if ($null -eq $startFolder) {

    throw (
      "A pasta nao foi encontrada pela API do PDM: " +
      "'$startFolderPathClean'."
    )
  }

  $search.StartFolderID =
  [int]$startFolder.ID
}

# ============================================================
# 4. COLETAR OS RESULTADOS
# ============================================================

$entries =
[System.Collections.Generic.List[object]]::new()

$currentResult =
$search.GetFirstResult()

while ($null -ne $currentResult) {

  $resultName =
  ([string]$currentResult.Name).Trim()

  $resultFullName =
  ([string]$currentResult.Path).Trim()

  $resultExtension =
  [System.IO.Path]::GetExtension(
    $resultName
  )

  $isPdf =
  $resultExtension -ieq ".pdf"

  $isSolidWorksDrawing =
  $resultExtension -ieq ".slddrw"

  $isInsideNdtFolder =
  $false

  if (-not (
      [string]::IsNullOrWhiteSpace(
        $resultFullName
      )
    )) {

    $resultPathParts =
    @(
      $resultFullName -split '[\\/]'
    )

    $isInsideNdtFolder =
    @(
      $resultPathParts |
        Where-Object {
        ([string]$_).Trim() -ieq "Folhas NDT"
      }
    ).Count -gt 0
  }

  $isAllowedResult =
  (
    $isPdf -or
    (
      $isSolidWorksDrawing -and
      $isInsideNdtFolder
    )
  )

  if (
    $isAllowedResult -and
    -not [string]::IsNullOrWhiteSpace(
      $resultFullName
    )
  ) {

    $baseName =
    [System.IO.Path]::GetFileNameWithoutExtension(
      $resultName
    )

    $entryDocumentType =
    if ($isSolidWorksDrawing) {
      "NDT"
    }
    else {
      $null
    }

    $entryDisplayName =
    if ($isSolidWorksDrawing) {
      "GD5_DCA_NDT"
    }
    else {
      $null
    }

    $entries.Add(
      [PSCustomObject]@{
        Name = $resultName
        BaseName = ([string]$baseName).Trim()
        FullName = $resultFullName
        Extension = $resultExtension
        DocumentType = $entryDocumentType
        TypeDisplayName = $entryDisplayName
        IsNdt = [bool]$isSolidWorksDrawing
        FromVault = $true
      }
    )
  }
  elseif (
    $isAllowedResult -and
    $Details
  ) {

    Write-Host (
      "  Resultado do Vault ignorado por nao possuir caminho: " +
      "'$resultName'."
    ) -ForegroundColor DarkGray
  }

  $currentResult =
  $search.GetNextResult()
}

# ============================================================
# 5. RETORNAR OS PDFS ENCONTRADOS
# ============================================================

return $entries.ToArray()
}

# ============================================================
# PESQUISA DE PDFS NO SISTEMA DE ARQUIVOS
# ============================================================
function Get-DcaDiskPdfEntries {

  # Pesquisa recursivamente os PDFs existentes no sistema de
  # arquivos.
  #
  # Esta funcao e utilizada quando a API do PDM estiver
  # indisponivel ou quando o chamador escolher o modo local.
  param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$FolderPath
  )

  # ============================================================
  # 1. NORMALIZAR E VALIDAR A PASTA
  # ============================================================

  $folderPathClean =
  $FolderPath.Trim()

  if (
    [string]::IsNullOrWhiteSpace(
      $folderPathClean
    )
  ) {

    throw (
      "O caminho da pesquisa local ficou vazio."
    )
  }

  if (-not (
      Test-Path `
        -LiteralPath $folderPathClean `
        -PathType Container
    )) {

    throw (
      "A pasta de pesquisa local nao foi encontrada: " +
      "'$folderPathClean'."
    )
  }

  # ============================================================
  # 2. COLETAR OS PDFS DISPONIVEIS NO DISCO
  # ============================================================

  $entries =
  [System.Collections.Generic.List[object]]::new()

  # A pesquisa e recursiva porque esta funcao tambem e utilizada
  # pela pesquisa geral por codigo.
  #
  # A leitura somente da pasta atual e realizada pelo modulo
  # especifico de navegacao por pastas.
  $pdfFiles =
  @(
    Get-ChildItem `
      -LiteralPath $folderPathClean `
      -Filter "*.pdf" `
      -File `
      -Recurse `
      -Force `
      -ErrorAction SilentlyContinue |
      Sort-Object FullName
  )

  foreach ($pdfFile in $pdfFiles) {

    if ($null -eq $pdfFile) {
      continue
    }

    $pdfFullName =
    ([string]$pdfFile.FullName).Trim()

    if (
      [string]::IsNullOrWhiteSpace(
        $pdfFullName
      )
    ) {

      continue
    }

    $baseName =
    [System.IO.Path]::GetFileNameWithoutExtension(
      $pdfFile.Name
    )

    # Mantem a mesma estrutura utilizada pelos resultados da API.
    $entries.Add(
      [PSCustomObject]@{
        Name = [string]$pdfFile.Name
        BaseName = ([string]$baseName).Trim()
        FullName = $pdfFullName
        FromVault = $false
      }
    )
  }

  # ============================================================
  # 3. RETORNAR OS PDFS ENCONTRADOS
  # ============================================================

  return $entries.ToArray()
}

# ============================================================
# DISPONIBILIZACAO LOCAL DO PDF
# ============================================================
function Confirm-DcaLocalPdf {

  # Garante que o PDF esteja disponivel localmente.
  #
  # Quando o arquivo ja existir no cache ou no disco, retorna seu
  # caminho imediatamente.
  #
  # Quando o resultado veio do Vault e ainda nao estiver
  # disponivel localmente, solicita uma copia ao PDM.
  param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNull()]
    $Entry
  )

  # ============================================================
  # 1. VALIDAR A ENTRADA
  # ============================================================

  $entryPath =
  ([string]$Entry.FullName).Trim()

  if (
    [string]::IsNullOrWhiteSpace(
      $entryPath
    )
  ) {

    throw (
      "A entrada do PDF nao possui um caminho completo."
    )
  }

  if (
    [System.IO.Path]::GetExtension(
      $entryPath
    ) -ine ".pdf"
  ) {

    throw (
      "O arquivo informado nao possui extensao PDF: " +
      "'$entryPath'."
    )
  }

  # ============================================================
  # 2. RETORNAR O ARQUIVO JA DISPONIVEL
  # ============================================================

  if (
    Test-Path `
      -LiteralPath $entryPath `
      -PathType Leaf
  ) {

    $localFile =
    Get-Item `
      -LiteralPath $entryPath `
      -ErrorAction Stop

    if ($localFile.Length -le 0) {

      throw (
        "O PDF encontrado no disco esta vazio: " +
        "'$entryPath'."
      )
    }

    return $localFile.FullName
  }

  # ============================================================
  # 3. VALIDAR A ORIGEM DO ARQUIVO
  # ============================================================

  $vault =
  $script:DcaVault

  $entryFromVault =
  $false

  if ($Entry.PSObject.Properties["FromVault"]) {

    $entryFromVault =
    [bool]$Entry.FromVault
  }

  if (
    -not $entryFromVault -or
    $null -eq $vault
  ) {

    throw (
      "PDF nao encontrado no disco: '$entryPath'."
    )
  }

  # ============================================================
  # 4. LOCALIZAR O ARQUIVO NO VAULT
  # ============================================================

  Write-Info (
    "Baixando o PDF do vault..."
  )

  [object]$parentFolder =
  $null

  $pdmFile =
  $vault.GetFileFromPath(
    $entryPath,
    [ref]$parentFolder
  )

  if ($null -eq $pdmFile) {

    throw (
      "Nao foi possivel obter o arquivo no vault: " +
      "'$entryPath'."
    )
  }

  if ($null -eq $parentFolder) {

    throw (
      "Nao foi possivel obter a pasta do arquivo no vault: " +
      "'$entryPath'."
    )
  }

  # ============================================================
  # 5. SOLICITAR UMA COPIA LOCAL
  # ============================================================

  [object]$fileVersion =
  [int]0

  [object]$folderId =
  [int]$parentFolder.ID

  if ($Details) {

    Write-Host (
      "  Preparando download pelo PDM:"
    ) -ForegroundColor Cyan

    Write-Host (
      "    Arquivo:     '$entryPath'"
    ) -ForegroundColor DarkGray

    Write-Host (
      "    Pasta ID:    '$folderId'"
    ) -ForegroundColor DarkGray

    Write-Host (
      "    Versao:      '$fileVersion'"
    ) -ForegroundColor DarkGray

    Write-Host (
      "    Tipo arquivo: " +
      $pdmFile.GetType().FullName
    ) -ForegroundColor DarkGray

    Write-Host (
      "    Tipo pasta:   " +
      $parentFolder.GetType().FullName
    ) -ForegroundColor DarkGray
  }

  try {

    # ==========================================================
    # LOCALIZAR DINAMICAMENTE A INTERFACE IEDMFILE5
    # ==========================================================
    #
    # O namespace da biblioteca de interoperabilidade pode variar
    # entre instalacoes do SOLIDWORKS PDM. Por isso, a interface
    # e procurada pelo nome entre os assemblies ja carregados.

    $edmFile5Type =
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
      $_.Name -eq "IEdmFile5"
    } |
      Select-Object -First 1

    # Se a biblioteca ainda nao estiver carregada, tenta carregar
    # explicitamente o caminho configurado no .env.
    if (
      $null -eq $edmFile5Type -and
      -not [string]::IsNullOrWhiteSpace(
        [string]$env:DCA_PDM_LIB
      ) -and
      (
        Test-Path `
          -LiteralPath $env:DCA_PDM_LIB `
          -PathType Leaf
      )
    ) {

      $pdmInteropAssembly =
      [System.Reflection.Assembly]::LoadFrom(
        $env:DCA_PDM_LIB
      )

      if ($null -ne $pdmInteropAssembly) {

        $edmFile5Type =
        $pdmInteropAssembly.GetTypes() |
          Where-Object {
          $_.IsInterface -and
          $_.Name -eq "IEdmFile5"
        } |
          Select-Object -First 1
      }
    }

    if ($null -eq $edmFile5Type) {

      $loadedAssemblyNames =
      @(
        [System.AppDomain]::CurrentDomain.GetAssemblies() |
          ForEach-Object {
          $_.GetName().Name
        } |
          Sort-Object -Unique
      )

      throw (
        "A interface IEdmFile5 nao foi encontrada nas " +
        "bibliotecas carregadas. DCA_PDM_LIB: " +
        "'$([string]$env:DCA_PDM_LIB)'. " +
        "Assemblies carregados: " +
        ($loadedAssemblyNames -join ", ")
      )
    }

    if ($Details) {

      Write-Host (
        "  Interface IEdmFile5 localizada:"
      ) -ForegroundColor Cyan

      Write-Host (
        "    Nome completo: " +
        $edmFile5Type.FullName
      ) -ForegroundColor DarkGray

      Write-Host (
        "    Assembly:      " +
        $edmFile5Type.Assembly.GetName().Name
      ) -ForegroundColor DarkGray
    }

       # ==========================================================
    # LOCALIZAR GETFILECOPY NA INTERFACE IEDMFILE5
    # ==========================================================
    #
    # Nao utiliza Marshal.CreateWrapperOfType porque IEdmFile5
    # e uma interface COM, e nao uma coclass derivada de
    # System.__ComObject.
    #
    # A chamada e realizada pelo MethodInfo da interface, usando
    # diretamente o objeto COM retornado pelo Vault.

    $getFileCopyMethod =
    $edmFile5Type.GetMethods() |
      Where-Object {
        $_.Name -eq "GetFileCopy" -and
        $_.GetParameters().Count -eq 5
      } |
      Select-Object -First 1

    if ($null -eq $getFileCopyMethod) {

      throw (
        "O metodo GetFileCopy com 5 parametros nao foi " +
        "encontrado em '$($edmFile5Type.FullName)'."
      )
    }

    $getFileCopyParameters =
    $getFileCopyMethod.GetParameters()

    if ($Details) {

      Write-Host (
        "  Assinatura de GetFileCopy:"
      ) -ForegroundColor Cyan

      for (
        $parameterIndex = 0
        $parameterIndex -lt $getFileCopyParameters.Count
        $parameterIndex++
      ) {

        $currentParameter =
        $getFileCopyParameters[$parameterIndex]

        Write-Host (
          "    [{0}] {1} {2} | ByRef: {3}" -f
          $parameterIndex,
          $currentParameter.ParameterType.FullName,
          $currentParameter.Name,
          $currentParameter.ParameterType.IsByRef
        ) -ForegroundColor DarkGray
      }
    }

    # ==========================================================
    # PREPARAR OS ARGUMENTOS DA CHAMADA
    # ==========================================================
    #
    # Os valores localizados nas posicoes 1 e 2 sao atualizados
    # pelo MethodInfo.Invoke quando os parametros forem ByRef.

    [object]$versionArgument =
    [int]0

    [object]$folderArgument =
    [int]$parentFolder.ID

    $getFileCopyArguments =
    [object[]]::new(5)

    $getFileCopyArguments[0] =
    [int]0

    $getFileCopyArguments[1] =
    $versionArgument

    $getFileCopyArguments[2] =
    $folderArgument

    $getFileCopyArguments[3] =
    [int]0

    $getFileCopyArguments[4] =
    [string]""

    if ($Details) {

      Write-Host (
        "  Executando GetFileCopy por reflexao:"
      ) -ForegroundColor Cyan

      Write-Host (
        "    Versao solicitada: '$versionArgument'"
      ) -ForegroundColor DarkGray

      Write-Host (
        "    Pasta solicitada:  '$folderArgument'"
      ) -ForegroundColor DarkGray
    }

    $unknownPointer =
    [System.IntPtr]::Zero

    $typedPdmFile =
    $null

    try {

      # Obtem o ponteiro IUnknown do objeto COM retornado pelo
      # Vault e cria uma referencia tipada como IEdmFile5.
      $unknownPointer =
      [System.Runtime.InteropServices.Marshal]::GetIUnknownForObject(
        $pdmFile
      )

      if ($unknownPointer -eq [System.IntPtr]::Zero) {

        throw (
          "GetIUnknownForObject retornou um ponteiro vazio para " +
          "'$entryPath'."
        )
      }

      $typedPdmFile =
      [System.Runtime.InteropServices.Marshal]::GetTypedObjectForIUnknown(
        $unknownPointer,
        $edmFile5Type
      )

      if ($null -eq $typedPdmFile) {

        throw (
          "GetTypedObjectForIUnknown nao retornou uma referencia " +
          "IEdmFile5 para '$entryPath'."
        )
      }

      if ($Details) {

        Write-Host (
          "  Referencia COM tipada criada:"
        ) -ForegroundColor Cyan

        Write-Host (
          "    Interface: '$($edmFile5Type.FullName)'"
        ) -ForegroundColor DarkGray

        Write-Host (
          "    Tipo RCW:  '$($typedPdmFile.GetType().FullName)'"
        ) -ForegroundColor DarkGray
      }

      $null =
      $getFileCopyMethod.Invoke(
        $typedPdmFile,
        $getFileCopyArguments
      )
    }
    finally {

      # Libera somente a referencia adicional obtida acima.
      # Nao utiliza FinalReleaseComObject porque $pdmFile ainda
      # pertence ao fluxo atual e sera usado por GetLocalPath.
      if ($unknownPointer -ne [System.IntPtr]::Zero) {

        $null =
        [System.Runtime.InteropServices.Marshal]::Release(
          $unknownPointer
        )
      }
    }

    # Os elementos do array recebem os valores atualizados para
    # parametros ref/out depois da invocacao por reflexao.
    $versionArgument =
    $getFileCopyArguments[1]

    $folderArgument =
    $getFileCopyArguments[2]

    $fileVersion =
    $versionArgument

    $folderId =
    $folderArgument

    if ($Details) {

      Write-Host (
        "  Solicitacao de copia enviada ao PDM."
      ) -ForegroundColor Green

      Write-Host (
        "    Versao retornada: '$fileVersion'"
      ) -ForegroundColor DarkGray

      Write-Host (
        "    Pasta retornada:  '$folderId'"
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
      "Nao foi possivel disponibilizar o PDF no cache local. " +
      "Arquivo: '$entryPath'. " +
      "FileVersion: '$fileVersion'. " +
      "FolderID: '$folderId'. " +
      "Detalhe: " +
      $realException.Message
    )
  }

  # ============================================================
  # 6. VALIDAR O ARQUIVO DISPONIBILIZADO
  # ============================================================

  # GetLocalPath tambem pertence a IEdmFile5 e pode nao aparecer
  # diretamente no System.__ComObject retornado pelo Vault.
  $getLocalPathMethod =
  $edmFile5Type.GetMethods() |
    Where-Object {
      $_.Name -eq "GetLocalPath" -and
      $_.GetParameters().Count -eq 1
    } |
    Select-Object -First 1

  if ($null -eq $getLocalPathMethod) {

    throw (
      "O metodo GetLocalPath com 1 parametro nao foi encontrado " +
      "em '$($edmFile5Type.FullName)'."
    )
  }

  if ($null -eq $typedPdmFile) {

    throw (
      "A referencia COM tipada ficou NULL antes de GetLocalPath."
    )
  }

  $getLocalPathArguments =
  [object[]]::new(1)

  $getLocalPathArguments[0] =
  [int]$parentFolder.ID

  if ($Details) {

    Write-Host (
      "  Executando GetLocalPath por reflexao:"
    ) -ForegroundColor Cyan

    Write-Host (
      "    Interface: '$($edmFile5Type.FullName)'"
    ) -ForegroundColor DarkGray

    Write-Host (
      "    Pasta ID:  '$($parentFolder.ID)'"
    ) -ForegroundColor DarkGray
  }

  try {

    $localCachePath =
    [string]$getLocalPathMethod.Invoke(
      $typedPdmFile,
      $getLocalPathArguments
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
      "Nao foi possivel obter o caminho local do PDF. " +
      "Arquivo: '$entryPath'. " +
      "FolderID: '$($parentFolder.ID)'. " +
      "Detalhe: " +
      $realException.Message
    )
  }

  if ($Details) {

    Write-Host (
      "  Caminho retornado por GetLocalPath:"
    ) -ForegroundColor Green

    Write-Host (
      "    '$localCachePath'"
    ) -ForegroundColor DarkGray
  }

  $localCachePath =
  $localCachePath.Trim()

  if (
    [string]::IsNullOrWhiteSpace(
      $localCachePath
    )
  ) {

    throw (
      "O Vault nao retornou o caminho do cache local para " +
      "'$entryPath'."
    )
  }

  if (-not (
      Test-Path `
        -LiteralPath $localCachePath `
        -PathType Leaf
    )) {

    throw (
      "O arquivo nao foi encontrado no cache local do PDM: " +
      "'$localCachePath'."
    )
  }

  if (
    [System.IO.Path]::GetExtension(
      $localCachePath
    ) -ine ".pdf"
  ) {

    throw (
      "O arquivo retornado pelo cache do PDM nao e um PDF: " +
      "'$localCachePath'."
    )
  }

  $localCacheFile =
  Get-Item `
    -LiteralPath $localCachePath `
    -ErrorAction Stop

  if ($localCacheFile.Length -le 0) {

    throw (
      "O PDF disponibilizado no cache do PDM esta vazio: " +
      "'$localCachePath'."
    )
  }

  # ============================================================
  # 7. RETORNAR O CAMINHO LOCAL VALIDADO
  # ============================================================

  return $localCacheFile.FullName

}
