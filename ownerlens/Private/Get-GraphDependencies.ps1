function Get-GraphDependencies {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]
    [object]$ServicePrincipal
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
  }
}
