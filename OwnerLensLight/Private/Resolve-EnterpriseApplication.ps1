function ConvertTo-ODataStringLiteral {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Value
  )

  return $Value.Replace("'", "''")
}

function Resolve-EnterpriseApplication {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$EnterpriseApplication
  )

  $select = "id,appId,displayName,appDisplayName,servicePrincipalType,publisherName,accountEnabled,appOwnerOrganizationId,homepage,loginUrl,replyUrls,servicePrincipalNames,tags"
  $matches = @()
  $parsedGuid = [guid]::Empty
  $isGuid = [guid]::TryParse($EnterpriseApplication, [ref]$parsedGuid)

  if ($isGuid) {
    try {
      $objectIdCandidate = Invoke-RestRequestWithRetry `
        -OperationName "Microsoft Graph service principal object lookup" `
        -Request {
          return Invoke-MgGraphRequest -Method GET -Uri "/v1.0/servicePrincipals/$($EnterpriseApplication)?`$select=$select" -OutputType PSObject -ErrorAction Stop
        }

      if ($objectIdCandidate) {
        $matches += $objectIdCandidate
      }
    } catch {
      if ($_.Exception.Message -notmatch "404|Request_ResourceNotFound|Resource .* does not exist") {
        throw
      }
    }

    $appIdLiteral = ConvertTo-ODataStringLiteral -Value $EnterpriseApplication
    $matches += @(Invoke-GraphPagedRequest `
      -OperationName "Microsoft Graph service principal appId lookup" `
      -Uri "/v1.0/servicePrincipals?`$filter=appId eq '$appIdLiteral'&`$select=$select&`$top=25")
  } else {
    $displayNameLiteral = ConvertTo-ODataStringLiteral -Value $EnterpriseApplication
    $matches = Invoke-GraphPagedRequest `
      -OperationName "Microsoft Graph service principal display name lookup" `
      -Uri "/v1.0/servicePrincipals?`$filter=displayName eq '$displayNameLiteral'&`$select=$select&`$top=25"
  }

  $uniqueMatches = @($matches |
    Where-Object { $_ -and -not [string]::IsNullOrWhiteSpace([string]$_.id) } |
    Sort-Object id -Unique)

  if ($uniqueMatches.Count -eq 0) {
    throw "Enterprise application was not found in Microsoft Graph: $EnterpriseApplication"
  }

  if ($uniqueMatches.Count -gt 1) {
    $choices = @($uniqueMatches | ForEach-Object { "$($_.displayName) (objectId=$($_.id), appId=$($_.appId))" })
    throw "Enterprise application lookup matched multiple service principals. Retry with objectId or appId. Matches: $($choices -join '; ')"
  }

  $sp = $uniqueMatches[0]
  $applicationObjectId = $null
  if (-not [string]::IsNullOrWhiteSpace([string]$sp.appId)) {
    try {
      $appIdLiteral = ConvertTo-ODataStringLiteral -Value ([string]$sp.appId)
      $applicationMatches = @(Invoke-GraphPagedRequest `
        -OperationName "Microsoft Graph application object lookup" `
        -Uri "/v1.0/applications?`$filter=appId eq '$appIdLiteral'&`$select=id,appId,displayName&`$top=2")

      if ($applicationMatches.Count -eq 1) {
        $applicationObjectId = [string]$applicationMatches[0].id
      }
    } catch {
      $applicationObjectId = $null
    }
  }

  return [pscustomobject]@{
    objectId = [string]$sp.id
    applicationObjectId = $applicationObjectId
    appId = [string]$sp.appId
    displayName = [string]$sp.displayName
    appDisplayName = [string]$sp.appDisplayName
    servicePrincipalType = [string]$sp.servicePrincipalType
    publisherName = [string]$sp.publisherName
    accountEnabled = $sp.accountEnabled
    appOwnerOrganizationId = [string]$sp.appOwnerOrganizationId
    homepage = [string]$sp.homepage
    loginUrl = [string]$sp.loginUrl
    replyUrls = @($sp.replyUrls)
    servicePrincipalNames = @($sp.servicePrincipalNames)
    tags = @($sp.tags)
  }
}
