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

  It "renders the Owner Candidates section with surrounding rules" {
    $script:ruleTitles = [System.Collections.ArrayList]::new()
    Mock Write-RichRule { $script:ruleTitles.Add([string]$Title) | Out-Null }
    Mock Write-RichTable {}

    Show-OwnerLensOwnerCandidatesTable -Report ([pscustomobject]@{
        ownerCandidates = @(
          [pscustomobject]@{
            candidate = "owner@example.com"
            candidateType = "User"
            confidence = "HIGH"
            relationship = "Direct"
            signal = "GraphOwner"
            evidenceId = "/servicePrincipals/sp-1/owners/user-1"
          }
        )
      })

    Should -Invoke Write-RichRule -Exactly 3
    @($script:ruleTitles) | Should -Be @("", "Owner Candidates", "")
    Should -Invoke Write-RichTable -Exactly 1 -ParameterFilter {
      (@($Property) -join ",") -eq "candidate,type,confidence,relationship,signal,evidenceId" -and
      $Box -eq "Square"
    }
  }
}
