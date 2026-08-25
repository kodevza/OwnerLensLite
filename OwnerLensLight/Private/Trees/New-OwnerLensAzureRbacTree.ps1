function Test-OwnerLensResourceUnderScope {
  param(
    [string]$ResourceId,
    [string]$Scope
  )

  if ([string]::IsNullOrWhiteSpace($ResourceId) -or [string]::IsNullOrWhiteSpace($Scope)) {
    return $false
  }

  $normalizedResourceId = $ResourceId.TrimEnd("/")
  $normalizedScope = $Scope.TrimEnd("/")

  return (
    $normalizedResourceId.Equals($normalizedScope, [System.StringComparison]::OrdinalIgnoreCase) -or
    $normalizedResourceId.StartsWith("$normalizedScope/", [System.StringComparison]::OrdinalIgnoreCase)
  )
}

function Get-OwnerLensResourceLabel {
  param(
    [object]$Dependency,
    [object]$Assignment
  )

  if ($Dependency) {
    $resourceName = Get-OwnerLensDisplayValue -Value $Dependency.resourceName -Fallback ([string]$Dependency.resourceId)
    $dependencyType = Get-OwnerLensDisplayValue -Value $Dependency.dependencyType -Fallback "Scope"
    $resourceType = Get-OwnerLensDisplayValue -Value $Dependency.resourceType
    $resourceGroup = Get-OwnerLensDisplayValue -Value $Dependency.resourceGroup
    $resourceId = [string]$Dependency.resourceId
    $resourceLabel = Format-OwnerLensRichLink `
      -Text $resourceName `
      -Uri (ConvertTo-OwnerLensAzurePortalResourceUri -ResourceId $resourceId)
    $scopeDetails = @()

    if (-not [string]::IsNullOrWhiteSpace($resourceType)) {
      $scopeDetails += $resourceType
    }

    if (-not [string]::IsNullOrWhiteSpace($resourceGroup)) {
      $scopeDetails += "rg=$resourceGroup"
    }

    if ($scopeDetails.Count -gt 0) {
      return "[blue]$dependencyType`: $resourceLabel ($($scopeDetails -join ", "))[/]"
    }

    return "[blue]$dependencyType`: $resourceLabel[/]"
  }

  $scope = Get-OwnerLensDisplayValue -Value $Assignment.scope -Fallback "unknown scope"
  return "[blue]Scope: $(Format-OwnerLensAzureResourceId -ResourceId $scope)[/]"
}

function Get-OwnerLensDefaultAzureOwnerTagNames {
  @("userOwner", "technicalOwner", "businessOwner", "groupOwner", "ownerGroup", "teamOwner", "team", "owner", "serviceOwner", "appOwner", "applicationOwner", "productOwner", "managedBy", "ownedBy", "costCenter", "costCentre", "cost-center", "cost_center")
}

function Add-OwnerLensTagNodes {
  param(
    [object]$Tree,
    [object]$Tags,
    [string[]]$OwnerTagNames = @()
  )

  if (-not $Tags) {
    return
  }

  $tagRows = @()
  if ($Tags -is [hashtable] -or $Tags -is [System.Collections.IDictionary]) {
    foreach ($key in $Tags.Keys) {
      $tagRows += [pscustomobject]@{ key = [string]$key; value = [string]$Tags[$key] }
    }
  }
  else {
    foreach ($property in $Tags.PSObject.Properties) {
      $tagRows += [pscustomobject]@{ key = [string]$property.Name; value = [string]$property.Value }
    }
  }

  $tagRows = @($tagRows | Where-Object { -not [string]::IsNullOrWhiteSpace($_.key) } | Sort-Object key)
  if ($tagRows.Count -eq 0) {
    return
  }

  $ownerTagNameSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
  foreach ($ownerTagName in @($OwnerTagNames)) {
    if (-not [string]::IsNullOrWhiteSpace($ownerTagName)) {
      $ownerTagNameSet.Add([string]$ownerTagName) | Out-Null
    }
  }

  $tagsNode = Add-RichTreeNode $Tree "tags ($($tagRows.Count))" -PassThru
  foreach ($tag in $tagRows) {
    $tagText = "$($tag.key)=$($tag.value)"
    if ($ownerTagNameSet.Contains([string]$tag.key)) {
      $tagText = "[green]$tagText[/]"
    }

    Add-RichTreeNode $tagsNode $tagText
  }
}

function Format-OwnerLensStorageDiagnosticStatus {
  param([object]$StorageAccount)

  $diagnosticServices = @($StorageAccount.diagnosticSettings | Sort-Object service)
  $configuredServices = @($diagnosticServices | Where-Object dataAccessLogEnabled)
  if ($configuredServices.Count -eq 0) {
    return "[yellow]No diagnostic settings detected; not possible to detect data access based on logs to increase accuracy.[/]"
  }

  $serviceSummaries = @($configuredServices | ForEach-Object {
      $settingNames = @($_.diagnosticSettingNames | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }) -join ","
      $workspaceIds = @($_.workspaceIds | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | ForEach-Object {
          Format-OwnerLensShortAzureResourceLink -ResourceId ([string]$_)
        }) -join ","
      $details = @("status=$($_.status)")

      if (-not [string]::IsNullOrWhiteSpace($settingNames)) {
        $details += "settings=$settingNames"
      }

      if (-not [string]::IsNullOrWhiteSpace($workspaceIds)) {
        $details += "workspaces=$workspaceIds"
      }

      "$($_.service) ($($details -join ", "))"
    })

  return "[dim]Configured: $($serviceSummaries -join "; ")[/]"
}

function Get-OwnerLensPrincipalDisplayText {
  param(
    [string]$Label,
    [string]$PrincipalType,
    [string]$PrincipalId,
    [string]$PrincipalUpn
  )

  $displayLabel = Get-OwnerLensDisplayValue -Value $Label -Fallback "unknown principal"
  $displayType = Get-OwnerLensDisplayValue -Value $PrincipalType -Fallback "Principal"
  $displayId = Get-OwnerLensDisplayValue -Value $PrincipalId -Fallback "unknown id"
  $displayUpn = Get-OwnerLensDisplayValue -Value $PrincipalUpn -Fallback "unknown upn"

  return "$displayLabel ($displayType, id=$displayId, upn=$displayUpn)"
}

function Get-OwnerLensActivityCallerPrincipalType {
  param([object]$Caller)

  return Get-OwnerLensPrincipalType `
    -Caller ([string]$Caller.caller) `
    -AppId ([string]$Caller.callerAppId)
}

function New-OwnerLensAzureRbacTree {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]
    [object]$Report
  )

  $sp = Get-OwnerLensReportValue -Report $Report -Path "enterpriseApplication"
  $displayName = Get-OwnerLensDisplayValue -Value $sp.displayName -Fallback "service principal"
  $root = New-RichTree "[magenta]Service Principal: $displayName (objectId=$($sp.objectId), appId=$($sp.appId))[/]"
  $roleAssignments = Get-OwnerLensReportArray -Report $Report -Path "azure.roleAssignments"
  $resourceDependencies = Get-OwnerLensReportArray -Report $Report -Path "azure.resourceDependencies"
  $coAssignedRoleCandidates = Get-OwnerLensReportArray -Report $Report -Path "azure.coAssignedRoleCandidates"
  $rbacScopeActivityCallers = Get-OwnerLensReportArray -Report $Report -Path "azure.rbacScopeActivityCallers"
  $storageAccountsWithRbac = Get-OwnerLensReportArray -Report $Report -Path "azure.storageAccountsWithRbac"
  $blobReadCallers = Get-OwnerLensReportArray -Report $Report -Path "azure.blobReadCallers"
  $ownerTagConfiguration = Get-OwnerLensReportValue -Report $Report -Path "meta.ownerTagConfiguration"
  $ownerTagNames = @($ownerTagConfiguration.userOwnerTagNames) +
    @($ownerTagConfiguration.groupOwnerTagNames) +
    @($ownerTagConfiguration.tagOwnerTagNames)
  if ($ownerTagNames.Count -eq 0) {
    $ownerTagNames = @(Get-OwnerLensDefaultAzureOwnerTagNames)
  }

  if ($roleAssignments.Count -eq 0) {
    Add-RichTreeNode $root "no Azure RBAC role assignments found for this service principal"
    return $root
  }

  foreach ($scopeGroup in @($roleAssignments | Group-Object scope | Sort-Object Name)) {
    $scope = [string]$scopeGroup.Name
    $assignments = @($scopeGroup.Group | Sort-Object subscriptionName, roleDefinitionName)
    $firstAssignment = $assignments | Select-Object -First 1
    $dependency = @($resourceDependencies | Where-Object {
        ([string]$_.resourceId).Equals($scope, [System.StringComparison]::OrdinalIgnoreCase)
      } | Select-Object -First 1)

    $resourceNode = Add-RichTreeNode $root (Get-OwnerLensResourceLabel -Dependency $dependency -Assignment $firstAssignment) -PassThru
    Add-RichTreeNode $resourceNode "scope: $(Format-OwnerLensAzureResourceId -ResourceId $scope)"

    $rolesNode = Add-RichTreeNode $resourceNode "roles for inspected SP ($($assignments.Count))" -PassThru
    foreach ($assignment in $assignments) {
      $roleLabel = Get-OwnerLensDisplayValue -Value $assignment.roleDefinitionName -Fallback "unknown role"
      $subscriptionName = Get-OwnerLensDisplayValue -Value $assignment.subscriptionName
      if (-not [string]::IsNullOrWhiteSpace($subscriptionName)) {
        $roleLabel = "$roleLabel (subscription=$subscriptionName)"
      }

      Add-RichTreeNode $rolesNode $roleLabel
    }

    Add-OwnerLensTagNodes -Tree $resourceNode -Tags $dependency.tags -OwnerTagNames $ownerTagNames

    $coAssignedPrincipals = @($coAssignedRoleCandidates | Where-Object {
        ([string]$_.scope).Equals($scope, [System.StringComparison]::OrdinalIgnoreCase)
      } | Sort-Object principalDisplayName, principalName, roleDefinitionName)
    if ($coAssignedPrincipals.Count -gt 0) {
      $principalGroups = @($coAssignedPrincipals | Group-Object {
          $principalId = Get-OwnerLensDisplayValue -Value $_.principalId
          if (-not [string]::IsNullOrWhiteSpace($principalId)) {
            return "id:$principalId"
          }

          $principalName = Get-OwnerLensDisplayValue -Value $_.principalName
          if (-not [string]::IsNullOrWhiteSpace($principalName)) {
            return "upn:$principalName"
          }

          return "display:$($_.principalDisplayName)"
        } | Sort-Object {
          $firstPrincipal = $_.Group | Select-Object -First 1
          Get-OwnerLensDisplayValue -Value $firstPrincipal.principalDisplayName -Fallback (Get-OwnerLensDisplayValue -Value $firstPrincipal.principalName -Fallback $firstPrincipal.principalId)
        })
      $coAssignedCount = Format-OwnerLensRichLink `
        -Text ([string]$principalGroups.Count) `
        -Uri (ConvertTo-OwnerLensAzurePortalIamUri -Scope $scope)
      $coAssignedNode = Add-RichTreeNode $resourceNode "other principals on same scope ($coAssignedCount)" -PassThru
      foreach ($principalGroup in $principalGroups) {
        $principal = $principalGroup.Group | Select-Object -First 1
        $principalLabel = Get-OwnerLensDisplayValue -Value $principal.principalDisplayName -Fallback (Get-OwnerLensDisplayValue -Value $principal.principalName -Fallback $principal.principalId)
        $principalType = Get-OwnerLensDisplayValue -Value $principal.principalType -Fallback "Principal"
        $principalId = Get-OwnerLensDisplayValue -Value $principal.principalId -Fallback "unknown id"
        $principalUpn = Get-OwnerLensDisplayValue -Value $principal.principalName -Fallback "unknown upn"
        $hasDataAccess = [bool](@($principalGroup.Group | Where-Object {
              [bool]$_.isStorageDataReadRole
            }).Count -gt 0)
        $principalText = Format-OwnerLensPrincipalLabel `
          -Text (Get-OwnerLensPrincipalDisplayText -Label $principalLabel -PrincipalType $principalType -PrincipalId $principalId -PrincipalUpn $principalUpn) `
          -PrincipalType $principalType `
          -HasDataAccess $hasDataAccess
        $principalNode = Add-RichTreeNode $coAssignedNode $principalText -PassThru
        $principalRoles = @($principalGroup.Group | Sort-Object roleDefinitionName, subscriptionName | ForEach-Object {
            Get-OwnerLensDisplayValue -Value $_.roleDefinitionName -Fallback "unknown role"
          } | Sort-Object -Unique)
        foreach ($roleName in $principalRoles) {
          Add-RichTreeNode $principalNode $roleName
        }
      }
    }

    $activityCallers = @($rbacScopeActivityCallers | Where-Object {
        @($_.rbacScopes) -contains $scope
      } | Sort-Object @{ Expression = "eventCount"; Descending = $true }, callerName, caller)
    if ($activityCallers.Count -gt 0) {
      $activityNode = Add-RichTreeNode $resourceNode "recent activity callers ($($activityCallers.Count))" -PassThru
      foreach ($caller in $activityCallers) {
        $callerLabel = Get-OwnerLensDisplayValue -Value $caller.callerName -Fallback (Get-OwnerLensDisplayValue -Value $caller.caller -Fallback $caller.callerKey)
        $callerType = Get-OwnerLensActivityCallerPrincipalType -Caller $caller
        $callerId = Get-OwnerLensDisplayValue -Value $caller.callerObjectId -Fallback $caller.callerAppId
        $highlightCaller = [bool]$caller.matchesInspectedServicePrincipal -or
          ([string]$callerType).Equals("User", [System.StringComparison]::OrdinalIgnoreCase)
        $callerText = Format-OwnerLensPrincipalLabel `
          -Text (Get-OwnerLensPrincipalDisplayText -Label $callerLabel -PrincipalType $callerType -PrincipalId $callerId -PrincipalUpn ([string]$caller.caller)) `
          -PrincipalType $callerType `
          -HasDataAccess $highlightCaller
        Add-RichTreeNode $activityNode "$callerText (events=$($caller.eventCount), lastSeen=$($caller.lastSeen), inspectedSP=$($caller.matchesInspectedServicePrincipal))"
      }
    }

    $storageAccounts = @($storageAccountsWithRbac | Where-Object {
        Test-OwnerLensResourceUnderScope -ResourceId ([string]$_.resourceId) -Scope $scope
      } | Sort-Object name)
    if ($storageAccounts.Count -gt 0) {
      $storageNode = Add-RichTreeNode $resourceNode "storage accounts with data-plane read ($($storageAccounts.Count))" -PassThru
      foreach ($storageAccount in $storageAccounts) {
        $readServices = @($storageAccount.dataPlaneReadServices) -join ","
        $verificationStatus = Get-OwnerLensDisplayValue -Value $storageAccount.dataAccessVerificationStatus -Fallback "Unknown"
        $storageAccountNode = Add-RichTreeNode $storageNode "$(Format-OwnerLensRichLink -Text ([string]$storageAccount.name) -Uri (ConvertTo-OwnerLensAzurePortalResourceUri -ResourceId ([string]$storageAccount.resourceId))) (rg=$($storageAccount.resourceGroup), location=$($storageAccount.location), read=$readServices, diagnostics=$verificationStatus)" -PassThru
        Add-RichTreeNode $storageAccountNode (Format-OwnerLensStorageDiagnosticStatus -StorageAccount $storageAccount)

        $blobParticipants = @($blobReadCallers | Where-Object {
            @($_.storageAccounts) -contains [string]$storageAccount.name
          } | Sort-Object @{ Expression = "blobAccessCount"; Descending = $true }, requesterUpn, requesterAppId)
        if ($blobParticipants.Count -gt 0) {
          $participantsNode = Add-RichTreeNode $storageAccountNode "blob data-plane participants ($($blobParticipants.Count))" -PassThru
          foreach ($participant in $blobParticipants) {
            $participantLabel = Get-OwnerLensDisplayValue -Value $participant.requesterUpn -Fallback (Get-OwnerLensDisplayValue -Value $participant.requesterAppId -Fallback $participant.requesterKey)
            Add-RichTreeNode $participantsNode "$participantLabel ($($participant.requesterType), reads=$($participant.blobReadCount), publishes=$($participant.blobPublishCount), inspectedSP=$($participant.matchesInspectedServicePrincipal))"
          }
        }
      }
    }
  }

  return $root
}
