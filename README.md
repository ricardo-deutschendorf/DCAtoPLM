# DCAtoPLM

> [!WARNING]
>
> Item and revision creation, batch processing, PDM search, folder search, PDF
> preparation, and workflow triggering have been implemented. PDF import behavior
> still depends on the installed Teamcenter integration assembly and must be
> validated in each target environment before production use.

Import PDF documents from a local SolidWorks PDM DCA vault into Siemens
Teamcenter.

DCAtoPLM searches the configured documentation vault, interprets document
metadata from PDF file names, creates the corresponding Teamcenter item and
revision, imports the PDF, and optionally starts a Teamcenter workflow according
to the current PDM state.

The application supports individual document searches, multiple searches in one
execution, multi-selection from search results, and complete folder imports.

> [!IMPORTANT]
> The integration was developed for **Siemens Teamcenter 2312**.
>
> Other Teamcenter versions may work, but compatibility has not been confirmed.
> Teamcenter business objects, properties, workflows, and integration assemblies
> are environment-specific and must be reviewed before use.

---

## Main features

- Search PDF documents through the SolidWorks PDM API.
- Fall back to the local file system when the PDM API is unavailable.
- Search partially without requiring `*`.
- Perform exact searches using an explicit search prefix, when configured.
- Submit multiple searches separated by commas.
- Select multiple PDFs from the same search result.
- Search folders throughout the complete documentation tree.
- Search folders using `*` and `?`.
- Select one or more folders from numbered results.
- Import all PDFs directly contained in selected folders.
- Prevent duplicate files from being added to the same batch.
- Detect the document category from the source path.
- Extract document codes, titles, and revisions from PDF file names.
- Create Teamcenter items and first revisions.
- Import PDFs into the corresponding Teamcenter revisions.
- Read the current SolidWorks PDM workflow state.
- Start Teamcenter workflows for approved or obsolete documents.
- Continue processing the batch when an individual document fails.
- Produce a final summary of complete, partial, and failed imports.
- Provide a preview mode that does not change Teamcenter.
- Provide an optional detailed output mode for troubleshooting.

---

## Supported document categories

| Source category | Internal document type | Purpose |
| --- | --- | --- |
| `Desenhos Originais` | `Original` | DCA original drawings |
| `FP - Ficha de Processo (PDF)` | `Processo` | DCA process documents |
| `Normas Externas` | `NormaExterna` | DCA external standards |

Each category is mapped to a Teamcenter item type and revision type through
environment variables.

The mappings can be different for the test and production environments.

---

## Supported workflow states

DCAtoPLM reads the current workflow state of each file in SolidWorks PDM.

The following states can trigger Teamcenter workflows:

| PDM state | Teamcenter action |
| --- | --- |
| `Aprovado` | Starts the workflow configured in `DCA_TC_APPROVED_WORKFLOW` |
| `Obsoleto` | Starts the workflow configured in `DCA_TC_OBSOLETE_WORKFLOW` |
| Any other state | Imports the item and PDF without starting a workflow |

The workflow is started only after the item and PDF import steps complete
without an exception.

> [!NOTE]
> Calling the integration assembly without an exception confirms that the workflow
> method was requested. Final workflow behavior depends on the template and
> handlers configured in Teamcenter.

---

## Repository structure

```text
DCAtoPLM/
├── import_dcaPdfToTeamcenter.ps1
├── functions/
│   └── teamcenter_functions.ps1
├── start_DCAtoPLM.bat
├── .env.example
├── .env
└── README.md

File	Responsibilityimport_dcaPdfToTeamcenter.ps1	Search, folder selection, PDF interpretation, batch preparation, prompts, and orchestration
functions/teamcenter_functions.ps1	Teamcenter connection, item creation, revision lookup, PDF import, and workflow invocation
start_DCAtoPLM.bat	Recommended Windows launcher
.env.example	Safe configuration template
.env	Local environment configuration, never committed
Requirements

The execution environment must provide:

Windows PowerShell compatible with the scripts.
Siemens Teamcenter 2312 access.
A Teamcenter account with permission to create items and revisions.
Permission to import PDF datasets.
Permission to start the configured workflows.
SolidWorks PDM client access.
Interop.EdmLib.dll.
Access to the configured SolidWorks PDM vault.
The compatible Teamcenter integration assembly, such as Importar GD.exe.
Access to the local PDM cache or permission to download files into it.

Administrator privileges should not normally be required.

Expected vault structure

The configured root is supplied through DCA_ROOT or -SearchRoot.

Example:

C:\VAULT_ROOT


The script locates the documentation directory below that root:

C:\VAULT_ROOT\
└── Documentação\
    ├── Desenhos Originais\
    │   ├── CUSTOMER_A\
    │   └── CUSTOMER_B\
    │
    ├── FP - Ficha de Processo (PDF)\
    │   ├── CUSTOMER_A\
    │   ├── CUSTOMER_B\
    │   └── instructions\
    │
    └── Normas Externas\
        ├── AMS\
        ├── ASTM\
        ├── MIL\
        └── other standards\


Folder searches are performed throughout the documentation tree, but only files inside a recognized category can be converted into Teamcenter objects.

The category determines the Teamcenter document type:

Desenhos Originais
    -> Original

FP - Ficha de Processo (PDF)
    -> Processo

Normas Externas
    -> NormaExterna

Configuration

The recommended configuration method is a local .env file.

Copy:

.env.example


to:

.env


Then replace every placeholder with the appropriate value for the workstation and target environment.

The .env file must not be committed because it can contain credentials, internal paths, and server addresses.

Example environment configuration
# ============================================================
# DCA vault
# ============================================================

DCA_ROOT=C:\VAULT_ROOT
DCA_VAULT_NAME=VAULT_NAME
DCA_PDM_LIB=C:\Path\To\Interop.EdmLib.dll
DCA_VAULT_CREDENTIAL=C:\Secure\vault-credential.xml
DCA_TEMP_FOLDER=C:\Temp\DCAtoPLM

# ============================================================
# Teamcenter integration assembly
# ============================================================

DCA_IMPORTER_PATH=C:\Path\To\Importar GD.exe

# ============================================================
# Selected Teamcenter environment
# Valid values: Teste or Processo
# ============================================================

DCA_TC_ENV=Teste

# ============================================================
# Teamcenter test environment
# ============================================================

DCA_TC_TEST_URL=<TEAMCENTER_TEST_URL>
DCA_TC_TEST_USER=<TEAMCENTER_TEST_USER>
DCA_TC_TEST_PASSWORD=<TEAMCENTER_TEST_PASSWORD>

# ============================================================
# Teamcenter production/process environment
# ============================================================

DCA_TC_PROCESS_URL=<TEAMCENTER_PROCESS_URL>
DCA_TC_PROCESS_USER=<TEAMCENTER_PROCESS_USER>
DCA_TC_PROCESS_PASSWORD=<TEAMCENTER_PROCESS_PASSWORD>

# ============================================================
# Teamcenter workflow templates
# ============================================================

DCA_TC_APPROVED_WORKFLOW=<APPROVED_WORKFLOW_TEMPLATE>
DCA_TC_OBSOLETE_WORKFLOW=<OBSOLETE_WORKFLOW_TEMPLATE>

# ============================================================
# Test environment business objects
# ============================================================

DCA_TC_TEST_ORIGINAL_ITEM_TYPE=<ORIGINAL_ITEM_TYPE>
DCA_TC_TEST_ORIGINAL_REVISION_TYPE=<ORIGINAL_REVISION_TYPE>
DCA_TC_TEST_ORIGINAL_CLIENT_PROPERTY=<CLIENT_PROPERTY>
DCA_TC_TEST_ORIGINAL_CLIENT_VALUE=<CLIENT_VALUE>

DCA_TC_TEST_PROCESS_ITEM_TYPE=<PROCESS_ITEM_TYPE>
DCA_TC_TEST_PROCESS_REVISION_TYPE=<PROCESS_REVISION_TYPE>
DCA_TC_TEST_PROCESS_CLIENT_PROPERTY=<CLIENT_PROPERTY>
DCA_TC_TEST_PROCESS_CLIENT_VALUE=<CLIENT_VALUE>

DCA_TC_TEST_STANDARD_ITEM_TYPE=<STANDARD_ITEM_TYPE>
DCA_TC_TEST_STANDARD_REVISION_TYPE=<STANDARD_REVISION_TYPE>
DCA_TC_TEST_STANDARD_CLIENT_PROPERTY=<CLIENT_PROPERTY>
DCA_TC_TEST_STANDARD_CLIENT_VALUE=<CLIENT_VALUE>

# ============================================================
# Production/process environment business objects
# ============================================================

DCA_TC_PROCESS_ORIGINAL_ITEM_TYPE=<ORIGINAL_ITEM_TYPE>
DCA_TC_PROCESS_ORIGINAL_REVISION_TYPE=<ORIGINAL_REVISION_TYPE>
DCA_TC_PROCESS_ORIGINAL_CLIENT_PROPERTY=<CLIENT_PROPERTY>
DCA_TC_PROCESS_ORIGINAL_CLIENT_VALUE=<CLIENT_VALUE>

DCA_TC_PROCESS_PROCESS_ITEM_TYPE=<PROCESS_ITEM_TYPE>
DCA_TC_PROCESS_PROCESS_REVISION_TYPE=<PROCESS_REVISION_TYPE>
DCA_TC_PROCESS_PROCESS_CLIENT_PROPERTY=<CLIENT_PROPERTY>
DCA_TC_PROCESS_PROCESS_CLIENT_VALUE=<CLIENT_VALUE>

DCA_TC_PROCESS_STANDARD_ITEM_TYPE=<STANDARD_ITEM_TYPE>
DCA_TC_PROCESS_STANDARD_REVISION_TYPE=<STANDARD_REVISION_TYPE>
DCA_TC_PROCESS_STANDARD_CLIENT_PROPERTY=<CLIENT_PROPERTY>
DCA_TC_PROCESS_STANDARD_CLIENT_VALUE=<CLIENT_VALUE>

Required changes before use

Before using the project in another company, vault, workstation, or Teamcenter environment, review:

Setting	Configuration locationLocal vault root	DCA_ROOT or -SearchRoot
SolidWorks PDM vault name	DCA_VAULT_NAME or -VaultName
PDM interop library	DCA_PDM_LIB or -PdmLibraryPath
Protected PDM credential file	DCA_VAULT_CREDENTIAL or -VaultCredentialPath
Temporary PDF directory	DCA_TEMP_FOLDER
Teamcenter integration assembly	DCA_IMPORTER_PATH
Teamcenter environment	DCA_TC_ENV
Test Teamcenter connection	DCA_TC_TEST_* variables
Production Teamcenter connection	DCA_TC_PROCESS_* variables
Teamcenter business objects	Environment-specific item and revision variables
Approval workflow	DCA_TC_APPROVED_WORKFLOW
Obsolete workflow	DCA_TC_OBSOLETE_WORKFLOW
Documentation categories	Category definitions in the main PowerShell script
Revision rules	Get-DcaTypeConfiguration
File-name parsing	ConvertFrom-PdfFileName and Get-NormaCodeFromText

The source code intentionally avoids storing production credentials or internal company configuration.

Running the application
Recommended launcher

Run:

start_DCAtoPLM.bat


The launcher starts the PowerShell workflow using the local configuration.

Direct PowerShell execution
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\import_dcaPdfToTeamcenter.ps1

Preview mode
.\import_dcaPdfToTeamcenter.ps1 `
  -SourceCode "AMS 22" `
  -Preview


Preview mode performs search, selection, metadata extraction, and batch summary, but does not:

connect to Teamcenter;
create items;
create revisions;
copy files into the import directory;
import PDFs;
start workflows.
Detailed output
.\import_dcaPdfToTeamcenter.ps1 `
  -SourceCode "\*SETUP*" `
  -Preview `
  -Details `
  -OutputDelayMilliseconds 0


-Details displays additional paths, individual document information, and diagnostic output.

Parameters
Parameter	Type	Default	Description-SearchRoot	string	DCA_ROOT	Root of the configured DCA vault
-SourceCode	string	Empty	Codes, patterns, or folder searches separated by commas
-ItemName	string	Empty	Optional initial Teamcenter item name
-VaultName	string	DCA_VAULT_NAME	SolidWorks PDM vault name
-PdmLibraryPath	string	DCA_PDM_LIB	Path to Interop.EdmLib.dll
-VaultCredentialPath	string	DCA_VAULT_CREDENTIAL	Protected credential file
-OutputDelayMilliseconds	int	100	Delay between output lines
-NoVaultApi	switch	Disabled	Searches only locally available files
-Details	switch	Disabled	Displays detailed search and diagnostic information
-Preview	switch	Disabled	Prepares the batch without changing Teamcenter
Search behavior
Automatic partial search

Code searches are partial by default.

Entering:

AMS 22


can return:

AMS 2241
AMS 2242
AMS 2248
AMS 2261
AMS 2262


The user does not need to include * for standard partial searches.

Explicit wildcard patterns remain supported:

AMS 22*
*2248*
BR50??A-00


Supported wildcards:

*  matches zero or more characters
?  matches one character

Multiple code searches

Separate searches with commas:

1000359,1000359-2,AMS 2248


Each value is searched independently.

Repeated search expressions are removed before execution.

Multiple result selection

When a search returns more than one PDF, select multiple results:

1,2,4


Each selected PDF becomes an independent batch entry.

Folder search

Prefix the search with \ to search for folders throughout the documentation tree.

Exact folder name
\MIL


When a single exact folder is found, the folder can be selected automatically.

Partial folder search
\*SETUP*

\Normas*

\*AEL


The application displays matching folders with a compact summary:

[1] FP - Ficha de Processo (PDF)\CUSTOMER\instructions
    Type:       DCA Process
    PDFs:       15
    Approved:   3
    Obsolete:   1
    Other:      11

[2] Normas Externas\External Standards A
    Type:       DCA External Standard
    PDFs:       28
    Approved:   7
    Obsolete:   4
    Other:      17


Folder selection supports:

1
1,2
1-3
T


Where:

1 selects one folder;
1,2 selects multiple folders;
1-3 selects a range;
T selects all displayed folders.

Only PDFs directly inside each selected folder are included. Subfolders appear as independent choices when the folder pattern also matches them.

This prevents a PDF from being counted once through the parent folder and again through a matching child folder.

Batch processing

DCAtoPLM processes each prepared document independently.

For each batch entry, the application:

Creates the Teamcenter item.
Creates or obtains the first item revision.
Ensures the source PDF is available locally.
Copies the PDF into the configured temporary directory.
Validates the temporary PDF.
Calls the Teamcenter PDF import method.
Reads the PDM state.
Starts the corresponding workflow when configured.
Records the individual result.
Continues with the next document if one document fails.

A failure does not stop the remaining batch unless it occurs before any documents can be prepared.

Final result states

A document can finish in one of these conditions:

Complete
Item created
PDF imported
Workflow requested when applicable

Partial
Item created
PDF not imported


This condition can leave an item in Teamcenter without the associated PDF and must be reviewed manually.

Failed
Item not created
PDF not processed


The final summary displays the total number of successful and failed entries.

Document-specific rules
DCA Original Drawing

Source category:

Desenhos Originais


Typical revision examples:

B
BA


The current configuration validates the Teamcenter revision length. If the target Teamcenter model supports longer revisions, update the validation in:

functions/teamcenter_functions.ps1


Function:

Get-DcaTypeConfiguration

DCA Process

Source category:

FP - Ficha de Processo (PDF)


Expected revision format:

A4
BA4
AA4
--4


The final character represents the internal revision.

Example:

BA4


is interpreted as:

Complete revision: BA4
Client revision:   BA
Internal revision: 4


Text inside brackets is accepted as a revision only when it matches the valid revision format.

For example:

1000359-2[BA4].pdf


is valid.

Text such as:

1000359-2[TEST].pdf


is not automatically accepted as a revision.

DCA External Standard

Source category:

Normas Externas


External standards use revision:

000


The parser recognizes several technical code formats, including:

AMS 2248
AMS 2759-3
AMS 2440C
AMS-STD-2175
MIL-PRF-85582
ASTM-A123


When possible, the text after the code is interpreted as the document title.

Example:

AMS 2248 CHEMICAL CHECK ANALYSIS LIMITS.pdf


is interpreted as:

Code: AMS 2248
Name: CHEMICAL CHECK ANALYSIS LIMITS

PDF import

Before calling the Teamcenter integration method, the script:

Confirms the PDF is available in the local PDM cache.
Downloads the file through PDM when necessary.
Copies the PDF into DCA_TEMP_FOLDER.
Confirms the temporary file exists.
Verifies that the file is not empty.
Verifies that the copied file size matches the source.
Passes the PDF path and Teamcenter revision to the integration assembly.

The integration currently expects a method compatible with:

ImportarPDF(
    DatasetId,
    DatasetRev,
    pathArquivo,
    ItemRevision,
    Sobrepor
)


The exact behavior depends on the installed Importar GD.exe assembly.

!CAUTION]TheDatasetIDandDatasetrevisionrequirementsmustbeconfirmedagainsttheintegrationassemblyusedbythetargetTeamcenterenvironment.AnincompatiblevaluecancausetheTeamcenteritemtobecreatedwithoutthePDFbeingattached.!CAUTION] The Dataset ID and Dataset revision requirements must be confirmed against the integration assembly used by the target Teamcenter environment. An incompatible value can cause the Teamcenter item to be created without the PDF being attached.
Teamcenter workflows

After a successful PDF import, DCAtoPLM can invoke:

Start_Workflow(
    Workflow_Template,
    Revisions
)


The selected workflow depends on the PDM state:

Aprovado -> DCA_TC_APPROVED_WORKFLOW
Obsoleto -> DCA_TC_OBSOLETE_WORKFLOW


Documents in states such as:

Verificado
Em verificação


are imported without an automatic workflow unless an additional rule is implemented.

The workflow template must already exist in Teamcenter and must support the revision type being submitted.

Duplicate items

If an item already exists in Teamcenter, the script reports the duplicate.

The application does not automatically generate an alternative item code.

Example:

The item 'AMS 2248' already exists in Teamcenter.


In batch mode, the duplicate is recorded as an individual failure and the application continues with the next document.

Temporary files

Temporary import files are stored in:

DCA_TEMP_FOLDER


Example:

C:\Temp\DCAtoPLM


The temporary PDF name is based on the Teamcenter item code.

Characters that are invalid in Windows file names are replaced before the temporary path is created.

PDM authentication

When a credential file is configured, the script reads it using Import-Clixml.

Create a protected credential file with:

Get-Credential |
  Export-Clixml -Path "C:\Secure\vault-credential.xml"


The encrypted credential is normally tied to the Windows user and computer that created it.

If no credential file is configured, the application attempts LoginAuto, which requires an active SolidWorks PDM session for the current Windows user.

Teamcenter environments

Two Teamcenter environments are supported:

Teste
Processo


Select the environment through:

DCA_TC_ENV=Teste


or:

DCA_TC_ENV=Processo


When connected to the production/process environment, the application requires an additional explicit confirmation before creating items.

Recommended production procedure

Before running a production import:

Update .env with the approved configuration.
Confirm the selected Teamcenter environment.
Confirm the PDM account can read and download the selected PDFs.
Confirm the Teamcenter account can create the required item types.
Confirm the Teamcenter account can create Dataset relations.
Confirm the workflow templates exist.
Run the same search with -Preview.
Review document types, revisions, states, and extracted codes.
Start with one controlled test document.
Inspect the created item, revision, PDF Dataset, and workflow.
Run a larger batch only after the controlled test succeeds.
Security
Never commit .env.
Never commit passwords or access tokens.
Never commit protected credential files.
Never publish internal Teamcenter URLs.
Never publish internal business object names without authorization.
Keep Teamcenter integration assemblies outside the repository.
Use accounts with the minimum permissions required.
Review logs before sharing them because logs can contain internal paths, item codes, server names, and usernames.
PowerShell syntax validation

Validate both PowerShell files without running the application:

$files = @(
  ".\import_dcaPdfToTeamcenter.ps1",
  ".\functions\teamcenter_functions.ps1"
)

foreach ($file in $files) {

  $tokens =
  $null

  $errors =
  $null

  [System.Management.Automation.Language.Parser]::ParseFile(
    (Resolve-Path $file),
    [ref]$tokens,
    [ref]$errors
  ) | Out-Null

  if ($errors.Count -gt 0) {

    Write-Host (
      "Syntax errors in: $file"
    ) -ForegroundColor Red

    $errors |
      ForEach-Object {
        Write-Host (
          "Line $($_.Extent.StartLineNumber): " +
          $_.Message
        ) -ForegroundColor Red
      }

    exit 1
  }
}

Write-Host "PowerShell syntax OK" -ForegroundColor Green


Syntax validation does not detect runtime problems such as:

invalid Teamcenter business object names;
missing environment variables;
unavailable PDM APIs;
incompatible integration assembly methods;
invalid workflow templates;
invalid PDF naming conventions;
reflection errors inside the Teamcenter integration executable.
Common errors
Item already exists
The item already exists in Teamcenter.


The item code is already registered. The application does not create another code automatically.

Revision format is invalid
The revision does not follow the DCA Process pattern.


Check the text inside brackets in the PDF file name.

PDF is not available locally
PDF not found on disk.


Confirm PDM authentication and local cache access.

Item created, but PDF not imported
Item created, but PDF not imported.


Review:

the ImportarPDF method signature;
Dataset ID;
Dataset revision;
temporary PDF path;
returned Teamcenter revision;
integration assembly compatibility;
Dataset creation permissions.
Workflow was not started

Verify:

the PDM state;
DCA_TC_APPROVED_WORKFLOW;
DCA_TC_OBSOLETE_WORKFLOW;
the workflow template name;
compatibility with the submitted revision type;
Teamcenter workflow permissions.
Current status

Implemented:

 SolidWorks PDM API search.
 Local file-system fallback.
 Automatic partial code search.
 Explicit wildcard search.
 Multiple searches separated by commas.
 Multiple PDF selection.
 Folder search throughout the documentation tree.
 Wildcard folder search.
 Multiple folder selection.
 Batch preparation.
 Duplicate file prevention.
 Document category detection.
 Original Drawing item creation.
 Process item creation.
 External Standard item creation.
 Revision property mapping.
 PDM state retrieval.
 Approval workflow invocation.
 Obsolete workflow invocation.
 Preview mode.
 Detailed diagnostic mode.
 Per-document batch error handling.
 Confirm PDF Dataset import behavior for every configured revision type.
 Confirm workflow completion and release-status behavior in production.
 Add recovery mode for items created without their PDFs.
 Add automatic detection of items that already exist and require only PDF attachment.
 Add a final Teamcenter verification that confirms the PDF Dataset relation.
Limitations
The project is specific to the current DCA document model.
Teamcenter object names and properties are environment-specific.
The integration depends on a compatible Importar GD.exe.
The PDM integration depends on the installed SolidWorks PDM client.
Folder imports require recognizable document categories.
Process and Original documents require valid revisions.
Files with unsupported naming conventions may require manual correction or can be skipped during folder imports.
A successful reflection call does not necessarily prove that the Dataset or workflow completed unless an explicit verification is implemented.
Recovery of an item created without its PDF is not yet automated.
Disclaimer

This repository contains an environment-specific integration example. Before using the project in another organization:

replace all placeholders;
review security requirements;
validate business object mappings;
validate workflow templates;
validate the integration assembly;
execute controlled tests in a non-production environment.

Use the project only in authorized environments and with approved credentials.