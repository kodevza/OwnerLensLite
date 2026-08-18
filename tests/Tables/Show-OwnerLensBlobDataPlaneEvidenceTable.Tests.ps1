BeforeAll {
  . (Join-Path $PSScriptRoot "../Support/Import-OwnerLensLightTestFunctions.ps1")
}

Describe "OwnerLens Blob Data-Plane Evidence table" {
  It "generates table rows with URI links" {
    $uri = "https://st1.blob.core.windows.net/c/a.txt"
    $rows = @(Get-OwnerLensBlobDataPlaneEvidenceTableRows -BlobReadEvidence @(
        [pscustomobject]@{
          eventTimestamp = "2024-01-01T00:00:00Z"
          storageAccountName = "st1"
          accessDirection = "Read"
          requesterUpn = "owner@example.com"
          requesterObjectId = "user-1"
          requesterAppId = ""
          requesterType = "User"
          authenticationType = "OAuth"
          operationName = "GetBlob"
          statusText = "Success"
          uri = $uri
        }
      ))

    $rows | Should -HaveCount 1
    $rows[0].uri | Should -Be "[link=$uri]$uri[/link]"
  }
}
