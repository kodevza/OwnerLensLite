function Get-OwnerLensBlobDataPlaneParticipantsTableRows {
  param([object[]]$BlobReadCallers)

  @($BlobReadCallers | Select-Object requesterUpn, requesterObjectId, requesterAppId, requesterType, authenticationType, blobReadCount, blobPublishCount, blobAccessCount, sasAuthenticationCount, @{ Name = "sasGeneratorUpns"; Expression = { Format-OwnerLensListValue -Value $_.sasGeneratorUpns } }, @{ Name = "sasGeneratorObjectIds"; Expression = { Format-OwnerLensListValue -Value $_.sasGeneratorObjectIds } }, @{ Name = "sasGeneratorAppIds"; Expression = { Format-OwnerLensListValue -Value $_.sasGeneratorAppIds } }, firstSeen, lastSeen, matchesInspectedServicePrincipal)
}

function Show-OwnerLensBlobDataPlaneParticipantsTable {
  param([object]$Report)

  Write-OwnerLensReportTable `
    -Title "Recent Blob Data-Plane Participants" `
    -Rows (Get-OwnerLensBlobDataPlaneParticipantsTableRows -BlobReadCallers (Get-OwnerLensReportArray -Report $Report -Path "azure.blobReadCallers")) `
    -Property requesterUpn, requesterObjectId, requesterAppId, requesterType, authenticationType, blobReadCount, blobPublishCount, blobAccessCount, sasAuthenticationCount, sasGeneratorUpns, sasGeneratorObjectIds, sasGeneratorAppIds, firstSeen, lastSeen, matchesInspectedServicePrincipal
}
