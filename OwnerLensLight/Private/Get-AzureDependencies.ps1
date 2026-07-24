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

function Test-AzureActivityLogMatchesScope {
  param(
    [object]$Log,
    [string]$Scope
  )

  if ([string]::IsNullOrWhiteSpace($Scope)) {
    return $false
  }

  $normalizedScope = ([string]$Scope).TrimEnd("/")
  $candidateScopes = @(
    [string]$Log.authorizationScope,
    [string]$Log.resourceId
  ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }

  foreach ($candidateScope in $candidateScopes) {
    $normalizedCandidateScope = ([string]$candidateScope).TrimEnd("/")
    if ($normalizedCandidateScope.Equals($normalizedScope, [System.StringComparison]::OrdinalIgnoreCase)) {
      return $true
    }

    if ($normalizedCandidateScope.StartsWith("$normalizedScope/", [System.StringComparison]::OrdinalIgnoreCase)) {
      return $true
    }
  }

  return $false
}

function New-AzureRbacScopeActivityEvidence {
  param(
    [object]$Subscription,
    [object]$Log,
    [object]$RoleAssignment,
    [object]$ServicePrincipal
  )

  [pscustomobject]@{
    subscriptionId = [string]$Subscription.Id
    subscriptionName = [string]$Subscription.Name
    rbacScope = [string]$RoleAssignment.Scope
    rbacRoleDefinitionName = [string]$RoleAssignment.RoleDefinitionName
    eventTimestamp = [string]$Log.eventTimestamp
    caller = [string]$Log.caller
    callerObjectId = [string]$Log.callerObjectId
    callerAppId = [string]$Log.callerAppId
    callerName = [string]$Log.callerName
    callerTenantId = [string]$Log.callerTenantId
    operationName = [string]$Log.operationName
    operationNameValue = [string]$Log.operationNameValue
    status = [string]$Log.status
    resourceGroupName = [string]$Log.resourceGroupName
    resourceId = [string]$Log.resourceId
    resourceType = [string]$Log.resourceType
    authorizationAction = [string]$Log.authorizationAction
    authorizationScope = [string]$Log.authorizationScope
    matchesInspectedServicePrincipal = [bool](Test-ActivityLogMatchesServicePrincipal -Log $Log -ServicePrincipal $ServicePrincipal)
    evidenceConfidence = "low"
    evidenceReason = "Activity logs show recent management-plane operations under an RBAC scope assigned to the inspected service principal; this is access context, not ownership proof."
  }
}

function Get-AzureRbacScopeActivityCallers {
  param(
    [object[]]$ActivityEvidence
  )

  $groups = @($ActivityEvidence) | Group-Object -Property {
    $callerObjectId = [string]$_.callerObjectId
    $callerAppId = [string]$_.callerAppId
    $caller = [string]$_.caller
    $callerName = [string]$_.callerName

    if (-not [string]::IsNullOrWhiteSpace($callerObjectId)) {
      return "object:$callerObjectId"
    }

    if (-not [string]::IsNullOrWhiteSpace($callerAppId)) {
      return "app:$callerAppId"
    }

    if (-not [string]::IsNullOrWhiteSpace($caller)) {
      return "caller:$caller"
    }

    if (-not [string]::IsNullOrWhiteSpace($callerName)) {
      return "name:$callerName"
    }

    return "unknown"
  }

  foreach ($group in $groups) {
    $items = @($group.Group | Sort-Object eventTimestamp)
    $first = $items | Select-Object -First 1
    $last = $items | Select-Object -Last 1

    [pscustomobject]@{
      callerKey = [string]$group.Name
      caller = [string]$last.caller
      callerObjectId = [string]$last.callerObjectId
      callerAppId = [string]$last.callerAppId
      callerName = [string]$last.callerName
      callerTenantId = [string]$last.callerTenantId
      eventCount = [int]$items.Count
      firstSeen = [string]$first.eventTimestamp
      lastSeen = [string]$last.eventTimestamp
      subscriptions = @($items | Select-Object -ExpandProperty subscriptionName -Unique)
      rbacScopes = @($items | Select-Object -ExpandProperty rbacScope -Unique)
      resourceIds = @($items | Select-Object -ExpandProperty resourceId -Unique | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
      operationNames = @($items | Select-Object -ExpandProperty operationNameValue -Unique | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
      matchesInspectedServicePrincipal = [bool](@($items | Where-Object matchesInspectedServicePrincipal).Count -gt 0)
      evidenceConfidence = "low"
      evidenceReason = "Caller performed recent management-plane operations under one or more RBAC scopes assigned to the inspected service principal."
    }
  }
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

    [string]$LogAnalyticsWorkspaceId = "",

    [ValidateRange(1, 1000000)]
    [int]$MaxBlobReadRecords = 5000,

    [string[]]$BlobReadOperationNames = @("GetBlob", "PutBlob", "PutBlock", "PutBlockList", "AppendBlock", "CopyBlob"),

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
  $coAssignedRoleCandidates = @()
  $resourceDependencies = @()
  $activityEvidence = @()
  $rbacScopeActivityEvidence = @()
  $blobReadEvidence = @()
  $storageAccountsWithRbac = @{}
  $activityStartTime = (Get-Date).AddDays(-$ActivityDays)
  $servicePrincipalObjectId = [string]$ServicePrincipal.objectId
  $candidateRoleAssignmentIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
  $queriedCoAssignedScopes = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

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

      foreach ($storageAccount in @(Get-AzureStorageAccountsForScope -Scope ([string]$assignment.Scope) -Resources $resources)) {
        $storageAccountResourceId = [string]$storageAccount.ResourceId
        if (-not [string]::IsNullOrWhiteSpace($storageAccountResourceId)) {
          $storageAccountsWithRbac[$storageAccountResourceId] = $storageAccount
        }
      }

      $assignmentScope = [string]$assignment.Scope
      if (-not $queriedCoAssignedScopes.Add($assignmentScope)) {
        continue
      }

      $sameScopeAssignments = @(Get-AzRoleAssignment -Scope $assignmentScope -ErrorAction SilentlyContinue)
      foreach ($sameScopeAssignment in $sameScopeAssignments) {
        if (-not ([string]$sameScopeAssignment.Scope).Equals([string]$assignment.Scope, [System.StringComparison]::OrdinalIgnoreCase)) {
          continue
        }

        $candidatePrincipalId = [string]$sameScopeAssignment.ObjectId
        if ([string]::IsNullOrWhiteSpace($candidatePrincipalId)) {
          continue
        }

        if ($candidatePrincipalId.Equals($servicePrincipalObjectId, [System.StringComparison]::OrdinalIgnoreCase)) {
          continue
        }

        $candidateRoleAssignmentId = [string]$sameScopeAssignment.RoleAssignmentId
        if (-not [string]::IsNullOrWhiteSpace($candidateRoleAssignmentId)) {
          if (-not $candidateRoleAssignmentIds.Add($candidateRoleAssignmentId)) {
            continue
          }
        }

        $coAssignedRoleCandidates += [pscustomobject]@{
          subscriptionId = [string]$subscription.Id
          subscriptionName = [string]$subscription.Name
          roleAssignmentId = $candidateRoleAssignmentId
          scope = [string]$sameScopeAssignment.Scope
          principalId = $candidatePrincipalId
          principalType = [string]$sameScopeAssignment.ObjectType
          principalName = [string]$sameScopeAssignment.SignInName
          principalDisplayName = [string]$sameScopeAssignment.DisplayName
          roleDefinitionId = [string]$sameScopeAssignment.RoleDefinitionId
          roleDefinitionName = [string]$sameScopeAssignment.RoleDefinitionName
        }
      }
    }

    if (-not $SkipActivityLogs) {
      $logs = Get-AzureActivityLogs `
        -SubscriptionId ([string]$subscription.Id) `
        -StartTime $activityStartTime `
        -MaxRecord $MaxActivityRecords

      foreach ($log in @($logs)) {
        foreach ($assignment in $assignments) {
          if (Test-AzureActivityLogMatchesScope -Log $log -Scope ([string]$assignment.Scope)) {
            $rbacScopeActivityEvidence += New-AzureRbacScopeActivityEvidence `
              -Subscription $subscription `
              -Log $log `
              -RoleAssignment $assignment `
              -ServicePrincipal $ServicePrincipal
          }
        }

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

  if (-not [string]::IsNullOrWhiteSpace($LogAnalyticsWorkspaceId)) {
    $blobReadEvidence = @(Get-StorageBlobReadLogs `
        -WorkspaceId $LogAnalyticsWorkspaceId `
        -StorageAccounts @($storageAccountsWithRbac.Values) `
        -ServicePrincipal $ServicePrincipal `
        -StartTime $activityStartTime `
        -MaxRecord $MaxBlobReadRecords `
        -BlobReadOperationNames $BlobReadOperationNames)
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
    coAssignedRoleCandidates = @($coAssignedRoleCandidates | Sort-Object subscriptionName, scope, principalDisplayName, roleDefinitionName)
    resourceDependencies = @($resourceDependencies |
      Sort-Object resourceId -Unique |
      Sort-Object dependencyType, resourceGroup, resourceName)
    activityEvidence = @($activityEvidence | Sort-Object eventTimestamp, resourceId)
    rbacScopeActivityEvidence = @($rbacScopeActivityEvidence | Sort-Object eventTimestamp, rbacScope, resourceId)
    rbacScopeActivityCallers = @(Get-AzureRbacScopeActivityCallers -ActivityEvidence @($rbacScopeActivityEvidence) |
      Sort-Object @{ Expression = "eventCount"; Descending = $true }, lastSeen)
    blobReadEvidence = @($blobReadEvidence | Sort-Object eventTimestamp, storageAccountName, uri)
    blobReadCallers = @(Get-StorageBlobReadCallers -BlobReadEvidence @($blobReadEvidence) |
      Sort-Object @{ Expression = "blobAccessCount"; Descending = $true }, lastSeen)
    storageAccountsWithRbac = @($storageAccountsWithRbac.Values | ForEach-Object {
      [pscustomobject]@{
        resourceId = [string]$_.ResourceId
        name = [string]$_.Name
        resourceGroup = [string]$_.ResourceGroupName
        location = [string]$_.Location
      }
    } | Sort-Object name)
    logAnalyticsWorkspaceId = [string]$LogAnalyticsWorkspaceId
    maxBlobReadRecords = $MaxBlobReadRecords
    activityStartTime = $activityStartTime.ToUniversalTime().ToString("o")
    maxActivityRecords = $MaxActivityRecords
    activitySkipped = [bool]$SkipActivityLogs
  }
}
