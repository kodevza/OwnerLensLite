function Get-AzureScopeParts {
  param([string]$Scope)

  $parts = [ordered]@{
    scopeType      = "Unknown"
    subscriptionId = $null
    resourceGroup  = $null
    resourceId     = $null
  }

  if ([string]::IsNullOrWhiteSpace($Scope)) {
    return [pscustomobject]$parts
  }

  if ($Scope -match "^/subscriptions/([^/]+)$") {
    $parts.scopeType = "Subscription"
    $parts.subscriptionId = $Matches[1]
    return [pscustomobject]$parts
  }

  if ($Scope -match "^/subscriptions/([^/]+)/resourceGroups/([^/]+)$") {
    $parts.scopeType = "ResourceGroup"
    $parts.subscriptionId = $Matches[1]
    $parts.resourceGroup = $Matches[2]
    return [pscustomobject]$parts
  }

  if ($Scope -match "^/subscriptions/([^/]+)/resourceGroups/([^/]+)/providers/.+$") {
    $parts.scopeType = "Resource"
    $parts.subscriptionId = $Matches[1]
    $parts.resourceGroup = $Matches[2]
    $parts.resourceId = $Scope
    return [pscustomobject]$parts
  }

  if ($Scope -match "^/providers/Microsoft\.Management/managementGroups/([^/]+)$") {
    $parts.scopeType = "ManagementGroup"
  }

  return [pscustomobject]$parts
}

function Get-AzureSubscriptionFilters {
  param([string]$SubscriptionIds)

  if ([string]::IsNullOrWhiteSpace($SubscriptionIds)) {
    $context = Get-AzContext
    if (-not $context -or -not $context.Subscription -or [string]::IsNullOrWhiteSpace([string]$context.Subscription.Id)) {
      throw "Azure context does not have a current subscription. Provide -SubscriptionIds or run Set-AzContext."
    }

    return @([string]$context.Subscription.Id)
  }

  return @($SubscriptionIds.Split(",") | ForEach-Object { $_.Trim() } | Where-Object { $_ })
}

function Find-AzureResourceForScope {
  param(
    [string]$Scope,
    [hashtable]$ResourceById,
    [hashtable]$ResourceGroupByName,
    [object]$Subscription
  )

  $scopeParts = Get-AzureScopeParts -Scope $Scope

  if ($scopeParts.scopeType -eq "Subscription") {
    return [pscustomobject]@{
      dependencyType = "Subscription"
      resourceId     = "/subscriptions/$($Subscription.Id)"
      resourceName   = [string]$Subscription.Name
      resourceGroup  = $null
      resourceType   = "Microsoft.Resources/subscriptions"
      location       = $null
      tags           = $null
    }
  }

  if ($scopeParts.scopeType -eq "ResourceGroup") {
    $resourceGroupKey = [string]$scopeParts.resourceGroup
    $resourceGroup = $ResourceGroupByName[$resourceGroupKey]
    return [pscustomobject]@{
      dependencyType = "ResourceGroup"
      resourceId     = "/subscriptions/$($Subscription.Id)/resourceGroups/$resourceGroupKey"
      resourceName   = $resourceGroupKey
      resourceGroup  = $resourceGroupKey
      resourceType   = "Microsoft.Resources/resourceGroups"
      location       = if ($resourceGroup) { [string]$resourceGroup.Location } else { $null }
      tags           = if ($resourceGroup) { $resourceGroup.Tags } else { $null }
    }
  }

  if ($scopeParts.scopeType -eq "Resource" -and $ResourceById.ContainsKey([string]$Scope)) {
    $resource = $ResourceById[[string]$Scope]
    return [pscustomobject]@{
      dependencyType = "Resource"
      resourceId     = [string]$resource.ResourceId
      resourceName   = [string]$resource.Name
      resourceGroup  = [string]$resource.ResourceGroupName
      resourceType   = [string]$resource.ResourceType
      location       = [string]$resource.Location
      tags           = $resource.Tags
    }
  }

  return [pscustomobject]@{
    dependencyType = $scopeParts.scopeType
    resourceId     = [string]$Scope
    resourceName   = $null
    resourceGroup  = $scopeParts.resourceGroup
    resourceType   = $null
    location       = $null
    tags           = $null
  }
}
