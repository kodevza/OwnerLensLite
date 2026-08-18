function Get-OwnerLensGraphAppRoleAssignmentsTableRows {
  param([object[]]$AppRoleAssignments)

  @($AppRoleAssignments | Select-Object resourceDisplayName, appRoleId, createdDateTime)
}

function Show-OwnerLensGraphAppRoleAssignmentsTable {
  param([object]$Report)

  if ($Report.graph.appRoleAssignments.Count -eq 0) {
    return
  }

  Write-RichRule "Microsoft Graph App Role Assignments" -Style "cyan"
  Get-OwnerLensGraphAppRoleAssignmentsTableRows -AppRoleAssignments @($Report.graph.appRoleAssignments) |
    Write-RichTable -Property resourceDisplayName, appRoleId, createdDateTime -Box Square
}
