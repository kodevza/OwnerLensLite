function Get-OwnerLensSummaryTableRows {
  param([object]$Report)

  $summary = Get-OwnerLensReportValue -Report $Report -Path "summary"
  @(
    [pscustomobject]@{ Area = "Azure"; Metric = "Role assignments"; Count = $summary.azureRoleAssignments }
    [pscustomobject]@{ Area = "Azure"; Metric = "Dependency scopes"; Count = $summary.azureDependencyScopes }
    [pscustomobject]@{ Area = "Azure"; Metric = "Recent activity records"; Count = $summary.azureActivityRecords }
    [pscustomobject]@{ Area = "Azure"; Metric = "Recent RBAC scope activity callers"; Count = $summary.azureRbacScopeActivityCallers }
    [pscustomobject]@{ Area = "Azure"; Metric = "Subscriptions with Activity Log diagnostics"; Count = $summary.azureActivityLogDiagnosticSettings }
    [pscustomobject]@{ Area = "Azure"; Metric = "Subscriptions with Activity Log to Log Analytics"; Count = $summary.azureActivityLogAnalyticsDiagnostics }
    [pscustomobject]@{ Area = "Azure"; Metric = "Storage accounts with data-plane read"; Count = $summary.azureStorageAccountsWithRbac }
    [pscustomobject]@{ Area = "Azure"; Metric = "Storage accounts with diagnostic logs"; Count = $summary.azureStorageAccountsWithDiagnosticLogs }
    [pscustomobject]@{ Area = "Azure"; Metric = "Storage accounts with Log Analytics diagnostics"; Count = $summary.azureStorageAccountsWithLogAnalyticsDiagnostics }
    [pscustomobject]@{ Area = "Azure"; Metric = "Recent blob data-plane participants"; Count = $summary.azureBlobReadCallers }
    [pscustomobject]@{ Area = "Azure"; Metric = "Recent blob objects read"; Count = $summary.azureBlobReadObjects }
    [pscustomobject]@{ Area = "Azure"; Metric = "Recent blob data-plane records"; Count = $summary.azureBlobReadRecords }
    [pscustomobject]@{ Area = "Graph"; Metric = "App role assignments"; Count = $summary.graphAppRoleAssignments }
    [pscustomobject]@{ Area = "Graph"; Metric = "Delegated permission grants"; Count = $summary.graphDelegatedPermissionGrants }
    [pscustomobject]@{ Area = "Graph"; Metric = "Group memberships"; Count = $summary.graphGroupMemberships }
    [pscustomobject]@{ Area = "Graph"; Metric = "User sign-ins"; Count = $summary.graphUserSignIns }
    [pscustomobject]@{ Area = "Graph"; Metric = "Owners"; Count = $summary.owners }
  )
}

function Show-OwnerLensSummaryTable {
  param([object]$Report)

  Write-OwnerLensReportTable `
    -Title "Summary" `
    -Rows (Get-OwnerLensSummaryTableRows -Report $Report) `
    -Property Area, Metric, Count `
    -BlankLineAfter
}
