function Get-OwnerLensUserSignInLocationRows {
  param([object[]]$UserSignIns)

  return @($UserSignIns | Group-Object {
      $countryOrRegion = Get-OwnerLensDisplayValue -Value $_.locationCountryOrRegion -Fallback "unknown country"
      $city = Get-OwnerLensDisplayValue -Value $_.locationCity -Fallback "unknown city"
      $state = Get-OwnerLensDisplayValue -Value $_.locationState -Fallback "unknown state"
      $ipAddress = Get-OwnerLensDisplayValue -Value $_.ipAddress -Fallback "unknown ip"
      return "$countryOrRegion|$state|$city|$ipAddress"
    } | ForEach-Object {
      $items = @($_.Group | Sort-Object createdDateTime)
      $first = $items | Select-Object -First 1
      $last = $items | Select-Object -Last 1
      [pscustomobject]@{
        countryOrRegion = Get-OwnerLensDisplayValue -Value $first.locationCountryOrRegion -Fallback "unknown country"
        state = Get-OwnerLensDisplayValue -Value $first.locationState -Fallback "unknown state"
        city = Get-OwnerLensDisplayValue -Value $first.locationCity -Fallback "unknown city"
        ipAddress = Get-OwnerLensDisplayValue -Value $first.ipAddress -Fallback "unknown ip"
        signInCount = $items.Count
        firstSeen = [string]$first.createdDateTime
        lastSeen = [string]$last.createdDateTime
      }
    } | Sort-Object @{ Expression = "signInCount"; Descending = $true }, countryOrRegion, state, city, ipAddress)
}

function Get-OwnerLensGraphUserSignInLocationsTableRows {
  param([object[]]$UserSignIns)

  @(Get-OwnerLensUserSignInLocationRows -UserSignIns $UserSignIns)
}

function Show-OwnerLensGraphUserSignInLocationsTable {
  param([object]$Report)

  Write-OwnerLensReportTable `
    -Title "Microsoft Graph User Sign-In Locations" `
    -Rows (Get-OwnerLensGraphUserSignInLocationsTableRows -UserSignIns (Get-OwnerLensReportArray -Report $Report -Path "graph.userSignIns")) `
    -Property countryOrRegion, state, city, ipAddress, signInCount, firstSeen, lastSeen
}
