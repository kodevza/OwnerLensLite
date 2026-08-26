BeforeAll {
  . (Join-Path $PSScriptRoot "../Support/Import-OwnerLensLiteTestFunctions.ps1")
}

Describe "OwnerLens Azure Activity Evidence table" {
  It "generates table rows with portal links" {
    $resourceId = "/subscriptions/sub-1/resourceGroups/rg-1/providers/Microsoft.Web/sites/app1"
    $rows = @(Get-OwnerLensAzureActivityEvidenceTableRows -ActivityEvidence @(
        [pscustomobject]@{
          eventTimestamp     = "2024-01-01T00:00:00Z"
          subscriptionName   = "Sub One"
          operationNameValue = "Microsoft.Web/sites/write"
          resourceId         = $resourceId
          status             = "Succeeded"
        }
      ))

    $rows | Should -HaveCount 1
    $rows[0].resourceId | Should -Be "[link=https://portal.azure.com/#resource$resourceId]$resourceId[/link]"
  }
}
