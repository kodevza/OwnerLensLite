function Get-OwnerLensOwnerCandidatesTableRows {
  param([object[]]$OwnerCandidates)

  @($OwnerCandidates | Select-Object candidate, @{ Name = "type"; Expression = { $_.candidateType } }, confidence, relationship, signal, @{ Name = "evidenceId"; Expression = { Format-OwnerLensOwnerCandidateEvidenceId -EvidenceId ([string]$_.evidenceId) } })
}

function Show-OwnerLensOwnerCandidatesTable {
  param([object]$Report)

  if (@($Report.ownerCandidates).Count -eq 0) {
    return
  }

  Write-RichRule "Owner Candidates" -Style "cyan"
  Get-OwnerLensOwnerCandidatesTableRows -OwnerCandidates @($Report.ownerCandidates) |
    Write-RichTable -Property candidate, type, confidence, relationship, signal, evidenceId -Box Square
}
