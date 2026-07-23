BeforeAll {
  . (Join-Path $PSScriptRoot "../ownerlens/Private/Get-AzureDependencies.ps1")
}

Describe "OwnerLens Light Azure helper logic" {
  It "matches activity logs by service principal object id, app id, or display name" {
    $servicePrincipal = [pscustomobject]@{
      objectId = "sp-object-id"
      appId = "app-client-id"
      displayName = "Automation API"
    }

    (Test-ActivityLogMatchesServicePrincipal `
      -ServicePrincipal $servicePrincipal `
      -Log ([pscustomobject]@{ callerObjectId = "SP-OBJECT-ID" })) | Should -BeTrue

    (Test-ActivityLogMatchesServicePrincipal `
      -ServicePrincipal $servicePrincipal `
      -Log ([pscustomobject]@{ callerAppId = "APP-CLIENT-ID" })) | Should -BeTrue

    (Test-ActivityLogMatchesServicePrincipal `
      -ServicePrincipal $servicePrincipal `
      -Log ([pscustomobject]@{ callerName = "Automation API" })) | Should -BeTrue

    (Test-ActivityLogMatchesServicePrincipal `
      -ServicePrincipal $servicePrincipal `
      -Log ([pscustomobject]@{ callerObjectId = "other" })) | Should -BeFalse
  }

  It "classifies Azure scopes" {
    (Get-AzureScopeParts -Scope "/subscriptions/sub-1").scopeType | Should -Be "Subscription"

    $resourceGroupScope = Get-AzureScopeParts -Scope "/subscriptions/sub-1/resourceGroups/rg-1"
    $resourceGroupScope.scopeType | Should -Be "ResourceGroup"
    $resourceGroupScope.resourceGroup | Should -Be "rg-1"

    $resourceScope = Get-AzureScopeParts -Scope "/subscriptions/sub-1/resourceGroups/rg-1/providers/Microsoft.Web/sites/app-1"
    $resourceScope.scopeType | Should -Be "Resource"
    $resourceScope.resourceId | Should -Be "/subscriptions/sub-1/resourceGroups/rg-1/providers/Microsoft.Web/sites/app-1"
  }
}
