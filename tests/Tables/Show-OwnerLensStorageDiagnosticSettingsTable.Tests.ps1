BeforeAll {
  . (Join-Path $PSScriptRoot "../Support/Import-OwnerLensLiteTestFunctions.ps1")
}

Describe "OwnerLens Storage Diagnostic Settings table" {
  It "generates table rows for missing diagnostic settings" {
    $rows = @(Get-OwnerLensStorageDiagnosticSettingsTableRows -StorageAccounts @(
        [pscustomobject]@{
          resourceId            = "/subscriptions/sub-1/resourceGroups/rg-1/providers/Microsoft.Storage/storageAccounts/st1"
          name                  = "st1"
          dataPlaneReadServices = @("Blob")
          diagnosticSettings    = @()
        }
      ))

    $rows | Should -HaveCount 1
    $rows[0].storageAccountName | Should -Be "st1"
    $rows[0].status | Should -Be "[yellow]NotConfigured[/]"
  }
}
