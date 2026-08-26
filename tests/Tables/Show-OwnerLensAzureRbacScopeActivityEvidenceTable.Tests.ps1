BeforeAll {
  . (Join-Path $PSScriptRoot "../Support/Import-OwnerLensLiteTestFunctions.ps1")
}

Describe "OwnerLens Azure RBAC Scope Activity Evidence table" {
  It "generates table rows with resource and scope portal links" {
    $resourceId = "/subscriptions/sub-1/resourceGroups/rg-1/providers/Microsoft.Web/sites/app1"
    $scope = "/subscriptions/sub-1/resourceGroups/rg-1"
    $rows = @(Get-OwnerLensAzureRbacScopeActivityEvidenceTableRows -RbacScopeActivityEvidence @(
        [pscustomobject]@{
          eventTimestamp     = "2024-01-01T00:00:00Z"
          callerName         = "Owner User"
          caller             = "owner@example.com"
          operationNameValue = "Microsoft.Web/sites/write"
          resourceId         = $resourceId
          rbacScope          = $scope
          status             = "Succeeded"
        }
      ))

    $rows | Should -HaveCount 1
    $rows[0].resourceId | Should -Match "Microsoft.Web/sites/app1"
    $rows[0].rbacScope | Should -Match "resourceGroups/rg-1"
    $rows[0].status | Should -Be "Succeeded"
  }

  It "renders the Recent Azure RBAC Scope Activity Evidence section" {
    Mock Write-RichRule {}
    Mock Write-RichTable {}

    Show-OwnerLensAzureRbacScopeActivityEvidenceTable -Report ([pscustomobject]@{
        azure = [pscustomobject]@{
          rbacScopeActivityEvidence = @(
            [pscustomobject]@{
              eventTimestamp     = "2024-01-01T00:00:00Z"
              callerName         = "Owner User"
              caller             = "owner@example.com"
              operationNameValue = "Microsoft.Web/sites/write"
              resourceId         = "/subscriptions/sub-1/resourceGroups/rg-1/providers/Microsoft.Web/sites/app1"
              rbacScope          = "/subscriptions/sub-1/resourceGroups/rg-1"
              status             = "Succeeded"
            }
          )
        }
      })

    Should -Invoke Write-RichRule -Exactly 1 -ParameterFilter {
      $Title -eq "Recent Azure RBAC Scope Activity Evidence" -and
      $Style -eq "cyan"
    }
    Should -Invoke Write-RichTable -Exactly 1 -ParameterFilter {
      (@($Property) -join ",") -eq "eventTimestamp,callerName,caller,operationNameValue,resourceId,rbacScope,status" -and
      $Box -eq "Square"
    }
  }
}
