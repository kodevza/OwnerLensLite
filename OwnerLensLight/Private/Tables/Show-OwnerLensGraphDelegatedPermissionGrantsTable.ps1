function Get-OwnerLensGraphDelegatedPermissionGrantsTableRows {
  param([object[]]$OAuth2PermissionGrants)

  @($OAuth2PermissionGrants | Select-Object resourceId, consentType, scope)
}

function Show-OwnerLensGraphDelegatedPermissionGrantsTable {
  param([object]$Report)

  if ($Report.graph.oauth2PermissionGrants.Count -eq 0) {
    return
  }

  Write-RichRule "Microsoft Graph Delegated Permission Grants" -Style "cyan"
  Get-OwnerLensGraphDelegatedPermissionGrantsTableRows -OAuth2PermissionGrants @($Report.graph.oauth2PermissionGrants) |
    Write-RichTable -Property resourceId, consentType, scope -Box Square
}
