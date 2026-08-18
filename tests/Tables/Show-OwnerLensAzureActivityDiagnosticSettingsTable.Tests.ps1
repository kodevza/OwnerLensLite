BeforeAll {
  . (Join-Path $PSScriptRoot "../Support/Import-OwnerLensLightTestFunctions.ps1")
}

Describe "OwnerLens Azure Activity Log Diagnostic Settings table" {
  It "generates table rows with formatted status" {
    $rows = @(Get-OwnerLensAzureActivityDiagnosticSettingsTableRows -ActivityDiagnosticSettings @(
        [pscustomobject]@{
          subscriptionId = "sub-1"
          subscriptionName = "Sub One"
          resourceId = "/subscriptions/sub-1"
          status = "NotConfigured"
          activityLogEnabled = $false
          logAnalyticsEnabled = $false
          diagnosticSettingNames = @()
          workspaceIds = @()
          storageAccountIds = @()
          eventHubAuthorizationRuleIds = @()
        }
      ))

    $rows | Should -HaveCount 1
    $rows[0].status | Should -Be "[yellow]NotConfigured[/]"
  }
}
