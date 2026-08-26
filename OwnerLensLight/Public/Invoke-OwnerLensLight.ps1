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

    [switch]$AnonymizeConsoleOutput,

    [switch]$SkipActivityLogs,

    [switch]$SkipLogin
  )

  begin {
    $ErrorActionPreference = "Stop"
    $consoleAnonymizationState = New-OwnerLensAnonymizationState

    function Write-ProgressLine {
      param([string]$Message)

      $timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
      $progressMessage = [string]$Message
      if ($AnonymizeConsoleOutput) {
        $progressMessage = ConvertTo-OwnerLensAnonymizedString -Value $progressMessage -State $consoleAnonymizationState
      }

      Write-Verbose "[$timestamp] $progressMessage"
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
    $report = Invoke-OwnerLensAssessment `
      -EnterpriseApplication $EnterpriseApplication `
      -SubscriptionIds $SubscriptionIds `
      -ActivityDays $ActivityDays `
      -MaxActivityRecords $MaxActivityRecords `
      -SignInUser $SignInUser `
      -MaxUserSignInRecords $MaxUserSignInRecords `
      -LogAnalyticsWorkspaceId $LogAnalyticsWorkspaceId `
      -MaxBlobReadRecords $MaxBlobReadRecords `
      -BlobReadOperationNames $BlobReadOperationNames `
      -UserOwnerTagNames $UserOwnerTagNames `
      -GroupOwnerTagNames $GroupOwnerTagNames `
      -TagOwnerTagNames $TagOwnerTagNames `
      -SkipActivityLogs:$SkipActivityLogs `
      -ProgressWriter ${function:Write-ProgressLine}

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
      $tableReport = $report
      if ($AnonymizeConsoleOutput) {
        $tableReport = ConvertTo-OwnerLensAnonymizedConsoleReport -Report $report
      }

      return (Format-OwnerCandidateTable -Candidates (Get-OwnerLensReportArray -Report $tableReport -Path "ownerCandidates"))
    }

    $consoleReport = $report
    if ($AnonymizeConsoleOutput) {
      $consoleReport = ConvertTo-OwnerLensAnonymizedConsoleReport -Report $report
    }

    Format-DependencyReport -Report $consoleReport -Full:($VerbosePreference -eq "Continue")
    return $report
  }
}
