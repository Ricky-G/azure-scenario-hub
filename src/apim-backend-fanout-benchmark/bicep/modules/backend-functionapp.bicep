// ========================================
// Mock backend: .NET 8 isolated Function App on Flex Consumption (FC1)
// ========================================
// Uses identity-based storage (no shared keys) so this works in subscriptions
// where Azure Policy disables `allowSharedKeyAccess` on storage accounts.
// Flex Consumption gives us:
//   - alwaysReady instance (no cold start)
//   - identity-based blob deployment container (no file share / no key)

@description('Azure region')
param location string

@description('Name prefix used to derive resource names')
param namePrefix string

@description('Tags applied to all resources')
param tags object = {}

@description('Application Insights connection string')
param appInsightsConnectionString string

var unique = uniqueString(resourceGroup().id)
var storageAccountName = toLower('st${namePrefix}${take(unique, 8)}')
var planName = 'plan-${namePrefix}-${unique}'
var functionAppName = 'func-${namePrefix}-${unique}'
var deploymentContainerName = 'app-package'

resource storage 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: storageAccountName
  location: location
  tags: tags
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
    supportsHttpsTrafficOnly: true
    publicNetworkAccess: 'Enabled'
    // Flex Consumption uses identity-based storage; shared keys not required.
    allowSharedKeyAccess: false
    networkAcls: {
      bypass: 'AzureServices'
      defaultAction: 'Allow'
    }
  }
}

resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2023-01-01' = {
  parent: storage
  name: 'default'
  properties: {}
}

resource deploymentContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = {
  parent: blobService
  name: deploymentContainerName
  properties: {
    publicAccess: 'None'
  }
}

resource plan 'Microsoft.Web/serverfarms@2023-12-01' = {
  name: planName
  location: location
  tags: tags
  sku: {
    name: 'FC1'
    tier: 'FlexConsumption'
  }
  kind: 'functionapp'
  properties: {
    reserved: true
  }
}

resource functionApp 'Microsoft.Web/sites@2023-12-01' = {
  name: functionAppName
  location: location
  tags: tags
  kind: 'functionapp,linux'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    serverFarmId: plan.id
    httpsOnly: true
    clientAffinityEnabled: false
    functionAppConfig: {
      deployment: {
        storage: {
          type: 'blobContainer'
          value: '${storage.properties.primaryEndpoints.blob}${deploymentContainerName}'
          authentication: {
            type: 'SystemAssignedIdentity'
          }
        }
      }
      runtime: {
        name: 'dotnet-isolated'
        version: '10.0'
      }
      scaleAndConcurrency: {
        maximumInstanceCount: 40
        instanceMemoryMB: 2048
        alwaysReady: [
          {
            name: 'http'
            instanceCount: 1
          }
        ]
      }
    }
    siteConfig: {
      minTlsVersion: '1.2'
      http20Enabled: true
      ftpsState: 'Disabled'
      appSettings: [
        {
          // Identity-based AzureWebJobsStorage — no key needed.
          name: 'AzureWebJobsStorage__accountName'
          value: storage.name
        }
        {
          name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
          value: appInsightsConnectionString
        }
      ]
    }
  }
  dependsOn: [
    deploymentContainer
  ]
}

// Storage Blob Data Owner: required for both deployment-container access and
// AzureWebJobsStorage identity-based access. Role definition GUID is the
// built-in 'Storage Blob Data Owner' role.
resource roleBlobOwner 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: storage
  name: guid(storage.id, functionApp.id, 'b7e6dc6d-f1e8-4753-8033-0f276bb0955b')
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'b7e6dc6d-f1e8-4753-8033-0f276bb0955b')
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

output functionAppName string = functionApp.name
output functionAppDefaultHostname string = functionApp.properties.defaultHostName
output functionAppId string = functionApp.id
