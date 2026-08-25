function Get-OwnerLensGraphDelegatedPermissionGrantsTableRows {
  param([object[]]$OAuth2PermissionGrants)

  @($OAuth2PermissionGrants | Select-Object resourceId, consentType, scope)
}

function Show-OwnerLensGraphDelegatedPermissionGrantsTable {
  param([object]$Report)

  Write-OwnerLensReportTable `
    -Title "Microsoft Graph Delegated Permission Grants" `
    -Rows (Get-OwnerLensGraphDelegatedPermissionGrantsTableRows -OAuth2PermissionGrants (Get-OwnerLensReportArray -Report $Report -Path "graph.oauth2PermissionGrants")) `
    -Property resourceId, consentType, scope
}
