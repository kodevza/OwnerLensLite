<#
.SYNOPSIS
Enables Azure Blob Storage read and write diagnostic logs for storage accounts.

.DESCRIPTION
Configures a diagnostic setting on each storage account Blob service sub-resource
(`Microsoft.Storage/storageAccounts/blobServices/default`) so blob read data-plane
logs flow to one Log Analytics workspace. These logs populate the StorageBlobLogs
table used by OwnerLens Lite to show who read blobs.

By default, the script scans all enabled subscriptions visible to the current Az
context. Use -SubscriptionIds to limit the scope.
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param(
  [Parameter(Mandatory = $true, ParameterSetName = "WorkspaceId")]
  [ValidateNotNullOrEmpty()]
  [string]$WorkspaceId,

  [Parameter(Mandatory = $true, ParameterSetName = "WorkspaceResourceId")]
  [ValidateNotNullOrEmpty()]
  [string]$WorkspaceResourceId,

  [string[]]$SubscriptionIds = @(),

  [ValidateNotNullOrEmpty()]
  [string]$DiagnosticSettingName = "ownerlens-blob-read-logs",

  [ValidateNotNullOrEmpty()]
  [string[]]$LogCategories = @("StorageRead", "StorageWrite"),

  [switch]$IncludeMetrics,

  [switch]$PassThru
)

$ErrorActionPreference = "Stop"

function Get-EnabledSubscriptions {
  param([string[]]$Filters)

  $enabledSubscriptions = @(Get-AzSubscription | Where-Object State -EQ "Enabled")
  if (-not $Filters -or $Filters.Count -eq 0) {
    return $enabledSubscriptions
  }

  $selected = @()
  foreach ($filter in $Filters) {
    $subscription = $enabledSubscriptions |
      Where-Object { $_.Id -eq $filter -or $_.Name -eq $filter } |
      Select-Object -First 1

    if (-not $subscription) {
      throw "Subscription not found or not enabled: $filter"
    }

    if (-not ($selected | Where-Object Id -EQ $subscription.Id)) {
      $selected += $subscription
    }
  }

  return $selected
}

function Resolve-LogAnalyticsWorkspaceResourceId {
  param(
    [string]$WorkspaceCustomerId,
    [object[]]$Subscriptions
  )

  $matches = @()
  foreach ($subscription in $Subscriptions) {
    Set-AzContext -SubscriptionId $subscription.Id | Out-Null
    $workspaces = @(Get-AzResource -ResourceType "Microsoft.OperationalInsights/workspaces" -ErrorAction Stop)

    foreach ($workspace in $workspaces) {
      $workspaceDetails = Get-AzResource -ResourceId $workspace.ResourceId -ExpandProperties -ErrorAction Stop
      $customerId = [string]$workspaceDetails.Properties.customerId
      if ($customerId.Equals($WorkspaceCustomerId, [System.StringComparison]::OrdinalIgnoreCase)) {
        $matches += $workspaceDetails
      }
    }
  }

  if ($matches.Count -eq 0) {
    throw "Log Analytics workspace not found for workspace ID: $WorkspaceCustomerId. Make sure the current Az account can read the workspace, or use -WorkspaceResourceId."
  }

  if ($matches.Count -gt 1) {
    throw "Multiple Log Analytics workspaces matched workspace ID '$WorkspaceCustomerId': $($matches.ResourceId -join ', '). Use -WorkspaceResourceId."
  }

  return [string]$matches[0].ResourceId
}

function Get-DiagnosticSettingPath {
  param(
    [string]$ResourceId,
    [string]$Name
  )

  $encodedName = [Uri]::EscapeDataString($Name)
  return "$ResourceId/providers/microsoft.insights/diagnosticSettings/$encodedName`?api-version=2021-05-01-preview"
}

function Get-DiagnosticSettingsListPath {
  param([string]$ResourceId)

  return "$ResourceId/providers/microsoft.insights/diagnosticSettings`?api-version=2021-05-01-preview"
}

function New-BlobReadDiagnosticSettingBody {
  param(
    [string]$WorkspaceId,
    [string[]]$Categories,
    [bool]$MetricsEnabled
  )

  $properties = [ordered]@{
    workspaceId = $WorkspaceId
    logs        = @($Categories | Sort-Object -Unique | ForEach-Object {
        [ordered]@{
          category        = [string]$_
          enabled         = $true
          retentionPolicy = [ordered]@{
            enabled = $false
            days    = 0
          }
        }
      })
  }

  if ($MetricsEnabled) {
    $properties.metrics = @(
      [ordered]@{
        category        = "Transaction"
        enabled         = $true
        retentionPolicy = [ordered]@{
          enabled = $false
          days    = 0
        }
      }
    )
  }

  return @{
    properties = $properties
  } | ConvertTo-Json -Depth 20
}

function Test-StorageReadDiagnosticSettingExists {
  param(
    [string]$ResourceId,
    [string]$WorkspaceId,
    [string[]]$RequiredCategories
  )

  $response = Invoke-AzRestMethod `
    -Method GET `
    -Path (Get-DiagnosticSettingsListPath -ResourceId $ResourceId) `
    -ErrorAction Stop

  $content = $response.Content | ConvertFrom-Json
  foreach ($setting in @($content.value)) {
    $properties = $setting.properties
    if (-not ([string]$properties.workspaceId).Equals($WorkspaceId, [System.StringComparison]::OrdinalIgnoreCase)) {
      continue
    }

    $enabledCategories = @($properties.logs |
        Where-Object { [bool]$_.enabled } |
        ForEach-Object { [string]$_.category })

    $missingCategory = $false
    foreach ($requiredCategory in $RequiredCategories) {
      if (-not ($enabledCategories | Where-Object { $_.Equals($requiredCategory, [System.StringComparison]::OrdinalIgnoreCase) })) {
        $missingCategory = $true
        break
      }
    }

    if (-not $missingCategory) {
      return $true
    }
  }

  return $false
}

if (-not (Get-Command Get-AzContext -ErrorAction SilentlyContinue)) {
  throw "Az PowerShell module missing. Install: Install-Module Az -Scope CurrentUser"
}

if (-not (Get-Command Invoke-AzRestMethod -ErrorAction SilentlyContinue)) {
  throw "Invoke-AzRestMethod missing. Update Az.Accounts: Update-Module Az.Accounts"
}

$subscriptions = @(Get-EnabledSubscriptions -Filters $SubscriptionIds)
if ($PSCmdlet.ParameterSetName -eq "WorkspaceId") {
  $WorkspaceResourceId = Resolve-LogAnalyticsWorkspaceResourceId `
    -WorkspaceCustomerId $WorkspaceId `
    -Subscriptions $subscriptions
}

$workspace = Get-AzResource -ResourceId $WorkspaceResourceId -ErrorAction Stop
if (-not ([string]$workspace.ResourceType).Equals("Microsoft.OperationalInsights/workspaces", [System.StringComparison]::OrdinalIgnoreCase)) {
  throw "WorkspaceResourceId does not point to a Log Analytics workspace: $WorkspaceResourceId"
}

$body = New-BlobReadDiagnosticSettingBody `
  -WorkspaceId $WorkspaceResourceId `
  -Categories $LogCategories `
  -MetricsEnabled ([bool]$IncludeMetrics)

$results = @()
foreach ($subscription in $subscriptions) {
  Write-Host "Scanning subscription: $($subscription.Name) ($($subscription.Id))"
  Set-AzContext -SubscriptionId $subscription.Id | Out-Null

  $storageAccounts = @(Get-AzResource -ResourceType "Microsoft.Storage/storageAccounts" -ErrorAction Stop |
      Sort-Object ResourceGroupName, Name)

  foreach ($storageAccount in $storageAccounts) {
    $blobServiceResourceId = "$($storageAccount.ResourceId)/blobServices/default"
    $status = "Skipped"
    $message = ""

    try {
      if ([string]$storageAccount.Kind -eq "FileStorage") {
        $status = "SkippedUnsupported"
        $message = "FileStorage accounts do not expose Blob service diagnostic logs."
      }
      elseif (Test-StorageReadDiagnosticSettingExists `
          -ResourceId $blobServiceResourceId `
          -WorkspaceId $WorkspaceResourceId `
          -RequiredCategories $LogCategories) {
        $status = "AlreadyConfigured"
        $message = "$($LogCategories -join ', ') diagnostic logs already route to the target workspace."
      }
      elseif ($PSCmdlet.ShouldProcess($blobServiceResourceId, "Enable $($LogCategories -join ', ') diagnostic logs to $WorkspaceResourceId")) {
        Invoke-AzRestMethod `
          -Method PUT `
          -Path (Get-DiagnosticSettingPath -ResourceId $blobServiceResourceId -Name $DiagnosticSettingName) `
          -Payload $body `
          -ErrorAction Stop | Out-Null

        $status = "Configured"
        $message = "$($LogCategories -join ', ') diagnostic logs now route to the target workspace."
      }
      else {
        $status = "WhatIf"
        $message = "Would configure $($LogCategories -join ', ') diagnostic logs."
      }
    }
    catch {
      $status = "Failed"
      $message = $_.Exception.Message
      Write-Warning "Failed to configure $($storageAccount.Name): $message"
    }

    $result = [pscustomobject]@{
      subscriptionId        = [string]$subscription.Id
      subscriptionName      = [string]$subscription.Name
      resourceGroup         = [string]$storageAccount.ResourceGroupName
      storageAccountName    = [string]$storageAccount.Name
      blobServiceResourceId = [string]$blobServiceResourceId
      diagnosticSettingName = [string]$DiagnosticSettingName
      workspaceResourceId   = [string]$WorkspaceResourceId
      status                = [string]$status
      message               = [string]$message
    }

    $results += $result
    Write-Host "$($result.status): $($result.storageAccountName) - $($result.message)"
  }
}

$results |
  Group-Object status |
  Sort-Object Name |
  Select-Object Name, Count |
  Format-Table -AutoSize

if ($PassThru) {
  return $results
}
