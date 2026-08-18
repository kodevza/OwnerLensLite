function Invoke-OwnerLensLight {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$EnterpriseApplication,

    [string]$TenantId = "",

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

    [ValidateNotNullOrEmpty()]
    [string[]]$Scopes = @("Application.Read.All", "Directory.Read.All", "Group.Read.All"),

    [string[]]$UserOwnerTagNames = @("userOwner", "technicalOwner", "businessOwner"),

    [string[]]$GroupOwnerTagNames = @("groupOwner", "ownerGroup", "teamOwner", "team"),

    [string[]]$TagOwnerTagNames = @("owner", "serviceOwner", "appOwner", "applicationOwner", "productOwner", "ownedBy", "costCenter", "costCentre", "cost-center", "cost_center"),

    [string]$OutputPath = "",

    [switch]$OutputJson,

    [switch]$OutputTable,

    [switch]$SkipActivityLogs,

    [switch]$SkipLogin
  )

  begin {
    $ErrorActionPreference = "Stop"

    function Write-ProgressLine {
      param([string]$Message)

      $timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
      Write-Verbose "[$timestamp] $Message"
    }

    try {
      Import-Module Microsoft.Graph.Authentication -ErrorAction Stop
    } catch {
      throw "Microsoft Graph PowerShell module missing: Microsoft.Graph.Authentication. Install: Install-Module Microsoft.Graph -Scope CurrentUser"
    }

    if (-not [string]::IsNullOrWhiteSpace($SignInUser) -and @($Scopes) -notcontains "AuditLog.Read.All") {
      $Scopes = @($Scopes) + "AuditLog.Read.All"
    }

    if (-not (Get-Command Get-AzContext -ErrorAction SilentlyContinue)) {
      throw "Az PowerShell module missing. Install: Install-Module Az -Scope CurrentUser"
    }

    if (-not (Get-Command Invoke-AzRestMethod -ErrorAction SilentlyContinue)) {
      throw "Invoke-AzRestMethod missing. Update Az.Accounts: Update-Module Az.Accounts"
    }

    $graphContext = Get-MgContext
    if (-not $SkipLogin -and -not $graphContext) {
      Write-ProgressLine "Microsoft Graph context not found. Starting Connect-MgGraph."

      $connectParams = @{ Scopes = $Scopes }
      if (-not [string]::IsNullOrWhiteSpace($TenantId)) {
        $connectParams.TenantId = $TenantId
      }

      Connect-MgGraph @connectParams | Out-Null
    }

    $azureContext = Get-AzContext
    if (-not $SkipLogin -and -not $azureContext) {
      Write-ProgressLine "Azure context not found. Starting Connect-AzAccount."
      Connect-AzAccount | Out-Null
    }
  }

  process {
    Write-ProgressLine "Resolving Enterprise Application: $EnterpriseApplication"
    $servicePrincipal = Resolve-EnterpriseApplication -EnterpriseApplication $EnterpriseApplication
    Write-ProgressLine "Resolved $($servicePrincipal.displayName) (objectId=$($servicePrincipal.objectId), appId=$($servicePrincipal.appId))"

    Write-ProgressLine "Loading Microsoft Graph dependency evidence"
    $activityStartTime = (Get-Date).AddDays(-$ActivityDays)
    $graphDependencies = Get-GraphDependencies `
      -ServicePrincipal $servicePrincipal `
      -SignInUser $SignInUser `
      -SignInStartTime $activityStartTime `
      -MaxUserSignInRecords $MaxUserSignInRecords

    Write-ProgressLine "Loading Azure RBAC/resource/activity dependency evidence"
    $azureDependencies = Get-AzureDependencies `
      -ServicePrincipal $servicePrincipal `
      -SubscriptionIds $SubscriptionIds `
      -ActivityDays $ActivityDays `
      -MaxActivityRecords $MaxActivityRecords `
      -LogAnalyticsWorkspaceId $LogAnalyticsWorkspaceId `
      -MaxBlobReadRecords $MaxBlobReadRecords `
      -BlobReadOperationNames $BlobReadOperationNames `
      -SkipActivityLogs:$SkipActivityLogs

    $report = [pscustomobject]@{
      meta = [pscustomobject]@{
        reportType = "enterpriseApplicationDependencies"
        createdAt = (Get-Date).ToUniversalTime().ToString("o")
        activityDays = $ActivityDays
        activityStartTime = $azureDependencies.activityStartTime
        maxActivityRecords = $MaxActivityRecords
        signInUser = $SignInUser
        maxUserSignInRecords = $MaxUserSignInRecords
        logAnalyticsWorkspaceId = $azureDependencies.logAnalyticsWorkspaceId
        maxBlobReadRecords = $azureDependencies.maxBlobReadRecords
        blobReadOperationNames = @($BlobReadOperationNames)
        activitySkipped = [bool]$SkipActivityLogs
        requestedSubscriptions = @($azureDependencies.requestedSubscriptions)
        ownerTagConfiguration = [pscustomobject]@{
          userOwnerTagNames = @($UserOwnerTagNames)
          groupOwnerTagNames = @($GroupOwnerTagNames)
          tagOwnerTagNames = @($TagOwnerTagNames)
        }
      }
      enterpriseApplication = $servicePrincipal
      summary = [pscustomobject]@{
        azureSubscriptions = @($azureDependencies.subscriptions).Count
        azureRoleAssignments = @($azureDependencies.roleAssignments).Count
        azureDependencyScopes = @($azureDependencies.resourceDependencies).Count
        azureActivityRecords = @($azureDependencies.activityEvidence).Count
        azureRbacScopeActivityRecords = @($azureDependencies.rbacScopeActivityEvidence).Count
        azureRbacScopeActivityCallers = @($azureDependencies.rbacScopeActivityCallers).Count
        azureActivityLogDiagnosticSettings = @($azureDependencies.activityDiagnosticSettings | Where-Object activityLogEnabled).Count
        azureActivityLogAnalyticsDiagnostics = @($azureDependencies.activityDiagnosticSettings | Where-Object logAnalyticsEnabled).Count
        azureStorageAccountsWithRbac = @($azureDependencies.storageAccountsWithRbac).Count
        azureStorageAccountsWithDiagnosticLogs = @($azureDependencies.storageAccountsWithRbac | Where-Object diagnosticLogEnabled).Count
        azureStorageAccountsWithLogAnalyticsDiagnostics = @($azureDependencies.storageAccountsWithRbac | Where-Object diagnosticLogAnalyticsEnabled).Count
        azureBlobReadRecords = @($azureDependencies.blobReadEvidence).Count
        azureBlobReadCallers = @($azureDependencies.blobReadCallers).Count
        azureBlobReadObjects = @($azureDependencies.blobReadObjects).Count
        graphAppRoleAssignments = @($graphDependencies.appRoleAssignments).Count
        graphDelegatedPermissionGrants = @($graphDependencies.oauth2PermissionGrants).Count
        graphGroupMemberships = @($graphDependencies.memberOf).Count
        graphResourceServicePrincipals = @($graphDependencies.resourceServicePrincipals).Count
        graphUserSignIns = @($graphDependencies.userSignIns).Count
        owners = @($graphDependencies.owners).Count
      }
      azure = [pscustomobject]@{
        subscriptions = @($azureDependencies.subscriptions)
        roleAssignments = @($azureDependencies.roleAssignments)
        coAssignedRoleCandidates = @($azureDependencies.coAssignedRoleCandidates)
        resourceDependencies = @($azureDependencies.resourceDependencies)
        activityEvidence = @($azureDependencies.activityEvidence)
        rbacScopeActivityEvidence = @($azureDependencies.rbacScopeActivityEvidence)
        rbacScopeActivityCallers = @($azureDependencies.rbacScopeActivityCallers)
        activityDiagnosticSettings = @($azureDependencies.activityDiagnosticSettings)
        storageAccountsWithRbac = @($azureDependencies.storageAccountsWithRbac)
        blobReadEvidence = @($azureDependencies.blobReadEvidence)
        blobReadCallers = @($azureDependencies.blobReadCallers)
        blobReadObjects = @($azureDependencies.blobReadObjects)
      }
      graph = $graphDependencies
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

    if (-not [string]::IsNullOrWhiteSpace($OutputPath)) {
      $resolvedOutputPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputPath)
      $outputDirectory = Split-Path -Parent $resolvedOutputPath
      if (-not [string]::IsNullOrWhiteSpace($outputDirectory)) {
        New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
      }

      $report | ConvertTo-Json -Depth 40 | Set-Content -LiteralPath $resolvedOutputPath -Encoding UTF8
      Write-ProgressLine "Wrote dependency report: $resolvedOutputPath"
    }

    if ($OutputJson) {
      return ($report | ConvertTo-Json -Depth 40)
    }

    if ($OutputTable) {
      return (Format-OwnerCandidateTable -Candidates @($report.ownerCandidates))
    }

    Format-DependencyReport -Report $report -Full:($VerbosePreference -eq "Continue")
    return $report
  }
}
