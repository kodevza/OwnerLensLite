function Convert-LogAnalyticsRows {
  param(
    [object]$Table
  )

  $columns = @($Table.columns | ForEach-Object { [string]$_.name })
  foreach ($row in @($Table.rows)) {
    $record = [ordered]@{}
    for ($index = 0; $index -lt $columns.Count; $index++) {
      $record[$columns[$index]] = $row[$index]
    }

    [pscustomobject]$record
  }
}

function Get-LogAnalyticsAccessToken {
  $token = Get-AzAccessToken -ResourceUrl "https://api.loganalytics.azure.com" -ErrorAction Stop
  if ($token.Token -is [securestring]) {
    return ([pscredential]::new("token", $token.Token)).GetNetworkCredential().Password
  }

  return [string]$token.Token
}

function Invoke-LogAnalyticsQuery {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]
    [string]$WorkspaceId,

    [Parameter(Mandatory = $true)]
    [string]$Query,

    [Parameter(Mandatory = $true)]
    [datetime]$StartTime,

    [Parameter(Mandatory = $true)]
    [datetime]$EndTime
  )

  $accessToken = Get-LogAnalyticsAccessToken
  $headers = @{
    Authorization = "Bearer $accessToken"
    "Content-Type" = "application/json"
  }
  $body = @{
    query = $Query
    timespan = "$($StartTime.ToUniversalTime().ToString("o"))/$($EndTime.ToUniversalTime().ToString("o"))"
  } | ConvertTo-Json -Depth 10

  $response = Invoke-RestRequestWithRetry `
    -OperationName "Log Analytics query" `
    -Request {
      Invoke-RestMethod `
        -Method POST `
        -Uri "https://api.loganalytics.azure.com/v1/workspaces/$WorkspaceId/query" `
        -Headers $headers `
        -Body $body `
        -ErrorAction Stop
    }

  $primaryResult = @($response.tables | Where-Object name -eq "PrimaryResult" | Select-Object -First 1)
  if (-not $primaryResult) {
    return @()
  }

  return @(Convert-LogAnalyticsRows -Table $primaryResult)
}

function Get-AzureStorageAccountsForScope {
  param(
    [string]$Scope,
    [object[]]$Resources
  )

  $scopeParts = Get-AzureScopeParts -Scope $Scope
  foreach ($resource in @($Resources)) {
    $resourceType = [string]$resource.ResourceType
    if (-not $resourceType.Equals("Microsoft.Storage/storageAccounts", [System.StringComparison]::OrdinalIgnoreCase)) {
      continue
    }

    $resourceId = [string]$resource.ResourceId
    if ([string]::IsNullOrWhiteSpace($resourceId)) {
      continue
    }

    if ($scopeParts.scopeType -eq "Subscription") {
      $resource
      continue
    }

    if ($scopeParts.scopeType -eq "ResourceGroup") {
      if ([string]$resource.ResourceGroupName -eq [string]$scopeParts.resourceGroup) {
        $resource
      }
      continue
    }

    if ($scopeParts.scopeType -eq "Resource" -and (
        $resourceId.Equals([string]$Scope, [System.StringComparison]::OrdinalIgnoreCase) -or
        ([string]$Scope).StartsWith("$resourceId/", [System.StringComparison]::OrdinalIgnoreCase))) {
      $resource
    }
  }
}

function New-KqlStringLiteral {
  param([string]$Value)

  return "'$(([string]$Value).Replace("'", "''"))'"
}

function New-KqlDynamicStringArray {
  param([string[]]$Values)

  $items = @($Values | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object -Unique | ForEach-Object {
      New-KqlStringLiteral -Value $_
    })

  return "dynamic([$($items -join ",")])"
}

function Get-StorageBlobAccessDirection {
  param([string]$OperationName)

  switch -Regex ([string]$OperationName) {
    "^(GetBlob|GetBlobProperties|GetBlobMetadata)$" { return "Read" }
    "^(PutBlob|PutBlock|PutBlockList|AppendBlock|CopyBlob|SetBlobMetadata|SetBlobProperties)$" { return "Publish" }
    default { return "Other" }
  }
}

function Get-StorageBlobParticipantType {
  param(
    [string]$RequesterAppId,
    [string]$RequesterUpn
  )

  $hasApp = -not [string]::IsNullOrWhiteSpace($RequesterAppId)
  $hasUser = -not [string]::IsNullOrWhiteSpace($RequesterUpn)

  if ($hasApp -and $hasUser) {
    return "UserAndServicePrincipal"
  }

  if ($hasApp) {
    return "ServicePrincipal"
  }

  if ($hasUser) {
    return "User"
  }

  return "Unknown"
}

function Test-StorageBlobRequesterMatchesServicePrincipal {
  param(
    [object]$BlobAccess,
    [object]$ServicePrincipal
  )

  $objectId = [string]$ServicePrincipal.objectId
  $appId = [string]$ServicePrincipal.appId

  $requesterObjectId = [string]$BlobAccess.requesterObjectId
  $requesterAppId = [string]$BlobAccess.requesterAppId

  if ($objectId -and $requesterObjectId -and $requesterObjectId.Equals($objectId, [System.StringComparison]::OrdinalIgnoreCase)) {
    return $true
  }

  if ($appId -and $requesterAppId -and $requesterAppId.Equals($appId, [System.StringComparison]::OrdinalIgnoreCase)) {
    return $true
  }

  return $false
}

function Get-StorageBlobReadLogs {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]
    [string]$WorkspaceId,

    [Parameter(Mandatory = $true)]
    [object[]]$StorageAccounts,

    [object]$ServicePrincipal = $null,

    [Parameter(Mandatory = $true)]
    [datetime]$StartTime,

    [ValidateRange(1, 1000000)]
    [int]$MaxRecord = 5000,

    [string[]]$BlobReadOperationNames = @("GetBlob", "PutBlob", "PutBlock", "PutBlockList", "AppendBlock", "CopyBlob")
  )

  $accounts = @($StorageAccounts | Where-Object {
      -not [string]::IsNullOrWhiteSpace([string]$_.Name)
    } | Sort-Object Name -Unique)

  if ($accounts.Count -eq 0) {
    return @()
  }

  $accountNames = @($accounts | ForEach-Object { [string]$_.Name })
  $accountResourceIds = @($accounts | ForEach-Object { [string]$_.ResourceId })
  $query = @"
let targetAccounts = $(New-KqlDynamicStringArray -Values $accountNames);
let targetResourceIds = $(New-KqlDynamicStringArray -Values $accountResourceIds);
let readOperations = $(New-KqlDynamicStringArray -Values $BlobReadOperationNames);
StorageBlobLogs
| where AccountName in~ (targetAccounts) or _ResourceId in~ (targetResourceIds)
| where OperationName in~ (readOperations)
| extend RequesterObjectId = tostring(column_ifexists("RequesterObjectId", "")),
         RequesterAppId = tostring(column_ifexists("RequesterAppId", "")),
         RequesterTenantId = tostring(column_ifexists("RequesterTenantId", "")),
         RequesterUpn = tostring(column_ifexists("RequesterUpn", "")),
         UserAgentHeader = tostring(column_ifexists("UserAgentHeader", ""))
| project TimeGenerated, AccountName, OperationName, StatusCode, StatusText, AuthenticationType, RequesterObjectId, RequesterAppId, RequesterTenantId, RequesterUpn, CallerIpAddress, UserAgentHeader, Uri, ObjectKey, _ResourceId
| order by TimeGenerated desc
| take $MaxRecord
"@

  $rows = @(Invoke-LogAnalyticsQuery `
      -WorkspaceId $WorkspaceId `
      -Query $query `
      -StartTime $StartTime `
      -EndTime (Get-Date))

  foreach ($row in $rows) {
    [pscustomobject]@{
      eventTimestamp = [string]$row.TimeGenerated
      storageAccountName = [string]$row.AccountName
      storageAccountResourceId = [string]$row._ResourceId
      operationName = [string]$row.OperationName
      statusCode = [string]$row.StatusCode
      statusText = [string]$row.StatusText
      accessDirection = Get-StorageBlobAccessDirection -OperationName ([string]$row.OperationName)
      authenticationType = [string]$row.AuthenticationType
      requesterObjectId = [string]$row.RequesterObjectId
      requesterAppId = [string]$row.RequesterAppId
      requesterTenantId = [string]$row.RequesterTenantId
      requesterUpn = [string]$row.RequesterUpn
      requesterType = Get-StorageBlobParticipantType -RequesterAppId ([string]$row.RequesterAppId) -RequesterUpn ([string]$row.RequesterUpn)
      callerIpAddress = [string]$row.CallerIpAddress
      userAgentHeader = [string]$row.UserAgentHeader
      uri = [string]$row.Uri
      objectKey = [string]$row.ObjectKey
      matchesInspectedServicePrincipal = if ($ServicePrincipal) {
        [bool](Test-StorageBlobRequesterMatchesServicePrincipal -BlobAccess ([pscustomobject]@{
              requesterObjectId = [string]$row.RequesterObjectId
              requesterAppId = [string]$row.RequesterAppId
            }) -ServicePrincipal $ServicePrincipal)
      } else {
        $false
      }
      evidenceConfidence = "medium"
      evidenceReason = "StorageBlobLogs show a blob data-plane operation recorded by Azure Storage diagnostic logs. Publish operations can represent data sent to an agent; read operations can represent data consumed from it."
    }
  }
}

function Get-StorageBlobReadCallers {
  param(
    [object[]]$BlobReadEvidence
  )

  $groups = @($BlobReadEvidence) | Group-Object -Property {
    $requesterObjectId = [string]$_.requesterObjectId
    $requesterAppId = [string]$_.requesterAppId
    $requesterUpn = [string]$_.requesterUpn

    $keyParts = @()
    if (-not [string]::IsNullOrWhiteSpace($requesterObjectId)) {
      $keyParts += "object:$requesterObjectId"
    }

    if (-not [string]::IsNullOrWhiteSpace($requesterAppId)) {
      $keyParts += "app:$requesterAppId"
    }

    if (-not [string]::IsNullOrWhiteSpace($requesterUpn)) {
      $keyParts += "upn:$requesterUpn"
    }

    if ($keyParts.Count -gt 0) {
      return ($keyParts -join "|")
    }

    return "unknown"
  }

  foreach ($group in $groups) {
    $items = @($group.Group | Sort-Object eventTimestamp)
    $first = $items | Select-Object -First 1
    $last = $items | Select-Object -Last 1
    $publishCount = @($items | Where-Object accessDirection -eq "Publish").Count
    $readCount = @($items | Where-Object accessDirection -eq "Read").Count

    [pscustomobject]@{
      requesterKey = [string]$group.Name
      requesterObjectId = [string]$last.requesterObjectId
      requesterAppId = [string]$last.requesterAppId
      requesterTenantId = [string]$last.requesterTenantId
      requesterUpn = [string]$last.requesterUpn
      requesterType = [string]$last.requesterType
      authenticationType = [string]$last.authenticationType
      readCount = [int]$items.Count
      blobAccessCount = [int]$items.Count
      blobReadCount = [int]$readCount
      blobPublishCount = [int]$publishCount
      firstSeen = [string]$first.eventTimestamp
      lastSeen = [string]$last.eventTimestamp
      storageAccounts = @($items | Select-Object -ExpandProperty storageAccountName -Unique | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
      accessDirections = @($items | Select-Object -ExpandProperty accessDirection -Unique | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
      operationNames = @($items | Select-Object -ExpandProperty operationName -Unique | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
      callerIpAddresses = @($items | Select-Object -ExpandProperty callerIpAddress -Unique | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
      userAgentHeaders = @($items | Select-Object -ExpandProperty userAgentHeader -Unique | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -First 10)
      sampleUris = @($items | Select-Object -ExpandProperty uri -Unique | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -First 10)
      matchesInspectedServicePrincipal = [bool](@($items | Where-Object matchesInspectedServicePrincipal).Count -gt 0)
      evidenceConfidence = "medium"
      evidenceReason = "Requester has one or more StorageBlobLogs data-plane records in the selected time window, grouped with both user and service principal identifiers when Azure logged both."
    }
  }
}
