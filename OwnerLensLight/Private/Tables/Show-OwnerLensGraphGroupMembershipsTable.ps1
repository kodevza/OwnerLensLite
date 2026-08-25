function Get-OwnerLensGraphGroupMembershipsTableRows {
  param([object[]]$MemberOf)

  @($MemberOf | Select-Object displayName, objectId, objectType)
}

function Show-OwnerLensGraphGroupMembershipsTable {
  param([object]$Report)

  Write-OwnerLensReportTable `
    -Title "Microsoft Graph Group Memberships" `
    -Rows (Get-OwnerLensGraphGroupMembershipsTableRows -MemberOf (Get-OwnerLensReportArray -Report $Report -Path "graph.memberOf")) `
    -Property displayName, objectId, objectType
}
