function Get-OwnerLensStorageAccountsWithDataPlaneReadTableRows {
  param([object[]]$StorageAccounts)

  @($StorageAccounts | Select-Object name, resourceGroup, location, @{ Name = "readServices"; Expression = { @($_.dataPlaneReadServices) -join "," } }, @{ Name = "readRoles"; Expression = { @($_.dataPlaneReadRoleNames) -join "," } }, diagnosticLogEnabled, diagnosticLogAnalyticsEnabled, dataAccessVerificationStatus, @{ Name = "resourceId"; Expression = { Format-OwnerLensAzureResourceId -ResourceId ([string]$_.resourceId) } })
}

function Show-OwnerLensStorageAccountsWithDataPlaneReadTable {
  param([object]$Report)

  Write-OwnerLensReportTable `
    -Title "Storage Accounts With Data-Plane Read" `
    -Rows (Get-OwnerLensStorageAccountsWithDataPlaneReadTableRows -StorageAccounts (Get-OwnerLensReportArray -Report $Report -Path "azure.storageAccountsWithRbac")) `
    -Property name, resourceGroup, location, readServices, readRoles, diagnosticLogEnabled, diagnosticLogAnalyticsEnabled, dataAccessVerificationStatus, resourceId
}
