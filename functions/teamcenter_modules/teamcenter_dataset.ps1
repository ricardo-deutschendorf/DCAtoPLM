# ============================================================
# REVISAO DE DESTINO E IMPORTACAO DE DATASET
# ============================================================
# Recupera uma revisao existente e importa um PDF (ou o SLDDRW da
# Folha NDT) como Dataset associado a essa revisao.
#   1. recupera a revisao de um Item e diagnostica suas relacoes;
#   2. verifica se o Dataset ja existe;
#   3. valida o PDF e executa ImportarPDF;
#   4. importa o desenho NDT (ImportarOffice) e o vincula a Pasta NDT
#      do DCA Processo;
#   5. localiza Processo e Folhas NDT pelo codigo.
# Nao cria Items ou revisoes e nao inicia workflows.
# ============================================================

# Localiza a revisao do Item com getItemRevisionfromItem (Importar GD).
function Get-TeamcenterRevision {
    param([Parameter(Mandatory)][ValidateNotNull()]$Item)

    if ($null -eq $Item) { throw "O Item do Teamcenter nao foi fornecido." }
    if ($null -eq $script:TeamcenterFunctions) { throw "As funcoes do Teamcenter nao foram carregadas. Execute Connect-Teamcenter primeiro." }

    # PSObject.BaseObject recupera o objeto tecnico quando o PowerShell o encapsula.
    if ($null -ne $Item.PSObject.BaseObject) { $Item = $Item.PSObject.BaseObject }

    $getRevisionMethod = Get-TeamcenterMethod -MethodName "getItemRevisionfromItem" -ParameterCount 1

    try { $revision = $getRevisionMethod.Invoke($null, @($Item)) }
    catch {
        $root = $_.Exception; while ($null -ne $root.InnerException) { $root = $root.InnerException }
        throw "Nao foi possivel recuperar a revisao do Item: $($root.Message)"
    }

    if ($null -eq $revision) { return $null }
    if ($null -ne $revision.PSObject.BaseObject) { $revision = $revision.PSObject.BaseObject }

    return $revision
}

# Diagnostico: le as relacoes mais comuns da revisao e retorna os objetos
# secundarios encontrados. So le; nenhum Dataset e criado, alterado ou removido.
function Show-DcaTeamcenterRevisionDatasets {
    param(
        [Parameter(Mandatory)][ValidateNotNull()]$Revision,
        [string[]]$RelationNames
    )

    # --- 1. Normalizar e validar a revisao ---
    if ($null -ne $Revision.PSObject.BaseObject) { $Revision = $Revision.PSObject.BaseObject }
    if ($null -eq $Revision) { throw "A revisao nao foi fornecida para o diagnostico dos Datasets." }

    $revisionTypeName = $Revision.GetType().FullName
    if ($revisionTypeName -notmatch '(?i)(ItemRevision|Revision)$') {
        throw "O objeto recebido nao e uma revisao valida. Tipo recebido: '$revisionTypeName'."
    }

    # --- 2. Obter o DataManagementService e o metodo GetProperties ---
    $dataManagementService = Get-TeamcenterDataManagementService

    $getPropertiesMethod = $dataManagementService.GetType().GetMethods() |
        Where-Object { $_.Name -ieq "GetProperties" -and $_.GetParameters().Count -eq 2 } | Select-Object -First 1
    if ($null -eq $getPropertiesMethod) { throw "DataManagementService.GetProperties nao foi encontrado." }

    # A relacao usada pelo Importar GD varia conforme o modelo do Teamcenter:
    # testa as mais comuns sem assumir qual e a usada.
    $relationPropertyNames = [string[]]@("IMAN_specification", "IMAN_reference", "IMAN_Rendering", "IMAN_manifestation", "IMAN_requirement")
    if ($null -ne $RelationNames -and $RelationNames.Count -gt 0) { $relationPropertyNames = [string[]]$RelationNames }

    # --- 3. Carregar as propriedades da revisao ---
    $revisionArrayType = $getPropertiesMethod.GetParameters()[0].ParameterType
    if (-not $revisionArrayType.IsArray) { throw "O primeiro parametro de GetProperties nao e um array." }

    $modelObjectType = $revisionArrayType.GetElementType()
    if ($null -eq $modelObjectType) { throw "O tipo dos objetos de GetProperties nao foi identificado." }

    $loadProperties = {
        param($objectArray, $names)
        $arguments = [object[]]::new(2); $arguments[0] = $objectArray; $arguments[1] = $names
        $getPropertiesMethod.Invoke($dataManagementService, $arguments)
    }

    $revisionArray = [System.Array]::CreateInstance($modelObjectType, 1)
    $revisionArray.SetValue($Revision, 0)

    $propertyResponse = & $loadProperties $revisionArray $relationPropertyNames
    if ($null -ne $propertyResponse) {
        $propertyErrors = @(Get-TeamcenterServiceErrors -ServiceData $propertyResponse)
        if ($propertyErrors.Count -gt 0) { Write-Warn "Algumas propriedades nao puderam ser carregadas: $($propertyErrors -join ' | ')" }
    }

    # --- 4. GetProperty (a versao atual do modelo cliente nao tem GetPropertyObject) ---
    $getPropertyMethod = $Revision.GetType().GetMethods() |
        Where-Object { $_.Name -eq "GetProperty" -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType -eq [string] } |
        Select-Object -First 1
    if ($null -eq $getPropertyMethod) { throw "O metodo GetProperty(string) nao foi encontrado no objeto de revisao '$revisionTypeName'." }

    # --- 5. Ler os objetos de cada relacao ---
    if ($Details) {
        Write-AnimatedLine ""
        Write-Host "  Diagnostico das relacoes da revisao:" -ForegroundColor Cyan
        Write-Host "  Tipo da revisao: $revisionTypeName" -ForegroundColor DarkGray
        Write-Host ""
    }

    $foundObjects = [System.Collections.Generic.List[object]]::new()

    foreach ($relationName in $relationPropertyNames) {
        if ($Details) { Write-Host "  Relacao: $relationName" -ForegroundColor White }

        try {
            $propertyObject = $getPropertyMethod.Invoke($Revision, @([string]$relationName))

            if ($null -eq $propertyObject) {
                if ($Details) { Write-Host "    Propriedade nao disponivel." -ForegroundColor DarkGray }
                continue
            }

            # A colecao pode vir de uma propriedade publica ou de um getter, conforme a versao das bibliotecas SOA.
            $arrayValueProperty = $propertyObject.GetType().GetProperties() |
                Where-Object { $_.Name -match "(?i)^(ModelObjectArrayValue|ObjectArrayValue)$" } | Select-Object -First 1

            $relatedObjects = @()

            if ($null -ne $arrayValueProperty) { $relatedObjects = @($arrayValueProperty.GetValue($propertyObject, $null)) }
            else {
                $arrayValueMethod = $propertyObject.GetType().GetMethods() |
                    Where-Object { $_.Name -match "(?i)^(get_|Get)(ModelObjectArrayValue|ObjectArrayValue)$" -and $_.GetParameters().Count -eq 0 } |
                    Select-Object -First 1

                if ($null -ne $arrayValueMethod) { $relatedObjects = @($arrayValueMethod.Invoke($propertyObject, @())) }
                elseif ($Details) {
                    Write-Host "    O tipo da propriedade nao disponibiliza um array de objetos relacionados." -ForegroundColor DarkGray
                    Write-Host "    Tipo da propriedade: $($propertyObject.GetType().FullName)" -ForegroundColor DarkGray
                }
            }

            $relatedObjects = @($relatedObjects | Where-Object { $null -ne $_ })

            if ($relatedObjects.Count -eq 0) {
                if ($Details) { Write-Host "    Nenhum objeto relacionado." -ForegroundColor DarkGray }
                continue
            }
            if ($Details) { Write-Host "    Objetos encontrados: $($relatedObjects.Count)" -ForegroundColor Green }

            # Carrega as propriedades que identificam os objetos relacionados e comparam os Datasets.
            try {
                $relatedObjectArray = [System.Array]::CreateInstance($modelObjectType, $relatedObjects.Count)
                for ($i = 0; $i -lt $relatedObjects.Count; $i++) {
                    if ($null -ne $relatedObjects[$i].PSObject.BaseObject) { $relatedObjects[$i] = $relatedObjects[$i].PSObject.BaseObject }
                    $relatedObjectArray.SetValue($relatedObjects[$i], $i)
                }

                $relatedPropertyResponse = & $loadProperties $relatedObjectArray ([string[]]@("object_name", "object_string", "object_type"))

                if ($null -ne $relatedPropertyResponse) {
                    $relatedPropertyErrors = @(Get-TeamcenterServiceErrors -ServiceData $relatedPropertyResponse)
                    if ($relatedPropertyErrors.Count -gt 0 -and $Details) {
                        Write-Warn "Algumas propriedades dos objetos relacionados nao foram carregadas: $($relatedPropertyErrors -join ' | ')"
                    }
                }
            }
            catch {
                if ($Details) {
                    $root = $_.Exception; while ($null -ne $root.InnerException) { $root = $root.InnerException }
                    Write-Warn "Nao foi possivel carregar todas as propriedades dos objetos relacionados: $($root.Message)"
                }
            }

            foreach ($related in $relatedObjects) {
                if ($null -ne $related.PSObject.BaseObject) { $related = $related.PSObject.BaseObject }

                $relatedTypeName     = $related.GetType().FullName
                $relatedName         = Get-TeamcenterModelPropertyText -ModelObject $related -PropertyName "object_name"
                $relatedId           = Get-TeamcenterModelPropertyText -ModelObject $related -PropertyName "object_string"
                $relatedBusinessType = Get-TeamcenterModelPropertyText -ModelObject $related -PropertyName "object_type"

                if ($Details) {
                    Write-Host "    Tipo tecnico: $relatedTypeName" -ForegroundColor Gray
                    if (-not [string]::IsNullOrWhiteSpace([string]$relatedBusinessType)) { Write-Host "    Tipo Teamcenter: '$relatedBusinessType'" -ForegroundColor Gray }
                    Write-Host "    Nome: '$relatedName'" -ForegroundColor Gray
                    if (-not [string]::IsNullOrWhiteSpace([string]$relatedId)) { Write-Host "    Identificacao: '$relatedId'" -ForegroundColor DarkGray }
                    Write-Host ""
                }

                $foundObjects.Add([PSCustomObject]@{
                        Relation     = $relationName
                        TypeName     = $relatedTypeName
                        BusinessType = [string]$relatedBusinessType
                        ObjectName   = [string]$relatedName
                        ObjectString = [string]$relatedId
                        Object       = $related
                    })
            }
        }
        catch {
            $root = $_.Exception; while ($null -ne $root.InnerException) { $root = $root.InnerException }
            if ($Details) { Write-Host "    Nao foi possivel ler: $($root.Message)" -ForegroundColor DarkGray }
        }
    }

    return $foundObjects.ToArray()
}

# Verifica se a revisao ja possui um Dataset com o nome esperado antes de
# ImportarPDF. So consulta; nada e criado ou alterado.
function Test-DcaTeamcenterDatasetExists {
    param(
        [Parameter(Mandatory)][ValidateNotNull()]$Revision,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$DatasetName,
        [string]$DatasetRevision
    )

    $datasetNameClean     = $DatasetName.Trim()
    $datasetRevisionClean = ([string]$DatasetRevision).Trim().ToUpperInvariant()

    if ($datasetNameClean -eq "") { throw "O nome esperado do Dataset ficou vazio." }

    # So objetos de Dataset (pelo tipo tecnico ou pelo tipo Teamcenter).
    $datasetCandidates = @(
        Show-DcaTeamcenterRevisionDatasets -Revision $Revision |
            Where-Object { [string]$_.TypeName -match '(?i)(Dataset|PDF)' -or [string]$_.BusinessType -match '(?i)(Dataset|PDF)' }
    )

    if ($Details) { Write-Host "  Datasets encontrados na revisao: $($datasetCandidates.Count)" -ForegroundColor DarkGray }

    # A comparacao usa o nome e o object_string; DatasetRevision so e registrada no retorno.
    foreach ($candidate in $datasetCandidates) {
        $foundName   = ([string]$candidate.ObjectName).Trim()
        $foundString = ([string]$candidate.ObjectString).Trim()

        if ($Details) {
            Write-Host "  Comparando Dataset:" -ForegroundColor DarkGray
            Write-Host "    Esperado: '$datasetNameClean'" -ForegroundColor DarkGray
            Write-Host "    Encontrado: '$foundName'" -ForegroundColor DarkGray
            Write-Host "    Relacao: '$($candidate.Relation)'" -ForegroundColor DarkGray
        }

        $nameMatches = $foundName -ieq $datasetNameClean -or $foundString -ieq $datasetNameClean -or
            $foundString -like "$datasetNameClean/*" -or $foundString -like "$datasetNameClean *"
        if (-not $nameMatches) { continue }

        return [PSCustomObject]@{
            Exists          = $true
            DatasetName     = $foundName
            DatasetRevision = $datasetRevisionClean
            Relation        = [string]$candidate.Relation
            TypeName        = [string]$candidate.TypeName
            ObjectString    = $foundString
            Dataset         = $candidate.Object
            ErrorMessage    = $null
        }
    }

    return [PSCustomObject]@{
        Exists          = $false
        DatasetName     = $datasetNameClean
        DatasetRevision = $datasetRevisionClean
        Relation        = $null
        TypeName        = $null
        ObjectString    = $null
        Dataset         = $null
        ErrorMessage    = $null
    }
}

# Valida os dados e chama ImportarPDF (Importar GD) para associar o PDF a revisao.
function Import-TeamcenterPdf {
    param(
        [Parameter(Mandatory)][ValidateNotNull()]$Revision,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$ItemCode,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$DatasetName,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$DatasetRevision,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$FilePath
    )

    # --- 1. Validar a revisao e o arquivo PDF ---
    if ($Details) {
        Write-Host "  Diagnostico inicial de Import-TeamcenterPdf:" -ForegroundColor Cyan
        Write-Host "    ItemCode: '$ItemCode'" -ForegroundColor DarkGray
        Write-Host "    DatasetName: '$DatasetName'" -ForegroundColor DarkGray
        Write-Host "    DatasetRevision: '$DatasetRevision'" -ForegroundColor DarkGray
        Write-Host "    FilePath: '$FilePath'" -ForegroundColor DarkGray
        Write-Host "    Tipo de FilePath: $($FilePath.GetType().FullName)" -ForegroundColor DarkGray
        Write-Host "    Comprimento de FilePath: $($FilePath.Length)" -ForegroundColor DarkGray
    }

    if ($null -eq $Revision) { throw "A revisao do Item '$ItemCode' nao foi fornecida." }
    if (-not (Test-Path -LiteralPath $FilePath -PathType Leaf)) { throw "PDF nao encontrado em '$FilePath'." }

    $pdfFile = Get-Item -LiteralPath $FilePath -ErrorAction Stop
    if ($pdfFile.Extension -ine ".pdf") { throw "O arquivo informado nao possui extensao PDF: '$FilePath'." }
    if ($pdfFile.Length -le 0) { throw "O PDF informado para '$ItemCode' esta vazio." }

    $FilePath = $pdfFile.FullName

    if ($FilePath.IndexOfAny([System.IO.Path]::GetInvalidPathChars()) -ge 0) {
        $pathCharacterCodes = @($FilePath.ToCharArray() | ForEach-Object { [int][char]$_ }) -join ", "
        throw "O caminho do PDF possui caracteres invalidos. Caminho: '$FilePath'. Codigos dos caracteres: $pathCharacterCodes"
    }

    # --- 2. Normalizar a revisao e validar o tipo (aceita revisoes especializadas) ---
    if ($null -ne $Revision.PSObject.BaseObject) { $Revision = $Revision.PSObject.BaseObject }

    $revisionTypeName = $Revision.GetType().FullName
    if ($revisionTypeName -notmatch '(?i)(ItemRevision|Revision)$') {
        throw "A revisao recebida nao e um objeto de revisao valido. Tipo recebido: '$revisionTypeName'."
    }

    # --- 3. Normalizar os dados do Dataset ---
    $datasetId            = $DatasetName.Trim()
    $datasetRevisionClean = $DatasetRevision.Trim().ToUpperInvariant()

    if ($datasetId -eq "") { throw "O nome do Dataset ficou vazio para '$ItemCode'." }
    if ($datasetRevisionClean -eq "") { throw "A revisao do Dataset ficou vazia para '$ItemCode'." }

    # --- 4. Localizar ImportarPDF: (1) id do Dataset, (2) revisao, (3) caminho do PDF,
    #        (4) objeto de revisao, (5) indicador booleano exigido pelo importador ---
    $importMethod = Get-TeamcenterMethod -MethodName "ImportarPDF" -ParameterCount 5

    if ($Details) {
        Write-Host "  Assinatura selecionada de ImportarPDF:" -ForegroundColor Cyan
        $importParameters = $importMethod.GetParameters()
        for ($i = 0; $i -lt $importParameters.Count; $i++) {
            Write-Host ("    [{0}] {1} {2}" -f $i, $importParameters[$i].ParameterType.FullName, $importParameters[$i].Name) -ForegroundColor DarkGray
        }
        Write-Host "    Retorno: $($importMethod.ReturnType.FullName)" -ForegroundColor DarkGray
    }

    $invokeArguments = [object[]]::new(5)
    $invokeArguments[0] = [string]$datasetId
    $invokeArguments[1] = [string]$datasetRevisionClean
    $invokeArguments[2] = [string]$FilePath
    $invokeArguments[3] = $Revision
    $invokeArguments[4] = [bool]$true

    if ($Details) {
        Write-Host "  Dados enviados ao ImportarPDF:" -ForegroundColor Cyan
        Write-Host "    Dataset ID:       '$datasetId'" -ForegroundColor Gray
        Write-Host "    Dataset Revision: '$datasetRevisionClean'" -ForegroundColor Gray
        Write-Host "    Arquivo:          '$FilePath'" -ForegroundColor Gray
        Write-Host "    Tipo da revisao:  '$revisionTypeName'" -ForegroundColor Gray
    }

    # --- 5. Importar (pode criar o Dataset de verdade; as validacoes locais ja terminaram) ---
    try { $importResult = $importMethod.Invoke($null, $invokeArguments) }
    catch {
        $root = $_.Exception; while ($null -ne $root.InnerException) { $root = $root.InnerException }
        throw "Falha ao importar o PDF para '$ItemCode': $($root.Message)"
    }

    $importResultText = ([string]$importResult).Trim()

    if ($importResultText -eq "") { throw "ImportarPDF nao retornou uma confirmacao para '$ItemCode'." }
    if ($importResultText -notmatch '^(?i:sim|true|1|yes)$') {
        throw "ImportarPDF nao confirmou a importacao de '$ItemCode'. Retorno recebido: '$importResultText'."
    }

    return $importResultText
}

# Importa o SLDDRW como Dataset (tipo, ferramenta e referencia vindos do .env)
# na revisao da folha NDT, usando ImportarOffice.
function Import-DcaNdtDrawing {
    param(
        [Parameter(Mandatory)]$Revision,
        [Parameter(Mandatory)][string]$DatasetName,
        [Parameter(Mandatory)][string]$DatasetRevision,
        [Parameter(Mandatory)]$DrawingEntry,
        [Parameter(Mandatory)][string]$TemporaryFolder
    )

    # --- 1. Configuracao obrigatoria do .env ---
    $datasetType = ([string]$env:DCA_TC_NDT_DRAWING_DATASET_TYPE).Trim()
    $toolUsed    = ([string]$env:DCA_TC_NDT_DRAWING_TOOL).Trim()
    $reference   = ([string]$env:DCA_TC_NDT_DRAWING_REFERENCE).Trim()

    foreach ($pair in @(
            @("DCA_TC_NDT_DRAWING_DATASET_TYPE", $datasetType),
            @("DCA_TC_NDT_DRAWING_TOOL", $toolUsed),
            @("DCA_TC_NDT_DRAWING_REFERENCE", $reference)
        )) {
        if ([string]::IsNullOrWhiteSpace([string]$pair[1])) { throw "$($pair[0]) nao esta configurado no .env." }
    }

    # --- 2. Garantir o SLDDRW localmente (download do Vault se preciso) ---
    $drawingSourcePath = ([string]$DrawingEntry.FullName).Trim()
    $drawingPath = $null

    if (Test-Path -LiteralPath $drawingSourcePath -PathType Leaf) { $drawingPath = $drawingSourcePath }
    else {
        Write-Info "Baixando o desenho NDT do Vault..."

        $vault = Get-DcaVault
        if ($null -eq $vault) { throw "Nao foi possivel obter a conexao com o Vault para baixar o desenho NDT." }

        $parentFolder = $null
        $pdmFile = $vault.GetFileFromPath($drawingSourcePath, [ref]$parentFolder)

        if ($null -eq $pdmFile) { throw "O desenho NDT nao foi encontrado no Vault: '$drawingSourcePath'." }
        if ($null -eq $parentFolder) { throw "A pasta do desenho NDT nao foi encontrada no Vault." }

        $fileVersion = 0
        $folderId = $parentFolder.ID

        # Versao 0 baixa a versao mais recente do arquivo.
        $pdmFile.GetFileCopy(0, [ref]$fileVersion, [ref]$folderId, 0, "")

        $drawingPath = [string]$pdmFile.GetLocalPath($parentFolder.ID)

        if ($Details) { Write-Info "Desenho baixado na versao ${fileVersion}: $drawingPath" }
    }

    if ([string]::IsNullOrWhiteSpace($drawingPath) -or -not (Test-Path -LiteralPath $drawingPath -PathType Leaf)) {
        throw "O desenho NDT nao ficou disponivel localmente: '$drawingSourcePath'."
    }

    # --- 3. Copia local com nome simples (sem espaco nem colchetes) ---
    $temporaryDrawingPath = Join-Path -Path $TemporaryFolder -ChildPath ($DatasetName + [System.IO.Path]::GetExtension($drawingPath))
    Copy-Item -LiteralPath $drawingPath -Destination $temporaryDrawingPath -Force

    $temporaryDrawingFile = Get-Item -LiteralPath $temporaryDrawingPath -ErrorAction Stop
    if ($temporaryDrawingFile.Length -le 0) { throw "A copia local do desenho NDT esta vazia: '$temporaryDrawingPath'." }

    # --- 4. Localizar ImportarGD.Controller.Functions.ImportarOffice (7 parametros) ---
    $functionsType = [System.AppDomain]::CurrentDomain.GetAssemblies() |
        ForEach-Object { try { $_.GetTypes() } catch { @() } } |
        Where-Object { $_.FullName -eq "ImportarGD.Controller.Functions" } | Select-Object -First 1
    if ($null -eq $functionsType) { throw "O tipo ImportarGD.Controller.Functions nao foi encontrado." }

    $importMethod = $functionsType.GetMethods([System.Reflection.BindingFlags]::Public -bor [System.Reflection.BindingFlags]::Static) |
        Where-Object { $_.Name -eq "ImportarOffice" -and $_.GetParameters().Count -eq 7 } | Select-Object -First 1
    if ($null -eq $importMethod) { throw "A sobrecarga ImportarOffice com 7 parametros nao foi encontrada." }

    $revisionObject = $Revision.PSObject.BaseObject
    if ($null -eq $revisionObject) { $revisionObject = $Revision }

    Write-Info "Importando o desenho NDT..."

    if ($Details) {
        Write-Host "  Dados enviados ao ImportarOffice:" -ForegroundColor Cyan
        Write-Host "    Dataset ID:       '$DatasetName'" -ForegroundColor DarkGray
        Write-Host "    Dataset Revision: '$DatasetRevision'" -ForegroundColor DarkGray
        Write-Host "    Arquivo:          '$temporaryDrawingPath'" -ForegroundColor DarkGray
        Write-Host "    Dataset Type:     '$datasetType'" -ForegroundColor DarkGray
        Write-Host "    ToolUsed:         '$toolUsed'" -ForegroundColor DarkGray
        Write-Host "    Reference:        '$reference'" -ForegroundColor DarkGray
    }

    # --- 5. Executar (cada argumento convertido e atribuido por posicao, sem wrappers PSObject) ---
    $invokeArguments = [object[]]::new(7)
    $invokeArguments[0] = [string]$DatasetName
    $invokeArguments[1] = [string]$DatasetRevision
    $invokeArguments[2] = [string]$temporaryDrawingFile.FullName
    $invokeArguments[3] = $revisionObject
    $invokeArguments[4] = [string]$datasetType
    $invokeArguments[5] = [string]$toolUsed
    $invokeArguments[6] = [string]$reference

    try { $importResult = $importMethod.Invoke($null, $invokeArguments) }
    catch {
        $root = $_.Exception; while ($null -ne $root.InnerException) { $root = $root.InnerException }
        throw "Falha no ImportarOffice para '$DatasetName': $($root.Message)"
    }

    # O ImportarOffice pode exibir erro em janela e retornar normalmente:
    # confirma que um Dataset diferente do PDF foi anexado a revisao.
    $drawingDatasets = @(
        Show-DcaTeamcenterRevisionDatasets -Revision $revisionObject |
            Where-Object { [string]$_.BusinessType -notmatch '(?i)^PDF$' -and [string]$_.TypeName -notmatch '(?i)\.PDF$' }
    )
    if ($drawingDatasets.Count -eq 0) { throw "O ImportarOffice nao anexou um Dataset de desenho para '$DatasetName'." }

    $importResultText = ([string]$importResult).Trim()
    if ($Details) { Write-Host "  Retorno do ImportarOffice: '$importResultText'" }

    # Sucesso real: "Sim" + espacos + "Dataset criado no Teamcenter".
    if ($importResultText -notmatch '(?i)^sim\b') { throw "O ImportarOffice nao criou o Dataset de '$DatasetName'. Retorno: '$importResultText'." }

    return $importResultText
}

# ============================================================
# VINCULO DO DESENHO NDT A PASTA NDT DO DCA PROCESSO
# ============================================================

function Get-DcaModelObjectUid {
    param($ModelObject)

    if ($null -eq $ModelObject) { return "" }

    try { return ([string]$ModelObject.Uid).Trim() }
    catch { return "" }
}

# Carrega propriedades de um objeto e devolve os erros do servico.
function Update-DcaModelObjectProperties {
    param(
        [Parameter(Mandatory)]$ModelObject,
        [Parameter(Mandatory)][string[]]$PropertyNames
    )

    if ($null -ne $ModelObject.PSObject.BaseObject) { $ModelObject = $ModelObject.PSObject.BaseObject }

    $dataManagementService = Get-TeamcenterDataManagementService

    $getPropertiesMethod = $dataManagementService.GetType().GetMethods() |
        Where-Object { $_.Name -ieq "GetProperties" -and $_.GetParameters().Count -eq 2 } | Select-Object -First 1
    if ($null -eq $getPropertiesMethod) { throw "DataManagementService.GetProperties nao foi encontrado." }

    $objectType = $getPropertiesMethod.GetParameters()[0].ParameterType.GetElementType()
    $objectArray = [System.Array]::CreateInstance($objectType, 1)
    $objectArray.SetValue($ModelObject, 0)

    $arguments = [object[]]::new(2)
    $arguments[0] = $objectArray
    $arguments[1] = [string[]]$PropertyNames

    $response = $getPropertiesMethod.Invoke($dataManagementService, $arguments)
    if ($null -eq $response) { return @() }

    return @(Get-TeamcenterServiceErrors -ServiceData $response)
}

# Cria uma relacao (GRM) entre dois objetos com DataManagementService.CreateRelations.
function New-DcaTeamcenterRelation {
    param(
        [Parameter(Mandatory)]$PrimaryObject,
        [Parameter(Mandatory)]$SecondaryObject,
        [Parameter(Mandatory)][string]$RelationType
    )

    if ($null -ne $PrimaryObject.PSObject.BaseObject)   { $PrimaryObject = $PrimaryObject.PSObject.BaseObject }
    if ($null -ne $SecondaryObject.PSObject.BaseObject) { $SecondaryObject = $SecondaryObject.PSObject.BaseObject }

    $dataManagementService = Get-TeamcenterDataManagementService

    $createRelationsMethod = $dataManagementService.GetType().GetMethods() | Where-Object {
        if ($_.Name -ine "CreateRelations" -or $_.GetParameters().Count -ne 1) { return $false }
        $parameterType = $_.GetParameters()[0].ParameterType
        $parameterType.IsArray -and $parameterType.GetElementType().Name -ieq "Relationship"
    } | Select-Object -First 1
    if ($null -eq $createRelationsMethod) { throw "DataManagementService.CreateRelations nao foi encontrado." }

    $relationshipType = $createRelationsMethod.GetParameters()[0].ParameterType.GetElementType()
    $relationship = [System.Activator]::CreateInstance($relationshipType)

    $memberValues = [ordered]@{
        PrimaryObject   = $PrimaryObject
        SecondaryObject = $SecondaryObject
        RelationType    = [string]$RelationType
        ClientId        = [string]"DcaNdtPasta"
    }

    $memberFlags = [System.Reflection.BindingFlags]::Public -bor [System.Reflection.BindingFlags]::Instance -bor [System.Reflection.BindingFlags]::IgnoreCase
    $memberTypes = [System.Reflection.MemberTypes]::Property -bor [System.Reflection.MemberTypes]::Field

    foreach ($memberName in $memberValues.Keys) {
        $member = $relationshipType.GetMember($memberName, $memberTypes, $memberFlags) | Select-Object -First 1
        if ($null -eq $member) { throw "O membro '$memberName' nao foi encontrado em '$($relationshipType.FullName)'." }

        if ($member -is [System.Reflection.PropertyInfo]) { $member.SetValue($relationship, $memberValues[$memberName], $null) }
        else { $member.SetValue($relationship, $memberValues[$memberName]) }
    }

    $relationshipArray = [System.Array]::CreateInstance($relationshipType, 1)
    $relationshipArray.SetValue($relationship, 0)

    $arguments = [object[]]::new(1)
    $arguments[0] = $relationshipArray

    try { $response = $createRelationsMethod.Invoke($dataManagementService, $arguments) }
    catch {
        $root = $_.Exception; while ($null -ne $root.InnerException) { $root = $root.InnerException }
        throw "Falha ao criar a relacao '$RelationType': $($root.Message)"
    }

    # A resposta pode ser o proprio ServiceData ou conter um.
    $serviceData = $response
    if ($null -ne $response) {
        $serviceDataProperty = $response.GetType().GetProperty("ServiceData")
        if ($null -ne $serviceDataProperty) {
            $nestedServiceData = $serviceDataProperty.GetValue($response, $null)
            if ($null -ne $nestedServiceData) { $serviceData = $nestedServiceData }
        }
    }

    if ($null -ne $serviceData) {
        $serviceErrors = @(Get-TeamcenterServiceErrors -ServiceData $serviceData)
        if ($serviceErrors.Count -gt 0) { throw "O Teamcenter recusou a relacao '$RelationType': $($serviceErrors -join ' | ')" }
    }
}

# Depois de importar o SLDDRW na Folha NDT, procura o DCA Processo de mesmo codigo
# e relaciona o Dataset do desenho a Pasta NDT dele (relacao GD5PastaNDT).
# Nao lanca excecao: problemas viram aviso.
function Add-DcaNdtDrawingToProcessFolder {
    param(
        [Parameter(Mandatory)]$NdtRevision,
        [Parameter(Mandatory)][string]$ProcessItemCode,
        [string]$RelationName = "GD5PastaNDT"
    )

    $processCode = $ProcessItemCode.Trim()

    try {
        $ndtRevisionObject = $NdtRevision.PSObject.BaseObject
        if ($null -eq $ndtRevisionObject) { $ndtRevisionObject = $NdtRevision }

        # --- 1. Dataset do desenho na revisao da Folha NDT ---
        $datasetType = ([string]$env:DCA_TC_NDT_DRAWING_DATASET_TYPE).Trim()

        $drawingDataset = @(
            Show-DcaTeamcenterRevisionDatasets -Revision $ndtRevisionObject | Where-Object { [string]$_.BusinessType -ieq $datasetType }
        ) | Select-Object -First 1

        if ($null -eq $drawingDataset) { throw "O Dataset '$datasetType' nao foi encontrado na revisao da Folha NDT." }

        # --- 2. DCA Processo de mesmo codigo, escolhido pelo tipo do Item ---
        if ($Details) { Write-Host "  Procurando o DCA Processo '$processCode' para vincular o desenho NDT..." -ForegroundColor Cyan }

        $processMatch = Find-DcaProcessRevisionByCode -ItemCode $processCode

        if ($null -eq $processMatch -or $null -eq $processMatch.Revision) {
            Write-Warn "Nenhum DCA Processo com o codigo '$processCode' foi encontrado. O desenho NDT nao foi vinculado a uma Pasta NDT."
            return [PSCustomObject]@{ Status = "ProcessoNaoEncontrado" }
        }

        $processRevision = $processMatch.Revision.PSObject.BaseObject
        if ($null -eq $processRevision) { $processRevision = $processMatch.Revision }

        # --- 3. ID da revisao do Processo (para as mensagens) ---
        $null = @(Update-DcaModelObjectProperties -ModelObject $processRevision -PropertyNames @("item_revision_id"))
        $processRevisionId = ([string](Get-TeamcenterModelPropertyText -ModelObject $processRevision -PropertyName "item_revision_id")).Trim()

        # --- 4. O desenho ja esta na pasta? (compara por UID; sem UID, pelo object_string) ---
        $drawingUid = Get-DcaModelObjectUid $drawingDataset.Object

        $matchesDrawing = {
            param($RelatedEntry)
            $relatedUid = Get-DcaModelObjectUid $RelatedEntry.Object
            if ($drawingUid -and $relatedUid) { return ($relatedUid -eq $drawingUid) }
            return ([string]$RelatedEntry.ObjectString -ieq [string]$drawingDataset.ObjectString)
        }

        $existingObjects = @(Show-DcaTeamcenterRevisionDatasets -Revision $processRevision -RelationNames @($RelationName))

        if (@($existingObjects | Where-Object { & $matchesDrawing $_ }).Count -gt 0) {
            if ($Details) { Write-Host "  O desenho NDT ja esta vinculado a Pasta NDT do Processo '$processCode/$processRevisionId'." -ForegroundColor DarkGray }
            return [PSCustomObject]@{ Status = "JaVinculado"; Target = "$processCode/$processRevisionId" }
        }

        # --- 5. Criar a relacao Processo -> Dataset do desenho ---
        New-DcaTeamcenterRelation -PrimaryObject $processRevision -SecondaryObject $drawingDataset.Object -RelationType $RelationName

        # --- 6. Confirmar ---
        $objectsAfter = @(Show-DcaTeamcenterRevisionDatasets -Revision $processRevision -RelationNames @($RelationName))

        if (@($objectsAfter | Where-Object { & $matchesDrawing $_ }).Count -gt 0) {
            if ($Details) { Write-Host "  O desenho NDT foi vinculado a Pasta NDT do Processo '$processCode/$processRevisionId'." -ForegroundColor DarkGray }
            return [PSCustomObject]@{ Status = "Vinculado"; Target = "$processCode/$processRevisionId" }
        }

        Write-Warn "A relacao com a Pasta NDT foi solicitada, mas nao foi possivel confirma-la. Confira no Teamcenter."
        return [PSCustomObject]@{ Status = "NaoConfirmado" }
    }
    catch {
        $root = $_.Exception; while ($null -ne $root.InnerException) { $root = $root.InnerException }

        Write-Warn "O desenho NDT foi importado, mas nao foi vinculado a Pasta NDT do Processo '$processCode': $($root.Message)"

        return [PSCustomObject]@{ Status = "Erro"; ErrorMessage = [string]$root.Message }
    }
}

# Localiza o DCA Processo pelo codigo, sem perguntar ao usuario. Usa a saved query e
# fica so com o Item do tipo configurado em *_PROCESS_ITEM_TYPE no .env; itens de
# outro tipo com o mesmo codigo (por exemplo Design) sao ignorados.
function Find-DcaProcessRevisionByCode {
    param([Parameter(Mandatory)][string]$ItemCode)

    $envPrefix = if ($script:TeamcenterEnvironment -eq "Processo") { "DCA_TC_PROCESS_PROCESS" } else { "DCA_TC_TEST_PROCESS" }

    $configuredType = ([string][System.Environment]::GetEnvironmentVariable("${envPrefix}_ITEM_TYPE")).Trim()
    if ($configuredType -eq "") { $configuredType = "GD5_DCA_PROCESSO" }

    # object_type devolve o nome de exibicao ("DCA PROCESSO") e o .env tem o nome
    # interno (GD5_DCA_PROCESSO): os dois sao normalizados.
    $normalizeType = { param($TypeText) ([string]$TypeText).Trim().ToUpperInvariant() -replace '^GD5_', '' -replace '_', ' ' }
    $expectedType = & $normalizeType $configuredType

    $candidates = @(Find-DcaTeamcenterItemBySavedQuery -ItemCode $ItemCode.Trim().ToUpperInvariant())

    foreach ($candidate in $candidates) {
        $candidateItem = $candidate.Item
        if ($null -eq $candidateItem) { continue }

        $null = @(Update-DcaModelObjectProperties -ModelObject $candidateItem -PropertyNames @("object_type"))

        $candidateType = & $normalizeType (Get-TeamcenterModelPropertyText -ModelObject $candidateItem -PropertyName "object_type")

        if ($Details) { Write-Host "  Candidato '$($candidate.ObjectUid)': tipo '$candidateType' (esperado '$expectedType')." -ForegroundColor DarkGray }

        if ($candidateType -ne $expectedType) { continue }

        $candidateRevision = Get-TeamcenterRevision -Item $candidateItem
        if ($null -eq $candidateRevision) { continue }

        return [PSCustomObject]@{ Item = $candidateItem; Revision = $candidateRevision; ItemType = $candidateType }
    }

    return $null
}

# Localiza todas as Folhas NDT do codigo informado; itens de outros tipos com o
# mesmo codigo sao ignorados.
function Find-DcaNdtRevisionsByCode {
    param([Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$ItemCode)

    $ndtItemCode = $ItemCode.Trim().ToUpperInvariant() + "-NDT"

    $envPrefix = if ($script:TeamcenterEnvironment -eq "Processo") { "DCA_TC_PROCESS_NDT" } else { "DCA_TC_TEST_NDT" }

    $configuredType = ([string][System.Environment]::GetEnvironmentVariable("${envPrefix}_ITEM_TYPE")).Trim()
    if ($configuredType -eq "") { $configuredType = "GD5_DCA_NDT" }

    # object_type pode devolver o nome de exibicao e o .env o nome interno do tipo.
    $normalizeType = { param($TypeText) ([string]$TypeText).Trim().ToUpperInvariant() -replace '^GD5_', '' -replace '_', ' ' }
    $expectedType = & $normalizeType $configuredType

    $candidates = @(Find-DcaTeamcenterItemBySavedQuery -ItemCode $ndtItemCode)

    $results = [System.Collections.Generic.List[object]]::new()

    # A Saved Query pode devolver mais de uma entrada para o mesmo Item.
    $knownItemUids = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

    foreach ($candidate in $candidates) {
        if ($null -eq $candidate -or $null -eq $candidate.Item) { continue }

        $candidateItem = $candidate.Item
        if ($null -ne $candidateItem.PSObject.BaseObject) { $candidateItem = $candidateItem.PSObject.BaseObject }

        $null = @(Update-DcaModelObjectProperties -ModelObject $candidateItem -PropertyNames @("object_type"))

        $candidateType = & $normalizeType (Get-TeamcenterModelPropertyText -ModelObject $candidateItem -PropertyName "object_type")

        if ($Details) { Write-Host "  Candidato NDT '$($candidate.ObjectUid)': tipo '$candidateType' (esperado '$expectedType')." -ForegroundColor DarkGray }

        if ($candidateType -ne $expectedType) { continue }

        $candidateRevision = Get-TeamcenterRevision -Item $candidateItem
        if ($null -eq $candidateRevision) { continue }
        if ($null -ne $candidateRevision.PSObject.BaseObject) { $candidateRevision = $candidateRevision.PSObject.BaseObject }

        $itemUid = Get-DcaModelObjectUid -ModelObject $candidateItem
        if (-not [string]::IsNullOrWhiteSpace($itemUid) -and -not $knownItemUids.Add($itemUid)) { continue }

        $results.Add([PSCustomObject]@{ Item = $candidateItem; Revision = $candidateRevision; ItemType = $candidateType; ItemUid = $itemUid })
    }

    return $results.ToArray()
}

function Show-DcaNdtImportLocation {
    param([Parameter(Mandatory)]$Location)

    Write-Host ""
    Write-Host ("  Onde a folha NDT {0} foi importada:" -f $Location.SourceCode) -ForegroundColor Green
    Write-Host ("  " + ("-" * 68)) -ForegroundColor DarkGray

    Write-Host ("    Ambiente:  Teamcenter de {0}" -f $Location.Environment) -ForegroundColor White
    Write-Host ("    Item:      {0}   (tipo {1})" -f $Location.ItemCode, $Location.ItemType) -ForegroundColor White
    Write-Host ("    Revisao:   {0}   (tipo {1})" -f $Location.RevisionId, $Location.RevisionType) -ForegroundColor White

    Write-Host ""
    Write-Host "    Conteudo da revisao no Teamcenter:" -ForegroundColor Cyan

    foreach ($entry in @($Location.Contents)) {
        $kind = if ([string]$entry.BusinessType -match '(?i)^PDF$') { "PDF    " } else { "Desenho" }
        Write-Host ("      [{0}] {1}   tipo: {2}   relacao: {3}" -f $kind, $entry.ObjectName, $entry.BusinessType, $entry.Relation) -ForegroundColor Gray
    }

    Write-Host ""
    Write-Host "    Origem dos arquivos (PDM):" -ForegroundColor Cyan
    Write-Host ("      PDF:     {0}" -f $Location.PdfSource) -ForegroundColor DarkGray
    Write-Host ("      Desenho: {0}" -f $Location.DrawingSource) -ForegroundColor DarkGray

    if (-not [string]::IsNullOrWhiteSpace([string]$Location.Workflow)) {
        Write-Host ""
        Write-Host ("    Workflow:  {0}" -f $Location.Workflow) -ForegroundColor Cyan
    }
}