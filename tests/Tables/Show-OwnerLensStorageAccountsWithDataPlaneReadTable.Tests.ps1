BeforeAll {
  . (Join-Path $PSScriptRoot "../Support/Import-OwnerLensLiteTestFunctions.ps1")
}

Describe "OwnerLens Storage Accounts With Data-Plane Read table" {
  It "generates table rows with joined read services" {
    $resourceId = "/subscriptions/sub-1/resourceGroups/rg-1/providers/Microsoft.Storage/storageAccounts/st1"
    $rows = @(Get-OwnerLensStorageAccountsWithDataPlaneReadTableRows -StorageAccounts @(
        [pscustomobject]@{
          name                          = "st1"
          resourceGroup                 = "rg-1"
          location                      = "westeurope"
          dataPlaneReadServices         = @("Blob", "Queue")
          dataPlaneReadRoleNames        = @("Storage Blob Data Reader")
          diagnosticLogEnabled          = $true
          diagnosticLogAnalyticsEnabled = $true
          dataAccessVerificationStatus  = "QueryableInLogAnalytics"
          resourceId                    = $resourceId
        }
      ))

    $rows | Should -HaveCount 1
    $rows[0].readServices | Should -Be "Blob,Queue"
    $rows[0].resourceId | Should -Match "storageAccounts/st1"
  }
}
