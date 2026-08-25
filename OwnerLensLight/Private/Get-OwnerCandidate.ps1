$OwnerCandidatePolicy = @{
  ExplicitOwner = @{
    Enabled = $true
    Score = 95
    Signal = "OWNER"
  }

  ExplicitOwnerTag = @{
    Enabled = $true
    Score = 80
    Signal = "TAG"
  }

  DirectoryRelationship = @{
    Enabled = $true
    Score = 30
    Signal = "MEMBERSHIP"
  }

  SharedRbacScope = @{
    Enabled = $true
    ScoreByCandidateType = @{
      User = 35
      Group = 30
      Default = 30
    }
    Signal = "RBAC"
  }

  OperationalActivity = @{
    Enabled = $true
    Score = 25
    Signal = "LOG"
  }

  CredentialGenerator = @{
    Enabled = $true
    Score = 40
    Signal = "SAS"
  }
}

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

function Test-OwnerCandidatePolicyEnabled {
  param([hashtable]$Rule)

  return ($Rule -and [bool]$Rule.Enabled)
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

function Get-OwnerCandidateSasGeneratorKey {
  param([object]$BlobRead)

  $sasGeneratorUpn = [string]$BlobRead.sasGeneratorUpn
  if (-not [string]::IsNullOrWhiteSpace($sasGeneratorUpn)) {
    return "upn:$sasGeneratorUpn"
  }

  $sasGeneratorObjectId = [string]$BlobRead.sasGeneratorObjectId
  if (-not [string]::IsNullOrWhiteSpace($sasGeneratorObjectId)) {
    return "object:$sasGeneratorObjectId"
  }

  $sasGeneratorAppId = [string]$BlobRead.sasGeneratorAppId
  if (-not [string]::IsNullOrWhiteSpace($sasGeneratorAppId)) {
    return "app:$sasGeneratorAppId"
  }

  return ""
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

function Get-OwnerCandidates {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]
    [object]$Report,

    [string[]]$UserOwnerTagNames = @("userOwner", "technicalOwner", "businessOwner"),

    [string[]]$GroupOwnerTagNames = @("groupOwner", "ownerGroup", "teamOwner", "team"),

    [string[]]$TagOwnerTagNames = @("owner", "serviceOwner", "appOwner", "applicationOwner", "productOwner", "ownedBy", "costCenter", "costCentre", "cost-center", "cost_center")
  )

  $userOwnerTagNameSet = ConvertTo-OwnerTagNameSet -TagNames $UserOwnerTagNames
  $groupOwnerTagNameSet = ConvertTo-OwnerTagNameSet -TagNames $GroupOwnerTagNames
  $tagOwnerTagNameSet = ConvertTo-OwnerTagNameSet -TagNames $TagOwnerTagNames
  $candidates = @()
  $enterpriseApplication = Get-OwnerLensReportValue -Report $Report -Path "enterpriseApplication"
  $graphOwners = Get-OwnerLensReportArray -Report $Report -Path "graph.owners"
  $graphMemberships = Get-OwnerLensReportArray -Report $Report -Path "graph.memberOf"
  $coAssignedRoleCandidates = Get-OwnerLensReportArray -Report $Report -Path "azure.coAssignedRoleCandidates"
  $resourceDependencies = Get-OwnerLensReportArray -Report $Report -Path "azure.resourceDependencies"
  $azureActivityEvidence = Get-OwnerLensReportArray -Report $Report -Path "azure.activityEvidence"
  $rbacScopeActivityCallers = Get-OwnerLensReportArray -Report $Report -Path "azure.rbacScopeActivityCallers"
  $blobReadEvidence = Get-OwnerLensReportArray -Report $Report -Path "azure.blobReadEvidence"

  $rule = $OwnerCandidatePolicy.ExplicitOwner
  if (-not (Test-OwnerCandidatePolicyEnabled -Rule $rule)) {
    $graphOwners = @()
  }

  foreach ($owner in @($graphOwners)) {
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

    $ownerEvidenceBase = "/servicePrincipals/$($enterpriseApplication.objectId)"
    $ownerReason = "Direct Microsoft Graph owner on the service principal."
    if ($ownerSource -eq "Application" -and -not [string]::IsNullOrWhiteSpace([string]$enterpriseApplication.applicationObjectId)) {
      $ownerEvidenceBase = "/applications/$($enterpriseApplication.applicationObjectId)"
      $ownerReason = "Direct Microsoft Graph owner on the application registration."
    }

    $candidates += New-OwnerCandidate `
      -Candidate $candidateName `
      -CandidateType $candidateType `
      -Confidence (ConvertTo-OwnerConfidence -Score (Get-OwnerCandidatePolicyScore -Rule $rule -CandidateType $candidateType)) `
      -Relationship "Direct" `
      -Signal ([string]$rule.Signal) `
      -EvidenceId ("{0}/owners/{1}" -f $ownerEvidenceBase, [string]$owner.objectId) `
      -EvidenceSource "$ownerEvidenceBase/owners" `
      -EvidenceValue ([string]$owner.objectId) `
      -Reason $ownerReason
  }

  $candidates += Add-OwnerCandidatesFromTags `
    -Tags (Get-EnterpriseApplicationOwnerTagEntries -Tags $enterpriseApplication.tags) `
    -Relationship "Direct" `
    -Rule $OwnerCandidatePolicy.ExplicitOwnerTag `
    -EvidenceId ([string]$enterpriseApplication.objectId) `
    -EvidenceSource "/servicePrincipals/$($enterpriseApplication.objectId)/tags" `
    -Reason "Owner-like tag found directly on the inspected service principal." `
    -UserOwnerTagNameSet $userOwnerTagNameSet `
    -GroupOwnerTagNameSet $groupOwnerTagNameSet `
    -TagOwnerTagNameSet $tagOwnerTagNameSet

  $rule = $OwnerCandidatePolicy.DirectoryRelationship
  if (-not (Test-OwnerCandidatePolicyEnabled -Rule $rule)) {
    $graphMemberships = @()
  }

  foreach ($memberOf in @($graphMemberships)) {
    $candidateType = ConvertTo-OwnerCandidateType -ObjectType ([string]$memberOf.objectType)
    $candidateName = [string]$memberOf.displayName
    if ([string]::IsNullOrWhiteSpace($candidateName)) {
      $candidateName = [string]$memberOf.objectId
    }

    $candidates += New-OwnerCandidate `
      -Candidate $candidateName `
      -CandidateType $candidateType `
      -Confidence (ConvertTo-OwnerConfidence -Score (Get-OwnerCandidatePolicyScore -Rule $rule -CandidateType $candidateType)) `
      -Relationship "Indirect" `
      -Signal ([string]$rule.Signal) `
      -EvidenceId ("/servicePrincipals/{0}/memberOf/{1}" -f $enterpriseApplication.objectId, [string]$memberOf.objectId) `
      -EvidenceSource "/servicePrincipals/$($enterpriseApplication.objectId)/memberOf" `
      -EvidenceValue ([string]$memberOf.objectId) `
      -Reason "The service principal is a member of this directory object."
  }

  $rule = $OwnerCandidatePolicy.SharedRbacScope
  if (-not (Test-OwnerCandidatePolicyEnabled -Rule $rule)) {
    $coAssignedRoleCandidates = @()
  }

  foreach ($coAssignee in @($coAssignedRoleCandidates)) {
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

    $candidates += New-OwnerCandidate `
      -Candidate $candidateName `
      -CandidateType $candidateType `
      -Confidence (ConvertTo-OwnerConfidence -Score (Get-OwnerCandidatePolicyScore -Rule $rule -CandidateType $candidateType)) `
      -Relationship "Indirect" `
      -Signal ([string]$rule.Signal) `
      -EvidenceId ([string]$coAssignee.scope) `
      -EvidenceSource ([string]$coAssignee.scope) `
      -EvidenceValue ([string]$coAssignee.roleDefinitionName) `
      -Reason "This principal has Azure RBAC on the same scope as the inspected service principal."
  }

  foreach ($resource in @($resourceDependencies)) {
    if (-not $resource.tags) {
      continue
    }

    $candidates += Add-OwnerCandidatesFromTags `
      -Tags (Get-OwnerCandidateTagEntries -Tags $resource.tags) `
      -Relationship "Indirect" `
      -Rule $OwnerCandidatePolicy.SharedRbacScope `
      -EvidenceId ([string]$resource.resourceId) `
      -EvidenceSource ([string]$resource.resourceId) `
      -Reason "Azure resource tag found on a resource reached through RBAC assigned to the inspected service principal." `
      -UserOwnerTagNameSet $userOwnerTagNameSet `
      -GroupOwnerTagNameSet $groupOwnerTagNameSet `
      -TagOwnerTagNameSet $tagOwnerTagNameSet
  }

  $rule = $OwnerCandidatePolicy.OperationalActivity
  if (-not (Test-OwnerCandidatePolicyEnabled -Rule $rule)) {
    $azureActivityEvidence = @()
    $rbacScopeActivityCallers = @()
  }

  foreach ($activity in @($azureActivityEvidence)) {
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
      -Confidence (ConvertTo-OwnerConfidence -Score (Get-OwnerCandidatePolicyScore -Rule $rule -CandidateType "ActivityCaller")) `
      -Relationship "Indirect" `
      -Signal ([string]$rule.Signal) `
      -EvidenceId ([string]$activity.resourceId) `
      -EvidenceSource ([string]$activity.resourceId) `
      -EvidenceValue ([string]$activity.operationNameValue) `
      -Reason "Recent Azure activity matched the inspected service principal; this is weak ownership evidence."
  }

  foreach ($activityCaller in @($rbacScopeActivityCallers | Where-Object {
        -not [bool]$_.matchesInspectedServicePrincipal
      })) {
    $candidateName = Get-OwnerCandidateRbacScopeActivityCallerName -ActivityCaller $activityCaller
    if ([string]::IsNullOrWhiteSpace($candidateName)) {
      continue
    }

    $evidenceId = [string](@($activityCaller.rbacScopes) | Where-Object {
        -not [string]::IsNullOrWhiteSpace([string]$_)
      } | Select-Object -First 1)
    if ([string]::IsNullOrWhiteSpace($evidenceId)) {
      $evidenceId = [string]$activityCaller.callerKey
    }

    $candidates += New-OwnerCandidate `
      -Candidate $candidateName `
      -CandidateType (Get-OwnerCandidateRbacScopeActivityCallerType -ActivityCaller $activityCaller) `
      -Confidence (ConvertTo-OwnerConfidence -Score (Get-OwnerCandidatePolicyScore -Rule $rule -CandidateType (Get-OwnerCandidateRbacScopeActivityCallerType -ActivityCaller $activityCaller))) `
      -Relationship "Indirect" `
      -Signal ([string]$rule.Signal) `
      -EvidenceId $evidenceId `
      -EvidenceSource "AzureActivity" `
      -EvidenceValue ("events={0},lastSeen={1}" -f [string]$activityCaller.eventCount, [string]$activityCaller.lastSeen) `
      -Reason "Recent Azure RBAC scope activity was performed by this principal under a scope where the inspected service principal has RBAC."
  }

  $sasGeneratorGroups = @($blobReadEvidence | Where-Object {
      ([string]$_.authenticationType).Equals("SAS", [System.StringComparison]::OrdinalIgnoreCase) -and
      -not [string]::IsNullOrWhiteSpace((Get-OwnerCandidateSasGeneratorKey -BlobRead $_))
    } | Group-Object { Get-OwnerCandidateSasGeneratorKey -BlobRead $_ })

  $rule = $OwnerCandidatePolicy.CredentialGenerator
  if (-not (Test-OwnerCandidatePolicyEnabled -Rule $rule)) {
    $sasGeneratorGroups = @()
  }

  foreach ($sasGeneratorGroup in $sasGeneratorGroups) {
    $sasEvents = @($sasGeneratorGroup.Group | Sort-Object eventTimestamp)
    $firstSasEvent = $sasEvents | Select-Object -First 1
    $candidateName = Get-OwnerCandidateSasGeneratorName -BlobRead $firstSasEvent
    if ([string]::IsNullOrWhiteSpace($candidateName)) {
      continue
    }

    $evidenceId = [string]$firstSasEvent.storageAccountResourceId
    if ([string]::IsNullOrWhiteSpace($evidenceId)) {
      $evidenceId = [string]$firstSasEvent.uri
    }

    $evidenceValues = @($sasEvents | ForEach-Object {
        Get-OwnerCandidateTextValue -Value $_.operationName -Fallback $_.sasSignedPermissions
      } | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | Sort-Object -Unique)

    $candidates += New-OwnerCandidate `
      -Candidate $candidateName `
      -CandidateType (Get-OwnerCandidateSasGeneratorType -BlobRead $firstSasEvent) `
      -Confidence (ConvertTo-OwnerConfidence -Score (Get-OwnerCandidatePolicyScore -Rule $rule -CandidateType (Get-OwnerCandidateSasGeneratorType -BlobRead $firstSasEvent))) `
      -Relationship "Indirect" `
      -Signal ([string]$rule.Signal) `
      -EvidenceId $evidenceId `
      -EvidenceSource "StorageBlobLogs" `
      -EvidenceValue ([string]($evidenceValues -join ",")) `
      -Reason "StorageBlobLogs identify this principal as the generator of a user delegation SAS used for blob data-plane access."
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
