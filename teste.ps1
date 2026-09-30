$helper =
"C:\Users\ricardo.deutschendor\Documents\DCAtoPLM\functions\teamcenter_functions.ps1"

. $helper

Get-Command 
    Connect-Teamcenter,
    Get-TeamcenterMethod,
    Get-TeamcenterConnection,
    Get-TeamcenterDataManagementService,
    Get-TeamcenterRevision,
    Import-TeamcenterPdf,
    New-DcaTeamcenterItem 
    -CommandType Function 
    -ErrorAction Stop |
Select-Object Name, CommandType

