function New-OwnerCandidate {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Candidate,

    [Parameter(Mandatory = $true)]
    [string]$CandidateType,

    [Parameter(Mandatory = $true)]
    [string]$Confidence,

    [Parameter(Mandatory = $true)]
    [string]$Relationship,

    [Parameter(Mandatory = $true)]
    [string]$Signal,

    [Parameter(Mandatory = $true)]
    [string]$EvidenceId,

    [Parameter(Mandatory = $true)]
    [string]$EvidenceSource,

    [string]$EvidenceValue = "",

    [string]$Reason = ""
  )

  return [pscustomobject]@{
    candidate = $Candidate
    candidateType = $CandidateType
    confidence = $Confidence
    relationship = $Relationship
    signal = $Signal
    evidenceId = $EvidenceId
    evidenceSource = $EvidenceSource
    evidenceValue = $EvidenceValue
    reason = $Reason
  }
}

function Get-OwnerCandidatePolicyScore {
  param(
    [Parameter(Mandatory = $true)]
    [hashtable]$Rule,

    [string]$CandidateType = ""
  )

  if ($Rule.ScoreByCandidateType) {
    if (-not [string]::IsNullOrWhiteSpace($CandidateType) -and $Rule.ScoreByCandidateType.ContainsKey($CandidateType)) {
      return [int]$Rule.ScoreByCandidateType[$CandidateType]
    }

    if ($Rule.ScoreByCandidateType.ContainsKey("Default")) {
      return [int]$Rule.ScoreByCandidateType.Default
    }
  }

  return [int]$Rule.Score
}

function ConvertTo-OwnerConfidence {
  param([int]$Score)

  if ($Score -ge 80) {
    return "HIGH"
  }

  if ($Score -ge 50) {
    return "MED"
  }

  return "LOW"
}

function ConvertTo-OwnerCandidateType {
  param([string]$ObjectType)

  switch -Regex ($ObjectType) {
    "user|#microsoft\.graph\.user" { return "User" }
    "group|#microsoft\.graph\.group" { return "Group" }
    default {
      if ([string]::IsNullOrWhiteSpace($ObjectType)) {
        return "Unknown"
      }

      return $ObjectType
    }
  }
}

function Add-OwnerCandidateFromGraphOwner {
  param(
    [Parameter(Mandatory = $true)]
    [object]$Owner,

    [Parameter(Mandatory = $true)]
    [object]$EnterpriseApplication,

    [Parameter(Mandatory = $true)]
    [hashtable]$Rule
  )

  $candidateType = ConvertTo-OwnerCandidateType -ObjectType ([string]$Owner.objectType)
  if ($candidateType -eq "User") {
    $candidateName = [string]$Owner.userPrincipalName
    if ([string]::IsNullOrWhiteSpace($candidateName)) {
      $candidateName = [string]$Owner.mail
    }
    if ([string]::IsNullOrWhiteSpace($candidateName)) {
      $candidateName = [string]$Owner.displayName
    }
  } else {
    $candidateName = [string]$Owner.displayName
  }

  if ([string]::IsNullOrWhiteSpace($candidateName)) {
    $candidateName = [string]$Owner.objectId
  }

  $ownerSource = [string]$Owner.ownerSource
  if ([string]::IsNullOrWhiteSpace($ownerSource)) {
    $ownerSource = "ServicePrincipal"
  }

  $ownerEvidenceBase = "/servicePrincipals/$($EnterpriseApplication.objectId)"
  $ownerReason = "Direct Microsoft Graph owner on the service principal."
  if ($ownerSource -eq "Application" -and -not [string]::IsNullOrWhiteSpace([string]$EnterpriseApplication.applicationObjectId)) {
    $ownerEvidenceBase = "/applications/$($EnterpriseApplication.applicationObjectId)"
    $ownerReason = "Direct Microsoft Graph owner on the application registration."
  }

  return New-OwnerCandidate `
    -Candidate $candidateName `
    -CandidateType $candidateType `
    -Confidence (ConvertTo-OwnerConfidence -Score (Get-OwnerCandidatePolicyScore -Rule $Rule -CandidateType $candidateType)) `
    -Relationship "Direct" `
    -Signal ([string]$Rule.Signal) `
    -EvidenceId ("{0}/owners/{1}" -f $ownerEvidenceBase, [string]$Owner.objectId) `
    -EvidenceSource "$ownerEvidenceBase/owners" `
    -EvidenceValue ([string]$Owner.objectId) `
    -Reason $ownerReason
}

function Add-OwnerCandidateFromDirectoryRelationship {
  param(
    [Parameter(Mandatory = $true)]
    [object]$MemberOf,

    [Parameter(Mandatory = $true)]
    [object]$EnterpriseApplication,

    [Parameter(Mandatory = $true)]
    [hashtable]$Rule
  )

  $candidateType = ConvertTo-OwnerCandidateType -ObjectType ([string]$MemberOf.objectType)
  $candidateName = [string]$MemberOf.displayName
  if ([string]::IsNullOrWhiteSpace($candidateName)) {
    $candidateName = [string]$MemberOf.objectId
  }

  return New-OwnerCandidate `
    -Candidate $candidateName `
    -CandidateType $candidateType `
    -Confidence (ConvertTo-OwnerConfidence -Score (Get-OwnerCandidatePolicyScore -Rule $Rule -CandidateType $candidateType)) `
    -Relationship "Indirect" `
    -Signal ([string]$Rule.Signal) `
    -EvidenceId ("/servicePrincipals/{0}/memberOf/{1}" -f $EnterpriseApplication.objectId, [string]$MemberOf.objectId) `
    -EvidenceSource "/servicePrincipals/$($EnterpriseApplication.objectId)/memberOf" `
    -EvidenceValue ([string]$MemberOf.objectId) `
    -Reason "The service principal is a member of this directory object."
}

function Add-OwnerCandidateFromCoAssignedRoleCandidate {
  param(
    [Parameter(Mandatory = $true)]
    [object]$CoAssignee,

    [Parameter(Mandatory = $true)]
    [hashtable]$Rule
  )

  $candidateType = ConvertTo-OwnerCandidateType -ObjectType ([string]$CoAssignee.principalType)
  if ($candidateType -eq "Unknown") {
    return $null
  }

  if ($candidateType -eq "User") {
    $candidateName = [string]$CoAssignee.principalName
    if ([string]::IsNullOrWhiteSpace($candidateName)) {
      $candidateName = [string]$CoAssignee.principalDisplayName
    }
  } else {
    $candidateName = [string]$CoAssignee.principalDisplayName
  }

  if ([string]::IsNullOrWhiteSpace($candidateName)) {
    $candidateName = [string]$CoAssignee.principalId
  }

  if ([string]::IsNullOrWhiteSpace($candidateName)) {
    return $null
  }

  $candidateScore = Get-OwnerCandidatePolicyScore -Rule $Rule -CandidateType $candidateType
  if ($candidateType -eq "User" -and [bool]$CoAssignee.isStorageDataReadRole -and $candidateScore -lt 50) {
    $candidateScore = 50
  }

  return New-OwnerCandidate `
    -Candidate $candidateName `
    -CandidateType $candidateType `
    -Confidence (ConvertTo-OwnerConfidence -Score $candidateScore) `
    -Relationship "Indirect" `
    -Signal ([string]$Rule.Signal) `
    -EvidenceId ([string]$CoAssignee.scope) `
    -EvidenceSource ([string]$CoAssignee.scope) `
    -EvidenceValue ([string]$CoAssignee.roleDefinitionName) `
    -Reason "This principal has Azure RBAC on the same scope as the inspected service principal."
}

function Add-OwnerCandidateFromAzureActivityEvidence {
  param(
    [Parameter(Mandatory = $true)]
    [object]$Activity,

    [Parameter(Mandatory = $true)]
    [hashtable]$Rule
  )

  $candidateName = [string]$Activity.callerName
  if ([string]::IsNullOrWhiteSpace($candidateName)) {
    $candidateName = [string]$Activity.caller
  }
  if ([string]::IsNullOrWhiteSpace($candidateName)) {
    return $null
  }

  return New-OwnerCandidate `
    -Candidate $candidateName `
    -CandidateType "ActivityCaller" `
    -Confidence (ConvertTo-OwnerConfidence -Score (Get-OwnerCandidatePolicyScore -Rule $Rule -CandidateType "ActivityCaller")) `
    -Relationship "Indirect" `
    -Signal ([string]$Rule.Signal) `
    -EvidenceId ([string]$Activity.resourceId) `
    -EvidenceSource ([string]$Activity.resourceId) `
    -EvidenceValue ([string]$Activity.operationNameValue) `
    -Reason "Recent Azure activity matched the inspected service principal; this is weak ownership evidence."
}

function Get-OwnerCandidateRbacScopeActivityCallerName {
  param([object]$ActivityCaller)

  $caller = [string]$ActivityCaller.caller
  if ($caller -match "@") {
    return $caller
  }

  $callerName = [string]$ActivityCaller.callerName
  if (-not [string]::IsNullOrWhiteSpace($callerName)) {
    return $callerName
  }

  if (-not [string]::IsNullOrWhiteSpace($caller)) {
    return $caller
  }

  $callerObjectId = [string]$ActivityCaller.callerObjectId
  if (-not [string]::IsNullOrWhiteSpace($callerObjectId)) {
    return $callerObjectId
  }

  $callerAppId = [string]$ActivityCaller.callerAppId
  if (-not [string]::IsNullOrWhiteSpace($callerAppId)) {
    return $callerAppId
  }

  return [string]$ActivityCaller.callerKey
}

function Get-OwnerCandidateRbacScopeActivityCallerType {
  param([object]$ActivityCaller)

  return Get-OwnerLensPrincipalType `
    -Caller ([string]$ActivityCaller.caller) `
    -AppId ([string]$ActivityCaller.callerAppId) `
    -Fallback "ActivityCaller"
}

function Add-OwnerCandidateFromRbacScopeActivityCaller {
  param(
    [Parameter(Mandatory = $true)]
    [object]$ActivityCaller,

    [Parameter(Mandatory = $true)]
    [hashtable]$Rule
  )

  $candidateName = Get-OwnerCandidateRbacScopeActivityCallerName -ActivityCaller $ActivityCaller
  if ([string]::IsNullOrWhiteSpace($candidateName)) {
    return $null
  }

  $evidenceId = [string](@($ActivityCaller.rbacScopes) | Where-Object {
      -not [string]::IsNullOrWhiteSpace([string]$_)
    } | Select-Object -First 1)
  if ([string]::IsNullOrWhiteSpace($evidenceId)) {
    $evidenceId = [string]$ActivityCaller.callerKey
  }

  $candidateType = Get-OwnerCandidateRbacScopeActivityCallerType -ActivityCaller $ActivityCaller

  return New-OwnerCandidate `
    -Candidate $candidateName `
    -CandidateType $candidateType `
    -Confidence (ConvertTo-OwnerConfidence -Score (Get-OwnerCandidatePolicyScore -Rule $Rule -CandidateType $candidateType)) `
    -Relationship "Indirect" `
    -Signal ([string]$Rule.Signal) `
    -EvidenceId $evidenceId `
    -EvidenceSource "AzureActivity" `
    -EvidenceValue ("events={0},lastSeen={1}" -f [string]$ActivityCaller.eventCount, [string]$ActivityCaller.lastSeen) `
    -Reason "Recent Azure RBAC scope activity was performed by this principal under a scope where the inspected service principal has RBAC."
}

function Get-OwnerCandidateSasGeneratorName {
  param([object]$BlobRead)

  $sasGeneratorUpn = [string]$BlobRead.sasGeneratorUpn
  if (-not [string]::IsNullOrWhiteSpace($sasGeneratorUpn)) {
    return $sasGeneratorUpn
  }

  $sasGeneratorObjectId = [string]$BlobRead.sasGeneratorObjectId
  if (-not [string]::IsNullOrWhiteSpace($sasGeneratorObjectId)) {
    return $sasGeneratorObjectId
  }

  return [string]$BlobRead.sasGeneratorAppId
}

function Get-OwnerCandidateTextValue {
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

function Get-OwnerCandidateSasGeneratorType {
  param([object]$BlobRead)

  if (-not [string]::IsNullOrWhiteSpace([string]$BlobRead.sasGeneratorUpn)) {
    return "User"
  }

  if (-not [string]::IsNullOrWhiteSpace([string]$BlobRead.sasGeneratorAppId)) {
    return "ServicePrincipal"
  }

  return "SasGenerator"
}

function Add-OwnerCandidateFromSasGeneratorGroup {
  param(
    [Parameter(Mandatory = $true)]
    [object]$SasGeneratorGroup,

    [Parameter(Mandatory = $true)]
    [hashtable]$Rule
  )

  $sasEvents = @($SasGeneratorGroup.Group | Sort-Object eventTimestamp)
  $firstSasEvent = $sasEvents | Select-Object -First 1
  $candidateName = Get-OwnerCandidateSasGeneratorName -BlobRead $firstSasEvent
  if ([string]::IsNullOrWhiteSpace($candidateName)) {
    return $null
  }

  $evidenceId = [string]$firstSasEvent.storageAccountResourceId
  if ([string]::IsNullOrWhiteSpace($evidenceId)) {
    $evidenceId = [string]$firstSasEvent.uri
  }

  $evidenceValues = @($sasEvents | ForEach-Object {
      Get-OwnerCandidateTextValue -Value $_.operationName -Fallback $_.sasSignedPermissions
    } | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | Sort-Object -Unique)
  $candidateType = Get-OwnerCandidateSasGeneratorType -BlobRead $firstSasEvent

  return New-OwnerCandidate `
    -Candidate $candidateName `
    -CandidateType $candidateType `
    -Confidence (ConvertTo-OwnerConfidence -Score (Get-OwnerCandidatePolicyScore -Rule $Rule -CandidateType $candidateType)) `
    -Relationship "Indirect" `
    -Signal ([string]$Rule.Signal) `
    -EvidenceId $evidenceId `
    -EvidenceSource "StorageBlobLogs" `
    -EvidenceValue ([string]($evidenceValues -join ",")) `
    -Reason "StorageBlobLogs identify this principal as the generator of a user delegation SAS used for blob data-plane access."
}

function Add-OwnerCandidateNotFound {
  return New-OwnerCandidate `
    -Candidate "No owner candidate found" `
    -CandidateType "NotFound" `
    -Confidence "LOW" `
    -Relationship "None" `
    -Signal "NONE" `
    -EvidenceId "not-found" `
    -EvidenceSource "ownerCandidates" `
    -EvidenceValue "" `
    -Reason "No Graph owners, memberships, Azure RBAC co-assignments, resource owner tags, or activity evidence were found."
}

function Test-OwnerTagNameMatch {
  param(
    [string]$TagName,
    [hashtable]$TagNameSet
  )

  if ([string]::IsNullOrWhiteSpace($TagName) -or -not $TagNameSet) {
    return $false
  }

  return $TagNameSet.ContainsKey($TagName)
}

function Resolve-OwnerTagCandidateType {
  param(
    [string]$TagName,
    [hashtable]$UserOwnerTagNameSet,
    [hashtable]$GroupOwnerTagNameSet,
    [hashtable]$TagOwnerTagNameSet
  )

  if (Test-OwnerTagNameMatch -TagName $TagName -TagNameSet $UserOwnerTagNameSet) {
    return "User"
  }

  if (Test-OwnerTagNameMatch -TagName $TagName -TagNameSet $GroupOwnerTagNameSet) {
    return "Group"
  }

  if (Test-OwnerTagNameMatch -TagName $TagName -TagNameSet $TagOwnerTagNameSet) {
    return "Tag"
  }

  return ""
}

function Add-OwnerCandidatesFromTags {
  param(
    [object[]]$Tags,
    [string]$Relationship,
    [hashtable]$Rule,
    [string]$EvidenceId,
    [string]$EvidenceSource,
    [string]$Reason,
    [hashtable]$UserOwnerTagNameSet,
    [hashtable]$GroupOwnerTagNameSet,
    [hashtable]$TagOwnerTagNameSet
  )

  if (-not (Test-OwnerCandidatePolicyEnabled -Rule $Rule)) {
    return @()
  }

  foreach ($tag in @($Tags)) {
    if ([string]::IsNullOrWhiteSpace([string]$tag.Value)) {
      continue
    }

    $candidateType = Resolve-OwnerTagCandidateType `
      -TagName ([string]$tag.Name) `
      -UserOwnerTagNameSet $UserOwnerTagNameSet `
      -GroupOwnerTagNameSet $GroupOwnerTagNameSet `
      -TagOwnerTagNameSet $TagOwnerTagNameSet

    if ([string]::IsNullOrWhiteSpace($candidateType)) {
      continue
    }

    New-OwnerCandidate `
      -Candidate (Format-OwnerTagCandidateValue -TagName ([string]$tag.Name) -TagValue ([string]$tag.Value) -CandidateType $candidateType) `
      -CandidateType $candidateType `
      -Confidence (ConvertTo-OwnerConfidence -Score (Get-OwnerCandidatePolicyScore -Rule $Rule -CandidateType $candidateType)) `
      -Relationship $Relationship `
      -Signal ([string]$Rule.Signal) `
      -EvidenceId $EvidenceId `
      -EvidenceSource $EvidenceSource `
      -EvidenceValue ("{0}={1}" -f $tag.Name, [string]$tag.Value) `
      -Reason $Reason
  }
}
