BeforeAll {
  . (Join-Path $PSScriptRoot "Support/Import-OwnerLensLiteTestFunctions.ps1")
}

Describe "OwnerLensLite Azure helper logic" {
  It "reports Azure collection stages and completed subscriptions" {
    $progressMessages = [System.Collections.Generic.List[string]]::new()
    Mock Get-AzSubscription {
      @([pscustomobject]@{ Id = "sub-1"; Name = "Sub One"; TenantId = "tenant-1"; State = "Enabled" })
    }
    Mock Get-AzContext { $null }
    Mock Set-AzContext {}
    Mock Get-AzureActivityDiagnosticSummary { @() }
    Mock Get-AzResource { @() }
    Mock Get-AzResourceGroup { @() }
    Mock Get-AzRoleAssignment { @() }

    Get-AzureDependencies `
      -ServicePrincipal ([pscustomobject]@{ objectId = "sp-1" }) `
      -SubscriptionIds "sub-1" `
      -SkipActivityLogs `
      -ProgressWriter { param($message) $progressMessages.Add($message) } | Out-Null

    $progressMessages | Should -Contain "Azure: selected 1 subscription(s) for collection."
    $progressMessages | Should -Contain "Azure [1/1] Sub One: starting collection."
    $progressMessages | Should -Contain "Azure [1/1] Sub One: completed."
    $progressMessages | Should -Contain "Azure: collection completed."
  }

  It "matches activity logs by service principal object id, app id, or display name" {
    $servicePrincipal = [pscustomobject]@{
      objectId    = "sp-object-id"
      appId       = "app-client-id"
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
      resourceId         = "/subscriptions/sub-1/resourceGroups/rg-1/providers/Microsoft.Web/sites/app-1"
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
      resourceId         = ""
      authorizationScope = "/subscriptions/sub-1/resourceGroups/rg-1/providers/Microsoft.KeyVault/vaults/kv-1/secrets/s1"
    }

    (Test-AzureActivityLogMatchesScope `
      -Log $authorizationLog `
      -Scope "/subscriptions/sub-1/resourceGroups/rg-1/providers/Microsoft.KeyVault/vaults/kv-1") | Should -BeTrue
  }

  It "summarizes RBAC scope activity callers" {
    $callers = @(Get-AzureRbacScopeActivityCallers -ActivityEvidence @(
        [pscustomobject]@{
          caller                           = "user@example.com"
          callerObjectId                   = "user-1"
          callerAppId                      = ""
          callerName                       = "User One"
          callerTenantId                   = "tenant-1"
          eventTimestamp                   = "2024-01-01T00:00:00Z"
          subscriptionName                 = "Sub One"
          rbacScope                        = "/subscriptions/sub-1/resourceGroups/rg-1"
          resourceId                       = "/subscriptions/sub-1/resourceGroups/rg-1/providers/Microsoft.Web/sites/app-1"
          operationNameValue               = "Microsoft.Web/sites/write"
          matchesInspectedServicePrincipal = $false
        },
        [pscustomobject]@{
          caller                           = "user@example.com"
          callerObjectId                   = "user-1"
          callerAppId                      = ""
          callerName                       = "User One"
          callerTenantId                   = "tenant-1"
          eventTimestamp                   = "2024-01-02T00:00:00Z"
          subscriptionName                 = "Sub One"
          rbacScope                        = "/subscriptions/sub-1/resourceGroups/rg-1"
          resourceId                       = "/subscriptions/sub-1/resourceGroups/rg-1/providers/Microsoft.Web/sites/app-2"
          operationNameValue               = "Microsoft.Web/sites/read"
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
        Name              = "stsub"
        ResourceId        = "/subscriptions/sub-1/resourceGroups/rg-1/providers/Microsoft.Storage/storageAccounts/stsub"
        ResourceGroupName = "rg-1"
        ResourceType      = "Microsoft.Storage/storageAccounts"
      },
      [pscustomobject]@{
        Name              = "app1"
        ResourceId        = "/subscriptions/sub-1/resourceGroups/rg-1/providers/Microsoft.Web/sites/app1"
        ResourceGroupName = "rg-1"
        ResourceType      = "Microsoft.Web/sites"
      },
      [pscustomobject]@{
        Name              = "stother"
        ResourceId        = "/subscriptions/sub-1/resourceGroups/rg-2/providers/Microsoft.Storage/storageAccounts/stother"
        ResourceGroupName = "rg-2"
        ResourceType      = "Microsoft.Storage/storageAccounts"
      }
    )

    @(Get-AzureStorageAccountsForScope `
        -Scope "/subscriptions/sub-1/resourceGroups/rg-1" `
        -Resources $resources).Name | Should -Be @("stsub")

    @(Get-AzureStorageAccountsForScope `
        -Scope "/subscriptions/sub-1/resourceGroups/rg-1/providers/Microsoft.Storage/storageAccounts/stsub/blobServices/default/containers/c1" `
        -Resources $resources).Name | Should -Be @("stsub")
  }

  It "identifies storage data-plane read roles" {
    @(Get-AzureStorageDataReadServices -RoleDefinitionName "Storage Blob Data Reader") | Should -Be @("Blob")
    @(Get-AzureStorageDataReadServices -RoleDefinitionName "Storage Table Data Contributor") | Should -Be @("Table")
    @(Get-AzureStorageDataReadServices -RoleDefinitionName "Storage Queue Data Message Processor") | Should -Be @("Queue")
    @(Get-AzureStorageDataReadServices -RoleDefinitionName "Storage Account Contributor") | Should -Be @()

    Test-AzureStorageDataReadRole -RoleDefinitionName "Reader" | Should -BeFalse
    Test-AzureStorageDataReadRole -RoleDefinitionName "Storage Blob Data Reader" | Should -BeTrue
  }

  It "detects storage diagnostic settings that can log data access" {
    $storageAccountResourceId = "/subscriptions/sub-1/resourceGroups/rg-1/providers/Microsoft.Storage/storageAccounts/st1"

    (Get-AzureStorageDiagnosticServiceResourceId `
      -StorageAccountResourceId $storageAccountResourceId `
      -Service "Blob") | Should -Be "$storageAccountResourceId/blobServices/default"

    Test-AzureStorageDiagnosticLogEnabled -DiagnosticSetting ([pscustomobject]@{
        Logs = @(
          [pscustomobject]@{ Category = "StorageRead"; Enabled = $true }
        )
      }) | Should -BeTrue

    Test-AzureStorageDiagnosticLogEnabled -DiagnosticSetting ([pscustomobject]@{
        Logs = @(
          [pscustomobject]@{ Category = "Storage Read"; Enabled = $true }
        )
      }) | Should -BeTrue

    Test-AzureStorageDiagnosticLogEnabled -DiagnosticSetting ([pscustomobject]@{
        EnabledLog = @(
          [pscustomobject]@{ Category = "StorageRead"; Enabled = $true }
        )
      }) | Should -BeTrue

    Test-AzureStorageDiagnosticLogEnabled -DiagnosticSetting ([pscustomobject]@{
        Logs = @(
          [pscustomobject]@{ CategoryGroup = "allLogs"; Enabled = $true }
        )
      }) | Should -BeTrue

    Test-AzureStorageDiagnosticLogEnabled -DiagnosticSetting ([pscustomobject]@{
        Logs = @(
          [pscustomobject]@{ Category = "Transaction"; Enabled = $true }
          [pscustomobject]@{ Category = "StorageRead"; Enabled = $false }
        )
      }) | Should -BeFalse
  }

  It "formats storage diagnostic status for configured and missing logs" {
    Format-OwnerLensStorageDiagnosticStatus -StorageAccount ([pscustomobject]@{
        diagnosticSettings = @(
          [pscustomobject]@{
            service                = "Blob"
            status                 = "LogAnalytics"
            dataAccessLogEnabled   = $true
            diagnosticSettingNames = @("send-blob-logs")
            workspaceIds           = @("/subscriptions/sub-1/resourceGroups/rg-log/providers/Microsoft.OperationalInsights/workspaces/law")
          }
        )
      }) | Should -Be (
      "[dim]Configured: Blob (status=LogAnalytics, settings=send-blob-logs, " +
      "workspaces=[link=https://portal.azure.com/#resource/subscriptions/sub-1/resourceGroups/rg-log/providers/Microsoft.OperationalInsights/workspaces/law]rg-log/workspaces/law[/link])[/]"
    )

    Format-OwnerLensStorageDiagnosticStatus -StorageAccount ([pscustomobject]@{
        diagnosticSettings = @(
          [pscustomobject]@{
            service                = "Blob"
            status                 = "NotConfigured"
            dataAccessLogEnabled   = $false
            diagnosticSettingNames = @()
            workspaceIds           = @()
          }
        )
      }) | Should -Be "[yellow]No diagnostic settings detected; not possible to detect data access based on logs to increase accuracy.[/]"
  }

  It "includes not configured storage diagnostic settings in table rows" {
    $rows = @(Get-OwnerLensStorageDiagnosticSettingRows -StorageAccounts @(
        [pscustomobject]@{
          resourceId            = "/subscriptions/sub-1/resourceGroups/rg-1/providers/Microsoft.Storage/storageAccounts/st1"
          name                  = "st1"
          dataPlaneReadServices = @("Blob")
          diagnosticSettings    = @()
        }
      ))

    $rows | Should -HaveCount 1
    $rows[0].storageAccountName | Should -Be "st1"
    $rows[0].service | Should -Be "Blob"
    $rows[0].status | Should -Be "[yellow]NotConfigured[/]"
    $rows[0].dataAccessLogEnabled | Should -BeFalse
    $rows[0].logAnalyticsEnabled | Should -BeFalse
  }

  It "formats storage diagnostic workspace ids as short portal links in table rows" {
    $rows = @(Get-OwnerLensStorageDiagnosticSettingRows -StorageAccounts @(
        [pscustomobject]@{
          resourceId         = "/subscriptions/sub-1/resourceGroups/rg-1/providers/Microsoft.Storage/storageAccounts/st1"
          name               = "st1"
          diagnosticSettings = @(
            [pscustomobject]@{
              service                = "Blob"
              status                 = "LogAnalytics"
              dataAccessLogEnabled   = $true
              logAnalyticsEnabled    = $true
              diagnosticSettingNames = @("send-blob-logs")
              workspaceIds           = @("/subscriptions/sub-1/resourceGroups/rg-log/providers/Microsoft.OperationalInsights/workspaces/law")
              resourceId             = "/subscriptions/sub-1/resourceGroups/rg-1/providers/Microsoft.Storage/storageAccounts/st1/blobServices/default"
            }
          )
        }
      ))

    $rows | Should -HaveCount 1
    $rows[0].workspaceIds | Should -Be (
      "[link=https://portal.azure.com/#resource/subscriptions/sub-1/resourceGroups/rg-log/providers/Microsoft.OperationalInsights/workspaces/law]" +
      "rg-log/workspaces/law[/link]"
    )
  }

  It "detects subscription Activity Log diagnostic settings to Log Analytics" {
    Test-AzureActivityDiagnosticLogEnabled -DiagnosticSetting ([pscustomobject]@{
        Logs = @(
          [pscustomobject]@{ Category = "Administrative"; Enabled = $true }
        )
      }) | Should -BeTrue

    Test-AzureActivityDiagnosticLogEnabled -DiagnosticSetting ([pscustomobject]@{
        Logs = @(
          [pscustomobject]@{ Category = "Administrative"; Enabled = $false }
        )
      }) | Should -BeFalse

    $rows = @(Get-OwnerLensActivityDiagnosticSettingRows -ActivityDiagnosticSettings @(
        [pscustomobject]@{
          subscriptionId               = "sub-1"
          subscriptionName             = "Sub One"
          resourceId                   = "/subscriptions/sub-1"
          status                       = "LogAnalytics"
          activityLogEnabled           = $true
          logAnalyticsEnabled          = $true
          diagnosticSettingNames       = @("send-activity")
          workspaceIds                 = @("/subscriptions/sub-1/resourceGroups/rg-log/providers/Microsoft.OperationalInsights/workspaces/law")
          storageAccountIds            = @()
          eventHubAuthorizationRuleIds = @()
        }
      ))

    $rows | Should -HaveCount 1
    $rows[0].subscriptionName | Should -Be "Sub One"
    $rows[0].status | Should -Be "LogAnalytics"
    $rows[0].activityLogEnabled | Should -BeTrue
    $rows[0].logAnalyticsEnabled | Should -BeTrue
    $rows[0].diagnosticSettingNames | Should -Be "send-activity"
    $rows[0].workspaceIds | Should -Be (
      "[link=https://portal.azure.com/#resource/subscriptions/sub-1/resourceGroups/rg-log/providers/Microsoft.OperationalInsights/workspaces/law]" +
      "rg-log/workspaces/law[/link]"
    )
  }

  It "builds an Azure RBAC relationship tree rooted at the inspected service principal" {
    $tags = [System.Collections.Generic.Dictionary[string, string]]::new()
    $tags["owner"] = "payments-team"

    $scope = "/subscriptions/sub-1/resourceGroups/rg-1/providers/Microsoft.Storage/storageAccounts/st1"
    $report = [pscustomobject]@{
      enterpriseApplication = [pscustomobject]@{
        objectId    = "sp-1"
        appId       = "app-1"
        displayName = "Payments Worker"
      }
      meta                  = [pscustomobject]@{
        ownerTagConfiguration = [pscustomobject]@{
          userOwnerTagNames  = @("userOwner")
          groupOwnerTagNames = @("teamOwner")
          tagOwnerTagNames   = @("owner")
        }
      }
      azure                 = [pscustomobject]@{
        roleAssignments          = @(
          [pscustomobject]@{
            subscriptionName   = "Sub One"
            roleDefinitionName = "Storage Blob Data Reader"
            scope              = $scope
          }
        )
        resourceDependencies     = @(
          [pscustomobject]@{
            dependencyType = "Resource"
            resourceId     = $scope
            resourceName   = "st1"
            resourceGroup  = "rg-1"
            resourceType   = "Microsoft.Storage/storageAccounts"
            tags           = $tags
          }
        )
        coAssignedRoleCandidates = @(
          [pscustomobject]@{
            scope                 = $scope
            principalId           = "user-2"
            principalType         = "User"
            principalDisplayName  = "Payments Owner"
            principalName         = "payments.owner@example.com"
            roleDefinitionName    = "Contributor"
            isStorageDataReadRole = $false
          }
          [pscustomobject]@{
            scope                 = $scope
            principalId           = "user-2"
            principalType         = "User"
            principalDisplayName  = "Payments Owner"
            principalName         = "payments.owner@example.com"
            roleDefinitionName    = "Storage Blob Data Reader"
            isStorageDataReadRole = $true
          }
          [pscustomobject]@{
            scope                 = $scope
            principalId           = "sp-2"
            principalType         = "ServicePrincipal"
            principalDisplayName  = "Publisher Agent"
            principalName         = ""
            roleDefinitionName    = "Storage Queue Data Message Processor"
            isStorageDataReadRole = $true
          }
        )
        rbacScopeActivityCallers = @(
          [pscustomobject]@{
            callerKey                        = "object:user-1"
            caller                           = "owner@example.com"
            callerObjectId                   = "user-1"
            callerAppId                      = "azure-portal-client-app"
            callerName                       = "Owner User"
            eventCount                       = 3
            lastSeen                         = "2024-01-02T00:00:00Z"
            rbacScopes                       = @($scope)
            matchesInspectedServicePrincipal = $false
          },
          [pscustomobject]@{
            callerKey                        = "object:sp-1"
            caller                           = "app-client-1"
            callerObjectId                   = "sp-1"
            callerAppId                      = "app-client-1"
            callerName                       = "Payments Worker"
            eventCount                       = 4
            lastSeen                         = "2024-01-03T00:00:00Z"
            rbacScopes                       = @($scope)
            matchesInspectedServicePrincipal = $true
          }
        )
        storageAccountsWithRbac  = @(
          [pscustomobject]@{
            resourceId                    = $scope
            name                          = "st1"
            resourceGroup                 = "rg-1"
            location                      = "westeurope"
            dataPlaneReadServices         = @("Blob")
            dataPlaneReadRoleNames        = @("Storage Blob Data Reader")
            rbacScopes                    = @($scope)
            diagnosticLogEnabled          = $true
            diagnosticLogAnalyticsEnabled = $true
            dataAccessVerificationStatus  = "QueryableInLogAnalytics"
            dataAccessVerificationReason  = "Data-plane diagnostic logs are enabled to Log Analytics for every storage service covered by the inspected RBAC roles."
            diagnosticSettings            = @(
              [pscustomobject]@{
                service                = "Blob"
                resourceId             = "$scope/blobServices/default"
                status                 = "LogAnalytics"
                dataAccessLogEnabled   = $true
                logAnalyticsEnabled    = $true
                diagnosticSettingNames = @("send-blob-logs")
                workspaceIds           = @("/subscriptions/sub-1/resourceGroups/rg-log/providers/Microsoft.OperationalInsights/workspaces/law")
              }
            )
          }
        )
        blobReadCallers          = @(
          [pscustomobject]@{
            requesterKey                     = "app:app-1"
            requesterAppId                   = "app-1"
            requesterUpn                     = ""
            requesterType                    = "ServicePrincipal"
            blobReadCount                    = 2
            blobPublishCount                 = 1
            blobAccessCount                  = 3
            storageAccounts                  = @("st1")
            matchesInspectedServicePrincipal = $true
          }
        )
      }
    }

    $tree = New-OwnerLensAzureRbacTree -Report $report
    $treeOutput = Write-RichTree $tree -NoColor -PassThru

    $treeOutput | Should -Match "Service Principal: Payments Worker"
    $treeOutput | Should -Match "Resource: st1"
    $treeOutput | Should -Match "roles for inspected SP"
    $treeOutput | Should -Match "Storage Blob Data Reader"
    $treeOutput | Should -Match "other principals on same scope"
    $tree.Children[0].Children[3].Name | Should -Match (
      "other principals on same scope \(\[link=https://portal.azure.com/#resource/" +
      "subscriptions/sub-1/resourceGroups/rg-1/providers/Microsoft.Storage/storageAccounts/st1/users\]2\[/link\]\)"
    )
    $coAssignedPrincipalNames = @($tree.Children[0].Children[3].Children | ForEach-Object { $_.Name })
    $coAssignedPrincipalNames | Should -Contain "[dim green]Publisher Agent (ServicePrincipal, id=sp-2, upn=unknown upn)[/]"
    $coAssignedPrincipalNames | Should -Contain "[bold green]Payments Owner (User, id=user-2, upn=payments.owner@example.com)[/]"
    $treeOutput | Should -Match "Publisher Agent \(ServicePrincipal, id=sp-2, upn=unknown upn\)"
    $treeOutput | Should -Match "Payments Owner \(User, id=user-2, upn=payments.owner@example.com\)"
    ([regex]::Matches($treeOutput, "Payments Owner \(User, id=user-2, upn=payments.owner@example.com\)").Count) | Should -Be 1
    $treeOutput | Should -Match "Contributor"
    $treeOutput | Should -Match "Storage Blob Data Reader"
    $treeOutput | Should -Match "Storage Queue Data Message Processor"
    $treeOutput | Should -Match "recent activity callers"
    $treeOutput | Should -Match "Owner User \(User, id=user-1, upn=owner@example.com\)"
    $tree.Children[0].Children[4].Children[1].Name | Should -Match "\[bold green\]Owner User \(User, id=user-1, upn=owner@example.com\)\[/\]"
    $tree.Children[0].Children[4].Children[0].Name | Should -Match "\[dim green\]Payments Worker \(ServicePrincipal, id=sp-1, upn=app-client-1\)\[/\]"
    $treeOutput | Should -Match "storage accounts with data-plane read"
    $treeOutput | Should -Match "read=Blob"
    $treeOutput | Should -Match "diagnostics=QueryableInLogAnalytics"
    $treeOutput | Should -Match "Configured: Blob \(status=LogAnalytics, settings=send-blob-logs, workspaces=rg-log/workspaces/law\)"
    $treeOutput | Should -Match "blob data-plane participants"
    $treeOutput | Should -Match "owner=payments-team"
    $tree.Children[0].Children[2].Children[0].Name | Should -Be "[green]owner=payments-team[/]"

    $tree.Children[0].Name | Should -Be (
      "[blue]Resource: [link=https://portal.azure.com/#resource/subscriptions/sub-1/" +
      "resourceGroups/rg-1/providers/Microsoft.Storage/storageAccounts/st1]st1[/link] (Microsoft.Storage/storageAccounts, rg=rg-1)[/]"
    )
    $tree.Children[0].Children[0].Name | Should -Match (
      "\[link=https://portal.azure.com/#resource/subscriptions/sub-1/resourceGroups/rg-1/" +
      "providers/Microsoft.Storage/storageAccounts/st1\]/subscriptions/sub-1/resourceGroups/rg-1/providers/Microsoft.Storage/storageAccounts/st1\[/link\]"
    )
    $tree.Children[0].Children[5].Children[0].Children[0].Name | Should -Match (
      "\[link=https://portal.azure.com/#resource/subscriptions/sub-1/resourceGroups/rg-log/" +
      "providers/Microsoft.OperationalInsights/workspaces/law\]rg-log/workspaces/law\[/link\]"
    )

    $jsonReport = $report | ConvertTo-Json -Depth 40 | ConvertFrom-Json
    $jsonReport.enterpriseApplication.displayName | Should -Be "Payments Worker"
    $jsonReport.enterpriseApplication.objectId | Should -Be "sp-1"
    $jsonReport.enterpriseApplication.appId | Should -Be "app-1"
    $jsonReport.meta.ownerTagConfiguration.userOwnerTagNames | Should -Contain "userOwner"
    $jsonReport.meta.ownerTagConfiguration.groupOwnerTagNames | Should -Contain "teamOwner"
    $jsonReport.meta.ownerTagConfiguration.tagOwnerTagNames | Should -Contain "owner"

    $jsonReport.azure.roleAssignments[0].scope | Should -Be $scope
    $jsonReport.azure.roleAssignments[0].roleDefinitionName | Should -Be "Storage Blob Data Reader"
    $jsonReport.azure.resourceDependencies[0].resourceId | Should -Be $scope
    $jsonReport.azure.resourceDependencies[0].resourceName | Should -Be "st1"
    $jsonReport.azure.resourceDependencies[0].tags.owner | Should -Be "payments-team"

    $jsonReport.azure.coAssignedRoleCandidates | Should -HaveCount 3
    $jsonReport.azure.coAssignedRoleCandidates.roleDefinitionName | Should -Contain "Contributor"
    $jsonReport.azure.coAssignedRoleCandidates.roleDefinitionName | Should -Contain "Storage Queue Data Message Processor"

    $jsonReport.azure.rbacScopeActivityCallers | Should -HaveCount 2
    $jsonReport.azure.rbacScopeActivityCallers.callerName | Should -Contain "Owner User"
    $jsonReport.azure.rbacScopeActivityCallers.callerName | Should -Contain "Payments Worker"
    $jsonReport.azure.rbacScopeActivityCallers.rbacScopes | Should -Contain $scope
    $jsonReport.azure.rbacScopeActivityCallers.matchesInspectedServicePrincipal | Should -Contain $true

    $jsonReport.azure.storageAccountsWithRbac[0].resourceId | Should -Be $scope
    $jsonReport.azure.storageAccountsWithRbac[0].dataPlaneReadServices | Should -Contain "Blob"
    $jsonReport.azure.storageAccountsWithRbac[0].dataAccessVerificationStatus | Should -Be "QueryableInLogAnalytics"
    $jsonReport.azure.storageAccountsWithRbac[0].diagnosticSettings[0].workspaceIds | Should -Contain (
      "/subscriptions/sub-1/resourceGroups/rg-log/providers/" +
      "Microsoft.OperationalInsights/workspaces/law"
    )

    $jsonReport.azure.blobReadCallers[0].requesterAppId | Should -Be "app-1"
    $jsonReport.azure.blobReadCallers[0].requesterType | Should -Be "ServicePrincipal"
    $jsonReport.azure.blobReadCallers[0].blobReadCount | Should -Be 2
    $jsonReport.azure.blobReadCallers[0].blobPublishCount | Should -Be 1
    $jsonReport.azure.blobReadCallers[0].storageAccounts | Should -Contain "st1"
  }

  It "summarizes blob data-plane participants" {
    $callers = @(Get-StorageBlobReadCallers -BlobReadEvidence @(
        [pscustomobject]@{
          eventTimestamp                   = "2024-01-01T00:00:00Z"
          storageAccountName               = "st1"
          operationName                    = "GetBlob"
          accessDirection                  = "Read"
          requesterObjectId                = "user-1"
          requesterAppId                   = ""
          requesterTenantId                = "tenant-1"
          requesterUpn                     = "user@example.com"
          requesterType                    = "User"
          authenticationType               = "OAuth"
          callerIpAddress                  = "10.0.0.1"
          userAgentHeader                  = "azcopy"
          uri                              = "https://st1.blob.core.windows.net/c/a.txt"
          matchesInspectedServicePrincipal = $false
        },
        [pscustomobject]@{
          eventTimestamp                   = "2024-01-02T00:00:00Z"
          storageAccountName               = "st1"
          operationName                    = "GetBlob"
          accessDirection                  = "Read"
          requesterObjectId                = "user-1"
          requesterAppId                   = ""
          requesterTenantId                = "tenant-1"
          requesterUpn                     = "user@example.com"
          requesterType                    = "User"
          authenticationType               = "OAuth"
          callerIpAddress                  = "10.0.0.2"
          userAgentHeader                  = "azcopy"
          uri                              = "https://st1.blob.core.windows.net/c/b.txt"
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

  It "summarizes who read each blob with first and last access times" {
    $objects = @(Get-StorageBlobReadObjects -BlobReadEvidence @(
        [pscustomobject]@{
          eventTimestamp                   = "2024-01-01T00:00:00Z"
          storageAccountName               = "st1"
          storageAccountResourceId         = "/subscriptions/sub-1/resourceGroups/rg-1/providers/Microsoft.Storage/storageAccounts/st1"
          operationName                    = "GetBlob"
          accessDirection                  = "Read"
          requesterObjectId                = "user-1"
          requesterAppId                   = ""
          requesterTenantId                = "tenant-1"
          requesterUpn                     = "user@example.com"
          requesterType                    = "User"
          authenticationType               = "OAuth"
          callerIpAddress                  = "10.0.0.1"
          userAgentHeader                  = "azcopy"
          uri                              = "https://st1.blob.core.windows.net/c/a.txt"
          objectKey                        = "/blobServices/default/containers/c/blobs/a.txt"
          matchesInspectedServicePrincipal = $false
        },
        [pscustomobject]@{
          eventTimestamp                   = "2024-01-02T00:00:00Z"
          storageAccountName               = "st1"
          storageAccountResourceId         = "/subscriptions/sub-1/resourceGroups/rg-1/providers/Microsoft.Storage/storageAccounts/st1"
          operationName                    = "GetBlob"
          accessDirection                  = "Read"
          requesterObjectId                = "user-1"
          requesterAppId                   = ""
          requesterTenantId                = "tenant-1"
          requesterUpn                     = "user@example.com"
          requesterType                    = "User"
          authenticationType               = "OAuth"
          callerIpAddress                  = "10.0.0.2"
          userAgentHeader                  = "azcopy"
          uri                              = "https://st1.blob.core.windows.net/c/a.txt"
          objectKey                        = "/blobServices/default/containers/c/blobs/a.txt"
          matchesInspectedServicePrincipal = $false
        },
        [pscustomobject]@{
          eventTimestamp                   = "2024-01-03T00:00:00Z"
          storageAccountName               = "st1"
          operationName                    = "PutBlockList"
          accessDirection                  = "Publish"
          requesterObjectId                = "user-1"
          requesterUpn                     = "user@example.com"
          uri                              = "https://st1.blob.core.windows.net/c/a.txt"
          objectKey                        = "/blobServices/default/containers/c/blobs/a.txt"
          matchesInspectedServicePrincipal = $false
        },
        [pscustomobject]@{
          eventTimestamp                   = "2024-01-04T00:00:00Z"
          storageAccountName               = "st1"
          operationName                    = "GetBlob"
          accessDirection                  = "Read"
          requesterObjectId                = "sp-1"
          requesterAppId                   = "app-1"
          requesterTenantId                = "tenant-1"
          requesterUpn                     = ""
          requesterType                    = "ServicePrincipal"
          authenticationType               = "OAuth"
          callerIpAddress                  = "10.0.0.3"
          userAgentHeader                  = "agent"
          uri                              = "https://st1.blob.core.windows.net/c/a.txt"
          objectKey                        = "/blobServices/default/containers/c/blobs/a.txt"
          matchesInspectedServicePrincipal = $true
        }
      ))

    $objects | Should -HaveCount 2

    $userRead = $objects | Where-Object requesterUpn -EQ "user@example.com"
    $userRead.requesterBlobKey | Should -Be "object:user-1|upn:user@example.com|uri:https://st1.blob.core.windows.net/c/a.txt"
    $userRead.blobReadCount | Should -Be 2
    $userRead.firstReadAt | Should -Be "2024-01-01T00:00:00Z"
    $userRead.lastReadAt | Should -Be "2024-01-02T00:00:00Z"
    $userRead.callerIpAddresses | Should -HaveCount 2

    $servicePrincipalRead = $objects | Where-Object requesterAppId -EQ "app-1"
    $servicePrincipalRead.blobReadCount | Should -Be 1
    $servicePrincipalRead.matchesInspectedServicePrincipal | Should -BeTrue
  }

  It "tracks blob publishers and readers with both user and service principal identifiers" {
    (Get-StorageBlobAccessDirection -OperationName "PutBlockList") | Should -Be "Publish"
    (Get-StorageBlobAccessDirection -OperationName "GetBlob") | Should -Be "Read"

    $servicePrincipal = [pscustomobject]@{
      objectId = "sp-object-1"
      appId    = "agent-app-1"
    }

    $callers = @(Get-StorageBlobReadCallers -BlobReadEvidence @(
        [pscustomobject]@{
          eventTimestamp                   = "2024-01-01T00:00:00Z"
          storageAccountName               = "st1"
          operationName                    = "PutBlockList"
          accessDirection                  = "Publish"
          requesterObjectId                = "user-1"
          requesterAppId                   = "upload-client-app"
          requesterTenantId                = "tenant-1"
          requesterUpn                     = "user@example.com"
          requesterType                    = "UserAndServicePrincipal"
          authenticationType               = "OAuth"
          callerIpAddress                  = "10.0.0.1"
          userAgentHeader                  = "agent-uploader"
          uri                              = "https://st1.blob.core.windows.net/inbox/prompt.json"
          matchesInspectedServicePrincipal = $false
        },
        [pscustomobject]@{
          eventTimestamp                   = "2024-01-01T00:05:00Z"
          storageAccountName               = "st1"
          operationName                    = "GetBlob"
          accessDirection                  = "Read"
          requesterObjectId                = "sp-object-1"
          requesterAppId                   = "agent-app-1"
          requesterTenantId                = "tenant-1"
          requesterUpn                     = ""
          requesterType                    = "ServicePrincipal"
          authenticationType               = "OAuth"
          callerIpAddress                  = "10.0.0.2"
          userAgentHeader                  = "agent-runtime"
          uri                              = "https://st1.blob.core.windows.net/inbox/prompt.json"
          matchesInspectedServicePrincipal = (Test-StorageBlobRequesterMatchesServicePrincipal `
              -BlobAccess ([pscustomobject]@{ requesterObjectId = "sp-object-1"; requesterAppId = "agent-app-1" }) `
              -ServicePrincipal $servicePrincipal)
        }
      ))

    $callers | Should -HaveCount 2

    $publisher = $callers | Where-Object requesterUpn -EQ "user@example.com"
    $publisher.requesterKey | Should -Be "object:user-1|app:upload-client-app|upn:user@example.com"
    $publisher.requesterType | Should -Be "UserAndServicePrincipal"
    $publisher.blobPublishCount | Should -Be 1
    $publisher.blobReadCount | Should -Be 0

    $reader = $callers | Where-Object requesterAppId -EQ "agent-app-1"
    $reader.requesterType | Should -Be "ServicePrincipal"
    $reader.blobReadCount | Should -Be 1
    $reader.blobPublishCount | Should -Be 0
    $reader.matchesInspectedServicePrincipal | Should -BeTrue
  }

  It "carries SAS generator identity into blob participant and object summaries" {
    $sasEvidence = @(
      [pscustomobject]@{
        eventTimestamp                   = "2024-01-01T00:00:00Z"
        storageAccountName               = "st1"
        storageAccountResourceId         = "/subscriptions/sub-1/resourceGroups/rg-1/providers/Microsoft.Storage/storageAccounts/st1"
        operationName                    = "GetBlob"
        accessDirection                  = "Read"
        requesterObjectId                = ""
        requesterAppId                   = ""
        requesterTenantId                = ""
        requesterUpn                     = ""
        requesterType                    = "Unknown"
        authenticationType               = "SAS"
        sasGeneratorObjectId             = "sas-user-1"
        sasGeneratorAppId                = "portal-app"
        sasGeneratorTenantId             = "tenant-1"
        sasGeneratorUpn                  = "sas.owner@example.com"
        sasSignedIdentifier              = "readonly-policy"
        sasExpiryStatus                  = ""
        callerIpAddress                  = "10.0.0.4"
        userAgentHeader                  = "browser"
        uri                              = "https://st1.blob.core.windows.net/c/a.txt?skoid=sas-user-1&sktid=tenant-1&sp=r&se=2024-01-02T00%3A00%3A00Z"
        objectKey                        = "/blobServices/default/containers/c/blobs/a.txt"
        matchesInspectedServicePrincipal = $false
      }
    )

    $callers = @(Get-StorageBlobReadCallers -BlobReadEvidence $sasEvidence)
    $objects = @(Get-StorageBlobReadObjects -BlobReadEvidence $sasEvidence)

    $callers | Should -HaveCount 1
    $callers[0].requesterKey | Should -Be "unknown"
    $callers[0].sasAuthenticationCount | Should -Be 1
    $callers[0].sasGeneratorObjectIds | Should -Be @("sas-user-1")
    $callers[0].sasGeneratorAppIds | Should -Be @("portal-app")
    $callers[0].sasGeneratorUpns | Should -Be @("sas.owner@example.com")
    $callers[0].sasSignedIdentifiers | Should -Be @("readonly-policy")

    $objects | Should -HaveCount 1
    $objects[0].sasAuthenticationCount | Should -Be 1
    $objects[0].sasGeneratorObjectIds | Should -Be @("sas-user-1")
    $objects[0].sasGeneratorUpns | Should -Be @("sas.owner@example.com")
    $objects[0].sasSignedIdentifiers | Should -Be @("readonly-policy")
  }

  It "removes SAS signatures from persisted blob log URIs while keeping safe SAS metadata" {
    Mock Invoke-LogAnalyticsQuery {
      return @(
        [pscustomobject]@{
          TimeGenerated              = "2024-01-01T00:00:00Z"
          AccountName                = "st1"
          _ResourceId                = "/subscriptions/sub-1/resourceGroups/rg-1/providers/Microsoft.Storage/storageAccounts/st1"
          OperationName              = "GetBlob"
          StatusCode                 = "200"
          StatusText                 = "Success"
          AuthenticationType         = "SAS"
          AuthenticationHash         = "hash"
          SasExpiryStatus            = ""
          SasGeneratorObjectId       = "sas-user-1"
          SasGeneratorAppId          = "portal-app"
          SasGeneratorTenantId       = "tenant-1"
          SasGeneratorUpn            = "sas.owner@example.com"
          SasGeneratorEventTimestamp = "2024-01-01T00:00:00Z"
          SasExpiresOn               = "2024-01-02T00%3A00%3A00Z"
          SasSignedIdentifier        = "readonly-policy"
          SasSignedPermissions       = "r"
          RequesterObjectId          = ""
          RequesterAppId             = ""
          RequesterTenantId          = ""
          RequesterUpn               = ""
          CallerIpAddress            = "10.0.0.4"
          UserAgentHeader            = "browser"
          Uri                        = "https://st1.blob.core.windows.net/c/a.txt?skoid=sas-user-1&sktid=tenant-1&sp=r&si=readonly-policy&se=2024-01-02T00%3A00%3A00Z&sig=secret"
          ObjectKey                  = "/blobServices/default/containers/c/blobs/a.txt"
        }
      )
    }

    $evidence = @(Get-StorageBlobReadLogs `
        -WorkspaceId "workspace-1" `
        -StorageAccounts @([pscustomobject]@{
          Name       = "st1"
          ResourceId = "/subscriptions/sub-1/resourceGroups/rg-1/providers/Microsoft.Storage/storageAccounts/st1"
        }) `
        -StartTime ([datetime]"2024-01-01T00:00:00Z"))

    $evidence | Should -HaveCount 1
    $evidence[0].uri | Should -Be "https://st1.blob.core.windows.net/c/a.txt"
    $evidence[0].uri | Should -Not -Match "sig=|sp=|se=|skoid=|sktid="
    $evidence[0].sasGeneratorObjectId | Should -Be "sas-user-1"
    $evidence[0].sasGeneratorTenantId | Should -Be "tenant-1"
    $evidence[0].sasSignedPermissions | Should -Be "r"
    $evidence[0].sasSignedIdentifier | Should -Be "readonly-policy"
    $evidence[0].sasExpiresOn | Should -Be "2024-01-02T00%3A00%3A00Z"
  }
}

Describe "Invoke-OwnerLensLite pipeline input" {
  BeforeEach {
    Mock Import-Module {}
    Mock Get-Command { [pscustomobject]@{ Name = $Name } }
    Mock Get-MgContext { [pscustomobject]@{ TenantId = "tenant-1" } }
    Mock Get-AzContext { [pscustomobject]@{ Subscription = "sub-1" } }
    Mock Resolve-EnterpriseApplication {
      [pscustomobject]@{
        objectId       = "object-$EnterpriseApplication"
        appId          = "app-$EnterpriseApplication"
        displayName    = "App $EnterpriseApplication"
        accountEnabled = $true
      }
    }
    Mock Get-GraphDependencies {
      [pscustomobject]@{
        owners                    = @()
        appRoleAssignments        = @()
        oauth2PermissionGrants    = @()
        memberOf                  = @()
        resourceServicePrincipals = @()
        userSignIns               = @()
      }
    }
    Mock Get-AzureDependencies {
      [pscustomobject]@{
        requestedSubscriptions     = @()
        subscriptions              = @()
        roleAssignments            = @()
        coAssignedRoleCandidates   = @()
        resourceDependencies       = @()
        activityEvidence           = @()
        rbacScopeActivityEvidence  = @()
        rbacScopeActivityCallers   = @()
        activityDiagnosticSettings = @()
        storageAccountsWithRbac    = @()
        blobReadEvidence           = @()
        blobReadCallers            = @()
        blobReadObjects            = @()
        logAnalyticsWorkspaceId    = ""
        maxBlobReadRecords         = 5000
        activityStartTime          = "2024-01-01T00:00:00.0000000Z"
      }
    }
    Mock Format-DependencyReport {}
  }

  It "processes each Enterprise Application supplied through the pipeline" {
    $reports = @("alpha", "beta" | Invoke-OwnerLensLite -SkipLogin -SkipActivityLogs)

    $reports | Should -HaveCount 2
    $reports.enterpriseApplication.displayName | Should -Be @("App alpha", "App beta")
    Should -Invoke Resolve-EnterpriseApplication -Exactly 2
  }
}

Describe "OwnerLensLite owner candidate table" {
  It "builds candidates with type, confidence, and evidence id" {
    $tags = [System.Collections.Generic.Dictionary[string, string]]::new()
    $tags["repoName"] = "super-learning-backend"
    $tags["costCenter"] = "cc-42"

    $report = [pscustomobject]@{
      enterpriseApplication = [pscustomobject]@{
        objectId = "sp-1"
      }
      graph                 = [pscustomobject]@{
        owners   = @(
          [pscustomobject]@{
            objectId          = "user-1"
            displayName       = "Ada Lovelace"
            userPrincipalName = "ada@example.com"
            objectType        = "#microsoft.graph.user"
          }
        )
        memberOf = @()
      }
      azure                 = [pscustomobject]@{
        coAssignedRoleCandidates = @(
          [pscustomobject]@{
            principalId          = "group-1"
            principalDisplayName = "App Owners"
            principalType        = "Group"
            roleDefinitionName   = "Contributor"
            scope                = "/subscriptions/sub-1/resourceGroups/rg-1"
          }
        )
        resourceDependencies     = @(
          [pscustomobject]@{
            resourceId = "/subscriptions/sub-1/resourceGroups/rg-1/providers/Microsoft.Storage/storageAccounts/st1"
            tags       = $tags
          }
        )
        activityEvidence         = @()
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
    ($candidates | Where-Object candidateType -EQ "Tag").evidenceId | Should -Be "/subscriptions/sub-1/resourceGroups/rg-1/providers/Microsoft.Storage/storageAccounts/st1"
    ($candidates | Where-Object candidateType -EQ "Tag").candidate | Should -Be "costCenter=cc-42"
    ($candidates | Where-Object candidateType -EQ "Tag").relationship | Should -Be "Indirect"
    ($candidates | Where-Object candidateType -EQ "Tag").signal | Should -Be "RBAC"
    ($candidates | Where-Object candidate -EQ "repoName=super-learning-backend") | Should -HaveCount 0
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
        tags     = @("ownerMail=direct-owner@example.com", "repoName=direct-repo")
      }
      graph                 = [pscustomobject]@{
        owners   = @()
        memberOf = @()
      }
      azure                 = [pscustomobject]@{
        coAssignedRoleCandidates = @()
        resourceDependencies     = @(
          [pscustomobject]@{
            resourceId = "/subscriptions/sub-1/resourceGroups/rg-1/providers/Microsoft.Web/sites/app-1"
            tags       = $resourceTags
          }
        )
        activityEvidence         = @()
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
      graph                 = [pscustomobject]@{
        owners   = @()
        memberOf = @()
      }
      azure                 = [pscustomobject]@{
        coAssignedRoleCandidates = @()
        resourceDependencies     = @()
        activityEvidence         = @()
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
        candidate     = "repoName=super-learning-backend"
        candidateType = "Tag"
        confidence    = "MED"
        relationship  = "Indirect"
        signal        = "RBAC"
        evidenceId    = "/subscriptions/sub-1/resourceGroups/rg-1/providers/Microsoft.Storage/storageAccounts/st1"
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
      graph                 = [pscustomobject]@{
        owners   = @()
        memberOf = @()
      }
      azure                 = [pscustomobject]@{
        coAssignedRoleCandidates = @(
          [pscustomobject]@{
            principalId          = "user-1"
            principalName        = "owner@example.com"
            principalDisplayName = "Owner Person"
            principalType        = "User"
            roleDefinitionName   = "Contributor"
            scope                = "/subscriptions/sub-1/resourceGroups/rg-1"
          }
        )
        resourceDependencies     = @()
        activityEvidence         = @()
      }
    }

    $candidates = @(Get-OwnerCandidates -Report $report)

    $candidates[0].candidate | Should -Be "owner@example.com"
    $candidates[0].candidateType | Should -Be "User"
  }

  It "gives storage data-plane read user candidates at least medium confidence" {
    $scope = "/subscriptions/sub-1/resourceGroups/rg-1/providers/Microsoft.Storage/storageAccounts/st1"
    $report = [pscustomobject]@{
      enterpriseApplication = [pscustomobject]@{
        objectId = "sp-1"
      }
      graph                 = [pscustomobject]@{
        owners   = @()
        memberOf = @()
      }
      azure                 = [pscustomobject]@{
        coAssignedRoleCandidates = @(
          [pscustomobject]@{
            principalId           = "user-1"
            principalName         = "reader@example.com"
            principalDisplayName  = "Storage Reader"
            principalType         = "User"
            roleDefinitionName    = "Storage Blob Data Reader"
            isStorageDataReadRole = $true
            scope                 = $scope
          }
        )
        resourceDependencies     = @()
        activityEvidence         = @()
      }
    }

    $candidates = @(Get-OwnerCandidates -Report $report)

    $candidates | Should -HaveCount 1
    $candidates[0].candidate | Should -Be "reader@example.com"
    $candidates[0].candidateType | Should -Be "User"
    $candidates[0].confidence | Should -Be "MED"
    $candidates[0].signal | Should -Be "RBAC"
    $candidates[0].evidenceId | Should -Be $scope
  }

  It "promotes SAS generators from blob data-plane logs to owner candidates" {
    $report = [pscustomobject]@{
      enterpriseApplication = [pscustomobject]@{
        objectId = "sp-1"
      }
      graph                 = [pscustomobject]@{
        owners   = @()
        memberOf = @()
      }
      azure                 = [pscustomobject]@{
        coAssignedRoleCandidates = @()
        resourceDependencies     = @()
        activityEvidence         = @()
        blobReadEvidence         = @(
          [pscustomobject]@{
            eventTimestamp           = "2024-01-01T00:00:00Z"
            storageAccountResourceId = "/subscriptions/sub-1/resourceGroups/rg-1/providers/Microsoft.Storage/storageAccounts/st1"
            operationName            = "GetBlob"
            authenticationType       = "SAS"
            sasGeneratorObjectId     = "sas-user-1"
            sasGeneratorAppId        = "portal-app"
            sasGeneratorUpn          = "sas.owner@example.com"
            sasSignedPermissions     = "r"
            uri                      = "https://st1.blob.core.windows.net/c/a.txt?skoid=sas-user-1"
          },
          [pscustomobject]@{
            eventTimestamp           = "2024-01-02T00:00:00Z"
            storageAccountResourceId = "/subscriptions/sub-1/resourceGroups/rg-1/providers/Microsoft.Storage/storageAccounts/st1"
            operationName            = "GetBlob"
            authenticationType       = "SAS"
            sasGeneratorObjectId     = "sas-user-1"
            sasGeneratorAppId        = "portal-app"
            sasGeneratorUpn          = "sas.owner@example.com"
            sasSignedPermissions     = "r"
            uri                      = "https://st1.blob.core.windows.net/c/b.txt?skoid=sas-user-1"
          }
        )
      }
    }

    $candidates = @(Get-OwnerCandidates -Report $report)

    $candidates | Should -HaveCount 1
    $candidates[0].candidate | Should -Be "sas.owner@example.com"
    $candidates[0].candidateType | Should -Be "User"
    $candidates[0].confidence | Should -Be "LOW"
    $candidates[0].relationship | Should -Be "Indirect"
    $candidates[0].signal | Should -Be "SAS"
    $candidates[0].evidenceId | Should -Be "/subscriptions/sub-1/resourceGroups/rg-1/providers/Microsoft.Storage/storageAccounts/st1"
  }

  It "promotes recent RBAC scope activity users to owner candidates" {
    $scope = "/subscriptions/sub-1/resourceGroups/rg-1/providers/Microsoft.Storage/storageAccounts/st1"
    $report = [pscustomobject]@{
      enterpriseApplication = [pscustomobject]@{
        objectId = "sp-1"
      }
      graph                 = [pscustomobject]@{
        owners   = @()
        memberOf = @()
      }
      azure                 = [pscustomobject]@{
        coAssignedRoleCandidates = @()
        resourceDependencies     = @()
        activityEvidence         = @()
        rbacScopeActivityCallers = @(
          [pscustomobject]@{
            callerKey                        = "object:user-1"
            caller                           = "owner@example.com"
            callerObjectId                   = "user-1"
            callerAppId                      = "azure-portal-client-app"
            callerName                       = "Owner User"
            eventCount                       = 3
            firstSeen                        = "2024-01-01T00:00:00Z"
            lastSeen                         = "2024-01-02T00:00:00Z"
            rbacScopes                       = @($scope)
            matchesInspectedServicePrincipal = $false
          }
        )
        blobReadEvidence         = @()
      }
    }

    $candidates = @(Get-OwnerCandidates -Report $report)

    $candidates | Should -HaveCount 1
    $candidates[0].candidate | Should -Be "owner@example.com"
    $candidates[0].candidateType | Should -Be "User"
    $candidates[0].confidence | Should -Be "LOW"
    $candidates[0].relationship | Should -Be "Indirect"
    $candidates[0].signal | Should -Be "LOG"
    $candidates[0].evidenceId | Should -Be $scope
    $candidates[0].evidenceValue | Should -Be "events=3,lastSeen=2024-01-02T00:00:00Z"
  }

  It "does not promote unresolved RBAC principals to owner candidates" {
    $report = [pscustomobject]@{
      enterpriseApplication = [pscustomobject]@{
        objectId = "sp-1"
      }
      graph                 = [pscustomobject]@{
        owners   = @()
        memberOf = @()
      }
      azure                 = [pscustomobject]@{
        coAssignedRoleCandidates = @(
          [pscustomobject]@{
            principalId          = "31b109c6-6aa2-4cba-84c6-879bb3d8656e"
            principalName        = ""
            principalDisplayName = ""
            principalType        = ""
            roleDefinitionName   = "Reader"
            scope                = "/subscriptions/sub-1/resourceGroups/rg-1/providers/Microsoft.Storage/storageAccounts/st1"
          }
        )
        resourceDependencies     = @()
        activityEvidence         = @()
      }
    }

    $candidates = @(Get-OwnerCandidates -Report $report)

    $candidates | Should -HaveCount 1
    $candidates[0].candidateType | Should -Be "NotFound"
    $candidates[0].evidenceId | Should -Be "not-found"
  }
}

Describe "OwnerLensLite owner candidate integration" {
  BeforeEach {
    Mock Import-Module {}
    Mock Get-Command { [pscustomobject]@{ Name = $Name } }
    Mock Get-MgContext { [pscustomobject]@{ TenantId = "tenant-1" } }
    Mock Get-AzContext { [pscustomobject]@{ Subscription = @{ Id = "sub-1" } } }
    Mock Format-DependencyReport {}

    Mock Resolve-EnterpriseApplication {
      [pscustomobject]@{
        objectId            = "sp-1"
        applicationObjectId = "app-object-1"
        appId               = "app-client-1"
        displayName         = "Payments Worker"
        accountEnabled      = $true
        tags                = @("owner=platform-from-enterprise-app")
      }
    }

    Mock Get-GraphDependencies {
      [pscustomobject]@{
        owners                    = @(
          [pscustomobject]@{
            objectId          = "sp-user-owner-1"
            displayName       = "Service Principal User Owner"
            userPrincipalName = "sp.user.owner@example.com"
            mail              = "sp.user.owner@example.com"
            objectType        = "#microsoft.graph.user"
            ownerSource       = "ServicePrincipal"
          },
          [pscustomobject]@{
            objectId          = "app-user-owner-1"
            displayName       = "Application User Owner"
            userPrincipalName = "app.user.owner@example.com"
            mail              = "app.user.owner@example.com"
            objectType        = "#microsoft.graph.user"
            ownerSource       = "Application"
          }
        )
        appRoleAssignments        = @()
        oauth2PermissionGrants    = @()
        memberOf                  = @(
          [pscustomobject]@{
            objectId    = "member-group-1"
            displayName = "Payments Operators"
            objectType  = "#microsoft.graph.group"
          }
        )
        resourceServicePrincipals = @()
        userSignIns               = @()
      }
    }

    $resourceTags = [System.Collections.Generic.Dictionary[string, string]]::new()
    $resourceTags["owner"] = "platform-team"
    $resourceTags["repoName"] = "payments-worker"

    Mock Get-AzureDependencies {
      [pscustomobject]@{
        requestedSubscriptions     = @("sub-1")
        subscriptions              = @()
        roleAssignments            = @()
        coAssignedRoleCandidates   = @(
          [pscustomobject]@{
            principalId          = "rbac-group-1"
            principalDisplayName = "Payments Contributors"
            principalType        = "Group"
            roleDefinitionName   = "Contributor"
            scope                = "/subscriptions/sub-1/resourceGroups/rg-payments"
          }
        )
        resourceDependencies       = @(
          [pscustomobject]@{
            resourceId = "/subscriptions/sub-1/resourceGroups/rg-payments/providers/Microsoft.Web/sites/payments-worker"
            tags       = $resourceTags
          }
        )
        activityEvidence           = @()
        rbacScopeActivityEvidence  = @()
        rbacScopeActivityCallers   = @()
        activityDiagnosticSettings = @()
        storageAccountsWithRbac    = @()
        blobReadEvidence           = @()
        blobReadCallers            = @()
        blobReadObjects            = @()
        logAnalyticsWorkspaceId    = ""
        maxBlobReadRecords         = 5000
        activityStartTime          = "2024-01-01T00:00:00.0000000Z"
      }
    }
  }

  It "finds service principal owner, application owner, direct tag, indirect tags, membership group, and RBAC group" {
    $report = Invoke-OwnerLensLite -EnterpriseApplication "Payments Worker" -SkipLogin -SkipActivityLogs

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

Describe "OwnerLensLite Microsoft Graph application owner discovery" {
  It "loads owners from the application object when applicationObjectId is available" {
    Mock Invoke-GraphPagedRequest {
      switch -Wildcard ($Uri) {
        "/v1.0/servicePrincipals/sp-1/owners*" {
          return @()
        }
        "/v1.0/applications/app-object-1/owners*" {
          return @(
            [pscustomobject]@{
              id                = "app-user-owner-1"
              displayName       = "Application User Owner"
              userPrincipalName = "app.user.owner@example.com"
              mail              = "app.user.owner@example.com"
              "@odata.type"     = "#microsoft.graph.user"
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
        objectId            = "sp-1"
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

  It "loads sign-ins for one requested user" {
    Mock Invoke-GraphPagedRequest {
      switch -Wildcard ($Uri) {
        "/v1.0/auditLogs/signIns*" {
          return @(
            [pscustomobject]@{
              id                      = "sign-in-1"
              createdDateTime         = "2024-01-02T00:00:00Z"
              userId                  = "user-1"
              userPrincipalName       = "owner@example.com"
              userDisplayName         = "Owner User"
              appId                   = "client-app-1"
              appDisplayName          = "Azure Portal"
              ipAddress               = "198.51.100.10"
              location                = [pscustomobject]@{
                city            = "Warsaw"
                state           = "Mazowieckie"
                countryOrRegion = "PL"
              }
              clientAppUsed           = "Browser"
              conditionalAccessStatus = "success"
              status                  = [pscustomobject]@{
                errorCode     = 0
                failureReason = ""
              }
              resourceDisplayName     = "Windows Azure Service Management API"
              resourceId              = "resource-1"
              correlationId           = "correlation-1"
            },
            [pscustomobject]@{
              id                = "sign-in-2"
              createdDateTime   = "2024-01-01T00:00:00Z"
              userId            = "user-1"
              userPrincipalName = "owner@example.com"
              appDisplayName    = "Azure CLI"
              status            = [pscustomobject]@{
                errorCode     = 50058
                failureReason = "User session missing."
              }
            }
          )
        }
        default {
          return @()
        }
      }
    }
    Mock Invoke-RestRequestWithRetry {}

    $dependencies = Get-GraphDependencies `
      -ServicePrincipal ([pscustomobject]@{ objectId = "sp-1" }) `
      -SignInUser "owner@example.com" `
      -SignInStartTime ([datetime]"2024-01-01T00:00:00Z") `
      -MaxUserSignInRecords 1

    $dependencies.userSignIns | Should -HaveCount 1
    $dependencies.userSignIns[0].id | Should -Be "sign-in-1"
    $dependencies.userSignIns[0].userPrincipalName | Should -Be "owner@example.com"
    $dependencies.userSignIns[0].appDisplayName | Should -Be "Azure Portal"
    $dependencies.userSignIns[0].locationCountryOrRegion | Should -Be "PL"
    $dependencies.userSignIns[0].locationCity | Should -Be "Warsaw"
    $dependencies.userSignIns[0].statusErrorCode | Should -Be "0"

    Should -Invoke Invoke-GraphPagedRequest -ParameterFilter {
      $OperationName -eq "Microsoft Graph user sign-ins request" -and
      $Uri -like "/v1.0/auditLogs/signIns*" -and
      [System.Uri]::UnescapeDataString($Uri) -like "*userPrincipalName eq 'owner@example.com'*" -and
      [System.Uri]::UnescapeDataString($Uri) -like "*createdDateTime ge 2024-01-01T00:00:00.0000000Z*"
    } -Exactly 1
  }

  It "summarizes user sign-in locations" {
    $rows = @(Get-OwnerLensUserSignInLocationRows -UserSignIns @(
        [pscustomobject]@{
          createdDateTime         = "2024-01-01T00:00:00Z"
          locationCountryOrRegion = "PL"
          locationState           = "Mazowieckie"
          locationCity            = "Warsaw"
          ipAddress               = "198.51.100.10"
        },
        [pscustomobject]@{
          createdDateTime         = "2024-01-02T00:00:00Z"
          locationCountryOrRegion = "PL"
          locationState           = "Mazowieckie"
          locationCity            = "Warsaw"
          ipAddress               = "198.51.100.10"
        },
        [pscustomobject]@{
          createdDateTime         = "2024-01-03T00:00:00Z"
          locationCountryOrRegion = ""
          locationState           = ""
          locationCity            = ""
          ipAddress               = ""
        }
      ))

    $rows | Should -HaveCount 2
    $rows[0].countryOrRegion | Should -Be "PL"
    $rows[0].city | Should -Be "Warsaw"
    $rows[0].ipAddress | Should -Be "198.51.100.10"
    $rows[0].signInCount | Should -Be 2
    $rows[0].firstSeen | Should -Be "2024-01-01T00:00:00Z"
    $rows[0].lastSeen | Should -Be "2024-01-02T00:00:00Z"
    $rows[1].countryOrRegion | Should -Be "unknown country"
    $rows[1].ipAddress | Should -Be "unknown ip"
  }

  It "does not retry permanent authorization failures" {
    $script:attempts = 0

    {
      Invoke-RestRequestWithRetry `
        -OperationName "Permanent failure" `
        -MaxRetryCount 3 `
        -RetryDelaySeconds 0 `
        -Request {
        $script:attempts += 1
        throw "Response status code does not indicate success: 403 (Forbidden)."
      }
    } | Should -Throw

    $script:attempts | Should -Be 1
  }

  It "propagates Graph application lookup failures while resolving enterprise applications" {
    $appId = "11111111-1111-1111-1111-111111111111"
    $objectId = "22222222-2222-2222-2222-222222222222"

    Mock Invoke-RestRequestWithRetry {
      [pscustomobject]@{
        id          = $objectId
        appId       = $appId
        displayName = "App One"
      }
    }

    Mock Invoke-GraphPagedRequest {
      if ($Uri -like "/v1.0/servicePrincipals*") {
        return @(
          [pscustomobject]@{
            id          = $objectId
            appId       = $appId
            displayName = "App One"
          }
        )
      }

      if ($Uri -like "/v1.0/applications*") {
        throw "Graph permission denied"
      }

      return @()
    }

    {
      Resolve-EnterpriseApplication -EnterpriseApplication $objectId
    } | Should -Throw -ExpectedMessage "*Graph permission denied*"
  }

  It "throws RBAC collection failures and restores the original Azure context" {
    Mock Get-AzContext {
      [pscustomobject]@{
        Subscription = [pscustomobject]@{
          Id = "original-sub"
        }
      }
    }
    Mock Get-AzSubscription {
      @(
        [pscustomobject]@{
          Id       = "sub-1"
          Name     = "Sub One"
          TenantId = "tenant-1"
          State    = "Enabled"
        }
      )
    }
    Mock Set-AzContext {}
    Mock Get-AzureActivityDiagnosticSummary { @() }
    Mock Get-AzResource { @() }
    Mock Get-AzResourceGroup { @() }
    Mock Get-AzRoleAssignment { throw "RBAC permission denied" }

    {
      Get-AzureDependencies `
        -ServicePrincipal ([pscustomobject]@{ objectId = "sp-1" }) `
        -SubscriptionIds "sub-1" `
        -SkipActivityLogs
    } | Should -Throw -ExpectedMessage "*RBAC permission denied*"

    Should -Invoke Set-AzContext -ParameterFilter { $SubscriptionId -eq "sub-1" } -Exactly 1
    Should -Invoke Set-AzContext -ParameterFilter { $Context.Subscription.Id -eq "original-sub" } -Exactly 1
  }

}
