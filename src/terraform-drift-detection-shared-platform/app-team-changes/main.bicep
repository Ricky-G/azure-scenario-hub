// =============================================================================
// APP TEAM - Out-of-band child resources (Bicep)
// =============================================================================
// This template simulates what the app team deploys from THEIR OWN pipeline
// (GitHub Actions + Bicep), completely separate from the platform team's
// Terraform Cloud workspace.
//
// It adds CHILD resources into the platform-owned parents:
//   * a blob container       -> into the platform storage account
//   * a SQL database + container -> into the platform Cosmos DB account
//   * a project              -> into the platform Azure AI Foundry account
//
// None of these change any property that the platform Terraform manages, which
// is exactly why they should NOT trigger drift. See README.md.
// =============================================================================

targetScope = 'resourceGroup'

@description('Name of the existing platform-owned storage account.')
param storageAccountName string

@description('Name of the existing platform-owned Cosmos DB account.')
param cosmosAccountName string

@description('Name of the existing platform-owned Azure AI Foundry (AIServices) account.')
param foundryAccountName string

@description('Azure region for the new Foundry project. Defaults to the resource group location.')
param location string = resourceGroup().location

@description('Name of the blob container the app team adds.')
param containerName string = 'appteam-data'

@description('Name of the Cosmos SQL database the app team adds.')
param cosmosDatabaseName string = 'appteam-db'

@description('Name of the Cosmos SQL container the app team adds.')
param cosmosContainerName string = 'orders'

@description('Name of the Foundry project the app team adds.')
param foundryProjectName string = 'appteam-project'

// ---------------------------------------------------------------------------
// Storage: add a blob container to the platform-owned account
// ---------------------------------------------------------------------------
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' existing = {
  name: storageAccountName
}

resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2023-05-01' existing = {
  parent: storageAccount
  name: 'default'
}

resource blobContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = {
  parent: blobService
  name: containerName
  properties: {
    publicAccess: 'None'
  }
}

// ---------------------------------------------------------------------------
// Cosmos DB: add a SQL database + container to the platform-owned account
// (No throughput options - the account is serverless.)
// ---------------------------------------------------------------------------
resource cosmosAccount 'Microsoft.DocumentDB/databaseAccounts@2024-11-15' existing = {
  name: cosmosAccountName
}

resource cosmosDatabase 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases@2024-11-15' = {
  parent: cosmosAccount
  name: cosmosDatabaseName
  properties: {
    resource: {
      id: cosmosDatabaseName
    }
  }
}

resource cosmosContainer 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers@2024-11-15' = {
  parent: cosmosDatabase
  name: cosmosContainerName
  properties: {
    resource: {
      id: cosmosContainerName
      partitionKey: {
        paths: [
          '/id'
        ]
        kind: 'Hash'
      }
    }
  }
}

// ---------------------------------------------------------------------------
// Foundry: add a project to the platform-owned account
// ---------------------------------------------------------------------------
resource foundryAccount 'Microsoft.CognitiveServices/accounts@2025-04-01-preview' existing = {
  name: foundryAccountName
}

resource foundryProject 'Microsoft.CognitiveServices/accounts/projects@2025-04-01-preview' = {
  parent: foundryAccount
  name: foundryProjectName
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    displayName: foundryProjectName
    description: 'Project added out-of-band by the app team to test Terraform drift detection.'
  }
}

output addedContainerName string = blobContainer.name
output addedCosmosDatabaseName string = cosmosDatabase.name
output addedFoundryProjectName string = foundryProject.name
