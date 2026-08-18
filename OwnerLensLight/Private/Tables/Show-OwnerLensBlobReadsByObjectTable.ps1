function Get-OwnerLensBlobReadsByObjectTableRows {
  param([object[]]$BlobReadObjects)

  @($BlobReadObjects | Select-Object requesterUpn, requesterObjectId, requesterAppId, requesterType, authenticationType, storageAccountName, objectKey, @{ Name = "uri"; Expression = { Format-OwnerLensUriLink -Uri ([string]$_.uri) } }, blobReadCount, firstReadAt, lastReadAt, matchesInspectedServicePrincipal)
}

function Show-OwnerLensBlobReadsByObjectTable {
  param([object]$Report)

  if ($Report.azure.blobReadObjects.Count -eq 0) {
    return
  }

  Write-RichRule "Recent Blob Reads By Object" -Style "cyan"
  Get-OwnerLensBlobReadsByObjectTableRows -BlobReadObjects @($Report.azure.blobReadObjects) |
    Write-RichTable -Property requesterUpn, requesterObjectId, requesterAppId, requesterType, authenticationType, storageAccountName, objectKey, uri, blobReadCount, firstReadAt, lastReadAt, matchesInspectedServicePrincipal -Box Square
}
