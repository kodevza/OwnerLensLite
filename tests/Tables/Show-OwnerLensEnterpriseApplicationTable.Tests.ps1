BeforeAll {
  . (Join-Path $PSScriptRoot "../Support/Import-OwnerLensLightTestFunctions.ps1")
}

Describe "OwnerLens Enterprise Application table" {
  It "generates table rows from report metadata" {
    $rows = @(Get-OwnerLensEnterpriseApplicationTableRows -Report ([pscustomobject]@{
          enterpriseApplication = [pscustomobject]@{
            displayName = "Payments Worker"
            objectId = "sp-1"
            appId = "app-1"
            accountEnabled = $true
          }
          meta = [pscustomobject]@{ createdAt = "2024-01-01T00:00:00Z" }
        }))

    $rows | Should -HaveCount 1
    $rows[0].Name | Should -Be "Payments Worker"
    $rows[0].ObjectId | Should -Be "sp-1"
    $rows[0].CreatedAt | Should -Be "2024-01-01T00:00:00Z"
  }
}
