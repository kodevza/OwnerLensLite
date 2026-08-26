function Get-AzureDependencies {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)] [object]$ServicePrincipal,
    [string]$SubscriptionIds = "",
    [ValidateRange(1, 3650)] [int]$ActivityDays = 30,
    [ValidateRange(1, 1000000)] [int]$MaxActivityRecords = 5000,
    [string]$LogAnalyticsWorkspaceId = "",
    [ValidateRange(1, 1000000)] [int]$MaxBlobReadRecords = 5000,
    [string[]]$BlobReadOperationNames = @("GetBlob", "PutBlob", "PutBlock", "PutBlockList", "AppendBlock", "CopyBlob"),
    [switch]$SkipActivityLogs
  )

  $subscriptionFilters = Get-AzureSubscriptionFilters -SubscriptionIds $SubscriptionIds
  $enabledSubscriptions = Get-AzSubscription | Where-Object State -EQ "Enabled"
  $selectedSubscriptions = @()
  foreach ($filter in $subscriptionFilters) {
    $subscription = $enabledSubscriptions | Where-Object { $_.Id -eq $filter -or $_.Name -eq $filter } | Select-Object -First 1
    if (-not $subscription) { throw "Subscription not found or not enabled: $filter" }
    if (-not ($selectedSubscriptions | Where-Object Id -EQ $subscription.Id)) { $selectedSubscriptions += $subscription }
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
        if (-not [string]::IsNullOrWhiteSpace([string]$resource.ResourceId)) { $resourceById[[string]$resource.ResourceId] = $resource }
      }
      $resourceGroupByName = @{}
      foreach ($resourceGroup in $resourceGroups) {
        if (-not [string]::IsNullOrWhiteSpace([string]$resourceGroup.ResourceGroupName)) { $resourceGroupByName[[string]$resourceGroup.ResourceGroupName] = $resourceGroup }
      }

      $assignments = @(Get-AzRoleAssignment -ObjectId $servicePrincipalObjectId -ErrorAction Stop)
      foreach ($assignment in $assignments) {
        $roleAssignments += [pscustomobject]@{
          subscriptionId = [string]$subscription.Id; subscriptionName = [string]$subscription.Name; roleAssignmentId = [string]$assignment.RoleAssignmentId
          scope = [string]$assignment.Scope; principalId = [string]$assignment.ObjectId; principalType = [string]$assignment.ObjectType; principalDisplayName = [string]$assignment.DisplayName
          roleDefinitionId = [string]$assignment.RoleDefinitionId; roleDefinitionName = [string]$assignment.RoleDefinitionName
          isStorageDataReadRole = Test-AzureStorageDataReadRole -RoleDefinitionName ([string]$assignment.RoleDefinitionName)
          condition = [string]$assignment.Condition; conditionVersion = [string]$assignment.ConditionVersion
        }
        $resourceDependencies += Find-AzureResourceForScope -Scope ([string]$assignment.Scope) -ResourceById $resourceById -ResourceGroupByName $resourceGroupByName -Subscription $subscription

        $dataReadServices = @(Get-AzureStorageDataReadServices -RoleDefinitionName ([string]$assignment.RoleDefinitionName))
        if ($dataReadServices.Count -gt 0) {
          foreach ($storageAccount in @(Get-AzureStorageAccountsForScope -Scope ([string]$assignment.Scope) -Resources $resources)) {
            $storageAccountResourceId = [string]$storageAccount.ResourceId
            if ([string]::IsNullOrWhiteSpace($storageAccountResourceId)) { continue }
            if (-not $storageAccountsWithRbac.ContainsKey($storageAccountResourceId)) {
              $storageAccountsWithRbac[$storageAccountResourceId] = [ordered]@{
                resource               = $storageAccount
                dataPlaneReadServices  = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
                dataPlaneReadRoleNames = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
                rbacScopes             = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
              }
            }
            foreach ($service in $dataReadServices) { $storageAccountsWithRbac[$storageAccountResourceId].dataPlaneReadServices.Add([string]$service) | Out-Null }
            $storageAccountsWithRbac[$storageAccountResourceId].dataPlaneReadRoleNames.Add([string]$assignment.RoleDefinitionName) | Out-Null
            $storageAccountsWithRbac[$storageAccountResourceId].rbacScopes.Add([string]$assignment.Scope) | Out-Null
          }
        }

        $assignmentScope = [string]$assignment.Scope
        if (-not $queriedCoAssignedScopes.Add($assignmentScope)) { continue }
        $sameScopeAssignments = @(Get-AzRoleAssignment -Scope $assignmentScope -ErrorAction Stop)
        foreach ($sameScopeAssignment in $sameScopeAssignments) {
          if (-not ([string]$sameScopeAssignment.Scope).Equals([string]$assignment.Scope, [System.StringComparison]::OrdinalIgnoreCase)) { continue }
          $candidatePrincipalId = [string]$sameScopeAssignment.ObjectId
          if ([string]::IsNullOrWhiteSpace($candidatePrincipalId)) { continue }
          if ($candidatePrincipalId.Equals($servicePrincipalObjectId, [System.StringComparison]::OrdinalIgnoreCase)) { continue }
          $candidateRoleAssignmentId = [string]$sameScopeAssignment.RoleAssignmentId
          if (-not [string]::IsNullOrWhiteSpace($candidateRoleAssignmentId) -and -not $candidateRoleAssignmentIds.Add($candidateRoleAssignmentId)) { continue }
          $coAssignedRoleCandidates += [pscustomobject]@{
            subscriptionId = [string]$subscription.Id; subscriptionName = [string]$subscription.Name; roleAssignmentId = $candidateRoleAssignmentId; scope = [string]$sameScopeAssignment.Scope
            principalId           = $candidatePrincipalId
            principalType         = [string]$sameScopeAssignment.ObjectType
            principalName         = [string]$sameScopeAssignment.SignInName
            principalDisplayName  = [string]$sameScopeAssignment.DisplayName
            roleDefinitionId = [string]$sameScopeAssignment.RoleDefinitionId; roleDefinitionName = [string]$sameScopeAssignment.RoleDefinitionName
            isStorageDataReadRole = Test-AzureStorageDataReadRole -RoleDefinitionName ([string]$sameScopeAssignment.RoleDefinitionName)
          }
        }
      }

      if (-not $SkipActivityLogs) {
        $logs = Get-AzureActivityLogs -SubscriptionId ([string]$subscription.Id) -StartTime $activityStartTime -MaxRecord $MaxActivityRecords
        foreach ($log in @($logs)) {
          foreach ($assignment in $assignments) {
            if (Test-AzureActivityLogMatchesScope -Log $log -Scope ([string]$assignment.Scope)) {
              $rbacScopeActivityEvidence += New-AzureRbacScopeActivityEvidence -Subscription $subscription -Log $log -RoleAssignment $assignment -ServicePrincipal $ServicePrincipal
            }
          }
          if (Test-ActivityLogMatchesServicePrincipal -Log $log -ServicePrincipal $ServicePrincipal) {
            $activityEvidence += [pscustomobject]@{
              subscriptionId     = [string]$subscription.Id
              subscriptionName   = [string]$subscription.Name
              eventTimestamp     = [string]$log.eventTimestamp
              caller             = [string]$log.caller
              callerObjectId     = [string]$log.callerObjectId
              callerAppId        = [string]$log.callerAppId
              callerName         = [string]$log.callerName
              operationName      = [string]$log.operationName
              operationNameValue = [string]$log.operationNameValue
              status             = [string]$log.status
              resourceGroupName  = [string]$log.resourceGroupName
              resourceId         = [string]$log.resourceId
              resourceType       = [string]$log.resourceType
              authorizationAction = [string]$log.authorizationAction; authorizationScope = [string]$log.authorizationScope; evidenceConfidence = "low"
              evidenceReason     = "Activity logs show recent use by this service principal identifier; this is access evidence, not ownership proof."
            }
          }
        }
      }
    }
    finally {
      if ($originalContext) {
        try { Set-AzContext -Context $originalContext -ErrorAction Stop | Out-Null } catch { Write-Warning "Failed to restore the original Azure context after OwnerLens collection." }
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
    requestedSubscriptions     = @($subscriptionFilters)
    subscriptions              = @($selectedSubscriptions | ForEach-Object { [pscustomobject]@{ subscriptionId = [string]$_.Id; subscriptionName = [string]$_.Name; tenantId = [string]$_.TenantId } })
    roleAssignments            = @($roleAssignments | Sort-Object subscriptionName, scope, roleDefinitionName)
    coAssignedRoleCandidates   = @($coAssignedRoleCandidates | Sort-Object subscriptionName, scope, principalDisplayName, roleDefinitionName)
    resourceDependencies       = @($resourceDependencies | Sort-Object resourceId -Unique | Sort-Object dependencyType, resourceGroup, resourceName)
    activityEvidence           = @($activityEvidence | Sort-Object eventTimestamp, resourceId)
    rbacScopeActivityEvidence  = @($rbacScopeActivityEvidence | Sort-Object eventTimestamp, rbacScope, resourceId)
    rbacScopeActivityCallers   = @(Get-AzureRbacScopeActivityCallers -ActivityEvidence @($rbacScopeActivityEvidence) | Sort-Object @{ Expression = "eventCount"; Descending = $true }, lastSeen)
    activityDiagnosticSettings = @($activityDiagnosticSettings | Sort-Object subscriptionName, resourceId)
    blobReadEvidence           = @($blobReadEvidence | Sort-Object eventTimestamp, storageAccountName, uri)
    blobReadCallers            = @(Get-StorageBlobReadCallers -BlobReadEvidence @($blobReadEvidence) | Sort-Object @{ Expression = "blobAccessCount"; Descending = $true }, lastSeen)
    blobReadObjects            = @(Get-StorageBlobReadObjects -BlobReadEvidence @($blobReadEvidence) | Sort-Object @{ Expression = "blobReadCount"; Descending = $true }, lastReadAt)
    storageAccountsWithRbac    = @($storageAccountsWithRbac.Values | ForEach-Object {
        $storageAccount = $_.resource
        $diagnosticSummary = Get-AzureStorageDiagnosticSummary -StorageAccount $storageAccount -DataPlaneReadServices @($_.dataPlaneReadServices)
        [pscustomobject]@{
          resourceId = [string]$storageAccount.ResourceId; name = [string]$storageAccount.Name; resourceGroup = [string]$storageAccount.ResourceGroupName; location = [string]$storageAccount.Location
          dataPlaneReadServices = @($_.dataPlaneReadServices | Sort-Object); dataPlaneReadRoleNames = @($_.dataPlaneReadRoleNames | Sort-Object); rbacScopes = @($_.rbacScopes | Sort-Object)
          diagnosticSettings            = @($diagnosticSummary.services)
          diagnosticLogEnabled          = [bool]$diagnosticSummary.diagnosticLogEnabled
          diagnosticLogAnalyticsEnabled = [bool]$diagnosticSummary.diagnosticLogAnalyticsEnabled
          dataAccessVerificationStatus = [string]$diagnosticSummary.dataAccessVerificationStatus; dataAccessVerificationReason = [string]$diagnosticSummary.dataAccessVerificationReason
        }
      } | Sort-Object name)
    logAnalyticsWorkspaceId    = [string]$LogAnalyticsWorkspaceId
    maxBlobReadRecords         = $MaxBlobReadRecords
    activityStartTime          = $activityStartTime.ToUniversalTime().ToString("o")
    maxActivityRecords         = $MaxActivityRecords
    activitySkipped            = [bool]$SkipActivityLogs
  }
}
