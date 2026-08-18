BeforeAll {
  . (Join-Path $PSScriptRoot "../Support/Import-OwnerLensLightTestFunctions.ps1")
}

Describe "OwnerLens Blob Reads By Object table" {
  It "generates table rows with URI links" {
    $uri = "https://st1.blob.core.windows.net/c/a.txt"
    $rows = @(Get-OwnerLensBlobReadsByObjectTableRows -BlobReadObjects @(
        [pscustomobject]@{
          requesterUpn = "owner@example.com"
          requesterObjectId = "user-1"
          requesterAppId = ""
          requesterType = "User"
          authenticationType = "OAuth"
          storageAccountName = "st1"
          objectKey = "/blobServices/default/containers/c/blobs/a.txt"
          uri = $uri
          blobReadCount = 2
          firstReadAt = "2024-01-01T00:00:00Z"
          lastReadAt = "2024-01-02T00:00:00Z"
          matchesInspectedServicePrincipal = $false
        }
      ))

    $rows | Should -HaveCount 1
    $rows[0].uri | Should -Be "[link=$uri]$uri[/link]"
  }
}
