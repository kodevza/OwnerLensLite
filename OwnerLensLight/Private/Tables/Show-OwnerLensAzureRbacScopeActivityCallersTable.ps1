function Get-OwnerLensAzureRbacScopeActivityCallersTableRows {
  param([object[]]$RbacScopeActivityCallers)

  @($RbacScopeActivityCallers | Select-Object callerName, caller, callerObjectId, callerAppId, eventCount, firstSeen, lastSeen, matchesInspectedServicePrincipal)
}

function Show-OwnerLensAzureRbacScopeActivityCallersTable {
  param([object]$Report)

  if ($Report.azure.rbacScopeActivityCallers.Count -eq 0) {
    return
  }

  Write-RichRule "Recent Azure RBAC Scope Activity Callers" -Style "cyan"
  Get-OwnerLensAzureRbacScopeActivityCallersTableRows -RbacScopeActivityCallers @($Report.azure.rbacScopeActivityCallers) |
    Write-RichTable -Property callerName, caller, callerObjectId, callerAppId, eventCount, firstSeen, lastSeen, matchesInspectedServicePrincipal -Box Square
}
