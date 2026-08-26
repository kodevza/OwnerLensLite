function ConvertTo-OwnerLensDiagnosticStatus {
  param(
    [object[]]$EnabledSettings,
    [object[]]$LogAnalyticsSettings,
    [object[]]$ExternalSettings
  )

  if (@($LogAnalyticsSettings).Count -gt 0) { return "LogAnalytics" }
  if (@($ExternalSettings).Count -gt 0) { return "ExternalDestination" }
  if (@($EnabledSettings).Count -gt 0) { return "EnabledNoDestinationDetected" }
  return "NotConfigured"
}

function Get-OwnerLensDiagnosticSettingDestinationSummary {
  param(
    [Parameter(Mandatory = $true)]
    [object[]]$Settings,

    [Parameter(Mandatory = $true)]
    [scriptblock]$EnabledPredicate
  )

  $enabledSettings = @($Settings | Where-Object $EnabledPredicate)
  $logAnalyticsSettings = @($enabledSettings | Where-Object {
      -not [string]::IsNullOrWhiteSpace([string](Get-ObjectProperty -Object $_ -PropertyName "WorkspaceId"))
    })
  $externalSettings = @($enabledSettings | Where-Object {
      -not [string]::IsNullOrWhiteSpace([string](Get-ObjectProperty -Object $_ -PropertyName "StorageAccountId")) -or
      -not [string]::IsNullOrWhiteSpace([string](Get-ObjectProperty -Object $_ -PropertyName "EventHubAuthorizationRuleId")) -or
      -not [string]::IsNullOrWhiteSpace([string](Get-ObjectProperty -Object $_ -PropertyName "MarketplacePartnerId"))
    })

  [pscustomobject]@{
    enabledSettings              = $enabledSettings
    logAnalyticsSettings         = $logAnalyticsSettings
    externalSettings             = $externalSettings
    status                       = ConvertTo-OwnerLensDiagnosticStatus `
      -EnabledSettings $enabledSettings `
      -LogAnalyticsSettings $logAnalyticsSettings `
      -ExternalSettings $externalSettings
    diagnosticSettingNames       = @(
      $enabledSettings |
        ForEach-Object { [string](Get-ObjectProperty -Object $_ -PropertyName "Name") } |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    )
    workspaceIds                 = @(
      $logAnalyticsSettings |
        ForEach-Object { [string](Get-ObjectProperty -Object $_ -PropertyName "WorkspaceId") } |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
        Sort-Object -Unique
    )
    storageAccountIds            = @(
      $enabledSettings |
        ForEach-Object { [string](Get-ObjectProperty -Object $_ -PropertyName "StorageAccountId") } |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
        Sort-Object -Unique
    )
    eventHubAuthorizationRuleIds = @(
      $enabledSettings |
        ForEach-Object { [string](Get-ObjectProperty -Object $_ -PropertyName "EventHubAuthorizationRuleId") } |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
        Sort-Object -Unique
    )
    marketplacePartnerIds        = @(
      $enabledSettings |
        ForEach-Object { [string](Get-ObjectProperty -Object $_ -PropertyName "MarketplacePartnerId") } |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
        Sort-Object -Unique
    )
  }
}
