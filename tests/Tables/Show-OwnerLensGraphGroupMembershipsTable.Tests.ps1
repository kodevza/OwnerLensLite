BeforeAll {
  . (Join-Path $PSScriptRoot "../Support/Import-OwnerLensLightTestFunctions.ps1")
}

Describe "OwnerLens Microsoft Graph Group Memberships table" {
  It "generates table rows from group memberships" {
    $rows = @(Get-OwnerLensGraphGroupMembershipsTableRows -MemberOf @(
        [pscustomobject]@{
          displayName = "Payments"
          objectId = "group-1"
          objectType = "Group"
        }
      ))

    $rows | Should -HaveCount 1
    $rows[0].objectType | Should -Be "Group"
  }
}
