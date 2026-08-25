function Get-OwnerLensBlobReadsByObjectTableRows {
  param([object[]]$BlobReadObjects)

  @($BlobReadObjects | Select-Object requesterUpn, requesterObjectId, requesterAppId, requesterType, authenticationType, storageAccountName, objectKey, @{ Name = "uri"; Expression = { Format-OwnerLensUriLink -Uri ([string]$_.uri) } }, blobReadCount, firstReadAt, lastReadAt, matchesInspectedServicePrincipal)
}

function Show-OwnerLensBlobReadsByObjectTable {
  param([object]$Report)

  Write-OwnerLensReportTable `
    -Title "Recent Blob Reads By Object" `
    -Rows (Get-OwnerLensBlobReadsByObjectTableRows -BlobReadObjects (Get-OwnerLensReportArray -Report $Report -Path "azure.blobReadObjects")) `
    -Property requesterUpn, requesterObjectId, requesterAppId, requesterType, authenticationType, storageAccountName, objectKey, uri, blobReadCount, firstReadAt, lastReadAt, matchesInspectedServicePrincipal
}
