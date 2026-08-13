#requires -Version 7.0

[CmdletBinding(SupportsShouldProcess)]
param(
  [Parameter(Mandatory)]
  [string]$ApiKey,

  [string]$Repository = "PSGallery",

  [string]$Path,

  [switch]$SkipBuild,

  [switch]$SkipSignatureValidation,

  [switch]$RequireTimestamp
)

$ErrorActionPreference = "Stop"

if (-not $SkipBuild) {
  & (Join-Path $PSScriptRoot "Build-OwnerLensLightModule.ps1")
}

if ([string]::IsNullOrWhiteSpace($Path)) {
  $Path = Join-Path $PSScriptRoot "../artifacts/OwnerLensLight"
}

$modulePath = Resolve-Path $Path

if (-not $SkipSignatureValidation) {
  & (Join-Path $PSScriptRoot "Test-OwnerLensLightSignatures.ps1") -Path $modulePath -RequireValid -RequireTimestamp:$RequireTimestamp
}

if ($PSCmdlet.ShouldProcess($Repository, "Publish OwnerLensLight")) {
  Publish-Module `
    -Path $modulePath `
    -Repository $Repository `
    -NuGetApiKey $ApiKey `
    -Force
}
