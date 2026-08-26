function New-OwnerLensAnonymizationState {
  [pscustomobject]@{
    UserAliases = @{}
    GuidAliases = @{}
    StorageAliases = @{}
    UserCount = 0
    GuidCount = 0
    StorageCount = 0
  }
}

function Get-OwnerLensAnonymizedAlias {
  param(
    [Parameter(Mandatory = $true)]
    [hashtable]$Aliases,

    [Parameter(Mandatory = $true)]
    [object]$State,

    [Parameter(Mandatory = $true)]
    [string]$Value,

    [Parameter(Mandatory = $true)]
    [ValidateSet("User", "Guid", "Storage")]
    [string]$Kind
  )

  if (-not $Aliases.ContainsKey($Value)) {
    if ($Kind -eq "User") {
      $State.UserCount = [int]$State.UserCount + 1
      $Aliases[$Value] = "user-{0:0000}" -f [int]$State.UserCount
    } elseif ($Kind -eq "Guid") {
      $State.GuidCount = [int]$State.GuidCount + 1
      $Aliases[$Value] = "guid-{0:0000}" -f [int]$State.GuidCount
    } else {
      $State.StorageCount = [int]$State.StorageCount + 1
      $Aliases[$Value] = "storage-{0:0000}" -f [int]$State.StorageCount
    }
  }

  return [string]$Aliases[$Value]
}

function Get-OwnerLensAnonymizedStorageAlias {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Value,

    [Parameter(Mandatory = $true)]
    [object]$State
  )

  return Get-OwnerLensAnonymizedAlias -Aliases $State.StorageAliases -State $State -Value $Value.ToLowerInvariant() -Kind Storage
}

function Test-OwnerLensUserIdentityField {
  param(
    [string]$PropertyName,
    [AllowNull()]
    [object]$SourceObject
  )

  if ([string]::IsNullOrWhiteSpace($PropertyName)) {
    return $false
  }

  if ($PropertyName -in @(
      "userPrincipalName",
      "signInUser",
      "requesterUpn",
      "sasGeneratorUpn",
      "sasGeneratorUpns",
      "callerName"
    )) {
    return $true
  }

  if ($SourceObject -is [System.Collections.IDictionary] -and $PropertyName -match "(?i)^(userOwner|technicalOwner|businessOwner|managedBy|ownedBy|owner)$") {
    return $true
  }

  if ($null -eq $SourceObject) {
    return $false
  }

  $candidateType = [string]($SourceObject.PSObject.Properties["candidateType"].Value)
  if ($PropertyName -eq "candidate" -and $candidateType.Equals("User", [System.StringComparison]::OrdinalIgnoreCase)) {
    return $true
  }

  $principalType = [string]($SourceObject.PSObject.Properties["principalType"].Value)
  if ($PropertyName -in @("principalName", "principalDisplayName") -and $principalType.Equals("User", [System.StringComparison]::OrdinalIgnoreCase)) {
    return $true
  }

  $objectType = [string]($SourceObject.PSObject.Properties["objectType"].Value)
  if ($PropertyName -eq "displayName" -and $objectType.EndsWith(".user", [System.StringComparison]::OrdinalIgnoreCase)) {
    return $true
  }

  return $false
}

function Test-OwnerLensStorageAccountField {
  param(
    [string]$PropertyName,
    [AllowNull()]
    [object]$SourceObject
  )

  if ([string]::IsNullOrWhiteSpace($PropertyName)) {
    return $false
  }

  if ($PropertyName -in @("storageAccountName", "storageAccounts")) {
    return $true
  }

  if ($null -eq $SourceObject) {
    return $false
  }

  $resourceType = [string]($SourceObject.PSObject.Properties["resourceType"].Value)
  if ($PropertyName -in @("name", "resourceName") -and $resourceType.Equals("Microsoft.Storage/storageAccounts", [System.StringComparison]::OrdinalIgnoreCase)) {
    return $true
  }

  $resourceId = [string]($SourceObject.PSObject.Properties["resourceId"].Value)
  if ($PropertyName -eq "name" -and $resourceId -match "(?i)/providers/Microsoft\.Storage/storageAccounts/") {
    return $true
  }

  return $false
}

function ConvertTo-OwnerLensAnonymizedStorageString {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Value,

    [Parameter(Mandatory = $true)]
    [object]$State
  )

  $text = [string]$Value

  $resourceIdPattern = "(?i)(/providers/Microsoft\.Storage/storageAccounts/)([^/\]\s\?]+)"
  $text = [regex]::Replace($text, $resourceIdPattern, {
      param($match)
      "{0}{1}" -f $match.Groups[1].Value, (Get-OwnerLensAnonymizedStorageAlias -Value $match.Groups[2].Value -State $State)
    })

  $blobUriPattern = "(?i)(https?://)([a-z0-9]{3,24})(\.(?:blob|queue|table|dfs|file)\.core\.windows\.net\b)"
  $text = [regex]::Replace($text, $blobUriPattern, {
      param($match)
      "{0}{1}{2}" -f $match.Groups[1].Value, (Get-OwnerLensAnonymizedStorageAlias -Value $match.Groups[2].Value -State $State), $match.Groups[3].Value
    })

  return $text
}

function ConvertTo-OwnerLensAnonymizedString {
  param(
    [AllowNull()]
    [string]$Value,

    [string]$PropertyName,

    [AllowNull()]
    [object]$SourceObject,

    [Parameter(Mandatory = $true)]
    [object]$State
  )

  if ([string]::IsNullOrWhiteSpace($Value)) {
    return [string]$Value
  }

  if (Test-OwnerLensUserIdentityField -PropertyName $PropertyName -SourceObject $SourceObject) {
    return Get-OwnerLensAnonymizedAlias -Aliases $State.UserAliases -State $State -Value ([string]$Value) -Kind User
  }

  if (Test-OwnerLensStorageAccountField -PropertyName $PropertyName -SourceObject $SourceObject) {
    return Get-OwnerLensAnonymizedStorageAlias -Value ([string]$Value) -State $State
  }

  $emailPattern = "(?i)\b[A-Z0-9._%+\-']+@[A-Z0-9.\-]+\.[A-Z]{2,}\b"
  $text = [regex]::Replace([string]$Value, $emailPattern, {
      param($match)
      Get-OwnerLensAnonymizedAlias -Aliases $State.UserAliases -State $State -Value $match.Value.ToLowerInvariant() -Kind User
    })

  $text = ConvertTo-OwnerLensAnonymizedStorageString -Value $text -State $State

  $guidPattern = "(?i)\b[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\b"
  $text = [regex]::Replace($text, $guidPattern, {
      param($match)
      Get-OwnerLensAnonymizedAlias -Aliases $State.GuidAliases -State $State -Value $match.Value.ToLowerInvariant() -Kind Guid
    })

  return $text
}

function ConvertTo-OwnerLensAnonymizedConsoleValue {
  param(
    [AllowNull()]
    [object]$Value,

    [string]$PropertyName = "",

    [AllowNull()]
    [object]$SourceObject = $null,

    [Parameter(Mandatory = $true)]
    [object]$State
  )

  if ($null -eq $Value) {
    return $null
  }

  if ($Value -is [string]) {
    return ConvertTo-OwnerLensAnonymizedString -Value ([string]$Value) -PropertyName $PropertyName -SourceObject $SourceObject -State $State
  }

  if ($Value -is [datetime] -or $Value -is [bool] -or $Value.GetType().IsPrimitive) {
    return $Value
  }

  if ($Value -is [System.Collections.IDictionary]) {
    $result = [ordered]@{}
    foreach ($key in $Value.Keys) {
      $keyText = [string]$key
      $result[$keyText] = ConvertTo-OwnerLensAnonymizedConsoleValue -Value $Value[$key] -PropertyName $keyText -SourceObject $Value -State $State
    }

    return $result
  }

  if ($Value -is [System.Collections.IEnumerable]) {
    return @($Value | ForEach-Object {
        ConvertTo-OwnerLensAnonymizedConsoleValue -Value $_ -PropertyName $PropertyName -SourceObject $SourceObject -State $State
      })
  }

  $resultObject = [ordered]@{}
  foreach ($property in $Value.PSObject.Properties) {
    $resultObject[$property.Name] = ConvertTo-OwnerLensAnonymizedConsoleValue -Value $property.Value -PropertyName $property.Name -SourceObject $Value -State $State
  }

  return [pscustomobject]$resultObject
}

function ConvertTo-OwnerLensAnonymizedConsoleReport {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]
    [object]$Report
  )

  $state = New-OwnerLensAnonymizationState
  return ConvertTo-OwnerLensAnonymizedConsoleValue -Value $Report -State $state
}
