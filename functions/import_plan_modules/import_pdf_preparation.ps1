# ============================================================
# PREPARACAO DO PDF PARA IMPORTACAO
# ============================================================
# Cria uma copia local validada do PDF antes do importador do
# Teamcenter. O PDF original nunca e alterado.
#   1. valida origem (caminho, extensao, tamanho);
#   2. garante a pasta DCA_TEMP_FOLDER;
#   3. normaliza o codigo usado no nome do arquivo;
#   4. substitui copias anteriores e copia o PDF;
#   5. valida tamanho e assinatura "%PDF-" da copia.
# ============================================================

function Copy-PdfToTemporaryFolder {
    param(
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$SourcePdfPath,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$ItemCode
    )

    # --- 1. PDF de origem ---
    $sourcePath = $SourcePdfPath.Trim()
    if ([string]::IsNullOrWhiteSpace($sourcePath)) { throw "O caminho do PDF de origem ficou vazio." }
    if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) { throw "PDF de origem nao encontrado: '$sourcePath'." }

    $sourceFile = Get-Item -LiteralPath $sourcePath -ErrorAction Stop
    if ($sourceFile.Extension -ine ".pdf") { throw "O arquivo de origem nao possui extensao PDF." }
    if ($sourceFile.Length -le 0) { throw "O PDF de origem esta vazio." }

    # --- 2. Pasta temporaria (DCA_TEMP_FOLDER, definida no .env) ---
    $temporaryFolder = ([string]$env:DCA_TEMP_FOLDER).Trim()
    if ([string]::IsNullOrWhiteSpace($temporaryFolder)) { throw "DCA_TEMP_FOLDER deve ser configurado no arquivo .env." }
    $null = New-Item -Path $temporaryFolder -ItemType Directory -Force -ErrorAction Stop

    # --- 3. Nome seguro: remove caracteres invalidos no Windows ---
    $safeItemCode = ($ItemCode.Trim() -replace '[\\/:*?"<>|]', '_').Trim().TrimEnd(".", " ")
    if ([string]::IsNullOrWhiteSpace($safeItemCode)) {
        throw "O codigo do Item ficou vazio depois da normalizacao do nome do arquivo."
    }

    # --- 4. Copia independente (substitui qualquer copia antiga) ---
    $temporaryFullPath = [System.IO.Path]::GetFullPath((Join-Path $temporaryFolder "$safeItemCode.pdf"))
    $sourceFullPath    = [System.IO.Path]::GetFullPath($sourceFile.FullName)

    if ($sourceFullPath -ieq $temporaryFullPath) {
        throw "O PDF de origem ja corresponde ao caminho temporario: '$temporaryFullPath'."
    }

    Write-Info "Preparando o PDF para importacao..."
    try {
        Remove-Item -LiteralPath $temporaryFullPath -Force -ErrorAction SilentlyContinue
        Copy-Item -LiteralPath $sourceFullPath -Destination $temporaryFullPath -Force -ErrorAction Stop
    }
    catch {
        Remove-Item -LiteralPath $temporaryFullPath -Force -ErrorAction SilentlyContinue
        throw "Nao foi possivel copiar o PDF para a pasta temporaria: $($_.Exception.Message)"
    }

    $temporaryFile = Get-Item -LiteralPath $temporaryFullPath -ErrorAction SilentlyContinue
    if ($null -eq $temporaryFile) { throw "O PDF nao foi criado na pasta temporaria." }

    # --- 5. Validar tamanho e assinatura ---
    if ($temporaryFile.Length -ne $sourceFile.Length) {
        throw (
            "O tamanho da copia temporaria e diferente do original. " +
            "Original: $($sourceFile.Length) bytes. Copia: $($temporaryFile.Length) bytes."
        )
    }

    # Abrir em modo leitura confirma que o arquivo nao esta bloqueado.
    $stream = [System.IO.File]::OpenRead($temporaryFullPath)
    try {
        $header = [byte[]]::new(5)
        if ($stream.Read($header, 0, 5) -lt 5) { throw "A copia temporaria e pequena demais para ser um PDF valido." }

        $pdfHeader = [System.Text.Encoding]::ASCII.GetString($header)
        if ($pdfHeader -ne "%PDF-") {
            throw "A copia temporaria nao possui uma assinatura PDF valida. Cabecalho encontrado: '$pdfHeader'."
        }
    }
    finally { $stream.Dispose() }

    if ($Details) { Write-Success "PDF copiado e validado na pasta temporaria." }

    return [string]$temporaryFile.FullName
}