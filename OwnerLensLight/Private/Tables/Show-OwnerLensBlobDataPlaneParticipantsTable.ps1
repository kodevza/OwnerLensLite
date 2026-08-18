function Get-OwnerLensBlobDataPlaneParticipantsTableRows {
  param([object[]]$BlobReadCallers)

  @($BlobReadCallers | Select-Object requesterUpn, requesterObjectId, requesterAppId, requesterType, authenticationType, blobReadCount, blobPublishCount, blobAccessCount, sasAuthenticationCount, @{ Name = "sasGeneratorUpns"; Expression = { Format-OwnerLensListValue -Value $_.sasGeneratorUpns } }, @{ Name = "sasGeneratorObjectIds"; Expression = { Format-OwnerLensListValue -Value $_.sasGeneratorObjectIds } }, @{ Name = "sasGeneratorAppIds"; Expression = { Format-OwnerLensListValue -Value $_.sasGeneratorAppIds } }, firstSeen, lastSeen, matchesInspectedServicePrincipal)
}

function Show-OwnerLensBlobDataPlaneParticipantsTable {
  param([object]$Report)

  if ($Report.azure.blobReadCallers.Count -eq 0) {
    return
  }

  Write-RichRule "Recent Blob Data-Plane Participants" -Style "cyan"
  Get-OwnerLensBlobDataPlaneParticipantsTableRows -BlobReadCallers @($Report.azure.blobReadCallers) |
    Write-RichTable -Property requesterUpn, requesterObjectId, requesterAppId, requesterType, authenticationType, blobReadCount, blobPublishCount, blobAccessCount, sasAuthenticationCount, sasGeneratorUpns, sasGeneratorObjectIds, sasGeneratorAppIds, firstSeen, lastSeen, matchesInspectedServicePrincipal -Box Square
}
