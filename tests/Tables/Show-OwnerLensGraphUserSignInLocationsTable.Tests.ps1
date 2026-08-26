BeforeAll {
  . (Join-Path $PSScriptRoot "../Support/Import-OwnerLensLiteTestFunctions.ps1")
}

Describe "OwnerLens Microsoft Graph User Sign-In Locations table" {
  It "generates location summary rows from user sign-ins" {
    $rows = @(Get-OwnerLensGraphUserSignInLocationsTableRows -UserSignIns @(
        [pscustomobject]@{
          createdDateTime         = "2024-01-01T00:00:00Z"
          locationCountryOrRegion = "PL"
          locationState           = "Mazowieckie"
          locationCity            = "Warsaw"
          ipAddress               = "198.51.100.10"
        }
      ))

    $rows | Should -HaveCount 1
    $rows[0].signInCount | Should -Be 1
  }
}
