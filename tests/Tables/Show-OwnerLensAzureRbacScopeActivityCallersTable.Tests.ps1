BeforeAll {
  . (Join-Path $PSScriptRoot "../Support/Import-OwnerLensLiteTestFunctions.ps1")
}

Describe "OwnerLens Azure RBAC Scope Activity Callers table" {
  It "generates table rows from caller summaries" {
    $rows = @(Get-OwnerLensAzureRbacScopeActivityCallersTableRows -RbacScopeActivityCallers @(
        [pscustomobject]@{
          callerName                       = "Owner User"
          caller                           = "owner@example.com"
          callerObjectId                   = "user-1"
          callerAppId                      = ""
          eventCount                       = 2
          firstSeen                        = "2024-01-01T00:00:00Z"
          lastSeen                         = "2024-01-02T00:00:00Z"
          matchesInspectedServicePrincipal = $false
        }
      ))

    $rows | Should -HaveCount 1
    $rows[0].callerName | Should -Be "Owner User"
    $rows[0].eventCount | Should -Be 2
  }
}
