function Get-OwnerLensActivityDiagnosticSettingRows {
  param([object[]]$ActivityDiagnosticSettings)

  @($ActivityDiagnosticSettings | ForEach-Object {
      $status = [string]$_.status
      if ($status.Equals("NotConfigured", [System.StringComparison]::OrdinalIgnoreCase)) {
        $status = "[yellow]NotConfigured[/]"
      } elseif ($status.Equals("ReadFailed", [System.StringComparison]::OrdinalIgnoreCase)) {
        $status = "[red]ReadFailed[/]"
      }

      [pscustomobject]@{
        subscriptionName = [string]$_.subscriptionName
        subscriptionId = [string]$_.subscriptionId
        status = $status
        activityLogEnabled = [bool]$_.activityLogEnabled
        logAnalyticsEnabled = [bool]$_.logAnalyticsEnabled
        diagnosticSettingNames = @($_.diagnosticSettingNames) -join ","
        workspaceIds = @($_.workspaceIds | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | ForEach-Object {
            Format-OwnerLensShortAzureResourceLink -ResourceId ([string]$_)
          }) -join ","
        storageAccountIds = @($_.storageAccountIds | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | ForEach-Object {
            Format-OwnerLensShortAzureResourceLink -ResourceId ([string]$_)
          }) -join ","
        eventHubAuthorizationRuleIds = @($_.eventHubAuthorizationRuleIds | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | ForEach-Object {
            Format-OwnerLensShortAzureResourceLink -ResourceId ([string]$_)
          }) -join ","
        resourceId = Format-OwnerLensAzureResourceId -ResourceId ([string]$_.resourceId)
      }
    })
}

function Get-OwnerLensAzureActivityDiagnosticSettingsTableRows {
  param([object[]]$ActivityDiagnosticSettings)

  @(Get-OwnerLensActivityDiagnosticSettingRows -ActivityDiagnosticSettings $ActivityDiagnosticSettings)
}

function Show-OwnerLensAzureActivityDiagnosticSettingsTable {
  param([object]$Report)

  $activityDiagnosticSettings = @(Get-OwnerLensAzureActivityDiagnosticSettingsTableRows -ActivityDiagnosticSettings @($Report.azure.activityDiagnosticSettings))
  if ($activityDiagnosticSettings.Count -eq 0) {
    return
  }

  Write-RichRule "Azure Activity Log Diagnostic Settings" -Style "cyan"
  $activityDiagnosticSettings |
    Write-RichTable -Property subscriptionName, subscriptionId, status, activityLogEnabled, logAnalyticsEnabled, diagnosticSettingNames, workspaceIds, storageAccountIds, eventHubAuthorizationRuleIds, resourceId -Box Square
}
