function Get-OwnerLensOwnerCandidatesTableRows {
  param([object[]]$OwnerCandidates)

  @($OwnerCandidates | Select-Object candidate, @{ Name = "type"; Expression = { $_.candidateType } }, confidence, relationship, signal, @{ Name = "evidenceId"; Expression = { Format-OwnerLensOwnerCandidateEvidenceId -EvidenceId ([string]$_.evidenceId) } })
}

function Show-OwnerLensOwnerCandidatesTable {
  param([object]$Report)

  Write-OwnerLensReportTable `
    -Title "Owner Candidates" `
    -Style "bold dim" `
    -SurroundWithBlankRules `
    -Rows (Get-OwnerLensOwnerCandidatesTableRows -OwnerCandidates (Get-OwnerLensReportArray -Report $Report -Path "ownerCandidates")) `
    -Property candidate, type, confidence, relationship, signal, evidenceId
}
