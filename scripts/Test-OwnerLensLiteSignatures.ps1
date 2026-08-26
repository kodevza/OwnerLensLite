<#
.SYNOPSIS
Reports and optionally enforces Authenticode signature status for OwnerLens Lite module files.
#>

param(
  [string[]]$Path = @(".\OwnerLensLite"),
  [switch]$RequireValid,
  [switch]$RequireTimestamp,
  [string]$OutputJson = ""
)

$ErrorActionPreference = "Stop"

if (-not $IsWindows) {
  throw "Test-OwnerLensLiteSignatures.ps1 is Windows-only because Get-AuthenticodeSignature is Windows-only."
}

function Get-SignatureFiles {
  param([string[]]$Roots)

  foreach ($root in $Roots) {
    if (-not (Test-Path -LiteralPath $root)) {
      continue
    }

    $item = Get-Item -LiteralPath $root
    if ($item.PSIsContainer) {
      Get-ChildItem -LiteralPath $item.FullName -Recurse -File |
        Where-Object { $_.Extension -in ".ps1", ".psm1", ".psd1" }
    }
    elseif ($item.Extension -in ".ps1", ".psm1", ".psd1") {
      $item
    }
  }
}

$results = foreach ($file in (Get-SignatureFiles -Roots $Path | Sort-Object FullName -Unique)) {
  $signature = Get-AuthenticodeSignature -FilePath $file.FullName
  $timestampStatus = if ($signature.TimeStamperCertificate) { "Present" } else { "Missing" }
  [pscustomobject]@{
    Path                   = $file.FullName
    Status                 = [string]$signature.Status
    StatusMessage          = [string]$signature.StatusMessage
    SignerSubject          = if ($signature.SignerCertificate) { [string]$signature.SignerCertificate.Subject } else { "" }
    Thumbprint             = if ($signature.SignerCertificate) { [string]$signature.SignerCertificate.Thumbprint } else { "" }
    TimestampStatus        = $timestampStatus
    TimestampSignerSubject = if ($signature.TimeStamperCertificate) { [string]$signature.TimeStamperCertificate.Subject } else { "" }
  }
}

if (-not $results) {
  throw "No OwnerLens Lite files with Authenticode signature support were found."
}

$results | Format-Table Path, Status, SignerSubject, Thumbprint, TimestampStatus -AutoSize

if ($OutputJson) {
  $resolvedOutputJson = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputJson)
  New-Item -ItemType Directory -Path (Split-Path -Parent $resolvedOutputJson) -Force | Out-Null
  $results | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $resolvedOutputJson -Encoding UTF8
}

if ($RequireValid) {
  $invalid = @($results | Where-Object { $_.Status -ne "Valid" })
  if ($invalid) {
    throw "One or more OwnerLens Lite signatures are not valid: $($invalid.Path -join ', ')"
  }
}

if ($RequireTimestamp) {
  $missingTimestamp = @($results | Where-Object { $_.TimestampStatus -ne "Present" })
  if ($missingTimestamp) {
    throw "One or more OwnerLens Lite signatures are missing a timestamp: $($missingTimestamp.Path -join ', ')"
  }
}
