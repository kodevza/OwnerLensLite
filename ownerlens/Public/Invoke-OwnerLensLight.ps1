function Invoke-OwnerLensLight {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$EnterpriseApplication,

    [string]$TenantId = "",

    [string]$SubscriptionIds = "",

    [ValidateRange(1, 3650)]
    [int]$ActivityDays = 30,

    [ValidateRange(1, 1000000)]
    [int]$MaxActivityRecords = 5000,

    [ValidateNotNullOrEmpty()]
    [string[]]$Scopes = @("Application.Read.All", "Directory.Read.All", "Group.Read.All"),

    [string]$OutputPath = "",

    [switch]$OutputJson,

    [switch]$SkipActivityLogs,

    [switch]$SkipLogin
  )

  $ErrorActionPreference = "Stop"

  function Write-ProgressLine {
    param([string]$Message)

    $timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    Write-Host "[$timestamp] $Message"
  }

  try {
    Import-Module Microsoft.Graph.Authentication -ErrorAction Stop
  } catch {
    throw "Microsoft Graph PowerShell module missing: Microsoft.Graph.Authentication. Install: Install-Module Microsoft.Graph -Scope CurrentUser"
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

  Write-ProgressLine "Resolving Enterprise Application: $EnterpriseApplication"
  $servicePrincipal = Resolve-EnterpriseApplication -EnterpriseApplication $EnterpriseApplication
  Write-ProgressLine "Resolved $($servicePrincipal.displayName) (objectId=$($servicePrincipal.objectId), appId=$($servicePrincipal.appId))"

  Write-ProgressLine "Loading Microsoft Graph dependency evidence"
  $graphDependencies = Get-GraphDependencies -ServicePrincipal $servicePrincipal

  Write-ProgressLine "Loading Azure RBAC/resource/activity dependency evidence"
  $azureDependencies = Get-AzureDependencies `
    -ServicePrincipal $servicePrincipal `
    -SubscriptionIds $SubscriptionIds `
    -ActivityDays $ActivityDays `
    -MaxActivityRecords $MaxActivityRecords `
    -SkipActivityLogs:$SkipActivityLogs

  $report = [pscustomobject]@{
    meta = [pscustomobject]@{
      reportType = "enterpriseApplicationDependencies"
      createdAt = (Get-Date).ToUniversalTime().ToString("o")
      activityDays = $ActivityDays
      activityStartTime = $azureDependencies.activityStartTime
      maxActivityRecords = $MaxActivityRecords
      activitySkipped = [bool]$SkipActivityLogs
      requestedSubscriptions = @($azureDependencies.requestedSubscriptions)
    }
    enterpriseApplication = $servicePrincipal
    summary = [pscustomobject]@{
      azureSubscriptions = @($azureDependencies.subscriptions).Count
      azureRoleAssignments = @($azureDependencies.roleAssignments).Count
      azureDependencyScopes = @($azureDependencies.resourceDependencies).Count
      azureActivityRecords = @($azureDependencies.activityEvidence).Count
      graphAppRoleAssignments = @($graphDependencies.appRoleAssignments).Count
      graphDelegatedPermissionGrants = @($graphDependencies.oauth2PermissionGrants).Count
      graphGroupMemberships = @($graphDependencies.memberOf).Count
      graphResourceServicePrincipals = @($graphDependencies.resourceServicePrincipals).Count
      owners = @($graphDependencies.owners).Count
    }
    azure = [pscustomobject]@{
      subscriptions = @($azureDependencies.subscriptions)
      roleAssignments = @($azureDependencies.roleAssignments)
      resourceDependencies = @($azureDependencies.resourceDependencies)
      activityEvidence = @($azureDependencies.activityEvidence)
    }
    graph = $graphDependencies
    notes = @(
      "Azure RBAC scopes show where the Enterprise Application service principal has assigned access.",
      "Azure Monitor activity evidence is low-confidence usage evidence from the selected activity window; it is not proof of ownership.",
      "Microsoft Graph app role assignments and delegated permission grants show API dependencies."
    )
  }

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

  Format-DependencyReport -Report $report
  return $report
}
