@description('The name of the App Service plan.')
param appServicePlanName string

@description('The location where the App Service plan will be deployed.')
param location string

@description('The name of the Logic App.')
param logicAppName string

@description('The resource ID of the subnet to connect the App Service plan to.')
param subnetId string

@description('The connection string for the storage account used by the Logic App.')
param storageAccountConnectionString string

resource appServicePlan 'Microsoft.Web/serverfarms@2021-02-01' = {
  name: appServicePlanName
  location: location
  sku: {
    name: 'WS1'
    tier: 'WorkflowStandard'
  }
}

resource virtualNetworkConnection 'Microsoft.Web/sites/virtualNetworkConnections@2021-02-01' = {
  name: '${appServicePlan.name}/primary'
  location: location
  properties: {
    vnetResourceId: subnetId
  }
}

resource logicApp 'Microsoft.Web/sites@2021-02-01' = {
  name: logicAppName
  location: location
  kind: 'functionapp'
  properties: {
    serverFarmId: appServicePlan.id
    siteConfig: {
      appSettings: [
        {
          name: 'FUNCTIONS_EXTENSION_VERSION'
          value: '~3'
        }
        {
          name: 'FUNCTIONS_WORKER_RUNTIME'
          value: 'dotnet'
        }
        {
          name: 'AzureWebJobsStorage'
          value: storageAccountConnectionString
        }
      ]
    }
  }
}
