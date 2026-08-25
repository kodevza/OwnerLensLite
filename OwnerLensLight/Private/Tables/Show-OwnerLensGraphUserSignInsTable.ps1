function Get-OwnerLensGraphUserSignInsTableRows {
  param([object[]]$UserSignIns)

  @($UserSignIns | Select-Object createdDateTime, userPrincipalName, appDisplayName, ipAddress, locationCountryOrRegion, locationState, locationCity, clientAppUsed, conditionalAccessStatus, statusErrorCode, statusFailureReason, resourceDisplayName)
}

function Show-OwnerLensGraphUserSignInsTable {
  param([object]$Report)

  Write-OwnerLensReportTable `
    -Title "Microsoft Graph User Sign-Ins" `
    -Rows (Get-OwnerLensGraphUserSignInsTableRows -UserSignIns (Get-OwnerLensReportArray -Report $Report -Path "graph.userSignIns")) `
    -Property createdDateTime, userPrincipalName, appDisplayName, ipAddress, locationCountryOrRegion, locationState, locationCity, clientAppUsed, conditionalAccessStatus, statusErrorCode, statusFailureReason, resourceDisplayName
}
