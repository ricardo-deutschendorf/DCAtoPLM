# DCAtoPLM

Import PDF documents from a local DCA vault into Siemens Teamcenter.

This project was created for PDF files stored in a local vault. The source-code
placeholders must be replaced with the values from the target company before
use.

```text
C:\VAULT_ROOT
```

The application searches the vault, lets the user select a document, creates the
corresponding Teamcenter item and revision, and imports the selected PDF into the
new revision.

> [!IMPORTANT]
> The integration was developed and tested for **Siemens Teamcenter 2312**.
> It may work with other Teamcenter versions, but compatibility with other
> versions has not been confirmed.

## Required changes before use

This project contains environment-specific settings. Before using it in another
company, vault, PDM installation, or Teamcenter environment, review and update
the following values:

| What to review | Where to change it | What to configure |
| --- | --- | --- |
| Local vault path | `start_DCAtoPLM.bat` and `$SearchRoot` in `import_dcaPdfToTeamcenter.ps1` | Replace `C:\VAULT_ROOT` with the local folder containing the documents. |
| PDM vault name | `$VaultName` in `import_dcaPdfToTeamcenter.ps1` or `DCA_VAULT_NAME` | Replace `VAULT_NAME` with the exact SolidWorks PDM vault name. |
| PDM library | `$PdmLibraryPath` or `DCA_PDM_LIB` | Replace `C:\PATH\TO\Interop.EdmLib.dll` with the installed library path. |
| PDM credentials | `$VaultCredentialPath` or `DCA_VAULT_CREDENTIAL` | Replace `<VAULT_CREDENTIAL_FILE>` with a protected `Export-Clixml` credential file when required. |
| Teamcenter connection | `DCA_TC_URL`, `DCA_TC_USER`, and `DCA_TC_PASSWORD` | Replace the Teamcenter placeholders with the target URL and credentials. |
| Teamcenter integration assembly | `Confirm-TeamcenterImporter` in `functions/teamcenter_functions.ps1` | Replace `C:\PATH\TO\Importar GD.exe` with the installed assembly path. |
| Teamcenter business objects | `Get-DcaTypeConfiguration` in `functions/teamcenter_functions.ps1` | Replace item types, revision types, property names, client name, and default revision. |
| Documentation folder | `Select-DcaPdfByCode` in `import_dcaPdfToTeamcenter.ps1` | Replace `DOCUMENTATION` with the parent folder used by the target vault. |
| Document category folders | `$categoryDefinitions` in `import_dcaPdfToTeamcenter.ps1` | Replace `ORIGINAL_DRAWINGS`, `PROCESS_DOCUMENTS`, and `EXTERNAL_STANDARDS`. |

The source code intentionally contains neutral placeholders. The application
will not work until the placeholders are replaced or the equivalent values are
provided through environment variables and command-line parameters.

Before a production import:

1. Configure the environment-specific values listed above.
2. Confirm that the account has permission to create Teamcenter items and revisions.
3. Run the application with `-Preview`.
4. Verify the search result, document type, item name, revision, and target configuration.
5. Perform a real import only after the preview is correct.

Never commit real passwords, tokens, credential files, or internal Teamcenter
URLs to the repository.

When the application starts, it displays a **CONFIGURATION WARNINGS** section
for every required setting that is still using a placeholder or has not been
configured. These warnings are intentionally shown before the search begins.
They identify the setting to change without displaying passwords or other
secret values.

## When to use this tool

Use DCAtoPLM when a PDF document already exists in the DCA vault and must be
registered in Teamcenter as a new item and revision.

The workflow is intended for these document categories:

- **DCA Process** documents.
- **DCA Original Drawing** documents.
- **DCA External Standard** documents.

The tool is useful when the source document must be found by its code, reviewed
before import, associated with the correct Teamcenter business object, and
attached to the created revision without manually repeating the entire process.

It is not a general-purpose document migration tool. The Teamcenter business
objects, revision rules, PDF naming conventions, and PDM folder categories are
specific to this implementation.

## What the application does

1. Reads an exact code or a wildcard search pattern.
2. Searches the PDM vault through the SolidWorks PDM API when available.
3. Falls back to the local file system when the PDM API cannot be used.
4. Displays matching PDF files and their metadata.
5. Lets the user select a document when multiple files match.
6. Determines the document type, code, title, and revision.
7. Requests the Teamcenter item name and revision information when required.
8. Shows a final summary before making changes.
9. Creates the Teamcenter item and first revision.
10. Validates and imports the PDF into the created revision.

If the requested item already exists in Teamcenter, the process stops and reports
the duplicate. It does not generate an alternative item code.

## Supported document categories

| Source folder | Document type | Teamcenter item | Teamcenter revision |
| --- | --- | --- | --- |
| `ORIGINAL_DRAWINGS` | DCA Original Drawing | `ITEM_TYPE_ORIGINAL_DRAWING` | `REVISION_TYPE_ORIGINAL_DRAWING` |
| `PROCESS_DOCUMENTS` | DCA Process | `ITEM_TYPE_PROCESS` | `REVISION_TYPE_PROCESS` |
| `EXTERNAL_STANDARDS` | DCA External Standard | `ITEM_TYPE_EXTERNAL_STANDARD` | `REVISION_TYPE_EXTERNAL_STANDARD` |

## Repository structure

```text
DCAtoPLM/
├── import_dcaPdfToTeamcenter.ps1
├── functions/
│   └── teamcenter_functions.ps1
├── start_DCAtoPLM.bat
└── README.md
```

| File | Responsibility |
| --- | --- |
| `import_dcaPdfToTeamcenter.ps1` | Main workflow, search, selection, validation, prompts, and import orchestration. |
| `functions/teamcenter_functions.ps1` | Teamcenter connection, object creation, error handling, revision lookup, and PDF import. |
| `start_DCAtoPLM.bat` | Recommended launcher using `C:\VAULT_ROOT` as the configured search root. |

## Requirements

The execution environment must provide:

1. Windows PowerShell compatible with the scripts.
2. Siemens Teamcenter 2312 access.
3. Permission to authenticate, create items and revisions, and import PDFs.
4. SolidWorks PDM access when vault API search is required.
5. `Interop.EdmLib.dll` on the computer running the script.
6. The `Importar GD.exe` Teamcenter integration assembly in the configured location.
7. Access to the local DCA folder structure.

The project does not install external dependencies. Run it with a user account
that has the required permissions; administrator privileges should not be
necessary.

## Expected DCA vault structure

The default search root is:

```text
C:\VAULT_ROOT
```

The script looks for a documentation directory and the following categories:

```text
C:\VAULT_ROOT\
└── DOCUMENTATION\
    ├── ORIGINAL_DRAWINGS\
    ├── PROCESS_DOCUMENTS\
    └── EXTERNAL_STANDARDS\
```

Subfolders are searched recursively. Only files with the `.pdf` extension are
considered.

The placeholder folder names are part of the current implementation. If the
vault uses different names, update the folder mappings in
`import_dcaPdfToTeamcenter.ps1` before running the tool.

## Running the application

### Recommended launcher

Run:

```text
start_DCAtoPLM.bat
```

The launcher starts PowerShell with `C:\VAULT_ROOT` as the search root. The script
requests the source code first and requests the item name after a PDF has been
selected.

### Direct PowerShell execution

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\import_dcaPdfToTeamcenter.ps1
```

### Execution with parameters

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\import_dcaPdfToTeamcenter.ps1 `
  -SearchRoot "C:\VAULT_ROOT" `
  -SourceCode "AMS 22*" `
  -VaultName "DCA"
```

## Parameters

| Parameter | Type | Default | Description |
| --- | --- | --- | --- |
| `-SearchRoot` | `string` | `C:\VAULT_ROOT` | Local root of the configured vault. |
| `-SourceCode` | `string` | Empty | Exact code or search pattern. Prompts interactively when omitted. |
| `-ItemName` | `string` | Empty | Initial Teamcenter item name. Prompts after document selection when omitted. |
| `-VaultName` | `string` | `VAULT_NAME` | SolidWorks PDM vault name. |
| `-PdmLibraryPath` | `string` | Local configuration | Path to `Interop.EdmLib.dll`. |
| `-VaultCredentialPath` | `string` | Placeholder | Credential file exported with `Export-Clixml`. |
| `-NoVaultApi` | `switch` | Disabled | Skips the PDM API and searches only local files. |
| `-Preview` | `switch` | Disabled | Searches and displays the summary without connecting to Teamcenter or creating objects. |

### Search examples

Search for all documents beginning with `1000359`:

```powershell
.\import_dcaPdfToTeamcenter.ps1 -SourceCode "1000359*"
```

Search only files currently available on the local disk:

```powershell
.\import_dcaPdfToTeamcenter.ps1 -NoVaultApi
```

Run a preview for an external standard:

```powershell
.\import_dcaPdfToTeamcenter.ps1 `
  -SourceCode "AMS 2248" `
  -Preview
```

## Where to change the configuration

### 1. Local DCA vault path

The default path is defined in two places:

- `start_DCAtoPLM.bat`: change `-SearchRoot "C:\VAULT_ROOT"`.
- `import_dcaPdfToTeamcenter.ps1`: change the default value of `$SearchRoot`.

For a one-time change, prefer the command-line parameter:

```powershell
.\import_dcaPdfToTeamcenter.ps1 -SearchRoot "D:\OtherVault"
```

### 2. SolidWorks PDM vault name

The placeholder vault name is `VAULT_NAME` in `import_dcaPdfToTeamcenter.ps1`:

```powershell
[string]$VaultName = "VAULT_NAME"
```

For a temporary override:

```powershell
$env:DCA_VAULT_NAME = "VAULT_NAME"
```

The environment variable takes precedence over the script default.

### 3. PDM library and credential file

Configure these values in `import_dcaPdfToTeamcenter.ps1`, or override them
without editing the script:

```powershell
$env:DCA_PDM_LIB = "C:\Path\To\Interop.EdmLib.dll"
$env:DCA_VAULT_CREDENTIAL = "C:\Secure\vault-credential.xml"
```

The credential file should be created with `Export-Clixml` and should not be
committed or shared between machines.

### 4. Teamcenter connection data

Teamcenter connection settings are read from environment variables:

```powershell
$env:DCA_TC_URL = "<TEAMCENTER_URL>"
$env:DCA_TC_USER = "<TEAMCENTER_USER>"
$env:DCA_TC_PASSWORD = "<TEAMCENTER_PASSWORD>"
```

Set these values before starting the application. Do not place real passwords,
internal URLs, tokens, or other confidential data in this README or in a
versioned script.

The connection defaults and environment-variable handling are implemented in
`functions/teamcenter_functions.ps1`, in `Get-TeamcenterSettings`. If the
Teamcenter environment requires a different authentication setup, this is the
primary function to update.

### 5. Teamcenter integration executable

The helper loads the Teamcenter integration assembly associated with
`Importar GD.exe`. If the executable is installed in a different location,
update the configured path in `functions/teamcenter_functions.ps1`.

This integration depends on the methods and types exposed by the installed
assembly. Changes to that assembly may require corresponding code changes.

### 6. Document categories and business objects

The document-to-Teamcenter mapping is defined in
`functions/teamcenter_functions.ps1`, in `Get-DcaTypeConfiguration`.

Update that function if the target environment uses different:

- Teamcenter item types.
- Teamcenter revision types.
- Client properties.
- Revision properties.
- Default revision identifiers.

## Document-specific rules

### DCA Original Drawing

Configured source folder:

```text
ORIGINAL_DRAWINGS\
```

Teamcenter configuration:

- Item type: `ITEM_TYPE_ORIGINAL_DRAWING`
- Revision type: `REVISION_TYPE_ORIGINAL_DRAWING`
- Client property: `CLIENT_PROPERTY = CLIENT_NAME`
- Additional property: `CLIENT_REVISION_PROPERTY`

The client revision can be one or two characters, such as `B` or `BA4`.
When the value ends in `A0` through `A4`, the script separates the client
revision from the paper format.

### DCA Process

Configured source folder:

```text
PROCESS_DOCUMENTS\
```

Teamcenter configuration:

- Item type: `ITEM_TYPE_PROCESS`
- Revision type: `REVISION_TYPE_PROCESS`
- Client property: `CLIENT_PROPERTY = CLIENT_NAME`
- Additional properties:
  - `CLIENT_REVISION_PROPERTY`
  - `INTERNAL_REVISION_PROPERTY`

The expected revision format contains one or two client-revision characters
followed by one internal digit:

```text
BA4
AA4
--4
```

For `BA4`, the complete value is used as the revision identifier, `BA` is
stored in `gd5revcliente`, and `4` is stored in `gd5revinterna`.

### DCA External Standard

Configured source folder:

```text
EXTERNAL_STANDARDS\
```

Teamcenter configuration:

- Item type: `ITEM_TYPE_EXTERNAL_STANDARD`
- Revision type: `REVISION_TYPE_EXTERNAL_STANDARD`
- Client property: `CLIENT_PROPERTY = CLIENT_NAME`
- Default revision identifier: `DEFAULT_REVISION`

The script recognizes common AMS naming patterns, including:

```text
AMS 2248
AMS 2759-3
AMS 2440C
AMS-STD-2175
AMS2470
```

When possible, the code is separated from the title. The extracted title is
used as the initial item name, and the user can keep it or enter another name.

## Operational workflow

### Stage 1 — Enter search criteria

Enter an exact code or a pattern using `*` and `?`:

```text
1000359-2
1000359*
AMS 22*
```

### Stage 2 — Select the document

The script:

1. Locates the documentation folder.
2. Queries the PDM vault or local disk.
3. Filters for PDF files.
4. Extracts code, title, and revision from the file name.
5. Displays numbered results.
6. Selects the PDF automatically when exactly one result is found.
7. Requests a selection when multiple results are found.

After selection:

- The user can press Enter to keep a suggested item name.
- A name is required when no name can be extracted.
- The revision is extracted when available.
- The revision is requested for document types that do not provide one.
- External standards use revision `000`.

### Stage 3 — Create the item and import the PDF

Before changing Teamcenter, the script displays a summary and requires the
user to type `YES`.

After confirmation:

1. The item and first revision are created.
2. Duplicate items are reported and the process stops.
3. The created revision is retrieved when necessary.
4. The PDF is copied to a temporary directory.
5. The temporary copy is validated.
6. The PDF is imported into the Teamcenter revision.
7. The result displays the created code, item name, and import confirmation.

## Preview mode

`-Preview` performs the search, selection, interpretation, and summary, but it
does not:

- connect to Teamcenter;
- create an item;
- create a revision;
- copy the PDF for import;
- import the document.

Use preview mode before a production import to verify the vault structure,
search pattern, document type, title, and revision interpretation.

## File naming conventions

For documents with a revision in the file name, the expected pattern is:

```text
CODE[REVISION].pdf
```

Examples:

```text
1000359-2[BA4].PDF
1000359[BA4].pdf
```

External standards can contain a code followed by a title:

```text
AMS 2248 CHEMICAL CHECK ANALYSIS LIMITS.pdf
```

The script interprets the example as:

```text
Code: AMS 2248
Name: CHEMICAL CHECK ANALYSIS LIMITS
```

## Search behavior

- `*` is converted to a multi-character search pattern.
- `?` is converted to a single-character search pattern.
- Exact searches are expanded to a contains-style PDM search.
- PDM API results are used when the API is available and authenticated.
- Local recursive enumeration is used as a fallback.
- A file available only on the PDM server may not appear in local fallback mode.
- A selected PDF that is not cached locally may be downloaded through PDM
  `GetFileCopy`, when the API is available.

Temporary files are stored under the current Windows user's temporary
directory:

```text
%TEMP%\DCAtoPLM
```

## Security and credentials

- Never commit passwords, tokens, credential files, or internal URLs.
- Prefer environment variables for Teamcenter connection settings.
- Protect `Export-Clixml` credential files with the Windows user and computer
  that created them.
- Do not copy credential files between machines without an approved secure
  process.
- Use an account with only the permissions required for this operation.
- Review the repository before sharing it outside the authorized environment.

## Error handling

The process exits with a non-zero code when an operation fails. Common errors
include:

- DCA search root not found.
- Documentation folder not found.
- No supported document category found.
- PDF not found locally or in the PDM cache.
- PDM authentication failure.
- Teamcenter connection or authentication failure.
- Invalid revision for the selected document type.
- Item already exists in Teamcenter.
- Item or revision creation failure.
- PDF copy, validation, or import failure.

When the PDM API fails during a search, the application reports the fallback to
the local file system. Documents that exist only on the server may be omitted.

## Local syntax validation

Validate the PowerShell syntax without running the import workflow:

```powershell
$files = @(
  ".\import_dcaPdfToTeamcenter.ps1",
  ".\functions\teamcenter_functions.ps1"
)

foreach ($file in $files) {
  $tokens = $null
  $errors = $null
  [System.Management.Automation.Language.Parser]::ParseFile(
    (Resolve-Path $file),
    [ref]$tokens,
    [ref]$errors
  ) | Out-Null

  if ($errors.Count -gt 0) {
    $errors | ForEach-Object { $_.Message }
    exit 1
  }
}

Write-Host "PowerShell syntax OK"
```

## Compatibility and limitations

- The supported and tested Teamcenter version is Siemens Teamcenter 2312.
- Other Teamcenter versions may work, but compatibility is not confirmed.
- The PDM behavior depends on the installed SolidWorks PDM client and
  `Interop.EdmLib.dll`.
- The Teamcenter behavior depends on the installed `Importar GD.exe` assembly.
- Business object names and properties are specific to the target Teamcenter
  environment.
- The application requires the DCA folder categories and file naming patterns
  described in this document unless the source code is adapted.

## Current status

The workflow supports creation and PDF import for:

- DCA Process.
- DCA Original Drawing.
- DCA External Standard, including code and title extraction from common AMS
  file names.

Use `-Preview` before a real import when working with a new vault, a new PDM
client installation, or a different Teamcenter environment.
