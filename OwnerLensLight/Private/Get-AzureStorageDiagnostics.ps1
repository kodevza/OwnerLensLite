function Get-AzureStorageDataReadServices {
  param([string]$RoleDefinitionName)

  switch -Regex ([string]$RoleDefinitionName) {
    "^Storage Blob Data (Reader|Contributor|Owner)$" { return @("Blob") }
    "^Storage Table Data (Reader|Contributor)$" { return @("Table") }
    "^Storage Queue Data (Reader|Contributor|Message Processor)$" { return @("Queue") }
    default { return @() }
  }
}

function Test-AzureStorageDataReadRole {
  param([string]$RoleDefinitionName)
  return @((Get-AzureStorageDataReadServices -RoleDefinitionName $RoleDefinitionName)).Count -gt 0
}

function Get-AzureStorageDiagnosticServiceResourceId {
  param([string]$StorageAccountResourceId, [string]$Service)

  if ([string]::IsNullOrWhiteSpace($StorageAccountResourceId)) { return "" }
  switch ([string]$Service) {
    "Blob" { return "$($StorageAccountResourceId.TrimEnd("/"))/blobServices/default" }
    "Table" { return "$($StorageAccountResourceId.TrimEnd("/"))/tableServices/default" }
    "Queue" { return "$($StorageAccountResourceId.TrimEnd("/"))/queueServices/default" }
    default { return [string]$StorageAccountResourceId }
  }
}

function Test-AzureStorageDiagnosticLogEnabled {
  param(
    [object]$DiagnosticSetting,
    [string[]]$DataAccessCategories = @("StorageRead", "StorageWrite", "StorageDelete")
  )

  $normalizedDataAccessCategories = @($DataAccessCategories | ForEach-Object { ([string]$_) -replace "[^A-Za-z0-9]", "" })
  $logs = @(
    Get-ObjectProperty -Object $DiagnosticSetting -PropertyName "Logs"
    Get-ObjectProperty -Object $DiagnosticSetting -PropertyName "Log"
    Get-ObjectProperty -Object $DiagnosticSetting -PropertyName "EnabledLog"
  )
  foreach ($log in $logs) {
    if (-not [bool](Get-ObjectProperty -Object $log -PropertyName "Enabled")) { continue }
    $category = [string](Get-ObjectProperty -Object $log -PropertyName "Category")
    $categoryGroup = [string](Get-ObjectProperty -Object $log -PropertyName "CategoryGroup")
    $normalizedCategory = $category -replace "[^A-Za-z0-9]", ""
    if (
      $DataAccessCategories -contains $category -or
      $normalizedDataAccessCategories -contains $normalizedCategory -or
      $categoryGroup.Equals("allLogs", [System.StringComparison]::OrdinalIgnoreCase) -or
      $categoryGroup.Equals("audit", [System.StringComparison]::OrdinalIgnoreCase)
    ) { return $true }
  }

  return $false
}

function Get-AzureStorageDiagnosticSummary {
  param([object]$StorageAccount, [string[]]$DataPlaneReadServices)

  $storageAccountResourceId = [string]$StorageAccount.ResourceId
  $services = @($DataPlaneReadServices | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object -Unique)
  $serviceRows = @()
  foreach ($service in $services) {
    $serviceResourceId = Get-AzureStorageDiagnosticServiceResourceId -StorageAccountResourceId $storageAccountResourceId -Service $service
    try {
      $settings = @(Get-AzDiagnosticSetting -ResourceId $serviceResourceId -ErrorAction Stop)
      $diagnosticSummary = Get-OwnerLensDiagnosticSettingDestinationSummary -Settings $settings -EnabledPredicate { Test-AzureStorageDiagnosticLogEnabled -DiagnosticSetting $_ }
      $serviceRows += [pscustomobject]@{
        service = [string]$service; resourceId = $serviceResourceId; status = [string]$diagnosticSummary.status
        dataAccessLogEnabled = [bool](@($diagnosticSummary.enabledSettings).Count -gt 0); logAnalyticsEnabled = [bool](@($diagnosticSummary.logAnalyticsSettings).Count -gt 0)
        diagnosticSettingNames = @($diagnosticSummary.diagnosticSettingNames); workspaceIds = @($diagnosticSummary.workspaceIds)
      }
    }
    catch {
      $serviceRows += [pscustomobject]@{
        service                = [string]$service
        resourceId             = $serviceResourceId
        status                 = "ReadFailed"
        dataAccessLogEnabled   = $false
        logAnalyticsEnabled    = $false
        diagnosticSettingNames = @()
        workspaceIds           = @()
        error                  = [string]$_.Exception.Message
      }
    }
  }

  $logAnalyticsCount = @($serviceRows | Where-Object logAnalyticsEnabled).Count
  $loggedCount = @($serviceRows | Where-Object dataAccessLogEnabled).Count
  $failedCount = @($serviceRows | Where-Object status -EQ "ReadFailed").Count
  [pscustomobject]@{
    services = @($serviceRows); diagnosticLogEnabled = [bool]($loggedCount -gt 0); diagnosticLogAnalyticsEnabled = [bool]($logAnalyticsCount -gt 0)
    dataAccessVerificationStatus = if ($services.Count -eq 0) {
      "NoDataPlaneService"
    }
    elseif ($logAnalyticsCount -eq $services.Count) {
      "QueryableInLogAnalytics"
    }
    elseif ($logAnalyticsCount -gt 0) {
      "PartiallyQueryableInLogAnalytics"
    }
    elseif ($loggedCount -gt 0) {
      "ConfiguredOutsideLogAnalytics"
    }
    elseif ($failedCount -gt 0) {
      "DiagnosticSettingsReadFailed"
    }
    else {
      "NotConfigured"
    }
    dataAccessVerificationReason = if ($services.Count -eq 0) {
      "No storage data-plane service was derived from the assigned RBAC roles."
    }
    elseif ($logAnalyticsCount -eq $services.Count) {
      "Data-plane diagnostic logs are enabled to Log Analytics for every storage service covered by the inspected RBAC roles."
    }
    elseif ($logAnalyticsCount -gt 0) {
      "Data-plane diagnostic logs are enabled to Log Analytics for only some storage services covered by the inspected RBAC roles."
    }
    elseif ($loggedCount -gt 0) {
      "Data-plane diagnostic logs are enabled, but no Log Analytics destination was detected; requester review may require the configured external destination."
    }
    elseif ($failedCount -gt 0) {
      "Diagnostic settings could not be read for one or more storage services."
    }
    else {
      "No data-plane diagnostic logs were detected, so historical requester verification is not available from Azure Storage resource logs."
    }
  }
}
