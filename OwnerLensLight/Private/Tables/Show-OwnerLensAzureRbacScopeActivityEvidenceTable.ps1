function Get-OwnerLensAzureRbacScopeActivityEvidenceTableRows {
  param([object[]]$RbacScopeActivityEvidence)

  @($RbacScopeActivityEvidence | Select-Object eventTimestamp, callerName, caller, operationNameValue, @{ Name = "resourceId"; Expression = { Format-OwnerLensAzureResourceId -ResourceId ([string]$_.resourceId) } }, @{ Name = "rbacScope"; Expression = { Format-OwnerLensAzureResourceId -ResourceId ([string]$_.rbacScope) } }, status)
}

function Show-OwnerLensAzureRbacScopeActivityEvidenceTable {
  param([object]$Report)

  Write-OwnerLensReportTable `
    -Title "Recent Azure RBAC Scope Activity Evidence" `
    -Rows (Get-OwnerLensAzureRbacScopeActivityEvidenceTableRows -RbacScopeActivityEvidence (Get-OwnerLensReportArray -Report $Report -Path "azure.rbacScopeActivityEvidence")) `
    -Property eventTimestamp, callerName, caller, operationNameValue, resourceId, rbacScope, status
}
