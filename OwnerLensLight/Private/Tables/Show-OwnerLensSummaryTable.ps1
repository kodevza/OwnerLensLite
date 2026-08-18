function Get-OwnerLensSummaryTableRows {
  param([object]$Report)

  @(
    [pscustomobject]@{ Area = "Azure"; Metric = "Role assignments"; Count = $Report.summary.azureRoleAssignments }
    [pscustomobject]@{ Area = "Azure"; Metric = "Dependency scopes"; Count = $Report.summary.azureDependencyScopes }
    [pscustomobject]@{ Area = "Azure"; Metric = "Recent activity records"; Count = $Report.summary.azureActivityRecords }
    [pscustomobject]@{ Area = "Azure"; Metric = "Recent RBAC scope activity callers"; Count = $Report.summary.azureRbacScopeActivityCallers }
    [pscustomobject]@{ Area = "Azure"; Metric = "Subscriptions with Activity Log diagnostics"; Count = $Report.summary.azureActivityLogDiagnosticSettings }
    [pscustomobject]@{ Area = "Azure"; Metric = "Subscriptions with Activity Log to Log Analytics"; Count = $Report.summary.azureActivityLogAnalyticsDiagnostics }
    [pscustomobject]@{ Area = "Azure"; Metric = "Storage accounts with data-plane read"; Count = $Report.summary.azureStorageAccountsWithRbac }
    [pscustomobject]@{ Area = "Azure"; Metric = "Storage accounts with diagnostic logs"; Count = $Report.summary.azureStorageAccountsWithDiagnosticLogs }
    [pscustomobject]@{ Area = "Azure"; Metric = "Storage accounts with Log Analytics diagnostics"; Count = $Report.summary.azureStorageAccountsWithLogAnalyticsDiagnostics }
    [pscustomobject]@{ Area = "Azure"; Metric = "Recent blob data-plane participants"; Count = $Report.summary.azureBlobReadCallers }
    [pscustomobject]@{ Area = "Azure"; Metric = "Recent blob objects read"; Count = $Report.summary.azureBlobReadObjects }
    [pscustomobject]@{ Area = "Azure"; Metric = "Recent blob data-plane records"; Count = $Report.summary.azureBlobReadRecords }
    [pscustomobject]@{ Area = "Graph"; Metric = "App role assignments"; Count = $Report.summary.graphAppRoleAssignments }
    [pscustomobject]@{ Area = "Graph"; Metric = "Delegated permission grants"; Count = $Report.summary.graphDelegatedPermissionGrants }
    [pscustomobject]@{ Area = "Graph"; Metric = "Group memberships"; Count = $Report.summary.graphGroupMemberships }
    [pscustomobject]@{ Area = "Graph"; Metric = "User sign-ins"; Count = $Report.summary.graphUserSignIns }
    [pscustomobject]@{ Area = "Graph"; Metric = "Owners"; Count = $Report.summary.owners }
  )
}

function Show-OwnerLensSummaryTable {
  param([object]$Report)

  Write-RichRule "Summary" -Style "cyan"
  Get-OwnerLensSummaryTableRows -Report $Report |
    Write-RichTable -Property Area, Metric, Count -Box Square
  Write-Host ""
}
