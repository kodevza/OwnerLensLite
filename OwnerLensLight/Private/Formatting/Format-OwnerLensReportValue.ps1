function Get-OwnerLensDisplayValue {
  param(
    [AllowNull()]
    [object]$Value,

    [string]$Fallback = ""
  )

  $text = [string]$Value
  if ([string]::IsNullOrWhiteSpace($text)) {
    return $Fallback
  }

  return $text
}

function Format-OwnerLensListValue {
  param(
    [AllowNull()]
    [object]$Value
  )

  return @($Value | ForEach-Object { [string]$_ } | Where-Object {
      -not [string]::IsNullOrWhiteSpace($_)
    }) -join ","
}

function ConvertTo-OwnerLensAzurePortalResourceUri {
  param([string]$ResourceId)

  if ([string]::IsNullOrWhiteSpace($ResourceId)) {
    return ""
  }

  return "https://portal.azure.com/#resource$(([string]$ResourceId).Trim())"
}

function ConvertTo-OwnerLensAzurePortalIamUri {
  param([string]$Scope)

  if ([string]::IsNullOrWhiteSpace($Scope)) {
    return ""
  }

  return "$(ConvertTo-OwnerLensAzurePortalResourceUri -ResourceId $Scope)/users"
}

function Format-OwnerLensRichLink {
  param(
    [string]$Text,
    [string]$Uri
  )

  if ([string]::IsNullOrWhiteSpace($Text) -or [string]::IsNullOrWhiteSpace($Uri)) {
    return [string]$Text
  }

  return "[link=$Uri]$Text[/link]"
}

function Format-OwnerLensAzureResourceId {
  param([string]$ResourceId)

  return Format-OwnerLensRichLink `
    -Text ([string]$ResourceId) `
    -Uri (ConvertTo-OwnerLensAzurePortalResourceUri -ResourceId ([string]$ResourceId))
}

function Format-OwnerLensShortAzureResourceLink {
  param([string]$ResourceId)

  if ([string]::IsNullOrWhiteSpace($ResourceId)) {
    return ""
  }

  return Format-OwnerLensRichLink `
    -Text (Format-OwnerLensShortAzureResourceId -ResourceId $ResourceId) `
    -Uri (ConvertTo-OwnerLensAzurePortalResourceUri -ResourceId $ResourceId)
}

function Format-OwnerLensShortAzureResourceId {
  param([string]$ResourceId)

  if ([string]::IsNullOrWhiteSpace($ResourceId)) {
    return ""
  }

  $parts = @(([string]$ResourceId).Trim("/") -split "/" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
  $subscriptionIndex = [Array]::IndexOf($parts, "subscriptions")
  $resourceGroupIndex = [Array]::IndexOf($parts, "resourceGroups")
  $providersIndex = [Array]::IndexOf($parts, "providers")

  if ($providersIndex -ge 0 -and ($providersIndex + 3) -lt $parts.Count) {
    $resourceType = $parts[$providersIndex + 2]
    $resourceName = $parts[$providersIndex + 3]
    if ($resourceGroupIndex -ge 0 -and ($resourceGroupIndex + 1) -lt $parts.Count) {
      return "$($parts[$resourceGroupIndex + 1])/$resourceType/$resourceName"
    }

    return "$resourceType/$resourceName"
  }

  if ($resourceGroupIndex -ge 0 -and ($resourceGroupIndex + 1) -lt $parts.Count) {
    return "rg/$($parts[$resourceGroupIndex + 1])"
  }

  if ($subscriptionIndex -ge 0 -and ($subscriptionIndex + 1) -lt $parts.Count) {
    return "sub/$($parts[$subscriptionIndex + 1])"
  }

  return [string]$ResourceId
}

function ConvertTo-OwnerLensGraphExplorerUri {
  param([string]$EvidenceId)

  if ([string]::IsNullOrWhiteSpace($EvidenceId)) {
    return ""
  }

  $path = ([string]$EvidenceId).Trim("/")
  $parts = @($path -split "/" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
  if ($parts.Count -lt 2) {
    return ""
  }

  if ($parts[0] -notin @("applications", "servicePrincipals")) {
    return ""
  }

  $requestPath = "$($parts[0])/$($parts[1])"
  if ($parts.Count -ge 3 -and $parts[2] -in @("memberOf", "owners")) {
    $requestPath = "$requestPath/$($parts[2])"
  }

  $request = [System.Uri]::EscapeDataString("/v1.0/$requestPath")
  return "https://developer.microsoft.com/graph/graph-explorer?request=$request&method=GET&version=v1.0"
}

function Format-OwnerLensGraphEvidenceId {
  param([string]$EvidenceId)

  $path = ([string]$EvidenceId).Trim("/")
  $parts = @($path -split "/" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
  if ($parts.Count -lt 2) {
    return [string]$EvidenceId
  }

  $label = "$($parts[0])/$($parts[1])"
  if ($parts.Count -ge 3) {
    $label = "$label/$($parts[2])"
  }

  if ($parts.Count -ge 4) {
    $label = "$label/...$($parts[$parts.Count - 1])"
  }

  return Format-OwnerLensRichLink `
    -Text $label `
    -Uri (ConvertTo-OwnerLensGraphExplorerUri -EvidenceId ([string]$EvidenceId))
}

function Format-OwnerLensOwnerCandidateEvidenceId {
  param([string]$EvidenceId)

  if ([string]::IsNullOrWhiteSpace($EvidenceId)) {
    return ""
  }

  if ($EvidenceId -eq "not-found") {
    return "not-found"
  }

  if ($EvidenceId.StartsWith("/subscriptions/", [System.StringComparison]::OrdinalIgnoreCase)) {
    return Format-OwnerLensRichLink `
      -Text (Format-OwnerLensShortAzureResourceId -ResourceId $EvidenceId) `
      -Uri (ConvertTo-OwnerLensAzurePortalResourceUri -ResourceId $EvidenceId)
  }

  if (
    $EvidenceId.StartsWith("/servicePrincipals/", [System.StringComparison]::OrdinalIgnoreCase) -or
    $EvidenceId.StartsWith("/applications/", [System.StringComparison]::OrdinalIgnoreCase)
  ) {
    return Format-OwnerLensGraphEvidenceId -EvidenceId $EvidenceId
  }

  return [string]$EvidenceId
}

function Format-OwnerLensUriLink {
  param([string]$Uri)

  return Format-OwnerLensRichLink -Text ([string]$Uri) -Uri ([string]$Uri)
}

function Format-OwnerLensPrincipalLabel {
  param(
    [string]$Text,
    [string]$PrincipalType,
    [bool]$HasDataAccess
  )

  if (
    ([string]$PrincipalType).Equals("ServicePrincipal", [System.StringComparison]::OrdinalIgnoreCase) -or
    ([string]$PrincipalType).Equals("Service Principal", [System.StringComparison]::OrdinalIgnoreCase)
  ) {
    if ($HasDataAccess) {
      return "[dim green]$Text[/]"
    }

    return [string]$Text
  }

  if (-not ([string]$PrincipalType).Equals("User", [System.StringComparison]::OrdinalIgnoreCase)) {
    return [string]$Text
  }

  if ($HasDataAccess) {
    return "[bold green]$Text[/]"
  }

  return "[bold]$Text[/]"
}
