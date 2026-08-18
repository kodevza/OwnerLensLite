function Get-OwnerLensGraphGroupMembershipsTableRows {
  param([object[]]$MemberOf)

  @($MemberOf | Select-Object displayName, objectId, objectType)
}

function Show-OwnerLensGraphGroupMembershipsTable {
  param([object]$Report)

  if ($Report.graph.memberOf.Count -eq 0) {
    return
  }

  Write-RichRule "Microsoft Graph Group Memberships" -Style "cyan"
  Get-OwnerLensGraphGroupMembershipsTableRows -MemberOf @($Report.graph.memberOf) |
    Write-RichTable -Property displayName, objectId, objectType -Box Square
}
