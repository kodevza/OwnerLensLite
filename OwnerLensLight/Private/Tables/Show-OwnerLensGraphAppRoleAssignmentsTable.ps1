function Get-OwnerLensGraphAppRoleAssignmentsTableRows {
  param([object[]]$AppRoleAssignments)

  @($AppRoleAssignments | Select-Object resourceDisplayName, appRoleId, createdDateTime)
}

function Show-OwnerLensGraphAppRoleAssignmentsTable {
  param([object]$Report)

  Write-OwnerLensReportTable `
    -Title "Microsoft Graph App Role Assignments" `
    -Rows (Get-OwnerLensGraphAppRoleAssignmentsTableRows -AppRoleAssignments (Get-OwnerLensReportArray -Report $Report -Path "graph.appRoleAssignments")) `
    -Property resourceDisplayName, appRoleId, createdDateTime
}
