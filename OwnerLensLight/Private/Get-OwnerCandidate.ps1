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

function Get-OwnerConfidenceRank {
  param([string]$Confidence)

  switch ($Confidence) {
    "HIGH" { return 3 }
    "MED" { return 2 }
    default { return 1 }
  }
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

function Get-TagOwnerConfidence {
  param([string]$TagName)

  switch -Regex ($TagName) {
    "^(owner|serviceOwner|technicalOwner|businessOwner|team)$" { return 80 }
    "^(repo|repository|repoName|source|sourceRepo)$" { return 60 }
    "^(application|app|product|service)$" { return 45 }
    default { return 30 }
  }
}

function ConvertTo-OwnerTagNameSet {
  param([string[]]$TagNames)

  $tagNameSet = @{}
  foreach ($tagName in @($TagNames)) {
    if ([string]::IsNullOrWhiteSpace($tagName)) {
      continue
    }

    $tagNameSet[[string]$tagName] = $true
  }

  return $tagNameSet
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

function Format-OwnerTagCandidateValue {
  param(
    [string]$TagName,
    [string]$TagValue,
    [string]$CandidateType
  )

  if ($CandidateType -eq "User" -or $CandidateType -eq "Group") {
    return $TagValue
  }

  return ("{0}={1}" -f $TagName, $TagValue)
}

function Get-OwnerCandidateTagEntries {
  param([object]$Tags)

  if (-not $Tags) {
    return @()
  }

  if ($Tags -is [System.Collections.IDictionary]) {
    return @($Tags.Keys | ForEach-Object {
      [pscustomobject]@{
        Name = [string]$_
        Value = [string]$Tags[$_]
      }
    })
  }

  return @($Tags.PSObject.Properties | ForEach-Object {
    [pscustomobject]@{
      Name = [string]$_.Name
      Value = [string]$_.Value
    }
  })
}

function Get-EnterpriseApplicationOwnerTagEntries {
  param([object]$Tags)

  if (-not $Tags) {
    return @()
  }

  if ($Tags -is [System.Collections.IDictionary]) {
    return @(Get-OwnerCandidateTagEntries -Tags $Tags)
  }

  return @($Tags | ForEach-Object {
    $tagText = [string]$_
    if ([string]::IsNullOrWhiteSpace($tagText)) {
      return
    }

    if ($tagText -match "^\s*([^=:]+)\s*[=:]\s*(.+?)\s*$") {
      [pscustomobject]@{
        Name = [string]$Matches[1]
        Value = [string]$Matches[2]
      }
    }
  })
}

function ConvertTo-OwnerCandidateTsvField {
  param([object]$Value)

  if ($null -eq $Value) {
    return ""
  }

  return ([string]$Value) -replace "[`t`r`n]+", " "
}

function Format-OwnerCandidateTable {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]
    [object[]]$Candidates
  )

  $rows = @($Candidates |
    Group-Object candidate, candidateType |
    ForEach-Object {
      $groupRows = @($_.Group | Sort-Object @{ Expression = { Get-OwnerConfidenceRank -Confidence ([string]$_.confidence) }; Descending = $true }, evidenceId)
      $bestConfidence = [string]$groupRows[0].confidence
      [pscustomobject]@{
        candidate = [string]$groupRows[0].candidate
        type = [string]$groupRows[0].candidateType
        confidence = $bestConfidence
        relationship = [string](($groupRows | Select-Object -ExpandProperty relationship -Unique) -join ",")
        signal = [string](($groupRows | Select-Object -ExpandProperty signal -Unique) -join ",")
        evidenceId = [string](($groupRows | Select-Object -ExpandProperty evidenceId -First 4) -join ",")
      }
    } |
    Sort-Object @{ Expression = { Get-OwnerConfidenceRank -Confidence ([string]$_.confidence) }; Descending = $true }, candidate)

  $columns = @("candidate", "type", "confidence", "relationship", "signal", "evidenceId")
  $lines = @(
    ($columns -join "`t")
    $rows | ForEach-Object {
      $row = $_
      (($columns | ForEach-Object { ConvertTo-OwnerCandidateTsvField -Value $row.$_ }) -join "`t")
    }
  )

  return ($lines -join [Environment]::NewLine)
}

function Get-OwnerCandidates {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]
    [object]$Report,

    [string[]]$UserOwnerTagNames = @("userOwner", "technicalOwner", "businessOwner"),

    [string[]]$GroupOwnerTagNames = @("groupOwner", "ownerGroup", "teamOwner", "team"),

    [string[]]$TagOwnerTagNames = @("owner", "serviceOwner", "costCenter", "costCentre", "cost-center", "cost_center")
  )

  $userOwnerTagNameSet = ConvertTo-OwnerTagNameSet -TagNames $UserOwnerTagNames
  $groupOwnerTagNameSet = ConvertTo-OwnerTagNameSet -TagNames $GroupOwnerTagNames
  $tagOwnerTagNameSet = ConvertTo-OwnerTagNameSet -TagNames $TagOwnerTagNames
  $candidates = @()
  foreach ($owner in @($Report.graph.owners)) {
    $candidateType = ConvertTo-OwnerCandidateType -ObjectType ([string]$owner.objectType)
    if ($candidateType -eq "User") {
      $candidateName = [string]$owner.userPrincipalName
      if ([string]::IsNullOrWhiteSpace($candidateName)) {
        $candidateName = [string]$owner.mail
      }
      if ([string]::IsNullOrWhiteSpace($candidateName)) {
        $candidateName = [string]$owner.displayName
      }
    } else {
      $candidateName = [string]$owner.displayName
    }

    if ([string]::IsNullOrWhiteSpace($candidateName)) {
      $candidateName = [string]$owner.objectId
    }

    $ownerSource = [string]$owner.ownerSource
    if ([string]::IsNullOrWhiteSpace($ownerSource)) {
      $ownerSource = "ServicePrincipal"
    }

    $ownerEvidenceBase = "/servicePrincipals/$($Report.enterpriseApplication.objectId)"
    $ownerReason = "Direct Microsoft Graph owner on the service principal."
    if ($ownerSource -eq "Application" -and -not [string]::IsNullOrWhiteSpace([string]$Report.enterpriseApplication.applicationObjectId)) {
      $ownerEvidenceBase = "/applications/$($Report.enterpriseApplication.applicationObjectId)"
      $ownerReason = "Direct Microsoft Graph owner on the application registration."
    }

    $candidates += New-OwnerCandidate `
      -Candidate $candidateName `
      -CandidateType $candidateType `
      -Confidence (ConvertTo-OwnerConfidence -Score 95) `
      -Relationship "Direct" `
      -Signal "OWNER" `
      -EvidenceId ("{0}/owners/{1}" -f $ownerEvidenceBase, [string]$owner.objectId) `
      -EvidenceSource "$ownerEvidenceBase/owners" `
      -EvidenceValue ([string]$owner.objectId) `
      -Reason $ownerReason
  }

  foreach ($tag in @(Get-EnterpriseApplicationOwnerTagEntries -Tags $Report.enterpriseApplication.tags)) {
    if ([string]::IsNullOrWhiteSpace([string]$tag.Value)) {
      continue
    }

    $candidateType = Resolve-OwnerTagCandidateType `
      -TagName ([string]$tag.Name) `
      -UserOwnerTagNameSet $userOwnerTagNameSet `
      -GroupOwnerTagNameSet $groupOwnerTagNameSet `
      -TagOwnerTagNameSet $tagOwnerTagNameSet

    if ([string]::IsNullOrWhiteSpace($candidateType)) {
      continue
    }

    $candidates += New-OwnerCandidate `
      -Candidate (Format-OwnerTagCandidateValue -TagName ([string]$tag.Name) -TagValue ([string]$tag.Value) -CandidateType $candidateType) `
      -CandidateType $candidateType `
      -Confidence (ConvertTo-OwnerConfidence -Score (Get-TagOwnerConfidence -TagName ([string]$tag.Name))) `
      -Relationship "Direct" `
      -Signal "TAG" `
      -EvidenceId ([string]$Report.enterpriseApplication.objectId) `
      -EvidenceSource "/servicePrincipals/$($Report.enterpriseApplication.objectId)/tags" `
      -EvidenceValue ("{0}={1}" -f $tag.Name, [string]$tag.Value) `
      -Reason "Owner-like tag found directly on the inspected service principal."
  }

  foreach ($memberOf in @($Report.graph.memberOf)) {
    $candidateType = ConvertTo-OwnerCandidateType -ObjectType ([string]$memberOf.objectType)
    $candidateName = [string]$memberOf.displayName
    if ([string]::IsNullOrWhiteSpace($candidateName)) {
      $candidateName = [string]$memberOf.objectId
    }

    $candidates += New-OwnerCandidate `
      -Candidate $candidateName `
      -CandidateType $candidateType `
      -Confidence (ConvertTo-OwnerConfidence -Score 70) `
      -Relationship "Indirect" `
      -Signal "MEMBERSHIP" `
      -EvidenceId ("/servicePrincipals/{0}/memberOf/{1}" -f $Report.enterpriseApplication.objectId, [string]$memberOf.objectId) `
      -EvidenceSource "/servicePrincipals/$($Report.enterpriseApplication.objectId)/memberOf" `
      -EvidenceValue ([string]$memberOf.objectId) `
      -Reason "The service principal is a member of this directory object."
  }

  foreach ($coAssignee in @($Report.azure.coAssignedRoleCandidates)) {
    $candidateType = ConvertTo-OwnerCandidateType -ObjectType ([string]$coAssignee.principalType)
    if ($candidateType -eq "Unknown") {
      continue
    }

    if ($candidateType -eq "User") {
      $candidateName = [string]$coAssignee.principalName
      if ([string]::IsNullOrWhiteSpace($candidateName)) {
        $candidateName = [string]$coAssignee.principalDisplayName
      }
    } else {
      $candidateName = [string]$coAssignee.principalDisplayName
    }

    if ([string]::IsNullOrWhiteSpace($candidateName)) {
      $candidateName = [string]$coAssignee.principalId
    }

    if ([string]::IsNullOrWhiteSpace($candidateName)) {
      continue
    }

    $confidence = if ($candidateType -eq "User") { 65 } elseif ($candidateType -eq "Group") { 60 } else { 45 }
    $candidates += New-OwnerCandidate `
      -Candidate $candidateName `
      -CandidateType $candidateType `
      -Confidence (ConvertTo-OwnerConfidence -Score $confidence) `
      -Relationship "Indirect" `
      -Signal "RBAC" `
      -EvidenceId ([string]$coAssignee.scope) `
      -EvidenceSource ([string]$coAssignee.scope) `
      -EvidenceValue ([string]$coAssignee.roleDefinitionName) `
      -Reason "This principal has Azure RBAC on the same scope as the inspected service principal."
  }

  foreach ($resource in @($Report.azure.resourceDependencies)) {
    if (-not $resource.tags) {
      continue
    }

    foreach ($tag in @(Get-OwnerCandidateTagEntries -Tags $resource.tags)) {
      if ([string]::IsNullOrWhiteSpace([string]$tag.Value)) {
        continue
      }

      $candidateType = Resolve-OwnerTagCandidateType `
        -TagName ([string]$tag.Name) `
        -UserOwnerTagNameSet $userOwnerTagNameSet `
        -GroupOwnerTagNameSet $groupOwnerTagNameSet `
        -TagOwnerTagNameSet $tagOwnerTagNameSet

      if ([string]::IsNullOrWhiteSpace($candidateType)) {
        continue
      }

      $candidates += New-OwnerCandidate `
        -Candidate (Format-OwnerTagCandidateValue -TagName ([string]$tag.Name) -TagValue ([string]$tag.Value) -CandidateType $candidateType) `
        -CandidateType $candidateType `
        -Confidence (ConvertTo-OwnerConfidence -Score (Get-TagOwnerConfidence -TagName ([string]$tag.Name))) `
        -Relationship "Indirect" `
        -Signal "RBAC" `
        -EvidenceId ([string]$resource.resourceId) `
        -EvidenceSource ([string]$resource.resourceId) `
        -EvidenceValue ("{0}={1}" -f $tag.Name, [string]$tag.Value) `
        -Reason "Azure resource tag found on a resource reached through RBAC assigned to the inspected service principal."
    }
  }

  foreach ($activity in @($Report.azure.activityEvidence)) {
    $candidateName = [string]$activity.callerName
    if ([string]::IsNullOrWhiteSpace($candidateName)) {
      $candidateName = [string]$activity.caller
    }
    if ([string]::IsNullOrWhiteSpace($candidateName)) {
      continue
    }

    $candidates += New-OwnerCandidate `
      -Candidate $candidateName `
      -CandidateType "ActivityCaller" `
      -Confidence (ConvertTo-OwnerConfidence -Score 25) `
      -Relationship "Indirect" `
      -Signal "LOG" `
      -EvidenceId ([string]$activity.resourceId) `
      -EvidenceSource ([string]$activity.resourceId) `
      -EvidenceValue ([string]$activity.operationNameValue) `
      -Reason "Recent Azure activity matched the inspected service principal; this is weak ownership evidence."
  }

  $rankedCandidates = @($candidates |
    Sort-Object @{ Expression = { Get-OwnerConfidenceRank -Confidence ([string]$_.confidence) }; Descending = $true }, candidate, evidenceId)

  if ($rankedCandidates.Count -eq 0) {
    return @(
      New-OwnerCandidate `
        -Candidate "No owner candidate found" `
        -CandidateType "NotFound" `
        -Confidence "LOW" `
        -Relationship "None" `
        -Signal "NONE" `
        -EvidenceId "not-found" `
        -EvidenceSource "ownerCandidates" `
        -EvidenceValue "" `
        -Reason "No Graph owners, memberships, Azure RBAC co-assignments, resource owner tags, or activity evidence were found."
    )
  }

  return $rankedCandidates
}
