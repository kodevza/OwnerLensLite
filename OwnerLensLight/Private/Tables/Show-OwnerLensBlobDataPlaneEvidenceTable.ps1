function Get-OwnerLensBlobDataPlaneEvidenceTableRows {
  param([object[]]$BlobReadEvidence)

  @($BlobReadEvidence | Select-Object eventTimestamp, storageAccountName, accessDirection, requesterUpn, requesterObjectId, requesterAppId, requesterType, authenticationType, operationName, statusText, @{ Name = "uri"; Expression = { Format-OwnerLensUriLink -Uri ([string]$_.uri) } })
}

function Show-OwnerLensBlobDataPlaneEvidenceTable {
  param([object]$Report)

  if ($Report.azure.blobReadEvidence.Count -eq 0) {
    return
  }

  Write-RichRule "Recent Blob Data-Plane Evidence" -Style "cyan"
  Get-OwnerLensBlobDataPlaneEvidenceTableRows -BlobReadEvidence @($Report.azure.blobReadEvidence) |
    Write-RichTable -Property eventTimestamp, storageAccountName, accessDirection, requesterUpn, requesterObjectId, requesterAppId, requesterType, authenticationType, operationName, statusText, uri -Box Square
}
