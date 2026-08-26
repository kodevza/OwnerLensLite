function Invoke-OwnerLensAssessment {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]
    [string]$EnterpriseApplication,

    [string]$SubscriptionIds = "",

    [ValidateRange(1, 3650)]
    [int]$ActivityDays = 30,

    [ValidateRange(1, 1000000)]
    [int]$MaxActivityRecords = 5000,

    [string]$SignInUser = "",

    [ValidateRange(1, 1000000)]
    [int]$MaxUserSignInRecords = 5000,

    [string]$LogAnalyticsWorkspaceId = "",

    [ValidateRange(1, 1000000)]
    [int]$MaxBlobReadRecords = 5000,

    [string[]]$BlobReadOperationNames = @("GetBlob", "PutBlob", "PutBlock", "PutBlockList", "AppendBlock", "CopyBlob"),

    [string[]]$UserOwnerTagNames = @("userOwner", "technicalOwner", "businessOwner"),

    [string[]]$GroupOwnerTagNames = @("groupOwner", "ownerGroup", "teamOwner", "team"),

    [string[]]$TagOwnerTagNames = @("owner", "serviceOwner", "appOwner", "applicationOwner", "productOwner", "ownedBy", "costCenter", "costCentre", "cost-center", "cost_center"),

    [switch]$SkipActivityLogs,

    [scriptblock]$ProgressWriter = $null
  )

  if ($ProgressWriter) {
    & $ProgressWriter "Resolving Enterprise Application: $EnterpriseApplication"
  }

  $servicePrincipal = Resolve-EnterpriseApplication -EnterpriseApplication $EnterpriseApplication

  if ($ProgressWriter) {
    & $ProgressWriter "Resolved $($servicePrincipal.displayName) (objectId=$($servicePrincipal.objectId), appId=$($servicePrincipal.appId))"
    & $ProgressWriter "Loading Microsoft Graph dependency evidence"
  }

  $activityStartTime = (Get-Date).AddDays(-$ActivityDays)
  $graphDependencies = Get-GraphDependencies `
    -ServicePrincipal $servicePrincipal `
    -SignInUser $SignInUser `
    -SignInStartTime $activityStartTime `
    -MaxUserSignInRecords $MaxUserSignInRecords

  if ($ProgressWriter) {
    & $ProgressWriter "Microsoft Graph dependency evidence loaded"
    & $ProgressWriter "Loading Azure RBAC/resource/activity dependency evidence"
  }

  $azureDependencies = Get-AzureDependencies `
    -ServicePrincipal $servicePrincipal `
    -SubscriptionIds $SubscriptionIds `
    -ActivityDays $ActivityDays `
    -MaxActivityRecords $MaxActivityRecords `
    -LogAnalyticsWorkspaceId $LogAnalyticsWorkspaceId `
    -MaxBlobReadRecords $MaxBlobReadRecords `
    -BlobReadOperationNames $BlobReadOperationNames `
    -SkipActivityLogs:$SkipActivityLogs `
    -ProgressWriter $ProgressWriter

  if ($ProgressWriter) {
    & $ProgressWriter "Azure RBAC/resource/activity dependency evidence loaded"
    & $ProgressWriter "Building dependency report"
  }

  $report = New-OwnerLensReport `
    -ServicePrincipal $servicePrincipal `
    -GraphDependencies $graphDependencies `
    -AzureDependencies $azureDependencies `
    -ActivityDays $ActivityDays `
    -MaxActivityRecords $MaxActivityRecords `
    -SignInUser $SignInUser `
    -MaxUserSignInRecords $MaxUserSignInRecords `
    -BlobReadOperationNames $BlobReadOperationNames `
    -UserOwnerTagNames $UserOwnerTagNames `
    -GroupOwnerTagNames $GroupOwnerTagNames `
    -TagOwnerTagNames $TagOwnerTagNames `
    -SkipActivityLogs:$SkipActivityLogs

  if ($ProgressWriter) {
    & $ProgressWriter "Dependency report completed"
  }

  return $report
}
