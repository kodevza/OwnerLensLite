<#
.SYNOPSIS
Runs the OwnerLens Light Enterprise Application dependency inspection workflow.
#>

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

  [string]$LogAnalyticsWorkspaceId = "",

  [ValidateRange(1, 1000000)]
  [int]$MaxBlobReadRecords = 5000,

  [string[]]$BlobReadOperationNames = @("GetBlob", "PutBlob", "PutBlock", "PutBlockList", "AppendBlock", "CopyBlob"),

  [ValidateNotNullOrEmpty()]
  [string[]]$Scopes = @("Application.Read.All", "Directory.Read.All", "Group.Read.All"),

  [string[]]$UserOwnerTagNames = @("userOwner", "technicalOwner", "businessOwner"),

  [string[]]$GroupOwnerTagNames = @("groupOwner", "ownerGroup", "teamOwner", "team"),

  [string[]]$TagOwnerTagNames = @("owner", "serviceOwner", "costCenter", "costCentre", "cost-center", "cost_center"),

  [string]$OutputPath = "",

  [switch]$OutputJson,

  [switch]$OutputTable,

  [switch]$SkipActivityLogs,

  [switch]$SkipLogin
)

begin {
  $ErrorActionPreference = "Stop"

  Import-Module (Join-Path $PSScriptRoot "ownerlens/ownerlens.psd1") -Force
}

process {
  Invoke-OwnerLensLight @PSBoundParameters
}
