<#
.SYNOPSIS
Runs the OwnerLens Light Enterprise Application dependency inspection workflow.
#>

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

Import-Module (Join-Path $PSScriptRoot "ownerlens/ownerlens.psd1") -Force

Invoke-OwnerLensLight @PSBoundParameters
