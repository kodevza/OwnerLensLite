function Get-GraphDependencies {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]
    [object]$ServicePrincipal,

    [string]$SignInUser = "",

    [datetime]$SignInStartTime = (Get-Date).AddDays(-30),

    [ValidateRange(1, 1000000)]
    [int]$MaxUserSignInRecords = 5000
  )

  $servicePrincipalId = [string]$ServicePrincipal.objectId
  $applicationObjectId = [string]$ServicePrincipal.applicationObjectId
  $resourcePrincipalIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

  $owners = Invoke-GraphPagedRequest `
    -OperationName "Microsoft Graph service principal owners request" `
    -Uri "/v1.0/servicePrincipals/$servicePrincipalId/owners?`$select=id,displayName,userPrincipalName,mail&`$top=999"

  $applicationOwners = @()
  if (-not [string]::IsNullOrWhiteSpace($applicationObjectId)) {
    $applicationOwners = Invoke-GraphPagedRequest `
      -OperationName "Microsoft Graph application owners request" `
      -Uri "/v1.0/applications/$applicationObjectId/owners?`$select=id,displayName,userPrincipalName,mail&`$top=999"
  }

  $appRoleAssignments = Invoke-GraphPagedRequest `
    -OperationName "Microsoft Graph service principal app role assignments request" `
    -Uri "/v1.0/servicePrincipals/$servicePrincipalId/appRoleAssignments?`$select=id,appRoleId,principalId,principalDisplayName,resourceId,resourceDisplayName,createdDateTime&`$top=999"

  foreach ($assignment in @($appRoleAssignments)) {
    if (-not [string]::IsNullOrWhiteSpace([string]$assignment.resourceId)) {
      $resourcePrincipalIds.Add([string]$assignment.resourceId) | Out-Null
    }
  }

  $oauth2PermissionGrants = Invoke-GraphPagedRequest `
    -OperationName "Microsoft Graph service principal delegated permission grants request" `
    -Uri "/v1.0/oauth2PermissionGrants?`$filter=clientId eq '$servicePrincipalId'&`$select=id,clientId,consentType,principalId,resourceId,scope&`$top=999"

  foreach ($grant in @($oauth2PermissionGrants)) {
    if (-not [string]::IsNullOrWhiteSpace([string]$grant.resourceId)) {
      $resourcePrincipalIds.Add([string]$grant.resourceId) | Out-Null
    }
  }

  $memberOf = Invoke-GraphPagedRequest `
    -OperationName "Microsoft Graph service principal group membership request" `
    -Uri "/v1.0/servicePrincipals/$servicePrincipalId/memberOf?`$select=id,displayName,description&`$top=999"

  $resourcePrincipals = @()
  foreach ($resourcePrincipalId in @($resourcePrincipalIds)) {
    try {
      $resourcePrincipal = Invoke-RestRequestWithRetry `
        -OperationName "Microsoft Graph resource service principal lookup" `
        -Request {
          return Invoke-MgGraphRequest -Method GET -Uri "/v1.0/servicePrincipals/$resourcePrincipalId?`$select=id,appId,displayName,appDisplayName,servicePrincipalType,publisherName" -OutputType PSObject -ErrorAction Stop
        }

      $resourcePrincipals += [pscustomobject]@{
        objectId = [string]$resourcePrincipal.id
        appId = [string]$resourcePrincipal.appId
        displayName = [string]$resourcePrincipal.displayName
        appDisplayName = [string]$resourcePrincipal.appDisplayName
        servicePrincipalType = [string]$resourcePrincipal.servicePrincipalType
        publisherName = [string]$resourcePrincipal.publisherName
      }
    } catch {
      $resourcePrincipals += [pscustomobject]@{
        objectId = [string]$resourcePrincipalId
        appId = $null
        displayName = $null
        appDisplayName = $null
        servicePrincipalType = $null
        publisherName = $null
        lookupError = $_.Exception.Message
      }
    }
  }

  $userSignIns = @()
  if (-not [string]::IsNullOrWhiteSpace($SignInUser)) {
    $escapedSignInUser = ([string]$SignInUser).Replace("'", "''")
    $signInStartTimeText = $SignInStartTime.ToUniversalTime().ToString("o")
    $userFilterProperty = if ($SignInUser -match "@") { "userPrincipalName" } else { "userId" }
    $signInFilter = "createdDateTime ge $signInStartTimeText and $userFilterProperty eq '$escapedSignInUser'"
    $encodedSignInFilter = [System.Uri]::EscapeDataString($signInFilter)
    $userSignIns = @(Invoke-GraphPagedRequest `
        -OperationName "Microsoft Graph user sign-ins request" `
        -Uri "/v1.0/auditLogs/signIns?`$filter=$encodedSignInFilter&`$top=999")

    $userSignIns = @($userSignIns | Select-Object -First $MaxUserSignInRecords)
  }

  return [pscustomobject]@{
    owners = @(
      $owners | ForEach-Object {
        [pscustomobject]@{
          objectId = [string]$_.id
          displayName = [string]$_.displayName
          userPrincipalName = [string]$_.userPrincipalName
          mail = [string]$_.mail
          objectType = [string](Get-ObjectProperty -Object $_ -PropertyName "@odata.type")
          ownerSource = "ServicePrincipal"
        }
      }
      $applicationOwners | ForEach-Object {
        [pscustomobject]@{
          objectId = [string]$_.id
          displayName = [string]$_.displayName
          userPrincipalName = [string]$_.userPrincipalName
          mail = [string]$_.mail
          objectType = [string](Get-ObjectProperty -Object $_ -PropertyName "@odata.type")
          ownerSource = "Application"
        }
      }
    )
    appRoleAssignments = @($appRoleAssignments | ForEach-Object {
      [pscustomobject]@{
        id = [string]$_.id
        appRoleId = [string]$_.appRoleId
        principalId = [string]$_.principalId
        principalDisplayName = [string]$_.principalDisplayName
        resourceId = [string]$_.resourceId
        resourceDisplayName = [string]$_.resourceDisplayName
        createdDateTime = [string]$_.createdDateTime
      }
    })
    oauth2PermissionGrants = @($oauth2PermissionGrants | ForEach-Object {
      [pscustomobject]@{
        id = [string]$_.id
        clientId = [string]$_.clientId
        consentType = [string]$_.consentType
        principalId = [string]$_.principalId
        resourceId = [string]$_.resourceId
        scope = [string]$_.scope
      }
    })
    memberOf = @($memberOf | ForEach-Object {
      [pscustomobject]@{
        objectId = [string]$_.id
        displayName = [string]$_.displayName
        description = [string]$_.description
        objectType = [string](Get-ObjectProperty -Object $_ -PropertyName "@odata.type")
      }
    })
    resourceServicePrincipals = @($resourcePrincipals | Sort-Object displayName, objectId)
    userSignIns = @($userSignIns | ForEach-Object {
      [pscustomobject]@{
        id = [string]$_.id
        createdDateTime = [string]$_.createdDateTime
        userId = [string]$_.userId
        userPrincipalName = [string]$_.userPrincipalName
        userDisplayName = [string]$_.userDisplayName
        appId = [string]$_.appId
        appDisplayName = [string]$_.appDisplayName
        ipAddress = [string]$_.ipAddress
        locationCity = [string](Get-ObjectProperty -Object $_.location -PropertyName "city")
        locationState = [string](Get-ObjectProperty -Object $_.location -PropertyName "state")
        locationCountryOrRegion = [string](Get-ObjectProperty -Object $_.location -PropertyName "countryOrRegion")
        clientAppUsed = [string]$_.clientAppUsed
        conditionalAccessStatus = [string]$_.conditionalAccessStatus
        statusErrorCode = [string](Get-ObjectProperty -Object $_.status -PropertyName "errorCode")
        statusFailureReason = [string](Get-ObjectProperty -Object $_.status -PropertyName "failureReason")
        resourceDisplayName = [string]$_.resourceDisplayName
        resourceId = [string]$_.resourceId
        correlationId = [string]$_.correlationId
      }
    } | Sort-Object createdDateTime -Descending)
  }
}
