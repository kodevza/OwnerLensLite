function Get-OwnerLensReportValue {
  param(
    [Parameter(Mandatory = $true)]
    [object]$Report,

    [Parameter(Mandatory = $true)]
    [string]$Path,

    [AllowNull()]
    [object]$Fallback = $null
  )

  $current = $Report
  foreach ($segment in @($Path -split "\.")) {
    if ($null -eq $current) {
      return $Fallback
    }

    $property = $current.PSObject.Properties[$segment]
    if ($null -eq $property) {
      return $Fallback
    }

    $current = $property.Value
  }

  if ($null -eq $current) {
    return $Fallback
  }

  return $current
}

function Get-OwnerLensReportArray {
  param(
    [Parameter(Mandatory = $true)]
    [object]$Report,

    [Parameter(Mandatory = $true)]
    [string]$Path
  )

  return @(Get-OwnerLensReportValue -Report $Report -Path $Path -Fallback @())
}

function New-OwnerLensReport {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]
    [object]$ServicePrincipal,

    [Parameter(Mandatory = $true)]
    [object]$GraphDependencies,

    [Parameter(Mandatory = $true)]
    [object]$AzureDependencies,

    [int]$ActivityDays = 30,

    [int]$MaxActivityRecords = 5000,

    [string]$SignInUser = "",

    [int]$MaxUserSignInRecords = 5000,

    [string[]]$BlobReadOperationNames = @(),

    [string[]]$UserOwnerTagNames = @(),

    [string[]]$GroupOwnerTagNames = @(),

    [string[]]$TagOwnerTagNames = @(),

    [switch]$SkipActivityLogs
  )

  $report = [pscustomobject]@{
    meta = [pscustomobject]@{
      reportType = "enterpriseApplicationDependencies"
      createdAt = (Get-Date).ToUniversalTime().ToString("o")
      activityDays = $ActivityDays
      activityStartTime = $AzureDependencies.activityStartTime
      maxActivityRecords = $MaxActivityRecords
      signInUser = $SignInUser
      maxUserSignInRecords = $MaxUserSignInRecords
      logAnalyticsWorkspaceId = $AzureDependencies.logAnalyticsWorkspaceId
      maxBlobReadRecords = $AzureDependencies.maxBlobReadRecords
      blobReadOperationNames = @($BlobReadOperationNames)
      activitySkipped = [bool]$SkipActivityLogs
      requestedSubscriptions = @($AzureDependencies.requestedSubscriptions)
      ownerTagConfiguration = [pscustomobject]@{
        userOwnerTagNames = @($UserOwnerTagNames)
        groupOwnerTagNames = @($GroupOwnerTagNames)
        tagOwnerTagNames = @($TagOwnerTagNames)
      }
    }
    enterpriseApplication = $ServicePrincipal
    summary = [pscustomobject]@{
      azureSubscriptions = @($AzureDependencies.subscriptions).Count
      azureRoleAssignments = @($AzureDependencies.roleAssignments).Count
      azureDependencyScopes = @($AzureDependencies.resourceDependencies).Count
      azureActivityRecords = @($AzureDependencies.activityEvidence).Count
      azureRbacScopeActivityRecords = @($AzureDependencies.rbacScopeActivityEvidence).Count
      azureRbacScopeActivityCallers = @($AzureDependencies.rbacScopeActivityCallers).Count
      azureActivityLogDiagnosticSettings = @($AzureDependencies.activityDiagnosticSettings | Where-Object activityLogEnabled).Count
      azureActivityLogAnalyticsDiagnostics = @($AzureDependencies.activityDiagnosticSettings | Where-Object logAnalyticsEnabled).Count
      azureStorageAccountsWithRbac = @($AzureDependencies.storageAccountsWithRbac).Count
      azureStorageAccountsWithDiagnosticLogs = @($AzureDependencies.storageAccountsWithRbac | Where-Object diagnosticLogEnabled).Count
      azureStorageAccountsWithLogAnalyticsDiagnostics = @($AzureDependencies.storageAccountsWithRbac | Where-Object diagnosticLogAnalyticsEnabled).Count
      azureBlobReadRecords = @($AzureDependencies.blobReadEvidence).Count
      azureBlobReadCallers = @($AzureDependencies.blobReadCallers).Count
      azureBlobReadObjects = @($AzureDependencies.blobReadObjects).Count
      graphAppRoleAssignments = @($GraphDependencies.appRoleAssignments).Count
      graphDelegatedPermissionGrants = @($GraphDependencies.oauth2PermissionGrants).Count
      graphGroupMemberships = @($GraphDependencies.memberOf).Count
      graphResourceServicePrincipals = @($GraphDependencies.resourceServicePrincipals).Count
      graphUserSignIns = @($GraphDependencies.userSignIns).Count
      owners = @($GraphDependencies.owners).Count
    }
    azure = [pscustomobject]@{
      subscriptions = @($AzureDependencies.subscriptions)
      roleAssignments = @($AzureDependencies.roleAssignments)
      coAssignedRoleCandidates = @($AzureDependencies.coAssignedRoleCandidates)
      resourceDependencies = @($AzureDependencies.resourceDependencies)
      activityEvidence = @($AzureDependencies.activityEvidence)
      rbacScopeActivityEvidence = @($AzureDependencies.rbacScopeActivityEvidence)
      rbacScopeActivityCallers = @($AzureDependencies.rbacScopeActivityCallers)
      activityDiagnosticSettings = @($AzureDependencies.activityDiagnosticSettings)
      storageAccountsWithRbac = @($AzureDependencies.storageAccountsWithRbac)
      blobReadEvidence = @($AzureDependencies.blobReadEvidence)
      blobReadCallers = @($AzureDependencies.blobReadCallers)
      blobReadObjects = @($AzureDependencies.blobReadObjects)
    }
    graph = $GraphDependencies
    notes = @(
      "Azure RBAC scopes show where the Enterprise Application service principal has assigned access.",
      "Azure Monitor activity evidence is low-confidence usage evidence from the selected activity window; it is not proof of ownership.",
      "Azure RBAC scope activity callers show recent management-plane activity under scopes where the Enterprise Application service principal has RBAC; data-plane access requires resource diagnostic logs.",
      "Storage account sections include only accounts where the Enterprise Application service principal has Storage Blob/Table/Queue data-plane read access, not accounts visible only through management-plane metadata access.",
      "Storage diagnostic status is checked on the Blob/Table/Queue service resources covered by the assigned data-plane RBAC roles.",
      "Azure blob data-plane evidence is available only when -LogAnalyticsWorkspaceId points to a workspace that receives StorageBlobLogs from the relevant storage accounts.",
      "Microsoft Graph user sign-ins are loaded only when -SignInUser is provided and require AuditLog.Read.All plus tenant sign-in log retention for the selected ActivityDays window.",
      "Microsoft Graph app role assignments and delegated permission grants show API dependencies."
    )
  }

  $report | Add-Member -MemberType NoteProperty -Name ownerCandidates -Value @(Get-OwnerCandidates `
      -Report $report `
      -UserOwnerTagNames $UserOwnerTagNames `
      -GroupOwnerTagNames $GroupOwnerTagNames `
      -TagOwnerTagNames $TagOwnerTagNames)

  return $report
}
