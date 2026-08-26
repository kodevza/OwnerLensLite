function Test-ActivityLogMatchesServicePrincipal {
  param([object]$Log, [object]$ServicePrincipal)

  $objectId = [string]$ServicePrincipal.objectId
  $appId = [string]$ServicePrincipal.appId
  $displayName = [string]$ServicePrincipal.displayName
  $callerObjectId = [string]$Log.callerObjectId
  $callerAppId = [string]$Log.callerAppId
  $caller = [string]$Log.caller
  $callerName = [string]$Log.callerName

  if ($objectId -and $callerObjectId -and $callerObjectId.Equals($objectId, [System.StringComparison]::OrdinalIgnoreCase)) { return $true }
  if ($appId -and $callerAppId -and $callerAppId.Equals($appId, [System.StringComparison]::OrdinalIgnoreCase)) { return $true }
  if ($appId -and $caller -and $caller.Equals($appId, [System.StringComparison]::OrdinalIgnoreCase)) { return $true }
  if ($displayName -and $callerName -and $callerName.Equals($displayName, [System.StringComparison]::OrdinalIgnoreCase)) { return $true }
  return $false
}

function Test-AzureActivityLogMatchesScope {
  param([object]$Log, [string]$Scope)

  if ([string]::IsNullOrWhiteSpace($Scope)) { return $false }
  $normalizedScope = ([string]$Scope).TrimEnd("/")
  $candidateScopes = @([string]$Log.authorizationScope, [string]$Log.resourceId) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
  foreach ($candidateScope in $candidateScopes) {
    $normalizedCandidateScope = ([string]$candidateScope).TrimEnd("/")
    if ($normalizedCandidateScope.Equals($normalizedScope, [System.StringComparison]::OrdinalIgnoreCase)) { return $true }
    if ($normalizedCandidateScope.StartsWith("$normalizedScope/", [System.StringComparison]::OrdinalIgnoreCase)) { return $true }
  }

  return $false
}

function New-AzureRbacScopeActivityEvidence {
  param([object]$Subscription, [object]$Log, [object]$RoleAssignment, [object]$ServicePrincipal)

  [pscustomobject]@{
    subscriptionId                   = [string]$Subscription.Id
    subscriptionName                 = [string]$Subscription.Name
    rbacScope                        = [string]$RoleAssignment.Scope
    rbacRoleDefinitionName           = [string]$RoleAssignment.RoleDefinitionName
    eventTimestamp                   = [string]$Log.eventTimestamp
    caller                           = [string]$Log.caller
    callerObjectId                   = [string]$Log.callerObjectId
    callerAppId                      = [string]$Log.callerAppId
    callerName                       = [string]$Log.callerName
    callerTenantId                   = [string]$Log.callerTenantId
    operationName                    = [string]$Log.operationName
    operationNameValue               = [string]$Log.operationNameValue
    status                           = [string]$Log.status
    resourceGroupName                = [string]$Log.resourceGroupName
    resourceId                       = [string]$Log.resourceId
    resourceType                     = [string]$Log.resourceType
    authorizationAction              = [string]$Log.authorizationAction
    authorizationScope               = [string]$Log.authorizationScope
    matchesInspectedServicePrincipal = [bool](Test-ActivityLogMatchesServicePrincipal -Log $Log -ServicePrincipal $ServicePrincipal)
    evidenceConfidence               = "low"
    evidenceReason                   = "Activity logs show management-plane operations under an RBAC scope assigned to the inspected service principal; this is access context, not ownership proof."
  }
}

function Get-AzureRbacScopeActivityCallers {
  param([object[]]$ActivityEvidence)

  $groups = @($ActivityEvidence) | Group-Object -Property {
    $callerObjectId = [string]$_.callerObjectId
    $callerAppId = [string]$_.callerAppId
    $caller = [string]$_.caller
    $callerName = [string]$_.callerName
    if (-not [string]::IsNullOrWhiteSpace($callerObjectId)) { return "object:$callerObjectId" }
    if (-not [string]::IsNullOrWhiteSpace($callerAppId)) { return "app:$callerAppId" }
    if (-not [string]::IsNullOrWhiteSpace($caller)) { return "caller:$caller" }
    if (-not [string]::IsNullOrWhiteSpace($callerName)) { return "name:$callerName" }
    return "unknown"
  }

  foreach ($group in $groups) {
    $items = @($group.Group | Sort-Object eventTimestamp)
    $first = $items | Select-Object -First 1
    $last = $items | Select-Object -Last 1
    [pscustomobject]@{
      callerKey                        = [string]$group.Name
      caller                           = [string]$last.caller
      callerObjectId                   = [string]$last.callerObjectId
      callerAppId                      = [string]$last.callerAppId
      callerName                       = [string]$last.callerName
      callerTenantId                   = [string]$last.callerTenantId
      eventCount                       = [int]$items.Count
      firstSeen                        = [string]$first.eventTimestamp
      lastSeen                         = [string]$last.eventTimestamp
      subscriptions                    = @($items | Select-Object -ExpandProperty subscriptionName -Unique)
      rbacScopes                       = @($items | Select-Object -ExpandProperty rbacScope -Unique)
      resourceIds                      = @($items | Select-Object -ExpandProperty resourceId -Unique | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
      operationNames                   = @($items | Select-Object -ExpandProperty operationNameValue -Unique | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
      matchesInspectedServicePrincipal = [bool](@($items | Where-Object matchesInspectedServicePrincipal).Count -gt 0)
      evidenceConfidence               = "low"
      evidenceReason                   = "Caller performed recent management-plane operations under one or more RBAC scopes assigned to the inspected service principal."
    }
  }
}

function Test-AzureActivityDiagnosticLogEnabled {
  param([object]$DiagnosticSetting)

  $logs = @(
    Get-ObjectProperty -Object $DiagnosticSetting -PropertyName "Logs"
    Get-ObjectProperty -Object $DiagnosticSetting -PropertyName "Log"
    Get-ObjectProperty -Object $DiagnosticSetting -PropertyName "EnabledLog"
  )
  foreach ($log in $logs) {
    if (-not [bool](Get-ObjectProperty -Object $log -PropertyName "Enabled")) { continue }
    $category = [string](Get-ObjectProperty -Object $log -PropertyName "Category")
    $categoryGroup = [string](Get-ObjectProperty -Object $log -PropertyName "CategoryGroup")
    if (
      -not [string]::IsNullOrWhiteSpace($category) -or
      $categoryGroup.Equals("allLogs", [System.StringComparison]::OrdinalIgnoreCase) -or
      $categoryGroup.Equals("audit", [System.StringComparison]::OrdinalIgnoreCase)
    ) { return $true }
  }

  return $false
}

function Get-AzureActivityDiagnosticSummary {
  param([object]$Subscription)

  $subscriptionResourceId = "/subscriptions/$($Subscription.Id)"
  try {
    $settings = @(Get-AzDiagnosticSetting -ResourceId $subscriptionResourceId -ErrorAction Stop)
    $diagnosticSummary = Get-OwnerLensDiagnosticSettingDestinationSummary -Settings $settings -EnabledPredicate { Test-AzureActivityDiagnosticLogEnabled -DiagnosticSetting $_ }
    return [pscustomobject]@{
      subscriptionId = [string]$Subscription.Id; subscriptionName = [string]$Subscription.Name; resourceId = $subscriptionResourceId
      status                       = [string]$diagnosticSummary.status
      activityLogEnabled           = [bool](@($diagnosticSummary.enabledSettings).Count -gt 0)
      logAnalyticsEnabled          = [bool](@($diagnosticSummary.logAnalyticsSettings).Count -gt 0)
      diagnosticSettingNames       = @($diagnosticSummary.diagnosticSettingNames)
      workspaceIds                 = @($diagnosticSummary.workspaceIds)
      storageAccountIds            = @($diagnosticSummary.storageAccountIds)
      eventHubAuthorizationRuleIds = @($diagnosticSummary.eventHubAuthorizationRuleIds)
      marketplacePartnerIds        = @($diagnosticSummary.marketplacePartnerIds)
    }
  }
  catch {
    return [pscustomobject]@{
      subscriptionId               = [string]$Subscription.Id
      subscriptionName             = [string]$Subscription.Name
      resourceId                   = $subscriptionResourceId
      status                       = "ReadFailed"
      activityLogEnabled           = $false
      logAnalyticsEnabled          = $false
      diagnosticSettingNames       = @()
      workspaceIds                 = @()
      storageAccountIds            = @()
      eventHubAuthorizationRuleIds = @()
      marketplacePartnerIds        = @()
      error                        = [string]$_.Exception.Message
    }
  }
}
