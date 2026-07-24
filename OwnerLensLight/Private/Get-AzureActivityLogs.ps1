function Get-AzureActivityLogField {
  param(
    [object]$Entry,
    [string]$PropertyName
  )

  $value = Get-ObjectProperty -Object $Entry -PropertyName $PropertyName
  if ($null -ne $value) {
    return $value
  }

  $properties = Get-ObjectProperty -Object $Entry -PropertyName "properties"
  return Get-ObjectProperty -Object $properties -PropertyName $PropertyName
}

function Get-AzureActivityLogClaim {
  param(
    [object]$Claims,
    [string[]]$ClaimNames
  )

  foreach ($claimName in $ClaimNames) {
    $value = Get-ObjectProperty -Object $Claims -PropertyName $claimName
    if ($null -ne $value -and -not [string]::IsNullOrWhiteSpace([string]$value)) {
      return $value
    }
  }

  return $null
}

function Get-AzureActivityLogs {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]
    [string]$SubscriptionId,

    [Parameter(Mandatory = $true)]
    [datetime]$StartTime,

    [ValidateRange(0, 1000000)]
    [int]$MaxRecord = 5000
  )

  $logs = [System.Collections.Generic.List[object]]::new()
  if ($MaxRecord -le 0) {
    return $logs
  }

  $endTime = Get-Date
  $filter = "eventTimestamp ge '$($StartTime.ToUniversalTime().ToString("o"))' and eventTimestamp le '$($endTime.ToUniversalTime().ToString("o"))'"
  $encodedFilter = [Uri]::EscapeDataString($filter)
  $requestPath = "/subscriptions/$SubscriptionId/providers/microsoft.insights/eventtypes/management/values?api-version=2015-04-01&`$filter=$encodedFilter"

  while ($requestPath -and $logs.Count -lt $MaxRecord) {
    $currentRequestPath = $requestPath
    $response = Invoke-RestRequestWithRetry `
      -OperationName "Azure Monitor activity log request" `
      -Request {
        if ($currentRequestPath -match "^https?://") {
          return Invoke-AzRestMethod -Method GET -Uri $currentRequestPath -ErrorAction Stop
        }

        return Invoke-AzRestMethod -Method GET -Path $currentRequestPath -ErrorAction Stop
      }

    $content = $response.Content | ConvertFrom-Json
    foreach ($entry in @($content.value)) {
      if ($logs.Count -ge $MaxRecord) {
        break
      }

      $operationName = Get-AzureActivityLogField -Entry $entry -PropertyName "operationName"
      $status = Get-AzureActivityLogField -Entry $entry -PropertyName "status"
      $authorization = Get-AzureActivityLogField -Entry $entry -PropertyName "authorization"
      $claims = Get-AzureActivityLogField -Entry $entry -PropertyName "claims"

      $logs.Add([pscustomobject]@{
        eventTimestamp = Get-AzureActivityLogField -Entry $entry -PropertyName "eventTimestamp"
        caller = Get-AzureActivityLogField -Entry $entry -PropertyName "caller"
        callerObjectId = Get-AzureActivityLogClaim -Claims $claims -ClaimNames @("http://schemas.microsoft.com/identity/claims/objectidentifier", "oid", "objectidentifier")
        callerAppId = Get-AzureActivityLogClaim -Claims $claims -ClaimNames @("appid", "azp")
        callerName = Get-AzureActivityLogClaim -Claims $claims -ClaimNames @("name", "http://schemas.xmlsoap.org/ws/2005/05/identity/claims/givenname")
        callerTenantId = Get-AzureActivityLogClaim -Claims $claims -ClaimNames @("http://schemas.microsoft.com/identity/claims/tenantid", "tid")
        operationName = Get-ObjectProperty -Object $operationName -PropertyName "localizedValue"
        operationNameValue = Get-ObjectProperty -Object $operationName -PropertyName "value"
        status = Get-ObjectProperty -Object $status -PropertyName "localizedValue"
        resourceGroupName = Get-AzureActivityLogField -Entry $entry -PropertyName "resourceGroupName"
        resourceId = Get-AzureActivityLogField -Entry $entry -PropertyName "resourceId"
        resourceType = Get-AzureActivityLogField -Entry $entry -PropertyName "resourceType"
        authorizationAction = Get-ObjectProperty -Object $authorization -PropertyName "action"
        authorizationScope = Get-ObjectProperty -Object $authorization -PropertyName "scope"
      }) | Out-Null
    }

    $requestPath = Get-ObjectProperty -Object $content -PropertyName "nextLink"
  }

  return $logs
}
