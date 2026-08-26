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

function Test-OwnerCandidatePolicyEnabled {
  param([hashtable]$Rule)

  return ($Rule -and [bool]$Rule.Enabled)
}

function Get-OwnerConfidenceRank {
  param([string]$Confidence)

  switch ($Confidence) {
    "HIGH" { return 3 }
    "MED" { return 2 }
    default { return 1 }
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
    $candidates += Add-OwnerCandidateFromGraphOwner -Owner $owner -EnterpriseApplication $enterpriseApplication -Rule $rule
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
    $candidates += Add-OwnerCandidateFromDirectoryRelationship -MemberOf $memberOf -EnterpriseApplication $enterpriseApplication -Rule $rule
  }

  $rule = $OwnerCandidatePolicy.SharedRbacScope
  if (-not (Test-OwnerCandidatePolicyEnabled -Rule $rule)) {
    $coAssignedRoleCandidates = @()
  }

  foreach ($coAssignee in @($coAssignedRoleCandidates)) {
    $candidate = Add-OwnerCandidateFromCoAssignedRoleCandidate -CoAssignee $coAssignee -Rule $rule
    if ($null -ne $candidate) {
      $candidates += $candidate
    }
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
    $candidate = Add-OwnerCandidateFromAzureActivityEvidence -Activity $activity -Rule $rule
    if ($null -ne $candidate) {
      $candidates += $candidate
    }
  }

  foreach ($activityCaller in @($rbacScopeActivityCallers | Where-Object {
        -not [bool]$_.matchesInspectedServicePrincipal
      })) {
    $candidate = Add-OwnerCandidateFromRbacScopeActivityCaller -ActivityCaller $activityCaller -Rule $rule
    if ($null -ne $candidate) {
      $candidates += $candidate
    }
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
    $candidate = Add-OwnerCandidateFromSasGeneratorGroup -SasGeneratorGroup $sasGeneratorGroup -Rule $rule
    if ($null -ne $candidate) {
      $candidates += $candidate
    }
  }

  $rankedCandidates = @($candidates |
    Sort-Object @{ Expression = { Get-OwnerConfidenceRank -Confidence ([string]$_.confidence) }; Descending = $true }, candidate, evidenceId)

  if ($rankedCandidates.Count -eq 0) {
    return @(Add-OwnerCandidateNotFound)
  }

  return $rankedCandidates
}
