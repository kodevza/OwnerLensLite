function Get-OwnerLensAzureActivityEvidenceTableRows {
  param([object[]]$ActivityEvidence)

  @($ActivityEvidence | Select-Object eventTimestamp, subscriptionName, operationNameValue, @{ Name = "resourceId"; Expression = { Format-OwnerLensAzureResourceId -ResourceId ([string]$_.resourceId) } }, status)
}

function Show-OwnerLensAzureActivityEvidenceTable {
  param([object]$Report)

  Write-OwnerLensReportTable `
    -Title "Recent Azure Activity Evidence" `
    -Rows (Get-OwnerLensAzureActivityEvidenceTableRows -ActivityEvidence (Get-OwnerLensReportArray -Report $Report -Path "azure.activityEvidence")) `
    -Property eventTimestamp, subscriptionName, operationNameValue, resourceId, status
}
