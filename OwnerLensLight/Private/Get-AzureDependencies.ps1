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
  param(
    [string]$StorageAccountResourceId,
    [string]$Service
  )

  if ([string]::IsNullOrWhiteSpace($StorageAccountResourceId)) {
    return ""
  }

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

  $normalizedDataAccessCategories = @($DataAccessCategories | ForEach-Object {
      ([string]$_) -replace "[^A-Za-z0-9]", ""
    })

  $logs = @(
    Get-ObjectProperty -Object $DiagnosticSetting -PropertyName "Logs"
    Get-ObjectProperty -Object $DiagnosticSetting -PropertyName "Log"
    Get-ObjectProperty -Object $DiagnosticSetting -PropertyName "EnabledLog"
  )

  foreach ($log in $logs) {
    $enabled = [bool](Get-ObjectProperty -Object $log -PropertyName "Enabled")
    if (-not $enabled) {
      continue
    }

    $category = [string](Get-ObjectProperty -Object $log -PropertyName "Category")
    $categoryGroup = [string](Get-ObjectProperty -Object $log -PropertyName "CategoryGroup")
    $normalizedCategory = $category -replace "[^A-Za-z0-9]", ""
    if (
      $DataAccessCategories -contains $category -or
      $normalizedDataAccessCategories -contains $normalizedCategory -or
      $categoryGroup.Equals("allLogs", [System.StringComparison]::OrdinalIgnoreCase) -or
      $categoryGroup.Equals("audit", [System.StringComparison]::OrdinalIgnoreCase)
    ) {
      return $true
    }
  }

  return $false
}

function ConvertTo-OwnerLensDiagnosticStatus {
  param(
    [object[]]$EnabledSettings,
    [object[]]$LogAnalyticsSettings,
    [object[]]$ExternalSettings
  )

  if (@($LogAnalyticsSettings).Count -gt 0) {
    return "LogAnalytics"
  }

  if (@($ExternalSettings).Count -gt 0) {
    return "ExternalDestination"
  }

  if (@($EnabledSettings).Count -gt 0) {
    return "EnabledNoDestinationDetected"
  }

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
    enabledSettings = $enabledSettings
    logAnalyticsSettings = $logAnalyticsSettings
    externalSettings = $externalSettings
    status = ConvertTo-OwnerLensDiagnosticStatus `
      -EnabledSettings $enabledSettings `
      -LogAnalyticsSettings $logAnalyticsSettings `
      -ExternalSettings $externalSettings
    diagnosticSettingNames = @($enabledSettings | ForEach-Object { [string](Get-ObjectProperty -Object $_ -PropertyName "Name") } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    workspaceIds = @($logAnalyticsSettings | ForEach-Object { [string](Get-ObjectProperty -Object $_ -PropertyName "WorkspaceId") } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object -Unique)
    storageAccountIds = @($enabledSettings | ForEach-Object { [string](Get-ObjectProperty -Object $_ -PropertyName "StorageAccountId") } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object -Unique)
    eventHubAuthorizationRuleIds = @($enabledSettings | ForEach-Object { [string](Get-ObjectProperty -Object $_ -PropertyName "EventHubAuthorizationRuleId") } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object -Unique)
    marketplacePartnerIds = @($enabledSettings | ForEach-Object { [string](Get-ObjectProperty -Object $_ -PropertyName "MarketplacePartnerId") } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object -Unique)
  }
}

function Get-AzureStorageDiagnosticSummary {
  param(
    [object]$StorageAccount,
    [string[]]$DataPlaneReadServices
  )

  $storageAccountResourceId = [string]$StorageAccount.ResourceId
  $services = @($DataPlaneReadServices | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object -Unique)
  $serviceRows = @()

  foreach ($service in $services) {
    $serviceResourceId = Get-AzureStorageDiagnosticServiceResourceId `
      -StorageAccountResourceId $storageAccountResourceId `
      -Service $service

    try {
      $settings = @(Get-AzDiagnosticSetting -ResourceId $serviceResourceId -ErrorAction Stop)
      $diagnosticSummary = Get-OwnerLensDiagnosticSettingDestinationSummary -Settings $settings -EnabledPredicate {
          Test-AzureStorageDiagnosticLogEnabled -DiagnosticSetting $_
        }

      $serviceRows += [pscustomobject]@{
        service = [string]$service
        resourceId = $serviceResourceId
        status = [string]$diagnosticSummary.status
        dataAccessLogEnabled = [bool](@($diagnosticSummary.enabledSettings).Count -gt 0)
        logAnalyticsEnabled = [bool](@($diagnosticSummary.logAnalyticsSettings).Count -gt 0)
        diagnosticSettingNames = @($diagnosticSummary.diagnosticSettingNames)
        workspaceIds = @($diagnosticSummary.workspaceIds)
      }
    } catch {
      $serviceRows += [pscustomobject]@{
        service = [string]$service
        resourceId = $serviceResourceId
        status = "ReadFailed"
        dataAccessLogEnabled = $false
        logAnalyticsEnabled = $false
        diagnosticSettingNames = @()
        workspaceIds = @()
        error = [string]$_.Exception.Message
      }
    }
  }

  $logAnalyticsCount = @($serviceRows | Where-Object logAnalyticsEnabled).Count
  $loggedCount = @($serviceRows | Where-Object dataAccessLogEnabled).Count
  $failedCount = @($serviceRows | Where-Object status -eq "ReadFailed").Count

  [pscustomobject]@{
    services = @($serviceRows)
    diagnosticLogEnabled = [bool]($loggedCount -gt 0)
    diagnosticLogAnalyticsEnabled = [bool]($logAnalyticsCount -gt 0)
    dataAccessVerificationStatus = if ($services.Count -eq 0) {
      "NoDataPlaneService"
    } elseif ($logAnalyticsCount -eq $services.Count) {
      "QueryableInLogAnalytics"
    } elseif ($logAnalyticsCount -gt 0) {
      "PartiallyQueryableInLogAnalytics"
    } elseif ($loggedCount -gt 0) {
      "ConfiguredOutsideLogAnalytics"
    } elseif ($failedCount -gt 0) {
      "DiagnosticSettingsReadFailed"
    } else {
      "NotConfigured"
    }
    dataAccessVerificationReason = if ($services.Count -eq 0) {
      "No storage data-plane service was derived from the assigned RBAC roles."
    } elseif ($logAnalyticsCount -eq $services.Count) {
      "Data-plane diagnostic logs are enabled to Log Analytics for every storage service covered by the inspected RBAC roles."
    } elseif ($logAnalyticsCount -gt 0) {
      "Data-plane diagnostic logs are enabled to Log Analytics for only some storage services covered by the inspected RBAC roles."
    } elseif ($loggedCount -gt 0) {
      "Data-plane diagnostic logs are enabled, but no Log Analytics destination was detected; requester review may require the configured external destination."
    } elseif ($failedCount -gt 0) {
      "Diagnostic settings could not be read for one or more storage services."
    } else {
      "No data-plane diagnostic logs were detected, so historical requester verification is not available from Azure Storage resource logs."
    }
  }
}

function Test-AzureActivityDiagnosticLogEnabled {
  param(
    [object]$DiagnosticSetting
  )

  $logs = @(
    Get-ObjectProperty -Object $DiagnosticSetting -PropertyName "Logs"
    Get-ObjectProperty -Object $DiagnosticSetting -PropertyName "Log"
    Get-ObjectProperty -Object $DiagnosticSetting -PropertyName "EnabledLog"
  )

  foreach ($log in $logs) {
    $enabled = [bool](Get-ObjectProperty -Object $log -PropertyName "Enabled")
    if (-not $enabled) {
      continue
    }

    $category = [string](Get-ObjectProperty -Object $log -PropertyName "Category")
    $categoryGroup = [string](Get-ObjectProperty -Object $log -PropertyName "CategoryGroup")
    if (
      -not [string]::IsNullOrWhiteSpace($category) -or
      $categoryGroup.Equals("allLogs", [System.StringComparison]::OrdinalIgnoreCase) -or
      $categoryGroup.Equals("audit", [System.StringComparison]::OrdinalIgnoreCase)
    ) {
      return $true
    }
  }

  return $false
}

function Get-AzureActivityDiagnosticSummary {
  param(
    [object]$Subscription
  )

  $subscriptionResourceId = "/subscriptions/$($Subscription.Id)"

  try {
    $settings = @(Get-AzDiagnosticSetting -ResourceId $subscriptionResourceId -ErrorAction Stop)
    $diagnosticSummary = Get-OwnerLensDiagnosticSettingDestinationSummary -Settings $settings -EnabledPredicate {
        Test-AzureActivityDiagnosticLogEnabled -DiagnosticSetting $_
      }

    return [pscustomobject]@{
      subscriptionId = [string]$Subscription.Id
      subscriptionName = [string]$Subscription.Name
      resourceId = $subscriptionResourceId
      status = [string]$diagnosticSummary.status
      activityLogEnabled = [bool](@($diagnosticSummary.enabledSettings).Count -gt 0)
      logAnalyticsEnabled = [bool](@($diagnosticSummary.logAnalyticsSettings).Count -gt 0)
      diagnosticSettingNames = @($diagnosticSummary.diagnosticSettingNames)
      workspaceIds = @($diagnosticSummary.workspaceIds)
      storageAccountIds = @($diagnosticSummary.storageAccountIds)
      eventHubAuthorizationRuleIds = @($diagnosticSummary.eventHubAuthorizationRuleIds)
      marketplacePartnerIds = @($diagnosticSummary.marketplacePartnerIds)
    }
  } catch {
    return [pscustomobject]@{
      subscriptionId = [string]$Subscription.Id
      subscriptionName = [string]$Subscription.Name
      resourceId = $subscriptionResourceId
      status = "ReadFailed"
      activityLogEnabled = $false
      logAnalyticsEnabled = $false
      diagnosticSettingNames = @()
      workspaceIds = @()
      storageAccountIds = @()
      eventHubAuthorizationRuleIds = @()
      marketplacePartnerIds = @()
      error = [string]$_.Exception.Message
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
  $activityDiagnosticSettings = @()
  $storageAccountsWithRbac = @{}
  $activityStartTime = (Get-Date).AddDays(-$ActivityDays)
  $servicePrincipalObjectId = [string]$ServicePrincipal.objectId
  $candidateRoleAssignmentIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
  $queriedCoAssignedScopes = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
  $originalContext = Get-AzContext

  foreach ($subscription in $selectedSubscriptions) {
    try {
      Set-AzContext -SubscriptionId $subscription.Id -ErrorAction Stop | Out-Null
      $activityDiagnosticSettings += Get-AzureActivityDiagnosticSummary -Subscription $subscription

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

      $assignments = @(Get-AzRoleAssignment -ObjectId $servicePrincipalObjectId -ErrorAction Stop)
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
          isStorageDataReadRole = Test-AzureStorageDataReadRole -RoleDefinitionName ([string]$assignment.RoleDefinitionName)
          condition = [string]$assignment.Condition
          conditionVersion = [string]$assignment.ConditionVersion
        }

        $resourceDependencies += Find-AzureResourceForScope `
          -Scope ([string]$assignment.Scope) `
          -ResourceById $resourceById `
          -ResourceGroupByName $resourceGroupByName `
          -Subscription $subscription

        $dataReadServices = @(Get-AzureStorageDataReadServices -RoleDefinitionName ([string]$assignment.RoleDefinitionName))
        if ($dataReadServices.Count -gt 0) {
          foreach ($storageAccount in @(Get-AzureStorageAccountsForScope -Scope ([string]$assignment.Scope) -Resources $resources)) {
            $storageAccountResourceId = [string]$storageAccount.ResourceId
            if ([string]::IsNullOrWhiteSpace($storageAccountResourceId)) {
              continue
            }

            if (-not $storageAccountsWithRbac.ContainsKey($storageAccountResourceId)) {
              $storageAccountsWithRbac[$storageAccountResourceId] = [ordered]@{
                resource = $storageAccount
                dataPlaneReadServices = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
                dataPlaneReadRoleNames = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
                rbacScopes = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
              }
            }

            foreach ($service in $dataReadServices) {
              $storageAccountsWithRbac[$storageAccountResourceId].dataPlaneReadServices.Add([string]$service) | Out-Null
            }

            $storageAccountsWithRbac[$storageAccountResourceId].dataPlaneReadRoleNames.Add([string]$assignment.RoleDefinitionName) | Out-Null
            $storageAccountsWithRbac[$storageAccountResourceId].rbacScopes.Add([string]$assignment.Scope) | Out-Null
          }
        }

        $assignmentScope = [string]$assignment.Scope
        if (-not $queriedCoAssignedScopes.Add($assignmentScope)) {
          continue
        }

        $sameScopeAssignments = @(Get-AzRoleAssignment -Scope $assignmentScope -ErrorAction Stop)
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
            isStorageDataReadRole = Test-AzureStorageDataReadRole -RoleDefinitionName ([string]$sameScopeAssignment.RoleDefinitionName)
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
    } finally {
      if ($originalContext) {
        try {
          Set-AzContext -Context $originalContext -ErrorAction Stop | Out-Null
        } catch {
          Write-Warning "Failed to restore the original Azure context after OwnerLens collection."
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
    activityDiagnosticSettings = @($activityDiagnosticSettings | Sort-Object subscriptionName, resourceId)
    blobReadEvidence = @($blobReadEvidence | Sort-Object eventTimestamp, storageAccountName, uri)
    blobReadCallers = @(Get-StorageBlobReadCallers -BlobReadEvidence @($blobReadEvidence) |
      Sort-Object @{ Expression = "blobAccessCount"; Descending = $true }, lastSeen)
    blobReadObjects = @(Get-StorageBlobReadObjects -BlobReadEvidence @($blobReadEvidence) |
      Sort-Object @{ Expression = "blobReadCount"; Descending = $true }, lastReadAt)
    storageAccountsWithRbac = @($storageAccountsWithRbac.Values | ForEach-Object {
      $storageAccount = $_.resource
      $diagnosticSummary = Get-AzureStorageDiagnosticSummary `
        -StorageAccount $storageAccount `
        -DataPlaneReadServices @($_.dataPlaneReadServices)
      [pscustomobject]@{
        resourceId = [string]$storageAccount.ResourceId
        name = [string]$storageAccount.Name
        resourceGroup = [string]$storageAccount.ResourceGroupName
        location = [string]$storageAccount.Location
        dataPlaneReadServices = @($_.dataPlaneReadServices | Sort-Object)
        dataPlaneReadRoleNames = @($_.dataPlaneReadRoleNames | Sort-Object)
        rbacScopes = @($_.rbacScopes | Sort-Object)
        diagnosticSettings = @($diagnosticSummary.services)
        diagnosticLogEnabled = [bool]$diagnosticSummary.diagnosticLogEnabled
        diagnosticLogAnalyticsEnabled = [bool]$diagnosticSummary.diagnosticLogAnalyticsEnabled
        dataAccessVerificationStatus = [string]$diagnosticSummary.dataAccessVerificationStatus
        dataAccessVerificationReason = [string]$diagnosticSummary.dataAccessVerificationReason
      }
    } | Sort-Object name)
    logAnalyticsWorkspaceId = [string]$LogAnalyticsWorkspaceId
    maxBlobReadRecords = $MaxBlobReadRecords
    activityStartTime = $activityStartTime.ToUniversalTime().ToString("o")
    maxActivityRecords = $MaxActivityRecords
    activitySkipped = [bool]$SkipActivityLogs
  }
}
