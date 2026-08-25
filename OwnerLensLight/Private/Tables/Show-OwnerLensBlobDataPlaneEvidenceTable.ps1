function Get-OwnerLensBlobDataPlaneEvidenceTableRows {
  param([object[]]$BlobReadEvidence)

  @($BlobReadEvidence | Select-Object eventTimestamp, storageAccountName, accessDirection, requesterUpn, requesterObjectId, requesterAppId, requesterType, authenticationType, operationName, statusText, @{ Name = "uri"; Expression = { Format-OwnerLensUriLink -Uri ([string]$_.uri) } })
}

function Show-OwnerLensBlobDataPlaneEvidenceTable {
  param([object]$Report)

  Write-OwnerLensReportTable `
    -Title "Recent Blob Data-Plane Evidence" `
    -Rows (Get-OwnerLensBlobDataPlaneEvidenceTableRows -BlobReadEvidence (Get-OwnerLensReportArray -Report $Report -Path "azure.blobReadEvidence")) `
    -Property eventTimestamp, storageAccountName, accessDirection, requesterUpn, requesterObjectId, requesterAppId, requesterType, authenticationType, operationName, statusText, uri
}
