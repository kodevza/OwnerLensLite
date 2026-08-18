function Get-OwnerLensStorageAccountsWithDataPlaneReadTableRows {
  param([object[]]$StorageAccounts)

  @($StorageAccounts | Select-Object name, resourceGroup, location, @{ Name = "readServices"; Expression = { @($_.dataPlaneReadServices) -join "," } }, @{ Name = "readRoles"; Expression = { @($_.dataPlaneReadRoleNames) -join "," } }, diagnosticLogEnabled, diagnosticLogAnalyticsEnabled, dataAccessVerificationStatus, @{ Name = "resourceId"; Expression = { Format-OwnerLensAzureResourceId -ResourceId ([string]$_.resourceId) } })
}

function Show-OwnerLensStorageAccountsWithDataPlaneReadTable {
  param([object]$Report)

  if ($Report.azure.storageAccountsWithRbac.Count -eq 0) {
    return
  }

  Write-RichRule "Storage Accounts With Data-Plane Read" -Style "cyan"
  Get-OwnerLensStorageAccountsWithDataPlaneReadTableRows -StorageAccounts @($Report.azure.storageAccountsWithRbac) |
    Write-RichTable -Property name, resourceGroup, location, readServices, readRoles, diagnosticLogEnabled, diagnosticLogAnalyticsEnabled, dataAccessVerificationStatus, resourceId -Box Square
}
