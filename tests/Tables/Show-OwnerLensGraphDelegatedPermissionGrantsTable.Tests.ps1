BeforeAll {
  . (Join-Path $PSScriptRoot "../Support/Import-OwnerLensLiteTestFunctions.ps1")
}

Describe "OwnerLens Microsoft Graph Delegated Permission Grants table" {
  It "generates table rows from permission grants" {
    $rows = @(Get-OwnerLensGraphDelegatedPermissionGrantsTableRows -OAuth2PermissionGrants @(
        [pscustomobject]@{
          resourceId  = "graph-sp"
          consentType = "AllPrincipals"
          scope       = "User.Read"
        }
      ))

    $rows | Should -HaveCount 1
    $rows[0].scope | Should -Be "User.Read"
  }
}
