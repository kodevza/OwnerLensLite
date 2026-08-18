BeforeAll {
  . (Join-Path $PSScriptRoot "../Support/Import-OwnerLensLightTestFunctions.ps1")
}

Describe "OwnerLens Microsoft Graph User Sign-Ins table" {
  It "generates table rows from user sign-ins" {
    $rows = @(Get-OwnerLensGraphUserSignInsTableRows -UserSignIns @(
        [pscustomobject]@{
          createdDateTime = "2024-01-01T00:00:00Z"
          userPrincipalName = "owner@example.com"
          appDisplayName = "Azure Portal"
          ipAddress = "198.51.100.10"
          locationCountryOrRegion = "PL"
          locationState = "Mazowieckie"
          locationCity = "Warsaw"
          clientAppUsed = "Browser"
          conditionalAccessStatus = "success"
          statusErrorCode = "0"
          statusFailureReason = ""
          resourceDisplayName = "Azure Portal"
        }
      ))

    $rows | Should -HaveCount 1
    $rows[0].userPrincipalName | Should -Be "owner@example.com"
  }
}
