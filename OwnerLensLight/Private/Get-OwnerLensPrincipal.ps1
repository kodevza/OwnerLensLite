function Get-OwnerLensPrincipalKey {
  param(
    [string]$ObjectId,
    [string]$AppId,
    [string]$Upn,
    [string]$Fallback = "unknown"
  )

  $keyParts = @()
  if (-not [string]::IsNullOrWhiteSpace($ObjectId)) {
    $keyParts += "object:$ObjectId"
  }

  if (-not [string]::IsNullOrWhiteSpace($AppId)) {
    $keyParts += "app:$AppId"
  }

  if (-not [string]::IsNullOrWhiteSpace($Upn)) {
    $keyParts += "upn:$Upn"
  }

  if ($keyParts.Count -gt 0) {
    return ($keyParts -join "|")
  }

  return $Fallback
}

function Get-OwnerLensPrincipalType {
  param(
    [string]$Caller,
    [string]$AppId,
    [string]$Fallback = "Principal"
  )

  if ($Caller -match "@") {
    return "User"
  }

  if (-not [string]::IsNullOrWhiteSpace($AppId)) {
    return "ServicePrincipal"
  }

  return $Fallback
}
