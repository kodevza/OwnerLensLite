BeforeAll {
  . (Join-Path $PSScriptRoot "../Support/Import-OwnerLensLightTestFunctions.ps1")
}

Describe "OwnerLens Blob Data-Plane Participants table" {
  It "generates table rows with formatted SAS generators" {
    $rows = @(Get-OwnerLensBlobDataPlaneParticipantsTableRows -BlobReadCallers @(
        [pscustomobject]@{
          requesterUpn = "owner@example.com"
          requesterObjectId = "user-1"
          requesterAppId = "app-1"
          requesterType = "UserAndServicePrincipal"
          authenticationType = "OAuth"
          blobReadCount = 2
          blobPublishCount = 1
          blobAccessCount = 3
          sasAuthenticationCount = 1
          sasGeneratorUpns = @("publisher@example.com")
          sasGeneratorObjectIds = @("publisher-1")
          sasGeneratorAppIds = @("publisher-app")
          firstSeen = "2024-01-01T00:00:00Z"
          lastSeen = "2024-01-02T00:00:00Z"
          matchesInspectedServicePrincipal = $false
        }
      ))

    $rows | Should -HaveCount 1
    $rows[0].sasGeneratorUpns | Should -Be "publisher@example.com"
    $rows[0].blobAccessCount | Should -Be 3
  }
}
