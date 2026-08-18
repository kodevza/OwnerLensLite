function Get-OwnerLensStorageDiagnosticSettingRows {
  param([object[]]$StorageAccounts)

  @($StorageAccounts | ForEach-Object {
      $storageAccount = $_
      $diagnosticRows = @($storageAccount.diagnosticSettings)
      if ($diagnosticRows.Count -eq 0) {
        $diagnosticRows = @($storageAccount.dataPlaneReadServices | ForEach-Object {
            [pscustomobject]@{
              service = [string]$_
              status = "NotConfigured"
              dataAccessLogEnabled = $false
              logAnalyticsEnabled = $false
              diagnosticSettingNames = @()
              workspaceIds = @()
              resourceId = Get-AzureStorageDiagnosticServiceResourceId `
                -StorageAccountResourceId ([string]$storageAccount.resourceId) `
                -Service ([string]$_)
            }
          })
      }

      @($diagnosticRows | ForEach-Object {
          $status = [string]$_.status
          if ($status.Equals("NotConfigured", [System.StringComparison]::OrdinalIgnoreCase)) {
            $status = "[yellow]NotConfigured[/]"
          }

          [pscustomobject]@{
            storageAccountName = [string]$storageAccount.name
            service = [string]$_.service
            status = $status
            dataAccessLogEnabled = [bool]$_.dataAccessLogEnabled
            logAnalyticsEnabled = [bool]$_.logAnalyticsEnabled
            diagnosticSettingNames = @($_.diagnosticSettingNames) -join ","
            workspaceIds = @($_.workspaceIds | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | ForEach-Object {
                Format-OwnerLensShortAzureResourceLink -ResourceId ([string]$_)
              }) -join ","
            resourceId = Format-OwnerLensAzureResourceId -ResourceId ([string]$_.resourceId)
          }
        })
    })
}

function Get-OwnerLensStorageDiagnosticSettingsTableRows {
  param([object[]]$StorageAccounts)

  @(Get-OwnerLensStorageDiagnosticSettingRows -StorageAccounts $StorageAccounts)
}

function Show-OwnerLensStorageDiagnosticSettingsTable {
  param([object]$Report)

  $storageDiagnosticSettings = @(Get-OwnerLensStorageDiagnosticSettingsTableRows -StorageAccounts @($Report.azure.storageAccountsWithRbac))
  if ($storageDiagnosticSettings.Count -eq 0) {
    return
  }

  Write-RichRule "Storage Diagnostic Settings" -Style "cyan"
  $storageDiagnosticSettings |
    Write-RichTable -Property storageAccountName, service, status, dataAccessLogEnabled, logAnalyticsEnabled, diagnosticSettingNames, workspaceIds, resourceId -Box Square
}
