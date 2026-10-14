function Get-DcaVault {
  if ($NoVaultApi) {
    return $null
  }

  if ($null -ne $script:DcaVault) {
    return $script:DcaVault
  }

  if ($script:DcaVaultTried) {
    return $null
  }

  $script:DcaVaultTried = $true
  $passwordPointer = [System.IntPtr]::Zero

  try {

    if (
      [string]::IsNullOrWhiteSpace($PdmLibraryPath) -or
      $PdmLibraryPath -like "<*>" -or
      -not (Test-Path -LiteralPath $PdmLibraryPath -PathType Leaf)
    ) {
      throw (
        "Interop.EdmLib.dll nao encontrada em '$PdmLibraryPath'. " +
        "Informe -PdmLibraryPath (mesmo valor de `$pdmLibraryPath do PDMtoPLM)."
      )
    }

    Add-Type -Path $PdmLibraryPath

    $vault = New-Object EdmLib.EdmVault5Class

    $hasCredentialFile = -not [string]::IsNullOrWhiteSpace($VaultCredentialPath) -and
    $VaultCredentialPath -notlike "<*>" -and
    (Test-Path -LiteralPath $VaultCredentialPath -PathType Leaf)

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

      if ([string]::IsNullOrWhiteSpace($credentialUser)) {
        throw "O usuario do vault nao foi encontrado no arquivo de credencial."
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

    if ($passwordPointer -ne [System.IntPtr]::Zero) {
      [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($passwordPointer)
    }

    Remove-Variable plainTextPassword -ErrorAction SilentlyContinue
  }
}
function Search-DcaVaultPdfEntries {

  param(
    [Parameter(Mandatory = $true)]
    $Vault,

    [Parameter(Mandatory = $true)]
    [string]$SearchText
  )

  $likePattern = $SearchText.Replace("*", "%").Replace("?", "_")

  if ($likePattern -notmatch "[%_]") {
    $likePattern = "%$likePattern%"
  }

  $search = $Vault.CreateSearch()
  $search.FileName = $likePattern
  $search.FindHistoricStates = $false

  $entries = [System.Collections.Generic.List[object]]::new()
  $currentResult = $search.GetFirstResult()

  while ($null -ne $currentResult) {

    $resultName = [string]$currentResult.Name

    if (
      -not [string]::IsNullOrWhiteSpace(
        $resultName
      ) -and
      $resultName.EndsWith(
        ".pdf",
        [System.StringComparison]::OrdinalIgnoreCase
      )
    ) {

      $entries.Add(
        [PSCustomObject]@{
          Name = $resultName
          BaseName = [System.IO.Path]::GetFileNameWithoutExtension($resultName).Trim()
          FullName = [string]$currentResult.Path
          FromVault = $true
        }
      )
    }

    $currentResult = $search.GetNextResult()
  }

  return $entries.ToArray()
}
function Get-DcaDiskPdfEntries {

  param(
    [Parameter(Mandatory = $true)]
    [string]$FolderPath
  )

  $entries = [System.Collections.Generic.List[object]]::new()

  $pdfFiles = @(Get-ChildItem `
    -LiteralPath $FolderPath `
    -Filter "*.pdf" `
    -File `
    -Recurse `
    -Force `
    -ErrorAction SilentlyContinue)

  foreach ($pdfFile in $pdfFiles) {

    $entries.Add(
      [PSCustomObject]@{
        Name = $pdfFile.Name
        BaseName = [System.IO.Path]::GetFileNameWithoutExtension($pdfFile.Name).Trim()
        FullName = $pdfFile.FullName
        FromVault = $false
      }
    )
  }

  return $entries.ToArray()
}
function Confirm-DcaLocalPdf {

  param(
    [Parameter(Mandatory = $true)]
    $Entry
  )

  if (Test-Path -LiteralPath $Entry.FullName -PathType Leaf) {
    return $Entry.FullName
  }

  $vault = $script:DcaVault

  if (-not $Entry.FromVault -or $null -eq $vault) {
    throw "PDF nao encontrado no disco: '$($Entry.FullName)'."
  }

  Write-Info "Baixando o PDF do vault..."

  $parentFolder = $null

  $pdmFile = $vault.GetFileFromPath($Entry.FullName, [ref]$parentFolder)

  if ($null -eq $pdmFile) {
    throw "Nao foi possivel obter o arquivo no vault."
  }

  if ($null -eq $parentFolder) {
    throw "Nao foi possivel obter a pasta do arquivo no vault."
  }

  $fileVersion = 0
  $folderId = $parentFolder.ID

  $pdmFile.GetFileCopy(0, [ref]$fileVersion, [ref]$folderId, 0, "")

  $localCachePath = $pdmFile.GetLocalPath($parentFolder.ID)

  if (-not (Test-Path -LiteralPath $localCachePath -PathType Leaf)) {
    throw "O arquivo nao foi encontrado no cache local do PDM: '$localCachePath'."
  }

  return $localCachePath
}

function Get-NormaCodeFromText {

  param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$Text
  )

  $normalizedText = $Text.Trim() -replace '\s+', ' '

  if (
    [string]::IsNullOrWhiteSpace(
      $normalizedText
    )
  ) {

    return [PSCustomObject]@{
      Code = $null
      Title = $null
      Parsed = $false
      Prefix = $null
      Pattern = $null
    }
  }

  # Test longer prefixes first so generic prefixes do not capture specific codes.
  $knownPrefixes = @(
    "COL-ASQR-PRO",
    "AMS-QQ-C",
    "AMS-QQ-N",
    "AMS-QQ-P",
    "AMS-QQ-S",
    "MIL-HDBK",
    "QPL-AMS",
    "AMS-STD",
    "AMS-QQ",
    "MIL-STD",
    "MIL-PRF",
    "MIL-DTL",
    "FED-STD",
    "ASTM-MNL",
    "SNT-TC",
    "AMS STD",
    "AMS A",
    "AMS M",
    "AMS S",
    "AMS-C",
    "AMS-H",
    "AMS-S",
    "ASTM-A",
    "ASTM-B",
    "ASTM-D",
    "ASTM-E",
    "ASTM-F",
    "ASTM-G",
    "ASME B",
    "ASME Y",
    "ANSI H",
    "AWS D",
    "SAE J",
    "SAE-J",
    "MIL-A",
    "MIL-C",
    "MIL-H",
    "MIL-I",
    "MIL-L",
    "MIL-R",
    "MIL-S",
    "TT-P",
    "NEDE E",
    "ADDHS",
    "ASQR",
    "EMBRAER",
    "UTCQR",
    "FLIGHTPARTS",
    "AMS",
    "ARP",
    "ASTM",
    "ANSI",
    "ASME",
    "AWS",
    "CID",
    "MFG",
    "NASM",
    "NAS",
    "QPL",
    "BAC",
    "CPS",
    "HSC",
    "HSM",
    "SVHS",
    "PMP",
    "MIL",
    "MS",
    "MEP",
    "ZERO",
    "SAE",
    "ISO",
    "DIN",
    "AS",
    "CG",
    "HS",
    "PN",
    "QC",
    "NB",
    "NE",
    "RR",
    "UC",
    "E",
    "F"
  )

  $knownPrefixes = @(
    $knownPrefixes |
      Sort-Object {
      $_.Length
    } -Descending
  )

  # Special AMS patterns.

  $specialPatterns = @(
    [PSCustomObject]@{
      Name = "AMS A numero sufixo"

      Prefix = "AMS A"

      Regex = '^(?<Code>AMS\s+A\s+\d+[A-Z0-9./-]*(?:\s+[A-Z])?)(?:\s+-?\s*(?<Title>.*))?$'
    }

    [PSCustomObject]@{
      Name = "AMS STD com espaco"

      Prefix = "AMS STD"

      Regex = '^(?<Code>AMS\s+STD\s+\d+[A-Z0-9./-]*)(?:\s+-?\s*(?<Title>.*))?$'
    }

    [PSCustomObject]@{
      Name = "AMS M com espaco"

      Prefix = "AMS M"

      Regex = '^(?<Code>AMS\s+M\s*\d+[A-Z0-9./-]*)(?:\s+-?\s*(?<Title>.*))?$'
    }

    [PSCustomObject]@{
      Name = "AMS S com espaco"

      Prefix = "AMS S"

      Regex = '^(?<Code>AMS\s+S\s*\d+[A-Z0-9./-]*)(?:\s+-?\s*(?<Title>.*))?$'
    }

    [PSCustomObject]@{
      Name = "AMS numerico com espaco"

      Prefix = "AMS"

      Regex = '^(?<Code>AMS\s+\d+[A-Z]?(?:-\d+)?)(?:\s+-?\s*(?<Title>.*))?$'
    }

    [PSCustomObject]@{
      Name = "AMS numerico sem espaco"

      Prefix = "AMS"

      Regex = '^(?<Code>AMS\d+[A-Z]?(?:-\d+)?)(?:\s+-?\s*(?<Title>.*))?$'
    }

    [PSCustomObject]@{
      Name = "AMS composto com hifen"

      Prefix = "AMS composto"

      Regex = '^(?<Code>AMS(?:-[A-Z0-9]+)+)(?:\s+-?\s*(?<Title>.*))?$'
    }
  )

  foreach ($specialPattern in $specialPatterns) {

    if (
      $normalizedText -notmatch
      $specialPattern.Regex
    ) {
      continue
    }

    $code = [string]$Matches["Code"]

    $title = $null

    if ($Matches.ContainsKey("Title")) {

      $title = [string]$Matches["Title"]
    }

    if (
      -not [string]::IsNullOrWhiteSpace(
        $title
      )
    ) {

      $title = $title.Trim().TrimStart("-", " ").TrimEnd(".", " ")
    }
    else {

      $title = $null
    }

    return [PSCustomObject]@{
      Code = $code.Trim()

      Title = $title

      Parsed = $true

      Prefix = [string]$specialPattern.Prefix

      Pattern = [string]$specialPattern.Name
    }
  }

  # Known-prefix rules.

  foreach ($prefix in $knownPrefixes) {

    # Allow variable whitespace in compound prefixes.
    $prefixRegex = [regex]::Escape($prefix)

    $prefixRegex = $prefixRegex.Replace(
      "\ ",
      "\s+"
    )

    # The identifier must contain at least one number.
    $pattern = (
      "^(?<Code>" +
      $prefixRegex +
      "(?:\s*-\s*|\s*)" +
      "[A-Z0-9./-]*\d[A-Z0-9./-]*" +
      "(?:\s+[A-Z])?" +
      ")" +
      "(?:\s+-?\s*(?<Title>.*))?$"
    )

    if ($normalizedText -notmatch $pattern) {
      continue
    }
    $code = [string]$Matches["Code"]

    if ([string]::IsNullOrWhiteSpace($code)) {
      continue
    }

    $code = $code.Trim()

    $title = $null

    if ($Matches.ContainsKey("Title")) {

      $title = [string]$Matches["Title"]
    }

    if (
      -not [string]::IsNullOrWhiteSpace(
        $title
      )
    ) {

      $title = $title.Trim()

      $title = $title.TrimStart(
        "-",
        "_",
        " "
      )

      $title = $title.TrimEnd(
        ".",
        " "
      )
    }
    else {

      $title = $null
    }

    return [PSCustomObject]@{
      Code = $code

      Title = $title

      Parsed = $true

      Prefix = $prefix

      Pattern = "Prefixo conhecido: $prefix"
    }
  }

  # Accept a complete technical code when it has no spaces and contains a number.
  if (
    $normalizedText -notmatch '\s' -and
    $normalizedText -match '\d' -and
    $normalizedText -match
    '^[A-Z0-9][A-Z0-9./_-]*$'
  ) {

    return [PSCustomObject]@{
      Code = $normalizedText

      Title = $null

      Parsed = $true

      Prefix = "Codigo completo"

      Pattern = "Codigo tecnico sem descricao"
    }
  }

  # Generic fallback for separating a technical code from its description.
  $genericPattern = (
    "^(?<Code>" +
    "[A-Z][A-Z0-9-]*" +
    "(?:\s+[A-Z]+)?" +
    "(?:[- ]?[A-Z]*)?" +
    "[- ]?\d+[A-Z0-9./-]*" +
    ")" +
    "(?:\s+-?\s*(?<Title>.*))?$"
  )

  if ($normalizedText -match $genericPattern) {

    $genericCode = [string]$Matches["Code"]

    $genericTitle = $null

    if ($Matches.ContainsKey("Title")) {

      $genericTitle = [string]$Matches["Title"]
    }

    if (
      -not [string]::IsNullOrWhiteSpace(
        $genericTitle
      )
    ) {

      $genericTitle = $genericTitle.Trim().TrimStart("-", " ").TrimEnd(".", " ")
    }
    else {

      $genericTitle = $null
    }

    return [PSCustomObject]@{
      Code = $genericCode.Trim()

      Title = $genericTitle

      Parsed = $true

      Prefix = "Generico"

      Pattern = "Codigo tecnico generico"
    }
  }

  return [PSCustomObject]@{
    Code = $normalizedText

    Title = $null

    Parsed = $false

    Prefix = "NAO_IDENTIFICADO"

    Pattern = $null
  }
}
function ConvertFrom-PdfFileName {

  param(
    [Parameter(Mandatory = $true)]
    [string]$BaseName,

    [Parameter(Mandatory = $true)]
    [string]$DocumentType
  )

  $name = $BaseName.Trim()
  $sourceCodeText = $name
  $clientRevision = $null

  if (
    $name -match
    '^(?<Code>[^\[\]]+?)\s*\[(?<BracketValue>[^\]]+)\]\s*$'
  ) {

    $possibleCode =
    $Matches["Code"].Trim()

    $possibleRevision =
    $Matches["BracketValue"].Trim().ToUpper()

    $validRevision =
    $false

    if ($DocumentType -eq "Processo") {

      # Processo: A1, BA4, AA4 ou --4.
      $validRevision =
      $possibleRevision -match
      '^[A-Z0-9-]{1,2}\d$'
    }
    elseif ($DocumentType -eq "Original") {

      # Original: uma ou duas letras/numeros.
      $validRevision =
      $possibleRevision -match
      '^[A-Z0-9]{1,2}$'
    }
    elseif ($DocumentType -eq "NormaExterna") {

      # Norma Externa usa 000 automaticamente.
      $validRevision =
      $possibleRevision -eq "000"
    }

    if ($validRevision) {

      $sourceCodeText =
      $possibleCode

      $clientRevision =
      $possibleRevision
    }
    else {

      # O texto entre colchetes nao e uma revisao.
      # Mantem o codigo anterior aos colchetes, mas deixa
      # a revisao vazia para o tratamento posterior.
      $sourceCodeText =
      $possibleCode

      $clientRevision =
      $null
    }
  }

  $codeParsed = $true

  $documentTitle = $null

  if ($DocumentType -eq "NormaExterna") {

    $normaInfo = Get-NormaCodeFromText `
      -Text $sourceCodeText

    $sourceCodeText = $normaInfo.Code

    $documentTitle = $normaInfo.Title

    $codeParsed = $normaInfo.Parsed
  }

  return [PSCustomObject]@{
    SourceCode = $sourceCodeText
    ClientRevision = $clientRevision
    DocumentTitle = $documentTitle
    CodeParsed = $codeParsed
  }
}

function Test-DcaCodeMatch {

  param(
    [string]$BaseName,
    [string]$ParsedCode,
    [string]$Pattern,
    [bool]$UsesWildcard
  )

  if ($UsesWildcard) {
    return (($BaseName -like $Pattern) -or ($ParsedCode -like $Pattern))
  }

  return (($BaseName -ieq $Pattern) -or ($ParsedCode -ieq $Pattern))
}
function Get-DcaPdmFileState {

  param(
    [Parameter(Mandatory = $true)]
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

  param(
    [Parameter(Mandatory = $true)]
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

      # PDF nao possui configuracoes como arquivos CAD.
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

  param(
    [Parameter(Mandatory = $true)]
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

        Write-Host (
          "  Erro inesperado ao ler '$variableName': " +
          $_.Exception.Message
        ) -ForegroundColor DarkGray

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
    "  Procurando variaveis preenchidas no cartao de:"
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
      "Nenhuma variavel preenchida foi encontrada no cartao."
    )

    return
  }

  Write-Host ""

  Write-Host (
    "  Variaveis preenchidas no cartao:"
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
function Get-DcaCardRevisionVariableNames {

  param(
    [string]$DocumentType
  )

  $configuredValue =
  ""

  if ($DocumentType -eq "Original") {

    $configuredValue =
    [string]$env:DCA_PDM_VAR_ORIGINAL_REVISION
  }
  elseif ($DocumentType -eq "Processo") {

    $configuredValue =
    [string]$env:DCA_PDM_VAR_PROCESS_REVISION
  }
  elseif ($DocumentType -eq "NormaExterna") {

    $configuredValue =
    [string]$env:DCA_PDM_VAR_STANDARD_REVISION
  }

  $variableNames =
  [System.Collections.Generic.List[string]]::new()

  foreach ($part in ($configuredValue -split '[|;]')) {

    $currentName =
    ([string]$part).Trim()

    if (-not [string]::IsNullOrWhiteSpace($currentName)) {
      $variableNames.Add($currentName)
    }
  }

  return $variableNames.ToArray()
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
function Convert-DcaOriginalDescription {

  param(
    [string]$Description
  )

  $descriptionClean =
  ([string]$Description).Trim()

  if (
    [string]::IsNullOrWhiteSpace(
      $descriptionClean
    )
  ) {

    return $null
  }

  # Remove virgulas usadas como separador no cartao.
  $descriptionClean =
  $descriptionClean.Replace(
    ",",
    " "
  )

  # Remove espacos duplicados.
  $descriptionClean =
  (
    $descriptionClean -replace
    '\s+',
    ' '
  ).Trim()

  if (
    [string]::IsNullOrWhiteSpace(
      $descriptionClean
    )
  ) {

    return $null
  }

  # Padrao do nome no Teamcenter:
  # primeira letra maiuscula e restante minusculo.
  if ($descriptionClean.Length -eq 1) {

    return $descriptionClean.ToUpperInvariant()
  }

  return (
    $descriptionClean.Substring(
      0,
      1
    ).ToUpperInvariant() +
    $descriptionClean.Substring(
      1
    ).ToLowerInvariant()
  )
}
function Update-DcaMatchDescriptionFromCard {

  param(
    [Parameter(Mandatory = $true)]
    $Match
  )

  $descriptionVariableName =
  $null

  if ($Match.DocumentType -eq "Processo") {

    $descriptionVariableName =
    [string]$env:DCA_PDM_VAR_PROCESS_DESCRIPTION
  }
  elseif ($Match.DocumentType -eq "Original") {

    $descriptionVariableName =
    [string]$env:DCA_PDM_VAR_ORIGINAL_DESCRIPTION
  }
  elseif ($Match.DocumentType -eq "NormaExterna") {

    $descriptionVariableName =
    [string]$env:DCA_PDM_VAR_STANDARD_DESCRIPTION
  }

  $descriptionVariableName =
  ([string]$descriptionVariableName).Trim()

  if (
    [string]::IsNullOrWhiteSpace(
      $descriptionVariableName
    )
  ) {

    Add-Member `
      -InputObject $Match `
      -NotePropertyName "DescriptionSource" `
      -NotePropertyValue "nao configurada" `
      -Force

    return
  }

  $cardDescription =
  Get-DcaPdmVariableValue `
    -Entry $Match.File `
    -VariableNames @(
    $descriptionVariableName
  )

  $cardDescription =
  ([string]$cardDescription).Trim()
  if ($Match.DocumentType -eq "Original") {

    $cardDescription =
    Convert-DcaOriginalDescription `
      -Description $cardDescription
  }
  if (
    [string]::IsNullOrWhiteSpace(
      $cardDescription
    )
  ) {

    Add-Member `
      -InputObject $Match `
      -NotePropertyName "DescriptionSource" `
      -NotePropertyValue "cartao vazio" `
      -Force

    if ($Details) {

      Write-Warn (
        "A descricao do cartao esta vazia em " +
        "'$($Match.File.Name)'. " +
        "Variavel: '$descriptionVariableName'."
      )
    }

    return
  }

  $Match.DocumentTitle =
  $cardDescription

  Add-Member `
    -InputObject $Match `
    -NotePropertyName "CardDescription" `
    -NotePropertyValue $cardDescription `
    -Force

  Add-Member `
    -InputObject $Match `
    -NotePropertyName "DescriptionSource" `
    -NotePropertyValue "cartao de dados" `
    -Force

  if ($Details) {

    Write-Host (
      "  Descricao do cartao: " +
      "'$cardDescription'"
    ) -ForegroundColor Cyan
  }
}
function Update-DcaMatchRevisionFromCard {

  param(
    [Parameter(Mandatory = $true)]
    $Match
  )
  $discoverCardVariables =
  ([string]$env:DCA_PDM_DISCOVER_CARD_VARIABLES).Trim()

  if (
    $discoverCardVariables -match
    '^(?i:true|1|sim|yes)$'
  ) {

    Show-DcaPdmCardVariables `
      -Entry $Match.File
  }
  $fileRevision =
  ([string]$Match.ClientRevision).Trim().ToUpper()

  $revisionSource =
  "nome do arquivo"

  $variableNames =
  @(
    Get-DcaCardRevisionVariableNames `
      -DocumentType ([string]$Match.DocumentType)
  )
  if ($Details) {

    $configuredVariablesDisplay =
    if ($variableNames.Count -gt 0) {
      $variableNames -join ", "
    }
    else {
      "<nenhuma>"
    }

    Write-Host (
      "  Variaveis de revisao configuradas: " +
      $configuredVariablesDisplay
    ) -ForegroundColor DarkGray
  }
  if ($variableNames.Count -gt 0) {

    $cardRevision =
    Get-DcaPdmVariableValue `
      -Entry $Match.File `
      -VariableNames $variableNames

    if ($Details) {

      Write-Host (
        "  Cartao de dados: " +
        $Match.File.Name
      ) -ForegroundColor Cyan

      Write-Host (
        "    Variavel(is) testada(s): " +
        ($variableNames -join ", ")
      ) -ForegroundColor DarkGray

      if (
        [string]::IsNullOrWhiteSpace(
          [string]$cardRevision
        )
      ) {

        Write-Host (
          "    Revisao do cartao: nao encontrada ou vazia"
        ) -ForegroundColor Yellow
      }
      else {

        Write-Host (
          "    Revisao do cartao: [$cardRevision]"
        ) -ForegroundColor Green
      }
    }

    if (
      -not [string]::IsNullOrWhiteSpace(
        $cardRevision
      )
    ) {

      $cardRevision =
      ([string]$cardRevision).Trim().ToUpperInvariant()

      if (
        -not [string]::IsNullOrWhiteSpace($fileRevision) -and
        $cardRevision -ne $fileRevision
      ) {

        Write-Warn (
          "Revisao diferente em '$($Match.File.Name)': " +
          "arquivo [$fileRevision] x cartao [$cardRevision]. " +
          "Usando o cartao."
        )
      }

      $Match.ClientRevision =
      $cardRevision

      $revisionSource =
      "cartao de dados"
    }
  }
  if (
    $variableNames.Count -eq 0 -and
    $Details
  ) {

    Write-Warn (
      "Nenhuma variavel de revisao do cartao foi configurada " +
      "para o tipo '$($Match.DocumentType)'."
    )

    Write-Host (
      "  Configure DCA_PDM_VAR_PROCESS_REVISION no arquivo .env."
    ) -ForegroundColor DarkGray
  }
  Add-Member `
    -InputObject $Match `
    -NotePropertyName "FileRevision" `
    -NotePropertyValue $fileRevision `
    -Force

  Add-Member `
    -InputObject $Match `
    -NotePropertyName "RevisionSource" `
    -NotePropertyValue $revisionSource `
    -Force
}