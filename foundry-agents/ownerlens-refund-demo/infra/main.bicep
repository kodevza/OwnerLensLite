extension microsoftGraphV1

targetScope = 'resourceGroup'

@description('Short prefix used in all resource and Entra application names.')
param prefix string = 'olrefund'

@description('Azure region. Flex Consumption support varies by region.')
param location string = resourceGroup().location

@description('Object ID of the explicit human owner for Payment Service. deploy.sh defaults this to the signed-in Azure user.')
param paymentOwnerObjectId string

var suffix = uniqueString(subscription().subscriptionId, resourceGroup().id, prefix)
var billingFunctionName = toLower('${prefix}-billing-${suffix}')
var paymentFunctionName = toLower('${prefix}-payment-${suffix}')
var billingPlanName = '${prefix}-billing-fc-${suffix}'
var paymentPlanName = '${prefix}-payment-fc-${suffix}'
var storageName = take(toLower(replace('${prefix}${suffix}st', '-', '')), 24)
var logName = '${prefix}-logs-${suffix}'
var insightsName = '${prefix}-appi-${suffix}'
var billingCallerIdentityName = '${prefix}-billing-caller-${suffix}'

var billingApiDisplayName = '${prefix} Billing API'
var paymentApiDisplayName = '${prefix} Payment API'
var agentDisplayName = '${prefix} Refund Agent'

// Tenant-scoped identifiers comply with Entra tenants that disallow arbitrary
// api://<host> identifier URIs (including the default tenant policy).
var billingApiIdentifierUri = 'api://${tenant().tenantId}/${billingFunctionName}'
var paymentApiIdentifierUri = 'api://${tenant().tenantId}/${paymentFunctionName}'

// Stable role IDs make the permission graph deterministic across redeployments.
var refundRequestRoleId = '3bd51af5-1af2-4a62-8aae-3edb4cbe841e'
var refundExecuteRoleId = 'd796889e-c303-48ab-b137-752994f271a7'
var chargeRequestRoleId = 'f4d1ac8b-53da-4d91-91b4-cf02f5f8a6e5'
var chargeExecuteRoleId = '8cb01170-73e7-478e-8738-324a252c1b34'

var storageBlobDataOwnerRoleId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'b7e6dc6d-f1e8-4753-8033-0f276bb0955b')
var storageQueueDataContributorRoleId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '974c5e8b-45b9-4653-ba55-5f855dd0fb88')
var storageTableDataContributorRoleId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '0a9a7e1f-b9d0-4cc4-a60d-0319b160aaa3')

// -----------------------------------------------------------------------------
// Entra applications + service principals
// -----------------------------------------------------------------------------

resource billingApiApp 'Microsoft.Graph/applications@v1.0' = {
  displayName: billingApiDisplayName
  uniqueName: '${prefix}-billing-api-${suffix}'
  description: 'OwnerLens demo billing API. Technical service context exists; explicit human owner intentionally absent.'
  signInAudience: 'AzureADMyOrg'
  identifierUris: [
    billingApiIdentifierUri
  ]
  appRoles: [
    {
      allowedMemberTypes: [
        'Application'
      ]
      description: 'Allows a workload identity to request a billing adjustment and refund.'
      displayName: 'Request refunds'
      id: refundRequestRoleId
      isEnabled: true
      value: 'Refund.Request'
    }
    {
      allowedMemberTypes: [
        'Application'
      ]
      description: 'Allows a workload identity to create a billing debit request and initiate a charge.'
      displayName: 'Create BDRs'
      id: chargeRequestRoleId
      isEnabled: true
      value: 'Charge.Request'
    }
  ]
  tags: [
    'OwnerLensDemo'
    'Service:Billing'
    'TechnicalTeam:BillingPlatform'
    'Ownership:MissingHumanOwner'
  ]
}

resource billingApiSp 'Microsoft.Graph/servicePrincipals@v1.0' = {
  appId: billingApiApp.appId
  accountEnabled: true
  appRoleAssignmentRequired: true
  tags: [
    'OwnerLensDemo'
    'Service:Billing'
    'TechnicalTeam:BillingPlatform'
  ]
}

resource paymentApiApp 'Microsoft.Graph/applications@v1.0' = {
  displayName: paymentApiDisplayName
  uniqueName: '${prefix}-payment-api-${suffix}'
  description: 'OwnerLens demo payment API. This is the real-money boundary and intentionally has the only explicit human owner.'
  signInAudience: 'AzureADMyOrg'
  identifierUris: [
    paymentApiIdentifierUri
  ]
  appRoles: [
    {
      allowedMemberTypes: [
        'Application'
      ]
      description: 'Allows a workload identity to execute a real-money refund.'
      displayName: 'Execute refunds'
      id: refundExecuteRoleId
      isEnabled: true
      value: 'Refund.Execute'
    }
    {
      allowedMemberTypes: [
        'Application'
      ]
      description: 'Allows a workload identity to execute a real-money charge.'
      displayName: 'Execute charges'
      id: chargeExecuteRoleId
      isEnabled: true
      value: 'Charge.Execute'
    }
  ]
  owners: {
    relationshipSemantics: 'replace'
    relationships: [
      paymentOwnerObjectId
    ]
  }
  tags: [
    'OwnerLensDemo'
    'Service:Payment'
    'Criticality:Financial'
    'Ownership:Explicit'
  ]
}

resource paymentApiSp 'Microsoft.Graph/servicePrincipals@v1.0' = {
  appId: paymentApiApp.appId
  accountEnabled: true
  appRoleAssignmentRequired: true
  owners: {
    relationshipSemantics: 'replace'
    relationships: [
      paymentOwnerObjectId
    ]
  }
  tags: [
    'OwnerLensDemo'
    'Service:Payment'
    'Criticality:Financial'
  ]
}

resource agentApp 'Microsoft.Graph/applications@v1.0' = {
  displayName: agentDisplayName
  uniqueName: '${prefix}-refund-agent-${suffix}'
  description: 'OwnerLens demo chatbot/agent. No explicit human owner by design; only technical/service context.'
  signInAudience: 'AzureADMyOrg'
  requiredResourceAccess: [
    {
      resourceAppId: billingApiApp.appId
      resourceAccess: [
        {
          id: refundRequestRoleId
          type: 'Role'
        }
        {
          id: chargeRequestRoleId
          type: 'Role'
        }
      ]
    }
  ]
  tags: [
    'OwnerLensDemo'
    'WorkloadType:Agent'
    'TechnicalTeam:AIPlatform'
    'Ownership:MissingHumanOwner'
  ]
}

resource agentSp 'Microsoft.Graph/servicePrincipals@v1.0' = {
  appId: agentApp.appId
  accountEnabled: true
  tags: [
    'OwnerLensDemo'
    'WorkloadType:Agent'
    'TechnicalTeam:AIPlatform'
  ]
}

// Agent -> Billing application permission.
resource agentToBilling 'Microsoft.Graph/appRoleAssignedTo@v1.0' = {
  appRoleId: refundRequestRoleId
  principalId: agentSp.id
  resourceId: billingApiSp.id
  resourceDisplayName: billingApiDisplayName
}

resource agentToBillingCharge 'Microsoft.Graph/appRoleAssignedTo@v1.0' = {
  appRoleId: chargeRequestRoleId
  principalId: agentSp.id
  resourceId: billingApiSp.id
  resourceDisplayName: billingApiDisplayName
}

// -----------------------------------------------------------------------------
// Azure resources
// -----------------------------------------------------------------------------

resource storage 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: storageName
  location: location
  kind: 'StorageV2'
  sku: {
    name: 'Standard_LRS'
  }
  properties: {
    allowBlobPublicAccess: false
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
  }
  tags: {
    demo: 'OwnerLens'
    service: 'shared-runtime-storage'
  }
}

resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2023-05-01' = {
  parent: storage
  name: 'default'
}

resource billingDeployContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = {
  parent: blobService
  name: 'billing-deployments'
  properties: {
    publicAccess: 'None'
  }
}

resource paymentDeployContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = {
  parent: blobService
  name: 'payment-deployments'
  properties: {
    publicAccess: 'None'
  }
}

resource logs 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: logName
  location: location
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 30
  }
}

resource insights 'Microsoft.Insights/components@2020-02-02' = {
  name: insightsName
  location: location
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: logs.id
  }
}

resource billingPlan 'Microsoft.Web/serverfarms@2024-04-01' = {
  name: billingPlanName
  location: location
  kind: 'functionapp'
  sku: {
    name: 'FC1'
    tier: 'FlexConsumption'
  }
  properties: {
    reserved: true
  }
}

resource paymentPlan 'Microsoft.Web/serverfarms@2024-04-01' = {
  name: paymentPlanName
  location: location
  kind: 'functionapp'
  sku: {
    name: 'FC1'
    tier: 'FlexConsumption'
  }
  properties: {
    reserved: true
  }
}

resource billingCallerIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: billingCallerIdentityName
  location: location
  tags: {
    demo: 'OwnerLens'
    purpose: 'Billing-to-Payment OAuth client'
    ownership: 'technical-service-context-only'
  }
}

resource billingFunction 'Microsoft.Web/sites@2024-04-01' = {
  name: billingFunctionName
  location: location
  kind: 'functionapp,linux'
  identity: {
    type: 'SystemAssigned, UserAssigned'
    userAssignedIdentities: {
      '${billingCallerIdentity.id}': {}
    }
  }
  properties: {
    serverFarmId: billingPlan.id
    httpsOnly: true
    functionAppConfig: {
      deployment: {
        storage: {
          type: 'blobContainer'
          value: '${storage.properties.primaryEndpoints.blob}billing-deployments'
          authentication: {
            type: 'SystemAssignedIdentity'
          }
        }
      }
      scaleAndConcurrency: {
        maximumInstanceCount: 20
        instanceMemoryMB: 2048
      }
      runtime: {
        name: 'python'
        version: '3.12'
      }
    }
    siteConfig: {
      minTlsVersion: '1.2'
      appSettings: [
        {
          name: 'AzureWebJobsStorage__accountName'
          value: storage.name
        }
        {
          name: 'AzureWebJobsStorage__credential'
          value: 'managedidentity'
        }
        {
          name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
          value: insights.properties.ConnectionString
        }
        {
          name: 'AUTH_MODE'
          value: 'easyauth'
        }
        {
          name: 'ENTRA_TENANT_ID'
          value: tenant().tenantId
        }
        {
          name: 'API_SCOPE'
          value: '${billingApiIdentifierUri}/.default'
        }
        {
          name: 'PAYMENT_API_URL'
          value: 'https://${paymentFunctionName}.azurewebsites.net'
        }
        {
          name: 'PAYMENT_API_SCOPE'
          value: '${paymentApiIdentifierUri}/.default'
        }
        {
          name: 'BILLING_CALLER_CLIENT_ID'
          value: billingCallerIdentity.properties.clientId
        }
      ]
    }
  }
  tags: {
    demo: 'OwnerLens'
    service: 'Billing'
    technicalTeam: 'BillingPlatform'
    explicitHumanOwner: 'false'
  }
}

resource paymentFunction 'Microsoft.Web/sites@2024-04-01' = {
  name: paymentFunctionName
  location: location
  kind: 'functionapp,linux'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    serverFarmId: paymentPlan.id
    httpsOnly: true
    functionAppConfig: {
      deployment: {
        storage: {
          type: 'blobContainer'
          value: '${storage.properties.primaryEndpoints.blob}payment-deployments'
          authentication: {
            type: 'SystemAssignedIdentity'
          }
        }
      }
      scaleAndConcurrency: {
        maximumInstanceCount: 20
        instanceMemoryMB: 2048
      }
      runtime: {
        name: 'python'
        version: '3.12'
      }
    }
    siteConfig: {
      minTlsVersion: '1.2'
      appSettings: [
        {
          name: 'AzureWebJobsStorage__accountName'
          value: storage.name
        }
        {
          name: 'AzureWebJobsStorage__credential'
          value: 'managedidentity'
        }
        {
          name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
          value: insights.properties.ConnectionString
        }
        {
          name: 'AUTH_MODE'
          value: 'easyauth'
        }
        {
          name: 'ENTRA_TENANT_ID'
          value: tenant().tenantId
        }
        {
          name: 'API_SCOPE'
          value: '${paymentApiIdentifierUri}/.default'
        }
      ]
    }
  }
  tags: {
    demo: 'OwnerLens'
    service: 'Payment'
    criticality: 'Financial'
    explicitHumanOwner: 'true'
  }
}

// Easy Auth: API business routes require Entra; docs/health stay public for demo usability.
resource billingAuth 'Microsoft.Web/sites/config@2022-09-01' = {
  parent: billingFunction
  name: 'authsettingsV2'
  properties: {
    platform: {
      enabled: true
      runtimeVersion: '~1'
    }
    globalValidation: {
      requireAuthentication: true
      unauthenticatedClientAction: 'Return401'
      excludedPaths: [
        '/health'
        '/docs'
        '/openapi.json'
        '/redoc'
      ]
    }
    identityProviders: {
      azureActiveDirectory: {
        enabled: true
        registration: {
          clientId: billingApiApp.appId
          openIdIssuer: 'https://login.microsoftonline.com/${tenant().tenantId}/v2.0'
        }
        validation: {
          allowedAudiences: [
            billingApiApp.appId
            billingApiIdentifierUri
          ]
          defaultAuthorizationPolicy: {
            allowedApplications: [
              agentApp.appId
            ]
          }
        }
      }
    }
    httpSettings: {
      requireHttps: true
    }
  }
}

resource paymentAuth 'Microsoft.Web/sites/config@2022-09-01' = {
  parent: paymentFunction
  name: 'authsettingsV2'
  properties: {
    platform: {
      enabled: true
      runtimeVersion: '~1'
    }
    globalValidation: {
      requireAuthentication: true
      unauthenticatedClientAction: 'Return401'
      excludedPaths: [
        '/health'
        '/docs'
        '/openapi.json'
        '/redoc'
      ]
    }
    identityProviders: {
      azureActiveDirectory: {
        enabled: true
        registration: {
          clientId: paymentApiApp.appId
          openIdIssuer: 'https://login.microsoftonline.com/${tenant().tenantId}/v2.0'
        }
        validation: {
          allowedAudiences: [
            paymentApiApp.appId
            paymentApiIdentifierUri
          ]
          defaultAuthorizationPolicy: {
            allowedApplications: [
              billingCallerIdentity.properties.clientId
            ]
          }
        }
      }
    }
    httpSettings: {
      requireHttps: true
    }
  }
}

// Billing outbound UAMI -> Payment application permission.
resource billingToPayment 'Microsoft.Graph/appRoleAssignedTo@v1.0' = {
  appRoleId: refundExecuteRoleId
  principalId: billingCallerIdentity.properties.principalId
  resourceId: paymentApiSp.id
  resourceDisplayName: paymentApiDisplayName
  dependsOn: [
    billingFunction
  ]
}

resource billingToPaymentCharge 'Microsoft.Graph/appRoleAssignedTo@v1.0' = {
  appRoleId: chargeExecuteRoleId
  principalId: billingCallerIdentity.properties.principalId
  resourceId: paymentApiSp.id
  resourceDisplayName: paymentApiDisplayName
  dependsOn: [
    billingFunction
  ]
}

// Function runtime/deployment storage permissions.
resource billingBlobRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storage.id, billingFunction.id, 'blob-owner')
  scope: storage
  properties: {
    roleDefinitionId: storageBlobDataOwnerRoleId
    principalId: billingFunction.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

resource billingQueueRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storage.id, billingFunction.id, 'queue-contributor')
  scope: storage
  properties: {
    roleDefinitionId: storageQueueDataContributorRoleId
    principalId: billingFunction.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

resource billingTableRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storage.id, billingFunction.id, 'table-contributor')
  scope: storage
  properties: {
    roleDefinitionId: storageTableDataContributorRoleId
    principalId: billingFunction.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

resource paymentBlobRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storage.id, paymentFunction.id, 'blob-owner')
  scope: storage
  properties: {
    roleDefinitionId: storageBlobDataOwnerRoleId
    principalId: paymentFunction.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

resource paymentQueueRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storage.id, paymentFunction.id, 'queue-contributor')
  scope: storage
  properties: {
    roleDefinitionId: storageQueueDataContributorRoleId
    principalId: paymentFunction.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

resource paymentTableRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storage.id, paymentFunction.id, 'table-contributor')
  scope: storage
  properties: {
    roleDefinitionId: storageTableDataContributorRoleId
    principalId: paymentFunction.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

output billingFunctionName string = billingFunction.name
output paymentFunctionName string = paymentFunction.name
output billingUrl string = 'https://${billingFunction.properties.defaultHostName}'
output paymentUrl string = 'https://${paymentFunction.properties.defaultHostName}'
output billingDocsUrl string = 'https://${billingFunction.properties.defaultHostName}/docs'
output paymentDocsUrl string = 'https://${paymentFunction.properties.defaultHostName}/docs'
output billingApiScope string = '${billingApiIdentifierUri}/.default'
output paymentApiScope string = '${paymentApiIdentifierUri}/.default'
output billingApiClientId string = billingApiApp.appId
output paymentApiClientId string = paymentApiApp.appId
output agentClientId string = agentApp.appId
output agentServicePrincipalObjectId string = agentSp.id
output billingApiServicePrincipalObjectId string = billingApiSp.id
output paymentApiServicePrincipalObjectId string = paymentApiSp.id
output billingCallerManagedIdentityClientId string = billingCallerIdentity.properties.clientId
output billingCallerManagedIdentityPrincipalId string = billingCallerIdentity.properties.principalId
output tenantId string = tenant().tenantId
