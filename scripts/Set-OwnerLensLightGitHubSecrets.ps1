<#
.SYNOPSIS
Configures GitHub Actions secrets required to sign and publish OwnerLens Light.

.DESCRIPTION
Reads required secret values from a local dotenv-style file and/or current process environment,
then writes them to the ownerlens-light GitHub repository.

GitHub does not allow reading existing secret values, so this script cannot copy secrets directly
from another repository. Provide the values locally, or run it in a shell where the variables are
already set.
#>

param(
  [string]$Repository = "kodevza/ownerlens-light",
  [string]$Environment = "package-signing",
  [string]$EnvPath = ".env.github-secrets",
  [switch]$SkipEnvFile,
  [switch]$WhatIf
)

$ErrorActionPreference = "Stop"

$environmentSecretNames = @(
  "AZURE_CLIENT_ID",
  "AZURE_TENANT_ID",
  "AZURE_SUBSCRIPTION_ID",
  "ARTIFACT_SIGNING_ENDPOINT",
  "ARTIFACT_SIGNING_ACCOUNT_NAME",
  "ARTIFACT_SIGNING_CERTIFICATE_PROFILE_NAME"
)

$repositorySecretNames = @(
  "PSGALLERY_API_KEY"
)

function Read-DotEnvFile {
  param([string]$Path)

  $values = @{}
  if (-not (Test-Path -LiteralPath $Path)) {
    return $values
  }

  foreach ($line in Get-Content -LiteralPath $Path) {
    $trimmed = $line.Trim()
    if ([string]::IsNullOrWhiteSpace($trimmed) -or $trimmed.StartsWith("#")) {
      continue
    }

    $separatorIndex = $trimmed.IndexOf("=")
    if ($separatorIndex -le 0) {
      continue
    }

    $name = $trimmed.Substring(0, $separatorIndex).Trim()
    $value = $trimmed.Substring($separatorIndex + 1).Trim()

    if (($value.StartsWith('"') -and $value.EndsWith('"')) -or
        ($value.StartsWith("'") -and $value.EndsWith("'"))) {
      $value = $value.Substring(1, $value.Length - 2)
    }

    $values[$name] = $value
  }

  return $values
}

function Get-SecretValue {
  param(
    [hashtable]$FileValues,
    [string]$Name
  )

  if ($FileValues.ContainsKey($Name) -and -not [string]::IsNullOrWhiteSpace([string]$FileValues[$Name])) {
    return [string]$FileValues[$Name]
  }

  return [Environment]::GetEnvironmentVariable($Name)
}

if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
  throw "GitHub CLI 'gh' was not found. Install GitHub CLI and authenticate with: gh auth login"
}

gh auth status *> $null
if ($LASTEXITCODE -ne 0) {
  throw "GitHub CLI is not authenticated. Run: gh auth login"
}

$fileValues = @{}
if (-not $SkipEnvFile) {
  $resolvedEnvPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($EnvPath)
  $fileValues = Read-DotEnvFile -Path $resolvedEnvPath
}

$allSecretNames = @($environmentSecretNames + $repositorySecretNames)
$missing = @()
foreach ($name in $allSecretNames) {
  $value = Get-SecretValue -FileValues $fileValues -Name $name
  if ([string]::IsNullOrWhiteSpace($value)) {
    $missing += $name
  }
}

if ($WhatIf) {
  Write-Host "Would configure GitHub environment '$Environment' in $Repository."
  foreach ($name in $environmentSecretNames) {
    $value = Get-SecretValue -FileValues $fileValues -Name $name
    $status = if ([string]::IsNullOrWhiteSpace($value)) { "missing locally" } else { "available locally" }
    Write-Host "Would set environment secret: $name ($status)"
  }
  foreach ($name in $repositorySecretNames) {
    $value = Get-SecretValue -FileValues $fileValues -Name $name
    $status = if ([string]::IsNullOrWhiteSpace($value)) { "missing locally" } else { "available locally" }
    Write-Host "Would set repository secret: $name ($status)"
  }
  return
}

if ($missing.Count -gt 0) {
  throw "Missing required secret values: $($missing -join ', '). Set them in the current shell or in $EnvPath."
}

Write-Host "Ensuring GitHub environment '$Environment' exists in $Repository"
gh api `
  --method PUT `
  "repos/$Repository/environments/$Environment" `
  --silent
if ($LASTEXITCODE -ne 0) {
  throw "Failed to create or update GitHub environment '$Environment'."
}

foreach ($name in $environmentSecretNames) {
  $value = Get-SecretValue -FileValues $fileValues -Name $name
  Write-Host "Setting environment secret: $name"
  $value | gh secret set $name --repo $Repository --env $Environment
  if ($LASTEXITCODE -ne 0) {
    throw "Failed to set environment secret '$name'."
  }
}

foreach ($name in $repositorySecretNames) {
  $value = Get-SecretValue -FileValues $fileValues -Name $name
  Write-Host "Setting repository secret: $name"
  $value | gh secret set $name --repo $Repository
  if ($LASTEXITCODE -ne 0) {
    throw "Failed to set repository secret '$name'."
  }
}

Write-Host "OwnerLens Light GitHub secrets configured."
