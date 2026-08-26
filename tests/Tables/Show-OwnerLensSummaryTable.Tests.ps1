BeforeAll {
  . (Join-Path $PSScriptRoot "../Support/Import-OwnerLensLiteTestFunctions.ps1")
}

Describe "OwnerLens Summary table" {
  It "generates table rows from summary metrics" {
    $rows = @(Get-OwnerLensSummaryTableRows -Report ([pscustomobject]@{
          summary = [pscustomobject]@{
            azureRoleAssignments                            = 1
            azureDependencyScopes                           = 2
            azureActivityRecords                            = 3
            azureRbacScopeActivityCallers                   = 4
            azureActivityLogDiagnosticSettings              = 5
            azureActivityLogAnalyticsDiagnostics            = 6
            azureStorageAccountsWithRbac                    = 7
            azureStorageAccountsWithDiagnosticLogs          = 8
            azureStorageAccountsWithLogAnalyticsDiagnostics = 9
            azureBlobReadCallers                            = 10
            azureBlobReadObjects                            = 11
            azureBlobReadRecords                            = 12
            graphAppRoleAssignments                         = 13
            graphDelegatedPermissionGrants                  = 14
            graphGroupMemberships                           = 15
            graphUserSignIns                                = 16
            owners                                          = 17
          }
        }))

    $rows | Should -HaveCount 17
    ($rows | Where-Object Metric -EQ "Role assignments").Count | Should -Be 1
    ($rows | Where-Object Metric -EQ "Owners").Count | Should -Be 17
  }
}
