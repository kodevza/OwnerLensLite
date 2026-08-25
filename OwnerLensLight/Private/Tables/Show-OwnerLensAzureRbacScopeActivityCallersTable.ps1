function Get-OwnerLensAzureRbacScopeActivityCallersTableRows {
  param([object[]]$RbacScopeActivityCallers)

  @($RbacScopeActivityCallers | Select-Object callerName, caller, callerObjectId, callerAppId, eventCount, firstSeen, lastSeen, matchesInspectedServicePrincipal)
}

function Show-OwnerLensAzureRbacScopeActivityCallersTable {
  param([object]$Report)

  Write-OwnerLensReportTable `
    -Title "Recent Azure RBAC Scope Activity Callers" `
    -Rows (Get-OwnerLensAzureRbacScopeActivityCallersTableRows -RbacScopeActivityCallers (Get-OwnerLensReportArray -Report $Report -Path "azure.rbacScopeActivityCallers")) `
    -Property callerName, caller, callerObjectId, callerAppId, eventCount, firstSeen, lastSeen, matchesInspectedServicePrincipal
}
