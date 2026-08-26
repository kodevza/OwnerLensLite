BeforeAll {
  . (Join-Path $PSScriptRoot "Support/Import-OwnerLensLightTestFunctions.ps1")
}

Describe "OwnerLens console anonymization" {
  It "replaces user identities and GUIDs with deterministic aliases" {
    $tags = [System.Collections.Generic.Dictionary[string, string]]::new()
    $tags["owner"] = "Ada Lovelace"
    $tags["costCenter"] = "cc-42"

    $report = [pscustomobject]@{
      meta = [pscustomobject]@{
        signInUser = "ada@example.com"
        ownerTagConfiguration = [pscustomobject]@{
          userOwnerTagNames = @("userOwner")
          groupOwnerTagNames = @("ownerGroup")
          tagOwnerTagNames = @("owner")
        }
      }
      enterpriseApplication = [pscustomobject]@{
        objectId = "11111111-1111-1111-1111-111111111111"
        appId = "22222222-2222-2222-2222-222222222222"
        displayName = "Payments API"
      }
      graph = [pscustomobject]@{
        owners = @(
          [pscustomobject]@{
            objectId = "33333333-3333-3333-3333-333333333333"
            displayName = "Ada Lovelace"
            userPrincipalName = "ada@example.com"
            objectType = "#microsoft.graph.user"
          }
        )
      }
      azure = [pscustomobject]@{
        resourceDependencies = @(
          [pscustomobject]@{
            resourceId = "/subscriptions/44444444-4444-4444-4444-444444444444/resourceGroups/rg-1/providers/Microsoft.Storage/storageAccounts/prodstorageacct01"
            resourceType = "Microsoft.Storage/storageAccounts"
            resourceName = "prodstorageacct01"
            tags = $tags
          }
        )
        storageAccountsWithRbac = @(
          [pscustomobject]@{
            name = "prodstorageacct01"
            resourceId = "/subscriptions/44444444-4444-4444-4444-444444444444/resourceGroups/rg-1/providers/Microsoft.Storage/storageAccounts/prodstorageacct01"
          }
        )
        blobReadEvidence = @(
          [pscustomobject]@{
            storageAccountName = "prodstorageacct01"
            uri = "https://prodstorageacct01.blob.core.windows.net/container/blob.txt"
          }
        )
        blobReadCallers = @(
          [pscustomobject]@{
            storageAccounts = @("prodstorageacct01")
          }
        )
      }
      ownerCandidates = @(
        [pscustomobject]@{
          candidate = "ada@example.com"
          candidateType = "User"
          evidenceId = "/servicePrincipals/11111111-1111-1111-1111-111111111111/owners/33333333-3333-3333-3333-333333333333"
        }
      )
    }

    $anonymized = ConvertTo-OwnerLensAnonymizedConsoleReport -Report $report
    $json = $anonymized | ConvertTo-Json -Depth 20

    $json | Should -Not -Match "ada@example.com|Ada Lovelace|11111111-1111-1111-1111-111111111111|33333333-3333-3333-3333-333333333333"
    $json | Should -Not -Match "prodstorageacct01"
    $anonymized.enterpriseApplication.displayName | Should -Be "Payments API"
    @($anonymized.meta.ownerTagConfiguration.tagOwnerTagNames) | Should -Be @("owner")
    $anonymized.ownerCandidates[0].candidate | Should -Match "^user-[0-9]{4}$"
    $anonymized.ownerCandidates[0].evidenceId | Should -Match "guid-[0-9]{4}"
    $anonymized.azure.storageAccountsWithRbac[0].name | Should -Match "^storage-[0-9]{4}$"
    $anonymized.azure.blobReadEvidence[0].storageAccountName | Should -Be $anonymized.azure.storageAccountsWithRbac[0].name
    $anonymized.azure.blobReadEvidence[0].uri | Should -Match "https://storage-[0-9]{4}\.blob\.core\.windows\.net/container/blob\.txt"
    @($anonymized.azure.blobReadCallers[0].storageAccounts) | Should -Be @($anonymized.azure.storageAccountsWithRbac[0].name)
  }

  It "uses anonymized data for console rendering while returning the original report" {
    Mock Import-Module {}
    Mock Get-Command { [pscustomobject]@{ Name = $Name } }
    Mock Get-MgContext { [pscustomobject]@{ TenantId = "tenant-1" } }
    Mock Get-AzContext { [pscustomobject]@{ Subscription = "sub-1" } }
    Mock Invoke-OwnerLensAssessment {
      [pscustomobject]@{
        enterpriseApplication = [pscustomobject]@{
          objectId = "11111111-1111-1111-1111-111111111111"
          appId = "22222222-2222-2222-2222-222222222222"
          displayName = "Payments API"
        }
        azure = [pscustomobject]@{
          roleAssignments = @()
          storageAccountsWithRbac = @(
            [pscustomobject]@{
              name = "prodstorageacct01"
              resourceId = "/subscriptions/44444444-4444-4444-4444-444444444444/resourceGroups/rg-1/providers/Microsoft.Storage/storageAccounts/prodstorageacct01"
            }
          )
          blobReadEvidence = @(
            [pscustomobject]@{
              storageAccountName = "prodstorageacct01"
              uri = "https://prodstorageacct01.blob.core.windows.net/container/blob.txt"
            }
          )
        }
        graph = [pscustomobject]@{
          userSignIns = @(
            [pscustomobject]@{
              userPrincipalName = "ada@example.com"
            }
          )
        }
        ownerCandidates = @(
          [pscustomobject]@{
            candidate = "ada@example.com"
            candidateType = "User"
            confidence = "HIGH"
            relationship = "Direct"
            signal = "OWNER"
            evidenceId = "/servicePrincipals/11111111-1111-1111-1111-111111111111/owners/33333333-3333-3333-3333-333333333333"
          }
        )
      }
    }
    Mock Format-DependencyReport { $script:renderedReport = $Report }

    $result = Invoke-OwnerLensLight -EnterpriseApplication "Payments API" -SkipLogin -AnonymizeConsoleOutput
    $renderedJson = $script:renderedReport | ConvertTo-Json -Depth 20

    $result.enterpriseApplication.objectId | Should -Be "11111111-1111-1111-1111-111111111111"
    $result.ownerCandidates[0].candidate | Should -Be "ada@example.com"
    $result.azure.storageAccountsWithRbac[0].name | Should -Be "prodstorageacct01"
    $renderedJson | Should -Not -Match "ada@example.com|prodstorageacct01|11111111-1111-1111-1111-111111111111|33333333-3333-3333-3333-333333333333"
    $script:renderedReport.ownerCandidates[0].candidate | Should -Match "^user-[0-9]{4}$"
    $script:renderedReport.azure.storageAccountsWithRbac[0].name | Should -Match "^storage-[0-9]{4}$"
  }
}
