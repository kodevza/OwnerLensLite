function Format-DependencyReport {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]
    [object]$Report
  )

  $sp = $Report.enterpriseApplication
  Write-Host ""
  Write-Host "OwnerLens Light Enterprise Application Dependency Report"
  Write-Host "========================================================"
  Write-Host "Enterprise application: $($sp.displayName)"
  Write-Host "Object ID: $($sp.objectId)"
  Write-Host "App ID: $($sp.appId)"
  Write-Host "Account enabled: $($sp.accountEnabled)"
  Write-Host "Created at: $($Report.meta.createdAt)"
  Write-Host ""

  Write-Host "Summary"
  Write-Host "-------"
  Write-Host "Azure role assignments: $($Report.summary.azureRoleAssignments)"
  Write-Host "Azure dependency scopes: $($Report.summary.azureDependencyScopes)"
  Write-Host "Recent Azure activity records: $($Report.summary.azureActivityRecords)"
  Write-Host "Recent Azure RBAC scope activity callers: $($Report.summary.azureRbacScopeActivityCallers)"
  Write-Host "Storage accounts with RBAC: $($Report.summary.azureStorageAccountsWithRbac)"
  Write-Host "Recent blob data-plane participants: $($Report.summary.azureBlobReadCallers)"
  Write-Host "Recent blob data-plane records: $($Report.summary.azureBlobReadRecords)"
  Write-Host "Graph app role assignments: $($Report.summary.graphAppRoleAssignments)"
  Write-Host "Graph delegated permission grants: $($Report.summary.graphDelegatedPermissionGrants)"
  Write-Host "Graph group memberships: $($Report.summary.graphGroupMemberships)"
  Write-Host "Owners: $($Report.summary.owners)"
  Write-Host ""

  if ($Report.azure.roleAssignments.Count -gt 0) {
    Write-Host "Azure RBAC"
    Write-Host "----------"
    $Report.azure.roleAssignments |
      Select-Object subscriptionName, roleDefinitionName, scope |
      Format-Table -AutoSize
  }

  if ($Report.azure.resourceDependencies.Count -gt 0) {
    Write-Host "Azure Dependency Scopes"
    Write-Host "-----------------------"
    $Report.azure.resourceDependencies |
      Select-Object dependencyType, resourceName, resourceGroup, resourceType, resourceId |
      Format-Table -AutoSize
  }

  if ($Report.azure.activityEvidence.Count -gt 0) {
    Write-Host "Recent Azure Activity Evidence"
    Write-Host "------------------------------"
    $Report.azure.activityEvidence |
      Select-Object eventTimestamp, subscriptionName, operationNameValue, resourceId, status |
      Format-Table -AutoSize
  }

  if ($Report.azure.rbacScopeActivityCallers.Count -gt 0) {
    Write-Host "Recent Azure RBAC Scope Activity Callers"
    Write-Host "----------------------------------------"
    $Report.azure.rbacScopeActivityCallers |
      Select-Object callerName, caller, callerObjectId, callerAppId, eventCount, firstSeen, lastSeen, matchesInspectedServicePrincipal |
      Format-Table -AutoSize
  }

  if ($Report.azure.rbacScopeActivityEvidence.Count -gt 0) {
    Write-Host "Recent Azure RBAC Scope Activity Evidence"
    Write-Host "-----------------------------------------"
    $Report.azure.rbacScopeActivityEvidence |
      Select-Object eventTimestamp, callerName, caller, operationNameValue, resourceId, rbacScope, status |
      Format-Table -AutoSize
  }

  if ($Report.azure.storageAccountsWithRbac.Count -gt 0) {
    Write-Host "Storage Accounts Under Azure RBAC Scopes"
    Write-Host "----------------------------------------"
    $Report.azure.storageAccountsWithRbac |
      Select-Object name, resourceGroup, location, resourceId |
      Format-Table -AutoSize
  }

  if ($Report.azure.blobReadCallers.Count -gt 0) {
    Write-Host "Recent Blob Data-Plane Participants"
    Write-Host "-----------------------------------"
    $Report.azure.blobReadCallers |
      Select-Object requesterUpn, requesterObjectId, requesterAppId, requesterType, authenticationType, blobReadCount, blobPublishCount, blobAccessCount, firstSeen, lastSeen, matchesInspectedServicePrincipal |
      Format-Table -AutoSize
  }

  if ($Report.azure.blobReadEvidence.Count -gt 0) {
    Write-Host "Recent Blob Data-Plane Evidence"
    Write-Host "-------------------------------"
    $Report.azure.blobReadEvidence |
      Select-Object eventTimestamp, storageAccountName, accessDirection, requesterUpn, requesterObjectId, requesterAppId, requesterType, operationName, statusText, uri |
      Format-Table -AutoSize
  }

  if ($Report.graph.appRoleAssignments.Count -gt 0) {
    Write-Host "Microsoft Graph App Role Assignments"
    Write-Host "------------------------------------"
    $Report.graph.appRoleAssignments |
      Select-Object resourceDisplayName, appRoleId, createdDateTime |
      Format-Table -AutoSize
  }

  if ($Report.graph.oauth2PermissionGrants.Count -gt 0) {
    Write-Host "Microsoft Graph Delegated Permission Grants"
    Write-Host "-------------------------------------------"
    $Report.graph.oauth2PermissionGrants |
      Select-Object resourceId, consentType, scope |
      Format-Table -AutoSize
  }

  if ($Report.graph.memberOf.Count -gt 0) {
    Write-Host "Microsoft Graph Group Memberships"
    Write-Host "---------------------------------"
    $Report.graph.memberOf |
      Select-Object displayName, objectId, objectType |
      Format-Table -AutoSize
  }
}
