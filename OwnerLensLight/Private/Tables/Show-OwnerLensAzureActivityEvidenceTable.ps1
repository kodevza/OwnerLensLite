function Get-OwnerLensAzureActivityEvidenceTableRows {
  param([object[]]$ActivityEvidence)

  @($ActivityEvidence | Select-Object eventTimestamp, subscriptionName, operationNameValue, @{ Name = "resourceId"; Expression = { Format-OwnerLensAzureResourceId -ResourceId ([string]$_.resourceId) } }, status)
}

function Show-OwnerLensAzureActivityEvidenceTable {
  param([object]$Report)

  if ($Report.azure.activityEvidence.Count -eq 0) {
    return
  }

  Write-RichRule "Recent Azure Activity Evidence" -Style "cyan"
  Get-OwnerLensAzureActivityEvidenceTableRows -ActivityEvidence @($Report.azure.activityEvidence) |
    Write-RichTable -Property eventTimestamp, subscriptionName, operationNameValue, resourceId, status -Box Square
}
