function Get-OwnerLensAzureRbacScopeActivityEvidenceTableRows {
  param([object[]]$RbacScopeActivityEvidence)

  @($RbacScopeActivityEvidence | Select-Object eventTimestamp, callerName, caller, operationNameValue, @{ Name = "resourceId"; Expression = { Format-OwnerLensAzureResourceId -ResourceId ([string]$_.resourceId) } }, @{ Name = "rbacScope"; Expression = { Format-OwnerLensAzureResourceId -ResourceId ([string]$_.rbacScope) } }, status)
}

function Show-OwnerLensAzureRbacScopeActivityEvidenceTable {
  param([object]$Report)

  if ($Report.azure.rbacScopeActivityEvidence.Count -eq 0) {
    return
  }

  Write-RichRule "Recent Azure RBAC Scope Activity Evidence" -Style "cyan"
  Get-OwnerLensAzureRbacScopeActivityEvidenceTableRows -RbacScopeActivityEvidence @($Report.azure.rbacScopeActivityEvidence) |
    Write-RichTable -Property eventTimestamp, callerName, caller, operationNameValue, resourceId, rbacScope, status -Box Square
}
