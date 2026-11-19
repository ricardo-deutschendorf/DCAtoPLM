# ============================================================
# CRIACAO DE ITEM E REVISAO NO TEAMCENTER
# ============================================================
# Prepara e executa a criacao de um Item e de sua revisao por meio de
# DataManagementService.CreateObjects.
#   Antes: valida codigo, nome, ambiente e revisao; obtem a configuracao
#          do tipo DCA; localiza CreateIn/CreateInput; prepara as
#          propriedades; monta o CompoundCreateInput e valida o documento.
#   Depois: interpreta erros SOA; recupera Item e revisao criados; remove
#          wrappers do PowerShell; grava aprovador e data na revisao de
#          Processo ou NDT (SetProperties) e devolve os objetos.
# Esta funcao pode criar objetos de verdade no Teamcenter: toda validacao
# deve acontecer antes de CreateObjects.
# ============================================================
function New-DcaTeamcenterItem {
    param(
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$SourceCode,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$ItemName,
        [string]$ClientRevision,
        [Parameter(Mandatory = $false)][AllowEmptyString()][string]$Approver,
        [Parameter(Mandatory = $false)][AllowEmptyString()][string]$ApprovalDate,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$DocumentType
    )

    # --- 1. Validar e normalizar os dados de entrada ---
    # Padrao de duplicidade: vale para excecoes e para erros parciais do SOA.
    $duplicatePattern = '(?i)already exists|ja existe|duplicate|not unique|is not unique'

    $sourceCodeClean = $SourceCode.Trim().ToUpperInvariant()
    $itemNameClean   = $ItemName.Trim()
    $approverClean   = ([string]$Approver).Trim()
    $approvalDateTeamcenter = ""

    if ([string]::IsNullOrWhiteSpace($sourceCodeClean)) { throw "SourceCode ficou vazio." }
    if ([string]::IsNullOrWhiteSpace($itemNameClean))   { throw "ItemName ficou vazio." }
    if ([string]::IsNullOrWhiteSpace($script:TeamcenterEnvironment)) {
        throw "O ambiente do Teamcenter ainda nao foi identificado. Execute Connect-Teamcenter antes da criacao."
    }

    # Busca um tipo pelo nome completo em todos os assemblies carregados.
    $findType = {
        param($fullName)
        [System.AppDomain]::CurrentDomain.GetAssemblies() |
            ForEach-Object { try { $_.GetTypes() } catch { @() } } |
            Where-Object { $_.FullName -eq $fullName } | Select-Object -First 1
    }

    # --- 2. Obter a configuracao tecnica do tipo DCA ---
    $typeConfiguration = Get-DcaTypeConfiguration -DocumentType $DocumentType -ClientRevision $ClientRevision -TeamcenterEnvironment $script:TeamcenterEnvironment

    if ($Details) {
        Write-Host ""
        Write-Host "  Ambiente Teamcenter: $($typeConfiguration.Environment)" -ForegroundColor Gray
        Write-Host "  Tipo do Item:        $($typeConfiguration.ItemType)" -ForegroundColor Gray
        Write-Host "  Tipo da Revisao:     $($typeConfiguration.RevisionType)" -ForegroundColor Gray
    }

    $itemType                = $typeConfiguration.ItemType
    $revisionType            = $typeConfiguration.RevisionType
    $clientProperty          = $typeConfiguration.ClientProperty
    $clientValue             = $typeConfiguration.ClientValue
    $teamcenterRevisionId    = $typeConfiguration.TeamcenterRevisionId
    $revisionExtraProperties = $typeConfiguration.RevisionProperties

    if ([string]::IsNullOrWhiteSpace($teamcenterRevisionId)) { throw "Revision ID ficou vazio para '$DocumentType'." }

    # --- 3. Localizar CreateObjects e os tipos de entrada ---
    # CreateIn e CreateInput vem da assinatura real de CreateObjects (reflexao), sem
    # depender de namespace ou versao especifica das bibliotecas SOA.
    $dataManagementService = Get-TeamcenterDataManagementService

    $createObjectsMethod = $dataManagementService.GetType().GetMethods() |
        Where-Object { $_.Name -eq "CreateObjects" -and $_.GetParameters().Count -eq 1 } | Select-Object -First 1
    if ($null -eq $createObjectsMethod) { throw "Metodo CreateObjects nao encontrado." }

    $createInArrayType = $createObjectsMethod.GetParameters()[0].ParameterType
    if (-not $createInArrayType.IsArray) { throw "O parametro de CreateObjects nao e um array." }

    $createInType = $createInArrayType.GetElementType()
    if ($null -eq $createInType) { throw "Tipo CreateIn nao identificado." }

    $createInputField = $createInType.GetField("Data", [System.Reflection.BindingFlags]::Public -bor [System.Reflection.BindingFlags]::Instance -bor [System.Reflection.BindingFlags]::IgnoreCase)
    if ($null -eq $createInputField) { throw "Campo Data nao encontrado em CreateIn." }

    $createInputType = $createInputField.FieldType
    if ($null -eq $createInputType) { throw "Tipo do CreateInput nao identificado." }

    # --- 4. Preparar as propriedades da revisao ---
    # Folhas NDT recebem o sufixo -NDT para nao conflitar com o item de Processo de mesmo codigo base.
    $candidateCode = $sourceCodeClean
    if ($DocumentType -eq "NDT" -and $candidateCode -notmatch '(?i)-NDT$') { $candidateCode = "$candidateCode-NDT" }

    # Toda revisao recebe item_revision_id, object_name e object_desc, alem das propriedades
    # do tipo (Original: gd5revcliente; Processo: gd5revcliente e gd5revinterna; Norma: nenhuma).
    $revisionProperties = @{
        "item_revision_id" = $teamcenterRevisionId
        "object_name"      = $itemNameClean
        "object_desc"      = $itemNameClean
    }
    foreach ($extraKey in $revisionExtraProperties.Keys) { $revisionProperties[$extraKey] = $revisionExtraProperties[$extraKey] }

    # Aprovacao do PDM (Processo e NDT): validada aqui e gravada em SetProperties depois do
    # CreateObjects, direto nas propriedades da revisao (nunca em comentarios ou object_desc).
    if ($DocumentType -in @("Processo", "NDT")) {

        if ($Details) {
            if ($approverClean -eq "") { Write-Host "  Aprovador do PDM: <vazio>" -ForegroundColor DarkGray }
            else {
                Write-Host "  Aprovador do PDM preparado:" -ForegroundColor Cyan
                Write-Host "    gd5AprovadorPDM = '$approverClean'" -ForegroundColor Gray
            }
        }

        $approvalDateClean = ([string]$ApprovalDate).Trim()

        if ($approvalDateClean -ne "") {
            $parsedApprovalDate = [datetime]::MinValue
            if (-not [datetime]::TryParseExact($approvalDateClean, "dd/MM/yyyy", [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::None, [ref]$parsedApprovalDate)) {
                throw "A data de aprovacao '$approvalDateClean' nao possui o formato esperado dd/MM/yyyy."
            }

            # SetProperties recebe a data como texto, produzido pelo conversor oficial da
            # biblioteca SOA para respeitar o formato de data esperado pelo Teamcenter.
            $propertyType = & $findType "Teamcenter.Soa.Client.Model.Property"
            if ($null -eq $propertyType) { throw "O tipo Teamcenter.Soa.Client.Model.Property nao foi encontrado para converter a data de aprovacao." }

            $toDateStringMethods = @(
                $propertyType.GetMethods([System.Reflection.BindingFlags]::Public -bor [System.Reflection.BindingFlags]::Static) |
                    Where-Object { $_.Name -ieq "ToDateString" -and $_.GetParameters().Count -eq 1 }
            )
            if ($toDateStringMethods.Count -eq 0) { throw "O metodo Property.ToDateString nao foi encontrado nas bibliotecas SOA carregadas." }

            $toDateStringMethod = $toDateStringMethods | Where-Object { $_.GetParameters()[0].ParameterType -eq [datetime] } | Select-Object -First 1
            if ($null -eq $toDateStringMethod) { $toDateStringMethod = $toDateStringMethods | Select-Object -First 1 }

            $dateParameterType = $toDateStringMethod.GetParameters()[0].ParameterType

            if ($Details) {
                Write-Host "  Conversor de data localizado:" -ForegroundColor Cyan
                Write-Host "    Tipo:   $($propertyType.FullName)" -ForegroundColor DarkGray
                Write-Host "    Metodo: $($toDateStringMethod.Name)" -ForegroundColor DarkGray
                Write-Host "    Entrada: $($dateParameterType.FullName)" -ForegroundColor DarkGray
            }

            $dateArgument = if ($dateParameterType -eq [datetime]) { $parsedApprovalDate }
            elseif ($dateParameterType -eq [datetimeoffset]) {
                [System.DateTimeOffset]::new($parsedApprovalDate, [System.TimeZoneInfo]::Local.GetUtcOffset($parsedApprovalDate))
            }
            else { throw "Property.ToDateString possui um parametro nao suportado: '$($dateParameterType.FullName)'." }

            try { $approvalDateTeamcenter = ([string]$toDateStringMethod.Invoke($null, @($dateArgument))).Trim() }
            catch {
                $root = $_.Exception; while ($null -ne $root.InnerException) { $root = $root.InnerException }
                throw "Nao foi possivel converter a data '$approvalDateClean' com Property.ToDateString: $($root.Message)"
            }

            if ($Details) {
                Write-Host "  Texto produzido por Property.ToDateString:" -ForegroundColor Cyan
                Write-Host "    '$approvalDateTeamcenter'" -ForegroundColor Yellow
            }
            if ($approvalDateTeamcenter -eq "") { throw "Property.ToDateString retornou uma data vazia para '$approvalDateClean'." }
            if ($Details) {
                Write-Host "  Data de aprovacao do PDM para o Teamcenter:" -ForegroundColor Cyan
                Write-Host "    gd5AprovadorPDMData = '$approvalDateTeamcenter'" -ForegroundColor Gray
            }
        }
    }

    # Propriedades inteiras vao em IntProps; as demais ficam em StringProps.
    $integerPropertyNames = @(Get-DcaIntegerPropertyNames)

    $revisionInput = New-DcaCreateInputObject -InputType $createInputType -BoName $revisionType -Properties $revisionProperties -IntegerPropertyNames $integerPropertyNames
    if ($null -eq $revisionInput) { throw "revisionInput ficou NULL para o tipo '$revisionType'." }

    if ($Details) {
        Write-Host "  revisionInput criado: $($revisionInput.GetType().FullName)" -ForegroundColor DarkGray
        Write-Host "  BoName da revisao: $([string]$revisionInput.BoName)" -ForegroundColor DarkGray
        Write-Host "  Propriedades da revisao:" -ForegroundColor Cyan
        foreach ($name in ($revisionInput.StringProps.Keys | Sort-Object)) {
            Write-Host ("    {0} = '{1}'" -f $name, $revisionInput.StringProps[$name]) -ForegroundColor Gray
        }
        if ($null -ne $revisionInput.IntProps) {
            foreach ($name in ($revisionInput.IntProps.Keys | Sort-Object)) {
                Write-Host ("    {0} = {1}  (inteiro)" -f $name, $revisionInput.IntProps[$name]) -ForegroundColor Gray
            }
        }
    }

    # --- 5. Preparar as propriedades do Item (o nome vale para Item e revisao) ---
    $itemProperties = @{
        "item_id"     = $candidateCode
        "object_name" = $itemNameClean
        "object_desc" = $itemNameClean
    }

    # A propriedade de cliente so e enviada com nome e valor configurados.
    if (-not [string]::IsNullOrWhiteSpace([string]$clientProperty) -and -not [string]::IsNullOrWhiteSpace([string]$clientValue)) {
        $itemProperties[$clientProperty] = $clientValue
    }

    if ($Details) {
        Write-Host "  Propriedades do Item:" -ForegroundColor Cyan
        foreach ($name in ($itemProperties.Keys | Sort-Object)) {
            Write-Host ("    {0} = '{1}'" -f $name, $itemProperties[$name]) -ForegroundColor Gray
        }
    }

    $itemInput = New-DcaCreateInputObject -InputType $createInputType -BoName $itemType -Properties $itemProperties
    if ($null -eq $itemInput) { throw "itemInput ficou NULL para o tipo '$itemType'." }

    # --- 6. Montar o CompoundCreateInput: Item e revisao seguem na mesma chamada ---
    $revisionInputArray = [System.Array]::CreateInstance($createInputType, 1)
    $revisionInputArray.SetValue($revisionInput, 0)

    $compoundInput = [System.Collections.Hashtable]::new()
    $compoundInput["revision"] = $revisionInputArray

    if ($Details) { Write-Host "  Tipo tecnico do CreateInput: $($itemInput.GetType().FullName)" -ForegroundColor DarkGray }
    Set-DcaObjectMemberValue -InputObject $itemInput -MemberName "CompoundCreateInput" -Value $compoundInput

    # --- 7. Montar a entrada final: CreateIn recebe o Item, que ja leva a revisao ---
    $createIn = [System.Activator]::CreateInstance($createInType)
    if ($null -eq $createIn) { throw "Nao foi possivel criar createIn." }

    $createIn.ClientId = [string]"CreateDcaItem"
    $createIn.Data = $itemInput

    $createInArray = [System.Array]::CreateInstance($createInType, 1)
    $createInArray.SetValue($createIn, 0)

    # --- 8. Validar as propriedades antes da criacao (ja separadas em StringProps e IntProps) ---
    if ($DocumentType -eq "Processo") {
        # Processo exige gd5revcliente (1 ou 2 caracteres), gd5revinterna (1 digito) e
        # item_revision_id com a revisao completa da FP (ex.: 03033 ou --0).
        $revisionClient   = ([string]$revisionInput.StringProps["gd5revcliente"]).Trim()
        $revisionInternal = Get-DcaCreateInputPropertyText -InputObject $revisionInput -PropertyName "gd5revinterna"
        $finalRevisionId  = ([string]$revisionInput.StringProps["item_revision_id"]).Trim()

        if ($revisionClient -eq "") { throw "gd5revcliente ficou vazio no objeto de revisao antes do CreateObjects." }
        if ($revisionClient -notmatch '^[A-Z0-9-]{1,2}$') {
            throw "gd5revcliente possui valor incompatível com o Teamcenter: '$revisionClient'. O limite do campo Revisao Cliente e de 2 caracteres."
        }
        if ($revisionInternal -eq "") { throw "gd5revinterna ficou vazio no objeto de revisao antes do CreateObjects." }
        if ($revisionInternal -notmatch '^[0-9]$') { throw "gd5revinterna possui valor invalido: '$revisionInternal'. Era esperado um digito." }
        if ($finalRevisionId -eq "") { throw "item_revision_id ficou vazio no objeto de revisao antes do CreateObjects." }

        if ($Details) {
            Write-Host "  Dados da revisao que serao enviados:" -ForegroundColor Cyan
            Write-Host "    item_revision_id = '$finalRevisionId'" -ForegroundColor Gray
            Write-Host "    gd5revcliente    = '$revisionClient'" -ForegroundColor Gray
            Write-Host "    gd5revinterna    = '$revisionInternal'" -ForegroundColor Gray
        }
    }

    # As propriedades adicionais definidas pela configuracao do tipo devem continuar preenchidas.
    foreach ($extraKey in $revisionExtraProperties.Keys) {
        $extraValueText = Get-DcaCreateInputPropertyText -InputObject $revisionInput -PropertyName $extraKey
        if ([string]::IsNullOrWhiteSpace($extraValueText)) { throw "A propriedade '$extraKey' ficou vazia na revisao." }
    }

    # O Teamcenter controla sequence_id; enviar manualmente pode rejeitar a criacao ou gerar sequencia errada.
    if ($revisionInput.StringProps.ContainsKey("sequence_id")) { throw "sequence_id nao deve ser enviado." }

    # --- 9. Executar a criacao (a partir daqui objetos podem ser criados de verdade) ---
    # O array vai embrulhado em object[1], senao o Invoke o desmembraria em argumentos.
    $invokeArguments = [object[]]::new(1); $invokeArguments[0] = $createInArray
    $createResponse = $null

    try { $createResponse = $createObjectsMethod.Invoke($dataManagementService, $invokeArguments) }
    catch {
        # A mensagem original do servico SOA esta nas excecoes internas.
        $root = $_.Exception; while ($null -ne $root.InnerException) { $root = $root.InnerException }
        $errorMessage = $root.Message

        if ($errorMessage -match $duplicatePattern) {
            if ($Details) {
                Write-Host "  Verificacao de duplicidade:" -ForegroundColor Yellow
                Write-Host "    Codigo:          '$candidateCode'" -ForegroundColor DarkGray
                Write-Host "    Item existente:  True" -ForegroundColor DarkGray
                Write-Host "    Modo solicitado: CreateItem" -ForegroundColor DarkGray
                Write-Host "    Acao sugerida:   executar com -RecoverExisting" -ForegroundColor DarkGray
            }
            throw "O item '$candidateCode' ja existe no Teamcenter. Mensagem original do servidor: $errorMessage"
        }

        throw "Falha ao executar CreateObjects para '$candidateCode': $errorMessage"
    }

    # --- 10. Validar a resposta (erros parciais podem existir mesmo com resposta valida) ---
    if ($null -eq $createResponse) { throw "CreateObjects retornou NULL." }

    $serviceData   = $createResponse.ServiceData
    $serviceErrors = @(Get-TeamcenterServiceErrors -ServiceData $serviceData)

    if ($serviceErrors.Count -gt 0) {
        $joinedErrors = $serviceErrors -join " | "
        if ($joinedErrors -match $duplicatePattern) { throw "O item '$candidateCode' ja existe no Teamcenter. Mensagem original do servidor: $joinedErrors" }
        throw "O Teamcenter rejeitou a criacao: $joinedErrors"
    }

    # --- 11. Recuperar Item e revisao (a resposta traz tambem objetos auxiliares) ---
    $createdObjects = @(Get-DcaCreatedObjects -CreateResponse $createResponse -ServiceData $serviceData)

    $createdItem = $createdObjects |
        Where-Object { $null -ne $_ -and ($_.GetType().Name -eq "Item" -or $_.GetType().FullName -match '\.Item$') } |
        Select-Object -First 1

    # Inclui tipos especializados derivados de ItemRevision.
    $createdRevision = $createdObjects |
        Where-Object { $null -ne $_ -and $_.GetType().FullName -match '(?i)(ItemRevision|Revision)$' } |
        Select-Object -First 1

    if ($null -eq $createdItem) { throw "CreateObjects nao retornou o Item criado. Objetos retornados: $($createdObjects.Count)." }
    if ($null -eq $createdRevision) {
        throw "CreateObjects nao retornou a revisao criada para '$candidateCode/$teamcenterRevisionId'. Objetos retornados: $($createdObjects.Count)."
    }

    # --- 12. Remover os wrappers do PowerShell antes de retornar ---
    if ($null -ne $createdItem.PSObject.BaseObject)     { $createdItem = $createdItem.PSObject.BaseObject }
    if ($null -ne $createdRevision.PSObject.BaseObject) { $createdRevision = $createdRevision.PSObject.BaseObject }

    # --- 13. Gravar aprovador e data na revisao criada: SetProperties(PropInfo[], string[]) ---
    if ($DocumentType -in @("Processo", "NDT")) {

        $propInfoType = & $findType "Teamcenter.Services.Strong.Core._2010_09.DataManagement.PropInfo"
        if ($null -eq $propInfoType) { throw "O tipo DataManagement.PropInfo nao foi encontrado." }

        $nameValueStructType = & $findType "Teamcenter.Services.Strong.Core._2010_09.DataManagement.NameValueStruct1"
        if ($null -eq $nameValueStructType) { throw "O tipo DataManagement.NameValueStruct1 nao foi encontrado." }

        $newNameValue = {
            param($name, $value)
            $entry = [System.Activator]::CreateInstance($nameValueStructType)
            $entry.Name = [string]$name
            $entry.Values = [string[]]@($value)
            $entry.PSObject.BaseObject
        }

        $nameValueEntries = [System.Collections.Generic.List[object]]::new()
        if ($approverClean -ne "") { $nameValueEntries.Add((& $newNameValue "gd5AprovadorPDM" $approverClean)) }
        if (-not [string]::IsNullOrWhiteSpace([string]$approvalDateTeamcenter)) { $nameValueEntries.Add((& $newNameValue "gd5AprovadorPDMData" $approvalDateTeamcenter)) }

        # So atualiza a revisao quando houver dados de aprovacao.
        if ($nameValueEntries.Count -gt 0) {

            $nameValueArray = [System.Array]::CreateInstance($nameValueStructType, $nameValueEntries.Count)
            for ($i = 0; $i -lt $nameValueEntries.Count; $i++) { $nameValueArray.SetValue($nameValueEntries[$i], $i) }

            $propertyInfo = [System.Activator]::CreateInstance($propInfoType)
            $propertyInfo.Object = $createdRevision
            $propertyInfo.VecNameVal = $nameValueArray
            $propertyInfo.Timestamp = [datetime]::MinValue   # sem controle otimista de alteracao

            $propInfoArray = [System.Array]::CreateInstance($propInfoType, 1)
            $propInfoArray.SetValue($propertyInfo.PSObject.BaseObject, 0)

            $setPropertiesMethod = $dataManagementService.GetType().GetMethods() | Where-Object {
                $p = $_.GetParameters()
                $_.Name -eq "SetProperties" -and $p.Count -eq 2 -and
                $p[0].ParameterType.FullName -eq "Teamcenter.Services.Strong.Core._2010_09.DataManagement.PropInfo[]" -and
                $p[1].ParameterType -eq [string[]]
            } | Select-Object -First 1
            if ($null -eq $setPropertiesMethod) { throw "A sobrecarga SetProperties(PropInfo[], string[]) nao foi encontrada." }

            if ($Details) {
                Write-Host ""
                Write-Host "  Dados que serao aplicados na revisao:" -ForegroundColor Cyan
                Write-Host "    Revisao: $candidateCode/$teamcenterRevisionId" -ForegroundColor Gray
                foreach ($entry in $nameValueEntries) { Write-Host "    $($entry.Name) = '$(@($entry.Values) -join ", ")'" -ForegroundColor White }
                Write-Host "  Estrutura de SetProperties:" -ForegroundColor Cyan
                Write-Host "    PropInfo: $($propertyInfo.GetType().FullName)" -ForegroundColor DarkGray
                Write-Host "    Objeto alvo: $($createdRevision.GetType().FullName)" -ForegroundColor DarkGray
                Write-Host "    Quantidade de propriedades: $($nameValueArray.Length)" -ForegroundColor DarkGray
                Write-Host "    Sobrecarga: SetProperties(PropInfo[], string[])" -ForegroundColor DarkGray
            }

            $setPropertiesArguments = [object[]]::new(2)
            $setPropertiesArguments[0] = $propInfoArray
            $setPropertiesArguments[1] = [string[]]@()   # nenhuma opcao adicional

            try { $setPropertiesResponse = $setPropertiesMethod.Invoke($dataManagementService, $setPropertiesArguments) }
            catch {
                $root = $_.Exception; while ($null -ne $root.InnerException) { $root = $root.InnerException }
                throw "Falha ao gravar os dados de aprovacao na revisao '$candidateCode/$teamcenterRevisionId': $($root.Message)"
            }

            if ($null -eq $setPropertiesResponse) { throw "SetProperties retornou NULL ao atualizar a revisao '$candidateCode/$teamcenterRevisionId'." }

            $setPropertiesServiceData = $setPropertiesResponse.Data
            if ($null -eq $setPropertiesServiceData) { throw "SetProperties nao retornou ServiceData ao atualizar '$candidateCode/$teamcenterRevisionId'." }

            $setPropertiesErrors = @(Get-TeamcenterServiceErrors -ServiceData $setPropertiesServiceData)
            if ($setPropertiesErrors.Count -gt 0) { throw "O Teamcenter rejeitou os dados de aprovacao: $($setPropertiesErrors -join ' | ')" }

            if ($Details) {
                $updatedNames = @($nameValueEntries | ForEach-Object { [string]$_.Name })
                Write-Host "  Propriedades de aprovacao gravadas na revisao ${candidateCode}/${teamcenterRevisionId}: $($updatedNames -join ', ')." -ForegroundColor Green
            }
        }
    }

    # --- 14. Retornar o destino criado ---
    return [PSCustomObject]@{
        Code     = $candidateCode
        Item     = $createdItem
        Revision = $createdRevision
    }
}