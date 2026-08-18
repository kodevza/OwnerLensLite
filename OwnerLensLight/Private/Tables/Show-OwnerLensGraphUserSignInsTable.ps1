function Get-OwnerLensGraphUserSignInsTableRows {
  param([object[]]$UserSignIns)

  @($UserSignIns | Select-Object createdDateTime, userPrincipalName, appDisplayName, ipAddress, locationCountryOrRegion, locationState, locationCity, clientAppUsed, conditionalAccessStatus, statusErrorCode, statusFailureReason, resourceDisplayName)
}

function Show-OwnerLensGraphUserSignInsTable {
  param([object]$Report)

  if ($Report.graph.userSignIns.Count -eq 0) {
    return
  }

  Write-RichRule "Microsoft Graph User Sign-Ins" -Style "cyan"
  Get-OwnerLensGraphUserSignInsTableRows -UserSignIns @($Report.graph.userSignIns) |
    Write-RichTable -Property createdDateTime, userPrincipalName, appDisplayName, ipAddress, locationCountryOrRegion, locationState, locationCity, clientAppUsed, conditionalAccessStatus, statusErrorCode, statusFailureReason, resourceDisplayName -Box Square
}
