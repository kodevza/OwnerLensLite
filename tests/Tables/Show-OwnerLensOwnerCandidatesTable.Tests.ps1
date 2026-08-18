BeforeAll {
  . (Join-Path $PSScriptRoot "../Support/Import-OwnerLensLightTestFunctions.ps1")
}

Describe "OwnerLens Owner Candidates table" {
  It "generates table rows with formatted evidence links" {
    $evidenceId = "/servicePrincipals/sp-1/owners/user-1"
    $rows = @(Get-OwnerLensOwnerCandidatesTableRows -OwnerCandidates @(
        [pscustomobject]@{
          candidate = "owner@example.com"
          candidateType = "User"
          confidence = "HIGH"
          relationship = "Direct"
          signal = "GraphOwner"
          evidenceId = $evidenceId
        }
      ))

    $rows | Should -HaveCount 1
    $rows[0].type | Should -Be "User"
    $rows[0].evidenceId | Should -Match "graph-explorer"
  }
}
