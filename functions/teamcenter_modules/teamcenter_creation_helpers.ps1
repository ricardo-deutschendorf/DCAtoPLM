# ============================================================
# FUNCOES AUXILIARES PARA CRIACAO NO TEAMCENTER
# ============================================================
# Prepara os tipos, propriedades e objetos usados na criacao de
# Items e revisoes no Teamcenter.
#   1. normaliza as revisoes e seleciona os tipos tecnicos conforme
#      o ambiente e o tipo DCA;
#   2. separa propriedades entre StringProps e IntProps;
#   3. cria e preenche objetos CreateInput (membros por reflexao);
#   4. interpreta os objetos retornados por CreateObjects.
# Aqui so se preparam e interpretam objetos; a chamada efetiva de
# CreateObjects fica em teamcenter_creation.ps1.
# ============================================================

# Normaliza a revisao do Desenho Original e remove o sufixo interno
# (A0 a A4) quando o cartao apresentar esse formato.
function Get-DcaClientRevisionInfo {
    param([string]$ClientRevision)

    $value = ([string]$ClientRevision).Trim().ToUpperInvariant()
    $revision = $value

    if ($value -match '^(?<Revision>[A-Z0-9]{1,10})A[0-4]$') { $revision = $Matches["Revision"] }

    return [PSCustomObject]@{ Original = $value; Revision = $revision }
}

# Retorna a configuracao tecnica para criar o Item e a revisao: tipos, propriedade
# e valor do cliente, item_revision_id e propriedades adicionais da revisao.
# Depende do ambiente ativo, do tipo do documento e da revisao do PDF ou do cartao.
function Get-DcaTypeConfiguration {
    param(
        [Parameter(Mandatory)][ValidateSet("Original", "Processo", "NormaExterna", "NDT")][string]$DocumentType,
        [string]$ClientRevision,
        [ValidateSet("Teste", "Processo")][string]$TeamcenterEnvironment
    )

    # --- 1. Determinar o ambiente (parametro > sessao conectada > .env) ---
    if ([string]::IsNullOrWhiteSpace($TeamcenterEnvironment)) {
        $TeamcenterEnvironment = if (-not [string]::IsNullOrWhiteSpace($script:TeamcenterEnvironment)) { $script:TeamcenterEnvironment }
                                 else { [string](Get-TeamcenterSettings).Environment }
    }
    if ($TeamcenterEnvironment -notin @("Teste", "Processo")) {
        throw "O ambiente do Teamcenter nao foi identificado. Ambiente recebido: '$TeamcenterEnvironment'."
    }

    # --- 2. Ler os tipos do ambiente: DCA_TC_<PROCESS|TEST>_<ORIGINAL|PROCESS|STANDARD|NDT>_<campo> ---
    $envPrefix = if ($TeamcenterEnvironment -eq "Processo") { "PROCESS" } else { "TEST" }
    $typeKey   = @{ Original = "ORIGINAL"; Processo = "PROCESS"; NormaExterna = "STANDARD"; NDT = "NDT" }[$DocumentType]
    $setting   = { param($field) [string][System.Environment]::GetEnvironmentVariable("DCA_TC_${envPrefix}_${typeKey}_$field") }

    $itemType       = & $setting "ITEM_TYPE"
    $revisionType   = & $setting "REVISION_TYPE"
    $clientProperty = & $setting "CLIENT_PROPERTY"
    $clientValue    = & $setting "CLIENT_VALUE"

    # --- 3. Bloquear a criacao se os nomes tecnicos estiverem vazios ou com marcadores ---
    if ([string]::IsNullOrWhiteSpace($itemType) -or $itemType -like "<*>") {
        throw "ItemType de '$DocumentType' ainda nao foi configurado para o ambiente '$TeamcenterEnvironment'."
    }
    if ([string]::IsNullOrWhiteSpace($revisionType) -or $revisionType -like "<*>") {
        throw "RevisionType de '$DocumentType' ainda nao foi configurado para o ambiente '$TeamcenterEnvironment'."
    }

    # --- 4. Desenho Original: a revisao normalizada e o item_revision_id e o valor de gd5revcliente ---
    if ($DocumentType -eq "Original") {
        $info = Get-DcaClientRevisionInfo -ClientRevision $ClientRevision

        if ([string]::IsNullOrWhiteSpace($info.Revision)) { throw "ClientRevision ficou vazia para '$DocumentType'." }
        if ($info.Revision.Length -gt 5) {
            throw "Revisao Cliente '$($info.Revision)' possui $($info.Revision.Length) caracteres. O limite configurado e 5."
        }

        return [PSCustomObject]@{
            Environment          = $TeamcenterEnvironment
            ItemType             = $itemType
            RevisionType         = $revisionType
            ClientProperty       = $clientProperty
            ClientValue          = $clientValue
            TeamcenterRevisionId = $info.Revision
            RevisionProperties   = @{ "gd5revcliente" = $info.Revision }
        }
    }

    # --- 5. Ficha de Processo: ultimo caractere = revisao interna (1 digito); o restante,
    #        ate 2 caracteres e podendo ter hifen (ex.: C-4), = revisao cliente.
    #        Para revisoes compostas de prototipo (ex.: 03033), os 2 primeiros
    #        caracteres sao gravados em gd5revcliente e o ultimo em gd5revinterna.
    #        O item_revision_id conserva a revisao completa da FP. ---
    if ($DocumentType -eq "Processo") {
        $raw = ([string]$ClientRevision).Trim().ToUpperInvariant()

        if ($raw -eq "") { throw "A revisao do Processo ficou vazia." }
        if ($raw.Length -lt 2) {
            throw "A revisao '$raw' nao possui caracteres suficientes para separar a revisao cliente da revisao interna."
        }

        $internalRevision = $raw.Substring($raw.Length - 1, 1).Trim()
        $clientRevision   = if ($raw.Length -in @(3, 4, 5)) {
            $raw.Substring(0, 2).Trim().ToUpperInvariant()
        } else {
            $raw.Substring(0, $raw.Length - 1).Trim().ToUpperInvariant()
        }

        if ($raw.Length -eq 5) {
            if ($raw -notmatch '^[A-Z0-9-]{4}[0-9]$') {
                throw "A revisao composta '$raw' possui formato invalido. Era esperado 4 caracteres seguidos de um digito interno."
            }
        }
        elseif ($raw.Length -in @(3, 4)) {
            if ($raw -notmatch '^[A-Z0-9-]{2}[A-Z0-9-]*[0-9]$') {
                throw "A revisao '$raw' possui formato invalido."
            }
        }

        if ($clientRevision.Length -gt 2 -or $clientRevision -notmatch '^[A-Z0-9-]{1,2}$') {
            throw "A revisao cliente '$clientRevision' extraida de '$raw' nao pode ser enviada ao Teamcenter. O campo Revisao Cliente aceita no maximo 2 caracteres."
        }
        if ($internalRevision -notmatch '^[0-9]$') {
            throw "A revisao interna '$internalRevision' e invalida. Era esperado exatamente um digito."
        }

        # As revisoes completas, como 03033 ou --0, sao o identificador da revisao.
        $revisionId = $raw

        if ($Details) {
            Write-Host "  Revisao recebida do cartao: [$raw]" -ForegroundColor DarkGray
            Write-Host "  Revisao cliente: [$clientRevision]" -ForegroundColor DarkGray
            Write-Host "  Revisao interna: [$internalRevision]" -ForegroundColor DarkGray
            Write-Host "  Revision ID do Teamcenter: [$revisionId]" -ForegroundColor Cyan
        }

        return [PSCustomObject]@{
            Environment          = $TeamcenterEnvironment
            ItemType             = $itemType
            RevisionType         = $revisionType
            ClientProperty       = $clientProperty
            ClientValue          = $clientValue
            TeamcenterRevisionId = $revisionId
            RevisionProperties   = @{ "gd5revcliente" = $clientRevision; "gd5revinterna" = $internalRevision }
        }
    }

    # --- 6. Folha NDT: a revisao do cartao vai direto como item_revision_id,
    #        sem gd5revcliente nem gd5revinterna ---
    if ($DocumentType -eq "NDT") {
        $ndtRevision = ([string]$ClientRevision).Trim().ToUpperInvariant()

        if ($ndtRevision -eq "") { throw "A revisao da Folha NDT ficou vazia. Confirme o valor da variavel Revision no cartao do PDM." }
        if ($ndtRevision.Length -gt 32) { throw "A revisao da Folha NDT possui mais de 32 caracteres: '$ndtRevision'." }
        if ($ndtRevision -notmatch '^[A-Z0-9.-]+$') {
            throw "A revisao da Folha NDT possui caracteres invalidos: '$ndtRevision'. Sao aceitos letras, numeros, ponto e hifen."
        }

        if ($Details) {
            Write-Host "  Configuracao da Folha NDT:" -ForegroundColor Cyan
            Write-Host "    Tipo do Item:    '$itemType'" -ForegroundColor DarkGray
            Write-Host "    Tipo da Revisao: '$revisionType'" -ForegroundColor DarkGray
            Write-Host "    Revision ID:     '$ndtRevision'" -ForegroundColor Cyan
        }

        return [PSCustomObject]@{
            Environment          = $TeamcenterEnvironment
            ItemType             = $itemType
            RevisionType         = $revisionType
            ClientProperty       = $clientProperty
            ClientValue          = $clientValue
            TeamcenterRevisionId = $ndtRevision
            DocumentRevision     = $ndtRevision
            RevisionProperties   = @{}
        }
    }

    # --- 7. Norma Externa: a revisao documental (ex.: REV-U) fica separada do item_revision_id,
    #        que precisa ter exatamente 3 digitos (padrao 001, ajustavel no .env) ---
    if ($DocumentType -eq "NormaExterna") {
        $standardRevision = ([string]$ClientRevision).Trim().ToUpperInvariant()

        if ($standardRevision -eq "") { throw "A revisao da Norma Externa ficou vazia." }
        if ($standardRevision -notmatch '^[A-Z0-9.-]{1,20}$') { throw "A revisao da Norma Externa possui formato invalido: '$standardRevision'." }

        $revisionId = ([string]$env:DCA_TC_STANDARD_INITIAL_REVISION).Trim()
        if ($revisionId -eq "") { $revisionId = "001" }
        if ($revisionId -notmatch '^[0-9]{3}$') {
            throw "DCA_TC_STANDARD_INITIAL_REVISION possui valor invalido: '$revisionId'. Era esperado exatamente tres numeros, por exemplo 001."
        }

        if ($Details) {
            Write-Host "  Revisao documental da Norma Externa: [$standardRevision]" -ForegroundColor DarkGray
            Write-Host "  Revision ID usado no Teamcenter: [$revisionId]" -ForegroundColor Cyan
        }

        return [PSCustomObject]@{
            Environment          = $TeamcenterEnvironment
            ItemType             = $itemType
            RevisionType         = $revisionType
            ClientProperty       = $clientProperty
            ClientValue          = $clientValue
            TeamcenterRevisionId = $revisionId
            DocumentRevision     = $standardRevision
            RevisionProperties   = @{}
        }
    }

    throw "Tipo de documento nao suportado: '$DocumentType'."
}

# Nomes das propriedades enviadas em IntProps (lista do .env). Vazio usa
# gd5revinterna; "none" desativa o envio de propriedades inteiras.
function Get-DcaIntegerPropertyNames {
    $configured = ([string]$env:DCA_TC_INTEGER_PROPERTIES).Trim()

    if ($configured -eq "") { return @("gd5revinterna") }
    if ($configured -ieq "none") { return @() }

    $names = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($part in ($configured -split '[|;,]')) {   # separadores aceitos: | ; ,
        if ($part.Trim() -ne "") { $null = $names.Add($part.Trim()) }
    }

    return @($names)
}

# Le uma propriedade do CreateInput (StringProps ou IntProps) sempre como texto,
# para simplificar as validacoes antes de CreateObjects.
function Get-DcaCreateInputPropertyText {
    param(
        [Parameter(Mandatory)][ValidateNotNull()]$InputObject,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$PropertyName
    )

    if ($null -ne $InputObject.StringProps -and $InputObject.StringProps.ContainsKey($PropertyName)) {
        return ([string]$InputObject.StringProps[$PropertyName]).Trim()
    }
    if ($null -ne $InputObject.IntProps -and $InputObject.IntProps.ContainsKey($PropertyName)) {
        return ([string]$InputObject.IntProps[$PropertyName]).Trim()
    }

    return ""
}

# Cria e preenche um CreateInput compativel com a API SOA: propriedades
# inteiras em IntProps e todas as demais em StringProps.
function New-DcaCreateInputObject {
    param(
        [Parameter(Mandatory)][type]$InputType,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$BoName,
        [Parameter(Mandatory)][hashtable]$Properties,
        [string[]]$IntegerPropertyNames = @()
    )

    # --- 1. Criar a instancia ---
    $inputObject = [System.Activator]::CreateInstance($InputType)
    if ($null -eq $inputObject) { throw "Nao foi possivel criar o CreateInput de '$BoName'." }
    $inputObject.BoName = $BoName

    # --- 2. Separar StringProps e IntProps ---
    $stringProps = [System.Collections.Hashtable]::new()
    $intProps    = [System.Collections.Hashtable]::new()

    foreach ($key in $Properties.Keys) {
        if ($key -in $IntegerPropertyNames) {
            $parsed = 0
            if (-not [int]::TryParse(([string]$Properties[$key]).Trim(), [ref]$parsed)) {
                throw "A propriedade inteira '$key' recebeu um valor invalido: '$($Properties[$key])'."
            }
            $intProps[$key] = [int]$parsed
        }
        else { $stringProps[$key] = [string]$Properties[$key] }
    }

    # --- 3. Aplicar ao CreateInput ---
    $inputObject.StringProps = $stringProps
    if ($intProps.Count -gt 0) { Set-DcaObjectMemberValue -InputObject $inputObject -MemberName "IntProps" -Value $intProps }
    if ($null -eq $inputObject.StringProps) { throw "StringProps ficou NULL no CreateInput de '$BoName'." }

    # NoEnumerate impede o PowerShell de decompor o objeto como colecao.
    Write-Output -NoEnumerate -InputObject $inputObject
}

# Reune os objetos criados, vindos da resposta direta de CreateObjects e do
# ServiceData, sem repeticoes.
function Get-DcaCreatedObjects {
    param($CreateResponse, $ServiceData)

    $createdObjects = [System.Collections.Generic.List[object]]::new()
    $add = { param($object) if ($null -ne $object -and -not $createdObjects.Contains($object)) { $createdObjects.Add($object) } }
    $publicInstance = [System.Reflection.BindingFlags]::Public -bor [System.Reflection.BindingFlags]::Instance

    # --- 1. Resposta direta: campos publicos de cada Output (listas ou objetos do modelo) ---
    if ($null -ne $CreateResponse -and $CreateResponse.PSObject.Properties["Output"]) {
        foreach ($entry in $CreateResponse.Output) {
            if ($null -eq $entry) { continue }

            foreach ($field in $entry.GetType().GetFields($publicInstance)) {
                $value = $field.GetValue($entry)
                if ($null -eq $value) { continue }

                if ($value -is [System.Collections.IEnumerable] -and $value -isnot [string]) { foreach ($item in $value) { & $add $item } }
                elseif ($value.GetType().FullName -like "Teamcenter.Soa.Client.Model.*") { & $add $value }
            }
        }
    }

    # --- 2. ServiceData: SizeOfCreatedObjects / GetCreatedObject ---
    if ($null -ne $ServiceData) {
        $methods = $ServiceData.GetType().GetMethods()
        $sizeMethod = $methods | Where-Object { $_.Name -ieq "SizeOfCreatedObjects" -and $_.GetParameters().Count -eq 0 } | Select-Object -First 1
        $getMethod  = $methods | Where-Object { $_.Name -ieq "GetCreatedObject" -and $_.GetParameters().Count -eq 1 } | Select-Object -First 1

        if ($null -ne $sizeMethod -and $null -ne $getMethod) {
            $createdCount = [int]$sizeMethod.Invoke($ServiceData, @())
            for ($i = 0; $i -lt $createdCount; $i++) { & $add ($getMethod.Invoke($ServiceData, @([int]$i))) }
        }
    }

    if ($Details) { Write-Host "  Quantidade de objetos criados: $($createdObjects.Count)" -ForegroundColor DarkGray }

    return $createdObjects.ToArray()
}

# Define um campo ou propriedade publica por reflexao (conforme a versao da
# API SOA, o mesmo membro aparece como campo ou como propriedade).
function Set-DcaObjectMemberValue {
    param(
        [Parameter(Mandatory)][ValidateNotNull()]$InputObject,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$MemberName,
        [Parameter(Mandatory)][ValidateNotNull()]$Value
    )

    $objectType = $InputObject.GetType()
    $bindingFlags = [System.Reflection.BindingFlags]::Public -bor [System.Reflection.BindingFlags]::Instance -bor [System.Reflection.BindingFlags]::IgnoreCase

    # --- 1. Como propriedade ---
    $property = $objectType.GetProperty($MemberName, $bindingFlags)
    if ($null -ne $property) {
        if (-not $property.CanWrite) { throw "A propriedade '$MemberName' existe em '$($objectType.FullName)', mas nao permite escrita." }
        $property.SetValue($InputObject, $Value, $null)
        return
    }

    # --- 2. Como campo ---
    $field = $objectType.GetField($MemberName, $bindingFlags)
    if ($null -ne $field) { $field.SetValue($InputObject, $Value); return }

    # --- 3. Nao existe: a mensagem lista os campos e propriedades do tipo ---
    $availableMembers = @(
        $objectType.GetMembers($bindingFlags) |
            Where-Object { $_.MemberType -eq [System.Reflection.MemberTypes]::Field -or $_.MemberType -eq [System.Reflection.MemberTypes]::Property } |
            ForEach-Object { $_.Name } | Sort-Object -Unique
    )

    throw "O membro '$MemberName' nao foi encontrado no tipo '$($objectType.FullName)'. Membros disponiveis: $($availableMembers -join ', ')"
}