function Get-AzureScopeParts {
  param([string]$Scope)

  $parts = [ordered]@{
    scopeType = "Unknown"
    subscriptionId = $null
    resourceGroup = $null
    resourceId = $null
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
      resourceId = "/subscriptions/$($Subscription.Id)"
      resourceName = [string]$Subscription.Name
      resourceGroup = $null
      resourceType = "Microsoft.Resources/subscriptions"
      location = $null
      tags = $null
    }
  }

  if ($scopeParts.scopeType -eq "ResourceGroup") {
    $resourceGroupKey = [string]$scopeParts.resourceGroup
    $resourceGroup = $ResourceGroupByName[$resourceGroupKey]
    return [pscustomobject]@{
      dependencyType = "ResourceGroup"
      resourceId = "/subscriptions/$($Subscription.Id)/resourceGroups/$resourceGroupKey"
      resourceName = $resourceGroupKey
      resourceGroup = $resourceGroupKey
      resourceType = "Microsoft.Resources/resourceGroups"
      location = if ($resourceGroup) { [string]$resourceGroup.Location } else { $null }
      tags = if ($resourceGroup) { $resourceGroup.Tags } else { $null }
    }
  }

  if ($scopeParts.scopeType -eq "Resource" -and $ResourceById.ContainsKey([string]$Scope)) {
    $resource = $ResourceById[[string]$Scope]
    return [pscustomobject]@{
      dependencyType = "Resource"
      resourceId = [string]$resource.ResourceId
      resourceName = [string]$resource.Name
      resourceGroup = [string]$resource.ResourceGroupName
      resourceType = [string]$resource.ResourceType
      location = [string]$resource.Location
      tags = $resource.Tags
    }
  }

  return [pscustomobject]@{
    dependencyType = $scopeParts.scopeType
    resourceId = [string]$Scope
    resourceName = $null
    resourceGroup = $scopeParts.resourceGroup
    resourceType = $null
    location = $null
    tags = $null
  }
}

function Test-ActivityLogMatchesServicePrincipal {
  param(
    [object]$Log,
    [object]$ServicePrincipal
  )

  $objectId = [string]$ServicePrincipal.objectId
  $appId = [string]$ServicePrincipal.appId
  $displayName = [string]$ServicePrincipal.displayName

  $callerObjectId = [string]$Log.callerObjectId
  $callerAppId = [string]$Log.callerAppId
  $caller = [string]$Log.caller
  $callerName = [string]$Log.callerName

  if ($objectId -and $callerObjectId -and $callerObjectId.Equals($objectId, [System.StringComparison]::OrdinalIgnoreCase)) {
    return $true
  }

  if ($appId -and $callerAppId -and $callerAppId.Equals($appId, [System.StringComparison]::OrdinalIgnoreCase)) {
    return $true
  }

  if ($appId -and $caller -and $caller.Equals($appId, [System.StringComparison]::OrdinalIgnoreCase)) {
    return $true
  }

  if ($displayName -and $callerName -and $callerName.Equals($displayName, [System.StringComparison]::OrdinalIgnoreCase)) {
    return $true
  }

  return $false
}

function Get-AzureDependencies {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]
    [object]$ServicePrincipal,

    [string]$SubscriptionIds = "",

    [ValidateRange(1, 3650)]
    [int]$ActivityDays = 30,

    [ValidateRange(1, 1000000)]
    [int]$MaxActivityRecords = 5000,

    [switch]$SkipActivityLogs
  )

  $subscriptionFilters = Get-AzureSubscriptionFilters -SubscriptionIds $SubscriptionIds
  $enabledSubscriptions = Get-AzSubscription | Where-Object State -eq "Enabled"
  $selectedSubscriptions = @()

  foreach ($filter in $subscriptionFilters) {
    $subscription = $enabledSubscriptions | Where-Object { $_.Id -eq $filter -or $_.Name -eq $filter } | Select-Object -First 1
    if (-not $subscription) {
      throw "Subscription not found or not enabled: $filter"
    }

    if (-not ($selectedSubscriptions | Where-Object Id -eq $subscription.Id)) {
      $selectedSubscriptions += $subscription
    }
  }

  $roleAssignments = @()
  $resourceDependencies = @()
  $activityEvidence = @()
  $activityStartTime = (Get-Date).AddDays(-$ActivityDays)
  $servicePrincipalObjectId = [string]$ServicePrincipal.objectId

  foreach ($subscription in $selectedSubscriptions) {
    Set-AzContext -SubscriptionId $subscription.Id | Out-Null

    $resources = @(Get-AzResource)
    $resourceGroups = @(Get-AzResourceGroup)
    $resourceById = @{}
    foreach ($resource in $resources) {
      if (-not [string]::IsNullOrWhiteSpace([string]$resource.ResourceId)) {
        $resourceById[[string]$resource.ResourceId] = $resource
      }
    }

    $resourceGroupByName = @{}
    foreach ($resourceGroup in $resourceGroups) {
      if (-not [string]::IsNullOrWhiteSpace([string]$resourceGroup.ResourceGroupName)) {
        $resourceGroupByName[[string]$resourceGroup.ResourceGroupName] = $resourceGroup
      }
    }

    $assignments = @(Get-AzRoleAssignment -ObjectId $servicePrincipalObjectId -ErrorAction SilentlyContinue)
    foreach ($assignment in $assignments) {
      $roleAssignments += [pscustomobject]@{
        subscriptionId = [string]$subscription.Id
        subscriptionName = [string]$subscription.Name
        roleAssignmentId = [string]$assignment.RoleAssignmentId
        scope = [string]$assignment.Scope
        principalId = [string]$assignment.ObjectId
        principalType = [string]$assignment.ObjectType
        principalDisplayName = [string]$assignment.DisplayName
        roleDefinitionId = [string]$assignment.RoleDefinitionId
        roleDefinitionName = [string]$assignment.RoleDefinitionName
        condition = [string]$assignment.Condition
        conditionVersion = [string]$assignment.ConditionVersion
      }

      $resourceDependencies += Find-AzureResourceForScope `
        -Scope ([string]$assignment.Scope) `
        -ResourceById $resourceById `
        -ResourceGroupByName $resourceGroupByName `
        -Subscription $subscription
    }

    if (-not $SkipActivityLogs) {
      $logs = Get-AzureActivityLogs `
        -SubscriptionId ([string]$subscription.Id) `
        -StartTime $activityStartTime `
        -MaxRecord $MaxActivityRecords

      foreach ($log in @($logs)) {
        if (Test-ActivityLogMatchesServicePrincipal -Log $log -ServicePrincipal $ServicePrincipal) {
          $activityEvidence += [pscustomobject]@{
            subscriptionId = [string]$subscription.Id
            subscriptionName = [string]$subscription.Name
            eventTimestamp = [string]$log.eventTimestamp
            caller = [string]$log.caller
            callerObjectId = [string]$log.callerObjectId
            callerAppId = [string]$log.callerAppId
            callerName = [string]$log.callerName
            operationName = [string]$log.operationName
            operationNameValue = [string]$log.operationNameValue
            status = [string]$log.status
            resourceGroupName = [string]$log.resourceGroupName
            resourceId = [string]$log.resourceId
            resourceType = [string]$log.resourceType
            authorizationAction = [string]$log.authorizationAction
            authorizationScope = [string]$log.authorizationScope
            evidenceConfidence = "low"
            evidenceReason = "Activity logs show recent use by this service principal identifier; this is access evidence, not ownership proof."
          }
        }
      }
    }
  }

  return [pscustomobject]@{
    requestedSubscriptions = @($subscriptionFilters)
    subscriptions = @($selectedSubscriptions | ForEach-Object {
      [pscustomobject]@{
        subscriptionId = [string]$_.Id
        subscriptionName = [string]$_.Name
        tenantId = [string]$_.TenantId
      }
    })
    roleAssignments = @($roleAssignments | Sort-Object subscriptionName, scope, roleDefinitionName)
    resourceDependencies = @($resourceDependencies |
      Sort-Object resourceId -Unique |
      Sort-Object dependencyType, resourceGroup, resourceName)
    activityEvidence = @($activityEvidence | Sort-Object eventTimestamp, resourceId)
    activityStartTime = $activityStartTime.ToUniversalTime().ToString("o")
    maxActivityRecords = $MaxActivityRecords
    activitySkipped = [bool]$SkipActivityLogs
  }
}
