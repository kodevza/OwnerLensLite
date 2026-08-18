BeforeAll {
  . (Join-Path $PSScriptRoot "../Support/Import-OwnerLensLightTestFunctions.ps1")
}

Describe "OwnerLens Microsoft Graph App Role Assignments table" {
  It "generates table rows from app role assignments" {
    $rows = @(Get-OwnerLensGraphAppRoleAssignmentsTableRows -AppRoleAssignments @(
        [pscustomobject]@{
          resourceDisplayName = "Microsoft Graph"
          appRoleId = "role-1"
          createdDateTime = "2024-01-01T00:00:00Z"
        }
      ))

    $rows | Should -HaveCount 1
    $rows[0].resourceDisplayName | Should -Be "Microsoft Graph"
  }
}
