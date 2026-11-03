$diagnosticFunctions =
@(
  "Show-DcaTeamcenterLookupMethods",
  "Show-TeamcenterQueryServiceTypes",
  "Show-TeamcenterSavedQueryTypeDetails"
)

foreach ($functionName in $diagnosticFunctions) {

  Write-Host ""
  Write-Host (
    "Referencias de {$functionName}:"
  ) -ForegroundColor Cyan

  Get-ChildItem `
    -Path "." `
    -Recurse `
    -File `
    -Filter "*.ps1" |
    Select-String `
      -SimpleMatch `
      -Pattern $functionName |
    ForEach-Object {

      Write-Host (
        "  $($_.Path):$($_.LineNumber): " +
        $_.Line.Trim()
      )
    }
}
read-host -Prompt "Pressione ENTER para continuar"