# ============================================================
# PESQUISA E DISPONIBILIZACAO DOS PDFS
# ============================================================
#   1. pesquisa PDFs (e SLDDRW em "Folhas NDT") pelo indice do Vault;
#   2. pesquisa PDFs no sistema de arquivos (alternativa);
#   3. garante uma copia local do PDF e valida o caminho.
# A pesquisa pelo Vault tem prioridade; o disco e a alternativa.
# ============================================================

function Search-DcaVaultPdfEntries {
    # Com StartFolderPath, a pesquisa comeca nessa pasta (a EdmLib pode incluir subpastas).
    param(
        [Parameter(Mandatory)][ValidateNotNull()]$Vault,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$SearchText,
        [string]$StartFolderPath
    )

    $text = $SearchText.Trim()
    if (-not $text) { throw "O texto da pesquisa no Vault ficou vazio." }

    # O PDM usa curingas SQL (% e _); o DCAtoPLM usa * e ?.
    # Sem curinga, faz pesquisa parcial pelo texto.
    $likePattern = $text.Replace("*", "%").Replace("?", "_")
    if ($likePattern -notmatch "[%_]") { $likePattern = "%$likePattern%" }

    $search = $Vault.CreateSearch()
    if ($null -eq $search) { throw "A API do PDM nao retornou um objeto de pesquisa." }

    $search.FileName = $likePattern
    $search.FindHistoricStates = $false   # sem versoes historicas

    $startPath = ([string]$StartFolderPath).Trim()
    if ($startPath) {
        $startFolder = $Vault.GetFolderFromPath($startPath)
        if ($null -eq $startFolder) { throw "A pasta nao foi encontrada pela API do PDM: '$startPath'." }
        $search.StartFolderID = [int]$startFolder.ID
    }

    $entries = [System.Collections.Generic.List[object]]::new()
    $result = $search.GetFirstResult()

    while ($null -ne $result) {
        $name      = ([string]$result.Name).Trim()
        $fullName  = ([string]$result.Path).Trim()
        $extension = [System.IO.Path]::GetExtension($name)
        $isDrawing = $extension -ieq ".slddrw"

        # SLDDRW so vale dentro de uma pasta chamada "Folhas NDT".
        $inNdtFolder = [bool]$fullName -and (
            @($fullName -split '[\\/]' | Where-Object { ([string]$_).Trim() -ieq "Folhas NDT" }).Count -gt 0
        )
        $allowed = ($extension -ieq ".pdf") -or ($isDrawing -and $inNdtFolder)

        if ($allowed -and $fullName) {
            $entries.Add([PSCustomObject]@{
                Name            = $name
                BaseName        = ([string][System.IO.Path]::GetFileNameWithoutExtension($name)).Trim()
                FullName        = $fullName
                Extension       = $extension
                DocumentType    = if ($isDrawing) { "NDT" } else { $null }
                TypeDisplayName = if ($isDrawing) { "GD5_DCA_NDT" } else { $null }
                IsNdt           = [bool]$isDrawing
                FromVault       = $true
            })
        }
        elseif ($allowed -and $Details) {
            Write-Host "  Resultado do Vault ignorado por nao possuir caminho: '$name'." -ForegroundColor DarkGray
        }

        $result = $search.GetNextResult()
    }

    return $entries.ToArray()
}

function Get-DcaDiskPdfEntries {
    # Pesquisa recursiva de PDFs no disco (API do PDM indisponivel ou modo local).
    param([Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$FolderPath)

    $folder = $FolderPath.Trim()
    if (-not $folder) { throw "O caminho da pesquisa local ficou vazio." }
    if (-not (Test-Path -LiteralPath $folder -PathType Container)) {
        throw "A pasta de pesquisa local nao foi encontrada: '$folder'."
    }

    # Recursiva porque a pesquisa geral por codigo tambem usa esta funcao.
    $entries = foreach (
        $pdf in Get-ChildItem -LiteralPath $folder -Filter "*.pdf" -File -Recurse -Force `
            -ErrorAction SilentlyContinue | Sort-Object FullName
    ) {
        $fullName = ([string]$pdf.FullName).Trim()
        if (-not $fullName) { continue }

        # Mesma estrutura dos resultados da API.
        [PSCustomObject]@{
            Name      = [string]$pdf.Name
            BaseName  = ([string][System.IO.Path]::GetFileNameWithoutExtension($pdf.Name)).Trim()
            FullName  = $fullName
            FromVault = $false
        }
    }

    return @($entries)
}

function Confirm-DcaLocalPdf {
    # Garante o PDF localmente: se ja existe no disco/cache, retorna o caminho;
    # se veio do Vault e nao esta local, solicita uma copia ao PDM.
    param([Parameter(Mandatory)][ValidateNotNull()]$Entry)

    # --- 1. Validar a entrada ---
    $entryPath = ([string]$Entry.FullName).Trim()
    if (-not $entryPath) { throw "A entrada do PDF nao possui um caminho completo." }
    if ([System.IO.Path]::GetExtension($entryPath) -ine ".pdf") {
        throw "O arquivo informado nao possui extensao PDF: '$entryPath'."
    }

    # --- 2. Arquivo ja disponivel ---
    if (Test-Path -LiteralPath $entryPath -PathType Leaf) {
        $localFile = Get-Item -LiteralPath $entryPath -ErrorAction Stop
        if ($localFile.Length -le 0) { throw "O PDF encontrado no disco esta vazio: '$entryPath'." }
        return $localFile.FullName
    }

    # --- 3. So o Vault pode fornecer o arquivo ---
    $vault = $script:DcaVault
    $entryFromVault = $Entry.PSObject.Properties["FromVault"] -and [bool]$Entry.FromVault
    if (-not $entryFromVault -or $null -eq $vault) { throw "PDF nao encontrado no disco: '$entryPath'." }

    # --- 4. Localizar o arquivo no Vault ---
    Write-Info "Baixando o PDF do vault..."

    [object]$parentFolder = $null
    $pdmFile = $vault.GetFileFromPath($entryPath, [ref]$parentFolder)
    if ($null -eq $pdmFile)      { throw "Nao foi possivel obter o arquivo no vault: '$entryPath'." }
    if ($null -eq $parentFolder) { throw "Nao foi possivel obter a pasta do arquivo no vault: '$entryPath'." }

    $folderId = [int]$parentFolder.ID
    $fileVersion = 0

    if ($Details) {
        @(
            "  Preparando download pelo PDM:"
            "    Arquivo:     '$entryPath'"
            "    Pasta ID:    '$folderId'"
            "    Versao:      '$fileVersion'"
            "    Tipo arquivo: $($pdmFile.GetType().FullName)"
            "    Tipo pasta:   $($parentFolder.GetType().FullName)"
        ) | ForEach-Object { Write-Host $_ -ForegroundColor DarkGray }
    }

    # --- 5. Solicitar a copia local (GetFileCopy da IEdmFile5, por reflexao) ---
    # O namespace do interop varia entre instalacoes; a interface e procurada pelo nome.
    # Nao usa CreateWrapperOfType: IEdmFile5 e interface COM, nao coclass.
    $typedPdmFile = $null
    try {
        $edmFile5Type = [System.AppDomain]::CurrentDomain.GetAssemblies() |
            ForEach-Object { try { $_.GetTypes() } catch { @() } } |
            Where-Object { $_.IsInterface -and $_.Name -eq "IEdmFile5" } |
            Select-Object -First 1

        # Biblioteca ainda nao carregada: tenta o caminho configurado no .env.
        if (
            $null -eq $edmFile5Type -and $env:DCA_PDM_LIB -and
            (Test-Path -LiteralPath $env:DCA_PDM_LIB -PathType Leaf)
        ) {
            $interop = [System.Reflection.Assembly]::LoadFrom($env:DCA_PDM_LIB)
            if ($null -ne $interop) {
                $edmFile5Type = $interop.GetTypes() |
                    Where-Object { $_.IsInterface -and $_.Name -eq "IEdmFile5" } |
                    Select-Object -First 1
            }
        }

        if ($null -eq $edmFile5Type) {
            $loadedNames = @(
                [System.AppDomain]::CurrentDomain.GetAssemblies() |
                    ForEach-Object { $_.GetName().Name } | Sort-Object -Unique
            )
            throw (
                "A interface IEdmFile5 nao foi encontrada nas bibliotecas carregadas. " +
                "DCA_PDM_LIB: '$([string]$env:DCA_PDM_LIB)'. " +
                "Assemblies carregados: $($loadedNames -join ', ')"
            )
        }

        if ($Details) {
            Write-Host "  Interface IEdmFile5 localizada:" -ForegroundColor Cyan
            Write-Host "    Nome completo: $($edmFile5Type.FullName)" -ForegroundColor DarkGray
            Write-Host "    Assembly:      $($edmFile5Type.Assembly.GetName().Name)" -ForegroundColor DarkGray
        }

        $getFileCopy = $edmFile5Type.GetMethods() |
            Where-Object { $_.Name -eq "GetFileCopy" -and $_.GetParameters().Count -eq 5 } |
            Select-Object -First 1
        if ($null -eq $getFileCopy) {
            throw "O metodo GetFileCopy com 5 parametros nao foi encontrado em '$($edmFile5Type.FullName)'."
        }

        if ($Details) {
            Write-Host "  Assinatura de GetFileCopy:" -ForegroundColor Cyan
            $parameters = $getFileCopy.GetParameters()
            for ($i = 0; $i -lt $parameters.Count; $i++) {
                Write-Host ("    [{0}] {1} {2} | ByRef: {3}" -f
                    $i, $parameters[$i].ParameterType.FullName, $parameters[$i].Name, $parameters[$i].ParameterType.IsByRef
                ) -ForegroundColor DarkGray
            }
        }

        # Posicoes 1 (versao) e 2 (pasta) sao atualizadas pelo Invoke quando ByRef.
        $arguments = [object[]]@([int]0, [int]0, [int]$folderId, [int]0, [string]"")

        $unknownPointer = [System.IntPtr]::Zero
        try {
            # Referencia tipada como IEdmFile5 a partir do objeto COM do Vault.
            $unknownPointer = [System.Runtime.InteropServices.Marshal]::GetIUnknownForObject($pdmFile)
            if ($unknownPointer -eq [System.IntPtr]::Zero) {
                throw "GetIUnknownForObject retornou um ponteiro vazio para '$entryPath'."
            }

            $typedPdmFile = [System.Runtime.InteropServices.Marshal]::GetTypedObjectForIUnknown($unknownPointer, $edmFile5Type)
            if ($null -eq $typedPdmFile) {
                throw "GetTypedObjectForIUnknown nao retornou uma referencia IEdmFile5 para '$entryPath'."
            }

            if ($Details) {
                Write-Host "  Referencia COM tipada criada:" -ForegroundColor Cyan
                Write-Host "    Interface: '$($edmFile5Type.FullName)'" -ForegroundColor DarkGray
                Write-Host "    Tipo RCW:  '$($typedPdmFile.GetType().FullName)'" -ForegroundColor DarkGray
            }

            $null = $getFileCopy.Invoke($typedPdmFile, $arguments)
        }
        finally {
            # Libera so a referencia adicional; $pdmFile ainda e usado no fluxo.
            if ($unknownPointer -ne [System.IntPtr]::Zero) {
                $null = [System.Runtime.InteropServices.Marshal]::Release($unknownPointer)
            }
        }

        $fileVersion = $arguments[1]
        $folderId    = $arguments[2]

        if ($Details) {
            Write-Host "  Solicitacao de copia enviada ao PDM." -ForegroundColor Green
            Write-Host "    Versao retornada: '$fileVersion'" -ForegroundColor DarkGray
            Write-Host "    Pasta retornada:  '$folderId'" -ForegroundColor DarkGray
        }
    }
    catch {
        throw (
            "Nao foi possivel disponibilizar o PDF no cache local. Arquivo: '$entryPath'. " +
            "FileVersion: '$fileVersion'. FolderID: '$folderId'. " +
            "Detalhe: $($_.Exception.GetBaseException().Message)"
        )
    }

    # --- 6. Obter e validar o caminho local (GetLocalPath tambem e da IEdmFile5) ---
    $getLocalPath = $edmFile5Type.GetMethods() |
        Where-Object { $_.Name -eq "GetLocalPath" -and $_.GetParameters().Count -eq 1 } |
        Select-Object -First 1
    if ($null -eq $getLocalPath) {
        throw "O metodo GetLocalPath com 1 parametro nao foi encontrado em '$($edmFile5Type.FullName)'."
    }
    if ($null -eq $typedPdmFile) { throw "A referencia COM tipada ficou NULL antes de GetLocalPath." }

    if ($Details) {
        Write-Host "  Executando GetLocalPath por reflexao:" -ForegroundColor Cyan
        Write-Host "    Interface: '$($edmFile5Type.FullName)'" -ForegroundColor DarkGray
        Write-Host "    Pasta ID:  '$($parentFolder.ID)'" -ForegroundColor DarkGray
    }

    try {
        $localCachePath = [string]$getLocalPath.Invoke($typedPdmFile, [object[]]@([int]$parentFolder.ID))
    }
    catch {
        throw (
            "Nao foi possivel obter o caminho local do PDF. Arquivo: '$entryPath'. " +
            "FolderID: '$($parentFolder.ID)'. Detalhe: $($_.Exception.GetBaseException().Message)"
        )
    }

    if ($Details) {
        Write-Host "  Caminho retornado por GetLocalPath:" -ForegroundColor Green
        Write-Host "    '$localCachePath'" -ForegroundColor DarkGray
    }

    $localCachePath = $localCachePath.Trim()
    if (-not $localCachePath) { throw "O Vault nao retornou o caminho do cache local para '$entryPath'." }
    if (-not (Test-Path -LiteralPath $localCachePath -PathType Leaf)) {
        throw "O arquivo nao foi encontrado no cache local do PDM: '$localCachePath'."
    }
    if ([System.IO.Path]::GetExtension($localCachePath) -ine ".pdf") {
        throw "O arquivo retornado pelo cache do PDM nao e um PDF: '$localCachePath'."
    }

    $localCacheFile = Get-Item -LiteralPath $localCachePath -ErrorAction Stop
    if ($localCacheFile.Length -le 0) { throw "O PDF disponibilizado no cache do PDM esta vazio: '$localCachePath'." }

    # --- 7. Caminho local validado ---
    return $localCacheFile.FullName
}