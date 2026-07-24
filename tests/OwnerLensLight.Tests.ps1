BeforeAll {
  Get-ChildItem -Path (Join-Path $PSScriptRoot "../ownerlens/Private") -Filter "*.ps1" -File |
    ForEach-Object { . $_.FullName }
  . (Join-Path $PSScriptRoot "../ownerlens/Public/Invoke-OwnerLensLight.ps1")
}

Describe "OwnerLens Light Azure helper logic" {
  It "matches activity logs by service principal object id, app id, or display name" {
    $servicePrincipal = [pscustomobject]@{
      objectId = "sp-object-id"
      appId = "app-client-id"
      displayName = "Automation API"
    }

    (Test-ActivityLogMatchesServicePrincipal `
      -ServicePrincipal $servicePrincipal `
      -Log ([pscustomobject]@{ callerObjectId = "SP-OBJECT-ID" })) | Should -BeTrue

    (Test-ActivityLogMatchesServicePrincipal `
      -ServicePrincipal $servicePrincipal `
      -Log ([pscustomobject]@{ callerAppId = "APP-CLIENT-ID" })) | Should -BeTrue

    (Test-ActivityLogMatchesServicePrincipal `
      -ServicePrincipal $servicePrincipal `
      -Log ([pscustomobject]@{ callerName = "Automation API" })) | Should -BeTrue

    (Test-ActivityLogMatchesServicePrincipal `
      -ServicePrincipal $servicePrincipal `
      -Log ([pscustomobject]@{ callerObjectId = "other" })) | Should -BeFalse
  }

  It "classifies Azure scopes" {
    (Get-AzureScopeParts -Scope "/subscriptions/sub-1").scopeType | Should -Be "Subscription"

    $resourceGroupScope = Get-AzureScopeParts -Scope "/subscriptions/sub-1/resourceGroups/rg-1"
    $resourceGroupScope.scopeType | Should -Be "ResourceGroup"
    $resourceGroupScope.resourceGroup | Should -Be "rg-1"

    $resourceScope = Get-AzureScopeParts -Scope "/subscriptions/sub-1/resourceGroups/rg-1/providers/Microsoft.Web/sites/app-1"
    $resourceScope.scopeType | Should -Be "Resource"
    $resourceScope.resourceId | Should -Be "/subscriptions/sub-1/resourceGroups/rg-1/providers/Microsoft.Web/sites/app-1"
  }

  It "matches activity logs under assigned Azure RBAC scopes" {
    $subscriptionLog = [pscustomobject]@{
      resourceId = "/subscriptions/sub-1/resourceGroups/rg-1/providers/Microsoft.Web/sites/app-1"
      authorizationScope = ""
    }

    (Test-AzureActivityLogMatchesScope `
      -Log $subscriptionLog `
      -Scope "/subscriptions/sub-1") | Should -BeTrue

    (Test-AzureActivityLogMatchesScope `
      -Log $subscriptionLog `
      -Scope "/subscriptions/sub-1/resourceGroups/rg-1") | Should -BeTrue

    (Test-AzureActivityLogMatchesScope `
      -Log $subscriptionLog `
      -Scope "/subscriptions/sub-1/resourceGroups/rg-2") | Should -BeFalse

    $authorizationLog = [pscustomobject]@{
      resourceId = ""
      authorizationScope = "/subscriptions/sub-1/resourceGroups/rg-1/providers/Microsoft.KeyVault/vaults/kv-1/secrets/s1"
    }

    (Test-AzureActivityLogMatchesScope `
      -Log $authorizationLog `
      -Scope "/subscriptions/sub-1/resourceGroups/rg-1/providers/Microsoft.KeyVault/vaults/kv-1") | Should -BeTrue
  }

  It "summarizes RBAC scope activity callers" {
    $callers = @(Get-AzureRbacScopeActivityCallers -ActivityEvidence @(
        [pscustomobject]@{
          caller = "user@example.com"
          callerObjectId = "user-1"
          callerAppId = ""
          callerName = "User One"
          callerTenantId = "tenant-1"
          eventTimestamp = "2024-01-01T00:00:00Z"
          subscriptionName = "Sub One"
          rbacScope = "/subscriptions/sub-1/resourceGroups/rg-1"
          resourceId = "/subscriptions/sub-1/resourceGroups/rg-1/providers/Microsoft.Web/sites/app-1"
          operationNameValue = "Microsoft.Web/sites/write"
          matchesInspectedServicePrincipal = $false
        },
        [pscustomobject]@{
          caller = "user@example.com"
          callerObjectId = "user-1"
          callerAppId = ""
          callerName = "User One"
          callerTenantId = "tenant-1"
          eventTimestamp = "2024-01-02T00:00:00Z"
          subscriptionName = "Sub One"
          rbacScope = "/subscriptions/sub-1/resourceGroups/rg-1"
          resourceId = "/subscriptions/sub-1/resourceGroups/rg-1/providers/Microsoft.Web/sites/app-2"
          operationNameValue = "Microsoft.Web/sites/read"
          matchesInspectedServicePrincipal = $false
        }
      ))

    $callers | Should -HaveCount 1
    $callers[0].callerKey | Should -Be "object:user-1"
    $callers[0].eventCount | Should -Be 2
    $callers[0].firstSeen | Should -Be "2024-01-01T00:00:00Z"
    $callers[0].lastSeen | Should -Be "2024-01-02T00:00:00Z"
    $callers[0].resourceIds | Should -HaveCount 2
  }

  It "finds storage accounts covered by Azure RBAC scopes" {
    $resources = @(
      [pscustomobject]@{
        Name = "stsub"
        ResourceId = "/subscriptions/sub-1/resourceGroups/rg-1/providers/Microsoft.Storage/storageAccounts/stsub"
        ResourceGroupName = "rg-1"
        ResourceType = "Microsoft.Storage/storageAccounts"
      },
      [pscustomobject]@{
        Name = "app1"
        ResourceId = "/subscriptions/sub-1/resourceGroups/rg-1/providers/Microsoft.Web/sites/app1"
        ResourceGroupName = "rg-1"
        ResourceType = "Microsoft.Web/sites"
      },
      [pscustomobject]@{
        Name = "stother"
        ResourceId = "/subscriptions/sub-1/resourceGroups/rg-2/providers/Microsoft.Storage/storageAccounts/stother"
        ResourceGroupName = "rg-2"
        ResourceType = "Microsoft.Storage/storageAccounts"
      }
    )

    @(Get-AzureStorageAccountsForScope `
      -Scope "/subscriptions/sub-1/resourceGroups/rg-1" `
      -Resources $resources).Name | Should -Be @("stsub")

    @(Get-AzureStorageAccountsForScope `
      -Scope "/subscriptions/sub-1/resourceGroups/rg-1/providers/Microsoft.Storage/storageAccounts/stsub/blobServices/default/containers/c1" `
      -Resources $resources).Name | Should -Be @("stsub")
  }

  It "summarizes blob data-plane participants" {
    $callers = @(Get-StorageBlobReadCallers -BlobReadEvidence @(
        [pscustomobject]@{
          eventTimestamp = "2024-01-01T00:00:00Z"
          storageAccountName = "st1"
          operationName = "GetBlob"
          accessDirection = "Read"
          requesterObjectId = "user-1"
          requesterAppId = ""
          requesterTenantId = "tenant-1"
          requesterUpn = "user@example.com"
          requesterType = "User"
          authenticationType = "OAuth"
          callerIpAddress = "10.0.0.1"
          userAgentHeader = "azcopy"
          uri = "https://st1.blob.core.windows.net/c/a.txt"
          matchesInspectedServicePrincipal = $false
        },
        [pscustomobject]@{
          eventTimestamp = "2024-01-02T00:00:00Z"
          storageAccountName = "st1"
          operationName = "GetBlob"
          accessDirection = "Read"
          requesterObjectId = "user-1"
          requesterAppId = ""
          requesterTenantId = "tenant-1"
          requesterUpn = "user@example.com"
          requesterType = "User"
          authenticationType = "OAuth"
          callerIpAddress = "10.0.0.2"
          userAgentHeader = "azcopy"
          uri = "https://st1.blob.core.windows.net/c/b.txt"
          matchesInspectedServicePrincipal = $false
        }
      ))

    $callers | Should -HaveCount 1
    $callers[0].requesterKey | Should -Be "object:user-1|upn:user@example.com"
    $callers[0].readCount | Should -Be 2
    $callers[0].blobAccessCount | Should -Be 2
    $callers[0].blobReadCount | Should -Be 2
    $callers[0].blobPublishCount | Should -Be 0
    $callers[0].firstSeen | Should -Be "2024-01-01T00:00:00Z"
    $callers[0].lastSeen | Should -Be "2024-01-02T00:00:00Z"
    $callers[0].callerIpAddresses | Should -HaveCount 2
    $callers[0].sampleUris | Should -HaveCount 2
  }

  It "tracks blob publishers and readers with both user and service principal identifiers" {
    (Get-StorageBlobAccessDirection -OperationName "PutBlockList") | Should -Be "Publish"
    (Get-StorageBlobAccessDirection -OperationName "GetBlob") | Should -Be "Read"

    $servicePrincipal = [pscustomobject]@{
      objectId = "sp-object-1"
      appId = "agent-app-1"
    }

    $callers = @(Get-StorageBlobReadCallers -BlobReadEvidence @(
        [pscustomobject]@{
          eventTimestamp = "2024-01-01T00:00:00Z"
          storageAccountName = "st1"
          operationName = "PutBlockList"
          accessDirection = "Publish"
          requesterObjectId = "user-1"
          requesterAppId = "upload-client-app"
          requesterTenantId = "tenant-1"
          requesterUpn = "user@example.com"
          requesterType = "UserAndServicePrincipal"
          authenticationType = "OAuth"
          callerIpAddress = "10.0.0.1"
          userAgentHeader = "agent-uploader"
          uri = "https://st1.blob.core.windows.net/inbox/prompt.json"
          matchesInspectedServicePrincipal = $false
        },
        [pscustomobject]@{
          eventTimestamp = "2024-01-01T00:05:00Z"
          storageAccountName = "st1"
          operationName = "GetBlob"
          accessDirection = "Read"
          requesterObjectId = "sp-object-1"
          requesterAppId = "agent-app-1"
          requesterTenantId = "tenant-1"
          requesterUpn = ""
          requesterType = "ServicePrincipal"
          authenticationType = "OAuth"
          callerIpAddress = "10.0.0.2"
          userAgentHeader = "agent-runtime"
          uri = "https://st1.blob.core.windows.net/inbox/prompt.json"
          matchesInspectedServicePrincipal = (Test-StorageBlobRequesterMatchesServicePrincipal `
              -BlobAccess ([pscustomobject]@{ requesterObjectId = "sp-object-1"; requesterAppId = "agent-app-1" }) `
              -ServicePrincipal $servicePrincipal)
        }
      ))

    $callers | Should -HaveCount 2

    $publisher = $callers | Where-Object requesterUpn -eq "user@example.com"
    $publisher.requesterKey | Should -Be "object:user-1|app:upload-client-app|upn:user@example.com"
    $publisher.requesterType | Should -Be "UserAndServicePrincipal"
    $publisher.blobPublishCount | Should -Be 1
    $publisher.blobReadCount | Should -Be 0

    $reader = $callers | Where-Object requesterAppId -eq "agent-app-1"
    $reader.requesterType | Should -Be "ServicePrincipal"
    $reader.blobReadCount | Should -Be 1
    $reader.blobPublishCount | Should -Be 0
    $reader.matchesInspectedServicePrincipal | Should -BeTrue
  }
}

Describe "Invoke-OwnerLensLight pipeline input" {
  BeforeEach {
    Mock Import-Module {}
    Mock Get-Command { [pscustomobject]@{ Name = $Name } }
    Mock Get-MgContext { [pscustomobject]@{ TenantId = "tenant-1" } }
    Mock Get-AzContext { [pscustomobject]@{ Subscription = "sub-1" } }
    Mock Resolve-EnterpriseApplication {
      [pscustomobject]@{
        objectId = "object-$EnterpriseApplication"
        appId = "app-$EnterpriseApplication"
        displayName = "App $EnterpriseApplication"
        accountEnabled = $true
      }
    }
    Mock Get-GraphDependencies {
      [pscustomobject]@{
        owners = @()
        appRoleAssignments = @()
        oauth2PermissionGrants = @()
        memberOf = @()
        resourceServicePrincipals = @()
      }
    }
    Mock Get-AzureDependencies {
      [pscustomobject]@{
        requestedSubscriptions = @()
        subscriptions = @()
        roleAssignments = @()
        coAssignedRoleCandidates = @()
        resourceDependencies = @()
        activityEvidence = @()
        rbacScopeActivityEvidence = @()
        rbacScopeActivityCallers = @()
        storageAccountsWithRbac = @()
        blobReadEvidence = @()
        blobReadCallers = @()
        logAnalyticsWorkspaceId = ""
        maxBlobReadRecords = 5000
        activityStartTime = "2024-01-01T00:00:00.0000000Z"
      }
    }
    Mock Format-DependencyReport {}
  }

  It "processes each Enterprise Application supplied through the pipeline" {
    $reports = @("alpha", "beta" | Invoke-OwnerLensLight -SkipLogin -SkipActivityLogs)

    $reports | Should -HaveCount 2
    $reports.enterpriseApplication.displayName | Should -Be @("App alpha", "App beta")
    Should -Invoke Resolve-EnterpriseApplication -Exactly 2
  }
}

Describe "OwnerLens Light owner candidate table" {
  It "builds candidates with type, confidence, and evidence id" {
    $tags = [System.Collections.Generic.Dictionary[string, string]]::new()
    $tags["repoName"] = "super-learning-backend"
    $tags["costCenter"] = "cc-42"

    $report = [pscustomobject]@{
      enterpriseApplication = [pscustomobject]@{
        objectId = "sp-1"
      }
      graph = [pscustomobject]@{
        owners = @(
          [pscustomobject]@{
            objectId = "user-1"
            displayName = "Ada Lovelace"
            userPrincipalName = "ada@example.com"
            objectType = "#microsoft.graph.user"
          }
        )
        memberOf = @()
      }
      azure = [pscustomobject]@{
        coAssignedRoleCandidates = @(
          [pscustomobject]@{
            principalId = "group-1"
            principalDisplayName = "App Owners"
            principalType = "Group"
            roleDefinitionName = "Contributor"
            scope = "/subscriptions/sub-1/resourceGroups/rg-1"
          }
        )
        resourceDependencies = @(
          [pscustomobject]@{
            resourceId = "/subscriptions/sub-1/resourceGroups/rg-1/providers/Microsoft.Storage/storageAccounts/st1"
            tags = $tags
          }
        )
        activityEvidence = @()
      }
    }

    $candidates = @(Get-OwnerCandidates -Report $report)

    $candidates | Should -HaveCount 3
    $candidates[0].candidate | Should -Be "ada@example.com"
    $candidates[0].candidateType | Should -Be "User"
    $candidates[0].confidence | Should -Be "HIGH"
    $candidates[0].relationship | Should -Be "Direct"
    $candidates[0].signal | Should -Be "OWNER"
    $candidates[0].evidenceId | Should -Be "/servicePrincipals/sp-1/owners/user-1"
    ($candidates | Where-Object candidateType -eq "Tag").evidenceId | Should -Be "/subscriptions/sub-1/resourceGroups/rg-1/providers/Microsoft.Storage/storageAccounts/st1"
    ($candidates | Where-Object candidateType -eq "Tag").candidate | Should -Be "costCenter=cc-42"
    ($candidates | Where-Object candidateType -eq "Tag").relationship | Should -Be "Indirect"
    ($candidates | Where-Object candidateType -eq "Tag").signal | Should -Be "RBAC"
    ($candidates | Where-Object candidate -eq "repoName=super-learning-backend") | Should -HaveCount 0
  }

  It "uses configured tag names for user, group, and generic tag owner candidates" {
    $resourceTags = [System.Collections.Generic.Dictionary[string, string]]::new()
    $resourceTags["ownerMail"] = "owner@example.com"
    $resourceTags["ownerGroup"] = "Payments Owners"
    $resourceTags["billingCode"] = "cc-42"
    $resourceTags["repoName"] = "payments-worker"

    $report = [pscustomobject]@{
      enterpriseApplication = [pscustomobject]@{
        objectId = "sp-1"
        tags = @("ownerMail=direct-owner@example.com", "repoName=direct-repo")
      }
      graph = [pscustomobject]@{
        owners = @()
        memberOf = @()
      }
      azure = [pscustomobject]@{
        coAssignedRoleCandidates = @()
        resourceDependencies = @(
          [pscustomobject]@{
            resourceId = "/subscriptions/sub-1/resourceGroups/rg-1/providers/Microsoft.Web/sites/app-1"
            tags = $resourceTags
          }
        )
        activityEvidence = @()
      }
    }

    $candidates = @(Get-OwnerCandidates `
        -Report $report `
        -UserOwnerTagNames @("ownerMail") `
        -GroupOwnerTagNames @("ownerGroup") `
        -TagOwnerTagNames @("billingCode"))

    $candidates | Where-Object {
      $_.candidate -eq "direct-owner@example.com" -and
      $_.candidateType -eq "User" -and
      $_.relationship -eq "Direct" -and
      $_.signal -eq "TAG"
    } | Should -HaveCount 1

    $candidates | Where-Object {
      $_.candidate -eq "owner@example.com" -and
      $_.candidateType -eq "User" -and
      $_.relationship -eq "Indirect" -and
      $_.signal -eq "RBAC"
    } | Should -HaveCount 1

    $candidates | Where-Object {
      $_.candidate -eq "Payments Owners" -and
      $_.candidateType -eq "Group" -and
      $_.relationship -eq "Indirect" -and
      $_.signal -eq "RBAC"
    } | Should -HaveCount 1

    $candidates | Where-Object {
      $_.candidate -eq "billingCode=cc-42" -and
      $_.candidateType -eq "Tag" -and
      $_.relationship -eq "Indirect" -and
      $_.signal -eq "RBAC"
    } | Should -HaveCount 1

    $candidates | Where-Object { $_.candidate -like "repoName=*" } | Should -HaveCount 0
  }

  It "returns a not-found evidence row when no candidate evidence exists" {
    $report = [pscustomobject]@{
      enterpriseApplication = [pscustomobject]@{
        objectId = "sp-1"
      }
      graph = [pscustomobject]@{
        owners = @()
        memberOf = @()
      }
      azure = [pscustomobject]@{
        coAssignedRoleCandidates = @()
        resourceDependencies = @()
        activityEvidence = @()
      }
    }

    $candidates = @(Get-OwnerCandidates -Report $report)

    $candidates | Should -HaveCount 1
    $candidates[0].candidateType | Should -Be "NotFound"
    $candidates[0].confidence | Should -Be "LOW"
    $candidates[0].relationship | Should -Be "None"
    $candidates[0].signal | Should -Be "NONE"
    $candidates[0].evidenceId | Should -Be "not-found"
  }

  It "formats the candidate output as TSV with relationship and signal, without evidence type" {
    $table = Format-OwnerCandidateTable -Candidates @(
      [pscustomobject]@{
        candidate = "repoName=super-learning-backend"
        candidateType = "Tag"
        confidence = "MED"
        relationship = "Indirect"
        signal = "RBAC"
        evidenceId = "/subscriptions/sub-1/resourceGroups/rg-1/providers/Microsoft.Storage/storageAccounts/st1"
      }
    )

    $lines = @($table -split "`r?`n")

    $lines | Should -HaveCount 2
    $lines[0] | Should -Be "candidate`ttype`tconfidence`trelationship`tsignal`tevidenceId"
    $lines[1] | Should -Be "repoName=super-learning-backend`tTag`tMED`tIndirect`tRBAC`t/subscriptions/sub-1/resourceGroups/rg-1/providers/Microsoft.Storage/storageAccounts/st1"
    $table | Should -Not -Match "evidenceType"
  }

  It "prefers principal name for user candidates" {
    $report = [pscustomobject]@{
      enterpriseApplication = [pscustomobject]@{
        objectId = "sp-1"
      }
      graph = [pscustomobject]@{
        owners = @()
        memberOf = @()
      }
      azure = [pscustomobject]@{
        coAssignedRoleCandidates = @(
          [pscustomobject]@{
            principalId = "user-1"
            principalName = "owner@example.com"
            principalDisplayName = "Owner Person"
            principalType = "User"
            roleDefinitionName = "Contributor"
            scope = "/subscriptions/sub-1/resourceGroups/rg-1"
          }
        )
        resourceDependencies = @()
        activityEvidence = @()
      }
    }

    $candidates = @(Get-OwnerCandidates -Report $report)

    $candidates[0].candidate | Should -Be "owner@example.com"
    $candidates[0].candidateType | Should -Be "User"
  }

  It "does not promote unresolved RBAC principals to owner candidates" {
    $report = [pscustomobject]@{
      enterpriseApplication = [pscustomobject]@{
        objectId = "sp-1"
      }
      graph = [pscustomobject]@{
        owners = @()
        memberOf = @()
      }
      azure = [pscustomobject]@{
        coAssignedRoleCandidates = @(
          [pscustomobject]@{
            principalId = "31b109c6-6aa2-4cba-84c6-879bb3d8656e"
            principalName = ""
            principalDisplayName = ""
            principalType = ""
            roleDefinitionName = "Reader"
            scope = "/subscriptions/sub-1/resourceGroups/rg-1/providers/Microsoft.Storage/storageAccounts/st1"
          }
        )
        resourceDependencies = @()
        activityEvidence = @()
      }
    }

    $candidates = @(Get-OwnerCandidates -Report $report)

    $candidates | Should -HaveCount 1
    $candidates[0].candidateType | Should -Be "NotFound"
    $candidates[0].evidenceId | Should -Be "not-found"
  }
}

Describe "OwnerLens Light owner candidate integration" {
  BeforeEach {
    Mock Import-Module {}
    Mock Get-Command { [pscustomobject]@{ Name = $Name } }
    Mock Get-MgContext { [pscustomobject]@{ TenantId = "tenant-1" } }
    Mock Get-AzContext { [pscustomobject]@{ Subscription = @{ Id = "sub-1" } } }
    Mock Format-DependencyReport {}

    Mock Resolve-EnterpriseApplication {
      [pscustomobject]@{
        objectId = "sp-1"
        applicationObjectId = "app-object-1"
        appId = "app-client-1"
        displayName = "Payments Worker"
        accountEnabled = $true
        tags = @("owner=platform-from-enterprise-app")
      }
    }

    Mock Get-GraphDependencies {
      [pscustomobject]@{
        owners = @(
          [pscustomobject]@{
            objectId = "sp-user-owner-1"
            displayName = "Service Principal User Owner"
            userPrincipalName = "sp.user.owner@example.com"
            mail = "sp.user.owner@example.com"
            objectType = "#microsoft.graph.user"
            ownerSource = "ServicePrincipal"
          },
          [pscustomobject]@{
            objectId = "app-user-owner-1"
            displayName = "Application User Owner"
            userPrincipalName = "app.user.owner@example.com"
            mail = "app.user.owner@example.com"
            objectType = "#microsoft.graph.user"
            ownerSource = "Application"
          }
        )
        appRoleAssignments = @()
        oauth2PermissionGrants = @()
        memberOf = @(
          [pscustomobject]@{
            objectId = "member-group-1"
            displayName = "Payments Operators"
            objectType = "#microsoft.graph.group"
          }
        )
        resourceServicePrincipals = @()
      }
    }

    $resourceTags = [System.Collections.Generic.Dictionary[string, string]]::new()
    $resourceTags["owner"] = "platform-team"
    $resourceTags["repoName"] = "payments-worker"

    Mock Get-AzureDependencies {
      [pscustomobject]@{
        requestedSubscriptions = @("sub-1")
        subscriptions = @()
        roleAssignments = @()
        coAssignedRoleCandidates = @(
          [pscustomobject]@{
            principalId = "rbac-group-1"
            principalDisplayName = "Payments Contributors"
            principalType = "Group"
            roleDefinitionName = "Contributor"
            scope = "/subscriptions/sub-1/resourceGroups/rg-payments"
          }
        )
        resourceDependencies = @(
          [pscustomobject]@{
            resourceId = "/subscriptions/sub-1/resourceGroups/rg-payments/providers/Microsoft.Web/sites/payments-worker"
            tags = $resourceTags
          }
        )
        activityEvidence = @()
        rbacScopeActivityEvidence = @()
        rbacScopeActivityCallers = @()
        storageAccountsWithRbac = @()
        blobReadEvidence = @()
        blobReadCallers = @()
        logAnalyticsWorkspaceId = ""
        maxBlobReadRecords = 5000
        activityStartTime = "2024-01-01T00:00:00.0000000Z"
      }
    }
  }

  It "finds service principal owner, application owner, direct tag, indirect tags, membership group, and RBAC group" {
    $report = Invoke-OwnerLensLight -EnterpriseApplication "Payments Worker" -SkipLogin -SkipActivityLogs

    $report.ownerCandidates | Where-Object {
      $_.candidate -eq "sp.user.owner@example.com" -and
      $_.candidateType -eq "User" -and
      $_.relationship -eq "Direct" -and
      $_.signal -eq "OWNER" -and
      $_.evidenceId -eq "/servicePrincipals/sp-1/owners/sp-user-owner-1"
    } | Should -HaveCount 1

    $report.ownerCandidates | Where-Object {
      $_.candidate -eq "app.user.owner@example.com" -and
      $_.candidateType -eq "User" -and
      $_.relationship -eq "Direct" -and
      $_.signal -eq "OWNER" -and
      $_.evidenceId -eq "/applications/app-object-1/owners/app-user-owner-1"
    } | Should -HaveCount 1

    $report.ownerCandidates | Where-Object {
      $_.candidate -eq "owner=platform-from-enterprise-app" -and
      $_.candidateType -eq "Tag" -and
      $_.relationship -eq "Direct" -and
      $_.signal -eq "TAG"
    } | Should -HaveCount 1

    $report.ownerCandidates | Where-Object {
      $_.candidate -eq "owner=platform-team" -and
      $_.candidateType -eq "Tag" -and
      $_.relationship -eq "Indirect" -and
      $_.signal -eq "RBAC"
    } | Should -HaveCount 1

    $report.ownerCandidates | Where-Object {
      $_.candidate -eq "Payments Operators" -and
      $_.candidateType -eq "Group" -and
      $_.relationship -eq "Indirect" -and
      $_.signal -eq "MEMBERSHIP"
    } | Should -HaveCount 1

    $report.ownerCandidates | Where-Object {
      $_.candidate -eq "Payments Contributors" -and
      $_.candidateType -eq "Group" -and
      $_.relationship -eq "Indirect" -and
      $_.signal -eq "RBAC"
    } | Should -HaveCount 1
  }
}

Describe "OwnerLens Light Microsoft Graph application owner discovery" {
  It "loads owners from the application object when applicationObjectId is available" {
    Mock Invoke-GraphPagedRequest {
      switch -Wildcard ($Uri) {
        "/v1.0/servicePrincipals/sp-1/owners*" {
          return @()
        }
        "/v1.0/applications/app-object-1/owners*" {
          return @(
            [pscustomobject]@{
              id = "app-user-owner-1"
              displayName = "Application User Owner"
              userPrincipalName = "app.user.owner@example.com"
              mail = "app.user.owner@example.com"
              "@odata.type" = "#microsoft.graph.user"
            }
          )
        }
        default {
          return @()
        }
      }
    }
    Mock Invoke-RestRequestWithRetry {}

    $dependencies = Get-GraphDependencies -ServicePrincipal ([pscustomobject]@{
        objectId = "sp-1"
        applicationObjectId = "app-object-1"
      })

    $dependencies.owners | Should -HaveCount 1
    $dependencies.owners[0].objectId | Should -Be "app-user-owner-1"
    $dependencies.owners[0].userPrincipalName | Should -Be "app.user.owner@example.com"
    $dependencies.owners[0].ownerSource | Should -Be "Application"

    Should -Invoke Invoke-GraphPagedRequest -ParameterFilter {
      $Uri -like "/v1.0/applications/app-object-1/owners*"
    } -Exactly 1
  }
}
